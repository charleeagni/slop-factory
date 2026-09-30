import Foundation

public struct XHandleRegistrationResponse: Sendable {
    public let statusCode: Int
    public let retryAfter: String?
    public let body: Data

    public func retryAfterDelay(relativeTo now: Date) -> TimeInterval? {
        guard let retryAfter else { return nil }
        let value = retryAfter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }),
           let seconds = TimeInterval(value), seconds.isFinite {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        guard let date = formatter.date(from: value) else { return nil }
        let delay = date.timeIntervalSince(now)
        return delay.isFinite && delay >= 0 ? delay : nil
    }

    public init(statusCode: Int, retryAfter: String? = nil, body: Data = Data()) {
        self.statusCode = statusCode
        self.retryAfter = retryAfter
        self.body = body
    }
}

@MainActor
public protocol XHandleRegistrationTransport {
    func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse
}

@MainActor
public final class URLSessionXHandleRegistrationTransport: XHandleRegistrationTransport {
    private let session: URLSession

    public convenience init() {
        self.init(protocolClasses: nil)
    }

    init(protocolClasses: [AnyClass]?) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.protocolClasses = protocolClasses
        session = URLSession(configuration: configuration, delegate: RejectRegistrationRedirects(), delegateQueue: nil)
    }

    public func submit(_ request: URLRequest) async throws -> XHandleRegistrationResponse {
        var request = request
        request.timeoutInterval = min(15, request.timeoutInterval)
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return XHandleRegistrationResponse(statusCode: response.statusCode, retryAfter: response.value(forHTTPHeaderField: "Retry-After"), body: data)
    }
}

private final class RejectRegistrationRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // A configured project must never forward the publishable key or handle elsewhere.
        completionHandler(nil)
    }
}
