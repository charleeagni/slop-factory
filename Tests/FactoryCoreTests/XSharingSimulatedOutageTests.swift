import Foundation
import Testing
@testable import FactoryCore

/// Exercise the production URLSession transport without changing the destination
/// or any Mac network setting. URLProtocol supplies connectivity failures.
private final class OutageFixture: @unchecked Sendable {
    struct Attempt {
        let url: URL
        let body: Data
        let offline: Bool
    }
    private let lock = NSLock()
    private var offline = false
    private var attempts: [Attempt] = []

    func reset() { lock.withLock { offline = false; attempts = [] } }
    func disconnect(_ value: Bool) { lock.withLock { offline = value } }
    var captured: [Attempt] { lock.withLock { attempts } }
    func capture(_ request: URLRequest) -> Bool {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        return lock.withLock {
            attempts.append(Attempt(url: request.url!, body: body, offline: offline))
            return offline
        }
    }
}

private final class SimulatedOutageProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = OutageFixture()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if Self.fixture.capture(request) {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let status = request.url!.lastPathComponent == "withdraw_x_sharing_v1" ? "withdrawn" : "recorded"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"status\":\"\(status)\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class OutageClock: XUsernameSharingClock {
    var monotonicNow: TimeInterval = 0
    var now: Date { Date(timeIntervalSince1970: 1_000_000 + monotonicNow) }
    private var waiters: [(TimeInterval, CheckedContinuation<Void, Error>)] = []
    var isWaiting: Bool { !waiters.isEmpty }
    func sleep(for seconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { waiters.append((monotonicNow + seconds, $0)) }
        try Task.checkCancellation()
    }
    func advance(_ seconds: TimeInterval) {
        monotonicNow += seconds
        let due = waiters.filter { $0.0 <= monotonicNow }
        waiters.removeAll { $0.0 <= monotonicNow }
        for (_, continuation) in due { continuation.resume() }
    }
    func finish() {
        let remaining = waiters
        waiters.removeAll()
        for (_, continuation) in remaining { continuation.resume(throwing: CancellationError()) }
    }
}

@MainActor
@Suite(.serialized)
struct XSharingSimulatedOutageTests {
    private let configuration = XHandleRegistrationConfiguration(
        projectURL: "https://toiylcfpbryztcfjievv.supabase.co",
        publishableKey: "sb_publishable_simulated_fixture"
    )!

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    private func report(_ coordinator: XUsernameSharingCoordinator) async {
        let window = UUID()
        coordinator.openWindow(id: window)
        await coordinator.observe(handle: "outage_fixture", origin: URL(string: "https://x.com/home")!,
                                  isMainFrame: true, windowID: window, generation: coordinator.generation)
    }

    @Test func connectionFailureExpiresWithoutReplayAfterRecoveryOrRestart() async throws {
        let fixture = SimulatedOutageProtocol.fixture
        fixture.reset()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sharing.json")
        let clock = OutageClock()
        defer { clock.finish() }
        let transport = URLSessionXHandleRegistrationTransport(protocolClasses: [SimulatedOutageProtocol.self])
        let coordinator = XUsernameSharingCoordinator(configuration: configuration, transport: transport, stateURL: file, clock: clock)
        #expect(coordinator.acknowledge())
        await report(coordinator)
        fixture.disconnect(true)
        let pending = Task { await report(coordinator) }
        let waiting = await eventually { fixture.captured.count == 2 && clock.isWaiting }
        try #require(waiting, "The real URLSession transport must return a connection failure and schedule a retry")
        clock.advance(31)
        await pending.value
        fixture.disconnect(false)
        await coordinator.resume()
        #expect(fixture.captured.count == 2)
        let restarted = XUsernameSharingCoordinator(configuration: configuration, transport: transport, stateURL: file, clock: clock)
        await restarted.resume()
        #expect(restarted.collectionEnabled)
        #expect(fixture.captured.count == 2, "Recovery and restart must not replay the expired activity")
        await report(restarted)
        let attempts = fixture.captured
        #expect(attempts.count == 3)
        #expect(attempts.map(\.offline) == [false, true, false])
        #expect(attempts.allSatisfy { $0.url.host == configuration.projectURL.host })
        let sequences = try attempts.map { try JSONSerialization.jsonObject(with: $0.body) as! [String: Any] }
        #expect(sequences.map { $0["p_sequence"] as? Int } == [1, 2, 3])
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("outage_fixture"))
    }

    @Test func offlineWithdrawalSurvivesRestartAndClearsOnlyAfterRecovery() async throws {
        let fixture = SimulatedOutageProtocol.fixture
        fixture.reset()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("sharing.json")
        let oldClock = OutageClock()
        let transport = URLSessionXHandleRegistrationTransport(protocolClasses: [SimulatedOutageProtocol.self])
        var original: XUsernameSharingCoordinator? = XUsernameSharingCoordinator(configuration: configuration, transport: transport, stateURL: file, clock: oldClock)
        #expect(original!.acknowledge())
        await report(original!)
        fixture.disconnect(true)
        #expect(await original!.decline())
        #expect(!original!.collectionEnabled)
        #expect(original!.statusText == "Sharing is off on this Mac. Removing feedback contact permission when a connection is available.")
        let pending = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect((pending["withdrawals"] as? [Any])?.count == 1)
        #expect(pending["grant"] == nil)
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("outage_fixture"))
        // End the first coordinator's scheduled work, as process exit would.
        original = nil
        oldClock.finish()
        for _ in 0..<40 { await Task.yield() }

        let clock = OutageClock()
        defer { clock.finish() }
        clock.advance(60)
        let restarted = XUsernameSharingCoordinator(configuration: configuration, transport: transport, stateURL: file, clock: clock)
        #expect(restarted.choice == .declined && !restarted.collectionEnabled)
        await report(restarted)
        await restarted.resume()
        #expect(fixture.captured.count == 3)
        #expect(restarted.statusText.contains("Removing feedback contact permission"))
        fixture.disconnect(false)
        clock.advance(300)
        await restarted.resume()
        let recovered = await eventually { restarted.statusText == "Sharing is off on this Mac." }
        #expect(recovered)
        let attempts = fixture.captured
        #expect(attempts.count == 4)
        #expect(attempts.map { $0.url.lastPathComponent } == ["report_x_activity_v1", "withdraw_x_sharing_v1", "withdraw_x_sharing_v1", "withdraw_x_sharing_v1"])
        #expect(attempts.map(\.offline) == [false, true, true, false])
        let withdrawals = try attempts.dropFirst().map { try JSONSerialization.jsonObject(with: $0.body) as! NSDictionary }
        #expect(withdrawals.allSatisfy { Set($0.allKeys.compactMap { $0 as? String }) == ["p_grant_id", "p_capability", "p_disclosure_version"] })
        #expect(withdrawals.allSatisfy { $0 == withdrawals.first })
        let confirmed = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        #expect((confirmed["withdrawals"] as? [Any])?.isEmpty == true)
        #expect(confirmed["grant"] == nil)
        #expect(restarted.choice == .declined && !restarted.collectionEnabled)
    }
}
