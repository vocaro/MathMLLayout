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
        let cells: [[(box: MathBox, align: String?)]]
        let labels: [MathBox?]
        let sources: [[TableCellSource]]
        let descendantNodes: Int
    }
    private var kept: [UInt: [Measurement]] = [:]
    var rebuildNodes = 0

    private func key(_ node: MathMLNode) -> UInt {
        node.children.withUnsafeBufferPointer { UInt(bitPattern: $0.baseAddress) }
    }

    func lookup(_ node: MathMLNode, _ context: LayoutContext) -> Measurement? {
        kept[key(node)]?.first { $0.node.attributes == node.attributes && $0.context == context }
    }

    func keep(_ node: MathMLNode, _ context: LayoutContext, cells: [[(box: MathBox, align: String?)]],
              labels: [MathBox?], sources: [[TableCellSource]], descendantNodes: Int) {
        let measurement = Measurement(node: node, context: context, cells: cells, labels: labels, sources: sources,
                                      descendantNodes: descendantNodes)
        kept[key(node), default: []].append(measurement)
    }
}
