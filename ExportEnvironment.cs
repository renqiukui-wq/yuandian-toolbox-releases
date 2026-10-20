using System;
using System.IO;
using Microsoft.Win32;

static class ExportEnvironment {
    internal sealed class ExportLocation {
        public string folder;
        public string source;
    }

    internal static ExportLocation Resolve(string source) {
        return Resolve(source, ReadRegistry);
    }

    internal static ExportLocation Resolve(string source, Func<string,string> readRegistry) {
        if (source != "JianyingPro" && source != "CapCut")
            throw new Exception("草稿来源设置无效，请在草稿设置中选择剪映或 CapCut。");
        string client = source == "CapCut" ? "CapCut" : "剪映";
        string path;
        try {
            path = readRegistry(@"Software\Bytedance\" + source + @"\Modules\Export");
        } catch (Exception e) {
            throw new Exception("无法读取" + client + "的默认导出目录：" + e.Message + "。请检查客户端导出设置，或选择自定义保存目录。", e);
        }
        if (String.IsNullOrWhiteSpace(path))
            throw new Exception("尚未找到" + client + "的默认导出目录。请先在客户端的导出窗口设置保存位置，或在工具箱选择自定义保存目录。");
        path = path.Trim();
        bool absolute = path.StartsWith(@"\\", StringComparison.Ordinal)
            || (path.Length >= 3 && Char.IsLetter(path[0]) && path[1] == ':' && (path[2] == '\\' || path[2] == '/'));
        if (!absolute)
            throw new Exception(client + "的默认导出目录不是有效的绝对路径。请在客户端重新设置保存位置，或选择自定义保存目录。");
        try {
            path = Path.GetFullPath(path);
        } catch (Exception e) {
            throw new Exception(client + "的默认导出目录格式无效。请在客户端重新设置保存位置，或选择自定义保存目录。", e);
        }
        if (!Directory.Exists(path))
            throw new Exception(client + "的默认导出目录不存在或无法访问：" + path + "。请在客户端重新设置保存位置，或选择自定义保存目录。");
        return new ExportLocation { folder = path, source = source };
    }

    static string ReadRegistry(string subkey) {
        using (RegistryKey key = Registry.CurrentUser.OpenSubKey(subkey, false)) {
            if (key == null) return null;
            object value = key.GetValue("ExportPath", null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            if (value == null) return null;
            if (key.GetValueKind("ExportPath") != RegistryValueKind.String || !(value is string))
                throw new Exception("ExportPath 配置必须是字符串目录");
            return (string)value;
        }
    }
}
