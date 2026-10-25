import SwiftUI
import SwiftData
import IDCore

struct MacRootView: View {
    let events: MacSessionEvents
    #if DEBUG
    @Environment(\.openWindow) private var openWindow
    #endif
    @Environment(SessionLock.self) private var session
    @State private var hasUnlocked = false
    @Query private var records: [IDRecord]
    var body: some View {
        Group {
            if session.isUnlocked { MacLibraryView(records: records) }
            else { LockView(session: session, autoUnlock: !hasUnlocked) }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(MacWindowObserver(events: events))
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("-menuBarPanelPreview") { openWindow(id: "menu-bar-preview") }
        }
        #endif
        .onChange(of: session.isUnlocked) { _, unlocked in
            if unlocked { hasUnlocked = true }
            events.refresh()
        }
    }
}

private struct MacLibraryView: View {
    let records: [IDRecord]
    @Environment(SessionLock.self) private var session
    @Environment(\.modelContext) private var context
    @Environment(\.reminderScheduler) private var reminders
    @State private var selection: UUID?
    @State private var add = false
    @State private var edit = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var searchFocused = false
    private var selected: IDRecord? { records.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            MacSidebar(records: records, selection: $selection, searchFocused: $searchFocused) { confirmDelete = true }
                .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 400)
        } detail: {
            if let selected { MacDetailView(record: selected) }
            else if records.isEmpty {
                ContentUnavailableView {
                    Label("Add your first ID", systemImage: "person.text.rectangle")
                } actions: {
                    Button("Add ID") { add = true }.buttonStyle(.glassProminent)
                }
            } else { ContentUnavailableView("Select an ID", systemImage: "person.text.rectangle") }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Add ID", systemImage: "plus") { add = true }.help("Add ID (⌘N)")
                Button("Edit", systemImage: "pencil") { edit = true }.disabled(selected == nil).help("Edit (⌘E)")
                Button("Delete", systemImage: "trash") { confirmDelete = true }.disabled(selected == nil).help("Delete ID")
                Button("Lock", systemImage: "lock") { session.lockNow() }.help("Lock (⌘L)")
            }
        }
        .focusedSceneValue(\.idActions, add || edit ? nil : MacActions(
            add: { add = true }, edit: selected == nil ? nil : { edit = true },
            delete: selected == nil || searchFocused ? nil : { confirmDelete = true }))
        .sheet(isPresented: $add) { AddIDSheet() }
        .sheet(isPresented: $edit) {
            if let selected, let kind = selected.kind {
                NavigationStack { RecordEditorView(kind: kind, record: selected) }.frame(width: 600, height: 700)
            }
        }
        .confirmationDialog("Delete this ID?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete ID", role: .destructive) {
                guard let selected, session.isUnlocked else { return }
                let id = selected.id
                context.delete(selected)
                do { try context.save(); reminders?.remove(recordID: id); selection = nil }
                catch { context.rollback(); deleteFailed = true }
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("This permanently deletes the ID from your devices.") }
        .alert("Couldn't delete this ID. Please try again.", isPresented: $deleteFailed) { Button("OK") { } }
    }
}
