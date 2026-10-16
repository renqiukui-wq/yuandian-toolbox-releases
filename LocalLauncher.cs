using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Collections.Generic;
using System.Diagnostics;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using System.Globalization;

[assembly: System.Reflection.AssemblyTitle("元点剪辑批量工具箱")]
[assembly: System.Reflection.AssemblyProduct("元点剪辑批量工具箱")]

class LocalLauncher {
    const int Port = 48740;
    const string Token = "xy-local-20261015-fd32b7ca938c4e0ea704";
    static string Root = AppDomain.CurrentDomain.BaseDirectory;
    static string RuntimeDirectory = Path.Combine(Root, "Resources", "Core");
    public static string RuntimeResources = Path.Combine(RuntimeDirectory, "Resources");
    static TcpListener Listener;
    static object Gate = new object();
    static Dictionary<string, Job> Jobs = new Dictionary<string, Job>();
    static JavaScriptSerializer Json() { return new JavaScriptSerializer { MaxJsonLength = 4*1024*1024 }; }
    class Job {
        public string id, folder, outputFolder, mode, coverMode, state = "waiting", error = "";
        public int total, completed;
        public Dictionary<string,string> before;
        public HashSet<string> expected;
    }
    [STAThread] static void Main(string[] args) {
        try {
            Listener = new TcpListener(IPAddress.Loopback, Port);
            Listener.Start();
            new Thread(Accept) { IsBackground = true }.Start();
            if (args.Length > 0 && args[0] == "--test-server") { Thread.Sleep(Timeout.Infinite); return; }
            string app = Path.Combine(RuntimeDirectory, "元点剪辑批量工具箱_界面.exe");
            if (!File.Exists(app)) throw new FileNotFoundException("缺少配套界面程序", app);
            // The supplied Wails executable requests administrator privileges in its existing manifest.
            // Shell execution preserves its normal Windows launch/elevation behavior.
            using (Process p = Process.Start(new ProcessStartInfo(app) { WorkingDirectory = RuntimeDirectory, UseShellExecute = true })) { p.WaitForExit(); }
            while (true) { bool busy = MaterialCollector.IsBusy || UpdateService.IsBusy; lock (Gate) foreach (Job j in Jobs.Values) if (j.state == "processing") busy = true; if (!busy) break; Thread.Sleep(500); }
        } catch (Exception e) { MessageBox.Show(e.Message, "元点剪辑批量工具箱启动失败"); }
        finally { if (Listener != null) Listener.Stop(); }
    }
    public static bool UpdateBusy {get{if(MaterialCollector.IsBusy)return true;lock(Gate){foreach(Job job in Jobs.Values)if(job.state=="waiting"||job.state=="processing")return true;}return false;}}
    static void Accept() {
        try { while (true) { TcpClient c = Listener.AcceptTcpClient(); ThreadPool.QueueUserWorkItem(delegate { Handle(c); }); } }
        catch (SocketException) { }
        catch (ObjectDisposedException) { }
    }
    static string Signature(string path) { FileInfo i = new FileInfo(path); return i.Length + ":" + i.LastWriteTimeUtc.Ticks; }
    static bool IsVideo(string path) {
        string ext = Path.GetExtension(path).ToLowerInvariant();
        return ext == ".mp4" || ext == ".mov" || ext == ".mkv" || ext == ".m4v" || ext == ".avi";
    }
    static Dictionary<string,string> Scan(string folder) {
        var files = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
        // Export targets are direct children of the selected folder; never scan unrelated trees.
        foreach (string p in Directory.GetFiles(folder)) if (IsVideo(p) && !Path.GetFileName(p).StartsWith(".xy-size-")) files[p] = Signature(p);
        return files;
    }
    static object State(Job j) { return new { id=j.id, folder=j.folder, outputFolder=j.outputFolder, state=j.state, error=j.error, total=j.total, completed=j.completed }; }
    static string Arg(string s) { return "\"" + s.Replace("\"", "\\\"") + "\""; }
    static string RunTool(string executable,string arguments) {
        var start=new ProcessStartInfo(Path.Combine(RuntimeResources,executable)){Arguments=arguments,WorkingDirectory=Root,UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
        using(var p=Process.Start(start)) {var errors=new StringBuilder();p.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)lock(errors)errors.AppendLine(e.Data);};p.BeginErrorReadLine();try{p.PriorityClass=ProcessPriorityClass.BelowNormal;}catch{}string output=p.StandardOutput.ReadToEnd();p.WaitForExit();if(p.ExitCode!=0)throw new Exception(executable+"："+errors.ToString());return output;}
    }
    static double VideoDuration(string input) {
        var data=Json().Deserialize<Dictionary<string,object>>(RunTool("MediaInfo.exe","--Output=JSON "+Arg(input)));
        var media=(Dictionary<string,object>)data["media"];var tracks=(System.Collections.IEnumerable)media["track"];
        foreach(Dictionary<string,object> track in tracks)if(Convert.ToString(track["@type"])=="Video"&&track.ContainsKey("Duration")){double duration;if(Double.TryParse(Convert.ToString(track["Duration"]),NumberStyles.Float,CultureInfo.InvariantCulture,out duration)&&duration>0)return duration;}
        throw new Exception("无法读取视频时长："+Path.GetFileName(input));
    }
    static double RandomCoverTime(double duration) {
        byte[] bytes=new byte[4];using(var rng=System.Security.Cryptography.RandomNumberGenerator.Create())rng.GetBytes(bytes);
        double fraction=BitConverter.ToUInt32(bytes,0)/(double)UInt32.MaxValue;
        return duration<0.2?0:duration*(0.1+fraction*0.8);
    }
    static void ConvertJob(Job j) {
        try {
            var after=Scan(j.folder);var targets=new List<string>();
            foreach(var f in after)if((j.expected.Count==0||j.expected.Contains(Path.GetFileNameWithoutExtension(f.Key)))&&(!j.before.ContainsKey(f.Key)||j.before[f.Key]!=f.Value))targets.Add(f.Key);
            if(targets.Count==0)throw new Exception("没有找到本次导出的视频。");
            lock(Gate)j.total=targets.Count;
            string size=j.mode=="landscape"?"1280:720":"720:1280";
            string filter="scale="+size+":force_original_aspect_ratio=decrease:force_divisible_by=2,pad="+size+":(ow-iw)/2:(oh-ih)/2:color=black,setsar=1";
            if(j.mode=="auto720")filter="scale=w='if(gte(dar,1),max(2,round(720*dar/2)*2),720)':h='if(gte(dar,1),720,max(2,round(720/dar/2)*2))',setsar=1";
            if(j.mode=="original")filter="null";
            foreach(string input in targets) {
                string extension=Path.GetExtension(input).ToLowerInvariant();string temporary=Path.Combine(j.folder,".xy-size-"+Guid.NewGuid().ToString("N")+extension);string cover=Path.Combine(j.folder,".xy-cover-"+Guid.NewGuid().ToString("N")+".jpg");
                try {
                    string output=Path.Combine(j.outputFolder,Path.GetFileName(input));if(File.Exists(output))throw new Exception("保存位置已有同名视频，请重命名或更换文件夹："+Path.GetFileName(input));
                    string arguments="-hide_banner -loglevel error -nostdin -y -i "+Arg(input);
                    if(j.coverMode=="random") {
                        if(extension!=".mp4"&&extension!=".mov"&&extension!=".m4v")throw new Exception("随机封面需要 MP4 或 MOV 格式。");
                        double time=RandomCoverTime(VideoDuration(input));
                        RunTool("ffmpeg.exe","-hide_banner -loglevel error -nostdin -y -ss "+time.ToString("0.######",CultureInfo.InvariantCulture)+" -i "+Arg(input)+" -map 0:v:0 -vf "+Arg(filter)+" -frames:v 1 -q:v 2 -threads 2 "+Arg(cover));
                        if(!File.Exists(cover)||new FileInfo(cover).Length==0)throw new Exception("随机封面抽取失败："+Path.GetFileName(input));
                        // Replace exactly the first visual frame and embed the same image as MP4 cover art.
                        // The timeline length and audio stream remain unchanged.
                        arguments+=" -i "+Arg(cover)+" -filter_complex "+Arg("[0:v:0]"+filter+"[base];[base][1:v:0]overlay=0:0:enable='eq(n,0)':eof_action=repeat[v]")+" -map [v] -map 0:a? -map 1:v:0 -c:v:1 copy -disposition:v:1 attached_pic";
                    } else arguments+=" -map 0:v:0 -map 0:a? -vf "+Arg(filter);
                    arguments+=" -map_metadata 0 -c:v:0 libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -threads 2 -c:a copy";
                    if(extension==".mp4"||extension==".mov"||extension==".m4v")arguments+=" -movflags +faststart";
                    RunTool("ffmpeg.exe",arguments+" "+Arg(temporary));
                    if(!File.Exists(temporary)||new FileInfo(temporary).Length==0)throw new Exception("未生成有效视频："+Path.GetFileName(input));
                    // Validate before publishing. File.Move refuses to overwrite a file created meanwhile.
                    VideoDuration(temporary);File.Move(temporary,output);File.Delete(input);
                    lock(Gate)j.completed++;
                }finally{if(File.Exists(temporary))File.Delete(temporary);if(File.Exists(cover))File.Delete(cover);}
            }
            if(Directory.GetFileSystemEntries(j.folder).Length==0)Directory.Delete(j.folder);
            lock(Gate)j.state="completed";
        }catch(Exception e){lock(Gate){j.state="failed";j.error=e.Message+" 本次未完成文件保留在："+j.folder;}}
        SaveStatus(j);
    }
    static void SaveStatus(Job j) {
        try { lock (Gate) { File.WriteAllText(Path.Combine(Root,"Resources","尺寸处理状态.json"),Json().Serialize(State(j)),Encoding.UTF8); } } catch { }
    }
    static object Route(string url, Dictionary<string,object> body) {
        if (!body.ContainsKey("token") || Convert.ToString(body["token"]) != Token) throw new Exception("本地请求校验失败");
        if(url == "/preview")return DraftPreview.Get(body.ContainsKey("draft")?Convert.ToString(body["draft"]):"");
        if(url == "/updates/info")return UpdateService.Info();
        if(url == "/updates/check")return UpdateService.Check();
        if(url == "/updates/open")return UpdateService.OpenDownload();
        if(url == "/updates/download")return UpdateService.StartDownload(body.ContainsKey("autoInstall")&&Convert.ToBoolean(body["autoInstall"]));
        if(url == "/updates/install"){if(UpdateBusy)return new{state="waiting",message="正在处理导出或素材，完成后自动更新。"};return UpdateService.Install();}
        if(url == "/updates/status")return UpdateService.DownloadStatus();
        if(url == "/updates/cancel")return UpdateService.CancelDownload();
        if(url == "/updates/show")return UpdateService.ShowDownloaded();
        lock (Gate) {
            if((url=="/begin"||url=="/collect/start")&&(UpdateInstaller.State=="preparing"||UpdateInstaller.State=="ready"))throw new Exception("正在安装更新，请稍候。");
            if (url == "/ping") return new { ok=true, version="2026.10.15" };
            if (url == "/collect/start") return MaterialCollector.Start(body.ContainsKey("drafts")?body["drafts"]:null);
            if (url == "/collect/status") return MaterialCollector.Status(body.ContainsKey("id")?Convert.ToString(body["id"]):"");
            if (url == "/begin") {
                foreach (Job old in Jobs.Values) if (old.state == "waiting" || old.state == "processing") throw new Exception("已有导出或尺寸处理任务正在运行，请完成后再开始。");
                string mode = Convert.ToString(body["mode"]);
                if (mode != "original" && mode != "auto720" && mode != "landscape" && mode != "portrait") throw new Exception("不支持的尺寸选项");
                string folder = Path.GetFullPath(Convert.ToString(body["folder"]));
                if (!Directory.Exists(folder)) throw new Exception("导出文件夹不存在，请先选择有效的自定义导出目录。");
                string idNew=Guid.NewGuid().ToString("N");
                string coverMode=body.ContainsKey("coverMode")?Convert.ToString(body["coverMode"]):"first";
                if(coverMode!="first"&&coverMode!="random")throw new Exception("不支持的封面选项。");
                string taskFolder=Path.Combine(folder,".元点处理中_"+idNew);
                var expected=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                if(body.ContainsKey("names")){var names=body["names"] as System.Collections.IEnumerable;if(names!=null)foreach(object n in names)expected.Add(Convert.ToString(n));}
                foreach(string file in Directory.GetFiles(folder))if(IsVideo(file)&&expected.Contains(Path.GetFileNameWithoutExtension(file)))throw new Exception("保存位置已有同名视频，请重命名或更换文件夹："+Path.GetFileName(file));
                Directory.CreateDirectory(taskFolder);File.SetAttributes(taskFolder,File.GetAttributes(taskFolder)|FileAttributes.Hidden);
                Job j=new Job{id=idNew,folder=taskFolder,outputFolder=folder,mode=mode,coverMode=coverMode,before=Scan(taskFolder),expected=expected};
                if (body.ContainsKey("names")) { var names = body["names"] as System.Collections.ArrayList; if(names != null) foreach(object n in names) j.expected.Add(Convert.ToString(n)); }
                Jobs[j.id] = j; SaveStatus(j); return State(j);
            }
            string id = body.ContainsKey("id") ? Convert.ToString(body["id"]) : "";
            if (!Jobs.ContainsKey(id)) throw new Exception("没有找到本次尺寸处理任务。");
            Job job = Jobs[id];
            if (url == "/cancel") { if(job.state=="waiting"){job.state="cancelled";if(Directory.Exists(job.folder)&&Directory.GetFileSystemEntries(job.folder).Length==0)Directory.Delete(job.folder);} SaveStatus(job); return State(job); }
            if (url == "/finish") {
                if (job.state == "waiting") { job.state="processing"; ThreadPool.QueueUserWorkItem(delegate { ConvertJob(job); }); }
                return State(job);
            }
            if (url == "/status") return State(job);
            throw new Exception("未知本地操作");
        }
    }
    static void Handle(TcpClient client) {
        using(client) {
            try {
                client.ReceiveTimeout=15000; client.SendTimeout=15000;
                using (NetworkStream stream=client.GetStream()) {
                    var headerBytes=new List<byte>(); int previous=0;
                    while(headerBytes.Count<16384) {
                        int b=stream.ReadByte(); if(b<0)return; headerBytes.Add((byte)b);
                        previous=(previous<<8)|b; if(previous==0x0d0a0d0a)break;
                    }
                    string headers=Encoding.ASCII.GetString(headerBytes.ToArray());
                    string[] lines=headers.Split(new[]{"\r\n"},StringSplitOptions.None); string[] request=lines[0].Split(' ');
                    int length=0;
                    foreach(string h in lines) if(h.StartsWith("Content-Length:",StringComparison.OrdinalIgnoreCase)) int.TryParse(h.Substring(15).Trim(),out length);
                    if(length<0||length>262144)throw new Exception("请求过大");
                    object result;
                    if(request[0]=="OPTIONS") result=new{ok=true};
                    else {
                        if(request[0]!="POST")throw new Exception("只支持本地 POST 请求");
                        byte[] payload=new byte[length]; int read=0; while(read<length){int n=stream.Read(payload,read,length-read);if(n==0)throw new IOException("请求未完成");read+=n;}
                        try { result=Route(request[1],Json().Deserialize<Dictionary<string,object>>(Encoding.UTF8.GetString(payload))); }
                        catch(Exception e){result=new{error=e.Message};}
                    }
                    byte[] data=Encoding.UTF8.GetBytes(Json().Serialize(result));
                    string response="HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+data.Length+"\r\n\r\n";
                    byte[] head=Encoding.ASCII.GetBytes(response);stream.Write(head,0,head.Length);stream.Write(data,0,data.Length);
                }
            } catch { }
        }
    }
}
