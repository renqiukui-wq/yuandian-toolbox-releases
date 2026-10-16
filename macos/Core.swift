import Foundation
import CryptoKit

struct ToolboxError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
let mediaExtensions: Set<String> = ["mp4","mov","m4v","mkv","avi","webm","jpg","jpeg","png","webp","heic","bmp","gif","mp3","wav","m4a","aac","flac","aiff","caf"]
let mediaPathKeys: Set<String> = ["path", "file_Path", "file_path", "material_path", "local_path"]
func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func fileDigest(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var hash = SHA256()
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func cleanName(_ name: String) -> String {
    let bad = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
    let value = name.components(separatedBy: bad).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty || value == "." || value == ".." ? "未命名" : String(value.prefix(160))
}
func isInside(_ child: URL, _ parent: URL) -> Bool {
    let a = child.resolvingSymlinksInPath().standardizedFileURL.path
    let b = parent.resolvingSymlinksInPath().standardizedFileURL.path
    return a == b || a.hasPrefix(b + "/")
}
func localURL(_ value: String, base: URL) -> URL? {
    if value.isEmpty || value.hasPrefix("http:") || value.hasPrefix("https:") { return nil }
    if value.hasPrefix("file://") { return URL(string: value)?.standardizedFileURL }
    if value.hasPrefix("/") { return URL(fileURLWithPath: value).standardizedFileURL }
    // A Windows path must remain unresolved; never treat it as a valid Mac relative path.
    if value.contains(":\\") || value.contains(":/") { return URL(fileURLWithPath: value, relativeTo: base).standardizedFileURL }
    return base.appendingPathComponent(value).standardizedFileURL
}
func referencedMedia(_ object: Any, base: URL) -> [URL] {
    var result: [URL] = []
    if let dict = object as? [String: Any] {
        for (key, value) in dict {
            if mediaPathKeys.contains(key), let value = value as? String,
               let url = localURL(value, base: base), mediaExtensions.contains(url.pathExtension.lowercased()) { result.append(url) }
            else { result += referencedMedia(value, base: base) }
        }
    } else if let array = object as? [Any] { for value in array { result += referencedMedia(value, base: base) } }
    return result
}
func rewriteMedia(_ object: Any, base: URL, replacements: [String: String]) -> Any {
    if var dict = object as? [String: Any] {
        for (key, value) in dict {
            if mediaPathKeys.contains(key), let value = value as? String, let url = localURL(value, base: base), let new = replacements[url.path] { dict[key] = new }
            else { dict[key] = rewriteMedia(value, base: base, replacements: replacements) }
        }
        return dict
    }
    if let array = object as? [Any] { return array.map { rewriteMedia($0, base: base, replacements: replacements) } }
    return object
}
struct Draft: Identifiable {
    var id: String { folder.path }
    let folder: URL
    let name: String
    let modified: Date
    let fingerprint: String
    let documents: [URL]
    let materials: [URL]
    let cover: URL?
    let timelineCount: Int
    let unreadable: Int
}
enum DraftLibrary {
    static let documentNames = ["draft_content.json", "draft_info.json", "draft_meta_info.json"]
    static func json(_ url: URL) throws -> Any {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 64 * 1024 * 1024 else { throw ToolboxError("草稿文件过大：\(url.lastPathComponent)") }
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
    static func documents(_ root: URL) -> [URL] {
        var result = documentNames.map { root.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        let timelines = root.appendingPathComponent("Timelines")
        let children = (try? FileManager.default.contentsOfDirectory(at: timelines, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            result += documentNames.map { child.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        }
        return result
    }
    static func inspect(_ folder: URL) throws -> Draft {
        let docs = documents(folder)
        guard !docs.isEmpty else { throw ToolboxError("未找到剪映草稿") }
        var name = folder.lastPathComponent
        var latest = Date.distantPast
        var parts: [String] = []
        var materials = Set<URL>()
        var unreadable = 0
        for doc in docs {
            let date = (try? doc.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            latest = max(latest, date)
            if let data = try? Data(contentsOf: doc) { parts.append(doc.path + digest(data)) }
            guard let object = try? json(doc) else { unreadable += 1; continue }
            if doc.lastPathComponent == "draft_meta_info.json", doc.deletingLastPathComponent() == folder,
               let dict = object as? [String: Any], let title = dict["draft_name"] as? String, !title.isEmpty { name = title }
            materials.formUnion(referencedMedia(object, base: folder))
        }
        let cover = ["draft_cover.jpg","draft_cover.png","draft_cover.jpeg","draft_cover.webp","cover.jpg","cover.png"].map { folder.appendingPathComponent($0) }.first { FileManager.default.fileExists(atPath: $0.path) }
        if let cover = cover, let data = try? Data(contentsOf: cover) { parts.append(digest(data)) }
        for material in materials.sorted(by: { $0.path < $1.path }) {
            let v = try? material.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            parts.append(material.path + ":\(v?.fileSize ?? -1):\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        let count = Set(docs.filter { $0.path.contains("/Timelines/") }.map { $0.deletingLastPathComponent().path }).count
        return Draft(folder: folder, name: name, modified: latest, fingerprint: digest(Data(parts.joined(separator: "|").utf8)), documents: docs, materials: materials.sorted { $0.path < $1.path }, cover: cover, timelineCount: max(1,count), unreadable: unreadable)
    }
    static func scan(_ root: URL) throws -> [Draft] {
        if !documents(root).isEmpty { return [try inspect(root)] }
        var found: [Draft] = []
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey,.isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { throw ToolboxError("无法读取所选文件夹") }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey,.isSymbolicLinkKey])
            if values?.isSymbolicLink == true { walker.skipDescendants(); continue }
            guard values?.isDirectory == true else { continue }
            if !documents(url).isEmpty { if let draft = try? inspect(url) { found.append(draft) }; walker.skipDescendants() }
        }
        return found.sorted { $0.modified > $1.modified }
    }
}
enum MaterialPackager {
    // Copy into a new destination. Never rewrite the user's original draft.
    static func package(_ draft: Draft, to parent: URL, cancelled: () -> Bool = { false }) throws -> URL {
        let fm = FileManager.default
        guard !isInside(parent, draft.folder) else { throw ToolboxError("保存位置不能位于原草稿内部") }
        let fresh = try DraftLibrary.inspect(draft.folder)
        guard fresh.unreadable == 0 else { throw ToolboxError("草稿含加密或无法解析的文件，无法保证素材完整；请在剪映中使用草稿备份功能。") }
        guard !fresh.materials.isEmpty else { throw ToolboxError("未找到可识别的本地素材引用，不能保证素材完整。") }
        for source in fresh.materials { guard fm.fileExists(atPath: source.path) else { throw ToolboxError("素材不存在：\(source.path)") } }
        let output = parent.appendingPathComponent(cleanName(fresh.name))
        guard !fm.fileExists(atPath: output.path) else { throw ToolboxError("已有同名文件夹：\(output.lastPathComponent)，请更换保存位置。") }
        let temporary = parent.appendingPathComponent(".yuandian-" + UUID().uuidString)
        defer { try? fm.removeItem(at: temporary) }
        if let tree = fm.enumerator(at: fresh.folder, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let file as URL in tree {
                if (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { throw ToolboxError("草稿包含符号链接，请先在剪映整理为普通文件后再打包。") }
            }
        }
        try fm.copyItem(at: fresh.folder, to: temporary)
        let media = temporary.appendingPathComponent("YuandianMedia")
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        var replacements: [String:String] = [:]
        var manifest: [[String:String]] = []
        for source in fresh.materials {
            if cancelled() { throw CancellationError() }
            let basename = String(digest(Data(source.path.utf8)).prefix(16)) + "_" + cleanName(source.lastPathComponent)
            let target = media.appendingPathComponent(basename)
            try fm.copyItem(at: source.resolvingSymlinksInPath(), to: target)
            let hash = try fileDigest(source)
            guard hash == (try fileDigest(target)) else { throw ToolboxError("素材校验失败：\(source.lastPathComponent)") }
            let final = output.appendingPathComponent("YuandianMedia").appendingPathComponent(basename)
            replacements[source.path] = final.path
            manifest.append(["original": source.path, "relative": "YuandianMedia/" + basename, "sha256": hash])
        }
        for document in fresh.documents {
            let suffix = String(document.path.dropFirst(fresh.folder.path.count + 1))
            let object = try DraftLibrary.json(document)
            let rewritten = rewriteMedia(object, base: fresh.folder, replacements: replacements)
            try JSONSerialization.data(withJSONObject: rewritten, options: [.prettyPrinted,.sortedKeys]).write(to: temporary.appendingPathComponent(suffix), options: .atomic)
        }
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted,.sortedKeys]).write(to: temporary.appendingPathComponent("元点素材清单.json"))
        guard (try DraftLibrary.inspect(fresh.folder)).fingerprint == fresh.fingerprint else { throw ToolboxError("处理期间草稿发生变化，请保存草稿后重试。") }
        if cancelled() { throw CancellationError() }
        try fm.moveItem(at: temporary, to: output)
        return output
    }
}
enum SizeMode: String, CaseIterable, Identifiable {
    case original = "保持原尺寸", auto720 = "自动 720P", landscape = "720P 横屏", portrait = "720P 竖屏"
    var id: String { rawValue }
    func dimensions(width: Double, height: Double) -> (Int,Int) {
        func even(_ n: Double) -> Int { max(2,Int((n / 2).rounded()) * 2) }
        switch self {
        case .original: return (even(width),even(height))
        case .landscape: return (1280,720)
        case .portrait: return (720,1280)
        case .auto720: return width >= height ? (even(720 * width / height),720) : (720,even(720 * height / width))
        }
    }
}
