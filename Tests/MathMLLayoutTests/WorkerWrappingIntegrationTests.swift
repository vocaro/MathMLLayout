import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

final class WorkerWrappingIntegrationTests: MathTestCase {
    private func box(_ node: MathMLNode) throws -> MathBox {
        try LayoutEngine(fontName: nil).layoutRoot(node, style: MathStyle(fontSize: 12, color: black))
    }

    func testRetainedTableFenceDoesNotRetainItsLayoutEngine() throws {
        let table = try node("<mtable><mtr><mtd><mrow><mo fence='true' stretchy='true'>(</mo>"
            + "<mfrac><mi>x</mi><mi>y</mi></mfrac><mo fence='true' stretchy='true'>)</mo>"
            + "</mrow></mtd></mtr></mtable>").children[0]
        let style = MathStyle(fontSize: 20, color: black)
        var engine: LayoutEngine? = LayoutEngine(fontName: "STIXTwoMath-Regular")
        weak var weakEngine = engine
        let retained = try engine!.layoutRoot(table, style: style)
        XCTAssertNotNil(engine!.tableMeasurements.lookup(table, engine!.rootContext(table, style: style)))
        func fence(in box: MathBox) -> FenceLayout? {
            var pending = [box]
            while let next = pending.popLast() {
                if let fence = next.fenceLayout { return fence }
                for item in next.items {
                    if case .box(let child, _) = item { pending.append(child) }
                }
            }
            return nil
        }
        let saved = try XCTUnwrap(fence(in: retained))
        XCTAssertTrue(saved.textWork === engine!.textWork)
        let before = try XCTUnwrap(saved.box(ascent: 30, descent: 10))
        engine = nil
        withExtendedLifetime(retained) { XCTAssertNil(weakEngine) }
        let after = try XCTUnwrap(saved.box(ascent: 30, descent: 10))
        XCTAssertEqual([after.width, after.ascent, after.descent], [before.width, before.ascent, before.descent])
        XCTAssertEqual(after.inkBounds, before.inkBounds)
        XCTAssertEqual(after.itemCount, before.itemCount)
        let paragraph = Paragraph(after, fontSize: 20)
        XCTAssertNil(after.logicalTextSlice)
        XCTAssertFalse(paragraph.textWorkExceeded)
        XCTAssertTrue(saved.textWork.consume(TextShapingWork.limit - saved.textWork.spent))
        XCTAssertFalse(saved.textWork.consume(1))
        XCTAssertTrue(paragraph.textWorkExceeded, "fence-only rows must report their retained pass budget")
    }

    func testRetainedFenceSeesLaterImageCacheEntriesAndKeepsItsProvider() throws {
        let canvas = CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8, bytesPerRow: 96,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let image = MathImage(canvas.makeImage()!, logicalSize: CGSize(width: 37, height: 11))
        let calls = FenceImageCalls()
        let provider = MathImageProvider.resolving { source in
            calls.add(source)
            return source == "hit" ? image : nil
        }
        var engine: LayoutEngine? = LayoutEngine(fontName: nil)
        weak var weakEngine = engine
        engine!.imageProvider = provider
        let context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 8, display: false, color: black)
        let content = MathMLNode(name: "mtext", children: [
            MathMLNode(name: "mglyph", attributes: ["src": "hit", "alt": "image"]),
            MathMLNode(name: "mglyph", attributes: ["src": "missing", "alt": "fallback"]),
        ])
        // Both entries are resolved after the retained fence is created, including a cached miss.
        let saved = FenceLayout(node: content, context: context, form: nil, engine: engine!,
                                lineWidth: .infinity, wrapWidth: .infinity, wrapParts: 0..<0,
                                wrapOverrides: [:], isCoreGeometry: true)
        _ = try engine!.layout(content, context, depth: 0)
        XCTAssertEqual(calls.values, ["hit", "missing"])
        let cached = try XCTUnwrap(engine!.imageCache["hit"] ?? nil)
        XCTAssertEqual(cached.logicalSize, image.logicalSize)
        let before = try XCTUnwrap(saved.box(ascent: 30, descent: 10))
        XCTAssertEqual(calls.values, ["hit", "missing"])
        let replacementCalls = FenceImageCalls()
        engine!.imageProvider = .resolving { source in replacementCalls.add(source); return nil }
        _ = try engine!.layout(content, context, depth: 0)
        XCTAssertEqual(replacementCalls.values, ["hit", "missing"])
        engine = nil
        XCTAssertNil(weakEngine)
        let after = try XCTUnwrap(saved.box(ascent: 30, descent: 10))
        XCTAssertEqual(calls.values, ["hit", "missing"])
        XCTAssertEqual(replacementCalls.values, ["hit", "missing"])
        XCTAssertEqual([after.width, after.ascent, after.descent], [before.width, before.ascent, before.descent])
        XCTAssertEqual(after.inkBounds, before.inkBounds)
        XCTAssertEqual(after.itemCount, before.itemCount)
    }

    func testCopiedBoxMetadataAndNestedArrayMutationsRemainIndependent() throws {
        // Non-ASCII keeps this test on the contextual-text metadata path.
        var original = try box(MathMLNode(name: "mtext", text: "alpha βeta"))
        let source = try XCTUnwrap(original.textSlice?.source)
        original.row = try box(MathMLNode(name: "mrow", children: [MathMLNode(name: "mtext", text: "alpha βeta")])).row
        original.tableMinimumWidth = 37
        original.topAccentAttachment = 4
        original.op = try box(MathMLNode(name: "mo", text: "+")).op
        let space = TextSegment(box: MathBox(width: 3), x: 0, isSpace: true)
        original.textSegments = [space]
        original.leadingTextSpace = [space]
        original.alignment = [AlignmentEvent(kind: .mark, x: 5, path: [0])]
        let target = AlignmentTarget(work: source.work)
        original.alignmentTargets = [target]
        let expectedInk = original.inkBounds
        let expectedItems = original.itemCount
        let expectedSpace = original.op?.lspace
        var copy = original
        copy.row = nil
        copy.textSlice = nil
        copy.tableMinimumWidth = 2
        copy.topAccentAttachment = 9
        copy.op?.lspace = 99
        copy.textSegments?[0].x = 8
        copy.leadingTextSpace?.removeAll()
        copy.alignmentTargets.removeAll()
        copy.alignment[0].x = 42
        copy.alignment[0].path.append(1)
        copy.isPhantom = true
        copy.items.removeAll()
        XCTAssertNotNil(original.row)
        XCTAssertTrue(original.textSlice?.source === source)
        XCTAssertEqual(original.tableMinimumWidth, 37)
        XCTAssertEqual(original.topAccentAttachment, 4)
        XCTAssertEqual(original.op?.lspace, expectedSpace)
        XCTAssertEqual(original.textSegments?[0].x, 0)
        XCTAssertEqual(original.leadingTextSpace?.count, 1)
        XCTAssertTrue(original.alignmentTargets.first === target)
        XCTAssertTrue(copy.alignmentTargets.isEmpty)
        XCTAssertEqual(original.alignment[0].x, 5)
        XCTAssertEqual(original.alignment[0].path, [0])
        XCTAssertFalse(original.isPhantom)
        XCTAssertEqual(original.inkBounds, expectedInk)
        XCTAssertEqual(original.itemCount, expectedItems)
        XCTAssertNil(copy.row)
        XCTAssertEqual(copy.op?.lspace, 99)
        XCTAssertEqual(copy.textSegments?[0].x, 8)
        XCTAssertEqual(copy.alignment[0].path, [0, 1])
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

    func testTableContextsCompareValuesAndCopyIndependently() {
        func context() -> LayoutContext {
            LayoutContext(fontSize: 12, unclampedSize: 12, minSize: 8, display: false, color: black)
        }
        let original = context()
        XCTAssertEqual(original, context()) // Independently allocated storage remains a cache hit.
        let mutations: [(inout LayoutContext) -> Void] = [
            { $0.tableRowAlign = "top" }, { $0.tableGroupAlign = "decimalpoint" },
            { $0.trackAlignment = true }, { $0.alignmentRTL = true },
            { $0.alignmentBaseline = false }, { $0.direction = .rightToLeft },
            { $0.lines.align = .right },
        ]
        for mutate in mutations {
            var changed = original
            mutate(&changed)
            XCTAssertNotEqual(changed, original)
            XCTAssertEqual(original, context())
        }
        var inherited = original
        inherited.tableRowAlign = "center"
        inherited.tableGroupAlign = "right"
        inherited.trackAlignment = true
        inherited.alignmentRTL = true
        inherited.alignmentBaseline = false
        var child = inherited
        child.tableRowAlign = "bottom"
        child.tableGroupAlign = "left"
        child.trackAlignment = false
        child.alignmentRTL = false
        child.alignmentBaseline = true
        XCTAssertEqual(inherited.tableRowAlign, "center")
        XCTAssertEqual(inherited.tableGroupAlign, "right")
        XCTAssertTrue(inherited.trackAlignment)
        XCTAssertTrue(inherited.alignmentRTL)
        XCTAssertFalse(inherited.alignmentBaseline)
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

private final class FenceImageCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var values: [String] { lock.withLock { recorded } }
    func add(_ value: String) { lock.withLock { recorded.append(value) } }
}
