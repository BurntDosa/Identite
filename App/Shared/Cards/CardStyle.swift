import SwiftUI
import IDCore

extension Color {
    init(cardHex: String) {
        let value = UInt32(cardHex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

struct CardStyle: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let width: CGFloat
    let isLight: Bool
    var preservesColors = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: width * 0.037, style: .continuous)
        content
            .overlay {
                if scheme == .dark && isLight && !preservesColors {
                    Color.black.opacity(0.1)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isLight ? Color.black.opacity(contrast == .increased ? 0.3 : 0.08)
                                   : Color.white.opacity(contrast == .increased ? 0.4 : 0.14), lineWidth: 1)
            }
            .background {
                shape.fill(.black)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.02 : 0.12), radius: width * 0.016, y: width * 0.008)
            }
            .contentShape(shape)
    }
}
