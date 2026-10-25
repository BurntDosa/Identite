import Vision
import UIKit
import IDCore

struct RecognizedDocument: Sendable {
    var paragraphs: [String] = []
    var addresses: [String] = []
    var aadhaarQR: AadhaarSecureQR?
}

actor TextRecognizer {
    static let shared = TextRecognizer()
    func recognize(in data: Data, kind: IDKind) async throws -> RecognizedDocument {
        var result = RecognizedDocument()
        var barcodeRequest = DetectBarcodesRequest()
        barcodeRequest.symbologies = [.qr]
        if let barcodes = try? await barcodeRequest.perform(on: data), kind == .aadhaar {
            result.aadhaarQR = barcodes.compactMap { $0.payloadString.flatMap(AadhaarSecureQR.decode) }.first
        }
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = false
        if let documents = try? await request.perform(on: data) {
            for document in documents {
                result.paragraphs += document.document.paragraphs.map(\.transcript)
                result.addresses += document.document.text.detectedData.compactMap {
                    if case .postalAddress(let address) = $0.match.details { return address.fullAddress }
                    return nil
                }
            }
        }
        if result.paragraphs.isEmpty {
            do { result.paragraphs = [try lines(in: data).joined(separator: "\n")] }
            catch { if result.aadhaarQR == nil { throw error } }
        }
        return result
    }
    func lines(in data: Data) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
