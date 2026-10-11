import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

// Shared helpers for the test suite: parsing and laying out a formula body, the font's
// constants in points, and a bitmap rendering whose ink can be located by colour.

var black: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }

/// The font size most tests lay out at, so one em is 20 points.
let em: CGFloat = 20

func mathML(_ body: String, display: Bool = false, attributes: String = "") throws -> MathMLNode {
    let block = display ? " display=\"block\"" : ""
    let separator = attributes.isEmpty ? "" : " "
    let markup = "<math xmlns=\"http://www.w3.org/1998/Math/MathML\"\(block)\(separator)\(attributes)>\(body)</math>"
    return try MathMLNode.parse(xml: Data(markup.utf8))
}

func typeset(_ body: String, size: CGFloat = em, display: Bool = false, font: String? = nil) throws -> MathLayout {
    try MathLayout(mathML(body, display: display), style: MathStyle(fontSize: size, color: black, fontName: font))
}

/// A MATH constant of the platform's math font, in points at `size`.
func constant(_ keyPath: KeyPath<MathConstants, CGFloat>, size: CGFloat = em) -> CGFloat {
    MathFont.named(nil).constants[keyPath: keyPath] * size
}

func height(_ layout: MathLayout) -> CGFloat { layout.ascent + layout.descent }

/// Lays a formula out with the engine itself, for tests of a box that is not a root (the root
/// grows to cover its ink; an inner box does not).
func innerBox(_ root: MathMLNode, size: CGFloat = em, display: Bool = false, font: String? = nil) throws -> MathBox {
    let engine = LayoutEngine(fontName: font)
    let context = LayoutContext(fontSize: size, unclampedSize: size, minSize: min(size, max(8, size * 0.6)),
                                display: display, color: black)
    return try engine.layout(root, context, depth: 0)
}

func innerBox(_ body: String, size: CGFloat = em, display: Bool = false, font: String? = nil) throws -> MathBox {
    try innerBox(mathML(body, display: display), size: size, display: display, font: font)
}

// Nodes built directly, for tables of operators that would need escaping as XML.
func mo(_ text: String, _ attributes: [String: String] = [:]) -> MathMLNode { MathMLNode(name: "mo", attributes: attributes, text: text) }
func mi(_ text: String) -> MathMLNode { MathMLNode(name: "mi", text: text) }
func mn(_ text: String) -> MathMLNode { MathMLNode(name: "mn", text: text) }
func math(_ children: MathMLNode...) -> MathMLNode { MathMLNode(name: "math", children: children) }

/// A formula drawn into a bitmap, to assert where its ink is. Parts given a `mathcolor` of
/// red, lime or blue are found separately from the rest, which is black.
struct Rendering {
    enum Ink: CaseIterable { case any, black, red, green, blue }

    let layout: MathLayout
    let scale: CGFloat
    let margin: CGFloat
    private let pixelsWide: Int, pixelsHigh: Int
    /// Premultiplied RGBA, rows top-down.
    let pixels: [UInt8]
    private let found: [Ink: CGRect]

    init(_ layout: MathLayout, scale: CGFloat = 4, margin: CGFloat = 16, origin: CGPoint = .zero) {
        self.layout = layout; self.scale = scale; self.margin = margin
        let width = Int(((layout.width + 2 * margin) * scale).rounded(.up))
        let height = Int(((layout.ascent + layout.descent + 2 * margin) * scale).rounded(.up))
        pixelsWide = width; pixelsHigh = height
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        layout.draw(in: context, baselineOrigin: CGPoint(x: margin + origin.x, y: margin + layout.descent + origin.y))
        let buffer = UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: width * height * 4)
        pixels = Array(buffer)
        var boxes: [Ink: (minX: Int, minY: Int, maxX: Int, maxY: Int)] = [:]
        buffer.withMemoryRebound(to: UInt32.self) { words in
            for row in 0..<height {
                let start = row * width
                for column in 0..<width where words[start + column] != 0 {
                    let offset = (start + column) * 4
                    guard let ink = Self.classify(buffer[offset], buffer[offset + 1], buffer[offset + 2], buffer[offset + 3]) else { continue }
                    for kind in [Ink.any, ink] {
                        var box = boxes[kind] ?? (column, row, column, row)
                        box.minX = min(box.minX, column); box.maxX = max(box.maxX, column)
                        box.minY = min(box.minY, row); box.maxY = max(box.maxY, row)
                        boxes[kind] = box
                    }
                }
            }
        }
        // Bitmap rows run top-down; bounds are in points from the baseline origin, y up.
        let baselineY = margin + layout.descent + origin.y, originX = margin + origin.x
        found = boxes.mapValues { box in
            let top = CGFloat(height - box.minY) / scale, bottom = CGFloat(height - box.maxY - 1) / scale
            return CGRect(x: CGFloat(box.minX) / scale - originX, y: bottom - baselineY,
                          width: CGFloat(box.maxX - box.minX + 1) / scale, height: top - bottom)
        }
    }

    /// The colour class of a premultiplied pixel, or nil when it is too faint to count as ink.
    private static func classify(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) -> Ink? {
        guard a > 48 else { return nil }
        let red = Int(r) * 255 / Int(a), green = Int(g) * 255 / Int(a), blue = Int(b) * 255 / Int(a)
        if red > 110, red > 2 * green, red > 2 * blue { return .red }
        if green > 110, green > 2 * red, green > 2 * blue { return .green }
        if blue > 110, blue > 2 * red, blue > 2 * green { return .blue }
        return .black
    }

    /// The bounds of the ink of one colour, in points relative to the baseline origin, y up.
    func bounds(_ ink: Ink = .any) -> CGRect? { found[ink] }

    /// The colour at a point given relative to the baseline origin: straight (not
    /// premultiplied) components in 0...1.
    func color(at point: CGPoint) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let column = Int(((point.x + margin) * scale).rounded(.down))
        let row = pixelsHigh - 1 - Int(((point.y + margin + layout.descent) * scale).rounded(.down))
        guard column >= 0, column < pixelsWide, row >= 0, row < pixelsHigh else { return (0, 0, 0, 0) }
        let offset = (row * pixelsWide + column) * 4
        let alpha = CGFloat(pixels[offset + 3]) / 255
        guard alpha > 0 else { return (0, 0, 0, 0) }
        return (CGFloat(pixels[offset]) / 255 / alpha, CGFloat(pixels[offset + 1]) / 255 / alpha,
                CGFloat(pixels[offset + 2]) / 255 / alpha, alpha)
    }
}

/// The ink of `body` by colour: `.any`, and whichever of black, red, green and blue it has.
func inks(_ body: String, size: CGFloat = em, display: Bool = false, font: String? = nil) throws -> [Rendering.Ink: CGRect] {
    let rendering = Rendering(try typeset(body, size: size, display: display, font: font))
    var result: [Rendering.Ink: CGRect] = [:]
    for ink in Rendering.Ink.allCases { result[ink] = rendering.bounds(ink) }
    return result
}

/// Asserts that a layout's box covers everything it draws, the promise hosts clip by.
func assertBoxCoversInk(_ layout: MathLayout, _ message: String, tolerance: CGFloat = 0.5, rendering: Rendering? = nil,
                        file: StaticString = #filePath, line: UInt = #line) {
    guard let ink = (rendering ?? Rendering(layout)).bounds() else { return }
    XCTAssertGreaterThanOrEqual(ink.minX, -tolerance, "left of \(message)", file: file, line: line)
    XCTAssertLessThanOrEqual(ink.maxX, layout.width + tolerance, "right of \(message)", file: file, line: line)
    XCTAssertLessThanOrEqual(ink.maxY, layout.ascent + tolerance, "top of \(message)", file: file, line: line)
    XCTAssertGreaterThanOrEqual(ink.minY, -layout.descent - tolerance, "bottom of \(message)", file: file, line: line)
}

/// A known crash cannot fail a test: it ends the process and hides every other result. Such
/// tests are skipped unless MATHML_RUN_KNOWN_CRASHERS is set; `issue` is where each is tracked.
func skipKnownCrash(_ issue: String) throws {
    if ProcessInfo.processInfo.environment["MATHML_RUN_KNOWN_CRASHERS"] == nil {
        throw XCTSkip("Crashes the test process; set MATHML_RUN_KNOWN_CRASHERS=1 to run it. See \(issue)")
    }
}
