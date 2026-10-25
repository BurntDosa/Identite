import CoreGraphics
import Foundation

public enum CardColorExtractor {
    /// The image and its downsampled pixels remain local to this call.
    public static func colors(from image: CGImage) -> CardColors? {
        colors(from: image) { data in
            CGContext(data: data, width: 64, height: 40, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        }
    }

    static func colors(from image: CGImage, makeContext: (UnsafeMutableRawPointer?) -> CGContext?) -> CardColors? {
        let width = 64, height = 40
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = makeContext(buffer.baseAddress) else { return false }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        let pixels = stride(from: 0, to: bytes.count, by: 4).map {
            CardRGB(SIMD3(Double(bytes[$0]), Double(bytes[$0 + 1]), Double(bytes[$0 + 2])) / 255).lab
        }

        // Farthest-point seeds prevent small but distinct card colours being missed.
        var centers = [pixels[(image.width &* 31 &+ image.height) % pixels.count]]
        while centers.count < 5 {
            let candidate = pixels.max { a, b in
                centers.map { CardRGB.distance(a, $0) }.min()! < centers.map { CardRGB.distance(b, $0) }.min()!
            }!
            if centers.contains(where: { CardRGB.distance($0, candidate) < 0.001 }) { break }
            centers.append(candidate)
        }
        var counts = [Int](repeating: 0, count: centers.count)
        for _ in 0..<24 {
            counts = [Int](repeating: 0, count: centers.count)
            var sums = [SIMD3<Double>](repeating: .zero, count: centers.count)
            for pixel in pixels {
                let index = centers.indices.min { CardRGB.distance(pixel, centers[$0]) < CardRGB.distance(pixel, centers[$1]) }!
                counts[index] += 1; sums[index] += pixel
            }
            let next = centers.indices.map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : centers[$0] }
            let converged = zip(centers, next).allSatisfy { CardRGB.distance($0, $1) < 0.01 }
            centers = next
            if converged { break }
        }

        struct Cluster {
            var center: SIMD3<Double>
            var count: Int
        }
        var clusters = centers.indices.filter { counts[$0] > 0 }.map { Cluster(center: centers[$0], count: counts[$0]) }
        while let pair = clusters.indices.lazy.compactMap({ i -> (Int, Int)? in
            clusters.indices.dropFirst(i + 1).first { CardRGB.distance(clusters[i].center, clusters[$0].center) < 10 }.map { (i, $0) }
        }).first {
            let a = clusters[pair.0], b = clusters[pair.1], total = a.count + b.count
            clusters[pair.0] = Cluster(center: (a.center * Double(a.count) + b.center * Double(b.count)) / Double(total), count: total)
            clusters.remove(at: pair.1)
        }
        clusters.sort {
            if $0.count != $1.count { return $0.count > $1.count }
            for i in 0..<3 where $0.center[i] != $1.center[i] { return $0.center[i] < $1.center[i] }
            return false
        }
        var colors = clusters.prefix(3).map { CardRGB(lab: $0.center) }
        let primary = colors[0]
        let direction = primary.lab.x > 50 ? -1.0 : 1.0
        for step in [18.0, 36, -18, -36, 54, -54, 72, -72] where colors.count < 3 {
            let candidate = primary.lightnessOffset(step * direction)
            if colors.allSatisfy({ CardRGB.distance($0.lab, candidate.lab) >= 10 }) { colors.append(candidate) }
        }
        return CardColors(primary: colors[0].hex, secondary: colors[1].hex, accent: colors[2].hex)
    }
}
