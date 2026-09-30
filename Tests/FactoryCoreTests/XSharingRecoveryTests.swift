import Foundation
import Testing
@testable import FactoryCore

@MainActor
private final class RecoveryClock: XUsernameSharingClock {
    var monotonicNow: TimeInterval = 0
    var now: Date { Date(timeIntervalSince1970: monotonicNow) }
    var sleeps: [TimeInterval] = []
    func sleep(for seconds: TimeInterval) async throws {
        sleeps.append(seconds)
        monotonicNow += seconds
    }
}

@MainActor
private final class RecoveryTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    var responses: [XHandleRegistrationResponse] = []
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        try Task.checkCancellation()
        requests.append(request)
        return responses.isEmpty ? .init(statusCode: 200, body: Data("{\"status\":\"recorded\"}".utf8)) : responses.removeFirst()
    }
}

@MainActor
@Test func ordinaryReportRetriesOnceWithSameSequenceAfterFiveSeconds() async throws {
    let clock = RecoveryClock(), transport = RecoveryTransport()
    transport.responses = [.init(statusCode: 503), .init(statusCode: 503)]
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport, clock: clock)
    #expect(coordinator.acknowledge())
    let window = UUID(); coordinator.openWindow(id: window)
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    #expect(transport.requests.count == 2)
    #expect(clock.sleeps == [5])
    let payloads = try transport.requests.map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: Any] }
    #expect(payloads.map { $0["p_sequence"] as? Int } == [1, 1])
}

@MainActor
@Test func ordinaryRetryHonorsDeadlineAndBoundsTimeout() async {
    for (delay, count, timeout) in [("31", 1, 15.0), ("25", 2, 5.0)] {
        let clock = RecoveryClock(), transport = RecoveryTransport()
        transport.responses = [.init(statusCode: 429, retryAfter: delay)]
        let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport, clock: clock)
        #expect(coordinator.acknowledge())
        let window = UUID(); coordinator.openWindow(id: window)
        await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
        #expect(transport.requests.count == count)
        #expect(transport.requests.last?.timeoutInterval == timeout)
    }
}

@MainActor
private final class ManualRecoveryClock: XUsernameSharingClock {
    var monotonicNow: TimeInterval = 0
    var now: Date { Date(timeIntervalSince1970: monotonicNow) }
    var waiters: [(TimeInterval, CheckedContinuation<Void, Error>)] = []
    func sleep(for seconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { waiters.append((monotonicNow + seconds, $0)) }
        try Task.checkCancellation()
    }
    func advance(_ seconds: TimeInterval) async {
        monotonicNow += seconds
        let due = waiters.filter { $0.0 <= monotonicNow }; waiters.removeAll { $0.0 <= monotonicNow }
        for (_, continuation) in due { continuation.resume() }
        for _ in 0..<30 { await Task.yield() }
    }
    func finish() { for (_, continuation) in waiters { continuation.resume(throwing: CancellationError()) }; waiters = [] }
}

@MainActor
@Test func durableWithdrawalRetriesAtOneFiveAndThirtyMinutes() async {
    let clock = ManualRecoveryClock(), transport = RecoveryTransport()
    transport.responses = [.init(statusCode: 503), .init(statusCode: 503), .init(statusCode: 503), .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))]
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport, clock: clock)
    #expect(coordinator.acknowledge())
    #expect(await coordinator.decline())
    for _ in 0..<30 { await Task.yield() }
    #expect(transport.requests.count == 1)
    await clock.advance(59); #expect(transport.requests.count == 1)
    await clock.advance(1); #expect(transport.requests.count == 2)
    await clock.advance(299); #expect(transport.requests.count == 2)
    await clock.advance(1); #expect(transport.requests.count == 3)
    await clock.advance(1800); #expect(transport.requests.count == 4)
    #expect(coordinator.statusText == "Sharing is off on this Mac.")
    clock.finish()
}

@MainActor
@Test func configurationRotationKeepsChoiceAndDestinationChangeWithdrawsOriginalGrant() async throws {
    let transport = RecoveryTransport()
    transport.responses = [.init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))]
    let original = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_original")!
    let coordinator = XUsernameSharingCoordinator(configuration: original, transport: transport)
    #expect(coordinator.acknowledge())
    let generation = coordinator.generation
    await coordinator.updateConfiguration(XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_rotated")!)
    #expect(coordinator.collectionEnabled)
    #expect(coordinator.generation == generation)
    await coordinator.updateConfiguration(XHandleRegistrationConfiguration(projectURL: "https://other.supabase.co", publishableKey: "sb_publishable_other")!)
    #expect(!coordinator.collectionEnabled)
    #expect(coordinator.choice == .unknown)
    #expect(transport.requests.count == 1)
    #expect(transport.requests.first?.url?.host == "example.supabase.co")
    #expect(transport.requests.first?.value(forHTTPHeaderField: "apikey") == "sb_publishable_rotated")
}

@MainActor
@Test func replacementWaitsForSameDestinationWithdrawalThenReportsLiveEvent() async {
    let clock = ManualRecoveryClock(), transport = RecoveryTransport()
    transport.responses = [.init(statusCode: 503), .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))]
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport, clock: clock)
    #expect(coordinator.acknowledge()); #expect(await coordinator.decline())
    for _ in 0..<30 { await Task.yield() }
    await clock.advance(45)
    #expect(coordinator.acknowledge())
    #expect(coordinator.statusText.contains("Waiting"))
    let window = UUID(); coordinator.openWindow(id: window)
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    for _ in 0..<30 { await Task.yield() }
    #expect(transport.requests.count == 1)
    await clock.advance(15)
    #expect(transport.requests.map { $0.url!.lastPathComponent } == ["withdraw_x_sharing_v1", "withdraw_x_sharing_v1", "report_x_activity_v1"])
    clock.finish()
}

@MainActor
private final class StaleRecoveryTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    var reply: CheckedContinuation<XHandleRegistrationResponse, Error>?
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        if requests.count == 1 { return try await withCheckedThrowingContinuation { reply = $0 } }
        let status = request.url!.lastPathComponent == "withdraw_x_sharing_v1" ? "withdrawn" : "recorded"
        return .init(statusCode: 200, body: Data("{\"status\":\"\(status)\"}".utf8))
    }
}

@MainActor
@Test func lateOldGrantReplyCannotBlockOrDisableReplacement() async {
    let transport = StaleRecoveryTransport()
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport)
    #expect(coordinator.acknowledge())
    let window = UUID(); coordinator.openWindow(id: window)
    let old = Task { await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation) }
    while transport.reply == nil { await Task.yield() }
    #expect(await coordinator.decline()); #expect(coordinator.acknowledge())
    await coordinator.observe(handle: "bob", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    #expect(transport.requests.count == 3)
    transport.reply?.resume(returning: .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))); transport.reply = nil
    await old.value
    #expect(coordinator.collectionEnabled)
}

@MainActor
@Test func accountAbsenceInvalidatesLateReplyEvenAfterSameHandleRediscovery() async {
    let transport = StaleRecoveryTransport()
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport)
    #expect(coordinator.acknowledge())
    let window = UUID(); coordinator.openWindow(id: window)
    let old = Task { await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation) }
    while transport.reply == nil { await Task.yield() }
    await coordinator.observe(handle: nil, origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    transport.reply?.resume(returning: .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))); transport.reply = nil
    await old.value
    #expect(coordinator.collectionEnabled)
    #expect(transport.requests.count == 1)
}

@MainActor
@Test func expiredReplacementEventCannotReplayAfterWithdrawalRecovery() async {
    let clock = ManualRecoveryClock(), transport = RecoveryTransport()
    transport.responses = [.init(statusCode: 503), .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))]
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport, clock: clock)
    #expect(coordinator.acknowledge()); #expect(await coordinator.decline()); #expect(coordinator.acknowledge())
    let window = UUID(); coordinator.openWindow(id: window)
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    for _ in 0..<30 { await Task.yield() }
    await clock.advance(60)
    #expect(transport.requests.count == 2)
    #expect(transport.requests.allSatisfy { $0.url!.lastPathComponent == "withdraw_x_sharing_v1" })
    clock.finish()
}

@MainActor
@Test func withdrawalForOtherDestinationDoesNotBlockNewDestinationActivity() async {
    let clock = ManualRecoveryClock(), transport = RecoveryTransport()
    transport.responses = [.init(statusCode: 503)]
    let coordinator = XUsernameSharingCoordinator(configuration: XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!, transport: transport, clock: clock)
    #expect(coordinator.acknowledge())
    await coordinator.updateConfiguration(XHandleRegistrationConfiguration(projectURL: "https://other.supabase.co", publishableKey: "sb_publishable_other")!)
    #expect(coordinator.acknowledge())
    let window = UUID(); coordinator.openWindow(id: window)
    await coordinator.observe(handle: "alice", origin: URL(string: "https://x.com")!, isMainFrame: true, windowID: window, generation: coordinator.generation)
    #expect(transport.requests.map { $0.url!.host! } == ["example.supabase.co", "other.supabase.co"])
    for _ in 0..<30 { await Task.yield() }; clock.finish()
}
