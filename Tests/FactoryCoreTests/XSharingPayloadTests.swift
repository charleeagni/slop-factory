import Foundation
import Testing
@testable import FactoryCore

@MainActor
struct XSharingPayloadTests {
    @Test func reportingAndWithdrawalSendOnlyTheContractAndNeverPersistObservedHandles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stateURL = folder.appendingPathComponent("sharing.json")
        let transport = PayloadTransport()
        let configuration = try #require(XHandleRegistrationConfiguration(
            projectURL: "https://example.supabase.co", publishableKey: "sb_publishable_test"))
        let sharing = XUsernameSharingCoordinator(configuration: configuration, transport: transport, stateURL: stateURL)
        #expect(sharing.acknowledge())
        let window = UUID()
        sharing.openWindow(id: window)
        await sharing.observe(handle: "payload_owner", origin: URL(string: "https://x.com")!,
            isMainFrame: true, windowID: window, generation: sharing.generation)
        #expect(transport.requests.count == 1)
        let report = try #require(transport.requests.first)
        let reportPayload = try payload(report)
        #expect(Set(reportPayload.keys) == Set(["p_grant_id", "p_capability", "p_disclosure_version", "p_sequence", "p_handle"]))
        #expect(reportPayload["p_handle"] as? String == "payload_owner")
        #expect(reportPayload["p_sequence"] as? Int == 1)
        #expect(reportPayload["p_disclosure_version"] as? String == "x-username-feedback-v1")
        let grantID = try #require(reportPayload["p_grant_id"] as? String)
        #expect(UUID(uuidString: grantID) != nil)
        let capability = try #require(reportPayload["p_capability"] as? String)
        #expect(capability.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil)
        assertRequest(report, rpc: "report_x_activity_v1")
        try assertPrivateState(stateURL)

        // Retain the withdrawal outbox with a permanent client response, so the
        // persisted privacy check covers both acknowledged and pending states.
        #expect(await sharing.decline())
        #expect(sharing.statusText.contains("Removing feedback contact permission"))
        #expect(transport.requests.count == 2)
        let withdrawal = try #require(transport.requests.last)
        let withdrawalPayload = try payload(withdrawal)
        #expect(Set(withdrawalPayload.keys) == Set(["p_grant_id", "p_capability", "p_disclosure_version"]))
        #expect(withdrawalPayload["p_grant_id"] as? String == grantID)
        #expect(withdrawalPayload["p_capability"] as? String == capability)
        #expect(withdrawalPayload["p_disclosure_version"] as? String == "x-username-feedback-v1")
        assertRequest(withdrawal, rpc: "withdraw_x_sharing_v1")
        try assertPrivateState(stateURL)
    }

    private func payload(_ request: URLRequest) throws -> [String: Any] {
        let body = try #require(request.httpBody)
        return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    private func assertRequest(_ request: URLRequest, rpc: String) {
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://example.supabase.co/rest/v1/rpc/\(rpc)")
        #expect(request.httpShouldHandleCookies == false)
        let headers = Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) })
        #expect(headers == ["apikey": "sb_publishable_test", "content-type": "application/json"])
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
    }

    private func assertPrivateState(_ stateURL: URL) throws {
        let saved = try String(contentsOf: stateURL, encoding: .utf8)
        #expect(!saved.contains("payload_owner"))
        let permissions = try FileManager.default.attributesOfItem(atPath: stateURL.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }
}

@MainActor
private final class PayloadTransport: XHandleRegistrationTransport {
    var requests: [URLRequest] = []
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        requests.append(request)
        if request.url?.lastPathComponent == "withdraw_x_sharing_v1" {
            return .init(statusCode: 400)
        }
        return .init(statusCode: 200, body: Data("{\"status\":\"recorded\"}".utf8))
    }
}
