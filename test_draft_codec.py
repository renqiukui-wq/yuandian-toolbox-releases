"""Regression tests for the DLL C ABI; uses synthetic documents only."""
import ctypes, json, sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
d=ctypes.CDLL(str(Path(sys.argv[1]).resolve()))
d.jydraft_init.argtypes=[ctypes.c_char_p];d.jydraft_init.restype=ctypes.c_int
for name in ["jydraft_encrypt","jydraft_decrypt"]:
    f=getattr(d,name);f.argtypes=[ctypes.c_char_p,ctypes.POINTER(ctypes.c_int)];f.restype=ctypes.c_void_p
d.jydraft_free_string.argtypes=[ctypes.c_void_p]
def call(name,text,fail=False):
    err=ctypes.c_int()
    ptr=getattr(d,name)(text,ctypes.byref(err))
    if fail:
        assert not ptr and err.value<0,(ptr,err.value)
        return err.value
    assert ptr and err.value==0,err.value
    try:return ctypes.string_at(ptr)
    finally:d.jydraft_free_string(ptr)
assert d.jydraft_init(b"nonexistent-editor-no-longer-required")==0
def roundtrip(n):
    document={"id":str(n),"materials":{"videos":[{"path":"D:/fixture/\u4e2d\u6587.mp4"}]},"text":"x"*n}
    raw=json.dumps(document,ensure_ascii=False).encode()
    a=call("jydraft_encrypt",raw);b=call("jydraft_encrypt",raw)
    assert a!=b,"random IV/key required"
    assert json.loads(call("jydraft_decrypt",a))==document
    damaged=bytearray(a);damaged[-8]=ord("A") if damaged[-8]!=ord("A") else ord("B")
    assert call("jydraft_decrypt",bytes(damaged),True)==-12,"authentication must reject changed data"
    assert json.loads(call("jydraft_decrypt",raw))==document
with ThreadPoolExecutor(max_workers=8) as pool:list(pool.map(roundtrip,[0,10,100,4096,8192,50000,100000,1000000]*2))
for bad in [b"",b"not-a-draft",b"A"*131,b"!"*200]:
    call("jydraft_decrypt",bad,True)
assert call("jydraft_decrypt",call("jydraft_encrypt",b"{}"))==b"{}"
d.jydraft_close()
print("PASS native codec: no editor dependency, UTF-8, short/large JSON, randomized encoding, authentication, malformed input and concurrent calls")
