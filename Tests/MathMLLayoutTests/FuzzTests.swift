import CoreGraphics
import Foundation
@testable import MathMLLayout
import XCTest

/// A seeded generator of hostile `MathMLNode` trees: every element the engine knows and some it
/// does not, nested in any order, with absurd attribute values, odd text and U+FFFC anywhere.
/// Trees are built directly, as a host would from its own DOM, so they include shapes the XML
/// parser cannot produce (tokens with any children, text on any element).
struct MathFuzzer {
    private var state: UInt64
    /// Nodes this tree may still add.
    private var budget = 0

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xD1B5_4A32_D192_ED03 }

    /// SplitMix64: the same trees for the same seed on every machine and Swift version.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(max(bound, 1))) }
    mutating func chance(_ percent: Int) -> Bool { below(100) < percent }
    mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }

    static let elementary = ["mstack", "mlongdiv", "msgroup", "msrow", "mscarries", "mscarry", "msline", "none"]
    static let tokens = ["mn", "mn", "mn", "mi", "mo", "mo", "mtext", "ms"]
    static let others = [
        "mglyph", "mglyph", "mrow", "mstyle", "mstyle", "mfrac", "msqrt", "mroot", "msub", "msup", "msubsup", "munder",
        "mover", "munderover", "mmultiscripts", "mprescripts", "mtable", "mtr", "mtd", "mlabeledtr", "mpadded",
        "mphantom", "menclose", "mfenced", "semantics", "annotation", "annotation-xml", "maction", "merror", "mspace",
        "math", "malignmark", "maligngroup",
    ]
    static let garbage = ["", "MSTACK", "foo", "m:mn", " mn", "\u{FFFC}", "mstack "]
    /// How many children an element is usually given, where the engine checks.
    static let arity = ["mfrac": 2, "mroot": 2, "msub": 2, "msup": 2, "msubsup": 3, "munder": 2, "mover": 2, "munderover": 3]

    static let integers = [
        "0", "1", "-1", "2", "-2", "3", "5", "-7", "19", "100", "-100", "20000", "-20000", "19999", "20001", "2147483647",
        "-2147483648", "2147483648", "-2147483649", "4294967296", "9223372036854775807", "-9223372036854775808",
        "9223372036854775808", "99999999999999999999", "-99999999999999999999", "+3", "1.5", "1e3", " 4 ", "", "x",
        "0x10", "\u{0663}", "nan", "inf", "-0", "+", "-", "００３", "+9223372036854775807", "-9223372036854775807",
    ]
    static let lengths = [
        "0", "1", "-1", "1em", "-1em", "0.5ex", "10px", "3pt", "1e308", "1e308em", "nan", "inf", "infinity", "-inf",
        "99999999999999999999em", "-99999999999999999999em", "1e9em", "999999999em", "1000000%", "-1000000%", "50%",
        "200%", ".", "..", "1..2em", "1.em", ".5em", "em", "", " ", "thin", "medium", "thick", "loose", "tight", "+5em",
        "-5em", "+", "-", "0.0000001pt", "5 em", "100width", "-100height", "2depth", "1e-320em", "veryverythickmathspace",
        "negativeveryverythickmathspace", "1in", "1000cm", "0.000000000000000000000000000001em", "small", "normal", "big",
        "999999999999999999999999999999999999999999999999999999999999999",
        "179769313486231570000000000000000000000000000000000000000000em",
    ]
    static let colors = ["red", "#fff", "#12345678", "transparent", "#gggggg", "", "#", "#1234567890", "#f00f", "BLUE"]
    static let booleans = ["true", "false", "TRUE", "", "1", " true "]
    static let keywords: [String: [String]] = [
        "longdivstyle": [
            "lefttop", "stackedrightright", "mediumstackedrightright", "shortstackedrightright", "righttop",
            "left/\\right", "left)(right", ":right=right", "stackedleftleft", "stackedleftlinetop", "mediumrightright",
            "", "LEFTTOP", " righttop ", "left/right", "x",
        ],
        "location": ["w", "nw", "n", "ne", "e", "se", "s", "sw", "", "x", "N", " s "],
        "crossout": [
            "none", "updiagonalstrike", "downdiagonalstrike", "verticalstrike", "horizontalstrike",
            "updiagonalstrike downdiagonalstrike verticalstrike horizontalstrike", "none updiagonalstrike", "", "x", "  ",
            "UPDIAGONALSTRIKE\tverticalstrike",
        ],
        "stackalign": ["left", "center", "right", "decimalpoint", "", "x", "LEFT"],
        "charalign": ["left", "center", "right", "", "x"],
        "align": [
            "top", "bottom", "center", "baseline", "axis", "top 1", "bottom -1", "center 2", "baseline 0", "axis 3",
            "top 9223372036854775807", "bottom -9223372036854775808", "center 99999999999999999999", "top -2", "x 1", "",
            " ", "top x", "1", "-1 top", "top 1 2", "axis -1", "baseline 2", "bottom 20000",
        ],
        "decimalpoint": [".", ",", "", " ", "\u{066B}", "1", "ab", "\u{FFFC}", "7"],
        "scriptsizemultiplier": ["0.6", "10", "0.11", "0.1", "0", "-1", "1e308", "nan", "inf", "10.0000001", "1", "", "x"],
        "mathvariant": ["bold", "italic", "double-struck", "fraktur", "normal", "bold-italic", "monospace", "x", ""],
        "src": ["one", "small", "wide", "tall", "nil", "", "other", "big"],
        "alt": ["", "alt", "x\u{FFFC}y", " ", "a  b\n", "\u{FFFC}", String(repeating: "w", count: 200), "1"],
        "notation": [
            "longdiv", "box", "roundedbox", "circle", "left right top bottom", "updiagonalstrike downdiagonalstrike",
            "verticalstrike horizontalstrike", "actuarial", "radical", "madruwb", "phasorangle", "", "x",
        ],
        "open": ["(", "", "[", "\u{FFFC}", "((("], "close": [")", "", "]", "|"], "separators": [",", "", ";,", " ", "\u{FFFC}"],
        "lquote": ["\u{FFFC}", "", "\u{AB}"], "rquote": ["\u{FFFC}", "", "\u{BB}"],
        "form": ["prefix", "infix", "postfix", ""], "display": ["block", "inline", ""],
        "columnalign": ["left", "center right", "", "x"], "rowalign": ["top", "bottom axis", "baseline", ""],
        "frame": ["solid", "dashed", "none"], "rowlines": ["solid", "dashed none"], "columnlines": ["solid", "none dashed"],
        "side": ["left", "right", "leftoverlap"], "bevelled": ["true", "false"],
        "numalign": ["left", "right"], "denomalign": ["left", "right"],
        "fontweight": ["bold", "normal"], "fontstyle": ["italic", "normal"],
    ]
    static let integerNames = ["position", "position", "shift", "shift", "length", "length", "selection", "scriptlevel", "rowspan", "columnspan"]
    static let lengthNames = [
        "charspacing", "leftoverhang", "rightoverhang", "mslinethickness", "width", "height", "depth", "valign",
        "mathsize", "fontsize", "lspace", "rspace", "scriptminsize", "linethickness", "voffset", "rowspacing",
        "columnspacing", "minsize", "maxsize",
    ]
    static let colorNames = ["mathbackground", "mathcolor", "color"]
    static let booleanNames = [
        "displaystyle", "stretchy", "symmetric", "largeop", "movablelimits", "accent", "accentunder", "fence", "separator",
        "equalrows", "equalcolumns",
    ]
    static let texts = [
        "", "0", "1", "7", "12", "345", "1,234", "3.14", "2,327", " 1 156 ", "\u{0663}\u{066B}\u{0661}\u{0664}", "0.5", ".", ",",
        "..", "1.2.3", "-", "+", "\u{D7}", "\u{F7}", "=", "\u{2212}", "(", ")", "\u{2211}", "\u{222B}", "x", "sin", "\u{FFFC}",
        "\u{FFFC}\u{FFFC}\u{FFFC}", "a\u{FFFC}b", "1\u{FFFC}2.\u{FFFC}", " \u{FFFC} ", "\u{2061}", "\u{2062}", "e\u{301}",
        "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", "\u{1F1EB}\u{1F1F7}", "\u{0}", "\t\n\r ", "  7  ", "\u{5D0}\u{5D1}",
        "\u{661}\u{662}\u{663}", "\u{200B}", "\u{202E}abc", "\u{FE0F}", "\u{0301}", "\u{1D7D8}", "A\u{0308}\u{0301}\u{0327}",
        "\u{FFFD}", "'", "\u{E000}", "\u{10FFFF}", "1 000 000", "9\u{FFFC}", "\u{FFFC}.", "|", "\u{2192}", "\u{23DE}", "^",
        String(repeating: "9", count: 40), String(repeating: "1.", count: 30),
    ]

    mutating func attributes(for name: String) -> [String: String] {
        var result: [String: String] = [:]
        // What an element reads, most of the time; anything at all, sometimes.
        let likely: [String] = switch name {
        case "mstack", "mlongdiv": ["align", "stackalign", "charalign", "charspacing", "longdivstyle", "decimalpoint"]
        case "msgroup": ["position", "shift"]
        case "msrow": ["position"]
        case "mscarries": ["position", "location", "crossout", "scriptsizemultiplier"]
        case "mscarry": ["location", "crossout"]
        case "msline": ["position", "length", "leftoverhang", "rightoverhang", "mslinethickness"]
        case "mglyph": ["src", "src", "alt", "width", "height", "valign", "mathbackground"]
        case "mstyle": ["decimalpoint", "scriptsizemultiplier", "scriptlevel", "mathsize", "scriptminsize"]
        case "maction": ["selection"]
        case "mtable": ["align", "rowspacing", "columnspacing", "columnalign", "rowalign", "frame", "rowlines", "columnlines",
                        "equalrows", "equalcolumns", "width", "side"]
        case "mtr", "mlabeledtr", "mtd": ["rowspan", "columnspan", "rowalign", "columnalign"]
        case "mo": ["form", "stretchy", "symmetric", "largeop", "movablelimits", "accent", "fence", "separator", "lspace",
                    "rspace", "minsize", "maxsize"]
        case "mfrac": ["linethickness", "bevelled", "numalign", "denomalign"]
        case "mpadded": ["width", "height", "depth", "lspace", "voffset"]
        case "mspace": ["width", "height", "depth"]
        case "menclose": ["notation"]
        case "mfenced": ["open", "close", "separators"]
        case "munder", "mover", "munderover": ["accent", "accentunder", "align"]
        case "ms": ["lquote", "rquote"]
        default: []
        }
        for _ in 0..<below(4) {
            let all = Self.integerNames + Self.lengthNames + Self.colorNames + Self.booleanNames + Array(Self.keywords.keys).sorted()
            let attribute = !likely.isEmpty && chance(75) ? pick(likely) : pick(all)
            if chance(4) {
                result[attribute] = pick(Self.integers + Self.lengths + Self.texts)
            } else if let values = Self.keywords[attribute] {
                result[attribute] = pick(values)
            } else if Self.integerNames.contains(attribute) {
                result[attribute] = chance(60) ? String(below(9) - 4) : pick(Self.integers)
            } else if Self.lengthNames.contains(attribute) {
                result[attribute] = pick(Self.lengths)
            } else if Self.colorNames.contains(attribute) {
                result[attribute] = pick(Self.colors)
            } else {
                result[attribute] = pick(Self.booleans)
            }
        }
        return result
    }

    mutating func name(inStack: Bool) -> String {
        let roll = below(200)
        if roll == 0 { return pick(Self.garbage) }
        if roll < (inStack ? 110 : 60) { return pick(Self.elementary) }
        if roll < 165 { return pick(Self.tokens) }
        return pick(Self.others)
    }

    mutating func node(_ name: String, depth: Int, maxDepth: Int) -> MathMLNode {
        budget -= 1
        var node = MathMLNode(name: name, attributes: attributes(for: name))
        let isToken = Self.tokens.contains(name)
        if isToken || chance(3) { node.text = pick(Self.texts) }
        guard depth < maxDepth, budget > 0 else { return node }
        var count: Int
        if isToken || name == "mglyph" || name == "none" || name == "msline" || name == "mspace" {
            // These have no element children, apart from a token's `mglyph`s. A host's tree may.
            count = chance(isToken ? 25 : 6) ? 1 + below(3) : 0
        } else if let fixed = Self.arity[name], chance(92) {
            count = fixed
        } else if chance(2) {
            count = 40 + below(160)
        } else {
            count = [0, 1, 1, 2, 2, 2, 3, 3, 4, 5, 7][below(11)]
            if name == "mlongdiv", chance(92) { count = max(count, 2 + below(3)) }
        }
        let inStack = Self.elementary.contains(name)
        while count > 0, budget > 0 {
            count -= 1
            let child = isToken && chance(80) ? "mglyph" : self.name(inStack: inStack)
            node.children.append(self.node(child, depth: depth + 1, maxDepth: maxDepth))
        }
        return node
    }

    /// One tree. Most are small and shallow, so that layout gets past its first error; a few are
    /// wide, and a few nest past the engine's depth bound.
    mutating func tree() -> MathMLNode {
        budget = [12, 30, 60, 60, 120, 250][below(6)]
        let maxDepth = chance(3) ? 70 : 3 + below(7)
        let root = chance(70) ? pick(["mstack", "mlongdiv", "mstack", "mlongdiv", "msgroup", "msrow", "mscarries"]) : "math"
        var tree = node(root, depth: 0, maxDepth: maxDepth)
        if maxDepth == 70 {
            // A chain to the bottom: random trees seldom reach the bound on their own.
            for _ in 0..<(40 + below(40)) {
                let wrapper = pick(["mstack", "msrow", "msgroup", "mscarries", "mscarry", "mlongdiv", "mstyle", "mrow", "mn", "msqrt"])
                var children = [tree]
                if wrapper == "mlongdiv" { children = [MathMLNode(name: "mn", text: "3"), MathMLNode(name: "none"), tree] }
                tree = MathMLNode(name: wrapper, attributes: attributes(for: wrapper), children: children)
            }
        }
        return chance(50) ? MathMLNode(name: "math", children: [tree]) : tree
    }
}

/// Layout, drawing and speech must return for any tree: no trap, no hang, bounded results.
final class FuzzTests: MathTestCase {
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private func bitmap(_ width: Int, _ height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private func image(_ width: Int, _ height: Int) -> CGImage {
        let context = bitmap(width, height)
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private lazy var images: MathImageProvider = {
        let images = ["one": image(1, 1), "small": image(16, 8), "wide": image(2000, 1), "tall": image(1, 2000),
                      "other": image(3, 5), "big": image(600, 400)]
        return MathImageProvider { images[$0] }
    }()

    private lazy var canvas = bitmap(64, 64)
    private let locales = ["en", "fr-CA", "de", "es-MX", "it", "ja"].map(Locale.init(identifier:))

    /// How much a host handed over: speech and layout may not do work out of proportion to it.
    private func size(of node: MathMLNode) -> Int {
        var total = 0, pending = [node]
        while let next = pending.popLast() {
            total += 1 + next.text.utf8.count + next.attributes.reduce(0) { $0 + $1.key.utf8.count + $1.value.utf8.count }
            pending.append(contentsOf: next.children)
        }
        return total
    }

    private func xml(_ node: MathMLNode) -> String {
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }
        var result = "<\(node.name)"
        for (key, value) in node.attributes.sorted(by: { $0.key < $1.key }) { result += " \(key)=\"\(escaped(value))\"" }
        result += ">"
        // An `mglyph` goes where its marker is, as the parser reads it back.
        var glyphs = node.children.filter { $0.name == "mglyph" }[...]
        for scalar in node.text.unicodeScalars {
            if scalar == "\u{FFFC}", let glyph = glyphs.popFirst() { result += xml(glyph) } else { result += escaped(String(scalar)) }
        }
        for child in node.children where child.name != "mglyph" { result += xml(child) }
        for glyph in glyphs { result += xml(glyph) }
        return result + "</\(node.name)>"
    }

    /// Lays out, draws and reads one tree, and checks what must hold of any result. Returns
    /// whether layout succeeded.
    @discardableResult
    private func exercise(_ tree: MathMLNode, style: MathStyle, _ label: String, file: StaticString = #filePath,
                          line: UInt = #line) -> Bool {
        var succeeded = false
        do {
            let layout = try MathLayout(tree, style: style)
            succeeded = true
            for extent in [layout.width, layout.ascent, layout.descent] {
                XCTAssert(extent.isFinite && extent >= 0 && extent <= MathLimits.extent, "\(label): extent \(extent)",
                          file: file, line: line)
            }
            layout.draw(in: canvas, baselineOrigin: CGPoint(x: 4, y: 24))
        } catch let error as MathLayoutError {
            if case .unsupported = error {} else if case .invalidMarkup = error {} else {
                XCTAssertEqual(error, .limitExceeded, label, file: file, line: line)
            }
        } catch {
            XCTFail("\(label): \(error)", file: file, line: line)
        }
        // A reading says each node at most once, in a few words.
        let bound = 200 * (size(of: tree) + 1)
        for locale in locales {
            let reading = tree.accessibilityDescription(locale: locale)
            XCTAssertLessThanOrEqual(reading.text.utf8.count, bound, "\(label): \(locale.identifier) reading", file: file, line: line)
        }
        return succeeded
    }

    private func run(seeds: Range<UInt64>, trace: Bool = false) -> (laidOut: Int, slowest: (seed: UInt64, seconds: Double)) {
        var laidOut = 0, slowest: (seed: UInt64, seconds: Double) = (0, 0)
        for seed in seeds {
            if trace { FileHandle.standardError.write(Data("seed \(seed)\n".utf8)) }
            var fuzzer = MathFuzzer(seed: seed)
            let tree = fuzzer.tree()
            let fontSize: CGFloat = fuzzer.chance(80) ? 20 : fuzzer.pick([1, 0.5, 7, 100, 1000, 0, -3])
            let style = MathStyle(fontSize: fontSize, color: black, isDisplay: fuzzer.chance(30),
                                  imageProvider: fuzzer.chance(70) ? images : nil)
            let start = Date()
            if exercise(tree, style: style, "seed \(seed)") { laidOut += 1 }
            // The same markup through the parser, which drops what XML cannot say: whole, then
            // damaged (cut short, with bytes changed, or in UTF-16), which it mostly refuses.
            if seed % 4 == 0 {
                let markup = xml(tree)
                var damaged = Data(markup.utf8)
                switch fuzzer.below(3) {
                case 0: damaged = damaged.prefix(fuzzer.below(damaged.count))
                case 1: for _ in 0...fuzzer.below(3) { damaged[fuzzer.below(damaged.count)] = UInt8(truncatingIfNeeded: fuzzer.next()) }
                default: damaged = markup.data(using: fuzzer.chance(50) ? .utf16 : .utf16BigEndian) ?? damaged
                }
                for (data, label) in [(Data(markup.utf8), "parsed"), (damaged, "damaged")] {
                    if let parsed = try? MathMLNode.parse(xml: data) { exercise(parsed, style: style, "seed \(seed) \(label)") }
                }
            }
            let seconds = Date().timeIntervalSince(start)
            if seconds > slowest.seconds { slowest = (seed, seconds) }
        }
        return (laidOut, slowest)
    }

    /// The regression guard: a fixed range of seeds and bounded layout/speech output.
    ///
    /// For hunting, `FUZZ_SEEDS=start:count` runs that range instead, and `FUZZ_TRACE=1` names each
    /// seed on stderr before it runs, so the last line before a crash is the seed that crashed.
    func testRandomTreesNeitherTrapNorHang() {
        let environment = ProcessInfo.processInfo.environment
        let asked = (environment["FUZZ_SEEDS"] ?? "").split(separator: ":").compactMap { UInt64($0) }
        let seeds: Range<UInt64> = asked.count == 2 ? asked[0]..<(asked[0] + asked[1]) : 0..<400
        let result = run(seeds: seeds, trace: environment["FUZZ_TRACE"] != nil)
        print("FUZZ \(seeds): laid out \(result.laidOut); slowest seed \(result.slowest.seed) \(result.slowest.seconds)s")
        // Enough of the trees must get through layout for this to test more than its errors.
        if seeds.count >= 100 { XCTAssertGreaterThan(result.laidOut, seeds.count / 4) }
        // Timing names slow seeds for investigation. Complexity regressions have directed
        // same-shape CPU growth guards; these varied trees assert geometry and speech budgets.
    }

    // MARK: Directed cases

    private func n(_ name: String, _ attributes: [String: String] = [:], _ children: [MathMLNode] = [],
                   text: String = "") -> MathMLNode {
        MathMLNode(name: name, attributes: attributes, children: children, text: text)
    }

    private let one = MathMLNode(name: "mn", text: "1")

    private func assertLimit(_ tree: MathMLNode, style: MathStyle? = nil, _ label: String, file: StaticString = #filePath,
                             line: UInt = #line) {
        XCTAssertThrowsError(try MathLayout(tree, style: style ?? MathStyle(fontSize: 20, color: black)), label, file: file,
                             line: line) { XCTAssertEqual($0 as? MathLayoutError, .limitExceeded, label, file: file, line: line) }
    }

    /// The largest things a stack can be asked for, each of which must lay out within the bounds
    /// or be refused, and be read in bounded words.
    func testStacksAndGlyphsAtTheLimits() {
        let style = MathStyle(fontSize: 20, color: black, imageProvider: images), tiny = MathStyle(fontSize: 1, color: black)
        let many = Array(repeating: one, count: 19_000)
        exercise(n("mstack", [:], many), style: style, "rows")
        exercise(n("mstack", [:], [n("msrow", [:], many)]), style: tiny, "columns")
        exercise(n("mstack", [:], [n("mn", [:], [], text: String(repeating: "7", count: 19_000))]), style: tiny, "digits")
        exercise(n("mstack", [:], [n("mscarries", ["crossout": "updiagonalstrike", "location": "se"], many), one]), style: tiny,
                 "carries")
        let huge = ["2147483647", "-2147483648", "2147483648", "9223372036854775807", "-9223372036854775808", "20000"]
        for value in huge {
            for name in ["msgroup", "msrow", "mscarries", "msline"] {
                // Alone, a row far away is where every row is; beside another it is too far.
                let far = n(name, name == "msline" ? ["position": value, "length": "2"] : ["position": value], [one, one])
                XCTAssert(exercise(n("mstack", [:], [far]), style: style, "\(name) position \(value)"))
                assertLimit(n("mstack", [:], [far, one]), "\(name) position \(value) beside a row")
                assertLimit(n("mlongdiv", [:], [one, one, one, far]), "\(name) position \(value) in a division")
            }
            assertLimit(n("mstack", [:], [n("msgroup", ["shift": value], [one, one, one])]), "shift \(value)")
            if value == huge[0] { assertLimit(n("mstack", [:], [n("msgroup", ["shift": value], many)]), "shift over many rows") }
            // Shifts and positions that add up through every level of nesting.
            var nested = n("msgroup", ["shift": value, "position": value], [one, one])
            for _ in 0..<60 { nested = n("msgroup", ["shift": value, "position": value], [one, nested]) }
            assertLimit(n("mstack", [:], [nested]), "nested shift \(value)")
            // A length is unsigned: a negative one is none, and the rule runs the width of the stack.
            let ruled = n("mstack", [:], [n("msline", ["length": value]), one])
            if value.hasPrefix("-") { XCTAssert(exercise(ruled, style: tiny, "length \(value)")) } else {
                assertLimit(n("mstack", [:], [ruled, ruled]), style: tiny, "length \(value)")
            }
        }
        exercise(n("mstack", [:], [n("msline", ["length": "19000"]), one]), style: tiny, "length 19000")
        // Images: any size asked of any image, and as many as a token may hold.
        for (width, height, valign) in [("1e9em", "", ""), ("999999999em", "", ""), ("999999999em", "999999999em", "-999999999em"),
                                        ("0", "", ""), ("-5", "7", ""), ("", "0.0000001px", "999999999em"), ("1000000%", "", "")] {
            for source in ["one", "wide", "tall", "nil"] {
                let glyph = n("mglyph", ["src": source, "alt": "a", "width": width, "height": height, "valign": valign])
                exercise(n("math", [:], [n("mi", [:], [glyph], text: "x\u{FFFC}y"), glyph]), style: style, "\(source) \(width)")
            }
        }
        let glyph = n("mglyph", ["src": "one", "alt": "a"])
        for count in [19_999, 20_001] {
            let glyphs = Array(repeating: glyph, count: count)
            exercise(n("mtext", [:], glyphs), style: style, "\(count) glyphs")
            exercise(n("mtext", [:], glyphs, text: String(repeating: "\u{FFFC}", count: count)), style: tiny, "\(count) markers")
            exercise(n("math", [:], glyphs), style: style, "\(count) glyphs alone")
        }
    }

    /// The stack between `MathLayout.init` and the image provider's call for an `mglyph` at the
    /// bottom of the deepest nesting of `wrap` that lays out.
    private func stackUse(_ wrap: (MathMLNode) -> MathMLNode) -> UInt {
        final class Lowest: @unchecked Sendable { var address = UInt.max }
        let lowest = Lowest()
        let provider = MathImageProvider { _ in
            var marker = 0
            withUnsafeMutablePointer(to: &marker) { lowest.address = min(lowest.address, UInt(bitPattern: $0)) }
            return nil
        }
        let style = MathStyle(fontSize: 20, color: black, imageProvider: provider)
        let leaf = n("mtext", [:], [n("mglyph", ["src": "s", "alt": "a"])])
        for levels in stride(from: MathLimits.depth, to: 0, by: -1) {
            let tree = (0..<levels).reduce(leaf) { inner, _ in wrap(inner) }
            var marker = 0
            let top = withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
            if (try? MathLayout(tree, style: style)) != nil, lowest.address < top { return top - lowest.address }
        }
        return 0
    }

    /// `MathLimits.depth` is what bounds the stack layout uses, on threads with half a megabyte of
    /// it. A stack's children take more frames to reach than other elements', so they must count
    /// for more: nested as deep as it lays out, elementary math may use no more stack than the
    /// rest of the engine does.
    func testNestedStacksUseNoMoreStackThanOtherElements() {
        let none = n("none")
        let others: [(MathMLNode) -> MathMLNode] = [
            { self.n("munderover", [:], [$0, self.one, self.one]) }, { self.n("menclose", ["notation": "longdiv"], [$0]) },
            { self.n("mtable", [:], [self.n("mtr", [:], [self.n("mtd", [:], [$0])])]) }, { self.n("mpadded", [:], [$0]) },
            { self.n("mfrac", [:], [$0, self.one]) }, { self.n("msqrt", [:], [$0]) },
        ]
        let bound = others.map(stackUse).max()!
        XCTAssertGreaterThan(bound, 0)
        let elementary: [(String, (MathMLNode) -> MathMLNode)] = [
            ("mstack", { self.n("mstack", [:], [$0]) }),
            ("divisor", { self.n("mlongdiv", [:], [$0, none, self.one]) }),
            ("result", { self.n("mlongdiv", ["longdivstyle": "stackedrightright"], [none, $0, self.one]) }),
            ("dividend", { self.n("mlongdiv", [:], [none, none, $0]) }),
            ("msrow", { self.n("msrow", [:], [$0]) }),
            ("mstyle", { self.n("mstack", [:], [self.n("mstyle", [:], [$0])]) }),
            ("msgroup", { self.n("mstack", [:], [self.n("msgroup", [:], [$0])]) }),
            ("mscarries", { self.n("mscarries", [:], [$0]) }),
            ("mscarry", { self.n("mscarry", [:], [$0, self.one]) }),
        ]
        for (name, wrap) in elementary {
            let used = stackUse(wrap)
            XCTAssertGreaterThan(used, 0, name)
            XCTAssertLessThanOrEqual(used, bound, "\(name) nested to the depth bound")
        }
    }

    /// One stack may span as many columns as a formula may have nodes. A formula of such stacks
    /// may not: columns no cell stands in count as nodes, or 20,000 nodes would buy 200 million columns.
    func testEmptyColumnsCountAcrossStacks() {
        let tiny = MathStyle(fontSize: 1, color: black)
        let far = n("mstack", [:], [n("mscarries", ["position": "9000"], [one]), one])
        XCTAssertNoThrow(try MathLayout(n("math", ["mathsize": "0.01px"], [far, far]), style: tiny))
        assertLimit(n("math", ["mathsize": "0.01px"], Array(repeating: far, count: 200)), style: tiny, "200 stacks 9,000 columns wide")
        let ruled = n("mstack", [:], [n("msline", ["length": "9000"])])
        assertLimit(n("math", ["mathsize": "0.01px"], Array(repeating: ruled, count: 200)), style: tiny, "200 rules 9,000 columns long")
        let divided = n("mlongdiv", [:], [n("msline", ["length": "9000"]), n("msline", ["length": "9000"]), one])
        assertLimit(n("math", ["mathsize": "0.01px"], Array(repeating: divided, count: 200)), style: tiny, "200 divisions")
        // Columns that hold something are paid for already.
        let digits = n("mstack", [:], [n("mn", [:], [], text: String(repeating: "7", count: 9_000)), n("msline"),
                                       n("msline", ["length": "9000"]), n("msrow", ["position": "500"], [one])])
        XCTAssertNoThrow(try MathLayout(n("math", ["mathsize": "0.01px"], [digits, digits]), style: tiny))
    }

    /// An `mglyph` without an image is its `alt`, and a host's tree may give thousands of them
    /// one long `alt`: the token's text is bounded as it grows, not once it is all built.
    func testAltTextIsBoundedAsItGrows() {
        final class Calls: @unchecked Sendable { var count = 0 }
        let calls = Calls()
        let provider = MathImageProvider { _ in calls.count += 1; return nil }
        let alt = String(repeating: "a", count: 1_000)
        let glyphs = (0..<5_000).map { n("mglyph", ["src": "\($0)", "alt": alt]) }
        assertLimit(n("mtext", [:], glyphs), style: MathStyle(fontSize: 20, color: black, imageProvider: provider), "alt")
        XCTAssertLessThanOrEqual(calls.count, MathLimits.textLength / alt.count + 1, "glyphs looked at")
    }

    /// What a document type declares is refused in any encoding, not only where the bytes spell
    /// "<!DOCTYPE": in UTF-16 an entity expanded in attribute values, and an attribute's default
    /// was given to every element of its name, which made gigabytes of megabytes.
    func testDeclarationsAreRefusedInAnyEncoding() throws {
        let math = "<math xmlns=\"http://www.w3.org/1998/Math/MathML\">"
        func document(_ declaration: String, _ body: String) -> String {
            "<?xml version=\"1.0\"?><!DOCTYPE math [\(declaration)]>\(math)\(body)</math>"
        }
        let documents = [
            document("<!ENTITY a \"expanded\">", "<mi alt=\"&a;\">x</mi>"),
            document("<!ATTLIST mi alt CDATA \"\(String(repeating: "d", count: 10_000))\">", String(repeating: "<mi/>", count: 1_000)),
            document("<!ENTITY % p \"<!ATTLIST mi alt CDATA 'd'>\"> %p;", "<mi/>"),
            document("<!ELEMENT mi ANY>", "<mi/>"),
        ]
        for (index, document) in documents.enumerated() {
            for encoding in [String.Encoding.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian] {
                XCTAssertThrowsError(try MathMLNode.parse(xml: XCTUnwrap(document.data(using: encoding))), "\(index) \(encoding)") {
                    XCTAssertEqual($0 as? MathLayoutError, .invalidMarkup("DOCTYPE"), "\(index) \(encoding)")
                }
            }
        }
        // UTF-16 without one parses as it did.
        let plain = "<?xml version=\"1.0\"?>\(math)<mi>x</mi><mo>&lt;</mo><mn>1</mn></math>"
        XCTAssertEqual(try MathMLNode.parse(xml: XCTUnwrap(plain.data(using: .utf16))), try MathMLNode.parse(xml: Data(plain.utf8)))
    }

    /// A reading says a digit is crossed out where the drawing strikes it, and nowhere else: not
    /// under a bare `none`, which is no carry (MathML 3, 3.6.5.2), nor for a `crossout` layout ignores.
    func testCrossoutsAreReadWhereTheyAreDrawn() throws {
        func strikes(_ body: String) throws -> Int {
            func paths(_ box: MathBox) -> Int {
                box.items.reduce(0) { count, item in
                    switch item {
                    case .path: count + 1
                    case .box(let inner, _): count + paths(inner)
                    default: count
                    }
                }
            }
            let context = LayoutContext(fontSize: 20, unclampedSize: 20, minSize: 12, display: false, color: black)
            return paths(try LayoutEngine(fontName: nil).layout(try node(body), context, depth: 0))
        }
        func read(_ body: String) throws -> Int {
            try node(body).accessibilityDescription.components(separatedBy: "with the column's digit crossed out").count - 1
        }
        let rows = [
            ("<mscarries crossout='updiagonalstrike'><mn>4</mn><none/></mscarries>", 1),
            ("<mscarries crossout='updiagonalstrike'><none/><none/></mscarries>", 0),
            ("<mscarries crossout='updiagonalstrike'><mscarry><none/></mscarry><mscarry crossout='none'><mn>1</mn></mscarry></mscarries>", 1),
            ("<mscarries crossout='scribble'><mn>4</mn><mn>1</mn></mscarries>", 0),
            ("<mscarries crossout='NONE'><mn>4</mn><mscarry crossout='x none'><mn>1</mn></mscarry></mscarries>", 0),
            ("<mscarries crossout=' VerticalStrike '><mn>4</mn><mscarry crossout='horizontalstrike'><none/></mscarry></mscarries>", 2),
        ]
        for (carries, expected) in rows {
            let body = "<mstack>\(carries)<mn>52</mn></mstack>"
            XCTAssertEqual(try strikes(body), expected, "drawn: \(carries)")
            XCTAssertEqual(try read(body), expected, "read: \(carries)")
        }
    }

    /// Speech is bounded as layout is: in text, and in nodes whichever element they are children of.
    func testSpeechIsBoundedInTextAndInWidth() {
        func reading(_ node: MathMLNode) -> String { node.accessibilityDescription(locale: Locale(identifier: "fr")).text }
        func words(_ node: MathMLNode) -> Int { reading(node).split(separator: " ").count }
        // A host's tree may hold one long string many times over: 5 MB of it in each of these.
        let long = String(repeating: "a", count: 1_000), bound = MathLimits.textLength + 2 * long.count
        XCTAssertLessThanOrEqual(reading(n("math", [:], Array(repeating: n("mtext", [:], [], text: long), count: 5_000))).utf16.count, bound)
        XCTAssertLessThanOrEqual(reading(n("math", [:], Array(repeating: n("mglyph", ["alt": long]), count: 5_000))).utf16.count, bound)
        let glyphs = Array(repeating: n("mglyph", ["alt": long]), count: 5_000)
        XCTAssertLessThanOrEqual(reading(n("mi", [:], glyphs)).utf16.count, bound)
        // And none of it is gathered past the bound: 1 GB of `alt` here, which took a minute to join.
        let longer = n("mglyph", ["alt": String(repeating: "a", count: 50_000)])
        let small = n("mi", [:], Array(repeating: longer, count: 1_900))
        let large = n("mi", [:], Array(repeating: longer, count: 19_000))
        // The text budget is exhausted in the first few glyphs for both inputs. Checking
        // growth catches joining all 1 GB before truncating it, regardless of CPU speed.
        assertCPUScaling(factor: 5, "glyph text past the budget", baseline: {
            XCTAssertLessThanOrEqual(reading(small).utf16.count, bound)
        }, larger: {
            XCTAssertLessThanOrEqual(reading(large).utf16.count, bound)
        })
        let fences = Array(repeating: n("mfenced", ["open": long, "close": long]), count: 5_000)
        XCTAssertLessThanOrEqual(reading(n("math", [:], fences)).utf16.count, bound)
        let powers = Array(repeating: n("msup", [:], [one, n("mn", [:], [], text: long)]), count: 5_000)
        XCTAssertLessThanOrEqual(reading(n("math", [:], powers)).utf16.count, 20 * bound)
        // Within the bound nothing is lost.
        XCTAssertEqual(reading(n("mtext", [:], [], text: String(repeating: "a", count: MathLimits.textLength))).utf16.count,
                       MathLimits.textLength)
        // Past the node bound an element says nothing of its children: no row, script or separator.
        let limit = MathLimits.nodes, many = Array(repeating: one, count: 100_000)
        for name in ["mtable", "mmultiscripts", "mfenced", "mrow", "msqrt"] {
            XCTAssertLessThanOrEqual(words(n(name, [:], many)), 4 * limit, name)
        }
        XCTAssertLessThanOrEqual(words(n("mtable", [:], Array(repeating: n("mtr"), count: 100_000))), 4 * limit)
        XCTAssertLessThanOrEqual(words(n("mtable", [:], [n("mtr", [:], many)])), 4 * limit)
    }
}
