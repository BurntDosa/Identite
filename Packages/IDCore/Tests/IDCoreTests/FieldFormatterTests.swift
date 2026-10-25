import Foundation
import Testing
@testable import IDCore

struct FieldFormatterTests {
 @Test func displayDates() {
  #expect(FieldFormatter.display("1990-01-01", for: .date) == "01/01/1990")
  #expect(FieldFormatter.display("2028-02-29", for: .date) == "29/02/2028")
  #expect(FieldFormatter.display("2027-02-29", for: .date) == "2027-02-29")
  #expect(FieldFormatter.display("invalid", for: .date) == "invalid")
  #expect(FieldFormatter.display("02/28", for: .monthYear) == "02/28")
  #expect(FieldFormatter.display("1990-01-01", for: .text) == "1990-01-01")
 }

@Test func grouping() {
  #expect(FieldFormatter.grouped("234123412346", for: .aadhaarNumber) == "2341 2341 2346")
  #expect(FieldFormatter.grouped("9876543210987656", for: .vid) == "9876 5432 1098 7656")
  #expect(FieldFormatter.grouped("4111111111111111", for: .cardNumber) == "4111 1111 1111 1111")
  #expect(FieldFormatter.grouped("378282246310005", for: .cardNumber) == "3782 822463 10005")
}
@Test func masking() {
  #expect(FieldFormatter.masked("234123412346", for: .aadhaarNumber) == "•••• •••• 2346")
  #expect(FieldFormatter.masked("4111111111114242", for: .cardNumber) == "•••• •••• •••• 4242")
  #expect(FieldFormatter.masked("001234567890", for: .accountNumber) == "•••• 7890")
  #expect(FieldFormatter.masked("12", for: .accountNumber) == "••••")
  #expect(FieldFormatter.masked("Test Person", for: .name) == "Test Person")
}

}
