// Selected wording adapted from MathCAT (MIT) and Speech Rule Engine (Apache-2.0).
// Modified for MathMLLayout; see THIRD_PARTY_NOTICES.md and doc/speech-wording-audit.md.
/// Digit and punctuation names are source-backed; elementary-math geometry phrases
/// are MathMLLayout compositions. Human review is limited to those novel descriptions
/// and joining policies; see doc/speech-wording-audit.md.
struct MathSpatialWords: Sendable {
    let digits: [String]
    let point, comma, space, colon, semicolon: String
    let column, alignment, fullWidth, carriesOrBorrows: String
    let alignments: [MathStackAlignment: String]
    let locations: [CarryLocation: String]
    let strikes: [String: String]
    let frames: [LongDivision: String]

    func character(_ character: Character) -> String {
        if let digit = character.wholeNumberValue, (0..<10).contains(digit) { return digits[digit] }
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

extension MathVocabulary {
    static func column(_ number: Int) -> String {
        phrase(spatial.column, number < 0 ? symbols.minus : "", String(number.magnitude)) + ":"
    }

    static func alignment(_ align: MathStackAlignment) -> String {
        phrase(spatial.alignment, spatial.alignments[align] ?? "")
    }
}
