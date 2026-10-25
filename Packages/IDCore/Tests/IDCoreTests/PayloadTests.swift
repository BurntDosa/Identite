import Foundation
import Testing
@testable import IDCore

struct PayloadTests {
@Test func roundTrip() throws {
  var p = IDPayload(); p[.name] = "Test Person"; p.pfAccounts = [PFAccount(id: UUID(), memberID: "MHBAN00000000000000001", employer: "Acme")]
  #expect(try IDPayload.decode(p.encoded()) == p)
}
@Test func emptyStringRemovesKey() { var p = IDPayload(); p[.name] = "A"; p[.name] = ""; #expect(p.values.isEmpty) }
@Test func unknownKeysSurvive() throws {
  let json = #"{"values":{"name":"A","futureField":"x"},"pfAccounts":[]}"#.data(using: .utf8)!
  let p = try IDPayload.decode(json)
  #expect(try IDPayload.decode(p.encoded()).values["futureField"] == "x")
}
@Test func corruptDataThrows() { #expect(throws: (any Error).self) { try IDPayload.decode(Data("garbage".utf8)) } }

}
