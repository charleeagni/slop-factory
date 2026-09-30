import AppKit
import FactoryCore
import WebKit

final class XWebPoster: Poster {
    init() {}

    @MainActor
    func showLogin() { XWindows.shared.showLogin() }

    func post(text: String, video: URL, draftOnly: Bool, runID: String, onManualPost: @escaping (ManualPostEvent) -> Void) throws -> PostResult {
        // FactoryCore calls the poster from its background check. A synchronous
        // call on the main thread would prevent WebKit from making progress.
        guard !Thread.isMainThread else { throw XPostError("compose", "Posting must run off the main thread.") }
        let completion = DispatchSemaphore(value: 0)
        let box = XPostResultBox()
        let callback = XManualPostCallback(runID: runID, onManualPost: onManualPost)
        Task { @MainActor in
            do {
                box.result = .success(try await XWindows.shared.post(
                    text: text, video: video, draftOnly: draftOnly, runID: runID, onManualPost: callback.call
                ))
            } catch {
                box.result = .failure(error)
            }
            completion.signal()
        }
        completion.wait()
        return try box.result!.get()
    }
}

private final class XPostResultBox: @unchecked Sendable {
    var result: Result<PostResult, Error>?
}

// The callback is handed to one main-actor session, which calls it once.
private final class XManualPostCallback: @unchecked Sendable {
    let call: (ManualPostOutcome) -> Void

    init(runID: String, onManualPost: @escaping (ManualPostEvent) -> Void) {
        call = { outcome in onManualPost(ManualPostEvent(runID: runID, outcome: outcome)) }
    }
}

private struct XPostError: LocalizedError {
    let step: String
    let detail: String

    init(_ step: String, _ detail: String) {
        self.step = step
        self.detail = detail
    }

    var errorDescription: String? { "X \(step): \(detail)" }
}

@MainActor
final class XWindows: NSObject, NSWindowDelegate {
    static let shared = XWindows()

    private let makeView: @MainActor () -> WKWebView

    init(makeView: @escaping @MainActor () -> WKWebView = { XBrowserView.make() }) {
        self.makeView = makeView
        super.init()
    }

    private var loginWindow: NSWindow?
    private var activeSessions: [UUID: XComposeSession] = [:]

    func showLogin() {
        if let loginWindow {
            loginWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = makeView()
        XBrowserView.openPopupsInWindows(view)
        let window = Self.makeWindow(title: "Log into X", view: view)
        loginWindow = window
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view.load(URLRequest(url: URL(string: "https://x.com/")!))
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === loginWindow else { return }
        loginWindow = nil
    }

    func post(text: String, video: URL, draftOnly: Bool, runID: String, onManualPost: @escaping (ManualPostOutcome) -> Void) async throws -> PostResult {
        activeSessions = activeSessions.filter { $0.value.isWindowVisible }
        guard video.isFileURL, FileManager.default.isReadableFile(atPath: video.path) else {
            throw XPostError("video", "The recording is missing or unreadable.")
        }
        let view = makeView()
        let window = Self.makeWindow(title: draftOnly ? "X draft: click Post when ready" : "Posting to X", view: view)
        let log = XPostLog(url: video.deletingLastPathComponent().appendingPathComponent("post.log"))
        let session = XComposeSession(window: window, view: view, log: log)
        activeSessions[session.id] = session
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        do {
            let result = try await session.post(text: text, video: video, draftOnly: draftOnly, runID: runID)
            switch result {
            case .posted: log.write("done: posted")
            case .draftReady: log.write("done: draft ready")
            }
            if case .posted = result {
                activeSessions.removeValue(forKey: session.id)
                window.close()
            } else {
                session.watchManualPost(runID: runID, onManualPost: onManualPost)
            }
            return result
        } catch {
            // Leave the page visible so the owner can inspect or finish the post.
            // Only app-owned errors may leave this boundary. WebKit errors can
            // contain page URLs or account text, even in their debug description.
            let failure = error as? XPostError ?? XPostError("posting", "Posting failed. Check the open window.")
            log.write("failed: \(failure.step)")
            window.title = "X posting failed"
            throw failure
        }
    }


    private static func makeWindow(title: String, view: WKWebView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.center()
        window.contentView = view
        window.isReleasedWhenClosed = false
        XHandleRegistrationService.installChoiceControl(on: window)
        return window
    }
}

@MainActor
private final class XComposeSession: NSObject, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    private let window: NSWindow
    private let view: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?
    private var expectedPostText = ""
    private var manualPostClickCount = 0
    var isWindowVisible: Bool { window.isVisible }

    private let log: XPostLog
    private var pendingUpload: URL?

    init(window: NSWindow, view: WKWebView, log: XPostLog) {
        self.window = window
        self.view = view
        self.log = log
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
        view.configuration.userContentController.add(XPostClickHandler(session: self), name: "slopManualPostClick")
    }

    func post(text: String, video: URL, draftOnly: Bool, runID: String) async throws -> PostResult {
        expectedPostText = String(text.prefix { $0 != "\n" })
        log.write("step: load compose")
        try await loadCompose()
        log.write("step: wait for composer")
        do {
            try await waitFor("compose", seconds: 10, script: Self.composerReady)
        } catch {
            // X sometimes lands on the timeline without the dialog; open it from the sidebar.
            log.write("step: open composer from sidebar")
            _ = try await evaluate("document.querySelector('[data-testid=\"SideNav_NewTweet_Button\"]')?.click()")
            try await waitFor("compose", seconds: 20, script: Self.composerReady)
        }
        log.write("step: insert text")
        try await insertText(text)
        log.write("step: attach video")
        try await attachVideo(video)
        log.write("step: wait for upload")
        try await waitForUpload()
        if draftOnly {
            _ = try await evaluate(Self.observeManualPostClick)
            return .draftReady(runID: runID)
        }

        let clicked = try await evaluate(Self.clickPost) as? Bool ?? false
        guard clicked else { throw XPostError("Post", "The Post button was unavailable.") }
        return .posted(try await waitForPostURL())
    }

    func watchManualPost(runID: String, onManualPost: @escaping (ManualPostOutcome) -> Void) {
        Task { @MainActor [self] in
            var handledClicks = 0
            while isWindowVisible {
                if manualPostClickCount > handledClicks {
                    handledClicks = manualPostClickCount
                    do {
                        let url = try await waitForPostURL(seconds: 60)
                        onManualPost(.posted(url))
                        window.title = "Posted to X"
                        return
                    } catch {
                        let message = error.localizedDescription
                        if message.contains("X reported a post failure") {
                            onManualPost(.failed(step: "Post", message: message))
                        } else {
                            onManualPost(.uncertain(step: "post acknowledgement", message: message))
                        }
                    }
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func didClickPost() { manualPostClickCount += 1 }

    private func loadCompose() async throws {
        guard let url = URL(string: "https://x.com/compose/post") else {
            throw XPostError("compose", "Invalid X compose URL.")
        }
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            view.load(URLRequest(url: url))
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                if let pending = self.navigation {
                    self.navigation = nil
                    pending.resume(throwing: XPostError("compose", "X did not load in 30 seconds."))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume()
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: XPostError("compose", "X navigation failed. Check the open window."))
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: XPostError("compose", "X navigation failed. Check the open window."))
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    private func insertText(_ text: String) async throws {
        let encoded = try String(data: JSONEncoder().encode(text), encoding: .utf8)
            .unwrap(or: XPostError("text", "Could not encode the post text."))
        let script = """
        (() => {
          const editor = document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)))?.querySelector(\(XComposeDialog.literal(XComposeDialog.editorSelector)));
          if (!editor) return false;
          editor.focus();
          document.execCommand('selectAll', false, null);
          const data = new DataTransfer();
          data.setData('text/plain', \(encoded));
          editor.dispatchEvent(new ClipboardEvent('paste', {clipboardData: data, bubbles: true, cancelable: true}));
          return true;
        })()
        """
        guard try await evaluate(script) as? Bool == true else {
            throw XPostError("text", "Could not fill the compose editor.")
        }
        // X's editor renders pasted text asynchronously.
        try await waitFor("text", seconds: 5, script: """
        (() => {
          const editor = document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)))?.querySelector(\(XComposeDialog.literal(XComposeDialog.textareaSelector)));
          return !!editor && \(encoded).split('\\n').filter(line => line).every(line => editor.innerText.includes(line));
        })()
        """)
    }

    private func attachVideo(_ video: URL) async throws {
        // WebKit ignores files assigned from script, so click the input and
        // answer the native open panel with the recording.
        pendingUpload = video
        let clicked = try await evaluate("""
        (() => {
          const input = document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)))?.querySelector(\(XComposeDialog.literal(XComposeDialog.fileInputSelector)));
          if (!input) return false;
          input.click();
          return true;
        })()
        """) as? Bool == true
        guard clicked else { throw XPostError("video", "X did not expose a video attachment control.") }
        let deadline = Date().addingTimeInterval(10)
        while pendingUpload != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(200))
        }
        guard pendingUpload == nil else {
            pendingUpload = nil
            throw XPostError("video", "X did not open the file picker.")
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        log.write(pendingUpload == nil ? "open panel: no attachment" : "open panel: attachment selected")
        completionHandler(pendingUpload.map { [$0] })
        pendingUpload = nil
    }

    private func waitFor(_ step: String, seconds: TimeInterval, script: String) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if try await evaluate(script) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw XPostError(step, "X did not become ready in \(Int(seconds)) seconds. Check the open window.")
    }

    private func waitForUpload() async throws {
        let deadline = Date().addingTimeInterval(180)
        var firstReady: Date?
        while Date() < deadline {
            if try await evaluate(Self.uploadReady) as? Bool == true {
                if let firstReady, Date().timeIntervalSince(firstReady) >= 2 { return }
                if firstReady == nil { firstReady = Date() }
            } else {
                firstReady = nil
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw XPostError("video upload", "X did not finish uploading in 180 seconds. Check the open window.")
    }

    private func waitForPostURL(seconds: TimeInterval = 30) async throws -> URL {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, isWindowVisible {
            if let current = view.url, Self.isPostURL(current),
               (try? await pageShowsExpectedPost()) == true { return current }
            if let link = (try? await evaluate(Self.successToastLink)) as? String,
               let url = URL(string: link), Self.isPostURL(url) { return url }
            if (try? await evaluate(Self.hasPostFailure)) as? Bool == true {
                throw XPostError("Post", "X reported a post failure. Check the open window.")
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw XPostError("post URL", "X did not show a link to the new post.")
    }

    private func pageShowsExpectedPost() async throws -> Bool {
        let encoded = try String(data: JSONEncoder().encode(expectedPostText), encoding: .utf8)
            .unwrap(or: XPostError("post URL", "Could not encode the post text."))
        let script = """
        (() => [...document.querySelectorAll('article[data-testid="tweet"]')]
          .some(article => article.innerText.includes(\(encoded))))()
        """
        return try await evaluate(script) as? Bool == true
    }

    private static func isPostURL(_ url: URL) -> Bool {
        guard ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased() ?? "") else { return false }
        return url.path.range(of: #"^/[^/]+/status/[0-9]+/?$"#, options: .regularExpression) != nil
    }

    private func evaluate(_ script: String) async throws -> Any? {
        do { return try await view.evaluateJavaScript(script) }
        catch { throw XPostError("page script", "X page script failed. Check the open window.") }
    }

    private static let composerReady = """
    (() => !!document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)))?.querySelector(\(XComposeDialog.literal(XComposeDialog.editorSelector))))()
    """

    private static let uploadReady = """
    (() => {
      const dialog = document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)));
      if (!dialog) return false;
      const button = [...dialog.querySelectorAll(\(XComposeDialog.literal(XComposeDialog.postButtonSelector)))]
        .find(b => b.getClientRects().length && !b.disabled && b.getAttribute('aria-disabled') !== 'true');
      const hasPreview = !!dialog.querySelector(\(XComposeDialog.literal(XComposeDialog.videoPreviewSelector)));
      // The character counter is also a progressbar, and X keeps an idle
      // upload bar at 0%, so only a partly filled bar means uploading.
      const width = parseFloat(dialog.querySelector('[data-testid="progressBar-bar"]')?.style.width ?? '0');
      const busy = (width > 0 && width < 100) || !!dialog.querySelector('[data-testid="attachments"] [role="progressbar"]');
      return !!(hasPreview && !busy && button);
    })()
    """

    private static let clickPost = """
    (() => {
      const dialog = document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)));
      if (!dialog) return false;
      const button = [...dialog.querySelectorAll(\(XComposeDialog.literal(XComposeDialog.postButtonSelector)))]
        .find(b => b.getClientRects().length && !b.disabled && b.getAttribute('aria-disabled') !== 'true');
      if (!button) return false;
      button.click();
      return true;
    })()
    """

    private static let observeManualPostClick = """
    (() => {
      const dialog = document.querySelector(\(XComposeDialog.literal(XComposeDialog.rootSelector)));
      if (!dialog) return false;
      dialog.addEventListener('click', event => {
        if (!event.isTrusted) return;
        const button = event.target instanceof Element
          ? event.target.closest(\(XComposeDialog.literal(XComposeDialog.postButtonSelector))) : null;
        if (button && !button.disabled && button.getAttribute('aria-disabled') !== 'true') {
          window.webkit.messageHandlers.slopManualPostClick.postMessage(true);
        }
      }, true);
      return true;
    })()
    """

    // Keep alert text inside the page; only the failure boolean crosses the bridge.
    private static let hasPostFailure = """
    (() => !!document.querySelector('[role="alert"]')?.innerText.trim())()
    """

    private static let successToastLink = """
    (() => {
      for (const toast of document.querySelectorAll('[data-testid="toast"], [role="alert"]')) {
        const link = toast.querySelector('a[href*="/status/"]');
        if (link) return link.href;
      }
      return null;
    })()
    """
}

// Keep all selectors for the prepared composer in one place. Every action and
// readiness check resolves through this dialog root.
private enum XComposeDialog {
    static let rootSelector = "[role=\"dialog\"]"
    static let editorSelector = "[data-testid=\"tweetTextarea_0\"] [contenteditable=\"true\"], [data-testid=\"tweetTextarea_0\"][contenteditable=\"true\"]"
    static let textareaSelector = "[data-testid=\"tweetTextarea_0\"]"
    static let fileInputSelector = "input[type=\"file\"]"
    static let postButtonSelector = "[data-testid=\"tweetButton\"], [data-testid=\"tweetButtonInline\"]"
    static let videoPreviewSelector = "[data-testid=\"attachments\"] video, [data-testid=\"attachments\"] [data-testid=\"videoPlayer\"], [data-testid=\"attachments\"] [data-testid=\"videoComponent\"], [data-testid=\"media-container\"] video, [data-testid=\"videoPlayer\"], [data-testid=\"videoComponent\"]"

    static func literal(_ value: String) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
private final class XPostClickHandler: NSObject, WKScriptMessageHandler {
    private weak var session: XComposeSession?

    init(session: XComposeSession) { self.session = session }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        session?.didClickPost()
    }
}

private extension Optional {
    func unwrap(or error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
