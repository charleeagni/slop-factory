import Foundation

/// Owner-editable text in app data (`my-prompt.txt`, `my-post.txt`). Each file
/// wins while it has text; otherwise the built-in default applies.
public struct MySlopText: Sendable {
    public let fileName: String
    public let builtIn: @Sendable () throws -> String

    /// The prompt every model gets. Defaults to the bundled frozen prompt.
    public static let prompt = MySlopText(fileName: "my-prompt.txt") {
        let installedBundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("SlopFactory_FactoryCore.bundle")) }
        guard let url = installedBundle?.url(forResource: "frozen-prompt", withExtension: "txt")
            ?? Bundle.module.url(forResource: "frozen-prompt", withExtension: "txt")
        else { throw CocoaError(.fileNoSuchFile) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The post headline. `{model}` becomes the model ID.
    public static let postText = MySlopText(fileName: "my-post.txt") {
        "We are so cooked, {model} just one-shotted this without even me asking for it! AGI is here!"
    }

    public func url(appDataFolder: URL) -> URL {
        appDataFolder.appendingPathComponent(fileName)
    }

    public func current(appDataFolder: URL) throws -> String {
        if let custom = try? String(contentsOf: url(appDataFolder: appDataFolder), encoding: .utf8),
           !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        return try builtIn()
    }

    /// Creates the file from the built-in text if needed and returns it for editing.
    public func editableURL(appDataFolder: URL) throws -> URL {
        let url = url(appDataFolder: appDataFolder)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
            try builtIn().write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    public func reset(appDataFolder: URL) throws {
        let url = url(appDataFolder: appDataFolder)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
