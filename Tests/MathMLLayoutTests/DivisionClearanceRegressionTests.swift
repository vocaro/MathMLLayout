import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

/// Signs wider than an outer digit column must clear the six enclosing division frames.
final class DivisionClearanceRegressionTests: MathTestCase {
    private struct Drawing {
        var work: [CGRect] = []
        var signs: [CGRect] = []
        var frame: [CGRect] = []
        var ink: [CGRect] = []
        var rules: [CGRect] = []
        var backgrounds: [CGRect] = []
        var curve: CGRect?
        var box = MathBox()
    }

    private func drawing(_ body: String) throws -> Drawing {
        let context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
        var result = Drawing(box: try LayoutEngine(fontName: nil).layout(node(body).children[0], context, depth: 0))
        let lime = MathColor.parse("lime")
        func collect(_ box: MathBox, at origin: CGPoint) {
            for item in box.items {
                switch item {
                case .box(let child, let point):
                    collect(child, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
                case .glyphs(let run):
                    var advances = [CGSize](repeating: .zero, count: run.glyphs.count)
                    var inks = [CGRect](repeating: .zero, count: run.glyphs.count)
                    CTFontGetAdvancesForGlyphs(run.font, .horizontal, run.glyphs, &advances, run.glyphs.count)
                    CTFontGetBoundingRectsForGlyphs(run.font, .horizontal, run.glyphs, &inks, run.glyphs.count)
                    for index in run.glyphs.indices {
                        let point = CGPoint(x: origin.x + run.positions[index].x, y: origin.y + run.positions[index].y)
                        let ink = inks[index].offsetBy(dx: point.x, dy: point.y)
                        result.ink.append(ink)
                        if run.color == lime {
                            let rect = CGRect(x: point.x, y: ink.minY, width: advances[index].width, height: ink.height)
                            result.work.append(rect)
                            if CTFontCopyNameForGlyph(run.font, run.glyphs[index]) as String? == "plus" { result.signs.append(rect) }
                        }
                    }
                case .rect(let rect, let color):
                    let rect = rect.offsetBy(dx: origin.x, dy: origin.y)
                    result.ink.append(rect)
                    if color == lime { result.work.append(rect) } else if color == black {
                        result.frame.append(rect); result.rules.append(rect)
                    } else { result.backgrounds.append(rect) }
                case .path(let path, let width, let color, _):
                    let rect = path.boundingBoxOfPath.insetBy(dx: -width / 2, dy: -width / 2)
                        .offsetBy(dx: origin.x, dy: origin.y)
                    result.ink.append(rect)
                    if color == black { result.frame.append(rect); result.curve = rect }
                default: break
                }
            }
        }
        collect(result.box, at: .zero)
        return result
    }

    private func division(_ style: String, leading: Bool, tallDivisor: Bool, sign: Bool = true,
                          operatorText: String = "+", backgrounds: Bool = false) -> String {
        let divisor = tallDivisor ? "<mn>8</mn><mn>8</mn>" : "<mn>8</mn>"
        let work = sign ? (leading ? "<mo>\(operatorText)</mo><mn>23</mn>" : "<mn>12</mn><mo>\(operatorText)</mo>") : "<mn>123</mn>"
        let result = "<mn mathcolor='blue'>456</mn>"
        let resultGroup = backgrounds ? "<msgroup mathbackground='yellow'>\(result)</msgroup>" : result
        let rowBackground = backgrounds ? " mathbackground='magenta'" : ""
        let rows = "<msrow mathcolor='lime'\(rowBackground)>\(work)</msrow><msline mathcolor='lime'/>"
        let workGroup = backgrounds ? "<msgroup mathbackground='cyan'>\(rows)</msgroup>" : rows
        return "<mlongdiv longdivstyle='\(style)' stackalign='right'><msgroup mathcolor='red'>\(divisor)</msgroup>"
            + "\(resultGroup)<mn mathcolor='lime'>123</mn>\(workGroup)</mlongdiv>"
    }

    private func assertClear(_ drawn: Drawing, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for frame in drawn.frame {
            for work in drawn.work {
                let overlap = frame.intersection(work)
                XCTAssertFalse(overlap.width > 0.01 && overlap.height > 0.01,
                               "\(message): frame \(frame) overlaps work \(work)", file: file, line: line)
            }
        }
        for ink in drawn.ink {
            XCTAssertGreaterThanOrEqual(ink.minX, -0.01, message, file: file, line: line)
            XCTAssertLessThanOrEqual(ink.maxX, drawn.box.width + 0.01, message, file: file, line: line)
            XCTAssertGreaterThanOrEqual(ink.minY, -drawn.box.descent - 0.01, message, file: file, line: line)
            XCTAssertLessThanOrEqual(ink.maxY, drawn.box.ascent + 0.01, message, file: file, line: line)
        }
    }

    func testOuterSignsAndTheirRulesClearEveryEnclosingFrame() throws {
        for style in ["lefttop", "righttop", "stackedrightright", "mediumstackedrightright", "stackedleftleft", "stackedleftlinetop"] {
            for leading in [true, false] {
                for tall in [true, false] {
                    let message = "\(style), leading=\(leading), tall divisor=\(tall)"
                    let drawn = try drawing(division(style, leading: leading, tallDivisor: tall))
                    XCTAssertEqual(drawn.signs.count, 1, message)
                    assertClear(drawn, message)
                    if let vertical = drawn.rules.first(where: { $0.height > $0.width }),
                       let sign = drawn.signs.first, vertical.minY < sign.maxY, sign.minY < vertical.maxY {
                        let left = style == "stackedleftleft" || style == "stackedleftlinetop"
                        let gap = left ? sign.minX - vertical.maxX : vertical.minX - sign.maxX
                        XCTAssertGreaterThanOrEqual(gap, style == "righttop" ? 0 : 4 - 0.01, message)
                    }
                    // The bar stays connected to the moved frame, including with a two-row divisor.
                    if ["lefttop", "righttop", "stackedleftlinetop"].contains(style) {
                        let bar = try XCTUnwrap(drawn.rules.filter { $0.width > $0.height }.max { $0.minY < $1.minY }, message)
                        if let curve = drawn.curve { XCTAssertEqual(bar.minX, curve.minX, accuracy: 0.01, message) }
                        if let vertical = drawn.rules.first(where: { $0.height > $0.width }) {
                            XCTAssertEqual(bar.maxY, vertical.maxY, accuracy: 0.01, message)
                            if style == "stackedleftlinetop" { XCTAssertEqual(bar.minX, vertical.minX, accuracy: 0.01, message) }
                            else {
                                let under = try XCTUnwrap(drawn.rules.filter { $0.width > $0.height }.min { $0.minY < $1.minY }, message)
                                XCTAssertEqual(bar.maxX, under.maxX, accuracy: 0.01, message)
                            }
                        }
                    }
                }
            }
        }
    }

    func testOrdinaryWorkKeepsTheOriginalFramePosition() throws {
        for style in ["stackedrightright", "mediumstackedrightright", "stackedleftleft", "stackedleftlinetop", "righttop", "lefttop"] {
            let drawn = try drawing(division(style, leading: false, tallDivisor: false, sign: false))
            assertClear(drawn, style)
            let digits = drawn.work.filter { $0.height > 1 }.sorted { $0.minX < $1.minX }
            let first = try XCTUnwrap(digits.first), last = try XCTUnwrap(digits.last)
            if let vertical = drawn.rules.first(where: { $0.height > $0.width }) {
                let gap = ["stackedleftleft", "stackedleftlinetop"].contains(style)
                    ? first.minX - vertical.maxX : vertical.minX - last.maxX
                XCTAssertEqual(gap, style == "righttop" ? 8 : 4, accuracy: 0.01, style)
            } else if let curve = drawn.curve {
                XCTAssertEqual(first.minX - curve.maxX, 2.5, accuracy: 0.01, style)
            }
        }
    }

    func testVeryWideSignsMoveTopFramesAndLengthenTheirBars() throws {
        for style in ["lefttop", "righttop", "stackedleftlinetop"] {
            let leading = style != "righttop"
            let ordinary = try drawing(division(style, leading: leading, tallDivisor: true, sign: false))
            let wide = try drawing(division(style, leading: leading, tallDivisor: true, operatorText: "+++"))
            assertClear(wide, style)
            let before = try XCTUnwrap(ordinary.rules.filter { $0.width > $0.height }.max { $0.minY < $1.minY }, style)
            let after = try XCTUnwrap(wide.rules.filter { $0.width > $0.height }.max { $0.minY < $1.minY }, style)
            XCTAssertGreaterThan(after.width, before.width + 1, "the moved frame lengthens the bar: \(style)")
            if let curve = wide.curve { XCTAssertEqual(after.minX, curve.minX, accuracy: 0.01, style) }
            if let vertical = wide.rules.first(where: { $0.height > $0.width }) {
                XCTAssertEqual(after.maxY, vertical.maxY, accuracy: 0.01, style)
                if leading { XCTAssertEqual(after.minX, vertical.minX, accuracy: 0.01, style) }
                else {
                    let under = try XCTUnwrap(wide.rules.filter { $0.width > $0.height }.min { $0.minY < $1.minY }, style)
                    XCTAssertEqual(after.maxX, under.maxX, accuracy: 0.01, style)
                }
            }
        }
    }

    func testSignsThatFallShortOfTheFrameLeaveItInPlace() throws {
        for (style, leading, tall) in [("righttop", false, true), ("lefttop", true, true), ("stackedleftlinetop", true, false)] {
            let ordinary = try drawing(division(style, leading: leading, tallDivisor: tall, sign: false))
            let near = try drawing(division(style, leading: leading, tallDivisor: tall))
            assertClear(near, style)
            XCTAssertEqual(ordinary.rules, near.rules, style)
            XCTAssertEqual(ordinary.curve, near.curve, style)
        }
    }

    func testMovedBarsKeepRowAndGroupBackgrounds() throws {
        for style in ["lefttop", "righttop", "stackedleftlinetop"] {
            let leading = style != "righttop"
            let plain = try drawing(division(style, leading: leading, tallDivisor: true, operatorText: "+++"))
            let painted = try drawing(division(style, leading: leading, tallDivisor: true, operatorText: "+++", backgrounds: true))
            assertClear(painted, style)
            XCTAssertEqual(painted.rules, plain.rules, style)
            XCTAssertEqual(painted.curve, plain.curve, style)
            XCTAssertEqual(painted.backgrounds.count, 3, style)
            let row = try XCTUnwrap(painted.backgrounds.last, style)
            for sign in painted.signs { XCTAssertTrue(row.contains(sign), style) }
        }
    }
}
