public enum CardNetwork: String, Sendable {
    case visa = "Visa", mastercard = "Mastercard", rupay = "RuPay", amex = "American Express"
    case diners = "Diners Club", discover = "Discover", other = "Other"

    public init(cardNumber: String) {
        let number = Validator.normalized(cardNumber, for: .cardNumber)
        func prefix(_ length: Int, in range: ClosedRange<Int>) -> Bool {
            guard number.count >= length, let value = Int(number.prefix(length)) else { return false }
            return range.contains(value)
        }
        if number.hasPrefix("6011") || prefix(3, in: 644...649) { self = .discover }
        else if prefix(4, in: 2221...2720) { self = .mastercard }
        else if number.hasPrefix("508") { self = .rupay }
        else if prefix(3, in: 300...305) { self = .diners }
        else if ["34", "37"].contains(where: number.hasPrefix) { self = .amex }
        else if ["36", "38", "39"].contains(where: number.hasPrefix) { self = .diners }
        else if ["60", "65", "81", "82"].contains(where: number.hasPrefix) { self = .rupay }
        else if prefix(2, in: 51...55) { self = .mastercard }
        else if number.hasPrefix("4") { self = .visa }
        else { self = .other }
    }
}
