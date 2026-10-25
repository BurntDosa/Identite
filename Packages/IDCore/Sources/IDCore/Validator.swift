import Foundation

public enum Validator {
    public static func normalized(_ value: String, for key: FieldKey) -> String {
        switch key {
        case .aadhaarNumber, .vid, .cardNumber, .cvv, .accountNumber, .uanNumber:
            return value.filter { $0.isASCII && $0.isNumber }
        case .panNumber, .ifsc, .epicNumber, .passportNumber, .dlNumber:
            return value.uppercased().filter { !$0.isWhitespace }
        default:
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func warning(for key: FieldKey, value: String, now: Date = .now, calendar: Calendar = .current) -> String? {
        guard !value.isEmpty else { return nil }
        let valid: Bool
        switch key {
        case .aadhaarNumber: valid = matches(value, "[2-9][0-9]{11}") && verhoeffIsValid(value)
        case .vid: valid = matches(value, "[0-9]{16}") && verhoeffIsValid(value)
        case .cardNumber: valid = matches(value, "[0-9]{12,19}") && luhnIsValid(value)
        case .cvv: valid = matches(value, "[0-9]{3,4}")
        case .panNumber: valid = matches(value, "[A-Z]{5}[0-9]{4}[A-Z]")
        case .ifsc: valid = matches(value, "[A-Z]{4}0[A-Z0-9]{6}")
        case .uanNumber: valid = matches(value, "[0-9]{12}")
        case .passportNumber: valid = matches(value, "[A-Z][0-9]{7}")
        case .epicNumber: valid = matches(value, "[A-Z]{3}[0-9]{7}")
        case .dlNumber: valid = matches(value.replacingOccurrences(of: "-", with: ""), "[A-Z]{2}[0-9]{1,2}[A-Z0-9]{8,13}")
        case .cardExpiry:
            guard matches(value, "(0[1-9]|1[0-2])/[0-9]{2}"),
                  let month = Int(value.prefix(2)), let year = Int(value.suffix(2)) else {
                return "This doesn't look like a valid expiry."
            }
            let current = calendar.dateComponents([.year, .month], from: now)
            valid = (2000 + year) * 12 + month >= current.year! * 12 + current.month!
        default: return nil
        }
        return valid ? nil : "This doesn't look like a valid \(IDKind.allCases.flatMap(\.fields).first { $0.key == key }?.label ?? key.rawValue)."
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: "\\A(?:" + pattern + ")\\z", options: .regularExpression) != nil
    }

    private static let multiplication = [
        [0,1,2,3,4,5,6,7,8,9], [1,2,3,4,0,6,7,8,9,5], [2,3,4,0,1,7,8,9,5,6],
        [3,4,0,1,2,8,9,5,6,7], [4,0,1,2,3,9,5,6,7,8], [5,9,8,7,6,0,4,3,2,1],
        [6,5,9,8,7,1,0,4,3,2], [7,6,5,9,8,2,1,0,4,3], [8,7,6,5,9,3,2,1,0,4],
        [9,8,7,6,5,4,3,2,1,0]
    ]
    private static let permutation = [
        [0,1,2,3,4,5,6,7,8,9], [1,5,7,6,2,8,3,0,9,4], [5,8,0,3,7,9,6,1,4,2],
        [8,9,1,6,0,4,3,5,2,7], [9,4,5,3,1,2,6,8,7,0], [4,2,8,6,5,7,3,9,0,1],
        [2,7,9,3,8,0,6,4,1,5], [7,0,4,6,9,1,3,2,5,8]
    ]

    public static func verhoeffCheckDigit(for digits: String) -> Int {
        guard let checksum = verhoeff(digits, offset: 1) else { return -1 }
        return [0,4,3,2,1,5,6,7,8,9][checksum]
    }

    public static func verhoeffIsValid(_ digits: String) -> Bool { verhoeff(digits, offset: 0) == 0 }

    private static func verhoeff(_ digits: String, offset: Int) -> Int? {
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var checksum = 0
        for (index, digit) in digits.reversed().enumerated() {
            checksum = multiplication[checksum][permutation[(index + offset) % 8][digit.wholeNumberValue!]]
        }
        return checksum
    }

    public static func luhnIsValid(_ digits: String) -> Bool {
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        var sum = 0
        for (index, digit) in digits.reversed().enumerated() {
            var number = digit.wholeNumberValue!
            if index % 2 == 1 { number *= 2; if number > 9 { number -= 9 } }
            sum += number
        }
        return sum % 10 == 0
    }
}
