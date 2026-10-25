import SwiftUI
import IDCore

struct CardCustomizeView: View {
    let kind: IDKind
    @Binding var payload: IDPayload
    @State private var lastFace: CardFace?

    static var designIDs: [String] {
        CardFaceCatalog.designs
    }
    private var selected: CardDesign {
        (payload[.cardDesign].flatMap(CardDesign.init(rawValue:)) ?? .defaultGeneric(forBank: payload[.bank] ?? ""))
            .faceDesign(forBank: payload[.bank] ?? "")
    }
    private var face: CardFace {
        if case .face(let face) = selected { return face }
        return lastFace ?? CardFaceCatalog.fallback(for: payload[.bank] ?? "")
    }
    private var isReplica: Bool { if case .face = selected { false } else { true } }
    var availableColorways: [CardColorway] { [.preset, .custom] + (face.cardColors == nil ? [] : [.card]) }
    var availableColorRoles: [CardColorRole] { CardFaceCatalog.colorRoles(for: face.design) }
    private func name(_ id: String) -> String {
        ["hsbcLivePlus": "HSBC Live+", "hdfcPixelPlay": "HDFC Pixel Play", "hdfcMillennia": "HDFC Millennia"][id]
            ?? CardFaceCatalog.name(for: id)
    }
    private var selectedID: String { if case .face(let face) = selected { face.design } else { selected.rawValue } }

    var body: some View {
        Section {
            CardFaceView(kind: kind, payload: payload)
                .frame(maxWidth: 440).frame(maxWidth: .infinity)
                .accessibilityIdentifier("customize-preview")
                .accessibilityLabel("Card design preview")
                .accessibilityValue(name(selectedID) + (isReplica ? "" : ", " + face.colorway.rawValue.capitalized))
            Button("Shuffle Design", systemImage: "shuffle") {
                var generator = SystemRandomNumberGenerator()
                save(CardFaceCatalog.shuffled(restoredFace(), using: &generator))
            }
            .frame(minHeight: 44).accessibilityIdentifier("customize-shuffle")
        }
        Section("Design") {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(Self.designIDs, id: \.self) { id in
                            choice(name(id), selected: selectedID == id, id: "design-" + id,
                                   action: { selectDesign(id) }) { thumbnail(id) }.id(id)
                        }
                    }.padding(4)
                }.accessibilityIdentifier("customize-design-strip")
                    .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
                    .onChange(of: selectedID) { _, id in proxy.scrollTo(id, anchor: .center) }
            }
        }
        if !isReplica {
            Section("Colours") {
                Picker("Colourway", selection: Binding(get: { face.colorway }, set: setColorway)) {
                    ForEach(availableColorways, id: \.self) { value in
                        Text(value == .preset ? "Presets" : value.rawValue.capitalized).tag(value)
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("customize-colourway")
                switch face.colorway {
                case .preset:
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(Array(CardFaceCatalog.presets.enumerated()), id: \.element.id) { index, preset in
                                choice(preset.name, selected: face.presetID == preset.id,
                                       id: "customize-colours-\(index)", action: {
                                    change { $0.colors = preset.colors; $0.presetID = preset.id; $0.colorway = .preset }
                                }) {
                                    HStack(spacing: 0) {
                                        ForEach(availableColorRoles, id: \.self) { role in Color(cardHex: preset.colors[role]) }
                                    }.frame(width: 44, height: 44).clipShape(Circle())
                                }
                            }
                        }.padding(4)
                    }
                case .custom:
                    CardColourField(colors: Binding(get: { face.colors }, set: { colors in
                        change { $0.colors = colors; $0.colorway = .custom; $0.presetID = nil }
                    }), roles: availableColorRoles)
                case .card:
                    if let colors = face.cardColors {
                        HStack(spacing: 20) {
                            ForEach(availableColorRoles, id: \.self) { role in
                                Circle().fill(Color(cardHex: colors[role])).frame(width: 36, height: 36)
                                    .overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(role.rawValue.capitalized + " colour")
                                    .accessibilityValue(CardPickerColour(color: Color(cardHex: colors[role])).name)
                                    .accessibilityIdentifier("customize-card-" + role.rawValue)
                            }
                        }.accessibilityElement(children: .contain)
                    }
                }
            }
        }
    }

    func selectDesign(_ id: String) {
        guard CardFaceCatalog.designs.contains(id) else { return }
        var value = restoredFace()
        value.design = id
        save(value)
    }
    private func restoredFace() -> CardFace {
        if case .face(let current) = selected { return current }
        return lastFace ?? RecordEditorView.newBankFace()
    }
    private func save(_ value: CardFace) { payload[.cardDesign] = CardDesign.face(value).rawValue }
    private func change(_ edit: (inout CardFace) -> Void) { var value = face; edit(&value); save(value) }
    private func setColorway(_ colorway: CardColorway) {
        change {
            $0.colorway = colorway
            if colorway == .card, let colors = $0.cardColors { $0.colors = colors }
            if colorway == .preset {
                let preset = CardFaceCatalog.presets.first { $0.id == face.presetID } ?? CardFaceCatalog.presets[0]
                $0.colors = preset.colors; $0.presetID = preset.id
            }
        }
    }
    private func choice<Content: View>(_ name: String, selected: Bool, id: String,
        action: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        Button(action: action) {
            content().accessibilityHidden(true)
                .padding(5).frame(minWidth: 44, minHeight: 44)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor)
                            .padding(2).accessibilityHidden(true)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
                .contentShape(Rectangle())
        }.buttonStyle(PressableCardButtonStyle()).accessibilityLabel(name)
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
    }
    @ViewBuilder private func thumbnail(_ id: String) -> some View {
        #if DEBUG
        let _ = CardRenderProbe.shared.hit("thumbnail-body")
        #endif
        if CardFaceCatalog.designs.contains(id) {
            var value: CardFace { var value = face; value.design = id; return value }
            CardFaceArt(face: value, width: 100).clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let replica = CardDesign(rawValue: id) {
            BankCardFace(design: replica, kind: kind, bank: "", network: .other, identifier: "", width: 100)
                .clipShape(RoundedRectangle(cornerRadius: 4)).accessibilityHidden(true)
        }
    }
}

private struct CardColourField: View {
    @Binding var colors: CardColors
    let roles: [CardColorRole]
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: CardColorRole = .primary
    @State private var achromaticPositions: [CardColorRole: CGPoint] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GeometryReader { geometry in
                ZStack {
                    CardColourFieldBackground(brightness: value(selected).brightness)
                    ForEach(roles, id: \.self) { role in
                        let colour = value(role)
                        Button { selected = role } label: {
                            // Marker glyphs stay inside the fixed target; full role labels below scale with text size.
                            Text(String(role.rawValue.prefix(1)).uppercased()).font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Contrast.ratio("#FFFFFF", colors[role]) > Contrast.ratio("#000000", colors[role]) ? .white : .black)
                                .frame(width: 36, height: 36).background(Color(cardHex: colors[role]), in: Circle())
                                .overlay(Circle().strokeBorder(.white, lineWidth: selected == role ? 4 : 2))
                                .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
                                .frame(width: 44, height: 44).contentShape(Circle())
                        }
                        .buttonStyle(PressableCardButtonStyle())
                        .highPriorityGesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("colour-field")).onChanged { gesture in
                            selected = role
                            var next = value(role)
                            next.hue = min(1, max(0, (gesture.location.x - 22) / max(1, geometry.size.width - 44)))
                            next.saturation = min(1, max(0, (gesture.location.y - 22) / max(1, geometry.size.height - 44)))
                            set(next, for: role)
                        })
                        .position(x: 22 + colour.hue * (geometry.size.width - 44), y: 22 + colour.saturation * (geometry.size.height - 44))
                        .zIndex(selected == role ? 1 : 0)
                        .accessibilityLabel(role.rawValue.capitalized + " colour")
                        .accessibilityValue(colour.name)
                        .accessibilityAddTraits(selected == role ? .isSelected : [])
                        .accessibilityAdjustableAction { direction in
                            selected = role
                            var next = value(role)
                            switch direction {
                            case .increment: next.hue = (next.hue + 0.05).truncatingRemainder(dividingBy: 1)
                            case .decrement: next.hue = (next.hue + 0.95).truncatingRemainder(dividingBy: 1)
                            @unknown default: return
                            }
                            set(next, for: role)
                        }
                        .accessibilityIdentifier("customize-handle-" + role.rawValue)
                    }
                }
                .coordinateSpace(name: "colour-field")
            }
            .frame(height: 180)
            .accessibilityElement(children: .contain).accessibilityIdentifier("customize-colour-field")
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
             : AnyLayout(HStackLayout(spacing: 12))) { chips }
            VStack(alignment: .leading) {
                Text(selected.rawValue.capitalized + " Brightness").font(.subheadline)
                Slider(value: Binding(get: { value(selected).brightness }, set: { brightness in
                    var next = value(selected); next.brightness = brightness; set(next, for: selected)
                }), in: 0...1) { Text(selected.rawValue.capitalized + " Brightness") }
                .labelsHidden().accessibilityIdentifier("customize-brightness")
            }
        }.padding(.vertical, 4)
            .onChange(of: roles) { _, roles in
                if !roles.contains(selected) { selected = .primary }
            }
    }

    @ViewBuilder private var chips: some View {
        ForEach(roles, id: \.self) { role in
            (typeSize.isAccessibilitySize ? AnyLayout(HStackLayout(spacing: 12))
             : AnyLayout(VStackLayout(spacing: 4))) {
                ColorPicker(role.rawValue.capitalized, selection: Binding(get: { Color(cardHex: colors[role]) }, set: { color in
                    selected = role
                    achromaticPositions[role] = nil
                    assign(CardPickerColour(color: color).hex, to: role)
                }), supportsOpacity: false)
                .labelsHidden().frame(minWidth: 44, minHeight: 44)
                .simultaneousGesture(TapGesture().onEnded { selected = role })
                .accessibilityAddTraits(selected == role ? .isSelected : [])
                .accessibilityIdentifier("customize-colour-" + role.rawValue)
                Button { selected = role } label: {
                    Text(role.rawValue.capitalized).font(.body).fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 8)
                        .background(selected == role ? Color.accentColor.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(PressableCardButtonStyle())
                .accessibilityLabel("Select " + role.rawValue + " colour")
                .accessibilityAddTraits(selected == role ? .isSelected : [])
                .accessibilityIdentifier("customize-select-" + role.rawValue)
            }.frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
        }
    }
    private func value(_ role: CardColorRole) -> CardPickerColour {
        var result = CardPickerColour(color: Color(cardHex: colors[role]))
        if let position = achromaticPositions[role] {
            if result.saturation == 0 { result.hue = position.x }
            if result.brightness == 0 { result.saturation = position.y }
        }
        return result
    }
    private func set(_ value: CardPickerColour, for role: CardColorRole) {
        achromaticPositions[role] = CGPoint(x: value.hue, y: value.saturation)
        assign(value.hex, to: role)
    }
    private func assign(_ hex: String, to role: CardColorRole) {
        switch role {
        case .primary: colors.primary = hex
        case .secondary: colors.secondary = hex
        case .accent: colors.accent = hex
        }
    }
}

struct CardColourFieldBackground: View {
    let brightness: Double
    var body: some View {
        GeometryReader { geometry in
            let x = 22 / max(44, geometry.size.width), y = 22 / max(44, geometry.size.height)
            Rectangle().fill(.linearGradient(
                Gradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: brightness) }).colorSpace(.device),
                startPoint: UnitPoint(x: x, y: 0.5), endPoint: UnitPoint(x: 1 - x, y: 0.5)))
                .overlay {
                    Rectangle().fill(.linearGradient(
                        Gradient(colors: [Color(hue: 0, saturation: 0, brightness: brightness), .clear]).colorSpace(.device),
                        startPoint: UnitPoint(x: 0.5, y: y), endPoint: UnitPoint(x: 0.5, y: 1 - y)))
                }
                .drawingGroup(opaque: true, colorMode: .nonLinear)
        }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityHidden(true)
    }
}

struct CardPickerColour {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(color: Color) {
        #if os(macOS)
        let native = NSColor(color).usingColorSpace(.sRGB) ?? .black
        #else
        let native = UIColor(color)
        #endif
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        native.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        hue = h; saturation = s; brightness = b
    }
    var hex: String {
        let color = Color(hue: hue, saturation: saturation, brightness: brightness)
        #if os(macOS)
        let native = NSColor(color).usingColorSpace(.sRGB) ?? .black
        let red = native.redComponent, green = native.greenComponent, blue = native.blueComponent
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: nil)
        #endif
        return String(format: "#%02X%02X%02X", Int((min(1, max(0, red)) * 255).rounded()),
                      Int((min(1, max(0, green)) * 255).rounded()), Int((min(1, max(0, blue)) * 255).rounded()))
    }
    var name: String {
        if brightness < 0.08 { return "Black" }
        if saturation < 0.08 { return brightness > 0.92 ? "White" : "Grey" }
        let names = ["red", "orange", "yellow", "lime", "green", "teal", "cyan", "blue", "indigo", "purple", "magenta", "rose"]
        return (brightness < 0.55 ? "Deep " : saturation < 0.35 ? "Pale " : "") + names[Int((hue * 12).rounded()) % 12]
    }
}
