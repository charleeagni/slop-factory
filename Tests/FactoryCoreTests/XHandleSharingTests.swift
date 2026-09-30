import Foundation
import Testing
@testable import FactoryCore

@MainActor
@Test func sharingRequiresDurableChoiceAndNeverReplaysOnRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let state = directory.appendingPathComponent("sharing.json")
    let transport = SharingTransport()
    let config = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!
    let coordinator = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: state)
    let window = UUID()
    coordinator.openWindow(id: window)
    await coordinator.observe(handle: "Alice", origin: URL(string: "https://x.com/home")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    #expect(transport.requests.isEmpty)
    #expect(coordinator.acknowledge())
    await coordinator.observe(handle: "Alice", origin: URL(string: "https://x.com/home")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    #expect(transport.requests.count == 1)
    let payload = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
    #expect(payload["p_handle"] as? String == "alice")
    #expect(payload["p_sequence"] as? Int == 1)
    let restarted = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: state)
    #expect(restarted.collectionEnabled)
    #expect(restarted.choiceTime != nil)
    await restarted.resume()
    #expect(transport.requests.count == 1)
    #expect(!String(data: try Data(contentsOf: state), encoding: .utf8)!.contains("alice"))
}

@MainActor
private final class SharingTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        if request.url!.lastPathComponent == "withdraw_x_sharing_v1" { return .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8)) }
        return .init(statusCode: 200, body: Data("{\"status\":\"recorded\"}".utf8))
    }
}

@MainActor
@Test func declinePersistsWithdrawalAndReplacementUsesFreshGrant() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let transport = SharingTransport()
    let config = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!
    let coordinator = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: directory.appendingPathComponent("state"))
    #expect(coordinator.acknowledge())
    let window = UUID(); coordinator.openWindow(id: window)
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    #expect(await coordinator.decline())
    #expect(!coordinator.collectionEnabled)
    #expect(coordinator.statusText == "Sharing is off on this Mac.")
    #expect(transport.requests[1].url!.lastPathComponent == "withdraw_x_sharing_v1")
    #expect(coordinator.acknowledge())
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    let first = try JSONSerialization.jsonObject(with: transport.requests[0].httpBody!) as! [String: Any]
    let replacement = try JSONSerialization.jsonObject(with: transport.requests[2].httpBody!) as! [String: Any]
    #expect(first["p_grant_id"] as? String != replacement["p_grant_id"] as? String)
}

@MainActor
@Test func windowsDeduplicateRediscoveryAndRejectPopupsAndLateEvents() async {
    let transport = SharingTransport()
    let config = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!
    let coordinator = XUsernameSharingCoordinator(configuration: config, transport: transport)
    #expect(coordinator.acknowledge())
    let first = UUID(), second = UUID(), popup = UUID()
    coordinator.openWindow(id: first); coordinator.openWindow(id: second); coordinator.openWindow(id: popup, isPopup: true)
    let generation = coordinator.generation
    for (window, handle) in [(first, "alice"), (first, ""), (first, "alice"), (second, "bob"), (popup, "carol"), (first, "bob")] {
        await coordinator.observe(handle: handle, origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: generation)
    }
    #expect(transport.requests.count == 3)
    coordinator.closeWindow(id: second)
    await coordinator.observe(handle: "carol", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: second, generation: generation)
    #expect(await coordinator.decline())
    await coordinator.observe(handle: "carol", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: first, generation: generation)
    #expect(transport.requests.count == 4)
}

@MainActor
@Test func failedAcknowledgementAndUnreadableStateFailClosed() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("invalid".utf8).write(to: directory)
    let config = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!
    let invalid = XUsernameSharingCoordinator(configuration: config, stateURL: directory)
    #expect(!invalid.acknowledge())
    #expect(!invalid.collectionEnabled)
    #expect(try String(contentsOf: directory, encoding: .utf8) == "invalid")
    let unwritable = XUsernameSharingCoordinator(configuration: config, stateURL: directory.appendingPathComponent("state"))
    #expect(!unwritable.acknowledge())
    #expect(!unwritable.collectionEnabled)
    #expect(unwritable.lastDiagnostic != nil)
}

@MainActor
@Test func concurrentWindowsKeepSeparateLiveReports() async throws {
    let transport = HeldSharingTransport()
    let config = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!
    let coordinator = XUsernameSharingCoordinator(configuration: config, transport: transport)
    #expect(coordinator.acknowledge())
    let first = UUID(), second = UUID()
    coordinator.openWindow(id: first); coordinator.openWindow(id: second)
    let running = Task { await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: first, generation: coordinator.generation) }
    while transport.requests.isEmpty { await Task.yield() }
    await coordinator.observe(handle: "bob", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: second, generation: coordinator.generation)
    #expect(transport.requests.count == 1)
    transport.release()
    await running.value
    #expect(transport.requests.count == 2)
    let secondPayload = try JSONSerialization.jsonObject(with: transport.requests[1].httpBody!) as! [String: Any]
    #expect(secondPayload["p_handle"] as? String == "bob")
    #expect(secondPayload["p_sequence"] as? Int == 2)
}

@MainActor
private final class HeldSharingTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    var continuation: CheckedContinuation<Void, Never>?
    func release() { continuation?.resume(); continuation = nil }
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        if requests.count == 1 { await withCheckedContinuation { continuation = $0 } }
        return .init(statusCode: 200, body: Data("{\"status\":\"recorded\"}".utf8))
    }
}

@MainActor
@Test func initialDeclineSurvivesRelaunchAndCleansLegacyQueue() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacy = directory.appendingPathComponent("legacy.json")
    try Data("[{\"handle\":\"olduser\"}]".utf8).write(to: legacy)
    let state = directory.appendingPathComponent("sharing.json")
    let transport = SharingTransport()
    let coordinator = XUsernameSharingCoordinator(configuration: nil, transport: transport, stateURL: state, legacyStateURL: legacy)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(await coordinator.decline())
    let restarted = XUsernameSharingCoordinator(configuration: nil, transport: transport, stateURL: state)
    #expect(restarted.choice == .declined)
    #expect(!restarted.collectionEnabled)
    #expect(restarted.lastDiagnostic == nil)
    await restarted.resume()
    #expect(transport.requests.isEmpty)
}
