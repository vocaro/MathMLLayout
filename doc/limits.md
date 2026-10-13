# Bounds and limitations

## Bounds

Input is treated as untrusted. A formula deeper than 64 levels, larger than 20,000 nodes, longer
than 50,000 UTF-16 units of text, more than 50,000 points in any dimension, or with more than
100,000 drawing items throws `MathLayoutError.limitExceeded`. So does one nested deeper than the
calling thread's stack has room for, within those 64 levels: a typical worker's 512 KB stack
can be spent in about twenty levels by an unoptimized build. Readings are bounded the
same way and leave out what is past the bounds. `MathMLNode.parse(xml:)` refuses document type
declarations in any encoding, so no entity expands and nothing external loads; it reads at most
4 MiB.

## Limitations on main

- **Line breaking.** No breaks inside `mpadded`, `mphantom`, `merror`, `munder`/`mover`/
  `munderover`, a script, or a row with a `mathbackground`; none between adjacent identifiers or
  inside a number. `indenttarget` must name a child of a row
  being broken, on an earlier row. `malignmark` and `maligngroup` align nothing. A table inside
  a table cell does not narrow, and `mtext` with a right-to-left run, an image, or an `alt`
  drawn on a `mathbackground` of its own does not wrap.
  `overflow` and `maxwidth` on `math` are not read:
  the host decides by the `maximumWidth` it passes.
- **`mglyph`.** MathML 2's `fontfamily` and `index` glyphs have no image and show their `alt`.
  An image has no scale of its own: size a 2x asset with `width` and `height`. An `mo` with an
  `mglyph` keeps the size its author gave it: it is not stretched, enlarged or centred on the
  axis.
- **Elementary math.** Columns run left to right only. `decimalpoint` names one character. An
  `mglyph` in a stack's number is not drawn. Division frames are drawn, not font glyphs.
- **Speech.** English, French, German, Spanish and Italian; a locale's region and script do not
  change the vocabulary, and other languages fall back to English. Recognized mathematical
  symbols in `mi` and `mo` have localized names; unknown identifiers, `mtext`, `ms` and image
  `alt` retain author wording and are not translated. Stacks and long divisions describe logical
  columns, carry locations and crossouts, line endpoints and division frames, without inferring
  arithmetic meaning. French root and limit templates elide `de` before a written vowel,
  preserving `de` before `oui`, `onze` and `onzième`; they do not infer silent/aspirated `h`,
  unwritten letter pronunciations or the language of author text. Letter-name usage, regional
  naturalness and the novel spatial wording still need human validation in
  [issue #63](https://github.com/vocaro/MathMLLayout/issues/63). See [Spoken readings](speech.md)
  for the supported templates and remaining review scope. Readings obey source node, depth,
  text and thread-stack bounds, leaving out content past them.
- Cell spans in `mtable` are ignored, and rows align on their baselines only.
- No kerning from the font's MathKernInfo.

## Pending draft changes — not available on main

The following drafts address issues #66–82. The limits above describe `main` at `57af55f`;
these implementations are separate proposals, not a combined release. See the
[integration note](#integration-note) before combining them.

- **Tables.** [PR #91](https://github.com/vocaro/MathMLLayout/pull/91) adds row/cell vertical
  alignment; rows with only top/bottom/center entries use a midpoint baseline, and labels
  contribute to row height. Equal tracks and authored table/column widths remain unsupported.
  [PR #95](https://github.com/vocaro/MathMLLayout/pull/95) adds bounded spans (20,000 occupied
  slots per table; 200,000 shared occupancy probes/label-span visits per pass), with label
  columns remaining separate gutters. [PR #87](https://github.com/vocaro/MathMLLayout/pull/87)
  fits nested tables inside breakable cell rows, retaining unbreakable content, frames and
  labels; cell rebuilds share a 1,280,000-node work budget per pass.
  [PR #98](https://github.com/vocaro/MathMLLayout/pull/98) adds LTR alignment groups and marks.
  Aligned cells stay indivisible under automatic wrapping; forced breaks and non-default
  spans opt out. RTL alignment and token marks mixed with `mglyph` remain staged.
- **Wrapping and widths.** [PR #93](https://github.com/vocaro/MathMLLayout/pull/93) fragments
  default padding and phantoms, preserving invisible phantom fragments. Explicit padding
  dimensions/offsets stay atomic; errors and backgrounds wrap into one decorated stack;
  under/over structures and script annotations remain atomic.
  [PR #97](https://github.com/vocaro/MathMLLayout/pull/97) wraps text containing inline images
  and decorated `alt` at ordinary spaces, keeping images and no-break segments whole.
  [PR #101](https://github.com/vocaro/MathMLLayout/pull/101) wraps plain `mtext` in logical order
  with full-paragraph bidi context and per-line shaping. Its decorated/image tokens stay
  atomic, and shaping/row assembly shares a 2,000,000-unit work budget per pass.
  [PR #90](https://github.com/vocaro/MathMLLayout/pull/90) lets root `maxwidth` narrow host
  budgets; `overflow` remains a host concern. Retrying at `widestUnbreakableWidth` requires
  removing or enlarging a smaller authored cap.
- **Indentation.** [PR #99](https://github.com/vocaro/MathMLLayout/pull/99) preserves unique
  descendant ID anchors on earlier lines in the same broken paragraph. Independently wrapped
  paragraphs have no shared anchor coordinates; absent, duplicate, same/later-line targets
  fall back to `auto`. Bounded indexing and a final placement pass add no wrapping retries.
  Unbounded/internal center/right alignment uses a common frame chosen before ID placement;
  an ID continuation can extend the returned width beyond that frame.
- **Images and elementary math.** [PR #89](https://github.com/vocaro/MathMLLayout/pull/89)
  adds intrinsic image scale/logical size. [PR #92](https://github.com/vocaro/MathMLLayout/pull/92)
  draws a number's `mglyph` as one elementary column; its entire fallback stays in that column
  and supplies no decimal separator. [PR #88](https://github.com/vocaro/MathMLLayout/pull/88)
  applies inherited direction within token text while elementary grids, numbers and frame
  sides retain the LTR policy; general layout schemata still progress LTR.
  [PR #96](https://github.com/vocaro/MathMLLayout/pull/96) supports bounded installed-font
  legacy glyph indices, using `alt` for unsupported names, variants or indices; it downloads
  no font. [PR #94](https://github.com/vocaro/MathMLLayout/pull/94) adds explicit whole-token
  stretch/display enlargement. Dictionary defaults alone preserve author sizing; image-only
  horizontal direction still requires surrounding operator text, and images supply no font
  italic-correction or accent-attachment metrics.
- **Script kerning.** [PR #86](https://github.com/vocaro/MathMLLayout/pull/86) applies
  MathKernInfo to pairs of single, unpositioned math-font glyphs. Compound expressions,
  fallback runs and glyph assemblies use zero corner kerning; device/variation corrections
  remain ignored.
- **Speech extension.** [PR #100](https://github.com/vocaro/MathMLLayout/pull/100) adds a per-call
  catalog of complete custom vocabularies and a narrow built-in `en-GB` bracket vocabulary.
  Selection tries the exact canonical locale, then its base language, then English for the
  whole reading; it never borrows individual English terms into a selected language.
  Author text remains literal, custom composers are trusted host code, and this adds no human
  validation of regional wording or pronunciation. [Issue #63](https://github.com/vocaro/MathMLLayout/issues/63)
  remains unresolved.
- **Worker depth.** [PR #102](https://github.com/vocaro/MathMLLayout/pull/102) reduces stack use
  with heap traversals and smaller contexts, retaining a 128 KB reserve and the 64-level ceiling.
  Its debug/release matrix on an exactly 512 KB worker uses the default math font, 12-point
  style, default attributes, no images and unconstrained width, matching geometry, rendering
  and five readings against an 8 MB worker. Leaves are `mi` containing `x`; structural siblings
  are `mn` containing `1`. These results were measured on arm64 macOS 27 with Swift 6.4:

  | Wrappers above an `mi` leaf | Tested count |
  | --- | --- |
  | Single-child `mrow`, `msqrt`, `mstyle`, `mpadded`, `semantics` | 63 |
  | Numerator-nested `mfrac`, base-nested `msup`, radicand-nested `mroot` | 63 |
  | Single-cell `mtable` → `mtr` → `mtd` | 21 tables (63 levels) |
  | Script-nested `msub`, base-nested `munderover` | 48, plus 15 outer `mrow` |

  This is not universal 64-level coverage: pure subscript/under-over chains and different
  attributes, fonts, stretching, width constraints or callbacks can exhaust the stack sooner.
  The layout-only measurement sweep reached 60/54 levels for pure subscript/under-over chains
  in debug, versus 64/64 in release; compiler/platform changes require remeasurement.
  Smaller workers may safely reject bounded inputs; the engine neither enlarges the caller's
  stack nor moves layout to another thread.

### Integration note

These drafts overlap shared table, wrapping and image sources and have not been tested together.
Combined integration must retain table/context metadata across the table drafts; reconcile image
segments with plain-text logical ranges; preserve phantom flags on decorated leading spaces and
LTR elementary frame exceptions; update legacy-glyph stretch expectations for explicit geometry;
and carry indentation anchors, leading-space trimming and opaque handling through heap traversals.
The linked PRs contain individual validation; combined regression tests remain necessary before
updating the current-support limits above.

[Documentation index](../README.md#documentation)
