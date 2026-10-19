import Foundation

struct MacRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: URL; let digest: String? }
    let tag_name: String; let html_url: URL; let body: String?; let draft: Bool; let assets: [Asset]
}
enum MacUpdates {
    static let repository = "https://github.com/renqiukui-wq/yuandian-toolbox-releases"
    static let assetName = "YuandianToolbox-macOS-universal.zip"
    static func version(_ release:MacRelease) -> String? {
        guard release.tag_name.hasPrefix("macos-v") else { return nil }
        let version=String(release.tag_name.dropFirst(7))
        let components=version.split(separator:".",omittingEmptySubsequences:false)
        guard components.count == 3, components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({$0.isASCII && $0.isNumber}) }) else { return nil }
        return version
    }
    static func validDownload(_ url:URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil && url.path.hasPrefix("/renqiukui-wq/yuandian-toolbox-releases/releases/download/macos-v")
    }
    static func latest(_ releases:[MacRelease]) -> MacRelease? {
        releases.filter { !$0.draft && version($0) != nil && $0.assets.contains { $0.name == assetName && validDownload($0.browser_download_url) } }
            .max { version($0)!.compare(version($1)!,options:.numeric) == .orderedAscending }
    }
    static func verify(_ file:URL,expected:String?) throws {
        guard let expected=expected?.lowercased(), expected.hasPrefix("sha256:"), expected.count == 71,
              expected.dropFirst(7).allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw ToolboxError("安装包缺少有效 SHA-256 校验，请前往网站下载。") }
        guard try fileDigest(file) == String(expected.dropFirst(7)) else { throw ToolboxError("安装包校验失败，请重新下载。") }
    }
}
final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let report: (Int64,Int64) -> Void
    init(report:@escaping (Int64,Int64) -> Void) { self.report=report }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) { report(totalBytesWritten,totalBytesExpectedToWrite) }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {}
}
