import Foundation
@testable import MathMLLayout
import XCTest

/// `MathMLNode.parse(xml:)`: what it reads, what it drops, and what it refuses.
final class ParserTests: XCTestCase {
    private func parse(_ xml: String, encoding: String.Encoding = .utf8) throws -> MathMLNode {
        try MathMLNode.parse(xml: try XCTUnwrap(xml.data(using: encoding)))
    }

    private func assertInvalid(_ xml: String, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try parse(xml), message.isEmpty ? xml : message, file: file, line: line) { error in
            guard case .invalidMarkup = error as? MathLayoutError else {
                return XCTFail("\(xml): expected invalidMarkup, got \(error)", file: file, line: line)
            }
        }
    }

    func testPredefinedAndNumericReferences() throws {
        let parsed = try parse("<math><mo>&lt;</mo><mo>&gt;</mo><mo>&amp;</mo><ms>&quot;&apos;</ms><mi>&#x3B1;</mi><mi>&#945;</mi><mi>&#x1D465;</mi></math>")
        XCTAssertEqual(parsed.children.map(\.text), ["<", ">", "&", "\"'", "α", "α", "𝑥"])
    }

    func testNamedEntitiesAreRefusedRatherThanDropped() {
        // Only XML's own entities are known. Dropping `&alpha;` would draw a different formula.
        assertInvalid("<math><mi>&alpha;</mi></math>")
        assertInvalid("<math><mi>f</mi><mo>&ApplyFunction;</mo><mi>x</mi></math>")
        assertInvalid("<math><mtext>a&nbsp;b</mtext></math>")
    }

    func testCDATACommentsAndProcessingInstructions() throws {
        let parsed = try parse("<?xml version=\"1.0\"?><!-- lead --><math><mtext>a<![CDATA[ < ]]>b</mtext><!-- c --><mi>x<!-- c -->y</mi><?pi data?><mn>1</mn></math>")
        XCTAssertEqual(parsed.children.map(\.name), ["mtext", "mi", "mn"])
        XCTAssertEqual(parsed.children.map(\.text), ["a < b", "xy", "1"])
    }

    func testTextOutsideTokensIsDropped() throws {
        let parsed = try parse("<math>stray<mrow> text <mi>x</mi> more </mrow><annotation>note</annotation></math>")
        XCTAssertEqual(parsed.text, "")
        XCTAssertEqual(parsed.children.map(\.text), ["", ""])
        XCTAssertEqual(parsed.children[0].children, [MathMLNode(name: "mi", text: "x")])
    }

    func testTokenTextIsKeptVerbatimForLayoutToNormalize() throws {
        let parsed = try parse("<math><mi> x </mi><mtext>a  b\n\tc</mtext></math>")
        XCTAssertEqual(parsed.children.map(\.text), [" x ", "a  b\n\tc"])
    }

    func testElementsInsideTokensJoinTheTokensText() throws {
        let parsed = try parse("<math><mi>a<mglyph src=\"g.png\" alt=\"g\"/>b</mi><mtext>x<span><b>y</b></span>z</mtext></math>")
        XCTAssertEqual(parsed.children.map(\.name), ["mi", "mtext"], "a token's element children are not its siblings")
        XCTAssertEqual(parsed.children[0].children.map(\.name), ["mglyph"])
        XCTAssertEqual(parsed.children[1].children.map(\.name), ["span"], "only the token's direct children are kept")
        XCTAssertEqual(parsed.children[1].text.filter { "xyz".contains($0) }, "xyz")
    }

    func testAttributesKeepTheirValuesAndLoseNamespacePrefixes() throws {
        let parsed = try parse("""
        <m:math xmlns:m="http://www.w3.org/1998/Math/MathML" xmlns:xlink="http://www.w3.org/1999/xlink" display="block" \
        alttext="a &lt; b"><m:mi mathvariant="bold" xlink:href="#x" id="i1">x</m:mi></m:math>
        """)
        XCTAssertEqual(parsed.attributes, ["display": "block", "alttext": "a < b"])
        XCTAssertEqual(parsed.children[0].attributes, ["mathvariant": "bold", "href": "#x", "id": "i1"])
    }

    func testPrefixedDefaultAndAbsentNamespacesReadTheSame() throws {
        let plain = try parse("<math><mfrac><mi>a</mi><mn>2</mn></mfrac></math>")
        let defaulted = try parse("<math xmlns=\"http://www.w3.org/1998/Math/MathML\"><mfrac><mi>a</mi><mn>2</mn></mfrac></math>")
        let prefixed = try parse("<mml:math xmlns:mml=\"http://www.w3.org/1998/Math/MathML\"><mml:mfrac><mml:mi>a</mml:mi><mml:mn>2</mml:mn></mml:mfrac></mml:math>")
        XCTAssertEqual(plain, defaulted)
        XCTAssertEqual(plain, prefixed)
    }

    func testAnyRootElementIsReturned() throws {
        XCTAssertEqual(try parse("<mrow><mi>x</mi></mrow>"), MathMLNode(name: "mrow", children: [MathMLNode(name: "mi", text: "x")]))
        XCTAssertEqual(try parse("<math/>"), MathMLNode(name: "math"))
    }

    func testEncodings() throws {
        let expected = MathMLNode(name: "math", children: [MathMLNode(name: "mi", text: "α"), MathMLNode(name: "mo", text: "−")])
        let body = "<math><mi>α</mi><mo>−</mo></math>"
        XCTAssertEqual(try parse(body), expected)
        XCTAssertEqual(try parse("\u{FEFF}" + body), expected, "UTF-8 with a byte order mark")
        XCTAssertEqual(try parse("<?xml version=\"1.0\" encoding=\"UTF-16\"?>" + body, encoding: .utf16), expected)
        XCTAssertEqual(try MathMLNode.parse(xml: Data("<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?><math><mi>\u{E9}</mi></math>".unicodeScalars.map { UInt8($0.value) })),
                       MathMLNode(name: "math", children: [MathMLNode(name: "mi", text: "é")]))
    }

    func testMalformedDocumentsThrowInvalidMarkup() {
        let documents = [
            "", " ", "not xml", "<math>", "<math><mi>x</math>", "<math><mi>x</mn></math>", "</math>",
            "<math><mi>x</mi></math><math/>", "<math><mi>x</mi></math>trailing", "<math><mi a=\"1\" a=\"2\">x</mi></math>",
            "<math><mi a=1>x</mi></math>", "<math><mi>&#0;</mi></math>", "<math><mi>&#x110000;</mi></math>",
            "<math><mi>a & b</mi></math>", "<math><mi>a < b</mi></math>",
        ]
        for document in documents { assertInvalid(document) }
    }

    /// README: "refuses document type declarations, so no entity expands and nothing external loads".
    func testDocumentTypeDeclarationsAreRefused() {
        let internalSubset = #"<!DOCTYPE math [<!ENTITY a "aaaa">]><math><mi>&a;</mi></math>"#
        let external = #"<!DOCTYPE math PUBLIC "-//W3C//DTD MathML 3.0//EN" "http://www.w3.org/Math/DTD/mathml3/mathml3.dtd"><math><mi>x</mi></math>"#
        for document in [internalSubset, external, "<?xml version=\"1.0\"?>\n" + internalSubset, "\u{FEFF}" + internalSubset] {
            assertInvalid(document)
        }
    }

    /// The refusal has to hold in every encoding XMLParser reads, not only where the bytes of
    /// "<!DOCTYPE" are ASCII.
    func testDocumentTypeDeclarationsAreRefusedInUTF16() throws {
        // Fails until https://github.com/vocaro/MathMLLayout/issues/7 is fixed.
        let document = #"<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE math [<!ENTITY a "block">]><math display="&a;"><mi>&a;</mi></math>"#
        for (name, encoding) in [("UTF-16", String.Encoding.utf16), ("UTF-16LE", .utf16LittleEndian), ("UTF-16BE", .utf16BigEndian)] {
            let data = try XCTUnwrap(document.data(using: encoding))
            XCTAssertThrowsError(try MathMLNode.parse(xml: data), "a \(name) document type declaration was accepted") { error in
                guard case .invalidMarkup = error as? MathLayoutError else { return XCTFail("expected invalidMarkup, got \(error)") }
            }
            // Nor may its entities reach the tree, expanded (attributes) or silently dropped (text).
            if let parsed = try? MathMLNode.parse(xml: data) {
                XCTAssertNil(parsed.attributes["display"], "\(name): an entity expanded into an attribute")
                XCTAssertNotEqual(parsed.children.first?.text, "", "\(name): an entity reference vanished from token text")
            }
        }
    }

    func testInputLargerThanFourMebibytesIsRefused() throws {
        let limit = 4 * 1024 * 1024
        let open = "<math><!--", close = "--><mi>x</mi></math>"
        let padded = open + String(repeating: "p", count: limit - open.utf8.count - close.utf8.count) + close
        XCTAssertEqual(padded.utf8.count, limit)
        XCTAssertEqual(try parse(padded).children, [MathMLNode(name: "mi", text: "x")], "exactly 4 MiB is read")
        XCTAssertThrowsError(try parse(open + "p" + padded.dropFirst(open.count))) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    func testDepthLimitIsExactlySixtyFourLevels() throws {
        func nested(_ levels: Int) -> String {
            // `levels` elements deep: math, then mrows, then the mi.
            "<math>" + String(repeating: "<mrow>", count: levels - 2) + "<mi>x</mi>" + String(repeating: "</mrow>", count: levels - 2) + "</math>"
        }
        XCTAssertNoThrow(try parse(nested(MathLimits.depth)))
        XCTAssertThrowsError(try parse(nested(MathLimits.depth + 1))) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        // What the parser accepts, layout accepts: the two bounds agree.
        let deepest = try parse(nested(MathLimits.depth))
        XCTAssertNoThrow(try MathLayout(deepest, style: MathStyle(fontSize: 17, color: black)))
    }

    func testNodeLimitIsExactlyTwentyThousandElements() throws {
        func wide(_ elements: Int) -> String { "<math>" + String(repeating: "<mi>x</mi>", count: elements - 1) + "</math>" }
        XCTAssertEqual(try parse(wide(MathLimits.nodes)).children.count, MathLimits.nodes - 1)
        XCTAssertThrowsError(try parse(wide(MathLimits.nodes + 1))) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
        // Elements inside tokens count too.
        let glyphs = "<math><mi>" + String(repeating: "<mglyph/>", count: MathLimits.nodes) + "</mi></math>"
        XCTAssertThrowsError(try parse(glyphs)) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded) }
    }
}
