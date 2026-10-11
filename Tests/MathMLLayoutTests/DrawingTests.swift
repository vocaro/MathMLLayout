import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// `MathLayout.draw(in:baselineOrigin:)`: where the ink lands, what it does to the host's
/// context, and whether the ink the engine computes is the ink it draws.
final class DrawingTests: XCTestCase {
    /// Formulas that between them draw every kind of item: glyph runs, rules, stroked paths,
    /// dashed paths, backgrounds, assembled and drawn stretchy operators.
    private let samples: [(body: String, font: String?)] = [
        ("<mi>f</mi><mo>(</mo><mi>x</mi><mo>)</mo><mo>=</mo><mfrac><msqrt><mi>j</mi></msqrt><msup><mi>g</mi><mn>2</mn></msup></mfrac>", nil),
        ("<menclose notation=\"box circle updiagonalstrike\"><mi mathbackground=\"yellow\">x</mi></menclose><merror><mtext>e</mtext></merror>", nil),
        ("<mtable frame=\"dashed\" rowlines=\"solid\" columnlines=\"dashed\"><mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr><mtr><mtd><mi>c</mi></mtd><mtd><mi>d</mi></mtd></mtr></mtable>", nil),
        ("<mo>{</mo><mtable><mtr><mtd><mn>1</mn></mtd></mtr><mtr><mtd><mn>2</mn></mtd></mtr><mtr><mtd><mn>3</mn></mtd></mtr><mtr><mtd><mn>4</mn></mtd></mtr><mtr><mtd><mn>5</mn></mtd></mtr><mtr><mtd><mn>6</mn></mtd></mtr></mtable><mo>}</mo>", nil),
        ("<munderover><mo>∑</mo><mrow><mi>i</mi><mo>=</mo><mn>1</mn></mrow><mi>n</mi></munderover><mover><mrow><mi>a</mi><mi>b</mi><mi>c</mi></mrow><mo>→</mo></mover><munder><mrow><mi>x</mi><mi>y</mi><mi>z</mi></mrow><mo>⏟</mo></munder>", nil),
        ("<mo>[</mo><mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac><mo>]</mo><msqrt><mfrac><mi>a</mi><mi>b</mi></mfrac></msqrt><mover><mrow><mi>a</mi><mi>b</mi><mi>c</mi></mrow><mo>→</mo></mover><mroot><mi>x</mi><mn>3</mn></mroot>", "Helvetica"),
        ("<mo>⟨</mo><mfrac><mi>a</mi><mi>b</mi></mfrac><mo>|</mo><mfrac><mi>c</mi><mi>d</mi></mfrac><mo>⟩</mo><mo>{</mo><mfrac><mi>a</mi><mi>b</mi></mfrac><mo>}</mo><mover><mrow><mi>a</mi><mi>b</mi><mi>c</mi></mrow><mo>⏞</mo></mover><munder><mrow><mi>a</mi><mi>b</mi></mrow><mo>_</mo></munder>", "Helvetica"),
        ("<mtext>速度</mtext><mo>=</mo><mi>α</mi><mfrac bevelled=\"true\"><mi>a</mi><mi>b</mi></mfrac><mmultiscripts><mi>X</mi><mn>1</mn><mn>2</mn><mprescripts/><mn>3</mn><mn>4</mn></mmultiscripts>", nil),
    ]

    private func layouts(display: Bool = true) throws -> [(label: String, layout: MathLayout)] {
        try samples.map { (String($0.body.prefix(60)), try typeset($0.body, display: display, font: $0.font)) }
    }

    // MARK: Where the ink lands

    func testInkFollowsTheBaselineOrigin() throws {
        for (label, layout) in try layouts() {
            let reference = try XCTUnwrap(Rendering(layout).bounds(), label)
            for offset in [CGPoint(x: 7, y: 0), CGPoint(x: 0, y: -5), CGPoint(x: 3.5, y: 6.25), CGPoint(x: -9, y: -4.75)] {
                // Bounds are measured from the origin, so they must not move with it.
                let moved = try XCTUnwrap(Rendering(layout, margin: 30, origin: offset).bounds(), label)
                XCTAssertEqual(moved.minX, reference.minX, accuracy: 0.3, "\(label) moved by \(offset)")
                XCTAssertEqual(moved.maxX, reference.maxX, accuracy: 0.3, "\(label) moved by \(offset)")
                XCTAssertEqual(moved.minY, reference.minY, accuracy: 0.3, "\(label) moved by \(offset)")
                XCTAssertEqual(moved.maxY, reference.maxY, accuracy: 0.3, "\(label) moved by \(offset)")
            }
        }
    }

    func testInkFollowsTheContextsScale() throws {
        for (label, layout) in try layouts() {
            let reference = try XCTUnwrap(Rendering(layout, scale: 4).bounds(), label)
            for scale in [CGFloat(1), 2, 3, 8] {
                let scaled = try XCTUnwrap(Rendering(layout, scale: scale).bounds(), label)
                let pixel = 1 / scale + 0.3
                XCTAssertEqual(scaled.minX, reference.minX, accuracy: pixel, "\(label) at \(scale)x"); XCTAssertEqual(scaled.maxX, reference.maxX, accuracy: pixel, "\(label) at \(scale)x")
                XCTAssertEqual(scaled.minY, reference.minY, accuracy: pixel, "\(label) at \(scale)x"); XCTAssertEqual(scaled.maxY, reference.maxY, accuracy: pixel, "\(label) at \(scale)x")
            }
        }
    }

    /// The root's box is grown from the ink the engine computes, and hosts clip to that box. So
    /// the computed ink must cover the drawn ink, and should not be much larger than it.
    func testComputedInkIsTheDrawnInk() throws {
        var cases = samples
        cases += FormulaCorpus.all.map { ($0.markup, nil) }
        for notation in ["box", "roundedbox", "circle", "longdiv", "actuarial", "madruwb", "radical", "updiagonalarrow", "left right", "top bottom", "verticalstrike horizontalstrike"] {
            cases.append(("<menclose notation=\"\(notation)\"><mi>x</mi><mo>+</mo><mi>y</mi></menclose>", nil))
        }
        for (body, font) in cases {
            for display in [false, true] {
                let layout = try typeset(body, display: display, font: font)
                let label = "\(body.prefix(70)) display \(display)"
                guard let drawn = Rendering(layout, scale: 3).bounds() else { continue }
                // The engine's own ink, in the root's coordinates: the root shifts its content right by any left overhang.
                let inner = try innerBox(body, display: display, font: font)
                var computed = try XCTUnwrap(inner.inkBounds, label)
                computed = computed.offsetBy(dx: max(0, -computed.minX), dy: 0)
                XCTAssertTrue(computed.insetBy(dx: -0.6, dy: -0.6).contains(drawn), "drawn ink \(drawn) is outside the computed ink \(computed): \(label)")
                XCTAssertTrue(drawn.insetBy(dx: -1.5, dy: -1.5).contains(computed), "computed ink \(computed) is much larger than the drawn ink \(drawn): \(label)")
            }
        }
    }

    // MARK: Colour

    func testTheStylesColorIsUsedAsGiven() throws {
        let bar = try mathML("<mfrac linethickness=\"10px\"><mspace width=\"2em\" height=\"1ex\"/><mspace width=\"2em\" height=\"1ex\"/></mfrac>", display: true)
        let axis = constant(\.axisHeight)
        func sample(_ color: CGColor) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
            let layout = try MathLayout(bar, style: MathStyle(fontSize: em, color: color, isDisplay: true))
            return Rendering(layout).color(at: CGPoint(x: layout.width / 2, y: axis))
        }
        let opaque = try sample(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        XCTAssertEqual(opaque.red, 0.2, accuracy: 0.02); XCTAssertEqual(opaque.green, 0.4, accuracy: 0.02); XCTAssertEqual(opaque.blue, 0.8, accuracy: 0.02)
        XCTAssertEqual(opaque.alpha, 1, accuracy: 0.01)
        let translucent = try sample(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 0.5))
        XCTAssertEqual(translucent.alpha, 0.5, accuracy: 0.02); XCTAssertEqual(translucent.red, 1, accuracy: 0.03)
        let gray = try sample(CGColor(gray: 0.5, alpha: 1))
        XCTAssertEqual(gray.red, gray.green, accuracy: 0.02); XCTAssertEqual(gray.green, gray.blue, accuracy: 0.02); XCTAssertEqual(gray.alpha, 1, accuracy: 0.01)
        XCTAssertGreaterThan(gray.red, 0.3); XCTAssertLessThan(gray.red, 0.75)
        // Glyphs take it too.
        let glyph = Rendering(try MathLayout(mathML("<mi>x</mi>"), style: MathStyle(fontSize: 60, color: CGColor(srgbRed: 0, green: 0.6, blue: 0, alpha: 1))))
        XCTAssertNotNil(glyph.bounds(.green)); XCTAssertNil(glyph.bounds(.black)); XCTAssertNil(glyph.bounds(.red))
    }

    // MARK: The host's context

    func testDrawingRestoresTheGraphicsState() throws {
        let layout = try typeset(samples[1].body, display: true)
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 11, y: 13); context.scaleBy(x: 1.5, y: 1.5)
        context.clip(to: CGRect(x: 2, y: 3, width: 150, height: 90))
        let transform = context.ctm, clip = context.boundingBoxOfClipPath
        layout.draw(in: context, baselineOrigin: CGPoint(x: 20, y: 40))
        XCTAssertEqual(context.ctm, transform)
        XCTAssertEqual(context.boundingBoxOfClipPath, clip)
        // And it draws what the host's own state says: a second draw after a host colour change is unaffected by it.
        context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        layout.draw(in: context, baselineOrigin: CGPoint(x: 20, y: 40))
        XCTAssertEqual(context.ctm, transform)
    }

    /// The text matrix is not part of the graphics state that `saveGState` saves, so setting it
    /// to draw glyphs changes it for the host. A host that set its own (a flip, for text drawn
    /// with CoreText in a y-down context) must find it unchanged after a formula is drawn.
    func testDrawingPreservesTheHostsTextMatrix() throws {
        let layout = try typeset("<mi>x</mi><mo>+</mo><mfrac><mn>1</mn><mn>2</mn></mfrac>")
        let context = try XCTUnwrap(CGContext(data: nil, width: 200, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let flipped = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 5, ty: 7)
        context.textMatrix = flipped
        layout.draw(in: context, baselineOrigin: CGPoint(x: 20, y: 40))
        XCTAssertEqual(context.textMatrix, flipped, "draw(in:baselineOrigin:) changed the context's text matrix")
        // A host that places an inline formula's rows draws each row itself.
        try XCTUnwrap(layout.rows.first).draw(in: context, baselineOrigin: CGPoint(x: 20, y: 40))
        XCTAssertEqual(context.textMatrix, flipped, "Row.draw(in:baselineOrigin:) changed the context's text matrix")
    }

    func testAHostsTextMatrixDoesNotAffectTheDrawing() throws {
        // Whatever text matrix the host left behind, the formula is drawn upright in the same place.
        let layout = try typeset("<mi>f</mi><mo>=</mo><msqrt><mi>x</mi></msqrt>")
        func pixels(_ matrix: CGAffineTransform) throws -> Data {
            let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 120, bitsPerComponent: 8, bytesPerRow: 240 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.scaleBy(x: 2, y: 2)
            context.textMatrix = matrix
            layout.draw(in: context, baselineOrigin: CGPoint(x: 10, y: 25))
            return Data(bytes: try XCTUnwrap(context.data), count: 240 * 120 * 4)
        }
        let reference = try pixels(.identity)
        XCTAssertEqual(try pixels(CGAffineTransform(scaleX: 1, y: -1)), reference)
        XCTAssertEqual(try pixels(CGAffineTransform(a: 2, b: 0.5, c: 0, d: 3, tx: 40, ty: -9)), reference)
    }

    // MARK: Repeatability

    func testDrawingIsRepeatableAndThreadSafe() throws {
        for (label, layout) in try layouts() {
            let reference = Rendering(layout, scale: 2).pixels
            XCTAssertEqual(Rendering(layout, scale: 2).pixels, reference, "drawn twice: \(label)")
            // One layout drawn from many threads at once.
            let matches = UnsafeMutableBufferPointer<Bool>.allocate(capacity: 16)
            defer { matches.deallocate() }
            let shared = Flags(buffer: matches)
            DispatchQueue.concurrentPerform(iterations: 16) { index in shared.buffer[index] = Rendering(layout, scale: 2).pixels == reference }
            XCTAssertEqual(Array(matches), Array(repeating: true, count: 16), "drawn concurrently: \(label)")
        }
    }

    func testEmptyLayoutsDrawNothing() throws {
        for body in ["", "<mrow/>", "<mspace width=\"2em\" height=\"1em\"/>", "<mphantom><mfrac><mi>a</mi><mi>b</mi></mfrac></mphantom>", "<mo>&#x2062;</mo>", "<mtext> </mtext>",
                     "<mi mathcolor=\"transparent\">x</mi>", "<mtable><mtr><mtd/></mtr></mtable>"] {
            XCTAssertNil(Rendering(try typeset(body)).bounds(), body)
        }
        let empty = try typeset("")
        XCTAssertEqual([empty.width, empty.ascent, empty.descent], [0, 0, 0])
    }

    func testDrawsIntoAVectorContext() throws {
        // A PDF context records the same calls a bitmap rasterizes: printing and export.
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 400, height: 200)
        let context = try XCTUnwrap(CGContext(consumer: try XCTUnwrap(CGDataConsumer(data: data)), mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        var x: CGFloat = 10
        for (_, layout) in try layouts() { layout.draw(in: context, baselineOrigin: CGPoint(x: x, y: 100)); x += 20 }
        context.endPDFPage(); context.closePDF()
        XCTAssertGreaterThan(data.length, 1_000)
        XCTAssertEqual(String(decoding: (data as Data).prefix(5), as: UTF8.self), "%PDF-")
    }
}

private struct Flags: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<Bool>
}
