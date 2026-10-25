import SwiftUI
import IDCore

struct DetailRowsView: View {
    let record: IDRecord
    var isVisible = true
    var decodedPayload: IDPayload? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        if let kind = record.kind, let payload = decodedPayload ?? (try? record.payload()) {
            Section {
                ForEach(Array(fields(for: kind).filter { payload[$0.key] != nil }.enumerated()), id: \.element.id) { index, spec in
                    FieldRow(spec: spec, value: payload[spec.key] ?? "", isActive: isVisible)
                        .opacity(appeared && isVisible ? 1 : 0)
                        .offset(y: (appeared && isVisible) || reduceMotion ? 0 : 8)
                        .animation(isVisible ? .easeOut(duration: 0.18).delay(Double(index) * Motion.rowStagger) : Motion.exitFade, value: isVisible)
                }
                ForEach(payload.pfAccounts) { account in
                    FieldRow(spec: FieldSpec(.name, "Member ID · \(account.employer)"), value: account.memberID)
                }
                if !record.notes.isEmpty { FieldRow(spec: FieldSpec(.address, "Notes"), value: record.notes) }
            }.onAppear { appeared = true }
        } else {
            Text("This ID can't be opened in this version")
        }
    }
    private func fields(for kind: IDKind) -> [FieldSpec] {
        guard kind == .creditCard || kind == .debitCard else { return kind.fields }
        return [FieldKey.cardNumber, .cardExpiry, .cvv, .cardholderName, .bank].compactMap { key in
            kind.fields.first { $0.key == key }
        }
    }

}
