import AppKit
import IDCore
import SwiftData
import SwiftUI
import XCTest

@MainActor final class CardEditorRegressionTests: XCTestCase {
    @MainActor private final class Model: ObservableObject {
        @Published var payload = IDPayload(values: ["bank": "Test Bank", "cardNumber": "4111111111111111",
            "cardDesign": CardDesign.face(CardFace(design: "cardy.1", colors: CardFaceCatalog.presets[6].colors)).rawValue])
        @Published var revision = 0
    }
    private struct Editor: View {
        @ObservedObject var model: Model
        var body: some View { Form { CardCustomizeView(kind: .debitCard, payload: $model.payload) }.formStyle(.grouped) }
    }
    private func window<Content: View>(_ content: Content) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func testStripHas37DesignsInRelease() {
        XCTAssertEqual(CardCustomizeView.designIDs, CardFaceCatalog.designs)
    }

    func testDesignChangeKeepsColours() throws {
        let model = Model()
        let scanned = CardColors(primary: "#312341", secondary: "#123456", accent: "#654321")
        let editor = CardCustomizeView(kind: .debitCard, payload: Binding(get: { model.payload }, set: { model.payload = $0 }))
        for original in [RecordEditorView.newBankFace(), CardFace(design: "cardy.1", colors: scanned),
                         CardFace(design: "cardy.1", colors: scanned, colorway: .card, cardColors: scanned)] {
            model.payload[.cardDesign] = CardDesign.face(original).rawValue
            editor.selectDesign("cardy.12")
            var expected = original; expected.design = "cardy.12"
            XCTAssertEqual(CardDesign(rawValue: try XCTUnwrap(model.payload[.cardDesign])), .face(expected))
        }
    }

    func testCardColorwayHiddenWithoutCardColors() {
        let model = Model()
        let editor = CardCustomizeView(kind: .debitCard, payload: Binding(get: { model.payload }, set: { model.payload = $0 }))
        XCTAssertEqual(editor.availableColorways, [.preset, .custom])
    }

    func testTypedDefaultAndScannedColours() throws {
        let typed = RecordEditorView.newBankFace()
        XCTAssertTrue(typed.isValid)
        XCTAssertEqual(typed.colorway, .preset)
        XCTAssertEqual(typed.colors, CardFaceCatalog.presets.first { $0.id == typed.presetID }?.colors)
        XCTAssertNil(typed.cardColors)
        let colors = CardColors(primary: "#123456", secondary: "#345678", accent: "#56789A")
        for raw in [nil, CardDesign.face(typed).rawValue, "hsbcLivePlus"] {
            var payload = IDPayload(); payload[.cardDesign] = raw
            RecordEditorView.applyScannedColors(colors, to: &payload)
            guard case .face(let scanned) = CardDesign(rawValue: try XCTUnwrap(payload[.cardDesign])) else { return XCTFail("Missing scanned face") }
            XCTAssertEqual(scanned.colors, colors); XCTAssertEqual(scanned.cardColors, colors)
            XCTAssertEqual(scanned.colorway, .card); XCTAssertNil(scanned.presetID)
            if raw == CardDesign.face(typed).rawValue { XCTAssertEqual(scanned.design, typed.design) }
        }
    }

    #if DEBUG
    func testColourChangesRenderOnlyVisibleThumbnails() async throws {
        let model = Model(), probe = CardRenderProbe.shared
        let window = window(Editor(model: model))
        defer { window.close(); probe.stop() }
        try await Task.sleep(for: .seconds(1))
        probe.start()
        for index in 1...3 {
            guard case .face(var c) = CardDesign(rawValue: model.payload[.cardDesign]!) else { return XCTFail("Missing fixture") }
            c.colors.primary = String(format: "#%02X0A3C", 119 + index * 15)
            model.payload[.cardDesign] = CardDesign.face(c).rawValue
            try await Task.sleep(for: .milliseconds(250))
            let counts = probe.take()
            print("EDITOR colour-change=\(index) thumbnailCanvas=\(counts["thumbnail-canvas", default: 0]) thumbnailBody=\(counts["thumbnail-body", default: 0]) previewCanvas=\(counts["preview-canvas", default: 0])")
            XCTAssertLessThanOrEqual(counts["thumbnail-canvas", default: 0], 16)
            XCTAssertLessThan(counts["thumbnail-body", default: 0], 48)
            XCTAssertEqual(counts["preview-canvas", default: 0], 1, "Exactly the live preview must update")
        }
    }

    private struct RecordHost: View {
        @ObservedObject var model: Model
        let record: IDRecord
        let report: (Bool) -> Void
        var body: some View {
            var editor = RecordEditorView(kind: .debitCard, record: record)
            editor.onDirtyStateChange = report
            return NavigationStack { editor }.accessibilityIdentifier("revision-\(model.revision)")
        }
    }
    private struct Auth: Authenticator { func authenticate(reason: String) async -> Bool { true } }

    func testRecreatingEditorKeepsOriginalDirtyBaseline() async throws {
        let model = Model(), container = try IDStore.makeContainer(inMemory: true)
        let record = try IDRecord(kind: .debitCard, person: nil, payload: model.payload)
        container.mainContext.insert(record)
        let session = SessionLock(authenticator: Auth())
        var states: [Bool] = []
        let host = RecordHost(model: model, record: record, report: { states.append($0) })
            .modelContainer(container).environment(session)
        let window = window(host)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(states, [false])
        record.nickname = "Updated elsewhere"
        record.notes = "Another device"
        let person = Person(name: "Test Person")
        container.mainContext.insert(person)
        record.person = person
        var remote = model.payload; remote[.bank] = "Another Test Bank"
        try record.setPayload(remote)
        model.revision += 1
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(states, [false], "A parent recreation must not make an untouched draft dirty")
    }
    #endif

    func testColourFieldPaintMatchesHandleCoordinates() throws {
        let size = CGSize(width: 320, height: 180)
        let renderer = ImageRenderer(content: CardColourFieldBackground(brightness: 0.75).frame(width: size.width, height: size.height))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { data in
            let context = try XCTUnwrap(CGContext(data: data.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        for hue in [0.03, 0.17, 0.82, 0.97] {
            for saturation in [0.05, 0.5, 0.95] {
                let x = Int((22 + hue * (size.width - 44)) * 2)
                let y = Int((22 + saturation * (size.height - 44)) * 2)
                let offset = (y * image.width + x) * 4
                let expected = try XCTUnwrap(NSColor(Color(hue: hue, saturation: saturation, brightness: 0.75)).usingColorSpace(.sRGB))
                XCTAssertLessThan(abs(Double(bytes[offset]) / 255 - expected.redComponent), 0.025)
                XCTAssertLessThan(abs(Double(bytes[offset + 1]) / 255 - expected.greenComponent), 0.025)
                XCTAssertLessThan(abs(Double(bytes[offset + 2]) / 255 - expected.blueComponent), 0.025)
            }
        }
    }
}
