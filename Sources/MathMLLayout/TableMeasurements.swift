import CoreGraphics

struct TableCellSource {
    let node: MathMLNode
    let context: LayoutContext
    let depth: Int
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
    var rebuildNodes = 0
    var rebuildTableWork = 0

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
