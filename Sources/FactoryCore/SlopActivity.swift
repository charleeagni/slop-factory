import Foundation

/// What the pipeline is doing right now, so the menu bar can show slop in progress.
public struct SlopActivity: Sendable, Equatable {
    public let model: String
    public let stage: String
}

extension FactoryCore {
    private static let activityLock = NSLock()
    nonisolated(unsafe) private static var _activity: SlopActivity?

    public static var activity: SlopActivity? {
        activityLock.withLock { _activity }
    }

    static func setActivity(_ activity: SlopActivity?) {
        activityLock.withLock { _activity = activity }
    }
}
