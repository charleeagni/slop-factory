import Foundation

public struct XHandleRegistrationConfiguration: Sendable {
    public let projectURL: URL
    public let publishableKey: String

    public init?(projectURL: String, publishableKey: String) {
        guard let url = URL(string: projectURL), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              publishableKey.hasPrefix("sb_publishable_"), publishableKey.count > "sb_publishable_".count,
              publishableKey.utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 || $0 == 45
              }) else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        if components.port == 443 { components.port = nil }
        guard let canonicalURL = components.url else { return nil }
        self.projectURL = canonicalURL
        self.publishableKey = publishableKey
    }
}
