# Supported markup

- **Tokens:** `mi`, `mn`, `mo`, `mtext`, `ms`, `mspace`, `mglyph`.
- **Grouping:** `math`, `mrow`, `mstyle`, `mpadded`, `mphantom`, `semantics`, `maction`, `merror`.
- **Scripts and limits:** `msup`, `msub`, `msubsup`, `mmultiscripts` (with `mprescripts`/`none`),
  `mover`, `munder`, `munderover`.
- **Fractions and roots:** `mfrac` (including `linethickness` and `bevelled`), `msqrt`, `mroot`.
- **Fences and enclosures:** `mfenced`, `menclose`.
- **Tables:** `mtable`, `mtr`, `mtd`, `mlabeledtr`, with `rowalign` (`top`, `bottom`,
  `center`, `baseline`, `axis`) and `columnalign`. A table's `rowalign` list applies by row,
  repeating its last value; a row's single value overrides it and a cell's overrides the row.
  An enclosing `mstyle` can set the table's default `rowalign` list; an explicit table value
  overrides that default. Nested style changes apply within their own scope.
  Labels inherit their row's vertical alignment and accept their own cell override. Alignment
  uses each cell's final size after wrapping; `axis` accounts for the cell's font size.
  Unspecified vertical alignment remains `baseline`
  ([MathML 3 §3.5](https://www.w3.org/TR/MathML3/chapter3.html#presm.mtable)).
  LTR and RTL `maligngroup`/`malignmark` support `groupalign` and `alignmentscope`
  ([alignment groups](alignment-groups.md)).
- **Elementary math** (MathML 3 §3.6): `mstack`, `mlongdiv`, `msgroup`, `msrow`, `mscarries`,
  `mscarry`, `msline`: digit columns with `stackalign`, `charalign`, `charspacing`, `position` and
  `shift`; lines with their length, overhangs and thickness; carries with `location`, `crossout`
  and `scriptsizemultiplier`; and all ten `longdivstyle` values.

`mo` follows an operator dictionary for form, spacing, stretchiness, large operators and fences.
Stretchy operators use the font's MATH variants and assemblies. Attributes include `displaystyle`,
`scriptlevel`, `mathvariant`, `mathsize`, `mathcolor`, `columnalign` and table spacing.
Inherited `dir` controls token shaping and structural progression, with local overrides;
see [the RTL policy for each schema](directionality.md).

Tables honor `rowspan` and `columnspan` using the [MathML 3 table model](https://www.w3.org/TR/MathML3/chapter3.html#presm.mtd).
Later cells skip occupied positions; shorter rows leave empty slots. A spanning cell measures
and aligns within all its tracks and their internal spacing. Single-track cells set initial
track sizes; a spanning deficit is shared equally across its tracks. Baseline-aligned row spans
anchor to the first row and distribute any missing depth across covered rows. `top`, `bottom`
and `center` align within the full spanning rectangle. Labels have an independent gutter and
may span rows without consuming main-grid positions. Internal solid and dashed rules stop
at spanning rectangles, including their share of adjacent gaps; rule caps and frames stay
inside table bounds. See [bounds and malformed-span handling](limits.md).

`equalcolumns="true"` solves a common track width from every cell's full spanning interval,
including internal gaps. `equalrows="true"` gives every row the same total height after
baseline/axis and spanning constraints; extra height is shared above and below its baseline.
Gaps and frame padding remain separate from track sizes.

Tables honor `width="auto"` or a nonnegative absolute, `em`, `ex`, percentage or unitless
length. Percentages and unitless table widths refer to the finite available line width,
including an authored `math maxwidth`; without one they remain automatic. The desired table
width includes gaps and frame padding; ordinary label gutters are additional and do not
participate in column percentages. The combined drawing is capped by the local host budget.
`columnwidth` lists repeat their final entry in source-column order, including
RTL tables. `auto` measures content, fixed lengths reserve at least that length, percentages
request a share of the entire table width, and `fit` divides remaining space equally. With
no authored table width, `fit` fills a finite local budget. Without a finite budget it is
automatic. Explicit column lengths also cause line wrapping in an otherwise unbounded layout.
Content minima and fixed column floors take precedence over desired width and host budgets:
unbreakable content overflows rather than clips. Percentage preferences are reduced toward
content minima when oversubscribed. Equal columns use the largest fixed or content constraint;
alignment groups can raise those minima. Extra desired width goes to `fit`, then `auto`, then
all columns. Invalid or negative sizing values are automatic; normal length bounds still apply.

A whole-cell embellished operator stretches vertically against eligible cells in its covered
rows or horizontally against eligible cells contained in its column interval. Compound cell
content retains ordinary row stretching. Explicit operator stretch and size attributes apply;
neighbours crossing the covered interval do not supply a stretch target. `leftoverlap` and
`rightoverlap` put labels at the physical grid edge without reserving a gutter. The label sits
above its covered row rectangle for `top` alignment, otherwise below, separated by
`minlabelspacing`; its drawing contributes to the final bounds. Ordinary `left`/`right` labels
retain their independent gutter. Label `columnspan` remains independent of the main grid.

Layout follows MathML Core with TeX's choices where it leaves room: a unary minus after `=` or
`(`, and a delimiter factor and shortfall so `f(x)` keeps plain parentheses. Text is an operand
to the operators beside it, so a word equation (`<mtext>` operands) is spaced like any other.
A label on a stretchy arrow is placed by the MATH table's StretchStack constants as OpenType
defines them, with the shifts from the baseline
([w3c/mathml-core#121](https://github.com/w3c/mathml-core/issues/121)); Core's text has them
from the arrow's ink, which sets the label far too high with STIX Two Math.
An operator with nothing beside it (alone in `math`, a table cell or a radicand) is not padded
with the dictionary's spacing, as TeX sets a lone atom, where Core pads it. An `lspace` or
`rspace` written on it is applied.

[Documentation index](../README.md#documentation)
