import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class InlineImageWrappingTests: MathTestCase {
    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 10, height: 5, bitsPerComponent: 8, bytesPerRow: 40,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 10, height: 5))
        return context.makeImage()!
    }

    private func lines(_ body: String, width: CGFloat = 0, provider: MathImageProvider? = nil) throws -> MathLines {
        try LayoutEngine.lines(node(body), style: MathStyle(fontSize: 20, color: black, imageProvider: provider),
                               maximumWidth: width, firstRowMaximumWidth: nil)
    }

    private func images(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .image(_, let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let inner, let point): images(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func backgrounds(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let inner, let point): backgrounds(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func glyphs(_ box: MathBox) -> [CGGlyph] {
        box.items.flatMap { item -> [CGGlyph] in
            switch item {
            case .glyphs(let run): run.glyphs
            case .box(let box, _): glyphs(box)
            default: []
            }
        }
    }

    private func glyphPositions(_ box: MathBox, at origin: CGPoint = .zero) -> [CGPoint] {
        box.items.flatMap { item -> [CGPoint] in
            switch item {
            case .glyphs(let run): run.positions.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y) }
            case .box(let inner, let point): glyphPositions(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func assertShaping(_ wrapped: MathBox, matches natural: MathBox, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(glyphs(wrapped), glyphs(natural), file: file, line: line)
        let actual = glyphPositions(wrapped), expected = glyphPositions(natural)
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, b) in zip(actual, expected) {
            XCTAssertEqual(a.x - (actual.first?.x ?? 0), b.x - (expected.first?.x ?? 0), accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.y, b.y, accuracy: 0.001, file: file, line: line)
        }
    }

    private func assertContained(_ result: MathLines, file: StaticString = #filePath, line: UInt = #line) {
        for row in result.rows {
            guard let ink = row.box.inkBounds else { continue }
            XCTAssertGreaterThanOrEqual(ink.minX, -0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(ink.maxX, row.box.width + 0.001, file: file, line: line)
            XCTAssertGreaterThanOrEqual(ink.minY, -row.box.descent - 0.001, file: file, line: line)
            XCTAssertLessThanOrEqual(ink.maxY, row.box.ascent + 0.001, file: file, line: line)
        }
    }

    func testImageWrapsAtSurroundingSpacesAndKeepsSizeAndValign() throws {
        let icon = image(), provider = MathImageProvider { _ in icon }
        let body = "<mtext>first words <mglyph src=\"icon\" alt=\"icon\" width=\"37px\" height=\"13px\" valign=\"-4px\"/> last words</mtext>"
        let result = try lines(body, provider: provider)
        XCTAssertEqual(result.rows.count, 5)
        XCTAssertEqual(result.rows.map { images($0.box).count }, [0, 0, 1, 0, 0])
        XCTAssertEqual(images(result.rows[2].box), [CGRect(x: 0, y: -4, width: 37, height: 13)])
        let expected = max(37, try layout("<mtext>words</mtext>").width, try layout("<mtext>first</mtext>").width)
        XCTAssertEqual(result.widestUnbreakable, expected, accuracy: 0.01)
        XCTAssertEqual(try lines(body, width: .infinity, provider: provider).widestUnbreakable, expected, accuracy: 0.01)
        assertContained(result)
    }

    func testSeveralAndAdjacentImagesKeepSourceOrderAndUnbreakableNeighbors() throws {
        let icon = image(), provider = MathImageProvider { _ in icon }
        let body = "<mtext>a <mglyph src=\"one\" width=\"11px\"/><mglyph src=\"two\" width=\"17px\"/>b <mglyph src=\"three\" width=\"23px\"/> c</mtext>"
        let result = try lines(body, provider: provider)
        XCTAssertEqual(result.rows.count, 4)
        XCTAssertEqual(images(result.rows[1].box).map(\.width), [11, 17])
        XCTAssertEqual(images(result.rows[2].box).map(\.width), [23])
        XCTAssertEqual(images(result.rows[1].box).map(\.minX), [0, 11])
        let expected = try lines("<mtext><mglyph src=\"one\" width=\"11px\"/><mglyph src=\"two\" width=\"17px\"/>b</mtext>", provider: provider).rows[0].box.width
        XCTAssertEqual(result.widestUnbreakable, expected, accuracy: 0.01)
        assertContained(result)
    }

    func testAbsentProviderAndDecoratedFallbackRetainShapingAndBackgrounds() throws {
        let body = "<mtext>before <mglyph src=\"missing\" alt=\"office café words\" mathbackground=\"yellow\"/> after</mtext>"
        for provider in [nil, MathImageProvider { _ in nil }] {
            let result = try lines(body, provider: provider)
            XCTAssertEqual(result.rows.count, 5)
            XCTAssertTrue(result.rows.allSatisfy { images($0.box).isEmpty })
            for (index, text) in ["office", "café", "words"].enumerated() {
                let row = result.rows[index + 1].box
                assertShaping(row, matches: try lines("<mtext>\(text)</mtext>").rows[0].box)
                XCTAssertEqual(backgrounds(row).count, 1)
                // A local background follows the original text advance; a glyph may overhang it.
                let natural = try lines("<mtext mathbackground=\"yellow\">\(text)</mtext>").rows[0].box
                XCTAssertEqual(backgrounds(row)[0].width, backgrounds(natural)[0].width, accuracy: 0.01)
            }
            XCTAssertTrue(backgrounds(result.rows[0].box).isEmpty)
            XCTAssertTrue(backgrounds(result.rows[4].box).isEmpty)
            assertContained(result)
            // When several fallback words share a row, the space keeps its background too.
            let pairWidth = try layout("<mtext>office café</mtext>").width
            let partial = try lines(body, width: pairWidth + 0.01, provider: provider)
            let pair = try XCTUnwrap(partial.rows.first { abs($0.box.width - pairWidth) < 0.02 })
            let fills = backgrounds(pair.box).sorted { $0.minX < $1.minX }
            XCTAssertFalse(fills.isEmpty)
            XCTAssertEqual(fills.last!.maxX - fills.first!.minX, pairWidth, accuracy: 0.01)
            for index in 1..<fills.count { XCTAssertEqual(fills[index - 1].maxX, fills[index].minX, accuracy: 0.001) }
            assertContained(partial)
        }
    }

    func testFallbackWithReorderedClustersKeepsOriginalBackgroundAdvance() throws {
        let words = ["कि", "किताब"]
        let body = "<mtext>before <mglyph alt=\"\(words.joined(separator: " "))\" mathbackground=\"yellow\"/> after</mtext>"
        let result = try lines(body)
        // If the platform uses nonmonotonic drawing origins, conservative whole-token layout
        // still preserves the original fallback. Otherwise each logical word is available.
        if result.rows.count == 1 {
            let original = try lines(body, width: .infinity).rows[0].box
            assertShaping(result.rows[0].box, matches: original)
            XCTAssertEqual(backgrounds(result.rows[0].box).map(\.width), backgrounds(original).map(\.width))
            assertContained(result)
            return
        }
        XCTAssertEqual(result.rows.count, 4)
        for (index, word) in words.enumerated() {
            let wrapped = result.rows[index + 1].box
            let natural = try lines("<mtext mathbackground=\"yellow\">\(word)</mtext>").rows[0].box
            assertShaping(wrapped, matches: natural)
            XCTAssertEqual(backgrounds(wrapped).first?.width ?? -1, backgrounds(natural).first?.width ?? -2, accuracy: 0.01)
        }
        assertContained(result)
    }

    func testRightToLeftFallbackWrapsInLogicalWordOrder() throws {
        let icon = image(), provider = MathImageProvider { _ in icon }
        for background in ["", " mathbackground=\"yellow\""] {
            let body = "<mtext>before words <mglyph src=\"icon\" alt=\"אבג דהו\"\(background)/> after words</mtext>"
            if background.isEmpty {
                let plain = try lines("<mtext>before words אבג דהו after words</mtext>")
                let fallback = try lines(body)
                XCTAssertEqual(fallback.rows.count, plain.rows.count)
                for (actual, expected) in zip(fallback.rows, plain.rows) {
                    XCTAssertEqual(actual.box.width, expected.box.width, accuracy: 0.001)
                    assertShaping(actual.box, matches: expected.box)
                }
            } else { XCTAssertEqual(try lines(body).rows.count, 6) }
            // When the provider supplies the image, an undisplayed RTL alt does not block wrapping.
            XCTAssertEqual(try lines(body, provider: provider).rows.count, 5)
        }
    }

    func testNoBreakSpacesAndAuthorPolicyWithImagesAndAlt() throws {
        let icon = image(), provider = MathImageProvider { _ in icon }
        for decorated in [false, true] {
            let background = decorated ? " mathbackground=\"yellow\"" : ""
            let body = "<mtext>prefix <mglyph src=\"missing\" alt=\"alpha&#xA0;beta gamma\"\(background)/> tail</mtext>"
            XCTAssertEqual(try lines(body).rows.count, 4)
        }
        let body = "<mtext>first&#xA0;<mglyph src=\"icon\"/> last words</mtext>"
        XCTAssertEqual(try lines(body, provider: provider).rows.count, 3)
        XCTAssertEqual(try lines("<mstyle linebreak=\"nobreak\">\(body)</mstyle>", provider: provider).rows.count, 1)
        let decorated = try lines("<mtext mathbackground=\"yellow\">first <mglyph src=\"icon\"/> last</mtext>", provider: provider)
        XCTAssertEqual(decorated.rows.count, 3)
        XCTAssertTrue(decorated.rows.allSatisfy { backgrounds($0.box).count == 1 })
        let unbreakable = try lines("<mtext>first<mglyph src=\"icon\"/>last</mtext>", provider: provider)
        XCTAssertEqual(unbreakable.rows.count, 1)
        XCTAssertEqual(unbreakable.widestUnbreakable, unbreakable.rows[0].box.width, accuracy: 0.01)
        assertContained(unbreakable)
    }
    private func assertSameGeometry(_ hidden: MathLines, _ visible: MathLines,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(hidden.rows.count, visible.rows.count, file: file, line: line)
        XCTAssertEqual(hidden.widestUnbreakable, visible.widestUnbreakable, accuracy: 0.001, file: file, line: line)
        for (a, b) in zip(hidden.rows, visible.rows) {
            XCTAssertEqual(a.origin, b.origin, file: file, line: line)
            XCTAssertEqual(a.box.width, b.box.width, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.box.ascent, b.box.ascent, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(a.box.descent, b.box.descent, accuracy: 0.001, file: file, line: line)
        }
    }

    func testPhantomDecoratedSpacesAndImagesKeepPartialRowGeometryWithoutDrawing() throws {
        let icon = image(), provider = MathImageProvider { source in source == "icon" ? icon : nil }
        let content = "<mtext>before <mglyph src='missing' alt='office cafe words' mathbackground='yellow'/> <mglyph src='icon' width='23px'/> after</mtext>"
            + "<mo linebreak='newline'>+</mo><mi>b</mi>"
        let limit = try layout("<mtext>office cafe</mtext>").width + 0.01
        for width in [limit, CGFloat.infinity] {
            let visible = try lines("<mrow>\(content)</mrow>", width: width, provider: provider)
            let hidden = try lines("<mphantom>\(content)</mphantom>", width: width, provider: provider)
            assertSameGeometry(hidden, visible)
            XCTAssertTrue(hidden.rows.allSatisfy { $0.box.inkBounds == nil })
            XCTAssertTrue(visible.rows.contains { backgrounds($0.box).count >= 3 })
            XCTAssertEqual(hidden.rows.flatMap { images($0.box) }.count, 1)
            let publicHidden = try MathLayout(node("<mphantom>\(content)</mphantom>"),
                style: MathStyle(fontSize: 20, color: black, imageProvider: provider), maximumWidth: width)
            XCTAssertNil(ink(publicHidden))
        }
    }

    func testPhantomBidiRangesStayInvisibleWhenFormulaAndTextBothBreak() throws {
        let content = "<mtext>אב 12 גד EF הו</mtext><mo linebreak='newline'>+</mo><mi>b</mi>"
        for width in [CGFloat(70), .infinity] {
            let visible = try lines("<mrow>\(content)</mrow>", width: width)
            let hidden = try lines("<mphantom>\(content)</mphantom>", width: width)
            assertSameGeometry(hidden, visible)
            XCTAssertTrue(hidden.rows.allSatisfy { $0.box.inkBounds == nil })
            XCTAssertNil(ink(try MathLayout(node("<mphantom>\(content)</mphantom>"),
                                           style: MathStyle(fontSize: 20, color: black), maximumWidth: width)))
        }
    }

    func testAuthoredCapAndNestedImageTextAnchorShareExplicitHostGeometry() throws {
        let icon = image(), provider = MathImageProvider { source in source == "icon" ? icon : nil }
        let body = "<mi>A</mi><mo linebreak='newline' linebreakstyle='after' indentshift='1em'>=</mo>"
            + "<mstyle><mrow id='target'><mtext>first <mglyph src='missing' alt='office cafe words' mathbackground='yellow'/> <mglyph src='icon' width='23px'/> last words</mtext></mrow></mstyle>"
            + "<mo linebreak='newline' indentalign='id' indenttarget='target'>=</mo><mi>b</mi>"
        var capped = try node(body); capped.attributes["maxwidth"] = "120px"
        let style = MathStyle(fontSize: 20, color: black, imageProvider: provider)
        let actual = try LayoutEngine.lines(capped, style: style, maximumWidth: 400, firstRowMaximumWidth: 70)
        let explicit = try LayoutEngine.lines(node(body), style: style, maximumWidth: 120, firstRowMaximumWidth: 70)
        assertSameGeometry(actual, explicit)
        XCTAssertGreaterThan(actual.rows.count, 3)
        XCTAssertEqual(try XCTUnwrap(actual.rows.last).origin.x, actual.rows[1].origin.x, accuracy: 0.001)
        XCTAssertEqual(actual.rows[1].origin.x, 20, accuracy: 0.001)
        XCTAssertLessThanOrEqual(actual.layoutPasses, LayoutEngine.maximumWrappingPasses)
        assertContained(actual)
    }

    func testMixedRTLAttachmentsRepeatAndDrawByRowWithinInkBounds() throws {
        let icon = image(), provider = MathImageProvider { source in source == "icon" ? icon : nil }
        var root = try node("<mstyle><mrow><mtext dir='rtl'> אב <mglyph src='missing' alt='بت تب' mathbackground='yellow'/> <mglyph src='icon' width='23px' height='13px' valign='-4px'/> גד </mtext></mrow></mstyle><mo linebreak='newline'>+</mo><mi>b</mi>")
        root.attributes["dir"] = "rtl"
        root.attributes["maxwidth"] = "20px"
        let style = MathStyle(fontSize: 20, color: black, imageProvider: provider)
        let first = try MathLayout(root, style: style, maximumWidth: 150)
        let repeated = try MathLayout(root, style: style, maximumWidth: 150)
        XCTAssertGreaterThan(first.rows.count, 4)
        XCTAssertEqual(first.width, repeated.width)
        XCTAssertEqual(first.rows.map(\.origin), repeated.rows.map(\.origin))
        assertBoxCoversInk(first, "mixed RTL attachments")
        func pixels(_ layout: MathLayout, separate: Bool) -> Data {
            let bitmap = CGContext(data: nil, width: 400, height: 600, bitsPerComponent: 8, bytesPerRow: 1600,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let baseline = CGPoint(x: 20, y: 560)
            if separate {
                for row in layout.rows {
                    row.draw(in: bitmap, baselineOrigin: CGPoint(x: baseline.x + row.origin.x, y: baseline.y + row.origin.y))
                }
            } else { layout.draw(in: bitmap, baselineOrigin: baseline) }
            return Data(bytes: bitmap.data!, count: 1600 * 600)
        }
        XCTAssertEqual(pixels(first, separate: false), pixels(first, separate: true))
        XCTAssertEqual(pixels(first, separate: false), pixels(repeated, separate: false))
        root.attributes.removeValue(forKey: "maxwidth")
        let retry = try MathLayout(root, style: style, maximumWidth: first.widestUnbreakableWidth)
        XCTAssertLessThanOrEqual(retry.width, first.widestUnbreakableWidth + 0.001)
    }

}
