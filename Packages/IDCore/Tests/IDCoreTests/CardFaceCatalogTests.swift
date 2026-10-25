import Foundation
import Testing
@testable import IDCore

struct CardFaceCatalogTests {
    @Test func colourControlsMatchNonemptyPaints() {
        let reduced: [String: [CardColorRole]] = [
            "cardy.4": [.primary, .accent], "cardy.8": [.primary], "cardy.16": [.primary],
            "cardy.10": [.primary, .accent], "cardy.25": [.primary, .accent],
            "cardy.28": [.primary, .secondary],
            "cardy.29": [.primary, .secondary], "astra.postageGarden": [.primary, .secondary]
        ]
        for design in CardFaceCatalog.designs {
            #expect(CardFaceCatalog.colorRoles(for: design) == reduced[design, default: CardColorRole.allCases])
        }
    }

    @Test func variant17RetainsItsNestedOverlayBlend() throws {
        let pattern = try #require(CardFaceCatalog.layers(for: "cardy.17").first { $0.asset == "cardy.17.pattern" })
        let children = try #require(pattern.children)
        #expect(children.count == 2)
        #expect(children[0].opacity == 0.1)
        #expect(children[1].blend == "overlay")
        #expect(children[1].opacity == 0.2)
    }
    @Test func everyCardyDesignHasLayers() throws {
        for id in CardFaceCatalog.designs {
            let layers = CardFaceCatalog.layers(for: id)
            #expect(!layers.isEmpty, "\(id) has no artwork")
            for layer in layers {
                #expect(CardFaceCatalog.assets.contains(layer.asset))
                #expect(layer.bounds.count == 4)
                #expect((0...1).contains(layer.opacity))
            }
            if id.hasPrefix("astra.") { #expect(layers.count == 1 && layers[0].asset == id) }
        }
    }

    @Test func variant8DrawsChromeOnce() {
        #expect(CardFaceCatalog.layers(for: "cardy.8").filter(\.toneMapped).count == 1)
    }

    @Test func overlaysAreArt() {
        for id in ["cardy.7", "cardy.8"] {
            #expect(CardFaceCatalog.layers(for: id).contains { $0.asset == id + ".overlay" })
        }
    }

    @Test func sourceLayerOrderAndOpacitySurvive() {
        let layers = CardFaceCatalog.layers(for: "cardy.12")
        #expect(layers.map(\.asset) == ["cardy.12.background-fill", "cardy.12.pattern", "cardy.12.noise", "cardy.12.overlay"])
        #expect(layers.first { $0.asset == "cardy.12.pattern" }?.opacity == 0.25)
        #expect(layers.first { $0.asset == "cardy.12.noise" }?.blend == "overlay")
    }

    @Test func shippedAssetsMatchTable() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = root.appendingPathComponent("App/Shared/Cards/Composed/CardyParts.xcassets")
        let shipped = Set(try FileManager.default.contentsOfDirectory(at: catalog, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "imageset" }.map { $0.deletingPathExtension().lastPathComponent })
        #expect(shipped == Set(CardFaceCatalog.assetNames))
        for name in shipped {
            let file = catalog.appendingPathComponent(name + ".imageset/part.png")
            #expect((try Data(contentsOf: file)).count > 0)
        }
    }
}
