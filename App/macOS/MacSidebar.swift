import SwiftUI
import SwiftData
import IDCore

struct MacSidebar: View {
    let records: [IDRecord]
    @Binding var selection: UUID?
    @Binding var searchFocused: Bool
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var query = ""
    @State private var person = "everyone"
    @FocusState private var searching: Bool
    var delete: () -> Void

    private var visible: [IDRecord] {
        records.filter { record in
            guard let kind = record.kind else { return false }
            guard person == "everyone" || (person == "me" && record.person == nil)
                    || record.person?.id.uuidString == person else { return false }
            guard let payload = try? record.payload() else { return query.isEmpty }
            return RecordSearch.matches(query, kind: kind, nickname: record.nickname, personName: record.person?.name, payload: payload)
        }.sorted {
            let left = IDKind.allCases.firstIndex(of: $0.kind ?? .aadhaar) ?? 0
            let right = IDKind.allCases.firstIndex(of: $1.kind ?? .aadhaar) ?? 0
            return left == right ? $0.createdAt < $1.createdAt : left < right
        }
    }

    var body: some View {
        List(selection: $selection) {
            section("Cards", bank: true)
            section("IDs", bank: false)
        }
        .listStyle(.sidebar).navigationTitle("IDs")
        .searchable(text: $query, placement: .sidebar, prompt: "Search IDs and cards")
        .searchFocused($searching)
        .onChange(of: searching) { _, value in searchFocused = value }
        .onDeleteCommand { if selection != nil && !searching { delete() } }
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Person", selection: $person) {
                        Text("Everyone").tag("everyone"); Text("Me").tag("me")
                        ForEach(people) { Text($0.name).tag($0.id.uuidString) }
                    }
                } label: { Label("Filter by person", systemImage: "line.3.horizontal.decrease") }
                .help("Filter by person")
            }
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }

    @ViewBuilder private func section(_ title: String, bank: Bool) -> some View {
        let items = visible.filter { ($0.kind == .creditCard || $0.kind == .debitCard) == bank }
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { record in
                    MacRecordLabel(record: record, thumbnailWidth: 64).tag(record.id)
                }
            }
        }
    }
}

struct MacRecordLabel: View {
    let record: IDRecord
    var thumbnailWidth: CGFloat = 56
    var body: some View {
        HStack(spacing: 12) {
            CardFaceView(record: record).frame(width: thumbnailWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.nickname.isEmpty ? record.kind?.displayName ?? "ID" : record.nickname)
                    .font(.headline).lineLimit(1)
                Text(CardFaceView(record: record).identifier).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 6).contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CardFaceView(record: record).spokenLabel)
        .accessibilityIdentifier("record-" + (record.nickname.isEmpty ? record.kindRaw : record.nickname))
    }
}
