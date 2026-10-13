import CoreGraphics
import Foundation

/// A source cell's rectangle in the table, excluding the independent label column.
struct TableCell {
    var box: MathBox
    var align: String?
    var rowAlign: String?
    var column: Int
    var rowSpan: Int
    var columnSpan: Int
}

/// Sparse occupancy, bounded independently of the number of source nodes. A cell starts at the
/// first completely free rectangle at or after the preceding cell. Rows beyond the source table
/// are clipped; malformed positive integers use one, and excessive valid requests throw.
struct TableGrid {
    var rows: [[TableCell]]
    private var occupied: Set<Int> = []
    private(set) var columns = 0
    private(set) var work = 0

    init(rowCount: Int) throws {
        guard rowCount <= MathLimits.nodes else { throw MathLayoutError.limitExceeded }
        rows = Array(repeating: [], count: rowCount)
    }

    static func span(_ value: String?) throws -> Int {
        guard let value else { return 1 }
        let digits = value.trimmingCharacters(in: .whitespacesAndNewlines).utf8
        guard !digits.isEmpty, digits.allSatisfy({ (48...57).contains($0) }) else { return 1 }
        var result = 0
        for digit in digits {
            result = result * 10 + Int(digit - 48)
            guard result <= MathLimits.nodes else { throw MathLayoutError.limitExceeded }
        }
        return max(result, 1)
    }

    mutating func insert(_ box: MathBox, row: Int, rowSpan: Int, columnSpan: Int,
                         align: String?, rowAlign: String?, workBudget: Int = MathLimits.tableWork) throws {
        let rowSpan = min(rowSpan, rows.count - row)
        guard rowSpan > 0, columnSpan > 0, columnSpan <= MathLimits.nodes,
              rowSpan <= (MathLimits.nodes - occupied.count) / columnSpan else {
            throw MathLayoutError.limitExceeded
        }
        let allowance = min(MathLimits.tableWork - work, max(workBudget, 0))
        var probes = 0
        var column = rows[row].last.map { $0.column + $0.columnSpan } ?? 0
        search: while true {
            guard column <= MathLimits.nodes - columnSpan else { throw MathLayoutError.limitExceeded }
            for r in row..<(row + rowSpan) {
                for c in column..<(column + columnSpan) {
                    guard probes < allowance else { throw MathLayoutError.limitExceeded }
                    work += 1
                    probes += 1
                    if occupied.contains(r * MathLimits.nodes + c) {
                        column = c + 1
                        continue search
                    }
                }
            }
            break
        }
        for r in row..<(row + rowSpan) {
            for c in column..<(column + columnSpan) { occupied.insert(r * MathLimits.nodes + c) }
        }
        columns = max(columns, column + columnSpan)
        rows[row].append(TableCell(box: box, align: align, rowAlign: rowAlign, column: column,
                                   rowSpan: rowSpan, columnSpan: columnSpan))
    }

    /// Single-column constraints first, then spanning deficits shared equally across the tracks.
    /// Gaps inside a span already contribute to its available width.
    func widths(gaps: [CGFloat], measure: (Int, Int, TableCell) -> CGFloat) -> [CGFloat] {
        var widths = [CGFloat](repeating: 0, count: columns)
        for (rowIndex, row) in rows.enumerated() {
            for (index, cell) in row.enumerated() where cell.columnSpan == 1 {
                widths[cell.column] = max(widths[cell.column], measure(rowIndex, index, cell))
            }
        }
        for (rowIndex, row) in rows.enumerated() {
            for (index, cell) in row.enumerated() where cell.columnSpan > 1 {
                let range = cell.column..<(cell.column + cell.columnSpan)
                let available = spanWidth(cell, widths: widths, gaps: gaps)
                let extra = max(0, measure(rowIndex, index, cell) - available) / CGFloat(cell.columnSpan)
                for column in range { widths[column] += extra }
            }
        }
        return widths
    }

    func spanWidth(_ cell: TableCell, widths: [CGFloat], gaps: [CGFloat]) -> CGFloat {
        let end = cell.column + cell.columnSpan
        return widths[cell.column..<end].reduce(0, +) + gaps[cell.column..<(end - 1)].reduce(0, +)
    }
}
