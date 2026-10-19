import Foundation
import AppKit
@preconcurrency import AVFoundation
import QuartzCore
@preconcurrency import CoreImage
import ImageIO

struct Preview {
    let image: NSImage?
    let note: String
}
enum PreviewService {
    static func thumbnail(_ url:URL) -> NSImage? {
        guard let source=CGImageSourceCreateWithURL(url as CFURL,nil),
              let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:960,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary) else { return nil }
        return NSImage(cgImage:image,size:.zero)
    }
    static func make(_ draft: Draft) -> Preview {
        if let cover = draft.cover, let image = thumbnail(cover) {
            let saved = (try? cover.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let note = saved < draft.modified.addingTimeInterval(-2) ? "封面早于草稿修改，请在剪映保存新封面" : "剪映已保存封面"
            return Preview(image: image, note: note)
        }
        for file in draft.materials where FileManager.default.fileExists(atPath: file.path) {
            if ["png","jpg","jpeg","heic","webp","bmp"].contains(file.pathExtension.lowercased()), let image = thumbnail(file) {
                return Preview(image: image, note: "素材画面 · 非完整时间线预览")
            }
            guard ["mp4","mov","m4v","mkv","avi","webm"].contains(file.pathExtension.lowercased()) else { continue }
            let asset = AVURLAsset(url: file)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 480)
            if let cg = try? generator.copyCGImage(at: .zero, actualTime: nil) { return Preview(image: NSImage(cgImage: cg, size: .zero), note: "素材画面 · 非完整时间线预览") }
        }
        return Preview(image: nil, note: draft.unreadable > 0 ? "加密草稿无可读封面，请在剪映保存封面" : "暂无封面或素材已移动")
    }
}
enum CoverMode: String, CaseIterable, Identifiable {
    case first = "默认第一帧", random = "随机画面帧"
    var id: String { rawValue }
}
enum VideoProcessor {
    static func convert(input: URL, parent: URL, mode: SizeMode, cover: CoverMode, progress: @escaping (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let fm = FileManager.default
        guard fm.isWritableFile(atPath:parent.path) else { throw ToolboxError("没有权限写入输出文件夹，请重新选择。") }
        let output = parent.appendingPathComponent(cleanName(input.deletingPathExtension().lastPathComponent)).appendingPathExtension("mp4")
        guard input.standardizedFileURL != output.standardizedFileURL, !fm.fileExists(atPath: output.path) else { throw ToolboxError("目标已有同名视频：\(output.lastPathComponent)。请选择空文件夹或修改名称。") }
        let temporary = parent.appendingPathComponent(".yuandian-" + UUID().uuidString).appendingPathExtension("mp4")
        defer { try? fm.removeItem(at: temporary) }
        let asset = AVURLAsset(url: input)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else { throw ToolboxError("视频没有可读取的画面轨道") }
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0 else { throw ToolboxError("无法读取视频时长") }
        let natural = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let frameRate = try await track.load(.nominalFrameRate)
        let bounds = CGRect(origin: .zero, size: natural).applying(transform)
        let (width,height) = mode.dimensions(width: abs(bounds.width), height: abs(bounds.height))
        guard width > 0, height > 0, width <= 16384, height <= 16384 else { throw ToolboxError("视频尺寸超出编码器支持范围") }
        let renderSize = CGSize(width: width, height: height)
        let fps = frameRate.isFinite && frameRate > 0 ? Double(frameRate) : 30
        var chosenCover: CIImage?
        if cover == .random {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let time = duration.seconds < 0.2 ? 0 : Double.random(in: 0.1...0.9) * duration.seconds
            let cg = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
            chosenCover = CIImage(cgImage: cg)
        }
        let coverImage = chosenCover
        let context = CIContext(options: nil)
        let rectangle = CGRect(origin: .zero, size: renderSize)
        let composition = AVMutableVideoComposition(asset: asset, applyingCIFiltersWithHandler: { request in
            // Select by timeline time, not a persistent animation layer. Only frame zero changes.
            let source = request.compositionTime.seconds < (0.5 / fps) ? (coverImage ?? request.sourceImage) : request.sourceImage
            let extent = source.extent
            let normalized = source.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            let scale = min(renderSize.width / extent.width, renderSize.height / extent.height)
            let image = normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (renderSize.width - extent.width * scale)/2, y: (renderSize.height - extent.height * scale)/2))
            let background = CIImage(color: CIColor(red:0,green:0,blue:0,alpha:1)).cropped(to: rectangle)
            request.finish(with: image.composited(over: background).cropped(to: rectangle), context: context)
        })
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 60000)
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality), exporter.supportedFileTypes.contains(.mp4) else { throw ToolboxError("系统编码器不支持此视频，请先在剪映导出 MP4 或 MOV。") }
        exporter.outputURL = temporary; exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true; exporter.videoComposition = composition
        let polling = Task { while !Task.isCancelled { progress(Double(exporter.progress)); try? await Task.sleep(nanoseconds: 300_000_000) } }
        defer { polling.cancel() }
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void,Never>) in
                exporter.exportAsynchronously { continuation.resume() }
            }
        }, onCancel: { exporter.cancelExport() })
        try Task.checkCancellation()
        guard exporter.status == .completed else { throw exporter.error ?? ToolboxError("视频处理未完成") }
        let check = AVURLAsset(url: temporary)
        let outputDuration = try await check.load(.duration)
        let checkTracks = try await check.loadTracks(withMediaType: .video)
        guard let checkTrack = checkTracks.first else { throw ToolboxError("输出校验失败：无画面") }
        let size = try await checkTrack.load(.naturalSize)
        guard Int(size.width.rounded()) == width, Int(size.height.rounded()) == height,
              abs(outputDuration.seconds-duration.seconds) <= max(0.15,2/fps) else { throw ToolboxError("输出校验失败：尺寸或时长异常") }
        let inputAudio = try await asset.loadTracks(withMediaType: .audio)
        let outputAudio = try await check.loadTracks(withMediaType: .audio)
        if !inputAudio.isEmpty && outputAudio.isEmpty { throw ToolboxError("输出校验失败：音频丢失") }
        try Task.checkCancellation()
        try fm.moveItem(at: temporary, to: output)
        progress(1)
        return output
    }
}
