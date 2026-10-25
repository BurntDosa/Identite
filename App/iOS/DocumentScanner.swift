import SwiftUI
import VisionKit
import IDCore

struct ScanOutcome {
    var fields: [FieldKey: String]
    var colors: CardColors?
}

struct DocumentScanner: UIViewControllerRepresentable {
    let kind: IDKind
    var completion: (Result<ScanOutcome, any Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    static func dismantleUIViewController(_ controller: VNDocumentCameraViewController, coordinator: Coordinator) {
        coordinator.cancel(); controller.delegate = nil
    }

    @MainActor final class Coordinator: NSObject, @MainActor VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        private var recognitionTask: Task<Void, Never>?
        private var generation = 0
        private var active = true
        init(parent: DocumentScanner) { self.parent = parent }
        func cancel() { active = false; generation += 1; recognitionTask?.cancel(); recognitionTask = nil }
        func recognize(_ operation: @escaping @MainActor () async throws -> ScanOutcome) {
            guard active else { return }
            generation += 1
            let attempt = generation
            recognitionTask?.cancel()
            recognitionTask = Task {
                let result: Result<ScanOutcome, any Error>
                do { result = .success(try await operation()) }
                catch { result = .failure(error) }
                guard active, generation == attempt, !Task.isCancelled else { return }
                active = false; recognitionTask = nil
                parent.completion(result)
            }
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { cancel(); parent.dismiss() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
            guard active else { return }
            cancel()
            parent.completion(.failure(error))
        }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            recognize { [parent] in
                    var paragraphs: [String] = []
                    var addresses: [String] = []
                    var qr: AadhaarSecureQR?
                    var colors: CardColors?
                    for index in 0..<scan.pageCount {
                        try Task.checkCancellation()
                        let image = scan.imageOfPage(at: index)
                        if index == 0, parent.kind == .creditCard || parent.kind == .debitCard, let pixels = image.cgImage {
                            colors = CardColorExtractor.colors(from: pixels)
                        }
                        guard let data = image.pngData() else { throw ScanError.unreadable }
                        let result = try await TextRecognizer.shared.recognize(in: data, kind: parent.kind)
                        paragraphs += result.paragraphs
                        addresses += result.addresses
                        qr = qr ?? result.aadhaarQR
                    }
                    let fields = CardTextExtractor.extract(kind: parent.kind, paragraphs: paragraphs, detectedAddresses: addresses)
                    return ScanOutcome(fields: qr?.merging(ocr: fields) ?? fields, colors: colors)
            }
        }
    }
    private enum ScanError: Error { case unreadable }
}


struct FieldTextScanner: View {
    let label: String
    let use: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selections: [(id: UUID, text: String)] = []
    @State private var unavailable = false
    static var isSupported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                LiveTextCamera(selections: $selections, unavailable: $unavailable)
                if unavailable {
                    Text("The camera isn't available. Close this sheet and try again.").padding()
                } else {
                    Text("Tap each text block in order, then choose Use. Tap again to remove it.")
                        .font(.caption).padding()
                    ScrollView { Text(selections.map(\.text).joined(separator: "\n")).padding() }
                        .frame(maxHeight: 140).privacySensitive()
                }
            }
            .navigationTitle("Scan \(label)").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") { use(selections.map(\.text).joined(separator: "\n")); dismiss() }
                        .disabled(selections.isEmpty || unavailable)
                }
            }
        }
    }
}

private struct LiveTextCamera: UIViewControllerRepresentable {
    @Binding var selections: [(id: UUID, text: String)]
    @Binding var unavailable: Bool
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
            recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !controller.isScanning, !unavailable else { return }
        do { try controller.startScanning() }
        catch { Task { @MainActor in unavailable = true } }
    }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: LiveTextCamera
        init(parent: LiveTextCamera) { self.parent = parent }
        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item else { return }
            if parent.selections.contains(where: { $0.id == text.id }) {
                parent.selections.removeAll { $0.id == text.id }
            } else { parent.selections.append((text.id, text.transcript)) }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            parent.unavailable = true
        }
    }
}
