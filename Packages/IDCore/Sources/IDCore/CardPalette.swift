import Foundation

public enum CardDesign: Hashable, Sendable {
    case hsbcLivePlus, hdfcPixelPlay, hdfcMillennia, face(CardFace)

    public init?(rawValue: String) {
        switch rawValue {
        case "hsbcLivePlus": self = .hsbcLivePlus
        case "hdfcPixelPlay": self = .hdfcPixelPlay
        case "hdfcMillennia": self = .hdfcMillennia
        default:
            guard rawValue.hasPrefix("design1:") || rawValue.hasPrefix("mix1:") || rawValue.hasPrefix("generic.") else { return nil }
            self = .face(CardFaceCatalog.decode(rawValue))
        }
    }

    public var rawValue: String {
        switch self {
        case .hsbcLivePlus: return "hsbcLivePlus"
        case .hdfcPixelPlay: return "hdfcPixelPlay"
        case .hdfcMillennia: return "hdfcMillennia"
        case .face(let face):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return "design1:" + String(decoding: try! encoder.encode(face), as: UTF8.self)

        }
    }

    public static func defaultGeneric(forBank bank: String) -> CardDesign {
        .face(CardFaceCatalog.fallback(for: bank))
    }
}

public enum GenericPalette: String, CaseIterable, Sendable {
    case graphite, ocean, sunset, forest, plum, sand

    public var hexStops: [String] {
        switch self {
        case .graphite: ["#2B2E33", "#3D434B", "#5A6470"]
        case .ocean: ["#0B3D91", "#1663C7", "#2E7CB4"]
        case .sunset: ["#7A1F3D", "#C2410C", "#A46A07"]
        case .forest: ["#0F3D2E", "#166534", "#4D7C0F"]
        case .plum: ["#3B0A45", "#6B21A8", "#9B4FE5"]
        case .sand: ["#A58C6F", "#C2A27A", "#E9D8BE"]
        }
    }
}

public enum CardPalette {
    public static func mesh(for kind: IDKind) -> [String]? {
        let hex: String
        switch kind {
        case .aadhaar: hex = "FFC890 FBE3C4 F6EFE4 FBE6CF F3EFE8 E7F0E2 F3EEE6 DCEDD6 A9DBA8"
        case .pan: hex = "E3F2FF BFDDFF 9CC6FA CDE8FF A9D2FB 7EB2F2 B7DEF9 8FC2F5 5E97E6"
        case .passport: hex = "1E3A5F 16324F 0F2440 183457 12294A 0C1D36 10233F 0B1A30 070F1F"
        case .voterID: hex = "E9E2FF D9CCF7 CDB8F0 E2D6F8 D7C3EE E6C4E4 EBD9F2 F0CFE3 F6D3DF"
        case .drivingLicence: hex = "D6F5EA B5EBDA 8FDCCB BFEEDD 93DDCB 66C9BE A6E4D2 6FCDC0 3FB3B2"
        case .bankAccount: hex = "0E5A47 0B4D44 083F42 0A4A3E 073F3C 06333A 063A33 052F33 04262E"
        case .uan: hex = "2E2A78 3B2A80 4E2C7E 2A2668 392673 4C2870 241F57 33205F 4A1F55"
        case .creditCard, .debitCard: return nil
        }
        return hex.split(separator: " ").map { "#" + $0 }
    }

    public static func isLight(_ kind: IDKind) -> Bool {
        [.aadhaar, .pan, .voterID, .drivingLicence].contains(kind)
    }

    public static func textHex(for kind: IDKind) -> String { isLight(kind) ? "#1C1C1E" : "#FFFFFF" }
}
