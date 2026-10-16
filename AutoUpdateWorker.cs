using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Text;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
class AutoUpdatePlan {public string Source,Target,NewHash,OldHash,StatusPath;public long Size,BootTicks,HelperTicks;public int BootPid,HelperPid;}
static class AutoUpdateWorker {
    static string Digest(string path){using(var s=File.OpenRead(path))using(var h=SHA256.Create())return BitConverter.ToString(h.ComputeHash(s)).Replace("-","").ToLowerInvariant();}
    static string Full(string path){return Path.GetFullPath(path);}
    static void PlainPath(string path){for(var p=new DirectoryInfo(Path.GetDirectoryName(path));p!=null;p=p.Parent)if((p.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("更新目录不能是链接。");if(File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0)throw new IOException("更新目标不能是链接。");}
    static void Status(AutoUpdatePlan plan,string state,string message){string temporary=plan.StatusPath+".tmp";File.WriteAllText(temporary,new JavaScriptSerializer().Serialize(new{state=state,message=message}),new UTF8Encoding(false));if(File.Exists(plan.StatusPath))File.Replace(temporary,plan.StatusPath,null);else File.Move(temporary,plan.StatusPath);}
    static void WaitForOld(int pid,long ticks){if(pid<=0)return;try{using(var p=Process.GetProcessById(pid)){if(p.StartTime.ToUniversalTime().Ticks!=ticks)return;if(!p.WaitForExit(180000))throw new IOException("旧版尚未退出，更新已暂停。请关闭旧版后重试。");}}catch(ArgumentException){}}
    public static int Apply(string planPath,string self){AutoUpdatePlan p=null;string stage=null,backup=null;bool replaced=false,statusAllowed=false;try{
        p=new JavaScriptSerializer().Deserialize<AutoUpdatePlan>(File.ReadAllText(planPath,Encoding.UTF8));
        if(p==null||!String.Equals(Full(p.Source),Full(self),StringComparison.OrdinalIgnoreCase)||!String.Equals(Full(Path.GetDirectoryName(p.StatusPath)),Full(Path.GetDirectoryName(self)),StringComparison.OrdinalIgnoreCase))throw new IOException("更新计划无效。");
        statusAllowed=true;p.Target=Full(p.Target);if(String.Equals(p.Target,Full(self),StringComparison.OrdinalIgnoreCase)||!p.Target.EndsWith(".exe",StringComparison.OrdinalIgnoreCase)||!File.Exists(p.Target))throw new IOException("未找到原程序位置。");
        PlainPath(p.Target);PlainPath(self);if(new FileInfo(self).Length!=p.Size||Digest(self)!=p.NewHash||Digest(p.Target)!=p.OldHash)throw new IOException("更新文件校验失败，原程序未修改。");
        stage=Path.Combine(Path.GetDirectoryName(p.Target),".元点更新_"+Guid.NewGuid().ToString("N")+".tmp");File.Copy(self,stage,false);if(Digest(stage)!=p.NewHash)throw new IOException("更新暂存文件校验失败。");
        Status(p,"ready","更新已就绪，正在等待旧版退出…");WaitForOld(p.HelperPid,p.HelperTicks);WaitForOld(p.BootPid,p.BootTicks);
        if(Digest(p.Target)!=p.OldHash)throw new IOException("原程序在更新期间发生变化，已停止替换。");
        backup=Path.Combine(Path.GetDirectoryName(self),"previous-version-"+Guid.NewGuid().ToString("N")+".exe");File.Copy(p.Target,backup,false);
        File.Replace(stage,p.Target,null);replaced=true;if(Digest(p.Target)!=p.NewHash)throw new IOException("替换后的程序校验失败。");
        StartUpdated(p.Target);Status(p,"completed","已自动替换并启动新版。");return 0;
    }catch(Exception e){if(replaced&&p!=null&&backup!=null&&File.Exists(backup)){try{string restore=p.Target+".restore-"+Guid.NewGuid().ToString("N");File.Copy(backup,restore);File.Replace(restore,p.Target,null);StartUpdated(p.Target);}catch{}}
        if(statusAllowed&&p!=null&&!String.IsNullOrEmpty(p.StatusPath)){try{Status(p,"failed","自动更新未完成："+e.Message);}catch{}}return 1;
    }finally{if(stage!=null&&File.Exists(stage)){try{File.Delete(stage);}catch{}}}}
    static void StartUpdated(string target){Process.Start(new ProcessStartInfo(target){WorkingDirectory=Path.GetDirectoryName(target),UseShellExecute=true});}
}
