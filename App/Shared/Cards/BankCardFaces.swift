import SwiftUI
import IDCore

enum BankCardFaces {
    static func resolvedFace(for design: CardDesign) -> CardFace {
        if case .face(let face) = design { return face }
        return CardFaceCatalog.fallback(for: design.rawValue)
    }
}

extension CardDesign {
    func faceDesign(forBank bank: String) -> CardDesign {
        .face(BankCardFaces.resolvedFace(for: self))
    }
}

struct BankCardFace: View {
    let design: CardDesign
    let kind: IDKind
    let bank: String
    let network: CardNetwork
    let identifier: String
    let width: CGFloat
    private var height: CGFloat { width / 1.586 }

    var body: some View {
        Group {
            switch design.faceDesign(forBank: bank) {
            case .face(let value): fixed(value)
            case .hsbcLivePlus, .hdfcPixelPlay, .hdfcMillennia:
                fixed(BankCardFaces.resolvedFace(for: design))
            }
        }
        .frame(width: width, height: height)
    }

    private func fixed(_ face: CardFace) -> some View {
        let legibility = CardFaceCatalog.legibility(for: face)
        return ZStack(alignment: .topLeading) {
            CardFaceArt(face: face, width: width, legibility: legibility)
            text(bank, zone: .bank, face: face, ink: legibility[.bank].ink)
            text(identifier, zone: .last4, face: face, ink: legibility[.last4].ink)
            let box = CardTextZone.network.bounds(for: face.design)
            NetworkMark(network: network, isLight: legibility[.network].ink == "#000000")
                .frame(width: width * 0.15, height: width * 0.06)
                .frame(width: width * box.width, height: height * box.height, alignment: .trailing)
                .offset(x: box.x * width, y: box.y * height)
        }
    }

    private func text(_ value: String, zone: CardTextZone, face: CardFace, ink: String) -> some View {
        let box = zone.bounds(for: face.design)
        return Text(value)
            .font(.system(size: width * (zone == .bank ? 0.0625 : 0.046875), weight: zone == .bank ? .semibold : .medium))
            .monospacedDigit()
            .tracking(zone == .bank ? -width * 0.0015 : 0)
            .foregroundStyle(Color(cardHex: ink))
            .lineLimit(1).truncationMode(.tail)
            .frame(width: box.width * width, height: box.height * height, alignment: .leading)
            .clipped()
            .offset(x: box.x * width, y: box.y * height)
    }

}

struct NetworkMark: View {
    let network: CardNetwork
    let isLight: Bool
    var body: some View {
        Group {
            switch network {
            case .visa:
                outlined(isLight ? "visa-blue" : "visa-white", mask: "visa-outline", aspect: 1000 / 324.68, inset: 27 / 2000)
            case .mastercard: Image("mastercard", bundle: CardyParts.bundle).renderingMode(.original).resizable().scaledToFit()
            case .rupay:
                outlined(isLight ? "rupay" : "rupay-white", mask: "rupay-outline", aspect: 600 / 155, inset: 14 / 600)
            case .other: EmptyView()
            default:
                GeometryReader { g in
                    Text(network.rawValue).font(.system(size: g.size.width * 0.19, weight: .semibold)).minimumScaleFactor(0.6)
                        .foregroundStyle(isLight ? Color.black : .white)
                        .frame(width: g.size.width, height: g.size.height)
                }
            }
        }
        .accessibilityLabel(network.rawValue)
    }

    private func outlined(_ name: String, mask: String, aspect: Double, inset: Double) -> some View {
        GeometryReader { geometry in
            let w = min(geometry.size.width, geometry.size.height * aspect), h = w / aspect
            Image(name, bundle: CardyParts.bundle).renderingMode(.original).resizable()
                .frame(width: w, height: h)
                .background {
                    // Crisp circular dilation; smaller letter strokes preserve counters at wallet size.
                    Image(mask, bundle: CardyParts.bundle).renderingMode(.template).resizable()
                        .foregroundStyle(isLight ? Color.black : .white)
                        .frame(width: w * (1 + 2 * inset), height: h + 2 * w * inset)
                }
                // Keep the outer contour inside the network box used by the contrast model.
                .offset(x: -w * inset)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

