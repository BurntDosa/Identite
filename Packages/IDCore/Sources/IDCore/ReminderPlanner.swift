import Foundation

public struct PlannedReminder: Equatable, Sendable {
    public let identifier: String
    public let fireDate: Date
    public let title: String
    public let body: String

    public init(identifier: String, fireDate: Date, title: String, body: String) {
        self.identifier = identifier
        self.fireDate = fireDate
        self.title = title
        self.body = body
    }
}

public enum ReminderPlanner {
    public static let identifierPrefix = "expiry-"

    public static func expiryDate(kind: IDKind, payload: IDPayload, calendar: Calendar) -> Date? {
        switch kind {
        case .passport, .drivingLicence:
            guard let value = payload[.dateOfExpiry], value.range(of: "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}\\z", options: .regularExpression) != nil else { return nil }
            let parts = value.split(separator: "-").compactMap { Int($0) }
            let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
            guard let date = calendar.date(from: components), calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
            return date
        case .creditCard, .debitCard:
            guard let value = payload[.cardExpiry], value.range(of: "\\A(0[1-9]|1[0-2])/[0-9]{2}\\z", options: .regularExpression) != nil,
                  let month = Int(value.prefix(2)), let year = Int(value.suffix(2)),
                  let start = calendar.date(from: DateComponents(year: 2000 + year, month: month, day: 1)),
                  let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
            return calendar.date(byAdding: .day, value: -1, to: nextMonth)
        default: return nil
        }
    }

    public static func reminder(recordID: UUID, kind: IDKind, nickname: String, personName: String?,
                                payload: IDPayload, now: Date, calendar: Calendar) -> PlannedReminder? {
        guard let expiry = expiryDate(kind: kind, payload: payload, calendar: calendar), expiry > now else { return nil }
        let months = kind == .passport ? 6 : kind == .drivingLicence ? 3 : 1
        guard let leadDate = calendar.date(byAdding: .month, value: -months, to: expiry),
              var fireDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDate) else { return nil }
        if fireDate <= now {
            guard let next = calendar.nextDate(after: now, matching: DateComponents(hour: 9, minute: 0, second: 0), matchingPolicy: .nextTime) else { return nil }
            fireDate = next
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "d MMM yyyy"
        let title = kind.displayName + " expiring soon"
        let name = nickname.isEmpty ? kind.displayName : nickname
        let person = personName.map { " (\($0))" } ?? ""
        return PlannedReminder(identifier: identifierPrefix + recordID.uuidString, fireDate: fireDate,
                               title: title, body: "\(name)\(person) expires on \(formatter.string(from: expiry)).")
    }
}
