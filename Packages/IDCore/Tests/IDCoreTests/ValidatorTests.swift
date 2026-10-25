import Foundation
import Testing
@testable import IDCore

struct ValidatorTests {
@Test func verhoeff() {
  #expect(Validator.verhoeffCheckDigit(for: "236") == 3)
  #expect(Validator.verhoeffIsValid("2363")); #expect(!Validator.verhoeffIsValid("2364"))
}
@Test func aadhaar() {
  #expect(Validator.warning(for: .aadhaarNumber, value: "234123412346") == nil)
  #expect(Validator.warning(for: .aadhaarNumber, value: "234123412345") != nil) // bad checksum
  #expect(Validator.warning(for: .aadhaarNumber, value: "134123412346") != nil) // starts with 1
  #expect(Validator.warning(for: .vid, value: "9876543210987659") == nil)
}
@Test func invalidChecksumInput() {
  #expect(!Validator.verhoeffIsValid("9876543210987656"))
  #expect(!Validator.verhoeffIsValid(""))
  #expect(!Validator.luhnIsValid(""))
  #expect(!Validator.luhnIsValid("4111x11111111111"))
}
@Test func luhn() {
  #expect(Validator.luhnIsValid("4111111111111111")); #expect(!Validator.luhnIsValid("4111111111111112"))
  #expect(Validator.luhnIsValid("378282246310005"))
}
@Test func normalisesBeforeValidating() {
  #expect(Validator.normalized("2341-2341 2346", for: .aadhaarNumber) == "234123412346")
  #expect(Validator.normalized(" abcde1234f ", for: .panNumber) == "ABCDE1234F")
  #expect(Validator.normalized("hdfc0001234", for: .ifsc) == "HDFC0001234")
  #expect(Validator.normalized("  Test Person ", for: .name) == "Test Person")
}
@Test func formats() {
  #expect(Validator.warning(for: .panNumber, value: "ABCDE1234F") == nil)
  #expect(Validator.warning(for: .panNumber, value: "ABCD1234F") != nil)
  #expect(Validator.warning(for: .ifsc, value: "HDFC0001234") == nil)
  #expect(Validator.warning(for: .ifsc, value: "HDFC1001234") != nil)
  #expect(Validator.warning(for: .passportNumber, value: "K1234567") == nil)
  #expect(Validator.warning(for: .epicNumber, value: "ABC1234567") == nil)
  #expect(Validator.warning(for: .dlNumber, value: "MH12-20110012345") == nil)
  #expect(Validator.warning(for: .name, value: "") == nil)
}
@Test func cardExpiryThisMonthIsNotExpired() {
  var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
  let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 21))!
  #expect(Validator.warning(for: .cardExpiry, value: "10/26", now: now, calendar: cal) == nil)
  #expect(Validator.warning(for: .cardExpiry, value: "09/26", now: now, calendar: cal) != nil)
  #expect(Validator.warning(for: .cardExpiry, value: "13/26", now: now, calendar: cal) != nil)
}

}
