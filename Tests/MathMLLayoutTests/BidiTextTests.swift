import CoreGraphics
import CoreText
import CryptoKit
import Foundation
@testable import MathMLLayout
import XCTest

final class BidiTextTests: MathTestCase {
    let fontName = "MathMLBidiTest-Regular"

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "MathMLBidiTest", withExtension: "ttf",
                                                 subdirectory: "ExternalFixtures/fonts"))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(), "bb045c01ab5c80d784fa71d299d0828ab572b2a8ced8563e33b595a5a56fed78")
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            XCTAssertEqual(CFErrorGetCode(try XCTUnwrap(error).takeRetainedValue()), CTFontManagerError.alreadyRegistered.rawValue)
        }
        XCTAssertEqual(CTFontCopyPostScriptName(CTFontCreateWithName(fontName as CFString, 20, nil)) as String, fontName)
    }

    func rows(_ text: String, width: CGFloat, direction: String? = nil) throws -> [Paragraph.Row] {
        let root = MathMLNode(name: "math", attributes: direction.map { ["dir": $0] } ?? [:],
                              children: [MathMLNode(name: "mtext", text: text)])
        let box = try LayoutEngine(fontName: fontName).layoutRoot(root,
            style: MathStyle(fontSize: 20, color: black, fontName: fontName))
        return Paragraph(box).rows(limit: width, first: width, auto: (.left, 0))
    }

    /// Decode fixture glyph names from its pinned glyph order, never from the shaping result.
    /// Sorting by draw coordinates verifies the visual order, independent of CTRun enumeration.
    func visualGlyphs(_ box: MathBox) -> [String] {
        let chars = Array(" ABCDEF1234().-+אבגדהוبت".unicodeScalars)
        var names = [".notdef"] + chars.map { $0 == " " ? "space" : String(format: "uni%04X", $0.value) }
        for name in ["uni0628", "uni062A"] { for form in ["isol", "init", "medi", "fina"] { names.append("\(name).\(form)") } }
        var placed: [(CGFloat, String)] = []
        func visit(_ box: MathBox, _ x: CGFloat) {
            for item in box.items {
                switch item {
                case .box(let child, let point): visit(child, x + point.x)
                case .glyphs(let run):
                    for (glyph, position) in zip(run.glyphs, run.positions) {
                        // CoreText emits its invisible glyph sentinel for bidi controls.
                        guard glyph != .max else { continue }
                        placed.append((x + position.x, Int(glyph) < names.count ? names[Int(glyph)] : "other"))
                    }
                default: break
                }
            }
        }
        visit(box, 0)
        return placed.sorted { $0.0 < $1.0 }.map(\.1).filter { $0 != ".notdef" }
    }

    func names(_ text: String) -> [String] {
        text.unicodeScalars.map { $0 == " " || $0 == "\u{A0}" || $0 == "\u{202F}" ? "space" : String(format: "uni%04X", $0.value) }
    }

    private func attachmentLines(_ body: String, width: CGFloat, direction: String = "rtl") throws -> MathLines {
        let bitmap = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(black); bitmap.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let icon = bitmap.makeImage()!
        var root = try node(body); root.attributes["dir"] = direction
        return try LayoutEngine.lines(root, style: MathStyle(fontSize: 20, color: black, fontName: fontName,
                                      imageProvider: MathImageProvider { _ in icon }),
                                      maximumWidth: width, firstRowMaximumWidth: nil)
    }

    private func attachmentRects(_ box: MathBox, at point: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .box(let child, let position):
                attachmentRects(child, at: CGPoint(x: point.x + position.x, y: point.y + position.y))
            case .image(_, let rect, _): [rect.offsetBy(dx: point.x, dy: point.y)]
            default: []
            }
        }
    }

    private func fillRects(_ box: MathBox, x: CGFloat = 0) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .box(let child, let position): fillRects(child, x: x + position.x)
            case .rect(let rect, _): [rect.offsetBy(dx: x, dy: 0)]
            default: []
            }
        }
    }

    func testRTLImageParagraphUsesLogicalRangesAndIndependentVisualOrder() throws {
        let body = "<mtext>אב <mglyph src='first' width='13px' height='9px' valign='-3px'/> גד EF</mtext>"
        let output = try attachmentLines(body, width: 63)
        XCTAssertEqual(output.rows.count, 2)
        XCTAssertEqual(output.rows[0].box.width, 63, accuracy: 0.001)
        XCTAssertEqual(visualGlyphs(output.rows[0].box), names("דג  בא"))
        XCTAssertEqual(visualGlyphs(output.rows[1].box), names("EF"))
        XCTAssertEqual(attachmentRects(output.rows[0].box), [CGRect(x: 25, y: -3, width: 13, height: 9)])
        XCTAssertEqual(output.widestUnbreakable, 20, accuracy: 0.001)
        let retried = try attachmentLines(body, width: output.widestUnbreakable)
        XCTAssertTrue(retried.rows.allSatisfy { $0.box.width <= output.widestUnbreakable + 0.001 })
    }

    func testAdjacentImagesHaveLogicalOwnershipInsideRTLWords() throws {
        let output = try attachmentLines("<mtext>אב <mglyph src='first' width='11px'/><mglyph src='second' width='17px'/> גד</mtext>", width: 0)
        XCTAssertEqual(output.rows.count, 3)
        let rects = attachmentRects(output.rows[1].box).sorted { $0.minX < $1.minX }
        XCTAssertEqual(rects.map(\.width), [17, 11])
        XCTAssertEqual(rects.map(\.minX), [0, 17])
        XCTAssertEqual(visualGlyphs(output.rows[0].box), names("בא"))
        XCTAssertEqual(visualGlyphs(output.rows[2].box), names("דג"))
    }

    func testDecoratedArabicFallbackParticipatesInParagraphShaping() throws {
        let output = try attachmentLines("<mtext>ABCD <mglyph alt='بت تب' mathbackground='yellow'/> ABCD</mtext>", width: 45)
        XCTAssertEqual(output.rows.count, 3)
        XCTAssertEqual(visualGlyphs(output.rows[1].box), ["uni0628.fina", "uni062A.init", "space", "uni062A.fina", "uni0628.init"])
        let fills = fillRects(output.rows[1].box)
        XCTAssertEqual(fills.count, 1)
        XCTAssertEqual(fills[0].minX, 0, accuracy: 0.001)
        XCTAssertEqual(fills[0].width, 45, accuracy: 0.001)
        let narrow = try attachmentLines("<mtext>ABCD <mglyph alt='بت تب' mathbackground='yellow'/> ABCD</mtext>", width: 20)
        XCTAssertEqual(narrow.rows.count, 4)
        XCTAssertEqual(visualGlyphs(narrow.rows[1].box), ["uni062A.fina", "uni0628.init"])
        XCTAssertEqual(visualGlyphs(narrow.rows[2].box), ["uni0628.fina", "uni062A.init"])
        XCTAssertEqual(narrow.rows.map { fillRects($0.box).count }, [0, 1, 1, 0])
    }

    func testMixedAttachmentsPreserveEdgeWhitespaceNoBreakSpacesAndTokenOverride() throws {
        let body = "<mtext dir='ltr'> אב&#xA0;<mglyph src='icon' width='13px'/> AB </mtext>"
        let output = try attachmentLines(body, width: 0)
        XCTAssertEqual(output.rows.count, 2)
        XCTAssertEqual(output.rows.map { $0.box.width }, [43, 25])
        XCTAssertEqual(visualGlyphs(output.rows[0].box), names(" בא "))
        XCTAssertEqual(attachmentRects(output.rows[0].box).first?.minX ?? -1, 30, accuracy: 0.001)
        XCTAssertEqual(visualGlyphs(output.rows[1].box), names("AB "))
    }

    func testDirectionalOverrideContinuesAcrossMixedAttachmentLines() throws {
        let output = try attachmentLines("<mtext>אב &#x202E;AB <mglyph src='icon' width='13px'/> CD&#x202C; גד</mtext>", width: 20)
        XCTAssertEqual(output.rows.count, 5)
        XCTAssertEqual(visualGlyphs(output.rows[1].box), names("BA"))
        XCTAssertEqual(attachmentRects(output.rows[2].box).count, 1)
        XCTAssertEqual(visualGlyphs(output.rows[3].box), names("DC"))
        XCTAssertEqual(visualGlyphs(output.rows[4].box), names("דג"))
    }

    func testLogicalAttachmentDelegatesPreserveExtremeBaselineOffsets() throws {
        for valign in [-20, 20] {
            let output = try attachmentLines("<mtext>אב <mglyph src='icon' width='13px' height='8px' valign='\(valign)px'/> גד</mtext>", width: 0)
            XCTAssertEqual(output.rows.count, 3)
            XCTAssertEqual(attachmentRects(output.rows[1].box), [CGRect(x: 0, y: valign, width: 13, height: 8)])
            let row = output.rows[1].box
            XCTAssertEqual(row.width, 13, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(row.ascent, CGFloat(valign + 8))
            XCTAssertGreaterThanOrEqual(row.descent, CGFloat(-valign))
            let ink = try XCTUnwrap(row.inkBounds)
            XCTAssertGreaterThanOrEqual(ink.minY, -row.descent)
            XCTAssertLessThanOrEqual(ink.maxY, row.ascent)
        }
    }

    func testSimpleImageTextRetainsAuthoredEdgeSpaces() throws {
        let output = try attachmentLines("<mtext> AB <mglyph src='icon' width='13px'/> CD </mtext>", width: 0, direction: "ltr")
        XCTAssertEqual(output.rows.count, 3)
        XCTAssertEqual(output.rows.map { $0.box.width }, [25, 13, 25])
        XCTAssertEqual(visualGlyphs(output.rows[0].box), names(" AB"))
        XCTAssertEqual(visualGlyphs(output.rows[2].box), names("CD "))
    }

    func testHebrewLinesFollowLogicalWordsAndVisualBidiOrder() throws {
        let output = try rows("אב גד הו", width: 45)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(visualGlyphs(output[0].box), names("דג בא"))
        XCTAssertEqual(visualGlyphs(output[1].box), names("וה"))
        XCTAssertEqual(output[0].box.width, 45, accuracy: 0.001)
        XCTAssertEqual(output[1].box.width, 20, accuracy: 0.001)
    }

    func testArabicContextualFormsAreReshapedOnEachLine() throws {
        let output = try rows("بت تب بت", width: 45)
        XCTAssertEqual(output.count, 2)
        XCTAssertEqual(visualGlyphs(output[0].box), ["uni0628.fina", "uni062A.init", "space", "uni062A.fina", "uni0628.init"])
        XCTAssertEqual(visualGlyphs(output[1].box), ["uni062A.fina", "uni0628.init"])
        XCTAssertEqual(output[0].box.width, 45, accuracy: 0.001)
    }

    func testMixedNumbersPunctuationAndInheritedParagraphDirection() throws {
        let rtl = try rows("אב 12 גד EF", width: 70, direction: "rtl")
        XCTAssertEqual(rtl.count, 2)
        XCTAssertEqual(visualGlyphs(rtl[0].box), names("דג 12 בא"))
        XCTAssertEqual(visualGlyphs(rtl[1].box), names("EF"))
        XCTAssertEqual(visualGlyphs(try XCTUnwrap(rows("אב - AB", width: 100, direction: "rtl").first).box), names("AB - בא"))
        XCTAssertEqual(visualGlyphs(try XCTUnwrap(rows("אב - AB", width: 100, direction: "ltr").first).box), names("בא - AB"))
        XCTAssertEqual(visualGlyphs(try XCTUnwrap(rows("אב (12)", width: 100, direction: "rtl").first).box), names("(12) בא"))
    }

    func testDirectionalEmbeddingAndIsolateSurviveLineBoundary() throws {
        // RLO begins on the preceding line: CD must still reverse to DC on the next.
        let embedded = try rows("אב \u{202E}AB CD\u{202C} גד", width: 20, direction: "rtl")
        XCTAssertEqual(embedded.count, 4)
        XCTAssertEqual(visualGlyphs(embedded[0].box), names("בא"))
        XCTAssertEqual(visualGlyphs(embedded[1].box), names("BA"))
        XCTAssertEqual(visualGlyphs(embedded[2].box), names("DC"))
        XCTAssertEqual(visualGlyphs(embedded[3].box), names("דג"))
        let isolated = try rows("אב \u{2066}AB CD\u{2069} גד", width: 20, direction: "rtl")
        XCTAssertEqual(isolated.count, 4)
        XCTAssertEqual(visualGlyphs(isolated[1].box), names("AB"))
        XCTAssertEqual(visualGlyphs(isolated[2].box), names("CD"))
    }

    func testNoBreakSpacesDrawingAndReportedMinimum() throws {
        for space in ["\u{A0}", "\u{202F}"] {
            let root = MathMLNode(name: "math", attributes: ["dir": "rtl"], children: [MathMLNode(name: "mtext", text: "אב\(space)גד הו")])
            let style = MathStyle(fontSize: 20, color: black, fontName: fontName)
            let output = try MathLayout(root, style: style, maximumWidth: 0)
            XCTAssertEqual(output.rows.count, 2)
            XCTAssertEqual(output.widestUnbreakableWidth, 45, accuracy: 0.001)
            let fitted = try MathLayout(root, style: style, maximumWidth: output.widestUnbreakableWidth)
            XCTAssertLessThanOrEqual(fitted.width, output.widestUnbreakableWidth + 0.001)
            assertBoxCoversInk(output, "RTL no-break space")
        }
    }

    func testFallbackFontsAndNeighborGeometry() throws {
        var fonts: Set<String> = []
        func collect(_ box: MathBox) {
            for item in box.items {
                if case .glyphs(let run) = item { fonts.insert(CTFontCopyPostScriptName(run.font) as String) }
                if case .box(let child, _) = item { collect(child) }
            }
        }
        for row in try rows("אב Ω גד", width: 25) { collect(row.box) }
        XCTAssertTrue(fonts.contains(fontName))
        XCTAssertGreaterThan(fonts.count, 1, "The Greek symbol must retain its CoreText fallback font")
        let root = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", text: "אב Ω גד"), MathMLNode(name: "mi", text: "A")])
        let style = MathStyle(fontSize: 20, color: black, fontName: fontName)
        for width: CGFloat in [0, 30, 55, 100] {
            let output = try MathLayout(root, style: style, maximumWidth: width)
            XCTAssertLessThanOrEqual(output.width, max(width, output.widestUnbreakableWidth) + 0.001)
            assertBoxCoversInk(output, "RTL fallback \(width)")
        }
    }

    func testAuthorOuterSpacesSurviveFormulaBreaksAndKeepNeighborPlacement() throws {
        let style = MathStyle(fontSize: 20, color: black, fontName: fontName)
        for neighbor in [false, true] {
            var children = [MathMLNode(name: "mtext", text: " אב גד ")]
            if neighbor { children.append(MathMLNode(name: "mi", attributes: ["mathvariant": "normal"], text: "A")) }
            children += [MathMLNode(name: "mo", attributes: ["linebreak": "newline"], text: "+"), MathMLNode(name: "mi", text: "B")]
            let root = MathMLNode(name: "math", children: children)
            let output = try MathLayout(root, style: style)
            XCTAssertEqual(output.rows.count, 2)
            XCTAssertEqual(output.rows[0].width, neighbor ? 65 : 55, accuracy: 0.001)
            let box = try LayoutEngine(fontName: fontName).layoutRoot(root, style: style)
            let broken = Paragraph(box).rows(limit: .infinity, first: .infinity, auto: (.left, 0))
            XCTAssertEqual(visualGlyphs(broken[0].box), names(neighbor ? " דג בא A" : " דג בא "))
        }
        let split = try rows(" אב גד ", width: 25)
        XCTAssertEqual(split.map { $0.box.width }, [25, 25])
    }

    func testASCIIParagraphEdgeSpacesSurviveFormulaAndWordBreaks() throws {
        let style = MathStyle(fontSize: 20, color: black, fontName: fontName)
        let root = MathMLNode(name: "math", children: [
            MathMLNode(name: "mi", text: "A"),
            MathMLNode(name: "mspace", attributes: ["linebreak": "newline"]),
            MathMLNode(name: "mtext", text: " AB CD "),
            MathMLNode(name: "mspace", attributes: ["linebreak": "newline"]),
            MathMLNode(name: "mi", text: "B"),
        ])
        let engine = LayoutEngine(fontName: fontName)
        let box = try engine.layoutRoot(root, style: style)
        let output = Paragraph(box).rows(limit: .infinity, first: .infinity, auto: (.left, 0))
        XCTAssertEqual(output.count, 3)
        XCTAssertEqual(output[1].box.width, 55, accuracy: 0.001)
        XCTAssertEqual(visualGlyphs(output[1].box).filter { $0 != "space" }, names("ABCD"))
        XCTAssertEqual(engine.textWork.lineRequests, 3, "Edge spaces must preserve the one-line ASCII fast path")
        let publicLayout = try MathLayout(root, style: style)
        XCTAssertEqual(publicLayout.rows[1].width, 55, accuracy: 0.001)
        let split = try rows(" AB CD ", width: 25)
        XCTAssertEqual(split.map { $0.box.width }, [25, 25])
        XCTAssertEqual(visualGlyphs(split[0].box), names(" AB"))
        XCTAssertEqual(visualGlyphs(split[1].box), names("CD "))
    }

    func testStackNumericParenthesesStayLTRUnderInheritedRTLTextDirection() throws {
        let root = MathMLNode(name: "math", attributes: ["dir": "rtl"], children: [
            MathMLNode(name: "mstack", children: [MathMLNode(name: "mn", text: "(12)")]),
        ])
        let box = try LayoutEngine(fontName: fontName).layoutRoot(root,
            style: MathStyle(fontSize: 20, color: black, fontName: fontName))
        XCTAssertEqual(visualGlyphs(box), names("(12)"))
    }

    func testDecoratedTextRetainsItsBackgroundWhenTheFormulaBreaks() throws {
        let root = MathMLNode(name: "math", children: [
            MathMLNode(name: "mtext", attributes: ["mathbackground": "lime"], text: "אב גד"),
            MathMLNode(name: "mo", attributes: ["linebreak": "newline"], text: "+"),
            MathMLNode(name: "mi", text: "A"),
        ])
        let output = try MathLayout(root, style: MathStyle(fontSize: 20, color: black, fontName: fontName), maximumWidth: 25)
        XCTAssertEqual(output.rows.count, 3)
        XCTAssertNotNil(Rendering(output).bounds(.green))
        assertBoxCoversInk(output, "decorated RTL text")
    }

    func testWorkBoundIsEnforcedForAParagraphWithinInputAndExtentBounds() throws {
        let root = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", text: String(repeating: "אב ", count: 2_000))])
        XCTAssertThrowsError(try MathLayout(root, style: MathStyle(fontSize: 1, color: black, fontName: fontName), maximumWidth: 0.5)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    func testSimpleLTRFallbackFontsAndInheritedRTLContext() throws {
        let text = "AB office CD"
        let style = MathStyle(fontSize: 20, color: black, fontName: fontName)
        func measure(_ direction: String?) throws -> (MathBox, TextShapingWork) {
            let root = MathMLNode(name: "math", attributes: direction.map { ["dir": $0] } ?? [:],
                                  children: [MathMLNode(name: "mtext", text: text)])
            let engine = LayoutEngine(fontName: fontName)
            return (try engine.layoutRoot(root, style: style), engine.textWork)
        }
        let fast = try measure(nil), rtl = try measure("rtl")
        XCTAssertEqual(fast.1.lineRequests, 1)
        XCTAssertGreaterThan(rtl.1.lineRequests, 1, "Inherited RTL must retain the contextual paragraph source")
        XCTAssertTrue(Paragraph(rtl.0).units.contains { $0.box.logicalTextSlice != nil })
        var fonts: Set<String> = []
        func collect(_ box: MathBox) {
            for item in box.items {
                if case .glyphs(let run) = item { fonts.insert(CTFontCopyPostScriptName(run.font) as String) }
                if case .box(let child, _) = item { collect(child) }
            }
        }
        for width: CGFloat in [0, 45, 100] {
            let fastRows = Paragraph(fast.0).rows(limit: width, first: width, auto: (.left, 0))
            let rtlRows = Paragraph(rtl.0).rows(limit: width, first: width, auto: (.left, 0))
            XCTAssertEqual(fastRows.map { $0.box.width }, rtlRows.map { $0.box.width })
            for row in fastRows { collect(row.box) }
        }
        XCTAssertTrue(fonts.contains(fontName))
        XCTAssertGreaterThan(fonts.count, 1, "ASCII fast-path fragments must retain the fallback font for office")
    }

    func testLogicalRangeCacheHitsKeepWorkAccountingAndExhaustionStopsLineRequests() throws {
        let root = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", text: "אב גד")])
        let engine = LayoutEngine(fontName: fontName)
        let box = try engine.layoutRoot(root, style: MathStyle(fontSize: 20, color: black, fontName: fontName))
        let source = try XCTUnwrap(Paragraph(box).units.first?.box.logicalTextSlice?.source)
        let work = engine.textWork
        let requests = work.lineRequests, spent = work.spent
        _ = source.box(source.words[0])
        XCTAssertEqual(work.lineRequests, requests, "A cache hit must not request another CoreText line")
        XCTAssertEqual(work.spent, spent + source.words[0].count, "Cached glyph assembly still consumes the shared work budget")
        XCTAssertTrue(work.consume(TextShapingWork.limit - work.spent))
        _ = source.box(0..<5)
        XCTAssertTrue(work.exhausted)
        XCTAssertEqual(work.lineRequests, requests, "Exhaustion must be checked before a new range is shaped")
    }

    func testTextWorkBudgetIsSharedAndStopsBeforeShaping() {
        let work = TextShapingWork()
        XCTAssertTrue(work.consume(TextShapingWork.limit))
        XCTAssertFalse(work.consume(1))
        XCTAssertFalse(work.consume(0))
        XCTAssertEqual(work.spent, TextShapingWork.limit)
    }
    func testLTRTokenWordsKeepTheirOrderInsideBrokenRTLMathematicalRows() throws {
        func positions(_ box: MathBox, x: CGFloat = 0) -> [CGFloat] {
            box.items.flatMap { item -> [CGFloat] in
                switch item {
                case .glyphs(let run): run.positions.map { x + $0.x }
                case .box(let child, let point): positions(child, x: x + point.x)
                default: []
                }
            }.sorted()
        }
        let style = MathStyle(fontSize: 20, color: black, fontName: fontName)
        let children = [MathMLNode(name: "mtext", attributes: ["dir": "ltr"], text: "AB CD EF")]
        let root = MathMLNode(name: "math", attributes: ["dir": "rtl"], children: children)
        let box = try LayoutEngine(fontName: fontName).layoutRoot(root, style: style)
        let lines = Paragraph(box).rows(limit: 45, first: 45, auto: (.left, 0))
        XCTAssertEqual(lines.count, 2)
        guard lines.count == 2 else { return }
        XCTAssertEqual(visualGlyphs(lines[0].box), names("ABCD"))
        XCTAssertEqual(lines[0].box.width, 45, accuracy: 0.001)
        let offsets = positions(lines[0].box)
        XCTAssertEqual(offsets[2] - offsets[1], 15, accuracy: 0.001, "the separator retains its five-point advance")
        XCTAssertEqual(visualGlyphs(lines[1].box), names("EF"))

        let mixed = MathMLNode(name: "math", attributes: ["dir": "rtl"], children: [
            MathMLNode(name: "mtext", attributes: ["dir": "ltr"], text: "AB CD"),
            MathMLNode(name: "mo", attributes: ["linebreak": "newline"], text: "+"),
            MathMLNode(name: "mtext", attributes: ["dir": "ltr"], text: "EF"),
        ])
        let drawn = try LayoutEngine(fontName: fontName).layoutRoot(mixed, style: style)
        let broken = Paragraph(drawn).rows(limit: 45, first: 45, auto: (.left, 0))
        XCTAssertEqual(broken.count, 2)
        guard broken.count == 2 else { return }
        XCTAssertEqual(visualGlyphs(broken[0].box), names("ABCD"))
        XCTAssertEqual(broken[0].box.width, 45, accuracy: 0.001)
        XCTAssertEqual(visualGlyphs(broken[1].box), names("EF+"))
    }

}
