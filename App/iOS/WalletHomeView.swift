import SwiftUI
import SwiftData
import IDCore

struct WalletHomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.reminderScheduler) private var reminders
    @Environment(SessionLock.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \IDRecord.createdAt) private var records: [IDRecord]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var selected: UUID?
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var personFilter = "everyone"
    @State private var homeFrames: [UUID: CGRect] = [:]
    @State private var scrolledUnderHeader = false
    @State private var contentBelow = false
    @State private var pressed: UUID?
    @State private var detailID: UUID?
    @Namespace private var headerGlass
    @State private var add = false
    @State private var edit = false
    @State private var showPeople = false
    @State private var settings = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var selectFeedback = 0

    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.18) : Motion.card }
    private var selectedRecord: IDRecord? { records.first { $0.id == selected } }
    private var visible: [WalletEntry] {
        records.compactMap { record in
            guard let kind = record.kind else { return nil }
            let matchesPerson = personFilter == "everyone" || (personFilter == "me" && record.person == nil)
                || record.person?.id.uuidString == personFilter
            guard matchesPerson else { return nil }
            let payload = try? record.payload()
            guard query.isEmpty || payload.map({ RecordSearch.matches(query, kind: kind, nickname: record.nickname,
                personName: record.person?.name, payload: $0) }) == true else { return nil }
            return WalletEntry(record: record, kind: kind, payload: payload)
        }.sorted {
            let l = IDKind.allCases.firstIndex(of: $0.kind) ?? 0
            let r = IDKind.allCases.firstIndex(of: $1.kind) ?? 0
            return l == r ? $0.record.createdAt < $1.record.createdAt : l < r
        }
    }
    private func isBank(_ record: IDRecord) -> Bool { record.kind == .creditCard || record.kind == .debitCard }
    private func ratio(_ record: IDRecord) -> CGFloat { record.kind == .passport ? 1.42 : 1.586 }

    var body: some View {
        let entries = visible
        NavigationStack {
            GeometryReader { geometry in
                let topOverflow = selected == nil ? geometry.safeAreaInsets.top : 0
                let bottomOverflow = selected == nil ? geometry.safeAreaInsets.bottom : 0
                let width = max(1, geometry.size.width - 32)
                let selectedWidth = typeSize.isAccessibilitySize ? width * 0.78 : width
                let pileHeight: CGFloat = min(3, CGFloat(max(0, entries.count - 1))) * 10
                ZStack(alignment: .top) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            if searching {
                                HStack {
                                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                    TextField("Search IDs and cards", text: $query).focused($searchFocused)
                                        .autocorrectionDisabled().accessibilityIdentifier("search-ids")
                                }.padding(12).glassEffect()
                            }
                            if !people.isEmpty {
                                Menu { personPicker } label: { Label(filterName, systemImage: "chevron.down") }
                                    .buttonStyle(.glass).opacity(selected == nil ? 1 : 0)
                            }
                            cardSection("Cards", cards: entries.filter { isBank($0.record) }, width: width)
                            cardSection("IDs", cards: entries.filter { !isBank($0.record) }, width: width)
                        }.padding(.horizontal, 16).padding(.top, 76).padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden).scrollClipDisabled()
                    .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 1 }) { _, value in
                        scrolledUnderHeader = value
                    }
                    .onScrollGeometryChange(for: Bool.self, of: { $0.contentSize.height - $0.contentOffset.y > $0.containerSize.height + 1 }) { _, value in
                        contentBelow = value
                    }
                    .scrollDisabled(selected != nil).allowsHitTesting(selected == nil)
                    .accessibilityHidden(selected != nil).accessibilityIdentifier("home-scroll")

                    WalletCardsLayer(entries: entries, selected: $selected, detailID: detailID,
                                     homeFrames: homeFrames, pressed: pressed, width: width,
                                     selectedWidth: selectedWidth, height: geometry.size.height,
                                     pileHeight: pileHeight, select: select)
                    // The cards live outside the scroll view, so its system edge effect cannot cover them.
                    // Full strength through the header (12 pt inset + 44 pt tall), then a 40 pt fade, like the system edge effect.
                    WalletEdgeBand(top: true, solid: (geometry.safeAreaInsets.top + 56) / (geometry.safeAreaInsets.top + 96))
                        .frame(height: geometry.safeAreaInsets.top + 96)
                        .offset(y: -geometry.safeAreaInsets.top)
                        .opacity(selected == nil && scrolledUnderHeader ? 1 : 0)
                        .animation(.easeOut(duration: 0.18), value: scrolledUnderHeader)
                    WalletEdgeBand(top: false, solid: 0.25)
                        .frame(height: geometry.safeAreaInsets.bottom + 48)
                        .offset(y: geometry.size.height - 48)
                        .opacity(selected == nil && contentBelow ? 1 : 0)
                        .animation(.easeOut(duration: 0.18), value: contentBelow)
                    header.padding(.horizontal, 16).padding(.top, 12).zIndex(40)
                    if entries.isEmpty {
                        if records.isEmpty {
                            VStack(spacing: 20) {
                                RoundedRectangle(cornerRadius: 18).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [8]))
                                    .aspectRatio(1.586, contentMode: .fit).frame(maxWidth: 300).accessibilityHidden(true)
                                Text("Add your first ID").font(.title2.bold())
                                Button("Add ID") { add = true }.buttonStyle(.glassProminent)
                            }.padding(32).frame(maxHeight: .infinity).accessibilityIdentifier("empty-state")
                        } else { ContentUnavailableView.search(text: query) }
                    }
                }
                .coordinateSpace(name: "wallet-stage")
                // Extend home content to the screen edges; keep the opened card's pile inside the stage.
                .padding(.top, topOverflow).padding(.bottom, bottomOverflow)
                .clipped()
                .padding(.top, -topOverflow).padding(.bottom, -bottomOverflow)
                .onPreferenceChange(CardFrames.self) { homeFrames = $0 }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $add) { AddIDSheet() }
            .sheet(isPresented: $edit) {
                if let record = selectedRecord, let kind = record.kind {
                    NavigationStack { RecordEditorView(kind: kind, record: record) }
                }
            }
            .sheet(isPresented: $showPeople) { PeopleView() }
            .sheet(isPresented: $settings) { SettingsView() }
            .confirmationDialog("Delete this ID?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete ID", role: .destructive) { deleteRecord() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This permanently deletes the ID from your devices.") }
            .alert("Couldn't delete this ID. Please try again.", isPresented: $deleteFailed) { Button("OK") { } }
            .task(id: selected) {
                guard selected == nil else { return }
                // Retain the returning card for mid-flight taps; this does not delay its movement.
                do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
                detailID = nil
            }
            .sensoryFeedback(.impact(weight: .light), trigger: selectFeedback)
            .onChange(of: entries.map(\.id)) { _, ids in
                if let selected, !ids.contains(selected) { self.selected = nil; detailID = nil }
            }
        }
    }

    private var filterName: String { personFilter == "everyone" ? "Everyone" : personFilter == "me" ? "Me" : people.first { $0.id.uuidString == personFilter }?.name ?? "Everyone" }
    private var personPicker: some View {
        Picker("Person", selection: $personFilter) {
            Text("Everyone").tag("everyone"); Text("Me").tag("me")
            ForEach(people) { Text($0.name).tag($0.id.uuidString) }
        }
    }
    private func cardSection(_ title: String, cards: [WalletEntry], width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !cards.isEmpty {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .padding(.bottom, 12).opacity(selected == nil ? 1 : 0)
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, entry in
                    let record = entry.record
                    let height = width / ratio(record)
                    Button { select(record.id) } label: {
                        Color.clear.frame(height: height).contentShape(Rectangle())
                    }
                    .buttonStyle(PressReporter { pressed = $0 ? record.id : nil })
                    .accessibilityLabel(entry.spokenLabel)
                    .accessibilityIdentifier("card-" + (record.nickname.isEmpty ? record.kindRaw : record.nickname))
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: CardFrames.self, value: [record.id: proxy.frame(in: .named("wallet-stage"))])
                        }
                    }
                    .padding(.bottom, index == cards.count - 1 ? 0 : -height * 0.5)
                    .zIndex(Double(index))
                }
            }
        }
    }
    private var header: some View {
        HStack {
            Text("IDs").font(selected == nil ? .largeTitle.bold() : .headline)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    if selected == nil {
                        HStack(spacing: 0) {
                            Button("Search", systemImage: "magnifyingglass") {
                                withAnimation(motion) { searching.toggle() }
                                searchFocused = searching
                                if !searching { query = "" }
                            }
                            Button("Add ID", systemImage: "plus") { add = true }.accessibilityIdentifier("add-id")
                        }.labelStyle(.iconOnly).buttonStyle(HeaderButtonStyle())
                            .glassEffect().glassEffectID("primary", in: headerGlass)
                    } else {
                        Button("Done") { collapse() }.padding(.horizontal, 16).frame(height: 44)
                            .buttonStyle(.plain).glassEffect().glassEffectID("primary", in: headerGlass)
                            .accessibilityIdentifier("done")
                    }
                    Menu {
                        if selected == nil {
                            Button("People", systemImage: "person.2") { showPeople = true }
                            Menu("Filter by person") { personPicker }
                            Button("Settings", systemImage: "gearshape") { settings = true }
                            Button("Lock Now", systemImage: "lock") { session.lockNow() }
                        } else {
                            Button("Edit", systemImage: "pencil") { edit = true }
                            Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        }
                    } label: { Label(selected == nil ? "More" : "ID actions", systemImage: "ellipsis") }
                        .labelStyle(.iconOnly).buttonStyle(HeaderButtonStyle())
                        .glassEffect().glassEffectID("more", in: headerGlass)
                }
            }
        }.frame(height: 44)
    }
    private func select(_ id: UUID) {
        withAnimation(motion) { detailID = id; selected = id }
        selectFeedback += 1
    }
    private func collapse() {
        withAnimation(motion) { selected = nil }
    }
    private func deleteRecord() {
        guard let record = selectedRecord, session.isUnlocked else { return }
        let id = record.id
        context.delete(record)
        do { try context.save(); reminders?.remove(recordID: id); selected = nil; detailID = nil }
        catch { context.rollback(); deleteFailed = true }
    }
}

private struct CardFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private struct PressReporter: ButtonStyle {
    let changed: (Bool) -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.onChange(of: configuration.isPressed) { _, pressed in changed(pressed) }
    }
}

private struct HeaderButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.frame(width: 44, height: 44).contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

private struct WalletEntry: Identifiable {
    let record: IDRecord
    let kind: IDKind
    let payload: IDPayload?
    var id: UUID { record.id }
    @MainActor var spokenLabel: String {
        guard let payload else { return "This ID can't be opened in this version" }
        return CardFaceView(kind: kind, payload: payload, personName: record.person?.name).spokenLabel
    }
}

// Drag changes stay below the query/decoding boundary.
private struct WalletCardsLayer: View {
    let entries: [WalletEntry]
    @Binding var selected: UUID?
    let detailID: UUID?
    let homeFrames: [UUID: CGRect]
    let pressed: UUID?
    let width: CGFloat
    let selectedWidth: CGFloat
    let height: CGFloat
    let pileHeight: CGFloat
    let select: (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var pileDrag: CGFloat = 0
    private let selectedY: CGFloat = 76

    var body: some View {
        let ranks = Dictionary(uniqueKeysWithValues: entries.filter { $0.id != selected }.enumerated().map { ($0.element.id, $0.offset) })
        ZStack(alignment: .top) {
            if let entry = entries.first(where: { $0.id == detailID }) {
                let isSelected = selected == entry.id
                let cardHeight = selectedWidth / (entry.kind == .passport ? 1.42 : 1.586)
                List { DetailRowsView(record: entry.record, isVisible: isSelected, decodedPayload: entry.payload) }
                    .listStyle(.insetGrouped).scrollContentBackground(.hidden)
                    .contentMargins(.top, 0)
                    .contentMargins(.bottom, pileHeight + 16, for: .scrollContent)
                    .frame(height: max(60, height - selectedY - cardHeight - 8))
                    .opacity(isSelected ? 1 : 0)
                    .animation(isSelected ? .easeOut(duration: 0.14).delay(reduceMotion ? 0 : 0.13) : .easeOut(duration: 0.08), value: isSelected)
                    .offset(y: (isSelected ? selectedY : homeFrames[entry.id]?.minY ?? selectedY) + cardHeight + 8 + (reduceMotion ? 0 : dragOffset))
                    .allowsHitTesting(isSelected).accessibilityHidden(!isSelected)
                    .accessibilityIdentifier("details")
                    .id(reduceMotion ? "\(entry.id)-\(isSelected)" : entry.id.uuidString).zIndex(-1)
                    .transition(.opacity.animation(.easeOut(duration: 0.14).delay(reduceMotion ? 0 : 0.13)))
            }
            ForEach(entries) { entry in
                let rank = ranks[entry.id] ?? 0
                let isSelected = selected == entry.id
                let homeY = homeFrames[entry.id]?.minY ?? height + 300
                let pileY = rank < 3 ? height - pileHeight + CGFloat(rank) * 10 : height + CGFloat(rank - 3) * 10
                Button { if isSelected { collapse() } else { select(entry.id) } } label: {
                    Group {
                        if let payload = entry.payload {
                            CardFaceView(kind: entry.kind, payload: payload, personName: entry.record.person?.name).equatable()
                        } else {
                            Text("This ID can't be opened in this version")
                                .frame(width: width, height: width / 1.586).background(.quaternary)
                        }
                    }.frame(width: width)
                }
                .buttonStyle(PressableCardButtonStyle())
                .scaleEffect(isSelected ? selectedWidth / width : 1, anchor: .top)
                .scaleEffect(pressed == entry.id && !reduceMotion ? 0.98 : 1)
                .offset(y: selected == nil ? homeY : isSelected ? selectedY + dragOffset : pileY + pileDrag)
                .id(reduceMotion ? "\(entry.id)-\(selected?.uuidString ?? "home")" : entry.id.uuidString)
                .transition(.opacity)
                .zIndex(isSelected ? Double(entries.count) + 20 : 5 + Double(rank))
                .allowsHitTesting(isSelected || (selected == nil && detailID == entry.id)).accessibilityHidden(!isSelected)
                .accessibilityIdentifier(isSelected ? "selected-card" : "card-art")
                .simultaneousGesture(dismissGesture(pile: false))
            }
            if selected != nil && pileHeight > 0 {
                VStack {
                    Spacer()
                    Button { collapse() } label: { Color.clear.frame(height: max(44, pileHeight)).contentShape(Rectangle()) }
                        .accessibilityLabel("Back to all IDs").accessibilityIdentifier("bottom-pile")
                        .simultaneousGesture(dismissGesture(pile: true))
                }.zIndex(30)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onChange(of: selected) { _, _ in
                withAnimation(reduceMotion ? .easeOut(duration: 0.18) : Motion.card) { dragOffset = 0; pileDrag = 0 }
            }
    }
    private func spring(velocity: CGFloat, distance: CGFloat) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .interpolatingSpring(.init(response: 0.35, dampingRatio: 1),
            initialVelocity: abs(distance) > 1 ? Double(velocity / distance) : 0)
    }
    private func collapse(velocity: CGFloat = 0, pile: Bool = false) {
        let origin = selected.flatMap { homeFrames[$0]?.minY } ?? selectedY
        let distance = pile ? -pileDrag : origin - selectedY - dragOffset
        withAnimation(spring(velocity: velocity, distance: distance)) { selected = nil; dragOffset = 0; pileDrag = 0 }
    }
    private func dismissGesture(pile: Bool) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard selected != nil, !reduceMotion else { return }
                if pile { pileDrag = min(0, value.translation.height) } else { dragOffset = max(0, value.translation.height) }
            }
            .onEnded { value in
                if pile ? value.predictedEndTranslation.height < -70 : value.predictedEndTranslation.height > 90 {
                    collapse(velocity: value.velocity.height, pile: pile)
                } else {
                    withAnimation(spring(velocity: value.velocity.height, distance: -(pile ? pileDrag : dragOffset))) {
                        dragOffset = 0; pileDrag = 0
                    }
                }
            }
    }
}

private struct WalletEdgeBand: View {
    let top: Bool
    let solid: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Rectangle()
            .fill(reduceTransparency ? AnyShapeStyle(Color(uiColor: .systemGroupedBackground)) : AnyShapeStyle(.regularMaterial))
            .overlay {
                Color(uiColor: .systemGroupedBackground).opacity(reduceTransparency ? 0 : 0.25)
            }
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0),
                                       .init(color: .black, location: solid),
                                       .init(color: .black.opacity(0.6), location: solid + (1 - solid) * 0.45),
                                       .init(color: .clear, location: 1)],
                               startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
            }
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
