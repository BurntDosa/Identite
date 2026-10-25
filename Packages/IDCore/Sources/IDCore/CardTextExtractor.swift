import Foundation

public enum CardTextExtractor {
    public static func extract(kind: IDKind, lines: [String]) -> [FieldKey: String] {
        if kind == .passport { return MRZParser.parseTD3(lines)?.payloadValues() ?? [:] }
        guard kind.isScannable else { return [:] }
        let lines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        var fields: [FieldKey: String] = [:]
        func labeled(_ pattern: String) -> String? {
            for (index, line) in lines.enumerated() {
                guard let range = line.range(of: "(?i)^\\s*(?:" + pattern + ")\\b\\s*[:.-]?\\s*", options: .regularExpression) else { continue }
                let remainder = String(line[range.upperBound...])
                if !remainder.isEmpty { return remainder }
                if index + 1 < lines.count { return lines[index + 1] }
            }
            return nil
        }
        func dateAfter(_ pattern: String) -> String? { labeled(pattern).flatMap(indianDate) }
        func firstToken(_ pattern: String) -> String? { matches(pattern, in: text.uppercased()).first }
        func number(for key: FieldKey, lengths: ClosedRange<Int>) -> String? {
            for line in lines {
                for run in matches("[0-9](?:[0-9 \\t-]*[0-9])?", in: line) {
                    let value = Validator.normalized(run, for: key)
                    if lengths.contains(value.count), Validator.warning(for: key, value: value) == nil { return value }
                }
            }
            return nil
        }
        func gender() -> String? {
            switch firstToken("\\b(FEMALE|MALE|TRANSGENDER)\\b") {
            case "FEMALE": return "Female"
            case "MALE": return "Male"
            case "TRANSGENDER": return "Transgender"
            default: return nil
            }
        }
        func address() -> String? {
            guard let index = lines.firstIndex(where: { $0.range(of: "(?i)^address\\b", options: .regularExpression) != nil }) else { return nil }
            var parts: [String] = []
            for offset in index..<lines.count {
                let line = offset == index ? lines[offset].replacingOccurrences(of: "(?i)^address\\s*[:.-]?\\s*", with: "", options: .regularExpression) : lines[offset]
                if !line.isEmpty { parts.append(line) }
                if !matches("\\b[0-9]{6}\\b", in: line).isEmpty { break }
            }
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        switch kind {
        case .aadhaar:
            fields[.aadhaarNumber] = number(for: .aadhaarNumber, lengths: 12...12)
            fields[.vid] = number(for: .vid, lengths: 16...16)
            fields[.dateOfBirth] = dateAfter("DOB|Date of Birth")
            if let index = lines.firstIndex(where: { $0.range(of: "(?i)\\b(DOB|Date of Birth)\\b", options: .regularExpression) != nil }), index > 0 {
                fields[.name] = lines[index - 1]
            }
            fields[.gender] = gender()
            fields[.address] = address()
        case .pan:
            fields[.panNumber] = firstToken("\\b[A-Z]{5}[0-9]{4}[A-Z]\\b")
            fields[.dateOfBirth] = dateAfter("DOB|Date of Birth") ?? lines.compactMap(indianDate).first
            fields[.name] = labeled("Name")
            fields[.fatherName] = labeled("Father['’]?s Name")
        case .voterID:
            fields[.epicNumber] = firstToken("\\b[A-Z]{3}[0-9]{7}\\b")
            fields[.name] = labeled("Name")
            fields[.relationName] = labeled("Father['’]?s Name|Husband['’]?s Name")
            fields[.gender] = gender()
            fields[.dateOfBirth] = dateAfter("DOB|Date of Birth")
            fields[.address] = address()
        case .drivingLicence:
            fields[.dlNumber] = firstToken("\\b[A-Z]{2}[0-9]{2}[ -]?[0-9]{11}\\b")
            fields[.name] = labeled("Name")
            fields[.dateOfBirth] = dateAfter("DOB|Date of Birth")
            fields[.dateOfIssue] = dateAfter("Date of Issue|Issue|DOI")
            fields[.dateOfExpiry] = dateAfter("Valid Till|Validity")
            fields[.bloodGroup] = firstToken("\\b(?:AB|A|B|O)[+-]")
        case .creditCard, .debitCard:
            fields[.cardNumber] = number(for: .cardNumber, lengths: 13...19)
            let expiries = lines.filter { $0.range(of: "(?i)valid\\s+from", options: .regularExpression) == nil }
                .flatMap { matches("\\b(?:0[1-9]|1[0-2])/[0-9]{2}\\b", in: $0) }
            fields[.cardExpiry] = expiries.max { lhs, rhs in
                String(lhs.suffix(2)) + lhs.prefix(2) < String(rhs.suffix(2)) + rhs.prefix(2)
            }
        case .passport, .bankAccount, .uan: break
        }
        return fields.reduce(into: [:]) { result, field in
            result[field.key] = Validator.normalized(field.value, for: field.key)
        }
    }

    public static func extract(kind: IDKind, paragraphs: [String], detectedAddresses: [String] = []) -> [FieldKey: String] {
        var fields = extract(kind: kind, lines: paragraphs.flatMap { $0.components(separatedBy: .newlines) })
        guard [.aadhaar, .voterID, .drivingLicence, .passport].contains(kind) else { return fields }
        // Restrict an explicitly labelled address to its paragraph, never the next unrelated block.
        let labelled = paragraphs.first { $0.range(of: "(?im)^address\\b", options: .regularExpression) != nil }
        if let labelled {
            let lines = labelled.components(separatedBy: .newlines)
            fields[.address] = extract(kind: .voterID, lines: lines)[.address]
        } else {
            fields[.address] = detectedAddresses.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        return fields
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func indianDate(_ text: String) -> String? {
        guard let value = matches("\\b[0-9]{2}[/-][0-9]{2}[/-][0-9]{4}\\b", in: text).first else { return nil }
        let parts = value.split(whereSeparator: { $0 == "/" || $0 == "-" }).compactMap { Int($0) }
        let components = DateComponents(year: parts[2], month: parts[1], day: parts[0])
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components), calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return String(format: "%04d-%02d-%02d", parts[2], parts[1], parts[0])
    }
}
