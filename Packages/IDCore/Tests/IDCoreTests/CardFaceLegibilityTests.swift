import Foundation
import Testing
@testable import IDCore

struct FixedCardTestGenerator: RandomNumberGenerator {
    var state: UInt64 = 20261024
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

struct CardFaceLegibilityTests {
    static let extremes = [
        CardColors(primary: "#777777", secondary: "#777777", accent: "#777777"),
        CardColors(primary: "#FAFAFA", secondary: "#FAFAFA", accent: "#FAFAFA"),
        CardColors(primary: "#050505", secondary: "#050505", accent: "#050505"),
        CardColors(primary: "#FF0000", secondary: "#00FF00", accent: "#0000FF"),
        CardColors(primary: "#3A3A3A", secondary: "#404040", accent: "#383838")
    ]

    @Test func everyDesignEveryPresetPasses() {
        for design in CardFaceCatalog.designs { for preset in CardFaceCatalog.presets {
            let face = CardFace(design: design, colors: preset.colors, colorway: .preset, presetID: preset.id)
            #expect(CardFaceCatalog.meetsContrast(face), "\(design) / \(preset.id)")
            #expect(CardFaceCatalog.legibility(for: face).bands.allSatisfy { $0.width == 1 })
        } }
    }

    @Test func customExtremesPass() {
        for design in CardFaceCatalog.designs { for (index, colors) in Self.extremes.enumerated() {
            #expect(CardFaceCatalog.meetsContrast(CardFace(design: design, colors: colors)), "\(design) / extreme \(index)")
        } }
    }

    @Test func designsNeverFlatten() {
        for design in CardFaceCatalog.designs { for (index, colors) in Self.extremes.enumerated() {
            let visibility = CardFaceCatalog.visibility(CardFace(design: design, colors: colors))
            #expect(visibility >= 0.04, "\(design) / extreme \(index): \(visibility)")
        } }
    }

    @Test func shuffleKeepsColours() {
        var generator = FixedCardTestGenerator()
        for design in CardFaceCatalog.designs {
            let face = CardFace(design: design, colors: Self.extremes[0], colorway: .card,
                                presetID: "garnet", cardColors: Self.extremes[4])
            let next = CardFaceCatalog.shuffled(face, using: &generator)
            #expect(next.design != face.design)
            #expect(next.colors == face.colors)
            #expect(next.colorway == face.colorway)
            #expect(next.presetID == face.presetID)
            #expect(next.cardColors == face.cardColors)
        }
    }

    @Test func randomSkipsHeavyBands() {
        var generator = FixedCardTestGenerator()
        for index in 0..<500 {
            let colors = (Self.extremes + CardFaceCatalog.presets.map(\.colors))[index % 14]
            let face = CardFaceCatalog.random(colors: colors, colorway: .custom, presetID: nil, cardColors: nil, using: &generator)
            #expect(CardFaceCatalog.designs.contains(face.design))
            #expect(CardFaceCatalog.visibility(face) >= 0.04)
            #expect(CardFaceCatalog.legibility(for: face).bands.allSatisfy { $0.opacity <= 0.40 })
        }
    }

    @Test func chromeFollowsPrimary() throws {
        let colors = try #require(CardFaceCatalog.presets.first { $0.id == "garnet" }?.colors)
        let face = CardFace(design: "cardy.8", colors: colors)
        let samples = CardFaceCoverage.samples(face, zone: nil)
        let average = samples.reduce(SIMD3<Double>.zero, +) / Double(samples.count)
        let original = CardRGB(colors.primary).lab, actual = CardRGB(average).lab
        let difference = abs(atan2(actual.z, actual.y) - atan2(original.z, original.y)) * 180 / .pi
        #expect(min(difference, 360 - difference) < 20)
        for layer in CardFaceCatalog.paintLayers(for: "cardy.8") where layer.toneMapped {
            #expect(colors.paint("primary", layer: layer) == colors.primary)
            #expect(abs(CardRGB(colors.paint("background", layer: layer)).lab.x - 18) < 0.5)
            #expect(abs(CardRGB(colors.paint("highlight", layer: layer)).lab.x - 90) < 0.5)
        }
    }

    @Test func solidOverlayDoesNotGetABand() {
        for id in ["cardy.7", "cardy.9", "cardy.12"] {
            let face = CardFace(design: id, colors: CardFaceCatalog.presets[0].colors)
            for zone in [CardTextZone.last4, .network] {
                #expect(CardFaceCatalog.legibility(for: face)[zone].band == nil)
            }
        }
    }
}

extension CardFaceLegibilityTests {
    @Test func vanishedPatternCannotBorrowVisibilityFromItsSolidPanel() {
        let colors = CardColors(primary: "#F5B635", secondary: "#0DB774", accent: "#0DB774")
        let face = CardFace(design: "cardy.15", colors: colors)
        #expect(CardFaceCoverage.visibility(face, paintOverrides: ["cardy.15.pattern": ["#FFFFFF": colors.paint(.primary)]]) < 0.04)
    }

    @Test func allDesignsKeepPatternsWithEqualAndNearEqualRoles() {
        let palettes = Self.extremes + [
            CardColors(primary: "#777777", secondary: "#787778", accent: "#777878"),
            CardColors(primary: "#F5B635", secondary: "#0DB774", accent: "#0DB774"),
            CardColors(primary: "#F5B635", secondary: "#0DB774", accent: "#0EB675")
        ]
        for id in CardFaceCatalog.designs { for (index, colors) in palettes.enumerated() {
            #expect(CardFaceCatalog.visibility(CardFace(design: id, colors: colors)) >= 0.04, "\(id), palette \(index)")
        } }
    }

    @Test func secondaryAndAccentRemainDistinctFromEachOther() {
        for accent in ["#0DB774", "#0EB675", "#28A774"] {
            let colors = CardColors(primary: "#F5B635", secondary: "#0DB774", accent: accent)
            let backing = CardRGB(colors.paint(.primary)).lab
            let pattern = CardRGB(colors.paint(.secondary)).lab
            #expect(CardRGB.distance(backing, pattern) >= 24)
        }
    }

    @Test func flatPrimaryDoesNotCountAsVisibleArt() {
        #expect(CardFaceCatalog.visibility(CardFace(design: "missing", colors: Self.extremes[0])) == 0)
    }

    @Test func equalColoursDeriveDistinctArtworkTones() {
        for value in ["#000000", "#777777", "#FFFFFF"] {
            let colors = CardColors(primary: value, secondary: value, accent: value)
            for role in [CardPaintRole.primary, .secondary, .accent, .highlight] {
                #expect(abs(CardRGB(colors.paint(role)).lab.x - CardRGB(value).lab.x) >= 17)
            }
        }
    }

    @Test func bandGeometryAndTones() {
        for preset in CardFaceCatalog.presets { for lightness in [10.0, 96.0] {
            #expect(abs(CardRGB(CardRGB(preset.colors.primary).tone(lightness: lightness).hex).lab.x - lightness) < 0.5)
        } }
        let face = CardFace(design: "cardy.8", colors: CardColors(primary: "#FFFFFF", secondary: "#000000", accent: "#FFFFFF"))
        let plan = CardFaceCatalog.legibility(for: face)
        #expect(!plan.bands.isEmpty)
        for band in plan.bands {
            #expect(band.alpha(atY: 0.5) == 0)
            #expect(band.width == 1)
            #expect(band.opacity > 0 && band.opacity <= 1)
            for t in stride(from: 0.0, to: 0.5, by: 0.01) {
                let y = band.edge == .top ? t : 1 - t
                let next = band.edge == .top ? t + 0.01 : 1 - t - 0.01
                #expect(band.alpha(atY: y) >= band.alpha(atY: next) - 0.000001)
            }
        }
        #expect(plan[.last4].bandOpacity == plan[.network].bandOpacity)
    }

    @Test func masksContainNoUnrecolouredSourceRGB() throws {
        for design in CardFaceCatalog.designs {
            for layer in CardFaceCatalog.paintLayers(for: design) where layer.neutral == nil {
                let part = try #require(CardFaceCoverage.designs[design]?[layer.asset])
                let n = part.paints.count
                for zone in part.zones {
                    let bytes = Array(zone)
                    #expect(stride(from: n, to: bytes.count, by: n+4).allSatisfy { offset in
                        (0..<4).allSatisfy { bytes[offset+$0] == 0 }
                    }, "Unrecoloured RGB in \(layer.asset)")
                }
            }
        }
    }

    @Test func splitInkAndBankGeometry() {
        let face = CardFace(design: "cardy.12", colors: CardColors(primary: "#FFFFFF", secondary: "#000000", accent: "#FFFFFF"))
        #expect(face.ink(for: .bank) == "#000000")
        #expect(face.ink(for: .last4) == "#FFFFFF")
        #expect(face.ink(for: .network) == "#FFFFFF")
        for (id, edge) in [("cardy.1", 155.0/311), ("cardy.4", 198.0/311), ("cardy.16", 169.0/311)] {
            let box = CardTextZone.bank.bounds(for: id)
            #expect(abs(box.x + box.width - (edge - 0.04)) < 0.00001)
        }
    }
}
