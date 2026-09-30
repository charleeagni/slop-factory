import Foundation
import Testing
@testable import FactoryCore

struct CodexExecutableResolverTests {
    @Test func choosesNewestInstalledCLIAndRechecksOnNextBuild() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstDirectory = root.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = root.appendingPathComponent("second", isDirectory: true)
        for directory in [firstDirectory, secondDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let executable = directory.appendingPathComponent("codex")
            try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        let first = firstDirectory.appendingPathComponent("codex")
        let second = secondDirectory.appendingPathComponent("codex")
        let runner = VersionRunner(versions: [first.path: "codex-cli 0.158.0", second.path: "codex-cli 0.159.0"])
        let path = "\(firstDirectory.path):\(secondDirectory.path)"

        #expect(ModelDetection.newestCodexExecutable(savedPath: first.path, searchPath: path, commandRunner: runner) == second)

        runner.versions[first.path] = "codex-cli 0.160.0"
        #expect(ModelDetection.newestCodexExecutable(savedPath: first.path, searchPath: path, commandRunner: runner) == first)
    }
}

private final class VersionRunner: CommandRunner {
    var versions: [String: String]
    init(versions: [String: String]) { self.versions = versions }

    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval) throws -> CommandResult {
        guard arguments == ["--version"], let version = versions[executable.path] else {
            return CommandResult(exitCode: 1, stdout: "", stderr: "")
        }
        return CommandResult(exitCode: 0, stdout: version, stderr: "")
    }
}
