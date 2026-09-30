import Foundation
import Testing
import FactoryCore

@MainActor
struct XSharingLegacyCoverageTests {
    private let configuration = XHandleRegistrationConfiguration(
        projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test"
    )!

    @Test func invalidUntrustedAndSubframeObservationsNeverReport() async throws {
        let transport = MigrationTransport()
        let sharing = XUsernameSharingCoordinator(configuration: configuration, transport: transport)
        #expect(sharing.acknowledge())
        let window = UUID()
        sharing.openWindow(id: window)
        for handle in ["", "a/b", "@alice", "alice smith", "éclair", "abcdefghijklmnop", "HOME", "login", "connect_people", "who_to_follow"] {
            await sharing.observe(handle: handle, origin: URL(string: "https://x.com/home")!,
                                  isMainFrame: true, windowID: window, generation: sharing.generation)
        }
        for origin in ["http://x.com", "https://x.com.evil.test", "https://twitter.com", "https://x.com:8443", "https://user:pass@x.com"] {
            await sharing.observe(handle: "alice", origin: try #require(URL(string: origin)),
                                  isMainFrame: true, windowID: window, generation: sharing.generation)
        }
        await sharing.observe(handle: "alice", origin: URL(string: "https://x.com")!,
                              isMainFrame: false, windowID: window, generation: sharing.generation)
        await sharing.observe(handle: nil, origin: URL(string: "https://x.com")!,
                              isMainFrame: true, windowID: window, generation: sharing.generation)
        #expect(transport.requests.isEmpty)

        await sharing.observe(handle: "Alice", origin: URL(string: "https://www.x.com/home")!,
                              isMainFrame: true, windowID: window, generation: sharing.generation)
        #expect(transport.requests.count == 1)
        let payload = try JSONSerialization.jsonObject(with: #require(transport.requests.first?.httpBody)) as? [String: Any]
        #expect(payload?["p_handle"] as? String == "alice")
    }

    @Test func confirmedWithdrawalRetriesAfterLocalSaveFailureAndStopsAfterRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let backup = directory.appendingPathExtension("backup")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: backup)
        }
        let stateURL = directory.appendingPathComponent("sharing.json")
        let transport = MigrationTransport()
        let clock = MigrationResumeClock()
        let sharing = XUsernameSharingCoordinator(configuration: configuration, transport: transport,
                                                   stateURL: stateURL, clock: clock)
        #expect(sharing.acknowledge())
        // Keep the durable withdrawal while making its confirmation write fail.
        transport.afterRemoteSuccess = {
            try FileManager.default.moveItem(at: directory, to: backup)
            try Data("blocks-directory-creation".utf8).write(to: directory)
        }
        #expect(await sharing.decline())
        #expect(!sharing.collectionEnabled)
        #expect(sharing.lastDiagnostic != nil)
        #expect(sharing.statusText.contains("Removing feedback contact permission"))
        try #require(transport.requests.count == 1)
        let originalPayload = try JSONSerialization.jsonObject(with: #require(transport.requests[0].httpBody)) as? NSDictionary

        transport.afterRemoteSuccess = nil
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backup, to: directory)
        clock.monotonicNow = 59
        await sharing.resume()
        #expect(transport.requests.count == 1)
        clock.monotonicNow = 60
        await sharing.resume()
        try #require(transport.requests.count == 2)
        let retriedPayload = try JSONSerialization.jsonObject(with: #require(transport.requests[1].httpBody)) as? NSDictionary
        #expect(retriedPayload == originalPayload)
        #expect(retriedPayload?["p_handle"] == nil)
        #expect(transport.requests.allSatisfy { $0.url?.lastPathComponent == "withdraw_x_sharing_v1" })
        #expect(sharing.statusText == "Sharing is off on this Mac.")

        let restarted = XUsernameSharingCoordinator(configuration: configuration, transport: transport,
                                                     stateURL: stateURL, clock: clock)
        await restarted.resume()
        #expect(restarted.choice == .declined)
        #expect(!restarted.collectionEnabled)
        #expect(restarted.lastDiagnostic == nil)
        #expect(restarted.statusText == "Sharing is off on this Mac.")
        #expect(transport.requests.count == 2)
    }
}

@MainActor
private final class MigrationResumeClock: XUsernameSharingClock {
    var monotonicNow: TimeInterval = 0
    var now: Date { Date(timeIntervalSince1970: monotonicNow) }

    // This test advances time and calls resume explicitly instead of running timers.
    func sleep(for seconds: TimeInterval) async throws { throw CancellationError() }
}

@MainActor
private final class MigrationTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    var afterRemoteSuccess: (() throws -> Void)?

    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        try afterRemoteSuccess?()
        let status = request.url?.lastPathComponent == "withdraw_x_sharing_v1" ? "withdrawn" : "recorded"
        return .init(statusCode: 200, body: Data("{\"status\":\"\(status)\"}".utf8))
    }
}
