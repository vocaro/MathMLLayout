import CoreGraphics

extension LayoutEngine {
    /// MathML 3, 3.2.5.8: a cell consisting of an embellished operator stretches against
    /// its row or column. A spanning neighbor contributes only when its complete span is
    /// contained in the operator's span. Measure all targets before rebuilding any cell.
    func stretchTableCells(_ cells: inout TableGrid, sources: [[TableCellSource]],
                           rowGaps: [CGFloat], columnGaps: [CGFloat], widths: [CGFloat],
                           allocatedWidths: [CGFloat] = []) throws {
        struct OperatorCell {
            let core: MathMLNode
            let path: [Int]
            let horizontal: Bool
        }
        let measured = cells.rows
        var operators = measured.map { [OperatorCell?](repeating: nil, count: $0.count) }
        for row in measured.indices {
            for index in measured[row].indices {
                let source = sources[row][index]
                guard let (core, path) = tableOperatorCore(source.node),
                      operatorFlags(core, form: nil).contains(.stretchy),
                      !Self.hasGlyph(core) || core.attributes.flag("stretchy") == true else { continue }
                operators[row][index] = OperatorCell(core: core, path: path,
                    horizontal: properties(core, form: nil, source.context).isHorizontal)
            }
        }
        var natural = measured.map { [MathBox?](repeating: nil, count: $0.count) }
        func unmodifiedSize(_ row: Int, _ index: Int) throws -> MathBox {
            if let box = natural[row][index] { return box }
            guard let op = operators[row][index] else { return measured[row][index].box }
            var core = op.core
            core.attributes["stretchy"] = "false"
            let source = sources[row][index]
            let node = replacingTableCore(source.node, path: op.path, core: core)
            let box = try relayoutCell(TableCellSource(node: node, context: source.context, depth: source.depth),
                                      width: cells.spanWidth(measured[row][index], widths: widths, gaps: columnGaps))
            natural[row][index] = box
            return box
        }
        var plans: [(row: Int, index: Int, source: TableCellSource, stretch: Embellishment.Stretch)] = []
        for row in measured.indices {
            for index in measured[row].indices {
                guard let op = operators[row][index] else { continue }
                let cell = measured[row][index]
                // Authored track allocation supplies an additional stretch target. Keep it
                // separate from natural tracks, which may include excluded crossing spans.
                let allocated = op.horizontal && allocatedWidths.count == cells.columns
                    ? cells.spanWidth(cell, widths: allocatedWidths, gaps: columnGaps) : 0
                var peers: [(row: Int, index: Int)] = [], stretchyPeers: [(row: Int, index: Int)] = []
                for otherRow in measured.indices {
                    // Row spans can only contain cells starting within their covered rows.
                    if !op.horizontal && !(row..<(row + cell.rowSpan)).contains(otherRow) { continue }
                    for otherIndex in measured[otherRow].indices {
                        try countTableWork(1)
                        if row == otherRow && index == otherIndex { continue }
                        let other = measured[otherRow][otherIndex]
                        let contained = op.horizontal
                            ? other.column >= cell.column && other.column + other.columnSpan <= cell.column + cell.columnSpan
                            : otherRow + other.rowSpan <= row + cell.rowSpan
                        guard contained else { continue }
                        if operators[otherRow][otherIndex]?.horizontal == op.horizontal {
                            stretchyPeers.append((otherRow, otherIndex))
                        } else { peers.append((otherRow, otherIndex)) }
                    }
                }
                // No neighboring expression means no requested stretch. When every neighbor
                // stretches, use their normal sizes, before minsize/maxsize changed them.
                guard !peers.isEmpty || !stretchyPeers.isEmpty || op.core.attributes["minsize"] != nil
                    || allocated > cell.box.width else { continue }
                let allStretchy = peers.isEmpty
                if allStretchy { peers = stretchyPeers + [(row, index)] }
                let stretch: Embellishment.Stretch
                if op.horizontal {
                    var target = allocated
                    for peer in peers {
                        let box = try allStretchy ? unmodifiedSize(peer.row, peer.index) : measured[peer.row][peer.index].box
                        target = max(target, box.width)
                    }
                    // Horizontal stretching uses the same author bounds as vertical stretching.
                    // The reference is the core's normal width, excluding any scripts or limits.
                    if op.core.attributes["minsize"] != nil || op.core.attributes["maxsize"] != nil {
                        let source = sources[row][index]
                        var outer = inherit(source.node, source.context)
                        var node = source.node
                        for (position, child) in op.path.enumerated() {
                            node = node.children[child]
                            if position < op.path.count - 1 { outer = inherit(node, outer) }
                        }
                        let context = inherit(op.core, outer)
                        var core = op.core; core.attributes["stretchy"] = "false"
                        let normal = try relayoutCell(TableCellSource(node: core, context: outer, depth: source.depth), width: .infinity)
                        let minimum = max(length(op.core.attributes["minsize"], context, reference: normal.width) ?? 0, 0)
                        target = max(target, minimum)
                        if let maximum = length(op.core.attributes["maxsize"], context, reference: normal.width) {
                            target = min(target, max(maximum, minimum))
                        }
                    }
                    stretch = .horizontal(width: target)
                } else {
                    var ascents = [CGFloat](repeating: 0, count: cell.rowSpan), descents = ascents
                    var spanning: [(offset: Int, span: Int, box: MathBox)] = []
                    for peer in peers {
                        let other = measured[peer.row][peer.index]
                        var box = try allStretchy ? unmodifiedSize(peer.row, peer.index) : other.box
                        if other.rowAlign == "axis" {
                            let rowAxis = value(\.axisHeight, sources[peer.row][peer.index].context)
                            let shift = rowAxis - other.axis
                            box.ascent += shift; box.descent -= shift
                        }
                        let offset = peer.row - row
                        if other.rowSpan == 1 {
                            ascents[offset] = max(ascents[offset], box.ascent)
                            descents[offset] = max(descents[offset], box.descent)
                        } else { spanning.append((offset, other.rowSpan, box)) }
                    }
                    for peer in spanning {
                        let end = peer.offset + peer.span
                        ascents[peer.offset] = max(ascents[peer.offset], peer.box.ascent)
                        let available = ascents[(peer.offset + 1)..<end].reduce(0, +) + descents[peer.offset..<end].reduce(0, +)
                            + rowGaps[(row + peer.offset)..<(row + end - 1)].reduce(0, +)
                        let extra = max(0, peer.box.descent - available) / CGFloat(peer.span)
                        for offset in peer.offset..<end { descents[offset] += extra }
                    }
                    let ownShift = cell.rowAlign == "axis"
                        ? value(\.axisHeight, sources[row][index].context) - cell.axis : 0
                    let ascent = ascents[0] - ownShift
                    let descent = descents.reduce(0, +) + ascents.dropFirst().reduce(0, +)
                        + rowGaps[row..<(row + cell.rowSpan - 1)].reduce(0, +) + ownShift
                    stretch = .vertical(ascent: ascent, descent: descent)
                }
                let source = sources[row][index]
                var node = source.node
                // Symmetric stretching in a table only applies to baseline/axis alignment.
                if !op.horizontal && cell.rowAlign != "baseline" && cell.rowAlign != "axis" {
                    var core = op.core; core.attributes["symmetric"] = "false"
                    node = replacingTableCore(node, path: op.path, core: core)
                }
                plans.append((row, index, TableCellSource(node: node, context: source.context, depth: source.depth), stretch))
            }
        }
        guard !plans.isEmpty else { return }
        // Group alignment consumed local source markers and translated the drawing. Restore
        // all participating cells, so the table can align their new side widths together.
        for row in cells.rows.indices {
            for index in cells.rows[row].indices {
                if let original = cells.rows[row][index].unalignedBox {
                    cells.rows[row][index].box = original
                    cells.rows[row][index].unalignedBox = nil
                }
            }
        }
        for plan in plans {
            let cell = measured[plan.row][plan.index]
            let width = cells.spanWidth(cell, widths: widths, gaps: columnGaps)
            cells.rows[plan.row][plan.index].box = try relayoutCell(plan.source, width: width,
                embellishment: Embellishment(stretch: plan.stretch))
        }
        // Fresh cell engines number their own events. Source order across the complete table
        // must remain unique when an unscoped table exports marks to an enclosing group.
        for row in cells.rows.indices {
            for index in cells.rows[row].indices { restampAlignment(&cells.rows[row][index].box) }
        }
    }

    /// Retain the core path so a table can override symmetric without changing the source tree.
    private func tableOperatorCore(_ source: MathMLNode) -> (MathMLNode, [Int])? {
        guard source.name == "mtd", source.children.count == 1 else { return nil }
        var node = source.children[0], path = [0]
        for _ in 0..<MathLimits.depth {
            let child: Int
            switch node.name {
            case "mo": return (node, path)
            case "msub", "msup", "msubsup", "munder", "mover", "munderover", "mmultiscripts", "mfrac":
                guard !node.children.isEmpty else { return nil }; child = 0
            case "semantics", "maction":
                guard let shown = Self.shownIndex(node) else { return nil }; child = shown
            case "mrow", "mstyle", "mphantom", "mpadded":
                let flow = node.children.indices.filter { !isSpaceLike(node.children[$0]) }
                guard flow.count == 1 else { return nil }; child = flow[0]
            default: return nil
            }
            path.append(child); node = node.children[child]
        }
        return nil
    }

    private func replacingTableCore(_ source: MathMLNode, path: [Int], core: MathMLNode) -> MathMLNode {
        var parents: [MathMLNode] = [], node = source
        for index in path { parents.append(node); node = node.children[index] }
        var result = core
        for (parent, index) in zip(parents, path).reversed() {
            var copy = parent; copy.children[index] = result; result = copy
        }
        return result
    }
}
