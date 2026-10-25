import AppKit
import IDCore
import SwiftUI
import XCTest

@MainActor final class CardFaceRenderTests: XCTestCase {
    func testEveryExposedColourChangesRenderedArtwork() throws {
        for design in CardFaceCatalog.designs {
            let original = CardFace(design: design, colors: colors)
            var payload = IDPayload()
            payload[.cardDesign] = CardDesign.face(original).rawValue
            let editor = CardCustomizeView(kind: .debitCard, payload: .constant(payload))
            let before = try pixels(render(original, artworkOnly: true))
            XCTAssertTrue(editor.availableColorRoles.contains(.primary), design)
            for role in editor.availableColorRoles {
                var changed = original
                switch role {
                case .primary: changed.colors.primary = "#0080FF"
                case .secondary: changed.colors.secondary = "#00FF00"
                case .accent: changed.colors.accent = "#FF8000"
                }
                let after = try pixels(render(changed, artworkOnly: true))
                let changedPixels = stride(from: 0, to: before.count, by: 4).filter { i in
                    (0..<3).contains { abs(Int(before[i + $0]) - Int(after[i + $0])) > 3 }
                }.count
                XCTAssertGreaterThan(changedPixels, 50, "Inactive control: \(design) / \(role)")
            }
        }
    }

    func testRendersAll37() throws {
        for design in CardFaceCatalog.designs {
            let value = CardFace(design: design, colors: CardFaceCatalog.presets[6].colors)
            let renderer = ImageRenderer(content: CardFaceArt(face: value, width: 350))
            renderer.scale = 2; renderer.isOpaque = true
            let data = try pixels(XCTUnwrap(renderer.cgImage))
            XCTAssertTrue(stride(from: 3, to: data.count, by: 4).allSatisfy { data[$0] == 255 }, design)
            let colors = Set(stride(from: 0, to: data.count, by: 4).map {
                UInt32(data[$0]) << 16 | UInt32(data[$0 + 1]) << 8 | UInt32(data[$0 + 2])
            })
            XCTAssertGreaterThan(colors.count, 1, design)
        }
    }

    func testReleaseMapsReplica() {
        for replica in [CardDesign.hsbcLivePlus, .hdfcPixelPlay, .hdfcMillennia] {
            let resolved = BankCardFaces.resolvedFace(for: replica)
            XCTAssertTrue(CardFaceCatalog.designs.contains(resolved.design))
            XCTAssertEqual(resolved, BankCardFaces.resolvedFace(for: replica))
            XCTAssertEqual(resolved, CardFaceCatalog.fallback(for: replica.rawValue))
        }
    }

    func testCardy23PreservesOuterSquareStrokes() throws {
        let value = CardFace(design: "cardy.23", colors: colors)
        let overrides = Dictionary(uniqueKeysWithValues: CardFaceCatalog.paintLayers(for: value.design).map { layer in
            (layer.asset, Dictionary(uniqueKeysWithValues: layer.roles.keys.map { ($0, $0) }))
        })
        let renderer = ImageRenderer(content: CardFaceArt(face: value, width: 350, sourcePaintOverrides: overrides).artwork)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage), data = try pixels(image)
        let i = (Int(Double(image.height) * 0.65) * image.width + Int(Double(image.width) * 0.54)) * 4
        XCTAssertGreaterThan(data[i + 1], 240, "The source's outer white stroke extends beyond the path bounds")
        XCTAssertGreaterThan(data[i + 2], 240)
    }

    func testCardy24ChevronSurvivesGraphite() throws {
        let image = try render(CardFace(design: "cardy.24", colors: CardFaceCatalog.presets[0].colors))
        let data = try pixels(image)
        var rowRanges: [Double] = []
        for row in 0..<8 {
            let y = Int((0.04 + Double(row) * 0.05) * Double(image.height))
            var values: [Double] = []
            for column in 0..<30 {
                let x = Int((0.03 + Double(column) * 0.031) * Double(image.width))
                var total = 0
                for dy in 0..<6 { for dx in 0..<6 {
                    let i = ((y + dy) * image.width + x + dx) * 4
                    total += Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])
                } }
                values.append(Double(total) / 108)
            }
            values.sort(); rowRanges.append(values[26] - values[3])
        }
        rowRanges.sort()
        XCTAssertGreaterThan(rowRanges[4], 8, "Chevron light/dark separation disappeared behind the edge band")
    }

    func testChromeGlassSoftensFoldUnderOverlay() throws {
        let image = try render(CardFace(design: "cardy.8", colors: colors), artworkOnly: true)
        let data = try pixels(image)
        func sharpestEdge(_ y: Double) -> Int {
            let row = Int(Double(image.height) * y)
            return (Int(Double(image.width) * 0.04)..<Int(Double(image.width) * 0.25)).map { x in
                let i = (row * image.width + x) * 4
                return (0..<3).map { abs(Int(data[i + $0]) - Int(data[i + 4 + $0])) }.max()!
            }.max()!
        }
        XCTAssertLessThan(Double(sharpestEdge(0.86)), Double(sharpestEdge(0.65)) * 0.4,
                          "Figma's bottom glass must blur the fold behind its tint")
    }

    private let colors = CardColors(primary: "#770A3C", secondary: "#B91532", accent: "#3763A4")
    private var minimumAverage = Double.infinity, minimumLocal = Double.infinity

    func testArtworkKeepsEveryUnmaskedPartUnderText() throws {
        for design in CardFaceCatalog.designs {
            let c = card(design)
            let reference = ZStack {
                Color(cardHex: c.colors.primary)
                ForEach(CardFaceCatalog.paintLayers(for: design), id: \.asset) { layer in
                    CardyParts(layer: layer, colors: c.colors).blendMode(layer.swiftUIBlendMode).opacity(layer.opacity)
                }
            }.frame(width: 343, height: 343 / 1.586).drawingGroup(opaque: true, colorMode: .nonLinear)
            let actual = ImageRenderer(content: CardFaceArt(face: c, width: 343).artwork)
            let expected = ImageRenderer(content: reference)
            actual.scale = 2; expected.scale = 2
            // Quantize both independent renders once in pixels(), avoiding order-dependent 8-bit raster rounding.
            actual.colorMode = .extendedLinear; expected.colorMode = .extendedLinear
            let a = try pixels(XCTUnwrap(actual.cgImage)), b = try pixels(XCTUnwrap(expected.cgImage))
            XCTAssertEqual(a.count, b.count)
            let differences = zip(a, b).map { abs(Int($0) - Int($1)) }
            XCTAssertEqual(differences.max(), 0,
                           "Artwork was cut out around text: \(design); \(differences.filter { $0 != 0 }.count) differing bytes")
        }
    }

    private func card(_ design: String) -> CardFace {
        CardFace(design: design, colors: colors)
    }

    private func face(_ design: String?, bank: String = "Sample Bank", scheme: ColorScheme = .light,
                      contrast: ColorSchemeContrast = .standard, reduceTransparency: Bool = false) throws -> CGImage {
        var payload = IDPayload(values: ["bank": bank, "cardNumber": "4111111111111111"])
        payload[.cardDesign] = design
        let renderer = ImageRenderer(content: CardFaceView(kind: .debitCard, payload: payload)
            .frame(width: 343, height: 343 / 1.586)
            .environment(\.colorScheme, scheme)
            .environment(\._colorSchemeContrast, contrast)
            .environment(\._accessibilityReduceTransparency, reduceTransparency))
        renderer.scale = 2
        return try XCTUnwrap(renderer.cgImage)
    }

    func testEveryDesignTextReadableOnCompleteFace() throws {
        let evidence = URL(fileURLWithPath: "/tmp/identite-chunk-b/faces", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for preset in CardFaceCatalog.presets.suffix(3) {
            for design in CardFaceCatalog.designs {
                var c = card(design); c.colors = preset.colors
                let art = try render(c), backdrop = try pixels(art)
                for scheme in [ColorScheme.light, .dark] { for contrast in [ColorSchemeContrast.standard, .increased] {
                  for reduceTransparency in [false, true] {
                    let image = try face(CardDesign.face(c).rawValue, scheme: scheme, contrast: contrast,
                                         reduceTransparency: reduceTransparency)
                    if preset.id == "garnet" && contrast == .standard && !reduceTransparency {
                        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                            .write(to: evidence.appendingPathComponent(design + (scheme == .dark ? "-dark.png" : "-light.png")))
                    }
                    if preset.id == "garnet" && design == "cardy.12" {
                        let matrix = evidence.deletingLastPathComponent().appendingPathComponent("environment-matrix", isDirectory: true)
                        try FileManager.default.createDirectory(at: matrix, withIntermediateDirectories: true)
                        let name = "\(scheme == .dark ? "dark" : "light")-\(contrast == .increased ? "increased" : "standard")-\(reduceTransparency ? "opaque" : "transparent").png"
                        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                            .write(to: matrix.appendingPathComponent(name))
                    }
                    let data = try pixels(image)
                    try assertForeground(image, card: c, backdrop: art)
                    // The center must contain the requested art, not the temporary gradient fallback.
                    let center = (image.height / 2 * image.width + image.width / 2) * 4
                    XCTAssertLessThan(abs(Int(data[center]) - Int(backdrop[center])), 30, "Missing art: \(design)")
                    for zone in CardTextZone.allCases {
                        // Remove foreground glyph/logo pixels when measuring the actual face background.
                        let box = zone.bounds(for: c.design)
                        var sum = SIMD3<Double>.zero, count = 0
                        let dim = 1.0 // Fixed artwork stays fixed in every system appearance.
                        for y in Int(ceil(box.y * Double(image.height)))..<Int((box.y + box.height) * Double(image.height)) {
                            for x in Int(ceil(box.x * Double(image.width)))..<Int((box.x + box.width) * Double(image.width)) {
                                let i = (y * image.width + x) * 4
                                if (0..<3).allSatisfy({ abs(Double(data[i + $0]) - Double(backdrop[i + $0]) * dim) < 4 }) {
                                    sum += SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2])) / 255
                                    count += 1
                                }
                            }
                        }
                        XCTAssertGreaterThan(count, 100, "Face lost its modeled background: \(design) / \(zone)")
                        if count > 0 { XCTAssertGreaterThanOrEqual(ratio(rgb(c.ink(for: zone)) * dim, sum / Double(count)), 4.5) }
                    }
                } } }
            }
        }
    }

    private func assertForeground(_ image: CGImage, card c: CardFace, backdrop: CGImage,
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try pixels(image), background = try pixels(backdrop)
        for zone in [CardTextZone.bank, .last4] {
            let box = zone.bounds(for: c.design), ink = rgb(c.ink(for: zone)) * 255
            var solidGlyphPixels = 0
            for y in Int(ceil(box.y * Double(image.height)))..<Int((box.y + box.height) * Double(image.height)) {
                for x in Int(ceil(box.x * Double(image.width)))..<Int((box.x + box.width) * Double(image.width)) {
                    let i = (y * image.width + x) * 4
                    if (0..<3).contains(where: { abs(Int(data[i + $0]) - Int(background[i + $0])) > 32 }),
                       (0..<3).allSatisfy({ abs(Double(data[i + $0]) - ink[$0]) <= 3 }) { solidGlyphPixels += 1 }
                }
            }
            XCTAssertGreaterThan(solidGlyphPixels, 80, "Missing text or wrong foreground ink: \(zone)", file: file, line: line)
        }
        // Compare the actual Visa pixels against the original asset, independently of NetworkMark.
        let box = CardTextZone.network.bounds(for: c.design), width = 343.0, height = width / 1.586
        let logo = Image(c.ink(for: .network) == "#000000" ? "visa-blue" : "visa-white", bundle: CardyParts.bundle)
            .renderingMode(.original).resizable().scaledToFit()
            .frame(width: width * 0.15, height: width * 0.06)
            .frame(width: width * box.width, height: height * box.height, alignment: .trailing)
            .offset(x: box.x * width - width * 0.15 * 27 / 2000, y: box.y * height)
        let reference = ImageRenderer(content: ZStack(alignment: .topLeading) {
            CardFaceArt(face: c, width: width)
            logo
        }.frame(width: width, height: height))
        reference.scale = 2
        let expected = try pixels(XCTUnwrap(reference.cgImage))
        var logoPixels = 0, matching = 0
        let logoInk = rgb(c.ink(for: .network) == "#000000" ? "#1434CB" : "#FFFFFF") * 255
        for y in Int(box.y * Double(image.height))..<Int((box.y + box.height) * Double(image.height)) {
            for x in Int(box.x * Double(image.width))..<Int((box.x + box.width) * Double(image.width)) {
                let i = (y * image.width + x) * 4
                if (0..<3).allSatisfy({ abs(Double(expected[i + $0]) - logoInk[$0]) <= 1 }) {
                    logoPixels += 1
                    if (0..<3).allSatisfy({ abs(Int(expected[i + $0]) - Int(data[i + $0])) <= 3 }) { matching += 1 }
                }
            }
        }
        XCTAssertGreaterThan(logoPixels, 100, file: file, line: line)
        XCTAssertGreaterThan(Double(matching) / Double(max(1, logoPixels)), 0.98, "Missing or incorrect network artwork", file: file, line: line)
    }

    func testSplitFaceRendersDifferentBankAndNetworkInks() throws {
        let c = CardFace(design: "cardy.12", colors: CardColors(primary: "#FFFFFF", secondary: "#000000", accent: "#3763A4"))
        XCTAssertNotEqual(c.ink(for: .bank), c.ink(for: .network))
        for scheme in [ColorScheme.light, .dark] { for contrast in [ColorSchemeContrast.standard, .increased] {
            for reduceTransparency in [false, true] {
                try assertForeground(face(CardDesign.face(c).rawValue, scheme: scheme, contrast: contrast,
                                          reduceTransparency: reduceTransparency), card: c, backdrop: render(c))
            }
        } }
    }


    func testLegacyAndCorruptValuesRenderDeterministically() throws {
        for value: String? in ["generic.ocean", nil, "mix1:{", "mix9:{}"] {
            XCTAssertTrue(try pixels(face(value)) == pixels(face(value)), "Legacy face changed between renders")
        }
        XCTAssertTrue(try pixels(face(nil)) == pixels(face(CardDesign.face(CardFaceCatalog.fallback(for: "Sample Bank")).rawValue)))
    }

    func testLongAndEmptyBankNamesStayInsideModelBounds() throws {
        for design in CardFaceCatalog.designs {
            let c = card(design)
            let raw = CardDesign.face(c).rawValue
            let empty = try face(raw, bank: ""), reference = try pixels(empty)
            let named = try pixels(face(raw, bank: "Industrial and Commercial Bank of China"))
            let box = CardTextZone.bank.bounds(for: design)
            var changed = 0, escaped = 0
            for y in 0..<empty.height { for x in 0..<empty.width {
                let i = (y * empty.width + x) * 4
                if (0..<3).contains(where: { abs(Int(named[i + $0]) - Int(reference[i + $0])) > 8 }) {
                    changed += 1
                    if Double(x) < box.x * Double(empty.width) - 1 || Double(x) > (box.x + box.width) * Double(empty.width) + 1
                        || Double(y) < box.y * Double(empty.height) - 1 || Double(y) > (box.y + box.height) * Double(empty.height) + 1 { escaped += 1 }
                }
            }}
            XCTAssertGreaterThan(changed, 100)
            XCTAssertEqual(escaped, 0, "Bank name escaped the single-line model box: \(design)")
        }
    }

    func testBankAccessibilityIncludesUntruncatedName() {
        let bank = "Industrial and Commercial Bank of China"
        let label = CardFaceView(kind: .debitCard,
            payload: IDPayload(values: ["bank": bank, "cardNumber": "4111111111111111"])).spokenLabel
        XCTAssertTrue(label.contains(bank), "The full bank name must remain accessible when the face truncates it")
        XCTAssertFalse(label.contains("4111111111111111"), "The accessible card label must keep the number masked")
    }

    func testFaceIncludesModelBand() throws {
        let c = try XCTUnwrap(CardFaceCatalog.designs.map { CardFace(design: $0,
            colors: CardColors(primary: "#71F1F9", secondary: "#6A2A64", accent: "#D6331F")) }
            .first { CardFaceCatalog.legibility(for: $0)[.bank].bandOpacity > 0 })
        let art = try render(c), a = try pixels(art), actual = try pixels(face(CardDesign.face(c).rawValue, bank: ""))
        let box = CardTextZone.bank.bounds
        let offset = (Int((box.y + box.height / 2) * Double(art.height)) * art.width + Int(0.5 * Double(art.width))) * 4
        XCTAssertTrue(CardFaceCatalog.legibility(for: c)[.bank].bandOpacity > 0)
        XCTAssertTrue((0..<3).allSatisfy { abs(Int(a[offset + $0]) - Int(actual[offset + $0])) <= 1 }, "Face omitted or altered the soft band")
    }

    func testDarkDimmingPreservesNearThresholdTextContrast() throws {
        let c = CardFace(design: "cardy.12",
                                colors: CardColors(primary: "#777777", secondary: "#777777", accent: "#777777"))
        for scheme in [ColorScheme.light, .dark] {
            let image = try face(CardDesign.face(c).rawValue, bank: "", scheme: scheme)
            XCTAssertGreaterThanOrEqual(ratio(rgb(c.ink(for: .bank)), try mean(image, zone: .bank)), 4.5)
        }
    }

    func testReplicaFallsBackInPublic() throws {
        for value in ["hsbcLivePlus", "hdfcPixelPlay", "hdfcMillennia"] {
            XCTAssertEqual(BankCardFaces.resolvedFace(for: try XCTUnwrap(CardDesign(rawValue: value))),
                           CardFaceCatalog.fallback(for: value))
            let actual = try pixels(face(value, bank: "HSBC"))
            let expected = try pixels(face(CardDesign.face(CardFaceCatalog.fallback(for: value)).rawValue, bank: "HSBC"))
            let differences = zip(actual, expected).map { abs(Int($0) - Int($1)) }
            // Identical faces can exhibit the documented 1/255 raster drift.
            XCTAssertLessThanOrEqual(differences.max() ?? 0, 1, value)
        }
    }

    private func render(_ card: CardFace, width: CGFloat = 343, scale: CGFloat = 2, artworkOnly: Bool = false) throws -> CGImage {
        if artworkOnly {
            let renderer = ImageRenderer(content: CardFaceArt(face: card, width: width).artwork)
            renderer.scale = scale
            return try XCTUnwrap(renderer.cgImage)
        }
        let renderer = ImageRenderer(content: CardFaceArt(face: card, width: width))
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage)
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { data in
            let context = try XCTUnwrap(CGContext(data: data.baseAddress, width: image.width, height: image.height,
                                                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private func mean(_ image: CGImage, zone: CardTextZone, design: String = "full") throws -> SIMD3<Double> {
        let data = try pixels(image), box = zone.bounds(for: design)
        var sum = SIMD3<Double>.zero, count = 0.0
        for y in Int(ceil(box.y * Double(image.height)))..<Int(ceil((box.y + box.height) * Double(image.height))) {
            for x in Int(ceil(box.x * Double(image.width)))..<Int(ceil((box.x + box.width) * Double(image.width))) {
                let i = (y * image.width + x) * 4
                sum += SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2])); count += 1
            }
        }
        return sum / (count * 255)
    }

    private func rgb(_ hex: String) -> SIMD3<Double> {
        let n = UInt32(hex.dropFirst(), radix: 16)!
        return SIMD3(Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255)) / 255
    }

    private func lab(_ rgb: SIMD3<Double>) -> SIMD3<Double> {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(rgb.x), g = linear(rgb.y), b = linear(rgb.z)
        func f(_ v: Double) -> Double { v > 216.0 / 24389 ? cbrt(v) : (24389.0 / 27 * v + 16) / 116 }
        let x = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047)
        let y = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        let z = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
        return SIMD3(116 * y - 16, 500 * (x - y), 200 * (y - z))
    }

    private func delta(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = lab(a) - lab(b)
        return sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    }

    func testEveryDesignHasArtworkAndPredictedTextZones() throws {
        let evidence = URL(fileURLWithPath: "/tmp/identite-chunk-a/renders", isDirectory: true)
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for design in CardFaceCatalog.designs {
            let c = card(design), image = try render(c), bytes = try pixels(image)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                .write(to: evidence.appendingPathComponent(design + ".png"))
            let values = stride(from: 0, to: bytes.count, by: 4).map { Int(bytes[$0]) + Int(bytes[$0 + 1]) + Int(bytes[$0 + 2]) }
            XCTAssertGreaterThan((values.max() ?? 0) - (values.min() ?? 0), 8, "Flat artwork: \(design)")
            for zone in CardTextZone.allCases {
                let difference = delta(try mean(image, zone: zone, design: c.design), rgb(CardFaceCatalog.averageColor(for: c, zone: zone)))
                XCTAssertLessThan(difference, 12, "Ink model drift: \(design) / \(zone), deltaE \(difference)")
            }
        }
    }

    func testRenderBudget() throws {
        for design in CardFaceCatalog.designs {
            let c = card(design)
            _ = try render(c)
            let start = ContinuousClock.now
            for _ in 0..<10 { _ = try pixels(render(c)) }
            let elapsed = start.duration(to: .now)
            let ms = Double(elapsed.components.seconds) * 100 + Double(elapsed.components.attoseconds) / 1e16
            print(String(format: "RENDER %@ %.3f ms (10 fresh renders with pixel readback, warm assets)", design, ms))
            XCTAssertLessThan(ms, 16, "Render budget exceeded: \(design)")
        }
    }






    private struct Generator: RandomNumberGenerator {
        var state: UInt64 = 20261023
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
        mutating func colors() -> CardColors {
            func hex(_ value: UInt64) -> String { String(format: "#%06X", UInt32(truncatingIfNeeded: value >> 32) & 0xFFFFFF) }
            return CardColors(primary: hex(next()), secondary: hex(next()), accent: hex(next()))
        }
    }

    private func visibleArtwork(_ c: CardFace, width: CGFloat = 343) throws -> Double {
        let image = try render(c, width: width, artworkOnly: true), data = try pixels(image)
        let primary = rgb(c.colors.primary)
        let visible = stride(from: 0, to: data.count, by: 4).filter { i in
            delta(SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2])) / 255, primary) >= 3
        }.count
        return Double(visible) / Double(image.width * image.height)
    }

    // Independent pixel measurements: the mean and the 10th percentile of contrast ratios.
    private func renderedContrast(_ image: CGImage, c: CardFace, zone: CardTextZone) throws -> (average: Double, local: Double) {
        let data = try pixels(image), box = zone.bounds(for: c.design), ink = rgb(c.ink(for: zone))
        var sum = SIMD3<Double>.zero, ratios: [Double] = []
        for y in Int(ceil(box.y * Double(image.height)))..<Int(ceil((box.y + box.height) * Double(image.height))) {
            for x in Int(ceil(box.x * Double(image.width)))..<Int(ceil((box.x + box.width) * Double(image.width))) {
                let i = (y * image.width + x) * 4
                let value = SIMD3(Double(data[i]), Double(data[i + 1]), Double(data[i + 2])) / 255
                sum += value; ratios.append(ratio(ink, value))
            }
        }
        ratios.sort()
        return (ratio(ink, sum / Double(ratios.count)), ratios[Int(Double(ratios.count - 1) * 0.1)])
    }

    private func assertReadable(_ c: CardFace, label: String, report: Bool = false) throws {
        for width: CGFloat in [343, 150, 100] {
            let image = try render(c, width: width)
            for zone in CardTextZone.allCases {
                let measured = try renderedContrast(image, c: c, zone: zone)
                minimumAverage = min(minimumAverage, measured.average); minimumLocal = min(minimumLocal, measured.local)
                if report {
                    print(String(format: "CONTRAST %@ width=%.0f scale=2 %@ average=%.6f local=%.6f", label, width, zone.rawValue, measured.average, measured.local))
                }
                XCTAssertGreaterThanOrEqual(measured.average, 4.5, "Average: \(label) / \(width) / \(zone)")
                XCTAssertGreaterThanOrEqual(measured.local, 4.5, "Local: \(label) / \(width) / \(zone)")
            }
        }
    }

    func testReviewContrastReproAtSupportedSizes() throws {
        let c = CardFace(design: "cardy.4",
                                colors: CardColors(primary: "#71F1F9", secondary: "#6A2A64", accent: "#D6331F"))
        for zone in CardTextZone.allCases {
            let treatment = CardFaceCatalog.legibility(for: c)[zone]
            print(String(format: "BAND gradient-repro %@ opacity=%.3f predictedAverage=%.6f predictedMinimum=%.6f", zone.rawValue,
                         treatment.bandOpacity, treatment.averageContrast, treatment.minimumContrast))
        }
        try assertReadable(c, label: "gradient-repro", report: true)
    }

    func testExtremeCustomArtworkStillHasBoundedBands() throws {
        for palette in [CardColors(primary: "#FFFFFF", secondary: "#000000", accent: "#FFFFFF"),
                        CardColors(primary: "#000000", secondary: "#FFFFFF", accent: "#000000")] {
            for design in CardFaceCatalog.designs {
                let c = CardFace(design: design, colors: palette)
                XCTAssertTrue(CardFaceCatalog.legibility(for: c).bands.allSatisfy { $0.opacity <= 1 })
                try assertReadable(c, label: design)
            }
        }
    }


    func testSplitTextBoxesDoNotCrossPanel() throws {
        for design in ["cardy.1", "cardy.4", "cardy.16"] {
            try assertReadable(CardFace(design: design, colors: CardColors(primary: "#FFFFFF", secondary: "#FFFFFF", accent: "#FFFFFF")), label: design)
        }
    }

    func testCustomColoursAreReadableRendered() throws {
        var generator = Generator()
        var bandCards = 0, bandBoxes = 0
        for index in 0..<300 {
            let palette = generator.colors()
            // Keep arbitrary valid parts instead of asking random() to screen custom edits.
            let design = CardFaceCatalog.designs[index % CardFaceCatalog.designs.count]
            var c = card(design)
            c.colors = palette
            let count = CardTextZone.allCases.filter { CardFaceCatalog.legibility(for: c)[$0].bandOpacity > 0 }.count
            bandCards += count > 0 ? 1 : 0; bandBoxes += count
            try assertReadable(c, label: "custom-\(index)")
        }
        print("BANDS custom cards=300 triggered=\(bandCards) boxes=900 triggeredBoxes=\(bandBoxes)")
        print(String(format: "SWEEP custom minimumAverage=%.6f minimumLocal=%.6f", minimumAverage, minimumLocal))
    }

    func testEqualAndNearEqualColoursHaveVisibleArtwork() throws {
        let palettes = [CardColors(primary: "#777777", secondary: "#777777", accent: "#777777"),
                        CardColors(primary: "#777777", secondary: "#787778", accent: "#777878"),
                        CardColors(primary: "#FFFFFF", secondary: "#FFFFFF", accent: "#FFFFFF"),
                        CardColors(primary: "#000000", secondary: "#000000", accent: "#000000")]
        for (paletteIndex, palette) in palettes.enumerated() {
            let repro = CardFace(design: "cardy.12", colors: palette)
            try assertReadable(repro, label: "maze-\(paletteIndex)", report: paletteIndex == 0)
            for width: CGFloat in [343, 150, 100] {
                let fraction = try visibleArtwork(repro, width: width)
                print(String(format: "VISIBILITY maze-%d width=%.0f fraction=%.6f", paletteIndex, width, fraction))
                XCTAssertGreaterThan(fraction, 0.06)

            }
            var generator = Generator()
            for draw in 0..<60 {
                let c = CardFaceCatalog.random(colors: palette, using: &generator)
                XCTAssertTrue(c.colors == palette, "Shuffle changed the saved colours")
                for width: CGFloat in [343, 150, 100] {
                    XCTAssertGreaterThanOrEqual(try visibleArtwork(c, width: width), 0.04, "Faint random art: \(paletteIndex) / \(draw) / \(width)")
                }
            }
        }
    }

    func testAssetsAreDeduplicatedAndPaintPassesNonempty() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("App/Shared/Cards/Composed/CardyParts.xcassets")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: assets, includingPropertiesForKeys: nil))
        var unique = Set<Data>()
        for case let path as URL in enumerator where path.pathExtension == "png" {
            XCTAssertTrue(unique.insert(try Data(contentsOf: path)).inserted, "Duplicate PNG: \(path.deletingLastPathComponent().lastPathComponent)")
        }
        for name in CardFaceCatalog.assetNames {
                let image = try XCTUnwrap(CardyParts.bundle.image(forResource: name)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let data = try pixels(image)
                XCTAssertTrue(stride(from: 3, to: data.count, by: 4).contains { data[$0] > 0 }, "Empty paint pass: \(name)")
        }
    }

    func testRecolouredMazeAndChevronsRespondToPalette() throws {
        for design in ["cardy.12", "cardy.24"] {
            var c = card(design)
            let before = try pixels(render(c))
            c.colors.secondary = "#E8D9B5"; c.colors.accent = "#2F7D4F"
            let after = try pixels(render(c))
            let changed = zip(before, after).filter { abs(Int($0) - Int($1)) > 16 }.count
            XCTAssertGreaterThan(changed, before.count / 100, "Part ignores palette: \(design)")
        }
    }


    private func ratio(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        func luminance(_ rgb: SIMD3<Double>) -> Double {
            let values = (0..<3).map { rgb[$0] <= 0.04045 ? rgb[$0] / 12.92 : pow((rgb[$0] + 0.055) / 1.055, 2.4) }
            return values[0] * 0.2126 + values[1] * 0.7152 + values[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    func testInkMatchesRenderedCompositionsIncludingGrain() throws {
        struct Generator: RandomNumberGenerator {
            var state: UInt64 = 2471
            mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
        }
        var generator = Generator()
        var bandCards = 0, bandBoxes = 0
        for index in 0..<120 {
            let palette: CardColors
            if index < 60 {
                palette = CardFaceCatalog.presets[index % CardFaceCatalog.presets.count].colors
            } else {
                func hex() -> String { String(format: "#%06X", UInt32(truncatingIfNeeded: generator.next() >> 32) & 0xFFFFFF) }
                palette = CardColors(primary: hex(), secondary: hex(), accent: hex())
            }
            let c = CardFaceCatalog.random(colors: palette, using: &generator), image = try render(c)
            for zone in CardTextZone.allCases {
                let actual = try mean(image, zone: zone, design: c.design)
                XCTAssertLessThan(delta(actual, rgb(CardFaceCatalog.averageColor(for: c, zone: zone))), 12,
                                  "Composite prediction: sample \(index), \(c.design), \(zone)")
                XCTAssertGreaterThanOrEqual(ratio(rgb(c.ink(for: zone)), actual), 4.5,
                                            "Rendered contrast: sample \(index), \(c.design), \(zone)")
            }
            let count = CardTextZone.allCases.filter { CardFaceCatalog.legibility(for: c)[$0].bandOpacity > 0 }.count
            bandCards += count > 0 ? 1 : 0; bandBoxes += count
            try assertReadable(c, label: "random-\(index)")
            for width: CGFloat in [343, 150, 100] {
                XCTAssertGreaterThanOrEqual(try visibleArtwork(c, width: width), 0.04, "Faint random art: \(index) / \(width)")
            }
        }
        print("BANDS random cards=120 triggered=\(bandCards) boxes=360 triggeredBoxes=\(bandBoxes)")
        print(String(format: "SWEEP random minimumAverage=%.6f minimumLocal=%.6f", minimumAverage, minimumLocal))
    }

    func testAllAssetsExistAndUntintedImagesAreNeutral() throws {
        for design in CardFaceCatalog.designs { for layer in CardFaceCatalog.paintLayers(for: design) {
            for name in layer.masks.values { XCTAssertNotNil(CardyParts.bundle.image(forResource: name), layer.asset) }
            if let name = layer.neutral {
                let asset = try XCTUnwrap(CardyParts.bundle.image(forResource: name))
                let data = try pixels(XCTUnwrap(asset.cgImage(forProposedRect: nil, context: nil, hints: nil)))
                XCTAssertTrue(stride(from: 0, to: data.count, by: 4).allSatisfy { data[$0] == data[$0 + 1] && data[$0] == data[$0 + 2] }, layer.asset)
            }
        } }
    }


}
