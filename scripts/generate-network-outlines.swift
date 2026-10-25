// Run with: swift scripts/generate-network-outlines.swift (from the repo root).
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/App/Shared/Assets.xcassets")
for (name, file) in [("visa", "visa-white.imageset/visa-white.svg"), ("rupay", "rupay.imageset/rupay.png")] {
    let source = NSImage(contentsOf: root.appendingPathComponent(file))!
        .cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let radius = Double(source.width) * (name == "rupay" ? 0.02 : 0.0125), pad = Int(ceil(radius)) + 2
    let w = source.width + 2 * pad, h = source.height + 2 * pad
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    var rgba = [UInt8](repeating: 0, count: w * h * 4)
    rgba.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: space, bitmapInfo: info)!
        context.draw(source, in: CGRect(x: pad, y: pad, width: source.width, height: source.height))
    }
    let inside = (0..<w * h).map { rgba[$0 * 4 + 3] >= 128 }
    var alpha = inside.map { UInt8($0 ? 255 : 0) }
    let reach = Int(ceil(radius + 1))
    func kernel(_ r: Double) -> [(Int, Int, UInt8)] {
        (-reach...reach).flatMap { dy in (-reach...reach).compactMap { dx -> (Int, Int, UInt8)? in
            let coverage = min(1, max(0, r + 0.5 - sqrt(Double(dx * dx + dy * dy))))
            return coverage > 0 ? (dx, dy, UInt8((coverage * 255).rounded())) : nil
        } }
    }
    let symbol = kernel(radius), letters = kernel(Double(source.width) * 0.009)
    for y in 1..<h - 1 { for x in 1..<w - 1 {
        let i = y * w + x
        guard inside[i], !inside[i - 1] || !inside[i + 1] || !inside[i - w] || !inside[i + w] else { continue }
        // The small RuPay counters close with a symbol-width stroke; keep its letters a true hairline.
        for (dx, dy, value) in (name == "rupay" && x - pad < Int(Double(source.width) * 0.83) ? letters : symbol) {
            let j = (y + dy) * w + x + dx
            precondition((0..<alpha.count).contains(j))
            alpha[j] = max(alpha[j], value)
        }
    } }
    precondition(alpha.max() == 255 && alpha.prefix(w).allSatisfy { $0 == 0 })
    precondition(zip(inside, alpha).allSatisfy { !$0.0 || $0.1 == 255 })
    for i in alpha.indices { for c in 0..<4 { rgba[i * 4 + c] = alpha[i] } }
    let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
        space: space, bitmapInfo: CGBitmapInfo(rawValue: info), provider: CGDataProvider(data: Data(rgba) as CFData)!,
        decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let folder = root.appendingPathComponent(name + "-outline.imageset")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("outline.png") as CFURL,
        UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
    try """
    {"images":[{"filename":"outline.png","idiom":"universal"}],"info":{"author":"xcode","version":1},"properties":{"template-rendering-intent":"template"}}
    """.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("\(name): \(source.width) x \(source.height), padded by \(pad), crisp radius \(radius)")
}
