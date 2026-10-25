public enum IDKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case aadhaar, pan, passport, voterID, drivingLicence, creditCard, debitCard, bankAccount, uan

    public var id: String { rawValue }
    public var isScannable: Bool { self != .bankAccount && self != .uan }
    public var hasPFAccounts: Bool { self == .uan }
    public var displayName: String {
        switch self {
        case .aadhaar: "Aadhaar"
        case .pan: "PAN"
        case .passport: "Passport"
        case .voterID: "Voter ID"
        case .drivingLicence: "Driving Licence"
        case .creditCard: "Credit Card"
        case .debitCard: "Debit Card"
        case .bankAccount: "Bank Account"
        case .uan: "UAN"
        }
    }

    public var fields: [FieldSpec] {
        let name = FieldSpec(.name, "Name")
        let dob = FieldSpec(.dateOfBirth, "Date of Birth", input: .date)
        let gender = FieldSpec(.gender, "Gender", input: .choice(["Female", "Male", "Transgender"]))
        let address = FieldSpec(.address, "Address", input: .multiline)
        let issue = FieldSpec(.dateOfIssue, "Date of Issue", input: .date)
        switch self {
        case .aadhaar:
            return [name, .init(.aadhaarNumber, "Aadhaar Number", input: .digits, isMasked: true, hasGroupedCopy: true),
                    .init(.vid, "VID", input: .digits, isOptional: true, isMasked: true, hasGroupedCopy: true), dob, gender, address]
        case .pan:
            return [name, .init(.panNumber, "PAN"), .init(.fatherName, "Father's Name"), dob]
        case .passport:
            return [.init(.passportNumber, "Passport Number"), .init(.surname, "Surname"), .init(.givenNames, "Given Names"),
                    .init(.nationality, "Nationality"), .init(.sex, "Sex", input: .choice(["F", "M", "X"])), dob,
                    .init(.placeOfBirth, "Place of Birth"), .init(.placeOfIssue, "Place of Issue"), issue,
                    .init(.dateOfExpiry, "Date of Expiry", input: .date), .init(.fatherName, "Father's Name", isOptional: true),
                    .init(.motherName, "Mother's Name", isOptional: true), .init(.spouseName, "Spouse's Name", isOptional: true),
                    .init(.address, "Address", input: .multiline, isOptional: true), .init(.fileNumber, "File Number", isOptional: true)]
        case .voterID:
            return [.init(.epicNumber, "EPIC Number"), name, .init(.relationName, "Father's / Husband's Name"), gender, dob, address]
        case .drivingLicence:
            return [.init(.dlNumber, "DL Number"), name, dob,
                    .init(.bloodGroup, "Blood Group", input: .choice(["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]), isOptional: true),
                    .init(.relationName, "Son / Daughter / Wife of"), address, issue,
                    .init(.dateOfExpiry, "Valid Till", input: .date), .init(.vehicleClasses, "Vehicle Classes"),
                    .init(.issuingRTO, "Issuing RTO", isOptional: true)]
        case .creditCard, .debitCard:
            return [.init(.bank, "Bank"), .init(.cardholderName, "Cardholder Name"),
                    .init(.cardNumber, "Card Number", input: .digits, isMasked: true, hasGroupedCopy: true),
                    .init(.cardExpiry, "Expiry", input: .monthYear),
                    .init(.cvv, "CVV", input: .digits, isOptional: true, isMasked: true, requiresFreshAuthentication: true)]
        case .bankAccount:
            return [.init(.bank, "Bank"), .init(.accountHolder, "Account Holder"),
                    .init(.accountNumber, "Account Number", input: .digits, isMasked: true), .init(.ifsc, "IFSC"),
                    .init(.accountType, "Account Type", input: .choice(["Savings", "Current", "Other"])),
                    .init(.branch, "Branch", isOptional: true), .init(.upiID, "UPI ID", isOptional: true)]
        case .uan:
            return [.init(.uanNumber, "UAN", input: .digits), name]
        }
    }
}
