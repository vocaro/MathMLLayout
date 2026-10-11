import CoreGraphics
import CoreText
import Foundation
@testable import MathMLLayout
import XCTest

/// Line breaking against formulas nobody wrote: a seeded generator builds `MathMLNode` trees,
/// shapes no XML parser produces among them, and every one is laid out at several widths and
/// held to what a host relies on. The same seed is the same formula on every run and machine.
///
/// `MATHML_FUZZ_SEEDS=first-last` in the environment runs that range instead of the few hundred
/// seeds the suite keeps, and `MATHML_FUZZ_TRACE=path` writes each seed there before it runs: a
/// trap aborts the process, and the file then names the seed that did it.
final class LineBreakingFuzzTests: MathTestCase {
    // MARK: Generator

    /// SplitMix64.
    struct Random {
        var state: UInt64
        /// Mixed once, so that the streams of two seeds in a row are not one stream a step apart.
        init(seed: UInt64) { state = seed; state = next() ^ 0xD1B5_4A32_D192_ED03 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ count: Int) -> Int { Int(next() % UInt64(max(count, 1))) }
        mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
        mutating func pick<T>(_ values: [T]) -> T { values[below(values.count)] }
    }

    /// The colour of every `mi`, `mn`, `mtext` and `ms` the generator makes, and of nothing else:
    /// what a broken formula must draw exactly as the unbroken one does, whatever its fences
    /// stretch to and its operators repeat.
    static let tokenColor = "#0000ff"

    struct Generator {
        var random: Random
        /// Nodes left to make.
        var budget: Int
        var ids = 0

        static let operators = [
            "+", "+", "+", "−", "-", "=", "=", "<", "≤", "×", "⋅", "\u{2062}", "\u{2062}", "\u{2061}", "\u{2063}", "\u{2064}",
            ",", ";", "(", ")", "[", "]", "|", "{", "}", "∑", "∫", "!", "→", "/", "", "lim", "±", ":", "…", "'", "%", "foo", "⟶",
            "∥", "~", "\u{0302}", "⏞",
        ]
        static let linebreaks = ["auto", "newline", "newline", "nobreak", "goodbreak", "badbreak", "indentingnewline", "NEWLINE",
                                 " newline ", "garbage", ""]
        static let styles = ["before", "after", "duplicate", "duplicate", "infixlinebreakstyle", "AFTER", "garbage", ""]
        static let aligns = ["left", "center", "right", "auto", "id", "id", "indentalign", "CENTER", "garbage", ""]
        static let lengths = [
            "0", "1em", "2em", "-1em", "-3em", "0.5ex", "10%", "-10%", "50%", "150%", "-50%", "99999%", "-99999%", "1e9em",
            "-1e9em", "nan", "inf", "-inf", "infinity", "1000em", "-1000em", "999999em", "5", "-5", "3px", "1in",
            "thinmathspace", "negativeverythickmathspace", String(repeating: "9", count: 60) + "%",
            "-" + String(repeating: "9", count: 60) + "%", String(repeating: "9", count: 62), "+2em", " 2em ", "2 em", "",
            "em", ".", "1.5.2em", "0x10", "indentshift", "100%", "200%",
        ]
        static let integers = ["0", "1", "2", "-1", "+1", "-2", "+3", "7", "99", "-99", "9223372036854775807",
                               "-9223372036854775808", "+9223372036854775807", "-9223372036854775807", "1e3", "x", ""]
        static let words = ["a", "of", "the", "rate", "x", "principal", "if", "otherwise", "speed", "×", "12", "e\u{0301}", "数学",
                            "ﬁn", "שלום", "😀", "over-long-hyphenated-word", "\u{FFFC}", "a\u{00A0}b", "a\u{2003}b", "\u{200B}"]
        static let spaces = [" ", " ", " ", "  ", "\u{00A0}", "\t", "\n", " \n ", "\u{2003}", "\u{FFFC}", ""]
        static let notations = ["longdiv", "box", "roundedbox", "circle", "left right", "top bottom", "updiagonalstrike",
                                "radical", "actuarial", "madruwb", "horizontalstrike box", "updiagonalarrow", "nothing", "",
                                "circle box", "verticalstrike downdiagonalstrike"]

        mutating func length() -> String { random.pick(Self.lengths) }

        mutating func identifier() -> String {
            if random.chance(10) { return "dup" }
            ids += 1
            return "t\(ids)"
        }

        /// An `indenttarget`: an element above, itself or one that comes later, one that is twice, none.
        mutating func target() -> String { random.chance(15) ? random.pick(["dup", "missing", ""]) : "t\(random.below(ids + 3))" }

        /// The line-breaking attributes of MathML 3 (3.2.5.2.2, 3.2.5.2.3), each with `percent` in a hundred.
        mutating func lineAttributes(_ attributes: inout [String: String], percent: Int) {
            if random.chance(percent) { attributes["linebreak"] = random.pick(Self.linebreaks) }
            if random.chance(percent) { attributes["linebreakstyle"] = random.pick(Self.styles) }
            if random.chance(percent / 2) { attributes["infixlinebreakstyle"] = random.pick(Self.styles) }
            if random.chance(percent / 2) { attributes["linebreakmultchar"] = random.pick(["×", "⋅", "", "\u{2062}", "abc", " ", "∑"]) }
            if random.chance(percent / 2) { attributes["lineleading"] = length() }
            if random.chance(percent) { attributes["indentalign"] = random.pick(Self.aligns) }
            if random.chance(percent / 3) { attributes["indentalignfirst"] = random.pick(Self.aligns) }
            if random.chance(percent / 3) { attributes["indentalignlast"] = random.pick(Self.aligns) }
            if random.chance(percent) { attributes["indentshift"] = length() }
            if random.chance(percent / 3) { attributes["indentshiftfirst"] = length() }
            if random.chance(percent / 3) { attributes["indentshiftlast"] = length() }
            if random.chance(percent) { attributes["indenttarget"] = target() }
        }

        mutating func formula() -> MathMLNode {
            guard random.chance(88) else { return element(0) }
            var attributes: [String: String] = [:]
            if random.chance(40) { attributes["display"] = "block" }
            lineAttributes(&attributes, percent: 12)
            return MathMLNode(name: "math", attributes: attributes, children: sequence(1))
        }

        /// The children of a row: mostly operands with operators between them, as formulas are.
        mutating func sequence(_ depth: Int, most: Int = 9) -> [MathMLNode] {
            var children: [MathMLNode] = []
            let count = random.chance(4) ? 0 : 1 + random.below(most)
            let alternates = random.chance(75)
            for index in 0..<count where budget > 0 {
                children.append(alternates ? (index % 2 == 0 ? operand(depth) : operatorNode()) : element(depth))
            }
            return children
        }

        mutating func operand(_ depth: Int) -> MathMLNode { random.chance(55) ? token() : element(depth) }

        mutating func token() -> MathMLNode {
            budget -= 1
            var attributes = ["mathcolor": LineBreakingFuzzTests.tokenColor]
            if random.chance(8) { attributes["id"] = identifier() }
            if random.chance(3) { attributes["mathbackground"] = "yellow" }
            if random.chance(3) { attributes["mathvariant"] = random.pick(["bold", "italic", "normal", "double-struck", "x"]) }
            switch random.below(10) {
            case 0..<4: return MathMLNode(name: "mi", attributes: attributes, text: random.pick(["x", "y", "f", "j", "alpha", "sin", "", "ab"]))
            case 4..<6: return MathMLNode(name: "mn", attributes: attributes, text: random.pick(["1", "42", "3.14", "1 000", ""]))
            case 6..<9:
                var text = random.chance(15) ? random.pick(Self.spaces) : ""
                for index in 0..<(random.chance(6) ? 120 : 1 + random.below(9)) {
                    text += (index > 0 ? random.pick(Self.spaces) : "") + random.pick(Self.words)
                }
                if random.chance(15) { text += random.pick(Self.spaces) }
                var children: [MathMLNode] = []
                if random.chance(8) { children.append(glyph()) }
                // No attribute of an `mtext` is a line-breaking one: these must change nothing.
                if random.chance(5) { attributes["linebreak"] = random.pick(Self.linebreaks) }
                return MathMLNode(name: "mtext", attributes: attributes, children: children, text: text)
            default:
                if random.chance(30) { attributes["lquote"] = random.pick(["«", "", "\u{FFFC}", "  "]) }
                return MathMLNode(name: "ms", attributes: attributes, text: random.pick(["s", "two words", ""]))
            }
        }

        mutating func glyph() -> MathMLNode {
            budget -= 1
            var attributes = ["src": random.pick(["image", "image", "missing", ""]), "alt": random.pick(["alt", "", "two words", "\u{FFFC}"])]
            if random.chance(40) { attributes["width"] = length() }
            if random.chance(40) { attributes["height"] = length() }
            if random.chance(30) { attributes["valign"] = length() }
            return MathMLNode(name: "mglyph", attributes: attributes)
        }

        mutating func operatorNode() -> MathMLNode {
            budget -= 1
            var attributes: [String: String] = [:]
            lineAttributes(&attributes, percent: 14)
            if random.chance(12) { attributes["id"] = identifier() }
            // Naming itself: the element is never on a row above the one its own break starts.
            if random.chance(4) { let id = identifier(); attributes["id"] = id; attributes["indenttarget"] = id; attributes["indentalign"] = "id" }
            if random.chance(6) { attributes["form"] = random.pick(["prefix", "infix", "postfix", "x"]) }
            for name in ["fence", "separator", "stretchy", "largeop", "movablelimits", "symmetric", "accent"] where random.chance(3) {
                attributes[name] = random.pick(["true", "false", "x"])
            }
            if random.chance(5) { attributes["lspace"] = length() }
            if random.chance(5) { attributes["rspace"] = length() }
            if random.chance(5) { attributes["mathcolor"] = "red" }
            if random.chance(2) { attributes["mathbackground"] = "#ff0" }
            var children: [MathMLNode] = []
            var text = random.pick(Self.operators)
            if random.chance(3) { children.append(glyph()); if random.chance(50) { text += "\u{FFFC}" } }
            return MathMLNode(name: "mo", attributes: attributes, children: children, text: text)
        }

        mutating func space() -> MathMLNode {
            budget -= 1
            var attributes: [String: String] = [:]
            if random.chance(55) { attributes["width"] = length() }
            if random.chance(10) { attributes["height"] = length() }
            if random.chance(10) { attributes["depth"] = length() }
            lineAttributes(&attributes, percent: 20)
            if random.chance(40) { attributes["linebreak"] = random.pick(Self.linebreaks) }
            if random.chance(10) { attributes["id"] = identifier() }
            return MathMLNode(name: "mspace", attributes: attributes)
        }

        mutating func styleAttributes() -> [String: String] {
            var attributes: [String: String] = [:]
            lineAttributes(&attributes, percent: 22)
            if random.chance(10) { attributes["displaystyle"] = random.pick(["true", "false"]) }
            if random.chance(12) { attributes["scriptlevel"] = random.pick(Self.integers) }
            if random.chance(8) { attributes["mathsize"] = random.pick(["small", "big", "200%", "5em", "1000em", "0", "-1em", "0.01em"]) }
            if random.chance(6) { attributes["mathbackground"] = random.pick(["yellow", "#abc", "transparent", "x"]) }
            if random.chance(6) { attributes["mathcolor"] = random.pick(["red", "green", "#123456", "x"]) }
            if random.chance(4) { attributes["scriptsizemultiplier"] = random.pick(["0.5", "2", "10", "0.11", "nan", "-1"]) }
            if random.chance(4) { attributes["scriptminsize"] = length() }
            if random.chance(4) { attributes["decimalpoint"] = random.pick([",", "", "ab"]) }
            if random.chance(8) { attributes["id"] = identifier() }
            return attributes
        }

        mutating func element(_ depth: Int) -> MathMLNode {
            guard depth < 9, budget > 0 else { return token() }
            budget -= 1
            let next = depth + 1
            switch random.below(100) {
            case 0..<14: budget += 1; return token()
            case 14..<24: budget += 1; return operatorNode()
            case 24..<38:
                var attributes: [String: String] = [:]
                if random.chance(10) { attributes["id"] = identifier() }
                if random.chance(4) { attributes["mathbackground"] = "yellow" }
                return MathMLNode(name: "mrow", attributes: attributes, children: sequence(next))
            case 38..<46: return MathMLNode(name: "mstyle", attributes: styleAttributes(), children: sequence(next))
            case 46..<53:
                var attributes: [String: String] = [:]
                if random.chance(30) { attributes["open"] = random.pick(["[", "{", "", "|", "((", "x", "\u{2062}"]) }
                if random.chance(30) { attributes["close"] = random.pick(["]", "}", "", "|", "))", "+"]) }
                if random.chance(30) { attributes["separators"] = random.pick([";", "", ",;", " ", "+", "=", "\u{2062}", ",,,,,,,,"]) }
                return MathMLNode(name: "mfenced", attributes: attributes, children: sequence(next, most: 5))
            case 53..<60:
                var attributes: [String: String] = [:]
                if random.chance(10) { attributes["bevelled"] = "true" }
                if random.chance(15) { attributes["linethickness"] = random.pick(["0", "thick", "5em", "-1", "nan"]) }
                if random.chance(15) { attributes["numalign"] = random.pick(["left", "right", "x"]) }
                let count = random.chance(3) ? random.below(4) : 2
                return MathMLNode(name: "mfrac", attributes: attributes, children: (0..<count).map { _ in operand(next) })
            case 60..<65:
                if random.chance(25) { return MathMLNode(name: "mroot", children: [operand(next), operand(next)]) }
                return MathMLNode(name: "msqrt", children: sequence(next))
            case 65..<70:
                var attributes: [String: String] = [:]
                if random.chance(85) { attributes["notation"] = random.pick(Self.notations) }
                return MathMLNode(name: "menclose", attributes: attributes, children: sequence(next))
            case 70..<79:
                let name = random.pick(["msub", "msup", "msup", "msubsup", "mmultiscripts", "munder", "mover", "munderover"])
                var count = name == "msubsup" || name == "munderover" ? 3 : 2
                if name == "mmultiscripts" { count = random.pick([1, 3, 3, 5, 2]) }
                if random.chance(3) { count = random.below(5) }
                // A base that is a row is what breaks under its scripts.
                var children = [random.chance(60) ? MathMLNode(name: random.pick(["mrow", "mrow", "mfenced", "mstyle"]),
                                                               children: sequence(next)) : operand(next)]
                for _ in 1..<max(count, 1) { children.append(random.chance(8) ? MathMLNode(name: "none") : operand(next)) }
                if name == "mmultiscripts", random.chance(40) {
                    children.append(MathMLNode(name: "mprescripts"))
                    for _ in 0..<random.pick([2, 2, 4, 1]) { children.append(operand(next)) }
                }
                var attributes: [String: String] = [:]
                if random.chance(10) { attributes["accent"] = random.pick(["true", "false"]) }
                return MathMLNode(name: name, attributes: attributes, children: children)
            case 79..<86:
                var attributes: [String: String] = [:]
                if random.chance(20) { attributes["columnalign"] = random.pick(["left", "right center", "x", "left left right"]) }
                if random.chance(15) { attributes["frame"] = random.pick(["solid", "dashed", "none"]) }
                if random.chance(15) { attributes["columnspacing"] = length() }
                if random.chance(10) { attributes["rowspacing"] = length() }
                if random.chance(10) { attributes["framespacing"] = length() + " " + length() }
                if random.chance(10) { attributes["align"] = random.pick(["axis", "top", "bottom 2", "center -1", "baseline"]) + " " + random.pick(Self.integers) }
                if random.chance(10) { attributes["rowlines"] = random.pick(["solid", "dashed none"]); attributes["columnlines"] = "dashed" }
                if random.chance(8) { attributes["side"] = random.pick(["left", "right"]) }
                if random.chance(8) { attributes["minlabelspacing"] = length() }
                var rows: [MathMLNode] = []
                let columns = 1 + random.below(4)
                for _ in 0..<(random.chance(4) ? 0 : 1 + random.below(4)) where budget > 0 {
                    if random.chance(8) { rows.append(operand(next)); continue }
                    var cells: [MathMLNode] = []
                    for _ in 0..<(random.chance(15) ? random.below(6) : columns) where budget > 0 {
                        budget -= 1
                        var cell: [String: String] = [:]
                        if random.chance(10) { cell["columnalign"] = random.pick(["left", "right", "center"]) }
                        cells.append(random.chance(8) ? operand(next) : MathMLNode(name: "mtd", attributes: cell, children: sequence(next, most: 6)))
                    }
                    rows.append(MathMLNode(name: random.chance(12) ? "mlabeledtr" : "mtr", children: cells))
                }
                return MathMLNode(name: "mtable", attributes: attributes, children: rows)
            case 86..<89:
                var attributes: [String: String] = [:]
                for name in ["width", "height", "depth", "lspace", "voffset"] where random.chance(35) {
                    attributes[name] = random.chance(40) ? random.pick(["+0.5width", "200%", "-2height", "0", "2depth", "+1em"]) : length()
                }
                return MathMLNode(name: random.pick(["mpadded", "mphantom", "merror"]), attributes: attributes, children: sequence(next))
            case 89..<92:
                if random.chance(50) {
                    return MathMLNode(name: "semantics", children: [operand(next), MathMLNode(name: "annotation", text: "x")])
                }
                return MathMLNode(name: "maction", attributes: ["selection": random.pick(Self.integers)], children: sequence(next, most: 3))
            case 92..<95: budget += 1; return space()
            case 95..<96: budget += 1; return glyph()
            case 96..<98:
                var rows: [MathMLNode] = []
                for _ in 0..<(1 + random.below(3)) {
                    budget -= 1
                    rows.append(random.chance(20) ? MathMLNode(name: "msline") : MathMLNode(name: "mn", text: random.pick(["12", "3.5", "407"])))
                }
                if random.chance(50) { return MathMLNode(name: "mstack", children: rows) }
                return MathMLNode(name: "mlongdiv", attributes: ["longdivstyle": random.pick(["lefttop", "stackedrightright", "x"])],
                                  children: [MathMLNode(name: "mn", text: "3"), MathMLNode(name: "mn", text: "4")] + rows)
            default: return odd(next)
            }
        }

        /// What no XML parser makes but a host's own DOM might: text on a container, elements in
        /// a token, table parts and stack parts loose in a row, marks without their `mglyph`.
        mutating func odd(_ depth: Int) -> MathMLNode {
            switch random.below(12) {
            case 0: return MathMLNode(name: "mrow", children: sequence(depth), text: "stray text")
            case 1: return MathMLNode(name: "mi", attributes: ["mathcolor": LineBreakingFuzzTests.tokenColor], children: sequence(depth, most: 3), text: "x")
            case 2: return MathMLNode(name: random.pick(["mtd", "mtr", "mlabeledtr"]), children: sequence(depth, most: 4))
            case 3: return MathMLNode(name: random.pick(["none", "mprescripts", "malignmark", "maligngroup", "annotation", "annotation-xml"]))
            case 4: return MathMLNode(name: random.pick(["msgroup", "msrow", "msline", "mscarries", "mscarry"]), children: sequence(depth, most: 3))
            case 5: return MathMLNode(name: "mo", children: sequence(depth, most: 2), text: random.pick(["+", "\u{FFFC}\u{FFFC}", "("]))
            case 6: return MathMLNode(name: "mspace", attributes: ["linebreak": "newline"], children: sequence(depth, most: 2), text: "text")
            case 7: return MathMLNode(name: "mtext", attributes: ["mathcolor": LineBreakingFuzzTests.tokenColor],
                                      children: [glyph(), glyph()], text: random.pick(["a b", "a \u{FFFC} b \u{FFFC}\u{FFFC} c", ""]))
            case 8: return MathMLNode(name: "mmultiscripts", children: [MathMLNode(name: "mprescripts")] + sequence(depth, most: 4))
            case 9: return MathMLNode(name: "semantics")
            case 10: return MathMLNode(name: random.chance(20) ? "foo" : "mrow")
            default: return MathMLNode(name: "math", attributes: styleAttributes(), children: sequence(depth))
            }
        }
    }

    // MARK: What is drawn

    /// One thing a box draws, with the height of its origin above the baseline.
    struct Mark: Equatable {
        /// A glyph and its font, or a rule, path or image.
        var kind: Int
        var isToken: Bool
        var y: CGFloat
    }

    /// Everything `box` draws, in drawing order. Space glyphs are left out: a line that breaks at a
    /// space in an `mtext` drops it.
    static func marks(_ box: MathBox, at origin: CGPoint = .zero, into marks: inout [Mark]) {
        for item in box.items {
            switch item {
            case .glyphs(let run):
                var character: UniChar = 0x20, space: CGGlyph = 0
                if !CTFontGetGlyphsForCharacters(run.font, &character, &space, 1) { space = 0 }
                let isToken = run.color.components.map { $0.count == 4 && $0[0] == 0 && $0[1] == 0 && $0[2] == 1 } ?? false
                let font = (CTFontCopyPostScriptName(run.font) as String).hashValue & 0xFFFF
                for (glyph, position) in zip(run.glyphs, run.positions) where space == 0 || glyph != space {
                    marks.append(Mark(kind: font << 16 | Int(glyph), isToken: isToken, y: origin.y + position.y))
                }
            case .rect: marks.append(Mark(kind: -1, isToken: false, y: origin.y))
            case .path, .dashes: marks.append(Mark(kind: -2, isToken: false, y: origin.y))
            case .image: marks.append(Mark(kind: -3, isToken: false, y: origin.y))
            case .box(let inner, let point): Self.marks(inner, at: CGPoint(x: origin.x + point.x, y: origin.y + point.y), into: &marks)
            }
        }
    }

    static func marks(_ boxes: [MathBox]) -> [Mark] {
        var result: [Mark] = []
        for box in boxes { marks(box, into: &result) }
        return result
    }

    /// Whether `part` is `whole` with marks left out, in order: what breaking may add (a repeated
    /// operator, a times sign made visible) it adds between what was there.
    static func isSubsequence(_ part: [Mark], of whole: [Mark]) -> Bool {
        var index = 0
        for mark in whole where index < part.count {
            if mark.kind == part[index].kind, abs(mark.y - part[index].y) < 1e-6 { index += 1 }
        }
        return index == part.count
    }

    // MARK: Properties

    /// What the generator put in a formula that changes what must hold of it.
    struct Facts {
        /// A `linebreak="newline"` somewhere: the formula may be rows at any width.
        var forces = false
        /// An indentation attribute somewhere: a row may start away from the edge.
        var indents = false
        /// `linebreakstyle="duplicate"` or `linebreakmultchar` somewhere: breaking may draw more.
        var adds = false

        init(_ node: MathMLNode) {
            for (name, value) in node.attributes {
                let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if name == "linebreak", value == "newline" || value == "indentingnewline" { forces = true }
                if name.hasPrefix("indent") { indents = true }
                if name == "linebreakmultchar" || name.hasSuffix("linebreakstyle") && value == "duplicate" { adds = true }
            }
            for child in node.children {
                let inner = Facts(child)
                forces = forces || inner.forces; indents = indents || inner.indents; adds = adds || inner.adds
            }
        }
    }

    static let image: CGImage = {
        let context = CGContext(data: nil, width: 6, height: 4, bitsPerComponent: 8, bytesPerRow: 24,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 6, height: 4))
        return context.makeImage()!
    }()
    /// One provider, so that styles made from it are equal.
    static let images = MathImageProvider { $0 == "image" ? image : nil }

    static func style(_ size: CGFloat, display: Bool = false) -> MathStyle {
        MathStyle(fontSize: size, color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), isDisplay: display, imageProvider: images)
    }

    /// The numbers of a result, for comparing two of them.
    static func geometry(_ lines: MathLines) -> [CGFloat] {
        [lines.width, lines.ascent, lines.descent, lines.widestUnbreakable, lines.axisHeight]
            + lines.rows.flatMap { [$0.origin.x, $0.origin.y, $0.box.width, $0.box.ascent, $0.box.descent] }
    }

    /// The limits `maximumWidth` and `firstRowMaximumWidth` stand for.
    static func limits(_ width: CGFloat, _ first: CGFloat?) -> (limit: CGFloat, first: CGFloat) {
        func bound(_ width: CGFloat) -> CGFloat { width.isNaN || width > MathLimits.extent ? .infinity : max(width, 0) }
        let limit = bound(width)
        return (limit, first.map { $0.isNaN ? limit : bound($0) } ?? limit)
    }

    /// Lays `root` out at one width and returns what does not hold of the result, each with the
    /// name of the property; empty when all is well or the formula is refused as it may be.
    static func violations(_ root: MathMLNode, style: MathStyle, width: CGFloat, first: CGFloat?, thorough: Bool = true) -> [String] {
        var found: [String] = []
        let facts = Facts(root)
        let (limit, firstLimit) = limits(width, first)
        let lines: MathLines
        do {
            lines = try LayoutEngine.lines(root, style: style, maximumWidth: width, firstRowMaximumWidth: first)
        } catch is MathLayoutError {
            return []
        } catch {
            return ["throws: \(error)"]
        }
        // Finite, in bounds, and the layout's box covers every row's.
        let numbers = geometry(lines)
        if !numbers.allSatisfy(\.isFinite) { return ["finite: \(numbers)"] }
        if lines.rows.isEmpty { return ["rows: none"] }
        if max(lines.width, lines.ascent, lines.descent) > MathLimits.extent { found.append("extent: \(numbers.prefix(3))") }
        if lines.rows.reduce(0, { $0 + $1.box.itemCount }) > MathLimits.items { found.append("items") }
        if lines.rows[0].origin.y != 0 { found.append("first baseline: \(lines.rows[0].origin.y)") }
        for (index, row) in lines.rows.enumerated() {
            let box = row.box
            if min(box.width, box.ascent, box.descent, row.origin.x) < 0 || row.origin.y > 0 {
                found.append("row \(index) box: \(row.origin) \(box.width) \(box.ascent) \(box.descent)")
            }
            if row.origin.x + box.width > lines.width + 1e-6 || row.origin.y + box.ascent > lines.ascent + 1e-6
                || box.descent - row.origin.y > lines.descent + 1e-6 {
                found.append("row \(index) outside the layout's box")
            }
            if index > 0, row.origin.y > lines.rows[index - 1].origin.y { found.append("row \(index) above the row before it") }
            // Every row's ink lies inside its box.
            if let ink = box.inkBounds, !ink.isNull,
               ink.minX < -1e-6 || ink.maxX > box.width + 1e-6 || ink.maxY > box.ascent + 1e-6 || ink.minY < -box.descent - 1e-6 {
                found.append("row \(index) ink \(ink) outside its box \(box.width) \(box.ascent) \(box.descent)")
            }
            // Only a stretch that cannot break is wider than its line, and it starts at the edge.
            let room = index == 0 ? firstLimit : limit
            if row.origin.x + box.width > room + 0.01 {
                if row.origin.x > 1e-6 { found.append("row \(index) overflows \(room) indented by \(row.origin.x)") }
                if box.width > lines.widestUnbreakable + 0.01 {
                    found.append("row \(index) is \(box.width) wide in \(room), wider than the widest unbreakable \(lines.widestUnbreakable)")
                }
            }
        }
        // Without a width or a forced break: one row, the box the formula had before it could break.
        let engine = LayoutEngine(fontName: style.fontName)
        if limit == .infinity, firstLimit == .infinity, !facts.forces, let unbroken = try? engine.layoutRoot(root, style: style) {
            let ink = unbroken.inkBounds ?? .zero
            let left = max(0, -ink.minX)
            let was = [max(0, unbroken.width + left, ink.maxX + left), max(0, unbroken.ascent, ink.maxY), max(0, unbroken.descent, -ink.minY)]
            if lines.rows.count != 1 {
                found.append("one row: \(lines.rows.count)")
            } else {
                let row = lines.rows[0]
                if [row.box.width, row.box.ascent, row.box.descent] != was { found.append("one row's box: \(numbers) was \(was)") }
                if [lines.width, lines.ascent, lines.descent] != [row.origin.x + was[0], was[1], was[2]] {
                    found.append("one row's layout: \(numbers) was \(was)")
                }
                if !facts.indents, row.origin != .zero { found.append("one row's origin: \(row.origin)") }
            }
        }
        // Nothing is lost, repeated or reordered: the tokens are drawn as the unbroken formula draws them,
        // whatever wraps inside it. Only a repeated operator repeats one, the script it is embellished with.
        let drawn = marks(lines.rows.map(\.box))
        if let unbroken = try? LayoutEngine(fontName: style.fontName).layoutRoot(root, style: style) {
            let tokens = marks([unbroken]).filter(\.isToken).map { Mark(kind: $0.kind, isToken: true, y: 0) }
            let shown = drawn.filter(\.isToken).map { Mark(kind: $0.kind, isToken: true, y: 0) }
            if facts.adds ? !isSubsequence(tokens, of: shown) : shown != tokens { found.append("tokens: \(shown.count) drawn of \(tokens.count)") }
        }
        guard thorough else { return found }
        // The same again is the same.
        if let again = try? LayoutEngine.lines(root, style: style, maximumWidth: width, firstRowMaximumWidth: first) {
            if geometry(again) != numbers || marks(again.rows.map(\.box)) != drawn { found.append("deterministic") }
        } else {
            found.append("deterministic: throws the second time")
        }
        // The rows are the unbroken row's own boxes, moved along and nothing else: every mark at its height.
        let wrapping = LayoutEngine(fontName: style.fontName)
        wrapping.lineWidth = limit; wrapping.wrapWidth = limit
        if let box = try? wrapping.layoutRoot(root, style: style) {
            let paragraph = Paragraph(box, fontSize: LayoutEngine.fontSize(style))
            let rows = paragraph.rows(limit: limit, first: firstLimit, auto: (.left, 0))
            let before = marks([box]), after = marks(rows.map(\.box))
            if !isSubsequence(before, of: after) { found.append("units: \(after.count) marks in rows of \(before.count)") }
            if !facts.adds, before.count != after.count { found.append("units: \(after.count) marks in rows, \(before.count) unbroken") }
            if rows.contains(where: { !$0.x.isFinite || $0.x < 0 }) { found.append("units: a row at \(rows.map(\.x))") }
            if paragraph.units.isEmpty || paragraph.stops.count < 2 { found.append("units: none") }
        }
        // At the width of the widest unbreakable stretch nothing overflows.
        let widest = lines.widestUnbreakable
        if ProcessInfo.processInfo.environment["MATHML_FUZZ_SKIP_WIDEST"] == nil, limit.isFinite, widest > 0, let exact = try? LayoutEngine.lines(root, style: style, maximumWidth: widest, firstRowMaximumWidth: nil) {
            for (index, row) in exact.rows.enumerated() where row.origin.x + row.box.width > widest + 0.01 {
                found.append("at its widest unbreakable width \(widest) row \(index) reaches \(row.origin.x + row.box.width)"
                    + " (then widest \(exact.widestUnbreakable))")
            }
        }
        return found
    }

    // MARK: Reporting

    /// `node` as the Swift that builds it.
    static func literal(_ node: MathMLNode) -> String {
        func quoted(_ text: String) -> String {
            "\"" + text.unicodeScalars.map { scalar in
                switch scalar {
                case "\"": "\\\""
                case "\\": "\\\\"
                case _ where scalar.isASCII && scalar.value >= 0x20: String(scalar)
                default: "\\u{\(String(scalar.value, radix: 16))}"
                }
            }.joined() + "\""
        }
        var parts = ["name: \(quoted(node.name))"]
        if !node.attributes.isEmpty {
            parts.append("attributes: [" + node.attributes.sorted { $0.key < $1.key }.map { "\(quoted($0.key)): \(quoted($0.value))" }.joined(separator: ", ") + "]")
        }
        if !node.children.isEmpty { parts.append("children: [" + node.children.map(literal).joined(separator: ", ") + "]") }
        if !node.text.isEmpty { parts.append("text: \(quoted(node.text))") }
        return "MathMLNode(" + parts.joined(separator: ", ") + ")"
    }

    /// Every formula one step smaller than `node`: a child in its place, a child, an attribute or
    /// half its text gone, or the same of something inside it.
    static func reductions(_ node: MathMLNode) -> [MathMLNode] {
        var result = node.children
        for index in node.children.indices { var copy = node; copy.children.remove(at: index); result.append(copy) }
        for key in node.attributes.keys.sorted() { var copy = node; copy.attributes[key] = nil; result.append(copy) }
        if node.text.count > 1 {
            var copy = node
            copy.text = String(node.text.prefix(node.text.count / 2)); result.append(copy)
            copy.text = String(node.text.suffix(node.text.count / 2)); result.append(copy)
        }
        for index in node.children.indices {
            for reduced in reductions(node.children[index]) { var copy = node; copy.children[index] = reduced; result.append(copy) }
        }
        return result
    }

    /// The smallest formula found that still fails, by taking any step smaller that does.
    static func shrunk(_ root: MathMLNode, fails: (MathMLNode) -> Bool) -> MathMLNode {
        var current = root
        var tries = 0
        while tries < 1500, let smaller = reductions(current).first(where: { tries += 1; return tries < 1500 && fails($0) }) {
            current = smaller
        }
        return current
    }

    // MARK: Runs

    static func formula(seed: UInt64) -> (root: MathMLNode, style: MathStyle, widths: [(CGFloat, CGFloat?)]) {
        var random = Random(seed: seed)
        var generator = Generator(random: random, budget: random.chance(5) ? 400 : 8 + random.below(70))
        let root = generator.formula()
        random = generator.random
        let style = style(random.pick([1, 9, 17, 20, 20, 40, 9, 17, 20, 0, -3, 2000, .nan, .infinity]), display: random.chance(30))
        let natural = (try? LayoutEngine.lines(root, style: style, maximumWidth: .infinity, firstRowMaximumWidth: nil))?.width ?? 200
        let hostile: [CGFloat] = [0, -1, .nan, -.infinity, 1e-300, 1e300, .greatestFiniteMagnitude, .leastNonzeroMagnitude, 0.001, 1, 5]
        var widths: [(CGFloat, CGFloat?)] = [(.infinity, nil)]
        for width in [natural * 0.7, natural * 0.35, random.pick(hostile), CGFloat(random.below(Int(min(natural, 4000)) + 2))] {
            let firsts: [CGFloat?] = [nil, nil, nil, width / 2, natural / 5, 0, .infinity, .nan, -1, 1e-300, 1e300, natural * 2]
            widths.append((width, random.pick(firsts)))
        }
        if random.chance(20) { widths.append((.infinity, random.pick([natural / 3, 0, .nan, 10]))) }
        return (root, style, widths)
    }

    /// Runs one seed and returns its failures; with `shrinks`, each with the smallest formula that shows it.
    static func failures(seed: UInt64, shrinks: Bool) -> [String] {
        let (root, style, widths) = formula(seed: seed)
        var result: [String] = []
        for (width, first) in widths {
            let found = violations(root, style: style, width: width, first: first)
            guard let name = found.first?.split(separator: ":").first.map(String.init) else { continue }
            let place = "seed \(seed) size \(style.fontSize) display \(style.isDisplay) width \(width) first \(first.map { "\($0)" } ?? "nil")"
            guard shrinks else { result.append("\(place): \(found.joined(separator: "; "))"); continue }
            let small = shrunk(root) { candidate in
                violations(candidate, style: style, width: width, first: first).contains { $0.hasPrefix(name) }
            }
            let now = violations(small, style: style, width: width, first: first)
            result.append("\(place): \(now.joined(separator: "; "))\n  \(literal(small))")
        }
        return result
    }

    // MARK: Drawing

    /// What `draw` inks on a `width` × `height` point canvas at 2x: its pixels, and their bounds in
    /// points from the canvas's bottom-left corner.
    ///
    /// Glyphs are drawn where they are laid out, which a bitmap context does not do unasked: it
    /// moves each to the whole pixel on its left and thickens it, and a glyph that starts at its
    /// row's edge is then drawn up to two pixels outside it. That is the context's doing and the
    /// same for any text, so it is turned off here to measure the layout's.
    static func bitmap(width: CGFloat, height: CGFloat, _ draw: (CGContext) -> Void) -> (pixels: [UInt8], ink: CGRect?) {
        let scale: CGFloat = 2
        let columns = max(Int((width * scale).rounded(.up)), 1), rows = max(Int((height * scale).rounded(.up)), 1)
        let context = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: columns * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: scale, y: scale)
        context.setShouldSubpixelQuantizeFonts(false)
        context.setShouldSmoothFonts(false)
        draw(context)
        let pixels = Array(UnsafeBufferPointer(start: context.data!.bindMemory(to: UInt8.self, capacity: columns * rows * 4),
                                               count: columns * rows * 4))
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { alpha in
            for y in 0..<rows {
                let base = y * columns * 4 + 3
                for x in 0..<columns where alpha[base + x * 4] > 24 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= 0 else { return (pixels, nil) }
        // The bitmap's rows run down.
        return (pixels, CGRect(x: CGFloat(minX) / scale, y: CGFloat(rows - 1 - maxY) / scale, width: CGFloat(maxX - minX + 1) / scale,
                               height: CGFloat(maxY - minY + 1) / scale))
    }

    /// Draws a seed's formula as a host does, each row alone and all of them together, and returns
    /// what is wrong: a row whose ink leaves its box, or a layout that is not its rows at their origins.
    static func drawingFailures(seed: UInt64) -> [String] {
        let (root, style, widths) = formula(seed: seed)
        var result: [String] = []
        let margin: CGFloat = 6
        for (width, first) in widths.prefix(3) {
            // Canvases a test can afford: most formulas, at the sizes a book has.
            guard let layout = try? MathLayout(root, style: style, maximumWidth: width, firstRowMaximumWidth: first),
                  layout.width <= 400, layout.ascent + layout.descent <= 400 else { continue }
            let place = "seed \(seed) width \(width) first \(first.map { "\($0)" } ?? "nil")"
            for (index, row) in layout.rows.enumerated().prefix(6) {
                let box = CGRect(x: margin, y: margin, width: row.width, height: row.ascent + row.descent)
                let drawn = bitmap(width: box.width + 2 * margin, height: box.height + 2 * margin) {
                    row.draw(in: $0, baselineOrigin: CGPoint(x: margin, y: margin + row.descent))
                }
                // Within a pixel and a half: what antialiasing spreads past an outline.
                if let ink = drawn.ink, !box.insetBy(dx: -0.75, dy: -0.75).contains(ink) {
                    result.append("\(place): row \(index) draws \(ink) outside its box \(box)")
                }
            }
            let size = CGSize(width: layout.width + 2 * margin, height: layout.ascent + layout.descent + 2 * margin)
            let origin = CGPoint(x: margin, y: margin + layout.descent)
            let whole = bitmap(width: size.width, height: size.height) { layout.draw(in: $0, baselineOrigin: origin) }
            let pieces = bitmap(width: size.width, height: size.height) { context in
                for row in layout.rows {
                    row.draw(in: context, baselineOrigin: CGPoint(x: origin.x + row.origin.x, y: origin.y + row.origin.y))
                }
            }
            if whole.pixels != pieces.pixels { result.append("\(place): the layout is not its rows at their origins") }
            if let ink = whole.ink, !CGRect(origin: CGPoint(x: margin, y: margin), size: CGSize(width: layout.width, height: layout.ascent + layout.descent))
                .insetBy(dx: -0.75, dy: -0.75).contains(ink) {
                result.append("\(place): the layout draws \(ink) outside its box \(layout.width) \(layout.ascent) \(layout.descent)")
            }
        }
        return result
    }

    // MARK: Tests

    func testRandomFormulasBreakAsTheyMust() throws {
        var seeds: ClosedRange<UInt64> = 0...119
        let environment = ProcessInfo.processInfo.environment
        if let range = environment["MATHML_FUZZ_SEEDS"]?.split(separator: "-").compactMap({ UInt64($0) }), range.count == 2, range[0] <= range[1] {
            seeds = range[0]...range[1]
        }
        let trace = environment["MATHML_FUZZ_TRACE"]
        // Shrinking lays a formula out thousands of times: for the seed under study, not a sweep.
        let shrinks = environment["MATHML_FUZZ_SHRINK"] != nil || seeds.count <= 120
        var failed = 0
        var slowest: (seed: UInt64, seconds: TimeInterval) = (0, 0)
        for seed in seeds {
            if let trace { try? "\(seed)\n".write(toFile: trace, atomically: false, encoding: .utf8) }
            let start = Date()
            // Bitmaps cost what a hundred layouts do: for one seed in eight.
            for failure in Self.failures(seed: seed, shrinks: shrinks) + (seed % 8 == 0 ? Self.drawingFailures(seed: seed) : []) {
                failed += 1
                if failed <= 200 { XCTFail(failure) }
            }
            let seconds = Date().timeIntervalSince(start)
            if seconds > slowest.seconds { slowest = (seed, seconds) }
        }
        XCTAssertEqual(failed, 0, "of seeds \(seeds)")
        // A formula of a few hundred nodes at most: one that takes seconds is a blow-up.
        XCTAssertLessThan(slowest.seconds, 20, "seed \(slowest.seed)")
        if trace != nil { print("fuzz: seeds \(seeds) done, slowest seed \(slowest.seed) took \(slowest.seconds)s") }
    }

    /// Layouts share the font and its sized copies and nothing else: laid out on many threads at
    /// once, every formula is what it is alone.
    func testRandomFormulasAreTheSameOnEveryThread() {
        typealias Case = (root: MathMLNode, style: MathStyle, width: CGFloat, first: CGFloat?)
        let cases: [Case] = (0..<40 as Range<UInt64>).flatMap { seed -> [Case] in
            let formula = Self.formula(seed: seed)
            return formula.widths.prefix(3).map { (formula.root, formula.style, $0.0, $0.1) }
        }
        @Sendable func result(_ item: Case) -> [CGFloat]? {
            guard let lines = try? LayoutEngine.lines(item.root, style: item.style, maximumWidth: item.width, firstRowMaximumWidth: item.first)
            else { return nil }
            return Self.geometry(lines) + Self.marks(lines.rows.map(\.box)).flatMap { [CGFloat($0.kind), $0.y] }
        }
        let expected = cases.map(result)
        XCTAssertGreaterThan(expected.compactMap { $0 }.count, cases.count / 2)
        let same = UnsafeMutableBufferPointer<Bool>.allocate(capacity: cases.count * 4)
        defer { same.deallocate() }
        same.initialize(repeating: false)
        let flags = Flags(buffer: same)
        DispatchQueue.concurrentPerform(iterations: cases.count * 4) { index in
            flags.buffer[index] = result(cases[index % cases.count]) == expected[index % cases.count]
        }
        XCTAssertEqual(same.filter { !$0 }.count, 0)
    }

    // MARK: Regressions

    /// Runs `body` on a thread with `stack` bytes of stack, and returns what it threw.
    static func onThread(stack: Int, _ body: @escaping @Sendable () throws -> Void) -> Error? {
        final class Outcome: @unchecked Sendable { var error: Error? }
        let outcome = Outcome(), done = DispatchSemaphore(value: 0)
        let thread = Thread {
            do { try body() } catch { outcome.error = error }
            done.signal()
        }
        thread.stackSize = stack
        thread.start()
        done.wait()
        return outcome.error
    }

    /// `depth` levels of `name`, each holding the next among what else it must have.
    static func nest(_ name: String, depth: Int) -> MathMLNode {
        let x = MathMLNode(name: "mi", text: "x")
        return (0..<depth).reduce(x) { inner, _ in
            switch name {
            case "mfrac", "msup", "mroot": MathMLNode(name: name, children: [inner, x])
            case "munderover": MathMLNode(name: name, children: [inner, x, x])
            case "mtable": MathMLNode(name: name, children: [MathMLNode(name: "mtr", children: [MathMLNode(name: "mtd", children: [inner])])])
            case "mlongdiv": MathMLNode(name: name, children: [x, x, inner])
            default: MathMLNode(name: name, children: [inner])
            }
        }
    }

    /// The bound on depth counts levels, and a thread's stack is bytes: 63 levels of `munderover` were
    /// 1.7 MB unoptimized and 600 KB optimized, on a thread that has 512 KB unless it is the main one.
    /// A formula is refused when the stack is nearly spent, at whatever depth that is.
    func testDeepFormulasAreRefusedWhereTheStackIsShort() {
        let style = Self.style(17, display: true)
        for name in ["mrow", "msqrt", "mfrac", "munderover", "menclose", "mtable", "mlongdiv"] {
            // As deep as the bound allows: a table is three levels, a long division two.
            let deep = Self.nest(name, depth: name == "mtable" ? 20 : name == "mlongdiv" ? 30 : 62)
            XCTAssertNil(Self.onThread(stack: 16 << 20) { _ = try MathLayout(deep, style: style, maximumWidth: 200) }, name)
            // No build lays that many levels out in a quarter of a megabyte.
            XCTAssertEqual(Self.onThread(stack: 256 << 10) { _ = try MathLayout(deep, style: style, maximumWidth: 200) } as? MathLayoutError,
                           .limitExceeded, name)
            // Whatever the stack, down to the least a thread may have: a layout or a refusal.
            for kilobytes in [16, 96, 144, 192, 384, 512, 1024] {
                let error = Self.onThread(stack: kilobytes << 10) { _ = try MathLayout(deep, style: style) }
                XCTAssertTrue(error == nil || error as? MathLayoutError == .limitExceeded, "\(name) \(kilobytes)")
            }
            // What formulas are, a few levels deep, lays out on the thread a host is likely to use.
            let shallow = Self.nest(name, depth: 6)
            XCTAssertNil(Self.onThread(stack: 512 << 10) { _ = try MathLayout(shallow, style: style, maximumWidth: 200) }, name)
            // The reading recurses as layout does, and leaves out what the stack has no room for.
            let reading = deep.accessibilityDescription
            XCTAssertNil(Self.onThread(stack: 16 << 20) { XCTAssertEqual(deep.accessibilityDescription, reading) })
            for kilobytes in [16, 256, 512] { XCTAssertNil(Self.onThread(stack: kilobytes << 10) { _ = deep.accessibilityDescription }) }
        }
        // What looks ahead of layout (is this child space-like, is it text, an embellished operator?)
        // walks trees deeper than layout will go, from every level: with no stack of its own to spend.
        let text = (0..<200).reduce(MathMLNode(name: "mtext", text: "a")) { inner, _ in MathMLNode(name: "mrow", children: [inner]) }
        let ahead = (0..<60).reduce(MathMLNode(name: "mi", text: "x")) { inner, _ in
            MathMLNode(name: "mrow", children: [inner, MathMLNode(name: "mo", text: "+"), text])
        }
        for kilobytes in stride(from: 16, through: 2048, by: 112) {
            XCTAssertEqual(Self.onThread(stack: kilobytes << 10) { _ = try MathLayout(ahead, style: style) } as? MathLayoutError, .limitExceeded)
        }
    }

    /// A row lays out its stretchy operators last, to the height of the rest, and looked for each
    /// child among them: unoptimized, a row of ten thousand fences took twenty times what a sum of
    /// as many terms does.
    func testARowOfFencesTakesWhatASumDoes() throws {
        func seconds(_ symbol: String) throws -> TimeInterval {
            let row = MathMLNode(name: "math", children: (0..<6_666).flatMap { _ in
                [MathMLNode(name: "mo", text: symbol), MathMLNode(name: "mi", text: "x")]
            })
            let start = Date()
            XCTAssertEqual(try MathLayout(row, style: Self.style(2)).rows.count, 1)
            return Date().timeIntervalSince(start)
        }
        // Once for the fonts, then against each other: a ratio, whatever the machine.
        _ = try seconds("+")
        let sum = try seconds("+")
        for symbol in ["|", "(", "↑"] { XCTAssertLessThan(try seconds(symbol), sum * 5 + 0.25, symbol) }
    }

    /// `scriptlevel` and `selection` are numbers an author writes, the ends of `Int` among them: a
    /// level added to the level it is in, and a selection that 1 was subtracted from, overflowed.
    func testIntegersAtTheEndsOfIntAreNumbersLikeAnyOther() throws {
        let width = { (body: String) in try self.layout(body).width }
        for (level, same) in [("+9223372036854775807", "+24"), ("-9223372036854775808", "-24"), ("9223372036854775807", "16"),
                              ("+9223372036854775806", "+30"), ("-9223372036854775807", "-30")] {
            // In a script, and under an `mstyle` that has moved the level the other way.
            let body = { (value: String) in
                "<msup><mi>x</mi><mn scriptlevel='\(value)'>2</mn></msup><mstyle scriptlevel='-1'><mstyle scriptlevel='\(value)'><mi>y</mi></mstyle></mstyle>"
            }
            XCTAssertEqual(try width(body(level)), try width(body(same)), level)
        }
        // A level stops at either end, from wherever it was.
        XCTAssertEqual(try width("<mstyle scriptlevel='+3'><mstyle scriptlevel='-9223372036854775808'><mi>y</mi></mstyle></mstyle>"),
                       try width("<mstyle scriptlevel='-8'><mi>y</mi></mstyle>"))
        // A selection that is no child's shows the first, as it did.
        let first = try width("<mn>1</mn>"), second = try width("<mn>22</mn>")
        for selection in ["-9223372036854775808", "9223372036854775807", "0", "-1", "3", "x"] {
            XCTAssertEqual(try width("<maction selection='\(selection)'><mn>1</mn><mn>22</mn></maction>"), first, selection)
        }
        XCTAssertEqual(try width("<maction selection='2'><mn>1</mn><mn>22</mn></maction>"), second)
        XCTAssertEqual(try width("<maction selection=' 1 '><mn>1</mn><mn>22</mn></maction>"), first)
    }

    /// A table's rule is as thick as the table's own font is large, and its lines as long as its
    /// content is wide, which markup sets apart: dashed as they were laid out, the lines of this table
    /// were 12 million dashes, which the bound on extent never saw. The context dashes them now.
    func testDashedTableLinesAreDashedAsTheyAreDrawn() throws {
        let wide = "<mstyle mathsize='1000em'><mstyle mathsize='1000em'><mspace width='1em' height='1em'/></mstyle></mstyle>"
        let hostile = "<mtable mathsize='0.001px' frame='dashed' rowlines='dashed' columnlines='dashed'><mtr><mtd>\(wide)</mtd><mtd><mn>1</mn></mtd></mtr>"
            + "<mtr><mtd><mn>1</mn></mtd><mtd><mn>1</mn></mtd></mtr></mtable>"
        func segments(_ box: MathBox) -> Int {
            box.items.reduce(0) { count, item in
                switch item {
                case .path(let path, _, _, _), .dashes(let path, _, _, _):
                    var elements = 0
                    path.applyWithBlock { _ in elements += 1 }
                    return count + elements
                case .box(let inner, _): return count + segments(inner)
                default: return count
                }
            }
        }
        let start = Date()
        let box = try LayoutEngine(fontName: nil).layoutRoot(node(hostile), style: Self.style(20))
        XCTAssertGreaterThan(box.width, 999)
        XCTAssertLessThan(segments(box), 100, "a frame, a row line and a column line")
        // Drawn, they cost what the canvas shows of them.
        let layout = try MathLayout(node(hostile), style: Self.style(20))
        _ = Self.bitmap(width: 300, height: 300) { layout.draw(in: $0, baselineOrigin: CGPoint(x: 10, y: 150)) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)

        // And they are dashes still: over the extent of solid lines, with less ink.
        func drawn(_ lines: String) throws -> (ink: CGRect?, pixels: Int) {
            let cells = "<mtr><mtd><mi>a</mi></mtd><mtd><mi>b</mi></mtd></mtr>"
            let layout = try self.layout("<mtable frame='\(lines)' rowlines='\(lines)' columnlines='\(lines)'>\(cells)\(cells)</mtable>", size: 40)
            let canvas = Self.bitmap(width: layout.width + 20, height: layout.ascent + layout.descent + 20) {
                layout.draw(in: $0, baselineOrigin: CGPoint(x: 10, y: 10 + layout.descent))
            }
            return (canvas.ink, stride(from: 3, to: canvas.pixels.count, by: 4).reduce(0) { $0 + (canvas.pixels[$1] > 128 ? 1 : 0) })
        }
        let dashed = try drawn("dashed"), solid = try drawn("solid"), bare = try drawn("none")
        let lines = solid.pixels - bare.pixels, dashes = dashed.pixels - bare.pixels
        XCTAssertGreaterThan(lines, 1_000)
        XCTAssertGreaterThan(dashes, lines / 4)
        XCTAssertLessThan(dashes, lines * 9 / 10)
        let frame = try XCTUnwrap(solid.ink), broken = try XCTUnwrap(dashed.ink)
        // Short of the frame's far corners by a gap between dashes at most.
        for (whole, part) in [(frame.minX, broken.minX), (frame.maxX, broken.maxX), (frame.minY, broken.minY), (frame.maxY, broken.maxY)] {
            XCTAssertEqual(whole, part, accuracy: 6)
        }
    }

    /// `.greatestFiniteMagnitude` is how a host says a line has no end as often as `.infinity` is. It
    /// was taken as a width: a row centred in it or indented by a share of it was placed past the
    /// bound on extent, and the formula refused.
    func testALineWiderThanAnyFormulaIsNoLimit() throws {
        let terms = "<mi>alpha</mi><mo>=</mo><mi>beta</mi><mo linebreak='newline'>+</mo><mi>gamma</mi>"
        for attributes in ["", "indentalign='center'", "indentalign='right'", "indentshift='10%'", "indentalign='center' indentshift='-5%'",
                           "indentshift='99999%' lineleading='200%'"] {
            let root = try node("<mstyle \(attributes)>\(terms)</mstyle><mo>+</mo><menclose notation='circle'>\(terms)</menclose>", display: true)
            let style = Self.style(20, display: true)
            let endless = try MathLayout(root, style: style)
            XCTAssertEqual(endless.rows.count, 2, attributes)
            for width in [CGFloat.greatestFiniteMagnitude, 1e300, 1e9, MathLimits.extent + 1] {
                for first in [nil, width, 1e12] as [CGFloat?] {
                    let layout = try MathLayout(root, style: style, maximumWidth: width, firstRowMaximumWidth: first)
                    XCTAssertEqual(layout.rows.map(\.origin), endless.rows.map(\.origin), "\(attributes) \(width)")
                    XCTAssertEqual(layout.rows.map(\.width), endless.rows.map(\.width), "\(attributes) \(width)")
                    XCTAssertEqual([layout.width, layout.ascent, layout.descent], [endless.width, endless.ascent, endless.descent])
                }
            }
            // The first row's width is its own: unbounded where the line is not.
            let narrow = try MathLayout(root, style: style, maximumWidth: 60, firstRowMaximumWidth: .greatestFiniteMagnitude)
            XCTAssertEqual(narrow.rows[0].width, endless.rows[0].width, attributes)
        }
    }

    /// A font size that is no number is a host's mistake, and was every measure of the formula: an
    /// axis height that is no number, a formula half a point wide.
    func testAFontSizeThatIsNoNumberIsTheSmallest() throws {
        let root = try node("<mi>x</mi><mo>+</mo><mfrac><mn>1</mn><msqrt><mi>y</mi></msqrt></mfrac><mtext>some words</mtext>")
        func measures(_ size: CGFloat, width: CGFloat = .infinity) throws -> [CGFloat] {
            let layout = try MathLayout(root, style: Self.style(size), maximumWidth: width)
            return [layout.width, layout.ascent, layout.descent, layout.axisHeight, layout.widestUnbreakableWidth, CGFloat(layout.rows.count)]
        }
        for width in [CGFloat.infinity, 4] {
            let least = try measures(1, width: width)
            XCTAssertTrue(least.allSatisfy { $0.isFinite && $0 > 0 })
            for size in [CGFloat.nan, -.nan, .signalingNaN, 0, -5, -.infinity, .leastNonzeroMagnitude] {
                XCTAssertEqual(try measures(size, width: width), least, "\(size)")
            }
            for size in [CGFloat.infinity, 1e300, .greatestFiniteMagnitude] {
                XCTAssertEqual(try measures(size, width: width), try measures(1000, width: width), "\(size)")
            }
        }
    }

    /// `widestUnbreakableWidth` is the width a host scales a formula to when a row overflows. Things
    /// that wrap side by side, with no operator to break at between them, are one stretch, and each
    /// wrapped to the line as if it were alone: three radicals overflowed a line that was room for
    /// all of them wrapped, and at the width that layout asked for they were laid out wider and
    /// overflowed again, by as much as that width twice over.
    func testAFormulaFitsTheWidthItSaysItNeeds() throws {
        let sum = (1...10).map { "<mi>term\($0)</mi>" }.joined(separator: "<mo>+</mo>")
        let fraction = "<mfrac><mrow>\(sum)</mrow><mn>2</mn></mfrac>"
        let bodies = ["<msqrt>\(sum)</msqrt><msqrt>\(sum)</msqrt><msqrt>\(sum)</msqrt>", fraction + fraction,
                      "<mfenced>\(fraction)</mfenced><mfenced>\(fraction)</mfenced>"]
        let style = Self.style(20, display: true)
        for body in bodies {
            let root = try node("<mi>y</mi><mo>=</mo>" + body, display: true)
            let natural = try MathLayout(root, style: style).width
            var overflowed = 0
            for divisor in [1.5, 2, 3, 5, 8, 13, 30, 100] as [CGFloat] {
                let limit = natural / divisor
                let narrow = try MathLayout(root, style: style, maximumWidth: limit)
                let needed = narrow.widestUnbreakableWidth
                for row in narrow.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, max(limit, needed) + 0.01, "\(divisor) \(body)") }
                if needed > limit { overflowed += 1 }
                // At the width it says it needs, it needs no more.
                let exact = try MathLayout(root, style: style, maximumWidth: needed)
                for row in exact.rows { XCTAssertLessThanOrEqual(row.origin.x + row.width, needed + 0.01, "\(divisor) \(body)") }
                XCTAssertLessThanOrEqual(exact.widestUnbreakableWidth, needed + 0.01, "\(divisor) \(body)")
            }
            XCTAssertGreaterThan(overflowed, 1, "lines too narrow however it wraps")
            // A line with room for it wrapped holds it, and wrapped not much further than that: over
            // half the line, where each term on a line of its own would be a fifth of it.
            for share in [0.75, 0.5, 0.34] as [CGFloat] {
                let fitted = try MathLayout(root, style: style, maximumWidth: natural * share)
                XCTAssertLessThanOrEqual(fitted.widestUnbreakableWidth, natural * share + 0.01, "\(share) \(body)")
                XCTAssertGreaterThan(fitted.rows.map(\.width).max()!, natural * share * 0.55, "\(share) \(body)")
            }
        }
    }
}

private struct Flags: @unchecked Sendable {
    let buffer: UnsafeMutableBufferPointer<Bool>
}
