import CoreGraphics

struct TableCellSource {
    let node: MathMLNode
    let context: LayoutContext
    let depth: Int
}

/// Shared across every private rebuild engine in one layout pass. It deliberately owns no
/// measurements or boxes: retained fragment recipes may keep this budget without keeping a
/// measurement cache that contains those recipes.
final class TableRebuildBudget {
    var nodes = 0
    var tableWork = 0
}

/// Cached by retained child-array storage, with attributes and inherited context checked too:
/// manually constructed trees may reuse the same children in differently styled tables.
final class TableMeasurements {
    struct Measurement {
        let node: MathMLNode
        let context: LayoutContext
        let cells: TableGrid
        let labels: [TableCell?]
        let sources: [[TableCellSource]]
        let rowAxes: [CGFloat]
        let tableWork: Int
        let descendantNodes: Int
    }
    private var kept: [UInt: [Measurement]] = [:]
    let rebuildBudget: TableRebuildBudget
    var rebuildNodes: Int {
        get { rebuildBudget.nodes }
        set { rebuildBudget.nodes = newValue }
    }
    var rebuildTableWork: Int {
        get { rebuildBudget.tableWork }
        set { rebuildBudget.tableWork = newValue }
    }

    init(rebuildBudget: TableRebuildBudget = TableRebuildBudget()) {
        self.rebuildBudget = rebuildBudget
    }

    private func key(_ node: MathMLNode) -> UInt {
        node.children.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    }

    func lookup(_ node: MathMLNode, _ context: LayoutContext) -> Measurement? {
        kept[key(node)]?.first { $0.node.attributes == node.attributes && $0.context == context }
    }

    func keep(_ node: MathMLNode, _ context: LayoutContext, cells: TableGrid,
              labels: [TableCell?], sources: [[TableCellSource]], rowAxes: [CGFloat], descendantNodes: Int, tableWork: Int) {
        let measurement = Measurement(node: node, context: context, cells: cells, labels: labels, sources: sources,
                                      rowAxes: rowAxes, tableWork: tableWork, descendantNodes: descendantNodes)
        kept[key(node), default: []].append(measurement)
    }
}
