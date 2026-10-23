import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class RTLAlignmentTests: XCTestCase {
    private func space(_ width: Int, _ color: String = "red") -> String {
        "<mspace width='\(width)em' height='1em' mathbackground='\(color)'/>"
    }
    private func cell(_ body: String) -> String { "<mtr><mtd>\(body)</mtd></mtr>" }
    private func table(_ a: String, _ b: String, _ attributes: String = "") -> String {
        "<mtable dir='rtl' \(attributes)>\(cell(a))\(cell(b))</mtable>"
    }
    private func rects(_ box: MathBox) -> [CGRect] {
        var result: [CGRect] = []
        func visit(_ box: MathBox, _ origin: CGPoint) {
            for item in box.items {
                switch item {
                case .rect(let rect, _): result.append(rect.offsetBy(dx: origin.x, dy: origin.y))
                case .box(let child, let p): visit(child, CGPoint(x: origin.x + p.x, y: origin.y + p.y))
                default: break
                }
            }
        }
        visit(box, .zero)
        return result
    }
    private func runs(_ box: MathBox) -> [(GlyphRun, CGFloat)] {
        var result: [(GlyphRun, CGFloat)] = []
        func visit(_ box: MathBox, _ x: CGFloat) {
            for item in box.items {
                switch item {
                case .glyphs(let run): result.append((run, x))
                case .box(let child, let p): visit(child, x + p.x)
                default: break
                }
            }
        }
        visit(box, 0)
        return result
    }
    private var first: String { "<maligngroup/>" + space(1) + "<maligngroup/>" + space(2, "blue") }
    private var second: String { "<maligngroup/>" + space(3, "lime") + "<maligngroup/>" + space(1, "black") }

    func testSourceGroupsProgressFromRightAndModesUsePhysicalEdges() throws {
        for (mode, redX) in [("left", 2.0), ("right", 4.0), ("center", 3.0)] {
            let box = try innerBox(table(first, second, "groupalign='{\(mode) left}'"))
            XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            let r = rects(box)
            XCTAssertEqual(r.map(\.width), [em, 2 * em, 3 * em, em])
            XCTAssertEqual(r[0].minX, redX * em, accuracy: 0.001)
            XCTAssertEqual(r[1].minX, 0, accuracy: 0.001)
            XCTAssertEqual(r[2].minX, 2 * em, accuracy: 0.001)
            XCTAssertEqual(r[3].minX, 0, accuracy: 0.001)
        }
    }

    func testRowMarkEdgesChoosePhysicalNeighborsAndFirstSourceMarkWins() throws {
        let engine = LayoutEngine(fontName: nil)
        let context = LayoutContext(fontSize: em, unclampedSize: em, minSize: 8, display: false,
                                    color: black, trackAlignment: true, alignmentRTL: true)
        for edge in ["left", "right"] {
            let node = try mathML("<mrow>" + space(1) + "<malignmark edge='\(edge)'/>" + space(2) + "</mrow>").children[0]
            let box = try engine.layout(node, context, depth: 0)
            let mark = try XCTUnwrap(box.alignment.first { if case .mark = $0.kind { return true }; return false })
            XCTAssertEqual(mark.x, 2 * em, accuracy: 0.001)
        }
        let a = "<maligngroup/>" + space(1) + "<malignmark/>" + space(2, "blue") + "<malignmark edge='right'/>"
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark/>" + space(1, "black")
        let r = rects(try innerBox(table(a, b)))
        XCTAssertEqual(r[0].minX, r[2].minX, accuracy: 0.001)
        XCTAssertEqual(r[1].maxX, r[3].maxX, accuracy: 0.001)
    }

    func testMissingGroupsReserveSpaceOnTheLeftAndEmptyGroupsStayDistinct() throws {
        let one = "<maligngroup/>" + space(1)
        let box = try innerBox(table(one, second))
        XCTAssertEqual(box.width, 4 * em, accuracy: 0.001)
        XCTAssertEqual(rects(box)[0].minX, em, accuracy: 0.001)
        let empty = "<maligngroup/><maligngroup/>" + space(1)
        XCTAssertEqual(rects(try innerBox(table(empty, second)))[0].minX, 0, accuracy: 0.001)
    }

    func testSameDirectionNestedGroupsAndOppositeDirectionAtomicExtents() throws {
        for wrapper in ["mrow", "mstyle"] {
            let a = "<\(wrapper) dir='rtl'>\(first)</\(wrapper)>"
            XCTAssertEqual(try innerBox(table(a, second)).width, 5 * em, accuracy: 0.001)
            let changed = "<\(wrapper) dir='ltr'>\(first)</\(wrapper)>"
            XCTAssertEqual(try innerBox(table(changed, second)).width, 4 * em, accuracy: 0.001)
            let outer = "<maligngroup/>\(changed)<maligngroup/>" + space(1, "black")
            XCTAssertEqual(try innerBox(table(outer, second)).width, 4 * em, accuracy: 0.001)
        }
    }

    func testRTLDecimalPointsAndExplicitNumericTokenMarksKeepDigitsLTR() throws {
        for marker in ["", "<malignmark/>"] {
            let a = "<maligngroup/><mn>12\(marker).3</mn><maligngroup/>" + space(1)
            let b = "<maligngroup/><mn>4\(marker).56</mn><maligngroup/>" + space(2)
            let drawn = runs(try innerBox(table(a, b, "groupalign='{decimalpoint left}'")))
            XCTAssertEqual(drawn.count, 2)
            XCTAssertEqual(drawn[0].1 + drawn[0].0.positions[2].x,
                           drawn[1].1 + drawn[1].0.positions[1].x, accuracy: 0.001)
            XCTAssertLessThan(drawn[0].0.positions[0].x, drawn[0].0.positions[1].x)
        }
    }

    func testRTLCellAndNestedBackgroundsExpandAcrossGroups() throws {
        for wrapper in ["mtd", "mrow", "mstyle"] {
            let a = wrapper == "mtd" ? "<mtr><mtd mathbackground='black'>\(first)</mtd></mtr>"
                : cell("<\(wrapper) mathbackground='black'>\(first)</\(wrapper)>")
            let box = try innerBox("<mtable dir='rtl'>\(a)\(cell(second))</mtable>")
            XCTAssertEqual(rects(box)[0].minX, 0, accuracy: 0.001)
            XCTAssertEqual(rects(box)[0].width, 5 * em, accuracy: 0.001)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(box.inkBounds).minX, -0.001)
            XCTAssertLessThanOrEqual(try XCTUnwrap(box.inkBounds).maxX, box.width + 0.001)
        }
    }

    func testRTLTracksKeepSourceAttributeListsAndPhysicalLabels() throws {
        for side in ["left", "right"] {
            let body = "<mtable dir='rtl' columnspacing='1em' groupalign='{right} {left}' side='\(side)' minlabelspacing='1em'>"
                + "<mlabeledtr><mtd>" + space(1, "black") + "</mtd><mtd>\(first)</mtd><mtd>\(first)</mtd></mlabeledtr>"
                + "<mtr><mtd>\(second)</mtd><mtd>\(second)</mtd></mtr></mtable>"
            let box = try innerBox(body), r = rects(box)
            let gutter = side == "left" ? 2 * em : 0
            XCTAssertEqual(r[0].minX, gutter + 10 * em, accuracy: 0.001)
            XCTAssertEqual(r[2].minX, gutter + 2 * em, accuracy: 0.001)
            XCTAssertEqual(r[4].minX, side == "left" ? 0 : 12 * em, accuracy: 0.001)
        }
    }

    func testRTLColumnAlignmentAndSpansUseReflectedTracks() throws {
        let body = "<mtable dir='rtl' columnspacing='1em' columnalign='left right'>"
            + "<mtr><mtd>" + space(1) + "</mtd><mtd>" + space(2, "blue") + "</mtd></mtr>"
            + "<mtr><mtd>" + space(3, "lime") + "</mtd><mtd>" + space(4, "black") + "</mtd></mtr>"
            + "<mtr><mtd columnspan='2'>" + space(8) + "</mtd></mtr></mtable>"
        let r = rects(try innerBox(body))
        XCTAssertEqual(r.map(\.minX), [5 * em, 2 * em, 5 * em, 0, 0])
    }

    func testRTLRowsKeepChildDrawingAndForcedBreaksInSourceOrder() throws {
        let body = space(1) + space(2, "blue")
            + "<mspace linebreak='newline'/>" + space(3, "lime") + space(4, "black")
        let root = try mathML(body, attributes: "dir='rtl'")
        let box = try innerBox(root)
        XCTAssertEqual(rects(box).map(\.minX), [9 * em, 7 * em, 4 * em, 0])
        let layout = try MathLayout(root, style: MathStyle(fontSize: em, color: black), maximumWidth: .infinity)
        XCTAssertEqual(layout.rows.count, 2)
        let lines = Paragraph(box).rows(limit: .infinity, first: .infinity, auto: (.left, 0))
        let first = rects(lines[0].box), second = rects(lines[1].box)
        XCTAssertEqual(first.map(\.minX), [2 * em, 0])
        XCTAssertEqual(second.map(\.minX), [4 * em, 0])
    }
    func testRTLIndentTargetsNamePhysicalLeftEdgesIncludingOpaqueLTRChildren() throws {
        for (content, targetX) in [
            (space(1) + "<mrow id='target'>" + space(2, "blue") + space(3, "lime") + "</mrow>" + space(4, "black"), 4.0),
            (space(1) + "<mrow dir='ltr' mathbackground='black'><mspace id='target' width='2em' height='1em'/>"
                + space(3, "lime") + "</mrow>" + space(4, "black"), 4.0),
        ] {
            let body = content
                + "<mspace linebreak='newline' indentalign='id' indenttarget='target'/>" + space(1)
            let lines = Paragraph(try innerBox(mathML(body, attributes: "dir='rtl'"))).rows(limit: .infinity, first: .infinity, auto: (.left, 0))
            XCTAssertEqual(lines.count, 2)
            XCTAssertEqual(lines[1].x, targetX * em, accuracy: 0.001)
        }
    }

    func testRTLOppositeDirectionRowsResolveTheirOwnForcedBreaks() throws {
        let body = "<math dir='rtl'>" + space(1)
            + "<mrow dir='ltr'>" + space(2) + "<mspace linebreak='newline'/>" + space(3) + "</mrow>"
            + space(4) + "</math>"
        let box = try innerBox(body)
        XCTAssertEqual(box.width, 8 * em, accuracy: 0.001)
        XCTAssertGreaterThan(box.height, 2 * em)
        let r = rects(box)
        XCTAssertEqual(r.map(\.minX), [7 * em, 4 * em, 4 * em, 0])
    }

    func testRTLTableScopesKeepNestedMarksAndDisableOnlyRequestedColumns() throws {
        let inner = "<mtable alignmentscope='false'>" + cell(space(1) + "<malignmark/>" + space(2, "blue")) + "</mtable>"
        let a = "<maligngroup/>" + inner
        let b = "<maligngroup/>" + space(3, "lime") + "<malignmark/>" + space(1, "black")
        let r = rects(try innerBox(table(a, b)))
        XCTAssertEqual(r[0].minX, r[2].minX, accuracy: 0.001)
        XCTAssertEqual(r[1].maxX, r[3].maxX, accuracy: 0.001)
        let body = "<mtable dir='rtl' alignmentscope='false true' columnspacing='0'>"
            + "<mtr><mtd>\(first)</mtd><mtd>\(first)</mtd></mtr>"
            + "<mtr><mtd>\(second)</mtd><mtd>\(second)</mtd></mtr></mtable>"
        let box = try innerBox(body)
        XCTAssertEqual(box.width, 9 * em, accuracy: 0.001)
        XCTAssertEqual(rects(box)[0].minX, 7.5 * em, accuracy: 0.001)
    }

    func testRTLSpanningCellsAndGridLinesReflectAsOneGrid() throws {
        func paths(_ box: MathBox, x: CGFloat = 0) -> [CGRect] {
            box.items.flatMap { item -> [CGRect] in
                switch item {
                case .path(let path, _, _, _), .dashes(let path, _, _, _): [path.boundingBoxOfPath.offsetBy(dx: x, dy: 0)]
                case .box(let child, let point): paths(child, x: x + point.x).map { $0.offsetBy(dx: 0, dy: point.y) }
                default: []
                }
            }
        }
        let body = "<mtable frame='solid' columnlines='solid dashed' rowlines='solid' columnspacing='1em 2em'>"
            + "<mtr><mtd rowspan='2'>" + space(1) + "</mtd><mtd columnspan='2'>" + space(7) + "</mtd></mtr>"
            + "<mtr><mtd>" + space(2) + "</mtd><mtd>" + space(3) + "</mtd></mtr></mtable>"
        let ltr = try innerBox(body), rtl = try innerBox("<mstyle dir='rtl'>\(body)</mstyle>")
        XCTAssertEqual(ltr.width, rtl.width, accuracy: 0.001)
        let expected = paths(ltr).map { CGRect(x: ltr.width - $0.maxX, y: $0.minY, width: $0.width, height: $0.height) }
        let actual = paths(rtl)
        XCTAssertEqual(expected.count, actual.count)
        for (a, b) in zip(expected, actual) {
            XCTAssertEqual(a.minX, b.minX, accuracy: 0.001)
            XCTAssertEqual(a.maxX, b.maxX, accuracy: 0.001)
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.001)
            XCTAssertEqual(a.maxY, b.maxY, accuracy: 0.001)
        }
    }

    func testRTLManyEmptyGroupsAndCombinedSideWidthsStayBounded() throws {
        let groups = Array(repeating: MathMLNode(name: "maligngroup"), count: 10_000)
        let body = MathMLNode(name: "mtable", attributes: ["dir": "rtl"], children: [
            MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: groups)])
        ])
        XCTAssertEqual(try innerBox(body).width, 0)
        let huge = "<maligngroup/>" + String(repeating: "<mspace width='50000px'/>", count: 3) + "<malignmark/>"
        let other = "<maligngroup/><malignmark/>" + String(repeating: "<mspace width='50000px'/>", count: 3)
        XCTAssertThrowsError(try innerBox(table(huge, other))) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }

}
