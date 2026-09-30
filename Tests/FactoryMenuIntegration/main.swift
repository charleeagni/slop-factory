import AppKit
@testable import FactoryCore

@MainActor
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    var checking = false
    var draftOnly = false
    var ticks = 0
    var trackedIDs: [ObjectIdentifier]?
    var actions: [FactoryMenuAction] = []
    let statusMenu = FactoryStatusMenu(snapshot: {
        FactoryMenuSnapshot(
            status: StatusSnapshot(claudeCount: ticks, openAICount: 1, latestPost: nil,
                                   models: ["gpt-fixture", "claude-fixture"]),
            activity: SlopActivity(model: "gpt-fixture", stage: ticks.isMultiple(of: 2) ? "building" : "recording"),
            checking: checking,
            sharingStatus: ticks.isMultiple(of: 2) ? "Sharing is off on this Mac." : "X username sharing is on for this installation.",
            draftOnly: draftOnly
        )
    }, perform: { action in
        actions.append(action)
        if case .setDraftOnly(let enabled) = action { draftOnly = enabled }
    })

    // Exercise actual AppKit tracking, not only the menu's data model. Update
    // account/sharing and run state during tracking, including its 5s timer.
    let updater = Timer(timeInterval: 0.1, repeats: true) { _ in
        MainActor.assumeIsolated {
            guard statusMenu.isTracking else { return }
            let ids = statusMenu.menu.items.map(ObjectIdentifier.init)
            if let trackedIDs { require(ids == trackedIDs, "menu structure changed during tracking") }
            else { trackedIDs = ids }
            ticks += 1
            checking.toggle()
            statusMenu.refresh()
            require(statusMenu.menu.items.map(ObjectIdentifier.init) == ids, "refresh rebuilt the tracked menu")
        }
    }
    let closer = Timer(timeInterval: 6.5, repeats: false) { _ in
        MainActor.assumeIsolated { statusMenu.menu.cancelTracking() }
    }
    RunLoop.main.add(updater, forMode: .common)
    RunLoop.main.add(closer, forMode: .common)
    require(statusMenu.statusItem.button != nil, "native status button missing")
    statusMenu.statusItem.button?.performClick(nil)
    updater.invalidate()
    closer.invalidate()
    require(ticks >= 30, "native menu did not stay open through repeated updates")
    require(!statusMenu.isTracking, "menu did not finish tracking")

    checking = false
    statusMenu.menuNeedsUpdate(statusMenu.menu)
    guard let check = statusMenu.menu.items.firstIndex(where: { $0.title == "Check now" }),
          let draft = statusMenu.menu.items.firstIndex(where: { $0.title == "Draft only" }),
          let models = statusMenu.menu.items.first(where: { $0.title == "Slop now" })?.submenu
    else { require(false, "factory menu actions missing"); exit(1) }
    statusMenu.menu.performActionForItem(at: check)
    models.performActionForItem(at: 0)
    statusMenu.menu.performActionForItem(at: draft)
    require(actions == [.check, .slop("gpt-fixture"), .setDraftOnly(true)], "native actions did not dispatch correctly")
    statusMenu.menuNeedsUpdate(statusMenu.menu)
    require(statusMenu.menu.items.first(where: { $0.title == "Draft only" })?.state == .on,
            "draft preference did not appear on reopening")
    checking = true
    statusMenu.refresh()
    require(statusMenu.menu.items.first(where: { $0.title == "Check now" })?.isEnabled == false,
            "running check still enabled")
    require(statusMenu.menu.items.first(where: { $0.title == "Slop now" })?.isEnabled == false,
            "running pipeline still enabled another model run")
    print("PASS native factory menu: \(ticks) updates while open, timer refresh, sharing changes, actions, and draft preference")
    exit(0)
}
app.run()
