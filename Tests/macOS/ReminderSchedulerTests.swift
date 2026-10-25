import Foundation
import IDCore
import SwiftData
import XCTest
import CoreData

@MainActor private final class FakeReminderCenter: ReminderNotificationCenter {
    var pending: Set<String> = []
    var delivered: Set<String> = []
    var holdAdd = false
    var addition: CheckedContinuation<Void, Never>?
    func pendingIdentifiers() async -> [String] { Array(pending) }
    func deliveredIdentifiers() async -> [String] { Array(delivered) }
    func authorize() async throws -> Bool { true }
    func removePending(_ identifiers: [String]) { pending.subtract(identifiers) }
    func removeDelivered(_ identifiers: [String]) { delivered.subtract(identifiers) }
    func add(_ reminder: PlannedReminder) async throws {
        if holdAdd { await withCheckedContinuation { addition = $0 } }
        pending.insert(reminder.identifier)
    }
    func finishAdd() { holdAdd = false; addition?.resume(); addition = nil }
}

@MainActor final class ReminderSchedulerTests: XCTestCase {
    private func fixture() throws -> IDRecord {
        try IDRecord(kind: .passport, person: nil, payload: IDPayload(values: ["dateOfExpiry": "2099-04-15"]))
    }

    func testDeletionReconcileRemovesPendingAndDelivered() async throws {
        let center = FakeReminderCenter(), record = try fixture()
        let id = ReminderPlanner.identifierPrefix + record.id.uuidString
        center.pending = [id, "unrelated"]; center.delivered = [id, "unrelated"]
        await ReminderScheduler(center: center).reschedule([])
        XCTAssertEqual(center.pending, ["unrelated"])
        XCTAssertEqual(center.delivered, ["unrelated"])
    }

    func testDeletedRecordCannotSurviveAnOutstandingAdd() async throws {
        let center = FakeReminderCenter(), record = try fixture()
        let scheduler = ReminderScheduler(center: center)
        center.holdAdd = true
        let old = Task { await scheduler.reschedule([record]) }
        for _ in 0..<1000 { if center.addition != nil { break }; await Task.yield() }
        XCTAssertNotNil(center.addition)
        old.cancel()
        let deleted = Task { await scheduler.reschedule([]) }
        for _ in 0..<100 { await Task.yield() }
        center.finishAdd()
        await old.value; await deleted.value
        XCTAssertTrue(center.pending.isEmpty)
    }

    func testExplicitDeleteImmediatelyClearsBothCopies() {
        let center = FakeReminderCenter(), id = UUID()
        let identifier = ReminderPlanner.identifierPrefix + id.uuidString
        center.pending = [identifier]; center.delivered = [identifier]
        let scheduler = ReminderScheduler(center: center)
        scheduler.remove(recordID: id)
        XCTAssertTrue(center.pending.isEmpty && center.delivered.isEmpty)
    }

    func testStoreChangesReconcileWithoutAnyRootView() async throws {
        let container = try IDStore.makeContainer(inMemory: true)
        container.mainContext.autosaveEnabled = false
        let record = try fixture(), center = FakeReminderCenter()
        container.mainContext.insert(record); try container.mainContext.save()
        let scheduler = ReminderScheduler(container: container, center: center)
        await scheduler.reschedule([record])
        XCTAssertFalse(center.pending.isEmpty)
        container.mainContext.delete(record); try container.mainContext.save()
        for _ in 0..<1000 { if center.pending.isEmpty { break }; await Task.yield() }
        XCTAssertTrue(center.pending.isEmpty, "A save must reconcile without a root view")
        center.pending = ["expiry-remote-deleted"]; center.delivered = center.pending
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange, object: nil)
        for _ in 0..<1000 { if center.pending.isEmpty && center.delivered.isEmpty { break }; await Task.yield() }
        XCTAssertTrue(center.pending.isEmpty && center.delivered.isEmpty, "An imported change must reconcile without a root view")
    }
}
