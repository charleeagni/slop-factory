import AppKit
import Combine
import Foundation
import FactoryCore

enum AppDataLocation {
    static var folder: URL {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--app-data-folder"), flag + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        }
        return FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("Slop Factory", isDirectory: true)
    }
}

/// Observable status keeps an open menu current after an asynchronous withdrawal.
@MainActor
final class XUsernameSharingPresentation: ObservableObject {
    @Published private(set) var statusText: String

    init(coordinator: XUsernameSharingCoordinator) {
        statusText = coordinator.statusText
    }

    func refresh(from coordinator: XUsernameSharingCoordinator) {
        statusText = coordinator.statusText
    }
}

/// Shared by login and posting views, independently of model discovery.
@MainActor
enum XHandleRegistrationService {
    static let shared = XUsernameSharingCoordinator(
        configuration: configuration,
        stateURL: AppDataLocation.folder.appendingPathComponent("x-username-sharing-v1.json"),
        legacyStateURL: AppDataLocation.folder.appendingPathComponent("x-handle-registrations.json")
    )
    static let presentation = XUsernameSharingPresentation(coordinator: shared)
    private static var presenting = false
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        XBrowserView.onSessionOpened = { shared.openWindow(id: $0) }
        XBrowserView.onSessionClosed = { shared.closeWindow(id: $0) }
        XBrowserView.onAccountObservation = { handle, origin, mainFrame, window, generation in
            Task { await shared.observe(handle: handle, origin: origin, isMainFrame: mainFrame,
                                        windowID: window, generation: generation) }
        }
        shared.onChange = {
            presentation.refresh(from: shared)
            XBrowserView.setCollectionGeneration(shared.collectionEnabled ? shared.generation : nil)
        }
        XBrowserView.setCollectionGeneration(shared.collectionEnabled ? shared.generation : nil)
        Task { await shared.resume() }
        if shared.choice == .unknown { presentChoice() }
    }

    static func presentChoice() {
        guard !presenting else { return }
        presenting = true
        defer { presenting = false }
        let alert = NSAlert()
        alert.messageText = "X username sharing"
        var detail = XUsernameSharingCoordinator.disclosure
        detail += "\n\n" + XUsernameSharingCoordinator.scopeText
        detail += "\n\nReports can be lost while offline, so counts may undercount use. Turning sharing off here does not change another installation’s choice."
        switch shared.choice {
        case .unknown: detail += "\n\nNo current sharing choice recorded."
        case .acknowledged: detail += "\n\nCurrent choice: Acknowledge and share my X username."
        case .declined: detail += "\n\nCurrent choice: Continue without sharing."
        }
        detail += "\n" + shared.statusText
        if let time = shared.choiceTime {
            detail += "\nChoice recorded: " + time.formatted(date: .abbreviated, time: .shortened)
        }
        alert.informativeText = detail
        alert.addButton(withTitle: "Acknowledge and share my X username")
        alert.addButton(withTitle: "Continue without sharing")
        alert.addButton(withTitle: "Close")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if !shared.acknowledge() { showSaveFailure() }
        case .alertSecondButtonReturn:
            // Stop browser capture before the asynchronous durable withdrawal path.
            shared.stopCollection()
            Task { if !(await shared.decline()) { showSaveFailure() } }
        default:
            break
        }
    }

    static func installChoiceControl(on window: NSWindow) {
        let accessory = XUsernameSharingTitlebarAccessory()
        accessory.layoutAttribute = .right
        window.addTitlebarAccessoryViewController(accessory)
    }

    private static func showSaveFailure() {
        let alert = NSAlert()
        alert.messageText = "X username sharing could not be saved"
        alert.informativeText = shared.lastDiagnostic ?? "Sharing remains off. Reopen X username sharing to try again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static var configuration: XHandleRegistrationConfiguration? {
        let environment = ProcessInfo.processInfo.environment
        let projectURL = environment["SLOP_FACTORY_SUPABASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SlopFactorySupabaseURL") as? String
        let publishableKey = environment["SLOP_FACTORY_SUPABASE_PUBLISHABLE_KEY"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SlopFactorySupabasePublishableKey") as? String
        guard let projectURL, let publishableKey else { return nil }
        return XHandleRegistrationConfiguration(projectURL: projectURL, publishableKey: publishableKey)
    }
}

@MainActor
private final class XUsernameSharingTitlebarAccessory: NSTitlebarAccessoryViewController {
    override func loadView() {
        let button = NSButton(title: "X username sharing…", target: self, action: #selector(reviewChoice))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.toolTip = "Review or change X username sharing for this Mac."
        let size = button.fittingSize
        button.frame = NSRect(origin: NSPoint(x: 8, y: 4), size: size)
        view = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 16, height: size.height + 8))
        view.addSubview(button)
    }

    @objc private func reviewChoice() {
        XHandleRegistrationService.presentChoice()
    }
}
