import Foundation
import Testing
@testable import IDCore

struct ReminderPlannerTests {
@Test func passportSixMonthsAhead() {
  var p = IDPayload(); p[.dateOfExpiry] = "2027-04-15"
  let r = ReminderPlanner.reminder(recordID: id, kind: .passport, nickname: "", personName: "Mom", payload: p, now: date(2026,1,1), calendar: cal)
  #expect(r?.fireDate == date(2026,10,15,9)); #expect(r?.body == "Passport (Mom) expires on 15 Apr 2027.")
}
@Test func leapFebruaryCard() {
  var p = IDPayload(); p[.cardExpiry] = "02/28"; p[.cardNumber] = "4111111111114242"
  #expect(ReminderPlanner.expiryDate(kind: .creditCard, payload: p, calendar: cal) == date(2028,2,29))
  let r = ReminderPlanner.reminder(recordID: id, kind: .creditCard, nickname: "HDFC", personName: nil, payload: p, now: date(2026,1,1), calendar: cal)
  #expect(r?.fireDate == date(2028,1,29,9)); #expect(r?.body.contains("4242") == false)
}
@Test func alreadyInsideWindowFiresNextNineAM() {
  var p = IDPayload(); p[.cardExpiry] = "10/26"
  #expect(ReminderPlanner.reminder(recordID: id, kind: .debitCard, nickname: "", personName: nil, payload: p, now: date(2026,10,21,12), calendar: cal)?.fireDate == date(2026,10,22,9))
}
@Test func expiredGetsNone() {
  var p = IDPayload(); p[.dateOfExpiry] = "2026-01-01"
  #expect(ReminderPlanner.reminder(recordID: id, kind: .drivingLicence, nickname: "", personName: nil, payload: p, now: date(2026,10,21), calendar: cal) == nil)
}
@Test func kindsWithoutExpiryGetNone() { #expect(ReminderPlanner.reminder(recordID: id, kind: .aadhaar, nickname: "", personName: nil, payload: IDPayload(), now: date(2026,1,1), calendar: cal) == nil) }

@Test func beforeNineUsesTodayAndExactNineUsesTomorrow() {
  var p = IDPayload(); p[.dateOfExpiry] = "2026-11-01"
  #expect(ReminderPlanner.reminder(recordID: id, kind: .passport, nickname: "", personName: nil, payload: p, now: date(2026,10,21,8), calendar: cal)?.fireDate == date(2026,10,21,9))
  #expect(ReminderPlanner.reminder(recordID: id, kind: .passport, nickname: "", personName: nil, payload: p, now: date(2026,10,21,9), calendar: cal)?.fireDate == date(2026,10,22,9))
}
@Test func rejectsMalformedExpiry() {
  var p = IDPayload(); p[.dateOfExpiry] = "2027-02-30"
  #expect(ReminderPlanner.expiryDate(kind: .passport, payload: p, calendar: cal) == nil)
  p[.cardExpiry] = "13/28"
  #expect(ReminderPlanner.expiryDate(kind: .creditCard, payload: p, calendar: cal) == nil)
}
}
