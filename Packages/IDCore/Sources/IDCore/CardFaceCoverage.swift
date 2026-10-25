import Foundation

/// The renderer and model use the same ordered paint layers, opacity, blends and text boxes.
enum CardFaceCoverage {
    static let columns = 32, rows = 12
    static let artColumns = 64, artRows = 40
    struct Limits: Decodable {
        let paints: [UInt8]
        let alpha: [UInt8]
        let neutralLow: [UInt8]
        let neutralHigh: [UInt8]
        let weight: Double
    }
    struct Part: Decodable {
        let paints: [String]
        let zones: [Data]
        let limits: [Limits]
        let art: Data
    }
    static let designs: [String: [String: Part]] = {
        let url = Bundle.module.url(forResource: "CardFaceCoverage", withExtension: "json")!
        return try! JSONDecoder().decode([String: [String: Part]].self, from: Data(contentsOf: url))
    }()

    static func blend(_ source: Double, _ backdrop: Double, mode: String) -> Double {
        switch mode {
        case "overlay": return backdrop <= 0.5 ? 2 * source * backdrop : 1 - 2 * (1 - source) * (1 - backdrop)
        case "multiply": return source * backdrop
        case "screen": return 1 - (1 - source) * (1 - backdrop)
        case "softLight":
            let d = backdrop <= 0.25 ? ((16 * backdrop - 12) * backdrop + 4) * backdrop : sqrt(backdrop)
            return source <= 0.5 ? backdrop - (1 - 2 * source) * backdrop * (1 - backdrop)
                : backdrop + (2 * source - 1) * (d - backdrop)
        default: return source
        }
    }

    static func clamped(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(min(1,max(0,rgb.x)),min(1,max(0,rgb.y)),min(1,max(0,rgb.z)))
    }

    static func samples(_ face: CardFace, zone: CardTextZone?, includeGrain: Bool = true,
                        paintOverrides: [String: [String: String]] = [:], omitting: String? = nil) -> [SIMD3<Double>] {
        let count = zone == nil ? artColumns * artRows : columns * rows
        var result = [SIMD3<Double>](repeating: CardRGB(face.colors.primary).channels, count: count)
        for layer in CardFaceCatalog.paintLayers(for: face.design) {
            if layer.asset == omitting { continue }
            if !includeGrain && (layer.neutral != nil || layer.category == "texture") { continue }
            guard let part = designs[face.design]?[layer.asset] else { continue }
            let data = Array(zone.map { part.zones[CardTextZone.allCases.firstIndex(of: $0)!] } ?? part.art)
            let paints = part.paints.map { CardRGB(paintOverrides[layer.asset]?[$0] ?? face.colors.paint($0, layer: layer)).channels }
            let n = paints.count, stride = n + 4
            for i in 0..<count {
                let offset = i * stride
                var rgb = SIMD3(Double(data[offset+n]),Double(data[offset+n+1]),Double(data[offset+n+2])) / 255
                var alpha = Double(data[offset+n+3]) / 255
                for role in 0..<n {
                    let weight = Double(data[offset+role]) / 255
                    rgb += paints[role] * weight; alpha += weight
                }
                alpha = min(1,alpha)
                guard alpha > 0 else { continue }
                rgb = clamped(rgb) / alpha
                let opacity = alpha * layer.opacity
                for channel in 0..<3 {
                    let background = result[i][channel]
                    result[i][channel] = background * (1-opacity) + blend(rgb[channel],background,mode:layer.blend) * opacity
                }
                result[i] = clamped(result[i])
            }
        }
        return result
    }

    static func visibility(_ face: CardFace, paintOverrides: [String: [String: String]] = [:]) -> Double {
        let pixels = samples(face, zone: nil, includeGrain: false, paintOverrides: paintOverrides)
        var fractions: [Double] = []
        for layer in CardFaceCatalog.paintLayers(for: face.design) where layer.neutral == nil {
            guard layer.category != "texture",
                  layer.category == "pattern" || layer.category == "shape" || layer.masks.count > 1,
                  let part = designs[face.design]?[layer.asset], !part.paints.isEmpty else { continue }
            let data = Array(part.art), stride = part.paints.count + 4
            let region = pixels.indices.filter { i in part.paints.indices.contains { data[i * stride + $0] > 0 } }
            guard !region.isEmpty else { continue }
            // Keep the complete layer stack, replacing only this pattern with its own backing.
            // For multicolour art, test every constituent paint as the possible solid backing.
            let tintOnly = Set(layer.masks.keys.map { layer.roles[$0] ?? $0 }).count == 1
            let xs = region.map { $0 % artColumns }, ys = region.map { $0 / artColumns }
            let area = (xs.max()! - xs.min()! + 1) * (ys.max()! - ys.min()! + 1)
            let transparentPattern = Double(region.count) / Double(area) < 0.95
            let references: [String?] = tintOnly || transparentPattern ? [nil] : layer.masks.keys.sorted().map {
                paintOverrides[layer.asset]?[$0] ?? face.colors.paint($0, layer: layer)
            }
            for color in references {
                var overrides = paintOverrides
                if let color { overrides[layer.asset] = Dictionary(uniqueKeysWithValues: part.paints.map { ($0, color) }) }
                let backing = samples(face, zone: nil, includeGrain: false, paintOverrides: overrides,
                                      omitting: color == nil ? layer.asset : nil)
                let visible = region.filter { i in
                    // Recover full paint coverage while retaining layer opacity and later occlusion.
                    let coverage = part.paints.indices.reduce(0) { $0 + Double(data[i * stride + $1]) / 255 }
                    let foreground = clamped(backing[i] + (pixels[i] - backing[i]) / max(coverage, 1.0 / 255))
                    return CardRGB.distance(CardRGB(foreground).lab, CardRGB(backing[i]).lab) >= 3
                }.count
                fractions.append(Double(visible) / Double(region.count))
            }
        }
        return fractions.min() ?? 0
    }

    private static func range(_ face: CardFace, zone: CardTextZone) -> (low: SIMD3<Double>, high: SIMD3<Double>) {
        let zoneIndex = CardTextZone.allCases.firstIndex(of: zone)!
        var low = CardRGB(face.colors.primary).channels, high = low
        for layer in CardFaceCatalog.paintLayers(for: face.design) {
            guard let part = designs[face.design]?[layer.asset] else { continue }
            let limits = part.limits[zoneIndex]
            guard limits.alpha[1] > 0 else { continue }
            var colors = part.paints.enumerated().filter { limits.paints[$0.offset] > 0 }
                .map { CardRGB(face.colors.paint($0.element, layer: layer)).channels }
            if layer.neutral != nil {
                colors += [SIMD3(Double(limits.neutralLow[0]),Double(limits.neutralLow[1]),Double(limits.neutralLow[2])) / 255,
                           SIMD3(Double(limits.neutralHigh[0]),Double(limits.neutralHigh[1]),Double(limits.neutralHigh[2])) / 255]
            }
            guard !colors.isEmpty else { continue }
            let alphas = limits.alpha.map { Double($0) / 255 * layer.opacity }
            for c in 0..<3 {
                let minimum = colors.map { $0[c] }.min()!, maximum = min(1,colors.map { $0[c] }.max()! * max(1,limits.weight))
                var values: [Double] = []
                for backdrop in [low[c],high[c]] { for source in [minimum,maximum] { for a in alphas {
                    values.append(backdrop * (1-a) + blend(source,backdrop,mode:layer.blend) * a)
                } } }
                low[c] = values.min()!; high[c] = values.max()!
            }
        }
        if low == high { return (low, high) }
        // Preserve the old two-level quantization margin, now after the actual design's complete layer stack.
        return (clamped(low-SIMD3(repeating:2.0/255)),clamped(high+SIMD3(repeating:2.0/255)))
    }

    static func average(_ samples: [SIMD3<Double>], band: CardEdgeBand?, zone: CardTextZone, design: String) -> SIMD3<Double> {
        guard let band else { return samples.reduce(.zero,+) / Double(samples.count) }
        let box = zone.bounds(for: design), tone = CardRGB(band.color).channels
        return samples.enumerated().reduce(.zero) { sum, sample in
            let y = box.y + box.height * (Double(sample.offset / columns) + 0.5) / Double(rows)
            let alpha = band.alpha(atY: y)
            return sum + sample.element * (1-alpha) + tone * alpha
        } / Double(samples.count)
    }
    static func legibility(_ c: CardFace) -> CardLegibility {
        let zones = CardTextZone.allCases
        let bounds = Dictionary(uniqueKeysWithValues: zones.map { ($0, range(c, zone: $0)) })
        let sampled = Dictionary(uniqueKeysWithValues: zones.map { ($0, samples(c, zone: $0)) })
        let tones = ["#000000": CardRGB(c.colors.primary).tone(lightness: 96).hex,
                     "#FFFFFF": CardRGB(c.colors.primary).tone(lightness: 10).hex]
        var treatments: [CardTextZone: CardTextTreatment] = [:], bands: [CardEdgeBand] = []
        func contrast(_ rgb: SIMD3<Double>, ink: String) -> Double {
            let l = CardRGB(rgb).luminance
            return ink == "#000000" ? (l + 0.05) / 0.05 : 1.05 / (l + 0.05)
        }
        func minimum(_ zone: CardTextZone, ink: String, band: CardEdgeBand?) -> Double {
            let box = zone.bounds(for: c.design), range = bounds[zone]!
            var worst = ink == "#000000" ? range.low : range.high
            if let band {
                let alpha = min(band.alpha(atY: box.y), band.alpha(atY: box.y + box.height))
                worst = worst * (1 - alpha) + CardRGB(band.color).channels * alpha
            }
            return contrast(worst, ink: ink)
        }
        func measure(_ zone: CardTextZone, ink: String, band: CardEdgeBand?) -> CardTextTreatment {
            let mean = average(sampled[zone]!, band: band, zone: zone, design: c.design)
            return CardTextTreatment(ink: ink, band: band, averageContrast: contrast(mean, ink: ink),
                                     minimumContrast: minimum(zone, ink: ink, band: band))
        }
        let plain = Dictionary(uniqueKeysWithValues: zones.map { zone in
            (zone, [measure(zone, ink: "#000000", band: nil), measure(zone, ink: "#FFFFFF", band: nil)])
        })
        for edge in [CardEdgeBand.Edge.top, .bottom] {
            let group = zones.filter { edge == .top ? $0 == .bank : $0 != .bank }
            guard !group.isEmpty else { continue }
            let untreated = group.map { plain[$0]!.max { $0.minimumContrast < $1.minimumContrast }! }
            if zip(group, untreated).allSatisfy({ zone, treatment in
                min(treatment.averageContrast, treatment.minimumContrast) >= (bounds[zone]!.low == bounds[zone]!.high ? 4.5 : 4.6)
            }) {
                for (zone, treatment) in zip(group, untreated) { treatments[zone] = treatment }
                continue
            }
            func band(_ ink: String, _ opacity: Double) -> CardEdgeBand {
                CardEdgeBand(edge: edge, width: 1, color: tones[ink]!, opacity: opacity)
            }
            func candidate(_ ink: String) -> CardEdgeBand {
                var low = 0.0, high = 1.0
                for _ in 0..<14 {
                    let mid = (low + high) / 2, light = band(ink, mid)
                    if group.allSatisfy({ minimum($0, ink: ink, band: light) >= 4.6 }) { high = mid } else { low = mid }
                }
                return band(ink, min(1, ceil(high * 1_000) / 1_000))
            }
            // Preserve the ink that suits the actual artwork; switch if it needs too much lighting.
            let inks = ["#000000", "#FFFFFF"].sorted { a, b in
                group.reduce(0) { $0 + log(plain[$1]!.first { $0.ink == a }!.averageContrast) }
                > group.reduce(0) { $0 + log(plain[$1]!.first { $0.ink == b }!.averageContrast) }
            }
            let preferred = candidate(inks[0]), other = candidate(inks[1])
            let chosen: (String, CardEdgeBand)
            if preferred.opacity <= CardEdgeBand.tastefulOpacity { chosen = (inks[0], preferred) }
            else if other.opacity <= CardEdgeBand.tastefulOpacity { chosen = (inks[1], other) }
            else { chosen = preferred.opacity < other.opacity ? (inks[0], preferred) : (inks[1], other) }
            bands.append(chosen.1)
            for zone in group { treatments[zone] = measure(zone, ink: chosen.0, band: chosen.1) }
        }
        return CardLegibility(treatments: treatments, bands: bands)
    }

}
