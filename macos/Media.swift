import Foundation
import AppKit
import AVFoundation
import QuartzCore

struct Preview {
    let image: NSImage?
    let note: String
}
enum PreviewService {
    static func make(_ draft: Draft) -> Preview {
        if let cover = draft.cover, let data = try? Data(contentsOf: cover), let image = NSImage(data: data) {
            let saved = (try? cover.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let note = saved < draft.modified.addingTimeInterval(-2) ? "封面早于草稿修改，请在剪映保存新封面" : "剪映已保存封面"
            return Preview(image: image, note: note)
        }
        for file in draft.materials.prefix(8) where FileManager.default.fileExists(atPath: file.path) {
            if ["png","jpg","jpeg","heic","webp","bmp"].contains(file.pathExtension.lowercased()), let image = NSImage(contentsOf: file) {
                return Preview(image: image, note: "素材画面 · 非完整时间线预览")
            }
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
        let fm = FileManager.default
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
        guard width <= 16384, height <= 16384 else { throw ToolboxError("视频尺寸超出编码器支持范围") }
        let renderSize = CGSize(width: width, height: height)
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        let fps = frameRate > 0 ? Double(frameRate) : 30
        composition.frameDuration = CMTime(seconds: 1 / fps, preferredTimescale: 60000)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        instruction.backgroundColor = NSColor.black.cgColor
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        let scale = min(CGFloat(width) / abs(bounds.width), CGFloat(height) / abs(bounds.height))
        let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        let scaled = normalized.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let centered = scaled.concatenating(CGAffineTransform(translationX: (CGFloat(width) - abs(bounds.width) * scale)/2, y: (CGFloat(height) - abs(bounds.height) * scale)/2))
        layerInstruction.setTransform(centered, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        composition.instructions = [instruction]
        if cover == .random {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let time = duration.seconds < 0.2 ? 0 : Double.random(in: 0.1...0.9) * duration.seconds
            let cg = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
            let parentLayer = CALayer(); parentLayer.frame = CGRect(origin: .zero, size: renderSize)
            let videoLayer = CALayer(); videoLayer.frame = parentLayer.bounds
            let coverLayer = CALayer(); coverLayer.frame = parentLayer.bounds
            coverLayer.contents = cg; coverLayer.contentsGravity = .resizeAspect
            coverLayer.backgroundColor = NSColor.black.cgColor
            coverLayer.opacity = 0
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = [1,1,0]; animation.keyTimes = [0,0.99,1]
            animation.calculationMode = .discrete
            animation.beginTime = AVCoreAnimationBeginTimeAtZero
            animation.duration = 1 / fps
            animation.fillMode = .forwards; animation.isRemovedOnCompletion = false
            coverLayer.add(animation, forKey: "first-frame-cover")
            parentLayer.addSublayer(videoLayer); parentLayer.addSublayer(coverLayer)
            composition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
        }
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
