import Foundation
import Testing
@testable import FactoryCore

struct ClaudeDetectionTests {
    @Test func aliasesResolveFromResultModelUsage() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        fixture.runner.aliasModels = [
            "opus": "claude-opus-4-1-20250805",
            "sonnet": "claude-sonnet-4-5-20250929",
            "haiku": "claude-haiku-4-5-20251001",
        ]

        try fixture.check()

        #expect(try fixture.store().seenModels == [
            "claude-haiku-4-5-20251001",
            "claude-opus-4-1-20250805",
            "claude-sonnet-4-5-20250929",
        ])
        #expect(fixture.notifications.messages.isEmpty)
        #expect(Set(fixture.runner.aliasesCalled) == Set(["opus", "sonnet", "haiku"]))
        #expect(fixture.runner.aliasesCalled.count == 3)
        #expect(fixture.runner.calls.filter { $0.executable.path == "/opt/bin/claude" }.allSatisfy {
            $0.arguments.contains("-p") && $0.arguments.contains("--effort") && $0.arguments.contains("medium") && $0.arguments.contains("--output-format") && $0.arguments.contains("json")
        })
    }

    @Test func aliasesResolveFromClaudeEventArray() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\n"
        fixture.runner.aliasModels = ["sonnet": "claude-sonnet-5-5"]
        fixture.runner.arrayOutputAliases = ["sonnet"]

        try fixture.check()

        #expect(try fixture.store().seenModels == ["claude-sonnet-5-5"])
        #expect(try fixture.store().pendingSources?.contains("claude-sonnet") == false)
    }

    @Test func additionalOptionsAreDetected() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        try fixture.claudeConfig(#"{"additionalModelOptionsCache":[{"value":"claude-fable-5-1[1m]"},{"value":"claude-opus-4-1-20250805"}]}"#)

        try fixture.check()

        #expect(try fixture.store().seenModels.contains("claude-fable-5-1[1m]"))
        #expect(try fixture.store().seenModels.contains("claude-opus-4-1-20250805"))
    }

    @Test func loginShellLocationsAreSavedAndReused() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/usr/local/bin/codex\n"
        fixture.runner.aliasModels = ["haiku": "claude-haiku-4-5-20251001"]
        try fixture.cache(#"{"models":[{"slug":"gpt-new","visibility":"list"}]}"#)

        try fixture.check()
        try fixture.check()

        let shellCalls = fixture.runner.calls.filter { $0.executable.path == "/bin/zsh" }
        #expect(shellCalls.count == 1)
        #expect(shellCalls.first?.arguments.first == "-lc")
        let saved = try String(contentsOf: fixture.data.appendingPathComponent("cli-paths.json"), encoding: .utf8)
        #expect(saved.contains("/opt/bin/claude"))
        #expect(saved.contains("/usr/local/bin/codex"))
    }

    @Test func discoveredEnvShebangCliRunsWithLoginShellPath() throws {
        let fixture = try ClaudeFixture()
        let runtime = fixture.root.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        let node = runtime.appendingPathComponent("node")
        try "#!/bin/sh\nshift\nprintf '[%s]' \"$@\"\n".write(to: node, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        let cli = runtime.appendingPathComponent("claude")
        try "#!/usr/bin/env node\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        fixture.runner.cliLookup = "claude=\(cli.path)\ncodex=\npath=\(runtime.path):/usr/bin:/bin:/usr/sbin:/sbin\n"

        #expect(ModelDetection.discoverProviders(commandRunner: fixture.runner, homeFolder: fixture.home, appDataFolder: fixture.data).contains(.claude))
        let discovered = try #require(ModelDetection.savedExecutable(for: "claude-opus-test", appDataFolder: fixture.data, commandRunner: fixture.runner))
        let result = try ProcessCommandRunner().run(executable: discovered, arguments: ["argument with spaces", "model;touch"], workingFolder: fixture.home, timeout: 5, environment: ModelDetection.runtimeEnvironment(appDataFolder: fixture.data))

        #expect(result.exitCode == 0)
        #expect(result.stdout == "[argument with spaces][model;touch]")
    }

    @Test func changedAliasIdIsReportedAsNewModel() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        fixture.runner.aliasModels = ["haiku": "claude-haiku-4-5-20251001"]
        try fixture.check()
        fixture.runner.aliasModels["haiku"] = "claude-haiku-5-20261001"

        try fixture.check()

        #expect(fixture.notifications.messages.count == 1)
        #expect(fixture.notifications.messages.first == "Slop posted: claude-haiku-5-20261001")
        #expect(fixture.runner.calls.contains { call in
            call.executable.path == "/opt/bin/claude" && call.arguments.contains("claude-haiku-5-20261001")
                && call.arguments.contains("--dangerously-skip-permissions")
        })
        #expect(try fixture.store().seenModels.contains("claude-haiku-4-5-20251001"))
        #expect(try fixture.store().seenModels.contains("claude-haiku-5-20261001"))
    }

    @Test func missingClaudeAndFailedAliasLeaveCodexWorking() throws {
        let missing = try ClaudeFixture()
        missing.runner.cliLookup = "codex=/opt/bin/codex\n"
        try missing.cache(#"{"models":[{"slug":"gpt-new","visibility":"list"}]}"#)
        try missing.check()
        #expect(try missing.store().seenModels == ["gpt-new"])
        #expect(missing.runner.aliasesCalled.isEmpty)

        let failing = try ClaudeFixture()
        failing.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        failing.runner.aliasModels = ["opus": "claude-opus-4-1-20250805"]
        failing.runner.failingAliases = ["sonnet"]
        try failing.cache(#"{"models":[{"slug":"gpt-new","visibility":"list"}]}"#)
        try failing.check()
        #expect(try failing.store().seenModels.contains("gpt-new"))
        #expect(try failing.store().seenModels.contains("claude-opus-4-1-20250805"))
        #expect(Set(failing.runner.aliasesCalled) == Set(["opus", "sonnet", "haiku"]))
    }

    @Test func unreadableConfigDoesNotBlockAliasesOrCodex() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        fixture.runner.aliasModels = ["haiku": "claude-haiku-4-5-20251001"]
        try FileManager.default.createDirectory(at: fixture.home.appendingPathComponent(".claude.json"), withIntermediateDirectories: false)
        try fixture.cache(#"{"models":[{"slug":"gpt-new","visibility":"list"}]}"#)

        try fixture.check()

        #expect(try fixture.store().seenModels == ["claude-haiku-4-5-20251001", "gpt-new"])
    }

    @Test func errorResultDoesNotRegisterModelUsage() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\n"
        fixture.runner.errorAliases = ["sonnet"]
        fixture.runner.aliasModels = ["haiku": "claude-haiku-4-5-20251001"]

        try fixture.check()

        #expect(try fixture.store().seenModels == ["claude-haiku-4-5-20251001"])
    }

    @Test func firstLaunchDoesNotCreateBaselineWhenEverySourceFails() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        fixture.runner.failingAliases = ["opus", "sonnet", "haiku"]
        try FileManager.default.createDirectory(at: fixture.home.appendingPathComponent(".claude.json"), withIntermediateDirectories: false)
        try fixture.cache("invalid JSON")

        let result = try FactoryCore.firstLaunchSetup(commandRunner: fixture.runner, homeFolder: fixture.home, appDataFolder: fixture.data, clock: { fixture.now })

        #expect(result?.foundProviders == [.claude, .openAI])
        #expect(!FileManager.default.fileExists(atPath: fixture.data.appendingPathComponent("seen.json").path))
    }

    @Test func recoveringClaudeAliasSeedsQuietlyWhileHealthyCodexStillPostsNewModel() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        fixture.runner.aliasModels = ["opus": "claude-opus-4-1"]
        fixture.runner.failingAliases = ["sonnet", "haiku"]
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"}]}"#)

        try fixture.check()
        #expect(try fixture.store().seenModels == ["claude-opus-4-1", "gpt-old"])
        fixture.runner.failingAliases = []
        fixture.runner.aliasModels["sonnet"] = "claude-sonnet-4-5"
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"},{"slug":"gpt-new","visibility":"list"}]}"#)

        try fixture.check()

        #expect(fixture.notifications.messages == ["Slop posted: gpt-new"])
        #expect(try fixture.store().seenModels.contains("claude-sonnet-4-5"))
    }

    @Test func partialAliasBaselineKeepsRecoveredAliasSilentAndDetectsChanges() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\n"
        fixture.runner.aliasModels = ["opus": "claude-opus-4-1"]
        fixture.runner.failingAliases = ["sonnet"]

        try fixture.check()
        fixture.runner.failingAliases = []
        fixture.runner.aliasModels["sonnet"] = "claude-sonnet-4-5"

        try fixture.check()

        #expect(fixture.notifications.messages.isEmpty)
        #expect(try fixture.store().seenModels.contains("claude-sonnet-4-5"))
    }

    @Test func unavailableCodexCacheSeedsWhenItFirstBecomesReadable() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "codex=/opt/bin/codex\n"
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        try fixture.cache(#"{"models":[{"slug":"gpt-old-a","visibility":"list"},{"slug":"gpt-old-b","visibility":"list"}]}"#)
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        try fixture.cache(#"{"models":[{"slug":"gpt-old-a","visibility":"list"},{"slug":"gpt-old-b","visibility":"list"},{"slug":"gpt-new","visibility":"list"}]}"#)
        try fixture.check()
        #expect(fixture.notifications.messages == ["Slop posted: gpt-new"])
    }

    @Test func failedClaudeAliasesRemainPendingWhileCodexSeedsAndWorks() throws {
        let fixture = try ClaudeFixture()
        fixture.runner.cliLookup = "claude=/opt/bin/claude\ncodex=/opt/bin/codex\n"
        fixture.runner.failingAliases = ["opus", "sonnet", "haiku"]
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"}]}"#)
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        fixture.runner.failingAliases = []
        fixture.runner.aliasModels = ["opus": "claude-old", "sonnet": "claude-old-2"]
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        fixture.runner.aliasModels["haiku"] = "claude-new"
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        fixture.runner.aliasModels["opus"] = "claude-newer"
        try fixture.check()
        #expect(fixture.notifications.messages == ["Slop posted: claude-newer"])
    }
}

private final class ClaudeFixture {
    let root: URL
    let home: URL
    let data: URL
    let notifications = ClaudeNotifier()
    let runner = ClaudeRunner()
    let now = Date(timeIntervalSince1970: 1000)
    var cacheURL: URL { home.appendingPathComponent(".codex/models_cache.json") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        home = root.appendingPathComponent("home")
        data = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func cache(_ contents: String) throws {
        try contents.write(to: cacheURL, atomically: true, encoding: .utf8)
    }

    func claudeConfig(_ contents: String) throws {
        try contents.write(to: home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
    }

    func check() throws {
        try FactoryCore.runOneCheck(commandRunner: runner, homeFolder: home, appDataFolder: data, notifier: notifications, clock: { self.now }, recorder: ClaudeRecorder(), poster: ClaudePoster(), draftOnly: false, repositoryURL: URL(string: "https://github.com/example/slop-factory")!)
    }

    func store() throws -> SeenStore {
        try JSONDecoder().decode(SeenStore.self, from: Data(contentsOf: data.appendingPathComponent("seen.json")))
    }
}

private final class ClaudeRunner: CommandRunner {
    struct Call {
        let executable: URL
        let arguments: [String]
    }

    var cliLookup = ""
    var aliasModels: [String: String] = [:]
    var failingAliases: Set<String> = []
    var errorAliases: Set<String> = []
    var arrayOutputAliases: Set<String> = []
    var calls: [Call] = []
    var aliasesCalled: [String] = []

    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval) throws -> CommandResult {
        if arguments == ["--version"] { return CommandResult(exitCode: 1, stdout: "", stderr: "") }
        calls.append(Call(executable: executable, arguments: arguments))
        if executable.path == "/bin/zsh" {
            return CommandResult(exitCode: 0, stdout: cliLookup, stderr: "")
        }
        if executable.lastPathComponent == "claude", let index = arguments.firstIndex(of: "--model"), arguments.indices.contains(index + 1) {
            let alias = arguments[index + 1]
            aliasesCalled.append(alias)
            if failingAliases.contains(alias) {
                return CommandResult(exitCode: 1, stdout: "", stderr: "alias failed")
            }
            if errorAliases.contains(alias) {
                return CommandResult(exitCode: 0, stdout: #"{"type":"result","is_error":true,"modelUsage":{"should-not-register":{}}}"#, stderr: "")
            }
            if let model = aliasModels[alias] {
                if arrayOutputAliases.contains(alias) {
                    return CommandResult(exitCode: 0, stdout: #"[{"type":"system","subtype":"init","model":"\#(model)"},{"type":"assistant"},{"type":"result","is_error":false,"modelUsage":{"\#(model)":{"inputTokens":1}}}]"#, stderr: "")
                }
                return CommandResult(exitCode: 0, stdout: #"{"type":"result","is_error":false,"modelUsage":{"\#(model)":{"inputTokens":1}}}"#, stderr: "")
            }
        }
        return CommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private final class ClaudeNotifier: Notifier {
    var messages: [String] = []
    func notify(_ message: String) { messages.append(message) }
}

private struct ClaudeRecorder: Recorder {
    func record(workingFolder: URL, runFolder: URL) throws {}
}

private struct ClaudePoster: Poster {
    func post(text: String, video: URL, draftOnly: Bool, runID: String, onManualPost: @escaping (ManualPostEvent) -> Void) throws -> PostResult {
        .posted(URL(string: "https://x.com/owner/status/123")!)
    }
}
