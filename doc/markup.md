# Supported markup

- **Tokens:** `mi`, `mn`, `mo`, `mtext`, `ms`, `mspace`, `mglyph`.
- **Grouping:** `math`, `mrow`, `mstyle`, `mpadded`, `mphantom`, `semantics`, `maction`, `merror`.
- **Scripts and limits:** `msup`, `msub`, `msubsup`, `mmultiscripts` (with `mprescripts`/`none`),
  `mover`, `munder`, `munderover`.
- **Fractions and roots:** `mfrac` (including `linethickness` and `bevelled`), `msqrt`, `mroot`.
- **Fences and enclosures:** `mfenced`, `menclose`.
- **Tables:** `mtable`, `mtr`, `mtd`, `mlabeledtr`.
- **Elementary math** (MathML 3 §3.6): `mstack`, `mlongdiv`, `msgroup`, `msrow`, `mscarries`,
  `mscarry`, `msline`: digit columns with `stackalign`, `charalign`, `charspacing`, `position` and
  `shift`; lines with their length, overhangs and thickness; carries with `location`, `crossout`
  and `scriptsizemultiplier`; and all ten `longdivstyle` values.

`mo` follows an operator dictionary for form, spacing, stretchiness, large operators and fences.
Stretchy operators use the font's MATH variants and assemblies. Attributes include `displaystyle`,
`scriptlevel`, `mathvariant`, `mathsize`, `mathcolor`, `columnalign` and table spacing.

Tables honor `rowspan` and `columnspan` using the [MathML 3 table model](https://www.w3.org/TR/MathML3/chapter3.html#presm.mtd).
Later cells skip occupied positions; shorter rows leave empty slots. A spanning cell measures
and aligns within all its tracks and their internal spacing. Single-track cells set initial
track sizes; a spanning deficit is shared equally across its tracks. Baseline-aligned row spans
anchor to the first row and distribute any missing depth across covered rows. `top`, `bottom`
and `center` align within the full spanning rectangle. Labels have an independent gutter and
may span rows without consuming main-grid positions. Internal solid and dashed rules stop
at spanning rectangles, including their share of adjacent gaps; rule caps and frames stay
inside table bounds. See [bounds and malformed-span handling](limits.md).

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
