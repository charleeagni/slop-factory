import Foundation
import Testing
@testable import FactoryCore

@MainActor
@Test func sharingKeyRepairSurvivesAnOlderInFlightWithdrawalFailure() async throws {
    let transport = ConfigurationRaceTransport(holdFirst: true)
    let original = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_old")!
    let repaired = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_repaired")!
    let coordinator = XUsernameSharingCoordinator(configuration: original, transport: transport)
    #expect(coordinator.acknowledge())
    let decline = Task { await coordinator.decline() }
    while transport.requests.isEmpty { await Task.yield() }
    await coordinator.updateConfiguration(repaired)
    transport.releaseFirst(statusCode: 401)
    #expect(await decline.value)
    for _ in 0..<100 where transport.requests.count < 2 {
        try await Task.sleep(for: .milliseconds(2))
    }
    #expect(transport.requests.count == 2, "The repaired key must get its promised attempt after the stale failure")
    #expect(transport.requests.last?.value(forHTTPHeaderField: "apikey") == "sb_publishable_repaired")
    #expect(coordinator.statusText == "Sharing is off on this Mac.")
    #expect(!coordinator.collectionEnabled)
}

@MainActor
private final class ConfigurationRaceTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    private let holdFirst: Bool
    private var first: CheckedContinuation<XHandleRegistrationResponse, Never>?

    init(holdFirst: Bool = false) { self.holdFirst = holdFirst }

    func releaseFirst(statusCode: Int) {
        first?.resume(returning: .init(statusCode: statusCode))
        first = nil
    }

    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        if holdFirst && requests.count == 1 {
            return await withCheckedContinuation { first = $0 }
        }
        return .init(statusCode: 200, body: Data("{\"status\":\"withdrawn\"}".utf8))
    }
}

@MainActor
@Test func sharingDestinationRepairWithdrawsOldGrantAfterAnUnsavedChange() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stateURL = directory.appendingPathComponent("sharing.json")
    let transport = ConfigurationRaceTransport()
    let original = XHandleRegistrationConfiguration(projectURL: "https://original.supabase.co", publishableKey: "sb_publishable_original")!
    let replacement = XHandleRegistrationConfiguration(projectURL: "https://replacement.supabase.co", publishableKey: "sb_publishable_replacement")!
    let coordinator = XUsernameSharingCoordinator(configuration: original, transport: transport, stateURL: stateURL)
    #expect(coordinator.acknowledge())
    let savedChoice = try Data(contentsOf: stateURL)
    try FileManager.default.removeItem(at: directory)
    try Data("storage temporarily unavailable".utf8).write(to: directory)
    await coordinator.updateConfiguration(replacement)
    #expect(!coordinator.collectionEnabled)
    #expect(coordinator.lastDiagnostic != nil)
    #expect(transport.requests.isEmpty)

    try FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try savedChoice.write(to: stateURL)
    await coordinator.updateConfiguration(replacement)
    #expect(transport.requests.count == 1, "Repairing the unsaved change must withdraw the persisted old grant")
    #expect(transport.requests.first?.url?.host == "original.supabase.co")
    #expect(transport.requests.first?.url?.lastPathComponent == "withdraw_x_sharing_v1")
    #expect(transport.requests.first?.value(forHTTPHeaderField: "apikey") == "sb_publishable_original")
    #expect(coordinator.choice == .unknown)
    #expect(!coordinator.collectionEnabled)
}

@MainActor
@Test func sharingKeyRepairRetriesAfterItsFirstSaveFails() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let stateURL = directory.appendingPathComponent("sharing.json")
    let transport = ConfigurationRaceTransport(holdFirst: true)
    let original = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_old")!
    let repaired = XHandleRegistrationConfiguration(projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_repaired")!
    let coordinator = XUsernameSharingCoordinator(configuration: original, transport: transport, stateURL: stateURL)
    #expect(coordinator.acknowledge())
    let decline = Task { await coordinator.decline() }
    while transport.requests.isEmpty { await Task.yield() }
    transport.releaseFirst(statusCode: 401)
    #expect(await decline.value)
    let savedChoice = try Data(contentsOf: stateURL)
    try FileManager.default.removeItem(at: directory)
    try Data("storage temporarily unavailable".utf8).write(to: directory)
    await coordinator.updateConfiguration(repaired)
    #expect(coordinator.lastDiagnostic != nil)
    #expect(transport.requests.count == 1)

    try FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try savedChoice.write(to: stateURL)
    await coordinator.updateConfiguration(repaired)
    #expect(transport.requests.count == 2, "The persisted old key must be repaired even after the new configuration was set in memory")
    #expect(transport.requests.last?.value(forHTTPHeaderField: "apikey") == "sb_publishable_repaired")
    #expect(coordinator.statusText == "Sharing is off on this Mac.")
    #expect(!coordinator.collectionEnabled)
}
