import SwiftUI

enum Motion {
    static let card = Animation.spring(response: 0.35, dampingFraction: 1)
    static let flick = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let rowStagger = 0.03
    static let exitFade = Animation.easeIn(duration: 0.08)
}

struct PressableCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.8 : 1)
            .animation(configuration.isPressed ? nil : Motion.card, value: configuration.isPressed)
    }
}
