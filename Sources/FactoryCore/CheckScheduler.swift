import Foundation
import Observation

@MainActor
@Observable
public final class CheckScheduler {
    public private(set) var isRunning = false

    @ObservationIgnored private let clock: () -> Date
    @ObservationIgnored private let run: @MainActor () async -> Void
    private let checkInterval: TimeInterval = 30 * 60

    public init(clock: @escaping () -> Date = Date.init, run: @escaping @MainActor () async -> Void) {
        self.clock = clock
        self.run = run
    }

    public func requestIfOverdue(lastCheck: Date?) {
        guard lastCheck.map({ clock().timeIntervalSince($0) > checkInterval }) ?? true else { return }
        requestCheck()
    }

    public func requestCheck() {
        request(run)
    }

    /// Runs `work` unless a check or another run is already in progress.
    public func request(_ work: @escaping @MainActor () async -> Void) {
        guard !isRunning else { return }
        isRunning = true
        Task {
            await work()
            isRunning = false
        }
    }
}
