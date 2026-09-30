import Foundation
import Testing
@testable import FactoryCore

@MainActor
struct XHandleRegistrationTransportTests {
    @Test func invalidAndPastRetryAfterValuesAreIgnored() {
        for value in [nil, "", "later", "-1", "NaN", "inf", "1e309", "1.5", "+10", "Thu, 01 Jan 1970 00:00:00 GMT"] as [String?] {
            let response = XHandleRegistrationResponse(statusCode: 503, retryAfter: value)
            #expect(response.retryAfterDelay(relativeTo: Date(timeIntervalSince1970: 60)) == nil)
        }
    }

    @Test func HTTPDateRetryAfterReturnsDelayRelativeToClock() {
        let response = XHandleRegistrationResponse(statusCode: 503, retryAfter: "Thu, 01 Jan 1970 00:05:00 GMT")
        #expect(response.retryAfterDelay(relativeTo: Date(timeIntervalSince1970: 60)) == 240)
    }

    @Test func numericRetryAfterReturnsDelayInSeconds() {
        let response = XHandleRegistrationResponse(statusCode: 429, retryAfter: "120")
        #expect(response.retryAfterDelay(relativeTo: Date(timeIntervalSince1970: 0)) == 120)
    }

    @Test func boundsRequestsToFifteenSeconds() async throws {
        let transport = URLSessionXHandleRegistrationTransport(protocolClasses: [TimeoutURLProtocol.self])
        let request = URLRequest(url: URL(string: "https://registration.test/rpc")!)
        let response = try await transport.submit(request)
        #expect(response.statusCode == 204)
    }

    @Test func preservesShortRemainingDeadlineAndRPCOutcome() async throws {
        let transport = URLSessionXHandleRegistrationTransport(protocolClasses: [DeadlineURLProtocol.self])
        let request = URLRequest(url: URL(string: "https://registration.test/rpc")!, timeoutInterval: 2.5)
        let response = try await transport.submit(request)
        #expect(response.statusCode == 200)
        #expect(String(data: response.body, encoding: .utf8) == "{\"status\":\"withdrawn\"}")
    }

    @Test func exposesHTTPStatusAndRetryAfterWithoutTreatingFailureStatusAsTransportFailure() async throws {
        let transport = URLSessionXHandleRegistrationTransport(protocolClasses: [RetryAfterURLProtocol.self])
        let request = URLRequest(url: URL(string: "https://registration.test/rpc")!)
        let response = try await transport.submit(request)
        #expect(response.statusCode == 429)
        #expect(response.retryAfter == "120")
    }
}

private final class RetryAfterURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "120"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class TimeoutURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: request.timeoutInterval == 15 ? 204 : 400, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class DeadlineURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let status = request.timeoutInterval == 2.5 ? 200 : 408
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"status\":\"withdrawn\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
