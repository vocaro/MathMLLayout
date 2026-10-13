import Foundation

/// Shared logical column geometry for drawing and speech. Column zero is the
/// alignment reference; columns increase to the right, including punctuation, in both
/// LTR and RTL contexts (MathML 3, 3.6). Positive position/shift moves towards tens,
/// physically left; stackalign and charalign name physical sides, independent of dir.
public enum MathStackAlignment: String, CaseIterable, Sendable {
    case left, center, right, decimalPoint = "decimalpoint"

    init(attribute: String?) {
        self = Self(rawValue: attribute?.trimmingCharacters(in: .whitespaces).lowercased() ?? "") ?? .decimalPoint
    }

    func firstColumn(count: Int, decimalPoint: Int?, position: Int) -> Int {
        let anchor = switch self {
        case .left: 0
        case .center: count / 2
        case .right: count
        case .decimalPoint: decimalPoint ?? count
        }
        return -anchor - position
    }

    static func columns(_ node: MathMLNode, _ name: String) -> Int {
        let value = node.attributes[name].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        return min(max(value, -(1 << 31)), 1 << 31)
    }
}
