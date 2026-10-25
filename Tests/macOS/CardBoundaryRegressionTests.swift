import AppKit
import IDCore
import SwiftUI
import XCTest

@MainActor final class CardBoundaryRegressionTests: XCTestCase {
    private func image<V: View>(_ view: V) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false
        return try XCTUnwrap(renderer.cgImage)
    }
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width * image.height * 4))
    }

    func testStyledCornersNeverExposeLayersBelowTheirBoundaryArtwork() throws {
        for id in ["cardy.7", "cardy.12", "cardy.13", "cardy.22"] {
            let layers = CardFaceCatalog.paintLayers(for: id)
            let colors = CardFaceCatalog.presets[6].colors
            for bottom in [false, true] {
                let covering = bottom ? layers.count - 1 : (["cardy.7", "cardy.13"].contains(id) ? 1 : 0)
                func styled(_ lower: Color) -> some View {
                    ZStack {
                        lower
                        ForEach(Array(layers[covering...]), id: \.asset) { layer in
                            CardyParts(layer: layer, colors: colors).blendMode(layer.swiftUIBlendMode).opacity(layer.opacity)
                        }
                    }.frame(width: 343, height: 343 / 1.586)
                        .modifier(CardStyle(width: 343, isLight: false, preservesColors: true))
                }
                let first = try image(styled(Color(red: 1, green: 0, blue: 1))), second = try image(styled(.green))
                let a = try pixels(first), b = try pixels(second)
                let clip = try image(Color.white.frame(width: 343, height: 343 / 1.586)
                    .clipShape(RoundedRectangle(cornerRadius: 343 * 0.037, style: .continuous)))
                let coverage = try pixels(clip)
                for right in [false, true] {
                    var differences = 0
                    // Inspect the full corner region inside and outside the continuous CardStyle clip.
                    for y in 0..<45 { for x in 0..<45 {
                        let px = right ? first.width - 1 - x : x
                        let py = bottom ? first.height - 1 - y : y
                        let i = (py * first.width + px) * 4
                        guard coverage[i + 3] == 255, px > 1, px < first.width - 2, py > 1, py < first.height - 2 else { continue }
                        if (0..<4).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) > 1 }) { differences += 1 }
                    } }
                    XCTAssertEqual(differences, 0, "\(id) \(bottom ? "bottom" : "top") \(right ? "right" : "left") leaks lower art")
                }
            }
        }
    }

    func testCardy26CircleJoinIsFullyOpaque() throws {
        let layer = try XCTUnwrap(CardFaceCatalog.paintLayers(for: "cardy.26").first { $0.asset == "cardy.26.back" })
        let name = try XCTUnwrap(layer.masks["#546EF3"])
        let mask = try XCTUnwrap(CardyParts.bundle.image(forResource: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try pixels(mask)
        let join = Int((layer.bounds[0] + layer.bounds[2] * 0.25) * Double(mask.width))
        var minimum = UInt8.max
        for y in Int(Double(mask.height) * 0.55)..<Int(Double(mask.height) * 0.95) {
            for x in (join - 1)...(join + 1) { minimum = min(minimum, data[(y * mask.width + x) * 4 + 3]) }
        }
        XCTAssertEqual(minimum, 255, "Touching halves must rasterize as one circle")
    }

    func testCardy15LowerPatternSurvivesOverlappingColours() throws {
        for accent in ["#0DB774", "#0EB675", "#28A774"] { for width in [100.0, 343] {
            let colors = CardColors(primary: "#F5B635", secondary: "#0DB774", accent: accent)
            let face = CardFace(design: "cardy.15", colors: colors)
            func styled(_ overrides: [String: [String: String]]) -> some View {
                CardFaceArt(face: face, width: width, sourcePaintOverrides: overrides).artwork
                    .modifier(CardStyle(width: width, isLight: false, preservesColors: true))
            }
            let actual = try image(styled([:]))
            let flattened = try image(styled(["cardy.15.pattern": ["#FFFFFF": colors.paint(.primary)]]))
            let a = try pixels(actual), b = try pixels(flattened)
            var visible = 0, count = 0
            for y in Int(Double(actual.height) * 0.50)..<Int(Double(actual.height) * 0.95) {
                for x in 3..<(actual.width - 3) {
                    let i = (y * actual.width + x) * 4
                    if (0..<3).contains(where: { abs(Int(a[i + $0]) - Int(b[i + $0])) >= 6 }) { visible += 1 }
                    count += 1
                }
            }
            XCTAssertGreaterThan(Double(visible) / Double(count), 0.005, "Cardy 15 lower pattern at width \(width)")
        } }
    }
}
