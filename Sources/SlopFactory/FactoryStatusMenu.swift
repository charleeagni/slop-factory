import AppKit
import Combine
import FactoryCore

enum FactoryMenuAction: Equatable {
    case check, slop(String), openRuns, openPost(URL)
    case editPrompt, resetPrompt, editPostText, resetPostText
    case sharing, login, setDraftOnly(Bool), quit
}

struct FactoryMenuSnapshot {
    let status: StatusSnapshot
    let activity: SlopActivity?
    let checking: Bool
    let sharingStatus: String
    let draftOnly: Bool
}

/// AppKit owns menu tracking. Status changes update native item titles without
/// rebuilding a SwiftUI menu graph while it is tracking mouse events.
@MainActor
final class FactoryStatusMenu: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    private(set) var isTracking = false
    private let snapshot: () -> FactoryMenuSnapshot
    private let perform: (FactoryMenuAction) -> Void
    private var updates: AnyCancellable?
    private var activityItem: NSMenuItem?
    private var countsItem: NSMenuItem?
    private var sharingItem: NSMenuItem?
    private var checkItem: NSMenuItem?
    private var slopItem: NSMenuItem?

    init(snapshot: @escaping () -> FactoryMenuSnapshot,
         perform: @escaping (FactoryMenuAction) -> Void) {
        self.snapshot = snapshot
        self.perform = perform
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        rebuild(snapshot())
        refresh()
        updates = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isTracking else { return }
        rebuild(snapshot())
    }

    func menuWillOpen(_ menu: NSMenu) { isTracking = true }
    func menuDidClose(_ menu: NSMenu) { isTracking = false }

    func refresh() {
        let state = snapshot()
        let title = state.activity.map { "🏭 \($0.stage)…" } ?? (state.checking ? "🏭…" : "🏭")
        if statusItem.button?.title != title { statusItem.button?.title = title }
        activityItem?.title = activityTitle(state) ?? "No run in progress"
        countsItem?.title = countsTitle(state)
        sharingItem?.title = state.sharingStatus
        checkItem?.isEnabled = !state.checking
        slopItem?.isEnabled = !state.checking && !state.status.models.isEmpty
    }

    private func rebuild(_ state: FactoryMenuSnapshot) {
        menu.removeAllItems()
        activityItem = activityTitle(state).map { add($0) }
        countsItem = add(countsTitle(state))
        if !state.status.pendingSources.isEmpty {
            add("Discovery pending: \(state.status.pendingSources.sorted().joined(separator: ", "))")
        }
        if let post = state.status.latestPost {
            let age = RelativeDateTimeFormatter().localizedString(for: post.postedAt, relativeTo: Date())
            add("Last slop: \(post.model) · \(age)", action: .openPost(post.url))
        } else {
            add("Last slop: none yet")
        }
        add("Open runs folder", action: .openRuns)
        menu.addItem(.separator())
        checkItem = add("Check now", action: .check)
        checkItem?.isEnabled = !state.checking
        let models = NSMenu(title: "Slop now")
        models.autoenablesItems = false
        for model in state.status.models {
            models.addItem(item(model, action: .slop(model)))
        }
        slopItem = NSMenuItem(title: "Slop now", action: nil, keyEquivalent: "")
        slopItem?.submenu = models
        slopItem?.isEnabled = !state.checking && !state.status.models.isEmpty
        if let slopItem { menu.addItem(slopItem) }
        menu.addItem(.separator())
        add("My slop prompt")
        add("Edit prompt…", action: .editPrompt)
        add("Reset to frozen prompt", action: .resetPrompt)
        add("My slop post text")
        add("Edit post text…", action: .editPostText)
        add("Reset to default post text", action: .resetPostText)
        menu.addItem(.separator())
        add("X username sharing…", action: .sharing)
        sharingItem = add(state.sharingStatus)
        add("Log into X…", action: .login)
        let draft = add("Draft only", action: .setDraftOnly(!state.draftOnly))
        draft.state = state.draftOnly ? .on : .off
        menu.addItem(.separator())
        add("Quit", action: .quit)
    }

    private func countsTitle(_ state: FactoryMenuSnapshot) -> String {
        "Watching: \(state.status.claudeCount) Claude · \(state.status.openAICount) OpenAI models"
    }

    private func activityTitle(_ state: FactoryMenuSnapshot) -> String? {
        if let activity = state.activity { return "Making slop: \(activity.model) · \(activity.stage)…" }
        return state.checking ? "Checking for new models…" : nil
    }

    @discardableResult private func add(_ title: String, action: FactoryMenuAction? = nil) -> NSMenuItem {
        let entry = item(title, action: action)
        menu.addItem(entry)
        return entry
    }

    private func item(_ title: String, action: FactoryMenuAction?) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action == nil ? nil : #selector(invoke(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = action
        entry.isEnabled = action != nil
        return entry
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? FactoryMenuAction else { return }
        perform(action)
    }
}
