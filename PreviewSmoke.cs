using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;
using System.Collections.Generic;
using System.Text;
using System.Web.Script.Serialization;
class LocalLauncher {
 public static string RuntimeResources=Path.Combine(Environment.CurrentDirectory,"work","build_inputs","runtime_payload","Resources","Core","Resources");
 static void Assert(bool condition,string message){if(!condition)throw new Exception(message);}
 static Dictionary<string,object> Read(string folder){var json=new JavaScriptSerializer{MaxJsonLength=4*1024*1024};return json.Deserialize<Dictionary<string,object>>(json.Serialize(DraftPreview.Get(folder)));}
 static void Picture(string file,Color color){using(var image=new Bitmap(160,90))using(var graphics=Graphics.FromImage(image)){graphics.Clear(color);image.Save(file,ImageFormat.Png);}}
 static void Main(){Console.OutputEncoding=new UTF8Encoding(false);string root=Path.Combine(Environment.CurrentDirectory,"preview-tests",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);File.WriteAllText(Path.Combine(root,"draft_content.json"),"{}");string cover=Path.Combine(root,"draft_cover.png");Picture(cover,Color.Red);DateTime time=File.GetLastWriteTimeUtc(cover);var a=Read(root);Assert((string)a["state"]=="ready","Cover must load");Picture(cover,Color.Blue);File.SetLastWriteTimeUtc(cover,time);var b=Read(root);Assert((string)a["image"]!=(string)b["image"],"Changed bytes must invalidate cached cover even if timestamp is unchanged");File.Delete(cover);Assert((string)Read(root)["state"]=="empty","Deleted cover must not remain cached");Picture(cover,Color.Green);Assert((string)Read(root)["state"]=="ready","Restored cover must load");Assert(File.ReadAllText(Path.Combine(root,"draft_content.json"))=="{}","Draft content must remain unchanged");Console.WriteLine("PASS: preview change, deletion, restoration and read-only draft behavior");}
}
