import Foundation
import Testing
@testable import FactoryCore

@MainActor
struct CheckSchedulerTests {
    @Test func launchAndWakeCheckOnlyWhenMoreThanThirtyMinutesOverdue() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let scheduler = CheckScheduler(clock: { now }, run: {})

        scheduler.requestIfOverdue(lastCheck: now.addingTimeInterval(-1_800))
        #expect(!scheduler.isRunning)

        scheduler.requestIfOverdue(lastCheck: now.addingTimeInterval(-1_801))
        #expect(scheduler.isRunning)
    }

    @Test func firstLaunchWithoutLastCheckRunsImmediately() async {
        let scheduler = CheckScheduler(clock: { Date(timeIntervalSince1970: 10_000) }, run: {})

        scheduler.requestIfOverdue(lastCheck: nil)

        #expect(scheduler.isRunning)
    }

    @Test func requestDuringARunIsSkipped() async {
        var starts = 0
        var finish: CheckedContinuation<Void, Never>?
        let scheduler = CheckScheduler(run: {
            starts += 1
            await withCheckedContinuation { finish = $0 }
        })

        scheduler.requestCheck()
        await Task.yield()
        scheduler.requestCheck()

        #expect(starts == 1)
        #expect(scheduler.isRunning)

        finish?.resume()
        for _ in 0..<20 where scheduler.isRunning { await Task.yield() }
        #expect(!scheduler.isRunning)
    }

    @Test func customRunSharesTheOneAtATimeGuard() async {
        var checks = 0
        var slops = 0
        var finish: CheckedContinuation<Void, Never>?
        let scheduler = CheckScheduler(run: { checks += 1 })

        scheduler.request {
            slops += 1
            await withCheckedContinuation { finish = $0 }
        }
        await Task.yield()
        scheduler.requestCheck()
        scheduler.request { slops += 1 }

        #expect(slops == 1)
        #expect(checks == 0)
        finish?.resume()
        for _ in 0..<20 where scheduler.isRunning { await Task.yield() }
        #expect(!scheduler.isRunning)
    }
}
