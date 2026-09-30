import AppKit
import FactoryCore
import WebKit

@MainActor
final class FailedPage: WKWebView {
    var navigationFailure = false
    var loads = 0
    var accountReads = 0
    var scripts: [String] = []
    var beforeFailure: (() async -> Void)?

    override var url: URL? {
        accountReads += 1
        return URL(string: "https://x.com/fixture_owner")
    }
    override var title: String? {
        accountReads += 1
        return "@fixture_owner on X"
    }
    override func load(_ request: URLRequest) -> WKNavigation? {
        // No real WebKit navigation or network. Complete the navigation locally.
        loads += 1
        if navigationFailure {
            Task { @MainActor in
                await beforeFailure?()
                beforeFailure = nil
                navigationDelegate?.webView?(self, didFailProvisionalNavigation: nil,
                    withError: NSError(domain: "fixture", code: 17, userInfo: [NSLocalizedDescriptionKey: "@fixture_owner at https://x.com/fixture_owner"]))
            }
        } else {
            navigationDelegate?.webView?(self, didFinish: nil)
        }
        return nil
    }
    override func evaluateJavaScript(_ script: String) async throws -> Any? {
        scripts.append(script)
        if script.contains("document.body") {
            accountReads += 1
            return "Signed in as @fixture_owner"
        }
        if let beforeFailure {
            self.beforeFailure = nil
            await beforeFailure()
        }
        throw NSError(domain: "fixture", code: 17, userInfo: [NSLocalizedDescriptionKey: "@fixture_owner at https://x.com/fixture_owner"])
    }
}

@MainActor
final class LocalSharingTransport: XHandleRegistrationTransport {
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("fixture.mp4")
        try Data([0]).write(to: video)
        var failures: [String] = []
        for mode in ["unknown", "declined", "decline-during-post"] {
            for draftOnly in [false, true] {
                for navigationFailure in [false, true] {
                    let config = XHandleRegistrationConfiguration(projectURL: "https://fixture.invalid", publishableKey: "sb_publishable_fixture")!
                    let coordinator = XUsernameSharingCoordinator(configuration: config, transport: LocalSharingTransport(),
                        stateURL: folder.appendingPathComponent(UUID().uuidString))
                    if mode == "declined" { _ = await coordinator.decline() }
                    if mode == "decline-during-post" {
                        precondition(coordinator.acknowledge())
                        precondition(coordinator.collectionEnabled)
                    }
                    let configuration = WKWebViewConfiguration()
                    configuration.websiteDataStore = .nonPersistent()
                    let page = FailedPage(frame: .zero, configuration: configuration)
                    page.navigationFailure = navigationFailure
                    if mode == "decline-during-post" {
                        page.beforeFailure = { _ = await coordinator.decline() }
                    }
                    let windows = XWindows(makeView: { page })
                    do {
                        _ = try await windows.post(text: "fixture draft", video: video, draftOnly: draftOnly, runID: "fixture") { _ in }
                        failures.append("\(mode): failure was not propagated")
                    } catch {
                        if error.localizedDescription.contains("fixture_owner") || String(describing: error).contains("fixture_owner") {
                            failures.append("\(mode): propagated account-bearing error")
                        }
                    }
                    let output = try String(contentsOf: folder.appendingPathComponent("post.log"), encoding: .utf8)
                    if page.accountReads != 0 { failures.append("\(mode): read account-bearing diagnostics") }
                    if output.contains("fixture_owner") { failures.append("\(mode): persisted username in post.log") }
                    if !output.contains("failed:") { failures.append("\(mode): missing useful failure diagnostic") }
                    if page.window?.isVisible != true { failures.append("\(mode): failed page was closed") }
                    if page.loads != 1 { failures.append("\(mode): posting blocked by sharing choice") }
                    if coordinator.collectionEnabled { failures.append("\(mode): collection enabled after failure") }
                    page.window?.close()
                    try FileManager.default.removeItem(at: folder.appendingPathComponent("post.log"))
                }
            }
        }
        guard failures.isEmpty else {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("Posting diagnostics passed for unknown, declined and decline-during-post, automatic and Draft only, script and navigation failures; no live navigation or post.")
        exit(0)
    } catch { print("FAIL: \(error)"); exit(1) }
}
app.run()
