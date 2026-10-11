import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// `mglyph` (MathML 3, 3.2.1.2): parsing, sizing, drawing the provider's image, and `alt` without one.
final class GlyphTests: MathTestCase {
    private let marker = "\u{FFFC}"
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    // MARK: Support

    private func bitmap(_ width: Int, _ height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// An image with a color in each quarter: red top left, green top right, blue bottom left
    /// and black bottom right, so a flipped or mirrored drawing shows.
    private func quarters(_ width: Int, _ height: Int) -> CGImage {
        let context = bitmap(width, height)
        let halfWidth = CGFloat(width) / 2, halfHeight = CGFloat(height) / 2
        let colors: [(CGFloat, CGFloat, [CGFloat])] = [
            (0, halfHeight, [1, 0, 0]), (halfWidth, halfHeight, [0, 1, 0]), (0, 0, [0, 0, 1]), (halfWidth, 0, [0, 0, 0]),
        ]
        for (x, y, color) in colors {
            context.setFillColor(CGColor(srgbRed: color[0], green: color[1], blue: color[2], alpha: 1))
            context.fill(CGRect(x: x, y: y, width: halfWidth, height: halfHeight))
        }
        return context.makeImage()!
    }

    private func provider(_ images: [String: CGImage]) -> MathImageProvider { MathImageProvider { images[$0] } }

    private func layout(_ body: String, images: MathImageProvider?, size: CGFloat = 20) throws -> MathLayout {
        try MathLayout(node(body), style: MathStyle(fontSize: size, color: black, imageProvider: images))
    }

    /// The box the engine makes of `node`, before the root grows it to cover its ink.
    private func box(_ node: MathMLNode, images: MathImageProvider?, size: CGFloat = 20) throws -> MathBox {
        let engine = LayoutEngine(fontName: nil)
        engine.imageProvider = images
        let context = LayoutContext(fontSize: size, unclampedSize: size, minSize: min(size, max(8, size * 0.6)),
                                    display: false, color: black)
        return try engine.layout(node, context, depth: 0)
    }

    private func box(_ body: String, images: MathImageProvider?, size: CGFloat = 20) throws -> MathBox {
        try box(node(body), images: images, size: size)
    }

    /// Where `box` draws images, relative to its baseline origin, in drawing order.
    private func imageRects(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .image(_, let rect): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let inner, let point): imageRects(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    /// The rectangles `box` fills, which are its backgrounds, relative to its baseline origin, in drawing order.
    private func fills(_ box: MathBox, at origin: CGPoint = .zero) -> [(rect: CGRect, color: CGColor)] {
        box.items.flatMap { item -> [(rect: CGRect, color: CGColor)] in
            switch item {
            case .rect(let rect, let color): [(rect.offsetBy(dx: origin.x, dy: origin.y), color)]
            case .box(let inner, let point): fills(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func glyphRuns(_ box: MathBox) -> [GlyphRun] {
        box.items.flatMap { item -> [GlyphRun] in
            switch item {
            case .glyphs(let run): [run]
            case .box(let inner, _): glyphRuns(inner)
            default: []
            }
        }
    }

    /// Draws `layout` and returns a reader of the RGBA drawn at a point relative to its
    /// baseline origin, y up.
    private func render(_ layout: MathLayout, margin: Int = 4) -> (CGFloat, CGFloat) -> [UInt8] {
        let width = Int(layout.width.rounded(.up)) + 2 * margin
        let height = Int(layout.ascent.rounded(.up)) + Int(layout.descent.rounded(.up)) + 2 * margin
        let context = bitmap(width, height)
        let baseline = CGFloat(margin) + layout.descent.rounded(.up)
        layout.draw(in: context, baselineOrigin: CGPoint(x: CGFloat(margin), y: baseline))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        return { x, y in
            // Bitmap rows run top-down. The context owns the pixels, so it lives as long as the reader.
            withExtendedLifetime(context) {
                let column = Int(CGFloat(margin) + x), row = height - 1 - Int(baseline + y)
                return (0..<4).map { pixels[(row * width + column) * 4 + $0] }
            }
        }
    }

    private func assertColor(_ pixel: [UInt8], _ expected: [UInt8], _ message: String = "",
                             file: StaticString = #filePath, line: UInt = #line) {
        for (actual, wanted) in zip(pixel, expected) {
            XCTAssertEqual(Int(actual), Int(wanted), accuracy: 12, "\(message) \(pixel)", file: file, line: line)
        }
    }

    private func assertRect(_ rect: CGRect?, _ expected: CGRect, accuracy: CGFloat = 0.01,
                            file: StaticString = #filePath, line: UInt = #line) {
        guard let rect else { return XCTFail("no rect", file: file, line: line) }
        XCTAssertEqual(rect.minX, expected.minX, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: accuracy, file: file, line: line)
    }

    private let red: [UInt8] = [255, 0, 0, 255], green: [UInt8] = [0, 255, 0, 255]
    private let blue: [UInt8] = [0, 0, 255, 255], opaqueBlack: [UInt8] = [0, 0, 0, 255]

    // MARK: Parsing

    func testParserKeepsAGlyphsAttributesAndMarksItsPlace() throws {
        let token = try node(#"<mi>a<mglyph src="img/s.png" alt="t" width="1em" height="2ex" valign="-3px"/>b</mi>"#).children[0]
        XCTAssertEqual(token.text, "a\(marker)b")
        XCTAssertEqual(token.children, [MathMLNode(name: "mglyph", attributes: [
            "src": "img/s.png", "alt": "t", "width": "1em", "height": "2ex", "valign": "-3px",
        ])])

        // Document order, and one marker each.
        let two = try node(#"<mtext><mglyph src="1" alt="one"/> and <mglyph src="2" alt="two"/></mtext>"#).children[0]
        XCTAssertEqual(two.text, "\(marker) and \(marker)")
        XCTAssertEqual(two.children.map { $0.attributes["src"] }, ["1", "2"])

        // Prefixed names resolve as they do on any element.
        let prefixed = try MathMLNode.parse(xml: Data("""
        <m:math xmlns:m="http://www.w3.org/1998/Math/MathML"><m:mo>+<m:mglyph m:src="s" alt="t"/></m:mo></m:math>
        """.utf8)).children[0]
        XCTAssertEqual(prefixed.text, "+\(marker)")
        XCTAssertEqual(prefixed.children, [MathMLNode(name: "mglyph", attributes: ["src": "s", "alt": "t"])])

        // Other children keep their attributes too, and leave no mark.
        let aligned = try node(#"<mtext>a<malignmark edge="right"/>b</mtext>"#).children[0]
        XCTAssertEqual(aligned.text, "ab")
        XCTAssertEqual(aligned.children, [MathMLNode(name: "malignmark", attributes: ["edge": "right"])])

        // Only a token's own children count, and only an mglyph writes the marker.
        let nested = try node(#"<mtext>a<maction><mglyph src="s"/>c</maction>b&#xFFFC;</mtext>"#).children[0]
        XCTAssertEqual(nested.text, "acb")
        XCTAssertEqual(nested.children, [MathMLNode(name: "maction")])

        // Outside a token an mglyph is an element like any other.
        let row = try node(#"<mrow><mglyph src="s" alt="t"/></mrow>"#).children[0]
        XCTAssertEqual(row.children, [MathMLNode(name: "mglyph", attributes: ["src": "s", "alt": "t"])])
        XCTAssertEqual(row.text, "")
    }

    // MARK: Size

    func testGlyphBoxComesFromWidthHeightAndValign() throws {
        let images = provider(["g": quarters(30, 20)])
        func glyph(_ attributes: String, size: CGFloat = 20) throws -> MathBox {
            try box("<mi><mglyph src=\"g\" alt=\"g\" \(attributes)/></mi>", images: images, size: size)
        }
        func assertBox(_ attributes: String, width: CGFloat, ascent: CGFloat, descent: CGFloat = 0, size: CGFloat = 20,
                       line: UInt = #line) throws {
            let box = try glyph(attributes, size: size)
            XCTAssertEqual(box.width, width, accuracy: 0.001, attributes, line: line)
            XCTAssertEqual(box.ascent, ascent, accuracy: 0.001, attributes, line: line)
            XCTAssertEqual(box.descent, descent, accuracy: 0.001, attributes, line: line)
            // The image fills the box: `valign` up from the baseline, `height` tall.
            XCTAssertEqual(imageRects(box).count, 1, attributes, line: line)
            assertRect(imageRects(box).first, CGRect(x: 0, y: -descent, width: width, height: ascent + descent), line: line)
        }
        // Neither: the image's pixels, as points.
        try assertBox("", width: 30, ascent: 20)
        try assertBox("", width: 30, ascent: 20, size: 40)
        // Both: as given, whatever the image's shape.
        try assertBox(#"width="12px" height="50px""#, width: 12, ascent: 50)
        // One: the other keeps the aspect ratio.
        try assertBox(#"width="15px""#, width: 15, ascent: 10)
        try assertBox(#"height="40px""#, width: 60, ascent: 40)
        // Font-relative units follow the token's font size.
        try assertBox(#"width="3em""#, width: 60, ascent: 40)
        try assertBox(#"width="3em""#, width: 30, ascent: 20, size: 10)
        try assertBox(#"width="3em" height="0.5em""#, width: 60, ascent: 10)
        let engine = LayoutEngine(fontName: nil)
        let ex = engine.xHeight(LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black))
        try assertBox(#"height="2ex""#, width: 3 * ex, ascent: 2 * ex)
        try assertBox(#"width="9pt""#, width: 12, ascent: 8)
        // Percentages and bare numbers are of the image's own size.
        try assertBox(#"width="50%""#, width: 15, ascent: 10)
        try assertBox(#"height="200%""#, width: 60, ascent: 40)
        try assertBox(#"width="50%" height="150%""#, width: 15, ascent: 30)
        try assertBox(#"width="2""#, width: 60, ascent: 40)
        // A length that does not parse is a missing one.
        try assertBox(#"width="wide" height="tall" valign="middle""#, width: 30, ascent: 20)
        // valign raises the bottom edge above the baseline, or lowers it below.
        try assertBox(#"valign="5px""#, width: 30, ascent: 25, descent: -5)
        try assertBox(#"valign="-8px""#, width: 30, ascent: 12, descent: 8)
        try assertBox(#"valign="-0.5em""#, width: 30, ascent: 10, descent: 10)
        try assertBox(#"valign="-0.5em""#, width: 30, ascent: 0, descent: 20, size: 40)
        try assertBox(#"width="12px" height="50px" valign="-20px""#, width: 12, ascent: 30, descent: 20)
        // Its default is zero, and a percentage or a multiple of zero is zero (MathML 3, 2.1.5.2).
        try assertBox(#"valign="-25%""#, width: 30, ascent: 20)
        try assertBox(#"valign="3""#, width: 30, ascent: 20)

        // A script's glyph is sized by the script's em; an unsized image does not shrink.
        let script = try box(#"<msup><mi>x</mi><mi><mglyph src="g" alt="g" width="1em"/></mi></msup>"#, images: images)
        XCTAssertEqual(imageRects(script).first?.width ?? 0, 20 * 0.7, accuracy: 0.01)
        let unsized = try box(#"<msup><mi>x</mi><mi><mglyph src="g" alt="g"/></mi></msup>"#, images: images)
        XCTAssertEqual(imageRects(unsized).first?.size, CGSize(width: 30, height: 20))

        // The public box covers the same extents; a raised image leaves no descent.
        let lowered = try layout(#"<mi><mglyph src="g" alt="g" width="12px" height="50px" valign="-20px"/></mi>"#, images: images)
        XCTAssertEqual([lowered.width, lowered.ascent, lowered.descent], [12, 30, 20])
        let raised = try layout(#"<mi><mglyph src="g" alt="g" valign="5px"/></mi>"#, images: images)
        XCTAssertEqual([raised.width, raised.ascent, raised.descent], [30, 25, 0])
    }

    func testGlyphWithoutASizeIsEmpty() throws {
        let images = provider(["g": quarters(30, 20)])
        for attributes in [#"width="0px""#, #"height="0""#, #"width="-5px""#, #"height="-1em""#, #"width="10px" height="0%""#,
                           #"width="-10px" height="-10px""#] {
            let body = "<mi><mglyph src=\"g\" alt=\"g\" \(attributes)/></mi>"
            let box = try box(body, images: images)
            XCTAssertEqual([box.width, box.ascent, box.descent], [0, 0, 0], attributes)
            XCTAssertNil(ink(try layout(body, images: images)), attributes)
        }
        // It takes no part in its token's extents either.
        let body = #"<mtext>a<mglyph src="g" alt="g" width="0px" height="90px" valign="-40px"/>b</mtext>"#
        let token = try box(body, images: images)
        let a = try box("<mtext>a</mtext>", images: nil), b = try box("<mtext>b</mtext>", images: nil)
        XCTAssertEqual(token.ascent, max(a.ascent, b.ascent))
        XCTAssertEqual(token.descent, max(a.descent, b.descent))
        XCTAssertEqual(token.width, a.width + b.width, accuracy: 0.001)
        XCTAssertTrue(imageRects(token).isEmpty)
    }

    // MARK: Drawing

    func testImageIsDrawnUprightInItsBox() throws {
        let image = quarters(20, 40)
        // What "upright" means here: a bitmap's first row is its top, and this one's starts red.
        let bytes = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertEqual(Array(bytes.prefix(4)), red)
        XCTAssertEqual(Array(bytes.suffix(4)), opaqueBlack)

        let body = #"<mi><mglyph src="g" alt="g"/></mi>"#
        let drawn = try layout(body, images: provider(["g": image]))
        assertRect(ink(drawn), CGRect(x: 0, y: 0, width: 20, height: 40), accuracy: 0.5)
        var pixel = render(drawn)
        assertColor(pixel(5, 30), red, "top left")
        assertColor(pixel(15, 30), green, "top right")
        assertColor(pixel(5, 10), blue, "bottom left")
        assertColor(pixel(15, 10), opaqueBlack, "bottom right")
        assertColor(pixel(-2, 20), [0, 0, 0, 0], "outside")

        // Without the provider the same markup draws its alt text: other ink, and none of it colored.
        let fallback = try layout(body, images: nil)
        XCTAssertNotEqual(ink(fallback), ink(drawn))
        XCTAssertEqual(fallback.width, try layout("<mtext>g</mtext>").width)
        pixel = render(fallback)
        for x in stride(from: CGFloat(0), to: fallback.width, by: 1) {
            for y in stride(from: -fallback.descent, to: fallback.ascent, by: 1) {
                let color = pixel(x, y)
                XCTAssertEqual(color[0], 0); XCTAssertEqual(color[1], 0); XCTAssertEqual(color[2], 0)
            }
        }

        // Stretched and lowered, each quarter is still in its corner of the box.
        let scaled = try layout(#"<mi><mglyph src="g" alt="g" width="60px" height="30px" valign="-10px"/></mi>"#,
                                images: provider(["g": image]))
        assertRect(ink(scaled), CGRect(x: 0, y: -10, width: 60, height: 30), accuracy: 0.5)
        pixel = render(scaled)
        assertColor(pixel(15, 12), red, "top left")
        assertColor(pixel(45, 12), green, "top right")
        assertColor(pixel(15, -3), blue, "bottom left")
        assertColor(pixel(45, -3), opaqueBlack, "bottom right")

        // Beside text, at the baseline origin the host asked for.
        let beside = try layout(#"<mtext>a<mglyph src="g" alt="g" width="10px" height="20px"/></mtext>"#,
                                images: provider(["g": image]))
        let a = try layout("<mtext>a</mtext>").width
        XCTAssertEqual(beside.width, a + 10, accuracy: 0.001)
        pixel = render(beside)
        assertColor(pixel(a + 2.5, 15), red, "top left")
        assertColor(pixel(a + 7.5, 5), opaqueBlack, "bottom right")
    }

    func testBackgroundShowsThroughATransparentImage() throws {
        let images = provider(["clear": bitmap(10, 10).makeImage()!])
        // In a token, and at row level where the element itself must not paint it a second time.
        for body in [##"<mi><mglyph src="clear" alt="c" mathbackground="#ff000080" mathcolor="blue"/></mi>"##,
                     ##"<mglyph src="clear" alt="c" mathbackground="#ff000080" mathcolor="blue"/>"##] {
            let drawn = try layout(body, images: images)
            assertRect(ink(drawn), CGRect(x: 0, y: 0, width: 10, height: 10), accuracy: 0.5)
            assertColor(render(drawn)(5, 5), [128, 0, 0, 128], body)
        }
        XCTAssertNil(ink(try layout(#"<mi><mglyph src="clear" alt="c"/></mi>"#, images: images)))
    }

    /// MathML 3, 3.1.10: `mathbackground` fills "the bounding box of the element". Without its
    /// image that is the box of the `alt` drawn for it.
    func testBackgroundIsPaintedBehindTheAltText() throws {
        let half = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 128.0 / 255)
        let glyph = ##"<mglyph src="s" alt="L" mathbackground="#ff000080"/>"##
        let alt = try box("<mtext>L</mtext>", images: nil)
        // In a token, in an operator, and at row level where the element itself must not paint it a second time.
        for body in ["<mi>\(glyph)</mi>", "<mo>\(glyph)</mo>", glyph] {
            for images in [nil, MathImageProvider { _ in nil }] {
                let fallback = try box(body, images: images)
                XCTAssertEqual(fallback.width, alt.width, body)
                XCTAssertEqual(fills(fallback).map(\.color), [half], body)
                assertRect(fills(fallback).first?.rect, CGRect(x: 0, y: -alt.descent, width: alt.width, height: alt.height))
                let drawn = try layout(body, images: images)
                let pixel = render(drawn)
                // An L leaves the top right of its box empty, and nothing is painted above the box.
                assertColor(pixel(alt.width - 1.5, alt.ascent - 1.5), [128, 0, 0, 128], body)
                assertColor(pixel(alt.width - 1.5, alt.ascent + 1.5), [0, 0, 0, 0], body)
                // The letter is drawn over the background, not under it.
                let row = stride(from: CGFloat(0.5), to: alt.width, by: 1).map { pixel($0, alt.ascent / 2) }
                XCTAssertTrue(row.contains { $0[0] < 64 && $0[3] > 200 }, body)
            }
        }
        XCTAssertTrue(fills(try box(#"<mi><mglyph src="s" alt="L"/></mi>"#, images: nil)).isEmpty)

        // Among text, behind the alt alone, and the text keeps its place.
        func part(_ body: String) throws -> MathBox { try box(body, images: nil) }
        let a = try part("<mtext>a</mtext>"), braid = try part("<mtext>braid</mtext>"), b = try part("<mtext>b</mtext>")
        let among = try part(##"<mtext>a<mglyph src="s" alt="braid" mathbackground="#00ff00"/>b</mtext>"##)
        XCTAssertEqual(among.width, a.width + braid.width + b.width, accuracy: 0.001)
        XCTAssertEqual(fills(among).count, 1)
        assertRect(fills(among).first?.rect, CGRect(x: a.width, y: -braid.descent, width: braid.width, height: braid.height))
        XCTAssertEqual(glyphRuns(among).count, 3)
        // Behind U+25AF when there is no alt.
        let missing = try part("<mtext>\u{25AF}</mtext>")
        for attributes in ["", #"alt="""#, #"alt="  ""#] {
            let empty = try part("<mi><mglyph \(attributes) mathbackground=\"#00ff00\"/></mi>")
            XCTAssertEqual(empty.width, missing.width, attributes)
            assertRect(fills(empty).first?.rect, CGRect(x: 0, y: -missing.descent, width: missing.width, height: missing.height))
        }
        // The alt is still drawn as its token's text is: in its variant, size and color.
        let styled = ##"<mtext mathvariant="bold" mathsize="2em" mathcolor="#0000ff">@</mtext>"##
        let plain = try part(styled.replacingOccurrences(of: "@", with: "b"))
        let onGreen = try part(styled.replacingOccurrences(of: "@", with: ##"<mglyph alt="b" mathbackground="#00ff00"/>"##))
        XCTAssertEqual(onGreen.width, plain.width)
        XCTAssertEqual(glyphRuns(onGreen).map(\.glyphs), glyphRuns(plain).map(\.glyphs))
        XCTAssertEqual(glyphRuns(onGreen).map(\.color), [CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)])
        assertRect(fills(onGreen).first?.rect, CGRect(x: 0, y: -plain.descent, width: plain.width, height: plain.height))
        // The token's own background is behind all of it, and painted first.
        let both = try part(##"<mtext mathbackground="#0000ff">a<mglyph alt="braid" mathbackground="#00ff00"/></mtext>"##)
        XCTAssertEqual(fills(both).map(\.color), [CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1),
                                                  CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)])
        XCTAssertEqual(fills(both).first?.rect.width ?? 0, a.width + braid.width, accuracy: 0.001)
        XCTAssertEqual(fills(both).last?.rect.minX ?? 0, a.width, accuracy: 0.001)
        // A color that does not parse is no background, nor is the default: the alt stays part of the text.
        for color in ["greenish", "transparent", "#00ff0000"] {
            let none = try part("<mtext>a<mglyph alt=\"braid\" mathbackground=\"\(color)\"/>b</mtext>")
            XCTAssertTrue(fills(none).isEmpty, color)
            XCTAssertEqual(glyphRuns(none).count, 1, color)
            XCTAssertEqual(none.width, try part("<mtext>abraidb</mtext>").width, color)
        }

        // An alt on a background counts against the text bound like any other, across tokens.
        func long(_ units: Int) -> MathMLNode {
            MathMLNode(name: "mi", children: [MathMLNode(name: "mglyph", attributes: [
                "alt": String(repeating: "a", count: units), "mathbackground": "red",
            ])])
        }
        XCTAssertNoThrow(try box(MathMLNode(name: "mrow", children: [long(100), long(100)]), images: nil))
        let each = MathLimits.textLength / 2 + 1
        XCTAssertThrowsError(try box(MathMLNode(name: "mrow", children: [long(each), long(each)]), images: nil)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    // MARK: The provider

    func testProviderIsAskedOncePerSource() throws {
        let image = quarters(4, 4)
        let asked = Recorder()
        let images = MathImageProvider { source in
            asked.add(source)
            return source.hasPrefix("missing") ? nil : image
        }
        let body = """
        <mi><mglyph src="a.png" alt="a"/></mi><mo><mglyph src="a.png" alt="a"/></mo><mglyph src="a.png" alt="a"/>\
        <mtext><mglyph src="../img/b c.png?x=1#y" alt="b"/><mglyph src="missing" alt="m"/><mglyph src="missing" alt="m"/></mtext>\
        <mi><mglyph alt="no source"/></mi><mi><mglyph src="" alt="empty"/></mi>\
        <mi><mglyph fontfamily="my-braid-font" index="2" alt="23braid"/></mi>
        """
        _ = try layout(body, images: images)
        // Once each, found or not, with the source as written; never without one.
        XCTAssertEqual(asked.values.sorted(), ["../img/b c.png?x=1#y", "a.png", "missing"])
        // Once per layout: another layout asks again.
        _ = try layout(body, images: images)
        XCTAssertEqual(asked.values.count, 6)
    }

    func testStyleEqualityFollowsTheProvider() {
        let image = quarters(2, 2)
        let images = MathImageProvider { _ in image }
        let copy = images
        let other = MathImageProvider { _ in image }
        XCTAssertEqual(images, copy)
        XCTAssertNotEqual(images, other, "closures cannot be compared, so only a copy is equal")
        func style(_ provider: MathImageProvider?) -> MathStyle { MathStyle(fontSize: 17, color: black, imageProvider: provider) }
        XCTAssertEqual(style(images), style(images))
        XCTAssertEqual(style(images), style(copy))
        XCTAssertNotEqual(style(images), style(other))
        XCTAssertNotEqual(style(images), style(nil))
        XCTAssertEqual(style(nil), MathStyle(fontSize: 17, color: black), "no provider by default")
        var changed = style(nil)
        changed.imageProvider = copy
        XCTAssertEqual(changed, style(images))
    }

    func testLayoutWithImagesIsThreadSafe() throws {
        let image = quarters(20, 40)
        let images = MathImageProvider { $0 == "g" ? image : nil }
        let parsed = try node(#"<mi>x</mi><mo>=</mo><mi><mglyph src="g" alt="g" width="1em"/></mi><mo>+</mo><mglyph src="h" alt="h"/>"#)
        let style = MathStyle(fontSize: 19, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), imageProvider: images)
        let reference = try MathLayout(parsed, style: style)
        let expected = drawing(reference)
        XCTAssertTrue(expected.contains { $0 != 0 })
        let failures = Recorder()
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            // Half lay out afresh, half draw the one layout from many threads.
            let layout = index % 2 == 0 ? try? MathLayout(parsed, style: style) : reference
            guard let layout, layout.width == reference.width, layout.ascent == reference.ascent,
                  drawing(layout) == expected else { return failures.add("\(index)") }
        }
        XCTAssertEqual(failures.values, [])
    }

    // MARK: Fallback

    func testFallsBackToAltTextWithoutAnImage() throws {
        let none = MathImageProvider { _ in nil }
        let width = { (body: String) in try self.layout(body).width }
        for images in [nil, none] {
            // The alt text is part of the token's text: shaped with it, at the same width.
            XCTAssertEqual(try layout(#"<mtext>a<mglyph src="s" alt="braid"/>b</mtext>"#, images: images).width,
                           try width("<mtext>abraidb</mtext>"))
            XCTAssertEqual(try layout(#"<mi><mglyph src="s" alt="2 3 braid"/></mi>"#, images: images).width,
                           try width("<mtext>2 3 braid</mtext>"))
            XCTAssertEqual(try layout(#"<mn>1<mglyph src="s" alt="0"/></mn>"#, images: images).width, try width("<mn>10</mn>"))
            XCTAssertEqual(try layout(#"<ms><mglyph src="s" alt="x"/></ms>"#, images: images).width, try width("<ms>x</ms>"))
            XCTAssertNotNil(ink(try layout(#"<mi><mglyph src="s" alt="braid"/></mi>"#, images: images)))
        }
        // In the token's style: its variant, size and color.
        XCTAssertEqual(try width(#"<mtext mathvariant="bold">a<mglyph src="s" alt="b"/></mtext>"#),
                       try width(#"<mtext mathvariant="bold">ab</mtext>"#))
        XCTAssertNotEqual(try width(#"<mtext mathvariant="bold"><mglyph src="s" alt="b"/></mtext>"#),
                          try width(#"<mtext><mglyph src="s" alt="b"/></mtext>"#))
        XCTAssertEqual(try width(#"<mtext mathsize="2em"><mglyph src="s" alt="b"/></mtext>"#),
                       2 * (try width("<mtext>b</mtext>")), accuracy: 0.01)
        let colored = try box(##"<mtext mathcolor="#ff0000"><mglyph src="s" alt="b" mathcolor="#0000ff"/></mtext>"##, images: nil)
        XCTAssertEqual(glyphRuns(colored).map(\.color), [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)])
        // An mi of one glyph is not a single-letter identifier: its alt stays upright.
        XCTAssertEqual(try width(#"<mi><mglyph src="s" alt="x"/></mi>"#), try width(#"<mi mathvariant="normal">x</mi>"#))
        XCTAssertNotEqual(try width(#"<mi><mglyph src="s" alt="x"/></mi>"#), try width("<mi>x</mi>"))
        XCTAssertEqual(try width(#"<mi mathvariant="italic"><mglyph src="s" alt="x"/></mi>"#), try width("<mi>x</mi>"))
        // The alt is normalized like token text.
        XCTAssertEqual(try width("<mi><mglyph src=\"s\" alt=\"  2 \t 3  \"/></mi>"), try width("<mtext>2 3</mtext>"))
        // MathML 2's glyph of a named font has no image even with a provider.
        let some = provider(["s": quarters(4, 4)])
        XCTAssertEqual(try layout(#"<mi><mglyph fontfamily="my-braid-font" index="2" alt="23braid"/></mi>"#, images: some).width,
                       try width("<mtext>23braid</mtext>"))
    }

    func testGlyphWithoutAltDrawsAWhiteRectangle() throws {
        let rectangle = try layout("<mtext>\u{25AF}</mtext>")
        XCTAssertGreaterThan(rectangle.width, 0)
        for body in [#"<mi><mglyph src="s"/></mi>"#, #"<mi><mglyph src="s" alt=""/></mi>"#, #"<mi><mglyph src="s" alt="  "/></mi>"#,
                     "<mi><mglyph/></mi>", "<mglyph/>", "<mi><mglyph alt=\"\u{FFFC}\"/></mi>"] {
            for images in [nil, MathImageProvider { _ in nil }] {
                let fallback = try layout(body, images: images)
                XCTAssertEqual(fallback.width, rectangle.width, body)
                XCTAssertEqual(ink(fallback), ink(rectangle), body)
            }
        }
        XCTAssertEqual(try layout(#"<mtext>a<mglyph src="s"/>b</mtext>"#).width, try layout("<mtext>a\u{25AF}b</mtext>").width)
    }

    // MARK: Placement

    func testTextAndGlyphsKeepTheirOrder() throws {
        let images = provider(["g": quarters(10, 10), "h": quarters(6, 30)])
        func textWidth(_ text: String) throws -> CGFloat { try box("<mtext>\(text)</mtext>", images: nil).width }
        let a = try textWidth("a"), bc = try textWidth("bc")

        let mixed = try box(#"<mtext>a<mglyph src="g" alt="g"/>bc<mglyph src="h" alt="h"/></mtext>"#, images: images)
        XCTAssertEqual(mixed.width, a + 10 + bc + 6, accuracy: 0.001)
        XCTAssertEqual(imageRects(mixed), [CGRect(x: a, y: 0, width: 10, height: 10),
                                           CGRect(x: a + 10 + bc, y: 0, width: 6, height: 30)])
        // The extents of the tallest and the deepest part.
        let letters = try box("<mtext>abc</mtext>", images: nil)
        XCTAssertLessThan(letters.ascent, 30)
        XCTAssertEqual(mixed.ascent, 30)
        XCTAssertEqual(mixed.descent, letters.descent)
        XCTAssertGreaterThan(letters.descent, 0)

        let leading = try box(#"<mi><mglyph src="h" alt="h"/><mglyph src="g" alt="g"/>bc</mi>"#, images: images)
        XCTAssertEqual(imageRects(leading).map(\.minX), [0, 6])
        XCTAssertEqual(leading.width, 16 + bc, accuracy: 0.001)

        // An image and an alt text in one token, each where its mglyph stands.
        let half = provider(["g": quarters(10, 10)])
        let partly = try box(#"<mtext>a<mglyph src="h" alt="H"/>b<mglyph src="g" alt="g"/>c</mtext>"#, images: half)
        let before = try textWidth("aHb")
        XCTAssertEqual(imageRects(partly), [CGRect(x: before, y: 0, width: 10, height: 10)])
        XCTAssertEqual(partly.width, before + 10 + (try textWidth("c")), accuracy: 0.001)

        // Whitespace collapses around a glyph as around a character, and is trimmed outside it.
        let spaced = try box("<mi>  a  <mglyph src=\"g\" alt=\"g\"/>\n b </mi>", images: images)
        XCTAssertEqual(imageRects(spaced).map(\.minX), [try textWidth("a ")])
        XCTAssertEqual(spaced.width, (try textWidth("a ")) + 10 + (try textWidth(" b")), accuracy: 0.001)
        let alone = try box("<mi>\n  <mglyph src=\"g\" alt=\"g\"/>\n</mi>", images: images)
        XCTAssertEqual([alone.width, alone.ascent, alone.descent], [10, 10, 0])
        // As it is around text alone: an indented identifier is still one letter, and an operator itself.
        XCTAssertEqual(try box("<mi>\n  x\n</mi>", images: nil).width, try box("<mi>x</mi>", images: nil).width)
        XCTAssertEqual(try box("<mi>a</mi><mo>\n  +\n</mo><mi>b</mi>", images: nil).width,
                       try box("<mi>a</mi><mo>+</mo><mi>b</mi>", images: nil).width)
        XCTAssertEqual(LayoutEngine.normalized(" a \n b "), "a b")
        XCTAssertEqual(LayoutEngine.normalized(" a \n b ", trimming: false), " a b ")

        // The pixels agree: red (the image's top left) starts where "a" ends.
        let drawn = try layout(#"<mtext>a<mglyph src="g" alt="g"/>bc</mtext>"#, images: images)
        let pixel = render(drawn)
        assertColor(pixel(a + 2, 7), red)
        assertColor(pixel(a + 8, 7), green)
    }

    func testHandBuiltNodesNeedNoMarkers() throws {
        let images = provider(["g": quarters(10, 10), "h": quarters(6, 30)])
        let g = MathMLNode(name: "mglyph", attributes: ["src": "g", "alt": "g"])
        let h = MathMLNode(name: "mglyph", attributes: ["src": "h", "alt": "h"])
        func textWidth(_ text: String) throws -> CGFloat { try box(MathMLNode(name: "mtext", text: text), images: nil).width }
        let ab = try textWidth("ab"), a = try textWidth("a"), b = try textWidth("b")

        // No marker at all: the glyphs follow the text, in order.
        let alone = try box(MathMLNode(name: "mi", children: [g]), images: images)
        XCTAssertEqual(imageRects(alone), [CGRect(x: 0, y: 0, width: 10, height: 10)])
        XCTAssertEqual(alone.width, 10)
        let after = try box(MathMLNode(name: "mtext", children: [g, h], text: "ab"), images: images)
        XCTAssertEqual(imageRects(after).map(\.minX), [ab, ab + 10])
        XCTAssertEqual(imageRects(after).map(\.width), [10, 6])
        XCTAssertEqual(after.width, ab + 16, accuracy: 0.001)

        // Fewer markers than glyphs: the marked ones in place, the rest after.
        let some = try box(MathMLNode(name: "mtext", children: [g, h], text: "a\(marker)b"), images: images)
        XCTAssertEqual(imageRects(some).map(\.minX), [a, a + 10 + b])
        XCTAssertEqual(imageRects(some).map(\.width), [10, 6])

        // The same without a provider, as text.
        XCTAssertEqual(try box(MathMLNode(name: "mtext", children: [g, h], text: "ab"), images: nil).width, try textWidth("abgh"))
        XCTAssertEqual(try box(MathMLNode(name: "ms", children: [g], text: "ab"), images: nil).width,
                       try box(MathMLNode(name: "ms", text: "abg"), images: nil).width, "inside the quotes")
        XCTAssertEqual(try box(MathMLNode(name: "mo", children: [g], text: "a"), images: nil).width, try textWidth("ag"))

        // A marker with no glyph left for it draws nothing.
        XCTAssertEqual(try box(MathMLNode(name: "mtext", text: "a\(marker)b"), images: images).width, ab)
        XCTAssertEqual(try box(MathMLNode(name: "mtext", text: "a \(marker) b"), images: images).width, try textWidth("a b"))
        let stray = try box(MathMLNode(name: "mi", text: marker), images: images)
        XCTAssertEqual(stray.width, 0)
        XCTAssertTrue(stray.items.isEmpty)
        XCTAssertEqual(try box(MathMLNode(name: "mi", text: "x\(marker)"), images: images).width,
                       try box(MathMLNode(name: "mi", text: "x"), images: images).width, "still a single-letter identifier")
        XCTAssertEqual(try box(MathMLNode(name: "mo", text: "+\(marker)"), images: images).width,
                       try box(MathMLNode(name: "mo", text: "+"), images: images).width)
        let extra = try box(MathMLNode(name: "mtext", children: [g], text: "\(marker)a\(marker)"), images: images)
        XCTAssertEqual(imageRects(extra).map(\.minX), [0])
        XCTAssertEqual(extra.width, 10 + a, accuracy: 0.001)
        // Nor does one in an attribute that is drawn.
        let quoted = MathMLNode(name: "ms", attributes: ["lquote": "\(marker)<", "rquote": ">"], children: [g], text: "a")
        XCTAssertEqual(imageRects(try box(quoted, images: images)).map(\.minX), [try textWidth("<a")])
    }

    func testGlyphsInNumbersAndOperators() throws {
        let images = provider(["g": quarters(10, 10)])
        let sized = #"<mglyph src="g" alt="+"/>"#
        func width(_ body: String) throws -> CGFloat { try box(body, images: images).width }
        XCTAssertEqual(try width("<mn>1\(sized)2</mn>"), (try width("<mn>1</mn>")) + 10 + (try width("<mn>2</mn>")), accuracy: 0.001)
        XCTAssertEqual(try width("<ms>\(sized)</ms>"), 10 + 2 * (try width("<mtext>\"</mtext>")), accuracy: 0.001)

        // An mo of only an image is an operator the dictionary does not know: a thick space each side.
        let em: CGFloat = 20
        let operands = try width("<mi>a</mi>") + width("<mi>b</mi>")
        let unknown = try box(node("<mo>\(sized)</mo>").children[0], images: images)
        XCTAssertEqual(unknown.width, 10)
        XCTAssertEqual(unknown.op?.lspace ?? 0, em * 5 / 18, accuracy: 0.001)
        XCTAssertEqual(unknown.op?.rspace ?? 0, em * 5 / 18, accuracy: 0.001)
        XCTAssertEqual(unknown.op?.flags, [])
        XCTAssertEqual(unknown.op?.isBinary, false)
        XCTAssertEqual(try width("<mi>a</mi><mo>\(sized)</mo><mi>b</mi>"), operands + 10 + 2 * em * 5 / 18, accuracy: 0.001)
        // Its alt is a description, not the operator's name: drawn, but not looked up.
        let plus = try box("<mo>+</mo>", images: nil).width
        XCTAssertEqual(try box("<mi>a</mi><mo>\(sized)</mo><mi>b</mi>", images: nil).width,
                       operands + (try box("<mtext>+</mtext>", images: nil).width) + 2 * em * 5 / 18, accuracy: 0.001)
        // Text beside the image does name one, and keeps that operator's properties.
        XCTAssertEqual(try width("<mi>a</mi><mo>+\(sized)</mo><mi>b</mi>"),
                       operands + (try box("<mtext>+</mtext>", images: nil).width) + 10 + 2 * em * 4 / 18, accuracy: 0.001)
        XCTAssertEqual(try box("<mo>+\(sized)</mo>", images: images).op?.isBinary, true)
        XCTAssertEqual(try width("<mi>a</mi><mo>+</mo><mi>b</mi>"), operands + plus + 2 * em * 4 / 18, accuracy: 0.001)
        // An invisible operator beside an image still shows the image.
        XCTAssertEqual(try width("<mo>\u{2062}\(sized)</mo>"), 10)
        // The image keeps its author's size: not stretched as a fence, nor enlarged as a large operator.
        let tall = "<mfrac><mfrac><mi>a</mi><mi>b</mi></mfrac><mi>c</mi></mfrac>"
        let fence = try box("<mrow><mo>(\(sized)</mo>\(tall)<mo>)</mo></mrow>", images: images)
        XCTAssertEqual(imageRects(fence).map(\.size), [CGSize(width: 10, height: 10)])
        XCTAssertEqual(imageRects(fence).first?.minY, 0)
        let large = try MathLayout(node("<mo>∑\(sized)</mo>", display: true),
                                   style: MathStyle(fontSize: 20, color: black, imageProvider: images))
        XCTAssertEqual(height(large), height(try layout("<mo>∑</mo>")), accuracy: 0.01, "the text-style sum beside it")
        XCTAssertLessThan(height(large), height(try layout("<mo>∑</mo>", display: true)))
        // Space-like or not as its token is.
        let engine = LayoutEngine(fontName: nil)
        XCTAssertTrue(engine.isSpaceLike(try node("<mtext>\(sized)</mtext>").children[0]))
        XCTAssertFalse(engine.isSpaceLike(try node("<mi>\(sized)</mi>").children[0]))
        XCTAssertFalse(engine.isSpaceLike(try node("<mo>\(sized)</mo>").children[0]))
        XCTAssertNotNil(engine.embellishedCore(try node("<mo>\(sized)</mo>").children[0]))
    }

    func testRowLevelGlyphIsLaidOutAsText() throws {
        let images = provider(["g": quarters(10, 10)])
        let glyph = #"<mglyph src="g" alt="braid" width="12px" height="8px" valign="-2px"/>"#
        let wraps: [(String) -> String] = [
            { $0 }, { "<mrow><mi>a</mi>\($0)</mrow>" }, { "<mfrac>\($0)<mn>2</mn></mfrac>" }, { "<msup><mi>x</mi>\($0)</msup>" },
            { "<mtable><mtr><mtd>\($0)</mtd></mtr></mtable>" },
        ]
        for wrap in wraps {
            for provider in [images, nil] {
                let bare = try box(wrap(glyph), images: provider)
                let wrapped = try box(wrap("<mtext>\(glyph)</mtext>"), images: provider)
                XCTAssertEqual(bare.width, wrapped.width, wrap(glyph))
                XCTAssertEqual(bare.ascent, wrapped.ascent, wrap(glyph))
                XCTAssertEqual(bare.descent, wrapped.descent, wrap(glyph))
                XCTAssertEqual(imageRects(bare), imageRects(wrapped), wrap(glyph))
                XCTAssertEqual(imageRects(bare).count, provider == nil ? 0 : 1)
            }
        }
        let alone = try box(glyph, images: images)
        XCTAssertEqual([alone.width, alone.ascent, alone.descent], [12, 6, 2])
        XCTAssertEqual(try layout("<mi>a</mi>\(glyph)").width, try layout("<mi>a</mi><mtext>braid</mtext>").width)

        // Space-like, as mtext is: an operator between two is spaced as between two texts.
        let engine = LayoutEngine(fontName: nil)
        XCTAssertTrue(engine.isSpaceLike(MathMLNode(name: "mglyph")))
        XCTAssertTrue(engine.isSpaceLike(try node("<mrow>\(glyph)<mspace width=\"1em\"/></mrow>").children[0]))
        XCTAssertEqual(try layout(#"<mglyph alt="a"/><mo>=</mo><mglyph alt="b"/>"#).width,
                       try layout("<mtext>a</mtext><mo>=</mo><mtext>b</mtext>").width)
        XCTAssertEqual(try layout("\(glyph)<mo>=</mo>\(glyph)", images: images).width,
                       24 + (try layout("<mo>=</mo>").width) + 2 * 20 * 5 / 18, accuracy: 0.01)
    }

    // MARK: Bounds

    func testHostileGlyphSizesAreBounded() throws {
        let extent = MathLimits.extent
        let images = provider(["g": quarters(30, 20), "wide": bitmap(60_000, 1).makeImage()!,
                               "tall": bitmap(1, 60_000).makeImage()!])
        func glyph(_ attributes: String, size: CGFloat = 100) throws -> MathLayout {
            try layout("<mi><mglyph alt=\"g\" \(attributes)/></mi>", images: images, size: size)
        }
        // Lengths: a thousand ems at 100 points is twice the bound.
        var result = try glyph(#"src="g" width="99999em" height="99999em""#)
        XCTAssertEqual([result.width, result.ascent, result.descent], [extent, extent, 0])
        result = try glyph(#"src="g" width="99999em""#)
        XCTAssertEqual([result.width, result.ascent], [extent, extent], "the height the aspect ratio asks for is bounded too")
        result = try glyph(#"src="g" height="99999em" width="1px""#)
        XCTAssertEqual([result.width, result.ascent], [1, extent])
        // valign cannot push either extent past the bound.
        result = try glyph(#"src="g" valign="-99999em""#)
        XCTAssertEqual([result.width, result.ascent, result.descent], [30, 0, extent])
        result = try glyph(#"src="g" valign="99999em""#)
        XCTAssertEqual([result.width, result.ascent, result.descent], [30, extent, 0])
        result = try glyph(#"src="g" height="99999em" valign="99999em""#)
        XCTAssertEqual([result.ascent, result.descent], [extent, 0])
        // Images: their own size, and what an aspect ratio makes of it.
        result = try glyph(#"src="wide""#)
        XCTAssertEqual([result.width, result.ascent], [extent, 1])
        result = try glyph(#"src="wide" height="100px""#)
        XCTAssertEqual([result.width, result.ascent], [extent, 100])
        result = try glyph(#"src="tall""#)
        XCTAssertEqual([result.width, result.ascent], [1, extent])
        result = try glyph(#"src="tall" width="50%" valign="-150em""#)
        XCTAssertEqual([result.width, result.ascent, result.descent], [0.5, 15_000, 15_000])
        // Together they exceed the formula's bound like anything else.
        XCTAssertThrowsError(try layout(#"<mi><mglyph src="wide" alt="w"/><mglyph src="wide" alt="w"/></mi>"#, images: images)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }

        // Glyph elements and alt text count against the limits whether or not a parser saw them.
        let glyphs = Array(repeating: MathMLNode(name: "mglyph", attributes: ["src": "g"]), count: 30_000)
        for images in [images, nil] {
            XCTAssertThrowsError(try box(MathMLNode(name: "mtext", children: glyphs), images: images)) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
            }
            let tokens = Array(repeating: MathMLNode(name: "mi", children: Array(glyphs.prefix(4_000))), count: 15)
            XCTAssertThrowsError(try box(MathMLNode(name: "mrow", children: tokens), images: images)) {
                XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
            }
        }
        let long = MathMLNode(name: "mglyph", attributes: ["alt": String(repeating: "a", count: 60_000)])
        XCTAssertThrowsError(try box(MathMLNode(name: "mtext", children: [long]), images: nil)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        XCTAssertThrowsError(try box(MathMLNode(name: "math", children: Array(repeating: MathMLNode(name: "mglyph"), count: 30_000)),
                                     images: nil)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }
}

/// The bytes `layout` draws, for comparing drawings made on different threads.
private func drawing(_ layout: MathLayout) -> [UInt8] {
    let width = Int(layout.width.rounded(.up)), height = Int((layout.ascent + layout.descent).rounded(.up))
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    layout.draw(in: context, baselineOrigin: CGPoint(x: 0, y: layout.descent))
    return Array(UnsafeBufferPointer(start: context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4),
                                     count: width * height * 4))
}

/// Collects strings from any thread.
private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var values: [String] { lock.withLock { recorded } }
    func add(_ value: String) { lock.withLock { recorded.append(value) } }
}
