import Foundation

public struct CommandResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public protocol CommandRunner {
    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval) throws -> CommandResult
}

public protocol EnvironmentCommandRunner: CommandRunner {
    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval, environment: [String: String]) throws -> CommandResult
}

public extension CommandRunner {
    func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        if let runner = self as? any EnvironmentCommandRunner {
            return try runner.run(executable: executable, arguments: arguments, workingFolder: workingFolder, timeout: timeout, environment: environment)
        }
        return try run(executable: executable, arguments: arguments, workingFolder: workingFolder, timeout: timeout)
    }
}

public struct ProcessCommandRunner: EnvironmentCommandRunner {
    public init() {}

    private static let runningProcesses = LockedSet()

    /// Stops agents still building so a quit app leaves no orphan behind to race
    /// the resumed run. ponytail: a crash or force quit still orphans them.
    public static func terminateAll() {
        runningProcesses.withLock { $0.forEach { $0.terminate() } }
    }

    final class LockedSet: @unchecked Sendable {
        private let lock = NSLock()
        private var processes: Set<Process> = []
        func withLock<T>(_ body: (inout Set<Process>) -> T) -> T { lock.withLock { body(&processes) } }
    }
    public func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval) throws -> CommandResult {
        try run(executable: executable, arguments: arguments, workingFolder: workingFolder, timeout: timeout, environment: [:])
    }
    public func run(executable: URL, arguments: [String], workingFolder: URL, timeout: TimeInterval, environment: [String: String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingFolder
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let err = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: out.path, contents: nil)
        FileManager.default.createFile(atPath: err.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: out); try? FileManager.default.removeItem(at: err) }
        let output = try FileHandle(forWritingTo: out), errors = try FileHandle(forWritingTo: err)
        defer { try? output.close(); try? errors.close() }
        process.standardOutput = output; process.standardError = errors
        try process.run()
        Self.runningProcesses.withLock { _ = $0.insert(process) }
        defer { Self.runningProcesses.withLock { _ = $0.remove(process) } }
        // Uptime pauses while the Mac sleeps, so sleep does not count toward the timeout.
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.1) }
        let timedOut = process.isRunning
        if timedOut { process.terminate(); process.waitUntilExit() }
        return CommandResult(exitCode: process.terminationStatus, stdout: String(decoding: try Data(contentsOf: out), as: UTF8.self), stderr: String(decoding: try Data(contentsOf: err), as: UTF8.self), timedOut: timedOut)
    }
}

public protocol Notifier: AnyObject {
    func notify(_ message: String)
    func notifyPosted(_ message: String, url: URL)
}

public extension Notifier {
    func notifyPosted(_ message: String, url: URL) { notify(message) }
}

public protocol Recorder {
    func record(workingFolder: URL, runFolder: URL) throws
}

public enum PostResult {
    case posted(URL)
    case draftReady(runID: String)
}

public enum ManualPostOutcome {
    case posted(URL)
    case failed(step: String, message: String)
    case uncertain(step: String, message: String)
}

public struct ManualPostEvent {
    public let runID: String
    public let outcome: ManualPostOutcome
    public init(runID: String, outcome: ManualPostOutcome) { self.runID = runID; self.outcome = outcome }
}

public struct ManualPostState: Codable {
    public enum Status: String, Codable { case pending, failed, uncertain, completed }
    public let runID: String
    public let model: String
    public let runFolder: String
    public let text: String
    public let status: Status
    public let failedStep: String?
    public let failure: String?
    public init(runID: String, model: String, runFolder: String, text: String, status: Status, failedStep: String? = nil, failure: String? = nil) {
        self.runID = runID; self.model = model; self.runFolder = runFolder; self.text = text
        self.status = status; self.failedStep = failedStep; self.failure = failure
    }
}

/// Posts one run's demo. `.posted` means the post is confirmed. `.draftReady`
/// means the owner must click Post; each later click reports exactly one
/// `ManualPostEvent` carrying `runID`: `.posted` when a URL is confirmed,
/// `.failed` when X reported an error (retried on the next check), or
/// `.uncertain` when the outcome is unknown (never retried). An untouched draft
/// reports nothing and stays pending.
public protocol Poster {
    func post(text: String, video: URL, draftOnly: Bool, runID: String, onManualPost: @escaping (ManualPostEvent) -> Void) throws -> PostResult
}

public struct SeenStore: Codable {
    public let seenModels: [String]
    public let lastCheck: Date
    public let latestPosts: [String: String]?
    public let latestPost: String?
    public let watchedClaudeCount: Int?
    public let watchedOpenAICount: Int?
    public let latestPostModel: String?
    public let latestPostDate: Date?
    public let initializedSources: [String]?
    public let pendingSources: [String]?
    public let manualPosts: [String: ManualPostState]?

    public init(seenModels: [String], lastCheck: Date, latestPosts: [String: String]? = nil, latestPost: String? = nil, watchedClaudeCount: Int? = nil, watchedOpenAICount: Int? = nil, latestPostModel: String? = nil, latestPostDate: Date? = nil, initializedSources: [String]? = nil, pendingSources: [String]? = nil, manualPosts: [String: ManualPostState]? = nil) {
        self.seenModels = seenModels
        self.lastCheck = lastCheck
        self.latestPosts = latestPosts
        self.latestPost = latestPost
        self.watchedClaudeCount = watchedClaudeCount
        self.watchedOpenAICount = watchedOpenAICount
        self.latestPostModel = latestPostModel
        self.latestPostDate = latestPostDate
        self.initializedSources = initializedSources
        self.pendingSources = pendingSources
        self.manualPosts = manualPosts
    }
}

public struct LatestPost {
    public let model: String
    public let postedAt: Date
    public let url: URL
}

public struct StatusSnapshot {
    public let claudeCount: Int
    public let openAICount: Int
    public let latestPost: LatestPost?
    public let models: [String]
    public let pendingSources: [String]

    public init(claudeCount: Int, openAICount: Int, latestPost: LatestPost?, models: [String] = [], pendingSources: [String] = []) {
        self.claudeCount = claudeCount
        self.openAICount = openAICount
        self.latestPost = latestPost
        self.models = models
        self.pendingSources = pendingSources
    }
}

public enum ModelProvider: Hashable, Sendable {
    case claude
    case openAI
}

public struct FirstLaunchResult: Sendable {
    public let foundProviders: Set<ModelProvider>
}

public enum FactoryCore {
    static let storeLock = NSLock()

    public static func discoverProviders(
        commandRunner: any CommandRunner,
        homeFolder: URL,
        appDataFolder: URL
    ) -> Set<ModelProvider> {
        ModelDetection.discoverProviders(
            commandRunner: commandRunner,
            homeFolder: homeFolder,
            appDataFolder: appDataFolder
        )
    }

    public static func firstLaunchSetup(
        commandRunner: any CommandRunner,
        homeFolder: URL,
        appDataFolder: URL,
        clock: () -> Date
    ) throws -> FirstLaunchResult? {
        let storeURL = appDataFolder.appendingPathComponent("seen.json")
        guard try storeLock.withLock({ try readStore(at: storeURL) }) == nil else { return nil }
        let providers = discoverProviders(
            commandRunner: commandRunner,
            homeFolder: homeFolder,
            appDataFolder: appDataFolder
        )
        guard !providers.isEmpty else { return FirstLaunchResult(foundProviders: []) }
        let observations = ModelDetection.observations(commandRunner: commandRunner, homeFolder: homeFolder, appDataFolder: appDataFolder, providers: providers)
        guard !observations.successfulSources.isEmpty else { return FirstLaunchResult(foundProviders: providers) }
        let visible = observations.successfulModels
        try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
        try storeLock.withLock {
            guard try readStore(at: storeURL) == nil else { return }
            try Onboarding.begin(appDataFolder: appDataFolder)
            try saveSeen(
                visible,
                storeURL: storeURL,
                clock: clock,
                claudeCount: observations.modelsBySource.filter { $0.key.hasPrefix("claude") }.values.reduce(into: Set<String>()) { $0.formUnion($1) }.count,
                openAICount: observations.modelsBySource["openai"]?.count ?? 0,
                initializedSources: observations.successfulSources,
                pendingSources: observations.failedSources
            )
        }
        return FirstLaunchResult(foundProviders: providers)
    }

    public static func statusSnapshot(appDataFolder: URL) throws -> StatusSnapshot {
        let store = try storeLock.withLock {
            try readStore(at: appDataFolder.appendingPathComponent("seen.json"))
        }
        let latest: LatestPost?
        if let model = store?.latestPostModel,
           let date = store?.latestPostDate,
           let rawURL = store?.latestPost,
           let url = URL(string: rawURL) {
            latest = LatestPost(model: model, postedAt: date, url: url)
        } else {
            latest = nil
        }
        return StatusSnapshot(
            claudeCount: store?.watchedClaudeCount ?? 0,
            openAICount: store?.watchedOpenAICount ?? 0,
            latestPost: latest,
            models: store?.seenModels ?? [],
            pendingSources: store?.pendingSources ?? []
        )
    }

    public static func runOneCheck(
        commandRunner: any CommandRunner,
        homeFolder: URL,
        appDataFolder: URL,
        notifier: any Notifier,
        clock: @escaping () -> Date,
        recorder: any Recorder,
        poster: any Poster,
        draftOnly: Bool,
        repositoryURL: URL,
        watchedProviders: Set<ModelProvider> = [.claude, .openAI]
    ) throws {
        try retryFailedManualPosts(
            appDataFolder: appDataFolder,
            notifier: notifier,
            clock: clock,
            poster: poster,
            draftOnly: draftOnly
        )
        defer {
            resumeUnfinishedRuns(commandRunner: commandRunner, appDataFolder: appDataFolder, notifier: notifier, clock: clock, recorder: recorder, poster: poster, draftOnly: draftOnly, repositoryURL: repositoryURL)
        }
        guard !watchedProviders.isEmpty else { return }
        let observations = ModelDetection.observations(commandRunner: commandRunner, homeFolder: homeFolder, appDataFolder: appDataFolder, providers: watchedProviders)
        guard !observations.successfulSources.isEmpty else { return }
        let visible = observations.successfulModels
        let watchedClaudeCount = observations.modelsBySource.filter { $0.key.hasPrefix("claude") }.values.reduce(into: Set<String>()) { $0.formUnion($1) }.count
        let watchedOpenAICount = observations.modelsBySource["openai"]?.count ?? 0
        let storeURL = appDataFolder.appendingPathComponent("seen.json")
        let previous = try storeLock.withLock { try readStore(at: storeURL) }

        var seen = previous.map { Set($0.seenModels) } ?? []
        var initialized = Set(previous?.initializedSources ?? [])
        try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
        let alreadyInitializedModels = observations.modelsBySource
            .filter { initialized.contains($0.key) }
            .values.reduce(into: Set<String>()) { $0.formUnion($1) }
        let newlyInitializedModels = observations.modelsBySource
            .filter { observations.successfulSources.contains($0.key) && !initialized.contains($0.key) }
            .values.reduce(into: Set<String>()) { $0.formUnion($1) }
        if previous == nil {
            seen.formUnion(visible)
        } else {
            for model in alreadyInitializedModels.subtracting(seen).sorted() {
                let provider = model.hasPrefix("claude-") ? "claude" : "openai"
                if let recovered = confirmedPost(model: model, appDataFolder: appDataFolder) {
                    do {
                        try storeLock.withLock {
                            try savePost(recovered.url, model: model, postedAt: clock(), provider: provider, runFolder: recovered.runFolder, storeURL: storeURL)
                        }
                    } catch {
                        notifier.notify("Slop was already posted for \(model): \(recovered.url.absoluteString). Saving post metadata failed: \(error)")
                    }
                    notifier.notifyPosted("Slop posted: \(model)", url: recovered.url)
                } else {
                    let confirmedURL = try makeSlop(
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
                    seen.insert(model)
                    do {
                        try storeLock.withLock { try saveSeen(seen, storeURL: storeURL, clock: clock, claudeCount: watchedClaudeCount, openAICount: watchedOpenAICount, initializedSources: initialized.union(observations.successfulSources), pendingSources: observations.failedSources) }
                    } catch {
                        if let confirmedURL {
                            notifier.notify("Slop posted: \(confirmedURL.absoluteString). Saving seen state for \(model) failed: \(error)")
                        }
                        throw error
                    }
                    continue
                }
                seen.insert(model)
                try storeLock.withLock { try saveSeen(seen, storeURL: storeURL, clock: clock, claudeCount: watchedClaudeCount, openAICount: watchedOpenAICount, initializedSources: initialized.union(observations.successfulSources), pendingSources: observations.failedSources) }
            }
        }
        seen.formUnion(newlyInitializedModels)
        initialized.formUnion(observations.successfulSources)
        try storeLock.withLock { try saveSeen(seen, storeURL: storeURL, clock: clock, claudeCount: watchedClaudeCount, openAICount: watchedOpenAICount, initializedSources: initialized, pendingSources: observations.failedSources) }
    }

    public static func postText(
        model: String, previousPost: String?, repositoryURL: URL,
        headline: String = (try? MySlopText.postText.builtIn()) ?? ""
    ) -> String {
        var text = headline.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "{model}", with: model)
        if let previousPost { text += "\n\nPrevious post: \(previousPost)" }
        return text + "\n\n\(repositoryURL.absoluteString)"
    }

    public static func repositoryURL(bundled: String?, localOverride: String?) -> URL {
        func validURL(_ value: String?) -> URL? {
            guard let value,
                  let components = URLComponents(string: value),
                  let scheme = components.scheme?.lowercased(),
                  (scheme == "http" || scheme == "https"),
                  let host = components.host, !host.isEmpty
            else { return nil }
            return components.url
        }
        return validURL(bundled) ?? validURL(localOverride)
            ?? URL(string: "https://github.com/charleeagni/slop-factory")!
    }

    static func readStore(at url: URL) throws -> SeenStore? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(SeenStore.self, from: Data(contentsOf: url))
    }

    static func writeStore(_ store: SeenStore, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(store).write(to: url, options: .atomic)
    }

    private static func saveSeen(_ seen: Set<String>, storeURL: URL, clock: () -> Date, claudeCount: Int, openAICount: Int, initializedSources: Set<String>, pendingSources: Set<String> = []) throws {
        let current = try readStore(at: storeURL)
        let mergedSeen = seen.union(current?.seenModels ?? [])
        try writeStore(SeenStore(seenModels: mergedSeen.sorted(), lastCheck: clock(), latestPosts: current?.latestPosts, latestPost: current?.latestPost, watchedClaudeCount: claudeCount, watchedOpenAICount: openAICount, latestPostModel: current?.latestPostModel, latestPostDate: current?.latestPostDate, initializedSources: initializedSources.sorted(), pendingSources: pendingSources.sorted(), manualPosts: current?.manualPosts), to: storeURL)
    }

    static func savePost(_ url: URL, model: String, postedAt: Date, provider: String, runFolder: URL, storeURL: URL) throws {
        var firstError: Error?
        do {
            try url.absoluteString.write(to: runFolder.appendingPathComponent("post-url.txt"), atomically: true, encoding: .utf8)
        } catch {
            firstError = error
        }
        do {
            let current = try readStore(at: storeURL)
            var latestPosts = current?.latestPosts ?? [:]
            latestPosts[provider] = url.absoluteString
            try writeStore(SeenStore(seenModels: current?.seenModels ?? [], lastCheck: current?.lastCheck ?? postedAt, latestPosts: latestPosts, latestPost: url.absoluteString, watchedClaudeCount: current?.watchedClaudeCount, watchedOpenAICount: current?.watchedOpenAICount, latestPostModel: model, latestPostDate: postedAt, initializedSources: current?.initializedSources, pendingSources: current?.pendingSources, manualPosts: current?.manualPosts), to: storeURL)
        } catch {
            firstError = firstError ?? error
        }
        if let firstError { throw firstError }
    }

    static func saveManualPost(_ state: ManualPostState, storeURL: URL) throws {
        let current = try readStore(at: storeURL)
        var posts = current?.manualPosts ?? [:]
        posts[state.runID] = state
        try writeStore(SeenStore(seenModels: current?.seenModels ?? [], lastCheck: current?.lastCheck ?? Date(), latestPosts: current?.latestPosts, latestPost: current?.latestPost, watchedClaudeCount: current?.watchedClaudeCount, watchedOpenAICount: current?.watchedOpenAICount, latestPostModel: current?.latestPostModel, latestPostDate: current?.latestPostDate, initializedSources: current?.initializedSources, pendingSources: current?.pendingSources, manualPosts: posts), to: storeURL)
    }

    static func saveCompletedManualPost(_ state: ManualPostState, storeURL: URL) throws {
        let current = try readStore(at: storeURL)
        var posts = current?.manualPosts ?? [:]
        posts[state.runID] = state
        var seen = Set(current?.seenModels ?? [])
        seen.insert(state.model)
        try writeStore(SeenStore(seenModels: seen.sorted(), lastCheck: current?.lastCheck ?? Date(), latestPosts: current?.latestPosts, latestPost: current?.latestPost, watchedClaudeCount: current?.watchedClaudeCount, watchedOpenAICount: current?.watchedOpenAICount, latestPostModel: current?.latestPostModel, latestPostDate: current?.latestPostDate, initializedSources: current?.initializedSources, pendingSources: current?.pendingSources, manualPosts: posts), to: storeURL)
    }

    private static func confirmedPost(model: String, appDataFolder: URL) -> (url: URL, runFolder: URL)? {
        let safeName = String(model.map { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
                ? character : "_"
        }.prefix(80))
        let runsFolder = appDataFolder.appendingPathComponent("runs", isDirectory: true)
        guard let runs = try? FileManager.default.contentsOfDirectory(at: runsFolder, includingPropertiesForKeys: nil) else { return nil }
        for run in runs where run.lastPathComponent.hasPrefix("\(safeName.isEmpty ? "model" : safeName)-") {
            if let url = savedPostURL(runFolder: run) { return (url, run) }
        }
        return nil
    }

    /// The confirmed post URL a run saved in post-url.txt, if any.
    static func savedPostURL(runFolder: URL) -> URL? {
        guard let rawURL = try? String(contentsOf: runFolder.appendingPathComponent("post-url.txt"), encoding: .utf8),
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    struct Build {
        let runFolder: URL
        let workingFolder: URL
    }

    static func newRunFolder(model: String, appDataFolder: URL) -> URL {
        let safeName = String(model.map { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
                ? character : "_"
        }.prefix(80))
        return appDataFolder.appendingPathComponent("runs", isDirectory: true)
            .appendingPathComponent("\(safeName.isEmpty ? "model" : safeName)-\(UUID().uuidString)", isDirectory: true)
    }

    /// Runs the model's agent in the run's working folder. `resume` continues
    /// the agent session `sessionID` (Claude) or the folder's last session (Codex).
    static func runBuild(model: String, commandRunner: any CommandRunner, appDataFolder: URL, build: Build, sessionID: String, resume: Bool) throws -> CommandResult {
        let runFolder = build.runFolder
        try FileManager.default.createDirectory(at: build.workingFolder, withIntermediateDirectories: true)
        let prompt = resume
            ? "You were interrupted. Continue the original task in this folder until it is complete."
            : try MySlopText.prompt.current(appDataFolder: appDataFolder)
        if !resume { try prompt.write(to: runFolder.appendingPathComponent("prompt.txt"), atomically: true, encoding: .utf8) }
        let isClaude = model.hasPrefix("claude-")
        let arguments = isClaude
            ? ["claude", "-p", "--model", model, "--effort", "medium", "--dangerously-skip-permissions", resume ? "--resume" : "--session-id", sessionID, prompt]
            : resume
            // Each run has its own working folder, so the folder's last Codex session is this run's.
            ? ["codex", "exec", "resume", "--last", "-m", model, "-c", "approval_policy=never", "-c", "model_reasoning_effort=\"medium\"", "-c", "sandbox_mode=\"workspace-write\"", "--skip-git-repo-check", prompt]
            : ["codex", "exec", "-m", model, "-c", "approval_policy=never", "-c", "model_reasoning_effort=\"medium\"", "-s", "workspace-write", "--skip-git-repo-check", prompt]
        let savedExecutable = ModelDetection.savedExecutable(for: model, appDataFolder: appDataFolder, commandRunner: commandRunner)
        var environment = ModelDetection.runtimeEnvironment(appDataFolder: appDataFolder)
        if isClaude { environment["CLAUDE_CODE_EFFORT_LEVEL"] = "medium" }
        let result = try commandRunner.run(
            executable: savedExecutable ?? URL(fileURLWithPath: "/usr/bin/env"),
            arguments: savedExecutable == nil ? arguments : Array(arguments.dropFirst()),
            workingFolder: build.workingFolder,
            timeout: 20 * 60,
            environment: environment
        )
        let log = "Exit code: \(result.exitCode)\nTimed out: \(result.timedOut)\n\nstdout:\n\(result.stdout)\n\nstderr:\n\(result.stderr)\n"
        try log.write(to: runFolder.appendingPathComponent("build.log"), atomically: true, encoding: .utf8)
        return result
    }
}
