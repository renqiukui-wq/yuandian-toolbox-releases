import SwiftUI
import AppKit

private let accent = Color(red:0.05,green:0.62,blue:0.55)
struct Surface<Content:View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { content.padding(22).frame(maxWidth:.infinity,alignment:.leading).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(Color.primary.opacity(0.07))) }
}
struct MainView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("appearance") private var appearance = "跟随系统"
    @State private var zoomed: String?
    private let clock = Timer.publish(every:15,on:.main,in:.common).autoconnect()
    var body: some View {
        NavigationSplitView {
            VStack(alignment:.leading,spacing:26) {
                HStack(spacing:10) {
                    Image(systemName:"square.stack.3d.up.fill").font(.title).foregroundStyle(accent)
                    VStack(alignment:.leading,spacing:3) { Text("元点").font(.title2.bold()); Text("剪辑批量工具箱").foregroundStyle(.secondary).font(.caption) }
                }.padding(.top,20)
                VStack(spacing:8) {
                    nav("草稿库","square.grid.2x2")
                    nav("视频处理","film.stack")
                    nav("检查更新","arrow.down.circle")
                }
                Spacer()
                Picker("外观",selection:$appearance) { Text("跟随系统").tag("跟随系统"); Text("浅色").tag("浅色"); Text("深色").tag("深色") }.labelsHidden()
                Text("macOS · \(AppModel.version)\nApple 芯片与 Intel 通用").font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }.padding(20).navigationSplitViewColumnWidth(210)
        } detail: {
            VStack(spacing:0) {
                HStack {
                    VStack(alignment:.leading,spacing:7) {
                        Text(model.section).font(.system(size:28,weight:.bold))
                        Text(subtitle).foregroundStyle(.secondary).font(.callout)
                    }
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }.padding(28)
                ScrollView {
                    VStack(spacing:20) {
                        if model.section == "草稿库" { draftsPage }
                        else if model.section == "视频处理" { videosPage }
                        else { updatesPage }
                    }.padding(.horizontal,28).padding(.bottom,28)
                }
                if model.busy {
                    VStack(alignment:.leading,spacing:8) {
                        HStack { Text(model.jobText).lineLimit(1); Spacer(); Button("取消任务") { model.cancel() } }
                        ProgressView(value:model.progress)
                    }.padding(18).background(.bar)
                }
            }.background(Color(nsColor:.windowBackgroundColor))
        }.tint(accent)
        .onReceive(clock) { _ in if model.section == "草稿库" { model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for:NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .sheet(isPresented:Binding(get:{zoomed != nil},set:{if !$0 {zoomed=nil}})) {
            VStack(spacing:18) {
                if let id = zoomed, let image = model.previews[id]?.image {
                    Image(nsImage:image).resizable().scaledToFit().frame(maxWidth:900,maxHeight:620)
                    Text(model.previews[id]?.note ?? "").foregroundStyle(.secondary)
                }
                Button("关闭") { zoomed=nil }.keyboardShortcut(.cancelAction)
            }.padding(24).frame(minWidth:500,minHeight:300)
        }
    }
    private var subtitle: String {
        if model.section == "草稿库" { return "看见每一个草稿，让素材整理更轻松。" }
        if model.section == "视频处理" { return "批量处理已导出的视频，横竖画面各得其所。" }
        return "独立的 Mac 版本与下载入口。"
    }
    private func nav(_ title:String,_ icon:String) -> some View {
        Button { model.section=title } label: { Label(title,systemImage:icon).font(.body.weight(.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(12).background(model.section == title ? accent.opacity(0.15) : .clear).clipShape(RoundedRectangle(cornerRadius:10)) }.buttonStyle(.plain)
    }
    private var draftsPage: some View {
        VStack(spacing:20) {
            Surface {
                HStack {
                    Label("草稿位置",systemImage:"folder").font(.headline)
                    Spacer()
                    Button("选择文件夹") { model.selectRoot() }.buttonStyle(.borderedProminent).disabled(model.busy || model.searching)
                    Button { model.refresh() } label: { Image(systemName:"arrow.clockwise") }.help("刷新草稿与封面").disabled(model.root == nil || model.searching || model.busy)
                }
                if let root = model.root { Text(root.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top,6) }
                Text(model.notice).font(.callout).foregroundStyle(.secondary).padding(.top,12).textSelection(.enabled)
                if model.searching { ProgressView("正在检查草稿与预览…").padding(.top,8) }
            }
            HStack {
                TextField("搜索草稿名称",text:$model.query).textFieldStyle(.roundedBorder).frame(maxWidth:320)
                Spacer()
                Text("已选 \(model.selected.count)").foregroundStyle(.secondary)
                Button("全选可见") { model.selected.formUnion(model.filtered.map{$0.id}) }.disabled(model.busy)
                Button("取消选择") { model.selected.removeAll() }.disabled(model.busy)
            }
            if model.drafts.isEmpty && !model.searching {
                Surface { VStack(spacing:16) { Image(systemName:"rectangle.stack").font(.system(size:44)).foregroundStyle(accent); Text("从选择草稿文件夹开始").font(.title3.bold()); Text("在剪映设置中查看草稿保存位置，然后在这里选择该文件夹。\n支持一次浏览多个草稿；加密草稿优先显示剪映保存的封面。").multilineTextAlignment(.center).foregroundStyle(.secondary) }.frame(maxWidth:.infinity).padding(.vertical,40) }
            } else {
                LazyVGrid(columns:[GridItem(.adaptive(minimum:200,maximum:290),spacing:16)],spacing:16) {
                    ForEach(model.filtered) { draft in
                        VStack(alignment:.leading,spacing:10) {
                            ZStack {
                                Rectangle().fill(Color.primary.opacity(0.04))
                                if let image = model.previews[draft.id]?.image { Image(nsImage:image).resizable().scaledToFit() }
                                else { Image(systemName:"photo").font(.largeTitle).foregroundStyle(.tertiary) }
                            }.frame(height:130).clipped().clipShape(RoundedRectangle(cornerRadius:10))
                            HStack(alignment:.top) {
                                Toggle("",isOn:Binding(get:{model.selected.contains(draft.id)},set:{if $0 { model.selected.insert(draft.id) } else { model.selected.remove(draft.id) }})).labelsHidden().toggleStyle(.checkbox).disabled(model.busy)
                                Text(draft.name).font(.headline).lineLimit(2).help(draft.name)
                                Spacer(minLength:0)
                            }
                            Text(model.previews[draft.id]?.note ?? "正在读取").font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height:30,alignment:.top)
                            HStack {
                                Text("\(draft.timelineCount) 条时间线").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { zoomed=draft.id } label: { Image(systemName:"arrow.up.left.and.arrow.down.right") }.help("放大预览").disabled(model.previews[draft.id]?.image == nil)
                                Button { NSWorkspace.shared.activateFileViewerSelecting([draft.folder]) } label: { Image(systemName:"folder") }.help("在 Finder 查看")
                            }.buttonStyle(.borderless)
                        }.padding(14).background(Color(nsColor:.controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).stroke(model.selected.contains(draft.id) ? accent : Color.primary.opacity(0.08),lineWidth:model.selected.contains(draft.id) ? 2 : 1))
                    }
                }
            }
            Surface {
                HStack {
                    VStack(alignment:.leading,spacing:6) {
                        Text("打包草稿与素材").font(.headline)
                        Text("复制到新文件夹并校验素材，保留原草稿。加密内容或缺失素材会明确报错。").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("打包所选草稿") { model.packageDrafts() }.buttonStyle(.borderedProminent).disabled(model.busy || model.selected.isEmpty || model.searching)
                }
                Text("预览会跟随已保存文件刷新；未保存的编辑无法读取。素材画面仅用于识别草稿。打包后的路径针对当前 Mac，跨电脑迁移需要在剪映重新定位素材。").font(.caption).foregroundStyle(.secondary).padding(.top,12)
            }
        }
    }
    private var videosPage: some View {
        VStack(spacing:20) {
            Surface {
                Text("输出尺寸").font(.headline)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(SizeMode.allCases) { mode in
                        Button { model.sizeMode=mode } label: {
                            HStack { Image(systemName:mode == .portrait ? "rectangle.portrait" : "rectangle"); VStack(alignment:.leading,spacing:4) { Text(mode.rawValue).fontWeight(.semibold); Text(mode == .landscape ? "1280 × 720 · 等比适配" : mode == .portrait ? "720 × 1280 · 等比适配" : mode == .auto720 ? "按每条视频比例，短边 720" : "沿用每条视频的画面尺寸").font(.caption).foregroundStyle(.secondary) }; Spacer(); if model.sizeMode == mode { Image(systemName:"checkmark.circle.fill").foregroundStyle(accent) } }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(model.sizeMode == mode ? accent.opacity(0.12) : Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius:10))
                        }.buttonStyle(.plain).disabled(model.busy)
                    }
                }.padding(.top,10)
                Divider().padding(.vertical,12)
                Picker("视频封面",selection:$model.coverMode) { ForEach(CoverMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).disabled(model.busy)
                Text("随机封面会替换视频第一帧，音频与视频时长保持；其他播放软件的缩略图策略可能不同。固定横竖屏按比例缩放并补黑边。").font(.caption).foregroundStyle(.secondary).padding(.top,8)
            }
            Surface {
                HStack { Text("待处理视频 · \(model.videos.count)").font(.headline); Spacer(); Button("清空") { model.videos.removeAll() }.disabled(model.busy); Button("添加视频") { model.addVideos() }.buttonStyle(.borderedProminent).disabled(model.busy) }
                if model.videos.isEmpty { Text("先在剪映导出视频，再添加到这里批量处理。").foregroundStyle(.secondary).padding(.vertical,28) }
                ForEach(model.videos) { video in
                    HStack { Image(systemName:"film").foregroundStyle(accent); Text(video.url.lastPathComponent).lineLimit(1).help(video.url.path); Spacer(); Text(video.state).font(.caption).foregroundStyle(.secondary).lineLimit(3).frame(maxWidth:300,alignment:.trailing) }.padding(.vertical,8)
                    Divider()
                }
                HStack { Button("选择输出文件夹") { model.output=model.chooseFolder("选择最终视频保存位置") }.disabled(model.busy); Text(model.output?.path ?? "尚未选择").font(.caption).foregroundStyle(.secondary).lineLimit(2); Spacer(); Button("开始批量处理") { model.processVideos() }.buttonStyle(.borderedProminent).disabled(model.busy || model.videos.isEmpty || model.output == nil) }.padding(.top,16)
                Text(model.notice).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(.top,10)
            }
            Text("Mac 首版提供视频后处理，不调用 Windows 剪映导出引擎。复杂草稿时间线请在 Mac 剪映中导出。输出目录只保留最终 MP4，不生成原版备份；输入视频保留。").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private var updatesPage: some View {
        Surface {
            HStack { Image(systemName:"arrow.down.circle.fill").font(.system(size:42)).foregroundStyle(accent); VStack(alignment:.leading,spacing:6) { Text("元点剪辑批量工具箱 · Mac").font(.title2.bold()); Text("当前版本 \(AppModel.version) · macOS 13 或更新版本").foregroundStyle(.secondary) } }
            Text(model.updateText).padding(.vertical,20).textSelection(.enabled)
            if model.checking || model.downloading { ProgressView().controlSize(.small) }
            HStack { Button("检查更新") { model.checkUpdates() }.disabled(model.checking); Button("下载 Mac 安装包") { model.downloadUpdate() }.buttonStyle(.borderedProminent).disabled(model.release == nil || model.downloading); Button("下载慢？去网站下载") { model.website() } }
            if let release = model.release { Divider().padding(.vertical,16); Text(release.tag_name).font(.headline); Text(release.body ?? "").font(.callout).textSelection(.enabled) }
            Text("下载完成后会校验安装包并在 Finder 中显示。解压后拖入“应用程序”完成安装；当前 Mac 首版不自动替换正在运行的应用。").font(.caption).foregroundStyle(.secondary).padding(.top,20)
        }
    }
}
