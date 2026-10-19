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

final class TransferProbe: @unchecked Sendable {
    private let lock=NSLock(); private var count:Int64=0
    func record(_ value:Int64) { lock.lock(); count=max(count,value); lock.unlock() }
    var received:Int64 { lock.lock(); defer { lock.unlock() }; return count }
}
func testDownload(_ root:URL) async throws {
    let package=root.appendingPathComponent("network.zip")
    try Data(repeating:71,count:2*1024*1024).write(to:package)
    let server=Process(); server.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
    server.arguments=["-c", """
import http.server, os, sys, time
os.chdir(sys.argv[1])
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
    def copyfile(self, source, output):
        while True:
            chunk=source.read(32768)
            if not chunk: break
            try: output.write(chunk); output.flush()
            except (BrokenPipeError, ConnectionResetError): break
            time.sleep(0.01)
httpd=http.server.ThreadingHTTPServer(('127.0.0.1',0), Handler)
with open('port.txt','w') as file: file.write(str(httpd.server_port))
httpd.serve_forever()
""",root.path]
    server.standardOutput=FileHandle.nullDevice; server.standardError=FileHandle.nullDevice
    try server.run(); defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
    let portFile=root.appendingPathComponent("port.txt")
    for _ in 0..<100 { if FileManager.default.fileExists(atPath:portFile.path) { break }; try await Task.sleep(nanoseconds:50_000_000) }
    let port=try String(contentsOf:portFile,encoding:.utf8)
    let request=URLRequest(url:URL(string:"http://127.0.0.1:\(port)/network.zip")!)
    let probe=TransferProbe()
    let (file,response)=try await MacDownload.fetch(request) { received,_ in probe.record(received) }
    defer { try? FileManager.default.removeItem(at:file) }
    try expect((response as? HTTPURLResponse)?.statusCode == 200,"download HTTP success")
    try MacUpdates.verify(file,expected:"sha256:"+fileDigest(package))
    try expect(probe.received > 0,"download delegate must report progress")
    let task=Task { try await MacDownload.fetch(request) { _,_ in } }
    try await Task.sleep(nanoseconds:80_000_000); task.cancel()
    do { let (leftover,_)=try await task.value; try? FileManager.default.removeItem(at:leftover); throw ToolboxError("download cancellation ignored") }
    catch is CancellationError {}
    catch let error as URLError { try expect(error.code == .cancelled,"cancel must interrupt network download") }
}

@main struct Tests {
    static func main() async throws {
        _ = NSApplication.shared
        let fm=FileManager.default
        let root=fm.temporaryDirectory.appendingPathComponent("yuandian-tests-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
        try await testDownload(root)
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
        let repeatDestination=root.appendingPathComponent("repacked"); try fm.createDirectory(at:repeatDestination,withIntermediateDirectories:true)
        let repeated=try MaterialPackager.package(readback,to:repeatDestination)
        try expect(try DraftLibrary.inspect(repeated).materials.allSatisfy { isInside($0,repeated) },"repack an already packaged draft")
        let cancelDestination=root.appendingPathComponent("cancelled-package"); try fm.createDirectory(at:cancelDestination,withIntermediateDirectories:true)
        var stopCopy=false
        do {
            _ = try MaterialPackager.package(changed,to:cancelDestination,cancelled:{stopCopy}) { _,_ in stopCopy=true }
            throw ToolboxError("copy cancellation ignored")
        } catch is CancellationError {}
        try expect(try fm.contentsOfDirectory(atPath:cancelDestination.path).isEmpty,"cancelled packaging must clean temporary output")
        let manyDraft=root.appendingPathComponent("many-materials"); try fm.createDirectory(at:manyDraft,withIntermediateDirectories:true)
        var manyPaths=(0..<12).map { ["path":root.appendingPathComponent("missing-\($0).mp4").path] }
        manyPaths.append(["path":source.path])
        try JSONSerialization.data(withJSONObject:["materials":manyPaths]).write(to:manyDraft.appendingPathComponent("draft_content.json"))
        try expect(try PreviewService.make(DraftLibrary.inspect(manyDraft)).image != nil,"preview must find an image beyond the first eight references")
        let large=root.appendingPathComponent("large.bin"); try Data(repeating:45,count:8*1024*1024).write(to:large)
        var streamStop=false
        do { try CopyFiles.file(from:large,to:root.appendingPathComponent("partial.bin"),cancelled:{streamStop}) { portion in if portion > 0 { streamStop=true } }; throw ToolboxError("stream cancellation ignored") } catch is CancellationError {}
        try expect(try fileDigest(large) == digest(Data(repeating:45,count:8*1024*1024)),"stream cancellation preserves source")
        let checksumFile=root.appendingPathComponent("download.zip"); try Data("test-package".utf8).write(to:checksumFile)
        try MacUpdates.verify(checksumFile,expected:"sha256:"+fileDigest(checksumFile))
        do { try MacUpdates.verify(checksumFile,expected:"sha256:"+String(repeating:"0",count:64)); throw ToolboxError("bad checksum accepted") } catch { try expect(error.localizedDescription.contains("校验失败"),"reject bad checksum") }
        func release(_ version:String,draft:Bool=false) -> MacRelease {
            MacRelease(tag_name:version,html_url:URL(string:MacUpdates.repository+"/releases/tag/"+version)!,body:nil,draft:draft,assets:[MacRelease.Asset(name:MacUpdates.assetName,browser_download_url:URL(string:MacUpdates.repository+"/releases/download/"+version+"/"+MacUpdates.assetName)!,digest:nil)])
        }
        try expect(MacUpdates.latest([release("macos-v0.1.2"),release("macos-v0.1.10"),release("v9.0.0"),release("macos-v9.0.0",draft:true),release("macos-vbad")])?.tag_name == "macos-v0.1.10","choose newest valid Mac version rather than API order")
        try expect(!MacUpdates.validDownload(URL(string:"https://example.com/download/macos-v0.1.1/file.zip")!),"reject external update URL")
        try expect(SizeMode.auto720.dimensions(width:0,height:0).0 == 0,"invalid dimensions cannot trap")
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
        let cancelOut=root.appendingPathComponent("cancel-video"); try fm.createDirectory(at:cancelOut,withIntermediateDirectories:true)
        let cancelledTask=Task { () throws -> URL in try Task.checkCancellation(); return try await VideoProcessor.convert(input:input,parent:cancelOut,mode:.landscape,cover:.first,progress:{_ in}) }
        cancelledTask.cancel()
        do { _ = try await cancelledTask.value; throw ToolboxError("video cancellation ignored") } catch is CancellationError {}
        try expect(try fm.contentsOfDirectory(atPath:cancelOut.path).isEmpty,"video cancellation leaves clean output")
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
        print("Cover pixels first=\(normalFirst) random=\(randomFirst) later=\(normalLater) outputLater=\(randomLater)")
        try expect(abs(Int(normalLater[0])-Int(randomLater[0])) < 15,"random cover must not cover subsequent frames")
        let rotated=root.appendingPathComponent("rotated.mov"); try await movie(rotated,rotated:true)
        let rotOut=root.appendingPathComponent("rotated-output"); try fm.createDirectory(at:rotOut,withIntermediateDirectories:true)
        _ = try await VideoProcessor.convert(input:rotated,parent:rotOut,mode:.auto720,cover:.first,progress:{_ in})
        try expect(try fileDigest(input) == inputHash,"input video must remain unchanged")
        print("PASS: draft scan, preview content invalidation, source preservation, material packaging, collisions, missing media, encrypted drafts, 4 size modes, audio and duration preservation, random first frame, later-frame preservation, rotation, clean output, preview fallback beyond eight references, repack, streamed copy cancellation, video cancellation, newest Mac release selection and download SHA-256 validation")
    }
}
