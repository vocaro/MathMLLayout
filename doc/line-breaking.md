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
  content after the breaks are chosen. Long `mtext` wraps at its spaces. A table wider
  than the line narrows its columns and wraps its cells; fraction parts, radicands and
  `menclose` contents wrap the same way.
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

[Documentation index](../README.md#documentation)
