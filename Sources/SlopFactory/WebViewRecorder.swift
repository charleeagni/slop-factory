import AppKit
import AVFoundation
import CoreVideo
import FactoryCore
import WebKit

struct WebViewRecorder: Recorder {
    func record(workingFolder: URL, runFolder: URL) throws {
        // Core invokes this from its background check. WebKit must stay on the main actor.
        let completion = DispatchSemaphore(value: 0)
        let result = RecordingResult()
        Task { @MainActor in
            do {
                try await RecordingSession().record(workingFolder: workingFolder, runFolder: runFolder)
                result.value = .success(())
            } catch {
                result.value = .failure(error)
            }
            completion.signal()
        }
        completion.wait()
        try result.value!.get()
    }
}

private final class RecordingResult: @unchecked Sendable {
    var value: Result<Void, Error>?
}

@MainActor
private final class RecordingWindow: NSWindow {
    // WebKit stops requestAnimationFrame for occluded windows. This window is
    // deliberately offscreen, but its page must render for the movie's lifetime.
    override var occlusionState: NSWindow.OcclusionState {
        super.occlusionState.union(.visible)
    }
}

private enum RecordingError: LocalizedError {
    case noRecordableOutput
    case navigationTimedOut
    case snapshotFailed
    case pixelBufferUnavailable
    case writerFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRecordableOutput: "The model produced no page or image to record."
        case .navigationTimedOut: "The page did not finish loading."
        case .snapshotFailed: "The web view could not capture a frame."
        case .pixelBufferUnavailable: "The video encoder could not allocate a frame."
        case .writerFailed(let message): "The video encoder failed: \(message)"
        }
    }
}

@MainActor
private final class RecordingSession: NSObject, WKNavigationDelegate {
    private static let width = 1280
    private static let height = 720
    private static let fps: Int32 = 15
    private static let frameCount = 18 * 15

    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var window: NSWindow?
    private var webView: WKWebView?

    func record(workingFolder: URL, runFolder: URL) async throws {
        let frame = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let view = WKWebView(frame: frame)
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        let window = RecordingWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: Self.width, height: Self.height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        self.window = window
        self.webView = view
        defer {
            view.stopLoading()
            view.navigationDelegate = nil
            window.orderOut(nil)
            self.webView = nil
            self.window = nil
        }

        let resolvedFolder = workingFolder.resolvingSymlinksInPath()
        guard let page = FactoryCore.recordablePage(in: resolvedFolder) else { throw RecordingError.noRecordableOutput }
        try await load(view) { view.loadFileURL(page, allowingReadAccessTo: resolvedFolder) }

        let output = runFolder.appendingPathComponent("demo.mp4")
        try? FileManager.default.removeItem(at: output)
        do {
            try await writeVideo(from: view, to: output)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
    private func load(_ view: WKWebView, action: () -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            action()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                if let pending = self.navigationContinuation {
                    self.navigationContinuation = nil
                    pending.resume(throwing: RecordingError.navigationTimedOut)
                }
            }
        }
        // Let the page's initial layout and scripts settle before recording.
        try await Task.sleep(for: .seconds(1))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    private func writeVideo(from view: WKWebView, to output: URL) async throws {
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Self.width,
            AVVideoHeightKey: Self.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_500_000,
                AVVideoExpectedSourceFrameRateKey: Self.fps,
                AVVideoMaxKeyFrameIntervalKey: Self.fps * 2,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Self.width,
                kCVPixelBufferHeightKey as String: Self.height,
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ]
        )
        writer.add(input)
        guard writer.startWriting() else {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "could not start")
        }
        writer.startSession(atSourceTime: .zero)
        let start = ContinuousClock.now
        do {
            for frame in 0..<Self.frameCount {
                let image = try await snapshot(view)
                guard let buffer = makePixelBuffer(from: image, pool: adaptor.pixelBufferPool) else {
                    throw RecordingError.pixelBufferUnavailable
                }
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(10))
                    if writer.status == .failed {
                        throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "unknown error")
                    }
                }
                guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Self.fps)) else {
                    throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "could not append frame")
                }
                let deadline = start.advanced(by: .seconds(Double(frame + 1) / Double(Self.fps)))
                if ContinuousClock.now < deadline {
                    try await Task.sleep(until: deadline, clock: .continuous)
                }
            }
            input.markAsFinished()
            await writer.finishWriting()
            guard writer.status == .completed else {
                throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "could not finish")
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private func snapshot(_ view: WKWebView) async throws -> CGImage {
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
        config.snapshotWidth = NSNumber(value: Self.width)
        let image = try await view.takeSnapshot(configuration: config)
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw RecordingError.snapshotFailed
        }
        return cgImage
    }

    private func makePixelBuffer(from image: CGImage, pool: CVPixelBufferPool?) -> CVPixelBuffer? {
        guard let pool else { return nil }
        var optionalBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &optionalBuffer) == kCVReturnSuccess,
              let buffer = optionalBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Self.width,
            height: Self.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        context.setFillColor(CGColor.black)
        context.fill(CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height))
        return buffer
    }
}
