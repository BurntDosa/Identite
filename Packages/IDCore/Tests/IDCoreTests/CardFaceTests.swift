import Foundation
import Testing
@testable import IDCore

struct CardFaceTests {
    private let colors = CardColors(primary: "#770A3C", secondary: "#B91532", accent: "#3763A4")
    private let scanned = CardColors(primary: "#123456", secondary: "#ABCDEF", accent: "#FEDCBA")

    private func face(_ raw: String) throws -> CardFace {
        guard case .face(let value) = CardDesign(rawValue: raw) else {
            throw NSError(domain: "Expected fixed face", code: 1)
        }
        return value
    }

    private func mix(pattern: String, base: String = "cardy.3.background-fill") throws -> String {
        let object: [String: Any] = ["base": base, "pattern": pattern, "shape": "unknown.shape",
            "texture": true, "layout": "future", "panel": "unknown.panel", "colorway": "card",
            "presetID": "garnet", "colors": ["primary": colors.primary, "secondary": colors.secondary, "accent": colors.accent],
            "cardColors": ["primary": scanned.primary, "secondary": scanned.secondary, "accent": scanned.accent]]
        return "mix1:" + String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }

    @Test func facesRoundTrip() throws {
        for id in CardFaceCatalog.designs {
            for way in [CardColorway.preset, .custom, .card] {
                let original = CardFace(design: id, colors: colors, colorway: way, presetID: "garnet", cardColors: scanned)
                let raw = CardDesign.face(original).rawValue
                #expect(raw.hasPrefix("design1:"))
                #expect(!raw.contains("\n"))
                #expect(try face(raw) == original)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                #expect(raw == "design1:" + String(decoding: try encoder.encode(original), as: UTF8.self))
            }
        }
    }

    @Test func designCountIs37() {
        #expect(CardFaceCatalog.designs.count == 37)
        #expect(Set(CardFaceCatalog.designs).count == 37)
        #expect(Array(CardFaceCatalog.designs.prefix(30)) == (1...30).map { "cardy.\($0)" })
        #expect(CardFaceCatalog.name(for: "cardy.12") == "Cardy 12")
        #expect(CardFaceCatalog.name(for: "astra.swissSignal") == "Swiss Signal")
    }

    @Test func mixMigratesByPattern() throws {
        for (pattern, expected) in [("astra.swissSignal", "astra.swissSignal"),
                                    ("cardy.12.pattern", "cardy.12"), ("cardy.8.3d-object", "cardy.8")] {
            let value = try face(mix(pattern: pattern))
            #expect(value.design == expected)
            #expect(value.colors == colors)
            #expect(value.colorway == .card)
            #expect(value.presetID == "garnet")
            #expect(value.cardColors == scanned)
        }
    }

    @Test func mixWithUnknownPartsStillMigrates() throws {
        #expect(try face(mix(pattern: "cardy.99.nope")).design == "cardy.3")
        let raw = try mix(pattern: "cardy.99.nope", base: "future.base")
        let value = try face(raw)
        #expect(value.design == CardFaceCatalog.fallbackDesign(for: raw))
        #expect(value.colors == colors)
        #expect(value.cardColors == scanned)
    }

    @Test func largeLegacySampleMigratesAndRoundTrips() throws {
        for index in 0..<600 {
            let id = index % 30 + 1
            let raw = try mix(pattern: "cardy.\(id).retired-\(index)")
            let migrated = try face(raw)
            #expect(migrated.design == "cardy.\(id)")
            #expect(migrated.colors == colors)
            #expect(try face(CardDesign.face(migrated).rawValue) == migrated)
        }
    }

    @Test func genericMigrates() throws {
        for preset in CardFaceCatalog.presets {
            let value = try face("generic." + preset.id)
            #expect(value.colorway == .preset)
            #expect(value.presetID == preset.id)
            #expect(value.colors == preset.colors)
        }
        #expect(try face("generic.future").colors.isValid)
    }

    @Test func corruptDesignFallsBack() throws {
        for raw in ["design1:{bad", "design1:", "mix1:{", "mix1:{}"] {
            let value = try face(raw)
            #expect(value.design == CardFaceCatalog.fallbackDesign(for: raw))
            #expect(CardFaceCatalog.presets.contains { $0.colors == value.colors })
            #expect(try face(raw) == value)
        }
        let raw = ##"design1:{"design":"cardy.999","colors":{"primary":"#770A3C","secondary":"#B91532","accent":"#3763A4"},"colorway":"custom"}"##
        #expect(try face(raw).design == CardFaceCatalog.fallbackDesign(for: raw))
        #expect(try face(raw).colors == colors)
    }

    @Test func corruptMetadataKeepsRecoverableColours() throws {
        let raw = ##"design1:{"design":9,"colors":{"primary":"#123456","secondary":"bad","accent":"#FEDCBA"},"colorway":false,"presetID":8,"cardColors":{"primary":"#123456","secondary":"#ABCDEF","accent":"#FEDCBA"}}"##
        let value = try face(raw)
        #expect(value.colors.primary == "#123456")
        #expect(value.colors.accent == "#FEDCBA")
        #expect(value.colors.isValid)
        #expect(value.cardColors == scanned)
        #expect(try face(CardDesign.face(value).rawValue) == value)
    }

    @Test func replicasStayRawAndPublicFallbackIsStable() throws {
        for replica in [CardDesign.hsbcLivePlus, .hdfcPixelPlay, .hdfcMillennia] {
            #expect(CardDesign(rawValue: replica.rawValue) == replica)
            let fallback = CardFaceCatalog.fallback(for: replica.rawValue)
            #expect(CardFaceCatalog.designs.contains(fallback.design))
            #expect(fallback == CardFaceCatalog.fallback(for: replica.rawValue))
            #expect(try face(CardDesign.face(fallback).rawValue) == fallback)
        }
        #expect(CardDesign.hsbcLivePlus.rawValue == "hsbcLivePlus")
        #expect(CardDesign(rawValue: "") == nil)
        #expect(CardDesign(rawValue: "future-design") == nil)
        // FNV-1a known vector; do not use Swift's randomized Hasher.
        #expect(CardFaceCatalog.fallbackDesign(for: "") == "astra.horizonTicket")
    }
}

extension CardFaceTests {
    @Test func cardColorwayWithoutScannedColorsRecoversAsCustom() throws {
        for id in ["\"cardy.15\"", "9"] {
            let raw = ##"design1:{"design":\##(id),"colors":{"primary":"#123456","secondary":"#ABCDEF","accent":"#FEDCBA"},"colorway":"card"}"##
            let value = try face(raw)
            #expect(value.colorway == .custom)
            #expect(value.colors == scanned)
            #expect(value.cardColors == nil)
        }
    }

    @Test func unrelatedPayloadEditPreservesUnknownDesign() throws {
        let raw = "design99:future-format"
        var payload = IDPayload(values: [FieldKey.cardDesign.rawValue: raw])
        payload = try IDPayload.decode(payload.encoded())
        payload[.bank] = "Test Bank"
        #expect(try IDPayload.decode(payload.encoded())[.cardDesign] == raw)
    }
}
