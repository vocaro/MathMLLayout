import CoreGraphics
@testable import MathMLLayout
import XCTest

final class RTLLayoutRegressionTests: XCTestCase {
    private func space(_ width: Int, _ color: String = "red") -> String {
        "<mspace width='\(width)em' height='1em' mathbackground='\(color)'/>"
    }
    private func rectangles(_ box: MathBox, x: CGFloat = 0) -> [(CGRect, CGColor)] {
        box.items.flatMap { item -> [(CGRect, CGColor)] in
            switch item {
            case .rect(let r, let c): [(r.offsetBy(dx: x, dy: 0), c)]
            case .box(let b, let p): rectangles(b, x: x + p.x).map { ($0.0.offsetBy(dx: 0, dy: p.y), $0.1) }
            default: []
            }
        }
    }

    private func glyphOrigins(_ box: MathBox, at origin: CGPoint = .zero) -> [CGPoint] {
        box.items.flatMap { item -> [CGPoint] in
            switch item {
            case .glyphs(let run): run.positions.map { CGPoint(x: origin.x + $0.x, y: origin.y + $0.y) }
            case .box(let child, let p): glyphOrigins(child, at: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
            default: []
            }
        }
    }

    func testForcedBreakInRTLScriptBaseIsHonoured() throws {
        let base = "<mrow>" + space(1) + "<mspace linebreak='newline' indentalign='left' indentshift='0px'/>" + space(2, "blue") + "</mrow>"
        for name in ["msub", "msup", "msubsup", "mmultiscripts"] {
            let scripts = name == "msubsup" || name == "mmultiscripts" ? "<mn>2</mn><mn>3</mn>" : "<mn>2</mn>"
            let body = "<\(name)>\(base)\(scripts)</\(name)>"
            let style = MathStyle(fontSize: em, color: black)
            let ltr = try MathLayout(mathML(body), style: style)
            let rtl = try MathLayout(mathML(body, attributes: "dir='rtl'"), style: style)
            XCTAssertGreaterThan(ltr.rows.count, 1)
            XCTAssertEqual(rtl.ascent + rtl.descent, ltr.ascent + ltr.descent, accuracy: 0.001, name)
            let drawn = try LayoutEngine.lines(mathML(body, attributes: "dir='rtl'"), style: style,
                                               maximumWidth: .infinity, firstRowMaximumWidth: nil)
            let rects = drawn.rows.flatMap { row in rectangles(row.box).map { $0.0.offsetBy(dx: row.origin.x, dy: row.origin.y) } }
            XCTAssertEqual(rects.count, 2)
            XCTAssertGreaterThan(rects[0].minY, rects[1].minY + em, name)
            let reference = try LayoutEngine.lines(mathML(body), style: style,
                                                   maximumWidth: .infinity, firstRowMaximumWidth: nil)
            let oldRects = reference.rows.flatMap { row in rectangles(row.box).map { $0.0.offsetBy(dx: row.origin.x, dy: row.origin.y) } }
            let expected = reference.rows.flatMap { glyphOrigins($0.box, at: $0.origin) }
            let actual = drawn.rows.flatMap { glyphOrigins($0.box, at: $0.origin) }
            XCTAssertEqual(actual.count, expected.count)
            for (a, b) in zip(actual, expected) {
                XCTAssertEqual(a.x - rects[1].minX, b.x - oldRects[1].minX, accuracy: 0.001, name)
                XCTAssertEqual(a.y - rects[1].minY, b.y - oldRects[1].minY, accuracy: 0.001, name)
            }
        }
    }

    func testForcedTableCellCannotExportConsumedAlignmentMarks() throws {
        for direction in ["ltr", "rtl"] {
            let node = try mathML("<mtable dir='\(direction)'><mtr><mtd><maligngroup/>" + space(1)
                + "<malignmark/><mspace linebreak='newline'/>" + space(2) + "</mtd></mtr></mtable>").children[0]
            let ctx = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                                    color: black, trackAlignment: true, alignmentRTL: direction == "rtl")
            let box = try LayoutEngine(fontName: nil).layout(node, ctx, depth: 0)
            XCTAssertFalse(box.alignment.contains { if case .mark = $0.kind { return true }; return false }, direction)
        }
    }

    func testRTLIndentTargetTracksShrinkingFenceLeftEdge() throws {
        for first in ["<mo id='target' mathbackground='red'>(</mo>",
                      "<mrow id='target'><mo mathbackground='red'>(</mo></mrow>"] {
            let inner = first + "<mn>1</mn><mo>)</mo>"
            let body = inner + "<mspace linebreak='newline' indentalign='id' indenttarget='target'/>"
                + "<mfrac><mn>2</mn><mfrac><mn>3</mn><mn>4</mn></mfrac></mfrac>"
            let root = try mathML(body, attributes: "dir='rtl'")
            let engine = LayoutEngine(fontName: nil)
            let box = try engine.layoutRoot(root, style: MathStyle(fontSize: em, color: black))
            let lines = Paragraph(box).rows(limit: .infinity, first: .infinity, auto: (.left, 0))
            XCTAssertEqual(lines.count, 2)
            guard lines.count == 2 else { return }
            let rect = try XCTUnwrap(rectangles(lines[0].box).first)
            let before = try XCTUnwrap(rectangles(box).first)
            XCTAssertGreaterThan(before.0.width, rect.0.width + 0.001, "the fence must actually shrink")
            XCTAssertEqual(lines[1].x, lines[0].x + rect.0.minX, accuracy: 0.001)
        }
    }
    private func retainedWords(work: TextShapingWork? = nil) -> MathBox {
        let ctx = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                                color: black, alignmentRTL: true)
        // The first retained word overhangs its advance, but the following space absorbs it.
        // This models a legacy/font fallback word whose drawn order remains LTR in RTL math.
        let a = MathBox(width: 10, ascent: 1, items: [.rect(CGRect(x: 9, y: 0, width: 3, height: 1), black)])
        let b = MathBox(width: 20, ascent: 1, items: [.rect(CGRect(x: 0, y: 0, width: 2, height: 1), black)])
        let space = BreakPoint(kind: .space, linebreak: .auto, style: LineStyle())
        var text = MathBox(width: 35, ascent: 1)
        text.add(a, at: .zero); text.add(b, at: CGPoint(x: 15, y: 0))
        text.row = BreakableRow(children: [.init(box: a, x: 0), .init(box: b, x: 15, point: space)],
                                itemCount: text.items.count, width: 35, isText: true, textWork: work, ctx)
        let last = MathBox(width: 1, ascent: 1, items: [.rect(CGRect(x: 0, y: 0, width: 1, height: 1), black)])
        var root = MathBox(width: 36, ascent: 1)
        root.add(text, at: CGPoint(x: 1, y: 0)); root.add(last, at: .zero)
        let stop = BreakPoint(kind: .none, linebreak: .newline, style: LineStyle())
        root.row = BreakableRow(children: [.init(box: text, x: 0), .init(box: .empty(), x: 35, point: stop),
                                          .init(box: last, x: 35)], itemCount: root.items.count, width: 36, ctx)
        return root
    }

    func testRTLRetainedWordInkIsMeasuredInItsDrawnOrder() {
        let rows = Paragraph(retainedWords()).rows(limit: 35, first: 35, auto: (.left, 0))
        XCTAssertEqual(rows.count, 2, "both words fit on the first forced row")
        XCTAssertEqual(rows.first?.box.width ?? 0, 35, accuracy: 0.001)
    }

    func testRTLRetainedWordMeasurementsUseTheSharedWorkBudget() {
        let work = TextShapingWork()
        XCTAssertTrue(work.consume(TextShapingWork.limit - 1))
        let paragraph = Paragraph(retainedWords(work: work))
        _ = paragraph.rows(limit: 35, first: 35, auto: (.left, 0))
        XCTAssertTrue(paragraph.textWorkExceeded)
        XCTAssertTrue(work.exhausted)
    }
}
