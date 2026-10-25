import Foundation
import IDCore
import UserNotifications
import SwiftData
import SwiftUI
import CoreData

@MainActor protocol ReminderNotificationCenter {
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func authorize() async throws -> Bool
    func add(_ reminder: PlannedReminder) async throws
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}

@MainActor struct SystemReminderCenter: ReminderNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func pendingIdentifiers() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func deliveredIdentifiers() async -> [String] { await center.deliveredNotifications().map { $0.request.identifier } }
    func authorize() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func removePending(_ identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
    func removeDelivered(_ identifiers: [String]) { center.removeDeliveredNotifications(withIdentifiers: identifiers) }
    func add(_ reminder: PlannedReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title; content.body = reminder.body
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

@MainActor final class ReminderScheduler: NSObject {
    private let center: any ReminderNotificationCenter
    private let container: ModelContainer?
    private var planned: [PlannedReminder] = []
    private var needsReconcile = false
    private var worker: Task<Void, Never>?

    init(container: ModelContainer? = nil, center: any ReminderNotificationCenter = SystemReminderCenter()) {
        self.container = container; self.center = center
        super.init()
        if container != nil {
            for name in [ModelContext.didSave, .NSPersistentStoreRemoteChange,
                         NSPersistentCloudKitContainer.eventChangedNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: name, object: nil)
            }
            requestReconcile()
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    @objc nonisolated private func storeChanged() {
        Task { @MainActor [weak self] in self?.requestReconcile() }
    }

    func requestReconcile() {
        guard let container else { return }
        // A fresh context reads committed imports without retaining a window's stale models or unsaved draft.
        let context = ModelContext(container)
        context.autosaveEnabled = false
        guard let records = try? context.fetch(FetchDescriptor<IDRecord>()) else { return }
        submit(records)
    }

    func remove(recordID: UUID) {
        let identifier = ReminderPlanner.identifierPrefix + recordID.uuidString
        center.removePending([identifier]); center.removeDelivered([identifier])
        planned.removeAll { $0.identifier == identifier }
        drain()
    }

    func reschedule(_ records: [IDRecord]) async {
        submit(records)
        await waitUntilIdle()
    }

    func waitUntilIdle() async { await worker?.value }

    private func submit(_ records: [IDRecord]) {
        planned = records.compactMap { record -> PlannedReminder? in
            guard let kind = record.kind, let payload = try? record.payload() else { return nil }
            return ReminderPlanner.reminder(recordID: record.id, kind: kind, nickname: record.nickname,
                personName: record.person?.name, payload: payload, now: .now, calendar: .current)
        }
        drain()
    }

    private func drain() {
        needsReconcile = true
        guard worker == nil else { return }
        worker = Task { @MainActor in
            while needsReconcile {
                needsReconcile = false
                await reconcile()
            }
            worker = nil
        }
    }

    private func reconcile() async {
        let planned = planned
        let existing = await center.pendingIdentifiers()
        let delivered = await center.deliveredIdentifiers()
        guard !needsReconcile else { return }
        center.removePending(existing.filter {
            $0.hasPrefix(ReminderPlanner.identifierPrefix)
        })
        let wanted = Set(planned.map(\.identifier))
        center.removeDelivered(delivered.filter { $0.hasPrefix(ReminderPlanner.identifierPrefix) && !wanted.contains($0) })
        guard !planned.isEmpty else { return }
        do {
            guard try await center.authorize() else { return }
            for reminder in planned {
                guard !needsReconcile else { return }
                try await center.add(reminder)
            }
        } catch { /* Notifications are optional; saving IDs does not depend on permission. */ }
    }
}

extension EnvironmentValues {
    @Entry var reminderScheduler: ReminderScheduler? = nil
}
