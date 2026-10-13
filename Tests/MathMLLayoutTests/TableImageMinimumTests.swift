import CoreGraphics
@testable import MathMLLayout
import XCTest

final class TableImageMinimumTests: XCTestCase {
    func testHorizontalImageMinimumProducesAFeasibleReportedTableMinimum() throws {
        let canvas = try XCTUnwrap(CGContext(data: nil, width: 20, height: 8, bitsPerComponent: 8,
                                          bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        canvas.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 20, height: 8))
        let image = try XCTUnwrap(canvas.makeImage())
        let provider = MathImageProvider.resolving { _ in
            MathImage(image, logicalSize: CGSize(width: 20, height: 8), stretchDirection: .horizontal)
        }
        let style = MathStyle(fontSize: 20, color: black, imageProvider: provider)
        let operatorCell = "<mtd><mo stretchy='true' minsize='100px' lspace='0px' rspace='0px'><mglyph src='bar'/></mo></mtd>"
        for direction in ["ltr", "rtl"] {
            for authored in [false, true] {
                let sizing = authored ? "width='160px' columnwidth='80px 80px'" : ""
                let extraCell = authored ? "<mtd><mspace width='10px'/></mtd>" : ""
                let body = "<mtable dir='\(direction)' \(sizing) columnspacing='0px'><mtr>" + operatorCell + extraCell + "</mtr></mtable>"
                let root = try mathML(body)
                let minimum: CGFloat = authored ? 180 : 100
                let narrow = try MathLayout(root, style: style, maximumWidth: 0)
                XCTAssertEqual(narrow.width, minimum, accuracy: 0.001)
                XCTAssertEqual(narrow.widestUnbreakableWidth, minimum, accuracy: 0.001)
                let retry = try MathLayout(root, style: style, maximumWidth: narrow.widestUnbreakableWidth)
                XCTAssertLessThanOrEqual(retry.width, narrow.widestUnbreakableWidth + 0.001)
                XCTAssertEqual(try XCTUnwrap(Rendering(retry).bounds(.red)).width, 100, accuracy: 0.5)
                assertBoxCoversInk(narrow, body)
                assertBoxCoversInk(retry, body)
            }
        }
    }
}
