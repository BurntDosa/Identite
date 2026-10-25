import SwiftUI
import SwiftData
import IDCore

@main
struct IDHolderApp: App {
    private let container: ModelContainer?
    private let reminders: ReminderScheduler?
    @State private var session: SessionLock

    init() {
        var inMemory = false
        var authenticator: any Authenticator = LocalAuthenticator()
        #if DEBUG
        let unitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        inMemory = unitTesting || ProcessInfo.processInfo.arguments.contains("-uiTestingInMemoryStore")
        if inMemory && (unitTesting || ProcessInfo.processInfo.arguments.contains("-uiTestingSkipAuth")) {
            authenticator = TestAuthenticator(onlyOnce: ProcessInfo.processInfo.arguments.contains("-uiTestingUnlockOnce"))
        }
        #endif
        _session = State(initialValue: SessionLock(authenticator: authenticator))
        do {
            let store = try IDStore.makeContainer(inMemory: inMemory)
            store.mainContext.autosaveEnabled = false
            #if DEBUG
            if inMemory && ProcessInfo.processInfo.arguments.contains("-seedSampleData") { try SampleData.seed(store.mainContext) }
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
        WindowGroup {
            if let container {
                Group {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-cardGallery") { CardGallery() }
                    else { RootView() }
                    #else
                    RootView()
                    #endif
                }
                .modelContainer(container).environment(session)
                .environment(\.reminderScheduler, reminders)
                #if DEBUG
                .modifier(TestAppearance())
                #endif
            } else {
                ContentUnavailableView("Couldn't open your IDs", systemImage: "lock.trianglebadge.exclamationmark",
                    description: Text("Your saved data has not been changed. Please reopen the app to try again."))
            }
        }
    }
}

#if DEBUG
private actor TestAuthenticator: Authenticator {
    let onlyOnce: Bool
    private var used = false
    init(onlyOnce: Bool) { self.onlyOnce = onlyOnce }
    func authenticate(reason: String) async -> Bool {
        guard !onlyOnce || !used else { return false }
        used = true
        return true
    }
}
private struct TestAppearance: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    func body(content: Content) -> some View {
        content.preferredColorScheme(ProcessInfo.processInfo.arguments.contains("-uiDark") ? .dark
            : ProcessInfo.processInfo.arguments.contains("-uiTestingInMemoryStore") ? .light : nil)
            .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("-uiAX5") ? .accessibility5 : typeSize)
    }
}
#endif
