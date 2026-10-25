import Foundation

public struct CardFace: Codable, Hashable, Sendable {
    public var design: String
    public var colors: CardColors
    public var colorway: CardColorway
    public var presetID: String?
    public var cardColors: CardColors?

    public init(design: String, colors: CardColors, colorway: CardColorway = .custom,
                presetID: String? = nil, cardColors: CardColors? = nil) {
        self.design = design; self.colors = colors; self.colorway = colorway
        self.presetID = presetID; self.cardColors = cardColors
    }
}

public enum CardFaceCatalog {
    public static let designs = (1...30).map { "cardy.\($0)" } + [
        "astra.horizonTicket", "astra.counterform", "astra.postageGarden", "astra.swissSignal",
        "astra.celestialMechanism", "astra.mosaicField", "astra.overprintPress"
    ]
    public static func name(for design: String) -> String {
        if design.hasPrefix("cardy."), designs.contains(design) { return "Cardy " + design.dropFirst(6) }
        return ["astra.horizonTicket": "Horizon Ticket", "astra.counterform": "Counterform",
                "astra.postageGarden": "Postage Garden", "astra.swissSignal": "Swiss Signal",
                "astra.celestialMechanism": "Celestial Mechanism", "astra.mosaicField": "Mosaic Field",
                "astra.overprintPress": "Overprint Press"][design] ?? "Design"
    }

    public static let presets: [CardPreset] = GenericPalette.allCases.map {
        CardPreset(id: $0.rawValue, name: $0.rawValue.capitalized,
                   colors: CardColors(primary: $0.hexStops[0], secondary: $0.hexStops[1], accent: $0.hexStops[2]))
    } + [
        CardPreset(id: "garnet", name: "Garnet", colors: CardColors(primary: "#770A3C", secondary: "#B91532", accent: "#3763A4")),
        CardPreset(id: "cobalt", name: "Cobalt", colors: CardColors(primary: "#0B3D91", secondary: "#1663C7", accent: "#F2B134")),
        CardPreset(id: "botanical", name: "Botanical", colors: CardColors(primary: "#0F3D2E", secondary: "#2F7D4F", accent: "#E8D9B5"))
    ]

    private static func hash(_ seed: String) -> UInt64 {
        seed.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }

    public static func fallbackDesign(for seed: String) -> String { designs[Int(hash(seed) % UInt64(designs.count))] }

    public static func fallback(for seed: String) -> CardFace {
        let preset = presets[Int(hash(seed) % UInt64(presets.count))]
        return CardFace(design: fallbackDesign(for: seed), colors: preset.colors, colorway: .preset, presetID: preset.id)
    }

    private static func sourceDesign(_ part: String) -> String? {
        if part.hasPrefix("astra."), designs.contains(part) { return part }
        let pieces = part.split(separator: ".")
        guard pieces.count >= 2, pieces[0] == "cardy" else { return nil }
        let id = pieces.prefix(2).joined(separator: ".")
        return designs.contains(id) ? id : nil
    }

    public static func migrate(_ legacy: LegacyCardComposition, seed: String? = nil) -> CardFace {
        CardFace(design: sourceDesign(legacy.pattern) ?? sourceDesign(legacy.base)
                 ?? fallbackDesign(for: seed ?? legacy.base + legacy.pattern),
                 colors: legacy.colors, colorway: legacy.colorway == .card && legacy.cardColors == nil ? .custom : legacy.colorway,
                 presetID: legacy.presetID, cardColors: legacy.cardColors)
    }

    static func decode(_ raw: String) -> CardFace {
        if raw.hasPrefix("generic.") {
            let preset = presets.first { $0.id == raw.dropFirst(8) }
            var result = fallback(for: raw)
            if let preset { result.colors = preset.colors; result.presetID = preset.id }
            return result
        }
        let isLegacy = raw.hasPrefix("mix1:")
        let data = Data(raw.dropFirst(isLegacy ? 5 : 8).utf8)
        if isLegacy, let legacy = try? JSONDecoder().decode(LegacyCardComposition.self, from: data) {
            return migrate(legacy, seed: raw)
        }
        if !isLegacy, var face = try? JSONDecoder().decode(CardFace.self, from: data) {
            if !designs.contains(face.design) { face.design = fallbackDesign(for: raw) }
            if face.colorway == .card && face.cardColors == nil { face.colorway = .custom }
            return face
        }
        // Recover valid individual colours even when a newer/corrupt field prevents typed decoding.
        var result = fallback(for: raw)
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return result }
        if let id = object["design"] as? String, designs.contains(id) { result.design = id }
        if isLegacy {
            result.design = sourceDesign(object["pattern"] as? String ?? "")
                ?? sourceDesign(object["base"] as? String ?? "") ?? result.design
        }
        func recover(_ value: Any?) -> CardColors? {
            guard let fields = value as? [String: Any] else { return nil }
            func color(_ key: String, _ fallback: String) -> String {
                guard let hex = fields[key] as? String, CardRGB.isHex(hex) else { return fallback }
                return hex
            }
            return CardColors(primary: color("primary", result.colors.primary),
                              secondary: color("secondary", result.colors.secondary), accent: color("accent", result.colors.accent))
        }
        result.colors = recover(object["colors"]) ?? result.colors
        result.cardColors = recover(object["cardColors"])
        if let way = object["colorway"] as? String, let colorway = CardColorway(rawValue: way) { result.colorway = colorway }
        if let preset = object["presetID"] as? String { result.presetID = preset }
        if result.colorway == .card && result.cardColors == nil { result.colorway = .custom }
        return result
    }
}

public struct CardFaceLayer: Decodable, Sendable {
    public let asset: String
    public let kind: String
    public let category: String?
    public let outerCorners: [String]?
    public let bounds: [Double]
    public let blend: String
    public let opacity: Double
    public let roles: [String: String]
    public let toneMapped: Bool
    public let masks: [String: String]
    public let neutral: String?
    public let children: [CardFaceLayer]?

    public var paintLayers: [CardFaceLayer] { children?.flatMap(\.paintLayers) ?? [self] }
}

extension CardFaceCatalog {
    private struct Design: Decodable { let layers: [CardFaceLayer]; let bankWidth: Double }
    private static let table: [String: Design] = {
        let url = Bundle.module.url(forResource: "CardFaceDesigns", withExtension: "json")!
        return try! JSONDecoder().decode([String: Design].self, from: Data(contentsOf: url))
    }()

    public static func layers(for design: String) -> [CardFaceLayer] { table[design]?.layers ?? [] }
    public static func paintLayers(for design: String) -> [CardFaceLayer] { layers(for: design).flatMap(\.paintLayers) }
    public static func colorRoles(for design: String) -> [CardColorRole] {
        var roles: Set<CardColorRole> = [.primary]
        for layer in paintLayers(for: design) {
            for source in layer.masks.keys {
                let paint = (layer.roles[source] ?? source).split(separator: ":").first
                if layer.toneMapped && paint == "primary" { continue }
                if paint == "primary" { roles.insert(.secondary) }
                if paint == "secondary" { roles.insert(.accent) }
            }
        }
        return CardColorRole.allCases.filter { roles.contains($0) }
    }
    public static func bankWidth(for design: String) -> Double { table[design]?.bankWidth ?? 0.54 }
    public static var assets: Set<String> {
        func ids(_ layer: CardFaceLayer) -> [String] { [layer.asset] + (layer.children?.flatMap(ids) ?? []) }
        return Set(table.values.flatMap { $0.layers.flatMap(ids) })
    }
    public static var assetNames: [String] {
        Set(table.values.flatMap { $0.layers.flatMap(\.paintLayers) }.flatMap {
            Array($0.masks.values) + ($0.neutral.map { [$0] } ?? [])
        }).sorted()
    }
}

extension CardColors {
    public func paint(_ source: String, layer: CardFaceLayer) -> String {
        let slot = (layer.roles[source] ?? source).split(separator: ":")
        let role = CardPaintRole(rawValue: String(slot[0])) ?? .background
        let color = paint(role, for: layer.asset)
        guard slot.count == 2, let offset = Double(slot[1]) else { return color }
        return CardRGB(color).lightnessOffset(offset).hex
    }
}

extension CardFaceCatalog {
    static let toneMappedAssets = Set(designs.flatMap { paintLayers(for: $0) }.filter(\.toneMapped).map(\.asset))
    public static func legibility(for face: CardFace) -> CardLegibility { CardFaceCoverage.legibility(face) }
    public static func averageColor(for face: CardFace, zone: CardTextZone) -> String {
        let band = legibility(for: face)[zone].band
        return CardRGB(CardFaceCoverage.average(CardFaceCoverage.samples(face, zone: zone),
            band: band, zone: zone, design: face.design)).hex
    }
    public static func ink(for face: CardFace, zone: CardTextZone) -> String { legibility(for: face)[zone].ink }
    public static func meetsContrast(_ face: CardFace) -> Bool {
        guard designs.contains(face.design), face.colors.isValid else { return false }
        return legibility(for: face).treatments.values.allSatisfy { min($0.averageContrast,$0.minimumContrast) >= 4.5 }
    }
    public static func visibility(_ face: CardFace) -> Double {
        CardFaceCoverage.visibility(face)
    }
    public static func random<G: RandomNumberGenerator>(colors: CardColors, colorway: CardColorway = .custom,
        presetID: String? = nil, cardColors: CardColors? = nil, using generator: inout G) -> CardFace {
        choose(colors: colors, colorway: colorway, presetID: presetID, cardColors: cardColors, excluding: nil, using: &generator)
    }
    public static func shuffled<G: RandomNumberGenerator>(_ face: CardFace, using generator: inout G) -> CardFace {
        choose(colors: face.colors, colorway: face.colorway, presetID: face.presetID,
               cardColors: face.cardColors, excluding: face.design, using: &generator)
    }
    private static func choose<G: RandomNumberGenerator>(colors: CardColors, colorway: CardColorway,
        presetID: String?, cardColors: CardColors?, excluding: String?, using generator: inout G) -> CardFace {
        var best: CardFace?, leastBand = Double.infinity
        for design in designs.filter({ $0 != excluding }).shuffled(using: &generator) {
            let face = CardFace(design: design, colors: colors, colorway: colorway, presetID: presetID, cardColors: cardColors)
            guard visibility(face) >= 0.04 else { continue }
            let opacity = legibility(for: face).bands.map(\.opacity).max() ?? 0
            if opacity <= 0.40 { return face }
            if opacity < leastBand { best = face; leastBand = opacity }
        }
        // A chosen face always remains usable even if a future palette requires heavier edge lighting.
        return best ?? CardFace(design: designs.first { $0 != excluding }!, colors: colors,
                                colorway: colorway, presetID: presetID, cardColors: cardColors)
    }
}

extension CardFace {
    public var isValid: Bool {
        CardFaceCatalog.designs.contains(design) && colors.isValid && (cardColors?.isValid ?? true)
    }
    public func ink(for zone: CardTextZone) -> String { CardFaceCatalog.ink(for: self, zone: zone) }
}
