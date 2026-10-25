import SwiftUI
import IDCore

struct IDCardFace: View {
    let kind: IDKind
    let bank: String
    let holder: String
    let identifier: String
    let width: CGFloat

    private var subtitle: String {
        switch kind {
        case .aadhaar: "आधार"
        case .pan: "Permanent Account Number"
        case .passport: "पासपोर्ट"
        case .voterID: "मतदाता पहचान पत्र"
        case .drivingLicence: "ड्राइविंग लाइसेंस"
        case .bankAccount: bank
        case .uan: "Universal Account Number"
        default: ""
        }
    }

    var body: some View {
        // SF's cap height is about 72% of its point size.
        let typeSize = width * 0.0625
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]
            ], colors: (CardPalette.mesh(for: kind) ?? []).map { Color(cardHex: $0) })
            if kind == .passport {
                RadialGradient(colors: [Color(cardHex: "C9A45C").opacity(0.12), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: width * 0.8)
            }
            LinearGradient(colors: [.white.opacity(0.035), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: width * 0.025) {
                    VStack(alignment: .leading, spacing: width * 0.008) {
                        Text(kind.displayName).font(.system(size: typeSize, weight: .semibold)).tracking(-typeSize * 0.025)
                        Text(subtitle).font(.system(size: typeSize * 0.55)).opacity(0.75)
                    }
                    Spacer(minLength: 0)
                    if kind == .passport {
                        Text("Republic of India").font(.system(size: typeSize * 0.55, weight: .semibold))
                            .foregroundStyle(Color(cardHex: "D9B871")).fixedSize()
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: width * 0.04) {
                    Text(holder).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(identifier).monospacedDigit().fixedSize().layoutPriority(1)
                }
                .font(.system(size: typeSize * 0.75, weight: .medium))
            }
            .foregroundStyle(Color(cardHex: CardPalette.textHex(for: kind)))
            .padding(width * 0.065)
        }
    }
}
