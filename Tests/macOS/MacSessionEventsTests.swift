import AppKit
import XCTest
import IDCore

private struct SuccessfulAuth: Authenticator {
    func authenticate(reason: String) async -> Bool { true }
}

@MainActor final class MacSessionEventsTests: XCTestCase {
    func testScreenSaverAndSessionResignLockDespiteVisiblePanel() async {
        let workspace = NotificationCenter(), distributed = NotificationCenter()
        let session = SessionLock(authenticator: SuccessfulAuth())
        let events = MacSessionEvents(session: session, workspaceCenter: workspace, distributedCenter: distributed)
        defer { events.stop() }
        _ = await session.unlock()
        events.updatePresence(mainWindowPresent: true, panelVisible: true)
        distributed.post(name: .init("com.apple.screensaver.didstart"), object: nil)
        events.updatePresence(mainWindowPresent: true, panelVisible: true)
        XCTAssertFalse(session.isUnlocked)
        distributed.post(name: .init("com.apple.screensaver.didstop"), object: nil)
        _ = await session.unlock()
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        events.updatePresence(mainWindowPresent: true, panelVisible: true)
        XCTAssertFalse(session.isUnlocked)
    }

    func testPanelKeepsSessionPresentAndClosingStartsTimeout() async {
        var now = ContinuousClock.now
        let session = SessionLock(authenticator: SuccessfulAuth(), now: { now })
        let events = MacSessionEvents(session: session)
        defer { events.stop() }
        _ = await session.unlock()
        events.updatePresence(mainWindowPresent: false, panelVisible: true)
        now += .seconds(600); session.evaluate()
        XCTAssertTrue(session.isUnlocked)
        events.updatePresence(mainWindowPresent: false, panelVisible: false)
        now += .seconds(299); session.evaluate()
        XCTAssertTrue(session.isUnlocked)
        now += .seconds(1); session.evaluate()
        XCTAssertFalse(session.isUnlocked)
    }

    func testReturningWindowEvaluatesExpiredSessionBeforeClearingAway() async {
        var now = ContinuousClock.now
        let session = SessionLock(authenticator: SuccessfulAuth(), now: { now })
        let events = MacSessionEvents(session: session)
        defer { events.stop() }
        _ = await session.unlock()
        events.updatePresence(mainWindowPresent: false, panelVisible: false)
        now += .seconds(300)
        events.updatePresence(mainWindowPresent: true, panelVisible: false)
        XCTAssertFalse(session.isUnlocked)
    }

    func testWindowPresenceResetsContinuousAwayTime() async {
        var now = ContinuousClock.now
        let session = SessionLock(authenticator: SuccessfulAuth(), now: { now })
        let events = MacSessionEvents(session: session)
        defer { events.stop() }
        _ = await session.unlock()
        events.updatePresence(mainWindowPresent: false, panelVisible: false)
        now += .seconds(200)
        events.updatePresence(mainWindowPresent: true, panelVisible: false)
        events.updatePresence(mainWindowPresent: false, panelVisible: false)
        now += .seconds(200); session.evaluate()
        XCTAssertTrue(session.isUnlocked)
    }

    func testSleepNotificationsLockImmediately() async {
        let session = SessionLock(authenticator: SuccessfulAuth())
        let events = MacSessionEvents(session: session)
        defer { events.stop() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            _ = await session.unlock()
            NSWorkspace.shared.notificationCenter.post(name: name, object: nil)
            XCTAssertFalse(session.isUnlocked)
        }
        _ = await session.unlock()
        events.lock()
        XCTAssertFalse(session.isUnlocked)
    }
}
