import SwiftUI
import SwiftData
import IDCore

struct RootView: View {
    @Environment(\.scenePhase) private var phase
    @Environment(SessionLock.self) private var session
    var body: some View {
        ZStack {
            if session.isUnlocked { WalletHomeView() }
            else { LockView(session: session) }
        }
        .onChange(of: phase, initial: true) { _, phase in
            if phase == .active { session.markPresent() } else { session.markAway() }
        }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if unlocked && phase != .active { session.markAway() }
        }
        .background { PrivacyCover(session: session, unlocked: session.isUnlocked) }
    }
}
