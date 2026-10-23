import CoreGraphics
import CoreText
@testable import MathMLLayout
import XCTest

final class VerticalArrowRegressionTests: XCTestCase {
    private let missingSTIX = "↥↧⇅⇈⇊↾↿⇂⇃"
    private var context: LayoutContext {
        LayoutContext(fontSize: em, unclampedSize: em, minSize: 12, display: false, color: black)
    }

    private func stretched(_ scalar: Unicode.Scalar, engine: LayoutEngine, attributes: [String: String] = [:],
                           ascent: CGFloat = 60, descent: CGFloat = 40, symmetric: Bool = false) throws -> (natural: MathBox, stretched: MathBox) {
        let node = mo(String(scalar), attributes)
        let natural = try engine.layout(mo(String(scalar)), context, depth: 0)
        let result = try XCTUnwrap(engine.stretchVertically(node, glyph: engine.font.glyph(for: scalar), scalar: scalar,
                                                          natural: natural, ascent: ascent, descent: descent,
                                                          symmetric: symmetric, context), "\(scalar)")
        return (natural, result)
    }

    private func paths(_ box: MathBox) -> [CGPath] {
        box.items.flatMap { item -> [CGPath] in
            switch item {
            case .path(let path, _, _, _): return [path]
            case .box(let child, _): return paths(child)
            default: return []
            }
        }
    }

    private func lines(_ path: CGPath) -> [(CGPoint, CGPoint)] {
        var previous = CGPoint.zero
        var result: [(CGPoint, CGPoint)] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .addLineToPoint { result.append((previous, element.points[0])) }
            if element.type == .moveToPoint || element.type == .addLineToPoint { previous = element.points[0] }
        }
        return result
    }

    func testMissingSTIXConstructionsDrawAtTheRequestedHeightAndNaturalAdvance() throws {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        XCTAssertNotNil(engine.font.table)
        for scalar in missingSTIX.unicodeScalars {
            let glyph = try XCTUnwrap(engine.font.glyph(for: scalar))
            XCTAssertNil(engine.font.table?.construction(glyph, vertical: true), "\(scalar)")
            let (natural, box) = try stretched(scalar, engine: engine)
            let ink = try XCTUnwrap(box.inkBounds)
            XCTAssertEqual(paths(box).count, 1, "\(scalar)")
            XCTAssertEqual(box.width, natural.width, accuracy: 0.001, "\(scalar) advance")
            XCTAssertEqual(ink.midX, try XCTUnwrap(natural.inkBounds).midX, accuracy: 0.001, "\(scalar) ink alignment")
            XCTAssertEqual(ink.height, 90.1, accuracy: 0.001, "\(scalar) covers the 100pt strut with delimiter shortfall")
            XCTAssertEqual(ink.midY, 10, accuracy: 0.001, "\(scalar) asymmetric center")
            XCTAssertEqual(box.ascent, ink.maxY, accuracy: 0.001)
            XCTAssertEqual(box.descent, -ink.minY, accuracy: 0.001)
            let layout = try typeset("<mo mathcolor='blue'>\(scalar)</mo><mspace width='1em' height='3em' depth='2em'/>",
                                     font: "STIXTwoMath-Regular")
            let rendered = Rendering(layout)
            XCTAssertEqual(try XCTUnwrap(rendered.bounds(.blue)).height, ink.height, accuracy: 0.6, "\(scalar) drawn height")
            assertBoxCoversInk(layout, "\(scalar) with STIX", rendering: rendered)
        }
    }

    func testEveryDictionaryVerticalArrowStretchesWithANoMATHFont() throws {
        let engine = LayoutEngine(fontName: "Helvetica")
        XCTAssertNil(engine.font.table)
        for scalar in OperatorDictionary.verticalArrows.unicodeScalars {
            XCTAssertTrue(OperatorDictionary.entry(String(scalar), form: .infix).flags.contains(.stretchy))
            XCTAssertFalse(OperatorDictionary.isHorizontal(String(scalar)))
            let (natural, box) = try stretched(scalar, engine: engine)
            XCTAssertEqual(paths(box).count, 1, "\(scalar)")
            XCTAssertEqual(box.width, natural.width, accuracy: 0.001, "\(scalar)")
            XCTAssertEqual(try XCTUnwrap(box.inkBounds).height, 90.1, accuracy: 0.001, "\(scalar)")
            let body = "<mo mathcolor='red'>\(scalar)</mo><mspace width='1em' height='3em' depth='2em'/>"
            let layout = try typeset(body, font: "Helvetica")
            let rendered = Rendering(layout)
            let ink = try XCTUnwrap(rendered.bounds(.red), "\(scalar) renders")
            XCTAssertEqual(ink.height, 90.1, accuracy: 0.6, "\(scalar)")
            XCTAssertEqual(ink.midY, 10, accuracy: 0.4, "\(scalar)")
            XCTAssertNil(rendered.bounds(.black), "\(scalar) uses its mathcolor")
            assertBoxCoversInk(layout, "\(scalar) with Helvetica", rendering: rendered)
        }
    }

    func testAvailableMATHConstructionsRemainGlyphs() throws {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        for scalar in "↑↓↕⇑⇓⇕".unicodeScalars {
            let glyph = try XCTUnwrap(engine.font.glyph(for: scalar))
            XCTAssertNotNil(engine.font.table?.construction(glyph, vertical: true), "\(scalar)")
            let (_, box) = try stretched(scalar, engine: engine)
            XCTAssertTrue(paths(box).isEmpty, "\(scalar) uses its font construction")
            XCTAssertGreaterThan(try XCTUnwrap(box.inkBounds).height, 80, "\(scalar)")
        }
    }

    func testFallbackRespectsSizeBoundsAndAxisCentering() throws {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        let axis = engine.value(\.axisHeight, context)
        for scalar in missingSTIX.unicodeScalars {
            let (_, capped) = try stretched(scalar, engine: engine, attributes: ["maxsize": "2em"])
            XCTAssertEqual(try XCTUnwrap(capped.inkBounds).height, 40, accuracy: 0.001, "\(scalar) maximum")
            let (natural, relative) = try stretched(scalar, engine: engine, attributes: ["maxsize": "200%"])
            XCTAssertEqual(relative.height, natural.height * 2, accuracy: 0.001, "\(scalar) relative maximum")
            let (_, minimum) = try stretched(scalar, engine: engine, attributes: ["minsize": "8em", "maxsize": "2em"])
            XCTAssertEqual(minimum.height, 160, accuracy: 0.001, "\(scalar) minimum wins")
            let (_, lone) = try stretched(scalar, engine: engine, attributes: ["minsize": "4em"], ascent: 0, descent: 0)
            XCTAssertEqual(lone.height, 80, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(lone.inkBounds).midY, axis, accuracy: 0.001, "\(scalar) lone minimum is centered on the axis")
            let (_, symmetric) = try stretched(scalar, engine: engine, ascent: 60, descent: 0, symmetric: true)
            let extent = 2 * max(60 - axis, axis)
            XCTAssertEqual(symmetric.height, max(extent * 0.901, extent - em / 2), accuracy: 0.001, "\(scalar) symmetric height")
            XCTAssertEqual(try XCTUnwrap(symmetric.inkBounds).midY, axis, accuracy: 0.001, "\(scalar) symmetric center")
            XCTAssertNil(engine.stretchVertically(mo(String(scalar), ["maxsize": "1"]), glyph: engine.font.glyph(for: scalar),
                                                 scalar: scalar, natural: natural, ascent: 60, descent: 40, symmetric: false, context))
        }
    }

    func testHarpoonsHaveTheCorrectBarbAndOffCenterShaft() throws {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        for (scalar, up, right) in [("↾", true, true), ("↿", true, false), ("⇂", false, true), ("⇃", false, false)]
            as [(Unicode.Scalar, Bool, Bool)] {
            let (natural, box) = try stretched(scalar, engine: engine)
            let segments = lines(try XCTUnwrap(paths(box).first))
            let shaft = try XCTUnwrap(segments.first { abs($0.1.y - $0.0.y) > 80 })
            let barb = try XCTUnwrap(segments.first { abs($0.1.x - $0.0.x) > 1 })
            let shaftX = shaft.0.x, middle = try XCTUnwrap(natural.inkBounds).midX
            XCTAssertGreaterThan((middle - shaftX) * (right ? 1 : -1), 1, "\(scalar) shaft lies opposite its barb")
            let barbX = abs(barb.0.x - shaftX) > abs(barb.1.x - shaftX) ? barb.0.x : barb.1.x
            XCTAssertGreaterThan((barbX - shaftX) * (right ? 1 : -1), 1, "\(scalar) barb points the correct way")
            let headY = up ? max(shaft.0.y, shaft.1.y) : min(shaft.0.y, shaft.1.y)
            XCTAssertEqual(up ? max(barb.0.y, barb.1.y) : min(barb.0.y, barb.1.y), headY, accuracy: 0.001, "\(scalar) barb at its pointed end")
        }
    }

    func testPairedArrowHeadsPointTheCorrectWays() throws {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        for (scalar, upHeads, downHeads) in [("⇅", 2, 2), ("⇈", 4, 0), ("⇊", 0, 4)] as [(Unicode.Scalar, Int, Int)] {
            let (_, box) = try stretched(scalar, engine: engine)
            let segments = lines(try XCTUnwrap(paths(box).first))
            let shafts = segments.filter { abs($0.1.y - $0.0.y) > 80 }
            XCTAssertEqual(shafts.count, 2, "\(scalar)")
            XCTAssertNotEqual(shafts.first?.0.x, shafts.last?.0.x, "\(scalar) distinct shafts")
            let heads = segments.filter { abs($0.1.y - $0.0.y) > 1 && abs($0.1.x - $0.0.x) > 1 }
            let bounds = try XCTUnwrap(paths(box).first).boundingBoxOfPath
            XCTAssertEqual(heads.filter { max($0.0.y, $0.1.y) == bounds.maxY }.count, upHeads, "\(scalar) upward heads")
            XCTAssertEqual(heads.filter { min($0.0.y, $0.1.y) == bounds.minY }.count, downHeads, "\(scalar) downward heads")
            if scalar == "⇅" {
                let leftX = try XCTUnwrap(shafts.map { $0.0.x }.min())
                XCTAssertTrue(heads.contains { ($0.0.x == leftX && $0.0.y == bounds.maxY) || ($0.1.x == leftX && $0.1.y == bounds.maxY) },
                              "the upward arrow is left of the downward arrow")
            }
        }
    }

    func testBarredArrowsKeepAHeadAndABarAtOppositeEnds() throws {
        let engine = LayoutEngine(fontName: "STIXTwoMath-Regular")
        for (scalar, up) in [("↥", true), ("↧", false)] as [(Unicode.Scalar, Bool)] {
            let (_, box) = try stretched(scalar, engine: engine)
            let segments = lines(try XCTUnwrap(paths(box).first))
            let bar = try XCTUnwrap(segments.first { abs($0.0.y - $0.1.y) < 0.001 && abs($0.0.x - $0.1.x) > 1 })
            let bounds = try XCTUnwrap(paths(box).first).boundingBoxOfPath
            XCTAssertEqual(bar.0.y, up ? bounds.minY : bounds.maxY, accuracy: 0.001, "\(scalar) bar at the tail")
            let arms = segments.filter { abs($0.0.y - $0.1.y) > 1 && abs($0.0.x - $0.1.x) > 1 }
            XCTAssertEqual(arms.count, 2, "\(scalar) whole head")
            for arm in arms {
                XCTAssertEqual(up ? max(arm.0.y, arm.1.y) : min(arm.0.y, arm.1.y), up ? bounds.maxY : bounds.minY,
                               accuracy: 0.001, "\(scalar) head opposite the bar")
            }
        }
    }

    func testStretchyFalseAndNaturalRowsKeepTheFontGlyph() throws {
        for scalar in missingSTIX.unicodeScalars {
            let natural = try innerBox("<mo>\(scalar)</mo>")
            let disabled = try innerBox("<mo stretchy='false'>\(scalar)</mo><mspace height='3em' depth='2em'/>")
            XCTAssertTrue(paths(natural).isEmpty)
            XCTAssertTrue(paths(disabled).isEmpty)
            XCTAssertEqual(try XCTUnwrap(disabled.inkBounds).height, try XCTUnwrap(natural.inkBounds).height, accuracy: 0.001, "\(scalar)")
        }
    }

    func testSubPointSizeBoundsStillContainTheWholeArrow() throws {
        // The usual 0.5pt stroke floor exceeds these requested heights. Both the ink and the
        // advertised box must obey the limits; otherwise a host clips the stretched operator.
        for size: CGFloat in [0.1, 0.2] {
            for scalar in OperatorDictionary.verticalArrows.unicodeScalars {
                for (attributes, expectedHeight) in [("minsize='4em'", size * 4),
                                                      ("minsize='4em' maxsize='2em'", size * 4),
                                                      ("maxsize='2em'", size * 2)] {
                    let body = "<mstyle mathsize='\(size)px'><mo \(attributes)>\(scalar)</mo></mstyle>"
                    let sized = attributes.hasPrefix("maxsize")
                        ? "<mstyle mathsize='\(size)px'><mo \(attributes)>\(scalar)</mo><mspace height='3em' depth='2em'/></mstyle>"
                        : body
                    let box = try innerBox(sized, font: "Helvetica")
                    let ink = try XCTUnwrap(box.inkBounds, "\(scalar) at \(size)")
                    XCTAssertEqual(ink.height, expectedHeight, accuracy: 0.000001, "\(scalar) \(attributes) at \(size)")
                    XCTAssertLessThanOrEqual(ink.maxY, box.ascent + 0.000001, "\(scalar) top stays inside the box")
                    XCTAssertGreaterThanOrEqual(ink.minY, -box.descent - 0.000001, "\(scalar) bottom stays inside the box")
                    let path = try XCTUnwrap(paths(box).first)
                    let shafts = lines(path).filter { abs($0.0.x - $0.1.x) < 0.000001 && abs($0.0.y - $0.1.y) > 0.000001 }
                    XCTAssertFalse(shafts.isEmpty, "\(scalar) retains a vertical shaft")
                }
            }
        }
    }
}
