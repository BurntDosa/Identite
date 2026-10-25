import Foundation
import SwiftData

@Model public final class Person {
    public var id: UUID = UUID()
    @Attribute(.allowsCloudEncryption) public var name: String = ""
    public var createdAt: Date = Date.now
    @Relationship(deleteRule: .nullify, inverse: \IDRecord.person)
    public var records: [IDRecord]? = []

    public init(name: String) {
        self.name = name
    }

    public var canDelete: Bool { records?.isEmpty ?? true }
}

@Model public final class IDRecord {
    public var id: UUID = UUID()
    public var kindRaw: String = ""
    public var person: Person?
    @Attribute(.allowsCloudEncryption) public var nickname: String = ""
    @Attribute(.allowsCloudEncryption) public var notes: String = ""
    @Attribute(.allowsCloudEncryption) public var payloadData: Data = Data()
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(kind: IDKind, person: Person?, payload: IDPayload) throws {
        self.kindRaw = kind.rawValue
        self.person = person
        self.payloadData = try payload.encoded()
    }

    public var kind: IDKind? { IDKind(rawValue: kindRaw) }

    public func payload() throws -> IDPayload {
        try IDPayload.decode(payloadData)
    }

    public func setPayload(_ payload: IDPayload) throws {
        payloadData = try payload.encoded()
        updatedAt = .now
    }
}
