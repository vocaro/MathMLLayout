/// A narrow British English variant: round, square and curly bracket names.
/// Names follow WJEC's mathematics glossary; opening/closing composition follows the base.
/// https://glossary.resources.wjec.co.uk/en/mathematics/brackets
/// Other terminology and generated templates deliberately inherit the English vocabulary.
public enum EnglishUnitedKingdomVocabulary: MathRegionalVocabulary {
    public typealias Base = EnglishVocabulary
    public static let language = "en-GB"
    public static var symbols: MathSymbols {
        var words = Base.symbols
        words.openParen = "open round bracket"; words.closeParen = "close round bracket"
        words.openBracket = "open square bracket"; words.closeBracket = "close square bracket"
        words.openBrace = "open curly bracket"; words.closeBrace = "close curly bracket"
        return words
    }
}
