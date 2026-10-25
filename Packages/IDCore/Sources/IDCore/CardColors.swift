import Foundation

public enum CardColorRole: String, Codable, CaseIterable, Sendable { case primary, secondary, accent }
public enum CardPaintRole: String, Codable, CaseIterable, Sendable { case background, primary, secondary, accent, highlight, image }
public enum CardColorway: String, Codable, Sendable { case preset, custom, card }

public struct CardColors: Codable, Hashable, Sendable {
    public var primary: String
    public var secondary: String
    public var accent: String

    public init(primary: String, secondary: String, accent: String) {
        self.primary = primary; self.secondary = secondary; self.accent = accent
    }

    public subscript(role: CardColorRole) -> String {
        switch role { case .primary: primary; case .secondary: secondary; case .accent: accent }
    }

    // Source role     User colour / derived CIELAB tone (D65, clipped to sRGB)
    // background      primary (the largest area)
    // primary         secondary, or a separated tone when it merges into primary
    // secondary       accent, or a second separated tone
    // accent          primary, L* - 18 (or +18 near black)
    // highlight       primary, L* + 36 (or -36 for a light primary)
    public func paint(_ role: CardPaintRole, for asset: String? = nil) -> String {
        let base = CardRGB(primary)
        if let asset, CardFaceCatalog.toneMappedAssets.contains(asset) {
            switch role {
            case .background: return base.tone(lightness: 18).hex
            case .primary: return primary
            case .highlight: return base.tone(lightness: 90).hex
            default: break
            }
        }
        func distinct(_ value: String, step: Double) -> String {
            guard CardRGB.distance(base.lab, CardRGB(value).lab) < 24 else { return value }
            return base.lightnessOffset(base.lab.x > 55 ? -step : step).hex
        }
        switch role {
        case .background: return primary
        case .primary: return distinct(secondary, step: 30)
        case .secondary:
            let value = CardRGB(distinct(accent, step: 50))
            let backing = CardRGB(distinct(secondary, step: 30)).lab
            guard CardRGB.distance(value.lab, backing) < 24 else { return value.hex }
            let candidates = [-30.0, 30, -50, 50].map { value.lightnessOffset($0) }
                + [value.tone(lightness: 5), value.tone(lightness: 95)]
            return candidates.max { a, b in
                min(CardRGB.distance(a.lab, base.lab), CardRGB.distance(a.lab, backing))
                < min(CardRGB.distance(b.lab, base.lab), CardRGB.distance(b.lab, backing))
            }!.hex
        case .accent: return base.lightnessOffset(base.lab.x < 18 ? 18 : -18).hex
        case .highlight: return base.lightnessOffset(base.lab.x > 64 ? -36 : 36).hex
        case .image: return "#808080" // Neutral coverage marker; the ink model uses the image's sampled RGB.
        }
    }

    public var isValid: Bool { CardColorRole.allCases.allSatisfy { CardRGB.isHex(self[$0]) } }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decode(String.self, forKey: .primary)
        secondary = try container.decode(String.self, forKey: .secondary)
        accent = try container.decode(String.self, forKey: .accent)
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected three RGB colours"))
        }
    }
}

public struct CardPreset: Hashable, Sendable {
    public let id: String
    public let name: String
    public let colors: CardColors

    public init(id: String, name: String, colors: CardColors) {
        self.id = id; self.name = name; self.colors = colors
    }
}

public enum CardTextZone: String, CaseIterable, Sendable {
    case bank, last4, network

    /// Normalized text boxes, shared by the face and contrast model.
    public var bounds: (x: Double, y: Double, width: Double, height: Double) {
        switch self {
        case .bank: (0.06, 0.07, 0.54, 0.13)
        case .last4: (0.06, 0.80, 0.39, 0.13)
        case .network: (0.75, 0.80, 0.19, 0.13)
        }
    }

    /// Shared bank-name geometry stops before a design's vertical art boundary.
    public func bounds(for design: String) -> (x: Double, y: Double, width: Double, height: Double) {
        var box = bounds
        if self == .bank { box.width = CardFaceCatalog.bankWidth(for: design) }
        return box
    }

}

public struct CardTextTreatment: Sendable {
    public let ink: String
    public let band: CardEdgeBand?
    public let averageContrast: Double
    public let minimumContrast: Double
    public var bandOpacity: Double { band?.opacity ?? 0 }
}

