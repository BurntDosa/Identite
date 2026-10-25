import Foundation
#if os(iOS)
import UIKit
import UniformTypeIdentifiers
#elseif os(macOS)
import AppKit
#endif

@MainActor public enum SecureClipboard {
    public static let lifetime: TimeInterval = 60

    #if os(macOS)
    private static var ownedValues: [NSPasteboard.Name: (NSPasteboard, Int)] = [:]
    #else
    private static var ownedChangeCount: Int?
    #endif
    private static let lifecycleObservers: [any NSObjectProtocol] = {
        #if os(macOS)
        let names = [NSApplication.willTerminateNotification]
        #else
        // App switching must preserve copies for pasting; iOS enforces expiry while suspended.
        let names = [UIApplication.willTerminateNotification]
        #endif
        return names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { clearOwnedValues() }
            }
        }
    }()

    // Crash/force-quit can skip cleanup; macOS has no system pasteboard expiration (iOS also has a system expiry).
    private static func clearOwnedValues() {
        #if os(macOS)
        for (pasteboard, changeCount) in ownedValues.values where pasteboard.changeCount == changeCount {
            pasteboard.clearContents()
        }
        ownedValues.removeAll()
        #else
        if UIPasteboard.general.changeCount == ownedChangeCount { UIPasteboard.general.items = [] }
        ownedChangeCount = nil
        #endif
    }

    public static func copy(_ string: String, lifetime: TimeInterval = lifetime) {
        #if os(iOS)
        _ = lifecycleObservers
        UIPasteboard.general.setItems([[UTType.plainText.identifier: string]],
                                     options: [.localOnly: true, .expirationDate: Date.now.addingTimeInterval(lifetime)])
        ownedChangeCount = UIPasteboard.general.changeCount
        #elseif os(macOS)
        copy(string, to: .general, lifetime: lifetime)
        #endif
    }

    #if os(macOS)
    static func copy(_ string: String, to pasteboard: NSPasteboard, lifetime: TimeInterval) {
        copy(string, to: pasteboard, clearAfter: .seconds(lifetime))
    }

    static func copy(_ string: String, to pasteboard: NSPasteboard, clearAfter: Duration) {
        _ = lifecycleObservers
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(string, forType: .string)
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        pasteboard.setData(Data(), forType: .init("org.nspasteboard.TransientType"))
        let changeCount = pasteboard.changeCount
        ownedValues[pasteboard.name] = (pasteboard, changeCount)
        _ = Task { @MainActor in
            try await Task.sleep(for: clearAfter)
            if pasteboard.changeCount == changeCount { pasteboard.clearContents() }
            if ownedValues[pasteboard.name]?.1 == changeCount { ownedValues[pasteboard.name] = nil }
        }
    }
    #endif
}
