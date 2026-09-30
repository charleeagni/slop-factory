import Foundation

/// How far a run got, saved as run.json in its run folder so an interrupted
/// run (quit, crash, restart) picks up where it stopped.
struct RunState: Codable {
    enum Stage: String, Codable { case building, recording, posting, done }

    let model: String
    var stage: Stage
    /// The agent session the build uses, so a resumed build continues it.
    var sessionID: String
    var attempts: Int

    // ponytail: fixed cap, stops a broken run retrying every check; make it a setting if 3 is wrong.
    static let maxAttempts = 3

    static func read(runFolder: URL) -> RunState? {
        guard let data = try? Data(contentsOf: runFolder.appendingPathComponent("run.json")) else { return nil }
        return try? JSONDecoder().decode(RunState.self, from: data)
    }

    func write(runFolder: URL) throws {
        try JSONEncoder().encode(self).write(to: runFolder.appendingPathComponent("run.json"), options: .atomic)
    }
}

extension FactoryCore {
    /// Run folders that stopped before finishing and still have attempts left, oldest first.
    static func unfinishedRuns(appDataFolder: URL) -> [(folder: URL, state: RunState)] {
        let runs = appDataFolder.appendingPathComponent("runs", isDirectory: true)
        let folders = (try? FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return folders
            .compactMap { folder in RunState.read(runFolder: folder).map { (folder, $0) } }
            .filter { $0.1.stage != .done && $0.1.attempts < RunState.maxAttempts }
            .sorted { creationDate($0.0) < creationDate($1.0) }
    }

    public static func hasUnfinishedRuns(appDataFolder: URL) -> Bool {
        !unfinishedRuns(appDataFolder: appDataFolder).isEmpty
    }

    private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
    }

    /// Resumes unfinished runs for models already seen (Slop now runs). Runs for
    /// unseen models are resumed by the check itself, so their seen state is saved.
    static func resumeUnfinishedRuns(
        commandRunner: any CommandRunner, appDataFolder: URL, notifier: any Notifier,
        clock: @escaping () -> Date, recorder: any Recorder, poster: any Poster,
        draftOnly: Bool, repositoryURL: URL
    ) {
        let storeURL = appDataFolder.appendingPathComponent("seen.json")
        let store = try? storeLock.withLock { try readStore(at: storeURL) }
        let seen = Set(store?.seenModels ?? [])
        for (folder, state) in unfinishedRuns(appDataFolder: appDataFolder) where seen.contains(state.model) {
            if state.stage == .posting {
                // A failed or uncertain post belongs to the manual post retry; only a
                // post cut off mid-flight (still pending) is sent again here.
                switch store?.manualPosts?[folder.lastPathComponent]?.status {
                case .completed?:
                    var done = state; done.stage = .done
                    try? done.write(runFolder: folder)
                    continue
                case .failed?, .uncertain?: continue
                default: break
                }
            }
            _ = try? makeSlop(
                model: state.model, commandRunner: commandRunner, appDataFolder: appDataFolder,
                notifier: notifier, clock: clock, recorder: recorder, poster: poster,
                draftOnly: draftOnly, repositoryURL: repositoryURL, resuming: folder
            )
        }
    }
}
