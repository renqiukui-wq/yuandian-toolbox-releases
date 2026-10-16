using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Text;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
static class UpdateInstaller {
    static readonly object Gate=new object();public static string State="idle",Message="";static string StatusPath;static Process Worker;
    public static void Reset(){lock(Gate){State="idle";Message="";StatusPath=null;}}
    static object Result(){return new{state=State,message=Message};}
    static string Hash(string path){using(var s=File.OpenRead(path))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","").ToLowerInvariant();}
    public static object Prepare(string source,string hash,long size){lock(Gate){if(StatusPath!=null&&File.Exists(StatusPath)){var previous=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,object>>(File.ReadAllText(StatusPath,Encoding.UTF8));State=Convert.ToString(previous["state"]);Message=Convert.ToString(previous["message"]);}
        if(Worker!=null&&!Worker.HasExited)return Result();State="preparing";Message="正在准备自动更新…";try{
        string target=Environment.GetEnvironmentVariable("YUANDIAN_APP_PATH"),pidText=Environment.GetEnvironmentVariable("YUANDIAN_BOOT_PID");int pid;
        if(String.IsNullOrEmpty(target)||!Int32.TryParse(pidText,out pid)||!File.Exists(target))throw new IOException("无法确认原程序位置，请从单文件程序启动后再试。");
        if(new FileInfo(source).Length!=size||Hash(source)!=hash)throw new IOException("下载文件已变化，请重新下载。");
        long bootTicks;using(var boot=Process.GetProcessById(pid)){if(!String.Equals(boot.MainModule.FileName,Path.GetFullPath(target),StringComparison.OrdinalIgnoreCase))throw new IOException("原程序进程不匹配。");bootTicks=boot.StartTime.ToUniversalTime().Ticks;}
        string planPath=Path.Combine(Path.GetDirectoryName(source),"install-plan.json");StatusPath=Path.Combine(Path.GetDirectoryName(source),"install-status.json");if(File.Exists(StatusPath))File.Delete(StatusPath);
        using(var helper=Process.GetCurrentProcess())File.WriteAllText(planPath,new JavaScriptSerializer().Serialize(new{Source=source,Target=target,NewHash=hash,OldHash=Hash(target),Size=size,BootPid=pid,BootTicks=bootTicks,HelperPid=helper.Id,HelperTicks=helper.StartTime.ToUniversalTime().Ticks,StatusPath=StatusPath}),new UTF8Encoding(false));
        Worker=Process.Start(new ProcessStartInfo(source,"--apply-update \""+planPath+"\""){UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(source)});
        for(int i=0;i<600;i++){if(File.Exists(StatusPath)){var s=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,object>>(File.ReadAllText(StatusPath,Encoding.UTF8));State=Convert.ToString(s["state"]);Message=Convert.ToString(s["message"]);return Result();}Thread.Sleep(100);}
        throw new IOException("更新准备超时，请稍后重试。");
    }catch(Exception e){State="failed";Message=e.Message;return Result();}}}
}
