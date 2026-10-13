import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

final class ImageAttachmentTests: MathTestCase {
    private let marker = "<mglyph src=\"image\"/>"

    private func image() -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(black)
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        return context.makeImage()!
    }

    private func provider(direction: MathImageStretchDirection? = .horizontal,
                          italic: CGFloat? = 4, accent: CGFloat? = 7) -> MathImageProvider {
        let image = image()
        return .resolving { _ in MathImage(image, scale: 2, stretchDirection: direction,
                                          italicCorrection: italic, topAccentAttachment: accent) }
    }

    private func raw(_ body: String, provider: MathImageProvider? = nil, display: Bool = false) throws -> MathBox {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        engine.imageProvider = provider
        return try engine.layout(node(body).children[0], LayoutContext(fontSize: 20, unclampedSize: 20,
                                 minSize: 8, display: display, color: black), depth: 0)
    }

    private func images(_ box: MathBox, at origin: CGPoint = .zero) -> [CGRect] {
        box.items.flatMap { item -> [CGRect] in
            switch item {
            case .image(_, let rect, _): [rect.offsetBy(dx: origin.x, dy: origin.y)]
            case .box(let inner, let point): images(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y))
            default: []
            }
        }
    }

    private func placements(_ box: MathBox) -> [(MathBox, CGPoint)] {
        box.items.compactMap { if case .box(let inner, let point) = $0 { return (inner, point) }; return nil }
    }

    private func containsInk(_ box: MathBox, file: StaticString = #filePath, line: UInt = #line) {
        guard let ink = box.inkBounds else { return }
        XCTAssertGreaterThanOrEqual(ink.minX, -1e-7, file: file, line: line)
        XCTAssertLessThanOrEqual(ink.maxX, box.width + 1e-7, file: file, line: line)
        XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - 1e-7, file: file, line: line)
        XCTAssertLessThanOrEqual(ink.maxY, box.ascent + 1e-7, file: file, line: line)
    }

    func testSourceMetricUnitsAndIndependentSizing() throws {
        let unsized = try raw("<mi>\(marker)</mi>", provider: provider())
        XCTAssertEqual(unsized.width, 24)
        XCTAssertEqual(unsized.italicCorrection, 4)
        XCTAssertEqual(unsized.topAccentAttachment, 7)
        let sized = try raw("<mi><mglyph src=\"image\" width=\"30px\" height=\"9px\" valign=\"-2px\"/></mi>", provider: provider())
        XCTAssertEqual(sized.width, 36)
        XCTAssertEqual(sized.height, 9)
        XCTAssertEqual(sized.italicCorrection, 6)
        XCTAssertEqual(sized.topAccentAttachment, 10.5)
        XCTAssertEqual(images(sized).first?.minY, -2)
        containsInk(sized)
        let scriptSized = try raw("<mi scriptlevel=\"2\">\(marker)</mi>", provider: provider())
        XCTAssertEqual(scriptSized.width, 24)
        XCTAssertEqual(scriptSized.italicCorrection, 4)
        let rtlText = try raw("<mtext dir=\"rtl\">\(marker)</mtext>", provider: provider())
        XCTAssertEqual(rtlText.italicCorrection, 4)
        XCTAssertEqual(rtlText.topAccentAttachment, 7)
    }

    func testImageOnlyHorizontalLabelsAndOptOuts() throws {
        let result = try raw("<munderover><mo stretchy=\"true\">\(marker)</mo><mtext>under label</mtext><mtext>over label</mtext></munderover>", provider: provider())
        let widest = max(try raw("<mtext scriptlevel=\"1\">under label</mtext>").width,
                         try raw("<mtext scriptlevel=\"1\">over label</mtext>").width)
        let base = try XCTUnwrap(placements(result).first?.0)
        XCTAssertEqual(base.width, widest, accuracy: 1e-7)
        XCTAssertEqual(images(base).first?.width ?? 0, widest * 20 / 24, accuracy: 1e-7)
        XCTAssertEqual(base.italicCorrection, widest * 4 / 24, accuracy: 1e-7)
        XCTAssertEqual(base.topAccentAttachment ?? 0, widest * 7 / 24, accuracy: 1e-7)
        XCTAssertEqual(images(base).first?.height, 10)
        containsInk(result)
        for optOut in ["stretchy=\"false\"", ""] {
            let unchanged = try raw("<mover><mo \(optOut)>\(marker)</mo><mspace width=\"80px\"/></mover>", provider: provider())
            XCTAssertEqual(images(unchanged).first?.width, 20)
        }
    }

    func testDirectionPrecedenceTextAndMixedTokenMetrics() throws {
        let mixed = try raw("<mo stretchy=\"true\">→\(marker)</mo>", provider: provider(direction: .vertical))
        XCTAssertTrue(mixed.op?.isHorizontal == true)
        XCTAssertEqual(mixed.italicCorrection, 0)
        XCTAssertNil(mixed.topAccentAttachment)
        let explicit = try raw("<mo stretchy=\"true\" imagestretchdirection=\"vertical\">→\(marker)</mo>", provider: provider())
        XCTAssertFalse(explicit.op?.isHorizontal ?? true)
        let markup = try raw("<mover><mo stretchy=\"true\" imagestretchdirection=\"horizontal\">\(marker)</mo><mspace width=\"80px\"/></mover>", provider: provider(direction: .vertical, italic: nil, accent: nil))
        XCTAssertEqual(images(markup).first?.width, 80)
        let multiple = try raw("<mo stretchy=\"true\">\(marker)\(marker)</mo>", provider: provider())
        XCTAssertFalse(multiple.op?.isHorizontal ?? true)
        XCTAssertNil(multiple.topAccentAttachment)
        XCTAssertEqual(multiple.italicCorrection, 0)
        let fallback = try raw("<mo stretchy=\"true\"><mglyph src=\"missing\" alt=\"→\"/></mo>")
        XCTAssertFalse(fallback.op?.isHorizontal ?? true)
        XCTAssertEqual(fallback.italicCorrection, 0)
        let ignored = try raw("<mo imagestretchdirection=\"diagonal\">\(marker)</mo>", provider: provider())
        XCTAssertTrue(ignored.op?.isHorizontal == true)
    }

    func testScriptCorrectionAndPhysicalRTLCoordinates() throws {
        for dir in ["ltr", "rtl"] {
            let result = try raw("<msubsup dir=\"\(dir)\"><mi>\(marker)</mi><mspace width=\"3px\" height=\"1px\" mathbackground=\"black\"/><mspace width=\"5px\" height=\"1px\" mathbackground=\"black\"/></msubsup>", provider: provider())
            let parts = placements(result)
            XCTAssertEqual(parts.count, 3)
            guard parts.count == 3 else { return }
            if dir == "ltr" {
                XCTAssertEqual(parts[0].1.x, 0)
                XCTAssertEqual(parts[1].1.x, 20)
                XCTAssertEqual(parts[2].1.x, 24)
            } else {
                XCTAssertEqual(parts[0].1.x - parts[1].1.x - 3, 0, accuracy: 1e-7)
                XCTAssertEqual(parts[0].1.x - parts[2].1.x - 5, 0, accuracy: 1e-7)
                XCTAssertEqual(parts[0].0.topAccentAttachment, 7)
            }
            containsInk(result)
        }
    }

    func testLimitsAndAccentsUseIndependentSuppliedCoordinates() throws {
        for dir in ["ltr", "rtl"] {
            let limits = try raw("<munderover dir=\"\(dir)\"><mo largeop=\"true\">\(marker)</mo><mspace width=\"5px\" height=\"1px\" mathbackground=\"black\"/><mspace width=\"3px\" height=\"1px\" mathbackground=\"black\"/></munderover>", provider: provider())
            let parts = placements(limits)
            XCTAssertEqual(parts.count, 3)
            guard parts.count == 3 else { return }
            XCTAssertEqual(parts[1].1.x, 7.5)
            XCTAssertEqual(parts[2].1.x, 12.5)
            let accent = try raw("<mover dir=\"\(dir)\" accent=\"true\"><mi>\(marker)</mi><mi><mglyph src=\"accent\" width=\"10px\"/></mi></mover>", provider: provider())
            let rects = images(accent)
            XCTAssertEqual(rects.count, 2)
            // Base source attachment 7, accent source attachment 7 scaled by 10/20.
            XCTAssertEqual(rects[1].minX + 3.5, rects[0].minX + 7, accuracy: 1e-7)
            containsInk(accent)
        }
    }

    func testDisplayEnlargementScalesMetricsAndExplicitOptOut() throws {
        let natural = try raw("<mo largeop=\"true\">\(marker)</mo>", provider: provider())
        XCTAssertEqual(natural.width, 24)
        let enlarged = try raw("<mstyle displaystyle=\"true\"><mo largeop=\"true\">\(marker)</mo></mstyle>", provider: provider())
        let rect = try XCTUnwrap(images(enlarged).first)
        let factor = rect.width / 20
        XCTAssertGreaterThan(factor, 1)
        XCTAssertEqual(enlarged.italicCorrection, 4 * factor, accuracy: 1e-7)
        XCTAssertEqual(enlarged.topAccentAttachment ?? 0, 7 * factor, accuracy: 1e-7)
        containsInk(enlarged)
        let disabled = try raw("<mo largeop=\"false\">\(marker)</mo>", provider: provider(), display: true)
        XCTAssertEqual(disabled.width, 24)
    }

    func testVerticalStretchAndDisplayHorizontalStretchPreservePhysicalMetrics() throws {
        let vertical = try raw("<mrow dir=\"rtl\"><mo stretchy=\"true\" imagestretchdirection=\"vertical\" symmetric=\"false\">\(marker)</mo><mspace height=\"60px\" depth=\"10px\"/></mrow>", provider: provider())
        let verticalRect = try XCTUnwrap(images(vertical).first)
        XCTAssertEqual(verticalRect.height, 70, accuracy: 1e-7)
        XCTAssertEqual(verticalRect.width, 20, accuracy: 1e-7)
        let operatorBox = try XCTUnwrap(placements(vertical).first?.0)
        XCTAssertEqual(operatorBox.italicCorrection, 4)
        XCTAssertEqual(operatorBox.topAccentAttachment, 7)
        containsInk(vertical)

        let horizontal = try raw("<mover dir=\"rtl\"><mo stretchy=\"true\" largeop=\"true\">\(marker)</mo><mspace width=\"180px\"/></mover>", provider: provider(), display: true)
        let base = try XCTUnwrap(placements(horizontal).first?.0)
        let horizontalRect = try XCTUnwrap(images(base).first)
        XCTAssertEqual(base.width, 180, accuracy: 1e-7)
        XCTAssertEqual(horizontalRect.width, 150, accuracy: 1e-7)
        XCTAssertEqual(base.italicCorrection, 30, accuracy: 1e-7)
        XCTAssertEqual(base.topAccentAttachment ?? 0, 52.5, accuracy: 1e-7)
        XCTAssertGreaterThan(horizontalRect.height, 10)
        containsInk(horizontal)
    }

    func testInvalidMetricsAreIgnoredAndBoundedMetadataContainsInk() throws {
        for invalid in [CGFloat.nan, .infinity, -.infinity, -1, 21] {
            let source = MathImage(image(), scale: 2, italicCorrection: invalid, topAccentAttachment: invalid)
            XCTAssertNil(source.italicCorrection)
            XCTAssertNil(source.topAccentAttachment)
            let box = try raw("<mi>\(marker)</mi>", provider: provider(italic: invalid, accent: invalid))
            XCTAssertEqual(box.width, 20)
            XCTAssertEqual(images(box).count, 1)
        }
        let huge = try raw("<mi><mglyph src=\"image\" width=\"1000000px\"/></mi>", provider: provider(italic: 20, accent: 20))
        XCTAssertLessThanOrEqual(huge.width, MathLimits.extent)
        containsInk(huge)
        let bounded = MathImage(image(), logicalSize: CGSize(width: CGFloat.nan, height: 10), italicCorrection: 40, topAccentAttachment: 40)
        XCTAssertEqual(bounded.logicalSize.width, 40)
        XCTAssertEqual(bounded.topAccentAttachment, 40)
        let bitmap = image()
        let independent = MathImage(bitmap, scale: 2, italicCorrection: .nan, topAccentAttachment: 7)
        XCTAssertNil(independent.italicCorrection)
        XCTAssertEqual(independent.topAccentAttachment, 7)
        let tiny = MathImageProvider.resolving { _ in
            MathImage(bitmap, logicalSize: CGSize(width: 1e-320, height: 1e-320),
                      stretchDirection: .horizontal, italicCorrection: 1e-320, topAccentAttachment: 1e-320)
        }
        let stretched = try raw("<mover><mo stretchy=\"true\">\(marker)</mo><mspace width=\"80px\"/></mover>", provider: tiny)
        XCTAssertTrue(stretched.width.isFinite)
        XCTAssertTrue(stretched.height.isFinite)
        XCTAssertTrue(images(stretched).allSatisfy { $0.width.isFinite && $0.height.isFinite })
    }
}
