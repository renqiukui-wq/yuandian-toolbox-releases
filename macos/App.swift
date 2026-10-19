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
    var completed = false
}
@MainActor final class AppModel: ObservableObject {
    static let shared = AppModel()
    static let version = "0.1.1"
    @Published var section = "草稿库"
    @Published var drafts: [Draft] = []
    @Published var previews: [String:Preview] = [:]
    @Published var selected = Set<String>()
    @Published var root: URL?
    @Published var searching = false
    @Published var automaticRefresh = true
    @Published var query = ""
    @Published var notice = "选择剪映草稿文件夹，查看已保存的草稿与素材预览。"
    @Published var videoNotice = "添加已导出的视频，再选择尺寸和输出文件夹。"
    @Published var report = ""
    @Published var scanProgress = ""
    @Published var downloadProgress = 0.0
    @Published var downloadBytes = ""
    @Published var newVersion = false
    @Published var downloadedFile: URL?
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
    private var downloadTask: Task<Void,Never>?
    private var scanCancellation = CancelFlag()
    private var restored = false
    private var cancellation = CancelFlag()
    var filtered: [Draft] { drafts.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    func chooseFolder(_ message: String) -> URL? {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.message = message; panel.prompt = "选择文件夹"
        panel.directoryURL = root ?? FileManager.default.urls(for:.moviesDirectory,in:.userDomainMask).first
        return panel.runModal() == .OK ? panel.url : nil
    }
    func selectRoot() {
        if let folder = chooseFolder("选择剪映草稿库，或单个草稿所在文件夹") {
            root = folder; UserDefaults.standard.set(folder.path, forKey: "draftRoot"); selected.removeAll(); refresh()
        }
    }
    func restore() {
        guard !restored else { return }; restored=true
        if let path = UserDefaults.standard.string(forKey:"draftRoot"), FileManager.default.fileExists(atPath:path) { root=URL(fileURLWithPath:path); refresh() }
        if let path = UserDefaults.standard.string(forKey:"videoOutput"), FileManager.default.fileExists(atPath:path) { output=URL(fileURLWithPath:path) }
        checkUpdates()
    }
    func chooseOutput() {
        if let folder=chooseFolder("选择最终视频保存位置") { output=folder; UserDefaults.standard.set(folder.path,forKey:"videoOutput") }
    }
    func stopScan() { automaticRefresh=false; scanCancellation.cancel(); scanProgress="正在停止扫描…" }
    func refresh(force:Bool=false) {
        guard !searching, !busy, let root=root else { return }
        searching=true; scanCancellation=CancelFlag(); let flag=scanCancellation
        let previous=cache; scanProgress="正在读取草稿列表…"
        Task {
            defer { searching=false; scanProgress="" }
            do {
                let items=try await Task.detached(priority:.utility) { try DraftLibrary.scan(root,cancelled:flag.isCancelled) }.value
                if flag.isCancelled() { throw CancellationError() }
                drafts=items; selected.formIntersection(Set(items.map{$0.id}))
                cache=previous.filter { key,_ in items.contains(where:{$0.id == key}) }
                previews=cache.mapValues{$0.1}
                notice=items.isEmpty ? "此文件夹没有可识别的剪映草稿，请选择草稿库或单个草稿目录。" : "共 \(items.count) 个草稿 · 每 15 秒检查已保存变化"
                for (index,draft) in items.enumerated() {
                    if flag.isCancelled() { throw CancellationError() }
                    scanProgress="正在读取预览 \(index+1)/\(items.count)：\(draft.name)"
                    // Retry failures; a temporarily locked image must not remain blank forever.
                    if !force, let saved=previous[draft.id], saved.0 == draft.fingerprint, saved.1.image != nil { continue }
                    let preview=await Task.detached(priority:.utility) { PreviewService.make(draft) }.value
                    if flag.isCancelled() { throw CancellationError() }
                    cache[draft.id]=(draft.fingerprint,preview); previews[draft.id]=preview
                }
            } catch is CancellationError { notice="扫描已停止，已读取的草稿和预览保留。" }
            catch { notice="读取失败："+error.localizedDescription }
        }
    }
    func cancel() { cancellation.cancel(); task?.cancel(); jobText = "正在取消，清理本次临时文件…" }
    func packageDrafts() {
        guard !busy, !selected.isEmpty, let destination = chooseFolder("选择草稿副本保存位置；原草稿保持不变") else { return }
        let items = drafts.filter { selected.contains($0.id) }
        var names=Set<String>()
        for draft in items {
            let name=cleanName(draft.name)
            if !names.insert(name.lowercased()).inserted || FileManager.default.fileExists(atPath:destination.appendingPathComponent(name).path) {
                notice="无法开始：所选草稿或目标目录存在同名文件夹 \(name)。请分别打包或更换目标目录。"; return
            }
        }
        report=""
        busy = true; progress = 0; cancellation = CancelFlag(); let flag = cancellation
        task = Task {
            var successes = 0; var failures: [String] = []
            for (i,draft) in items.enumerated() {
                if flag.isCancelled() { break }
                jobText = "正在复制 \(i+1)/\(items.count)：\(draft.name)"
                do { _ = try await Task.detached(priority:.utility) { try MaterialPackager.package(draft,to:destination,cancelled:flag.isCancelled) { file,portion in
                    Task { @MainActor in
                        guard self.busy else { return }
                        self.progress=(Double(i)+portion)/Double(items.count)
                        self.jobText="\(i+1)/\(items.count) · \(draft.name) · \(file)"
                    }
                } }.value; successes += 1 }
                catch is CancellationError { break }
                catch { failures.append(draft.name + "：" + error.localizedDescription) }
                progress = Double(i+1) / Double(items.count)
            }
            busy = false
            report=failures.joined(separator:"\n")
            notice = "\(flag.isCancelled() ? "已取消" : "素材打包完成")：成功 \(successes)，失败 \(failures.count)。" + failures.prefix(3).joined(separator:"\n")
            jobText = notice
            if successes > 0 && !flag.isCancelled() { NSWorkspace.shared.open(destination) }
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
        guard !busy, let destination=output else { return }
        let pending=videos.indices.filter { !videos[$0].completed }
        guard !pending.isEmpty else { videoNotice="所有视频已完成；如需用其他设置再次处理，请清空列表后重新添加。"; return }
        let mode=sizeMode; let cover=coverMode
        var names=Set<String>()
        for index in pending {
            let name=cleanName(videos[index].url.deletingPathExtension().lastPathComponent)+".mp4"
            if !names.insert(name.lowercased()).inserted || FileManager.default.fileExists(atPath:destination.appendingPathComponent(name).path) {
                videoNotice="无法开始：待处理队列或输出目录已有同名视频 \(name)。请移除重复项或更换输出目录。"; return
            }
        }
        busy=true; cancellation=CancelFlag(); progress=0; report=""
        task=Task {
            var successes=0; var failures:[String]=[]
            for (position,index) in pending.enumerated() {
                if Task.isCancelled { break }
                let input=videos[index].url
                videos[index].state="正在处理"; jobText="\(position+1)/\(pending.count) · \(input.lastPathComponent)"
                do {
                    _ = try await VideoProcessor.convert(input:input,parent:destination,mode:mode,cover:cover) { value in
                        Task { @MainActor in guard self.busy else { return }; self.progress=(Double(position)+value)/Double(pending.count) }
                    }
                    videos[index].state="已完成"; videos[index].completed=true; successes += 1
                } catch is CancellationError { videos[index].state="已取消，可重试"; break }
                catch { videos[index].state="失败："+error.localizedDescription; failures.append(input.lastPathComponent+"："+error.localizedDescription) }
            }
            busy=false; report=failures.joined(separator:"\n")
            videoNotice="\(Task.isCancelled ? "已取消" : "处理完成")：成功 \(successes)，失败 \(failures.count)。再次开始仅处理未完成项。"
            jobText=videoNotice
            if successes > 0 && !Task.isCancelled { NSWorkspace.shared.open(destination) }
        }
    }
    func checkUpdates() {
        guard !checking, !downloading else { return }; checking = true; updateText = "正在查询 Mac 版本…"
        Task {
            defer { checking = false }
            do {
                var request = URLRequest(url:URL(string:"https://api.github.com/repos/renqiukui-wq/yuandian-toolbox-releases/releases?per_page=100")!)
                request.setValue("Yuandian-Mac/" + Self.version,forHTTPHeaderField:"User-Agent"); request.timeoutInterval = 20
                let (data,response) = try await URLSession.shared.data(for:request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ToolboxError("暂时无法检查更新，请稍后重试或前往网站") }
                let releases = try JSONDecoder().decode([MacRelease].self,from:data)
                release = MacUpdates.latest(releases)
                if let release = release {
                    let remote = String(release.tag_name.dropFirst("macos-v".count))
                    let newer = remote.compare(Self.version,options:.numeric) == .orderedDescending
                    newVersion=newer
                    updateText = newer ? "发现新版本 \(remote)" : "当前版本 \(Self.version) · 已是最新 Mac 版"
                } else { updateText = "Mac 安装包尚未发布，可前往项目网站查看进度。" }
            } catch { updateText = error.localizedDescription }
        }
    }
    func cancelDownload() { downloadTask?.cancel() }
    func showDownload() { if let file=downloadedFile { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
    func downloadUpdate() {
        guard !downloading, !checking, let release=release, let asset=release.assets.first(where:{$0.name == MacUpdates.assetName}) else { return }
        guard MacUpdates.validDownload(asset.browser_download_url) else { updateText="下载地址校验失败"; return }
        let panel=NSSavePanel(); panel.nameFieldStringValue=asset.name; panel.allowedContentTypes=[.zip]
        guard panel.runModal() == .OK, let target=panel.url else { return }
        downloading=true; downloadProgress=0; downloadBytes="连接服务器…"; downloadedFile=nil
        updateText="正在下载 Mac 安装包，可取消或改用网站下载。"
        downloadTask=Task {
            defer { downloading=false }
            let configuration=URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest=60; configuration.timeoutIntervalForResource=900
            let session=URLSession(configuration:configuration); defer { session.invalidateAndCancel() }
            do {
                var request=URLRequest(url:asset.browser_download_url)
                request.setValue("Yuandian-Mac/"+Self.version,forHTTPHeaderField:"User-Agent")
                let delegate=DownloadProgress { received,total in
                    Task { @MainActor in
                        guard self.downloading else { return }
                        self.downloadProgress=total > 0 ? Double(received)/Double(total) : 0
                        self.downloadBytes=ByteCountFormatter.string(fromByteCount:received,countStyle:.file)+(total > 0 ? " / "+ByteCountFormatter.string(fromByteCount:total,countStyle:.file) : "")
                    }
                }
                let (temporary,response)=try await session.download(for:request,delegate:delegate)
                defer { try? FileManager.default.removeItem(at:temporary) }
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ToolboxError("下载失败，请重试或前往网站。") }
                updateText="下载完成，正在校验文件…"
                try await Task.detached { try MacUpdates.verify(temporary,expected:asset.digest) }.value
                try Task.checkCancellation()
                let data=try Data(contentsOf:temporary,options:.mappedIfSafe)
                try data.write(to:target,options:.atomic)
                downloadedFile=target; downloadProgress=1
                updateText="下载并校验成功。解压后将应用拖入“应用程序”替换旧版。"
                showDownload()
            } catch {
                updateText=Task.isCancelled || (error as? URLError)?.code == .cancelled ? "下载已取消，可重新下载；目标文件未被替换。" : "下载失败："+error.localizedDescription
            }
        }
    }
    func website() { NSWorkspace.shared.open(release?.html_url ?? URL(string:"https://github.com/renqiukui-wq/yuandian-toolbox-releases/releases")!) }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppModel.shared.busy || AppModel.shared.downloading {
            let alert = NSAlert(); alert.messageText = "任务仍在进行"; alert.informativeText = "请先等待任务完成，或取消处理后再退出。"; alert.runModal(); return .terminateCancel
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
                .onAppear {
                    if let index = CommandLine.arguments.firstIndex(of:"--ui-smoke"), CommandLine.arguments.count > index+1 {
                        UISmoke.run(model:model,folder:URL(fileURLWithPath:CommandLine.arguments[index+1]))
                    } else { model.restore() }
                }
        }.defaultSize(width:1180,height:800)
    }
}

@MainActor enum UISmoke {
    static var started = false
    static func run(model:AppModel,folder:URL) {
        guard !started else { return }; started=true
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        model.automaticRefresh=false
        let samples=folder.appendingPathComponent("fixtures")
        do {
            try FileManager.default.createDirectory(at:samples,withIntermediateDirectories:true)
            for (index,name) in ["横屏草稿 · 验证样例","竖屏草稿与中文长名称排版验证","缺少封面 · 验证提示"].enumerated() {
                let draft=samples.appendingPathComponent(name)
                try FileManager.default.createDirectory(at:draft,withIntermediateDirectories:true)
                try Data("{\"materials\":{}}".utf8).write(to:draft.appendingPathComponent("draft_content.json"))
                if index < 2 {
                    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:index == 0 ? 320 : 180,pixelsHigh:index == 0 ? 180 : 320,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
                    let context=NSGraphicsContext(bitmapImageRep:bitmap)!
                    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
                    NSColor(calibratedRed:0.06,green:index == 0 ? 0.55 : 0.35,blue:0.65,alpha:1).setFill()
                    NSBezierPath(rect:NSRect(x:0,y:0,width:bitmap.pixelsWide,height:bitmap.pixelsHigh)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                    try bitmap.representation(using:.png,properties:[:])!.write(to:draft.appendingPathComponent("draft_cover.png"))
                }
            }
            model.drafts=try DraftLibrary.scan(samples)
            for draft in model.drafts { model.previews[draft.id]=PreviewService.make(draft) }
            model.selected=Set(model.drafts.prefix(1).map{$0.id})
            model.notice="界面验证样例：横竖封面、长名称与缺图提示。"
            model.videos=[VideoItem(url:URL(fileURLWithPath:"/tmp/横屏视频.mp4")),VideoItem(url:URL(fileURLWithPath:"/tmp/竖屏视频.mp4"),state:"已完成",completed:true)]
            model.videoNotice="已完成项保留状态，再次开始仅处理未完成项。"
        } catch { print("UI fixture failed: \(error)"); exit(5) }
        let cases = [("草稿库","浅色","drafts-light"),("视频处理","浅色","video-light"),("检查更新","浅色","update-light"),("草稿库","深色","drafts-dark"),("视频处理","深色","video-dark"),("检查更新","深色","update-dark")]
        func capture(_ index:Int) {
            if index == cases.count { print("PASS: native windows rendered in light and dark modes"); NSApplication.shared.terminate(nil); return }
            let item=cases[index]; model.section=item.0; UserDefaults.standard.set(item.1,forKey:"appearance")
            DispatchQueue.main.asyncAfter(deadline:.now()+3) {
                guard let view=NSApplication.shared.windows.first(where:{$0.isVisible && $0.contentView != nil})?.contentView,
                      let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else { print("UI render failed"); exit(2) }
                view.cacheDisplay(in:view.bounds,to:bitmap)
                guard let bytes=bitmap.representation(using:.png,properties:[:]) else { exit(3) }
                do { try bytes.write(to:folder.appendingPathComponent(item.2+".png")) } catch { exit(4) }
                capture(index+1)
            }
        }
        capture(0)
    }
}
