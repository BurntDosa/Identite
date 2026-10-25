import SwiftUI
import SwiftData
import IDCore

struct MenuBarPanel: View {
    @ObservedObject var events: MacSessionEvents
    @Environment(SessionLock.self) private var session
    var body: some View {
        Group {
            if session.isUnlocked { UnlockedPanel().id(events.panelVisible) }
            else {
                VStack(spacing: 12) {
                    Text("Identité is locked").font(.headline)
                    LockView(session: session, autoUnlock: false).frame(height: 300)
                }.padding(.top, 20)
            }
        }
        .frame(width: 360, height: 560)
        .background(MacWindowObserver(events: events, panel: true))
        .onChange(of: session.isUnlocked) { _, _ in events.refresh() }
    }
}

private struct UnlockedPanel: View {
    @Environment(SessionLock.self) private var session
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \IDRecord.createdAt) private var records: [IDRecord]
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var query = ""
    @State private var expanded: UUID?
    private var visible: [IDRecord] {
        records.filter {
            guard let kind = $0.kind else { return false }
            guard let payload = try? $0.payload() else { return query.isEmpty }
            return RecordSearch.matches(query, kind: kind, nickname: $0.nickname, personName: $0.person?.name, payload: payload)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            TextField("Search IDs and cards", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("panel-search").padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    group("Me", personID: nil)
                    ForEach(people) { group($0.name, personID: $0.id) }
                    if visible.isEmpty { Text("No IDs found").foregroundStyle(.secondary).padding() }
                }.padding(.horizontal, 12).padding(.bottom, 12)
            }
            Divider()
            HStack {
                Button("Open Identité") { openWindow(id: "main"); NSApp.activate() }
                Spacer()
                Button("Lock", systemImage: "lock") { session.lockNow() }
            }.buttonStyle(.borderless).padding(12)
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-menuBarPanelExpandFirst") { expanded = visible.first?.id }
        }
        #endif
        .onChange(of: visible.map(\.id)) { _, ids in
            if let expanded, !ids.contains(expanded) { self.expanded = nil }
        }
    }

    @ViewBuilder private func group(_ title: String, personID: UUID?) -> some View {
        let group = visible.filter { $0.person?.id == personID }
        if !group.isEmpty {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
            ForEach(group) { record in
                VStack(spacing: 0) {
                    Button {
                        withAnimation(reduceMotion ? .easeInOut(duration: 0.18) : Motion.card) {
                            expanded = expanded == record.id ? nil : record.id
                        }
                    } label: {
                        HStack {
                            MacRecordLabel(record: record)
                            Image(systemName: expanded == record.id ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                    .accessibilityValue(expanded == record.id ? "Expanded" : "Collapsed")
                    if expanded == record.id {
                        VStack(spacing: 0) { DetailRowsView(record: record) }
                            .padding(.horizontal, 10).background(.background, in: RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity).id(record.id)
                    }
                }
            }
        }
    }
}
