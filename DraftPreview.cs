using System;
using System.IO;
using System.Text;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Web.Script.Serialization;
static class DraftPreview {
 static readonly object Gate=new object();
 class Entry {public string signature;public object result;}
 static readonly Dictionary<string,Entry> Cache=new Dictionary<string,Entry>(StringComparer.OrdinalIgnoreCase);
 static string Hash(byte[] bytes){using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-","");}
 static JavaScriptSerializer Json(){return new JavaScriptSerializer{MaxJsonLength=64*1024*1024,RecursionLimit=512};}
 static object Result(string image,string kind,string message){return new{state=image==null?"empty":"ready",image=image,kind=kind,message=message};}
 static byte[] Read(string file,int limit){using(var stream=new FileStream(file,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){if(stream.Length>limit)throw new Exception("文件过大");using(var output=new MemoryStream()){stream.CopyTo(output);return output.ToArray();}}}
 static string Resize(byte[] bytes){using(var ms=new MemoryStream(bytes))using(var image=Image.FromStream(ms,true,true)){
  if(image.Width>20000||image.Height>20000||(long)image.Width*image.Height>80000000)throw new Exception("封面尺寸过大");
  double ratio=Math.Min(1,Math.Min(960.0/image.Width,540.0/image.Height));int w=Math.Max(1,(int)(image.Width*ratio)),h=Math.Max(1,(int)(image.Height*ratio));
  using(var bitmap=new Bitmap(w,h))using(var g=Graphics.FromImage(bitmap))using(var output=new MemoryStream()){
   g.Clear(Color.FromArgb(18,24,33));g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(image,0,0,w,h);bitmap.Save(output,ImageFormat.Jpeg);return "data:image/jpeg;base64,"+Convert.ToBase64String(output.ToArray());
  }
 }}
 static string Signature(IEnumerable<string> files){var s=new StringBuilder();foreach(string f in files){var i=new FileInfo(f);s.Append(f).Append('|').Append(i.Length).Append('|').Append(i.LastWriteTimeUtc.Ticks).Append(';');}return s.ToString();}
 static List<string> Documents(string root){var result=new List<string>();foreach(string name in new[]{"draft_content.json","draft_info.json","draft_meta_info.json"}){string p=Path.Combine(root,name);if(File.Exists(p))result.Add(p);}string timelines=Path.Combine(root,"Timelines");if(Directory.Exists(timelines)){foreach(string dir in Directory.GetDirectories(timelines).Take(100)){if((File.GetAttributes(dir)&FileAttributes.ReparsePoint)!=0)continue;foreach(string name in new[]{"draft_content.json","draft_info.json"}){string p=Path.Combine(dir,name);if(File.Exists(p))result.Add(p);}}}return result;}
 static void Paths(object node,string root,List<string> results){var dict=node as Dictionary<string,object>;if(dict!=null){foreach(var p in dict){string value=p.Value as string;if(value!=null&&(p.Key=="path"||p.Key=="file_Path"||p.Key=="file_path")){try{Uri uri;if(Uri.TryCreate(value,UriKind.Absolute,out uri)&&uri.IsFile)value=uri.LocalPath;if(!Path.IsPathRooted(value))value=Path.Combine(root,value);string ext=Path.GetExtension(value).ToLowerInvariant();if(new[]{".mp4",".mov",".mkv",".avi",".m4v",".jpg",".jpeg",".png",".webp",".bmp"}.Contains(ext)&&File.Exists(value)&&!results.Contains(value))results.Add(value);}catch{}}else Paths(p.Value,root,results);}}else{var list=node as IList;if(list!=null)foreach(object item in list)Paths(item,root,results);}}
 static string Frame(string source){string ffmpeg=Path.Combine(LocalLauncher.RuntimeResources,"ffmpeg.exe");string tempRoot=Path.Combine(Path.GetTempPath(),"YuandianPreview");Directory.CreateDirectory(tempRoot);string output=Path.Combine(tempRoot,Guid.NewGuid().ToString("N")+".jpg");try{
  var start=new ProcessStartInfo(ffmpeg,"-v error -nostdin -y -i "+Arg(source)+" -frames:v 1 -vf "+Arg("scale=960:540:force_original_aspect_ratio=decrease")+" -threads 1 "+Arg(output)){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true};
  using(var p=Process.Start(start)){p.ErrorDataReceived+=(s,e)=>{};p.BeginErrorReadLine();try{p.PriorityClass=ProcessPriorityClass.BelowNormal;}catch{}if(!p.WaitForExit(5000)){p.Kill();p.WaitForExit();throw new Exception("预览生成超时");}if(p.ExitCode!=0||!File.Exists(output))throw new Exception("素材无法读取");}
  return Resize(Read(output,20*1024*1024));
 }finally{if(File.Exists(output))File.Delete(output);}}
 static string Arg(string s){return "\""+s.Replace("\"","\\\"")+"\"";}
 public static object Get(string folder){
  string root=Path.GetFullPath(folder??"");if(!Directory.Exists(root))return Result(null,"missing","草稿目录不存在");
  if((File.GetAttributes(root)&FileAttributes.ReparsePoint)!=0)return Result(null,"missing","不支持链接目录");
  var docs=Documents(root);if(docs.Count==0)return Result(null,"missing","未找到草稿内容");
  foreach(string name in new[]{"draft_cover.jpg","draft_cover.png","draft_cover.jpeg","draft_cover.webp","cover.jpg","cover.png"}){
   string file=Path.Combine(root,name);if(!File.Exists(file))continue;
   try{byte[] bytes=Read(file,20*1024*1024);string signature="cover:"+file+":"+Hash(bytes);lock(Gate){Entry old;if(Cache.TryGetValue(root,out old)&&old.signature==signature)return old.result;}
    object value=Result(Resize(bytes),"cover","剪映最近保存的草稿封面");Remember(root,signature,value);return value;
   }catch{}
  }
  string stamp=Signature(docs);var sources=new List<string>();foreach(string doc in docs.Take(8)){try{string text=Encoding.UTF8.GetString(Read(doc,64*1024*1024)).TrimStart('\uFEFF');object data;try{data=Json().DeserializeObject(text);}catch{text=DraftCrypto.Convert(text,false);data=Json().DeserializeObject(text);}Paths(data,root,sources);}catch{}if(sources.Count>=10)break;}
  string fallbackSignature="material:"+stamp+":"+Signature(sources.Take(3));lock(Gate){Entry old;if(Cache.TryGetValue(root,out old)&&old.signature==fallbackSignature)return old.result;}
  foreach(string source in sources.Take(3)){try{object value=Result(Frame(source),"material","素材画面，仅供识别草稿，不代表完整时间线效果");Remember(root,fallbackSignature,value);return value;}catch{}}
  object empty=Result(null,"unavailable","暂无可用预览：请在剪映打开并保存草稿，检查素材是否存在");Remember(root,fallbackSignature,empty);return empty;
 }
 static void Remember(string root,string signature,object value){lock(Gate){if(Cache.Count>=160&&!Cache.ContainsKey(root))Cache.Remove(Cache.Keys.First());Cache[root]=new Entry{signature=signature,result=value};}}
}
