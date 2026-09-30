import Foundation

public enum LoginRegistrationResult: Equatable, Sendable {
    case enabled
    case requiresApproval
    case failed(String)
}

public struct OnboardingStatus: Codable, Equatable, Sendable {
    public let loginPresented: Bool
    public let registrationComplete: Bool
    public let registrationNeedsApproval: Bool
    public let registrationError: String?

    public var isComplete: Bool { loginPresented && registrationComplete }
}

/// Persists the welcome/login and Open at Login steps separately from seen-model history.
public enum Onboarding {
    private static let filename = "onboarding.json"

    public static func status(appDataFolder: URL) throws -> OnboardingStatus? {
        let url = appDataFolder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(OnboardingStatus.self, from: Data(contentsOf: url))
    }

    /// Called alongside initial baseline seeding so a restart can distinguish a new install
    /// with unfinished onboarding from an older install that has already completed setup.
    public static func begin(appDataFolder: URL) throws {
        guard try status(appDataFolder: appDataFolder) == nil else { return }
        try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
        try save(OnboardingStatus(loginPresented: false, registrationComplete: false, registrationNeedsApproval: false, registrationError: nil), in: appDataFolder)
    }

    /// Runs only unfinished setup. A successful registration remains complete even if the
    /// user later disables the login item in System Settings.
    @discardableResult
    public static func resume(
        appDataFolder: URL,
        presentLogin: () -> Void,
        register: () -> LoginRegistrationResult
    ) throws -> OnboardingStatus {
        try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
        var current = try status(appDataFolder: appDataFolder)
            ?? OnboardingStatus(loginPresented: false, registrationComplete: false, registrationNeedsApproval: false, registrationError: nil)

        if !current.loginPresented {
            presentLogin()
            current = OnboardingStatus(loginPresented: true, registrationComplete: false, registrationNeedsApproval: false, registrationError: nil)
            try save(current, in: appDataFolder)
        }

        // Approval-gated registration is re-checked each launch so approving in Settings finishes setup.
        if !current.registrationComplete {
            switch register() {
            case .enabled:
                current = OnboardingStatus(loginPresented: true, registrationComplete: true, registrationNeedsApproval: false, registrationError: nil)
            case .requiresApproval:
                current = OnboardingStatus(loginPresented: true, registrationComplete: false, registrationNeedsApproval: true, registrationError: nil)
            case let .failed(message):
                current = OnboardingStatus(loginPresented: true, registrationComplete: false, registrationNeedsApproval: false, registrationError: message)
            }
            try save(current, in: appDataFolder)
        }
        return current
    }

    /// Explicit recovery action for a failed or approval-gated login item.
    @discardableResult
    public static func retryRegistration(appDataFolder: URL, register: () -> LoginRegistrationResult) throws -> OnboardingStatus {
        try FileManager.default.createDirectory(at: appDataFolder, withIntermediateDirectories: true)
        let old = try status(appDataFolder: appDataFolder)
            ?? OnboardingStatus(loginPresented: true, registrationComplete: false, registrationNeedsApproval: false, registrationError: nil)
        let next: OnboardingStatus
        switch register() {
        case .enabled: next = OnboardingStatus(loginPresented: true, registrationComplete: true, registrationNeedsApproval: false, registrationError: nil)
        case .requiresApproval: next = OnboardingStatus(loginPresented: true, registrationComplete: false, registrationNeedsApproval: true, registrationError: nil)
        case let .failed(message): next = OnboardingStatus(loginPresented: old.loginPresented, registrationComplete: false, registrationNeedsApproval: false, registrationError: message)
        }
        try save(next, in: appDataFolder)
        return next
    }

    private static func save(_ status: OnboardingStatus, in folder: URL) throws {
        let data = try JSONEncoder().encode(status)
        try data.write(to: folder.appendingPathComponent(filename), options: .atomic)
    }
}
