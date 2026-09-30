import Foundation

extension ModelDetection {
    static func newestCodexExecutable(savedPath: String, searchPath: String?, commandRunner: any CommandRunner) -> URL {
        let saved = URL(fileURLWithPath: savedPath)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bundledCLI = "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        var candidates = [saved]
        if let searchPath {
            candidates += searchPath.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex")
            }
        }
        candidates += [
            URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true).appendingPathComponent(bundledCLI),
            home.appendingPathComponent("Applications/ChatGPT.app", isDirectory: true).appendingPathComponent(bundledCLI),
        ]

        var best = saved
        var bestVersion: [Int]?
        var inspected = Set<String>()
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            let resolved = candidate.resolvingSymlinksInPath().path
            guard inspected.insert(resolved).inserted,
                  let result = try? commandRunner.run(
                    executable: candidate,
                    arguments: ["--version"],
                    workingFolder: FileManager.default.temporaryDirectory,
                    timeout: 5,
                    environment: searchPath.map { ["PATH": $0] } ?? [:]
                  ), result.exitCode == 0, !result.timedOut,
                  let version = codexVersion(in: result.stdout)
            else { continue }
            if let current = bestVersion, !current.lexicographicallyPrecedes(version) { continue }
            best = candidate
            bestVersion = version
        }
        return best
    }

    static func codexVersion(in output: String) -> [Int]? {
        guard let range = output.range(of: #"\b[0-9]+\.[0-9]+\.[0-9]+\b"#, options: .regularExpression) else { return nil }
        let parts = output[range].split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }
}
