import Foundation

public struct PFAccount: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var memberID: String
    public var employer: String

    public init(id: UUID = UUID(), memberID: String, employer: String) {
        self.id = id
        self.memberID = memberID
        self.employer = employer
    }
}

public struct IDPayload: Codable, Equatable, Sendable {
    public var values: [String: String]
    public var pfAccounts: [PFAccount]

    public init(values: [String: String] = [:], pfAccounts: [PFAccount] = []) {
        self.values = values
        self.pfAccounts = pfAccounts
    }

    public subscript(key: FieldKey) -> String? {
        get { values[key.rawValue] }
        set { values[key.rawValue] = newValue == "" ? nil : newValue }
    }

    public static func decode(_ data: Data) throws -> IDPayload {
        try JSONDecoder().decode(Self.self, from: data)
    }

    public func encoded() throws -> Data { try JSONEncoder().encode(self) }
}
