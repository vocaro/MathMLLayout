# Release notes

## Unreleased

- A layout measures each glyph's ink once, not again for every row and width that line breaking
  tries. Layouts on many threads at once no longer queue in the kernel for CoreText's glyph
  outlines; no layout result changed.

## 0.3.2 — 2026-10-23

- Code, tests and documents are spelled in American English; no public declaration, output or
  reading changed ([#121](https://github.com/vocaro/MathMLLayout/issues/121)).
- The corpus sampler finds the equations in HTML fixtures under libxml2 releases before 2.14
  ([#118](https://github.com/vocaro/MathMLLayout/issues/118)).
- `python3 scripts/eng run gate` runs the whole release gate as one exclusive lane
  ([#122](https://github.com/vocaro/MathMLLayout/issues/122)).

## 0.3.1 — 2026-10-13

Wrapping, indentation, table layout, image metrics and OpenType MATH corrections.

- Mixed RTL image/text and decorated fallbacks wrap in logical order. Explicit padding,
  errors and backgrounds rebuild per fragment; eligible under/over bases keep their annotations
  ([#111](https://github.com/vocaro/MathMLLayout/issues/111)).
- Indentation targets retain final coordinates through independently wrapped rows,
  decorated fragments and script arguments
  ([#112](https://github.com/vocaro/MathMLLayout/issues/112)).
- Tables support equal tracks, authored widths, whole-cell operator stretching and overlap
  labels without ordinary gutters ([#113](https://github.com/vocaro/MathMLLayout/issues/113)).
- Optional image stretch direction, italic clearance and top-accent attachment metadata
  support image-only operators and physical attachment geometry
  ([#114](https://github.com/vocaro/MathMLLayout/issues/114)).
- Supported MATH variation corrections follow the selected font instance. Device corrections
  opt in through a fixed layout-time output scale
  ([#115](https://github.com/vocaro/MathMLLayout/issues/115)).

- Documentation distinguishes supported behavior from remaining restrictions and records
  macOS and iOS release verification. See [bounds and limitations](doc/limits.md) and
  [testing](https://github.com/vocaro/MathMLLayout/blob/0.3.1/doc/testing.md#031-release-verification).

## 0.3.0 — 2026-10-13

RTL layout, table spans and alignment, richer image support and extensible speech vocabularies.
Existing 0.2.0 initializers and default base-language readings remain supported.

### Added

- Inherited RTL progression for rows, table columns, scripts, multiscripts, radicals,
  beveled fractions, leading padding and directional enclosures. Mixed-direction children
  retain their own shaping and local overrides; physical alignment and explicit enclosure
  sides retain their meaning. See [directionality](doc/directionality.md)
  ([#108](https://github.com/vocaro/MathMLLayout/issues/108)).
- Bounded table `rowspan` and `columnspan`, vertical cell/row alignment and inherited
  `mstyle` row defaults. Alignment groups and marks work in LTR and RTL, through cell
  wrapping, compatible spans, nested tables and wrapped neighboring elements. Token marks
  retain their position beside text, inline images and legacy glyphs through the new
  `MathMLNode.tokenTextOffset` property. See [table alignment groups](doc/alignment-groups.md).
- `MathImage` and `MathImageProvider.resolving` supply intrinsic image scale or logical size
  in points. Existing image providers retain one pixel per point; authored dimensions take
  precedence. Bounded legacy `mglyph` font/index lookup uses installed fonts and falls back
  to `alt` for unsupported inputs. Explicit `stretchy` and `largeop` opt into whole-token
  image-operator geometry. See [images](doc/images.md) and [image operators](doc/image-operators.md).
- OpenType MATH corner kerning for eligible single-glyph script pairs, including the
  adjoining physical corners of RTL scripts. Compound, fallback and assembled boxes retain
  zero corner kerning.
- Top-level `math maxwidth` can narrow host line budgets, including absolute/font-relative
  widths with an unbounded host. See [line breaking](doc/line-breaking.md).
- Public `MathVocabulary`, `MathRegionalVocabulary` and `MathVocabularyCatalog` APIs for
  complete custom languages and explicit regional overrides, selected per reading. Locale
  selection tries the exact supported tag, its base language, then English for the whole
  reading. Built-in `en-GB` adds British bracket terminology. See
  [the vocabulary extension contract](doc/speech-locales.md).
- Offline corpus validation in the default test suite: 100 OpenStax Precalculus 2e equations
  and 296 Speech Rule Engine regression inputs. All 393 valid inputs must render with
  deterministic, bounded dimensions and contained raster ink; three malformed script inputs
  must produce their recorded rejection. Sources, hashes, provenance and licenses are
  bundled in test resources. These checks establish robustness, not visual conformance.

### Fixed

- Plain bidirectional `mtext` wraps in logical order with per-line shaping and inherited
  paragraph direction. Simple LTR text reuses glyph/word measurements to reduce wrapping
  work while other text retains full paragraph bidi context.
- Inline images and decorated fallbacks wrap at supported spaces while retaining attachment
  alignment, authored whitespace and explicit token marks. Each elementary-math `mglyph`
  occupies one logical number column; embedded glyph descriptions follow source order,
  and missing or empty `alt` remains silent.
- Default `mpadded` and `mphantom` preserve wrapper semantics across line fragments;
  phantom fragments stay invisible. Nested indentation targets and nested-table width
  fitting retain their geometry through relayout.
- Table alignment resolves against rendered neighbor fragments and retains marker and
  background geometry through wrapping, spans and direction changes. Invalid direction
  attributes preserve inherited scope.
- Recursive layout uses less worker stack space, releases cached table engines and preserves
  fence rebuild state. Exact 512 KB worker tests cover the documented 64-level shape matrices,
  including RTL and wrapped alignment. Input and work limits remain enforced; this is not
  universal coverage of every 64-level formula. See [bounds and limitations](doc/limits.md).

### Documentation

- Added guides for directionality, alignment groups, image operators and speech locale
  extension, plus a native-speaker speech review packet. Consolidated third-party notices
  under `doc/licenses`. Remaining linguistic review is tracked in
  [#63](https://github.com/vocaro/MathMLLayout/issues/63).

## 0.2.0

Line breaking, `mglyph`, elementary math and localized readings
([#1](https://github.com/vocaro/MathMLLayout/issues/1)). The 0.1.0 API still compiles.

### Added

- LTR table columns align `maligngroup` groups and explicit `malignmark` points, including
  inherited `groupalign` lists and decimal alignment. RTL, wrapping and span policies are
  documented in [table alignment groups](doc/alignment-groups.md)
  ([#76](https://github.com/vocaro/MathMLLayout/issues/76)).

- Long single arrows `⟵`, `⟶` and `⟷` use the font's short-arrow assemblies when their own
  glyph has none. Drawn horizontal shafts use the font's rule thickness, with a half-point minimum
  ([#38](https://github.com/vocaro/MathMLLayout/issues/38)).
- Vertical arrows without a MATH construction stretch as drawn shapes, including barred,
  paired and harpoon arrows. They keep their natural advance and horizontal ink alignment
  ([#39](https://github.com/vocaro/MathMLLayout/issues/39)).
- A bracket pair wholly on one output row resizes to that row's content after line breaking,
  compacting the row and reattaching scripts. A pair split across rows keeps its original size
  ([#43](https://github.com/vocaro/MathMLLayout/issues/43)).
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

- Spoken readings now describe stack columns, shifted rows, carry/borrow locations and
  crossout styles, and long-division frames. Stack digits and punctuation are explicit.
  Large-operator side limits, under-accents, multiple primes, configured fence separators,
  identifier symbols and simple ordinal roots are read in all five languages; French vowel
  elision is explicit ([#31](https://github.com/vocaro/MathMLLayout/issues/31)).
  Fresh linguistic review is limited to novel descriptions in the
  [speech audit](doc/speech-wording-audit.md#structural-follow-up-for-31), tracked separately
  in [#63](https://github.com/vocaro/MathMLLayout/issues/63).

- `mmultiscripts` spoken readings distinguish right/left subscripts and superscripts
  in all five languages. Pairs follow source order after the base, including silent
  placeholders, and compound scripts announce their end
  ([#55](https://github.com/vocaro/MathMLLayout/issues/55)). The speech guide and
  wording audit record templates and pinned evidence; the remaining human review is tracked
  in [#63](https://github.com/vocaro/MathMLLayout/issues/63).
- Inline large operators retain their font baseline instead of being shifted onto the math
  axis. This corrects under/over limit placement; display-style centering is preserved
  ([#54](https://github.com/vocaro/MathMLLayout/issues/54)).
- Selected French, German, Spanish and Italian spoken names now follow pinned MathCAT and
  Speech Rule Engine rules and fixtures, including double-dot accents, several hat/bar
  accents, partial derivatives and the German contour integral. French `<` and `>` readings
  omit `strictement`. The [wording audit](doc/speech-wording-audit.md) records
  accepted source-backed wording and the limited review queue for novel descriptions.
  Underbars, brace names, Italian caron and bounded ordinals also follow upstream evidence;
  Spanish variable roots retain explicit indices
  ([#31](https://github.com/vocaro/MathMLLayout/issues/31)).
- Neighboring wrapping parts receive independent width budgets when a shared budget overflows.
  The reported `widestUnbreakableWidth` is verified by laying out at that width, including
  height-dependent padding, forced rows and the layout's geometry bounds
  ([#26](https://github.com/vocaro/MathMLLayout/issues/26)).
- Empty tables, and tables smaller than their rule in either dimension, omit their frame so it
  cannot draw outside the table's box
  ([#41](https://github.com/vocaro/MathMLLayout/issues/41)). Bare `mtr` and `mlabeledtr` rows apply
  relative sizes and script levels once, as rows inside a table do
  ([#47](https://github.com/vocaro/MathMLLayout/issues/47)).
- A long row with a negative space keeps the fitting rows before it; the search for a row's end
  includes its ink's reach, so a window of candidates cannot skip those rows
  ([#42](https://github.com/vocaro/MathMLLayout/issues/42)).
- Silent `none` and `mprescripts` children of `mmultiscripts` count toward the node bound in
  readings and layout, including incomplete script pairs discarded by a marker
  ([#46](https://github.com/vocaro/MathMLLayout/issues/46)).
- All six enclosing long-division styles move their frame clear of a sign that overflows an
  outer digit column, lengthening the top bar when it moves
  ([#48](https://github.com/vocaro/MathMLLayout/issues/48)).
- Performance regression tests compare CPU work against smaller cases rather than asserting
  wall-clock limits, so scheduler delays under heavy load do not fail them
  ([#45](https://github.com/vocaro/MathMLLayout/issues/45)).
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
- Three values that were misread ([#17](https://github.com/vocaro/MathMLLayout/issues/17)):
  - A unitless `0` is zero where a length has nothing to be a multiple of, so
    `framespacing="0 0"` puts the frame against the cells. It was taken as invalid and the
    default spacing used.
  - `display` on the root and `side` on `mtable` ignore case and surrounding space, like every
    other enumerated attribute: `display="BLOCK"` gave text style.
  - A color with a sign among its hex digits, such as `#+ff`, is no color. It was read as
    `#0ff`.
- `<mtable displaystyle="true">` sets its cells in display style, as MathJax and LaTeXML write
  `align`, `gather` and `cases`. The attribute was ignored on the table itself, so every fraction
  and sum in an aligned equation was set at its text size, a sum's limits beside it
  ([#6](https://github.com/vocaro/MathMLLayout/issues/6)).
- `mtable align` with a row number follows MathML 3: `axis N` puts row N's baseline on the line,
  as `baseline N` does, where it was one axis height too high, and a number that names no row is
  ignored, where it was taken for the nearest row
  ([#11](https://github.com/vocaro/MathMLLayout/issues/11)).
- A table's row and column lines end at its edges: each stuck out by half the rule's thickness,
  through the frame when there was one. And the box of `menclose notation="updiagonalarrow"`
  grows to hold the arrowhead, which was drawn outside it over content much wider than tall or
  much taller than wide ([#12](https://github.com/vocaro/MathMLLayout/issues/12)).
- Every horizontal arrow the operator dictionary calls stretchy stretches to its label. With
  STIX Two Math 28 of the 47 stayed at their natural width, `⇌ ⇋ ⟹ ⟸ ⟺ ⟼ ⇄ ⇆ ↠ ↣` among
  them, and with a font that has no MATH table all but `← → ↔ ⟵ ⟶ ⟷`. A long arrow now takes
  the assembly of its short form (`⟹` from `⇒`, `⟼` from `↦`), and an arrow the font cannot
  stretch is drawn with its glyph's shafts, heads, tails and barbs, as `⟶` was
  ([#13](https://github.com/vocaro/MathMLLayout/issues/13)).
- A stretchy operator that is the only child in flow of its row covers the row's space-like
  children: a bar, bracket or arrow beside a strut of `mspace` kept its natural size unless the
  row held a second operator or an identifier
  ([#8](https://github.com/vocaro/MathMLLayout/issues/8)).
- `minsize` sizes an operator that has nothing to cover, half each side of the axis, as MathML
  Core asks: TeX's `\big(`, written `<mo minsize="1.2em" maxsize="1.2em">(</mo>`, was an ordinary
  parenthesis when it stood alone or beside another fence
  ([#8](https://github.com/vocaro/MathMLLayout/issues/8)).
- A `maxsize` less than `minsize` is taken to be the `minsize`, and a negative `minsize` to be
  zero, as MathML Core asks. `maxsize` used to win
  ([#23](https://github.com/vocaro/MathMLLayout/issues/23)).
- `maction` and `semantics` are everywhere the child that is drawn: the one `selection` names,
  and the first that is not an annotation. A reading said the first child, so
  `<maction selection="2">` was read as what it did not show and a `semantics` whose annotation
  comes first as nothing; and an operator shown that way was not spaced or stretched as one. A
  fraction, power or root around either marks its end in a reading only when that child is
  more than a single token ([#16](https://github.com/vocaro/MathMLLayout/issues/16)).
- Layout time no longer grows with the cube of the nesting depth for rows of space-like
  children: 60 nested rows of 300 spaces took 4.5 s in a debug build and take 0.05 s. A
  hand-built tree with one row of spaces in many places is read once, where reading it could
  take without end ([#34](https://github.com/vocaro/MathMLLayout/issues/34)).
- An `lspace` or `rspace` written on an operator is applied where the operator has nothing
  beside it: alone in `math`, a table cell or a radicand, `<mo lspace="1em">=</mo>` was as wide
  as its glyph. The dictionary's spacing is still left off there, as TeX sets a lone atom
  ([#20](https://github.com/vocaro/MathMLLayout/issues/20)).
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
  - The annotations a `semantics` has before its child were passed over uncounted. A tree built
    by hand with ten thousand of them, under ten thousand parents that share them, was inside
    every bound and took most of a minute to lay out. They count toward the 20,000 nodes
    ([#40](https://github.com/vocaro/MathMLLayout/issues/40)).

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
  do the same; [doc/images.md](doc/images.md) has the details.

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

## 0.1.1

- Assigned the copyright to Vocaro Technologies LLC
  ([#2](https://github.com/vocaro/MathMLLayout/issues/2)). No API or behavior changes.

## 0.1.0

- First release, moved out of [EPUBLib](https://github.com/vocaro/EPUBLib) (at `35f7fdc`), where it
  was written for the native EPUB viewer
  ([vocaro/EPUBLib#3](https://github.com/vocaro/EPUBLib/issues/3)).
- Presentation-MathML layout and drawing with CoreText and the OpenType MATH table; parser,
  spoken readings, bounds on untrusted input. See [doc/markup.md](doc/markup.md) for what is supported.
- Every one of the 1,798 formulas in EPUBLib's real-book corpus lays out without a fallback.
