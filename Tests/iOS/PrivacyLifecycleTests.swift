import IDCore
import SwiftUI
import XCTest
import VisionKit

@MainActor final class PrivacyLifecycleTests: XCTestCase {
    private struct Auth: Authenticator { func authenticate(reason: String) async -> Bool { true } }
    func testExpiredReturnKeepsShieldUntilAuthenticated() async {
        var now = ContinuousClock.now
        let session = SessionLock(authenticator: Auth(), now: { now })
        _ = await session.unlock()
        let anchor = PrivacyCover.ShieldAnchor(session: session)
        defer { anchor.stop() }
        anchor.cover(); now += .seconds(301); anchor.uncover()
        XCTAssertFalse(session.isUnlocked)
        XCTAssertTrue(anchor.isCovered, "The expired editor must stay covered while its presentation is being removed")
        _ = await session.unlock(); anchor.uncover()
        XCTAssertFalse(anchor.isCovered)
        anchor.cover(); now += .seconds(299); anchor.uncover()
        XCTAssertTrue(session.isUnlocked)
        XCTAssertFalse(anchor.isCovered)
    }

    func testCancelledScanCannotDeliverSuccessOrFailure() async {
        for succeeds in [true, false] {
            var resume: CheckedContinuation<Void, Never>?
            var completions = 0
            let scanner = DocumentScanner(kind: .pan) { _ in completions += 1 }
            let coordinator = scanner.makeCoordinator()
            coordinator.recognize {
                await withCheckedContinuation { resume = $0 }
                if !succeeds { throw CancellationError() }
                return ScanOutcome(fields: [.name: "Audit scan"], colors: nil)
            }
            for _ in 0..<1000 { if resume != nil { break }; await Task.yield() }
            XCTAssertNotNil(resume)
            coordinator.cancel(); resume?.resume()
            for _ in 0..<100 { await Task.yield() }
            XCTAssertEqual(completions, 0)
        }
    }

    func testNativeEditorCopyCutPasteAndTerminationOwnership() async throws {
        var value = "Audit 🙂 selection"
        let original = value
        let host = UIHostingController(rootView: SensitiveTextField(title: "Name",
            text: Binding(get: { value }, set: { value = $0 }), input: .text, canCopy: { true }))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        func field(_ view: UIView) -> SensitiveNativeField? {
            (view as? SensitiveNativeField) ?? view.subviews.lazy.compactMap(field).first
        }
        let input = try XCTUnwrap(field(host.view))
        XCTAssertEqual(input.text?.count, value.count)
        XCTAssertTrue(input.becomeFirstResponder())
        input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
        XCTAssertFalse(input.selectedTextRange?.isEmpty ?? true)
        input.copy(nil)
        XCTAssertTrue(UIPasteboard.general.string == value)
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertFalse(UIPasteboard.general.hasStrings)
        input.cut(nil)
        XCTAssertTrue(value.isEmpty)
        XCTAssertTrue(UIPasteboard.general.hasStrings)
        input.paste(nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(value == original)
        XCTAssertTrue(input.undoManager?.canUndo == true)
        input.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(value.isEmpty)
        input.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(value == original)
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertFalse(UIPasteboard.general.hasStrings)
    }

    func testNativeClipboardExpiresAfterSixtySeconds() async throws {
        let input = SensitiveNativeField()
        input.text = "Audit expiry"; input.canCopy = { true }
        input.selectedTextRange = input.textRange(from: input.beginningOfDocument, to: input.endOfDocument)
        input.copy(nil)
        XCTAssertTrue(UIPasteboard.general.hasStrings)
        try await Task.sleep(for: .seconds(61))
        XCTAssertFalse(UIPasteboard.general.hasStrings)
    }

    func testMultilineEditorCopyCutAndPasteUpdatesBinding() async throws {
        var value = "Audit 🙂\nnotes"
        let original = value
        let host = UIHostingController(rootView: SensitiveTextField(title: "Notes",
            text: Binding(get: { value }, set: { value = $0 }), input: .multiline, canCopy: { true }))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 160)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        func field(_ view: UIView) -> SensitiveNativeTextView? {
            (view as? SensitiveNativeTextView) ?? view.subviews.lazy.compactMap(field).first
        }
        let input = try XCTUnwrap(field(host.view))
        XCTAssertTrue(input.becomeFirstResponder())
        input.selectedRange = NSRange(location: 0, length: (original as NSString).length)
        input.copy(nil)
        XCTAssertTrue(UIPasteboard.general.string == original)
        input.cut(nil)
        XCTAssertTrue(value.isEmpty)
        input.paste(nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(value == original)
        XCTAssertTrue(input.undoManager?.canUndo == true)
        input.undoManager?.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(value.isEmpty)
        input.undoManager?.redo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(value == original)
        NotificationCenter.default.post(name: UIApplication.willTerminateNotification, object: nil)
        XCTAssertFalse(UIPasteboard.general.hasStrings)
    }

    func testReplacementScanRejectsOlderCompletionAndCancelledAttemptCannotRestart() async {
        var old: CheckedContinuation<Void, Never>?
        var delivered = 0
        let scanner = DocumentScanner(kind: .pan) { _ in delivered += 1 }
        let coordinator = scanner.makeCoordinator()
        coordinator.recognize {
            await withCheckedContinuation { old = $0 }
            return ScanOutcome(fields: [:], colors: nil)
        }
        for _ in 0..<1000 { if old != nil { break }; await Task.yield() }
        coordinator.recognize { ScanOutcome(fields: [:], colors: nil) }
        for _ in 0..<100 { await Task.yield() }
        old?.resume()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(delivered, 1)
        let dismissed = scanner.makeCoordinator()
        dismissed.cancel()
        dismissed.recognize { ScanOutcome(fields: [:], colors: nil) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(delivered, 1)
    }

    func testNativeScannerDismantleCancelsCoordinator() async throws {
        try XCTSkipUnless(DocumentScanner.isSupported, "VisionKit document camera requires a supported physical device")
        var delivered = 0
        let coordinator = DocumentScanner(kind: .pan) { _ in delivered += 1 }.makeCoordinator()
        let controller = VNDocumentCameraViewController()
        controller.delegate = coordinator
        DocumentScanner.dismantleUIViewController(controller, coordinator: coordinator)
        XCTAssertNil(controller.delegate)
        coordinator.recognize { ScanOutcome(fields: [:], colors: nil) }
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(delivered, 0)
    }

    func testRevealedCVVUsesSystemOnlyKeyboardAndStillEdits() async throws {
        var value = "123"
        let host = UIHostingController(rootView: SensitiveTextField(title: "CVV",
            text: Binding(get: { value }, set: { value = $0 })))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 80)
        let window = UIWindow(frame: host.view.frame)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutIfNeeded()
        func field(_ view: UIView) -> SensitiveNativeField? {
            (view as? SensitiveNativeField) ?? view.subviews.lazy.compactMap(field).first
        }
        let input = try XCTUnwrap(field(host.view))
        XCTAssertEqual(input.text?.count, value.count)
        XCTAssertFalse(input.allTargets.isEmpty)
        XCTAssertEqual(input.keyboardType, .phonePad, "Apple excludes keyboard extensions from phonePad fields")
        input.text = "456"; input.sendActions(for: .editingChanged)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(value == "456")
        XCTAssertFalse(input.canPerformAction(#selector(UIResponderStandardEditActions.copy(_:)), withSender: nil))
    }
}
