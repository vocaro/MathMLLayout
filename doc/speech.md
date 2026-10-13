# Spoken readings

See [Speech.swift](examples/Speech.swift) for the complete Swift example.

`accessibilityDescription(locale:)` reads a formula in English, French, German, Spanish or Italian
(`MathReading.languages`), whatever the locale's region. For any other language it returns the
English reading with `language` set to `"en"`, so the voice can match the words.
`accessibilityDescription` is the English reading. Stacks and long divisions are read row by row with logical column positions,
and an `mglyph` by its author-supplied `alt`. Text and image descriptions are not translated.

## Structural readings

Side limits on a large operator (`msubsup`, including a single operator selected through
`semantics` or `maction`) use the same from/to wording as `munderover`. Ordinary bases
retain subscript/power wording, with an ending for compound powers. An explicit
`largeop="false"` disables the limit interpretation.

Recognized under-accents name the accent and its position. Bars below a base use the
underbar name; a lower brace uses the underbrace name. An explicit `accent="false"` or
`accentunder="false"` preserves the ordinary over/under reading. Combined under/over
accents are read lower first, then upper. Prime sequences, whether repeated ASCII/Unicode primes or double/triple/quadruple-prime
characters, announce each prime within the source-text budget. Mixed strings retain
ordinary exponent wording.

`mfenced` reads its configured separators: whitespace is ignored, an empty list inserts
nothing, and the last separator repeats when there are more gaps than separators.
Known mathematical symbols in `mi`, including infinity, receive the same localized name
as in `mo`. `mtext`, `ms`, unknown identifiers, and image `alt` retain author wording.

Square and cube roots retain their special names. Indices 1 and 4–10 use source-backed
ordinal forms in all five languages. The conventional variable `n` uses an ordinal in
English, French, German and Italian; Spanish uses `raíz de índice n de x fin de raíz`.
Spanish numeric roots follow MathCAT's ordinal-first order, for example `cuarta raíz de x`.
Other numeric or compound indices use an explicit index phrase.
French root and limit templates elide `de` before a written vowel (`d'a`); they do not infer
silent/aspirated `h`, unwritten letter pronunciations, or the language of author text.
The disjunctive words `oui`, `onze` and `onzième` retain `de`.
The choice to elide before vowel-letter variables is a deterministic speech policy;
letter-name usage and regional naturalness still need human validation, tracked in
[issue #63](https://github.com/vocaro/MathMLLayout/issues/63).

## Elementary math and columns

Every stack announces its alignment and the column of each cell. Column zero is the
alignment reference, and column numbers increase to the right. Negative columns lie to
its left. For decimal alignment, the decimal separator (or the implied separator after
the first number) occupies column zero before position offsets. Right alignment uses the
boundary after the last cell as its reference. Center alignment uses the middle cell,
or the cell to the right of the middle for an even count. These are the same logical
coordinates used by drawing, independent of font or physical widths.

`position` and every group's incremental `shift` accumulate, including shifts past lines
and nested groups. Numbers directly in a stack row are spelled digit by digit, naming
point, comma and grouping space literally; punctuation is not guessed to be a decimal or
grouping separator. `mstyle` is transparent to the grid, `none` names a blank column, and a
compound formula occupies one cell. Decimal-point settings inherited from `math`/`mstyle`
and changes within row styles determine the alignment. A finite line names its first and
last columns, including a one-column line; zero length names the whole stack width.

Carries name their columns and compass locations. A child's valid location overrides the
row location; an invalid location uses the row's. The crossout target is the annotated column’s digit, irrespective of the carry’s compass location.
Crossouts name all recognized drawn
strike styles in a fixed order: upward diagonal, downward diagonal, vertical, horizontal.
An explicit child crossout overrides the row, including `none`. A `none` slot has neither
a location nor a crossout. The introduction says **carries or borrows** because MathML
uses `mscarries` for both and does not encode which operation the annotation represents.
No subtraction heuristic guesses that a particular annotation is a borrow.

Long division describes the divisor/result positions and its frame, distinguishing all ten
supported `longdivstyle` values. Unknown values use the drawing default; the specification's
`mediumrightright` alias is accepted. Divisor, dividend and result keep their explicit labels,
then working rows follow. Standalone numeric divisor tokens and results placed beside the dividend are spelled digit by
digit. A result drawn above the dividend names its shared columns; grouped operand rows retain
their own positions and shifts.

Speech still obeys source node, depth, text and thread-stack limits. Generated line endpoints
use constant space even for extreme `length` attributes; omitted content is not recovered by
an accent, prime, squared-power or root shortcut. Logical coordinates describe presentation,
not inferred arithmetic meaning. Spatial wording is composed for this engine and has not
been certified by native speakers or assistive-technology users.

## Multiscripts

`mmultiscripts` reads the base first, then the right script pairs, then the left script
pairs after `mprescripts`. Pairs follow source order: in the left-to-right layout,
right pairs go from nearest to farthest from the base, while left pairs go from
farthest to nearest. Each pair reads its subscript before its superscript. Every nonempty script
names its side and kind. A `none` is silent but still occupies its slot, and an empty
pair is silent. Compound scripts include a closing phrase; single tokens, including
those selected through `semantics` or `maction`, do not.

For example:

```xml
<math>
  <mmultiscripts>
    <mi>C</mi><mi>k</mi><none/>
    <mprescripts/><mi>n</mi><none/>
  </mmultiscripts>
</math>
```

The English reading is `C right subscript k left subscript n`.

| Language | Right subscript | Right superscript | Left subscript | Left superscript |
| --- | --- | --- | --- | --- |
| English | right subscript | right superscript | left subscript | left superscript |
| French | indice droite | exposant droite | indice gauche | exposant gauche |
| German | rechter unterer Index | rechter oberer Index | linker unterer Index | linker oberer Index |
| Spanish | subíndice derecho | superíndice derecho | subíndice izquierdo | superíndice izquierdo |
| Italian | pedice destro | apice destro | pedice sinistro | apice sinistro |

Compound scripts close with `end subscript` / `end superscript` (en),
`fin d'indice` / `fin d'exposant` (fr), `Ende Index` (de),
`fin de subíndice` / `fin de superíndice` (es), or `fine pedice` / `fine apice` (it).
For example, a right subscript containing `n + 1` reads
`right subscript n plus 1 end subscript`. Nested multiscripts close before the
next outer script. The order is the same in every supported language and fallback.
For incomplete, nonconforming pairs, speech reads the available slot; every
`mprescripts`, including a repeated marker, resets to a left subscript slot.

Selected wording has been checked against pinned MathCAT and Speech Rule Engine sources;
matching rules, locale maps and fixtures are accepted as evidence for these terms without
requiring a fresh translation review. Underbar and brace names and bounded root ordinals now
also follow those sources. This does not claim new native-speaker or voice validation.

Fresh linguistic review is limited to the novel elementary-math descriptions (columns,
alignment, lines, carry/borrow locations and crossouts, division frames), compound-script
closing and other scoped combinations without matching upstream utterances, and French
joining of arbitrary formula/letter readings. The [wording audit](speech-wording-audit.md#accepted-evidence-and-remaining-human-review-scope)
records exact evidence and adaptations for the completed [#31](https://github.com/vocaro/MathMLLayout/issues/31).
The remaining human review is tracked in [issue #63](https://github.com/vocaro/MathMLLayout/issues/63).
The [review packet](speech-review/README.md) provides concrete examples in
all five languages, rendered context and a checklist for reporting case-level findings.
Listening with host voices remains useful usability QA; it is not a blanket wording gate.

[Documentation index](../README.md#documentation)
