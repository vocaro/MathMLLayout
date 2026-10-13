// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout; see doc/licenses/THIRD_PARTY_NOTICES.md and doc/speech-wording-audit.md.
/// Digit and punctuation names are source-backed; elementary-math geometry phrases
/// are MathMLLayout compositions. Human review is limited to those novel descriptions
/// and joining policies; see doc/speech-wording-audit.md.
public struct MathSpatialWords: Sendable {
    public let digits: [String]
    public let point, comma, space, colon, semicolon: String
    public let column, alignment, fullWidth, carriesOrBorrows: String
    public let alignments: [MathStackAlignment: String]
    public let locations: [CarryLocation: String]
    public let strikes: [String: String]
    public let frames: [LongDivision: String]

    public init(digits: [String], point: String, comma: String, space: String, colon: String,
                semicolon: String, column: String, alignment: String, fullWidth: String,
                carriesOrBorrows: String, alignments: [MathStackAlignment: String],
                locations: [CarryLocation: String], strikes: [String: String], frames: [LongDivision: String]) {
        self.digits = digits
        self.point = point; self.comma = comma; self.space = space
        self.colon = colon; self.semicolon = semicolon
        self.column = column; self.alignment = alignment; self.fullWidth = fullWidth
        self.carriesOrBorrows = carriesOrBorrows
        self.alignments = alignments; self.locations = locations
        self.strikes = strikes; self.frames = frames
    }

    /// An incomplete vocabulary is ineligible for locale selection; English is never inserted
    /// into an otherwise localized reading. Unknown source characters remain literal.
    var isComplete: Bool {
        let values = digits + [point, comma, space, colon, semicolon, column, alignment, fullWidth, carriesOrBorrows]
        return digits.count == 10 && values.allSatisfy { !$0.isEmpty }
            && MathStackAlignment.allCases.allSatisfy { alignments[$0]?.isEmpty == false }
            && CarryLocation.allCases.allSatisfy { locations[$0]?.isEmpty == false }
            && LongDivision.allCases.allSatisfy { frames[$0]?.isEmpty == false }
            && ["updiagonalstrike", "downdiagonalstrike", "verticalstrike", "horizontalstrike"]
                .allSatisfy { strikes[$0]?.isEmpty == false }
    }

    public func character(_ character: Character) -> String {
        if let digit = character.wholeNumberValue, (0..<10).contains(digit), digits.indices.contains(digit) { return digits[digit] }
        switch character {
        case ".": return point
        case ",": return comma
        case " ": return space
        case ":": return colon
        case ";": return semicolon
        default: return String(character)
        }
    }
}

public extension MathVocabulary {
    static func column(_ number: Int) -> String {
        phrase(spatial.column, number < 0 ? symbols.minus : "", String(number.magnitude)) + ":"
    }

    static func alignment(_ align: MathStackAlignment) -> String {
        phrase(spatial.alignment, spatial.alignments[align] ?? "")
    }
}
