import CoreGraphics
@testable import MathMLLayout
import XCTest

/// Intersections between independently implemented image, table, and anchor features.
final class LayoutEnhancementIntegrationTests: MathTestCase {
    private func imageProvider() -> MathImageProvider {
        let canvas = CGContext(data: nil, width: 20, height: 8, bitsPerComponent: 8,
                               bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 20, height: 8))
        let image = canvas.makeImage()!
        return .resolving { _ in
            MathImage(image, logicalSize: CGSize(width: 20, height: 8),
                      stretchDirection: .horizontal, italicCorrection: 3, topAccentAttachment: 6)
        }
    }

    func testImageOnlyOperatorStretchesInAnAuthoredTableTrackBesideRTLWrapping() throws {
        let body = """
        <mtable width="160px" columnwidth="80px 80px" columnspacing="0px" rowspacing="0px">
          <mtr>
            <mtd><mo stretchy="true" lspace="0px" rspace="0px"><mglyph src="bar"/></mo></mtd>
            <mtd><mtext dir="rtl">שלום עולם שלום עולם</mtext></mtd>
          </mtr>
        </mtable>
        """
        let root = try node(body)
        let style = MathStyle(fontSize: 20, color: black, imageProvider: imageProvider())
        let result = try MathLayout(root, style: style, maximumWidth: 160)
        XCTAssertEqual(result.width, 160, accuracy: 0.001)
        // The complete 23-point advance includes three points of deliberate script
        // clearance; scaling that advance to 80 leaves this independently known ink width.
        XCTAssertEqual(try XCTUnwrap(Rendering(result).bounds(.red)).width, 80 * 20 / 23, accuracy: 0.5)
        XCTAssertEqual(result.rows.count, 1)
        assertBoxCoversInk(result, body)
        let repeated = try MathLayout(root, style: style, maximumWidth: 160)
        XCTAssertEqual(Rendering(repeated).pixels, Rendering(result).pixels)
        let narrow = try MathLayout(root, style: style, maximumWidth: 0)
        let retry = try MathLayout(root, style: style, maximumWidth: narrow.widestUnbreakableWidth)
        XCTAssertLessThanOrEqual(retry.width, narrow.widestUnbreakableWidth + 0.001)
    }

    func testScriptArgumentAnchorKeepsItsFinalCoordinateThroughBackgroundAndNegativePadding() throws {
        let body = """
        <msup>
          <mspace width="20px" height="5px"/>
          <mpadded width="+4px" lspace="-2px">
            <mrow mathbackground="blue">
              <mspace width="3px"/>
              <mspace id="target" width="7px" height="4px" mathbackground="red"/>
            </mrow>
          </mpadded>
        </msup>
        <mspace linebreak="newline" indentalign="id" indenttarget="target" indentshift="0px"/>
        <mspace width="5px" height="4px" mathbackground="lime"/>
        """
        let result = try MathLayout(node(body), style: MathStyle(fontSize: 20, color: black), maximumWidth: 100)
        XCTAssertEqual(result.rows.count, 2)
        let rendered = Rendering(result)
        let target = try XCTUnwrap(rendered.bounds(.red))
        let continuation = try XCTUnwrap(rendered.bounds(.green))
        XCTAssertEqual(continuation.minX, target.minX, accuracy: 0.25)
        XCTAssertEqual(result.rows[1].origin.x, target.minX, accuracy: 0.25)
        assertBoxCoversInk(result, body, rendering: rendered)

        // An automatic candidate must resolve to the same final coordinate as the forced
        // break. Choose a budget strictly between the first structure and the full row.
        let automatic = body.replacingOccurrences(of: "linebreak=\"newline\"", with: "linebreak=\"goodbreak\"")
        let natural = try MathLayout(node(automatic), style: MathStyle(fontSize: 20, color: black))
        let fitted = try MathLayout(node(automatic), style: MathStyle(fontSize: 20, color: black),
                                    maximumWidth: natural.width - 2)
        XCTAssertEqual(fitted.rows.count, 2)
        XCTAssertEqual(fitted.rows[1].origin.x, result.rows[1].origin.x, accuracy: 0.001)
        assertBoxCoversInk(fitted, automatic)
    }
}
