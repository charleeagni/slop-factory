import AppKit
import Darwin
import FactoryCore
import ServiceManagement
import SwiftUI
import UserNotifications

@main
struct SlopFactoryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

private enum RepositoryLink {
    static var currentURL: URL {
        FactoryCore.repositoryURL(
            bundled: Bundle.main.object(forInfoDictionaryKey: "SlopFactoryRepositoryURL") as? String,
            localOverride: UserDefaults.standard.string(forKey: "repositoryURL")
        )
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: FactoryStatusMenu?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusMenu = FactoryStatusMenu(snapshot: {
            let background = BackgroundChecks.shared
            return FactoryMenuSnapshot(
                status: background.statusSnapshot(), activity: FactoryCore.activity,
                checking: background.scheduler.isRunning,
                sharingStatus: XHandleRegistrationService.shared.statusText,
                draftOnly: UserDefaults.standard.object(forKey: "draftOnly") as? Bool ?? false
            )
        }, perform: { action in
            let background = BackgroundChecks.shared
            switch action {
            case .check: background.scheduler.requestCheck()
            case .slop(let model): background.slopNow(model)
            case .openRuns: background.openRunsFolder()
            case .openPost(let url): NSWorkspace.shared.open(url)
            case .editPrompt: background.edit(.prompt)
            case .resetPrompt: background.reset(.prompt)
            case .editPostText: background.edit(.postText)
            case .resetPostText: background.reset(.postText)
            case .sharing: XHandleRegistrationService.presentChoice()
            case .login: XWebPoster().showLogin()
            case .setDraftOnly(let enabled): UserDefaults.standard.set(enabled, forKey: "draftOnly")
            case .quit: NSApplication.shared.terminate(nil)
            }
        })
        UNUserNotificationCenter.current().delegate = self
        XHandleRegistrationService.start()
        // Manual X check: `open -a "Slop Factory" --args --draft-video <mp4>`
        // drafts an existing recording without a build. Always Draft only.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--draft-video"), flag + 1 < arguments.count {
            let video = URL(fileURLWithPath: arguments[flag + 1])
            let repository = RepositoryLink.currentURL
            let text = FactoryCore.postText(model: "manual-check", previousPost: nil, repositoryURL: repository)
            Task.detached {
                _ = try? XWebPoster().post(text: text, video: video, draftOnly: true, runID: UUID().uuidString) { _ in }
            }
            return
        }
        Task { @MainActor in await BackgroundChecks.shared.launch() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ProcessRunner.terminateAll()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let rawURL = response.notification.request.content.userInfo["postURL"] as? String,
           let url = URL(string: rawURL) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        completionHandler()
    }
}

@MainActor
private final class BackgroundChecks {
    static let shared = BackgroundChecks()

    let scheduler: CheckScheduler
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var watchedProviders: Set<ModelProvider> = []

    private static var appDataFolder: URL {
        AppDataLocation.folder
    }

    private init() {
        scheduler = CheckScheduler {
            guard !Self.shared.watchedProviders.isEmpty else { return }
            let repositoryURL = RepositoryLink.currentURL
            let appDataFolder = Self.appDataFolder
            let homeFolder = FileManager.default.homeDirectoryForCurrentUser
            let draftOnly = UserDefaults.standard.object(forKey: "draftOnly") as? Bool ?? false
            let watchedProviders = Self.shared.watchedProviders
            await Task.detached {
                try? FactoryCore.runOneCheck(
                    commandRunner: ProcessRunner(),
                    homeFolder: homeFolder,
                    appDataFolder: appDataFolder,
                    notifier: SystemNotifier(),
                    clock: Date.init,
                    recorder: WebViewRecorder(),
                    poster: XWebPoster(),
                    draftOnly: draftOnly,
                    repositoryURL: repositoryURL,
                    watchedProviders: watchedProviders
                )
            }.value
        }
    }

    func statusSnapshot() -> StatusSnapshot {
        (try? FactoryCore.statusSnapshot(appDataFolder: Self.appDataFolder))
            ?? StatusSnapshot(claudeCount: 0, openAICount: 0, latestPost: nil)
    }

    func slopNow(_ model: String) {
        let repositoryURL = RepositoryLink.currentURL
        let appDataFolder = Self.appDataFolder
        let draftOnly = UserDefaults.standard.object(forKey: "draftOnly") as? Bool ?? false
        scheduler.request {
            await Task.detached {
                try? FactoryCore.slopNow(
                    model: model,
                    commandRunner: ProcessRunner(),
                    appDataFolder: appDataFolder,
                    notifier: SystemNotifier(),
                    clock: Date.init,
                    recorder: WebViewRecorder(),
                    poster: XWebPoster(),
                    draftOnly: draftOnly,
                    repositoryURL: repositoryURL
                )
            }.value
        }
    }

    func edit(_ text: MySlopText) {
        do {
            NSWorkspace.shared.open(try text.editableURL(appDataFolder: Self.appDataFolder))
        } catch {
            SystemNotifier().notify("Could not open \(text.fileName): \(error)")
        }
    }

    func reset(_ text: MySlopText) {
        do {
            try text.reset(appDataFolder: Self.appDataFolder)
        } catch {
            SystemNotifier().notify("Could not reset \(text.fileName): \(error)")
        }
    }

    func openRunsFolder() {
        let folder = Self.appDataFolder.appendingPathComponent("runs", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        } catch {
            SystemNotifier().notify("Could not open runs folder: \(error)")
        }
    }

    func launch() async {
        let appDataFolder = Self.appDataFolder
        let homeFolder = FileManager.default.homeDirectoryForCurrentUser
        do {
            let firstLaunch = try await Task.detached {
                try FactoryCore.firstLaunchSetup(
                    commandRunner: ProcessRunner(),
                    homeFolder: homeFolder,
                    appDataFolder: appDataFolder,
                    clock: Date.init
                )
            }.value
            if let firstLaunch {
                watchedProviders = firstLaunch.foundProviders
            } else {
                watchedProviders = await Task.detached {
                    FactoryCore.discoverProviders(
                        commandRunner: ProcessRunner(),
                        homeFolder: homeFolder,
                        appDataFolder: appDataFolder
                    )
                }.value
            }
            if firstLaunch != nil {
                try Onboarding.begin(appDataFolder: appDataFolder)
            }
            if try Onboarding.status(appDataFolder: appDataFolder) != nil {
                let status = try Onboarding.resume(
                    appDataFolder: appDataFolder,
                    presentLogin: {
                        if firstLaunch != nil { showFirstLaunchMessage(for: watchedProviders) }
                        XWebPoster().showLogin()
                    },
                    register: registerOpenAtLogin
                )
                if !status.registrationComplete { showRegistrationRecovery(for: status) }
            }
            if !watchedProviders.isEmpty { startChecks() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "First launch could not finish"
            alert.informativeText = "Slop Factory could not record your existing models: \(error.localizedDescription)"
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    private func showFirstLaunchMessage(for providers: Set<ModelProvider>) {
        let alert = NSAlert()
        if providers.isEmpty {
            alert.messageText = "No CLIs found"
            alert.informativeText = "Install Claude Code (claude) or the Codex CLI (codex) to watch models. No model checks will run until a CLI is installed and Slop Factory is relaunched."
        } else {
            let names = [
                providers.contains(.claude) ? "Claude Code (claude)" : nil,
                providers.contains(.openAI) ? "Codex CLI (codex)" : nil,
            ].compactMap { $0 }
            alert.messageText = "Watching \(names.joined(separator: " and "))"
            alert.informativeText = "Existing models have been recorded. Slop Factory will now open X so you can log in."
        }
        alert.addButton(withTitle: "Continue")
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func registerOpenAtLogin() -> LoginRegistrationResult {
        do {
            try SMAppService.mainApp.register()
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            default: return .failed("macOS did not enable Slop Factory at login.")
            }
        } catch {
            NSLog("Could not register Slop Factory as a login item: %@", String(describing: error))
            return .failed(error.localizedDescription)
        }
    }

    private func showRegistrationRecovery(for status: OnboardingStatus) {
        let alert = NSAlert()
        alert.messageText = status.registrationNeedsApproval ? "Allow Slop Factory at login" : "Open at Login needs attention"
        alert.informativeText = status.registrationNeedsApproval
            ? "macOS requires approval. Enable Slop Factory in Login Items settings to finish setup."
            : "Slop Factory could not register as a login item. " + (status.registrationError ?? "Try again or review Login Items settings.")
        alert.addButton(withTitle: "Open Login Items Settings")
        alert.addButton(withTitle: "Retry")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
        case .alertSecondButtonReturn:
            let retried = try? Onboarding.retryRegistration(appDataFolder: Self.appDataFolder, register: registerOpenAtLogin)
            if let retried, !retried.registrationComplete { showRegistrationRecovery(for: retried) }
        default:
            break
        }
    }

    private func startChecks() {
        requestIfOverdueOrUnfinished()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduler.requestCheck()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestIfOverdueOrUnfinished()
            }
        }
    }

    /// A run interrupted by a quit or restart resumes right away instead of at the next check.
    private func requestIfOverdueOrUnfinished() {
        if FactoryCore.hasUnfinishedRuns(appDataFolder: Self.appDataFolder) {
            scheduler.requestCheck()
        } else {
            scheduler.requestIfOverdue(lastCheck: lastCheck())
        }
    }

    private func lastCheck() -> Date? {
        let storeURL = Self.appDataFolder.appendingPathComponent("seen.json")
        guard let data = try? Data(contentsOf: storeURL),
              let store = try? JSONDecoder().decode(SeenStore.self, from: data)
        else { return nil }
        return store.lastCheck
    }
}

private typealias ProcessRunner = ProcessCommandRunner
