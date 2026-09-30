import Foundation

extension FactoryCore {
    private enum BuildFailure: LocalizedError {
        case timedOut
        case exited(Int32)

        var errorDescription: String? {
            switch self {
            case .timedOut: "The model build timed out."
            case .exited(let code): "The model build exited with code \(code)."
            }
        }
    }

    static func retryFailedManualPosts(
        appDataFolder: URL, notifier: any Notifier, clock: @escaping () -> Date,
        poster: any Poster, draftOnly: Bool
    ) throws {
        let storeURL = appDataFolder.appendingPathComponent("seen.json")
        let failed = try storeLock.withLock { try readStore(at: storeURL)?.manualPosts?.values.filter { $0.status == .failed }.sorted { $0.runID < $1.runID } ?? [] }
        for state in failed {
            if let url = savedPostURL(runFolder: URL(fileURLWithPath: state.runFolder)) {
                try storeLock.withLock { try recordConfirmedPost(url, state: state, clock: clock, notifier: notifier, storeURL: storeURL) }
                notifier.notifyPosted("Slop posted: \(state.model)", url: url)
                continue
            }
            let runFolder = URL(fileURLWithPath: state.runFolder)
            let workingFolder = runFolder.appendingPathComponent("working", isDirectory: true)
            guard let buildLog = try? String(contentsOf: runFolder.appendingPathComponent("build.log"), encoding: .utf8),
                  buildLog.hasPrefix("Exit code: 0\nTimed out: false\n") else { continue }
            guard recordablePage(in: workingFolder) != nil else { continue }
            let pending = ManualPostState(runID: state.runID, model: state.model, runFolder: state.runFolder, text: state.text, status: .pending)
            try storeLock.withLock { try saveManualPost(pending, storeURL: storeURL) }
            do {
                let result = try poster.post(
                    text: state.text,
                    video: URL(fileURLWithPath: state.runFolder).appendingPathComponent("demo.mp4"),
                    draftOnly: draftOnly,
                    runID: state.runID,
                    onManualPost: { event in
                        guard event.runID == state.runID else { return }
                        do {
                            try storeLock.withLock {
                                switch event.outcome {
                                case .posted(let url):
                                    try recordConfirmedPost(url, state: state, clock: clock, notifier: notifier, storeURL: storeURL)
                                case .failed(let step, let message):
                                    try saveManualPost(ManualPostState(runID: state.runID, model: state.model, runFolder: state.runFolder, text: state.text, status: .failed, failedStep: step, failure: message), storeURL: storeURL)
                                case .uncertain(let step, let message):
                                    try saveManualPost(ManualPostState(runID: state.runID, model: state.model, runFolder: state.runFolder, text: state.text, status: .uncertain, failedStep: step, failure: message), storeURL: storeURL)
                                }
                            }
                        } catch { notifier.notify("Manual post outcome could not be saved: \(error)") }
                        switch event.outcome {
                        case .posted(let url): notifier.notifyPosted("Slop posted: \(state.model)", url: url)
                        case .failed(let step, let message): notifier.notify("Manual post failed for \(state.model) at \(step): \(message). It will retry on the next check.")
                        case .uncertain(let step, let message): notifier.notify("Manual post outcome for \(state.model) is uncertain at \(step): \(message). Check X before retrying.")
                        }
                    }
                )
                switch result {
                case .posted(let url):
                    // X confirmed the post; a bookkeeping failure must not send it back to .failed and repost.
                    do {
                        try storeLock.withLock { try recordConfirmedPost(url, state: state, clock: clock, notifier: notifier, storeURL: storeURL) }
                    } catch {
                        notifier.notify("Slop posted for \(state.model): \(url.absoluteString). Saving its completed state failed: \(error)")
                    }
                    notifier.notifyPosted("Slop posted: \(state.model)", url: url)
                case .draftReady:
                    // The owner's click may already have reported an outcome; keep it.
                    break
                }
            } catch {
                try storeLock.withLock {
                    try saveManualPost(ManualPostState(runID: state.runID, model: state.model, runFolder: state.runFolder, text: state.text, status: .failed, failedStep: "Post", failure: String(describing: error)), storeURL: storeURL)
                }
                notifier.notify("Manual post retry failed for \(state.model) at Post: \(error). It will retry on the next check.")
            }
        }
    }

    /// Records a post X confirmed as completed (and its model as seen), even when
    /// saving its URL fails, so no later check clicks Post for it again.
    static func recordConfirmedPost(_ url: URL, state: ManualPostState, clock: () -> Date, notifier: any Notifier, storeURL: URL) throws {
        let provider = state.model.hasPrefix("claude-") ? "claude" : "openai"
        do {
            try savePost(url, model: state.model, postedAt: clock(), provider: provider, runFolder: URL(fileURLWithPath: state.runFolder), storeURL: storeURL)
        } catch {
            notifier.notify("Slop posted for \(state.model): \(url.absoluteString). Saving post URL failed: \(error)")
        }
        try saveCompletedManualPost(ManualPostState(runID: state.runID, model: state.model, runFolder: state.runFolder, text: state.text, status: .completed), storeURL: storeURL)
    }

    /// Builds, records and posts slop for a model that is already known,
    /// without waiting for a new one. Leaves the seen list and lastCheck alone.
    public static func slopNow(
        model: String,
        commandRunner: any CommandRunner,
        appDataFolder: URL,
        notifier: any Notifier,
        clock: @escaping () -> Date,
        recorder: any Recorder,
        poster: any Poster,
        draftOnly: Bool,
        repositoryURL: URL
    ) throws {
        try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
        try makeSlop(
            model: model,
            commandRunner: commandRunner,
            appDataFolder: appDataFolder,
            notifier: notifier,
            clock: clock,
            recorder: recorder,
            poster: poster,
            draftOnly: draftOnly,
            repositoryURL: repositoryURL
        )
    }

    /// One model through the pipeline: build, record, post, notify.
    @discardableResult
    static func makeSlop(
        model: String,
        commandRunner: any CommandRunner,
        appDataFolder: URL,
        notifier: any Notifier,
        clock: @escaping () -> Date,
        recorder: any Recorder,
        poster: any Poster,
        draftOnly: Bool,
        repositoryURL: URL,
        resuming: URL? = nil
    ) throws -> URL? {
        let storeURL = appDataFolder.appendingPathComponent("seen.json")
        defer { setActivity(nil) }
        // Pick up this model's interrupted run, if any, instead of starting over.
        let runFolder = resuming
            ?? unfinishedRuns(appDataFolder: appDataFolder).last { $0.state.model == model }?.folder
            ?? newRunFolder(model: model, appDataFolder: appDataFolder)
        let resumed = RunState.read(runFolder: runFolder)
        var state = resumed ?? RunState(model: model, stage: .building, sessionID: UUID().uuidString.lowercased(), attempts: 0)
        state.attempts += 1
        let build = Build(runFolder: runFolder, workingFolder: runFolder.appendingPathComponent("working", isDirectory: true))
        try FileManager.default.createDirectory(at: build.workingFolder, withIntermediateDirectories: true)
        try state.write(runFolder: runFolder)
        if state.stage == .building {
            setActivity(SlopActivity(model: model, stage: "building"))
            var result = try runBuild(model: model, commandRunner: commandRunner, appDataFolder: appDataFolder, build: build, sessionID: state.sessionID, resume: resumed != nil)
            if resumed != nil, result.exitCode != 0, !result.timedOut {
                // The session never started or cannot resume: build fresh in the same folder.
                state.sessionID = UUID().uuidString.lowercased()
                try state.write(runFolder: runFolder)
                result = try runBuild(model: model, commandRunner: commandRunner, appDataFolder: appDataFolder, build: build, sessionID: state.sessionID, resume: false)
            }
            if result.timedOut {
                notifier.notify("New model detected: \(model). Build failed (timed out). See build.log in the run folder.")
                throw BuildFailure.timedOut
            }
            guard result.exitCode == 0 else {
                notifier.notify("New model detected: \(model). Build failed. See build.log in the run folder.")
                throw BuildFailure.exited(result.exitCode)
            }
            state.stage = .recording
            try state.write(runFolder: runFolder)
        }
        if state.stage == .recording {
            setActivity(SlopActivity(model: model, stage: "recording"))
            do {
                try recorder.record(workingFolder: build.workingFolder, runFolder: build.runFolder)
            } catch {
                notifier.notify("New model detected: \(model). Record failed: \(error)")
                throw error
            }
            state.stage = .posting
            try state.write(runFolder: runFolder)
        }
        let provider = model.hasPrefix("claude-") ? "claude" : "openai"
        let previousURL = try storeLock.withLock { () throws -> String? in
            let current = try readStore(at: storeURL)
            return current?.latestPost ?? current?.latestPosts?[provider]
        }
        let postText = postText(
            model: model, previousPost: previousURL, repositoryURL: repositoryURL,
            headline: try MySlopText.postText.current(appDataFolder: appDataFolder)
        )
        let runID = build.runFolder.lastPathComponent
        let postResult: PostResult
        var confirmedURL: URL?
        var manualPostCompleted = false
        try storeLock.withLock {
            try saveManualPost(ManualPostState(runID: runID, model: model, runFolder: build.runFolder.path, text: postText, status: .pending), storeURL: storeURL)
        }
        let onManualPost: (ManualPostEvent) -> Void = { event in
            guard event.runID == runID else { return }
            do {
                try storeLock.withLock {
                    switch event.outcome {
                    case .posted(let url):
                        manualPostCompleted = true
                        try recordConfirmedPost(url, state: ManualPostState(runID: runID, model: model, runFolder: build.runFolder.path, text: postText, status: .completed), clock: clock, notifier: notifier, storeURL: storeURL)
                    case .failed(let step, let message):
                        try saveManualPost(ManualPostState(runID: runID, model: model, runFolder: build.runFolder.path, text: postText, status: .failed, failedStep: step, failure: message), storeURL: storeURL)
                    case .uncertain(let step, let message):
                        try saveManualPost(ManualPostState(runID: runID, model: model, runFolder: build.runFolder.path, text: postText, status: .uncertain, failedStep: step, failure: message), storeURL: storeURL)
                    }
                }
            } catch {
                notifier.notify("New model detected: \(model). Saving manual post outcome failed: \(error)")
            }
            switch event.outcome {
            case .posted(let url): notifier.notifyPosted("Slop posted: \(model)", url: url)
            case .failed(let step, let message): notifier.notify("Manual post failed for \(model) at \(step): \(message). It will retry on the next check.")
            case .uncertain(let step, let message): notifier.notify("Manual post outcome for \(model) is uncertain at \(step): \(message). Check X before retrying.")
            }
        }
        setActivity(SlopActivity(model: model, stage: draftOnly ? "drafting" : "posting"))
        do {
            postResult = try poster.post(
                text: postText,
                video: build.runFolder.appendingPathComponent("demo.mp4"),
                draftOnly: draftOnly,
                runID: runID,
                onManualPost: onManualPost
            )
        } catch {
            try? storeLock.withLock {
                try saveManualPost(ManualPostState(runID: runID, model: model, runFolder: build.runFolder.path, text: postText, status: .failed, failedStep: "Post", failure: String(describing: error)), storeURL: storeURL)
            }
            notifier.notify("New model detected: \(model). Post failed: \(error)")
            throw error
        }
        // Posted or waiting in X for the owner's click: nothing left to resume.
        state.stage = .done
        try? state.write(runFolder: runFolder)
        switch postResult {
        case .posted(let url):
            confirmedURL = url
            do {
                try storeLock.withLock { try recordConfirmedPost(url, state: ManualPostState(runID: runID, model: model, runFolder: build.runFolder.path, text: postText, status: .completed), clock: clock, notifier: notifier, storeURL: storeURL) }
            } catch {
                notifier.notify("Slop posted for \(model): \(url.absoluteString). Saving its completed state failed: \(error)")
            }
            notifier.notifyPosted("Slop posted: \(model)", url: url)
        case .draftReady(let resultRunID):
            if !storeLock.withLock({ manualPostCompleted }) {
                let current = try storeLock.withLock { try readStore(at: storeURL)?.manualPosts?[resultRunID] }
                if current?.status == nil || current?.status == .pending {
                    try storeLock.withLock {
                        try saveManualPost(ManualPostState(runID: resultRunID, model: model, runFolder: build.runFolder.path, text: postText, status: .pending), storeURL: storeURL)
                    }
                }
                notifier.notify("Draft ready for \(model). Click Post in X when you're ready.")
            }
        }
        return confirmedURL
    }
}
