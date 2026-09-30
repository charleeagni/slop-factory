import Foundation
import Testing
@testable import FactoryCore

struct OnboardingTests {
    @Test func interruptedAfterSeedingResumesLoginAndRegistrationWithoutRepeatingEither() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // Baseline seeding creates this separate marker before any welcome UI is shown.
        let seen = folder.appendingPathComponent("seen.json")
        let baseline = Data(#"{"seenModels":["claude-a","gpt-b"]}"#.utf8)
        try baseline.write(to: seen)
        try Onboarding.begin(appDataFolder: folder)
        var loginCalls = 0
        var registerCalls = 0

        let first = try Onboarding.resume(appDataFolder: folder, presentLogin: { loginCalls += 1 }, register: { registerCalls += 1; return .failed("approval required") })
        #expect(first.registrationError == "approval required")
        let resumed = try Onboarding.resume(appDataFolder: folder, presentLogin: { loginCalls += 1 }, register: { registerCalls += 1; return .enabled })
        #expect(resumed.isComplete)
        #expect(loginCalls == 1)
        #expect(registerCalls == 2)
        #expect(try Data(contentsOf: seen) == baseline)
    }

    @Test func approvalGatedRegistrationIsRecheckedUntilApproved() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = try Onboarding.resume(appDataFolder: folder, presentLogin: {}, register: { .requiresApproval })
        #expect(first.registrationNeedsApproval)
        let approved = try Onboarding.resume(appDataFolder: folder, presentLogin: {}, register: { .enabled })
        #expect(approved.isComplete)
    }

    @Test func registrationFailureCanBeRetried() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try Onboarding.resume(appDataFolder: folder, presentLogin: {}, register: { .failed("blocked") })
        let retried = try Onboarding.retryRegistration(appDataFolder: folder, register: { .enabled })
        #expect(retried.isComplete)
        #expect(retried.registrationError == nil)
    }

    @Test func completedOnboardingDoesNotRepeatLoginOrRegistration() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try Onboarding.resume(appDataFolder: folder, presentLogin: {}, register: { .enabled })
        var calls = 0
        let next = try Onboarding.resume(appDataFolder: folder, presentLogin: { calls += 1 }, register: { calls += 1; return .failed("unexpected") })
        #expect(next.isComplete)
        #expect(calls == 0)
    }

    @Test func deliberateDisableAfterSuccessfulSetupDoesNotReenableItem() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try Onboarding.resume(appDataFolder: folder, presentLogin: {}, register: { .enabled })
        var calls = 0 // represents the login-item effect after the user disables it in Settings
        _ = try Onboarding.resume(appDataFolder: folder, presentLogin: {}, register: { calls += 1; return .enabled })
        #expect(calls == 0)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
