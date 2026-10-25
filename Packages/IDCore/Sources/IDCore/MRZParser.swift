import Foundation

public struct MRZResult: Equatable, Sendable {
    public let passportNumber: String
    public let surname: String
    public let givenNames: String
    public let nationality: String
    public let sex: String
    public let dateOfBirth: String
    public let dateOfExpiry: String

    public init(passportNumber: String, surname: String, givenNames: String, nationality: String,
                sex: String, dateOfBirth: String, dateOfExpiry: String) {
        self.passportNumber = passportNumber
        self.surname = surname
        self.givenNames = givenNames
        self.nationality = nationality
        self.sex = sex
        self.dateOfBirth = dateOfBirth
        self.dateOfExpiry = dateOfExpiry
    }

    public func payloadValues() -> [FieldKey: String] {
        [.passportNumber: passportNumber, .surname: surname, .givenNames: givenNames,
         .nationality: nationality, .sex: sex, .dateOfBirth: dateOfBirth, .dateOfExpiry: dateOfExpiry]
    }
}

public enum MRZParser {
    public static func parseTD3(_ lines: [String], now: Date = .now) -> MRZResult? {
        let cleaned = lines.map { $0.uppercased().filter { !$0.isWhitespace }.replacingOccurrences(of: "«", with: "<") }
        guard cleaned.count >= 2 else { return nil }
        for index in 0..<(cleaned.count - 1) {
            let first = Array(cleaned[index]), second = Array(cleaned[index + 1])
            guard first.count == 44, second.count == 44, first.first == "P" else { continue }
            guard (first + second).allSatisfy({ characterValue($0) != nil }),
                  check(second[0..<9], second[9]), check(second[13..<19], second[19]),
                  check(second[21..<27], second[27]), check(second[28..<42], second[42]),
                  check(Array(second[0..<10]) + second[13..<20] + second[21..<43], second[43]) else { return nil }
            let currentYear = Calendar(identifier: .gregorian).component(.year, from: now) % 100
            guard let birth = date(String(second[13..<19]), currentYear: currentYear, birth: true),
                  let expiry = date(String(second[21..<27]), currentYear: currentYear, birth: false) else { return nil }
            let names = String(first[5..<44]).components(separatedBy: "<<")
            func name(_ string: String) -> String { string.split(separator: "<").joined(separator: " ") }
            return MRZResult(passportNumber: String(second[0..<9]).replacingOccurrences(of: "<+$", with: "", options: .regularExpression),
                             surname: name(names[0]), givenNames: name(names.dropFirst().joined(separator: "<")),
                             nationality: String(second[10..<13]), sex: String(second[20]), dateOfBirth: birth, dateOfExpiry: expiry)
        }
        return nil
    }

    private static func characterValue(_ character: Character) -> Int? {
        guard let ascii = character.asciiValue else { return nil }
        switch ascii {
        case 48...57: return Int(ascii - 48)
        case 65...90: return Int(ascii - 65) + 10
        case 60: return 0
        default: return nil
        }
    }

    private static func check(_ characters: some Collection<Character>, _ digit: Character) -> Bool {
        guard let expected = digit.wholeNumberValue else { return false }
        let weights = [7, 3, 1]
        var sum = 0
        for (index, character) in characters.enumerated() {
            guard let value = characterValue(character) else { return false }
            sum += value * weights[index % 3]
        }
        return sum % 10 == expected
    }

    private static func date(_ string: String, currentYear: Int, birth: Bool) -> String? {
        guard string.count == 6, string.allSatisfy({ $0.isASCII && $0.isNumber }),
              let yy = Int(string.prefix(2)), let month = Int(string.dropFirst(2).prefix(2)), let day = Int(string.suffix(2)) else { return nil }
        let year = (birth && yy > currentYear ? 1900 : 2000) + yy
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
