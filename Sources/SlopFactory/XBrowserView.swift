import AppKit
import FactoryCore
import WebKit

// Web views for x.com. X treats a bare WebKit user agent as an unsupported
// browser, so these present as Safari. Sign-in popups (Google, Apple) open in
// real child windows that keep `window.opener`, which those flows need.
@MainActor
enum XBrowserView {
    private static let popups = XPopupWindows()
    private static var collectionGeneration: UUID?
    private static var sessions: [UUID: XAccountObservationHandler] = [:]
    static var onSessionOpened: (UUID) -> Void = { _ in }
    static var onSessionClosed: (UUID) -> Void = { _ in }
    static var onAccountObservation: (String?, URL, Bool, UUID, UUID) -> Void = { _, _, _, _, _ in }

    static func setCollectionGeneration(_ generation: UUID?) {
        guard collectionGeneration != generation else { return }
        collectionGeneration = generation
        for handler in sessions.values { handler.setGeneration(generation) }
    }

    static func close(_ view: WKWebView) {
        guard let handler = sessions.values.first(where: { $0.webView === view }) else { return }
        handler.setGeneration(nil)
        sessions.removeValue(forKey: handler.session)
        onSessionClosed(handler.session)
    }

    static func make(configuration: WKWebViewConfiguration = WKWebViewConfiguration(),
                     isPopup: Bool = false) -> WKWebView {
        let content = WKUserContentController()
        for script in configuration.userContentController.userScripts
            where !script.source.contains("__slopXAccountContext") && script.source != XAccountObservationScript.source {
            content.addUserScript(script)
        }
        configuration.userContentController = content
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        let view = XAccountWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 760), configuration: configuration)
        // Provider windows establish login only. The owning top-level window observes its own account.
        if !isPopup {
            let handler = XAccountObservationHandler()
            handler.webView = view
            view.accountHandler = handler
            sessions[handler.session] = handler
            onSessionOpened(handler.session)
            handler.setGeneration(collectionGeneration)
        }
        view.allowsBackForwardNavigationGestures = true
        return view
    }

    static func openPopupsInWindows(_ view: WKWebView) {
        view.uiDelegate = popups
    }
}

@MainActor
private final class XPopupWindows: NSObject, WKUIDelegate {
    private var windows: [WKWebView: NSWindow] = [:]

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popup = XBrowserView.make(configuration: configuration, isPopup: true)
        popup.uiDelegate = self
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 680),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = popup
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows[popup] = window
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        windows.removeValue(forKey: webView)?.close()
    }
}

@MainActor
private final class XAccountObservationHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    let session = UUID()
    private var generation: UUID?
    private weak var observedWindow: NSWindow?

    func attachWindow(_ window: NSWindow?) {
        guard window !== observedWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: observedWindow)
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowClosing),
                                                   name: NSWindow.willCloseNotification, object: window)
        }
    }

    @objc private func windowClosing(_ notification: Notification) {
        if let webView { XBrowserView.close(webView) }
        NotificationCenter.default.removeObserver(self)
    }

    func setGeneration(_ next: UUID?) {
        guard generation != next, let webView else { return }
        generation = nil
        let content = webView.configuration.userContentController
        content.removeScriptMessageHandler(forName: XAccountObservationScript.messageName, contentWorld: .defaultClient)
        let unrelated = content.userScripts.filter { !$0.source.contains("__slopXAccountContext") && $0.source != XAccountObservationScript.source }
        content.removeAllUserScripts()
        for script in unrelated { content.addUserScript(script) }
        webView.evaluateJavaScript(XAccountObservationScript.stop, in: nil, in: .defaultClient, completionHandler: nil)
        guard let next else { return }
        generation = next
        content.add(self, contentWorld: .defaultClient, name: XAccountObservationScript.messageName)
        let script = XAccountObservationScript.start(generation: next, session: session)
        content.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd,
                                          forMainFrameOnly: true, in: .defaultClient))
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let generation, let webView, message.webView === webView,
              message.name == XAccountObservationScript.messageName,
              message.frameInfo.isMainFrame,
              let origin = message.frameInfo.request.url,
              XHandleValidation.isTrustedOrigin(origin),
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == origin.host,
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              let body = message.body as? [String: Any],
              body["generation"] as? String == generation.uuidString,
              body["session"] as? String == session.uuidString else { return }
        if body["handle"] is NSNull, body["href"] is NSNull {
            XBrowserView.onAccountObservation(nil, origin, true, session, generation)
            return
        }
        guard origin.path.range(of: #"^/(?:login|logout|signup|i/flow)(?:/|$)"#,
                                options: [.regularExpression, .caseInsensitive]) == nil,
              let rawHandle = body["handle"] as? String,
              let handle = XHandleValidation.normalize(rawHandle),
              let rawHref = body["href"] as? String,
              let href = URL(string: rawHref), XHandleValidation.isTrustedOrigin(href),
              href.host == origin.host,
              let path = URLComponents(url: href, resolvingAgainstBaseURL: false)?.percentEncodedPath,
              path.range(of: #"^/[A-Za-z0-9_]{1,15}/?$"#, options: .regularExpression) != nil,
              XHandleValidation.normalize(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) == handle
        else { return }
        XBrowserView.onAccountObservation(handle, origin, true, session, generation)
    }
}

@MainActor
private final class XAccountWebView: WKWebView {
    var accountHandler: XAccountObservationHandler?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        accountHandler?.attachWindow(window)
    }
}
