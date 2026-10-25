import SwiftUI
import SwiftData
import IDCore

@main
struct IDHolderMacApp: App {
    private let container: ModelContainer?
    private let reminders: ReminderScheduler?
    private let events: MacSessionEvents
    @State private var copySelection = MacCopySelection()
    @State private var session: SessionLock

    init() {
        var inMemory = false
        var authenticator: any Authenticator = LocalAuthenticator()
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        inMemory = arguments.contains("-uiTestingInMemoryStore") || arguments.contains("-seedSampleData")
        if inMemory && arguments.contains("-uiTestingSkipAuth") { authenticator = MacTestAuthenticator() }
        if inMemory { NSApplication.shared.appearance = NSAppearance(named: arguments.contains("-uiDark") ? .darkAqua : .aqua) }
        #endif
        let session = SessionLock(authenticator: authenticator)
        _session = State(initialValue: session)
        events = MacSessionEvents(session: session)
        do {
            let store = try IDStore.makeContainer(inMemory: inMemory)
            store.mainContext.autosaveEnabled = false
            #if DEBUG
            if inMemory && arguments.contains("-seedSampleData") { try SampleData.seed(store.mainContext) }
            #endif
            container = store
            #if DEBUG
            reminders = inMemory ? nil : ReminderScheduler(container: store)
            #else
            reminders = ReminderScheduler(container: store)
            #endif
        } catch { container = nil; reminders = nil }
    }

    var body: some Scene {
        WindowGroup("Identité", id: "main") {
            if let container {
                Group {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-cardGallery") { CardGallery() }
                    else { MacRootView(events: events) }
                    #else
                    MacRootView(events: events)
                    #endif
                }.modelContainer(container).environment(session).environment(copySelection)
                    .environment(\.reminderScheduler, reminders)
            } else { storeError }
        }
        .defaultSize(width: 1000, height: 760)
        .commands { MacCommands(session: session, copySelection: copySelection) }
        MenuBarExtra {
            if let container { MenuBarPanel(events: events).modelContainer(container).environment(session).environment(copySelection)
                .environment(\.reminderScheduler, reminders) }
            else { storeError.frame(width: 360, height: 300) }
        } label: {
            Image("IdentiteGlyph")
                .accessibilityLabel("Identité")
        }.menuBarExtraStyle(.window)
        #if DEBUG
        Window("Menu Bar Preview", id: "menu-bar-preview") {
            if ProcessInfo.processInfo.arguments.contains("-menuBarPanelPreview"), let container {
                MenuBarPanel(events: events).modelContainer(container).environment(session).environment(copySelection)
                    .environment(\.reminderScheduler, reminders)
                    .background(.background)
            }
        }
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(ProcessInfo.processInfo.arguments.contains("-menuBarPanelPreview") ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        #endif
        Settings {
            if let container { MacSettingsView(events: events).modelContainer(container).environment(session).environment(copySelection)
                .environment(\.reminderScheduler, reminders) }
            else { storeError }
        }
    }
    private var storeError: some View {
        ContentUnavailableView("Couldn't open your IDs", systemImage: "lock.trianglebadge.exclamationmark",
            description: Text("Your saved data has not been changed. Please reopen the app to try again."))
    }
}

#if DEBUG
private struct MacTestAuthenticator: Authenticator {
    func authenticate(reason: String) async -> Bool { true }
}
#endif
