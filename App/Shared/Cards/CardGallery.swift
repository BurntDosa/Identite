#if DEBUG
import SwiftUI
import IDCore

struct CardGallery: View {
    @State private var page: Int = {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-galleryPage"), args.indices.contains(i + 1) else { return 0 }
        return max(0, Int(args[i + 1]) ?? 0)
    }()

    private struct Sample: Identifiable {
        let id: String
        let kind: IDKind
        var design: CardDesign? = nil
        var longName = false
        var payload: IDPayload {
            var p = IDPayload(values: ["name": longName ? "Venkata Subramanian Raghunathan" : "Test Person",
                "givenNames": "Test", "surname": "Person", "cardholderName": "Test Person", "accountHolder": "Test Person",
                "bank": "Sample Bank", "cardNumber": "4111111111114242", "aadhaarNumber": "234123412346",
                "panNumber": "ABCDE1234F", "passportNumber": "K1234567", "epicNumber": "ABC1234567",
                "dlNumber": "MH12-20110012345", "accountNumber": "001234567890", "uanNumber": "100123456789"])
            p[.cardDesign] = design?.rawValue
            return p
        }
    }
    private var samples: [Sample] {
        var result: [Sample] = []
        result += IDKind.allCases.filter { ![.creditCard, .debitCard].contains($0) }.map { Sample(id: $0.displayName, kind: $0) }
        result += [.init(id: "Long name", kind: .drivingLicence, longName: true)]
        for preset in CardFaceCatalog.presets.suffix(3) {
            for design in CardFaceCatalog.designs {
                let face = CardFace(design: design, colors: preset.colors, colorway: .preset, presetID: preset.id)
                result.append(Sample(id: preset.name + " · " + CardFaceCatalog.name(for: design), kind: .creditCard, design: .face(face)))
            }
        }
        return result
    }

    private var focusedIndex: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-galleryIndex"), args.indices.contains(i + 1),
              let index = Int(args[i + 1]), samples.indices.contains(index) else { return nil }
        return index
    }
    private var visibleSamples: [Sample] {
        if let focusedIndex { return [samples[focusedIndex]] }
        return Array(samples.dropFirst(page * 6).prefix(6))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: focusedIndex == nil ? 2 : 1), spacing: 20) {
                    ForEach(visibleSamples) { sample in
                        VStack(alignment: .leading, spacing: 8) {
                            CardFaceView(kind: sample.kind, payload: sample.payload, personName: "Me")
                            Text(sample.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
                Text("Fake data · \(page * 6 + 1)–\(min((page + 1) * 6, samples.count)) of \(samples.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Gallery page", selection: $page) {
                    ForEach(0..<((samples.count + 5) / 6), id: \.self) { Text(String($0 + 1)).tag($0) }
                }.pickerStyle(.menu).padding()
            }
            .navigationTitle("Card Gallery")
        }
    }
}
#endif
