using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("元点剪辑批量工具箱")]
[assembly: AssemblyProduct("元点剪辑批量工具箱")]
[assembly: AssemblyDescription("单文件便携版")]

class SingleFileBootstrap {
    class Bundle { public string version; public Entry[] files; }
    class Entry { public string path, sha256; public long size; }
    static JavaScriptSerializer Json() { return new JavaScriptSerializer { MaxJsonLength = 1024 * 1024 }; }
    static string Hash(Stream stream) {
        using (var sha = SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
    }
    static string CacheRoot() {
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "元点剪辑批量工具箱", "runtime");
    }
    static void NoLinks(string path, string boundary) {
        for (var current = new DirectoryInfo(path); current != null; current = current.Parent) {
            if (current.Exists && (current.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("组件目录不能是链接：" + current.FullName);
            if (String.Equals(current.FullName.TrimEnd('\\'), boundary.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)) return;
        }
        throw new IOException("组件路径超出允许目录。");
    }
    static string Target(string root, string relative) {
        if (String.IsNullOrEmpty(relative) || relative.Contains(":") || relative.Contains("\\") || relative.StartsWith("/")) throw new IOException("组件文件名无效。");
        string full = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
        if (!full.StartsWith(root.TrimEnd('\\') + "\\", StringComparison.OrdinalIgnoreCase)) throw new IOException("组件文件超出运行目录。");
        return full;
    }
    static bool Matches(string file, Entry entry) {
        if (!File.Exists(file)) return false;
        if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) throw new IOException("组件文件不能是链接：" + file);
        var info = new FileInfo(file);
        if (info.Length != entry.size) return false;
        using (var input = File.OpenRead(file)) return Hash(input) == entry.sha256;
    }
    static string Prepare(out string version) {
        Assembly assembly = Assembly.GetExecutingAssembly();
        Bundle manifest;
        using (var reader = new StreamReader(assembly.GetManifestResourceStream("Bundle.Manifest"), Encoding.UTF8))
            manifest = Json().Deserialize<Bundle>(reader.ReadToEnd());
        if (manifest == null || manifest.files == null || manifest.files.Length == 0 || manifest.version == null || manifest.version.Length != 64) throw new IOException("内置组件清单无效。");
        foreach (char c in manifest.version) if (!Uri.IsHexDigit(c)) throw new IOException("组件版本无效。");
        string parent = CacheRoot();
        NoLinks(parent, Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData));
        Directory.CreateDirectory(parent);
        string root = Path.Combine(parent, manifest.version);
        version = manifest.version;
        // A file lock serializes extraction across independent launches and app copies.
        FileStream extractionLock = null;
        Stopwatch timer = Stopwatch.StartNew();
        while (extractionLock == null) {
            try { extractionLock = new FileStream(Path.Combine(parent, ".extract.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { if (timer.Elapsed.TotalSeconds > 120) throw new IOException("组件正在准备，请稍后重试。"); Thread.Sleep(100); }
        }
        using (extractionLock) {
            NoLinks(root, parent);
            Directory.CreateDirectory(root);
            using (Stream embedded = assembly.GetManifestResourceStream("Bundle.Payload"))
            using (var zip = new ZipArchive(embedded, ZipArchiveMode.Read)) {
                var indexed = new Dictionary<string, ZipArchiveEntry>(StringComparer.OrdinalIgnoreCase);
                foreach (var item in zip.Entries) {
                    Target(root, item.FullName);
                    if (indexed.ContainsKey(item.FullName)) throw new IOException("内置组件存在重名文件。");
                    indexed.Add(item.FullName, item);
                }
                if (indexed.Count != manifest.files.Length) throw new IOException("内置组件数量与清单不符。");
                foreach (Entry entry in manifest.files) {
                    string target = Target(root, entry.path);
                    NoLinks(Path.GetDirectoryName(target), parent);
                    ZipArchiveEntry item;
                    if (!indexed.TryGetValue(entry.path, out item) || item.Length != entry.size) throw new IOException("缺少内置组件：" + entry.path);
                    if (Matches(target, entry)) continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(target));
                    string temporary = target + ".unpack-" + Guid.NewGuid().ToString("N");
                    try {
                        using (var input = item.Open())
                        using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) input.CopyTo(output);
                        if (!Matches(temporary, entry)) throw new IOException("组件校验失败：" + entry.path);
                        if (File.Exists(target)) File.Replace(temporary, target, null); else File.Move(temporary, target);
                    } finally { if (File.Exists(temporary)) File.Delete(temporary); }
                }
            }
        }
        return root;
    }
    static void Report(string path, object result) {
        File.WriteAllText(Path.GetFullPath(path), Json().Serialize(result), new UTF8Encoding(false));
    }
    [STAThread] static int Main(string[] args) {
        if(args.Length==2&&args[0]=="--apply-update")return AutoUpdateWorker.Apply(args[1],Assembly.GetExecutingAssembly().Location);
        bool verify = args.Length == 2 && args[0] == "--verify-package";
        try {
            string version;
            string root = Prepare(out version);
            string launcher = Path.Combine(root, "元点剪辑批量工具箱.exe");
            if (!File.Exists(launcher)) throw new FileNotFoundException("缺少内置启动组件。", launcher);
            if (verify) { Report(args[1], new { ok = true, version = version, runtime = root, entry = launcher }); return 0; }
            var launch=new ProcessStartInfo(launcher){WorkingDirectory=root,UseShellExecute=false,CreateNoWindow=true};
            launch.EnvironmentVariables["YUANDIAN_APP_PATH"]=Assembly.GetExecutingAssembly().Location;
            launch.EnvironmentVariables["YUANDIAN_BOOT_PID"]=Process.GetCurrentProcess().Id.ToString();
            using (Process app = Process.Start(launch)) {
                app.WaitForExit(); return app.ExitCode;
            }
        } catch (Exception error) {
            if (verify) { try { Report(args[1], new { ok = false, error = error.Message }); } catch {} }
            else MessageBox.Show("启动失败：" + error.Message, "元点剪辑批量工具箱", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
