import Foundation
import Testing
@testable import FactoryCore

@MainActor
private final class PolicyClock: XUsernameSharingClock {
    var monotonicNow: TimeInterval = 0
    var wallTime: TimeInterval = 1_000_000
    var now: Date { Date(timeIntervalSince1970: wallTime) }
    var automatic = false
    var sleeps: [TimeInterval] = []
    private var waiters: [(TimeInterval, CheckedContinuation<Void, Error>)] = []

    func sleep(for seconds: TimeInterval) async throws {
        sleeps.append(seconds)
        if automatic {
            monotonicNow += seconds
            wallTime += seconds
        } else {
            try await withCheckedThrowingContinuation { waiters.append((monotonicNow + seconds, $0)) }
        }
        try Task.checkCancellation()
    }

    func advance(_ seconds: TimeInterval) async {
        monotonicNow += seconds
        wallTime += seconds
        let due = waiters.filter { $0.0 <= monotonicNow }
        waiters.removeAll { $0.0 <= monotonicNow }
        for (_, continuation) in due { continuation.resume() }
        await settle()
    }

    func finish() {
        let remaining = waiters
        waiters.removeAll()
        for (_, continuation) in remaining { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
private final class PolicyTransport: XHandleRegistrationTransport {
    enum Reply {
        case http(Int, String? = nil)
        case networkFailure
    }
    var replies: [Reply] = []
    var requests: [URLRequest] = []
    var duringRequest: ((Int) -> Void)?

    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        duringRequest?(requests.count)
        let reply = replies.isEmpty ? .http(200) : replies.removeFirst()
        switch reply {
        case .networkFailure: throw URLError(.notConnectedToInternet)
        case .http(let code, let retryAfter):
            let outcome = request.url?.lastPathComponent == "withdraw_x_sharing_v1" ? "withdrawn" : "recorded"
            return .init(statusCode: code, retryAfter: retryAfter, body: Data("{\"status\":\"\(outcome)\"}".utf8))
        }
    }
}

@MainActor
private func settle() async { for _ in 0..<40 { await Task.yield() } }

private func policyConfiguration(_ key: String = "sb_publishable_original") -> XHandleRegistrationConfiguration {
    XHandleRegistrationConfiguration(projectURL: "https://policy.supabase.co", publishableKey: key)!
}

@MainActor
private func report(_ coordinator: XUsernameSharingCoordinator, handle: String = "policy_owner") async {
    let window = UUID()
    coordinator.openWindow(id: window)
    await coordinator.observe(handle: handle, origin: URL(string: "https://x.com/home")!,
                              isMainFrame: true, windowID: window, generation: coordinator.generation)
}

@MainActor
struct XSharingRetryPolicyTests {
    @Test(arguments: [408, 429, 500, 503, 599, -1])
    func transientOrdinaryFailuresRetryOnlyOnce(status: Int) async throws {
        let clock = PolicyClock(), transport = PolicyTransport()
        clock.automatic = true
        let failure: PolicyTransport.Reply = status == -1 ? .networkFailure : .http(status)
        transport.replies = [failure, failure]
        let coordinator = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, clock: clock)
        #expect(coordinator.acknowledge())
        await report(coordinator)
        await coordinator.resume()
        #expect(transport.requests.count == 2)
        #expect(clock.sleeps == [5])
        let payloads = try transport.requests.map { try JSONSerialization.jsonObject(with: $0.httpBody!) as! [String: Any] }
        #expect(payloads.map { $0["p_sequence"] as? Int } == [1, 1])
        #expect(payloads.map { $0["p_handle"] as? String } == ["policy_owner", "policy_owner"])
    }

    @Test(arguments: [400, 401, 403, 404, 409, 422])
    func permanentOrdinaryFailureNeverRetries(status: Int) async {
        let clock = PolicyClock(), transport = PolicyTransport()
        clock.automatic = true
        transport.replies = [.http(status, "10")]
        let coordinator = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, clock: clock)
        #expect(coordinator.acknowledge())
        await report(coordinator)
        await coordinator.resume()
        #expect(transport.requests.count == 1)
        #expect(clock.sleeps.isEmpty)
        #expect(coordinator.collectionEnabled)
    }

    @Test(arguments: [-86_400.0, 86_400.0])
    func wallClockAdjustmentDoesNotExpireLiveOrdinaryEvent(jump: TimeInterval) async {
        let clock = PolicyClock(), transport = PolicyTransport()
        clock.automatic = true
        transport.replies = [.http(503)]
        transport.duringRequest = { if $0 == 1 { clock.wallTime += jump } }
        let coordinator = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, clock: clock)
        #expect(coordinator.acknowledge())
        await report(coordinator)
        #expect(transport.requests.count == 2)
        #expect(clock.sleeps == [5])
    }

    @Test func monotonicExpiryDropsRetryEvenIfWallClockDoesNotMove() async {
        let clock = PolicyClock(), transport = PolicyTransport()
        clock.automatic = true
        transport.replies = [.http(503)]
        transport.duringRequest = { if $0 == 1 { clock.monotonicNow = 30 } }
        let coordinator = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, clock: clock)
        #expect(coordinator.acknowledge())
        await report(coordinator)
        #expect(transport.requests.count == 1)
        #expect(clock.sleeps.isEmpty)
    }

    @Test func withdrawalHonorsLongerRetryAfterWithoutOrdinaryDeadline() async {
        let clock = PolicyClock(), transport = PolicyTransport()
        defer { clock.finish() }
        transport.replies = [.http(429, "7200"), .http(200)]
        let coordinator = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, clock: clock)
        #expect(coordinator.acknowledge())
        #expect(await coordinator.decline())
        await settle()
        #expect(transport.requests.count == 1)
        await clock.advance(7199)
        #expect(transport.requests.count == 1)
        #expect(coordinator.statusText.contains("Removing feedback contact permission"))
        await clock.advance(1)
        #expect(transport.requests.count == 2)
        #expect(transport.requests.allSatisfy { $0.url?.lastPathComponent == "withdraw_x_sharing_v1" })
        #expect(coordinator.statusText == "Sharing is off on this Mac.")
    }

    @Test func permanentWithdrawalRetriesOnceOnLaunchAndOnceOnKeyRepair() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sharing.json")
        let clock = PolicyClock(), firstTransport = PolicyTransport()
        defer { clock.finish() }
        firstTransport.replies = [.http(401)]
        var first: XUsernameSharingCoordinator? = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: firstTransport, stateURL: file, clock: clock)
        #expect(first!.acknowledge())
        #expect(await first!.decline())
        await first!.resume()
        await clock.advance(10_000)
        #expect(firstTransport.requests.count == 1)
        first = nil

        let restartedTransport = PolicyTransport()
        restartedTransport.replies = [.http(401), .http(401)]
        let restarted = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: restartedTransport, stateURL: file, clock: clock)
        #expect(restarted.choice == .declined)
        await restarted.resume()
        await restarted.resume()
        await restarted.updateConfiguration(policyConfiguration())
        #expect(restartedTransport.requests.count == 1)
        let repaired = policyConfiguration("sb_publishable_repaired")
        await restarted.updateConfiguration(repaired)
        await restarted.resume()
        await restarted.updateConfiguration(repaired)
        #expect(restartedTransport.requests.count == 2)
        #expect(restartedTransport.requests.last?.value(forHTTPHeaderField: "apikey") == "sb_publishable_repaired")
        #expect(!restarted.collectionEnabled)
        #expect(restarted.statusText.contains("Removing feedback contact permission"))
        #expect(clock.sleeps.isEmpty)
    }

    @Test func declinedRestartResumesOnlyUsernameFreeWithdrawalThenDeletesOutbox() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sharing.json")
        let oldClock = PolicyClock(), oldTransport = PolicyTransport()
        oldTransport.replies = [.http(200), .networkFailure]
        var old: XUsernameSharingCoordinator? = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: oldTransport, stateURL: file, clock: oldClock)
        #expect(old!.acknowledge())
        await report(old!, handle: "ephemeral_owner")
        #expect(await old!.decline())
        await settle()
        let pending = try String(contentsOf: file, encoding: .utf8)
        #expect(!pending.contains("ephemeral_owner"))
        let withdrawalBody = try #require(oldTransport.requests.last?.httpBody)
        old = nil
        oldClock.finish()
        await settle()

        let clock = PolicyClock(), transport = PolicyTransport()
        clock.wallTime += 60
        defer { clock.finish() }
        let restarted = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, stateURL: file, clock: clock)
        #expect(restarted.choice == .declined)
        #expect(!restarted.collectionEnabled)
        await report(restarted, handle: "must_not_send")
        await restarted.resume()
        #expect(transport.requests.count == 1)
        let request = try #require(transport.requests.first)
        #expect(request.url?.lastPathComponent == "withdraw_x_sharing_v1")
        let expected = try JSONSerialization.jsonObject(with: withdrawalBody) as! NSDictionary
        let actual = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as! NSDictionary
        #expect(actual == expected)
        #expect(actual["p_handle"] == nil)
        #expect(restarted.statusText == "Sharing is off on this Mac.")
        let confirmed = XUsernameSharingCoordinator(configuration: policyConfiguration(), transport: transport, stateURL: file, clock: clock)
        await confirmed.resume()
        #expect(transport.requests.count == 1)
        #expect(confirmed.choice == .declined)
        let state = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect((state["withdrawals"] as? [Any])?.isEmpty == true)
        #expect(state["grant"] == nil)
    }
}
