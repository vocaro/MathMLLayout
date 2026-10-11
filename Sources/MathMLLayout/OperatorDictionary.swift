import CoreGraphics

/// An operator's form: its position in an `mrow`, or its `form` attribute.
enum OperatorForm: Sendable, Equatable { case prefix, infix, postfix }

struct OperatorFlags: OptionSet, Sendable, Hashable {
    let rawValue: UInt8
    static let stretchy = OperatorFlags(rawValue: 1)
    static let symmetric = OperatorFlags(rawValue: 2)
    static let fence = OperatorFlags(rawValue: 4)
    static let separator = OperatorFlags(rawValue: 8)
    static let largeop = OperatorFlags(rawValue: 16)
    static let movablelimits = OperatorFlags(rawValue: 32)
    static let accent = OperatorFlags(rawValue: 64)
}

/// An operator's resolved spacing and behaviour, after the dictionary and its attributes.
struct OperatorProperties: Sendable {
    var form: OperatorForm
    /// Points.
    var lspace: CGFloat
    var rspace: CGFloat
    var flags: OperatorFlags
    /// Stretches along the inline axis (arrows, over- and underbraces, wide accents).
    var isHorizontal: Bool
    /// A binary operator by the dictionary, which becomes unary where TeX's rule 5 says so.
    var isBinary = false
    /// The `mo` says `form="infix"`, which its place in the row then does not change: rule 5
    /// leaves it its spacing.
    var isMarkedInfix = false
    /// The dictionary's spacing, in eighteenths of an em, before attributes or script level.
    var dictionarySpacing: (lspace: UInt8, rspace: UInt8) = (0, 0)
    /// Whether and how a line may break at the operator; nil when it was not laid out as an `mo`.
    var breakPoint: BreakPoint?
    func has(_ flag: OperatorFlags) -> Bool { flags.contains(flag) }
}

/// How willingly a line breaks at an operator, best first (MathML 3, 3.1.7.2, and The TeXbook's
/// chapter 18: after relations in preference to binary operations). `none` never breaks unless
/// its `mo` says so, and `glue` also holds its neighbours together: a function and its argument.
enum BreakClass: UInt8, Sendable { case none, relation, separator, space, additive, multiplicative, glue }

/// The operator dictionary: default spacing and properties of common operators by form.
///
/// Spacing follows TeX's classes, which MathML's dictionary also encodes: relations and
/// arrows get a thick space (5/18 em) each side, binary operators a medium one (4/18 em) and
/// lose it as prefixes (unary minus), punctuation a thin space after, large operators a thin
/// space each side, fences none. An operator not listed gets thick spaces, as in MathML Core.
///
/// The same classes rank line breaks: at a relation first, then at a sum, then at a product. An
/// operator not listed is spaced as a relation, and between two operands breaks as one.
enum OperatorDictionary {
    struct Entry: Sendable, Equatable {
        /// Eighteenths of an em.
        var lspace: UInt8
        var rspace: UInt8
        var flags: OperatorFlags
        var breakClass = BreakClass.none
    }
    static let unknown = Entry(lspace: 5, rspace: 5, flags: [], breakClass: .relation)

    private struct Key: Hashable { let text: String; let form: OperatorForm }

    /// The entry for `text` in `form`; a missing form falls back to infix, postfix, then prefix.
    static func entry(_ text: String, form: OperatorForm) -> Entry {
        if let listed = listedForm(text, form: form), let entry = table[Key(text: text, form: listed)] { return entry }
        return form == .infix ? unknown : Entry(lspace: unknown.lspace, rspace: unknown.rspace, flags: unknown.flags)
    }

    /// The form of the entry that `entry` finds, nil for an operator not listed: what the operator
    /// is, where its position says otherwise. A "(" in the middle of a row is still an opening
    /// fence, and an "=" that starts one is still a relation.
    static func listedForm(_ text: String, form: OperatorForm) -> OperatorForm? {
        [form, .infix, .postfix, .prefix].first { table[Key(text: text, form: $0)] != nil }
    }

    /// Whether an operator stretches horizontally rather than vertically.
    static func isHorizontal(_ text: String) -> Bool {
        text.unicodeScalars.count == 1 && horizontal.contains(text.unicodeScalars.first!)
    }

    private static let horizontalArrows = "←→↔↚↛↮↜↝↞↠↢↣↤↦↩↪↫↬↭↼↽⇀⇁⇄⇆⇇⇉⇋⇌⇍⇎⇏⇐⇒⇔⇚⇛⟵⟶⟷⟸⟹⟺⟻⟼⟽⟾"
    private static let verticalArrows = "↑↓↕⇑⇓⇕↥↧⇅⇈⇊↾↿⇂⇃"
    private static let horizontalAccents = "‾¯_^ˆ~˜ˇ˘⏞⏟⏜⏝⎴⎵⏠⏡\u{0302}\u{0303}\u{030C}\u{0305}\u{0311}\u{0332}\u{20D6}\u{20D7}\u{20E1}"
    private static let horizontal = Set((horizontalArrows + horizontalAccents).unicodeScalars)

    private static let table: [Key: Entry] = {
        var table: [Key: Entry] = [:]
        func add(_ characters: String, _ form: OperatorForm, _ lspace: UInt8, _ rspace: UInt8, _ flags: OperatorFlags = [],
                 _ breakClass: BreakClass = .none) {
            for scalar in characters.unicodeScalars {
                table[Key(text: String(scalar), form: form)] = Entry(lspace: lspace, rspace: rspace, flags: flags,
                                                                     breakClass: breakClass)
            }
        }
        func addWords(_ words: [String], _ form: OperatorForm, _ lspace: UInt8, _ rspace: UInt8, _ flags: OperatorFlags = []) {
            for word in words { table[Key(text: word, form: form)] = Entry(lspace: lspace, rspace: rspace, flags: flags) }
        }
        let relations = "=≠<>≤≥≦≧≨≩≪≫≮≯≰≱≈≉≊≋≃≄≅≆≇≡≢≣∼≁≍≎≏≐≑≒≓≔≕≖≗≘≙≚≛≜≝≞≟∝∈∉∊∋∌∍"
            + "⊂⊃⊄⊅⊆⊇⊈⊉⊊⊋⊏⊐⊑⊒≺≻≼≽≾≿⊀⊁⊢⊣⊥⊨⊩⊪⊫⊬⊭∣∤∥∦≬⋈⋍⋐⋑⋘⋙⋚⋛⋞⋟⋠⋡⋢⋣⋤⋥⋦⋧⋨⋩⋪⋫⋬⋭"
            + "∴∵∷∶:⩽⩾⪅⪆⪇⪈⪉⪊⪋⪌⪯⪰⊸⟂≺"
        add(relations, .infix, 5, 5, [], .relation)
        add("↖↗↘↙↰↱↲↳↶↷↺↻", .infix, 5, 5, [], .relation)
        add(horizontalArrows, .infix, 5, 5, .stretchy, .relation)
        add(verticalArrows, .infix, 5, 5, .stretchy, .relation)
        // Binary operators, split by how tightly they bind: a line breaks at a sum before a product.
        add("+−±∓⊕⊖⊝∪⊎⊔∨∖⊞⊟⋎⋓\\", .infix, 4, 4, [], .additive)
        add("×÷·∙∗∘⋅⊗⊘⊙⊚⊛∩⊓∧⋆⋄◇△▽◁▷⊲⊳⊴⊵≀⨯⨿⊠⊡⋋⋌⋏⋒†‡*", .infix, 4, 4, [], .multiplicative)
        add("+−±∓¬∁", .prefix, 0, 0)
        add("∀∃∄∂∇∆√∛∜", .prefix, 0, 0)
        add("/", .infix, 0, 0)
        add("!′″‴⁗‵‶‷'%°", .postfix, 0, 0)
        add(",;", .infix, 0, 3, .separator, .separator)
        add("\u{2063}", .infix, 0, 0, .separator)
        // Invisible times is a product. Function application and invisible plus (a mixed number) never part.
        add("\u{2062}", .infix, 0, 0, [], .multiplicative)
        add("\u{2061}\u{2064}", .infix, 0, 0, [], .glue)
        add(".…⋯⋮⋰⋱", .infix, 0, 0)
        let fence: OperatorFlags = [.stretchy, .symmetric, .fence]
        add("([{⟨⟦⟪⟬⟮⦃⦅⦇⦉⦋⦍⦏⦑⦓⦕⦗⌈⌊〈❲⁅", .prefix, 0, 0, fence)
        add(")]}⟩⟧⟫⟭⟯⦄⦆⦈⦊⦌⦎⦐⦒⦔⦖⦘⌉⌋〉❳⁆", .postfix, 0, 0, fence)
        for form in [OperatorForm.prefix, .infix, .postfix] { add("|‖⦀¦⦙", form, 0, 0, fence) }
        add("∑∏∐⋀⋁⋂⋃⨀⨁⨂⨃⨄⨅⨆⨉⫿⅀", .prefix, 3, 3, [.largeop, .movablelimits, .symmetric])
        add("∫∬∭∮∯∰∱∲∳⨋⨌⨍⨎⨏⨐⨑⨒⨓⨔⨕⨖⨗⨘⨙⨚⨛⨜", .prefix, 3, 3, [.largeop, .symmetric])
        addWords(["lim", "max", "min", "sup", "inf", "liminf", "limsup", "lim inf", "lim sup", "det", "gcd", "Pr",
                  "inj lim", "proj lim"], .prefix, 0, 3, .movablelimits)
        add(horizontalAccents, .postfix, 0, 0, [.accent, .stretchy])
        add("˙¨´`˚¸˝\u{0300}\u{0301}\u{0304}\u{0306}\u{0307}\u{0308}\u{030A}\u{030B}\u{20DB}\u{20DC}", .postfix, 0, 0, .accent)
        return table
    }()
}
