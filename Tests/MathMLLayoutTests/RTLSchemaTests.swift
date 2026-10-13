import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// MathML 3 3.1.5: progression reverses, vertical shifts and child glyphs do not.
final class RTLSchemaTests: XCTestCase {
    private func space(_ width: Int, _ color: String = "red", height: Int = 10) -> String {
        "<mspace width='\(width)px' height='\(height)px' mathbackground='\(color)'/>"
    }

    private func box(_ body: String, rtl: Bool, font: String? = nil) throws -> MathBox {
        try innerBox(mathML(body, attributes: "dir='\(rtl ? "rtl" : "ltr")'"), font: font)
    }

    private func rectangles(_ box: MathBox, origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let child, let point): rectangles(child, origin: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func runs(_ box: MathBox) -> [GlyphRun] {
        box.items.flatMap { item -> [GlyphRun] in
            switch item {
            case .glyphs(let run): [run]
            case .box(let child, _): runs(child)
            default: []
            }
        }
    }

    func testSubSupAndMultiscriptSlotsHaveNumericRTLGeometry() throws {
        let base = space(40, "black")
        let scriptSpace = constant(\.spaceAfterScript)
        for name in ["msub", "msup", "msubsup", "mmultiscripts"] {
            let pair = name == "msubsup" || name == "mmultiscripts"
            let body = "<\(name)>\(base)\(space(10))\(pair ? space(20, "blue") : "")</\(name)>"
            let ltr = try box(body, rtl: false), rtl = try box(body, rtl: true)
            let expectedWidth = 40 + (pair ? 20 : 10) + scriptSpace
            XCTAssertEqual(rtl.width, expectedWidth, accuracy: 0.001, name)
            let a = rectangles(ltr), b = rectangles(rtl)
            XCTAssertEqual(a.count, b.count)
            XCTAssertEqual(b[0].minX, expectedWidth - 40, accuracy: 0.001)
            XCTAssertEqual(b[1].minX, expectedWidth - 50, accuracy: 0.001)
            if pair { XCTAssertEqual(b[2].minX, scriptSpace, accuracy: 0.001) }
            for (left, right) in zip(a, b) {
                XCTAssertEqual(right.minX, rtl.width - left.maxX, accuracy: 0.001)
                XCTAssertEqual(right.minY, left.minY, accuracy: 0.001)
            }
            XCTAssertEqual(rtl.ascent, ltr.ascent, accuracy: 0.001)
            XCTAssertEqual(rtl.descent, ltr.descent, accuracy: 0.001)
        }
        let body = "<mmultiscripts>\(base)\(space(10))<none/>\(space(20, "blue"))<none/>"
            + "<mprescripts/>\(space(30, "lime"))<none/>\(space(15, "black"))<none/></mmultiscripts>"
        let rtl = try box(body, rtl: true), r = rectangles(rtl)
        XCTAssertEqual(rtl.width, 115 + 4 * scriptSpace, accuracy: 0.001)
        // Prescript source order progresses toward the base; postscripts progress away.
        XCTAssertGreaterThan(r[0].minX, r[1].minX)
        XCTAssertGreaterThan(r[1].minX, r[2].maxX)
        XCTAssertEqual(r[2].minX, r[3].maxX, accuracy: 0.001)
        XCTAssertGreaterThan(r[3].minX, r[4].maxX)
        let ltr = try box(body, rtl: false)
        for (a, b) in zip(rectangles(ltr), r) { XCTAssertEqual(b.minX, rtl.width - a.maxX, accuracy: 0.001) }
    }

    func testRadicalIndexBarAndBevelledFractionReverseOnlyHorizontalPlacement() throws {
        for font in [nil, "Helvetica"] {
            for body in ["<msqrt>\(space(50))</msqrt>", "<mroot>\(space(50))\(space(12, "blue"))</mroot>",
                         "<mfrac bevelled='true'>\(space(30))\(space(45, "blue"))</mfrac>"] {
                let ltr = try box(body, rtl: false, font: font), rtl = try box(body, rtl: true, font: font)
                XCTAssertEqual(rtl.width, ltr.width, accuracy: 0.001)
                XCTAssertEqual(rtl.ascent, ltr.ascent, accuracy: 0.001)
                XCTAssertEqual(rtl.descent, ltr.descent, accuracy: 0.001)
                for (a, b) in zip(rectangles(ltr), rectangles(rtl)) {
                    XCTAssertEqual(b.minX, rtl.width - a.maxX, accuracy: 0.001, body)
                    XCTAssertEqual(b.minY, a.minY, accuracy: 0.001, body)
                }
                let r = rectangles(rtl)
                if body.contains("mroot") {
                    XCTAssertGreaterThan(r[0].minX, r.last!.maxX, "index is to the right of the radicand")
                    XCTAssertGreaterThan(r[0].minY, 0)
                } else if body.contains("bevelled") {
                    XCTAssertGreaterThan(r[0].minX, r[1].minX, "numerator leads on the right")
                } else { XCTAssertEqual(r.last!.minX, 0, accuracy: 0.001) }
            }
        }
    }

    /// Compare a reflected draw of the decoration alone with the RTL decoration's draw.
    /// This exercises font variants, large assemblies and stroked fallback contours.
    func testRadicalSignContoursReflectForNaturalTallAndFallbackSigns() throws {
        for font in [nil, "Helvetica"] {
            for height: CGFloat in [10, 300] {
                let engine = LayoutEngine(fontName: font)
                var context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false, color: black)
                let base = MathBox(width: 45, ascent: height)
                let ltr = engine.radical(base: base, index: nil, context)
                context.alignmentRTL = true; context.direction = .rightToLeft
                let rtl = engine.radical(base: base, index: nil, context)
                func pixels(_ box: MathBox, reflected: Bool) -> (pixels: [UInt8], width: Int) {
                    let scale: CGFloat = 4, margin: CGFloat = 4
                    let width = Int(ceil((box.width + 2 * margin) * scale))
                    let height = Int(ceil((box.height + 2 * margin) * scale))
                    let canvas = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                           bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                           bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
                    canvas.scaleBy(x: scale, y: scale)
                    canvas.translateBy(x: margin + (reflected ? box.width : 0), y: margin + box.descent)
                    if reflected { canvas.scaleBy(x: -1, y: 1) }
                    box.draw(in: canvas, at: .zero)
                    return (Array(UnsafeBufferPointer(start: canvas.data!.assumingMemoryBound(to: UInt8.self), count: width * height)), width)
                }
                let expected = pixels(ltr, reflected: true), actual = pixels(rtl, reflected: false)
                XCTAssertEqual(actual.pixels.count, expected.pixels.count)
                let mass = expected.pixels.reduce(0) { $0 + Int($1) }
                XCTAssertGreaterThan(mass, 1000)
                // Drawing font outlines and drawing glyphs differ in hinting, especially
                // on assembly stems. Permit one device pixel (0.25 pt) in either direction.
                func unmatched(_ a: [UInt8], _ b: [UInt8], width: Int) -> Int {
                    a.indices.filter { index in
                        guard a[index] > 128 else { return false }
                        for dy in -1...1 {
                            for dx in -1...1 {
                                let x = index % width + dx, neighbour = index + dy * width + dx
                                if x >= 0, x < width, b.indices.contains(neighbour), b[neighbour] > 128 { return false }
                            }
                        }
                        return true
                    }.count
                }
                XCTAssertEqual(unmatched(actual.pixels, expected.pixels, width: actual.width), 0)
                XCTAssertEqual(unmatched(expected.pixels, actual.pixels, width: expected.width), 0)
            }
        }
    }

    func testLeadingPaddingPhysicalFractionAlignmentAndEnclosureSides() throws {
        let padded = "<mpadded width='80px' lspace='10px' voffset='3px'>\(space(30))</mpadded>"
        let p = rectangles(try box(padded, rtl: true))
        XCTAssertEqual(p[0].minX, 40, accuracy: 0.001)
        XCTAssertEqual(p[0].minY, 3, accuracy: 0.001)
        for alignment in ["left", "right"] {
            let body = "<mfrac numalign='\(alignment)'>\(space(20))\(space(50, "blue"))</mfrac>"
            let ltr = rectangles(try box(body, rtl: false)), rtl = rectangles(try box(body, rtl: true))
            XCTAssertEqual(rtl[1].minX, ltr[1].minX, accuracy: 0.001, "physical numalign \(alignment)")
        }
        for notation in ["longdiv", "actuarial", "madruwb", "radical box"] {
            let body = "<menclose notation='\(notation)'>\(space(40))</menclose>"
            let ltr = try box(body, rtl: false), rtl = try box(body, rtl: true)
            XCTAssertEqual(rectangles(rtl)[0].minX, rtl.width - rectangles(ltr)[0].maxX, accuracy: 0.001)
            let a = try XCTUnwrap(ltr.inkBounds), b = try XCTUnwrap(rtl.inkBounds)
            XCTAssertEqual(b.minX, rtl.width - a.maxX, accuracy: 0.001)
            XCTAssertEqual(b.maxX, rtl.width - a.minX, accuracy: 0.001)
        }
        for notation in ["left", "right", "updiagonalstrike", "downdiagonalstrike", "updiagonalarrow"] {
            let body = "<menclose notation='\(notation)'>\(space(40))</menclose>"
            let ltr = try box(body, rtl: false), rtl = try box(body, rtl: true)
            XCTAssertEqual(ltr.inkBounds, rtl.inkBounds, "physical notation \(notation)")
        }
    }

    func testRTLFallbackFencesKeepTheirPhysicalOpeningAndClosingShapes() throws {
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}"), ("⌈", "⌉"), ("⌊", "⌋")] {
            let body = "<mfenced open='\(open)' close='\(close)'>\(space(40, height: 100))</mfenced>"
            let ltr = try typeset(body, font: "Helvetica")
            let rtl = try typeset("<mstyle dir='rtl'>\(body)</mstyle>", font: "Helvetica")
            XCTAssertEqual(rtl.width, ltr.width, accuracy: 0.001)
            XCTAssertEqual(Rendering(rtl).pixels, Rendering(ltr).pixels, "physical fences \(open)\(close)")
        }
    }

    func testArabicHebrewTokenMarksKeepTheirLocalShapedCoordinates() throws {
        for text in ["ب<malignmark/> 12 אב", "אב<malignmark/> 12 ب"] {
            let token = "<mtext mathbackground='red'>\(text)</mtext>"
            let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                                        color: black, direction: .rightToLeft, trackAlignment: true, alignmentRTL: true)
            func markedBox(_ body: String) throws -> MathBox {
                try LayoutEngine(fontName: nil).layout(mathML(body).children[0], context, depth: 0)
            }
            func mark(_ box: MathBox) throws -> CGFloat {
                try XCTUnwrap(box.alignment.first { if case .mark = $0.kind { return true }; return false }).x
            }
            let reference = try markedBox("<mstyle scriptlevel='1'>\(token)</mstyle>")
            let scripted = try markedBox("<msup>\(space(40, "black"))\(token)</msup>")
            let scriptRect = try XCTUnwrap(rectangles(scripted).last)
            XCTAssertEqual(try mark(scripted) - scriptRect.minX, try mark(reference), accuracy: 0.001)
            let rootReference = try markedBox(token)
            let radical = try markedBox("<msqrt>\(token)</msqrt>")
            let radicand = try XCTUnwrap(rectangles(radical).last)
            XCTAssertEqual(try mark(radical) - radicand.minX, try mark(rootReference), accuracy: 0.001)
        }
    }

    func testUnderOverCenteringAndPhysicalAccentAttachments() throws {
        for name in ["munder", "mover", "munderover"] {
            let body = "<\(name)>\(space(40))\(space(10))\(name == "munderover" ? space(20, "blue") : "")</\(name)>"
            let ltr = try box(body, rtl: false), rtl = try box(body, rtl: true)
            XCTAssertEqual(rectangles(ltr), rectangles(rtl), "centered \(name)")
        }
        let accent = "<mover accent='true'><mi dir='ltr'>f</mi><mo dir='ltr'>^</mo></mover>"
        let ltr = try box(accent, rtl: false), rtl = try box(accent, rtl: true)
        XCTAssertEqual(ltr.inkBounds, rtl.inkBounds, "the unchanged f keeps its physical accent attachment")
        for name in ["munder", "mover", "munderover"] {
            let body = "<\(name)><mo movablelimits='true'>∑</mo>\(space(10))\(name == "munderover" ? space(20, "blue") : "")</\(name)>"
            let inline = try box(body, rtl: true), display = try innerBox(mathML(body, display: true, attributes: "dir='rtl'"), display: true)
            let r = rectangles(inline)
            XCTAssertLessThan(r[0].maxX, inline.width, "inline movable limit follows on the left")
            XCTAssertGreaterThan(display.height, inline.height)
        }
    }

    func testArabicHebrewAndMixedLocalOverridesPreserveChildShapingAndInk() throws {
        let bodies = [
            "<msubsup><mi>س</mi><mtext mathcolor='red'>אב 12</mtext><mn>23</mn></msubsup>",
            "<mmultiscripts><mi>א</mi><mi>ب</mi><mn>2</mn><mprescripts/><mi>ج</mi><mn>3</mn></mmultiscripts>",
            "<mroot><mrow><mi>س</mi><mo>+</mo><mi>א</mi></mrow><mn>12</mn></mroot>",
            "<munderover><mo>∫</mo><mtext>אב</mtext><mtext>ب 12</mtext></munderover>",
            "<mfenced><msup><mi>س</mi><mn>2</mn></msup><msqrt><mi>א</mi></msqrt></mfenced>",
            "<mstyle dir='ltr'><msup><mi>f</mi><mn>2</mn></msup><msqrt><mi>س</mi></msqrt></mstyle>",
            "<msup dir='ltr'><mrow dir='rtl'><mi>א</mi><mi>س</mi></mrow><mn>2</mn></msup>",
            "<msqrt><mstyle dir='ltr'><mi>x</mi><mo>+</mo><msup dir='rtl'><mi>س</mi><mn>2</mn></msup></mstyle></msqrt>",
        ]
        for font in [nil, "Helvetica"] {
            for body in bodies {
                for direction in ["rtl", "ltr"] {
                    let root = try mathML(body, attributes: "dir='\(direction)'"), style = MathStyle(fontSize: em, color: black, fontName: font)
                    let layout = try MathLayout(root, style: style)
                    assertBoxCoversInk(layout, "\(direction) \(body)")
                }
            }
        }
        // Numeric text and LTR Latin letters are moved intact; Arabic is shaped exactly as
        // it would be on its own with the same inherited text direction and script level.
        let child = "<mtext mathcolor='red'>ب 12 אב</mtext>"
        let embedded = runs(try box("<msup>\(space(40))\(child)</msup>", rtl: true))
        let reference = runs(try box("<mstyle scriptlevel='1'>\(child)</mstyle>", rtl: true))
        XCTAssertEqual(embedded.count, reference.count)
        for (a, b) in zip(embedded, reference) {
            XCTAssertNil(a.reflectionWidth, "token glyphs keep their shaped orientation")
            XCTAssertEqual(a.glyphs, b.glyphs)
            XCTAssertEqual(a.positions, b.positions)
            XCTAssertEqual(CTFontCopyPostScriptName(a.font), CTFontCopyPostScriptName(b.font))
        }
        // A local schema override gives the same placement as the standalone LTR schema.
        let body = "<msup dir='ltr'>\(space(40))\(space(10))</msup>"
        XCTAssertEqual(rectangles(try box(body, rtl: true)), rectangles(try box(body, rtl: false)))
    }

    func testExplicitMarksTrackPlacedChildrenInsideSchemataAndTables() throws {
        let marked = "<mrow>\(space(13, "blue"))<malignmark/>\(space(7))</mrow>"
        let bodies = [
            "<msup>\(space(40))\(marked)</msup>",
            "<mmultiscripts>\(space(40))<none/><none/><mprescripts/>\(marked)<none/></mmultiscripts>",
            "<msqrt>\(marked)</msqrt>", "<mroot>\(space(40))\(marked)</mroot>",
            "<mfrac bevelled='true'>\(marked)\(space(40))</mfrac>",
            "<mover>\(space(40))\(marked)</mover>",
            "<mpadded width='80px' lspace='10px'>\(marked)</mpadded>",
            "<menclose notation='longdiv'>\(marked)</menclose>",
        ]
        for body in bodies {
            let node = try mathML(body).children[0]
            let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                                        color: black, direction: .rightToLeft, trackAlignment: true, alignmentRTL: true)
            let result = try LayoutEngine(fontName: nil).layout(node, context, depth: 0)
            let marks = result.alignment.filter { if case .mark = $0.kind { return true }; return false }
            XCTAssertEqual(marks.count, 1, body)
            let blue = try XCTUnwrap(rectangles(result).first { abs($0.width - 13) < 0.001 })
            XCTAssertEqual(marks.first?.x ?? -1, blue.minX, accuracy: 0.001, body)
            // Structural marks remain useful to an outer group; alignment moves the whole
            // schema rather than splitting a script, bar or enclosure from its child.
            let table = "<mtable rowspacing='0'><mtr><mtd><maligngroup/>\(body)</mtd></mtr>"
                + "<mtr><mtd><maligngroup/><mrow>\(space(13, "blue"))<malignmark/>\(space(45))</mrow></mtd></mtr></mtable>"
            let rects = rectangles(try box(table, rtl: true)).filter { abs($0.width - 13) < 0.001 }
            XCTAssertEqual(rects.count, 2)
            XCTAssertEqual(rects[0].minX, rects[1].minX, accuracy: 0.001, body)
            assertBoxCoversInk(try typeset("<mstyle dir='rtl'>\(table)</mstyle>"), body)
        }
    }

    func testRTLWrappedSchemasFitTheirReportedMinimumAndKeepInkContained() throws {
        let terms = (0..<6).map { _ in "<mi>س</mi><mo>+</mo><mi>אב</mi>" }.joined(separator: "<mo>+</mo>")
        for body in ["<msup><mrow>\(terms)</mrow><mn>2</mn></msup>", "<msqrt>\(terms)</msqrt>",
                     "<mroot><mrow>\(terms)</mrow><mn>3</mn></mroot>",
                     "<menclose notation='longdiv'>\(terms)</menclose>",
                     "<msup dir='ltr'><mrow>\(terms)</mrow><mn>2</mn></msup>"] {
            let root = try mathML(body, attributes: "dir='rtl'"), style = MathStyle(fontSize: em, color: black)
            let full = try MathLayout(root, style: style)
            let width = max(full.widestUnbreakableWidth, full.width * 0.45)
            let layout = try MathLayout(root, style: style, maximumWidth: width)
            XCTAssertLessThanOrEqual(layout.width, width + 0.01, body)
            assertBoxCoversInk(layout, body)
            let minimum = try MathLayout(root, style: style, maximumWidth: layout.widestUnbreakableWidth)
            XCTAssertLessThanOrEqual(minimum.width, layout.widestUnbreakableWidth + 0.01, body)
            assertBoxCoversInk(minimum, body)
        }
    }
}
