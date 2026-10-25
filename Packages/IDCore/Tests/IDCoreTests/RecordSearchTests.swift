import Foundation
import Testing
@testable import IDCore

struct RecordSearchTests {
var card: IDPayload { var p = IDPayload(); p[.bank] = "HDFC Bank"; p[.cardNumber] = "4111567811114242"; return p }
@Test func matchesNicknameBankPersonKind() {
  #expect(RecordSearch.matches("salary", kind: .debitCard, nickname: "Salary card", personName: nil, payload: card))
  #expect(RecordSearch.matches("hdfc", kind: .debitCard, nickname: "", personName: nil, payload: card))
  #expect(RecordSearch.matches("me", kind: .debitCard, nickname: "", personName: nil, payload: card))
  #expect(RecordSearch.matches("debit", kind: .debitCard, nickname: "", personName: "Mom", payload: card))
}
@Test func lastFourOnly() {
  #expect(RecordSearch.matches("4242", kind: .debitCard, nickname: "", personName: nil, payload: card))
  #expect(!RecordSearch.matches("5678", kind: .debitCard, nickname: "", personName: nil, payload: card))
}
@Test func emptyQueryMatches() { #expect(RecordSearch.matches("  ", kind: .pan, nickname: "", personName: nil, payload: IDPayload())) }

}
