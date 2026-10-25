import Foundation
import Testing
@testable import IDCore

struct CardPaletteTests {
    @Test func everyIDKindHasA3x3Mesh() {
        for kind in IDKind.allCases {
            if [.creditCard, .debitCard].contains(kind) {
                #expect(CardPalette.mesh(for: kind) == nil)
            } else {
                #expect(CardPalette.mesh(for: kind)?.count == 9)
            }
        }
    }
    @Test func textContrastAtAnchors() {
        for kind in IDKind.allCases {
            guard let mesh = CardPalette.mesh(for: kind) else { continue }
            for i in [0, 6, 8] {
                #expect(Contrast.ratio(CardPalette.textHex(for: kind), mesh[i]) >= 4.5, "\(kind) anchor \(i)")
            }
        }
    }
    @Test func genericContrast() {
        for palette in GenericPalette.allCases {
            let ink = palette == .sand ? "#1C1C1E" : "#FFFFFF"
            for stop in [palette.hexStops.first!, palette.hexStops.last!] {
                #expect(Contrast.ratio(ink, stop) >= 4.5, "\(palette) \(stop)")
            }
        }
    }
    @Test func lightSurfacesRetainContrastWhenDimmed() {
        func dim(_ hex: String) -> String {
            let value = UInt32(hex.dropFirst(), radix: 16)!
            return "#" + [16, 8, 0].map { String(format: "%02X", Int((Double((value >> $0) & 255) * 0.9).rounded())) }.joined()
        }
        let surfaces = IDKind.allCases.filter(CardPalette.isLight).flatMap { kind in
            [0, 6, 8].map { CardPalette.mesh(for: kind)![$0] }
        } + [GenericPalette.sand.hexStops.first!, GenericPalette.sand.hexStops.last!]
        for stop in surfaces { #expect(Contrast.ratio(dim("#1C1C1E"), dim(stop)) >= 4.5, "Dimmed \(stop)") }
    }
    @Test func genericPalettesAndDefaults() {
        #expect(GenericPalette.allCases.count == 6)
        #expect(CardDesign.defaultGeneric(forBank: "ICICI Bank") == .face(CardFaceCatalog.fallback(for: "ICICI Bank")))
        #expect(CardDesign.defaultGeneric(forBank: "") == .face(CardFaceCatalog.fallback(for: "")))
        for design in [CardDesign.hsbcLivePlus, .hdfcPixelPlay, .hdfcMillennia] {
            #expect(CardDesign(rawValue: design.rawValue) == design)
        }
        for palette in GenericPalette.allCases {
            #expect(CardDesign(rawValue: "generic." + palette.rawValue) == .face(CardFace(design: CardFaceCatalog.fallbackDesign(for: "generic." + palette.rawValue), colors: CardFaceCatalog.presets.first { $0.id == palette.rawValue }!.colors, colorway: .preset, presetID: palette.rawValue)))
        }
        #expect(CardDesign(rawValue: "future-design") == nil)
        #expect(CardDesign(rawValue: "generic.unknown") != nil)
    }
    @Test func contrastMath() {
        #expect(abs(Contrast.ratio("#000000", "#FFFFFF") - 21) < 0.01)
        #expect(Contrast.ratio("#123456", "#123456") == 1)
        #expect(abs(Contrast.ratio("#777777", "#FFFFFF") - 4.478) < 0.001)
    }
}
