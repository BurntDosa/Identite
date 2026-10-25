import SwiftUI
import IDCore

struct MacSettingsView: View {
    let events: MacSessionEvents
    @Environment(SessionLock.self) private var session
    var body: some View {
        Group {
            if session.isUnlocked {
                TabView {
                    Tab("People", systemImage: "person.2") { PeopleView() }
                    Tab("General", systemImage: "gearshape") { SettingsView() }
                }
            } else { LockView(session: session, autoUnlock: false) }
        }.frame(width: 500, height: 420)
        .background(MacWindowObserver(events: events))
    }
}
