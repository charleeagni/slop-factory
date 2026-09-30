// Compiled together with the production recorder by Scripts/test-recorder.sh.
// The synchronous Recorder runs off-main while NSApplication services WebKit.
import AppKit
import AVFoundation
import FactoryCore
import ImageIO

struct CheckFailure: Error, CustomStringConvertible { let description: String }
func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}
extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let self else { throw CheckFailure(description: message) }; return self
    }
}
struct Pixels {
    let rgb: [UInt8]
    init(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let bytes = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var data = [UInt8](); data.reserveCapacity(1280 * 720 * 3)
        for y in 0..<720 { for x in 0..<1280 {
            let p = y * stride + x * 4
            data.append(contentsOf: [bytes[p+2], bytes[p+1], bytes[p]])
        } }
        rgb = data
    }
    func mean(_ x: Int, _ y: Int, size: Int = 20) -> [Int] {
        var sums = [0,0,0]
        for row in y..<y+size { for col in x..<x+size {
            for c in 0..<3 { sums[c] += Int(rgb[(row * 1280 + col) * 3 + c]) }
        } }
        return sums.map { $0 / (size * size) }
    }
    func color(_ x: Int, _ y: Int, _ expected: [Int], tolerance: Int = 25) throws {
        let actual = mean(x,y)
        try check(zip(actual, expected).allSatisfy { abs($0-$1) <= tolerance }, "region \(x),\(y) expected \(expected), got \(actual)")
    }
    func image() -> CGImage {
        CGImage(width: 1280, height: 720, bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: 1280*3,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                provider: CGDataProvider(data: Data(rgb) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    func save(_ url: URL) throws {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(), nil)
        try check(CGImageDestinationFinalize(destination), "save frame")
    }
    func changedPixels(from other: Pixels, above rowLimit: Int = 720) -> Int {
        var count = 0
        for p in stride(from: 0, to: rowLimit*1280*3, by: 3) {
            if (0..<3).contains(where: { abs(Int(rgb[p+$0])-Int(other.rgb[p+$0])) > 35 }) { count += 1 }
        }
        return count
    }
}
func inspect(_ movie: URL, kind: String, evidence: URL) async throws {
    let asset = AVURLAsset(url: movie)
    let tracks = try await asset.loadTracks(withMediaType: .video)
    let track = try tracks.first.unwrap("missing video")
    let size = try await track.load(.naturalSize)
    let fps = try await track.load(.nominalFrameRate)
    let duration = try await asset.load(.duration)
    let formats = try await track.load(.formatDescriptions)
    let audio = try await asset.loadTracks(withMediaType: .audio)
    try check(size == CGSize(width: 1280, height: 720), "dimensions")
    try check(abs(fps - 15) < 0.01, "fps \(fps)")
    try check(abs(CMTimeGetSeconds(duration) - 18) <= 1.0/15 + 0.001, "duration")
    try check(audio.isEmpty, "unexpected audio")
    try check(formats.count == 1 && CMFormatDescriptionGetMediaSubType(formats[0]) == kCMVideoCodecType_H264, "codec")
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    reader.add(output)
    try check(reader.startReading(), "decode start")
    var count = 0
    var frames = [Pixels]()
    var markerStates = Set<Bool>()
    while let sample = output.copyNextSampleBuffer() {
        defer { count += 1 }
        if [15,45,75,135,255].contains(count) {
            let pixels = Pixels(try CMSampleBufferGetImageBuffer(sample).unwrap("missing pixels"))
            try pixels.save(evidence.appendingPathComponent("frame-\(count).png"))
            frames.append(pixels)
            switch kind {
            case "static", "animated":
                for (x,y,color) in [(300,200,[224,48,32]),(900,200,[32,64,192]),(300,500,[32,64,192]),(900,500,[32,192,64]),(80,70,[255,255,0])] {
                    try pixels.color(x,y,color)
                }
                let marker = pixels.mean(580,340)
                try check(marker.allSatisfy { $0 < 25 } || marker.allSatisfy { $0 > 230 } || kind == "static", "invalid animation marker \(marker)")
                markerStates.insert(marker[0] > 128)
            case "dark":
                try pixels.color(300,200,[0,0,0], tolerance: 10)
                try pixels.color(600,350,[0,0,0], tolerance: 10)
            case "claude", "openai":
                // A night sky alone is not a scene: require the warm stall/lantern
                // colors in the middle and lower scene, plus changing surroundings.
                var warm = 0
                for y in 180..<650 { for x in 200..<1100 {
                    let p = (y*1280+x)*3
                    if Int(pixels.rgb[p]) > 120 && Int(pixels.rgb[p]) > Int(pixels.rgb[p+2]) + 45 { warm += 1 }
                } }
                try check(warm > 5000, "missing warm market scene: \(warm) pixels")
            default: throw CheckFailure(description: "unknown fixture \(kind)")
            }
        }
    }
    try check(reader.status == .completed && count == 270, "frame count \(count)")
    if kind == "animated" { try check(markerStates.count == 2, "animation frozen: \(markerStates)") }
    if kind == "claude" || kind == "openai" {
        let differences = frames.dropFirst().map { $0.changedPixels(from: frames[0], above: 360) }
        try check(differences.filter { $0 > 500 }.count >= 2, "surroundings frozen: \(differences)")
        print("\(kind) changed upper-scene pixels: \(differences)")
    }
    print("PASS \(kind): H.264 1280x720, \(fps) fps, \(count) frames, \(CMTimeGetSeconds(duration))s, silent; content at 1/3/5/9/17s")
}
let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let evidence = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let selected = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "all"
setbuf(stdout, nil)
try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.global().asyncAfter(deadline: .now() + 600) {
    print("FAIL: recorder integration exceeded ten minutes"); exit(1)
}
// Fail if a recorder window intersects any attached display during capture.
let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    // This timer is scheduled on the main run loop that services AppKit.
    MainActor.assumeIsolated {
        for window in NSApp.windows where window.isVisible {
            if NSScreen.screens.contains(where: { $0.frame.intersects(window.frame) }) {
                print("FAIL: capture window is onscreen"); exit(1)
            }
        }
    }
}
Task.detached {
    do {
        if selected.hasPrefix("inspect-") {
            try await inspect(URL(fileURLWithPath: CommandLine.arguments[4]), kind: String(selected.dropFirst(8)), evidence: evidence)
            exit(0)
        }
        let recorder: any Recorder = WebViewRecorder()
        let cases = selected == "all" ? ["static", "animated", "empty", "claude", "openai", "static", "dark"] : [selected]
        for (index, kind) in cases.enumerated() {
            let run = evidence.appendingPathComponent("\(index)-\(kind)")
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let working = kind == "empty" ? run.appendingPathComponent("working") : fixtures.appendingPathComponent(kind)
            if kind == "empty" { try FileManager.default.createDirectory(at: working, withIntermediateDirectories: true) }
            if kind == "empty" {
                var rejected = false
                do { try recorder.record(workingFolder: working, runFolder: run) }
                catch { rejected = true; print("Expected empty output rejection: \(error)") }
                try check(rejected, "empty output did not throw")
                try check(!FileManager.default.fileExists(atPath: run.appendingPathComponent("demo.mp4").path), "empty output created a movie")
                continue
            }
            try recorder.record(workingFolder: working, runFolder: run)
            try await inspect(run.appendingPathComponent("demo.mp4"), kind: kind, evidence: run)
            let visible = await MainActor.run { NSApp.windows.filter(\.isVisible).count }
            try check(visible == 0, "recorder left window visible")
        }
        if selected == "all" {
            let invalid = evidence.appendingPathComponent("not-a-directory")
            try Data("filesystem failure fixture".utf8).write(to: invalid)
            var threw = false
            do { try recorder.record(workingFolder: fixtures.appendingPathComponent("static"), runFolder: invalid) }
            catch { threw = true; print("Expected filesystem failure: \(error)") }
            try check(threw, "filesystem failure did not throw")
            try check(!FileManager.default.fileExists(atPath: invalid.appendingPathComponent("demo.mp4").path), "partial failed movie")
            let visible = await MainActor.run { NSApp.windows.filter(\.isVisible).count }
            try check(visible == 0, "failed recording left window visible")
            let recovery = evidence.appendingPathComponent("recovery")
            try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
            try recorder.record(workingFolder: fixtures.appendingPathComponent("animated"), runFolder: recovery)
            try await inspect(recovery.appendingPathComponent("demo.mp4"), kind: "animated", evidence: recovery)
        }
        print("PASS recorder integration"); exit(0)
    } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()
