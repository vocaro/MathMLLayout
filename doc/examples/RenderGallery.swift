import CoreGraphics
import Foundation
import ImageIO
import MathMLLayout
import UniformTypeIdentifiers

/// Regenerates the README's PNGs from the MathML files in doc/examples/mathml on macOS.
@main
enum RenderGallery {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".", isDirectory: true)
        let inputs = root.appendingPathComponent("doc/examples/mathml", isDirectory: true)
        let outputs = root.appendingPathComponent("doc/renderings", isDirectory: true)
        try FileManager.default.createDirectory(at: outputs, withIntermediateDirectories: true)

        let scale: CGFloat = 2
        let width: CGFloat = 320
        let height: CGFloat = 120
        let style = MathStyle(fontSize: 28, color: CGColor(gray: 0, alpha: 1),
                              isDisplay: true, fontName: "STIXTwoMath-Regular")

        for name in ["quadratic", "matrix", "annotated-arrow"] {
            let input = inputs.appendingPathComponent(name).appendingPathExtension("mathml")
            let formula = try MathMLNode.parse(xml: Data(contentsOf: input))
            let layout = try MathLayout(formula, style: style)
            guard layout.width <= width - 32, layout.ascent + layout.descent <= height - 32,
                  let context = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw failure("Cannot fit or create the bitmap for \(name)")
            }
            context.scaleBy(x: scale, y: scale)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.setShouldAntialias(true)
            let origin = CGPoint(x: (width - layout.width) / 2,
                                 y: (height - layout.ascent - layout.descent) / 2 + layout.descent)
            layout.draw(in: context, baselineOrigin: origin)

            let output = outputs.appendingPathComponent(name).appendingPathExtension("png")
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw failure("Cannot create the PNG for \(name)")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else {
                throw failure("Cannot write \(output.path)")
            }
            print("Rendered \(name): \(image.width) × \(image.height) pixels")
        }
        print(ProcessInfo.processInfo.operatingSystemVersionString)
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "RenderGallery", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
