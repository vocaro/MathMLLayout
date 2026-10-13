import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Compiled alongside the current library sources by generate.py, avoiding stale build products.
@main
struct SpeechReviewReadings {
    struct Sample: Decodable {
        let id: String
        let markup: String
        let languages: [String]
        let image: Bool
    }

    static func main() throws {
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: input))
        var readings: [String: [String: String]] = [:]
        let fontName = "STIXTwoMath-Regular"
        let font = CTFontCreateWithName(fontName as CFString, 20, nil)
        guard CTFontCopyPostScriptName(font) as String == fontName else {
            throw NSError(domain: "SpeechReview", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Install STIX Two Math to render the review examples."])
        }
        for sample in samples {
            let node = try MathMLNode.parse(xml: Data(sample.markup.utf8))
            readings[sample.id] = Dictionary(uniqueKeysWithValues: sample.languages.map { language in
                (language, node.accessibilityDescription(locale: Locale(identifier: language)).text)
            })
            guard sample.image else { continue }
            let layout = try MathLayout(node, style: MathStyle(fontSize: 24,
                color: CGColor(gray: 0, alpha: 1), fontName: fontName))
            let margin: CGFloat = 12, scale: CGFloat = 2
            let width = Int(ceil((layout.width + 2 * margin) * scale))
            let height = Int(ceil((layout.ascent + layout.descent + 2 * margin) * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw NSError(domain: "SpeechReview", code: 2)
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            layout.draw(in: context, baselineOrigin: CGPoint(x: margin, y: margin + layout.descent))
            let path = output.appendingPathComponent("images/\(sample.id).png")
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw NSError(domain: "SpeechReview", code: 3)
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "SpeechReview", code: 4) }
        }
        try JSONSerialization.data(withJSONObject: readings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            .write(to: output.appendingPathComponent("readings.json"))
        print("Generated \(samples.count) parsed examples and \(readings.values.reduce(0) { $0 + $1.count }) locale readings.")
    }
}
