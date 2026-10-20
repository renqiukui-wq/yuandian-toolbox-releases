/* SPDX-License-Identifier: MIT
 * Local draft file codec. Compatible with the five existing jydraft C exports.
 * Uses Windows CNG AES-256-GCM with authentication; no editor DLL, process
 * injection, network access, or application-global state is required.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <bcrypt.h>
#include <wincrypt.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define API __declspec(dllexport)
#define LIMIT (64u * 1024u * 1024u)
static const unsigned offsets[12]={0,7,20,33,40,47,59,66,76,89,99,127};
static const char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static char *fail(int *error,int code) { if(error)*error=code;return NULL; }
static char *duplicate(const char *s,size_t n) {
    char *p=(char*)malloc(n+1);if(p){memcpy(p,s,n);p[n]=0;}return p;
}
static int transform(int encrypt,const unsigned char *input,ULONG length,
                     unsigned char *output,unsigned char keyiv[48],unsigned char tag[16]) {
    BCRYPT_ALG_HANDLE alg=NULL;BCRYPT_KEY_HANDLE key=NULL;
    BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO auth;ULONG written=0;
    NTSTATUS status=BCryptOpenAlgorithmProvider(&alg,BCRYPT_AES_ALGORITHM,NULL,0);
    if(status<0)return -13;
    status=BCryptSetProperty(alg,BCRYPT_CHAINING_MODE,(PUCHAR)BCRYPT_CHAIN_MODE_GCM,sizeof(BCRYPT_CHAIN_MODE_GCM),0);
    if(status>=0)status=BCryptGenerateSymmetricKey(alg,&key,NULL,0,keyiv,32,0);
    if(status>=0) {
        BCRYPT_INIT_AUTH_MODE_INFO(auth);
        auth.pbNonce=keyiv+32;auth.cbNonce=16;
        auth.pbTag=tag;auth.cbTag=16;
        status=encrypt ? BCryptEncrypt(key,(PUCHAR)input,length,&auth,NULL,0,output,length,&written,0)
                       : BCryptDecrypt(key,(PUCHAR)input,length,&auth,NULL,0,output,length,&written,0);
    }
    if(key)BCryptDestroyKey(key);
    BCryptCloseAlgorithmProvider(alg,0);
    return status<0 ? (status==(NTSTATUS)0xC000A002L ? -12 : -13) : (written==length ? 0 : -13);
}
API int jydraft_init(const char *editor_path) { (void)editor_path;return 0; }
API void jydraft_close(void) {}
API void jydraft_free_string(char *text) { free(text); }

API char *jydraft_decrypt(const char *text,int *error) {
    if(error)*error=0;
    if(!text)return fail(error,-10);
    size_t length=strnlen(text,LIMIT+1);
    if(length>LIMIT)return fail(error,-10);
    const char *start=text;
    if(length>=3 && (unsigned char)start[0]==0xef && (unsigned char)start[1]==0xbb && (unsigned char)start[2]==0xbf)start+=3;
    while(*start && isspace((unsigned char)*start))start++;
    if(*start=='{' || *start=='[') {
        char *plain=duplicate(start,strlen(start));return plain?plain:fail(error,-14);
    }
    length=strlen(start);
    while(length && isspace((unsigned char)start[length-1]))length--;
    if(length<132)return fail(error,-11);
    unsigned char keyiv[48];char *base64=(char*)malloc(length+1);
    if(!base64)return fail(error,-14);
    size_t written=0;unsigned group=0;
    for(size_t i=0;i<length;) {
        if(group<12 && i==offsets[group]) {
            memcpy(keyiv+group*4,start+i,4);group++;i+=4;
        } else base64[written++]=start[i++];
    }
    base64[written]=0;
    DWORD bytes=0;
    int valid=group==12 && written%4==0;
    for(size_t i=0;valid && i<written;i++)
        if(!strchr(alphabet,base64[i]) && base64[i]!='=')valid=0;
    if(!valid || !CryptStringToBinaryA(base64,(DWORD)written,CRYPT_STRING_BASE64,NULL,&bytes,NULL,NULL) || bytes<16) {
        free(base64);SecureZeroMemory(keyiv,sizeof(keyiv));return fail(error,-11);
    }
    unsigned char *binary=(unsigned char*)malloc(bytes);
    char *plain=(char*)malloc(bytes+1);
    if(!binary || !plain){free(binary);free(plain);free(base64);return fail(error,-14);}
    if(!CryptStringToBinaryA(base64,(DWORD)written,CRYPT_STRING_BASE64,binary,&bytes,NULL,NULL)){
        free(binary);free(plain);free(base64);return fail(error,-11);
    }
    free(base64);
    int code=transform(0,binary,bytes-16,(unsigned char*)plain,keyiv,binary+bytes-16);
    SecureZeroMemory(keyiv,sizeof(keyiv));free(binary);
    if(code){SecureZeroMemory(plain,bytes);free(plain);return fail(error,code);}
    size_t n=bytes-16;
    /* Short JSON documents are whitespace-padded before encryption. */
    while(n && isspace((unsigned char)plain[n-1]))n--;
    plain[n]=0;
    if(memchr(plain,0,n)){SecureZeroMemory(plain,bytes);free(plain);return fail(error,-11);}
    return plain;
}
API char *jydraft_encrypt(const char *text,int *error) {
    if(error)*error=0;
    if(!text)return fail(error,-10);
    size_t size=strnlen(text,LIMIT+1);
    if(size>LIMIT || size==0)return fail(error,-10);
    size_t n=size<64?64:size;
    unsigned char *input=(unsigned char*)malloc(n);
    unsigned char *binary=(unsigned char*)malloc(n+16);
    if(!input || !binary){free(input);free(binary);return fail(error,-14);}
    memcpy(input,text,size);memset(input+size,' ',n-size);
    unsigned char keyiv[48],random[48];
    if(BCryptGenRandom(NULL,random,sizeof(random),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0){
        free(input);free(binary);return fail(error,-13);
    }
    for(unsigned i=0;i<48;i++)keyiv[i]=(unsigned char)alphabet[random[i]&63];
    SecureZeroMemory(random,sizeof(random));
    int code=transform(1,input,(ULONG)n,binary,keyiv,binary+n);
    SecureZeroMemory(input,n);free(input);
    if(code){free(binary);SecureZeroMemory(keyiv,sizeof(keyiv));return fail(error,code);}
    DWORD chars=0;
    if(!CryptBinaryToStringA(binary,(DWORD)n+16,CRYPT_STRING_BASE64|CRYPT_STRING_NOCRLF,NULL,&chars)){
        free(binary);return fail(error,-13);
    }
    char *base64=(char*)malloc(chars),*result=(char*)malloc((size_t)chars+48);
    if(!base64 || !result){free(base64);free(result);free(binary);return fail(error,-14);}
    if(!CryptBinaryToStringA(binary,(DWORD)n+16,CRYPT_STRING_BASE64|CRYPT_STRING_NOCRLF,base64,&chars)){
        free(base64);free(result);free(binary);return fail(error,-13);
    }
    free(binary);
    size_t len=strlen(base64),source=0,dest=0;unsigned group=0;
    while(source<len) {
        if(group<12 && dest==offsets[group]){
            memcpy(result+dest,keyiv+group*4,4);dest+=4;group++;
        } else result[dest++]=base64[source++];
    }
    result[dest]=0;
    SecureZeroMemory(keyiv,sizeof(keyiv));free(base64);
    if(group!=12){free(result);return fail(error,-11);}
    return result;
}
