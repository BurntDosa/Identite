import CoreGraphics
import Foundation
import Testing
@testable import IDCore

struct CardColorExtractorTests {
    @Test func allocationFailureDoesNotInventScannedColours() throws {
        let source = try image(blocks: [("#770A3C", 1)])
        let result = CardColorExtractor.colors(from: source, makeContext: { _ in nil })
        #expect(result == nil)
    }
    private func image(blocks: [(String, Double)], glare: Bool = false) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        var x = 0.0
        for (hex, share) in blocks {
            let rgb = CardRGB(hex).channels
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [rgb.x, rgb.y, rgb.z, 1])!)
            context.fill(CGRect(x: x, y: 0, width: 640 * share, height: 400))
            x += 640 * share
        }
        if glare {
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 220, y: 80, width: 200, height: 160))
        }
        return try #require(context.makeImage())
    }

    @Test func blockImageYieldsItsColours() throws {
        let source = try image(blocks: [("#770A3C", 0.60), ("#B91532", 0.20), ("#9C5868", 0.12), ("#3763A4", 0.08)])
        let colors = try #require(CardColorExtractor.colors(from: source))
        for (role, expected) in [(CardColorRole.primary, "#770A3C"), (.secondary, "#B91532"), (.accent, "#9C5868")] {
            let close = CardRGB.distance(CardRGB(colors[role]).lab, CardRGB(expected).lab) < 6
            #expect(close, "Dominant synthetic block was not recovered")
        }
    }

    @Test func deterministic() throws {
        let source = try image(blocks: [("#0B3D91", 0.6), ("#1663C7", 0.25), ("#F2B134", 0.15)])
        #expect(CardColorExtractor.colors(from: source) == CardColorExtractor.colors(from: source))
    }

    private func checkDistinctAndReadable(_ image: CGImage) throws {
        let colors = try #require(CardColorExtractor.colors(from: image))
        for (i, first) in CardColorRole.allCases.enumerated() {
            for second in CardColorRole.allCases.dropFirst(i + 1) {
                let separated = CardRGB.distance(CardRGB(colors[first]).lab, CardRGB(colors[second]).lab) >= 10
                #expect(separated, "Monochrome tones were not perceptually separated")
            }
        }
        var generator = FixedCardTestGenerator()
        #expect(CardFaceCatalog.meetsContrast(CardFaceCatalog.random(colors: colors, using: &generator)))
    }

    @Test func nearMonochromeStillGivesThreeRoles() throws {
        try checkDistinctAndReadable(image(blocks: [("#F2F2F2", 1)], glare: true))
    }

    @Test func blackCard() throws {
        try checkDistinctAndReadable(image(blocks: [("#111111", 1)]))
    }

    @Test func whiteBlackAndSilver() throws {
        for hex in ["#FFFFFF", "#000000", "#AAAAAA"] { try checkDistinctAndReadable(image(blocks: [(hex, 1)])) }
    }

    @Test func nearbyClustersMergeBeforeRanking() throws {
        let source = try image(blocks: [("#770A3C", 0.35), ("#7B0D40", 0.3), ("#3763A4", 0.2), ("#E8D9B5", 0.15)])
        let colors = try #require(CardColorExtractor.colors(from: source))
        let largest = CardRGB.distance(CardRGB(colors.primary).lab, CardRGB("#770A3C").lab) < 6
        let second = CardRGB.distance(CardRGB(colors.secondary).lab, CardRGB("#3763A4").lab) < 6
        #expect(largest && second)
    }

    @Test func colourMathReferenceAndRoundTrip() {
        let red = CardRGB("#FF0000").lab
        #expect(abs(red.x - 53.2408) < 0.001)
        #expect(abs(red.y - 80.0925) < 0.001)
        #expect(abs(red.z - 67.2032) < 0.001)
        for hex in ["#FFFFFF", "#000000", "#770A3C", "#3763A4", "#808080"] {
            let unchanged = CardRGB(lab: CardRGB(hex).lab).hex == hex
            #expect(unchanged)
        }
    }
}
