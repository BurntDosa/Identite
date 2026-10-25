import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let width = 1024, height = Int((1024.0 / 1.586).rounded())
let columns = 32, rows = 12
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
func read(_ path: String, resize: Bool = true) -> (Int, Int, [UInt8]) {
    let image = NSImage(contentsOfFile: path)!
    let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let w = resize ? width : cg.width, h = resize ? height : cg.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { data in
        let context = CGContext(data: data.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: space, bitmapInfo: bitmapInfo)!
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, bytes)
}
var nonempty = Set<String>()
func write(_ bytes: [UInt8], to path: String) {
    if stride(from: 3, to: bytes.count, by: 4).contains(where: { bytes[$0] > 0 }) { nonempty.insert(path) }
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                        space: space, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
}
func crop(_ source: (Int, Int, [UInt8]), bounds: [Double]) -> [UInt8] {
    let (w, h, data) = source
    var result = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let u = (Double(x) / Double(width) - bounds[0]) / bounds[2]
            let v = (Double(y) / Double(height) - bounds[1]) / bounds[3]
            guard u >= 0, u < 1, v >= 0, v < 1 else { continue }
            let sx = min(w - 1, Int(u * Double(w))), sy = min(h - 1, Int(v * Double(h)))
            for channel in 0..<4 { result[(y * width + x) * 4 + channel] = data[(sy * w + sx) * 4 + channel] }
        }
    }
    return result
}

func extendOuterCorners(_ source: (Int, Int, [UInt8]), edges: [String]) -> (Int, Int, [UInt8]) {
    let (w, h, original) = source
    var data = original
    let radius = min(h, Int(ceil(Double(w) * 18 / 311)) + 2)
    for edge in edges { for row in 0..<radius {
        let y = edge == "top" ? row : h - 1 - row
        var sourceY = y
        var opaque: [Int] = []
        for inset in 0...2 {
            sourceY = edge == "top" ? y + inset : y - inset
            opaque = (0..<w).filter { original[(sourceY * w + $0) * 4 + 3] >= 254 }
            if let first = opaque.first, let last = opaque.last, first < radius * 2, last >= w - radius * 2 { break }
        }
        precondition(!opaque.isEmpty, "Outer backing must reach full opacity within its source radius")
        for x in 0..<w where original[(y * w + x) * 4 + 3] < 255 {
            let sourceX = min(opaque.last!, max(opaque.first!, x))
            let anchor = (sourceY * w + sourceX) * 4, alpha = Int(original[anchor + 3])
            precondition(alpha >= 254)
            for c in 0..<4 { data[(y * w + x) * 4 + c] = UInt8(min(255, Int(original[anchor + c]) * 255 / alpha)) }
        }
    } }
    return (w, h, data)
}
struct Job: Decodable {
    let id: String
    let masks: [String: String]
    let neutral: String?
    let source: String?
    let vectors: [String: String]?
    let bounds: [Double]?
    let clip: [Double]?
    let opacity: Double
    let mode: String
    let blurRegions: [BlurRegion]?
    let outerCorners: [String]?
}
struct BlurRegion: Decodable { let bounds: [Double]; let radius: Double }
struct Layer: Decodable {
    let asset: String
    let children: [Layer]?
    var leaves: [Layer] { children?.flatMap(\.leaves) ?? [self] }
}
struct Design: Decodable { let layers: [Layer]; let bankWidth: Double }
struct Config: Decodable { let jobs: [Job]; let designs: [String: Design] }
struct Limits: Encodable {
    let paints: [UInt8]
    let alpha: [UInt8]
    let neutralLow: [UInt8]
    let neutralHigh: [UInt8]
    let weight: Double
}
struct Coverage: Encodable {
    let paints: [String]
    let zones: [Data]
    let limits: [Limits]
    let art: Data
}
func sample(_ channels: [[UInt8]], paints: [String], bankWidth: Double) -> Coverage {
    let paintCount = paints.count
    let zones = [[0.06,0.07,bankWidth,0.13],[0.06,0.8,0.39,0.13],[0.75,0.8,0.19,0.13]]
    func grid(_ box: [Double], columns: Int, rows: Int, average: Bool = true) -> Data {
        var data = [UInt8]()
        for row in 0..<rows { for column in 0..<columns {
            let x0 = Int(ceil((box[0] + box[2]*Double(column)/Double(columns))*Double(width)))
            let x1 = Int(ceil((box[0] + box[2]*Double(column+1)/Double(columns))*Double(width)))
            let y0 = Int(ceil((box[1] + box[3]*Double(row)/Double(rows))*Double(height)))
            let y1 = Int(ceil((box[1] + box[3]*Double(row+1)/Double(rows))*Double(height)))
            for channel in channels {
                if !average {
                    // Identical stratified pixel locations in every layer preserve fine patterns instead of averaging them away.
                    let seed = UInt64(row * columns + column + 1) &* 6364136223846793005 &+ 1442695040888963407
                    let x = x0 + Int((seed >> 32) % UInt64(x1 - x0))
                    let y = y0 + Int((seed >> 16) % UInt64(y1 - y0))
                    data.append(channel[y * width + x])
                    continue
                }
                var total = 0
                for y in y0..<y1 { for x in x0..<x1 { total += Int(channel[y*width+x]) } }
                data.append(UInt8((Double(total)/Double((x1-x0)*(y1-y0))).rounded()))
            }
        } }
        return Data(data)
    }
    func limits(_ box: [Double]) -> Limits {
        var maximum = [UInt8](repeating: 0,count: paintCount), low = [UInt8](repeating: 255,count: 3)
        var high = [UInt8](repeating: 0,count: 3), minimumAlpha = 255, maximumAlpha = 0, maximumWeight = 0
        for y in Int(ceil(box[1]*Double(height)))..<Int(ceil((box[1]+box[3])*Double(height))) {
            for x in Int(ceil(box[0]*Double(width)))..<Int(ceil((box[0]+box[2])*Double(width))) {
                let i=y*width+x
                for role in 0..<paintCount { maximum[role] = max(maximum[role],channels[role][i]) }
                let neutralAlpha=Int(channels[paintCount+3][i])
                let weight=(0..<paintCount).reduce(neutralAlpha) { $0+Int(channels[$1][i]) }
                minimumAlpha=min(minimumAlpha,min(255,weight)); maximumAlpha=max(maximumAlpha,min(255,weight))
                maximumWeight=max(maximumWeight,weight)
                if neutralAlpha>0 {
                    for c in 0..<3 {
                        let value=UInt8(min(255,Int(channels[paintCount+c][i])*255/neutralAlpha))
                        low[c]=min(low[c],value); high[c]=max(high[c],value)
                    }
                }
            }
        }
        return Limits(paints: maximum,alpha:[UInt8(minimumAlpha),UInt8(maximumAlpha)],neutralLow:low,neutralHigh:high,weight:Double(maximumWeight)/255)
    }
    return Coverage(paints: paints,zones:zones.map { grid($0,columns:columns,rows:rows) },limits:zones.map(limits),
                    art:grid([0,0,1,1],columns:64,rows:40,average:false))
}
let configPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/figma/fixed-jobs.json"
let config = try JSONDecoder().decode(Config.self,from:Data(contentsOf:URL(fileURLWithPath:configPath)))
var result: [String: [String: Coverage]] = [:]
for job in config.jobs {
    autoreleasepool {
        let keys = job.masks.keys.sorted()
        if job.mode == "vector" {
            for key in keys {
                write(extendOuterCorners(read(job.vectors![key]!), edges: job.outerCorners ?? []).2, to: job.masks[key]!)
            }
        } else {
            var rgba = crop(extendOuterCorners(read(job.source!,resize:false), edges: job.outerCorners ?? []),bounds:job.bounds!)
            for y in 0..<height { for x in 0..<width {
                let i=(y*width+x)*4
                if let clip=job.clip, (Double(x)/Double(width)<clip[0] || Double(x)/Double(width)>=clip[0]+clip[2]
                    || Double(y)/Double(height)<clip[1] || Double(y)/Double(height)>=clip[1]+clip[3]) {
                    for c in 0..<4 { rgba[i+c]=0 };continue
                }
                if job.opacity < 1 {
                    for c in 0..<4 { rgba[i+c]=UInt8(min(255,(Double(rgba[i+c])/job.opacity).rounded())) }
                }
            } }
            if job.mode == "neutral" { write(rgba,to:job.neutral!) }
            else {
                // Preserve the established full-range chrome mapping, including narrow specular peaks.
                let luminances: [Double] = job.mode == "toneMap" ? stride(from: 0, to: rgba.count, by: 4).compactMap { i in
                    guard rgba[i + 3] > 10 else { return nil }
                    return (0.2126 * Double(rgba[i]) + 0.7152 * Double(rgba[i + 1]) + 0.0722 * Double(rgba[i + 2])) / Double(rgba[i + 3])
                } : []
                let low = luminances.min() ?? 0, high = luminances.max() ?? 1
                var masks = keys.map { _ in [UInt8](repeating:0,count:rgba.count) }
                for i in stride(from:0,to:rgba.count,by:4) where rgba[i+3]>0 {
                    let a=Double(rgba[i+3]), rgb=(0..<3).map { min(1,Double(rgba[i+$0])/a) }
                    let weights: [Double]
                    if job.mode == "toneMap" {
                        let luma=0.2126*rgb[0]+0.7152*rgb[1]+0.0722*rgb[2]
                        let t=sqrt(min(1,max(0,(luma-low)/max(0.01,high-low))))
                        weights=keys.map { $0 == "background" ? max(0,1-2*t) : $0 == "primary" ? 1-abs(2*t-1) : max(0,2*t-1) }
                    } else {
                        // Eight cube vertices partition alpha and reproduce the original RGB with source-paint overrides.
                        weights=keys.map { key in
                            let value=UInt32(key.dropFirst(),radix:16)!
                            return (0..<3).reduce(1.0) { total,c in total * (((value >> (16-c*8)) & 255)>0 ? rgb[c] : 1-rgb[c]) }
                        }
                    }
                    precondition(abs(weights.reduce(0,+)-1)<0.00001)
                    var alphas=weights.map { Int(floor($0*a)) }
                    let remainder=Int(a)-alphas.reduce(0,+)
                    let order=weights.indices.sorted { weights[$0]*a-Double(alphas[$0]) > weights[$1]*a-Double(alphas[$1]) }
                    for k in order.prefix(remainder) { alphas[k]+=1 }
                    precondition(alphas.reduce(0,+)==Int(a),"Recolouring changed source alpha")
                    for k in keys.indices { for c in 0..<4 { masks[k][i+c]=UInt8(alphas[k]) } }
                }
                for k in keys.indices { write(masks[k],to:job.masks[keys[k]]!) }
            }
        }
        for region in job.blurRegions ?? [] {
            precondition(job.neutral == nil, "Backdrop blur must preserve the paint partition")
            var originals = keys.map { read(job.masks[$0]!).2 }
            let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .useSoftwareRenderer: true])
            let blurred = originals.map { bytes -> [UInt8] in
                let image = CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4,
                    size: CGSize(width: width, height: height), format: .RGBA8, colorSpace: nil)
                    .clampedToExtent().applyingGaussianBlur(sigma: region.radius * Double(width) / 311)
                var result = [UInt8](repeating: 0, count: bytes.count)
                result.withUnsafeMutableBytes {
                    context.render(image, toBitmap: $0.baseAddress!, rowBytes: width * 4,
                        bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)
                }
                return result
            }
            let b = region.bounds
            for y in Int(ceil(b[1] * Double(height)))..<min(height, Int(ceil((b[1] + b[3]) * Double(height)))) {
                for x in Int(ceil(b[0] * Double(width)))..<min(width, Int(ceil((b[0] + b[2]) * Double(width)))) {
                    let i = (y * width + x) * 4
                    let oldAlpha = originals.reduce(0) { $0 + Int($1[i + 3]) }
                    var alphas = blurred.map { Int($0[i + 3]) }
                    let difference = oldAlpha - alphas.reduce(0, +)
                    precondition(abs(difference) <= keys.count, "Backdrop blur changed opaque source coverage")
                    if let largest = alphas.indices.max(by: { alphas[$0] < alphas[$1] }) { alphas[largest] += difference }
                    precondition(alphas.reduce(0, +) == oldAlpha, "Backdrop blur changed source alpha")
                    for k in keys.indices { for c in 0..<4 { originals[k][i + c] = UInt8(alphas[k]) } }
                }
            }
            for k in keys.indices { write(originals[k], to: job.masks[keys[k]]!) }
        }
        var channels = keys.map { key in
            let bytes=read(job.masks[key]!).2
            return stride(from:3,to:bytes.count,by:4).map { bytes[$0] }
        }
        if let path=job.neutral {
            let bytes=read(path).2
            for c in 0..<4 { channels.append(stride(from:c,to:bytes.count,by:4).map { bytes[$0] }) }
        } else { for _ in 0..<4 { channels.append([UInt8](repeating:0,count:width*height)) } }
        for (id,design) in config.designs where design.layers.flatMap(\.leaves).contains(where: { $0.asset == job.id }) {
            result[id,default:[:]][job.id]=sample(channels,paints:keys,bankWidth:design.bankWidth)
        }
    }
}
let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
try encoder.encode(result).write(to:URL(fileURLWithPath:"Packages/IDCore/Sources/IDCore/Resources/CardFaceCoverage.json"))
precondition(result.count==37 && result.values.reduce(0) { $0+$1.count } == config.jobs.count)
print("Sampled 37 whole designs in their actual text zones; source alpha partition assertions passed.")

try encoder.encode(nonempty.sorted()).write(to: URL(fileURLWithPath: "build/figma/nonempty-paints.json"))
