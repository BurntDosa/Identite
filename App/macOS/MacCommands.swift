import SwiftUI
import IDCore

struct MacActions {
    var add: () -> Void
    var edit: (() -> Void)?
    var delete: (() -> Void)?
}
private struct IDActionsKey: FocusedValueKey { typealias Value = MacActions }
@MainActor @Observable final class MacCopySelection {
    var owner: UUID?
    var action: (() -> Void)?
    weak var window: NSWindow?
    func select(_ id: UUID, action: @escaping () -> Void) {
        owner = id; self.action = action; window = NSApp.keyWindow
    }
    func clear(_ id: UUID) {
        if owner == id { owner = nil; action = nil; window = nil }
    }
}
extension FocusedValues {
    var idActions: MacActions? {
        get { self[IDActionsKey.self] }
        set { self[IDActionsKey.self] = newValue }
    }

}

struct MacCommands: Commands {
    let session: SessionLock
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.idActions) private var actions
    let copySelection: MacCopySelection
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New ID…") { actions?.add() }.keyboardShortcut("n").disabled(actions == nil || !session.isUnlocked)
            Button("Open Identité") { openWindow(id: "main") }
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x").disabled(!session.isUnlocked)
            Button("Copy") {
                if copySelection.window === NSApp.keyWindow, !(NSApp.keyWindow?.firstResponder is NSTextView), let action = copySelection.action { action() }
                else { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
            }.keyboardShortcut("c").disabled(!session.isUnlocked)
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v").disabled(!session.isUnlocked)
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a").disabled(!session.isUnlocked)
            Divider()
            Button("Edit ID…") { actions?.edit?() }.keyboardShortcut("e").disabled(actions?.edit == nil || !session.isUnlocked)
            Button("Delete ID…") { actions?.delete?() }.keyboardShortcut(.delete, modifiers: [])
                .disabled(actions?.delete == nil || !session.isUnlocked)
        }
        CommandGroup(after: .sidebar) {
            Button("Lock") { session.lockNow() }.keyboardShortcut("l").disabled(!session.isUnlocked)
        }
        SidebarCommands()
    }
}
