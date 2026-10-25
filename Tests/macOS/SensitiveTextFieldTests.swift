import AppKit
import SwiftUI
import XCTest
import IDCore
import SwiftData

@MainActor final class SensitiveTextFieldTests: XCTestCase {
    private struct Auth: Authenticator { func authenticate(reason: String) async -> Bool { true } }

    func testStoredEditorCopyAndCutUseOwnedClipboard() async throws {
        let container = try IDStore.makeContainer(inMemory: true)
        let record = try IDRecord(kind: .pan, person: nil, payload: IDPayload(values: ["name": "Audit Person"]))
        record.nickname = "Audit nickname"; record.notes = "Audit notes"
        container.mainContext.insert(record)
        let session = SessionLock(authenticator: Auth())
        _ = await session.unlock()
        let host = NSHostingView(rootView: RecordEditorView(kind: .pan, record: record)
            .modelContainer(container).environment(session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close(); NSPasteboard.general.clearContents() }
        try await Task.sleep(for: .milliseconds(300))
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        for value in ["Audit nickname", "Audit Person", "Audit notes"] {
            let input = try XCTUnwrap(fields(host).first { $0.stringValue == value && $0.isEditable })
            XCTAssertTrue(window.makeFirstResponder(input))
            let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
            editor.selectAll(nil); editor.copy(nil)
            XCTAssertTrue(NSPasteboard.general.types?.contains(.init("org.nspasteboard.ConcealedType")) == true)
            XCTAssertTrue(NSPasteboard.general.types?.contains(.init("org.nspasteboard.TransientType")) == true)
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            XCTAssertTrue(NSPasteboard.general.string(forType: .string) == nil, "Native editor copies must register ownership")
            editor.selectAll(nil); editor.cut(nil)
            XCTAssertTrue(editor.string.isEmpty)
            XCTAssertTrue(NSPasteboard.general.string(forType: .string) == value)
            editor.paste(nil)
            XCTAssertTrue(editor.string == value, "Paste must remain usable")
            NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
            XCTAssertTrue(NSPasteboard.general.string(forType: .string) == nil)
        }
    }

    func testNativeCopyExpiresAfter60SecondsAndRespectsRevocation() async throws {
        var allowed = true
        let editor = SensitiveFieldEditor()
        editor.string = "Audit selection"; editor.canCopy = { allowed }
        editor.selectAll(nil); editor.copy(nil)
        defer { NSPasteboard.general.clearContents() }
        XCTAssertTrue(NSPasteboard.general.string(forType: .string) != nil)
        try await Task.sleep(for: .seconds(61))
        XCTAssertTrue(NSPasteboard.general.string(forType: .string) == nil)
        allowed = false
        editor.copy(nil); editor.cut(nil)
        XCTAssertTrue(NSPasteboard.general.string(forType: .string) == nil)
        XCTAssertFalse(editor.string.isEmpty)
    }

    func testDatePickerDoesNotOfferUnmanagedNativeCopy() async throws {
        let host = NSHostingView(rootView: DatePicker("Expiry", selection: .constant(Date(timeIntervalSince1970: 0)), displayedComponents: .date))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close(); NSPasteboard.general.clearContents() }
        try await Task.sleep(for: .milliseconds(150))
        func picker(_ view: NSView) -> NSDatePicker? {
            (view as? NSDatePicker) ?? view.subviews.lazy.compactMap(picker).first
        }
        let input = try XCTUnwrap(picker(host))
        XCTAssertTrue(window.makeFirstResponder(input))
        NSPasteboard.general.clearContents()
        NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
        XCTAssertTrue(NSPasteboard.general.string(forType: .string) == nil)
    }

    func testMultilineReturnAndUnicodeCutKeepEditing() async throws {
        var value = "Audit 🙂"
        let host = NSHostingView(rootView: SensitiveTextField(title: "Notes",
            text: Binding(get: { value }, set: { value = $0 }), input: .multiline, canCopy: { true }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 350, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.makeKeyAndOrderFront(nil)
        defer { window.close(); NSPasteboard.general.clearContents() }
        try await Task.sleep(for: .milliseconds(150))
        func field(_ view: NSView) -> NSTextField? {
            (view as? NSTextField) ?? view.subviews.lazy.compactMap(field).first
        }
        let input = try XCTUnwrap(field(host))
        XCTAssertTrue(window.makeFirstResponder(input))
        let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
        editor.insertNewline(nil)
        XCTAssertTrue(value.contains("\n"), "Return must insert a newline in Notes")
        try await Task.sleep(for: .milliseconds(100))
        editor.selectAll(nil); editor.cut(nil)
        XCTAssertTrue(value.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        editor.paste(nil)
        XCTAssertTrue(value.contains("🙂") && value.contains("\n"))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(editor.undoManager?.canUndo == true)
        XCTAssertTrue(editor.validateUserInterfaceItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z")))
        XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        XCTAssertTrue(editor.string.isEmpty, "Undo must revert the native paste")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(value.isEmpty, "Undo must revert the paste through the binding")
        XCTAssertTrue(editor.validateUserInterfaceItem(NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "z")))
        XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("redo:"), with: nil))
        XCTAssertTrue(value.contains("🙂") && value.contains("\n"))
    }

    func testRevealedFieldBlocksNativeExportAndStillEdits() throws {
        var value = "123"
        let host = NSHostingView(rootView: SensitiveTextField(title: "CVV",
            text: Binding(get: { value }, set: { value = $0 })))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        func field(_ view: NSView) -> NSTextField? {
            (view as? NSTextField) ?? view.subviews.lazy.compactMap { field($0) }.first
        }
        let input = try XCTUnwrap(field(host))
        XCTAssertTrue(window.makeFirstResponder(input))
        let editor = try XCTUnwrap(input.currentEditor() as? NSTextView)
        XCTAssertEqual(editor.string, "123")
        editor.setSelectedRange(NSRange(location: 0, length: 3))
        XCTAssertEqual(editor.selectedRange().length, 3)
        let pasteboard = NSPasteboard(name: .init("cvv-regression-\(UUID())"))
        XCTAssertFalse(editor.writeSelection(to: pasteboard, type: .string))
        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertFalse(editor.writeSelection(to: pasteboard, types: [.string]))
        XCTAssertNil(editor.validRequestor(forSendType: .string, returnType: nil))
        for action in [#selector(NSText.copy(_:)), #selector(NSText.cut(_:))] {
            XCTAssertFalse(editor.validateUserInterfaceItem(NSMenuItem(title: "", action: action, keyEquivalent: "")))
        }
        editor.insertText("456", replacementRange: NSRange(location: 0, length: 3))
        XCTAssertEqual(value, "456")
    }
}
