using System;
using System.IO;
using System.Net;
using System.Text;
using System.Threading;
using System.Diagnostics;
using System.Collections;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

static class UpdateService {
    static readonly object Gate=new object();
    class Release {public string version,page,url,hash;public long size;public bool github;}
    class DownloadJob {public bool autoInstall;public string hash="";public string version="",state="downloading",message="正在连接下载服务器…",path="";public long received,total;public bool cancel;public HttpWebRequest request;}
    static Release Latest;
    static DownloadJob Download;
    public static bool IsBusy {get{lock(Gate)return Download!=null&&Download.state=="downloading";}}
    static Version ParseVersion(string text) {
        Version result;
        if(String.IsNullOrEmpty(text)||!Regex.IsMatch(text,@"^\d+\.\d+\.\d+$")||!Version.TryParse(text,out result))throw new Exception("更新信息中的版本号无效。");
        return result;
    }
    static Uri Https(string text) {
        Uri uri;
        if(!Uri.TryCreate(text,UriKind.Absolute,out uri)||uri.Scheme!="https"||!String.IsNullOrEmpty(uri.UserInfo))throw new Exception("更新地址必须使用有效的 HTTPS 链接。");
        return uri;
    }
    static string Repo(){string value=ReleaseSettings.GithubRepository;if(!Regex.IsMatch(value,@"^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"))throw new Exception("发布仓库配置无效。");return value;}
    static string Text(Dictionary<string,object> data,string key){return data.ContainsKey(key)?Convert.ToString(data[key]):"";}
    static bool Flag(Dictionary<string,object> data,string key){return data.ContainsKey(key)&&data[key] is bool&&(bool)data[key];}
    public static object Info(){return new {currentVersion=ReleaseSettings.Version,configured=!String.IsNullOrWhiteSpace(ReleaseSettings.GithubRepository)||!String.IsNullOrWhiteSpace(ReleaseSettings.ManifestUrl)};}
    static HttpWebRequest Request(Uri uri){
        ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
        var r=(HttpWebRequest)WebRequest.Create(uri);r.Method="GET";r.Timeout=15000;r.ReadWriteTimeout=20000;r.AllowAutoRedirect=false;
        r.UserAgent="YuandianToolbox/"+ReleaseSettings.Version;
        r.CachePolicy=new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
        return r;
    }
    static string GetJson(string url,bool github){
        var request=Request(Https(url));request.Accept="application/vnd.github+json";
        if(github)request.Headers["X-GitHub-Api-Version"]="2026-03-10";
        using(var response=(HttpWebResponse)request.GetResponse()){
            if(response.StatusCode!=HttpStatusCode.OK)throw new Exception("版本信息地址没有返回有效内容。");
            using(var stream=response.GetResponseStream())using(var buffer=new MemoryStream()){
                byte[] bytes=new byte[8192];int n;
                while((n=stream.Read(bytes,0,bytes.Length))>0){if(buffer.Length+n>1048576)throw new Exception("更新信息过大，请联系软件发布者。");buffer.Write(bytes,0,n);}
                return Encoding.UTF8.GetString(buffer.ToArray()).TrimStart('﻿');
            }
        }
    }
    public static object Check(){
        lock(Gate){if(IsBusy)throw new Exception("请先完成或取消当前下载。");Latest=null;}
        bool github=!String.IsNullOrWhiteSpace(ReleaseSettings.GithubRepository);
        if(!github&&String.IsNullOrWhiteSpace(ReleaseSettings.ManifestUrl))return new{state="unconfigured",currentVersion=ReleaseSettings.Version,message="更新通道尚未开通，请从软件发布者处获取新版。"};
        try{return github?ReadGithub(GetJson("https://api.github.com/repos/"+Repo()+"/releases/latest",true),Repo()):ReadManifest(GetJson(ReleaseSettings.ManifestUrl,false));}
        catch(WebException e){var response=e.Response as HttpWebResponse;if(response!=null){int code=(int)response.StatusCode;response.Close();if(code==404)throw new Exception("尚未找到公开正式版本，请稍后重试。");if(code==403||code==429)throw new Exception("更新服务暂时限制请求，请稍后重试。");}throw new Exception("暂时无法连接更新服务，请检查网络后重试。");}
    }
    static Dictionary<string,object> Json(string text){var data=new JavaScriptSerializer{MaxJsonLength=1048576}.Deserialize<Dictionary<string,object>>(text);if(data==null)throw new Exception("更新信息无效。");return data;}
    static object Publish(Release item,string notes){
        bool available=ParseVersion(item.version).CompareTo(ParseVersion(ReleaseSettings.Version))>0;
        if(notes.Length>20000)notes=notes.Substring(0,20000)+"…";
        if(available){Https(item.page);lock(Gate)Latest=item;}
        bool can=available&&!String.IsNullOrEmpty(item.url)&&Regex.IsMatch(item.hash??"",@"^[0-9a-fA-F]{64}$")&&item.size>0&&item.size<=2147483648L;
        return new{state=available?"available":"current",currentVersion=ReleaseSettings.Version,latestVersion=item.version,notes=notes,canDownload=can,size=item.size,message=available?(can?"发现新版本，可直接在软件内下载。":"发现新版本，请前往发布页下载。"):"当前版本已是最新版本"};
    }
    public static object ReadGithub(string text,string repo){
        if(!Regex.IsMatch(repo,@"^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9][A-Za-z0-9._-]*$"))throw new Exception("发布仓库配置无效。");
        var data=Json(text);if(Flag(data,"draft")||Flag(data,"prerelease"))throw new Exception("该版本尚未正式发布。");
        string version=Text(data,"tag_name");if(version.StartsWith("v",StringComparison.OrdinalIgnoreCase))version=version.Substring(1);ParseVersion(version);
        var release=new Release{version=version,page="https://github.com/"+repo+"/releases/latest",github=true};
        var assets=data.ContainsKey("assets")?data["assets"] as IEnumerable:null;
        if(assets!=null)foreach(var raw in assets){var asset=raw as Dictionary<string,object>;if(asset==null||Text(asset,"name")!=ReleaseSettings.AssetName||Text(asset,"state")!="uploaded")continue;
            Uri url=Https(Text(asset,"browser_download_url"));
            if(url.Host!="github.com"||!url.AbsolutePath.StartsWith("/"+repo+"/releases/download/",StringComparison.OrdinalIgnoreCase))throw new Exception("下载地址与发布仓库不匹配。");
            release.url=url.AbsoluteUri;long size;if(!Int64.TryParse(Text(asset,"size"),out size))throw new Exception("下载文件大小无效。");release.size=size;
            string digest=Text(asset,"digest");release.hash=digest.StartsWith("sha256:",StringComparison.OrdinalIgnoreCase)?digest.Substring(7):"";break;
        }
        return Publish(release,Text(data,"body"));
    }
    public static object ReadManifest(string text){
        var data=Json(text);if(Text(data,"product")!="yuandian-toolbox")throw new Exception("更新信息与当前软件不匹配。");
        return Publish(new Release{version=Text(data,"version"),page=Text(data,"downloadPage")},Text(data,"notes"));
    }
    public static object OpenDownload(){string url;lock(Gate){url=Latest!=null?Latest.page:!String.IsNullOrWhiteSpace(ReleaseSettings.GithubRepository)?"https://github.com/"+Repo()+"/releases/latest":null;if(url==null)throw new Exception("请先检查更新。");}Https(url);Process.Start(new ProcessStartInfo(url){UseShellExecute=true});return new{ok=true};}
    static object Status(DownloadJob d){return d==null?(object)new{state="idle",received=0L,total=0L,percent=0,message=""}:new{state=d.state,version=d.version,received=d.received,total=d.total,percent=d.total>0?(int)Math.Min(100,d.received*100/d.total):0,message=d.message,path=d.state=="completed"?d.path:"",autoInstall=d.autoInstall,installState=UpdateInstaller.State,installMessage=UpdateInstaller.Message};}
    public static object DownloadStatus(){lock(Gate)return Status(Download);}
    public static object StartDownload(bool autoInstall=false){
        lock(Gate){if(IsBusy)return Status(Download);if(Latest==null||String.IsNullOrEmpty(Latest.url)||!Regex.IsMatch(Latest.hash??"",@"^[0-9a-fA-F]{64}$")||Latest.size<=0||Latest.size>2147483648L)throw new Exception("此版本暂不支持软件内校验下载，请前往发布页。");
            Release release=Latest;DownloadJob job=new DownloadJob{total=release.size,version=release.version,hash=release.hash.ToLowerInvariant(),autoInstall=autoInstall};UpdateInstaller.Reset();Download=job;ThreadPool.QueueUserWorkItem(delegate{DownloadFile(release,job);});return Status(job);}
    }
    public static object Install(){DownloadJob job;lock(Gate){if(Download==null||Download.state!="completed")throw new Exception("请先完成下载。");job=Download;}return UpdateInstaller.Prepare(job.path,job.hash,job.total);}
    public static object CancelDownload(){lock(Gate){if(IsBusy){Download.cancel=true;Download.message="正在取消下载…";if(Download.request!=null)Download.request.Abort();}return Status(Download);}}
    static void CheckCancelled(DownloadJob job){lock(Gate)if(job.cancel)throw new OperationCanceledException();}
    static void NoLinks(string path,string boundary){for(var dir=new DirectoryInfo(path);dir!=null;dir=dir.Parent){if(dir.Exists&&(dir.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("下载目录不能是链接。");if(String.Equals(dir.FullName,boundary,StringComparison.OrdinalIgnoreCase))return;}throw new IOException("下载目录无效。");}
    static void ValidateFile(string path,Release release){
        if(new FileInfo(path).Length!=release.size)throw new IOException("下载不完整，请重试。");
        using(var input=File.OpenRead(path))using(var hash=SHA256.Create()){string actual=BitConverter.ToString(hash.ComputeHash(input)).Replace("-","");if(!String.Equals(actual,release.hash,StringComparison.OrdinalIgnoreCase))throw new IOException("文件校验失败，请重新下载。");input.Position=0;if(input.ReadByte()!=77||input.ReadByte()!=90)throw new IOException("下载内容不是有效的 Windows 程序。");}
    }
    static void DownloadFile(Release release,DownloadJob job){
        string partial=null;
        try{
            string local=Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string directory=Path.Combine(local,"元点剪辑批量工具箱","updates",release.version,Guid.NewGuid().ToString("N"));NoLinks(directory,local);Directory.CreateDirectory(directory);
            string target=Path.Combine(directory,"元点剪辑批量工具箱.exe");partial=target+".part";Uri url=Https(release.url);
            for(int redirects=0;;redirects++){
                CheckCancelled(job);if(redirects>5)throw new IOException("下载链接跳转次数过多。");
                if(release.github&&url.Host!="github.com"&&!url.Host.EndsWith(".githubusercontent.com",StringComparison.OrdinalIgnoreCase))throw new IOException("下载跳转地址不受支持。");
                var request=Request(url);lock(Gate)job.request=request;
                using(var response=(HttpWebResponse)request.GetResponse()){
                    int code=(int)response.StatusCode;if(code>=300&&code<400){url=Https(new Uri(url,response.Headers["Location"]).AbsoluteUri);continue;}
                    if(code!=200)throw new IOException("下载服务器未返回有效文件。");
                    if(response.ContentLength>=0&&response.ContentLength!=release.size)throw new IOException("下载文件大小与发布信息不一致。");
                    using(var stream=response.GetResponseStream())using(var output=new FileStream(partial,FileMode.CreateNew,FileAccess.Write,FileShare.None)){
                        byte[] buffer=new byte[65536];int n;long received=0;
                        while((n=stream.Read(buffer,0,buffer.Length))>0){CheckCancelled(job);received+=n;if(received>release.size)throw new IOException("下载文件大小异常。");output.Write(buffer,0,n);lock(Gate){job.received=received;job.message="正在下载新版…";}}
                    }
                    break;
                }
            }
            CheckCancelled(job);lock(Gate)job.message="正在校验文件…";ValidateFile(partial,release);CheckCancelled(job);File.Move(partial,target);
            lock(Gate){job.path=target;job.state="completed";job.message=job.autoInstall?"下载完成，文件校验通过，准备自动更新。":"下载完成，文件校验通过。请退出旧版后，用下载的 EXE 替换原文件。";}
        }catch(Exception e){lock(Gate){job.state=job.cancel?"cancelled":"failed";job.message=job.cancel?"下载已取消，可重新下载。":e is WebException?"下载连接中断，请检查网络后重试。":e.Message;}}
        finally{lock(Gate)job.request=null;if(partial!=null&&File.Exists(partial)){try{File.Delete(partial);}catch{}}}
    }
    public static object ShowDownloaded(){string path;lock(Gate){if(Download==null||Download.state!="completed")throw new Exception("请先完成下载。");path=Download.path;}if(!File.Exists(path))throw new Exception("下载文件已被移动或删除，请重新下载。");Process.Start(new ProcessStartInfo("explorer.exe","/select,\""+path+"\""){UseShellExecute=true});return new{ok=true};}
}
