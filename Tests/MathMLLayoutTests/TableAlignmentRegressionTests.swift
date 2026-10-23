import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class TableAlignmentRegressionTests: XCTestCase {
    private func space(_ width: Int, _ color: String) -> String {
        "<mspace width='\(width)em' height='1em' mathbackground='\(color)'/>"
    }
    private func table(_ a: String, _ b: String, direction: String) -> String {
        "<mtable dir='\(direction)' columnalign='left'><mtr><mtd>\(a)</mtd></mtr><mtr><mtd>\(b)</mtd></mtr></mtable>"
    }
    private func rectangles(_ box: MathBox, at origin: CGPoint = .zero, onlyBlack: Bool = false) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .rect(let rect, let color):
                !onlyBlack || color.components?.prefix(3).allSatisfy({ $0 == 0 }) == true ? [rect.offsetBy(dx: origin.x, dy: origin.y)] : []
            case .box(let child, let p): rectangles(child, at: CGPoint(x: origin.x + p.x, y: origin.y + p.y), onlyBlack: onlyBlack)
            default: []
            }
        }
    }
    private func runs(_ box: MathBox, at origin: CGPoint = .zero) -> [(GlyphRun, CGPoint)] {
        box.items.flatMap { item -> [(GlyphRun, CGPoint)] in
            switch item {
            case .glyphs(let run): [(run, origin)]
            case .box(let child, let p): runs(child, at: CGPoint(x: origin.x + p.x, y: origin.y + p.y))
            default: []
            }
        }
    }
    private let forced = "<mspace linebreak='newline' indentalign='left' indentshift='0px'/>"

    func testSeparatorMarksKeepTheirCaretWhileBothWordsStayOnTheLine() throws {
        for direction in ["ltr", "rtl"] {
            for text in ["alpha<malignmark/> beta", "alpha <malignmark edge='right'/>beta"] {
                let token = "<mtext dir='ltr'>\(text)</mtext>"
                let a = "<maligngroup/>" + token + forced + space(1, "red")
                let b = "<maligngroup/>" + token
                let box = try innerBox(table(a, b, direction: direction))
                let drawn = runs(box)
                XCTAssertEqual(drawn.count, 3)
                XCTAssertEqual(drawn[0].1.x + drawn[0].0.positions[0].x,
                               drawn[2].1.x + drawn[2].0.positions[0].x, accuracy: 0.001, "\(direction): \(text)")
            }
        }
    }

    func testWrappedNestedBackgroundCoversItsAlignedSectionsWithoutOverhang() throws {
        for direction in ["ltr", "rtl"] {
            let first = direction == "ltr" ? 3 : 2, second = 5 - first
            let a = "<mrow mathbackground='black'><maligngroup/>" + space(first, "red") + forced
                + "<maligngroup/>" + space(second, "blue") + "</mrow>"
            let b = "<maligngroup/>" + space(first, "lime") + "<maligngroup/>" + space(second, "purple")
            let box = try innerBox(table(a, b, direction: direction))
            let backgrounds = rectangles(box, onlyBlack: true)
            XCTAssertEqual(backgrounds.count, 2)
            XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            let ordered = backgrounds.sorted { $0.minX < $1.minX }
            XCTAssertEqual(ordered[0].minX, 0, accuracy: 0.001)
            XCTAssertEqual(ordered[0].width, 3 * em, accuracy: 0.001)
            XCTAssertEqual(ordered[1].minX, 3 * em, accuracy: 0.001)
            XCTAssertEqual(ordered[1].width, 2 * em, accuracy: 0.001)
            XCTAssertLessThanOrEqual(try XCTUnwrap(box.inkBounds).maxX, box.width + 0.001)
        }
    }

    func testBreakOnlySpacesDoNotEnlargeThePreviousGroupOnALaterLine() throws {
        for direction in ["ltr", "rtl"] {
            for styling in ["", "mathbackground='black'"] {
                let stop = "<mspace linebreak='newline' indentalign='left' \(styling)/>"
                let a = "<maligngroup/>" + space(2, "red") + stop + "<maligngroup/>" + space(3, "blue")
                let b = "<maligngroup/>" + space(2, "lime") + "<maligngroup/>" + space(3, "purple")
                let box = try innerBox(table(a, b, direction: direction))
                XCTAssertEqual(box.width, 5 * em, accuracy: 0.001)
            }
        }
    }

    func testRowMarksKeepTheResolvedNeighborEdgeAcrossForcedWrapping() throws {
        for direction in ["ltr", "rtl"] {
            let contents = direction == "ltr"
                ? ["<malignmark/><mo>+</mo><mi>x</mi>", "<mi>x</mi><mo>+</mo><malignmark edge='right'/>"]
                : ["<mo>+</mo><malignmark/><mi>x</mi>", "<mi>x</mi><malignmark edge='right'/><mo>+</mo>"]
            for content in contents {
                let a = "<maligngroup/>" + content + forced + space(1, "red")
                let b = "<maligngroup/>" + content
                let box = try innerBox(table(a, b, direction: direction))
                let drawn = runs(box)
                XCTAssertEqual(drawn.count, 4)
                XCTAssertEqual(drawn[0].1.x + drawn[0].0.positions[0].x,
                               drawn[2].1.x + drawn[2].0.positions[0].x, accuracy: 0.001, "\(direction): \(content)")
            }
        }
    }

    func testRowMarksFollowTheDrawnEdgeOfAShrinkingFence() throws {
        for direction in ["ltr", "rtl"] {
            for edge in ["left", "right"] {
                let mark = "<malignmark edge='\(edge)'/>"
                let opening = "<mo mathbackground='red'>(</mo>"
                let prefix = (edge == "left") == (direction == "ltr") ? mark + opening : opening + mark
                let a = "<maligngroup/>" + prefix + "<mn>1</mn><mo>)</mo>" + forced
                    + "<mfrac><mn>2</mn><mfrac><mn>3</mn><mn>4</mn></mfrac></mfrac>"
                let b = "<maligngroup/>" + space(3, "lime")
                    + "<malignmark edge='\(direction == "ltr" ? "right" : "left")'/>"
                let box = try innerBox(table(a, b, direction: direction))
                let drawn = rectangles(box)
                let fence = try XCTUnwrap(drawn.first), other = try XCTUnwrap(drawn.last)
                let unbroken = try innerBox(mathML(a, attributes: "dir='\(direction)'"))
                XCTAssertGreaterThan(try XCTUnwrap(rectangles(unbroken).first).width, fence.width + 0.001)
                XCTAssertEqual(edge == "right" ? fence.maxX : fence.minX,
                               direction == "ltr" ? other.maxX : other.minX, accuracy: 0.001)
            }
        }
    }
}
