import Foundation
import Testing
@testable import IDCore

struct CardTextExtractorTests {
@Test func aadhaarPicksNumberNotVIDOrPhone() {
  let lines = ["Government of India", "Test Person", "DOB: 01/02/1990", "MALE", "2341 2341 2346", "VID : 9876 5432 1098 7659", "Mobile: 9876543210"]
  let f = CardTextExtractor.extract(kind: .aadhaar, lines: lines)
  #expect(f[.aadhaarNumber] == "234123412346"); #expect(f[.vid] == "9876543210987659")
  #expect(f[.dateOfBirth] == "1990-02-01"); #expect(f[.gender] == "Male"); #expect(f[.name] == "Test Person")
}
@Test func maskedAadhaarYieldsNoNumber() { #expect(CardTextExtractor.extract(kind: .aadhaar, lines: ["XXXX XXXX 2346"])[.aadhaarNumber] == nil) }
@Test func panNumber() { #expect(CardTextExtractor.extract(kind: .pan, lines: ["INCOME TAX DEPARTMENT", "ABCDE1234F"])[.panNumber] == "ABCDE1234F") }
@Test func cardTakesLatestExpiry() {
  let f = CardTextExtractor.extract(kind: .creditCard, lines: ["4111 1111 1111 1111", "VALID FROM 01/24", "VALID THRU 01/29"])
  #expect(f[.cardNumber] == "4111111111111111"); #expect(f[.cardExpiry] == "01/29")
}
@Test func passportUsesMRZ() { #expect(CardTextExtractor.extract(kind: .passport, lines: specimen)[.passportNumber] == "L898902C3") }
@Test func dlNumberAndBloodGroup() {
  let f = CardTextExtractor.extract(kind: .drivingLicence, lines: ["DL No: MH12 20110012345", "Blood Group: B+", "Valid Till: 31-12-2035"])
  #expect(f[.dlNumber] == "MH1220110012345"); #expect(f[.bloodGroup] == "B+"); #expect(f[.dateOfExpiry] == "2035-12-31")
}
@Test func manualKindsExtractNothing() { #expect(CardTextExtractor.extract(kind: .uan, lines: ["123456789012"]).isEmpty) }

@Test func voterLabelsAndAddress() {
  let f = CardTextExtractor.extract(kind: .voterID, lines: ["ABC1234567", "Name: Test Person", "Husband's Name: Test Relation", "FEMALE", "DOB: 02-03-1991", "Address: Test Street", "Test City 560001", "Unrelated text"])
  #expect(f[.name] == "Test Person"); #expect(f[.relationName] == "Test Relation")
  #expect(f[.gender] == "Female"); #expect(f[.dateOfBirth] == "1991-03-02")
  #expect(f[.address] == "Test Street\nTest City 560001")
}
@Test func panLabelsAndInvalidDate() {
  let f = CardTextExtractor.extract(kind: .pan, lines: ["Name", "Test Person", "Father's Name", "Test Parent", "31/02/1990"])
  #expect(f[.name] == "Test Person"); #expect(f[.fatherName] == "Test Parent")
  #expect(f[.dateOfBirth] == nil)
}
@Test func noAadhaarInsideVID() {
  #expect(CardTextExtractor.extract(kind: .aadhaar, lines: ["VID: 9876 5432 1098 7659"])[.aadhaarNumber] == nil)
}
}

struct DocumentParagraphTests {
    @Test func addressDoesNotConsumeNextParagraph() {
        let fields = CardTextExtractor.extract(kind: .voterID, paragraphs: ["Name: Fake Person", "Address:\n12 Fake Street\nFake Town", "Election officer\nUnrelated office"])
        #expect(fields[.address] == "12 Fake Street\nFake Town")
        #expect(fields[.name] == "Fake Person")
    }
    @Test(arguments: [IDKind.drivingLicence, .passport, .voterID]) func detectedAddressHint(kind: IDKind) {
        let fields = CardTextExtractor.extract(kind: kind, paragraphs: ["Unlabelled document"], detectedAddresses: ["12 Fake Road, Fake Town 560001"])
        #expect(fields[.address] == "12 Fake Road, Fake Town 560001")
    }
    @Test func labelledAddressWinsOverOfficeHint() {
        let fields = CardTextExtractor.extract(kind: .drivingLicence, paragraphs: ["Address: 12 Fake Street\nFake Town 560001"], detectedAddresses: ["Other office"])
        #expect(fields[.address] == "12 Fake Street\nFake Town 560001")
        #expect(CardTextExtractor.extract(kind: .creditCard, paragraphs: [], detectedAddresses: ["Fake Street"])[.address] == nil)
    }
}
