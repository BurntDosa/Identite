import SwiftUI
import IDCore

struct CardyParts: View {
    let layer: CardFaceLayer
    let colors: CardColors
    var sourcePaintOverrides: [String: String] = [:]

    private final class BundleToken {}
    static let bundle = Bundle(for: BundleToken.self)

    var body: some View {
        Canvas(colorMode: .nonLinear) { context, size in
            let rect = CGRect(origin: .zero, size: size)
            if layer.kind == "image", layer.outerCorners?.isEmpty == false {
                // Partitioned raster masks can lose a quantization level when resized; keep their backing opaque.
                let b = layer.bounds
                context.fill(Path(CGRect(x: b[0] * size.width, y: b[1] * size.height,
                    width: b[2] * size.width, height: b[3] * size.height)), with: .color(Color(cardHex: colors.primary)))
            }
            context.drawLayer { paintLayer in
                paintLayer.blendMode = .plusLighter
                for source in layer.masks.keys.sorted() {
                    let name = layer.masks[source]!
                    var paint = paintLayer
                    paint.addFilter(.colorMultiply(Color(cardHex: sourcePaintOverrides[source] ?? colors.paint(source, layer: layer))))
                    paint.draw(Image(name, bundle: Self.bundle).renderingMode(.original), in: rect)
                }
            }
            if let name = layer.neutral {
                context.draw(Image(name, bundle: Self.bundle).resizable(), in: rect)
            }
        }
        .accessibilityHidden(true)
    }
}

extension CardFaceLayer {
    var swiftUIBlendMode: BlendMode {
        switch blend {
        case "overlay": .overlay
        case "softLight": .softLight
        case "multiply": .multiply
        case "screen": .screen
        default: .normal
        }
    }
}
