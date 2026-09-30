import Foundation

public enum XHandleValidation {
    private static let reserved: Set<String> = [
        "about", "account", "accounts", "compose", "download", "explore", "hashtag", "home", "i",
        "intent", "login", "logout", "messages", "notifications", "privacy", "search", "settings",
        "share", "signup", "tos", "help", "jobs", "oauth", "premium", "communities", "connect_people",
        "who_to_follow", "welcome"
    ]

    public static func normalize(_ handle: String) -> String? {
        guard (1...15).contains(handle.utf8.count), handle.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95
        }) else { return nil }
        let normalized = handle.lowercased()
        return reserved.contains(normalized) ? nil : normalized
    }

    public static func isTrustedOrigin(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && ["x.com", "www.x.com"].contains(url.host?.lowercased() ?? "")
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }
}
