import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
import MathMLLayout
import UniformTypeIdentifiers

struct Manifest: Decodable {
    struct Case: Decodable {
        let id: String
        let markup: String
        let font: String?
        let fontSize: CGFloat?
        let maximumWidth: CGFloat?
    }
    struct Font: Decodable { let path: String; let postScriptName: String; let sha256: String }
    let cases: [Case]
    let fonts: [Font]?
}

func failure(_ message: String) -> NSError {
    NSError(domain: "MathMLExternalRender", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
func rect(_ r: CGRect) -> [String: CGFloat] {
    ["left": r.minX, "right": r.maxX, "top": -r.maxY, "bottom": -r.minY,
     "width": r.width, "height": r.height]
}

func render(_ sample: Manifest.Case, fonts: [String: String], output: URL) throws -> [String: Any] {
    guard sample.id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
        throw failure("Unsafe fixture ID: \(sample.id)")
    }
    let font = sample.font.flatMap { fonts[$0] } ?? "STIXTwoMath-Regular"
    if sample.font != nil && fonts[sample.font!] == nil { throw failure("Unknown font \(sample.font!)") }
    let node = try MathMLNode.parse(xml: Data(sample.markup.utf8))
    let size = sample.fontSize ?? 20
    let style = MathStyle(fontSize: size, color: CGColor(gray: 0, alpha: 1), fontName: font)
    let layout: MathLayout
    if let width = sample.maximumWidth { layout = try MathLayout(node, style: style, maximumWidth: width) }
    else { layout = try MathLayout(node, style: style) }
    let scale: CGFloat = 4, margin: CGFloat = 16
    let width = Int(ceil((layout.width + 2 * margin) * scale))
    let height = Int(ceil((layout.ascent + layout.descent + 2 * margin) * scale))
    // Batch reports must stay bounded even when the library legitimately permits large layouts.
    guard width > 0, height > 0, width <= 16_384, height <= 16_384, width * height <= 32_000_000 else {
        throw failure("Raster exceeds batch budget: \(width) × \(height)")
    }
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw failure("Cannot allocate bitmap")
    }
    context.scaleBy(x: scale, y: scale)
    layout.draw(in: context, baselineOrigin: CGPoint(x: margin, y: margin + layout.descent))
    func scan(_ target: CGContext) -> [String: CGRect] {
        let bytes = target.data!.assumingMemoryBound(to: UInt8.self)
        var found: [String: CGRect] = [:]
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let a = Int(bytes[offset + 3])
                guard a > 48 else { continue }
                let r = Int(bytes[offset]) * 255 / a, g = Int(bytes[offset + 1]) * 255 / a, b = Int(bytes[offset + 2]) * 255 / a
                let color = r > 110 && r > 2 * g && r > 2 * b ? "red" :
                            b > 110 && b > 2 * r && b > 2 * g ? "blue" : "other"
                let pixel = CGRect(x: CGFloat(x) / scale - margin,
                                   y: CGFloat(height - y - 1) / scale - margin - layout.descent,
                                   width: 1 / scale, height: 1 / scale)
                for key in ["all", color] { found[key] = found[key].map { $0.union(pixel) } ?? pixel }
            }
        }
        return found
    }
    let found = scan(context)
    let measuringStyle = MathStyle(fontSize: size, color: CGColor(gray: 0, alpha: 0), fontName: font)
    let geometry: MathLayout
    if let width = sample.maximumWidth { geometry = try MathLayout(node, style: measuringStyle, maximumWidth: width) }
    else { geometry = try MathLayout(node, style: measuringStyle) }
    guard [layout.width, layout.ascent, layout.descent] == [geometry.width, geometry.ascent, geometry.descent],
          let measuringContext = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw failure("Cannot measure backgrounds with unchanged layout")
    }
    measuringContext.scaleBy(x: scale, y: scale)
    geometry.draw(in: measuringContext, baselineOrigin: CGPoint(x: margin, y: margin + layout.descent))
    let rectangles = scan(measuringContext).filter { $0.key == "red" || $0.key == "blue" }
    let image = try context.makeImage().unwrap("Cannot create image")
    let filename = sample.id + ".png"
    let dest = try CGImageDestinationCreateWithURL(output.appendingPathComponent(filename) as CFURL,
                          UTType.png.identifier as CFString, 1, nil).unwrap("Cannot create PNG destination")
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { throw failure("Cannot write PNG") }
    var clipped = false
    if let ink = found["all"] {
        clipped = ink.minX < -0.5 || ink.maxX > layout.width + 0.5 || ink.maxY > layout.ascent + 0.5 || ink.minY < -layout.descent - 0.5
    }
    return ["id": sample.id, "image": filename, "requestedFont": font, "fontSize": size, "width": layout.width, "ascent": layout.ascent,
            "descent": layout.descent, "ink": found.mapValues(rect), "rectangles": rectangles.mapValues(rect), "clipped": clipped,
            "widestUnbreakableWidth": layout.widestUnbreakableWidth,
            "rows": layout.rows.map { ["width": $0.width, "ascent": $0.ascent, "descent": $0.descent] },
            "reading": node.accessibilityDescription]
}

extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw failure(message) }; return value
    }
}

@main enum Main {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw failure("Usage: MathMLExternalRender manifest.json output-directory")
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1]), root = input.deletingLastPathComponent()
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let inputData = try Data(contentsOf: input)
        let manifest = try JSONDecoder().decode(Manifest.self, from: inputData)
        guard Set(manifest.cases.map(\.id)).count == manifest.cases.count else { throw failure("Duplicate IDs") }
        var fonts: [String: String] = [:]
        for font in manifest.fonts ?? [] {
            let url = root.appendingPathComponent(font.path)
            let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            guard hash == font.sha256 else { throw failure("Font hash mismatch: \(font.path)") }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                let code = error.map { CFErrorGetCode($0.takeRetainedValue()) }
                guard code == CTFontManagerError.alreadyRegistered.rawValue else { throw failure("Font registration failed: \(font.path)") }
            }
            let loaded = CTFontCreateWithName(font.postScriptName as CFString, 10, nil)
            guard CTFontCopyPostScriptName(loaded) as String == font.postScriptName else { throw failure("Font substitution: \(font.path)") }
            fonts[font.path] = font.postScriptName
        }
        var results: [[String: Any]] = []
        for sample in manifest.cases {
            do { results.append(try render(sample, fonts: fonts, output: output)) }
            catch { results.append(["id": sample.id, "error": String(describing: error)]) }
        }
        let report: [String: Any] = ["engine": "MathMLLayout", "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "manifestSHA256": SHA256.hash(data: inputData).map { String(format: "%02x", $0) }.joined(),
            "fonts": (manifest.fonts ?? []).map { ["path": $0.path, "postScriptName": $0.postScriptName, "sha256": $0.sha256] },
            "fontSizeDefault": 20, "scale": 4, "margin": 16, "coordinates": "points, baseline-relative, y-down",
            "boxMeaning": "root ink-covering bounds; rows use layout advances", "cases": results]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("mathmllayout.json"))
        print("Rendered \(results.count) cases to \(output.path)")
    }
}
