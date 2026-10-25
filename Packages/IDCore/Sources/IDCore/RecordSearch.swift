import Foundation

public enum RecordSearch {
    public static func matches(_ query: String, kind: IDKind, nickname: String, personName: String?, payload: IDPayload) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let names: [FieldKey] = [.name, .surname, .givenNames, .cardholderName, .accountHolder, .bank]
        let masked: [FieldKey] = [.aadhaarNumber, .vid, .cardNumber, .accountNumber]
        let candidates = [kind.displayName, nickname, personName ?? "Me"]
            + names.compactMap { payload[$0] }
            + masked.compactMap { key in payload[key].map { String(Validator.normalized($0, for: key).suffix(4)) } }
        return candidates.contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }
}
