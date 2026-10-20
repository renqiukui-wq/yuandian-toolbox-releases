using System;
using System.IO;
using System.Text;
class ExportEnvironmentSmoke {
    static void Check(bool ok,string label){if(!ok)throw new Exception(label);}
    static void Reject(Action action,string expected){
        try {action();} catch(Exception e) {Check(e.Message.Contains(expected),e.Message);return;}
        throw new Exception("Expected rejection: "+expected);
    }
    static void Main(string[] args){
        Console.OutputEncoding=new UTF8Encoding(false);
        if(args.Length>0&&args[0]=="--local-observe"){
            var actual=ExportEnvironment.Resolve("JianyingPro");
            Console.WriteLine("Resolved existing editor default: "+actual.folder);
            return;
        }
        string current=Directory.GetCurrentDirectory();
        foreach(string source in new[]{"JianyingPro","CapCut"}){
            string key=null;
            var location=ExportEnvironment.Resolve(source,k=>{key=k;return current.Replace('\\','/')+"  ";});
            Check(key==@"Software\Bytedance\"+source+@"\Modules\Export","registry branch");
            Check(location.folder==Path.GetFullPath(current)&&location.source==source,"resolved folder");
        }
        Reject(()=>ExportEnvironment.Resolve("unknown",k=>current),"来源设置无效");
        Reject(()=>ExportEnvironment.Resolve("JianyingPro",k=>null),"尚未找到");
        Reject(()=>ExportEnvironment.Resolve("CapCut",k=>"relative/folder"),"绝对路径");
        Reject(()=>ExportEnvironment.Resolve("JianyingPro",k=>"C:relative"),"绝对路径");
        Reject(()=>ExportEnvironment.Resolve("JianyingPro",k=>Path.Combine(current,Guid.NewGuid().ToString("N"))),"不存在");
        Reject(()=>ExportEnvironment.Resolve("JianyingPro",k=>{throw new UnauthorizedAccessException("test");}),"无法读取");
        Console.WriteLine("PASS default export registry branches, normalization, absent/invalid/unavailable folder and read errors; no registry mutation");
    }
}
