# Speech wording audit for issue #31

Audited on 2026-10-12 against these pinned revisions:

- [MathCAT `85c89a37073d6efdb08efba5765dd69c7efddaf9`](https://github.com/daisy/MathCAT/tree/85c89a37073d6efdb08efba5765dd69c7efddaf9) (MIT).
- [Speech Rule Engine `28cac44da8eba13bce646823183e959d6d943e79`](https://github.com/Speech-Rule-Engine/speech-rule-engine/tree/28cac44da8eba13bce646823183e959d6d943e79) (Apache-2.0).

Scope: the wording table and wording questions in
[issue #31](https://github.com/vocaro/MathMLLayout/issues/31).
This is a source comparison, not native-speaker or screen-reader-user validation.
The engine's structural omissions are recorded below, not repaired by this audit.

## How evidence was used

Prefer a rule for the actual construct, then a test in the requested language, then a
symbol name. Preserve MathMLLayout's operand order, explicit closing phrases and whole-language
fallback. A different upstream phrase does not by itself prove the former wording wrong.
The changes below choose traceable upstream forms, without claiming a regional classroom standard.

MathCAT's `SharedRules/default.yaml` `diacriticals` rule reads a variable followed by its
accent. Its French and German `shared.rs::modified_vars` tests exercise that construction.
Its Spanish test of the same name calls `test("en", ...)` and expects English; it is **not**
Spanish-language verification. Several Unicode entries cite Google or DeepL, so upstream
agreement is supporting evidence, not proof of independent human review. MathCAT has no Italian
language directory at this revision.

SRE's symbol maps supply names, not necessarily complete utterances. Its German `overbar`
action and Italian `Bar001` ClearSpeak expectation give direct evidence for a bar over a
variable. SRE's `alphabets.json::greekSmall[26]` supplies the name of ∂; its
[alphabet definition](https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/speech_rules/alphabet.ts) substitutes U+2202 into the Greek
small-letter sequence at that position.
The [Bar001 input][S-bar-input] is `<mover accent="true"><mi>f</mi><mo>¯</mo></mover>`;
its German and Italian expected readings directly support the postfix bar names below.

## Decisions for every entry in the wording table

“Changed” means an upstream form was adopted. “Kept” means evidence supports the existing
form or its name within MathMLLayout's template. “Uncertain” means the inspected rules/tests
do not resolve the question. The source references below point to immutable files.

| Construct | French | German | Spanish | Italian |
| --- | --- | --- | --- | --- |
| Double-dot accent | **Changed:** `x tréma` [M-fr-test], [M-fr-full], [S-fr-symbols] | **Changed:** `x diaeresis` [M-de-test], [S-de-symbols] | **Changed:** `x diéresis` [M-es-full], [S-es-symbols] | **Changed:** `x dieresi` [S-it-symbols] |
| Check accent | **Kept:** `x caron` [M-fr-test], [M-fr-full] | **Changed:** `x Caron` [M-de-test], [M-de-full]; capitalize the name in this vocabulary | **Kept:** `x carón` [M-es-full] | **Uncertain:** `x caron`; no matching Italian check-accent rule or test found in the inspected sources |
| Hat accent | **Changed:** `x accent circonflexe` [M-fr-test], [M-fr-unicode] | **Changed:** `x Zirkumflex` [M-de-test], [M-de-unicode]; capitalize the noun | **Kept:** `x circunflejo` [S-es-symbols]; MathCAT uses `acento circunflejo` [M-es-unicode] | **Changed:** `x accento circonflesso` [S-it-symbols] |
| Bar accent | **Kept:** `x barre` [M-fr-full], the modified-variable branch for U+00AF | **Changed:** `x Überstrich` [S-de-actions] `overbar`, [S-de-adornments] `Bar001`; MathCAT's modified-variable branch instead says `bar` [M-de-full] | **Kept:** `x barra` [M-es-full], [S-es-actions] `overbar` | **Changed:** `x barra sopra` [S-it-adornments] `Bar001`; Mathspeak's `overbar` uses `con barra sopra` [S-it-actions] |
| ∂ | **Changed:** `dérivée partielle` [M-fr-unicode], [S-fr-alphabet] | **Changed:** `partielle Ableitung` [M-de-full], [S-de-alphabet] | **Kept:** `parcial`, MathCAT's terse form [M-es-unicode]. Its longer `derivada parcial` and SRE's `diferencial parcial` disagree [S-es-alphabet]; preference remains uncertain | **Changed:** `derivata parziale` [S-it-alphabet] |
| ∮ | **Kept:** `l'intégrale de contour`; both name `intégrale de contour` [M-fr-unicode], [S-fr-symbols] | **Changed:** `das Randintegral`; both name `Randintegral` [M-de-full], [S-de-symbols] | **Kept:** `la integral de contorno` [M-es-full], [S-es-symbols] | **Kept:** `l'integrale di contorno` [S-it-symbols] |
| Carries | **Uncertain:** `retenues` | **Uncertain:** `Überträge` | **Uncertain:** `acarreos` versus `llevadas` and regional suitability | **Uncertain:** `riporti` |
| A stack's line | **Uncertain:** `trait` | **Uncertain:** `Strich`, also the prime name | **Uncertain:** `línea` | **Uncertain:** `linea` |

The double-dot names are used for both U+00A8 and combining U+0308 inside `mover`.
Likewise, the hat and bar names apply to the aliases already recognized by MathMLLayout.
This deliberately gives equivalent accents the same name instead of copying upstream
differences between spacing and combining code points. These are accent names, not an
inference that the formula denotes a second derivative. In particular, `dos puntos` and
`due punti` have been replaced for the double-dot accent.

No matching stack/carry speech rules were found in the inspected MathCAT language rules or
SRE locale actions. A name for a bar or a table row does not establish the name of a
stack's arithmetic line. Existing carry and line strings are retained pending better evidence.
The source comments no longer claim verified classroom usage or suitability throughout
Spain and Latin America.

## Other wording questions from #31

- **French < and > — changed.** MathCAT's non-terse U+003C/U+003E rules say
  `est inférieur à` / `est supérieur à` [M-fr-unicode]; SRE's maps agree on the
  names [S-fr-symbols]. Drop `strictement` and the unsupported comment claiming
  that `inférieur` alone includes equality. Keep ≤ / ≥ distinct with `ou égal`.
- **Indexed roots — retained, naturalness uncertain.** MathCAT's French
  `simple_mi_root` reads `la racine n-ième de x` [M-fr-roots]; its German
  `variable_root_index_uses_german_ordinal_suffix` reads `die n-te wurzel von x`
  [M-de-roots]. SRE's ClearSpeak `root` actions apply language-specific ordinal grammar
  [S-fr-roots], [S-de-roots], [S-it-roots]. MathMLLayout receives an arbitrary already-read
  index string, including compound expressions. These examples do not justify appending
  ordinal suffixes to every string. Keep the explicit index templates until a separate
  change handles token type, ordinal generation and compound-index scope. The Spanish
  SimpleSpeak root rule even contains an English `-th` pronunciation branch
  [M-es-simple]; do not adopt it.
- **Generic mmultiscripts “script” names — unresolved.** SRE distinguishes subscript,
  superscript and side: its French utility produces `indice gauche` versus
  `exposant gauche` [S-fr-script], German ClearSpeak actions have
  `linker unterer Index` versus `linker oberer Index` [S-de-roots], and Italian
  messages distinguish `pedice` / `apice` [S-it-messages].
  That supports positional readings in a future engine change, not applying a
  subscript name indiscriminately to every script. Keep the current generic
  `indice` / `Index` / `índice` labels as documented limitations.
- **Agreement and French elision — unresolved.** The inspected rules give
  `racine carrée de` followed by an operand. They do not establish a general rule for
  joining arbitrary formula readings such as `a`, digits, spoken letters or compound
  expressions. No automatic `de` → `d'` substitution was added.

## Remaining structural and accessibility limitations

The following issue items still need engine work or a separately justified policy:

- Stacks and long division omit column positions, shifts, alignment, line lengths,
  carry locations and division-frame style. Carries and borrows share a label;
  crossout style is not distinguished.
- Stack numbers are read whole, leaving digits, decimal and grouping punctuation to
  the host voice. Digit-by-digit output would need locale-aware punctuation decisions.
- Only `mo` symbols are named; `mi`, token text and image `alt` are passed through.
- Integral limits in `msubsup` use subscript/power templates; `munder` does not name accents.
- Only a single prime receives the special superscript reading.
- `mfenced` speech ignores `separators`.
- `mmultiscripts` speech omits each script's corner.

Issue #31 also references #16. The current suite already tests that `maction` and
`semantics` speech follows the child selected for drawing; that is outside this wording audit.

## Regression coverage and attribution

`Tests/MathMLLayoutTests/SpeechWordingTests.swift` checks parsed formulas, language tags,
spacing/combining accent aliases in all five languages, supported check names, ∂ and ∮
in a formula, and the distinction between strict and non-strict French comparisons.
Existing phrase fixtures were updated where the wording changed. The tests preserve the
chosen wording; they do not certify linguistic quality or byte-for-byte equivalence to
either complete upstream engine.

Selected names and test expectations are adapted; neither upstream engine is a runtime
dependency. See [third-party notices](../THIRD_PARTY_NOTICES.md) for the retained MIT and
Apache licenses, copyright notices and SRE NOTICE.
The notices also retain the German fixtures' ETH Zurich sponsorship and the Italian
fixtures' TextHelp acknowledgment. Apps distributing the compiled speech material must
include the [license and attribution copies](../THIRD_PARTY_NOTICES.md#redistributing-mathmllayout).

Validation on 2026-10-12 with Swift 6.4 on macOS: the full debug and release suites
each passed all 394 tests with zero failures. The release run used `-Xswiftc -enable-testing`.
SwiftPM's native build system, writable module caches and `--disable-sandbox` were used
because the default build setup could not run within this task's filesystem sandbox.
All 31 pinned source-file links were checked against the upstream repository trees;
local documentation links and `git diff --check` also passed.

[M-fr-test]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/tests/Languages/fr/shared.rs
[M-de-test]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/tests/Languages/de/shared.rs
[M-fr-unicode]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/fr/unicode.yaml
[M-de-unicode]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/de/unicode.yaml
[M-es-unicode]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/es/unicode.yaml
[M-fr-full]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/fr/unicode-full.yaml
[M-de-full]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/de/unicode-full.yaml
[M-es-full]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/es/unicode-full.yaml
[M-fr-roots]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/tests/Languages/fr/ClearSpeak/mroot.rs
[M-de-roots]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/tests/Languages/de/ClearSpeak/mroot.rs
[M-es-simple]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/es/SimpleSpeak_Rules.yaml
[S-fr-symbols]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/symbols/math_symbols.json
[S-de-symbols]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/symbols/math_symbols.json
[S-es-symbols]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/symbols/math_symbols.json
[S-it-symbols]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/symbols/math_symbols.json
[S-fr-alphabet]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/messages/alphabets.json
[S-de-alphabet]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/messages/alphabets.json
[S-es-alphabet]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/messages/alphabets.json
[S-it-alphabet]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/messages/alphabets.json
[S-de-actions]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/rules/mathspeak_german_actions.json
[S-es-actions]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/rules/mathspeak_spanish_actions.json
[S-it-actions]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/rules/mathspeak_italian_actions.json
[S-de-adornments]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/de/clearspeak/clearspeak_part3_adornments.json
[S-it-adornments]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/it/clearspeak/clearspeak_part3_adornments.json
[S-fr-roots]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/rules/clearspeak_french_actions.json
[S-de-roots]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/rules/clearspeak_german_actions.json
[S-it-roots]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/rules/clearspeak_italian_actions.json
[S-fr-script]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/speech_rules/mathspeak_french_util.ts
[S-it-messages]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/messages/messages.json
[S-bar-input]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/input/clearspeak/clearspeak_part3_adornments.json
