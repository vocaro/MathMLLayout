# Bounds and limitations

For the latest measured results and platform details, see
[0.3.1 release verification](https://github.com/vocaro/MathMLLayout/blob/0.3.1/doc/testing.md#031-release-verification).

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. The stack guard can also reject
layout for insufficient remaining stack before the depth ceiling. Readings obey the source
node, depth, text and stack bounds, leaving out content past them. `MathMLNode.parse(xml:)`
refuses document type declarations in any encoding, so no entity expands and nothing external
loads; it reads at most 4 MiB. The general lessons are in
[shared stack and work bounds](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/stack-and-work-bounds.md#a-depth-limit-does-not-bound-stack-or-total-work)
and [shared untrusted-markup screening](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/document-parsing.md#screen-untrusted-markup-before-any-parser-sees-it).

Width fitting permits at most 1,114 complete layout passes. Within each pass, tables reserve at
most 20,000 occupied grid slots apiece; initial table construction shares 200,000 occupancy
probes/label-span row visits. Valid spans above 20,000, excessive occupied area or exhausted
work throw `MathLayoutError.limitExceeded`; malformed/zero spans use one, and row spans stop
at the last source row. Cell, wrapper-fragment and retained-fence rebuilds share separate limits
of 1,280,000 node visits and 200,000 table-work visits per pass; cached tables charge their
original descendant count and measured grid work. Private recipe engines keep independent
measurement caches and share only a small counter object, so retaining a recipe does not retain
its source table cache or create a cache/recipe/engine ownership cycle.
Logical text range requests and row assembly share 2,000,000 units per pass: requested UTF-16
range lengths (including cache hits), row units, wrapper reconstruction placements and annotation
descendants visited, and neighboring-element fragment edges generated for alignment marks,
including retained-word candidate assembly in RTL
paragraphs. This counter does not measure elapsed time or CoreText's internal paragraph
resolution and shaping cost. Long logical paragraphs can still take substantial time.
Narrow paragraphs can exhaust the budget before the input limit. The general method is in
[shared work budgets](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/stack-and-work-bounds.md#work-budgets-charge-cached-work-its-original-cost).

### Worker stack coverage

Layout runs on the calling thread. Single-child wrapper descent, line-breaking descent and
drawing-item traversal use heap cursors; structural elements and speech still recurse. The
stack guard retains a 128 KB reserve for remaining work, font operations and host callbacks.
The engine neither enlarges the caller's stack nor moves layout to another thread
([shared remaining-stack guard](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/stack-and-work-bounds.md#a-remaining-stack-guard-keeps-a-reserve-for-work-it-cannot-see)).

`WorkerDepthTests` asserts these 64-level shapes on an **exactly 512 KB** worker in debug and
release, against an 8 MB reference worker. Leaves are `mi` containing `x`; structural siblings
are `mn` containing `1`. Fixtures use the default math font, 12-point style, default attributes,
no images and unconstrained width. Geometry, drawing-item counts, ink bounds, a 128×128-pixel
rendering and all five base-language readings are compared with the reference and repeated runs.

| Shape | Wrappers above the leaf |
| --- | --- |
| Single-child `mrow`, `msqrt`, `mstyle`, `mpadded`, `semantics` | 63 |
| Numerator-nested `mfrac`, base-nested `msup`, radicand-nested `mroot` | 63 |
| Single-cell `mtable` → `mtr` → `mtd` | 21 tables (63 element levels) |
| Script-nested `msub`, base-nested `munderover` | 48, plus 15 outer `mrow` |

The [0.3.0 release verification](https://github.com/vocaro/MathMLLayout/blob/0.3.1/doc/testing.md#030-release-verification) on 2026-10-13
repeated these assertions and measured all eleven optional pure-chain fixtures in macOS debug,
macOS optimized and iOS. Every sweep reached 64 element levels: 63 wrappers, or 21 three-element
table wrappers, including pure subscript and under-over chains. The sweep checks successful
`MathLayout` construction only; it does not perform the fixed matrix's rendering/readings
comparisons above. The linked verification records the compiler and platform versions.

Additional fixed 64-level tests cover the same shape matrix with inherited `dir="rtl"`,
and RTL table alignment through 58 nested rows, including a wrapped neighboring-element
target. Geometry, drawing-item counts, ink, pixels and all five base-language readings match
the 8 MB reference on an exactly 512 KB worker, including repeated runs. Generated sign
reflection keeps the font's glyph runs and introduces no extra drawing-tree depth.

These fixtures do not establish universal 64-level coverage. Different attributes, fonts,
stretched operators, width constraints or callbacks can reach the stack guard sooner. Smaller
workers may safely reject bounded inputs; tests include exact 128 KB and 256 KB stacks and the
requested-stack sweep down to 16 KB. Stack-sensitive results require remeasurement after
compiler/platform changes; see [Worker depth](testing.md#worker-depth). The general method is in
[shared small-worker comparison](https://github.com/vocaro/vocaro-engineering/blob/main/knowledge/apple/stack-and-work-bounds.md#compare-a-small-worker-against-a-reference-worker-in-debug-and-release).

## Supported behavior

- **Wrapping and widths.** `mpadded`, `mphantom`, errors and background-bearing rows/tokens
  can fragment across host rows; phantom fragments stay invisible. Explicit padding lengths
  resolve against each fragment, and error/background decorations surround each fragment's
  own content. Eligible under/over bases repeat their attached annotations on each fragment.
  Plain and mixed-image `mtext` wraps at logical U+0020 spaces with full-paragraph bidi
  context and per-line shaping. Decorated fallback `alt` participates in that same paragraph,
  retaining its local background. Each image and no-break segment stays whole; authored edge
  spaces, direction controls, baseline offsets and token alignment marks survive wrapping.
  Nested tables narrow inside breakable cell rows, retaining unbreakable content
  and fixed frame/label space. Root `maxwidth` can narrow host line budgets. See
  [Line breaking](line-breaking.md).
- **Text measurement.** Plain ASCII letters, digits and U+0020 spaces under LTR/natural
  direction reuse their full-token glyphs and word metrics in one pass, provided CoreText
  preserves separate space clusters. Other plain text retains full-paragraph bidi context
  and per-line shaping. Formula-only candidate spans use constant-time ink summaries even
  in paragraphs containing logical text. The work budgets above still apply.
- **Indentation.** `indenttarget` resolves unique descendant IDs on earlier output lines of
  the receiving paragraph, including final coordinates exported from independently wrapped
  rows, decorated wrappers and script arguments. Nested baselines must precede the receiving
  baseline. Metadata traversal, indexing and final placement are bounded and add no wrapping
  retries. See [Line breaking](line-breaking.md#indentation-targets).
- **Direction and elementary math.** Inherited `dir` controls token shaping and structural
  progression in rows, table columns and layout schemata. RTL scripts attach on the left;
  surds/root degrees move right; beveled fractions and directional enclosures reverse
  progression. Children retain their own shaping and local overrides. Physical alignments,
  glyph accent attachments and explicit enclosure sides remain physical. A number's `mglyph`
  occupies one logical column, sized to its image or entire fallback. See
  [Directionality](directionality.md) and [Direction and columns](elementary-direction.md).
- **Tables.** Row and column spans use a bounded sparse grid; overlapping requests advance
  to a vacant rectangle in source-column order. Ordinary labels have independent gutters;
  overlap labels use the physical table edges without reserving those gutters. Equal tracks,
  authored table/column widths and whole-cell operator stretching share the bounded grid
  pipeline. Row/cell
  vertical alignment uses final cell geometry; a row with only top/bottom/center entries has
  a midpoint baseline, and ordinary labels contribute to row height. Overlap label ink is
  included in the final bounds. LTR and RTL alignment groups and
  marks survive forced and automatic cell wrapping. Row spans share their column's groups.
  Token marks also align beside inline images, legacy glyphs and fallbacks. Left/right edges
  and label sides remain physical.
  See [Alignment groups](alignment-groups.md).
- **Images and legacy glyphs.** The host can supply intrinsic image scale or logical size;
  markup can override image dimensions. An `mo` containing `mglyph` preserves author sizing
  and baseline by default. Explicit `stretchy="true"`/`largeop="true"` opts into whole-token
  affine stretch/display enlargement; dictionary defaults alone do not alter that geometry.
  Renderer-specific `imagestretchdirection` or `MathImage.stretchDirection` supports image-only
  horizontal operators; optional host metrics supply physical italic clearance and top-accent
  attachment for single-image tokens, scaling with image geometry.
  Legacy font/index glyphs use one installed font's exact PostScript/full/family name and a
  bounded decimal glyph ID. Unsupported inputs use `alt`; `src` presence selects the image
  path even when unresolved. See [Images](images.md) and [Image operators](image-operators.md).
- **Script kerning and MATH adjustments.** MathKernInfo applies to pairs of single,
  unpositioned math-font glyphs, including the physical adjoining corners of RTL scripts.
  Supported VariationIndex records use the selected font instance; Device records opt in
  through a fixed layout-time output scale. See [Fonts](fonts.md).
- **Speech.** Built-in readings support English, French, German, Spanish and Italian, plus
  a narrow `en-GB` bracket vocabulary. Complete custom languages and regional compositions
  use the per-call [vocabulary extension contract](speech-locales.md). Selection tries the
  exact supported canonical locale, then its base language, then English for the whole reading,
  without borrowing individual English terms into a selected vocabulary.
  Recognized mathematical symbols in `mi`/`mo` have localized names; unknown identifiers,
  `mtext`, `ms` and token `alt` retain author wording. Embedded `mglyph` descriptions follow
  source order; each glyph in an elementary number reserves one logical column. Missing or
  empty `alt` is silent but still reserves its column. Stacks and divisions describe logical
  columns, carries, crossouts, line endpoints and frames. French root/limit templates elide
  `de` before written vowels except `oui`, `onze` and `onzième`. See [Spoken readings](speech.md).

## Limitations

The following restrictions remain in the current implementation:

- **Wrapping and widths.** Numeric tokens and script annotations remain atomic; no breaks
  occur between adjacent identifiers or inside numbers. Under/over operator bases, movable
  limits and bases without a breakable row remain atomic. Opposite-direction rows resolve
  their breaks internally and remain atomic to the enclosing paragraph. Unrecoverable
  simple-text fast-path segment origins remain atomic.
  A smaller authored `maxwidth` must be removed/enlarged when retrying at
  `widestUnbreakableWidth`. `overflow` remains a host concern.
- **Indentation.** Independently wrapped paragraphs export targets to subsequent host output
  lines; references from their own lines back out to another receiving frame remain unresolved.
  Fraction/radical arguments, table cells, elementary stacks and under/over arguments retain
  separate frames. Other formulae and unselected content provide no coordinates. Phantoms do
  retain their would-be placed geometry. Absent, duplicate, same-line, later-line and otherwise
  inadmissible targets fall back to `auto`.
  Unbounded/internal center/right alignment uses a common frame chosen before ID placement;
  an ID continuation can extend the returned width beyond that frame.
- **Direction and elementary math.** Elementary grids, numeric text and division frames
  retain their LTR policy under surrounding RTL direction. `decimalpoint` names one character. A number's
  `mglyph` occupies one column; its `alt` supplies neither a decimal separator nor several
  digit columns. Division frames are drawn, not font glyphs. The remaining per-schema
  restrictions and direction-changing scope policies are in [Directionality](directionality.md).
- **Tables.** Fixed column floors and content minima can exceed the available width;
  percentage/fit sizing is a preference above
  those minima, and oversubscribed percentages reduce toward them. Invalid/negative widths
  are automatic, unresolved relative table widths are automatic without a finite host, and
  ordinary MathML length limits apply. Allocation uses a fixed 48-step search, never retries
  to solve percentages. Stretch neighbor visits share the existing table-work bound, and
  stretching shares cell-rebuild/stack limits. A label's `columnspan` adds no main-grid columns.
  Alignment groups in
  column spans interact only within identical source-column intervals; spans crossing a
  mixture of scoped and unscoped columns consume their internal markers.
- **Images and legacy glyphs.** Compound text/image and multiple-image tokens have no
  whole-token italic-correction or accent-attachment metrics. Image metrics are deliberate
  renderer-specific host metadata, never inferred from pixels, text or `alt`.
  Legacy font lookup uses installed fonts only; unsupported fonts, variants,
  indices or legacy dimension/offset combinations use `alt`.
- **Script kerning and MATH adjustments.** Compound expressions, fallback runs and glyph
  assemblies use zero corner kerning. Device corrections default to off. Variation corrections
  support GDEF 1.3 with normal signed 16-/8-bit delta rows and `fvar`/`avar` 1.0; unsupported
  normalization/store formats and malformed records retain unadjusted metrics. See [Fonts](fonts.md)
  for parsing and cache bounds.
- **Speech.** Readings do not infer arithmetic meaning, translate author wording, infer
  silent/aspirated `h` or unwritten letter pronunciations, or determine author-text language.
  Custom composers are trusted host code and must produce output proportional to bounded
  operands. Letter-name usage, regional naturalness and novel spatial wording still need human validation in
  [issue #63](https://github.com/vocaro/MathMLLayout/issues/63).

[Documentation index](../README.md#documentation)
