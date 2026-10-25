import AppKit
import SwiftUI
import IDCore

@MainActor final class MacSessionEvents: NSObject, ObservableObject {
    @Published private(set) var panelVisible = false
    private let session: SessionLock
    private let windows = NSHashTable<NSWindow>.weakObjects()
    private let panels = NSHashTable<NSWindow>.weakObjects()
    private var timer: Timer?
    private let workspaceCenter: NotificationCenter
    private let distributedCenter: NotificationCenter
    private var screenSaverActive = false
    private var workspaceSessionActive = true

    init(session: SessionLock, workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
         distributedCenter: NotificationCenter = DistributedNotificationCenter.default()) {
        self.session = session
        self.workspaceCenter = workspaceCenter; self.distributedCenter = distributedCenter
        super.init()
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
                     NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didEndSheetNotification] {
            center.addObserver(self, selector: #selector(refresh), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(closing(_:)), name: NSWindow.willCloseNotification, object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceCenter.addObserver(self, selector: #selector(lock), name: name, object: nil)
        }
        distributedCenter.addObserver(self, selector: #selector(lock),
            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        distributedCenter.addObserver(self, selector: #selector(screenSaverStarted),
            name: Notification.Name("com.apple.screensaver.didstart"), object: nil)
        distributedCenter.addObserver(self, selector: #selector(screenSaverStopped),
            name: Notification.Name("com.apple.screensaver.didstop"), object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceCenter.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(); self?.session.evaluate() }
        }
    }

    func register(_ window: NSWindow, panel: Bool) {
        (panel ? panels : windows).add(window)
        refresh()
    }

    @objc private func closing(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        windows.remove(window); panels.remove(window)
        refresh()
    }

    @objc func refresh() {
        let mainPresent = NSApplication.shared.isActive && windows.allObjects.contains {
            $0.isVisible && !$0.isMiniaturized && ($0.isKeyWindow || $0.attachedSheet?.isKeyWindow == true)
        }
        updatePresence(mainWindowPresent: mainPresent, panelVisible: panels.allObjects.contains { $0.isVisible })
    }

    func updatePresence(mainWindowPresent: Bool, panelVisible: Bool) {
        if self.panelVisible != panelVisible { self.panelVisible = panelVisible }
        guard workspaceSessionActive, !screenSaverActive else { session.markAway(); return }
        if mainWindowPresent || panelVisible { session.markPresent() } else { session.markAway() }
    }

    @objc private func screenSaverStarted() { screenSaverActive = true; lock() }
    @objc private func screenSaverStopped() { screenSaverActive = false; refresh() }
    @objc private func sessionResigned() { workspaceSessionActive = false; lock() }
    @objc private func sessionActivated() { workspaceSessionActive = true; refresh() }

    @objc func lock() { session.lockNow() }

    func stop() {
        timer?.invalidate(); timer = nil
        NotificationCenter.default.removeObserver(self)
        workspaceCenter.removeObserver(self)
        distributedCenter.removeObserver(self)
    }
}

// SwiftUI keeps the menu panel's content alive while hidden; observe its actual NSWindow.
struct MacWindowObserver: NSViewRepresentable {
    let events: MacSessionEvents
    var panel = false
    func makeNSView(context: Context) -> Anchor { Anchor(events: events, panel: panel) }
    func updateNSView(_ view: Anchor, context: Context) { }

    final class Anchor: NSView {
        let events: MacSessionEvents
        let panel: Bool
        init(events: MacSessionEvents, panel: Bool) {
            self.events = events; self.panel = panel
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { Task { @MainActor in events.register(window, panel: panel) } }
        }
    }
}
