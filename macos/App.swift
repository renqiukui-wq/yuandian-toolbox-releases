import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    func isCancelled() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
struct VideoItem: Identifiable {
    let url: URL
    var id: String { url.path }
    var state = "等待处理"
}
struct MacRelease: Decodable {
    struct Asset: Decodable { let name: String; let browser_download_url: URL; let digest: String? }
    let tag_name: String; let html_url: URL; let body: String?; let draft: Bool; let assets: [Asset]
}
@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let version = "0.1.0"
    @Published var section = "草稿库"
    @Published var drafts: [Draft] = []
    @Published var previews: [String:Preview] = [:]
    @Published var selected = Set<String>()
    @Published var root: URL?
    @Published var searching = false
    @Published var query = ""
    @Published var notice = "选择剪映草稿文件夹，查看已保存的草稿与素材预览。"
    @Published var busy = false
    @Published var progress = 0.0
    @Published var jobText = ""
    @Published var videos: [VideoItem] = []
    @Published var sizeMode: SizeMode = .auto720
    @Published var coverMode: CoverMode = .first
    @Published var output: URL?
    @Published var release: MacRelease?
    @Published var updateText = "Mac 独立更新通道，不会下载 Windows EXE。"
    @Published var checking = false
    @Published var downloading = false
    private var cache: [String:(String,Preview)] = [:]
    private var task: Task<Void,Never>?
    private var cancellation = CancelFlag()
    var filtered: [Draft] { drafts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    func chooseFolder(_ message: String) -> URL? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.message = message; panel.prompt = "选择文件夹"
        return panel.runModal() == .OK ? panel.url : nil
    }
    func selectRoot() {
        if let folder = chooseFolder("选择剪映草稿库，或单个草稿所在文件夹") {
            root = folder; UserDefaults.standard.set(folder.path, forKey: "draftRoot"); selected.removeAll(); refresh()
        }
    }
    func restore() {
        if let path = UserDefaults.standard.string(forKey: "draftRoot"), FileManager.default.fileExists(atPath:path) { root = URL(fileURLWithPath:path); refresh() }
    }
    func refresh() {
        guard !searching, !busy, let root = root else { return }
        searching = true
        let previous = cache
        Task {
            do {
                let result = try await Task.detached(priority: .utility) { () -> ([Draft],[String:(String,Preview)]) in
                    let items = try DraftLibrary.scan(root)
                    var next: [String:(String,Preview)] = [:]
                    for draft in items {
                        let preview = previous[draft.id]?.0 == draft.fingerprint ? previous[draft.id]!.1 : PreviewService.make(draft)
                        next[draft.id] = (draft.fingerprint,preview)
                    }
                    return (items,next)
                }.value
                drafts = result.0; cache = result.1; previews = cache.mapValues { $0.1 }
                selected.formIntersection(Set(drafts.map { $0.id }))
                notice = drafts.isEmpty ? "此文件夹没有可识别的剪映草稿。请选择实际草稿库或单个草稿目录。" : "共 \(drafts.count) 个草稿 · 每 15 秒检查已保存内容与封面变化"
            } catch { notice = "读取失败：" + error.localizedDescription }
            searching = false
        }
    }
    func cancel() { cancellation.cancel(); task?.cancel(); jobText = "正在取消，清理本次临时文件…" }
    func packageDrafts() {
        guard !busy, !selected.isEmpty, let destination = chooseFolder("选择草稿副本保存位置；原草稿保持不变") else { return }
        let items = drafts.filter { selected.contains($0.id) }
        busy = true; progress = 0; cancellation = CancelFlag(); let flag = cancellation
        task = Task {
            var successes = 0; var failures: [String] = []
            for (i,draft) in items.enumerated() {
                if flag.isCancelled() { break }
                jobText = "正在复制 \(i+1)/\(items.count)：\(draft.name)"
                do { _ = try await Task.detached(priority:.utility) { try MaterialPackager.package(draft, to:destination, cancelled:flag.isCancelled) }.value; successes += 1 }
                catch is CancellationError { break }
                catch { failures.append(draft.name + "：" + error.localizedDescription) }
                progress = Double(i+1) / Double(items.count)
            }
            busy = false
            notice = "\(flag.isCancelled() ? "已取消" : "素材打包完成")：成功 \(successes)，失败 \(failures.count)。" + failures.prefix(3).joined(separator:"\n")
            jobText = notice
            if successes > 0 { NSWorkspace.shared.open(destination) }
        }
    }
    func addVideos() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie]; panel.message = "选择已从剪映导出的视频（MP4 / MOV）"
        guard panel.runModal() == .OK else { return }
        let existing = Set(videos.map { $0.id })
        videos += panel.urls.filter { !existing.contains($0.path) }.map { VideoItem(url:$0) }
    }
    func processVideos() {
        guard !busy, !videos.isEmpty, let destination = output else { return }
        let inputs = videos.map { $0.url }; let mode = sizeMode; let cover = coverMode
        var names = Set<String>()
        for input in inputs {
            let name = cleanName(input.deletingPathExtension().lastPathComponent) + ".mp4"
            if !names.insert(name.lowercased()).inserted || FileManager.default.fileExists(atPath:destination.appendingPathComponent(name).path) {
                notice = "导出取消：同名文件 \(name)。请更换输出文件夹，或调整输入文件名。"; return
            }
        }
        busy = true; cancellation = CancelFlag(); progress = 0
        task = Task {
            var successes = 0; var failures = 0
            for (index,input) in inputs.enumerated() {
                if Task.isCancelled { break }
                videos[index].state = "正在处理"
                jobText = "\(index+1)/\(inputs.count) · \(input.lastPathComponent)"
                do {
                    _ = try await VideoProcessor.convert(input:input,parent:destination,mode:mode,cover:cover) { value in
                        Task { @MainActor in self.progress = (Double(index)+value)/Double(inputs.count) }
                    }
                    videos[index].state = "已完成"; successes += 1
                } catch is CancellationError { videos[index].state = "已取消"; break }
                catch { videos[index].state = error.localizedDescription; failures += 1 }
            }
            busy = false
            notice = "\(Task.isCancelled ? "已取消" : "处理完成")：成功 \(successes)，失败 \(failures)。原视频未改动。"
            jobText = notice
            if successes > 0 { NSWorkspace.shared.open(destination) }
        }
    }
    func checkUpdates() {
        guard !checking else { return }; checking = true; updateText = "正在查询 Mac 版本…"
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url:URL(string:"https://api.github.com/repos/renqiukui-wq/yuandian-toolbox-releases/releases?per_page=100")!)
                request.setValue("Yuandian-Mac/" + Self.version,forHTTPHeaderField:"User-Agent"); request.timeoutInterval = 20
                let (data,response) = try await URLSession.shared.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ToolboxError("暂时无法检查更新，请稍后重试或前往网站") }
                let releases = try JSONDecoder().decode([MacRelease].self,from:data)
                release = releases.first { !$0.draft && $0.tag_name.hasPrefix("macos-v") && $0.assets.contains { $0.name == "YuandianToolbox-macOS-universal.zip" } }
                if let release = release {
                    let remote = String(release.tag_name.dropFirst("macos-v".count))
                    let newer = remote.compare(Self.version,options:.numeric) == .orderedDescending
                    updateText = newer ? "发现新版本 \(remote)" : "当前版本 \(Self.version) · 已是最新 Mac 版"
                } else { updateText = "Mac 安装包尚未发布，可前往项目网站查看进度。" }
            } catch { updateText = error.localizedDescription }
        }
    }
    func downloadUpdate() {
        guard !downloading, let release = release, let asset = release.assets.first(where:{$0.name == "YuandianToolbox-macOS-universal.zip"}) else { return }
        guard asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com", asset.browser_download_url.path.hasPrefix("/renqiukui-wq/yuandian-toolbox-releases/releases/download/") else { updateText = "下载地址校验失败"; return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = asset.name
        guard panel.runModal() == .OK, let target = panel.url else { return }
        downloading = true; updateText = "正在下载 Mac 安装包…下载慢可前往网站下载。"
        Task {
            defer { downloading = false }
            do {
                let (temporary,response) = try await URLSession.shared.download(from:asset.browser_download_url)
                defer { try? FileManager.default.removeItem(at:temporary) }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ToolboxError("下载失败，请重试") }
                guard let hash = asset.digest, hash.hasPrefix("sha256:") else { throw ToolboxError("此附件缺少 SHA-256 校验信息，请前往网站下载") }
                let actual = try await Task.detached { try fileDigest(temporary) }.value
                guard actual == String(hash.dropFirst(7)).lowercased() else { throw ToolboxError("安装包校验失败，请重新下载") }
                // NSSavePanel already obtained explicit overwrite intent for this exact path.
                let data = try Data(contentsOf:temporary)
                try data.write(to:target,options:.atomic)
                updateText = "下载并校验成功。解压后将应用拖入“应用程序”替换旧版。"
                NSWorkspace.shared.activateFileViewerSelecting([target])
            } catch { updateText = error.localizedDescription }
        }
    }
    func website() { NSWorkspace.shared.open(release?.html_url ?? URL(string:"https://github.com/renqiukui-wq/yuandian-toolbox-releases/releases")!) }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppModel.shared.busy || AppModel.shared.downloading {
            let alert = NSAlert(); alert.messageText = "任务仍在进行"; alert.informativeText = "请先等待任务完成，或取消处理后再退出。"; alert.runModal(); return .cancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
@main struct YuandianApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel.shared
    @AppStorage("appearance") private var appearance = "跟随系统"
    var body: some Scene {
        WindowGroup("元点剪辑批量工具箱") {
            MainView().environmentObject(model)
                .preferredColorScheme(appearance == "深色" ? .dark : appearance == "浅色" ? .light : nil)
                .frame(minWidth:980,minHeight:660)
                .onAppear { model.restore() }
        }.defaultSize(width:1180,height:800)
    }
}
