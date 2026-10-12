# Spoken readings

See [Speech.swift](examples/Speech.swift) for the complete Swift example.

`accessibilityDescription(locale:)` reads a formula in English, French, German, Spanish or Italian
(`MathReading.languages`), whatever the locale's region. For any other language it returns the
English reading with `language` set to `"en"`, so the voice can match the words.
`accessibilityDescription` is the English reading. Stacks and long divisions are read row by row,
and an `mglyph` by its `alt`.

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
| French | indice droit | exposant droit | indice gauche | exposant gauche |
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
it has not been validated by native speakers. The [wording audit](../Documentation/SpeechWordingAudit.md)
records the evidence, changes and remaining questions from [#31](https://github.com/vocaro/MathMLLayout/issues/31).

[Documentation index](../README.md#documentation)
