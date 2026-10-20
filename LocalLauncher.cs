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
        public bool removeSilence;
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
    static string RunTool(string executable,string arguments,bool diagnostics=false) {
        var start=new ProcessStartInfo(Path.Combine(RuntimeResources,executable)){Arguments=arguments,WorkingDirectory=Root,UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
        using(var p=Process.Start(start)) {var errors=new StringBuilder();p.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)lock(errors)errors.AppendLine(e.Data);};p.BeginErrorReadLine();try{p.PriorityClass=ProcessPriorityClass.BelowNormal;}catch{}string output=p.StandardOutput.ReadToEnd();p.WaitForExit();if(p.ExitCode!=0)throw new Exception(executable+"："+errors.ToString());return diagnostics?output+errors.ToString():output;}
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
    internal sealed class VideoSpec { public int width,height; public double dar,rotation,sar=1,duration;public bool audio; }
    internal static int ShortEdge(string mode) { switch(mode) { case "auto720":return 720;case "auto1080":return 1080;case "auto1440":return 1440;case "auto2160":return 2160;default:return 0; } }
    static double Number(Dictionary<string,object> value,string key,double fallback) { double result;return value.ContainsKey(key)&&Double.TryParse(Convert.ToString(value[key],CultureInfo.InvariantCulture),NumberStyles.Float,CultureInfo.InvariantCulture,out result)&&!Double.IsNaN(result)&&!Double.IsInfinity(result)?result:fallback; }
    static VideoSpec ProbeVideo(string input) {
        var data=Json().Deserialize<Dictionary<string,object>>(RunTool("MediaInfo.exe","--Output=JSON "+Arg(input)));
        var media=(Dictionary<string,object>)data["media"];
        foreach(Dictionary<string,object> track in (System.Collections.IEnumerable)media["track"])if(Convert.ToString(track["@type"])=="Video") {
            var spec=new VideoSpec{width=(int)Number(track,"Width",0),height=(int)Number(track,"Height",0),rotation=Number(track,"Rotation",0),sar=Number(track,"PixelAspectRatio",1),duration=Number(track,"Duration",0)};
            if(spec.width<=0||spec.height<=0)throw new Exception("无法读取视频尺寸："+Path.GetFileName(input));
            spec.dar=spec.width*spec.sar/spec.height;
            if(Math.Abs(spec.rotation%180)>45&&Math.Abs(spec.rotation%180)<135)spec.dar=1/spec.dar;
            if(spec.dar<=0)throw new Exception("视频比例无效");foreach(Dictionary<string,object> other in (System.Collections.IEnumerable)media["track"])if(Convert.ToString(other["@type"])=="Audio")spec.audio=true;return spec;
        } throw new Exception("没有视频轨道");
    }
    internal static int[] TargetSize(VideoSpec spec,string mode) {
        int edge=ShortEdge(mode);if(edge==0)return new[]{spec.width,spec.height};
        double width=spec.dar>=1?edge*spec.dar:edge,height=spec.dar>=1?edge:edge/spec.dar;
        if(width>16384||height>16384)throw new Exception("目标尺寸超出编码范围");
        return new[]{Math.Max(2,(int)Math.Round(width/2,MidpointRounding.AwayFromZero)*2),Math.Max(2,(int)Math.Round(height/2,MidpointRounding.AwayFromZero)*2)};
    }
    internal static bool NeedsResize(VideoSpec spec,string mode) {
        if(mode=="original")return false;var target=TargetSize(spec,mode);
        return spec.width!=target[0]||spec.height!=target[1]||Math.Abs(spec.sar-1)>.0001||Math.Abs(spec.rotation%360)>.01;
    }
    static void ConvertJob(Job j) {
        try {
            var after=Scan(j.folder);var targets=new List<string>();
            foreach(var f in after)if((j.expected.Count==0||j.expected.Contains(Path.GetFileNameWithoutExtension(f.Key)))&&(!j.before.ContainsKey(f.Key)||j.before[f.Key]!=f.Value))targets.Add(f.Key);
            if(targets.Count==0)throw new Exception("没有找到本次导出的视频。");
            lock(Gate)j.total=targets.Count;var errors=new List<string>();
            foreach(string input in targets) {
                string extension=Path.GetExtension(input).ToLowerInvariant();string temporary=Path.Combine(j.folder,".xy-size-"+Guid.NewGuid().ToString("N")+extension);string cover=Path.Combine(j.folder,".xy-cover-"+Guid.NewGuid().ToString("N")+".jpg");
                try {
                    string output=Path.Combine(j.outputFolder,Path.GetFileName(input));if(File.Exists(output))throw new Exception("保存位置已有同名视频，请重命名或更换文件夹："+Path.GetFileName(input));
                    var spec=ProbeVideo(input);var dimensions=TargetSize(spec,j.mode);
                    bool resize=NeedsResize(spec,j.mode);
                    var keep=new List<SilenceProcessor.Range>{new SilenceProcessor.Range(0,spec.duration)};bool cut=false;
                    if(j.removeSilence&&spec.audio){var detected=RunTool("ffmpeg.exe","-hide_banner -nostdin -i "+Arg(input)+" -map 0:a:0 -af silencedetect=noise=-40dB:d=0.5 -vn -sn -f null -",true);var cuts=SilenceProcessor.Parse(detected,spec.duration,.08);cut=cuts.Count>0;if(cut)keep=SilenceProcessor.Keep(cuts,spec.duration);}
                    double expectedDuration=cut?SilenceProcessor.Duration(keep):spec.duration;
                    if(!resize&&!cut&&j.coverMode!="random") { File.Move(input,output);lock(Gate)j.completed++;continue; }
                    string filter=resize?"scale="+dimensions[0]+":"+dimensions[1]+",setsar=1":"null";
                    string arguments="-hide_banner -loglevel error -nostdin -y -i "+Arg(input);
                    string graph=cut?SilenceProcessor.Filter(keep,filter,spec.audio):"[0:v:0]"+filter+"[base]";
                    if(j.coverMode=="random") {
                        if(extension!=".mp4"&&extension!=".mov"&&extension!=".m4v")throw new Exception("随机封面需要 MP4 或 MOV 格式。");
                        double offset=RandomCoverTime(expectedDuration),time=offset;
                        if(cut){foreach(var range in keep){if(offset<=range.end-range.start){time=range.start+offset;break;}offset-=range.end-range.start;}}
                        RunTool("ffmpeg.exe","-hide_banner -loglevel error -nostdin -y -ss "+time.ToString("0.######",CultureInfo.InvariantCulture)+" -i "+Arg(input)+" -map 0:v:0 -vf "+Arg(filter)+" -frames:v 1 -q:v 2 -threads 2 "+Arg(cover));
                        if(!File.Exists(cover)||new FileInfo(cover).Length==0)throw new Exception("随机封面抽取失败："+Path.GetFileName(input));
                        arguments+=" -i "+Arg(cover);graph+=";[base][1:v:0]overlay=0:0:enable='eq(n,0)':eof_action=repeat[v]";
                    }else graph+=";[base]null[v]";
                    string script=temporary+".filter";File.WriteAllText(script,graph,new UTF8Encoding(false));
                    try{
                        arguments+=" -filter_complex_script "+Arg(script)+" -map [v] "+(cut&&spec.audio?"-map [audio]":"-map 0:a?");
                        if(j.coverMode=="random")arguments+=" -map 1:v:0 -c:v:1 copy -disposition:v:1 attached_pic";
                        arguments+=" -map_metadata 0 -c:v:0 libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -threads 2 "+(cut?"-c:a aac -b:a 192k":"-c:a copy");
                        if(extension==".mp4"||extension==".mov"||extension==".m4v")arguments+=" -movflags +faststart";
                        RunTool("ffmpeg.exe",arguments+" "+Arg(temporary));
                    }finally{if(File.Exists(script))File.Delete(script);}
                    if(!File.Exists(temporary)||new FileInfo(temporary).Length==0)throw new Exception("未生成有效视频："+Path.GetFileName(input));
                    // Validate before publishing. File.Move refuses to overwrite a file created meanwhile.
                    var verified=ProbeVideo(temporary); if(spec.audio&&!verified.audio)throw new Exception("输出音轨校验失败"); if(spec.duration>0&&Math.Abs(verified.duration-expectedDuration)>0.25)throw new Exception("输出时长校验失败"); if(resize&&(verified.width!=dimensions[0]||verified.height!=dimensions[1]))throw new Exception("输出尺寸校验失败");File.Move(temporary,output);File.Delete(input);
                    lock(Gate)j.completed++;
                }catch(Exception e){errors.Add(Path.GetFileName(input)+"："+e.Message);}finally{if(File.Exists(temporary))File.Delete(temporary);if(File.Exists(cover))File.Delete(cover);}
            }
            if(Directory.GetFileSystemEntries(j.folder).Length==0)Directory.Delete(j.folder);
            lock(Gate){j.state=errors.Count==0?"completed":"failed";if(errors.Count>0)j.error="已完成 "+j.completed+" / "+j.total+" 个视频。未完成："+String.Join("；",errors.ToArray())+"。未完成文件保留在："+j.folder;}
        }catch(Exception e){lock(Gate){j.state="failed";j.error=e.Message+" 本次未完成文件保留在："+j.folder;}}
        SaveStatus(j);
    }
    static void SaveStatus(Job j) {
        try { lock (Gate) { File.WriteAllText(Path.Combine(Root,"Resources","尺寸处理状态.json"),Json().Serialize(State(j)),Encoding.UTF8); } } catch { }
    }
    static string ExportDiagnostic(Dictionary<string,object> body) {
        string folder=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"元点剪辑批量工具箱","logs");Directory.CreateDirectory(folder);
        string path=Path.Combine(folder,"export-start.log");var record=new Dictionary<string,object>();foreach(string key in new[]{"time","stage","method","message","settings"})if(body.ContainsKey(key))record[key]=body[key];record["recordedAt"]=DateTime.UtcNow.ToString("o");
        string text=Json().Serialize(record);if(text.Length>32000)throw new Exception("错误详情过长");lock(Gate){if(File.Exists(path)&&new FileInfo(path).Length>2*1024*1024){string old=path+".1";if(File.Exists(old))File.Delete(old);File.Move(path,old);}File.AppendAllText(path,text+Environment.NewLine,new UTF8Encoding(false));}return path;
    }
    static object Route(string url, Dictionary<string,object> body) {
        if (!body.ContainsKey("token") || Convert.ToString(body["token"]) != Token) throw new Exception("本地请求校验失败");
        if(url == "/diagnostics/export")return new{logFile=ExportDiagnostic(body)};
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
                if (mode != "original" && ShortEdge(mode)==0) throw new Exception("不支持的尺寸选项");
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
                Job j=new Job{id=idNew,folder=taskFolder,outputFolder=folder,mode=mode,coverMode=coverMode,before=Scan(taskFolder),expected=expected,removeSilence=body.ContainsKey("removeSilence")&&Convert.ToBoolean(body["removeSilence"])};
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
                        catch(Exception e){result=new{error=e.Message};if(request[1]=="/begin"||request[1]=="/finish")try{ExportDiagnostic(new Dictionary<string,object>{{"stage",request[1]},{"message",e.Message}});}catch{}}
                    }
                    byte[] data=Encoding.UTF8.GetBytes(Json().Serialize(result));
                    string response="HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nAccess-Control-Allow-Private-Network: true\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+data.Length+"\r\n\r\n";
                    byte[] head=Encoding.ASCII.GetBytes(response);stream.Write(head,0,head.Length);stream.Write(data,0,data.Length);
                }
            } catch { }
        }
    }
}
