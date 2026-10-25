import SwiftUI
import IDCore

struct LockView: View {
    let session: SessionLock
    var showsButton = true
    var autoUnlock = true
    @Environment(\.colorScheme) private var scheme
    @State private var authenticating = false
    @State private var failed = false

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: -105) {
                ForEach(Array([IDKind.aadhaar, .pan, .voterID, .drivingLicence].enumerated()), id: \.element) { index, kind in
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: (CardPalette.mesh(for: kind) ?? []).map { Color(cardHex: $0) },
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 300, height: 190)
                        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.12)) }
                        .rotationEffect(.degrees(Double(index) * 5 - 8))
                        .shadow(color: .black.opacity(0.12), radius: 5, y: 3)
                }
            }
            .saturation(0.35).opacity(scheme == .dark ? 0.28 : 0.65).blur(radius: 7).accessibilityHidden(true)
            VStack(spacing: 24) {
                Image("IdentiteGlyph").resizable().scaledToFit().frame(height: 64)
                    .foregroundStyle(.primary).accessibilityHidden(true)
                Text("Identité").font(.largeTitle.bold()).accessibilityIdentifier(showsButton ? "lock-title" : "privacy-title")
                if showsButton {
                    Button {
                        Task { await unlock() }
                    } label: {
                        Text(LocalAuthenticator.unlockLabel)
                        #if os(macOS)
                            .foregroundStyle(scheme == .dark ? Color.white : Color.black)
                        #endif
                    }
                    .buttonStyle(.glass).controlSize(.large)
                    #if os(macOS)
                    .tint(.clear)
                    #endif
                    .disabled(authenticating).accessibilityIdentifier("unlock")
                    if failed { Text("Couldn't unlock. Try again.").foregroundStyle(.secondary) }
                }
            }.padding(24)
        }
        .task { if showsButton && autoUnlock { await unlock() } }
        #if os(macOS)
        .background {
            MacLockActivation {
                // After a cancel or failure, wait for the Open button instead of re-prompting each time the window becomes key.
                if showsButton && !session.isUnlocked && !failed { Task { await unlock() } }
            }
        }
        #endif
    }

    private func unlock() async {
        guard !authenticating else { return }
        authenticating = true
        failed = !(await session.unlock())
        authenticating = false
    }
}

#if os(macOS)
private struct MacLockActivation: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> Anchor { Anchor(action: action) }
    func updateNSView(_ view: Anchor, context: Context) { view.action = action }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) { NotificationCenter.default.removeObserver(view) }
    final class Anchor: NSView {
        var action: () -> Void
        init(action: @escaping () -> Void) {
            self.action = action
            super.init(frame: .zero)
            NotificationCenter.default.addObserver(self, selector: #selector(becameKey(_:)),
                name: NSWindow.didBecomeKeyNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        @objc private func becameKey(_ notification: Notification) {
            if let target = notification.object as? NSWindow, target === window { action() }
        }
    }
}
#endif
