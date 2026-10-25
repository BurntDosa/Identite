import AppKit
import IDCore
import SwiftUI
import XCTest

/// Real wallet faces, fake identifiers only. Run normally with the macOS test suite.
@MainActor final class CardFaceStressTests: XCTestCase {
    private let width = 350.0
    private var height: Double { width / 1.586 }
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private var output: URL { root.appendingPathComponent("docs/design/build-review/fixed") }
    private let linear = (0...255).map { value -> Double in
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private struct Generator: RandomNumberGenerator {
        var state: UInt64 = 2026102401
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
        mutating func hex() -> String { String(format: "#%06X", UInt32(truncatingIfNeeded: next() >> 32) & 0xFFFFFF) }
    }
    private struct Case {
        let id: String, group: String, palette: String
        var face: CardFace
        let network: CardNetwork
    }
    private struct Result: Codable {
        let id: String, sheet: String, preset: String, network: String
        let face: CardFace
        let bandOpacities: [Double], inks: [String]
        let bankContrast: Double, last4Contrast: Double
        let wordmarkContrast: Double?, symbolContrast: Double?
        let noBoxResidual: Double, bandTransferResidual: Double, logoInteriorResidual: Double
    }
    private struct Masks {
        let text: [UInt8], logo: [UInt8], outline: [UInt8]
    }
    private var textMasks: [String: [UInt8]] = [:]
    private var logoMasks: [String: [UInt8]] = [:]

    private func cases() throws -> [Case] {
        var result: [Case] = [], generator = Generator()
        let presets = CardFaceCatalog.presets
        func add(_ group: String, _ palette: String, _ c: CardFace, network: CardNetwork? = nil) {
            result.append(Case(id: String(format: "%04d", result.count + 1), group: group, palette: palette,
                face: c, network: network ?? [.visa, .mastercard, .rupay][result.count % 3]))
        }
        for preset in presets { for design in CardFaceCatalog.designs {
            add("presets-" + preset.id, preset.name, CardFace(design: design, colors: preset.colors, colorway: .preset, presetID: preset.id))
        } }
        let extremes = [CardColors(primary: "#777777", secondary: "#777777", accent: "#777777"),
            CardColors(primary: "#FAFAFA", secondary: "#FAFAFA", accent: "#FAFAFA"),
            CardColors(primary: "#050505", secondary: "#050505", accent: "#050505"),
            CardColors(primary: "#FF0000", secondary: "#00FF00", accent: "#0000FF"),
            CardColors(primary: "#3A3A3A", secondary: "#404040", accent: "#383838"), presets[6].colors]
        for (index, colors) in extremes.enumerated() { for design in CardFaceCatalog.designs {
            add("custom-\(index + 1)", index == 5 ? "Card" : "Custom \(index + 1)",
                CardFace(design: design, colors: colors, colorway: index == 5 ? .card : .custom, cardColors: index == 5 ? colors : nil))
        } }
        for network in [CardNetwork.visa, .mastercard, .rupay] { for design in CardFaceCatalog.designs {
            add("network-" + network.rawValue, "Garnet", CardFace(design: design, colors: presets[6].colors), network: network)
        } }
        for index in 0..<300 {
            let colors = index < 150 ? presets[index % presets.count].colors
                : CardColors(primary: generator.hex(), secondary: generator.hex(), accent: generator.hex())
            add("shuffle", "Random \(index + 1)", CardFaceCatalog.random(colors: colors, using: &generator))
        }
        for (index, accent) in ["#0DB774", "#0EB675"].enumerated() { for design in CardFaceCatalog.designs {
            add("overlapping-roles-\(index + 1)", "Overlapping roles \(index + 1)", CardFace(design: design,
                colors: CardColors(primary: "#F5B635", secondary: "#0DB774", accent: accent)))
        } }
        add("review-repro", "Original Random 288", CardFace(design: "cardy.15",
            colors: CardColors(primary: "#F5B635", secondary: "#0DB774", accent: "#28A774")))
        return try result.map { item in
            var saved = item; saved.face = try roundTrip(item.face)
            return saved
        }
    }

    private enum FixtureError: Error { case invalidDesign }
    private func roundTrip(_ face: CardFace) throws -> CardFace {
        let saved = CardDesign.face(face).rawValue
        guard CardFaceCatalog.designs.contains(face.design), face.isValid, saved.hasPrefix("design1:"),
              case .face(let decoded) = CardDesign(rawValue: saved), decoded == face else {
            throw FixtureError.invalidDesign
        }
        return decoded
    }

    private func render<V: View>(_ content: V) throws -> CGImage {
        let renderer = ImageRenderer(content: content.frame(width: width, height: height).environment(\.colorScheme, .light))
        renderer.scale = 3; renderer.isOpaque = false
        return try XCTUnwrap(renderer.cgImage)
    }
    private func face(_ item: Case) -> some View {
        BankCardFace(design: .face(item.face), kind: .debitCard, bank: "Test Bank",
                     network: item.network, identifier: "•••• 3003", width: width)
    }
    private func originalLogo(_ network: CardNetwork, isLight: Bool = false, outline: Bool = false) -> some View {
        let box = CardTextZone.network.bounds
        let inset = network == .visa ? 27.0 / 2000 : network == .rupay ? 14.0 / 600 : 0
        let name = network == .visa ? (isLight ? "visa-blue" : "visa-white")
            : network == .rupay ? (isLight ? "rupay" : "rupay-white") : "mastercard"
        let aspect = network == .visa ? 1000 / 324.68 : 600.0 / 155
        return ZStack(alignment: .topLeading) {
            Color.clear
            Group {
                if outline && network != .mastercard {
                    Image(network == .visa ? "visa-outline" : "rupay-outline", bundle: CardyParts.bundle)
                        .renderingMode(.template).resizable().foregroundStyle(.white)
                        .frame(width: width * 0.15 * (1 + 2 * inset), height: width * 0.15 / aspect + 2 * width * 0.15 * inset)
                        .frame(width: width * 0.15, height: width * 0.06)
                } else {
                    Image(name, bundle: CardyParts.bundle).renderingMode(.original).resizable().scaledToFit()
                        .frame(width: width * 0.15, height: width * 0.06)
                }
            }
                .frame(width: width * box.width, height: height * box.height, alignment: .trailing)
                .offset(x: box.x * width - width * 0.15 * inset, y: box.y * height)
        }
    }

    private func masks(_ item: Case) throws -> Masks {
        let design = item.face.design
        if textMasks[design] == nil {
            // Independent typography reference: never infer glyph coverage from the face being checked.
            textMasks[design] = try pixels(render(ZStack(alignment: .topLeading) {
                Color.clear
                ForEach([CardTextZone.bank, .last4], id: \.self) { [self] zone in
                    let box = zone.bounds(for: design)
                    Text(zone == .bank ? "Test Bank" : "•••• 3003")
                        .font(.system(size: width * (zone == .bank ? 0.0625 : 0.046875), weight: zone == .bank ? .semibold : .medium))
                        .monospacedDigit().tracking(zone == .bank ? -width * 0.0015 : 0)
                        .foregroundStyle(.white).lineLimit(1).truncationMode(.tail)
                        .frame(width: box.width * width, height: box.height * height, alignment: .leading)
                        .clipped().offset(x: box.x * width, y: box.y * height)
                }
            }))
        }
        let isLight = item.face.ink(for: .network) == "#000000"
        let key = item.network.rawValue + (isLight ? "-light" : "-dark"), outlineKey = item.network.rawValue + "-outline"
        if logoMasks[key] == nil { logoMasks[key] = try pixels(render(originalLogo(item.network, isLight: isLight))) }
        if logoMasks[outlineKey] == nil { logoMasks[outlineKey] = try pixels(render(originalLogo(item.network, outline: true))) }
        return Masks(text: textMasks[design]!, logo: logoMasks[key]!, outline: logoMasks[outlineKey]!)
    }
    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try data.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }
    private func luminance(_ data: [UInt8], _ i: Int) -> Double {
        0.2126 * linear[Int(data[i])] + 0.7152 * linear[Int(data[i + 1])] + 0.0722 * linear[Int(data[i + 2])]
    }
    private func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
    private func rgb(_ hex: String) -> SIMD3<Double> {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return SIMD3(Double(value >> 16 & 255), Double(value >> 8 & 255), Double(value & 255))
    }

    private func check(_ item: Case, image: CGImage, art: CGImage, plain: CGImage, sheet: String) throws -> Result {
        let c = item.face, plan = CardFaceCatalog.legibility(for: c), masks = try masks(item)
        let foreground = try pixels(image), background = try pixels(art), untreated = try pixels(plain)
        var ratios: [Double] = [], symbolRatio: Double?, wordmarkRatio: Double?
        for zone in CardTextZone.allCases {
            let box = zone.bounds(for: c.design)
            var minimum = Double.infinity, symbols = Double.infinity, count = 0, symbolCount = 0
            for y in Int(box.y * Double(image.height))..<Int((box.y + box.height) * Double(image.height)) {
                for x in Int(box.x * Double(image.width))..<Int((box.x + box.width) * Double(image.width)) {
                    let i = (y * image.width + x) * 4
                    if zone == .network {
                        if item.network == .mastercard { continue }
                        // Source alpha alone selects every solid outer-contour pixel, regardless of actual ink.
                        guard masks.outline[i + 3] == 255, masks.logo[i + 3] == 0 else { continue }
                    } else {
                        guard masks.text[i + 3] == 255 else { continue }
                    }
                    let measured = ratio(luminance(foreground, i), luminance(background, i))
                    if zone == .network && item.network == .rupay && Double(x) / Double(image.width) > 0.914 {
                        symbols = min(symbols, measured); symbolCount += 1
                    } else { minimum = min(minimum, measured); count += 1 }
                }
            }
            if zone == .network && item.network == .mastercard { continue }
            XCTAssertGreaterThan(count, zone == .network ? 20 : 80, "\(item.id): missing independent \(zone) coverage")
            XCTAssertGreaterThanOrEqual(minimum, 4.5, "\(item.id): \(zone) \(c.design) / \(c.design)")
            if zone == .network {
                wordmarkRatio = minimum
                if item.network == .rupay {
                    XCTAssertGreaterThan(symbolCount, 10, "\(item.id): missing independent RuPay triangle coverage")
                    XCTAssertGreaterThanOrEqual(symbols, 3, "\(item.id): RuPay symbol silhouette")
                    symbolRatio = symbols
                }
            } else { ratios.append(minimum) }
        }

        // RuPay's source letters have alpha 239/255; compare source-over colour, never skip translucent interiors.
        var interiorResidual = 0.0, interiorCounts = [0, 0, 0]
        for i in stride(from: 0, to: foreground.count, by: 4) where masks.logo[i + 3] > 0 {
            let group: Int
            if item.network == .rupay {
                group = masks.logo[i] > masks.logo[i + 1] && masks.logo[i + 1] > masks.logo[i + 2] ? 1
                    : masks.logo[i + 1] > masks.logo[i] && masks.logo[i + 1] > masks.logo[i + 2] ? 2 : 0
            } else if item.network == .mastercard {
                group = (i / 4) % image.width < Int(0.865 * Double(image.width)) ? 0 : 1
            } else { group = 0 }
            if masks.logo[i + 3] >= 230 { interiorCounts[group] += 1 }
            let logoAlpha = Double(masks.logo[i + 3]) / 255
            let outlineAlpha = item.network == .mastercard ? 0 : Double(masks.outline[i + 3]) / 255
            let ink = plan[.network].ink == "#FFFFFF" ? 255.0 : 0.0
            for channel in 0..<3 {
                let under = ink * outlineAlpha + Double(background[i + channel]) * (1 - outlineAlpha)
                let expected = Double(masks.logo[i + channel]) + under * (1 - logoAlpha)
                interiorResidual = max(interiorResidual, abs(Double(foreground[i + channel]) - expected))
            }
        }
        for group in 0..<(item.network == .rupay ? 3 : item.network == .mastercard ? 2 : 1) {
            XCTAssertGreaterThan(interiorCounts[group], 20, "\(item.id): missing source logo region \(group)")
        }
        XCTAssertLessThanOrEqual(interiorResidual, 3, "\(item.id): original \(item.network.rawValue) interiors changed")

        var residual = 0.0, transferResidual = 0.0
        for y in 0..<image.height {
            let yy = (Double(y) + 0.5) / (height * 3)
            let band = plan.bands.first { $0.alpha(atY: yy) > 0 }
            let alpha = band?.alpha(atY: yy) ?? 0
            let tone = band.map { rgb($0.color) } ?? .zero
            for x in 0..<image.width {
                let xx = (Double(x) + 0.5) / Double(image.width), i = (y * image.width + x) * 4
                // No rectangle exemptions: even unused space between letters must equal artwork + bands.
                if masks.text[i + 3] == 0 && masks.logo[i + 3] == 0 && masks.outline[i + 3] == 0 {
                    for channel in 0..<4 {
                        residual = max(residual, abs(Double(foreground[i + channel]) - Double(background[i + channel])))
                    }
                }
                // Only the transfer model excludes raster boundaries; the complete-face check above does not.
                if x < 3 || y < 3 || x >= image.width - 3 || y >= image.height - 3 { continue }
                if let band, abs(xx - band.width) < 2 / Double(image.width) { continue }
                var expected = SIMD3(Double(untreated[i]), Double(untreated[i + 1]), Double(untreated[i + 2]))
                if let band, xx < band.width { expected = expected * (1 - alpha) + tone * alpha }
                for channel in 0..<3 {
                    transferResidual = max(transferResidual, abs(Double(background[i + channel]) - expected[channel]))
                }
            }
        }
        XCTAssertLessThanOrEqual(residual, 3, "\(item.id): unexpected face pixels outside independent glyph/logo masks")
        XCTAssertLessThanOrEqual(transferResidual, 3, "\(item.id): band has an interior edge or model/render transfer mismatch")
        return Result(id: item.id, sheet: sheet, preset: item.palette, network: item.network.rawValue, face: c,
            bandOpacities: plan.bands.map(\.opacity), inks: CardTextZone.allCases.map { plan[$0].ink },
            bankContrast: ratios[0], last4Contrast: ratios[1], wordmarkContrast: wordmarkRatio,
            symbolContrast: symbolRatio, noBoxResidual: residual, bandTransferResidual: transferResidual,
            logoInteriorResidual: interiorResidual)
    }

    private func save(_ image: CGImage, _ url: URL) throws {
        try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])).write(to: url)
    }

    private func mutation(_ network: CardNetwork, failure: String,
                          change: (inout [UInt8], [UInt8], Masks) throws -> Void) throws {
        let c = try roundTrip(CardFace(design: "cardy.12",
            colors: CardColors(primary: "#FFFFFF", secondary: "#FFFFFF", accent: "#FFFFFF")))
        let item = Case(id: "mutation", group: "mutation", palette: "White", face: c, network: network)
        let original = try render(face(item)), art = try render(CardFaceArt(face: c, width: width))
        let plain = try render(CardFaceArt(face: c, width: width).artwork)
        _ = try check(item, image: original, art: art, plain: plain, sheet: "mutation-control")
        var data = try pixels(original)
        try change(&data, pixels(art), masks(item))
        let changed = try XCTUnwrap(CGImage(width: original.width, height: original.height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: original.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: CGDataProvider(data: Data(data) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let options = XCTExpectedFailure.Options()
        options.issueMatcher = { $0.compactDescription.contains(failure) }
        try XCTExpectFailure("The harness must reject this pixel mutation", options: options) {
            _ = try check(item, image: changed, art: art, plain: plain, sheet: "mutation")
        }
    }

    func testRejectsFadedBankGlyphs() throws {
        try mutation(.visa, failure: "mutation: bank") { data, background, masks in
            var retained = 0, faded = 0
            for i in stride(from: 0, to: data.count / 2, by: 4) where masks.text[i + 3] > 0 {
                if masks.text[i + 3] == 255 && retained < 81 { retained += 1; continue }
                for channel in 0..<3 {
                    data[i + channel] = UInt8((Double(background[i + channel]) * 0.95 + Double(data[i + channel]) * 0.05).rounded())
                }
                if masks.text[i + 3] == 255 { faded += 1 }
            }
            XCTAssertGreaterThan(faded, 1000)
            print("MUTATION faded bank: \(faded) solid pixels, \(retained) retained")
        }
    }

    func testRejectsBlackTileBehindVisa() throws {
        try mutation(.visa, failure: "unexpected face pixels outside independent glyph/logo masks") { data, _, masks in
            let box = CardTextZone.network.bounds
            let tile = try pixels(render(ZStack(alignment: .topLeading) {
                Color.clear
                RoundedRectangle(cornerRadius: 4).fill(.black)
                    .frame(width: box.width * width, height: box.height * height)
                    .offset(x: box.x * width, y: box.y * height)
            }))
            var changed = 0
            for i in stride(from: 0, to: data.count, by: 4)
                where tile[i + 3] > 0 && masks.logo[i + 3] == 0 && masks.outline[i + 3] == 0 {
                for channel in 0..<3 { data[i + channel] = UInt8(Double(data[i + channel]) * (1 - Double(tile[i + 3]) / 255)) }
                changed += 1
            }
            XCTAssertGreaterThan(changed, 1000)
            print("MUTATION Visa tile: \(changed) pixels inside the network rectangle")
        }
    }

    func testRejectsRuPayBlackSilhouette() throws {
        try mutation(.rupay, failure: "original RuPay interiors changed") { data, _, masks in
            var changed = 0
            for i in stride(from: 0, to: data.count, by: 4) where masks.logo[i + 3] > 0 {
                for channel in 0..<3 { data[i + channel] = 0 }
                changed += 1
            }
            XCTAssertGreaterThan(changed, 1000)
            print("MUTATION RuPay silhouette: \(changed) source pixels blackened")
        }
    }

    func testRejectsInvalidSavedFixture() throws {
        let c = CardFace(design: "cardy.99", colors: CardFaceCatalog.presets[0].colors)
        XCTAssertFalse(c.isValid)
        XCTAssertNotEqual(CardDesign(rawValue: CardDesign.face(c).rawValue), .face(c), "Stored future designs deliberately fall back")
        XCTAssertThrowsError(try roundTrip(c), "Fallback must not bypass current fixture eligibility")
        var malformed = c; malformed.design = "cardy.1"; malformed.colors.primary = "invalid"
        XCTAssertFalse(malformed.isValid)
        XCTAssertThrowsError(try roundTrip(malformed))
    }

    func testEveryStressFixtureRoundTrips() throws {
        XCTAssertEqual(try cases().count, 1041)
    }

    func testChromeUsesColourwayAndRetainsShading() throws {
        let folder = output.appendingPathComponent("chrome")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var renders: [String: [UInt8]] = [:]
        for preset in CardFaceCatalog.presets where ["garnet", "sand", "graphite", "cobalt"].contains(preset.id) {
            let c = try roundTrip(CardFace(design: "cardy.8", colors: preset.colors))
            let saved = CardDesign.face(c).rawValue
            XCTAssertTrue(saved.hasPrefix("design1:"))
            XCTAssertEqual(CardDesign(rawValue: saved), .face(c))
            let item = Case(id: preset.id, group: "chrome", palette: preset.name, face: c, network: .visa)
            let name = preset.id + "-chrome-fold"
            let image = try render(face(item))
            try save(image, folder.appendingPathComponent(name + "-after.png"))
            _ = try check(item, image: image, art: render(CardFaceArt(face: c, width: width)),
                plain: render(CardFaceArt(face: c, width: width).artwork),
                sheet: "chrome")
            let raw = try pixels(render(CardFaceArt(face: c, width: width).artwork))
            renders[preset.id] = raw
            if preset.id == "garnet" || preset.id == "cobalt" {
                let dominant = preset.id == "garnet" ? 0 : 2
                let coloured = stride(from: 0, to: raw.count, by: 4).filter {
                    Int(raw[$0 + dominant]) > Int(raw[$0 + 1]) + 16
                }.count
                XCTAssertGreaterThan(Double(coloured) / Double(raw.count / 4), 0.7, "Chrome ignores \(preset.name)")
            }
            let levels = Set(stride(from: 0, to: raw.count, by: 4).map {
                Int(raw[$0]) + Int(raw[$0 + 1]) + Int(raw[$0 + 2])
            })
            XCTAssertGreaterThan(levels.count, 150, "Chrome lost continuous shading")
            XCTAssertGreaterThan(levels.max()!, 600, "Chrome lost specular highlights")
        }
        let graphite = try XCTUnwrap(renders["graphite"])
        for preset in ["garnet", "sand", "cobalt"] {
            let data = try XCTUnwrap(renders[preset])
            let changed = stride(from: 0, to: data.count, by: 4).filter { i in
                (0..<3).contains { abs(Int(data[i + $0]) - Int(graphite[i + $0])) > 12 }
            }.count
            XCTAssertGreaterThan(Double(changed) / Double(data.count / 4), 0.8, "Chrome ignored colourway \(preset)")
        }
    }

    #if DEBUG
    func testSimulatorFixturesAndFixedAppearance() throws {
        let folder = output.appendingPathComponent("ios")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, fixture) in CardStressFixtures.cases.enumerated() {
            XCTAssertEqual(CardDesign(rawValue: CardDesign.face(fixture.face).rawValue), .face(fixture.face))
            let item = Case(id: String(index + 1), group: "ios", palette: fixture.name,
                face: try roundTrip(fixture.face), network: CardNetwork(cardNumber: fixture.number))
            let light = try render(face(item))
            _ = try check(item, image: light,
                art: render(CardFaceArt(face: fixture.face, width: width)),
                plain: render(CardFaceArt(face: fixture.face, width: width).artwork),
                sheet: "ios")
            let renderer = ImageRenderer(content: face(item).frame(width: width, height: height).environment(\.colorScheme, .dark))
            renderer.scale = 3
            let dark = try pixels(XCTUnwrap(renderer.cgImage)), reference = try pixels(light)
            XCTAssertEqual(reference.count, dark.count)
            let delta = zip(reference, dark).map { abs(Int($0) - Int($1)) }.max() ?? 0
            // Repeated same-appearance grain renders also vary by one 8-bit level.
            XCTAssertLessThanOrEqual(delta, 1, "Fixed art adapted to Dark Mode: \(fixture.name)")
            try save(light, folder.appendingPathComponent("mac-reference-\(index + 1)-\(fixture.name).png"))
        }
    }
    #endif
    private func sheet(_ cards: [(Case, CGImage)], title: String, path: URL) throws {
        let columns = 4, cellW = 374, cellH = 310, rows = (cards.count + columns - 1) / columns
        let size = NSSize(width: columns * cellW + 16, height: rows * cellH + 54)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        (title + " · 350 pt @3x sources · Test Bank / •••• 3003").draw(at: NSPoint(x: 16, y: size.height - 32),
            withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.black])
        for (index, item) in cards.enumerated() {
            let (test, image) = item, c = test.face
            let x = Double(index % columns * cellW + 16), top = size.height - Double(index / columns * cellH + 48)
            let rect = NSRect(x: x, y: top - height, width: width, height: height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).addClip()
            NSImage(cgImage: image, size: rect.size).draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            let bands = CardFaceCatalog.legibility(for: c).bands.map { String(format: "%.3f", $0.opacity) }.joined(separator: "/")
            let label = "\(test.id) · \(test.palette) · \(test.network.rawValue)\n\(c.design)\n\(c.colors.primary) / \(c.colors.secondary) / \(c.colors.accent)\nbands: \(bands.isEmpty ? "none" : bands) · \(c.colorway.rawValue)"
            label.draw(in: NSRect(x: x, y: top - height - 76, width: width, height: 72), withAttributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: path)
    }

    func testStressContactSheets() throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scratch = root.appendingPathComponent("build/stress/cards")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let cases = try cases()
        XCTAssertEqual(cases.count, 1041)
        var results: [Result] = [], sheets: [(String, Int)] = [], start = 0
        while start < cases.count {
            let group = cases[start].group
            var end = start
            while end < cases.count && cases[end].group == group { end += 1 }
            for offset in stride(from: start, to: end, by: 20) {
                let filename = group + String(format: "-%02d.png", (offset - start) / 20 + 1)
                var cards: [(Case, CGImage)] = []
                for item in cases[offset..<min(end, offset + 20)] {
                    try autoreleasepool {
                        let image = try render(face(item)), art = try render(CardFaceArt(face: item.face, width: width))
                        let plain = try render(CardFaceArt(face: item.face, width: width).artwork)
                        results.append(try check(item, image: image, art: art, plain: plain, sheet: filename))
                        cards.append((item, image))
                        try save(image, scratch.appendingPathComponent(item.id + ".png"))
                    }
                }
                try sheet(cards, title: group, path: output.appendingPathComponent(filename))
                sheets.append((filename, cards.count))
                print("STRESS \(filename): \(cards.count) real faces checked")
            }
            start = end
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: output.appendingPathComponent("cases.json"))
        let bands = results.flatMap(\.bandOpacities), used = results.filter { !$0.bandOpacities.isEmpty }.count
        let glyphMinimum = results.flatMap { [$0.bankContrast, $0.last4Contrast] + [$0.wordmarkContrast].compactMap { $0 } }.min()!
        let symbolMinimum = results.compactMap(\.symbolContrast).min()!
        let inks = results.flatMap(\.inks), white = inks.filter { $0 == "#FFFFFF" }.count
        let bins = [(0.0, 0.2), (0.2, 0.4), (0.4, 0.6), (0.6, 0.72), (0.72, 1.0)]
        let distribution = bins.map { lo, hi in "| >\(lo)–\(hi) | \(bands.filter { $0 > lo && $0 <= hi }.count) |" }.joined(separator: "\n")
        let table = sheets.map { "| [\($0.0)](\($0.0)) | \($0.1) |" }.joined(separator: "\n")
        let designSummary: [[String: Any]] = CardFaceCatalog.designs.map { design in
            let faces = results.filter { $0.face.design == design }
            let presets = faces.filter { $0.sheet.hasPrefix("presets-") }
            let failures = faces.filter {
                min($0.bankContrast, $0.last4Contrast, $0.wordmarkContrast ?? .infinity) < 4.5
                    || ($0.symbolContrast ?? .infinity) < 3 || $0.noBoxResidual > 3
                    || $0.bandTransferResidual > 3 || $0.logoInteriorResidual > 3
            }.count
            return ["design": design, "faces": faces.count, "failures": failures,
                    "minimumContrast": faces.flatMap { [$0.bankContrast, $0.last4Contrast] + [$0.wordmarkContrast].compactMap { $0 } }.min()!,
                    "presetFaces": presets.count, "presetFacesWithBands": presets.filter { !$0.bandOpacities.isEmpty }.count,
                    "facesWithBands": faces.filter { !$0.bandOpacities.isEmpty }.count]
        }
        try JSONSerialization.data(withJSONObject: designSummary, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("design-summary.json"))
        let designTable = designSummary.map { row in
            let bandCount = row["presetFacesWithBands"] as! Int
            return String(format: "| %@ | %d | %d | %.4f | %d/9 (%.1f%%) |", row["design"] as! String,
                          row["faces"] as! Int, row["failures"] as! Int, row["minimumContrast"] as! Double,
                          bandCount, Double(bandCount) / 9 * 100)
        }.joined(separator: "\n")
        let report = """
        # Fixed card stress report

        \(results.count) saved faces; \(used) use bands (\(bands.count) bands).
        Minimum glyph contrast: \(glyphMinimum). Minimum symbol contrast: \(symbolMinimum).
        White inks: \(white)/\(inks.count).
        Maximum complete-face residual: \(results.map(\.noBoxResidual).max()!) /255.
        Maximum band transfer residual: \(results.map(\.bandTransferResidual).max()!) /255.
        Maximum source-logo interior residual: \(results.map(\.logoInteriorResidual).max()!) /255.

        | Design | Faces | Failing faces | Minimum glyph contrast | Preset band rate |
        |---|---:|---:|---:|---:|
        \(designTable)

        | Edge opacity | Bands |
        |---|---:|
        \(distribution)

        | Sheet | Faces |
        |---|---:|
        \(table)
        """
        try report.write(to: output.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        XCTAssertGreaterThanOrEqual(glyphMinimum, 4.5)
    }
}
