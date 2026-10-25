public enum FieldKey: String, Codable, CaseIterable, Sendable {
    case name, aadhaarNumber, vid, dateOfBirth, gender, address
    case panNumber, fatherName, passportNumber, surname, givenNames, nationality, sex
    case placeOfBirth, placeOfIssue, dateOfIssue, dateOfExpiry, motherName, spouseName, fileNumber
    case epicNumber, relationName, dlNumber, bloodGroup, vehicleClasses, issuingRTO
    case bank, cardholderName, cardNumber, cardExpiry, cvv, accountHolder, accountNumber, ifsc
    case accountType, branch, upiID, uanNumber, cardDesign
}

public enum FieldInput: Equatable, Sendable {
    case text, multiline, digits, date, monthYear, choice([String])
}

public struct FieldSpec: Identifiable, Equatable, Sendable {
    public let key: FieldKey
    public let label: String
    public let isOptional: Bool
    public let input: FieldInput
    public let isMasked: Bool
    public let hasGroupedCopy: Bool
    public let requiresFreshAuthentication: Bool
    public var id: FieldKey { key }

    public init(_ key: FieldKey, _ label: String, input: FieldInput = .text,
                isOptional: Bool = false, isMasked: Bool = false, hasGroupedCopy: Bool = false, requiresFreshAuthentication: Bool = false) {
        self.key = key
        self.label = label
        self.input = input
        self.isOptional = isOptional
        self.isMasked = isMasked
        self.hasGroupedCopy = hasGroupedCopy
        self.requiresFreshAuthentication = requiresFreshAuthentication
    }
}
