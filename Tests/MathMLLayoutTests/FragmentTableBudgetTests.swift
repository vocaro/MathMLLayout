import CoreGraphics
@testable import MathMLLayout
import XCTest

final class FragmentTableBudgetTests: XCTestCase {
    private var context: LayoutContext {
        LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
    }

    func testIndependentFragmentEnginesShareTableWorkWithoutSharingMeasurements() throws {
        let table = try XCTUnwrap(mathML("<mtable><mtr><mtd columnspan='2'><mi>x</mi></mtd></mtr></mtable>").children.first)
        let source = LayoutEngine(fontName: nil)
        _ = try source.layout(table, context, depth: 0)
        let first = source.fragmentRebuildEngine(), second = source.fragmentRebuildEngine()
        XCTAssertFalse(first.tableMeasurements === source.tableMeasurements)
        XCTAssertFalse(second.tableMeasurements === first.tableMeasurements)
        XCTAssertTrue(first.tableMeasurements.rebuildBudget === source.tableMeasurements.rebuildBudget)
        XCTAssertTrue(second.tableMeasurements.rebuildBudget === first.tableMeasurements.rebuildBudget)
        XCTAssertNil(first.tableMeasurements.lookup(table, context))
        source.tableMeasurements.rebuildTableWork = MathLimits.tableWork - 3
        _ = try first.layout(table, context, depth: 0)
        XCTAssertEqual(source.tableMeasurements.rebuildTableWork, MathLimits.tableWork - 1)
        XCTAssertEqual(second.remainingTableWork, 1)
        // This second recipe cannot obtain a fresh 200,000-visit allowance.
        XCTAssertThrowsError(try second.layout(table, context, depth: 0)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
        XCTAssertEqual(first.fragmentRebuildEngine().remainingTableWork, 1)
    }

    func testFragmentAndCellRebuildsShareTheSameNodeAllowance() throws {
        let source = LayoutEngine(fontName: nil)
        let first = source.fragmentRebuildEngine(), second = source.fragmentRebuildEngine()
        source.tableMeasurements.rebuildNodes = LayoutEngine.maximumCellRebuildNodes - 2
        _ = try first.layout(mi("x"), context, depth: 0)
        XCTAssertEqual(source.tableMeasurements.rebuildNodes, LayoutEngine.maximumCellRebuildNodes - 1)
        _ = try source.relayoutCell(TableCellSource(node: mi("y"), context: context, depth: 0), width: 100)
        XCTAssertEqual(source.tableMeasurements.rebuildNodes, LayoutEngine.maximumCellRebuildNodes)
        XCTAssertThrowsError(try second.layout(mi("z"), context, depth: 0)) {
            XCTAssertEqual($0 as? MathLayoutError, .limitExceeded)
        }
    }

    func testRetainedTableWrapperRecipeKeepsOnlyTheBudgetAndReleasesItsSourceCache() throws {
        var recipe: RowFragment?
        weak var sourceEngine: LayoutEngine?
        weak var sourceCache: TableMeasurements?
        weak var sharedBudget: TableRebuildBudget?
        do {
            let engine = LayoutEngine(fontName: nil)
            sourceEngine = engine
            sourceCache = engine.tableMeasurements
            sharedBudget = engine.tableMeasurements.rebuildBudget
            let table = try XCTUnwrap(mathML("<mtable><mtr><mtd><mpadded width='+2px'><mtext>alpha beta</mtext></mpadded></mtd></mtr></mtable>").children.first)
            let box = try engine.layout(table, context, depth: 0)
            let measurement = try XCTUnwrap(engine.tableMeasurements.lookup(table, context))
            var pending = [box] + measurement.cells.rows.flatMap { $0.map(\.box) }
            while let child = pending.popLast() {
                if let fragment = child.row?.fragment { recipe = fragment; break }
                pending += child.row?.children.map(\.box) ?? []
                for item in child.items {
                    if case .box(let descendant, _) = item { pending.append(descendant) }
                }
            }
            XCTAssertNotNil(recipe)
        }
        XCTAssertNil(sourceEngine)
        XCTAssertNil(sourceCache, "the shared budget must not retain measured recipe boxes")
        XCTAssertNotNil(sharedBudget)
        let rebuilt = try XCTUnwrap(recipe).rebuild(MathBox(width: 10, ascent: 5, descent: 2))
        XCTAssertEqual(rebuilt.width, 12, accuracy: 0.001)
        recipe = nil
        XCTAssertNil(sharedBudget, "dropping the last recipe must release its private engine and budget")
    }

    func testRetainedFenceRebuildUsesTheSharedTableAllowance() throws {
        let source = LayoutEngine(fontName: nil)
        let table = try XCTUnwrap(mathML("<mtable><mtr><mtd columnspan='2'><mi>x</mi></mtd></mtr></mtable>").children.first)
        let fence = FenceLayout(node: table, context: context, form: nil, engine: source,
                                lineWidth: .infinity, wrapWidth: .infinity, wrapParts: 0..<0,
                                wrapOverrides: [:], isCoreGeometry: true)
        source.tableMeasurements.rebuildTableWork = MathLimits.tableWork - 3
        XCTAssertNotNil(fence.box(ascent: 30, descent: 10))
        XCTAssertEqual(source.tableMeasurements.rebuildTableWork, MathLimits.tableWork - 1)
        XCTAssertNil(fence.box(ascent: 30, descent: 10))
    }
}
