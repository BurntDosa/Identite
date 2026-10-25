import AppKit
import IDCore
import SwiftUI
import XCTest

@MainActor final class CardFaceFidelityTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var output: URL { root.appendingPathComponent("docs/design/build-review/fixed") }
    private struct Score: Codable {
        let design: String
        let meanAbsoluteDifference: Double
        let coarseMeanAbsoluteDifference: Double
        let comparedPixels: Int
        let excludedLogoPixels: Int
        let notes: String
    }
    private struct Row {
        let score: Score
        let original: CGImage
        let rendered: CGImage
    }

    func testFidelitySheet() throws {
        let cache = root.appendingPathComponent("build/figma/fixed-originals")
        let ids = (1...30).map { "cardy.\($0)" }
        guard ids.allSatisfy({ FileManager.default.fileExists(atPath: cache.appendingPathComponent($0 + ".png").path) }) else {
            throw XCTSkip("Cache all 30 Figma 1604:1803 variant PNGs at scale=3, use_absolute_bounds=true in build/figma/fixed-originals/cardy.N.png; CI requires no token.")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scratch = root.appendingPathComponent("build/fixed/fidelity")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        var rows: [Row] = []
        for id in ids {
            let original = try load(cache.appendingPathComponent(id + ".png"))
            let layers = CardFaceCatalog.paintLayers(for: id)
            let base = layers[0].roles.keys.first!
            let colors = CardColors(primary: base, secondary: base, accent: base)
            var overrides = Dictionary(uniqueKeysWithValues: layers.map { layer in
                (layer.asset, Dictionary(uniqueKeysWithValues: layer.masks.keys.filter { $0.hasPrefix("#") }.map { ($0, $0) }))
            })
            if let chrome = layers.first(where: \.toneMapped) {
                overrides[chrome.asset] = try chromeSourcePaints(chrome)
            }
            let view = CardFaceArt(face: CardFace(design: id, colors: colors), width: CGFloat(original.width), sourcePaintOverrides: overrides)
            let rendered = try renderArtwork(view, width: original.width)
            let mapped = try resize(original, width: rendered.width, height: rendered.height)
            let a = try pixels(mapped), b = try pixels(rendered)
            var total = 0, count = 0, logos = 0
            for y in 0..<mapped.height { for x in 0..<mapped.width {
                let offset = (y * mapped.width + x) * 4
                if id == "cardy.6", excludesLogo(x: Double(x) / Double(mapped.width), y: Double(y) / Double(mapped.height)) {
                    logos += 1; continue
                }
                // The fixed card template owns corner rounding; compare the source's opaque artwork.
                guard a[offset + 3] == 255 else { continue }
                for channel in 0..<3 { total += abs(Int(a[offset + channel]) - Int(b[offset + channel])) }
                count += 1
            } }
            let notes = id == "cardy.6" ? "Wave/Piqo sample-logo rectangles excluded by owner; all other Top side art retained."
                : id == "cardy.8" ? "Original chrome colours use a least-squares inverse three-stop luminance ramp; runtime retains L* 18 / primary / L* 90."
                : ""
            let score = Score(design: id, meanAbsoluteDifference: Double(total) / Double(count * 3),
                              coarseMeanAbsoluteDifference: try coarseDifference(mapped, rendered, excludingLogos: id == "cardy.6"),
                              comparedPixels: count, excludedLogoPixels: logos, notes: notes)
            rows.append(Row(score: score, original: mapped, rendered: rendered))
            try save(rendered, to: scratch.appendingPathComponent(id + ".png"))
            print(String(format: "FIDELITY %@ MAD %.4f /255", id, score.meanAbsoluteDifference))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows.map(\.score)).write(to: output.appendingPathComponent("fidelity.json"))
        try sheet(rows, to: output.appendingPathComponent("fidelity.png"))
        for offset in stride(from: 0, to: rows.count, by: 5) {
            try sheet(Array(rows[offset..<min(offset + 5, rows.count)]),
                      to: output.appendingPathComponent(String(format: "fidelity-%02d.png", offset / 5 + 1)))
        }
        XCTAssertEqual(rows.count, 30)
    }

    private func renderArtwork(_ view: CardFaceArt, width: Int) throws -> CGImage {
        let renderer = ImageRenderer(content: view.artwork)
        renderer.scale = 1; renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.cgImage)
        return try XCTUnwrap(image.cropping(to: CGRect(x: 0, y: 0, width: Double(width), height: floor(Double(width) / 1.586))))
    }

    func testFidelityExportHasNoFractionalBlackRow() throws {
        let colors = CardColors(primary: "#9AB4C3", secondary: "#9AB4C3", accent: "#9AB4C3")
        let overrides = Dictionary(uniqueKeysWithValues: CardFaceCatalog.paintLayers(for: "cardy.12").map { layer in
            (layer.asset, Dictionary(uniqueKeysWithValues: layer.masks.keys.map { ($0, "#9AB4C3") }))
        })
        let image = try renderArtwork(CardFaceArt(face: CardFace(design: "cardy.12", colors: colors),
            width: 933, sourcePaintOverrides: overrides), width: 933)
        XCTAssertEqual(image.height, Int(floor(933 / 1.586)))
        let data = try pixels(image)
        for x in 50..<(image.width - 50) {
            let last = ((image.height - 1) * image.width + x) * 4
            let prior = last - image.width * 4
            for c in 0..<3 { XCTAssertEqual(data[last + c], data[prior + c]) }
        }
    }

    private func excludesLogo(x: Double, y: Double) -> Bool {
        // Owner-approved exclusions: Figma 1604:4718 (Wave), 1604:4719 (Piqo), normalized to the card.
        [(0.08038585209, 0.12, 0.1543408360, 0.15), (0.71704180064, 0.12, 0.20578778135, 0.20)]
            .contains { x >= $0.0 && x < $0.0 + $0.2 && y >= $0.1 && y < $0.1 + $0.3 }
    }

    private func coarseDifference(_ a: CGImage, _ b: CGImage, excludingLogos: Bool) throws -> Double {
        let width = 64, height = 40
        let left = try pixels(resize(a, width: width, height: height))
        let right = try pixels(resize(b, width: width, height: height))
        var total = 0, count = 0
        for y in 0..<height { for x in 0..<width {
            let i = (y * width + x) * 4
            guard left[i + 3] == 255, !(excludingLogos && excludesLogo(x: Double(x) / Double(width), y: Double(y) / Double(height))) else { continue }
            for channel in 0..<3 { total += abs(Int(left[i + channel]) - Int(right[i + channel])) }
            count += 3
        } }
        return Double(total) / Double(count)
    }

    private func chromeSourcePaints(_ layer: CardFaceLayer) throws -> [String: String] {
        let source = try load(root.appendingPathComponent("docs/design/cardy/parts/8/paste-your-3d-object-here.png"))
        let data = try pixels(source), bounds = layer.bounds
        var low = 1.0, high = 0.0
        var luminances: [Double] = []
        for y in 0..<646 { for x in 0..<1024 {
            let sx = min(source.width - 1, Int((Double(x) / 1024 - bounds[0]) / bounds[2] * Double(source.width)))
            let sy = min(source.height - 1, Int((Double(y) / 646 - bounds[1]) / bounds[3] * Double(source.height)))
            let i = (sy * source.width + sx) * 4
            guard data[i + 3] > 10 else { continue }
            let value = (0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1]) + 0.0722 * Double(data[i + 2])) / Double(data[i + 3])
            low = min(low, value); high = max(high, value)
            luminances.append(value)
        } }
        // Fit the original greys to the existing three masks; no source image replaces production artwork.
        var equations = Array(repeating: Array(repeating: 0.0, count: 4), count: 3)
        for value in luminances {
            let t = sqrt((value - low) / max(0.01, high - low))
            let weights = [max(0, 1 - 2 * t), 1 - abs(2 * t - 1), max(0, 2 * t - 1)]
            for i in 0..<3 {
                for j in 0..<3 { equations[i][j] += weights[i] * weights[j] }
                equations[i][3] += weights[i] * value
            }
        }
        for column in 0..<3 {
            let pivot = equations[column][column]
            for j in column..<4 { equations[column][j] /= pivot }
            for row in 0..<3 where row != column {
                let factor = equations[row][column]
                for j in column..<4 { equations[row][j] -= factor * equations[column][j] }
            }
        }
        func hex(_ value: Double) -> String {
            let value = Int((255 * min(1, max(0, value))).rounded())
            return String(format: "#%02X%02X%02X", value, value, value)
        }
        return Dictionary(uniqueKeysWithValues: zip(["background", "primary", "highlight"], equations.map { hex($0[3]) }))
    }

    private func load(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
    private func resize(_ image: CGImage, width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let converted = try resize(image, width: image.width, height: image.height)
        return Array(try XCTUnwrap(converted.dataProvider?.data) as Data)
    }
    private func save(_ image: CGImage, to url: URL) throws {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
    }
    private func sheet(_ rows: [Row], to url: URL) throws {
        let cardWidth = 430.0, cardHeight = cardWidth / 1.586, rowHeight = cardHeight + 42
        let size = NSSize(width: cardWidth * 2 + 48, height: 46 + rowHeight * Double(rows.count))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.black]
        "Figma original  →  Identité source-paint render · 1.555 → 1.586".draw(at: NSPoint(x: 16, y: size.height - 30), withAttributes: font)
        for (index, row) in rows.enumerated() {
            let top = size.height - 46 - Double(index) * rowHeight
            String(format: "%@ · mean absolute RGB difference %.3f /255%@", row.score.design, row.score.meanAbsoluteDifference,
                   row.score.excludedLogoPixels > 0 ? " · sample logos masked" : "")
                .draw(at: NSPoint(x: 16, y: top - 18), withAttributes: font)
            for (column, image) in [row.original, row.rendered].enumerated() {
                let rect = NSRect(x: 16 + Double(column) * (cardWidth + 16), y: top - 26 - cardHeight, width: cardWidth, height: cardHeight)
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: rect, xRadius: cardWidth * 0.037, yRadius: cardWidth * 0.037).addClip()
                NSImage(cgImage: image, size: rect.size).draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
    }
}
