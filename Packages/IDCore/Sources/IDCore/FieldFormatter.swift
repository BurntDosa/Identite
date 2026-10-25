import Foundation

public enum FieldFormatter {
    public static func display(_ value: String, for input: FieldInput) -> String {
        guard input == .date else { return value }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return value }
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter.string(from: date)
    }

    public static func grouped(_ value: String, for key: FieldKey) -> String {
        guard [.aadhaarNumber, .vid, .cardNumber].contains(key) else { return value }
        let sizes = key == .cardNumber && CardNetwork(cardNumber: value) == .amex ? [4, 6, 5] : [4]
        var remaining = value[...]
        var groups: [String] = []
        var index = 0
        while !remaining.isEmpty {
            let size = sizes[min(index, sizes.count - 1)]
            groups.append(String(remaining.prefix(size)))
            remaining = remaining.dropFirst(min(size, remaining.count))
            index += 1
        }
        return groups.joined(separator: " ")
    }

    public static func masked(_ value: String, for key: FieldKey) -> String {
        if key == .cvv { return "•••" }
        guard [.aadhaarNumber, .vid, .cardNumber, .accountNumber].contains(key) else { return value }
        guard value.count > 4 else { return "••••" }
        if key == .accountNumber { return "•••• " + value.suffix(4) }
        var digitsToHide = max(0, value.filter(\.isNumber).count - 4)
        return String(grouped(value, for: key).map { character in
            guard character.isNumber, digitsToHide > 0 else { return character }
            digitsToHide -= 1
            return Character("•")
        })
    }
}
