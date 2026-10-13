import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// Elementary math (MathML 3, 3.6): `mstack`, `mlongdiv` and their rows, carries and lines.
/// Geometry is read from the box tree: where each glyph, rule and stroke is drawn, in points
/// from the stack's baseline origin, y up.
final class ElementaryMathTests: MathTestCase {
    private struct Glyph {
        /// The font's name for it: "one", "comma", "plus".
        var name: String
        var size: CGFloat
        var origin: CGPoint
        var advance: CGFloat
        var ink: CGRect
        var color: CGColor
        var right: CGFloat { origin.x + advance }
        var middle: CGFloat { origin.x + advance / 2 }
    }

    /// A line or a curve of a stroked path.
    private struct Segment {
        var from: CGPoint, to: CGPoint
        var isCurve: Bool
        var color: CGColor
    }

    private struct Drawing {
        var box = MathBox()
        /// Top row first, then left to right.
        var glyphs: [Glyph] = []
        var images: [CGRect] = []
        var rules: [(rect: CGRect, color: CGColor)] = []
        var segments: [Segment] = []

        func all(_ name: String) -> [Glyph] { glyphs.filter { $0.name == name } }

        func glyph(_ name: String, _ index: Int = 0, file: StaticString = #filePath, line: UInt = #line) throws -> Glyph {
            let found = all(name)
            return try XCTUnwrap(found.indices.contains(index) ? found[index] : nil, "no \(name) #\(index)", file: file,
                                 line: line)
        }

        /// The glyphs on one baseline, left to right; row 0 is the top one.
        func row(_ index: Int) -> [Glyph] {
            let baselines = Set(glyphs.map { ($0.origin.y * 100).rounded() }).sorted(by: >)
            guard baselines.indices.contains(index) else { return [] }
            return glyphs.filter { ($0.origin.y * 100).rounded() == baselines[index] }
        }

        var horizontals: [CGRect] { rules.map(\.rect).filter { $0.width > $0.height } }
        var verticals: [CGRect] { rules.map(\.rect).filter { $0.height > $0.width } }
    }

    private let em: CGFloat = 20
    private var constants: MathConstants { MathFont.named(nil).constants }

    /// The element's own box, as the engine hands it to the row around it.
    private func stackBox(_ element: MathMLNode, images: MathImageProvider? = nil) throws -> MathBox {
        let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 0.6 * em, display: false, color: black)
        let engine = LayoutEngine(fontName: nil)
        engine.imageProvider = images
        return try engine.layout(element, context, depth: 0)
    }

    private func stackBox(_ body: String) throws -> MathBox { try stackBox(node(body).children[0]) }

    private func drawing(_ element: MathMLNode, images: MathImageProvider? = nil) throws -> Drawing {
        var drawing = Drawing(box: try stackBox(element, images: images))
        collect(drawing.box, at: .zero, into: &drawing)
        drawing.glyphs.sort { ($0.origin.y, -$0.origin.x) > ($1.origin.y, -$1.origin.x) }
        return drawing
    }

    private func drawing(_ body: String, images: MathImageProvider? = nil) throws -> Drawing {
        try drawing(node(body).children[0], images: images)
    }

    private func collect(_ box: MathBox, at origin: CGPoint, into drawing: inout Drawing) {
        func moved(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + origin.x, y: point.y + origin.y) }
        for item in box.items {
            if case .glyphs(let run) = item {
                var advances = [CGSize](repeating: .zero, count: run.glyphs.count)
                var rects = [CGRect](repeating: .zero, count: run.glyphs.count)
                CTFontGetAdvancesForGlyphs(run.font, .horizontal, run.glyphs, &advances, run.glyphs.count)
                CTFontGetBoundingRectsForGlyphs(run.font, .horizontal, run.glyphs, &rects, run.glyphs.count)
                for (index, glyph) in run.glyphs.enumerated() {
                    let at = moved(run.positions[index])
                    drawing.glyphs.append(Glyph(name: CTFontCopyNameForGlyph(run.font, glyph) as String? ?? "",
                                                size: CTFontGetSize(run.font), origin: at, advance: advances[index].width,
                                                ink: rects[index].offsetBy(dx: at.x, dy: at.y), color: run.color))
                }
            } else if case .image(_, let rect, _) = item {
                drawing.images.append(rect.offsetBy(dx: origin.x, dy: origin.y))
            } else if case .rect(let rect, let color) = item {
                drawing.rules.append((rect.offsetBy(dx: origin.x, dy: origin.y), color))
            } else if case .path(let path, _, let color, _) = item {
                var current = CGPoint.zero
                path.applyWithBlock { element in
                    let points = element.pointee.points
                    switch element.pointee.type {
                    case .moveToPoint: current = moved(points[0])
                    case .addLineToPoint:
                        drawing.segments.append(Segment(from: current, to: moved(points[0]), isCurve: false, color: color))
                        current = moved(points[0])
                    case .addQuadCurveToPoint:
                        drawing.segments.append(Segment(from: current, to: moved(points[1]), isCurve: true, color: color))
                        current = moved(points[1])
                    default: break
                    }
                }
            } else if case .box(let inner, let point) = item {
                collect(inner, at: moved(point), into: &drawing)
            }
        }
    }

    private func equal(_ first: CGFloat, _ second: CGFloat, _ message: String = "", file: StaticString = #filePath,
                       line: UInt = #line) {
        XCTAssertEqual(first, second, accuracy: 0.01, message, file: file, line: line)
    }

    /// The box covers everything it draws, and so does the formula around it once drawn.
    private func assertCoversInk(_ body: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let box = try stackBox(body)
        let bounds = try XCTUnwrap(box.inkBounds, body, file: file, line: line)
        XCTAssertGreaterThanOrEqual(bounds.minX, -0.01, body, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxX, box.width + 0.01, body, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxY, box.ascent + 0.01, body, file: file, line: line)
        XCTAssertGreaterThanOrEqual(bounds.minY, -box.descent - 0.01, body, file: file, line: line)
        let result = try layout(body)
        let drawn = try XCTUnwrap(ink(result), body, file: file, line: line)
        XCTAssertGreaterThanOrEqual(drawn.minX, -0.5, body, file: file, line: line)
        XCTAssertLessThanOrEqual(drawn.maxX, result.width + 0.5, body, file: file, line: line)
        XCTAssertLessThanOrEqual(drawn.maxY, result.ascent + 0.5, body, file: file, line: line)
        XCTAssertGreaterThanOrEqual(drawn.minY, -result.descent - 0.5, body, file: file, line: line)
    }

    // MARK: Direction in elementary math

    /// MathML 3's elementary exception: columns and carries remain LTR in RTL contexts.
    private func sameDrawing(_ lhs: String, _ rhs: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let a = try drawing(lhs), b = try drawing(rhs)
        equal(a.box.width, b.box.width, file: file, line: line)
        equal(a.box.ascent, b.box.ascent, file: file, line: line)
        equal(a.box.descent, b.box.descent, file: file, line: line)
        XCTAssertEqual(a.glyphs.map(\.name), b.glyphs.map(\.name), file: file, line: line)
        for (x, y) in zip(a.glyphs, b.glyphs) {
            equal(x.origin.x, y.origin.x, file: file, line: line)
            equal(x.origin.y, y.origin.y, file: file, line: line)
        }
        XCTAssertEqual(a.rules.map(\.rect), b.rules.map(\.rect), file: file, line: line)
        XCTAssertEqual(a.segments.count, b.segments.count, file: file, line: line)
        for (x, y) in zip(a.segments, b.segments) {
            XCTAssertEqual(x.from, y.from, file: file, line: line)
            XCTAssertEqual(x.to, y.to, file: file, line: line)
            XCTAssertEqual(x.isCurve, y.isCurve, file: file, line: line)
        }
    }

    func testRTLColumnsKeepPhysicalAlignmentPositionsAndDecimalPoint() throws {
        for alignment in MathStackAlignment.allCases {
            for charAlignment in ["left", "center", "right"] {
                let body = "<msgroup position='1' shift='-1'><msrow><mo>+</mo><none/><mn>12.3</mn></msrow>"
                    + "<msrow position='-1'><mn>4.56</mn></msrow><msline length='3' position='1' "
                    + "leftoverhang='0.3em' rightoverhang='0.1em'/></msgroup>"
                let attrs = "stackalign='\(alignment.rawValue)' charalign='\(charAlignment)'"
                try sameDrawing("<mstack \(attrs) dir='ltr'>\(body)</mstack>", "<mstack \(attrs) dir='rtl'>\(body)</mstack>")
                try assertCoversInk("<mstack \(attrs) dir='rtl'>\(body)</mstack>")
            }
        }
        let arabic = "<mstack><mn>١٢٫٣</mn><mn>٤٫٥٦</mn><msline/></mstack>"
        try sameDrawing("<mstyle dir='rtl'>\(arabic)</mstyle>", "<mstyle dir='ltr'>\(arabic)</mstyle>")
        let decimal = "<mstack><mn>12,3</mn><msrow position='1'><mn>4,56</mn></msrow></mstack>"
        try sameDrawing("<math dir='rtl' decimalpoint=','>\(decimal)</math>",
                        "<math dir='ltr' decimalpoint=','>\(decimal)</math>")
    }

    func testRTLCompassCarriesCrossoutsAndOverhangsKeepPhysicalSides() throws {
        for location in CarryLocation.allCases {
            let body = "<mscarries position='1' location='\(location.rawValue)' "
                + "crossout='updiagonalstrike downdiagonalstrike verticalstrike horizontalstrike'>"
                + "<mn>1</mn><mscarry location='e' crossout='none'><mn>2</mn></mscarry></mscarries>"
                + "<mn>345</mn><msline leftoverhang='0.7em' rightoverhang='0.2em'/>"
            try sameDrawing("<mstack dir='ltr'>\(body)</mstack>", "<mstack dir='rtl'>\(body)</mstack>")
            try assertCoversInk("<mstack dir='rtl'>\(body)</mstack>")
        }
    }

    func testEveryDivisionFrameKeepsOperandsAndSeparatorsOnNamedSidesInRTL() throws {
        for frame in LongDivision.allCases {
            let body = "<mn>3</mn><mn>24</mn><mn>72</mn><msgroup shift='-1'><mn>6</mn>"
                + "<msline length='1'/><mn>12</mn><mn>12</mn><msline/><mn>0</mn></msgroup>"
            let attrs = "longdivstyle='\(frame.rawValue)'"
            try sameDrawing("<mlongdiv \(attrs) dir='ltr'>\(body)</mlongdiv>",
                            "<mlongdiv \(attrs) dir='rtl'>\(body)</mlongdiv>")
            try assertCoversInk("<mlongdiv \(attrs) dir='rtl'>\(body)</mlongdiv>")
        }
    }

    /// Mixed bidi tokens use their base direction inside a single physical grid column.
    func testArabicHebrewTokenAndCarryDirectionsInheritAndOverride() throws {
        for text in ["+ 12 אב", "+ 12 العربية"] {
            let token = "<mtext>\(text)</mtext>"
            try sameDrawing("<math dir='rtl'><mstack><msgroup><msrow>\(token)</msrow></msgroup></mstack></math>",
                            "<mstack><mtext dir='rtl'>\(text)</mtext></mstack>")
            try sameDrawing("<mstack dir='rtl'><msrow dir='ltr'>\(token)</msrow></mstack>",
                            "<mstack dir='ltr'>\(token)</mstack>")
            try sameDrawing("<mstack dir='rtl'><mstyle dir='ltr'>\(token)</mstyle></mstack>",
                            "<mstack dir='ltr'>\(token)</mstack>")
            try sameDrawing("<mstack dir='rtl'><mscarries><mscarry dir='ltr'>\(token)</mscarry></mscarries><mn>1</mn></mstack>",
                            "<mstack dir='ltr'><mscarries><mscarry>\(token)</mscarry></mscarries><mn>1</mn></mstack>")
            let rtl = try drawing("<mstack dir='rtl'>\(token)</mstack>")
            let ltr = try drawing("<mstack dir='ltr'>\(token)</mstack>")
            XCTAssertNotEqual(rtl.glyphs.map(\.name), ltr.glyphs.map(\.name), "base direction affects mixed token order")
            try assertCoversInk("<mstack dir='rtl'><mscarries>\(token)</mscarries>\(token)</mstack>")
        }
        // Invalid values inherit, while numeric tokens remain LTR even with an override.
        try sameDrawing("<mstack dir='rtl'><mtext dir='invalid'>+ 12 אב</mtext></mstack>",
                        "<mstack dir='rtl'><mtext>+ 12 אב</mtext></mstack>")
        try sameDrawing("<mstack><mscarries><mn dir='rtl'>12</mn></mscarries><mn dir='rtl'>345</mn></mstack>",
                        "<mstack><mscarries><mn dir='ltr'>12</mn></mscarries><mn dir='ltr'>345</mn></mstack>")
    }

    func testDivisionBidiOperandsInheritAndOverrideWithoutMirroringFrames() throws {
        // Unlike numeric operands, mixed bidi text changes its internal order. Explicit
        // token directions reproduce that order under an LTR parent; frame separators
        // must still draw the same parentheses, slashes, colon and equals sign.
        for frame in LongDivision.allCases {
            let attrs = "longdivstyle='\(frame.rawValue)'"
            let divisor = "<mtext>+ 12 אב</mtext>"
            let result = "<mtext>+ 34 العربية</mtext>"
            let work = "<mn>72</mn><mscarries location='ne'><mtext>+ 56 אב</mtext></mscarries><mn>12</mn><msline/>"
            let body = divisor + result + work
            let directed = body.replacingOccurrences(of: "<mtext>", with: "<mtext dir='rtl'>")
            try sameDrawing("<math dir='rtl'><mstyle><mlongdiv \(attrs)>\(body)</mlongdiv></mstyle></math>",
                            "<mlongdiv \(attrs) dir='ltr'>\(directed)</mlongdiv>")
            let overridden = body.replacingOccurrences(of: "<mtext>", with: "<mtext dir='ltr'>")
            try sameDrawing("<mlongdiv \(attrs) dir='rtl'>\(overridden)</mlongdiv>",
                            "<mlongdiv \(attrs) dir='ltr'>\(body)</mlongdiv>")
            try assertCoversInk("<mlongdiv \(attrs) dir='rtl'>\(body)</mlongdiv>")
        }
    }

    func testRTLSpeechCoordinatesStayIdenticalToPhysicalLTRColumns() throws {
        let body = "<msgroup position='1' shift='-1'><mscarries position='1' location='nw' crossout='updiagonalstrike'>"
            + "<mn>1</mn><none/></mscarries><mn>12.3</mn><msline length='2' position='1'/><mn>4.56</mn></msgroup>"
        for alignment in MathStackAlignment.allCases {
            let lhs = try node("<mstack dir='ltr' stackalign='\(alignment.rawValue)'>\(body)</mstack>")
            let rhs = try node("<mstack dir='rtl' stackalign='\(alignment.rawValue)'>\(body)</mstack>")
            for language in MathReading.languages {
                XCTAssertEqual(lhs.accessibilityDescription(locale: Locale(identifier: language)).text,
                               rhs.accessibilityDescription(locale: Locale(identifier: language)).text)
            }
        }
        for frame in LongDivision.allCases {
            let content = "<mn>3</mn><mn>24</mn><mn>72</mn>\(body)"
            let lhs = try node("<mlongdiv dir='ltr' longdivstyle='\(frame.rawValue)'>\(content)</mlongdiv>")
            let rhs = try node("<mlongdiv dir='rtl' longdivstyle='\(frame.rawValue)'>\(content)</mlongdiv>")
            XCTAssertEqual(lhs.accessibilityDescription, rhs.accessibilityDescription)
        }
    }

    // MARK: Image columns

    private func imageProvider(width: Int = 30, height: Int = 12) -> MathImageProvider {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = context.makeImage()!
        return MathImageProvider { $0 == "digit" ? image : nil }
    }

    func testNumberImageKeepsItsColumnAndSizesIt() throws {
        let image = #"<mglyph src="digit" alt="two"/>"#
        let body = "<mstack charspacing='2px'><msrow><mn>1\(image)3</mn></msrow><mn>456</mn></mstack>"
        let result = try drawing(body, images: imageProvider())
        XCTAssertEqual(result.row(0).map(\.name), ["one", "three"])
        let rect = try XCTUnwrap(result.images.first)
        equal(rect.width, 30); equal(rect.height, 12)
        equal(rect.minX, try result.glyph("one").right + 2)
        equal(try result.glyph("three").origin.x, rect.maxX + 2)
        equal(try result.glyph("five").right, rect.maxX)
        equal(try result.glyph("four").origin.x, try result.glyph("one").origin.x)
        equal(try result.glyph("six").origin.x, try result.glyph("three").origin.x)
    }

    func testImageFallbackStaysAtomicAndDoesNotBecomeADecimalPoint() throws {
        for images in [nil, MathImageProvider { _ in nil }] {
            let result = try drawing(#"<mstack charspacing="2px"><mn>1<mglyph src="digit" alt="23.4"/>5</mn><mn>678</mn></mstack>"#,
                                     images: images)
            XCTAssertTrue(result.images.isEmpty)
            equal(try result.glyph("six").origin.x, try result.glyph("one").origin.x)
            equal(try result.glyph("seven").right, try result.glyph("four").right)
            equal(try result.glyph("eight").origin.x, try result.glyph("five").origin.x)
            // No column spacing inside the fallback, only on either side of the whole cell.
            equal(try result.glyph("three").origin.x, try result.glyph("two").right)
            equal(try result.glyph("five").origin.x, try result.glyph("four").right + 2)
        }
    }

    func testMultipleImageColumnsKeepDecimalPositionAndGroupShift() throws {
        let image = #"<mglyph src="digit" alt="two"/>"#
        let result = try drawing("<mstack charspacing='2px'><msgroup shift='1'><mn>1\(image)\(image).3</mn>"
                                + "<msrow position='-1'><mn>456.7</mn></msrow></msgroup></mstack>", images: imageProvider())
        XCTAssertEqual(result.images.count, 2)
        equal(result.images[1].minX, result.images[0].maxX + 2)
        equal(try result.glyph("period", 0).origin.x, try result.glyph("period", 1).origin.x)
        equal(try result.glyph("three").origin.x, try result.glyph("seven").origin.x)
        equal(try result.glyph("five").right, result.images[0].maxX)
        equal(try result.glyph("six").right, result.images[1].maxX)
    }

    func testImageSizesAndValignUseTheNumberContext() throws {
        let result = try drawing(#"<mstack charspacing="0"><mn mathsize="200%">1<mglyph src="digit" width="1em" height="0.5em" valign="-4px" mathsize="10%"/>3</mn></mstack>"#,
                                 images: imageProvider())
        let rect = try XCTUnwrap(result.images.first)
        equal(rect.width, 40); equal(rect.height, 20)
        equal(rect.minY, try result.glyph("one").origin.y - 4)
        equal(try result.glyph("three").origin.x, rect.maxX)
    }

    func testCarryAndBackgroundsFollowTheImageColumn() throws {
        let result = try drawing(##"<mstack charspacing="2px"><mscarries><none/><mn>9</mn><none/></mscarries><msrow mathbackground="red"><mn mathbackground="blue">1<mglyph src="digit" mathbackground="#00ff00"/>3</mn></msrow></mstack>"##,
                                 images: imageProvider())
        let rect = try XCTUnwrap(result.images.first)
        equal(try result.glyph("nine").middle, rect.midX)
        let green = try XCTUnwrap(result.rules.first { ($0.color.components ?? []).prefix(3) == [0, 1, 0] })
        XCTAssertEqual(green.rect, rect)
        for background in result.rules where background.rect != rect {
            XCTAssertTrue(background.rect.contains(rect))
        }
        XCTAssertGreaterThanOrEqual(result.box.ascent, try result.glyph("nine").ink.maxY)
    }

    func testLongDivisionWorkingRowsPreserveImageColumnsAndContainInk() throws {
        for form in LongDivision.allCases {
            let result = try drawing("<mlongdiv longdivstyle='\(form.rawValue)'><mn>2</mn><mn>4</mn>"
                                    + #"<mn>1<mglyph src="digit" width="45px" height="50px" valign="-20px"/>3</mn>"#
                                    + "<msrow position='1'><mn>456</mn></msrow></mlongdiv>", images: imageProvider())
            XCTAssertEqual(result.images.count, 1, form.rawValue)
            let rect = try XCTUnwrap(result.images.first)
            equal(try result.glyph("three").origin.x, rect.maxX + 2)
            let bounds = try XCTUnwrap(result.box.inkBounds)
            XCTAssertGreaterThanOrEqual(bounds.minX, -0.01)
            XCTAssertLessThanOrEqual(bounds.maxX, result.box.width + 0.01)
            XCTAssertGreaterThanOrEqual(bounds.minY, -result.box.descent - 0.01)
            XCTAssertLessThanOrEqual(bounds.maxY, result.box.ascent + 0.01)
        }
    }

    func testHostBuiltNumberPairsMissingAndExtraMarkers() throws {
        let glyph = MathMLNode(name: "mglyph", attributes: ["src": "digit"])
        let number = MathMLNode(name: "mn", children: [glyph, glyph], text: "1\u{FFFC}3")
        let result = try drawing(MathMLNode(name: "mstack", children: [number]), images: imageProvider())
        XCTAssertEqual(result.images.count, 2)
        XCTAssertLessThan(try result.glyph("one").right, result.images[0].minX)
        XCTAssertLessThan(result.images[0].maxX, try result.glyph("three").origin.x)
        XCTAssertGreaterThan(result.images[1].minX, try result.glyph("three").right)
        let extra = MathMLNode(name: "mn", children: [glyph], text: "\u{FFFC}1\u{FFFC}")
        XCTAssertEqual(try drawing(MathMLNode(name: "mstack", children: [extra]), images: imageProvider()).images.count, 1)
    }

    func testImageCharalignAndZeroSizeKeepAtomicColumns() throws {
        for (alignment, factor) in [("left", CGFloat(0)), ("center", 0.5), ("right", 1)] {
            let result = try drawing("<mstack charalign='\(alignment)' charspacing='0'><mn>1"
                                    + #"<mglyph src="digit" width="10px"/>3</mn><mn>4<mglyph src="digit" width="40px"/>6</mn></mstack>"#,
                                     images: imageProvider())
            XCTAssertEqual(result.images.count, 2)
            equal(result.images[0].minX, result.images[1].minX + 30 * factor)
        }
        let result = try drawing(#"<mstack charspacing="0"><mn>1<mglyph src="digit" width="0px"/>3</mn><mn>456</mn></mstack>"#,
                                 images: imageProvider())
        XCTAssertTrue(result.images.isEmpty)
        equal(try result.glyph("one").origin.x, try result.glyph("four").origin.x)
        equal(try result.glyph("three").origin.x, try result.glyph("six").origin.x)
        XCTAssertGreaterThan(try result.glyph("three").origin.x, try result.glyph("one").right)
    }

    func testNumberImageChildrenRespectTheirDepth() throws {
        let glyph = MathMLNode(name: "mglyph", attributes: ["alt": "1"])
        let stack = MathMLNode(name: "mstack", children: [MathMLNode(name: "mn", children: [glyph])])
        let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 12, display: false, color: black)
        XCTAssertNoThrow(try LayoutEngine(fontName: nil).layout(stack, context, depth: MathLimits.depth - 4))
        XCTAssertThrowsError(try LayoutEngine(fontName: nil).layout(stack, context, depth: MathLimits.depth - 3)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    func testNumberImageChildrenAndFallbackTextUseLayoutBudgets() throws {
        let glyph = MathMLNode(name: "mglyph", attributes: ["src": "digit", "alt": "1"])
        let number = MathMLNode(name: "mn", children: [glyph])
        let token = MathMLNode(name: "mn", children: [MathMLNode(name: "malignmark")], text: "1")
        for child in [number, token] {
            let tree = MathMLNode(name: "mstack", children: Array(repeating: child, count: MathLimits.nodes / 2))
            for images in [nil, imageProvider(width: 1, height: 1)] {
                XCTAssertThrowsError(try stackBox(tree, images: images)) {
                    XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
                }
            }
        }
        let long = MathMLNode(name: "mglyph", attributes: ["alt": String(repeating: "1", count: MathLimits.textLength + 1)])
        XCTAssertThrowsError(try stackBox(MathMLNode(name: "mstack", children: [MathMLNode(name: "mn", children: [long])]))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    // MARK: Columns

    /// The specification's first example (3.6): 424 over + 33 over a line.
    func testDigitsShareColumnsAndAlignRight() throws {
        let sum = try drawing("<mstack><mn>424</mn><msrow><mo>+</mo><none/><mn>33</mn></msrow><msline/></mstack>")
        XCTAssertEqual(sum.row(0).map(\.name), ["four", "two", "four"], "an mn gives a column to each digit")
        XCTAssertEqual(sum.row(1).map(\.name), ["plus", "three", "three"])
        let top = sum.row(0), bottom = sum.row(1)
        // Tens and ones stand over each other, and both rows end at the right edge.
        equal(bottom[1].origin.x, top[1].origin.x)
        equal(bottom[2].origin.x, top[2].origin.x)
        equal(top[2].right, sum.box.width)
        equal(bottom[2].right, sum.box.width)
        // The sign is a column of its own, left of the hundreds that `none` leaves empty under the 4.
        equal(bottom[0].origin.x, 0)
        let gap = top[1].origin.x - top[0].right
        XCTAssertGreaterThan(gap, 0)
        equal(top[0].origin.x - bottom[0].right, gap, "the same space between every two columns")
        equal(top[2].origin.x - top[1].origin.x, top[1].origin.x - top[0].origin.x)
        // Rows are a line apart, and the rule runs under all four columns below the last row.
        XCTAssertGreaterThan(top[0].origin.y - bottom[0].origin.y, top[0].ink.height * 1.2)
        XCTAssertEqual(sum.rules.count, 1)
        equal(sum.rules[0].rect.minX, 0)
        equal(sum.rules[0].rect.width, sum.box.width)
        XCTAssertLessThan(sum.rules[0].rect.maxY, bottom[1].ink.minY)
        // Without the none, the sign takes the hundreds column.
        let tight = try drawing("<mstack><mn>424</mn><msrow><mo>+</mo><mn>33</mn></msrow></mstack>")
        XCTAssertLessThan(tight.box.width, sum.box.width)
        equal(try tight.glyph("plus").right, try tight.glyph("four").right)
        // Rows of digits are one pitch apart, whatever their digits.
        let rows = try drawing("<mstack><mn>111</mn><mn>1,000</mn><mn>888</mn></mstack>")
        equal(rows.row(0)[0].origin.y - rows.row(1)[0].origin.y, rows.row(1)[0].origin.y - rows.row(2)[0].origin.y)
    }

    func testNumbersSplitIntoCharacters() throws {
        // Space around a number is no column, nor is the marker that stands for an mglyph in it.
        let marked = try drawing(MathMLNode(name: "mstack", children: [
            MathMLNode(name: "mn", text: " \n1\u{FFFC}2\t "), MathMLNode(name: "mn", text: "34"),
        ]))
        XCTAssertEqual(marked.glyphs.map(\.name), ["one", "two", "three", "four"])
        equal(try marked.glyph("two").right, try marked.glyph("four").right)
        // A space inside one is a column, as narrow as a space unless a digit shares it.
        let grouped = try drawing("<mstack><mn>1 234</mn><mn>5 678</mn></mstack>")
        let pitch = try grouped.glyph("three").origin.x - grouped.glyph("two").origin.x
        let digit = try grouped.glyph("one").advance
        XCTAssertEqual(grouped.row(0).map(\.name), ["one", "two", "three", "four"])
        let space = try grouped.glyph("two").origin.x - grouped.glyph("one").right - 2 * (pitch - digit)
        XCTAssertGreaterThan(space, 2)
        XCTAssertLessThan(space, digit - 2)
        let shared = try drawing("<mstack><mn>1 234</mn><mn>56789</mn></mstack>")
        equal(try shared.glyph("two").origin.x - shared.glyph("one").origin.x, 2 * pitch)
        // Every character is a column: signs, separators and letters too.
        let odd = try drawing("<mstack><mn>-1,5e3</mn></mstack>")
        XCTAssertEqual(odd.glyphs.count, 6)
        XCTAssertEqual(Set(odd.glyphs.map { ($0.origin.y * 100).rounded() }).count, 1)
        XCTAssertTrue(try drawing("<mstack><mn></mn><mn>  </mn></mstack>").glyphs.isEmpty)
    }

    func testStackAlign() throws {
        func rows(_ align: String?, _ numbers: [String] = ["1.25", "346", "78.9"]) throws -> Drawing {
            let attribute = align.map { " stackalign='\($0)'" } ?? ""
            return try drawing("<mstack\(attribute)>\(numbers.map { "<mn>\($0)</mn>" }.joined())</mstack>")
        }
        // On the decimal point, by default: the points, and the ones before them, share columns.
        // A number without one has it implied on its right.
        for align in [nil, "decimalpoint", "nonsense"] {
            let stack = try rows(align)
            equal(try stack.glyph("period", 0).origin.x, try stack.glyph("period", 1).origin.x)
            equal(try stack.glyph("one").origin.x, try stack.glyph("six").origin.x)
            equal(try stack.glyph("eight").origin.x, try stack.glyph("six").origin.x)
            equal(try stack.glyph("five").right, stack.box.width)
            equal(try stack.glyph("three").origin.x, 0)
        }
        let left = try rows("left")
        for name in ["one", "three", "seven"] { equal(try left.glyph(name).origin.x, 0, name) }
        let right = try rows("right")
        for name in ["five", "six", "nine"] { equal(try right.glyph(name).right, right.box.width, name) }
        XCTAssertLessThan(try right.glyph("period", 0).origin.x, try right.glyph("period", 1).origin.x)
        // Centred on the middle column, or the one right of the middle of an even count.
        let center = try rows("center", ["1", "234", "56", "7890"])
        for name in ["one", "six", "nine"] { equal(try center.glyph(name).origin.x, try center.glyph("three").origin.x, name) }
        // The specification's example with the operator on the right: no row needs padding.
        let dutch = try drawing("<mstack><mn>123</mn><msrow><mn>456</mn><mo>+</mo></msrow><msline/><mn>579</mn></mstack>")
        equal(try dutch.glyph("three").origin.x, try dutch.glyph("six").origin.x)
        equal(try dutch.glyph("nine").origin.x, try dutch.glyph("six").origin.x)
        XCTAssertGreaterThanOrEqual(try dutch.glyph("plus").origin.x, try dutch.glyph("six").right)
        equal(try dutch.glyph("plus").right, dutch.box.width)
        // The implied point follows the first number, even one written as an mn a digit.
        let digits = try drawing("<mstack><msrow><mn>4</mn><mn>2</mn><mn>5</mn></msrow>"
            + "<msrow><mo>+</mo><mstyle><mn>3</mn></mstyle><mn>6</mn><mo>=</mo><mn>9</mn></msrow></mstack>")
        equal(try digits.glyph("six").origin.x, try digits.glyph("five").origin.x)
        equal(try digits.glyph("three").origin.x, try digits.glyph("two").origin.x)
    }

    func testDecimalPointCharacter() throws {
        // A comma is a column like any other until `decimalpoint` names it.
        let plain = try drawing("<mstack><mn>1,5</mn><mn>22</mn></mstack>")
        equal(try plain.glyph("five").origin.x, try plain.glyph("two", 1).origin.x)
        let comma = try drawing("<mstack decimalpoint=','><mn>1,5</mn><mn>22</mn></mstack>")
        equal(try comma.glyph("one").origin.x, try comma.glyph("two", 1).origin.x)
        equal(try comma.glyph("five").right, comma.box.width)
        let styled = try drawing("<mstack><msrow><mstyle decimalpoint=','><mn>1,5</mn></mstyle></msrow><mn>22</mn></mstack>")
        equal(try styled.glyph("one").origin.x, try styled.glyph("two", 1).origin.x)
        // With one named, the full stop is a column like any other.
        let stop = try drawing("<mstack decimalpoint=','><mn>1.5</mn><mn>22</mn></mstack>")
        equal(try stop.glyph("five").origin.x, try stop.glyph("two", 1).origin.x)
        // The specification's last example writes its numbers with the Arabic decimal separator.
        let arabic = try drawing("<mstack><mn>&#x664;&#x663;&#x665;&#x66B;&#x663;</mn><mn>&#x661;&#x663;&#x660;&#x666;</mn></mstack>")
        XCTAssertEqual(arabic.row(0).count, 5)
        XCTAssertEqual(arabic.row(1).count, 4)
        equal(arabic.row(0)[2].origin.x, arabic.row(1)[3].origin.x, "the ones share a column")
        // A point in an operator counts too, which is why the dotted repeating decimal is right-aligned.
        let dots = "<msrow><mo>.</mo><none/><none/><none/><none/><mo>.</mo></msrow><mn> 0.142857 </mn>"
        let repeating = try drawing("<mstack stackalign='right'>\(dots)</mstack>")
        equal(try repeating.glyph("period", 0).right, try repeating.glyph("one").right)
        equal(try repeating.glyph("period", 1).right, try repeating.glyph("seven").right)
        let pointed = try drawing("<mstack>\(dots)</mstack>")
        equal(try pointed.glyph("period", 0).origin.x, try pointed.glyph("period", 2).origin.x)
    }

    func testCharAlign() throws {
        // The comma is narrower than the 4 it shares a column with.
        func stack(_ align: String?) throws -> (comma: Glyph, four: Glyph) {
            let attribute = align.map { " charalign='\($0)'" } ?? ""
            let stack = try drawing("<mstack\(attribute)><mn>1,5</mn><mn>345</mn></mstack>")
            return (try stack.glyph("comma"), try stack.glyph("four"))
        }
        for align in [nil, "right", "nonsense"] {
            let (comma, four) = try stack(align)
            XCTAssertLessThan(comma.advance, four.advance - 1)
            equal(comma.right, four.right)
        }
        let left = try stack("left")
        equal(left.comma.origin.x, left.four.origin.x)
        let center = try stack("center")
        equal(center.comma.middle, center.four.middle)
    }

    /// A sign is wider than a digit. It sizes a column of its own, but in a column of digits it
    /// overflows instead, away from its row, so the digits of the other rows keep their pitch.
    func testWideSignsOverflowDigitColumns() throws {
        let body = "<mstack><mn>99</mn><msrow><mo>+</mo><mn>11</mn></msrow><msline/><mn>110</mn></mstack>"
        let sum = try drawing(body)
        let total = sum.row(2), plus = try sum.glyph("plus")
        XCTAssertGreaterThan(plus.advance, total[0].advance + 1)
        equal(total[2].origin.x - total[1].origin.x, total[1].origin.x - total[0].origin.x, "no gap after the hundreds")
        equal(plus.right, total[0].right, "a leading sign overflows to the left")
        equal(sum.rules[0].rect.minX, plus.origin.x, "and the line under the sum starts under it")
        equal(sum.rules[0].rect.maxX, total[2].right)
        XCTAssertGreaterThan(sum.box.width, total[2].right - total[0].origin.x, "the box still covers the sign")
        try assertCoversInk(body)
        let trailing = try drawing("<mstack stackalign='right'><mn>123</mn><msrow><mn>456</mn><mo>+</mo></msrow></mstack>")
        let gap = try trailing.glyph("three").origin.x - trailing.glyph("two").right
        equal(try trailing.glyph("plus").origin.x, try trailing.glyph("three").origin.x, "a trailing sign, to the right")
        equal(try trailing.glyph("six").right + gap, try trailing.glyph("plus").origin.x)
        // Between cells, or alone in its row, it goes where charalign says.
        let alone = try drawing("<mstack charalign='left'><mn>1</mn><mo>+</mo></mstack>")
        equal(try alone.glyph("plus").origin.x, try alone.glyph("one").origin.x)
        let between = try drawing("<mstack stackalign='right'><mn>123</mn><msrow><mn>4</mn><mo>+</mo><mn>5</mn></msrow></mstack>")
        equal(try between.glyph("plus").right, try between.glyph("two").right)
    }

    func testCharSpacing() throws {
        func stack(_ spacing: String?, carries: String = "") throws -> (gap: CGFloat, drawing: Drawing) {
            let attribute = spacing.map { " charspacing='\($0)'" } ?? ""
            let stack = try drawing("<mstack\(attribute)>\(carries)<mn>345</mn><mn>678</mn></mstack>")
            let three = try stack.glyph("three"), four = try stack.glyph("four")
            if carries.isEmpty { equal(stack.box.width, 3 * three.advance + 2 * (four.origin.x - three.right)) }
            return (four.origin.x - three.right, stack)
        }
        equal(try stack("tight").gap, 0)
        equal(try stack(nil).gap, 0.1 * em)
        equal(try stack("medium").gap, 0.1 * em)
        equal(try stack("loose").gap, 0.25 * em)
        equal(try stack("1em").gap, em)
        equal(try stack("7px").gap, 7)
        equal(try stack("-1em").gap, 0, "columns never overlap")
        equal(try stack("nonsense").gap, 0.1 * em)
        // A keyword makes room for a carry wider than its column; a length is what it says.
        let wide = "<mscarries><mn>12</mn><mn>12</mn><none/></mscarries>"
        let digit = try stack(nil).drawing.glyph("three").advance
        let carry = try stack(nil, carries: wide).drawing.glyph("one").advance * 2
        XCTAssertGreaterThan(carry, digit)
        equal(try stack("tight", carries: wide).gap, carry - digit)
        equal(try stack(nil, carries: wide).gap, 0.1 * em + carry - digit)
        equal(try stack("loose", carries: wide).gap, 0.25 * em + carry - digit)
        equal(try stack("0.1em", carries: wide).gap, 0.1 * em)
        // A carry beside a digit needs the whole gap.
        equal(try stack("tight", carries: "<mscarries location='w'><mn>1</mn><mn>1</mn><none/></mscarries>").gap, carry / 2)
    }

    func testPositionAndShift() throws {
        func stack(_ rows: String) throws -> Drawing { try drawing("<mstack>\(rows)</mstack>") }
        // Positive positions move a row towards the tens, by whole columns; negative ones away.
        let up = try stack("<mn>123</mn><msrow position='1'><mn>456</mn></msrow>")
        let pitch = try up.glyph("two").origin.x - up.glyph("one").origin.x
        equal(try up.glyph("six").origin.x, try up.glyph("two").origin.x)
        equal(try up.glyph("four").origin.x, try up.glyph("one").origin.x - pitch)
        equal(up.box.width, 3 * pitch + (try up.glyph("one").advance))
        let down = try stack("<mn>123</mn><msrow position='-2'><mn>456</mn></msrow>")
        equal(try down.glyph("four").origin.x, try down.glyph("three").origin.x)
        // A group moves all its rows, and `shift` moves each one further than the one before.
        let group = try stack("<mn>123</mn><msgroup position='1'><mn>456</mn><mn>789</mn></msgroup>")
        equal(try group.glyph("six").origin.x, try group.glyph("two").origin.x)
        equal(try group.glyph("nine").origin.x, try group.glyph("two").origin.x)
        let shifted = try stack("<msgroup shift='1'><mn>123</mn><mn>456</mn><mn>789</mn></msgroup>")
        equal(try shifted.glyph("six").origin.x, try shifted.glyph("two").origin.x)
        equal(try shifted.glyph("nine").origin.x, try shifted.glyph("one").origin.x)
        // Nested groups add up, as in the specification's long division: 2 − 1 − 1 = 0.
        let nested = try stack("<mn>123</mn><msgroup position='2' shift='-1'><mn>4</mn>"
            + "<msgroup position='-1'><mn>5</mn></msgroup></msgroup>")
        equal(try nested.glyph("four").origin.x, try nested.glyph("one").origin.x)
        equal(try nested.glyph("five").origin.x, try nested.glyph("three").origin.x)
        // The decimal point is a column to count when moving past it.
        let point = try stack("<mn>1.0</mn><msrow position='-2'><mn>9</mn></msrow>")
        equal(try point.glyph("nine").origin.x, try point.glyph("zero").origin.x)
    }

    /// The specification's multiplications (3.6.8.2).
    func testMultiplication() throws {
        let simple = "<mstack><msgroup><mn>123</mn><msrow><mo>&#xD7;</mo><mn>321</mn></msrow></msgroup><msline/>"
            + "<msgroup shift='1'><mn>123</mn><mn>246</mn><mn>369</mn></msgroup><msline/></mstack>"
        let product = try drawing(simple)
        XCTAssertEqual((0..<5).map { product.row($0).map(\.name).joined(separator: " ") },
                       ["one two three", "multiply three two one", "one two three", "two four six", "three six nine"])
        let pitch = product.row(0)[1].origin.x - product.row(0)[0].origin.x
        equal(product.row(2)[2].right, product.box.width)
        equal(product.row(3)[2].right, product.box.width - pitch)
        equal(product.row(4)[2].right, product.box.width - 2 * pitch)
        equal(product.row(4)[0].origin.x, 0)
        equal(product.row(4)[2].origin.x - product.row(4)[1].origin.x, pitch, "the sign above leaves no gap in 369")
        XCTAssertEqual(product.rules.count, 2)
        for rule in product.rules { equal(rule.rect.width, product.box.width) }
        try assertCoversInk(simple)

        let carried = "<mstack><mscarries><mn>1</mn><mn>1</mn><none/></mscarries>"
            + "<mscarries><mn>1</mn><mn>1</mn><none/></mscarries>"
            + "<mn>1,234</mn><msrow><mo>&#xD7;</mo><mn>4,321</mn></msrow><msline/>"
            + "<mscarries position='2'><mn>1</mn><none/><mn>1</mn><mn>1</mn><mn>1</mn><none/><mn>1</mn></mscarries>"
            + "<msgroup shift='1'><mn>1,234</mn><mn>24,68</mn><mn>370,2</mn><msrow position='1'><mn>4,936</mn></msrow></msgroup>"
            + "<msline/><mn>5,332,114</mn></mstack>"
        let long = try drawing(carried)
        // The author's commas fall in the same two columns in every row, which stay comma-wide.
        let commas = long.all("comma")
        XCTAssertEqual(commas.count, 8)
        XCTAssertEqual(Set(commas.map { ($0.origin.x * 100).rounded() }).count, 2)
        let total = long.glyphs.filter { $0.origin.y == long.glyphs.map(\.origin.y).min() }
        XCTAssertEqual(total.map(\.name).joined(), "fivecommathreethreetwocommaoneonefour")
        equal(total[2].origin.x - total[1].right, total[4].origin.x - total[3].right)
        XCTAssertLessThan(total[2].origin.x - total[0].origin.x, 2 * (total[3].origin.x - total[2].origin.x) - 1)
        // Two rows of carries over the first factor, and a row of five over the partial products.
        let carries = long.glyphs.filter { $0.size < em }
        XCTAssertEqual(carries.count, 9)
        XCTAssertEqual(Set(carries.map { ($0.origin.y * 100).rounded() }).count, 3)
        equal(carries[0].middle, try long.glyph("two").middle, "over the hundreds of 1,234")
        equal(carries[2].middle, carries[0].middle)
        XCTAssertGreaterThan(carries[0].origin.y, carries[2].ink.maxY)
        equal(carries[8].middle, total[6].middle, "with position 2, the last carry is over the hundreds")
        equal(carries[4].middle, total[0].middle, "and the first over the millions")
        try assertCoversInk(carried)
    }

    // MARK: Lines

    func testLines() throws {
        func stack(_ line: String, _ attributes: String = "") throws -> Drawing {
            try drawing("<mstack\(attributes)><mn>12345</mn><msline\(line)/><mn>67890</mn></mstack>")
        }
        let plain = try stack("")
        let digits = plain.row(0), rule = plain.rules[0].rect
        let standard = constants.fractionRuleThickness * em
        // Length 0 spans the stack, whatever the position, between the two rows.
        equal(rule.minX, 0); equal(rule.width, plain.box.width); equal(rule.height, standard)
        XCTAssertLessThan(rule.maxY, digits[0].ink.minY)
        XCTAssertGreaterThan(rule.minY, plain.row(1)[0].ink.maxY)
        equal(try stack(" length='0' position='3'").rules[0].rect.width, plain.box.width)
        // A length is a number of that many digits: under the last two columns, then moved by position.
        var short = try stack(" length='2'").rules[0].rect
        equal(short.minX, digits[3].origin.x); equal(short.maxX, digits[4].right)
        equal(short.minY, rule.minY)
        short = try stack(" length='2' position='2'").rules[0].rect
        equal(short.minX, digits[1].origin.x); equal(short.maxX, digits[2].right)
        short = try stack(" length='2'", " stackalign='left'").rules[0].rect
        equal(short.minX, digits[0].origin.x); equal(short.maxX, digits[1].right)
        short = try stack(" length='3'", " stackalign='center'").rules[0].rect
        equal(short.minX, digits[1].origin.x); equal(short.maxX, digits[3].right)
        // Past the last column it makes the stack one empty column wider, as a digit there would.
        let past = try stack(" length='1' position='-1'")
        equal(past.rules[0].rect.minX, digits[4].right + (digits[1].origin.x - digits[0].right))
        equal(past.rules[0].rect.width, digits[0].advance)
        equal(past.box.width, plain.box.width + digits[1].origin.x - digits[0].origin.x)
        // Overhangs lengthen it on each side, and the box grows to cover them.
        short = try stack(" length='2' leftoverhang='0.5em' rightoverhang='3px'").rules[0].rect
        equal(short.minX, digits[3].origin.x - 0.5 * em); equal(short.maxX, digits[4].right + 3)
        let hanging = try stack(" leftoverhang='0.5em' rightoverhang='1em'")
        equal(hanging.rules[0].rect.width, plain.box.width + 1.5 * em)
        equal(hanging.box.width, plain.box.width + 1.5 * em)
        equal(try hanging.glyph("one").origin.x, 0.5 * em)
        equal(try stack(" length='2' leftoverhang='-0.2em'").rules[0].rect.minX, digits[3].origin.x + 0.2 * em)
        XCTAssertTrue(try stack(" length='1' leftoverhang='-5em'").rules.isEmpty, "a line has no negative length")
        // Thickness, with mfrac's keywords, grows downwards from the same top.
        let top = try stack("", " align='top'").rules[0].rect.maxY
        for (value, thickness) in [("thin", standard / 2), ("medium", standard), ("thick", standard * 2), ("3px", 3),
                                   ("0.2em", 0.2 * em), ("999em", em), ("nonsense", standard)] {
            let thick = try stack(" mslinethickness='\(value)'", " align='top'").rules[0].rect
            equal(thick.height, thickness, value); equal(thick.maxY, top, value)
        }
        XCTAssertTrue(try stack(" mslinethickness='0'").rules.isEmpty)
        equal(try stack(" mslinethickness='thick'").box.height, plain.box.height + standard, "rows move by the thickness alone")
        XCTAssertEqual(try stack(" mathcolor='red'").rules[0].color, MathColor.parse("red"))
        // Two lines in a row stay apart.
        let double = try drawing("<mstack><mn>12</mn><msline/><msline/></mstack>")
        XCTAssertEqual(double.rules.count, 2)
        XCTAssertGreaterThan(double.rules[0].rect.minY - double.rules[1].rect.maxY, standard)
    }

    /// A line with no length spans the stack (3.6.7.2). The stack is as wide as its rows, so the
    /// line goes on under a sign that overflows the first or the last column, as the line under
    /// a sum does on paper. Its overhangs are measured from those columns all the same.
    func testALineAcrossTheStackReachesASignThatOverflows() throws {
        func stack(_ line: String = "", sign: String = "<mo>+</mo>") throws -> Drawing {
            let body = "<mstack><mn>99</mn><msrow>\(sign)<mn>11</mn></msrow><msline\(line)/><mn>110</mn></mstack>"
            try assertCoversInk(body)
            return try drawing(body)
        }
        // "+11" over "110": the plus shares the hundreds with a digit, and overflows them to the left.
        let sum = try stack()
        let plus = try sum.glyph("plus"), total = sum.row(2)
        XCTAssertLessThan(plus.origin.x, total[0].origin.x - 1, "the sign does overflow")
        equal(sum.rules[0].rect.minX, plus.origin.x); equal(sum.rules[0].rect.maxX, total[2].right)
        equal(sum.rules[0].rect.minX, 0); equal(sum.rules[0].rect.width, sum.box.width)
        // A trailing sign overflows to the right.
        func ending(_ line: String = "") throws -> Drawing {
            try drawing("<mstack stackalign='right'><mn>123</mn><msrow><mn>456</mn><mo>+</mo></msrow><msline\(line)/><mn>579</mn></mstack>")
        }
        let trailing = try ending()
        XCTAssertGreaterThan(try trailing.glyph("plus").right, try trailing.glyph("nine").right + 1)
        equal(trailing.rules[0].rect.minX, try trailing.glyph("four").origin.x)
        equal(trailing.rules[0].rect.maxX, try trailing.glyph("plus").right)
        // Every such line of a stack is the same, wherever the sign is.
        let lines = try drawing("<mstack><msline/><mn>99</mn><msrow><mo>+</mo><mn>11</mn></msrow><msline/><mn>110</mn><msline/></mstack>")
        XCTAssertEqual(lines.rules.count, 3)
        for rule in lines.rules { equal(rule.rect.minX, try lines.glyph("plus").origin.x); equal(rule.rect.width, sum.rules[0].rect.width) }
        // An overhang is past the column the line spans, not past the sign (3.6.7.2), and the line ends at
        // whichever is further out. So one no longer than the sign overflows changes nothing, nor does a negative one.
        let overflow = total[0].origin.x - plus.origin.x
        XCTAssertGreaterThan(overflow, 0.2 * em); XCTAssertLessThan(overflow, 0.5 * em - 1)
        for overhang in ["1px", "0.2em", "-0.2em"] {
            let under = try stack(" leftoverhang='\(overhang)'")
            equal(under.rules[0].rect.minX, try under.glyph("plus").origin.x, overhang)
            equal(under.rules[0].rect.maxX, under.row(2)[2].right, overhang)
        }
        equal(try ending(" rightoverhang='1px'").rules[0].rect.maxX, try trailing.glyph("plus").right)
        // A longer one is as long as it says: half an em left of the hundreds, which is past the sign.
        let hanging = try stack(" leftoverhang='0.5em' rightoverhang='3px'")
        equal(hanging.rules[0].rect.minX, hanging.row(2)[0].origin.x - 0.5 * em)
        XCTAssertLessThan(hanging.rules[0].rect.minX, try hanging.glyph("plus").origin.x - 1)
        equal(hanging.rules[0].rect.maxX, hanging.row(2)[2].right + 3)
        equal(try ending(" rightoverhang='0.5em'").rules[0].rect.maxX, try trailing.glyph("nine").right + 0.5 * em)
        // With no sign to reach, a negative one shortens the line.
        let bare = try drawing("<mstack><mn>99</mn><msline leftoverhang='-0.2em'/><mn>11</mn></mstack>")
        equal(bare.rules[0].rect.minX, bare.row(1)[0].origin.x + 0.2 * em); equal(bare.rules[0].rect.maxX, bare.box.width)
        // A line with a length is a number of that many digits, and keeps to their columns and its overhangs.
        let counted = try stack(" length='3'")
        equal(counted.rules[0].rect.minX, counted.row(2)[0].origin.x); equal(counted.rules[0].rect.maxX, counted.row(2)[2].right)
        XCTAssertGreaterThan(counted.rules[0].rect.minX, try counted.glyph("plus").origin.x + 1)
        let short = try stack(" length='3' leftoverhang='1px'")
        equal(short.rules[0].rect.minX, short.row(2)[0].origin.x - 1)
        // A sign with a column of its own overflows nothing, and carries have no width (3.6.1.1).
        let fitting = try stack(sign: "<mo>+</mo><none/>")
        equal(fitting.rules[0].rect.minX, try fitting.glyph("plus").origin.x); equal(fitting.rules[0].rect.width, fitting.box.width)
        let carried = try drawing("<mstack><mscarries location='w'><mn>1</mn><none/></mscarries><mn>34</mn><msline/></mstack>")
        XCTAssertLessThan(try carried.glyph("one").origin.x, try carried.glyph("three").origin.x - 1)
        equal(carried.rules[0].rect.minX, try carried.glyph("three").origin.x)
        equal(carried.rules[0].rect.maxX, try carried.glyph("four").right)

        // In a division the bar is part of the frame, which meets it where the columns end. A sign
        // in the work that overflows them moves a line of the work, not the bar.
        let rule = constants.fractionRuleThickness * em
        let us = try drawing("<mlongdiv><mn>7</mn><mn>58</mn><mn>406</mn><msrow><mo>-</mo><mn>35</mn></msrow><msline/></mlongdiv>")
        let minus = try us.glyph("uni2212"), hook = try XCTUnwrap(us.segments.first)
        XCTAssertLessThan(minus.origin.x, try us.glyph("four").origin.x - 1)
        let bar = try XCTUnwrap(us.horizontals.max { $0.minY < $1.minY }), under = try XCTUnwrap(us.horizontals.min { $0.minY < $1.minY })
        equal(bar.minX, hook.from.x - rule / 2); equal(bar.maxX, try us.glyph("six").right)
        equal(under.minX, minus.origin.x); equal(under.maxX, bar.maxX)
        let chinese = try drawing("<mlongdiv longdivstyle='righttop' stackalign='right'><mn>7</mn><mn>58</mn><mn>406</mn>"
            + "<msrow><mn>35</mn><mo>-</mo></msrow><msline/></mlongdiv>")
        let corner = chinese.horizontals.sorted { $0.minY > $1.minY }
        XCTAssertEqual(corner.count, 3)
        equal(corner[0].maxX, corner[1].maxX, "the bar still ends where the line under the divisor does")
        equal(corner[0].minX, try chinese.glyph("four").origin.x)
        XCTAssertGreaterThan(try chinese.glyph("uni2212").right, try chinese.glyph("six").right + 1)
        equal(corner[2].minX, corner[0].minX); equal(corner[2].maxX, try chinese.glyph("uni2212").right)
    }

    /// The specification's repeating decimals (3.6.8.4): a line over or under some digits.
    func testRepeatingDecimals() throws {
        let last = try drawing("<mstack stackalign='right'><msline length='1'/><mn> 0.3333 </mn></mstack>")
        XCTAssertEqual(last.glyphs.count, 6)
        equal(last.rules[0].rect.minX, last.glyphs[5].origin.x); equal(last.rules[0].rect.maxX, last.glyphs[5].right)
        XCTAssertGreaterThan(last.rules[0].rect.minY, last.glyphs[5].ink.maxY)
        let over = try drawing("<mstack stackalign='right'><msline length='6'/><mn> 0.142857 </mn></mstack>")
        equal(over.rules[0].rect.minX, try over.glyph("one").origin.x); equal(over.rules[0].rect.maxX, try over.glyph("seven").right)
        XCTAssertGreaterThan(over.rules[0].rect.minY, try over.glyph("one").ink.maxY)
        let under = try drawing("<mstack stackalign='right'><mn> 0.142857 </mn><msline length='6'/></mstack>")
        equal(under.rules[0].rect.minX, try under.glyph("one").origin.x)
        XCTAssertLessThan(under.rules[0].rect.maxY, try under.glyph("one").ink.minY)
    }

    // MARK: Carries

    func testCarriesAreSmallAndAnnotateTheNextRow() throws {
        let stack = try drawing("<mstack><mn>678</mn><mscarries><mn>1</mn><mn>2</mn><none/></mscarries><mn>345</mn></mstack>")
        let one = try stack.glyph("one"), two = try stack.glyph("two")
        // 0.6 of the size, centred over the hundreds and tens of the row below, between the rows.
        equal(one.size, 0.6 * em); equal(two.size, 0.6 * em)
        equal(try stack.glyph("three").size, em)
        equal(one.middle, try stack.glyph("three").middle)
        equal(two.middle, try stack.glyph("four").middle)
        XCTAssertGreaterThan(one.ink.minY, try stack.glyph("three").ink.maxY)
        XCTAssertLessThan(one.ink.maxY, try stack.glyph("six").ink.minY)
        equal(one.origin.y, two.origin.y)
        // They have no width: with a fixed spacing the columns are as far apart as without them.
        func pitches(_ carries: String, spacing: String = " charspacing='0.1em'") throws -> [CGFloat] {
            let digits = try drawing("<mstack\(spacing)>\(carries)<mn>345</mn></mstack>").glyphs.filter { $0.size == em }
            return [digits[1].origin.x - digits[0].origin.x, digits[2].origin.x - digits[1].origin.x].map { ($0 * 100).rounded() }
        }
        let wide = "<mscarries><mn>888</mn><mn>888</mn><mn>888</mn></mscarries>"
        XCTAssertEqual(try pitches(wide), try pitches(""))
        XCTAssertGreaterThan(try pitches(wide, spacing: "")[0], try pitches("", spacing: "")[0], "the keywords do make room")
        // position moves the columns they belong to.
        let moved = try drawing("<mstack><mscarries position='1'><mn>1</mn></mscarries><mn>345</mn></mstack>")
        equal(try moved.glyph("one").middle, try moved.glyph("four").middle)
        let unmoved = try drawing("<mstack><mscarries><mn>1</mn></mscarries><mn>345</mn></mstack>")
        equal(try unmoved.glyph("one").middle, try unmoved.glyph("five").middle)
        // scriptsizemultiplier on the element, or inherited, replaces the 0.6.
        func size(_ carries: String, _ open: String = "", _ close: String = "") throws -> CGFloat {
            try drawing("\(open)<mstack><mscarries\(carries)><mn>1</mn></mscarries><mn>345</mn></mstack>\(close)").glyph("one").size
        }
        equal(try size(" scriptsizemultiplier='0.8'"), 0.8 * em)
        equal(try size("", "<mstyle scriptsizemultiplier='0.9'>", "</mstyle>"), 0.9 * em)
        equal(try size(" scriptsizemultiplier='0.8'", "<mstyle scriptsizemultiplier='0.9'>", "</mstyle>"), 0.8 * em)
        equal(try size(" scriptsizemultiplier='0'"), 0.6 * em)
        // Two rows of carries stack; one after the last row, which is an error, is still drawn.
        let twice = try drawing("<mstack><mscarries><mn>1</mn></mscarries><mscarries><mn>2</mn></mscarries><mn>345</mn></mstack>")
        XCTAssertGreaterThan(try twice.glyph("one").ink.minY, try twice.glyph("two").ink.maxY)
        XCTAssertGreaterThan(try twice.glyph("two").ink.minY, try twice.glyph("five").ink.maxY)
        equal(try twice.glyph("one").middle, try twice.glyph("five").middle)
        let dangling = try drawing("<mstack><mn>345</mn><mscarries location='w'><mn>1</mn></mscarries></mstack>")
        XCTAssertLessThan(try dangling.glyph("one").ink.maxY, try dangling.glyph("five").ink.minY)
        // A carry may be any element.
        let fraction = try drawing("<mstack><mscarries><mfrac><mn>1</mn><mn>2</mn></mfrac></mscarries><mn>345</mn></mstack>")
        XCTAssertGreaterThan(try fraction.glyph("two").ink.minY, try fraction.glyph("five").ink.maxY)
    }

    func testCarryLocations() throws {
        /// A carry of 1 on the 4 of 345, between two other rows.
        func carry(_ location: String, on element: String) throws -> (carry: Glyph, digit: Glyph, box: MathBox) {
            let attribute = " location='\(location)'"
            let child = element == "mscarry" ? "<mscarry\(attribute)><mn>1</mn></mscarry>" : "<mn>1</mn>"
            let body = "<mstack><mn>678</mn><mscarries\(element == "mscarries" ? attribute : "")><none/>\(child)<none/>"
                + "</mscarries><mn>345</mn><mn>290</mn></mstack>"
            let stack = try drawing(body)
            try assertCoversInk(body)
            return (try stack.glyph("one"), try stack.glyph("four"), stack.box)
        }
        let raise = constants.superscriptShiftUp * em, drop = constants.subscriptShiftDown * em
        for element in ["mscarries", "mscarry"] {
            let north = try carry("n", on: element), south = try carry("s", on: element)
            equal(north.carry.middle, north.digit.middle); equal(south.carry.middle, south.digit.middle)
            XCTAssertGreaterThan(north.carry.ink.minY, north.digit.ink.maxY)
            XCTAssertLessThan(south.carry.ink.maxY, south.digit.ink.minY)
            for location in ["w", "nw", "sw", "e", "ne", "se"] {
                let (carry, digit, _) = try carry(location, on: element)
                let isWest = location.hasSuffix("w")
                equal(isWest ? carry.right : carry.origin.x, isWest ? digit.origin.x : digit.right, location)
                switch location.first {
                case "n": equal(carry.origin.y, digit.origin.y + raise, location)
                case "s": equal(carry.origin.y, digit.origin.y - drop, location)
                default: equal(carry.ink.midY, digit.ink.midY, location)
                }
            }
            // Only a carry above takes a line of its own; one below makes room under its row.
            XCTAssertGreaterThan(north.box.height, try carry("w", on: element).box.height + 5)
            XCTAssertGreaterThan(south.box.height, try carry("e", on: element).box.height + 5)
            equal(try carry("nonsense", on: element).carry.origin.y, north.carry.origin.y)
        }
        // The specification's second borrow: 2 above the struck 3, 1 at the top left of the 2 beside it.
        let borrow = try drawing("<mstack><mscarries location='nw'><none/>"
            + "<mscarry crossout='updiagonalstrike' location='n'><mn>2</mn></mscarry><mn>1</mn><none/></mscarries>"
            + "<mn>2,327</mn><msrow><mo>-</mo><mn> 1,156</mn></msrow><msline/><mn>1,171</mn></mstack>")
        let small = borrow.glyphs.filter { $0.size < em }
        XCTAssertEqual(small.map(\.name), ["two", "one"])
        equal(small[0].middle, try borrow.glyph("three").middle)
        equal(small[1].right, try borrow.glyph("two", 2).origin.x)
        XCTAssertGreaterThan(small[1].origin.y, try borrow.glyph("three").origin.y)
        XCTAssertGreaterThan(small[0].origin.y, small[1].origin.y)
        XCTAssertEqual(borrow.segments.count, 1)
    }

    func testCrossouts() throws {
        func stack(_ crossout: String, carry: String = "<mn>1</mn>", color: String = "") throws -> Drawing {
            try drawing("<mstack><mscarries crossout='\(crossout)'\(color)>\(carry)<none/>"
                + "<mscarry crossout='none'><mn>2</mn></mscarry></mscarries><mn>345</mn></mstack>")
        }
        // Only the column with a carry that asks for it is struck: the 3, not the 4 or the 5.
        func struck(_ crossout: String) throws -> (strike: Segment, three: Glyph, four: Glyph) {
            let drawn = try stack(crossout)
            XCTAssertEqual(drawn.segments.count, 1, crossout)
            return (try XCTUnwrap(drawn.segments.first), try drawn.glyph("three"), try drawn.glyph("four"))
        }
        var (strike, three, four) = try struck("updiagonalstrike")
        XCTAssertLessThan(strike.from.x, three.ink.minX); XCTAssertGreaterThan(strike.to.x, three.ink.maxX)
        XCTAssertLessThan(strike.from.y, three.ink.minY); XCTAssertGreaterThan(strike.to.y, three.ink.maxY)
        XCTAssertLessThan(strike.to.x, four.ink.midX)
        (strike, three, four) = try struck("downdiagonalstrike")
        XCTAssertLessThan(strike.from.x, three.ink.minX); XCTAssertGreaterThan(strike.to.x, three.ink.maxX)
        XCTAssertGreaterThan(strike.from.y, three.ink.maxY); XCTAssertLessThan(strike.to.y, three.ink.minY)
        (strike, three, four) = try struck("verticalstrike")
        equal(strike.from.x, three.middle); equal(strike.to.x, strike.from.x)
        XCTAssertLessThan(min(strike.from.y, strike.to.y), three.ink.minY)
        XCTAssertGreaterThan(max(strike.from.y, strike.to.y), three.ink.maxY)
        (strike, three, four) = try struck("horizontalstrike")
        equal(strike.from.y, three.ink.midY); equal(strike.to.y, strike.from.y)
        XCTAssertLessThan(strike.from.x, three.ink.minX); XCTAssertGreaterThan(strike.to.x, three.ink.maxX)
        XCTAssertLessThan(strike.to.x, four.ink.minX)
        // Every value given is drawn, and none among them means nothing.
        let all = "none updiagonalstrike  downdiagonalstrike verticalstrike horizontalstrike bogus"
        XCTAssertEqual(try stack(all).segments.count, 4)
        XCTAssertTrue(try stack("none").segments.isEmpty)
        // A column without a carry is not struck, and an empty mscarry strikes without a carry.
        XCTAssertTrue(try stack("updiagonalstrike", carry: "<none/>").segments.isEmpty)
        let bare = try stack("updiagonalstrike", carry: "<mscarry><none/></mscarry>")
        XCTAssertEqual(bare.segments.count, 1)
        XCTAssertEqual(bare.glyphs.filter { $0.size < em }.map(\.name), ["two"])
        // In the carry's colour, and really drawn: the ink reaches past the digit's corners.
        XCTAssertEqual(try stack("updiagonalstrike", color: " mathcolor='red'").segments[0].color, MathColor.parse("red"))
        let crossed = "<mstack><mscarries crossout='updiagonalstrike'><mscarry><none/></mscarry></mscarries><mn>7</mn></mstack>"
        let marks = try XCTUnwrap(ink(try layout(crossed))), clean = try XCTUnwrap(ink(try layout("<mstack><mn>7</mn></mstack>")))
        XCTAssertGreaterThan(marks.width, clean.width + 1)
        XCTAssertGreaterThan(marks.height, clean.height + 1)
        // The specification's first borrow: 3 and 2 struck with 2 and 12 above them, the 7 untouched.
        let body = "<mstack><mscarries crossout='updiagonalstrike'><mn>2</mn><mn>12</mn>"
            + "<mscarry crossout='none'><none/></mscarry></mscarries>"
            + "<mn>2,327</mn><msrow><mo>-</mo><mn> 1,156</mn></msrow><msline/><mn>1,171</mn></mstack>"
        let borrow = try drawing(body)
        XCTAssertEqual(borrow.glyphs.filter { $0.size < em }.map(\.name), ["two", "one", "two"])
        XCTAssertEqual(borrow.segments.count, 2)
        XCTAssertLessThan(borrow.segments[0].from.x, try borrow.glyph("three").ink.minX)
        XCTAssertGreaterThan(borrow.segments[1].to.x, try borrow.glyph("two", 3).ink.maxX)
        XCTAssertLessThan(borrow.segments[1].to.x, try borrow.glyph("seven").ink.minX + 2)
        equal(try borrow.glyph("uni2212").origin.x, 0)
        try assertCoversInk(body)
        // The Swedish borrow: an underlined 10 over the 2, and the 5 struck by a carry that draws nothing.
        let swedish = "<mstack><mscarries><mscarry crossout='updiagonalstrike'><none/></mscarry>"
            + "<menclose notation='bottom'><mn>10</mn></menclose></mscarries>"
            + "<mn>52</mn><msrow><mo>-</mo><mn> 7</mn></msrow><msline/><mn>45</mn></mstack>"
        let sweden = try drawing(swedish)
        let diagonal = try XCTUnwrap(sweden.segments.first { $0.from.y != $0.to.y })
        XCTAssertLessThan(diagonal.from.x, try sweden.glyph("five").ink.minX)
        XCTAssertGreaterThan(diagonal.to.x, try sweden.glyph("five").ink.maxX)
        XCTAssertGreaterThan(try sweden.glyph("one").ink.minY, try sweden.glyph("two").ink.maxY)
        try assertCoversInk(swedish)
    }

    // MARK: Long division

    /// 406 ÷ 7 = 58, each number with a digit of its own: 7 in the divisor, 8 in the result,
    /// 4 in the dividend.
    private func division(_ style: String?, divisor: String = "<mn>7</mn>", result: String = "<mn>58</mn>") -> String {
        let attribute = style.map { " longdivstyle=\"\($0)\"" } ?? ""
        return "<mlongdiv\(attribute)>\(divisor)\(result)<mn>406</mn><msgroup position='1' shift='-1'>"
            + "<msgroup><mn>35</mn><msline length='2'/></msgroup>"
            + "<msgroup><mn>56</mn><mn>56</mn><msline length='2'/><mn>0</mn></msgroup></msgroup></mlongdiv>"
    }

    private static let styles = ["lefttop", "stackedrightright", "mediumstackedrightright", "shortstackedrightright", "righttop",
                                 "left/\\right", "left)(right", ":right=right", "stackedleftleft", "stackedleftlinetop"]

    /// Everything a style draws, to tell two apart.
    private func signature(_ drawing: Drawing) -> String {
        func number(_ value: CGFloat) -> String { String(Int((value * 10).rounded())) }
        func numbers(_ values: CGFloat...) -> String { values.map(number).joined(separator: ",") }
        return (drawing.glyphs.map { "\($0.name)@\(numbers($0.origin.x, $0.origin.y))" }
            + drawing.rules.map { "rule@\(numbers($0.rect.minX, $0.rect.minY, $0.rect.width, $0.rect.height))" }
            + drawing.segments.map { "stroke@\(numbers($0.from.x, $0.from.y, $0.to.x, $0.to.y))" }).joined(separator: " ")
    }

    func testEveryLongDivisionStyleIsItsOwnLayout() throws {
        var signatures: [String: String] = [:]
        let rule = constants.fractionRuleThickness * em
        for style in Self.styles {
            let body = division(style)
            try assertCoversInk(body)
            let drawn = try drawing(body)
            signatures[style] = signature(drawn)
            let seven = try drawn.glyph("seven"), eight = try drawn.glyph("eight"), four = try drawn.glyph("four")
            let six = try XCTUnwrap(drawn.all("six").first { $0.origin.y == four.origin.y }, style)
            let five = try XCTUnwrap(drawn.all("five").first { $0.origin.y == eight.origin.y }, style)
            // The work is the same everywhere: 35 under 40, a line, 56 under the 0 and the 6.
            let work = drawn.glyphs.filter {
                $0.origin.y < four.origin.y - 1 && $0.origin.x >= four.origin.x - 1 && $0.origin.x <= six.origin.x + 1
            }
            XCTAssertEqual(work.map(\.name).joined(separator: " "), "three five five six five six zero", style)
            equal(try drawn.glyph("three").origin.x, four.origin.x, style)
            equal(try drawn.glyph("zero", 1).origin.x, six.origin.x, style)
            equal(seven.origin.y, four.origin.y, "the divisor stands on the dividend's line: \(style)")
            // The frame is what is not one of the two lines of the work.
            let lines = drawn.horizontals.filter {
                $0.minX >= four.origin.x - 0.01 && $0.maxX <= six.right + 0.01 && $0.maxY < four.ink.minY
            }
            XCTAssertEqual(lines.count, 2, style)
            let frame = drawn.horizontals.filter { !lines.contains($0) }, verticals = drawn.verticals
            for line in frame { equal(line.height, rule, style) }
            for line in verticals { equal(line.width, rule, style) }
            if ["lefttop", "righttop", "stackedleftlinetop"].contains(style) {
                // The result is a row of the stack: ones over ones, above a bar over the dividend.
                XCTAssertGreaterThan(eight.ink.minY, four.ink.maxY, style)
                equal(eight.origin.x, six.origin.x, style)
                equal(five.origin.x, try drawn.glyph("zero").origin.x, style)
                let bar = try XCTUnwrap(frame.first { $0.minY > four.ink.maxY && $0.maxY < eight.ink.minY }, style)
                XCTAssertLessThanOrEqual(bar.minX, four.origin.x, style)
                XCTAssertGreaterThanOrEqual(bar.maxX, six.right - 0.01, style)
            } else {
                XCTAssertLessThanOrEqual(eight.origin.y, four.origin.y, style)
            }
            /// Left to right on the dividend's line.
            func assertInOrder(_ glyphs: [Glyph]) {
                XCTAssertEqual(glyphs.map(\.origin.x), glyphs.map(\.origin.x).sorted(), style)
                for glyph in glyphs { equal(glyph.origin.y, four.origin.y, style) }
            }
            switch style {
            case "lefttop":
                // 7 ) 406 with the hook between them, from the bar down past the baseline.
                XCTAssertLessThan(seven.right, four.origin.x)
                XCTAssertEqual(drawn.segments.filter(\.isCurve).count, 1)
                let hook = drawn.segments[0]
                XCTAssertGreaterThan(hook.from.x, seven.right); XCTAssertLessThan(hook.from.x, four.origin.x)
                equal(hook.from.x, hook.to.x)
                XCTAssertGreaterThan(hook.from.y, four.ink.maxY); XCTAssertLessThan(hook.to.y, four.origin.y)
                XCTAssertEqual(frame.count, 1); XCTAssertTrue(verticals.isEmpty)
                equal(frame[0].minX, hook.from.x - rule / 2); equal(frame[0].maxX, six.right)
            case "stackedrightright", "mediumstackedrightright", "shortstackedrightright":
                // 406 | 7 over a line over 58.
                XCTAssertGreaterThan(seven.origin.x, six.right, style)
                XCTAssertLessThan(eight.ink.maxY, seven.ink.minY, style)
                XCTAssertGreaterThan(five.origin.x, six.right, style)
                XCTAssertEqual(verticals.count, 1, style); XCTAssertEqual(frame.count, 1, style)
                XCTAssertTrue(drawn.segments.isEmpty, style)
                XCTAssertGreaterThan(verticals[0].minX, six.right, style)
                XCTAssertLessThan(verticals[0].maxX, seven.origin.x, style)
                equal(frame[0].minX, verticals[0].minX, style)
                XCTAssertGreaterThanOrEqual(frame[0].maxX, eight.right, style)
                XCTAssertLessThan(frame[0].maxY, seven.ink.minY, style)
                XCTAssertGreaterThan(frame[0].minY, eight.ink.maxY, style)
                XCTAssertGreaterThan(verticals[0].maxY, seven.ink.maxY, style)
                switch style {
                case "stackedrightright":
                    equal(verticals[0].height, drawn.box.height, "the height of the work")
                case "mediumstackedrightright":
                    XCTAssertLessThan(verticals[0].minY, eight.ink.minY, "down past the result")
                    XCTAssertGreaterThan(verticals[0].minY, try drawn.glyph("five", 2).ink.maxY, "but no further")
                default:
                    equal(verticals[0].minY, frame[0].minY, "down to the line under the divisor only")
                }
            case "righttop":
                // 58 over a bar; under it 406 and the 7 in a corner: a line before it and one under it.
                XCTAssertGreaterThan(seven.origin.x, six.right)
                XCTAssertEqual(verticals.count, 1); XCTAssertEqual(frame.count, 2); XCTAssertTrue(drawn.segments.isEmpty)
                XCTAssertGreaterThan(verticals[0].minX, six.right); XCTAssertLessThan(verticals[0].maxX, seven.origin.x)
                let bar = try XCTUnwrap(frame.max { $0.minY < $1.minY }), under = try XCTUnwrap(frame.min { $0.minY < $1.minY })
                equal(bar.minX, 0); XCTAssertGreaterThan(bar.maxX, seven.right)
                equal(under.minX, verticals[0].minX); equal(under.maxX, bar.maxX)
                XCTAssertLessThan(under.maxY, seven.ink.minY)
                equal(verticals[0].maxY, bar.maxY); equal(verticals[0].minY, under.minY)
            case "left/\\right", "left)(right":
                // 7 / 406 \ 58 or 7 ) 406 ( 58 on one line.
                let open = try drawn.glyph(style == "left)(right" ? "parenright" : "slash")
                let close = try drawn.glyph(style == "left)(right" ? "parenleft" : "backslash")
                assertInOrder([seven, open, four, six, close, five, eight])
                XCTAssertGreaterThanOrEqual(open.origin.x, seven.right, style)
                XCTAssertGreaterThanOrEqual(close.origin.x, six.right, style)
                XCTAssertTrue(frame.isEmpty && verticals.isEmpty && drawn.segments.isEmpty, style)
            case ":right=right":
                // 406 : 7 = 58 on one line.
                assertInOrder([four, six, try drawn.glyph("colon"), seven, try drawn.glyph("equal"), five, eight])
                equal(four.origin.x, 0)
                XCTAssertTrue(frame.isEmpty && verticals.isEmpty && drawn.segments.isEmpty)
            case "stackedleftleft":
                // 7 over a line over 58, flush against a line the height of the work, then 406.
                XCTAssertLessThan(seven.right, four.origin.x); XCTAssertLessThan(eight.right, four.origin.x)
                XCTAssertLessThan(eight.ink.maxY, seven.ink.minY)
                equal(seven.right, eight.right)
                XCTAssertEqual(verticals.count, 1); XCTAssertEqual(frame.count, 1); XCTAssertTrue(drawn.segments.isEmpty)
                XCTAssertGreaterThan(verticals[0].minX, seven.right); XCTAssertLessThan(verticals[0].maxX, four.origin.x)
                equal(verticals[0].height, drawn.box.height)
                equal(frame[0].minX, 0); equal(frame[0].maxX, verticals[0].minX)
                XCTAssertLessThan(frame[0].maxY, seven.ink.minY); XCTAssertGreaterThan(frame[0].minY, eight.ink.maxY)
            case "stackedleftlinetop":
                // 58 over a bar that turns down before 406; the 7 left of that, underlined.
                XCTAssertLessThan(seven.right, four.origin.x)
                XCTAssertEqual(verticals.count, 1); XCTAssertEqual(frame.count, 2); XCTAssertTrue(drawn.segments.isEmpty)
                XCTAssertGreaterThan(verticals[0].minX, seven.right); XCTAssertLessThan(verticals[0].maxX, four.origin.x)
                let bar = try XCTUnwrap(frame.max { $0.minY < $1.minY }), under = try XCTUnwrap(frame.min { $0.minY < $1.minY })
                equal(bar.minX, verticals[0].minX); equal(bar.maxX, six.right)
                equal(under.minX, 0); equal(under.maxX, verticals[0].maxX)
                XCTAssertLessThan(under.maxY, seven.ink.minY)
                equal(verticals[0].maxY, bar.maxY); equal(verticals[0].minY, under.minY)
                XCTAssertLessThan(verticals[0].height, drawn.box.height / 3)
            default: XCTFail(style)
            }
        }
        XCTAssertEqual(Set(signatures.values).count, 10, "no two styles draw the same")
        // lefttop is the default, and what an unknown value falls back to. Values are trimmed.
        for style in [nil, "nonsense", " lefttop "] {
            XCTAssertEqual(signature(try drawing(division(style))), signatures["lefttop"], style ?? "default")
        }
        XCTAssertEqual(signature(try drawing(division(":right=right "))), signatures[":right=right"])
        XCTAssertEqual(signature(try drawing(division("mediumrightright"))), signatures["mediumstackedrightright"])
    }

    /// The specification's example (3.6.8.3), whose work runs past the dividend's decimal point.
    func testLongDivisionWorkFollowsTheDividendsColumns() throws {
        func division(_ style: String) -> String {
            "<mlongdiv longdivstyle=\"\(style)\"><mn> 3 </mn><mn> 435.3</mn><mn> 1306</mn><msgroup position='2' shift='-1'>"
                + "<msgroup><mn> 12</mn><msline length='2'/></msgroup>"
                + "<msgroup><mn> 10</mn><mn> 9</mn><msline length='2'/></msgroup>"
                + "<msgroup><mn> 16</mn><mn> 15</mn><msline length='2'/><mn> 1.0</mn></msgroup>"
                + "<msgroup position='-1'><mn> 9</mn><msline length='3'/><mn> 1</mn></msgroup></msgroup></mlongdiv>"
        }
        let us = try drawing(division("lefttop"))
        XCTAssertEqual((0..<10).map { us.row($0).map(\.name).joined(separator: " ") },
                       ["four three five period three", "three one three zero six", "one two", "one zero", "nine", "one six",
                        "one five", "one period zero", "nine", "one"])
        let dividend = Array(us.row(1).dropFirst()), result = us.row(0)
        equal(result[2].origin.x, dividend[3].origin.x, "435.3 has its ones over those of 1306")
        equal(result[4].right, us.box.width, "and its tenths past them")
        equal(us.row(2)[0].origin.x, dividend[0].origin.x); equal(us.row(3)[1].origin.x, dividend[2].origin.x)
        equal(us.row(4)[0].origin.x, dividend[2].origin.x); equal(us.row(5)[1].origin.x, dividend[3].origin.x)
        equal(us.row(7)[0].origin.x, dividend[3].origin.x, "1.0 aligns on its point, not its last digit")
        equal(us.row(7)[1].origin.x, result[3].origin.x)
        equal(us.row(8)[0].origin.x, us.row(7)[2].origin.x); equal(us.row(9)[0].origin.x, us.row(7)[2].origin.x)
        let last = try XCTUnwrap(us.horizontals.min { $0.minY < $1.minY })
        equal(last.minX, us.row(7)[0].origin.x); equal(last.maxX, us.row(7)[2].right)
        // Beside the dividend, the divisor follows its digits, not the columns the work adds on the right.
        let following = [(":right=right", "colon", 0), ("left/\\right", "backslash", 0), ("shortstackedrightright", "three", 1)]
        for (style, name, index) in following {
            let drawn = try drawing(division(style))
            let next = try drawn.glyph(name, index)
            XCTAssertLessThan(next.origin.x - (try drawn.glyph("six").right), em, style)
            XCTAssertGreaterThan(try drawn.glyph("zero", 2).right, next.origin.x, style)
            try assertCoversInk(division(style))
        }
        let french = try drawing(division("stackedrightright"))
        XCTAssertGreaterThan(french.verticals[0].minX, try french.glyph("zero", 2).right)
    }

    func testLongDivisionWithMissingParts() throws {
        XCTAssertThrowsError(try stackBox("<mlongdiv><mn>7</mn></mlongdiv>")) {
            XCTAssertEqual($0 as? MathLayoutError, .invalidMarkup("mlongdiv"))
        }
        for style in Self.styles {
            // An unfinished division: no result yet, no divisor, neither, or parts that are groups.
            for (divisor, result) in [("<mn>7</mn>", "<none/>"), ("<none/>", "<mn>58</mn>"), ("<none/>", "<none/>"),
                                      ("<msrow><mn>7</mn></msrow>", "<msgroup><mn>58</mn><msline/></msgroup>")] {
                try assertCoversInk(division(style, divisor: divisor, result: result))
            }
            let bare = try drawing("<mlongdiv longdivstyle=\"\(style)\"><mn>7</mn><mn>58</mn></mlongdiv>")
            XCTAssertTrue(Set(["seven", "five", "eight"]).isSubset(of: bare.glyphs.map(\.name)), style)
            XCTAssertGreaterThan(bare.box.width, 0, style)
            let unfinished = try drawing(division(style, result: "<none/>"))
            XCTAssertTrue(unfinished.all("eight").isEmpty, style)
            equal(try unfinished.glyph("seven").origin.y, try unfinished.glyph("four").origin.y, style)
        }
    }

    // MARK: Work beside the divisor or the result

    /// What a division draws before and after its dividend, and what the dividend's stack draws: as
    /// rectangles, a glyph's its advance wide and its ink high, with x from the dividend's first digit.
    private struct Sides {
        var before: [CGRect] = [], after: [CGRect] = [], work: [CGRect] = []
        /// Where what precedes the dividend ends, where what follows it starts, and where the box ends.
        var trailing: CGFloat { before.map(\.maxX).max() ?? 0 }
        var leading: CGFloat { after.map(\.minX).min() ?? 0 }
        var right: CGFloat = 0
    }

    /// 1 ÷ 8 = 0.125 with `work` under the 1: rows that reach past it, or none. Colour tells what is drawn
    /// apart: the dividend and the work are lime, the divisor red and the result blue, which leaves the
    /// frame and the signs black. The top is on the baseline, so that work moves nothing up or down.
    private func eighth(_ style: String, work: String = "", divisor: String = "<mn>8</mn>",
                        result: String = "<mn>0.125</mn>") -> String {
        "<mlongdiv longdivstyle=\"\(style)\" align='top'><msgroup mathcolor='red'>\(divisor)</msgroup>"
            + "<msgroup mathcolor='blue'>\(result)</msgroup><mn mathcolor='lime'>1</mn>"
            + "<msgroup mathcolor='lime'>\(work)</msgroup></mlongdiv>"
    }

    /// The work of 1 ÷ 8: 10 − 8, 20 − 16, 40 − 40. Its first row is a column longer than the dividend.
    private static let eighths = "<msgroup position='-1' shift='-1'><msgroup><mn>10</mn><mn>8</mn><msline length='2'/></msgroup>"
        + "<msgroup><mn>20</mn><mn>16</mn><msline length='2'/></msgroup>"
        + "<msgroup><mn>40</mn><mn>40</mn><msline length='2'/><mn>0</mn></msgroup></msgroup>"

    /// The sides of a division that `eighth` wrote, having asserted that nothing on either is drawn over
    /// anything of the dividend's stack, and that the box covers them all.
    private func sides(_ body: String, file: StaticString = #filePath, line: UInt = #line) throws -> Sides {
        let drawn = try drawing(body), lime = MathColor.parse("lime")
        let dividend = try XCTUnwrap(drawn.glyphs.first { $0.color == lime }, body, file: file, line: line).origin.x
        var sides = Sides(right: drawn.box.width - dividend)
        func sort(_ rect: CGRect, _ color: CGColor) {
            let rect = rect.offsetBy(dx: -dividend, dy: 0)
            if color == lime { sides.work.append(rect) } else if rect.midX < 0 { sides.before.append(rect) } else {
                sides.after.append(rect)
            }
        }
        for glyph in drawn.glyphs {
            sort(CGRect(x: glyph.origin.x, y: glyph.ink.minY, width: glyph.advance, height: glyph.ink.height), glyph.color)
        }
        for rule in drawn.rules { sort(rule.rect, rule.color) }
        for part in sides.before + sides.after {
            for other in sides.work {
                let shared = part.intersection(other)
                XCTAssertFalse(shared.width > 0.01 && shared.height > 0.01, "\(part) is drawn over \(other): \(body)",
                               file: file, line: line)
            }
        }
        try assertCoversInk(body, file: file, line: line)
        return sides
    }

    /// Asserts that `moved` are the rectangles that `plain` are, `distance` to the right.
    private func assertMoved(_ moved: [CGRect], _ plain: [CGRect], by distance: CGFloat = 0, _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(moved.count, plain.count, message, file: file, line: line)
        for (now, then) in zip(moved, plain) {
            equal(now.minX, then.minX + distance, message, file: file, line: line)
            equal(now.minY, then.minY, message, file: file, line: line)
            equal(now.width, then.width, message, file: file, line: line)
            equal(now.height, then.height, message, file: file, line: line)
        }
    }

    /// 1 ÷ 8 = 0.125. The first row of the work, "10", is level with the result and a column longer than
    /// the dividend, and the result began where the dividend ends: one was drawn over the other. What
    /// follows the dividend follows the "10" instead, as one piece, as far from it as from a dividend.
    func testAShortStackedResultStandsClearOfTheWork() throws {
        let style = "shortstackedrightright", pad = 0.2 * em, rule = constants.fractionRuleThickness * em
        // With no work: a line 0.2 em after the dividend, then the 8 over a line over the result.
        let plain = try sides(eighth(style))
        let digit = plain.work[0].width
        XCTAssertEqual(plain.after.count, 8)
        let line = plain.after[7], bar = plain.after[6]
        equal(line.minX, digit + pad); equal(line.width, rule); equal(plain.leading, line.minX)
        equal(bar.minX, line.minX); equal(bar.minY, line.minY); equal(bar.height, rule); equal(plain.right, bar.maxX)
        equal(plain.after[0].minX, line.maxX + pad, "the divisor"); equal(plain.after[1].minX, line.maxX + pad, "the result")
        equal(bar.maxX, plain.after[5].maxX + pad)
        // With the work, the 0 of "10" is where the line was. All of it is a column further right.
        let moved = try sides(eighth(style, work: Self.eighths))
        let ten = moved.work[2]
        equal(ten.minX, digit + 0.1 * em); XCTAssertGreaterThan(ten.maxX, line.maxX + pad)
        equal(moved.leading, ten.maxX + pad)
        assertMoved(moved.after, plain.after, by: ten.maxX - digit)
        equal(moved.right, moved.after[6].maxX, "and the box with it")
        // The rest of the work runs on under the result as before: only what is level with it is in its way.
        XCTAssertGreaterThan(moved.work.map(\.maxX).max() ?? 0, moved.leading + 1)
        // Work no longer than the dividend moves nothing, nor does work that is longer further down.
        assertMoved(try sides(eighth(style, work: "<mn>1</mn>")).after, plain.after)
        let lower = try sides(eighth(style, work: "<mn>1</mn>" + Self.eighths))
        assertMoved(lower.after, plain.after)
        XCTAssertGreaterThan(lower.work[3].maxX, lower.leading + 1, "the 10 does reach under the result")
        // A divisor of two rows has the line beside the first row of the work, and that is in its way too.
        let tall = try sides(eighth(style, work: Self.eighths, divisor: "<mn>8</mn><mn>8</mn>"))
        equal(tall.leading, tall.work[2].maxX + pad)
        // The specification's example (3.6.8.3) is as it was: its work is longer than 1306 only well below the result.
        let spec = try drawing("<mlongdiv longdivstyle='\(style)'><mn>3</mn><mn>435.3</mn><mn>1306</mn><msgroup position='2' shift='-1'>"
            + "<msgroup><mn>12</mn><msline length='2'/></msgroup><msgroup><mn>10</mn><mn>9</mn><msline length='2'/></msgroup>"
            + "<msgroup><mn>16</mn><mn>15</mn><msline length='2'/><mn>1.0</mn></msgroup>"
            + "<msgroup position='-1'><mn>9</mn><msline length='3'/><mn>1</mn></msgroup></msgroup></mlongdiv>")
        let six = try spec.glyph("six"), corner = try XCTUnwrap(spec.verticals.first)
        equal(corner.minX, six.right + pad); equal(try spec.glyph("three", 1).origin.x, corner.maxX + pad)
        equal(try spec.glyph("four").origin.x, corner.maxX + pad); equal(spec.box.width, try spec.glyph("three", 3).right + pad)
        // The move is part of the box, so a division that it makes too wide is refused like any other.
        func long(_ digits: Int) -> String {
            let number = String(repeating: "1", count: digits)
            return "<mlongdiv longdivstyle='\(style)'><mn>8</mn><mn>\(number)</mn><mn>1</mn>"
                + "<msrow position='\(1 - digits)'><mn>\(number)</mn></msrow></mlongdiv>"
        }
        let wide = try layout(long(1_500)).width
        XCTAssertGreaterThan(wide, 2 * 1_500 * digit); XCTAssertLessThan(wide, MathLimits.extent)
        XCTAssertThrowsError(try layout(long(3_000))) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }

    /// The one-line styles. What is on the dividend's line is a row high and has the work under it, however
    /// far that reaches. A divisor or a result of two rows is level with the first row of the work: where it
    /// would be drawn over that, it and the signs on its side of the dividend stand past the work instead.
    private func assertOneLineStandsClear(_ style: String) throws {
        let space = 0.25 * em, rows = "<mn>0.125</mn><mn>0.000</mn>", pair = "<mn>8</mn><mn>8</mn>"
        let isAfter = style == ":right=right"
        // A row high: 0.25 em from the dividend each side, with the work or without it.
        let flat = try sides(eighth(style)), digit = flat.work[0].width
        equal(flat.leading, digit + space, style)
        if isAfter { XCTAssertTrue(flat.before.isEmpty) } else { equal(flat.trailing, -space, style) }
        for work in [Self.eighths, "<mn>111</mn>", "<msrow position='-6'><mn>111000000</mn></msrow>"] {
            let low = try sides(eighth(style, work: work))
            assertMoved(low.before, flat.before, style); assertMoved(low.after, flat.after, style)
        }
        // A result of two rows, and work that stops short of its second.
        let plain = try sides(eighth(style, result: rows))
        equal(plain.leading, digit + space, style)
        let short = try sides(eighth(style, work: "<msrow position='-1'><mn>10</mn></msrow>", result: rows))
        assertMoved(short.after, plain.after, style); assertMoved(short.before, plain.before, style)
        // Work that reaches into it: the sign that follows the dividend follows the work, and the rest follows the sign.
        let far = try sides(eighth(style, work: "<msrow position='-6'><mn>1000000</mn></msrow>", result: rows))
        XCTAssertGreaterThan(far.work[7].maxX, plain.after[plain.after.count - 5].minX + 1, style)
        equal(far.leading, far.work[7].maxX + space, style)
        assertMoved(far.after, plain.after, by: far.work[7].maxX - digit, style); assertMoved(far.before, plain.before, style)
        equal(far.right, far.after.map(\.maxX).max() ?? 0, style)
        // A divisor of two rows. After the dividend it is as the result is.
        let tall = try sides(eighth(style, divisor: pair))
        guard !isAfter else {
            let moved = try sides(eighth(style, work: "<msrow position='-2'><mn>100</mn></msrow>", divisor: pair))
            XCTAssertGreaterThan(moved.work[3].maxX, tall.after[tall.after.count - 1].minX + 1, style)
            equal(moved.leading, moved.work[3].maxX + space, style)
            return assertMoved(moved.after, tall.after, by: moved.work[3].maxX - digit, style)
        }
        // Before it, it is in the way of work that reaches left of the dividend, and it goes left with its sign.
        let left = try sides(eighth(style, work: "<mn>111</mn>", divisor: pair))
        XCTAssertLessThan(left.work[1].minX, tall.before[2].maxX - 1, style)
        equal(left.trailing, left.work[1].minX - space, style)
        assertMoved(left.before, tall.before, by: left.work[1].minX, style); assertMoved(left.after, tall.after, style)
        // Both at once: each side moves away from the dividend by what is in its own way.
        let both = try sides(eighth(style, work: "<msrow position='-6'><mn>111000000</mn></msrow>", divisor: pair, result: rows))
        let outer = try sides(eighth(style, divisor: pair, result: rows))
        assertMoved(both.before, outer.before, by: both.work[1].minX, style)
        assertMoved(both.after, outer.after, by: both.work[9].maxX - digit, style)
    }

    func testLeftSlashRightStandsClearOfTheWork() throws { try assertOneLineStandsClear("left/\\right") }

    func testLeftParenRightStandsClearOfTheWork() throws { try assertOneLineStandsClear("left)(right") }

    func testColonRightEqualsRightStandsClearOfTheWork() throws { try assertOneLineStandsClear(":right=right") }

    // MARK: Alignment and style

    func testAlignSetsTheBaseline() throws {
        func stack(_ align: String?) throws -> Drawing {
            try drawing("<mstack\(align.map { " align='\($0)'" } ?? "")><mn>12</mn><mn>34</mn><msline/><mn>56</mn></mstack>")
        }
        let plain = try stack(nil), tall = plain.box.height
        // As mtable's: the middle on the baseline by default and for center, or on the axis.
        for align in [nil, "baseline", "center", "nonsense"] {
            equal(try stack(align).box.ascent, tall / 2, align ?? "default")
            equal(try stack(align).box.descent, tall / 2, align ?? "default")
        }
        equal(try stack("axis").box.ascent, tall / 2 + constants.axisHeight * em); equal(try stack("axis").box.height, tall)
        equal(try stack("top").box.ascent, 0); equal(try stack("top").box.descent, tall)
        equal(try stack("bottom").box.ascent, tall); equal(try stack("bottom").box.descent, 0)
        // With a row number, that row of digits: its baseline, top, bottom or middle. Lines are not rows.
        for (align, row) in [("baseline 1", 0), ("baseline 2", 1), ("baseline 3", 2), ("baseline -1", 2),
                             ("baseline -3", 0), ("axis 2", 1), ("BASELINE 2", 1)] {
            equal(try stack(align).row(row)[0].origin.y, 0, align)
            equal(try stack(align).box.height, tall, align)
        }
        // A number that names no row is ignored, as mtable ignores one: the stack is aligned whole.
        for align in ["baseline 0", "baseline 4", "baseline 9", "baseline -4", "baseline -9", "axis 9", "center -9",
                      "baseline -9223372036854775808", "baseline 99999999999999999999"] {
            equal(try stack(align).box.ascent, try stack(String(align.split(separator: " ")[0])).box.ascent, align)
        }
        equal(try stack("top 9").box.ascent, 0); equal(try stack("bottom -9").box.ascent, tall)
        let pitch = plain.row(0)[0].origin.y - plain.row(1)[0].origin.y
        equal(try stack("top 2").box.ascent, pitch); equal(try stack("bottom 1").box.ascent, pitch)
        equal(try stack("center 1").box.ascent, pitch / 2)
        equal(try stack("top 1").box.ascent, 0)
        // In a formula, the row named shares the baseline of what is beside it.
        let beside = try layout("<mi>x</mi><mo>=</mo><mstack align='baseline 1'><mn>12</mn><mn>34</mn></mstack>")
        let centred = try layout("<mi>x</mi><mo>=</mo><mstack><mn>12</mn><mn>34</mn></mstack>")
        equal(height(beside), height(centred))
        XCTAssertGreaterThan(beside.descent, centred.descent + 1)
        equal(beside.ascent, try stackBox("<mstack align='baseline 1'><mn>12</mn><mn>34</mn></mstack>").ascent)
        // A long division counts the rows of its stack, the result first where it is on top.
        let division = try drawing("<mlongdiv align='baseline 2'><mn>7</mn><mn>58</mn><mn>406</mn></mlongdiv>")
        equal(try division.glyph("four").origin.y, 0); equal(try division.glyph("seven").origin.y, 0)
        XCTAssertGreaterThan(try division.glyph("eight").origin.y, 0)
        let german = try drawing("<mlongdiv align='baseline 1' longdivstyle=':right=right'><mn>7</mn><mn>58</mn><mn>406</mn>"
            + "<mn>35</mn></mlongdiv>")
        equal(try german.glyph("four").origin.y, 0); equal(try german.glyph("eight").origin.y, 0)
    }

    func testStyleIsInherited() throws {
        let red = try XCTUnwrap(MathColor.parse("red")), blue = try XCTUnwrap(MathColor.parse("blue"))
        let body = "<mstack mathcolor='red'><mscarries crossout='horizontalstrike'><mn>1</mn></mscarries><mn>23</mn>"
            + "<msrow mathcolor='blue'><mo>+</mo><mn>4</mn></msrow><msline/><msgroup mathsize='2em'><mn>5</mn></msgroup></mstack>"
        let colored = try drawing(body)
        for name in ["one", "two", "three", "five"] { XCTAssertEqual(try colored.glyph(name).color, red, name) }
        for name in ["plus", "four"] { XCTAssertEqual(try colored.glyph(name).color, blue, name) }
        XCTAssertEqual(colored.rules[0].color, red); XCTAssertEqual(colored.segments[0].color, red)
        equal(try colored.glyph("five").size, 2 * em); equal(try colored.glyph("four").size, em)
        let rows = (1...3).map { colored.row($0)[0].origin.y }
        XCTAssertGreaterThan(rows[1] - rows[2], rows[0] - rows[1], "a larger row takes more room")
        equal(try colored.glyph("five").right, try colored.glyph("four").right, "and still ends in the ones column")
        try assertCoversInk(body)
        // A number's own attributes reach each of its digits.
        let number = try drawing("<mstack><mn mathvariant='bold' mathcolor='blue'>12</mn><mn>12</mn></mstack>")
        XCTAssertNotEqual(number.row(0)[0].name, number.row(1)[0].name)
        XCTAssertEqual(number.row(0).map(\.color), [blue, blue])
        let styled = try drawing("<mstack><msrow><mstyle mathcolor='blue'><mn>1</mn><mo>+</mo></mstyle><mn>2</mn></msrow></mstack>")
        XCTAssertEqual(styled.glyphs.map(\.color), [blue, blue, black])
        XCTAssertEqual(styled.glyphs.map(\.name), ["one", "plus", "two"], "an mstyle's children are the row's cells")
        // Division frames are drawn in the element's colour.
        for style in Self.styles {
            let division = try drawing("<mlongdiv mathcolor='red' longdivstyle=\"\(style)\"><mn>7</mn><mn>58</mn><mn>406</mn></mlongdiv>")
            XCTAssertTrue(division.glyphs.allSatisfy { $0.color == red } && division.rules.allSatisfy { $0.color == red }
                && division.segments.allSatisfy { $0.color == red }, style)
        }
    }

    func testBackgrounds() throws {
        let yellow = try XCTUnwrap(MathColor.parse("yellow")), red = try XCTUnwrap(MathColor.parse("red"))
        // The stack's own is the whole box, painted first by the engine like any element's.
        let whole = try drawing("<mstack mathbackground='yellow'><mn>12</mn><mn>345</mn></mstack>")
        XCTAssertEqual(whole.rules.count, 1)
        XCTAssertEqual(whole.rules[0].color, yellow)
        XCTAssertEqual(whole.rules[0].rect, CGRect(x: 0, y: -whole.box.descent, width: whole.box.width, height: whole.box.height))
        guard case .rect = whole.box.items[0] else { return XCTFail("the background is behind the digits") }
        // A row's covers its cells for the height of the row; a number's, its digits.
        let rows = try drawing("<mstack><msrow mathbackground='yellow'><mn>6</mn><mo>+</mo><mn>12</mn></msrow>"
            + "<msrow><mn mathbackground='red'>34</mn><mn>5</mn></msrow></mstack>")
        XCTAssertEqual(rows.rules.map(\.color), [yellow, red])
        let row = rows.rules[0].rect, number = rows.rules[1].rect
        equal(row.minX, try rows.glyph("six").origin.x); equal(row.maxX, try rows.glyph("two").right)
        equal(row.maxY, rows.box.ascent); equal(row.minY, number.maxY)
        equal(number.minX, try rows.glyph("three").origin.x); equal(number.maxX, try rows.glyph("four").right)
        equal(number.minY, -rows.box.descent)
        let carry = try drawing("<mstack><mscarries><mscarry mathbackground='red'><mn>1</mn></mscarry></mscarries><mn>5</mn></mstack>")
        XCTAssertEqual(carry.rules.map(\.color), [red])
        XCTAssertTrue(carry.rules[0].rect.contains(try carry.glyph("one").ink))
    }

    /// What a box draws, in the order it draws it.
    private func order(_ box: MathBox) -> [String] {
        box.items.flatMap { item -> [String] in
            switch item {
            case .rect: return ["rect"]
            case .glyphs: return ["glyphs"]
            case .box(let inner, _): return order(inner)
            default: return ["path"]
            }
        }
    }

    /// `mathbackground` fills the box of the element it is on (3.1.10), and a group, a row of
    /// carries and a line have one each: the group's lines, the row's line, the line itself.
    func testGroupsCarriesAndLinesHaveBackgrounds() throws {
        let yellow = try XCTUnwrap(MathColor.parse("yellow")), red = try XCTUnwrap(MathColor.parse("red"))
        let blue = try XCTUnwrap(MathColor.parse("blue"))
        // A group's is behind its rows' own, from the top of its first row to the bottom of its last
        // and from the leftmost column of any of them to the rightmost: here the 3's and the 4's.
        let group = try drawing("<mstack><mn>12345</mn><msgroup mathbackground='yellow' position='1' shift='1'>"
            + "<msrow mathbackground='red'><mn>67</mn></msrow><msrow mathbackground='blue'><mn>8</mn></msrow></msgroup>"
            + "<mn>9</mn></mstack>")
        XCTAssertEqual(group.rules.map(\.color), [yellow, red, blue])
        XCTAssertEqual(Array(order(group.box).prefix(3)), ["rect", "rect", "rect"], "all behind the digits")
        var rect = group.rules[0].rect
        equal(rect.maxY, group.rules[1].rect.maxY); equal(rect.minY, group.rules[2].rect.minY)
        equal(rect.minX, try group.glyph("three").origin.x); equal(rect.maxX, try group.glyph("four").right)
        equal(group.rules[2].rect.maxX, try group.glyph("three").right)
        XCTAssertLessThan(rect.maxY, try group.glyph("one").ink.minY)
        XCTAssertGreaterThan(rect.minY, try group.glyph("nine").ink.maxY)
        // A group in a group is over it, and a line of the group counts with its overhangs.
        let nested = try drawing("<mstack><mn>12345</mn><msgroup mathbackground='yellow'><msgroup mathbackground='red'>"
            + "<mn>6</mn></msgroup><msline length='2' position='2' leftoverhang='0.5em'/></msgroup></mstack>")
        XCTAssertEqual(nested.rules.map(\.color), [yellow, red, black])
        rect = nested.rules[0].rect
        equal(rect.minX, try nested.glyph("two").origin.x - 0.5 * em); equal(rect.minX, nested.rules[2].rect.minX)
        equal(rect.maxX, try nested.glyph("five").right)
        equal(rect.maxY, nested.rules[1].rect.maxY); equal(rect.minY, nested.rules[2].rect.minY)
        equal(nested.rules[1].rect.minX, try nested.glyph("six").origin.x)
        // So does a carry of the group that stands beside the first digit of a row.
        let borrowed = try drawing("<mstack><msgroup mathbackground='yellow'><mscarries location='w'><mn>1</mn><none/></mscarries>"
            + "<mn>34</mn></msgroup></mstack>")
        XCTAssertEqual(borrowed.rules.map(\.color), [yellow])
        equal(borrowed.rules[0].rect.minX, try borrowed.glyph("one").origin.x)
        equal(borrowed.rules[0].rect.maxX, try borrowed.glyph("four").right)
        equal(borrowed.rules[0].rect.height, borrowed.box.height)
        // A group with nothing in it, or with rows of nothing, has no box to fill.
        XCTAssertTrue(try drawing("<mstack><mn>1</mn><msgroup mathbackground='yellow'/><msgroup mathbackground='yellow'><msrow/>"
            + "</msgroup></mstack>").rules.isEmpty)

        // A row of carries': its columns, an empty one too, for the height of its line above the digits.
        let above = try drawing("<mstack><mscarries mathbackground='yellow'><mn>1</mn><mn>1</mn><none/></mscarries><mn>678</mn></mstack>")
        XCTAssertEqual(above.rules.map(\.color), [yellow])
        XCTAssertEqual(order(above.box).first, "rect")
        rect = above.rules[0].rect
        equal(rect.minX, try above.glyph("six").origin.x); equal(rect.maxX, try above.glyph("eight").right)
        equal(rect.maxY, above.box.ascent)
        XCTAssertGreaterThan(rect.minY, try above.glyph("six").ink.maxY)
        for carry in above.all("one") { XCTAssertTrue(rect.contains(carry.ink)) }
        // Carries beside the digits have no line of their own. Each takes it along, behind its own.
        let beside = try drawing("<mstack><mscarries location='w' mathbackground='yellow'><mn>1</mn><none/>"
            + "<mscarry mathbackground='red'><mn>2</mn></mscarry></mscarries><mn>345</mn></mstack>")
        XCTAssertEqual(beside.rules.map(\.color), [yellow, yellow, red])
        XCTAssertEqual(order(beside.box), ["glyphs", "glyphs", "glyphs", "rect", "glyphs", "rect", "rect", "glyphs"])
        for (index, name) in ["one", "two"].enumerated() {
            let carry = try beside.glyph(name)
            equal(beside.rules[index].rect.minX, carry.origin.x, name); equal(beside.rules[index].rect.width, carry.advance, name)
            XCTAssertTrue(beside.rules[index].rect.insetBy(dx: -0.01, dy: -0.01).contains(carry.ink), name)
        }
        XCTAssertEqual(beside.rules[1].rect, beside.rules[2].rect)
        equal(beside.rules[0].rect.maxX, try beside.glyph("three").origin.x)

        // A line's is the line, overhangs and all: behind it, for a colour that lets it show.
        let line = try drawing("<mstack><mn>123</mn><msline length='2' leftoverhang='0.5em' mslinethickness='3px' mathbackground='yellow'/>"
            + "<mn>456</mn></mstack>")
        XCTAssertEqual(line.rules.map(\.color), [yellow, black])
        XCTAssertEqual(line.rules[0].rect, line.rules[1].rect)
        equal(line.rules[0].rect.minX, try line.glyph("two").origin.x - 0.5 * em); equal(line.rules[0].rect.maxX, line.box.width)
        equal(line.rules[0].rect.height, 3)
        let clear = "<mstack><mn>123</mn><msline mathcolor='transparent' mathbackground='red' mslinethickness='3px'/><mn>456</mn></mstack>"
        let seen = try XCTUnwrap(inks(clear)[.red])
        XCTAssertEqual(seen.width, try stackBox(clear).width, accuracy: 0.5); XCTAssertEqual(seen.height, 3, accuracy: 0.5)
        XCTAssertTrue(try drawing("<mstack><mn>1</mn><msline mslinethickness='0' mathbackground='yellow'/></mstack>").rules.isEmpty)

        // In a division too, whether the result is a row of the dividend's stack or a stack of its own.
        for style in Self.styles {
            let division = try drawing("<mlongdiv longdivstyle=\"\(style)\"><mn>7</mn><msgroup mathbackground='yellow'><mn>58</mn>"
                + "</msgroup><mn>406</mn><msgroup position='1' mathbackground='red'><mn>35</mn><msline length='2'/></msgroup></mlongdiv>")
            let result = try XCTUnwrap(division.rules.first { $0.color == yellow }, style).rect
            let work = try XCTUnwrap(division.rules.first { $0.color == red }, style).rect
            XCTAssertTrue(result.contains(try division.glyph("eight").ink), style)
            equal(result.maxX, try division.glyph("eight").right, style)
            XCTAssertTrue(work.contains(try division.glyph("three").ink), style)
            equal(work.minX, try division.glyph("three").origin.x, style); equal(work.maxX, try division.glyph("zero").right, style)
        }
        // Outside a stack each is a stack of its own, whose box the engine fills once.
        for body in ["<msgroup mathbackground='yellow'><mn>1</mn></msgroup>", "<mscarries mathbackground='yellow'><mn>1</mn></mscarries>"] {
            XCTAssertEqual(try drawing(body).rules.map(\.color), [yellow], body)
        }
        XCTAssertEqual(try drawing("<msline length='2' mathbackground='yellow'/>").rules.map(\.color), [yellow, black])
    }

    /// A sign wider than the digits it shares a column with overflows the column (3.6.1.2). The
    /// background of what it is in goes as far as it does, not to the edge of the column.
    func testBackgroundsCoverWhatOverflowsAColumn() throws {
        let yellow = try XCTUnwrap(MathColor.parse("yellow"))
        func background(_ body: String, file: StaticString = #filePath, line: UInt = #line) throws -> (rect: CGRect, drawn: Drawing) {
            let drawn = try drawing(body)
            XCTAssertEqual(drawn.rules.map(\.color), [yellow], body, file: file, line: line)
            try assertCoversInk(body, file: file, line: line)
            return (try XCTUnwrap(drawn.rules.first, body, file: file, line: line).rect, drawn)
        }
        // A leading sign overflows the hundreds to the left, and its row's background with it.
        var (rect, sum) = try background("<mstack><mn>99</mn><msrow mathbackground='yellow'><mo>+</mo><mn>11</mn></msrow><mn>110</mn></mstack>")
        var plus = try sum.glyph("plus")
        XCTAssertLessThan(plus.origin.x, sum.row(2)[0].origin.x - 1, "the sign does overflow")
        equal(rect.minX, plus.origin.x); equal(rect.maxX, sum.row(1)[2].right)
        XCTAssertTrue(rect.contains(plus.ink))
        // A trailing one, to the right.
        (rect, sum) = try background("<mstack stackalign='right'><mn>123</mn><msrow mathbackground='yellow'><mn>456</mn><mo>+</mo></msrow></mstack>")
        plus = try sum.glyph("plus")
        XCTAssertGreaterThan(plus.right, try sum.glyph("three").right + 1)
        equal(rect.minX, try sum.glyph("four").origin.x); equal(rect.maxX, plus.right)
        XCTAssertTrue(rect.contains(plus.ink))
        // An mstyle's around the sign alone is the sign's box, and a number's beside it is still its digits'.
        (rect, sum) = try background("<mstack><mn>99</mn><msrow><mstyle mathbackground='yellow'><mo>+</mo></mstyle><mn>11</mn></msrow>"
            + "<mn>110</mn></mstack>")
        equal(rect.minX, try sum.glyph("plus").origin.x); equal(rect.maxX, try sum.glyph("plus").right)
        (rect, sum) = try background("<mstack><mn>99</mn><msrow><mo>+</mo><mn mathbackground='yellow'>11</mn></msrow><mn>110</mn></mstack>")
        equal(rect.minX, sum.row(1)[1].origin.x); equal(rect.maxX, sum.row(1)[2].right)
        // A group's follows its rows.
        (rect, sum) = try background("<mstack><msgroup mathbackground='yellow'><mn>99</mn><msrow><mo>+</mo><mn>11</mn></msrow></msgroup>"
            + "<mn>110</mn></mstack>")
        equal(rect.minX, try sum.glyph("plus").origin.x); equal(rect.maxX, sum.row(1)[2].right)
        // Carries wider than their column, where the spacing is a length and makes no room for them.
        (rect, sum) = try background("<mstack charspacing='0'><mscarries mathbackground='yellow'><mn>123</mn></mscarries><mn>4</mn></mstack>")
        XCTAssertLessThan(try sum.glyph("one").origin.x, try sum.glyph("four").origin.x - 1)
        equal(rect.minX, try sum.glyph("one").origin.x); equal(rect.maxX, try sum.glyph("three").right)
        // What is narrower than its column changes nothing: the column is still covered.
        (rect, sum) = try background("<mstack><msrow mathbackground='yellow'><mn>1,5</mn></msrow><mn>345</mn></mstack>")
        equal(rect.minX, try sum.glyph("three").origin.x); equal(rect.maxX, sum.box.width)
    }

    // MARK: Robustness

    func testInnerElementsOutsideAStackLayOut() throws {
        let row = "<msrow><mn>12</mn><mo>+</mo></msrow>"
        equal(try stackBox(row).width, try stackBox("<mstack>\(row)</mstack>").width)
        XCTAssertEqual(try drawing(row).glyphs.map(\.name), ["one", "two", "plus"])
        let orphans = [
            row, "<msgroup shift='1'><mn>12</mn><mn>34</mn></msgroup>", "<mscarries><mn>1</mn><none/></mscarries>",
            "<mscarry crossout='updiagonalstrike' location='w'><mn>1</mn></mscarry>", "<msline length='2'/>", "<msline/>",
            "<msrow/>", "<msgroup/>", "<mscarries/>", "<mscarry/>", "<mstack/>", "<msrow mathbackground='yellow'><mn>1</mn></msrow>",
        ]
        for body in orphans {
            let box = try stackBox(body)
            XCTAssertTrue(box.width.isFinite && box.ascent.isFinite && box.descent.isFinite && box.width >= 0, body)
            XCTAssertNoThrow(try layout("<mi>x</mi><mo>=</mo>\(body)<mo>+</mo><mfrac><mn>1</mn>\(body)</mfrac>"), body)
        }
        equal(try drawing("<mscarry><mn>1</mn></mscarry>").glyph("one").size, 0.6 * em)
        equal(try stackBox("<msline length='2'/>").width, 2 * (try drawing("<mn>0</mn>").glyphs[0].advance) + 0.1 * em)
        XCTAssertEqual(try drawing("<msrow mathbackground='yellow'><mn>1</mn></msrow>").rules.count, 1, "painted once")
        equal(try drawing("<msrow mathsize='2em' mathcolor='red'><mn>1</mn></msrow>").glyph("one").size, 2 * em, "sized once")
        // Elements in the wrong place inside a stack, and stacks inside stacks.
        let misplaced = [
            "<mstack><mscarry><mn>1</mn></mscarry><mn>23</mn></mstack>",
            "<mstack><msrow><msline/><mn>1</mn><msrow><mn>2</mn></msrow></msrow></mstack>",
            "<mstack><msrow><mstack><mn>12</mn><mn>34</mn></mstack><mn>5</mn></msrow>"
                + "<mlongdiv><mn>3</mn><mn>4</mn><mn>12</mn></mlongdiv></mstack>",
            "<mstack><mscarries><mscarries><mn>1</mn></mscarries><msline/><mscarry><mscarry><mn>2</mn></mscarry></mscarry>"
                + "</mscarries><mn>345</mn></mstack>",
            "<mstack><mn></mn><mn> </mn><none/><msrow><none/></msrow><mtext>total</mtext><mfrac><mn>1</mn><mn>2</mn></mfrac></mstack>",
            "<mlongdiv><msline/><mscarries><mn>1</mn></mscarries><mscarries><mn>1</mn></mscarries><msline/></mlongdiv>",
            "<mstack><mscarries><mn>1</mn></mscarries><msline/><mn>2</mn></mstack>",
        ]
        for body in misplaced { try assertCoversInk(body) }
        // Attributes that say nothing sensible are ignored.
        let odd = "<mstack stackalign='up' charalign='down' charspacing='wide' align='sideways 1.5'>"
            + "<mscarries location='north' crossout='scribble' position='left' scriptsizemultiplier='nan'><mn>1</mn></mscarries>"
            + "<msrow position='1.5'><mn>23</mn></msrow>"
            + "<msline length='-4' position='x' leftoverhang='far' mslinethickness='heavy'/>"
            + "<msgroup position='' shift='1e3'><mn>4</mn><mn>5</mn></msgroup></mstack>"
        let plain = "<mstack><mscarries><mn>1</mn></mscarries><mn>23</mn><msline/><mn>4</mn><mn>5</mn></mstack>"
        XCTAssertEqual(signature(try drawing(odd)), signature(try drawing(plain)))
    }

    func testHostileStacksAreBounded() throws {
        func assertLimit(_ body: String, size: CGFloat = 20, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertThrowsError(try layout(body, size: size), String(body.prefix(80)), file: file, line: line) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded, file: file, line: line)
            }
        }
        // Columns that cost nothing to ask for: a position, a shift or a length may not make the grid huge.
        for huge in ["999999999", "-999999999", "9223372036854775807", "-9223372036854775808", "30000"] {
            assertLimit("<mstack><mn>1</mn><msrow position='\(huge)'><mn>2</mn></msrow></mstack>")
            assertLimit("<mstack><msgroup shift='\(huge)'><mn>1</mn><mn>2</mn><mn>3</mn></msgroup></mstack>")
            assertLimit("<mstack><mn>1</mn><mscarries position='\(huge)'><mn>2</mn></mscarries><mn>3</mn></mstack>")
            assertLimit("<mstack><mn>1</mn><msline length='2' position='\(huge)'/></mstack>")
            assertLimit("<mstack><mn>1</mn><msgroup position='\(huge)'><msgroup position='\(huge)'><mn>2</mn></msgroup></msgroup></mstack>")
            assertLimit("<mlongdiv><mn>1</mn><mn>2</mn><mn>3</mn><msrow position='\(huge)'><mn>4</mn></msrow></mlongdiv>")
        }
        assertLimit("<mstack><mn>1</mn><msline length='999999999'/></mstack>")
        assertLimit("<mstack><msline length='9223372036854775807'/></mstack>")
        // Too large to be a number at all, it is no position.
        equal(try stackBox("<mstack><mn>1</mn><msrow position='99999999999999999999'><mn>2</mn></msrow></mstack>").width,
              try stackBox("<mstack><mn>1</mn><mn>2</mn></mstack>").width)
        // Where every row moves alike nothing is far from anything, and the stack is as small as ever.
        let rows = "<mn>12</mn><msrow position='1'><mn>34</mn></msrow>"
        equal(try stackBox("<mstack><msgroup position='999999999'>\(rows)</msgroup></mstack>").width,
              try stackBox("<mstack>\(rows)</mstack>").width)
        XCTAssertLessThan(try stackBox("<mstack><mn>1</mn><msrow position='1000'><mn>2</mn></msrow></mstack>").width, MathLimits.extent)
        // Lengths are clamped like any other, and too wide a result is refused.
        assertLimit("<mstack charspacing='999em'><mn>1234567890</mn></mstack>", size: 100)
        assertLimit("<mstack><mn>1</mn><msline leftoverhang='999em' rightoverhang='999em'/></mstack>", size: 100)
        XCTAssertLessThanOrEqual(try stackBox("<mstack><mn>1</mn><msline mslinethickness='999em'/></mstack>").height, 3 * em)
        // Depth: groups, styles, carries and stacks nest no deeper than anything else.
        func nested(_ open: String, _ close: String, _ count: Int = 100) -> String {
            String(repeating: open, count: count) + "<mn>1</mn>" + String(repeating: close, count: count)
        }
        assertLimit("<mstack>\(nested("<msgroup>", "</msgroup>"))</mstack>")
        assertLimit("<mstack><msrow>\(nested("<mstyle>", "</mstyle>"))</msrow></mstack>")
        assertLimit(nested("<mstack><msrow>", "</msrow></mstack>"))
        assertLimit(nested("<mstack><mscarries><mscarry>", "</mscarry></mscarries></mstack>"))
        assertLimit(nested("<mlongdiv><mn>1</mn><mn>2</mn>", "</mlongdiv>"))
        assertLimit(nested("<mscarry>", "</mscarry>"))
        XCTAssertNoThrow(try layout("<mstack>\(nested("<msgroup>", "</msgroup>", 40))</mstack>"))
        // Size: every digit, group, row, carry and line counts as a node, and digits as text.
        assertLimit("<mstack><mn>\(String(repeating: "7", count: 25_000))</mn></mstack>", size: 1)
        assertLimit("<mstack><mn>\(String(repeating: "7", count: 60_000))</mn></mstack>", size: 1)
        assertLimit("<mstack>\(String(repeating: "<mn>7</mn>", count: 5_000))</mstack>")
        let style = MathStyle(fontSize: 1, color: black)
        func tree(_ outer: String, _ inner: String, _ count: Int) -> MathMLNode {
            let child = MathMLNode(name: outer, children: Array(repeating: MathMLNode(name: inner), count: count))
            return MathMLNode(name: "math", children: [outer == "mstack" ? child : MathMLNode(name: "mstack", children: [child])])
        }
        for (outer, inner) in [("mstack", "msline"), ("mstack", "msrow"), ("mstack", "msgroup"), ("mstack", "mscarries"),
                               ("msrow", "none"), ("msrow", "mstyle"), ("mscarries", "none"), ("mscarries", "mscarry"),
                               ("msgroup", "msline")] {
            XCTAssertThrowsError(try MathLayout(tree(outer, inner, 30_000), style: style), "\(outer) of \(inner)") {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
            }
            XCTAssertNoThrow(try MathLayout(tree(outer, inner, 3_000), style: style), "\(outer) of \(inner)")
        }
        // Within the limits, large stacks lay out, and stay inside the bounds.
        let tall = try layout("<mstack>\(String(repeating: "<mn>7</mn><msline/>", count: 2_000))</mstack>", size: 2)
        XCTAssertLessThan(height(tall), MathLimits.extent)
        let wide = try layout("<mstack><mn>\(String(repeating: "7", count: 8_000))</mn><msline/></mstack>", size: 2)
        XCTAssertLessThan(wide.width, MathLimits.extent)
        XCTAssertGreaterThan(wide.width, 8_000)
    }

    /// More of the specification's examples (3.6.8.1), and that every box covers its ink.
    func testStacksCoverTheirInk() throws {
        let bodies = [
            "<mstack><mn>424</mn><msrow><mo>+</mo><none/><mn>33</mn></msrow><msline/></mstack>",
            "<mstack><mn>123</mn><msrow><mn>456</mn><mo>+</mo></msrow><msline/><mn>579</mn></mstack>",
            "<mstack stackalign='right'><msrow><mo>.</mo><none/><none/><none/><none/><mo>.</mo></msrow><mn> 0.142857 </mn></mstack>",
            "<mstack><mscarries location='w'><mn>12</mn><none/></mscarries><mn>34</mn></mstack>",
            "<mstack><mscarries location='e'><none/><mn>12</mn></mscarries><mn>34</mn></mstack>",
            "<mstack charspacing='0'><mscarries><mn>12345</mn><none/></mscarries><mn>34</mn></mstack>",
            "<mstack><mscarries location='s' crossout='verticalstrike horizontalstrike'><mn>1</mn><mn>2</mn></mscarries>"
                + "<mn>34</mn></mstack>",
            "<mstack charalign='center'><msrow><mtext>remainder</mtext><mn>1</mn></msrow><mn>22</mn></mstack>",
            "<mstack><msline length='2' leftoverhang='1em' rightoverhang='1em' mslinethickness='thick'/></mstack>",
            "<mstack><mn>12</mn><msrow><mfrac><mn>1</mn><mn>2</mn></mfrac><msqrt><mn>3</mn></msqrt></msrow></mstack>",
        ]
        for body in bodies {
            try assertCoversInk(body)
            for align in ["top", "bottom", "axis", "baseline 1"] {
                try assertCoversInk(body.replacingOccurrences(of: "<mstack", with: "<mstack align='\(align)'"))
            }
        }
        // One unbreakable box: beside other things it takes its width and nothing more.
        let alone = try layout(bodies[0]).width, x = try layout("<mi>x</mi>").width
        equal(try layout("<mi>x</mi>\(bodies[0])<mi>x</mi>").width, alone + 2 * x)
    }

    /// `decimalpoint` is `mstyle`'s attribute (3.3.4.2): a stack inherits it from any ancestor.
    func testDecimalPointIsInherited() throws {
        // German numbers: "." groups the thousands and "," is the decimal point.
        let rows = "<mn>1.234,5</mn><mn>12,75</mn>"
        let own = "<mstack decimalpoint=\",\">\(rows)</mstack>", plain = "<mstack>\(rows)</mstack>"
        func drawn(_ body: String) throws -> CGRect? { try ink(layout(body)) }
        XCTAssertNotEqual(try drawn(own), try drawn(plain), "aligned on the comma, the rows sit differently")
        XCTAssertEqual(try drawn("<mstyle decimalpoint=\",\">\(plain)</mstyle>"), try drawn(own))
        XCTAssertEqual(try drawn("<mstyle decimalpoint=\",\"><mfrac>\(plain)<mn>2</mn></mfrac></mstyle>"),
                       try drawn("<mfrac>\(own)<mn>2</mn></mfrac>"), "through any number of ancestors")
        // On the `math` element too.
        var root = try node(plain)
        root.attributes["decimalpoint"] = ","
        XCTAssertEqual(try ink(MathLayout(root, style: MathStyle(fontSize: 20, color: black))), try drawn(own))
        // The stack's own wins over an ancestor's, and an empty one sets nothing.
        XCTAssertEqual(try drawn("<mstyle decimalpoint=\"x\">\(own)</mstyle>"), try drawn(own))
        XCTAssertEqual(try drawn("<mstyle decimalpoint=\" \">\(plain)</mstyle>"), try drawn(plain))
    }
}
