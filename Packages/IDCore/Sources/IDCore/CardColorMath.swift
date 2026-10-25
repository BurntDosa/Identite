import Foundation

/// Encoded sRGB for arithmetic pixel means; CIELAB D65 for perceptual distances and tones.
struct CardRGB: Sendable {
    var channels: SIMD3<Double>

    init(_ hex: String) {
        let n = UInt32(hex.dropFirst(), radix: 16) ?? 0
        channels = SIMD3(Double((n >> 16) & 255), Double((n >> 8) & 255), Double(n & 255)) / 255
    }

    init(_ channels: SIMD3<Double>) { self.channels = channels }

    static func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func encoded(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }

    var luminance: Double {
        0.2126 * Self.linear(channels.x) + 0.7152 * Self.linear(channels.y) + 0.0722 * Self.linear(channels.z)
    }

    static func isHex(_ value: String) -> Bool {
        value.utf8.count == 7 && value.first == "#" && value.dropFirst().utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    var hex: String {
        "#" + (0..<3).map { String(format: "%02X", Int((min(1, max(0, channels[$0])) * 255).rounded())) }.joined()
    }

    var lab: SIMD3<Double> {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(channels.x), g = linear(channels.y), b = linear(channels.z)
        func f(_ v: Double) -> Double { v > 216.0 / 24389 ? cbrt(v) : (24389.0 / 27 * v + 16) / 116 }
        let x = f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047)
        let y = f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b)
        let z = f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883)
        return SIMD3(116 * y - 16, 500 * (x - y), 200 * (y - z))
    }

    init(lab: SIMD3<Double>) {
        let y = (lab.x + 16) / 116, x = lab.y / 500 + y, z = y - lab.z / 200
        func f(_ v: Double) -> Double { v > 6.0 / 29 ? v * v * v : (v - 16.0 / 116) * 108.0 / 841 }
        let xx = f(x) * 0.95047, yy = f(y), zz = f(z) * 1.08883
        func encoded(_ v: Double) -> Double { min(1, max(0, v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055)) }
        channels = SIMD3(encoded(3.2404542 * xx - 1.5371385 * yy - 0.4985314 * zz),
                         encoded(-0.9692660 * xx + 1.8760108 * yy + 0.0415560 * zz),
                         encoded(0.0556434 * xx - 0.2040259 * yy + 1.0572252 * zz))
    }

    func lightnessOffset(_ amount: Double) -> CardRGB {
        var value = lab
        value.x = min(100, max(0, value.x + amount))
        return CardRGB(lab: value)
    }

    /// Keep the primary's Lab hue and as much chroma as sRGB permits at the requested lightness.
    func tone(lightness: Double) -> CardRGB {
        let source = lab
        var low = 0.0, high = 1.0
        func candidate(_ chroma: Double) -> CardRGB {
            CardRGB(lab: SIMD3(lightness, source.y * chroma, source.z * chroma))
        }
        // Clipping moves L* or hue; reduce chroma until the round-trip preserves the requested Lab.
        for _ in 0..<16 {
            let middle = (low + high) / 2
            let expected = SIMD3(lightness, source.y * middle, source.z * middle)
            if Self.distance(candidate(middle).lab, expected) < 0.05 { low = middle } else { high = middle }
        }
        return candidate(low)
    }

    static func distance(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let d = a - b
        return sqrt(d.x * d.x + d.y * d.y + d.z * d.z)
    }
}
