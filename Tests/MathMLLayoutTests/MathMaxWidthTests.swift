import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class MathMaxWidthTests: MathTestCase {
    let body = ["alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta"]
        .map { "<mi>\($0)</mi>" }.joined(separator: "<mo>+</mo>")

    var style: MathStyle { MathStyle(fontSize: 20, color: black) }

    func root(_ maxwidth: String?, body: String? = nil) throws -> MathMLNode {
        var result = try node(body ?? self.body)
        result.attributes["maxwidth"] = maxwidth
        return result
    }

    func assertSame(_ actual: MathLayout, _ expected: MathLayout, _ message: String = "",
                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.rows.count, expected.rows.count, message, file: file, line: line)
        for (a, b) in zip(actual.rows, expected.rows) {
            XCTAssertEqual(a.origin, b.origin, message, file: file, line: line)
            XCTAssertEqual(a.width, b.width, accuracy: 0.001, message, file: file, line: line)
            XCTAssertEqual(a.ascent, b.ascent, accuracy: 0.001, message, file: file, line: line)
            XCTAssertEqual(a.descent, b.descent, accuracy: 0.001, message, file: file, line: line)
        }
        XCTAssertEqual(actual.widestUnbreakableWidth, expected.widestUnbreakableWidth,
                       accuracy: 0.001, message, file: file, line: line)
        XCTAssertEqual(ink(actual), ink(expected), message, file: file, line: line)
    }

    func testAuthoredCapNarrowsHostBudgetsIndependently() throws {
        // Includes a larger first-row budget: it keeps its existing meaning, but the author
        // cannot enlarge either host budget. Unknown and enormous host widths are unbounded.
        let cases: [(CGFloat, CGFloat?, CGFloat)] = [
            (200, 80, 120), (100, 80, 300), (100, 180, 120),
            (.infinity, nil, 120), (.greatestFiniteMagnitude, 80, 120),
            (.nan, .nan, 120), (.infinity, 80, 120), (100, .infinity, 120),
            (0, nil, 120), (-10, -5, 120), (200, 0, 120),
        ]
        for (host, first, authored) in cases {
            let normalizedHost = host.isNaN || host > MathLimits.extent ? CGFloat.infinity : max(0, host)
            let normalizedFirst = first.map {
                $0.isNaN ? normalizedHost : $0 > MathLimits.extent ? .infinity : max(0, $0)
            } ?? normalizedHost
            let actual = try MathLayout(root("\(authored)px"), style: style,
                                        maximumWidth: host, firstRowMaximumWidth: first)
            let expected = try MathLayout(root(nil), style: style, maximumWidth: min(normalizedHost, authored),
                                          firstRowMaximumWidth: min(normalizedFirst, authored))
            assertSame(actual, expected, "host=\(host), first=\(String(describing: first))")
        }
        let narrowed = try MathLayout(root("120px"), style: style, maximumWidth: 200, firstRowMaximumWidth: 80)
        XCTAssertGreaterThan(narrowed.rows.count, 2)
        XCTAssertLessThanOrEqual(narrowed.rows[0].width, 80.001)
        for row in narrowed.rows.dropFirst() { XCTAssertLessThanOrEqual(row.origin.x + row.width, 120.001) }
        var display = try root("120px")
        display.attributes["display"] = "block"
        var uncapped = display
        uncapped.attributes["maxwidth"] = nil
        assertSame(try MathLayout(display, style: style, maximumWidth: 200, firstRowMaximumWidth: 80),
                   try MathLayout(uncapped, style: style, maximumWidth: 120, firstRowMaximumWidth: 80))
    }

    func testAbsoluteAndFontRelativeUnitsOnAnUnboundedHost() throws {
        let engine = LayoutEngine(fontName: nil)
        let ex = CTFontGetXHeight(engine.font.base) * style.fontSize
        let values: [(String, CGFloat)] = [
            ("120px", 120), ("90pt", 120), ("7.5pc", 120), ("1.25in", 120),
            ("3.175cm", 120), ("31.75mm", 120), ("127q", 120), ("6em", 120),
            ("10ex", 10 * ex), ("thickmathspace", 20 * 5 / 18),
        ]
        for (text, points) in values {
            XCTAssertEqual(try XCTUnwrap(engine.mathMaximumWidth(root(text), style: style, available: .infinity)),
                           points, accuracy: 0.001, text)
            assertSame(try MathLayout(root(text), style: style),
                       try MathLayout(root(nil), style: style, maximumWidth: points), text)
        }
        // Width limits do not use the 1000-em clamp intended for spacing lengths.
        let tinyStyle = MathStyle(fontSize: 1, color: black)
        XCTAssertEqual(try XCTUnwrap(engine.mathMaximumWidth(root("2000px"), style: tinyStyle, available: 3000)), 2000)
        var resized = try root("6em")
        resized.attributes["mathsize"] = "150%"
        var uncapped = resized
        uncapped.attributes["maxwidth"] = nil
        assertSame(try MathLayout(resized, style: style),
                   try MathLayout(uncapped, style: style, maximumWidth: 180))
        resized.attributes["mathsize"] = nil
        resized.attributes["scriptlevel"] = "1"
        let context = engine.inherit(resized, engine.rootContext(resized, style: style))
        resized.attributes["maxwidth"] = "10ex"
        XCTAssertEqual(try XCTUnwrap(engine.mathMaximumWidth(resized, style: style, available: .infinity)),
                       10 * engine.xHeight(context), accuracy: 0.001)
    }

    func testPercentAndUnitlessValuesUseTheGeneralHostWidth() throws {
        for authored in ["60%", "0.6"] {
            assertSame(try MathLayout(root(authored), style: style, maximumWidth: 200, firstRowMaximumWidth: 80),
                       try MathLayout(root(nil), style: style, maximumWidth: 120, firstRowMaximumWidth: 80), authored)
            for host in [CGFloat.infinity, .greatestFiniteMagnitude, .nan] {
                // A finite first-row width does not supply a reference for the overall width.
                assertSame(try MathLayout(root(authored), style: style, maximumWidth: host, firstRowMaximumWidth: 80),
                           try MathLayout(root(nil), style: style, maximumWidth: host, firstRowMaximumWidth: 80), authored)
            }
        }
        for authored in ["200%", "2"] {
            assertSame(try MathLayout(root(authored), style: style, maximumWidth: 120),
                       try MathLayout(root(nil), style: style, maximumWidth: 120), authored)
        }
    }

    func testInvalidNegativeAndNonfiniteValuesLeaveHostBudgetsAlone() throws {
        let invalid = ["", " ", "garbage", "auto", "NaN", "Infinity", "infpx", "1e309px", "-1px",
                       "-10%", "negativeverythinmathspace", "1width", "10%height", "1.2.3em", "120vw",
                       String(repeating: "9", count: 100) + "px"]
        for host in [CGFloat.infinity, 120] {
            let expected = try MathLayout(root(nil), style: style, maximumWidth: host, firstRowMaximumWidth: 80)
            for value in invalid {
                assertSame(try MathLayout(root(value), style: style, maximumWidth: host, firstRowMaximumWidth: 80),
                           expected, value)
            }
        }
        for value in ["9999999999999999999999999999999999999999999999999999999999999in", "60000px"] {
            assertSame(try MathLayout(root(value), style: style), try MathLayout(root(nil), style: style), value)
        }
        var nonmath = try root("1px")
        nonmath.name = "mrow"
        var plain = nonmath
        plain.attributes["maxwidth"] = nil
        assertSame(try MathLayout(nonmath, style: style, maximumWidth: 120),
                   try MathLayout(plain, style: style, maximumWidth: 120))
    }

    func testZeroForcedBreaksAndUnbreakableReporting() throws {
        for value in ["0", "0px", "0%", "-0em"] {
            let actual = try MathLayout(root(value), style: style)
            assertSame(actual, try MathLayout(root(nil), style: style, maximumWidth: 0), value)
            XCTAssertGreaterThan(actual.widestUnbreakableWidth, 0)
            XCTAssertGreaterThan(actual.rows.count, 1)
            XCTAssertTrue(actual.rows.allSatisfy { $0.width > 0 })
        }
        let forced = "<mi>alpha</mi><mo linebreak='newline'>=</mo><mi>beta</mi>"
        for value in ["120px", "60000px", "invalid"] {
            let actual = try MathLayout(root(value, body: forced), style: style)
            XCTAssertEqual(actual.rows.count, 2)
        }
        let single = "<mn>123456789012345678901234567890</mn>"
        let capped = try MathLayout(root("1px", body: single), style: style)
        XCTAssertEqual(capped.rows.count, 1)
        XCTAssertGreaterThan(capped.width, 1)
        XCTAssertEqual(capped.widestUnbreakableWidth, capped.width, accuracy: 0.001)
        let exact = try MathLayout(root(nil, body: single), style: style, maximumWidth: capped.widestUnbreakableWidth)
        XCTAssertLessThanOrEqual(exact.width, capped.widestUnbreakableWidth + 0.001)
    }

    func testAuthoredCapWrapsNestedPartsAndKeepsTrialsBounded() throws {
        let nested = "<msqrt>\(body)</msqrt><mo>+</mo><mfrac><mrow>\(body)</mrow><mn>2</mn></mfrac>"
        let cappedRoot = try root("90px", body: nested)
        let result = try MathLayout(cappedRoot, style: style)
        assertSame(result, try MathLayout(root(nil, body: nested), style: style, maximumWidth: 90))
        let measured = try LayoutEngine.lines(cappedRoot, style: style, maximumWidth: .infinity,
                                             firstRowMaximumWidth: nil)
        XCTAssertLessThanOrEqual(measured.layoutPasses, LayoutEngine.maximumWrappingPasses)
        // Reporting the minimum does not falsely promise that an authored smaller cap will fit;
        // the host must remove/change that cap when retrying at the minimum.
        let exact = try MathLayout(root(nil, body: nested), style: style, maximumWidth: result.widestUnbreakableWidth)
        for row in exact.rows {
            XCTAssertLessThanOrEqual(row.origin.x + row.width, result.widestUnbreakableWidth + 0.001)
        }
    }
}
