# Release notes

## 0.2.0

Line breaking, `mglyph`, elementary math and localized readings
([#1](https://github.com/vocaro/MathMLLayout/issues/1)). The 0.1.0 API still compiles.

### Added

- **Line breaking.** `MathLayout(_:style:maximumWidth:firstRowMaximumWidth:)` breaks a formula
  into `rows` that fit a line, each with its `origin` and box, and each drawable alone, so an
  inline formula can continue on the next text lines. Breaks follow MathML 3 §3.1.7: authored
  `linebreak`, `linebreakstyle`, `linebreakmultchar`, `lineleading` and the `indent*` attributes,
  and otherwise the operator dictionary's ranking. They reach inside nested rows, `mfenced` and
  script bases; `mtext`, table cells, fraction parts, radicands and enclosures wrap.
  `widestUnbreakableWidth` and `axisHeight` are public.
- **`mglyph`.** `MathStyle.imageProvider` supplies each `src`'s image, sized by `width`, `height`
  and `valign`. Without an image the `alt` text is drawn and read; nothing throws.
- **Elementary math.** `mstack`, `mlongdiv`, `msgroup`, `msrow`, `mscarries`, `mscarry` and
  `msline` are laid out natively, with every `longdivstyle`, and read row by row.
- **Localized readings.** `accessibilityDescription(locale:)` returns a `MathReading`: the text,
  in English, French, German, Spanish or Italian, and the language it is actually in (`"en"`
  when the locale has no vocabulary).

### Fixed

- An operator among `mtext` operands keeps its spacing: `future value = principal × rate` was
  drawn as "future value=principal" when it had one operator, and with the `×` as a sign when
  it had two.
- A token's trailing white space is trimmed: `<mi>x </mi>` was drawn upright with a space after
  it, and `<mo> + </mo>` was not found in the operator dictionary or read as "plus".
- Drawing leaves the context's text matrix as the host set it. `draw(in:baselineOrigin:)` left
  it at identity, so text a host drew afterwards lost its flip
  ([#15](https://github.com/vocaro/MathMLLayout/issues/15)).
- An `mpadded` whose `width`, `height` or `depth` is decremented past zero has none, as MathML 3
  asks. It had a negative one, and with a negative width what followed was drawn before the box
  began ([#10](https://github.com/vocaro/MathMLLayout/issues/10)).
- A table's rows count toward the 20,000-node bound. A hand-built table of 100,000 empty rows
  with no row spacing was laid out ([#14](https://github.com/vocaro/MathMLLayout/issues/14)).
- An operator marked `form="infix"` keeps its spacing where its place in the row would make it
  a sign: `<mo form="infix">+</mo><mi>a</mi>` was laid out as if it said `form="prefix"`
  ([#9](https://github.com/vocaro/MathMLLayout/issues/9)).
- Hostile markup that 0.1.0 let through, found by fuzzing this release:
  - `scriptlevel="+9223372036854775807"` and `maction selection="-9223372036854775808"`
    overflowed an integer and stopped the process.
  - A UTF-16 document hid its `<!DOCTYPE` from the check for one, so its entities and attribute
    defaults expanded: 19 GB from 2 MB of markup.
  - A dashed table frame or line made every dash at layout, without bound when the table's own
    font was tiny beside its content. Dashes are now drawn, not stored.
  - Nesting within the 64-level bound could still overflow the 512 KB stack of a secondary
    thread. Layout now throws `limitExceeded`, and a reading leaves the rest out, before the
    stack runs out.
  - A row of thousands of stretchy operators took quadratic time, and a NaN font size gave a
    NaN box.

### Changed

- A `linebreak="newline"` now breaks the row even when no `maximumWidth` is given, so such a
  formula has more than one row. Its baseline is the first row's.
- `mglyph`, `mstack` and `mlongdiv` no longer throw `MathLayoutError.unsupported`.
- A label over or under an operator that stretches horizontally, as in
  `<mover><mo>→</mo><mtext>heat</mtext></mover>`, is placed by the MATH table's StretchStack
  constants in place of the over- and underbar gaps
  ([#21](https://github.com/vocaro/MathMLLayout/issues/21)). Its baseline is the font's standard
  shift from the arrow's baseline, further only to keep the minimum gap from the arrow's ink, so
  labels on one arrow after another share a baseline whatever their letters. With STIX Two Math
  at 20 points a label moves by up to about 3 points, mostly away from the arrow. The shifts are
  read from the baseline, as OpenType defines them and
  [w3c/mathml-core#121](https://github.com/w3c/mathml-core/issues/121) settled, where MathML
  Core's text still has them from the ink.
- `MathMLNode.parse(xml:)` keeps the attributes of a token's element children, and marks each
  `mglyph`'s place in the token's `text` with U+FFFC. Hosts that build nodes themselves should
  do the same; the README's Images section has the details.

### For EPUBLib

Each workaround that [vocaro/EPUBLib#61](https://github.com/vocaro/EPUBLib/pull/61) added for
[vocaro/EPUBLib#25](https://github.com/vocaro/EPUBLib/issues/25) can go:

- **`MathBreaking.swift`** (`MathBreaks`, `MathArrangement`): pass the line width as
  `maximumWidth` and use `rows` instead of slicing the tree and stacking a layout per slice.
  That retires its lists of relations, operators and brackets, the empty `mi` put before an
  operator that starts a row, and the quarter-em axis (`axisHeight`). `MathFormula`'s shrink
  policy can compare `widestUnbreakableWidth` with the line, and an inline formula can place its
  rows on consecutive lines of the paragraph (`firstRowMaximumWidth`) instead of becoming a block.
- **`mglyph` as text** (`MathConversion`, `missingGlyph`): keep the element as a child of its
  token with its attributes and a U+FFFC in the text, and give `MathStyle` an image provider.
  The engine falls back to `alt`, then to U+25AF, itself.
- **`MathElementary.swift`** (`rewrite`, `spoken`): pass `mstack` and `mlongdiv` through
  unchanged. The approximations it counted in `SectionReport.mathApproximations` are gone.
- **`MathSpeech.generate`**: call `accessibilityDescription(locale:)` with the content's language
  and tag the utterance with the `language` it returns, in place of `generatedLanguage`.
- The disclosure of the `mtext` operand spacing defect.

## 0.1.0

- First release, moved out of [EPUBLib](https://github.com/vocaro/EPUBLib) (at `35f7fdc`), where it
  was written for the native EPUB viewer
  ([vocaro/EPUBLib#3](https://github.com/vocaro/EPUBLib/issues/3)).
- Presentation-MathML layout and drawing with CoreText and the OpenType MATH table; parser,
  spoken readings, bounds on untrusted input. See the [README](README.md) for what is supported.
- Every one of the 1,798 formulas in EPUBLib's real-book corpus lays out without a fallback.
