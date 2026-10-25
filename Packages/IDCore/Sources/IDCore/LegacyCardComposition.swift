import Foundation

/// Decode old part selections without applying today's catalog eligibility rules.
public struct LegacyCardComposition: Decodable, Sendable {
    public var base: String
    public var pattern: String
    public var shape: String?
    public var texture: Bool
    public var layout: String
    public var panel: String?
    public var colors: CardColors
    public var colorway: CardColorway
    public var presetID: String?
    public var cardColors: CardColors?

    private enum CodingKeys: String, CodingKey {
        case base, pattern, shape, texture, layout, panel, colors, colorway, presetID, cardColors
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        base = try c.decodeIfPresent(String.self, forKey: .base) ?? ""
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        shape = try c.decodeIfPresent(String.self, forKey: .shape)
        texture = try c.decodeIfPresent(Bool.self, forKey: .texture) ?? false
        layout = try c.decodeIfPresent(String.self, forKey: .layout) ?? "full"
        panel = try c.decodeIfPresent(String.self, forKey: .panel)
        colors = try c.decode(CardColors.self, forKey: .colors)
        colorway = try c.decodeIfPresent(CardColorway.self, forKey: .colorway) ?? .custom
        presetID = try c.decodeIfPresent(String.self, forKey: .presetID)
        cardColors = try c.decodeIfPresent(CardColors.self, forKey: .cardColors)
    }
}

