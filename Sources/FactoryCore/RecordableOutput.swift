import Foundation

extension FactoryCore {
    public static func recordablePage(in folder: URL) -> URL? {
        let manager = FileManager.default
        guard let entries = manager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var files: [URL] = []
        while let url = entries.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if ["node_modules", ".git", ".build"].contains(url.lastPathComponent) {
                    entries.skipDescendants()
                }
                continue
            }
            files.append(url)
        }
        let candidates = files.filter { ["html", "htm", "svg", "png", "jpg", "jpeg", "gif", "webp"].contains($0.pathExtension.lowercased()) }
        return candidates.sorted { lhs, rhs in
            func rank(_ url: URL) -> Int {
                let name = url.lastPathComponent.lowercased()
                if name == "index.html" && url.deletingLastPathComponent() == folder { return 0 }
                if name == "index.html" && url.pathComponents.contains("dist") { return 1 }
                if name == "index.html" { return 2 }
                if ["html", "htm"].contains(url.pathExtension.lowercased()) { return 3 }
                return 4
            }
            let left = rank(lhs), right = rank(rhs)
            return left == right ? lhs.path < rhs.path : left < right
        }.first
    }
}
