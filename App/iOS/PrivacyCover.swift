import SwiftUI
import IDCore

// A separate non-key window also covers sheets, the keyboard, and the document camera.
struct PrivacyCover: UIViewRepresentable {
    let session: SessionLock
    let unlocked: Bool
    func makeUIView(context: Context) -> ShieldAnchor { ShieldAnchor(session: session) }
    func updateUIView(_ view: ShieldAnchor, context: Context) { view.sessionChanged() }
    static func dismantleUIView(_ view: ShieldAnchor, coordinator: ()) { view.stop() }

    final class ShieldAnchor: UIView {
        private let session: SessionLock
        private var shield: UIWindow?
        private(set) var isCovered = false { didSet { shield?.isHidden = !isCovered } }
        init(session: SessionLock) {
            self.session = session
            super.init(frame: .zero)
            NotificationCenter.default.addObserver(self, selector: #selector(sceneDeactivated), name: UIScene.willDeactivateNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(sceneActivated), name: UIScene.didActivateNotification, object: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let scene = window?.windowScene, shield == nil else { return }
            let shield = UIWindow(windowScene: scene)
            shield.windowLevel = .alert + 1
            shield.rootViewController = UIHostingController(rootView: LockView(session: session, showsButton: false))
            shield.isUserInteractionEnabled = false
            self.shield = shield
            isCovered = scene.activationState != .foregroundActive
        }
        @objc private func sceneDeactivated(_ notification: Notification) {
            guard let scene = notification.object as? UIWindowScene, scene === window?.windowScene else { return }
            cover()
        }
        func cover() {
            session.markAway()
            shield?.rootViewController = UIHostingController(rootView: LockView(session: session, showsButton: false))
            shield?.isUserInteractionEnabled = false
            isCovered = true
        }
        @objc private func sceneActivated(_ notification: Notification) {
            guard let scene = notification.object as? UIWindowScene, scene === window?.windowScene else { return }
            uncover()
        }
        func uncover() {
            session.markPresent()
            // Keep an interactive lock screen above old sheets until a fresh authentication succeeds.
            if !session.isUnlocked {
                shield?.rootViewController = UIHostingController(rootView: LockView(session: session, autoUnlock: false))
                shield?.isUserInteractionEnabled = true
            }
            isCovered = !session.isUnlocked
        }
        func sessionChanged() {
            if session.isUnlocked, window?.windowScene?.activationState == .foregroundActive { isCovered = false }
        }
        func stop() {
            NotificationCenter.default.removeObserver(self)
            shield?.isHidden = true
            shield = nil
        }
    }
}
