using System;
using System.IO;
using System.Text;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;

static class MaterialCollector {
    static object Gate=new object();
    class TaskInfo {
        public string id=Guid.NewGuid().ToString("N"),state="processing",message="正在检查素材",error="";
        public int completed,total,files;
        public string[] drafts;
    }
    class Document { public string file,text,signature; public byte[] original; public object data; public bool encrypted; }
    class Asset { public string source,target,relative; public bool directory; }
    static Dictionary<string,TaskInfo> Tasks=new Dictionary<string,TaskInfo>();
    public static bool IsBusy{get{lock(Gate)return Tasks.Values.Any(t=>t.state=="processing");}}
    static JavaScriptSerializer Json(){return new JavaScriptSerializer{MaxJsonLength=64*1024*1024,RecursionLimit=512};}
    public static object Start(object values){
        var list=values as IEnumerable; if(list==null)throw new Exception("请先选择草稿。");
        var paths=new List<string>(); foreach(object x in list){string p=Path.GetFullPath(Convert.ToString(x));if(!paths.Contains(p,StringComparer.OrdinalIgnoreCase))paths.Add(p);}
        if(paths.Count==0)throw new Exception("请先选择草稿。");
        foreach(string p in paths)if(!Directory.Exists(p)||(!File.Exists(Path.Combine(p,"draft_content.json"))&&!File.Exists(Path.Combine(p,"draft_info.json"))))throw new Exception("不是有效的草稿目录："+p);
        lock(Gate){
            foreach(TaskInfo t in Tasks.Values)if(t.state=="processing")throw new Exception("已有素材复制任务正在执行。");
            var task=new TaskInfo{drafts=paths.ToArray(),total=paths.Count};Tasks[task.id]=task;
            ThreadPool.QueueUserWorkItem(delegate{Run(task);});return State(task);
        }
    }
    static object State(TaskInfo t){return new{id=t.id,state=t.state,message=t.message,error=t.error,completed=t.completed,total=t.total,files=t.files};}
    public static object Status(string id){lock(Gate){if(!Tasks.ContainsKey(id))throw new Exception("未找到素材复制任务。");return State(Tasks[id]);}}
    static void Run(TaskInfo t){
        try{
            foreach(string draft in t.drafts){lock(Gate)t.message="正在收集："+Path.GetFileName(draft);int count=Collect(draft,t.id);lock(Gate){t.files+=count;t.completed++;}}
            lock(Gate){t.state="completed";t.message="已完成 "+t.completed+" 个草稿，共复制 "+t.files+" 个外部素材文件。";}
        }catch(Exception e){lock(Gate){t.state="failed";t.error=e.Message;t.message=e.Message;}}
    }
    static string Hash(byte[] data){using(var s=SHA256.Create())return BitConverter.ToString(s.ComputeHash(data)).Replace("-","").ToLowerInvariant();}
    static string HashFile(string p){using(var s=SHA256.Create())using(var f=File.OpenRead(p))return BitConverter.ToString(s.ComputeHash(f)).Replace("-","").ToLowerInvariant();}
    static bool Inside(string child,string root){string c=Path.GetFullPath(child),r=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;return c.StartsWith(r,StringComparison.OrdinalIgnoreCase);}
    static bool Skip(string p){return p.Split(Path.DirectorySeparatorChar,Path.AltDirectorySeparatorChar).Any(x=>x==".backup"||x==".xy-material-backups"||x=="CollectedMaterials"||x==".recycle_bin");}
    static IEnumerable<string> SafeFiles(string root){
        if((File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0)throw new Exception("不支持链接目录："+root);
        foreach(string p in Directory.GetFiles(root))if((File.GetAttributes(p)&FileAttributes.ReparsePoint)==0)yield return p;else throw new Exception("不支持链接文件："+p);
        foreach(string dir in Directory.GetDirectories(root))if(!Skip(dir))foreach(string p in SafeFiles(dir))yield return p;
    }
    static IEnumerable<string> Documents(string root){
        foreach(string p in Directory.GetFiles(root,"*",SearchOption.TopDirectoryOnly))if(Path.GetExtension(p).Equals(".json",StringComparison.OrdinalIgnoreCase))yield return p;
        foreach(string dir in Directory.GetDirectories(root)){
            string name=Path.GetFileName(dir);
            if(name!="Timelines"&&name!="subdraft")continue;
            foreach(string p in SafeFiles(dir))if(Path.GetExtension(p).Equals(".json",StringComparison.OrdinalIgnoreCase))yield return p;
        }
    }
    static string FilePath(string s){
        if(String.IsNullOrWhiteSpace(s))return null;
        if(s.StartsWith("file:",StringComparison.OrdinalIgnoreCase)){Uri u;if(Uri.TryCreate(s,UriKind.Absolute,out u)&&u.IsFile)s=u.LocalPath;}
        if(s.Length>2&&Char.IsLetter(s[0])&&s[1]==':'&&(s[2]=='/'||s[2]=='\\'))return Path.GetFullPath(s);
        if(s.StartsWith("\\\\"))return Path.GetFullPath(s);
        return null;
    }
    static object Transform(object value,string key,bool inMaterials,string draft,Dictionary<string,Asset> assets,bool discover){
        var dict=value as Dictionary<string,object>;
        if(dict!=null){foreach(string k in dict.Keys.ToArray())dict[k]=Transform(dict[k],k,inMaterials||k.IndexOf("material",StringComparison.OrdinalIgnoreCase)>=0,draft,assets,discover);return value;}
        var list=value as IList;if(list!=null){for(int i=0;i<list.Count;i++)list[i]=Transform(list[i],key,inMaterials,draft,assets,discover);return value;}
        string text=value as string;if(text==null)return value;
        string path=FilePath(text);if(path==null||Inside(path,draft))return value;
        // Paths that identify the project location are not material references.
        string lower=key.ToLowerInvariant();if(lower=="draft_fold_path"||lower=="draft_root_path"||lower=="draft_path")return value;
        bool file=File.Exists(path),directory=Directory.Exists(path);
        bool materialKey=lower.Contains("path")||lower.Contains("file")||lower=="url";
        if(!materialKey)return value;
        if(directory&&!inMaterials)return value;
        if(!file&&!directory){
            // Empty/deleted editor cache entries must not be guessed or rewritten.
            if(inMaterials&&(!String.IsNullOrEmpty(Path.GetExtension(path))))throw new FileNotFoundException("素材不存在，未更改草稿引用："+path);
            return value;
        }
        Asset a;
        if(!assets.TryGetValue(path,out a)){
            if(!discover)return value;
            string relative="Resources/CollectedMaterials/"+Hash(Encoding.UTF8.GetBytes(path.ToLowerInvariant())).Substring(0,16)+"/"+Path.GetFileName(path.TrimEnd('\\','/'));
            a=new Asset{source=path,relative=relative,target=Path.Combine(draft,relative.Replace('/',Path.DirectorySeparatorChar)),directory=directory};assets[path]=a;
        }
        return discover?value:a.target.Replace('\\','/');
    }
    static int Collect(string draft,string id){
        // Refuse an editor-held lock; a stale unlocked .locked file is harmless.
        string lockFile=Path.Combine(draft,".locked");FileStream editorLock=null;
        try{
            if(File.Exists(lockFile))try{editorLock=new FileStream(lockFile,FileMode.Open,FileAccess.ReadWrite,FileShare.None);}catch(IOException){throw new Exception("草稿正在被剪映使用，请先保存并关闭草稿："+draft);}
            var docs=new List<Document>();var assets=new Dictionary<string,Asset>(StringComparer.OrdinalIgnoreCase);
            foreach(string file in Documents(draft)){
                byte[] raw=File.ReadAllBytes(file);string text=Encoding.UTF8.GetString(raw).TrimStart('\uFEFF');object data;bool encrypted=false;
                try{data=Json().DeserializeObject(text);}catch{
                    if(Path.GetFileName(file)!="draft_content.json"&&Path.GetFileName(file)!="draft_meta_info.json")continue;
                    text=DraftCrypto.Convert(text,false);data=Json().DeserializeObject(text);encrypted=true;
                }
                Transform(data,"",false,draft,assets,true);
                docs.Add(new Document{file=file,text=text,original=raw,signature=Hash(raw),data=data,encrypted=encrypted});
            }
            // Discover and validate the entire reference graph before copying or rewriting anything.
            int copied=0;foreach(Asset a in assets.Values){
                if(a.directory){
                    if((File.GetAttributes(a.source)&FileAttributes.ReparsePoint)!=0)throw new Exception("不支持将链接目录作为素材："+a.source);
                    foreach(string file in SafeFiles(a.source)){
                        if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)throw new Exception("素材中包含链接文件："+file);
                        string target=Path.Combine(a.target,file.Substring(a.source.TrimEnd('\\','/').Length+1));CopyVerified(file,target);copied++;
                    }
                }else{CopyVerified(a.source,a.target);copied++;}
            }
            var updates=new Dictionary<string,byte[]>();
            foreach(Document doc in docs){
                Transform(doc.data,"",false,draft,assets,false);string changed=Json().Serialize(doc.data);
                // Only rewrite documents that actually contain a replaced external material path.
                bool touches=assets.Keys.Any(p=>doc.text.IndexOf(p,StringComparison.OrdinalIgnoreCase)>=0||doc.text.IndexOf(p.Replace('\\','/'),StringComparison.OrdinalIgnoreCase)>=0||doc.text.IndexOf(p.Replace("\\","\\\\"),StringComparison.OrdinalIgnoreCase)>=0);
                if(!touches)continue;
                if(doc.encrypted){string encoded=DraftCrypto.Convert(changed,true);if(DraftCrypto.Convert(encoded,false)!=changed)throw new Exception("草稿重新编码校验失败："+doc.file);changed=encoded;}
                updates[doc.file]=new UTF8Encoding(false).GetBytes(changed);
            }
            foreach(Document doc in docs)if(HashFile(doc.file)!=doc.signature)throw new Exception("检查期间草稿发生变化，请保存关闭后重试："+doc.file);
            string backupRoot=Path.Combine(draft,".xy-material-backups",id);var committed=new List<string>();
            try{
                foreach(var update in updates){
                    string backup=Path.Combine(backupRoot,update.Key.Substring(draft.TrimEnd('\\','/').Length+1));Directory.CreateDirectory(Path.GetDirectoryName(backup));
                    string temporary=update.Key+".xy-material-"+id+".tmp";File.WriteAllBytes(temporary,update.Value);
                    try{File.Replace(temporary,update.Key,backup);committed.Add(update.Key);}finally{if(File.Exists(temporary))File.Delete(temporary);}
                }
            }catch{foreach(string file in committed){string backup=Path.Combine(backupRoot,file.Substring(draft.TrimEnd('\\','/').Length+1));File.Copy(backup,file,true);}throw;}
            var manifest=new{id=id,draft=draft,copied_files=copied,rewritten_documents=updates.Count,backup=backupRoot,assets=assets.Values.Select(a=>new{source=a.source,target=a.target}).ToArray()};
            Directory.CreateDirectory(Path.Combine(draft,"Resources"));
            File.WriteAllText(Path.Combine(draft,"Resources","material-copy-manifest.json"),Json().Serialize(manifest),new UTF8Encoding(false));
            return copied;
        }finally{if(editorLock!=null)editorLock.Dispose();}
    }
    static void CopyVerified(string source,string target){
        Directory.CreateDirectory(Path.GetDirectoryName(target));string before=HashFile(source);
        if(File.Exists(target)&&HashFile(target)==before)return;
        string temporary=target+".xy-copy-"+Guid.NewGuid().ToString("N");
        try{File.Copy(source,temporary);if(HashFile(source)!=before||HashFile(temporary)!=before)throw new Exception("素材复制校验失败："+source);
            if(File.Exists(target))File.Replace(temporary,target,null);else File.Move(temporary,target);
        }finally{if(File.Exists(temporary))File.Delete(temporary);}
    }
}

static class DraftCrypto {
    [DllImport("kernel32",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr LoadLibrary(string path);
    [DllImport("kernel32",CharSet=CharSet.Ansi,ExactSpelling=true)]static extern IntPtr GetProcAddress(IntPtr module,string name);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate int Init(byte[] path);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate IntPtr Codec(byte[] text,out int error);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]delegate void Free(IntPtr value);
    static object Gate=new object();static bool Ready=false;static Codec Decode,Encode;static Free Release;
    static T Proc<T>(IntPtr lib,string name){IntPtr address=GetProcAddress(lib,name);if(address==IntPtr.Zero)throw new Exception("草稿组件缺少接口："+name);return (T)(object)Marshal.GetDelegateForFunctionPointer(address,typeof(T));}
    static byte[] Utf8(string s){return Encoding.UTF8.GetBytes(s+"\0");}
    static void Ensure(){
        if(Ready)return;
        string bridge=Path.Combine(LocalLauncher.RuntimeResources,"jydraft_bridge.dll");
        IntPtr lib=LoadLibrary(bridge);if(lib==IntPtr.Zero)throw new Exception("无法加载草稿读写组件，错误 "+Marshal.GetLastWin32Error());
        string apps=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"JianyingPro","Apps");
        string install=Directory.Exists(apps)?Directory.GetDirectories(apps).Where(p=>File.Exists(Path.Combine(p,"videoeditor.dll"))).OrderByDescending(p=>p,StringComparer.OrdinalIgnoreCase).FirstOrDefault():null;
        if(install==null)throw new Exception("未找到本机剪映的 videoeditor.dll，无法完整处理加密草稿。");
        int result;string previousDirectory=Environment.CurrentDirectory;
        try{result=Proc<Init>(lib,"jydraft_init")(Utf8(install));}finally{Environment.CurrentDirectory=previousDirectory;}
        if(result!=0)throw new Exception("草稿读写组件初始化失败，错误 "+result);
        Decode=Proc<Codec>(lib,"jydraft_decrypt");Encode=Proc<Codec>(lib,"jydraft_encrypt");Release=Proc<Free>(lib,"jydraft_free_string");Ready=true;
    }
    public static string Convert(string text,bool encrypt){lock(Gate){Ensure();int error;IntPtr value=(encrypt?Encode:Decode)(Utf8(text),out error);if(value==IntPtr.Zero)throw new Exception("草稿读写失败，错误 "+error);
        try{int length=0;while(length<64*1024*1024&&Marshal.ReadByte(value,length)!=0)length++;if(length==64*1024*1024)throw new Exception("草稿内容过大");byte[] raw=new byte[length];Marshal.Copy(value,raw,0,length);return Encoding.UTF8.GetString(raw);}finally{Release(value);}
    }}
}
