import SwiftUI
import IDCore

struct CardFaceArt: View {
    let face: CardFace
    let width: CGFloat
    var legibility: CardLegibility? = nil
    // Fidelity tests alone supply original source paints; the editor always uses its colourway.
    var sourcePaintOverrides: [String: [String: String]] = [:]
    private var height: CGFloat { width / 1.586 }

    var body: some View {
        Canvas(opaque: true, colorMode: .nonLinear) { context, _ in
            #if DEBUG
            CardRenderProbe.shared.hit(width == 100 ? "thumbnail-canvas" : "preview-canvas")
            #endif
            guard let art = context.resolveSymbol(id: 0) else { return }
            context.draw(art, at: .zero, anchor: .topLeading)
            for band in (legibility ?? CardFaceCatalog.legibility(for: face)).bands {
                let edge = band.edge == .top ? 0.0 : height
                let end = band.edge == .top ? height * CardEdgeBand.height : height * (1 - CardEdgeBand.height)
                let gradient = Gradient(stops: CardEdgeBand.stops.map {
                    .init(color: Color(cardHex: band.color).opacity(band.opacity * $0.strength), location: $0.location)
                })
                let rect = CGRect(x: 0, y: min(edge, end), width: width * band.width, height: abs(end - edge))
                context.fill(Path(rect), with: .linearGradient(gradient,
                    startPoint: CGPoint(x: 0, y: edge), endPoint: CGPoint(x: 0, y: end)))
            }
        } symbols: {
            artwork.tag(0)
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    var artwork: some View {
        ZStack {
            Color(cardHex: face.colors.primary)
            ForEach(CardFaceCatalog.paintLayers(for: face.design), id: \.asset) { layer in
                CardyParts(layer: layer, colors: face.colors, sourcePaintOverrides: sourcePaintOverrides[layer.asset] ?? [:])
                    .blendMode(layer.swiftUIBlendMode).opacity(layer.opacity)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .drawingGroup(opaque: true, colorMode: .nonLinear)
        .accessibilityHidden(true)
    }
}
