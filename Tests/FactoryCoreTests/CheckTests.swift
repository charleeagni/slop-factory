import Foundation
import Testing
@testable import FactoryCore

struct CheckTests {
    @Test func firstLaunchWithNoCLILeavesStoreMissingAndRunsNoCheck() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-existing","visibility":"list"}]}"#)

        let launch = try FactoryCore.firstLaunchSetup(
            commandRunner: fixture.runner,
            homeFolder: fixture.home,
            appDataFolder: fixture.data,
            clock: { fixture.now }
        )
        try fixture.check(watchedProviders: launch?.foundProviders ?? [])

        #expect(launch?.foundProviders.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
        #expect(fixture.runner.commands.isEmpty)
        #expect(fixture.recorder.recordedWorkingFolders.isEmpty)
        #expect(fixture.poster.posts.isEmpty)
    }

    @Test func firstLaunchSeedsOnlyFoundProviderThenNextCheckRunsNewModel() throws {
        let fixture = try Fixture()
        fixture.runner.cliPathsOutput = "claude=\ncodex=/usr/local/bin/codex\n"
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"}]}"#)
        try #"{"additionalModelOptionsCache":[{"value":"claude-existing"}]}"#
            .write(to: fixture.home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        let launch = try FactoryCore.firstLaunchSetup(
            commandRunner: fixture.runner,
            homeFolder: fixture.home,
            appDataFolder: fixture.data,
            clock: { fixture.now }
        )

        #expect(launch?.foundProviders == [.openAI])
        #expect(try fixture.store().seenModels == ["gpt-old"])
        let baselineIDs = try fixture.store().seenModels
        let onboarding = try Onboarding.resume(appDataFolder: fixture.data, presentLogin: {}, register: { .enabled })
        #expect(onboarding.isComplete)
        #expect(try fixture.store().seenModels == baselineIDs)
        #expect(fixture.runner.commands.isEmpty)
        #expect(fixture.poster.posts.isEmpty)
        #expect(try FactoryCore.firstLaunchSetup(
            commandRunner: fixture.runner,
            homeFolder: fixture.home,
            appDataFolder: fixture.data,
            clock: { fixture.now }
        )?.foundProviders == nil)

        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"},{"slug":"gpt-new","visibility":"list"}]}"#)
        try fixture.check(watchedProviders: launch?.foundProviders ?? [])

        #expect(fixture.runner.commands.map { $0.arguments.contains("gpt-new") } == [true])
        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().seenModels == ["gpt-new", "gpt-old"])
        #expect(try FactoryCore.statusSnapshot(appDataFolder: fixture.data).claudeCount == 0)
    }

    @Test func installingCLIOnLaterLaunchSeedsExistingModelsWithoutPosting() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-existing","visibility":"list"}]}"#)
        let first = try FactoryCore.firstLaunchSetup(
            commandRunner: fixture.runner,
            homeFolder: fixture.home,
            appDataFolder: fixture.data,
            clock: { fixture.now }
        )
        #expect(first?.foundProviders.isEmpty == true)

        fixture.runner.cliPathsOutput = "claude=\ncodex=/usr/local/bin/codex\n"
        let next = try FactoryCore.firstLaunchSetup(
            commandRunner: fixture.runner,
            homeFolder: fixture.home,
            appDataFolder: fixture.data,
            clock: { fixture.now }
        )

        #expect(next?.foundProviders == [.openAI])
        #expect(try fixture.store().seenModels == ["gpt-existing"])
        #expect(fixture.runner.commands.isEmpty)
        #expect(fixture.poster.posts.isEmpty)
    }

    @Test func statusSnapshotShowsWatchedProvidersAndLatestPostAfterChecks() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"}]}"#)
        try #"{"additionalModelOptionsCache":[{"value":"claude-sonnet-5"}]}"#
            .write(to: fixture.home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        try fixture.check()

        var status = try FactoryCore.statusSnapshot(appDataFolder: fixture.data)
        #expect(status.claudeCount == 1)
        #expect(status.openAICount == 1)
        #expect(status.latestPost == nil)

        fixture.now = Date(timeIntervalSince1970: 1234)
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"},{"slug":"gpt-new","visibility":"list"}]}"#)
        try fixture.check()

        status = try FactoryCore.statusSnapshot(appDataFolder: fixture.data)
        #expect(status.claudeCount == 1)
        #expect(status.openAICount == 2)
        #expect(status.latestPost?.model == "gpt-new")
        #expect(status.latestPost?.postedAt == fixture.now)
        #expect(status.latestPost?.url == URL(string: "https://x.com/owner/status/123"))
    }

    @Test func firstCheckSeedsVisibleModelsWithoutNotification() throws {
        let fixture = try Fixture()
        try fixture.cache("""
        {"models":[{"slug":"gpt-new","visibility":"list"},{"slug":"codex-auto-review","visibility":"hide"}]}
        """)

        try fixture.check()

        #expect(fixture.notifications.messages.isEmpty)
        #expect(try fixture.store().seenModels == ["gpt-new"])
        #expect(try fixture.store().lastCheck == fixture.now)
    }

    @Test func laterCheckNotifiesEachNewVisibleModelAndPersistsIt() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"}]}"#)
        try fixture.check()
        fixture.now = Date(timeIntervalSince1970: 1234)
        try fixture.cache("""
        {"models":[{"slug":"gpt-old","visibility":"list"},{"slug":"gpt-new","visibility":"list"},{"slug":"codex-auto-review","visibility":"hidden"}]}
        """)

        try fixture.check()

        #expect(fixture.notifications.messages == ["Slop posted: gpt-new"])
        #expect(try fixture.store().seenModels == ["gpt-new", "gpt-old"])
        #expect(try fixture.store().lastCheck == fixture.now)
        let run = try #require(fixture.runFolders().first)
        #expect(try String(contentsOf: run.appendingPathComponent("prompt.txt"), encoding: .utf8).isEmpty == false)
        #expect(FileManager.default.fileExists(atPath: run.appendingPathComponent("working").path))
        #expect(FileManager.default.fileExists(atPath: run.appendingPathComponent("build.log").path))
        #expect(fixture.runner.commands.count == 1)
        #expect(fixture.runner.commands[0].arguments.prefix(4) == ["codex", "exec", "-m", "gpt-new"])
        #expect(fixture.runner.commands[0].arguments.contains("approval_policy=never"))
        #expect(fixture.runner.commands[0].arguments.contains("model_reasoning_effort=\"medium\""))
        #expect(fixture.runner.commands[0].arguments.contains("workspace-write"))
        #expect(fixture.runner.commands[0].workingFolder.resolvingSymlinksInPath() == run.appendingPathComponent("working").resolvingSymlinksInPath())
        #expect(fixture.runner.commands[0].timeout == 1200)
    }

    @Test func missingAndUnreadableCacheDoNotNotifyOrCrash() throws {
        let fixture = try Fixture()
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))

        try fixture.cache("invalid JSON")
        try fixture.check()
        #expect(fixture.notifications.messages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func unreadableCachePathDoesNotNotifyOrCrash() throws {
        let fixture = try Fixture()
        try FileManager.default.createDirectory(at: fixture.cacheURL, withIntermediateDirectories: false)

        try fixture.check()

        #expect(fixture.notifications.messages.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func failedBuildIsNotPostedAndRetriesOnNextCheck() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        fixture.runner.results = [CommandResult(exitCode: 3, stdout: "out", stderr: "broken")]
        try fixture.cache(#"{"models":[{"slug":"gpt-fail","visibility":"list"}]}"#)
        #expect(throws: (any Error).self) { try fixture.check() }
        #expect(try fixture.store().seenModels.isEmpty)
        #expect(fixture.notifications.messages == ["New model detected: gpt-fail. Build failed. See build.log in the run folder."])
        let run = try #require(fixture.runFolders().first)
        #expect(try String(contentsOf: run.appendingPathComponent("build.log"), encoding: .utf8).contains("broken"))
        #expect(fixture.recorder.recordedWorkingFolders.isEmpty)
        #expect(fixture.poster.posts.isEmpty)
        #expect(try (fixture.store().manualPosts ?? [:]).isEmpty)

        try fixture.check()
        #expect(try fixture.store().seenModels == ["gpt-fail"])
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func successfulBuildIsRecordedBeforeModelIsSeen() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-demo","visibility":"list"}]}"#)

        try fixture.check()

        let run = try #require(fixture.runFolders().first)
        #expect(fixture.recorder.recordedWorkingFolders.map { $0.resolvingSymlinksInPath() } == [run.appendingPathComponent("working").resolvingSymlinksInPath()])
        #expect(try fixture.store().seenModels == ["gpt-demo"])
    }

    @Test func newModelPostsRecordedVideoAndSavesItsURL() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-demo","visibility":"list"}]}"#)

        try fixture.check()

        let run = try #require(fixture.runFolders().first)
        #expect(fixture.poster.posts.count == 1)
        #expect(fixture.poster.posts[0].text == "We are so cooked, gpt-demo just one-shotted this without even me asking for it! AGI is here!\n\nhttps://github.com/example/slop-factory")
        #expect(fixture.poster.posts[0].video.lastPathComponent == "demo.mp4")
        #expect(fixture.poster.posts[0].video.deletingLastPathComponent().lastPathComponent == run.lastPathComponent)
        #expect(try String(contentsOf: run.appendingPathComponent("post-url.txt"), encoding: .utf8) == "https://x.com/owner/status/123")
    }

    @Test func nextPostLinksPreviousPostForSameProvider() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-a","visibility":"list"}]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-a","visibility":"list"},{"slug":"gpt-b","visibility":"list"}]}"#)

        try fixture.check()

        #expect(fixture.poster.posts.count == 2)
        #expect(fixture.poster.posts[1].text == "We are so cooked, gpt-b just one-shotted this without even me asking for it! AGI is here!\n\nPrevious post: https://x.com/owner/status/123\n\nhttps://github.com/example/slop-factory")
        #expect(try fixture.store().latestPosts?["openai"] == "https://x.com/owner/status/123")
    }

    @Test func claudePostLinksPreviousOpenAIPost() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try #"{"additionalModelOptionsCache":[]}"#
            .write(to: fixture.home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-first","visibility":"list"}]}"#)
        try fixture.check()
        try #"{"additionalModelOptionsCache":[{"value":"claude-next"}]}"#
            .write(to: fixture.home.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

        try fixture.check()

        #expect(fixture.poster.posts.last?.text == "We are so cooked, claude-next just one-shotted this without even me asking for it! AGI is here!\n\nPrevious post: https://x.com/owner/status/123\n\nhttps://github.com/example/slop-factory")
    }

    @Test func legacyStoreWithoutSourceStateSeedsQuietlyThenDetectsNewModels() throws {
        let fixture = try Fixture()
        try FileManager.default.createDirectory(at: fixture.data, withIntermediateDirectories: true)
        try #"{"seenModels":["gpt-old"],"lastCheck":0}"#
            .write(to: fixture.data.appendingPathComponent("seen.json"), atomically: true, encoding: .utf8)
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"},{"slug":"gpt-unseen","visibility":"list"}]}"#)

        try fixture.check()
        #expect(fixture.poster.posts.isEmpty)

        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"},{"slug":"gpt-unseen","visibility":"list"},{"slug":"gpt-new","visibility":"list"}]}"#)
        try fixture.check()
        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().seenModels == ["gpt-new", "gpt-old", "gpt-unseen"])
    }

    @Test func failedPostNotifiesAndLeavesModelUnseenForRetry() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-retry","visibility":"list"}]}"#)
        fixture.poster.failNext = true

        #expect(throws: (any Error).self) { try fixture.check() }
        #expect(try fixture.store().seenModels.isEmpty)
        #expect(fixture.notifications.messages.contains { $0.contains("Post failed") })

        try fixture.check()
        #expect(try fixture.store().seenModels == ["gpt-retry"])
        #expect(fixture.poster.posts.count == 2)
    }

    @Test func confirmedPostSurvivesRunURLWriteFailureWithoutRetryingPost() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-saved-fail","visibility":"list"}]}"#)
        fixture.poster.rejectURLWrite = true

        try fixture.check()

        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().seenModels == ["gpt-saved-fail"])
        #expect(try fixture.store().latestPosts?["openai"] == "https://x.com/owner/status/123")
        #expect(fixture.notifications.postedURLs == [URL(string: "https://x.com/owner/status/123")!])
        #expect(fixture.notifications.messages.contains { $0.localizedCaseInsensitiveContains("saving post url failed") })

        try fixture.check()
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func savedRunURLRecoversConfirmedPostAfterSeenStoreFailureAndRestart() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        let originalStore = try Data(contentsOf: fixture.storeURL)
        try fixture.cache(#"{"models":[{"slug":"gpt-recover","visibility":"list"}]}"#)
        fixture.poster.onPost = {
            try FileManager.default.removeItem(at: fixture.storeURL)
            try FileManager.default.createDirectory(at: fixture.storeURL, withIntermediateDirectories: false)
        }

        #expect(throws: (any Error).self) { try fixture.check() }
        #expect(fixture.poster.posts.count == 1)
        #expect(fixture.notifications.postedURLs == [URL(string: "https://x.com/owner/status/123")!])
        #expect(fixture.notifications.messages.contains { $0.localizedCaseInsensitiveContains("saving") })
        let confirmedRun = try #require(fixture.runFolders().first)
        #expect(try String(contentsOf: confirmedRun.appendingPathComponent("post-url.txt"), encoding: .utf8) == "https://x.com/owner/status/123")

        try FileManager.default.removeItem(at: fixture.storeURL)
        try originalStore.write(to: fixture.storeURL)
        fixture.poster.onPost = nil

        try fixture.check()

        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().seenModels == ["gpt-recover"])
        #expect(try fixture.store().latestPosts?["openai"] == "https://x.com/owner/status/123")
    }

    @Test func confirmedRetryPostSurvivesRunURLWriteFailureWithoutPostingAgain() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-retry-save","visibility":"list"}]}"#)
        fixture.poster.failNext = true
        #expect(throws: (any Error).self) { try fixture.check() }
        let runID = try #require(fixture.store().manualPosts?.keys.first)
        fixture.poster.rejectURLWrite = true

        try fixture.check()

        #expect(fixture.poster.posts.count == 2)
        #expect(try fixture.store().manualPosts?[runID]?.status == .completed)
        #expect(try fixture.store().seenModels == ["gpt-retry-save"])
        #expect(fixture.notifications.postedURLs == [URL(string: "https://x.com/owner/status/123")!])
        #expect(fixture.notifications.messages.contains { $0.localizedCaseInsensitiveContains("saving post url failed") })

        try fixture.check()
        #expect(fixture.poster.posts.count == 2)
    }

    @Test func failedRunWithSavedURLIsReconciledWithoutPostingAgain() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-reconcile","visibility":"list"}]}"#)
        fixture.poster.failNext = true
        #expect(throws: (any Error).self) { try fixture.check() }
        let runID = try #require(fixture.store().manualPosts?.keys.first)
        let run = try #require(fixture.runFolders().first)
        try "https://x.com/owner/status/789".write(to: run.appendingPathComponent("post-url.txt"), atomically: true, encoding: .utf8)

        try fixture.check()

        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().manualPosts?[runID]?.status == .completed)
        #expect(try fixture.store().latestPosts?["openai"] == "https://x.com/owner/status/789")
    }

    @Test func draftReadyAsksOwnerToPostWithoutSavingAPostURL() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-draft","visibility":"list"}]}"#)
        fixture.poster.draftOnlyResult = true
        fixture.draftOnly = true

        try fixture.check()

        #expect(fixture.poster.draftOnlyArguments == [true])
        #expect(fixture.notifications.messages == ["Draft ready for gpt-draft. Click Post in X when you're ready."])
        #expect(try fixture.store().seenModels == ["gpt-draft"])
        #expect(try fixture.store().manualPosts?.values.first?.status == .pending)
        let run = try #require(fixture.runFolders().first)
        #expect(!FileManager.default.fileExists(atPath: run.appendingPathComponent("post-url.txt").path))
        try fixture.check()
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func confirmedManualFailureRetriesOnNextCheckAndRecordsSuccessfulHistory() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-manual-retry","visibility":"list"}]}"#)
        fixture.draftOnly = true
        fixture.poster.draftOnlyResult = true
        try fixture.check()
        let originalVideo = try #require(fixture.poster.posts.first?.video)
        let runID = try #require(fixture.store().manualPosts?.keys.first)

        fixture.poster.failManualPost(step: "Post", message: "X rejected this post")

        #expect(try fixture.store().manualPosts?[runID]?.status == .failed)
        #expect(fixture.notifications.messages.contains { $0.contains("Post") && $0.contains("X rejected this post") })
        fixture.draftOnly = false
        fixture.poster.draftOnlyResult = false
        try fixture.check()

        #expect(fixture.poster.posts.map(\.video) == [originalVideo, originalVideo])
        #expect(try fixture.store().manualPosts?[runID]?.status == .completed)
        #expect(try fixture.store().latestPosts?["openai"] == "https://x.com/owner/status/123")
        #expect(fixture.notifications.postedURLs.last == URL(string: "https://x.com/owner/status/123"))
    }

    @Test func uncertainManualPostIsNotRetriedAndDraftOnlyRetryWaitsForOwner() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        fixture.draftOnly = true
        fixture.poster.draftOnlyResult = true
        try fixture.cache(#"{"models":[{"slug":"gpt-unsure","visibility":"list"}]}"#)
        try fixture.check()
        let unsureRun = try #require(fixture.poster.manualRunID)
        fixture.poster.manualPost?(ManualPostEvent(runID: unsureRun, outcome: .uncertain(step: "post acknowledgement", message: "No link yet")))
        try fixture.cache(#"{"models":[{"slug":"gpt-unsure","visibility":"list"},{"slug":"gpt-fail","visibility":"list"}]}"#)
        try fixture.check()
        let failedRun = try #require(fixture.poster.manualRunID)
        fixture.poster.failManualPost()

        try fixture.check()
        try fixture.check()

        #expect(try fixture.store().manualPosts?[unsureRun]?.status == .uncertain)
        #expect(try fixture.store().manualPosts?[unsureRun]?.failedStep == "post acknowledgement")
        #expect(try fixture.store().manualPosts?[failedRun]?.status == .pending)
        #expect(fixture.poster.posts.count == 3)
        #expect(fixture.poster.draftOnlyArguments == [true, true, true])
        #expect(fixture.notifications.messages.contains { $0.contains("uncertain") && $0.contains("gpt-unsure") })
    }

    @Test func manualPostAfterDraftReadySavesURLAndLinksNextPost() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-draft","visibility":"list"}]}"#)
        fixture.poster.draftOnlyResult = true
        fixture.draftOnly = true
        try fixture.check()

        let run = try #require(fixture.runFolders().first)
        fixture.poster.completeManualPost(URL(string: "https://x.com/owner/status/456")!)

        #expect(try String(contentsOf: run.appendingPathComponent("post-url.txt"), encoding: .utf8) == "https://x.com/owner/status/456")
        #expect(try fixture.store().latestPosts?["openai"] == "https://x.com/owner/status/456")
        #expect(fixture.notifications.messages.last == "Slop posted: gpt-draft")

        try fixture.cache(#"{"models":[{"slug":"gpt-draft","visibility":"list"},{"slug":"gpt-next","visibility":"list"}]}"#)
        fixture.poster.draftOnlyResult = false
        fixture.draftOnly = false
        try fixture.check()
        #expect(fixture.poster.posts.last?.text.contains("Previous post: https://x.com/owner/status/456") == true)
    }

    @Test func manualPostBeforeDraftReadyReturnDoesNotAskOwnerToPostAgain() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-draft","visibility":"list"}]}"#)
        fixture.poster.draftOnlyResult = true
        fixture.poster.completeBeforeReturn = URL(string: "https://x.com/owner/status/456")!
        fixture.draftOnly = true

        try fixture.check()

        let run = try #require(fixture.runFolders().first)
        #expect(fixture.notifications.messages == ["Slop posted: gpt-draft"])
        #expect(try String(contentsOf: run.appendingPathComponent("post-url.txt"), encoding: .utf8) == "https://x.com/owner/status/456")
        #expect(try fixture.store().seenModels == ["gpt-draft"])
    }

    @Test func manualPostDuringLaterCheckPreservesSeenModels() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-draft","visibility":"list"}]}"#)
        fixture.poster.draftOnlyResult = true
        fixture.draftOnly = true
        try fixture.check()

        fixture.runner.onRun = {
            fixture.poster.completeManualPost(URL(string: "https://x.com/owner/status/456")!)
        }
        fixture.poster.draftOnlyResult = false
        fixture.draftOnly = false
        try fixture.cache(#"{"models":[{"slug":"gpt-draft","visibility":"list"},{"slug":"gpt-next","visibility":"list"}]}"#)
        try fixture.check()

        #expect(try fixture.store().seenModels == ["gpt-draft", "gpt-next"])
        #expect(fixture.poster.posts.last?.text.contains("Previous post: https://x.com/owner/status/456") == true)
    }

    @Test func recordingFailureNotifiesAndRetriesModel() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-retry","visibility":"list"}]}"#)
        fixture.recorder.failNext = true

        #expect(throws: (any Error).self) { try fixture.check() }
        #expect(try fixture.store().seenModels.isEmpty)
        #expect(fixture.notifications.messages.contains { $0.contains("gpt-retry") && $0.localizedCaseInsensitiveContains("record") })
        #expect(fixture.poster.posts.isEmpty)

        try fixture.check()
        #expect(try fixture.store().seenModels == ["gpt-retry"])
        #expect(fixture.recorder.recordedWorkingFolders.count == 2)
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func timedOutBuildIsNotPostedOrSeen() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        fixture.runner.results = [CommandResult(exitCode: 9, stdout: "", stderr: "", timedOut: true)]
        try fixture.cache(#"{"models":[{"slug":"gpt-slow","visibility":"list"}]}"#)
        #expect(throws: (any Error).self) { try fixture.check() }
        #expect(try fixture.store().seenModels.isEmpty)
        #expect(fixture.notifications.messages == ["New model detected: gpt-slow. Build failed (timed out). See build.log in the run folder."])
        let run = try #require(fixture.runFolders().first)
        #expect(FileManager.default.fileExists(atPath: run.appendingPathComponent("build.log").path))
        #expect(fixture.recorder.recordedWorkingFolders.isEmpty)
        #expect(fixture.poster.posts.isEmpty)
    }

    @Test func crashBeforeCompletionRetriesNextCheck() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-retry","visibility":"list"}]}"#)
        fixture.runner.crashNext = true
        #expect(throws: (any Error).self) { try fixture.check() }
        #expect(try fixture.store().seenModels.isEmpty)
        try fixture.check()
        #expect(try fixture.store().seenModels == ["gpt-retry"])
        #expect(fixture.runner.commands.count == 2)
    }

    @Test func twoModelsRunSequentially() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"gpt-b","visibility":"list"},{"slug":"gpt-a","visibility":"list"}]}"#)
        try fixture.check()
        #expect(fixture.runner.commands.map { $0.arguments[3] } == ["gpt-a", "gpt-b"])
        #expect(fixture.runner.maximumActive == 1)
        #expect(fixture.runFolders().count == 2)
        #expect(try fixture.store().seenModels == ["gpt-a", "gpt-b"])
    }

    @Test func slopNowBuildsAndPostsAKnownModelWithoutAnyNewModel() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-old","visibility":"list"}]}"#)
        try fixture.check()
        #expect(try FactoryCore.statusSnapshot(appDataFolder: fixture.data).models == ["gpt-old"])
        fixture.now = Date(timeIntervalSince1970: 1234)

        try FactoryCore.slopNow(model: "gpt-old", commandRunner: fixture.runner, appDataFolder: fixture.data, notifier: fixture.notifications, clock: { fixture.now }, recorder: fixture.recorder, poster: fixture.poster, draftOnly: false, repositoryURL: URL(string: "https://github.com/example/slop-factory")!)

        #expect(fixture.runner.commands.map { $0.arguments[3] } == ["gpt-old"])
        #expect(fixture.poster.posts.count == 1)
        #expect(fixture.notifications.messages == ["Slop posted: gpt-old"])
        let status = try FactoryCore.statusSnapshot(appDataFolder: fixture.data)
        #expect(status.latestPost?.model == "gpt-old")
        #expect(status.latestPost?.postedAt == fixture.now)
        #expect(try fixture.store().seenModels == ["gpt-old"])
        #expect(try fixture.store().lastCheck == Date(timeIntervalSince1970: 1000))
    }

    @Test func failedSlopNowPostRetriesRecordedDemoOnNextCheck() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        let originalCheckTime = try fixture.store().lastCheck
        fixture.poster.failNext = true

        #expect(throws: (any Error).self) {
            try FactoryCore.slopNow(model: "gpt-known", commandRunner: fixture.runner, appDataFolder: fixture.data, notifier: fixture.notifications, clock: { fixture.now }, recorder: fixture.recorder, poster: fixture.poster, draftOnly: false, repositoryURL: URL(string: "https://github.com/example/slop-factory")!)
        }
        let recordedVideo = try #require(fixture.poster.posts.first?.video)
        let runID = recordedVideo.deletingLastPathComponent().lastPathComponent
        #expect(try fixture.store().seenModels == ["gpt-known"])
        #expect(try fixture.store().lastCheck == originalCheckTime)

        try fixture.check()

        #expect(fixture.poster.posts.map(\.video) == [recordedVideo, recordedVideo])
        #expect(fixture.runner.commands.count == 1)
        #expect(fixture.recorder.recordedWorkingFolders.count == 1)
        #expect(try fixture.store().seenModels == ["gpt-known"])
        #expect(try fixture.store().manualPosts?[runID]?.status == .completed)
    }

    @Test func failedPostWithNoRecordableOutputIsNotRetried() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        fixture.poster.failNext = true

        #expect(throws: (any Error).self) {
            try FactoryCore.slopNow(model: "gpt-known", commandRunner: fixture.runner, appDataFolder: fixture.data, notifier: fixture.notifications, clock: { fixture.now }, recorder: fixture.recorder, poster: fixture.poster, draftOnly: false, repositoryURL: URL(string: "https://github.com/example/slop-factory")!)
        }
        let video = try #require(fixture.poster.posts.first?.video)
        let run = video.deletingLastPathComponent()
        try FileManager.default.removeItem(at: run.appendingPathComponent("working/index.html"))

        try fixture.check()

        #expect(fixture.poster.posts.count == 1)
        #expect(try fixture.store().manualPosts?[run.lastPathComponent]?.status == .failed)

        try "<!doctype html><title>fixture</title>".write(to: run.appendingPathComponent("working/index.html"), atomically: true, encoding: .utf8)
        try "Exit code: 1\nTimed out: false\n".write(to: run.appendingPathComponent("build.log"), atomically: true, encoding: .utf8)
        try fixture.check()
        #expect(fixture.poster.posts.count == 1)
    }

    @Test func failedSlopNowPostRetriesAfterRelaunch() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[{"slug":"gpt-known","visibility":"list"}]}"#)
        try fixture.check()
        fixture.poster.failNext = true
        #expect(throws: (any Error).self) {
            try FactoryCore.slopNow(model: "gpt-known", commandRunner: fixture.runner, appDataFolder: fixture.data, notifier: fixture.notifications, clock: { fixture.now }, recorder: fixture.recorder, poster: fixture.poster, draftOnly: false, repositoryURL: URL(string: "https://github.com/example/slop-factory")!)
        }
        let originalVideo = try #require(fixture.poster.posts.first?.video)
        let runID = originalVideo.deletingLastPathComponent().lastPathComponent
        let notifications = FakeNotifier()
        let relaunchRunner = FakeRunner()
        let relaunchRecorder = FakeRecorder()
        let relaunchPoster = FakePoster()

        try FactoryCore.runOneCheck(commandRunner: relaunchRunner, homeFolder: fixture.home, appDataFolder: fixture.data, notifier: notifications, clock: { fixture.now }, recorder: relaunchRecorder, poster: relaunchPoster, draftOnly: false, repositoryURL: URL(string: "https://github.com/example/slop-factory")!, watchedProviders: [.openAI])

        #expect(relaunchPoster.posts.map(\.video) == [originalVideo])
        #expect(relaunchRunner.commands.isEmpty)
        #expect(relaunchRecorder.recordedWorkingFolders.isEmpty)
        #expect(try fixture.store().manualPosts?[runID]?.status == .completed)
    }

    @Test func claudeModelUsesHeadlessPermissionSkippingCommand() throws {
        let fixture = try Fixture()
        try fixture.cache(#"{"models":[]}"#)
        try fixture.check()
        try fixture.cache(#"{"models":[{"slug":"claude-sonnet-5","visibility":"list"}]}"#)
        try fixture.check()
        let arguments = try #require(fixture.runner.commands.first).arguments
        #expect(arguments.prefix(4) == ["claude", "-p", "--model", "claude-sonnet-5"])
        #expect(arguments.contains("--effort"))
        #expect(arguments.contains("medium"))
        #expect(fixture.runner.environments.last?["CLAUDE_CODE_EFFORT_LEVEL"] == "medium")
        #expect(arguments.contains("--dangerously-skip-permissions"))
    }
}

final class Fixture {
    let root: URL
    let home: URL
    let data: URL
    let notifications = FakeNotifier()
    let runner = FakeRunner()
    let recorder = FakeRecorder()
    let poster = FakePoster()
    var draftOnly = false
    var now = Date(timeIntervalSince1970: 1000)
    var storeURL: URL { data.appendingPathComponent("seen.json") }
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

    func check(watchedProviders: Set<ModelProvider> = [.claude, .openAI]) throws {
        try FactoryCore.runOneCheck(commandRunner: runner, homeFolder: home, appDataFolder: data, notifier: notifications, clock: { self.now }, recorder: recorder, poster: poster, draftOnly: draftOnly, repositoryURL: URL(string: "https://github.com/example/slop-factory")!, watchedProviders: watchedProviders)
    }

    func runFolders() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: data.appendingPathComponent("runs"), includingPropertiesForKeys: nil)) ?? []
    }

    func store() throws -> SeenStore {
        try JSONDecoder().decode(SeenStore.self, from: Data(contentsOf: storeURL))
    }
}

final class FakeRunner: EnvironmentCommandRunner {
    struct Command { let arguments: [String]; let workingFolder: URL; let timeout: TimeInterval }
    var commands: [Command] = []
    var environments: [[String: String]] = []
    var cliPathsOutput = ""
    var results: [CommandResult] = []
    var crashNext = false
    var onRun: (() -> Void)?
    var maximumActive = 0
    private var active = 0
    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        if executable.path != "/bin/zsh" && arguments != ["--version"] { environments.append(environment) }
        return try run(executable: executable, arguments: arguments, workingFolder: workingFolder, timeout: timeout)
    }
    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval) throws -> CommandResult {
        if executable.path == "/bin/zsh" {
            return CommandResult(exitCode: 0, stdout: cliPathsOutput, stderr: "")
        }
        if arguments == ["--version"] { return CommandResult(exitCode: 1, stdout: "", stderr: "") }
        commands.append(Command(arguments: arguments, workingFolder: workingFolder, timeout: timeout))
        onRun?()
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        if crashNext { crashNext = false; throw TestCrash() }
        return results.isEmpty ? CommandResult(exitCode: 0, stdout: "ok", stderr: "") : results.removeFirst()
    }
}

struct TestCrash: Error {}

final class FakeRecorder: Recorder {
    var recordedWorkingFolders: [URL] = []
    var failNext = false

    func record(workingFolder: URL, runFolder: URL) throws {
        recordedWorkingFolders.append(workingFolder)
        if failNext {
            failNext = false
            throw TestCrash()
        }
        try "<!doctype html><title>fixture</title>".write(to: workingFolder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
    }
}

final class FakeNotifier: Notifier {
    var messages: [String] = []
    var postedURLs: [URL] = []
    func notify(_ message: String) { messages.append(message) }
    func notifyPosted(_ message: String, url: URL) { messages.append(message); postedURLs.append(url) }
}

final class FakePoster: Poster {
    struct Post { let text: String; let video: URL }
    var posts: [Post] = []
    var draftOnlyArguments: [Bool] = []
    var draftOnlyResult = false
    var completeBeforeReturn: URL?
    var failNext = false
    var manualPost: ((ManualPostEvent) -> Void)?
    var manualRunID: String?
    var rejectURLWrite = false
    var onPost: (() throws -> Void)?
    func completeManualPost(_ url: URL) {
        guard let manualPost, let manualRunID else { return }
        manualPost(ManualPostEvent(runID: manualRunID, outcome: .posted(url)))
    }
    func failManualPost(step: String = "Post", message: String = "X rejected the post") {
        guard let manualPost, let manualRunID else { return }
        manualPost(ManualPostEvent(runID: manualRunID, outcome: .failed(step: step, message: message)))
    }
    func post(text: String, video: URL, draftOnly: Bool, runID: String, onManualPost: @escaping (ManualPostEvent) -> Void) throws -> PostResult {
        posts.append(Post(text: text, video: video))
        draftOnlyArguments.append(draftOnly)
        manualPost = onManualPost
        manualRunID = runID
        if failNext { failNext = false; throw TestCrash() }
        try onPost?()
        if draftOnlyResult {
            if let completeBeforeReturn { onManualPost(ManualPostEvent(runID: runID, outcome: .posted(completeBeforeReturn))) }
            return .draftReady(runID: runID)
        }
        if rejectURLWrite {
            try FileManager.default.createDirectory(at: video.deletingLastPathComponent().appendingPathComponent("post-url.txt"), withIntermediateDirectories: false)
        }
        return .posted(URL(string: "https://x.com/owner/status/123")!)
    }
}
