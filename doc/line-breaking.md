# Line breaking

Give a layout the width of its line and it breaks into rows that fit:

See [LineBreaking.swift](examples/LineBreaking.swift) for the complete Swift example.

The top-level `math` element's `maxwidth` is honored by default, following
[MathML 3 §2.2.1](https://www.w3.org/TR/MathML3/chapter2.html#interf.toplevel).
It can narrow the host's `maximumWidth` and `firstRowMaximumWidth`, never enlarge either.
Without `maxwidth`, each host budget keeps its existing meaning; the first-row budget can differ
from the remaining rows' budget. For example, with host widths of 200 and 80, `maxwidth="120px"`
allows 80 points on the first row and 120 on subsequent rows. `maxwidth="300px"` leaves both
host budgets unchanged.

Lengths use the engine's coordinates (one point equals one CSS pixel): `px`, `pt` (4/3 points),
`pc` (16 points), `in` (96 points), `cm`, `mm`, and `q` (a shared length parser extension) are absolute.
`em`, `ex`, and MathML named spaces use the root's effective font after its `mathsize` and
`scriptlevel` apply. Percentages
and unitless multiples refer to the host's `maximumWidth`, before any authored cap, not its
first-row budget or the formula's natural width. With no finite host width these relative
values are ignored, except zero; absolute and font-relative lengths can still cause wrapping.
These interpretations follow [MathML 3 §2.1.5.2](https://www.w3.org/TR/MathML3/chapter2.html#type.length).

Missing, invalid, negative, or nonfinite authored values leave the host budgets unchanged.
Zero is accepted: breakable units get separate rows, and any positive-width unbreakable unit
overflows, as it would with a zero host width. Widths above the engine's 50,000-point extent
bound are treated as unbounded; no larger formula could fit within that bound. `maxwidth` on
other elements is ignored. `widestUnbreakableWidth` still reports the formula's feasible minimum,
independently of the authored cap, so a host can detect overflow. Remove or enlarge a smaller
authored cap before retrying at that reported minimum. `overflow` preferences for
scrolling, eliding, truncating or scaling remain the host's responsibility.

- **Where it breaks.** Where the markup says (`linebreak="newline"`, at any width), and otherwise
  at operators ranked by the operator dictionary: at a relation sooner than at `+` or `−`, and
  there sooner than at `×` or an invisible times, with a penalty for each level of nesting. Never
  before a sign, after an opening fence, before a closing fence, or between a function and its
  argument. Separators break after; other operators start the next row and keep their spacing.
- **How deep.** Inside nested `mrow`, `mstyle` and `mfenced`, and inside the base of a script. A
  bracket pair split across rows keeps one size; a pair wholly on one row shrinks to that row's
  content after the breaks are chosen. Long `mtext` wraps at its logical U+0020 spaces. Arabic, Hebrew and mixed direction
  text are resolved and shaped for each selected line from the full token paragraph. Numbers,
  punctuation, neutral characters and directional controls retain that paragraph context;
  no-break spaces keep adjacent words together. An inherited `dir="rtl"` or `dir="ltr"` sets
  the text paragraph direction. Text with inline images and decorated `alt` fallbacks retains
  one logical paragraph too: CoreText places atomic image attachments alongside the text's
  per-line visual runs, while decorated fallback text keeps its local background. Images keep
  source ownership, logical dimensions and `valign`; edge whitespace and token alignment
  marks survive the selected logical ranges. A table wider
  than the line narrows its columns and wraps its cells, including spanning cells within
  their combined track widths and internal gaps. Alignment groups and embedded text marks
  survive cell breaks; all fragments of a source group share one horizontal shift, with
  [defined span scopes and minimum-width measurements](alignment-groups.md#wrapping-and-spans).
  Fraction parts, radicands and
  `menclose` contents wrap the same way. `mpadded`, `mphantom`, `merror` and background-bearing
  rows/tokens also flow across host rows. Explicit padding geometry is reapplied to each
  fragment; phantoms keep its spacing while drawing nothing. Each error fragment has its own
  frame, and each background fragment fills its own content rectangle. Eligible under/over
  bases repeat their attached annotations on every base fragment, with stretchy annotations
  resized to that fragment. See the fragmentation policy below and the remaining
  [atomic structures](limits.md#limitations).
- **Attributes** (MathML 3 §3.1.7): `linebreak`, `linebreakstyle`, `linebreakmultchar`,
  `lineleading`, `indentalign`, `indentshift`, `indenttarget` and their `first`/`last` forms, on
  `mo` and `mspace` or inherited from `mstyle` and `math`. Unless they say otherwise rows align
  left, and a display formula indents the rows after its first by one em.
- **Rows.** `rows` gives each row's `origin` (its baseline's left end, relative to the layout's),
  `width`, `ascent` and `descent`. The layout's baseline is its first row's, so `descent` reaches
  down through the last row. Each row's box covers its own ink.
- **Clipping.** A box covers the ink as it is laid out. A bitmap context then moves each glyph
  onto its pixel grid, down and to the left, and on macOS font smoothing thickens it, so ink can
  fall up to two device pixels outside the box. A host that clips to a box allows that much
  around it, or turns off `setShouldSubpixelQuantizeFonts` and `setShouldSmoothFonts` in its own
  context before drawing.
- **Too wide anyway.** A unit that cannot break (a long number, a wide radical) makes its row
  overflow. `widestUnbreakableWidth` is the narrowest `maximumWidth` at which none does; when it
  is more than the line, scale the formula.
- `axisHeight` is the math axis's height above the baseline, for centring rows as a table does.


RTL mathematical rows retain source-order break decisions and draw each selected line from
right to left, preserving the orientation and bidi shaping of each token. Opposite-direction
rows resolve their own breaks and remain atomic to the outer paragraph. Physical left/right
indentation and ID targets use the final drawn coordinates. RTL script boxes retain their staged LTR
base-row geometry and resolve those rows internally, keeping forced breaks and scripts on
the final base fragment. Token bidi direction remains inherited. Retained LTR text words in
RTL formulas are measured as drawn blocks, with assembly charged to the shared text-work
budget; formula-only candidates retain their constant-time ink summaries. See [alignment groups](alignment-groups.md)
for the table-specific policies.

## Indentation targets

[MathML 3 §3.2.5.2.3](https://www.w3.org/TR/MathML3/chapter3.html#presm.op.indent)
defines `indentalign="id"` as physical left-edge alignment to `indenttarget`. The referenced
element must precede the reference; a renderer may use `auto` when the element's position
does not permit alignment. The specification permits targets in `mphantom` and outside
the current `math`. This API receives one formula, so it has no coordinates for another
formula. Phantoms retain the geometry they would have drawn.

Within that formula, unique IDs in nested rows, selected `semantics`/`maction` branches,
decorated wrappers and script arguments can be targets for following lines of the enclosing
paragraph. Opposite-direction rows wrap independently and export their final placed target
coordinates. Coordinates include internal first/last-line indentation, center/right alignment,
ink coverage, script shifts, explicit negative padding offsets and resized fences. For example:

```xml
<math>
  <mspace width="20px"/>
  <mrow dir="rtl">
    <mspace width="20px" height="4px"/>
    <mspace linebreak="newline" indentshiftlast="6px"/>
    <mspace width="3px"/>
    <mspace id="target" width="7px" height="4px"/>
  </mrow>
  <mspace linebreak="newline" indentalign="id" indenttarget="target"/>
  <mspace width="5px" height="4px"/>
</math>
```

The target is on the independently wrapped row's second baseline, at physical x = 26 points
in the enclosing formula. The following host line begins at that same x. Nested output lines
remain within their containing host row: every target must belong to an earlier host output
row and have a final baseline above the receiving line. A target placed higher as a
superscript on the receiving host row does not create an earlier output line. Source order
alone cannot make a same-line or later-line target eligible.

Missing, duplicate, same-line, later-line and inadmissible references use `auto`; unselected
branches supply no anchors. IDs inside fractions, radicals, table cells, elementary stacks and
under/over arguments remain in their own argument frames. References from an independently
wrapped paragraph back out to a different receiving frame are not resolved. IDs on the
complete structural element itself remain eligible in its enclosing paragraph.

Placed metadata is retained as a balanced tree, translated during box assembly and walked
iteratively. ID lookup uses the existing logarithmic predecessor index. Final targets are
resolved once after selected rows, fences and center/right placement are known. Internal or
unbounded center/right alignment uses the widest provisional row as a fixed frame; an ID
continuation may extend the returned width beyond that frame. Recomputing the frame could
move its target indefinitely, so it is never retried to a fixed point.

## Wrapper fragmentation

Wrapper fragmentation is local to each selected host row. Nested wrappers rebuild from the
inside out after text shaping, surrounding only their own contiguous content rather than
neighbouring formula items. For explicitly authored `mpadded` geometry, absolute lengths
apply to every fragment; percentages, multiples, relative changes and `width`/`height`/`depth`
pseudo-units resolve against that fragment's unpadded content. The fragment's horizontal
advance then places following items; its ink remains covered even for negative offsets or
a declared width smaller than its content. A zero/no-op authored value follows the same policy.
Under/over annotations repeat on eligible breakable row bases; their annotation arguments
remain whole. Operator bases, movable limits, numeric tokens and script annotations retain
their boundaries. Opposite-direction rows use their own internal paragraph frame.

[Documentation index](../README.md#documentation)
