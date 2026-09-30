import AppKit
import FactoryCore

@MainActor
func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

@MainActor
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

@MainActor
func choose(_ title: String, expecting text: String, action: () -> Void) {
    var clicked = false
    let timer = Timer(timeInterval: 0.1, repeats: true) { _ in
        MainActor.assumeIsolated {
            guard let window = NSApp.modalWindow, let content = window.contentView else { return }
            let views = descendants(content)
            let copy = views.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n")
            require(copy.contains(XUsernameSharingCoordinator.disclosure), "native disclosure must include exact finished-spec wording")
            require(copy.contains(XUsernameSharingCoordinator.scopeText), "native disclosure must state installation scope")
            require(copy.contains(text), "native disclosure must show current choice/status")
            guard let button = views.compactMap({ $0 as? NSButton }).first(where: { $0.title == title }) else {
                require(false, "native choice button missing: \(title)"); return
            }
            clicked = true
            button.performClick(nil)
        }
    }
    RunLoop.main.add(timer, forMode: .common)
    action()
    timer.invalidate()
    require(clicked, "native choice must present a modal alert")
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    let mode = CommandLine.arguments.last!
    let coordinator = XHandleRegistrationService.shared
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    XHandleRegistrationService.installChoiceControl(on: window)
    let controls = window.titlebarAccessoryViewControllers.flatMap { descendants($0.view) }
    guard let sharingButton = controls.compactMap({ $0 as? NSButton }).first(where: { $0.title == "X username sharing…" }) else {
        require(false, "X window must expose the native sharing control")
        exit(1)
    }
    switch mode {
    case "dismiss-decline":
        require(coordinator.choice == .unknown, "first launch must have unknown choice")
        choose("Close", expecting: "No current sharing choice recorded.") { XHandleRegistrationService.start() }
        require(coordinator.choice == .unknown && !coordinator.collectionEnabled, "dismissal must leave collection disabled")
        choose("Continue without sharing", expecting: "No current sharing choice recorded.") { sharingButton.performClick(nil) }
        try? await Task.sleep(for: .milliseconds(100))
        require(coordinator.choice == .declined && !coordinator.collectionEnabled, "native decline must persist without enabling collection")
        require(coordinator.choiceTime != nil, "native decline must record choice time")
    case "relaunch-accept":
        require(coordinator.choice == .declined && !coordinator.collectionEnabled, "decline must survive process relaunch")
        XHandleRegistrationService.start()
        require(NSApp.modalWindow == nil, "declined relaunch must not prompt again")
        choose("Acknowledge and share my X username", expecting: "Current choice: Continue without sharing.") { sharingButton.performClick(nil) }
        require(coordinator.choice == .acknowledged && coordinator.collectionEnabled, "native acceptance must persist and enable collection")
        require(coordinator.choiceTime != nil, "native acceptance must record choice time")
    case "relaunch-acknowledged":
        require(coordinator.choice == .acknowledged && coordinator.collectionEnabled, "acknowledgement must survive process relaunch")
        XHandleRegistrationService.start()
        require(NSApp.modalWindow == nil, "acknowledged relaunch must not prompt again")
        choose("Close", expecting: "Current choice: Acknowledge and share my X username.") { sharingButton.performClick(nil) }
        require(coordinator.choice == .acknowledged, "closing review must preserve saved acknowledgement")
    default: require(false, "unknown native choice fixture mode")
    }
    print("Native X sharing choice passed: \(mode)")
    exit(0)
}
app.run()
