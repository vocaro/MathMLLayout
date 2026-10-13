import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class WorkerWrappingIntegrationTests: MathTestCase {
    private func box(_ node: MathMLNode) throws -> MathBox {
        try LayoutEngine(fontName: nil).layoutRoot(node, style: MathStyle(fontSize: 12, color: black))
    }

    func testDirectionAndLineStyleCopiesRemainIndependent() {
        var outer = LayoutContext(fontSize: 12, unclampedSize: 12, minSize: 8, display: false, color: black)
        outer.direction = .rightToLeft
        var inner = outer
        inner.direction = .leftToRight
        inner.lines.align = .right
        XCTAssertEqual(outer.direction, .rightToLeft)
        XCTAssertEqual(outer.lines.align, .auto)
        XCTAssertEqual(inner.direction, .leftToRight)
        XCTAssertEqual(inner.lines.align, .right)
    }

    func testBothPhantomDispatchPathsRetainSpacingWithoutDrawing() throws {
        let cases = [
            [MathMLNode(name: "mtext", text: "alpha beta")],
            [MathMLNode(name: "mi", text: "x"), MathMLNode(name: "mn", text: "1")],
        ]
        for children in cases {
            let visible = try box(MathMLNode(name: "mrow", children: children))
            let hidden = try box(MathMLNode(name: "mphantom", children: children))
            XCTAssertTrue(hidden.isPhantom)
            XCTAssertFalse(hidden.items.isEmpty)
            XCTAssertNil(hidden.inkBounds)
            XCTAssertEqual(hidden.spacingInkBounds, visible.spacingInkBounds)
            XCTAssertEqual([hidden.width, hidden.ascent, hidden.descent],
                           [visible.width, visible.ascent, visible.descent])
            XCTAssertEqual(hidden.itemCount, visible.itemCount)
            var parent = MathBox()
            parent.add(hidden, at: CGPoint(x: 5, y: 0))
            XCTAssertNil(parent.inkBounds)
            XCTAssertEqual(parent.spacingInkBounds, visible.spacingInkBounds?.offsetBy(dx: 5, dy: 0))
            let canvas = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            parent.draw(in: canvas, at: CGPoint(x: 4, y: 32))
            let pixels = UnsafeBufferPointer(start: canvas.data!.assumingMemoryBound(to: UInt8.self), count: 64 * 256)
            XCTAssertTrue(pixels.allSatisfy { $0 == 0 })
        }
    }

    func testSingleChildDefaultPaddingRetainsLogicalWords() throws {
        let words = MathMLNode(name: "mtext", text: "alpha beta gamma")
        let transparent = try box(MathMLNode(name: "mpadded", children: [words]))
        XCTAssertNotNil(transparent.row)
        XCTAssertEqual(Paragraph(transparent, fontSize: 12).units.count, 3)
        let explicit = try box(MathMLNode(name: "mpadded", attributes: ["width": "+1px"], children: [words]))
        XCTAssertNil(explicit.row)
        XCTAssertEqual(Paragraph(explicit, fontSize: 12).units.count, 1)
    }

    func testPhantomBackgroundKeepsOpaqueAnchorMetadata() throws {
        let children = [MathMLNode(name: "mi", attributes: ["id": "left"], text: "x"),
                        MathMLNode(name: "mi", attributes: ["id": "right"], text: "y")]
        // Two original items and two rebuilt items used to collide, making the background
        // falsely flattenable. A dedicated opaque row keeps the child anchors and stays atomic.
        let decorated = try box(MathMLNode(name: "mphantom", attributes: ["mathbackground": "red"], children: children))
        let row = try XCTUnwrap(decorated.row)
        XCTAssertEqual(row.itemCount, -1)
        XCTAssertEqual(row.children.map(\.id), ["left", "right"])
        XCTAssertEqual(Paragraph(decorated, fontSize: 12).units.count, 1)
        XCTAssertFalse(decorated.isPhantom)
        XCTAssertNotNil(decorated.inkBounds)
    }
}
