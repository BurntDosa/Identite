import Foundation
import Testing
@testable import IDCore

struct MRZParserTests {
@Test func parsesSpecimen() {
  let r = MRZParser.parseTD3(["some header text"] + specimen)
  #expect(r == MRZResult(passportNumber: "L898902C3", surname: "ERIKSSON", givenNames: "ANNA MARIA", nationality: "UTO", sex: "F", dateOfBirth: "1974-08-12", dateOfExpiry: "2012-04-15"))
}
@Test func toleratesOCRSpacing() { #expect(MRZParser.parseTD3(specimen.map { $0.replacingOccurrences(of: "<<<<", with: "<< <<") }) != nil) }
@Test func rejectsBadCheckDigit() { #expect(MRZParser.parseTD3([specimen[0], specimen[1].replacingOccurrences(of: "L898902C36", with: "L898902C37")]) == nil) }

}
