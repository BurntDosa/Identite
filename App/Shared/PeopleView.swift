import SwiftUI
import SwiftData
import IDCore

struct PeopleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionLock.self) private var session
    @Query(sort: \Person.createdAt) private var people: [Person]
    @State private var editing: Person?
    @State private var name = ""
    @State private var showName = false
    @State private var failed = false
    @State private var nameFailed = false
    @State private var actionGeneration: Int?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(people) { person in
                        HStack {
                            Button(person.name) { editing = person; name = person.name; actionGeneration = session.authorizationGeneration; showName = true }
                                .accessibilityLabel("Rename \(person.name)")
                            Spacer()
                            Button("Delete", role: .destructive) {
                                do { try Self.delete(person, in: context, session: session) }
                                catch { context.rollback(); failed = true }
                            }.disabled(!person.canDelete)
                        }.buttonStyle(.borderless)
                    }
                    Button("Add person", systemImage: "plus") { editing = nil; name = ""; actionGeneration = session.authorizationGeneration; showName = true }
                } footer: {
                    Text("Me is always available. To delete a person, first reassign or delete their IDs.")
                }
            }.navigationTitle("People")
                #if os(iOS)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                #endif
        }
        .sheet(isPresented: $showName, onDismiss: { actionGeneration = nil }) {
            NavigationStack {
                Form {
                    SensitiveTextField(title: "Name", text: $name, input: .text,
                        canCopy: { session.isUnlocked && actionGeneration == session.authorizationGeneration })
                        .accessibilityIdentifier("person-name")
                }
                .formStyle(.grouped)
                .navigationTitle(editing == nil ? "Add person" : "Rename person")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showName = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                try Self.saveName(name, editing: editing, in: context, session: session, generation: actionGeneration)
                                showName = false
                            } catch { context.rollback(); nameFailed = true }
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .alert("Couldn't save changes. Please try again.", isPresented: $nameFailed) { Button("OK") { } }
            }
            #if os(iOS)
            .presentationDetents([.medium])
            #else
            .frame(minWidth: 320, minHeight: 180)
            #endif
        }
        .alert("Couldn't save changes. Please try again.", isPresented: $failed) { Button("OK") { } }
        .onChange(of: session.isUnlocked) { _, unlocked in
            if !unlocked { showName = false; editing = nil; name = ""; actionGeneration = nil }
        }
        .onDisappear { actionGeneration = nil }
    }
    static func saveName(_ name: String, editing: Person?, in context: ModelContext,
                         session: SessionLock, generation: Int?) throws {
        guard session.isUnlocked, generation == session.authorizationGeneration else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let editing { editing.name = trimmed } else { context.insert(Person(name: trimmed)) }
        try context.save()
    }

    static func delete(_ person: Person, in context: ModelContext, session: SessionLock) throws {
        guard session.isUnlocked, person.canDelete else { return }
        context.delete(person); try context.save()
    }
}
