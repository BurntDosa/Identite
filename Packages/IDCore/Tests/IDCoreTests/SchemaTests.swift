import Testing
@testable import IDCore

struct SchemaTests {
    @Test func aadhaar() { #expect(IDKind.aadhaar.fields.map(\.key) == [.name, .aadhaarNumber, .vid, .dateOfBirth, .gender, .address]) }
    @Test func pan() { #expect(IDKind.pan.fields.map(\.key) == [.name, .panNumber, .fatherName, .dateOfBirth]) }
    @Test func passport() { #expect(IDKind.passport.fields.map(\.key) == [.passportNumber, .surname, .givenNames, .nationality, .sex, .dateOfBirth, .placeOfBirth, .placeOfIssue, .dateOfIssue, .dateOfExpiry, .fatherName, .motherName, .spouseName, .address, .fileNumber]) }
    @Test func voterID() { #expect(IDKind.voterID.fields.map(\.key) == [.epicNumber, .name, .relationName, .gender, .dateOfBirth, .address]) }
    @Test func drivingLicence() { #expect(IDKind.drivingLicence.fields.map(\.key) == [.dlNumber, .name, .dateOfBirth, .bloodGroup, .relationName, .address, .dateOfIssue, .dateOfExpiry, .vehicleClasses, .issuingRTO]) }
    @Test func creditCard() { #expect(IDKind.creditCard.fields.map(\.key) == [.bank, .cardholderName, .cardNumber, .cardExpiry, .cvv]) }
    @Test func debitCard() { #expect(IDKind.debitCard.fields.map(\.key) == [.bank, .cardholderName, .cardNumber, .cardExpiry, .cvv]) }
    @Test func bankAccount() { #expect(IDKind.bankAccount.fields.map(\.key) == [.bank, .accountHolder, .accountNumber, .ifsc, .accountType, .branch, .upiID]) }
    @Test func uan() { #expect(IDKind.uan.fields.map(\.key) == [.uanNumber, .name]) }
    @Test func maskedFields() {
        let masked = Set(IDKind.allCases.flatMap { $0.fields.filter(\.isMasked).map(\.key) })
        #expect(masked == [.aadhaarNumber, .vid, .cardNumber, .accountNumber, .cvv])
    }
    @Test func groupedCopyFields() {
        let grouped = Set(IDKind.allCases.flatMap { $0.fields.filter(\.hasGroupedCopy).map(\.key) })
        #expect(grouped == [.aadhaarNumber, .vid, .cardNumber])
    }
    @Test func dlExpiryLabel() { #expect(IDKind.drivingLicence.fields.first { $0.key == .dateOfExpiry }?.label == "Valid Till") }
    @Test func cardDesignIsMetadataOnly() {
        #expect(FieldKey.allCases.contains(.cardDesign))
        #expect(!IDKind.allCases.flatMap(\.fields).contains { $0.key == .cardDesign })
    }
}
