import SwiftUI
import IDCore

struct AddIDSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    kinds("Cards", kinds: [.creditCard, .debitCard])
                    kinds("IDs", kinds: IDKind.allCases.filter { ![.creditCard, .debitCard].contains($0) })
                }.padding(16)
            }
            .navigationTitle("Add ID")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }
    private func kinds(_ title: String, kinds: [IDKind]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(kinds) { kind in
                    NavigationLink {
                        RecordEditorView(kind: kind, record: nil, onSaved: { dismiss() })
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            CardFaceView(kind: kind, payload: IDPayload(values: ["name": "Your name", "bank": "Your bank"]))
                            Text(kind.displayName).font(.subheadline).foregroundStyle(.primary)
                        }
                    }.buttonStyle(PressableCardButtonStyle()).accessibilityIdentifier("add-" + kind.rawValue)
                        .accessibilityLabel(kind.displayName)
                }
            }
        }
    }
}
