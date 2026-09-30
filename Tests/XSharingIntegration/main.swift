import AppKit
import FactoryCore
import WebKit

@MainActor
final class SharingBrowserCheck {
    var observed: [(String?, UUID, UUID)] = []
    var opened: [UUID] = []
    var closed: [UUID] = []
    var windows: [NSWindow] = []

    func require(_ condition: Bool, _ message: String) {
        guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }

    func pause() async { try? await Task.sleep(for: .milliseconds(650)) }

    func evaluate(_ script: String, in view: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                if case .failure(let error) = result {
                    fputs("JavaScript failed: \(script): \(error)\n", stderr)
                }
                continuation.resume(with: result.map { Optional($0) })
            }
        }
    }

    func make(popup: Bool = false, handle: String = "FixtureOwner") -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: """
            window.accountReads = 0;
            const original = document.querySelector.bind(document);
            document.querySelector = function(selector) {
              if (selector === 'a[data-testid="AppTabBar_Profile_Link"]') window.accountReads++;
              return original(selector);
            };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        let view = XBrowserView.make(configuration: config, isPopup: popup)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        windows.append(window)
        view.loadHTMLString("<html><body><a data-testid='AppTabBar_Profile_Link' href='/\(handle)'>Profile</a></body></html>",
                            baseURL: URL(string: "https://x.com/home")!)
        return view
    }

    func ready(_ view: WKWebView) async throws {
        for _ in 0..<80 {
            if !view.isLoading, (try? await evaluate("document.readyState", in: view)) as? String == "complete" { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        require(false, "local WebKit fixture failed to load")
    }

    func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let transport = FixtureTransport()
        let configuration = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_fixture")!
        let coordinator = XUsernameSharingCoordinator(configuration: configuration, transport: transport,
                                                       stateURL: directory.appendingPathComponent("sharing.json"))
        coordinator.onChange = {
            XBrowserView.setCollectionGeneration(coordinator.collectionEnabled ? coordinator.generation : nil)
        }
        XBrowserView.onSessionOpened = { self.opened.append($0); coordinator.openWindow(id: $0) }
        XBrowserView.onSessionClosed = { self.closed.append($0); coordinator.closeWindow(id: $0) }
        XBrowserView.onAccountObservation = { handle, origin, isMainFrame, session, generation in
            Task { await coordinator.observe(handle: handle, origin: origin, isMainFrame: isMainFrame, windowID: session, generation: generation) }
            self.observed.append((handle, session, generation))
        }
        let view = make()
        try await ready(view)
        require(try await evaluate("window.accountReads", in: view) as? Int == 0, "unknown choice read an account")
        require(observed.isEmpty, "unknown choice delivered an account")
        require(opened.count == 1, "top-level session must register before enabling")

        require(coordinator.acknowledge(), "acknowledgement must save before enabling")
        let generation = coordinator.generation
        await pause()
        require(observed.count == 1 && observed.first?.0 == "fixtureowner", "enabling existing window must capture its account")
        require(observed.first?.1 == opened.first && observed.first?.2 == generation, "observation must carry its own session and choice generation")

        require(transport.requests.count == 1, "acknowledged browser account must reach transport once")
        let payload = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
        require(payload["p_handle"] as? String == "fixtureowner", "transport report must belong to this browser account")
        let popup = make(popup: true)
        try await ready(popup)
        require(try await evaluate("window.accountReads", in: popup) as? Int == 0, "provider popup must not read accounts")
        require(opened.count == 1 && observed.count == 1, "popup must not create an activity session")

        let second = make(handle: "SecondOwner")
        try await ready(second)
        await pause()
        require(opened.count == 2, "each top-level window has its own session")
        require(transport.reportHandles == ["fixtureowner", "secondowner"], "simultaneous windows report their own handles")
        _ = try await evaluate("document.querySelector('a').removeAttribute('href')", in: view)
        await pause()
        require(observed.last?.0 == nil && observed.last?.1 == opened[0], "logout clears only its owning window")
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/FixtureOwner')", in: view)
        await pause()
        require(transport.reportHandles == ["fixtureowner", "secondowner"], "logout and rediscovery do not add activity")
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/SwitchedOwner')", in: view)
        await pause()
        require(transport.reportHandles == ["fixtureowner", "secondowner", "switchedowner"], "account switch creates exactly one activity for the owning window")
        let beforeInvalid = observed.count
        for (session, choice) in [(opened[1], generation), (opened[0], UUID())] {
            _ = try await evaluate("window.webkit.messageHandlers.slopXAccount.postMessage({generation: '\(choice.uuidString)', session: '\(session.uuidString)', handle: 'intruder', href: 'https://x.com/intruder'}); null", in: view)
        }
        await pause()
        require(observed.count == beforeInvalid, "cross-window and stale-choice messages cannot deliver observations")
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/QueuedOwner')", in: view)
        let beforeDecline = observed.count
        require(await coordinator.decline(), "decline must durably save withdrawal")
        require(transport.requests.last?.url?.lastPathComponent == "withdraw_x_sharing_v1", "decline must withdraw remotely")
        // Enqueue after stop on the same WebKit connection to observe completed teardown.
        let reads = try await evaluate("window.accountReads", in: view) as? Int
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/ChangedOwner')", in: view)
        await pause()
        require(try await evaluate("window.accountReads", in: view) as? Int == reads, "decline must stop existing mutation observers")
        require(observed.count == beforeDecline, "decline must reject later account messages")
        require(try await evaluate("document.querySelector('a').textContent", in: view) as? String == "Profile", "decline must leave the page usable")

        require(coordinator.acknowledge(), "replacement acknowledgement must save")
        let replacement = coordinator.generation
        await pause()
        require(observed.contains { $0.0 == "changedowner" && $0.1 == opened[0] && $0.2 == replacement }, "new acknowledgement must install fresh generation")
        let beforeLateMessage = observed.count
        _ = try await evaluate("window.webkit.messageHandlers.slopXAccount.postMessage({generation: '\(generation.uuidString)', session: '\(opened[0].uuidString)', handle: 'oldowner', href: 'https://x.com/oldowner'}); null", in: view)
        await pause()
        require(observed.count == beforeLateMessage, "old grant's queued browser messages cannot enter a replacement choice")
        let rotated = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_rotated")!
        let beforeRotation = observed.count
        await coordinator.updateConfiguration(rotated)
        await pause()
        require(coordinator.generation == replacement && observed.count == beforeRotation, "same-destination key rotation preserves choice without recapturing accounts")
        let destination = XHandleRegistrationConfiguration(projectURL: "https://replacement.supabase.co", publishableKey: "sb_publishable_replacement")!
        await coordinator.updateConfiguration(destination)
        require(!coordinator.collectionEnabled, "destination change requires a new choice")
        require(transport.requests.last?.url?.host == "example.supabase.co" && transport.requests.last?.url?.lastPathComponent == "withdraw_x_sharing_v1", "destination change withdraws at the old destination")
        let readsAfterDestination = try await evaluate("window.accountReads", in: view) as? Int
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/DestinationOwner')", in: view)
        await pause()
        require(try await evaluate("window.accountReads", in: view) as? Int == readsAfterDestination, "destination change tears down account reads in existing windows")
        require(coordinator.acknowledge(), "new destination requires its own durable acknowledgement")
        await pause()
        let beforeOldDestination = observed.count
        _ = try await evaluate("window.webkit.messageHandlers.slopXAccount.postMessage({generation: '\(replacement.uuidString)', session: '\(opened[0].uuidString)', handle: 'oldowner', href: 'https://x.com/oldowner'}); null", in: view)
        await pause()
        require(observed.count == beforeOldDestination, "old destination messages cannot cross the new choice")
        require(transport.requests.last?.url?.host == "replacement.supabase.co", "new activity uses the acknowledged destination")
        await coordinator.updateConfiguration(nil)
        let readsAfterInvalid = try await evaluate("window.accountReads", in: view) as? Int
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/InvalidOwner')", in: view)
        await pause()
        let invalidReads = try await evaluate("window.accountReads", in: view) as? Int
        require(!coordinator.collectionEnabled && invalidReads == readsAfterInvalid, "invalid configuration stops capture")
        windows[0].close()
        let beforeClose = observed.count
        _ = try await evaluate("document.querySelector('a').setAttribute('href', '/ClosedOwner')", in: view)
        await pause()
        require(observed.count == beforeClose, "closed windows stop reading accounts even while their web view remains alive")
        windows[2].close()
        require(closed == opened, "native window closure must retire its session")
        XBrowserView.setCollectionGeneration(nil)
        for window in windows { window.close() }
        let beforeMenu = opened.count
        let poster = XWebPoster()
        poster.showLogin()
        let login = NSApp.windows.first { $0.title == "Log into X" && $0.isVisible }!
        (login.contentView as? WKWebView)?.stopLoading()
        require(opened.count == beforeMenu + 1, "menu login registers a session")
        poster.showLogin()
        require(opened.count == beforeMenu + 1, "focusing an open login window does not count another activity")
        login.close()
        poster.showLogin()
        let reopened = NSApp.windows.first { $0.title == "Log into X" && $0.isVisible }!
        (reopened.contentView as? WKWebView)?.stopLoading()
        require(reopened !== login && opened.count == beforeMenu + 2, "reopening menu login creates a fresh qualifying window session")
        reopened.close()
        try FileManager.default.removeItem(at: directory)
        print("Native X sharing browser checks passed")
        exit(0)
    }
}

@MainActor
final class FixtureTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    var reportHandles: [String] {
        requests.compactMap { request in
            guard request.url?.lastPathComponent == "report_x_activity_v1",
                  let body = request.httpBody,
                  let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { return nil }
            return payload["p_handle"] as? String
        }
    }
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        let status = request.url?.lastPathComponent == "withdraw_x_sharing_v1" ? "withdrawn" : "recorded"
        return .init(statusCode: 200, body: Data("{\"status\":\"\(status)\"}".utf8))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    do { try await SharingBrowserCheck().run() }
    catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
app.run()
