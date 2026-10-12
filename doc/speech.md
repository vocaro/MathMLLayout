# Spoken readings

See [Speech.swift](examples/Speech.swift) for the complete Swift example.

`accessibilityDescription(locale:)` reads a formula in English, French, German, Spanish or Italian
(`MathReading.languages`), whatever the locale's region. For any other language it returns the
English reading with `language` set to `"en"`, so the voice can match the words.
`accessibilityDescription` is the English reading. Stacks and long divisions are read row by row,
and an `mglyph` by its `alt`.

Selected wording has been checked against pinned MathCAT and Speech Rule Engine sources;
it has not been validated by native speakers. The [wording audit](../Documentation/SpeechWordingAudit.md)
records the evidence, changes and remaining questions from [#31](https://github.com/vocaro/MathMLLayout/issues/31).

[Documentation index](../README.md#documentation)
