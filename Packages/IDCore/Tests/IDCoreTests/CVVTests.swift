import Testing
@testable import IDCore

struct CVVTests {
    @Test func schemaIsOptionalAndAlwaysRequiresFreshAuthentication() throws {
        for kind in [IDKind.creditCard, .debitCard] {
            let spec = try #require(kind.fields.first { $0.key == .cvv })
            #expect(spec.input == .digits && spec.isOptional && spec.isMasked)
            #expect(spec.requiresFreshAuthentication && !spec.hasGroupedCopy)
        }
        #expect(IDKind.allCases.flatMap(\.fields).filter(\.requiresFreshAuthentication).allSatisfy { $0.key == .cvv })
        #expect(!FieldSpec(.name, "Name").requiresFreshAuthentication)
    }
    @Test func validatesAndMasksWithoutExposingDigits() {
        for value in ["123", "1234", ""] { #expect(Validator.warning(for: .cvv, value: value) == nil) }
        for value in ["12", "12345", "a12", "１２３", "123\n"] { #expect(Validator.warning(for: .cvv, value: value) != nil) }
        for value in ["", "1", "123", "1234", "12345"] { #expect(FieldFormatter.masked(value, for: .cvv) == "•••") }
        #expect(Validator.normalized(" 0 12 ", for: .cvv) == "012")
    }
    @Test func cvvIsNotSearchable() {
        let payload = IDPayload(values: ["cvv": "987"])
        #expect(!RecordSearch.matches("987", kind: .creditCard, nickname: "", personName: nil, payload: payload))
    }
}
