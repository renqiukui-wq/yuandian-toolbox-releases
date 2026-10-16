import Foundation
import AppKit
import AVFoundation

func expect(_ condition: @autoclosure () throws -> Bool, _ message:String) throws {
    if try !condition() { throw ToolboxError("TEST FAILED: " + message) }
}
func paint(_ url:URL,_ color:NSColor) throws {
    let image = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:64,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let context = NSGraphicsContext(bitmapImageRep:image)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=context
    color.setFill(); NSBezierPath(rect:NSRect(x:0,y:0,width:64,height:64)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try image.representation(using:.png,properties:[:])!.write(to:url)
}
func movie(_ url:URL,rotated:Bool=false) async throws {
    let writer = try AVAssetWriter(outputURL:url,fileType:.mov)
    let input = AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:640,AVVideoHeightKey:360])
    if rotated { input.transform = CGAffineTransform(rotationAngle:.pi/2).translatedBy(x:0,y:-360) }
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:640,kCVPixelBufferHeightKey as String:360])
    writer.add(input); guard writer.startWriting() else { throw writer.error! }; writer.startSession(atSourceTime:.zero)
    for frame in 0..<45 {
        while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds:1_000_000) }
        var buffer: CVPixelBuffer?; CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&buffer)
        let pixel = buffer!; CVPixelBufferLockBaseAddress(pixel,[])
        let ctx = CGContext(data:CVPixelBufferGetBaseAddress(pixel),width:640,height:360,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pixel),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
        ctx.setFillColor(CGColor(red:CGFloat(45-frame)/45,green:0.15,blue:CGFloat(frame)/45,alpha:1)); ctx.fill(CGRect(x:0,y:0,width:640,height:360))
        CVPixelBufferUnlockBaseAddress(pixel,[])
        guard adaptor.append(pixel,withPresentationTime:CMTime(value:Int64(frame),timescale:30)) else { throw writer.error ?? ToolboxError("fixture append failed") }
    }
    input.markAsFinished()
    await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in writer.finishWriting { c.resume() } }
    guard writer.status == .completed else { throw writer.error ?? ToolboxError("fixture failed") }
}
func addAudio(_ input:URL,_ output:URL) async throws {
    let audioURL = input.deletingLastPathComponent().appendingPathComponent("tone.caf")
    let format = AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
    let audio = try AVAudioFile(forWriting:audioURL,settings:format.settings)
    let buffer = AVAudioPCMBuffer(pcmFormat:format,frameCapacity:72000)!; buffer.frameLength=72000
    for i in 0..<72000 { buffer.floatChannelData![0][i] = Float(sin(Double(i)*2*Double.pi*440/48000)*0.08) }
    try audio.write(from:buffer)
    let composition=AVMutableComposition()
    let asset=AVURLAsset(url:input); let audioAsset=AVURLAsset(url:audioURL)
    let video=try await asset.loadTracks(withMediaType:.video).first!
    let sound=try await audioAsset.loadTracks(withMediaType:.audio).first!
    let duration=try await asset.load(.duration)
    let vt=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid)!
    try vt.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:video,at:.zero)
    let at=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid)!
    try at.insertTimeRange(CMTimeRange(start:.zero,duration:duration),of:sound,at:.zero)
    let exporter=AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality)!
    exporter.outputURL=output; exporter.outputFileType = .mp4
    await withCheckedContinuation { (c:CheckedContinuation<Void,Never>) in exporter.exportAsynchronously { c.resume() } }
    guard exporter.status == .completed else { throw exporter.error ?? ToolboxError("audio fixture failed") }
}
func pixel(_ url:URL,seconds:Double) throws -> [UInt8] {
    let g=AVAssetImageGenerator(asset:AVURLAsset(url:url)); g.appliesPreferredTrackTransform=true
    g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
    let image=try g.copyCGImage(at:CMTime(seconds:seconds,preferredTimescale:600),actualTime:nil)
    var bytes=[UInt8](repeating:0,count:4)
    bytes.withUnsafeMutableBytes { raw in
        let ctx=CGContext(data:raw.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image,in:CGRect(x:0,y:0,width:1,height:1))
    }
    return bytes
}
@main struct Tests {
    static func main() async throws {
        _ = NSApplication.shared
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("yuandian-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
        let library=root.appendingPathComponent("drafts"); let draft=library.appendingPathComponent("中文 草稿"); let destination=root.appendingPathComponent("packed")
        try fm.createDirectory(at:draft,withIntermediateDirectories:true); try fm.createDirectory(at:destination,withIntermediateDirectories:true)
        let source=root.appendingPathComponent("same '中文'.png"); try paint(source,.red)
        let document=draft.appendingPathComponent("draft_content.json")
        let object:[String:Any]=["materials":["videos":[["path":source.path]]]]
        let original=try JSONSerialization.data(withJSONObject:object); try original.write(to:document)
        let cover=draft.appendingPathComponent("draft_cover.png"); try paint(cover,.red)
        let before=try DraftLibrary.inspect(draft)
        let oldDate=(try cover.resourceValues(forKeys:[.contentModificationDateKey])).contentModificationDate!
        try paint(cover,.blue); try fm.setAttributes([.modificationDate:oldDate],ofItemAtPath:cover.path)
        let changed=try DraftLibrary.inspect(draft)
        try expect(before.fingerprint != changed.fingerprint,"cover must refresh even if mtime does not change")
        try expect(PreviewService.make(changed).image != nil,"cover must load")
        try expect(try DraftLibrary.scan(library).count == 1,"scan nested library")
        let packed=try MaterialPackager.package(changed,to:destination)
        let readback=try DraftLibrary.inspect(packed)
        try expect(readback.materials.allSatisfy { isInside($0,packed) && fm.fileExists(atPath:$0.path) },"all material paths must point inside packaged copy")
        try expect(try Data(contentsOf:document) == original,"original draft must be untouched")
        do { _ = try MaterialPackager.package(changed,to:destination); throw ToolboxError("collision was accepted") } catch { try expect(error.localizedDescription.contains("同名"),"collision refusal") }
        try fm.removeItem(at:source)
        do { _ = try MaterialPackager.package(changed,to:root); throw ToolboxError("missing material accepted") } catch { try expect(error.localizedDescription.contains("不存在"),"missing material refusal") }
        try Data("encrypted-not-json".utf8).write(to:document)
        try expect(try DraftLibrary.inspect(draft).unreadable == 1,"encrypted draft detection")
        try expect(SizeMode.auto720.dimensions(width:1080,height:1920).0 == 720,"portrait auto720")
        try expect(SizeMode.auto720.dimensions(width:1920,height:1080).0 == 1280,"landscape auto720")
        try expect(SizeMode.auto720.dimensions(width:1000,height:1000).1 == 720,"square auto720")
        let silent=root.appendingPathComponent("silent.mov"); try await movie(silent)
        let input=root.appendingPathComponent("input.mp4"); try await addAudio(silent,input)
        let inputHash=try fileDigest(input)
        for mode in SizeMode.allCases {
            let out=root.appendingPathComponent(mode.id); try fm.createDirectory(at:out,withIntermediateDirectories:true)
            let url=try await VideoProcessor.convert(input:input,parent:out,mode:mode,cover:.first,progress:{_ in})
            try expect(fm.fileExists(atPath:url.path),"converted output exists")
            try expect(try fm.contentsOfDirectory(atPath:out.path).count == 1,"only final video remains")
        }
        let randomOut=root.appendingPathComponent("random"); try fm.createDirectory(at:randomOut,withIntermediateDirectories:true)
        let random=try await VideoProcessor.convert(input:input,parent:randomOut,mode:.landscape,cover:.random,progress:{_ in})
        let normalFirst=try pixel(input,seconds:0); let randomFirst=try pixel(random,seconds:0)
        try expect(abs(Int(normalFirst[0])-Int(randomFirst[0])) > 10,"random cover must change first frame")
        let normalLater=try pixel(input,seconds:1); let randomLater=try pixel(random,seconds:1)
        try expect(abs(Int(normalLater[0])-Int(randomLater[0])) < 15,"random cover must not cover subsequent frames")
        let rotated=root.appendingPathComponent("rotated.mov"); try await movie(rotated,rotated:true)
        let rotOut=root.appendingPathComponent("rotated-output"); try fm.createDirectory(at:rotOut,withIntermediateDirectories:true)
        _ = try await VideoProcessor.convert(input:rotated,parent:rotOut,mode:.auto720,cover:.first,progress:{_ in})
        try expect(try fileDigest(input) == inputHash,"input video must remain unchanged")
        print("PASS: draft scan, preview content invalidation, source preservation, material packaging, collisions, missing media, encrypted drafts, 4 size modes, audio and duration preservation, random first frame, later-frame preservation, rotation and clean output")
    }
}
