import Foundation
import Testing
@testable import FactoryCore

@MainActor
struct XSharingPersistenceTests {
    private let config = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test")!
    private let origin = URL(string: "https://x.com")!

    @Test func upgradeNeverReportsPendingOrDeliveredLegacyHandlesAfterAcknowledgement() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legacy = folder.appendingPathComponent("legacy.json")
        try Data("[{\"handle\":\"oldpending\",\"delivered\":false},{\"handle\":\"olddelivered\",\"delivered\":true}]".utf8).write(to: legacy)
        let transport = PersistenceTransport()
        let sharing = XUsernameSharingCoordinator(configuration: config, transport: transport,
            stateURL: folder.appendingPathComponent("sharing.json"), legacyStateURL: legacy)
        await sharing.resume()
        #expect(transport.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(sharing.acknowledge())
        await sharing.resume()
        #expect(transport.requests.isEmpty)
        let window = UUID()
        sharing.openWindow(id: window)
        await sharing.observe(handle: "freshaccount", origin: origin, isMainFrame: true, windowID: window, generation: sharing.generation)
        #expect(transport.requests.count == 1)
        #expect(try transport.payload(0)["p_handle"] as? String == "freshaccount")
    }

    @Test func failedLegacyCleanupKeepsQueueUnusedAndChoiceDisabled() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
        let legacy = folder.appendingPathComponent("legacy.json")
        let original = Data("[{\"handle\":\"neverupload\",\"delivered\":false}]".utf8)
        try original.write(to: legacy)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        let transport = PersistenceTransport()
        let sharing = XUsernameSharingCoordinator(configuration: config, transport: transport, legacyStateURL: legacy)
        #expect(!sharing.collectionEnabled)
        #expect(!sharing.acknowledge())
        #expect(sharing.lastDiagnostic != nil)
        await sharing.resume()
        let window = UUID()
        sharing.openWindow(id: window)
        await sharing.observe(handle: "newuser", origin: origin, isMainFrame: true, windowID: window, generation: sharing.generation)
        #expect(transport.requests.isEmpty)
        #expect(try Data(contentsOf: legacy) == original)
    }

    @Test func corruptStateIsPreservedAcrossDeclineAcknowledgementAndResume() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stateURL = folder.appendingPathComponent("sharing.json")
        let original = Data("{\"grant\":{\"capability\":\"preserve-for-repair\"},broken".utf8)
        try original.write(to: stateURL)
        let transport = PersistenceTransport()
        let sharing = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(!sharing.acknowledge())
        #expect(!(await sharing.decline()))
        await sharing.resume()
        #expect(!sharing.collectionEnabled)
        #expect(sharing.lastDiagnostic != nil)
        #expect(transport.requests.isEmpty)
        #expect(try Data(contentsOf: stateURL) == original)
    }

    @Test func malformedWithdrawalMetadataFailsClosedWithoutReplacingRevocationData() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stateURL = folder.appendingPathComponent("sharing.json")
        let transport = PersistenceTransport()
        let original = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(original.acknowledge())
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
        var grant = state["grant"] as! [String: Any]
        grant["withdrawalFailures"] = -1
        state["grant"] = nil
        state["choice"] = "declined"
        state["withdrawals"] = [grant]
        let corrupt = try JSONSerialization.data(withJSONObject: state)
        try corrupt.write(to: stateURL)
        let restarted = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(restarted.choice == .unknown)
        #expect(!restarted.acknowledge())
        #expect(!restarted.collectionEnabled)
        #expect(try Data(contentsOf: stateURL) == corrupt)
    }

    @Test func launchWithRotatedKeyKeepsChoiceAndWithdrawsUsingRepairedCredentials() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stateURL = folder.appendingPathComponent("sharing.json")
        let transport = PersistenceTransport()
        let original = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(original.acknowledge())
        let rotated = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_rotated")!
        let restarted = XUsernameSharingCoordinator(configuration: rotated, transport: transport, stateURL: stateURL)
        #expect(restarted.choice == .acknowledged)
        #expect(restarted.collectionEnabled)
        #expect(await restarted.decline())
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "apikey") == "sb_publishable_rotated")
    }

    @Test func changedDisclosureWithdrawsSavedGrantWithoutReusingItsChoice() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stateURL = folder.appendingPathComponent("sharing.json")
        let transport = PersistenceTransport()
        let original = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(original.acknowledge())
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
        var grant = state["grant"] as! [String: Any]
        // Simulate a stored disclosure retired by a later client build.
        grant["version"] = "retired-disclosure-fixture"
        state["version"] = "retired-disclosure-fixture"
        state["grant"] = grant
        try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        let restarted = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(restarted.choice == .unknown)
        #expect(!restarted.collectionEnabled)
        await restarted.resume()
        #expect(transport.requests.count == 1)
        #expect(transport.requests.first?.url?.lastPathComponent == "withdraw_x_sharing_v1")
        #expect(try transport.payload(0)["p_disclosure_version"] as? String == "retired-disclosure-fixture")
        #expect(try transport.payload(0)["p_grant_id"] as? String == grant["id"] as? String)
        #expect(!restarted.collectionEnabled)
    }

    @Test func failedDeclineStopsCollectionAndRetainsGrantForSuccessfulSaveRetry() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stateURL = folder.appendingPathComponent("sharing.json")
        let transport = PersistenceTransport()
        let sharing = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(sharing.acknowledge())
        let window = UUID()
        sharing.openWindow(id: window)
        await sharing.observe(handle: "alice", origin: origin, isMainFrame: true, windowID: window, generation: sharing.generation)
        let originalGrant = try transport.payload(0)["p_grant_id"] as? String
        let savedState = try Data(contentsOf: stateURL)
        try FileManager.default.removeItem(at: folder)
        try Data("blocks-directory-creation".utf8).write(to: folder)
        #expect(!(await sharing.decline()))
        #expect(!sharing.collectionEnabled)
        #expect(sharing.statusText.contains("could not be saved"))
        await sharing.resume()
        #expect(sharing.statusText.contains("could not be saved"))
        #expect(transport.requests.count == 1)
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try savedState.write(to: stateURL)
        #expect(await sharing.decline())
        #expect(try transport.payload(1)["p_grant_id"] as? String == originalGrant)
        #expect(try transport.payload(1)["p_handle"] == nil)
        #expect(sharing.statusText == "Sharing is off on this Mac.")
        let restarted = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(restarted.choice == .declined)
        #expect(!restarted.collectionEnabled)
    }

    @Test func restartDoesNotReuseSequenceReservedForUnconfirmedReport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stateURL = folder.appendingPathComponent("sharing.json")
        let transport = PersistenceTransport()
        transport.failNext = true
        let first = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        #expect(first.acknowledge())
        let window = UUID()
        first.openWindow(id: window)
        let running = Task {
            await first.observe(handle: "alice", origin: origin, isMainFrame: true, windowID: window, generation: first.generation)
        }
        while transport.requests.isEmpty { await Task.yield() }
        first.closeWindow(id: window)
        first.stopCollection()
        running.cancel()
        await running.value
        let restarted = XUsernameSharingCoordinator(configuration: config, transport: transport, stateURL: stateURL)
        await restarted.resume()
        #expect(transport.requests.count == 1)
        restarted.openWindow(id: window)
        await restarted.observe(handle: "bob", origin: origin, isMainFrame: true, windowID: window, generation: restarted.generation)
        #expect(transport.requests.count == 2)
        #expect(try transport.payload(0)["p_sequence"] as? Int == 1)
        #expect(try transport.payload(1)["p_sequence"] as? Int == 2)
        #expect(try transport.payload(0)["p_grant_id"] as? String == transport.payload(1)["p_grant_id"] as? String)
        let saved = try String(contentsOf: stateURL, encoding: .utf8)
        #expect(!saved.contains("alice") && !saved.contains("bob"))
        let permissions = try FileManager.default.attributesOfItem(atPath: stateURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}

@MainActor
private final class PersistenceTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    var failNext = false
    func payload(_ index: Int) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: requests[index].httpBody!) as! [String: Any]
    }
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        if failNext { failNext = false; throw URLError(.networkConnectionLost) }
        let status = request.url!.lastPathComponent == "withdraw_x_sharing_v1" ? "withdrawn" : "recorded"
        return .init(statusCode: 200, body: Data("{\"status\":\"\(status)\"}".utf8))
    }
}
