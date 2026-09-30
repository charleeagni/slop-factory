import Foundation
import Testing
@testable import FactoryCore

struct RunResumeTests {
    private let repository = URL(string: "https://github.com/example/slop-factory")!

    @Test func interruptedBuildResumesTheSameAgentSessionInTheSameFolder() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-new","visibility":"list"}]}"#)
        fixture.runner.crashNext = true
        #expect(throws: (any Error).self) { try fixture.check() }

        try fixture.check()

        #expect(fixture.runFolders().count == 1)
        let commands = fixture.runner.commands
        #expect(commands.count == 2)
        #expect(commands[0].workingFolder.resolvingSymlinksInPath() == commands[1].workingFolder.resolvingSymlinksInPath())
        #expect(commands[1].arguments.prefix(4) == ["codex", "exec", "resume", "--last"])
        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().seenModels == ["gpt-new"])
        #expect(RunState.read(runFolder: try #require(fixture.runFolders().first))?.stage == .done)
    }

    @Test func claudeBuildResumesItsSavedSessionID() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        fixture.runner.crashNext = true
        #expect(throws: (any Error).self) { try slopNow(fixture, "claude-test") }

        try slopNow(fixture, "claude-test")

        let first = fixture.runner.commands[0].arguments, second = fixture.runner.commands[1].arguments
        let session = try #require(first.firstIndex(of: "--session-id")).advanced(by: 1)
        #expect(second[try #require(second.firstIndex(of: "--resume")) + 1] == first[session])
        #expect(fixture.runFolders().count == 1)
    }

    @Test func failedResumeFallsBackToAFreshBuildInTheSameFolder() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        fixture.runner.crashNext = true
        #expect(throws: (any Error).self) { try slopNow(fixture, "gpt-known") }
        fixture.runner.results = [CommandResult(exitCode: 1, stdout: "", stderr: "no session")]

        try slopNow(fixture, "gpt-known")

        #expect(fixture.runner.commands.map { $0.arguments[2] } == ["-m", "resume", "-m"])
        #expect(fixture.runFolders().count == 1)
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func runStoppedAfterBuildResumesAtRecordingOnNextCheck() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        fixture.recorder.failNext = true
        #expect(throws: (any Error).self) { try slopNow(fixture, "gpt-known") }

        try fixture.check()

        #expect(fixture.runner.commands.count == 1)
        #expect(fixture.recorder.recordedWorkingFolders.count == 2)
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func runGivesUpAfterMaxAttempts() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        fixture.runner.results = Array(repeating: CommandResult(exitCode: 1, stdout: "", stderr: ""), count: 20)
        #expect(throws: (any Error).self) { try slopNow(fixture, "gpt-known") }
        for _ in 0..<5 { try fixture.check() }

        #expect(!FactoryCore.hasUnfinishedRuns(appDataFolder: fixture.data))
        #expect(RunState.read(runFolder: try #require(fixture.runFolders().first))?.attempts == RunState.maxAttempts)
    }

    private func slopNow(_ fixture: Fixture, _ model: String) throws {
        try FactoryCore.slopNow(model: model, commandRunner: fixture.runner, appDataFolder: fixture.data, notifier: fixture.notifications, clock: { fixture.now }, recorder: fixture.recorder, poster: fixture.poster, draftOnly: false, repositoryURL: repository)
    }
}
