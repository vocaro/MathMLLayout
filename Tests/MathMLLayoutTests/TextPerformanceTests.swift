import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class TextPerformanceTests: MathTestCase {
    func testSimpleLTRWordsReuseFullTokenGlyphsWithoutRangeLineRequests() throws {
        let text = String(repeating: "word ", count: 10_000)
        XCTAssertEqual(text.utf16.count, MathLimits.textLength)
        let root = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", text: text)])
        let style = MathStyle(fontSize: 1, color: black)
        let engine = LayoutEngine(fontName: nil)
        let box = try engine.layoutRoot(root, style: style)
        XCTAssertEqual(engine.textWork.lineRequests, 1, "One full-token line, with no per-word CoreText lines")
        let paragraph = Paragraph(box)
        let minimum = paragraph.widest
        XCTAssertGreaterThan(minimum, 0)
        XCTAssertEqual(paragraph.rows(limit: .infinity, first: .infinity, auto: (.left, 0)).count, 1)
        XCTAssertEqual(engine.textWork.lineRequests, 1, "Minimum reporting must reuse the same word metrics")
        XCTAssertEqual(engine.textWork.spent, 0)
        let output = try MathLayout(root, style: style)
        XCTAssertEqual(output.rows.count, 1)
        XCTAssertEqual(output.widestUnbreakableWidth, minimum, accuracy: 0.001)
        XCTAssertEqual(output.width, paragraph.entire.width, accuracy: 0.001)
    }

    func testSimpleLTRLigaturesKerningAndOuterSpacesMatchContextualLines() throws {
        for font in [nil, "Times-Roman", "Helvetica"] as [String?] {
            let style = MathStyle(fontSize: 20, color: black, fontName: font)
            for text in ["office affine AVATAR 123", "  office affine  "] {
                let root = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", text: text)])
                let whole = try MathLayout(root, style: style)
                for width in [CGFloat(0), whole.width / 2, whole.width] {
                    let fast = try MathLayout(root, style: style, maximumWidth: width)
                    // Explicit RTL disables segmentation. ASCII letters still run visually LTR;
                    // compare inner-word geometry without directional paragraph-edge spaces.
                    if !text.hasPrefix(" ") {
                        let contextual = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", attributes: ["dir": "rtl"], text: text)])
                        let exact = try MathLayout(contextual, style: style, maximumWidth: width)
                        XCTAssertEqual(fast.width, exact.width, accuracy: 0.001, "\(font ?? "default"): \(text)")
                        XCTAssertEqual(fast.rows.count, exact.rows.count)
                        XCTAssertEqual(fast.widestUnbreakableWidth, exact.widestUnbreakableWidth, accuracy: 0.001)
                    }
                    assertBoxCoversInk(fast, "simple LTR \(text)")
                }
                XCTAssertEqual(whole.width, try LayoutEngine(fontName: font).layoutRoot(root, style: style).width, accuracy: 0.001)
            }
        }
    }

    func testFastPathEligibilityExcludesBidiAndContextualText() {
        XCTAssertTrue(LayoutEngine.hasSimpleLTRWordBoundaries("office 123 AV", direction: .natural))
        XCTAssertTrue(LayoutEngine.hasSimpleLTRWordBoundaries("office 123 AV", direction: .leftToRight))
        XCTAssertFalse(LayoutEngine.hasSimpleLTRWordBoundaries("office 123 AV", direction: .rightToLeft))
        for text in ["אב AB", "بت AB", "AB - CD", "AB \u{202E}CD", "AB \u{2066}CD", "AB\u{A0}CD", "AB Ω", "e\u{301} AB"] {
            XCTAssertFalse(LayoutEngine.hasSimpleLTRWordBoundaries(text, direction: .natural), text)
        }
    }

    func testFormulaCandidateSpansKeepConstantTimeSummariesWithLogicalTextElsewhere() throws {
        let count = 2_000
        let formula = (0..<count).flatMap { _ in [MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mo", text: "+")] }
            + [MathMLNode(name: "mi", text: "x")]
        let root = MathMLNode(name: "math", children: formula + [
            MathMLNode(name: "mspace", attributes: ["linebreak": "newline"]),
            MathMLNode(name: "mtext", text: "אב גד"),
        ])
        let engine = LayoutEngine(fontName: nil)
        let box = try engine.layoutRoot(root, style: MathStyle(fontSize: 1, color: black))
        let work = engine.textWork
        let before = work.spent
        let requests = work.lineRequests
        let paragraph = Paragraph(box)
        let rows = paragraph.rows(limit: box.width / 2, first: box.width / 2, auto: (.left, 0))
        XCTAssertGreaterThan(rows.count, 2)
        XCTAssertEqual(work.lineRequests, requests + 1, "Only the selected full logical-text range needs a new line")
        XCTAssertLessThan(work.rowAssemblies, 20, "Formula candidate search must not build rows")
        XCTAssertLessThan(work.spent - before, count * 4, "Only selected formula rows and short text spans consume assembly work")
        XCTAssertFalse(work.exhausted)
        let publicLayout = try MathLayout(root, style: MathStyle(fontSize: 1, color: black), maximumWidth: box.width / 2)
        assertBoxCoversInk(publicLayout, "formula search with logical text")
    }

    func testFormulaSummariesRetainNegativeSpaceGeometryBesideLogicalText() throws {
        let formula = [
            MathMLNode(name: "mi", text: "x"),
            MathMLNode(name: "mspace", attributes: ["width": "20em"]),
            MathMLNode(name: "mo", text: "+"),
            MathMLNode(name: "mspace", attributes: ["width": "-20em"]),
        ] + (0..<20).flatMap { _ in [MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mo", text: "+")] }
            + [MathMLNode(name: "mi", text: "x")]
        let style = MathStyle(fontSize: 1, color: black)
        func rows(_ tail: MathMLNode, width: CGFloat) throws -> [Paragraph.Row] {
            let root = MathMLNode(name: "math", children: formula + [
                MathMLNode(name: "mspace", attributes: ["linebreak": "newline"]), tail,
            ])
            let box = try LayoutEngine(fontName: nil).layoutRoot(root, style: style)
            return Paragraph(box).rows(limit: width, first: width, auto: (.left, 0))
        }
        for width: CGFloat in [0, 10, 25, 50] {
            let mixed = try rows(MathMLNode(name: "mtext", text: "אב גד"), width: width)
            let plain = try rows(MathMLNode(name: "mi", text: "x"), width: width)
            XCTAssertEqual(mixed.prefix(plain.count - 1).map { $0.box.width }, plain.dropLast().map { $0.box.width }, "width \(width)")
        }
    }

    func testRepeatedSimpleLTRTextRetainsLinearCPUScaling() throws {
        func exercise(_ count: Int) throws {
            let root = MathMLNode(name: "math", children: [MathMLNode(name: "mtext", text: String(repeating: "word ", count: count))])
            let output = try MathLayout(root, style: MathStyle(fontSize: 1, color: black))
            XCTAssertEqual(output.rows.count, 1)
        }
        try assertCPUScaling(factor: 12, "unbounded simple LTR text", baseline: { try exercise(500) }, larger: { try exercise(2_000) })
    }
}
