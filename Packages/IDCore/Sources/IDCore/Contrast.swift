import Foundation

public enum Contrast {
    public static func ratio(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func luminance(_ hex: String) -> Double {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        precondition(digits.count == 6 && UInt32(digits, radix: 16) != nil, "Expected six-digit RGB hex")
        let value = UInt32(digits, radix: 16)!
        let components = [16, 8, 0].map { shift -> Double in
            let c = Double((value >> shift) & 255) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}
