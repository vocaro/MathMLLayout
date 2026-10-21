# Speech vocabulary extension contract

`MathVocabularyCatalog` selects a provider once before the bounded speech traversal. Its
`languages` are the actual selectable BCP 47 voice tags. Custom providers precede built-ins;
the first complete provider for a canonical tag wins. Catalogs are immutable values supplied
per call; registration has no global state. Providers must use stable, thread-safe terminology
and pure composition functions. The general lesson behind this contract is in
[shared spoken localization](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#spoken-localization-must-preserve-authored-content-and-actual-language).

```swift
let catalog = MathVocabularyCatalog(vocabularies: [MyVocabulary.self, MyRegionalVocabulary.self])
let reading = formula.accessibilityDescription(locale: requestedLocale, vocabularies: catalog)
// Select a host voice with reading.language, which can differ from requestedLocale.
```

## Matching and fallback

Tags support a language, optional script, optional region, and standard BCP 47 variant subtags.
Underscores and casing are normalized (`QAA_zz` becomes `qaa-ZZ`), without adding likely subtags.
For a requested locale, Unicode/private extensions and ICU keywords are ignored for vocabulary
matching: `en-GB-u-nu-latn` and `en_GB@calendar=gregorian` select `en-GB`.

Selection tries the exact canonical tag, then the unqualified base language, then built-in
English for the **whole** reading. It never tries another region, strips only part of an unsupported
script/region combination, or borrows English terms for a selected language. Thus `fr-CA` selects
`fr`; `en-AU` selects `en`; `en-Latn-GB` selects `en` unless that exact script/region provider is
registered. A complete `qaa-Latn-ZZ` fixture selects that exact tag, while `qaa-Cyrl-ZZ` uses `qaa`.
Language codes retain Foundation’s normalization (including `fra`/`deu`/`spa` aliases). This is
a deliberately bounded matching policy, not a full BCP 47 registry or grandfathered-tag lookup.
The general rationale is in
[shared spoken localization](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#spoken-localization-must-preserve-authored-content-and-actual-language).

Malformed provider tags, empty symbol/accent names, incomplete geometry maps, or a digit table
that lacks exactly ten nonempty names make the provider ineligible. An empty `ordinalRoots` table
is valid: unsupported indices use the provider's explicit `root` composition. The selected
`MathReading.language` is canonical, rather than the requested locale's tag. The original
`MathReading.languages` continues to list the five base languages; `supportedLocales` includes
built-in regional providers.

## Complete language providers

Implement `MathVocabulary` directly for a new language. `MathSymbols` and `MathAccents` require
all named fields in their public initializers, retaining the engine's symbol aliases.
`MathSpatialWords` requires names for ten digits, literal punctuation, alignment and columns,
carry/borrow positions, four strike directions, and all ten long-division frames. Maps must
cover every public `MathStackAlignment`, `CarryLocation`, and `LongDivision` case. There is no
implicit inherited English vocabulary for a new language.

Every structural composition is a protocol requirement: fractions, powers and scripts, roots,
limits and accents, tables and row-count agreement, stack introductions, carries, crossouts,
and divisor/dividend/result labels. Already-spoken operands arrive in source order. The
`simple`/`closed` flags say where the engine needs explicit boundaries. Put operands and generated
words in the language's required order inside each function; select agreement using counts or
operand text where that is sufficient. Presentation MathML does not provide arbitrary grammatical
gender or the pronunciation/language of an author token.

`phrase([String])` joins already-read parts. Its default removes empty operands and separates
nonempty parts with spaces. It is a protocol requirement, so custom joining dispatches through
the selected provider even in nested rows. `accent(_:on:)`, `column(_:)`, and `alignment(_:)`
also dispatch through the provider; their defaults use only that provider's terminology.
Construct functions can implement their own joining policy and explicit endings. Prime sequences
use `primed(_:count:)` in one call, allowing language-specific order without quadratic rebuilding;
`primed(_:)` is the one-prime convenience. Carry/borrow groups dispatch through `carries(_:)`,
whose built-in implementations retain the existing combined carry-or-borrow introduction. An omitted
operand is an empty string and must not trigger a fresh source traversal.

Composers are trusted application code. They must return finite output proportional to the
bounded operands, must not read the source tree or do automatic translation, and should remove
dangling labels where operands are empty. The engine retains its source node/depth/UTF-16-text
and thread-stack budgets; it cannot sandbox arbitrary user-supplied Swift functions. The general
composition and bounded-output rules are in
[shared spoken localization](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#spoken-localization-must-preserve-authored-content-and-actual-language)
and [shared stack and work bounds](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/stack-and-work-bounds.md#a-depth-limit-does-not-bound-stack-or-total-work).

## Explicit regional inheritance

Implement `MathRegionalVocabulary` with `typealias Base = ExistingVocabulary` and a distinct
`language` tag. Unchanged tables and construct functions forward to that complete base. Override
only the regional terms and compositions required by the evidence. For example, a symbol change
copies `Base.symbols` and changes a named field; it never rewrites the completed reading, so author
text containing the same word remains intact. The general rule is in
[shared spoken localization](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#spoken-localization-must-preserve-authored-content-and-actual-language).

Inherited construct functions retain the base's internal joining. If a region needs different
joining or agreement inside a fraction/root/etc., override that construct function as well as
any row-level `phrase` policy. `EnglishUnitedKingdomVocabulary` is a concrete minimal example:
its six bracket fields change, and its other complete English templates remain inherited.

## Concrete supported variant and evidence

The built-in `en-GB` provider uses **round bracket** for `( )`, **square bracket** for `[ ]`, and
**curly bracket** for `{ }`. These terms are given for the actual mathematical notation in the
[WJEC mathematics glossary, “brackets”](https://glossary.resources.wjec.co.uk/en/mathematics/brackets)
(accessed 2026-10-12). The source lists round, rectangular/square, and curly brackets. This engine
chooses square and adds its existing open/close boundary words. The UK's
[Office for National Statistics punctuation guide](https://service-manual.ons.gov.uk/content/formatting-and-punctuation/punctuation)
also distinguishes round and square brackets; that source supports names, not a mathematics
speech utterance.

This is a narrow supported vocabulary choice, not comprehensive coverage of British English
regional classroom usage. All other wording inherits the existing base and its
[source audit](speech-wording-audit.md). No new human or host-voice validation is claimed.
Existing novel-wording and French-joining review remains scoped to
[issue #63](https://github.com/vocaro/MathMLLayout/issues/63); this extension does not reopen it.

## Exercised extension fixtures

`SpeechVocabularyAPITests` imports the public API without `@testable`. Its synthetic `qaa`
provider independently supplies every term and required composition, including a non-space
joiner, count templates, nested fraction/root/power boundaries, accents, prime sequences, carry-group
composition, and stack geometry.
`qaa` belongs to the [private-use language range in RFC 5646 §2.2.1](https://www.rfc-editor.org/rfc/rfc5646.html#section-2.2.1); the sentinel fixture is not a natural-language
translation. A `qaa-ZZ` regional fixture changes symbols and power composition. Tests cover exact
script/region matching, base and whole-English fallback, malformed/incomplete providers,
first-registration precedence, per-call isolation, selected voice tags, and literal author
`mtext`/`ms`/image `alt` words. Existing token normalization and mathematical-symbol naming remain.
The general method is in
[shared sentinel languages](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/text-layout-and-unicode.md#sentinel-languages-test-plumbing-not-pronunciation).

`SpeechLocaleBoundsTests` exercises source node/depth/text budgets, stack group collection, and
small thread stacks for that complete fixture, its region, `en-GB`, and English fallback.
The existing five-language phrase fixtures continue to pin all unqualified default readings.

[Spoken readings](speech.md)
