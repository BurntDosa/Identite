import SwiftUI
import IDCore

struct MacDetailView: View {
    let record: IDRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Form {
            Section {
                CardFaceView(record: record).frame(maxWidth: 440).frame(maxWidth: .infinity)
                    .padding(.vertical, 12).listRowBackground(Color.clear)
                    .id(record.id)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
            }
            DetailRowsView(record: record).id(record.id)
        }
        .formStyle(.grouped)
        .animation(reduceMotion ? .easeInOut(duration: 0.18) : Motion.card, value: record.id)
        .navigationTitle(record.nickname.isEmpty ? record.kind?.displayName ?? "ID" : record.nickname)
    }
}
