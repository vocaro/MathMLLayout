# Speech wording audit for issue #31

Audited on 2026-10-12 against these pinned revisions:

- [MathCAT `85c89a37073d6efdb08efba5765dd69c7efddaf9`](https://github.com/daisy/MathCAT/tree/85c89a37073d6efdb08efba5765dd69c7efddaf9) (MIT).
- [Speech Rule Engine `28cac44da8eba13bce646823183e959d6d943e79`](https://github.com/Speech-Rule-Engine/speech-rule-engine/tree/28cac44da8eba13bce646823183e959d6d943e79) (Apache-2.0).

Scope: the wording table and wording questions in
[issue #31](https://github.com/vocaro/MathMLLayout/issues/31).
This source-backed audit is complete for the wording questions and structural follow-up in #31.
Matching upstream rules, locale maps and fixtures are accepted as wording evidence; a new
native-speaker review is not a prerequisite for adopting those forms. Only the remaining
novel descriptions and joining policies listed below need fresh linguistic review.
This is not a claim that MathMLLayout itself has received native-speaker or voice validation.
The follow-up for
[#55](https://github.com/vocaro/MathMLLayout/issues/55) repairs multiscript positions.

## How evidence was used

Prefer a rule for the actual construct, then a test in the requested language, then a
symbol name. Preserve MathMLLayout's operand order, explicit closing phrases and whole-language
fallback. A different upstream phrase does not by itself prove the former wording wrong.
The changes below choose traceable upstream forms, without claiming a regional classroom standard.

MathCAT's `SharedRules/default.yaml` `diacriticals` rule reads a variable followed by its
accent. Its French and German `shared.rs::modified_vars` tests exercise that construction.
Its Spanish test of the same name calls `test("en", ...)` and expects English; it is **not**
Spanish-language verification. Several Unicode entries cite Google or DeepL, so upstream
agreement is wording evidence, not proof that each entry received independent human review.
MathCAT [credits named French, German and Spanish translators](https://daisy.github.io/MathCAT/#acknowledgements);
that project-level provenance does not establish review of an individual rule or our adaptations.
MathCAT has no Italian
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
form or its name within MathMLLayout's template. “Novel” means there is no matching construct-specific upstream reading; the retained
MathMLLayout description belongs in the limited human-review queue. The source references below point to immutable files.

| Construct | French | German | Spanish | Italian |
| --- | --- | --- | --- | --- |
| Double-dot accent | **Changed:** `x tréma` [M-fr-test], [M-fr-full], [S-fr-symbols] | **Changed:** `x diaeresis` [M-de-test], [S-de-symbols] | **Changed:** `x diéresis` [M-es-full], [S-es-symbols] | **Changed:** `x dieresi` [S-it-symbols] |
| Check accent | **Kept:** `x caron` [M-fr-test], [M-fr-full] | **Changed:** `x Caron` [M-de-test], [M-de-full]; capitalize the name in this vocabulary | **Kept:** `x carón` [M-es-full] | **Changed:** `x con caron` [S-it-latin], U+010D `c con caron`; name evidence, adapted to the existing postfix accent template |
| Hat accent | **Changed:** `x accent circonflexe` [M-fr-test], [M-fr-unicode] | **Changed:** `x Zirkumflex` [M-de-test], [M-de-unicode]; capitalize the noun | **Kept:** `x circunflejo` [S-es-symbols]; MathCAT uses `acento circunflejo` [M-es-unicode] | **Changed:** `x accento circonflesso` [S-it-symbols] |
| Bar accent | **Kept:** `x barre` [M-fr-full], the modified-variable branch for U+00AF | **Changed:** `x Überstrich` [S-de-actions] `overbar`, [S-de-adornments] `Bar001`; MathCAT's modified-variable branch instead says `bar` [M-de-full] | **Kept:** `x barra` [M-es-full], [S-es-actions] `overbar` | **Changed:** `x barra sopra` [S-it-adornments] `Bar001`; Mathspeak's `overbar` uses `con barra sopra` [S-it-actions] |
| ∂ | **Changed:** `dérivée partielle` [M-fr-unicode], [S-fr-alphabet] | **Changed:** `partielle Ableitung` [M-de-full], [S-de-alphabet] | **Kept:** `parcial`, MathCAT's terse form [M-es-unicode]. Its longer `derivada parcial` and SRE's `diferencial parcial` disagree [S-es-alphabet]; the terse source-backed form is accepted without claiming regional preference | **Changed:** `derivata parziale` [S-it-alphabet] |
| ∮ | **Kept:** `l'intégrale de contour`; both name `intégrale de contour` [M-fr-unicode], [S-fr-symbols] | **Changed:** `das Randintegral`; both name `Randintegral` [M-de-full], [S-de-symbols] | **Kept:** `la integral de contorno` [M-es-full], [S-es-symbols] | **Kept:** `l'integrale di contorno` [S-it-symbols] |
| Carry/borrow introduction | **Novel:** `retenues ou emprunts` | **Novel:** `Überträge oder Entlehnungen` | **Novel:** `acarreos o préstamos`; regional alternatives are not selected by the locale | **Novel:** `riporti o prestiti` |
| A stack's line | **Novel:** `trait` with endpoint/full-width descriptions | **Novel:** `Strich` with endpoint/full-width descriptions | **Novel:** `línea` with endpoint/full-width descriptions | **Novel:** `linea` with endpoint/full-width descriptions |

The double-dot names are used for both U+00A8 and combining U+0308 inside `mover`.
Likewise, the hat and bar names apply to the aliases already recognized by MathMLLayout.
This deliberately gives equivalent accents the same name instead of copying upstream
differences between spacing and combining code points. These are accent names, not an
inference that the formula denotes a second derivative. In particular, `dos puntos` and
`due punti` have been replaced for the double-dot accent.

No matching stack/carry speech rules were found in the inspected MathCAT language rules or
SRE locale actions. A name for a bar or a table row does not establish the name of a
stack's arithmetic line. The complete carry/borrow introductions and line descriptions remain
MathMLLayout compositions. Their review does not reopen source-backed accent or symbol names.
The source comments no longer claim verified classroom usage or suitability throughout
Spain and Latin America.

## Other wording decisions from #31

- **French < and > — source-backed.** MathCAT's non-terse U+003C/U+003E rules say
  `est inférieur à` / `est supérieur à` [M-fr-unicode]; SRE's maps agree [S-fr-symbols].
  The unsupported `strictement` wording/comment was removed; ≤ / ≥ retain distinct `ou égal`.
- **Indexed roots — source-backed within a bounded grammar.** The additional decisions
  below record numeric and `n` evidence, adaptations and the Spanish variable fallback.
  Unsupported indices are described explicitly, without arbitrary ordinal suffixes.
- **Generic mmultiscripts names — resolved structurally in #55.** Readings distinguish all
  four corners with sourced labels. Only unmatched closing/composite descriptions remain
  in the human-review queue.
- **French elision — normal grammar sourced, formula joining remains a limited policy.**
  The Canadian guide supports vowel elision. Applying it to arbitrary author text or
  mathematical letter tokens does not establish their spoken pronunciation or agreement.

## Structural follow-up for #31

The implementation follow-up addresses the engine omissions enumerated in #31,
with explicit policies for information that presentation MathML cannot infer:

- Stack rows and carries announce logical column coordinates using shared drawing geometry.
  Nested positions/shifts, all stack alignments, line endpoints, carry locations and all ten
  division frames are represented. `mstyle` and decimal alignment follow the renderer's grid.
- Carries are introduced as **carries or borrows** in all languages. MathML 3 does not encode
  which one an `mscarries` annotation denotes, so this avoids a false classification. Crossout
  styles are named, including inherited styles, overrides and multiple simultaneous strikes.
- Direct stack-row numbers and simple numeric divisor/result/carry tokens are spelled out
  digit by digit. Period, comma and space are named literally; their numerical role is not guessed.
- Known symbols in `mi` receive the localized symbol names. Free text and image `alt` remain
  author-authored content; automatic translation is outside presentation MathML speech.
- Large-operator side scripts use limit wording. Under-accents, combined accents, prime sequences, configured fence separators and compound-power endings are represented.
- Small integer root indices use ordinal forms. `n` uses an upstream-supported ordinal in
  English, French, German and Italian; Spanish keeps its explicit index template. Other indices
  retain the explicit index template. French `de` elides before a written vowel in roots and lower limits.

The [MathML 3 elementary-math rules](https://www.w3.org/TR/MathML3/chapter3.html#presm.mstack)
and [fence expansion](https://www.w3.org/TR/MathML3/chapter3.html#presm.mfenced) establish the
presentation geometry and separator behavior. They do not prescribe speech wording.
The shared `MathStackAlignment` calculations retain the renderer's existing coordinates and
attribute bounds; the structural tests cover independently calculated positions for nested shifts,
punctuation, blanks, center/right/decimal alignment, inheritance, strike overrides and frame aliases.

The bounded root grammar is source-backed as detailed below: numeric indices 1 and 4–10
use upstream ordinal forms, with the existing square/cube-root special cases retained.
This is not a general ordinal generator or an assertion that every root index is a numeral.
Unsupported variable or compound indices keep explicit index labels rather than guessed suffixes.

The Government of Canada's [élision guide](https://nos-langues.canada.ca/fr/cles-de-la-redaction/elision)
supports `de` elision before vowels and records uncertainty before letter names. The engine's
vowel-based joining policy fixes the issue's `de a` example. It does not infer silent `h`, apply
agreement to arbitrary author text, or claim to resolve every letter-name or regional convention.
The full structural policies and examples are in the [speech guide](../doc/speech.md).

### Additional source-backed decisions

The following files use the same pinned revisions listed at the top of this audit.

| Language | Adopted underbar phrase | Adopted overbrace / underbrace names | Evidence |
| --- | --- | --- | --- |
| English | `x underbar` | `top brace` / `bottom brace` | [S-en-actions] `underbar`; [S-en-delimiters] U+23DE/U+23DF |
| French | `x trait souscrit` | `accolade supérieure` / `accolade inférieure` | [S-fr-actions] `underbar-enclose` and [S-fr-messages] `enclose.bottom`; [S-fr-delimiters] U+23DE/U+23DF |
| German | `x Unterstrich` | `Obere geschweifte Klammer` / `Untere geschweifte Klammer` | [S-de-actions] `underbar`; [S-de-delimiters] U+23DE/U+23DF |
| Spanish | `x subbarra` | `corchete rizado superior` / `corchete rizado inferior` | [S-es-actions] `underbar`; [S-es-delimiters] U+23DE/U+23DF |
| Italian | `x con barra sotto` | `parentesi graffa superiore` / `parentesi graffa inferiore` | [S-it-actions] `underbar`; [S-it-delimiters] U+23DE/U+23DF |

French uses the exact enclosure label as its postfix name instead of copying SRE's separate
`début` / `fin` enclosure scope. Brace names are name evidence in the existing postfix
accent template; they are not represented as identical complete upstream accent utterances.
Italian [S-it-latin] U+010D explicitly names `c con caron`; this supports `con caron`
for the check accent. The inconsistent `caronte` in one double-accent entry is not adopted.

For **bounded roots**, SRE [number maps][S-en-numbers] and the language-specific number
functions provide digit names and ordinals. English [S-en-number-code] supplies `first`,
`fourth` through `tenth`; French [S-fr-number-code] supplies `première` and the `-ième`
forms, including `cinquième` and `neuvième`; German [S-de-number-code] supplies `erste`,
`siebte`, `achte` and the regular forms. Spanish [S-es-numbers] `onesOrdinals`
supplies the feminine forms directly. Italian [S-it-numbers] `onesOrdinals` plus
[S-it-number-code] `wordOrdinal` with gender `f` supplies `prima` through `decima`.

MathCAT's [French root rule][M-fr-root-rules] orders `racine` before the ordinal;
its [fixtures][M-fr-roots] `ordinal_root` and `simple_mi_root` support that order and `n-ième`.
Its [German fixture][M-de-roots] `variable_root_index_uses_german_ordinal_suffix`
supports `n-te`. SRE's [German][S-de-root-tests] `HighRoot012` supports the numeric
`vierte Wurzel aus` core. SRE's [Italian][S-it-root-tests] `HighRoot012` and `HighRoot015`
support `radice quarta di` and `radice n-esima di`, including `fine radice`.
MathMLLayout omits the optional French/German article and retains its existing explicit
root ending and punctuation policy; these are documented adaptations, not fixture equality.

The Spanish [MathCAT root rule][M-es-simple] numeric branch puts `ToOrdinal` before
`raíz`, followed by `de`; numeric readings now follow that order (`cuarta raíz de x`). MathCAT's
[Spanish definitions][M-es-definitions] use masculine ordinal names; MathMLLayout selects
SRE's explicit feminine ordinal table for the feminine root noun instead of copying
that mismatch. The template and gender vocabulary are therefore sourced from different
files, not claimed as an identical complete MathCAT utterance.
Its variable branch contains an English `-th` pronunciation and is rejected. No matching
Spanish variable-root ordinal was found in the inspected sources, so `n` now uses
`raíz de índice n de x fin de raíz`. This avoids declaring the previously composed
`raíz n-ésima` source-backed. Compound/unsupported indices retain this explicit scope policy.

**Digit and punctuation names** are accepted from each locale's number map:
[English][S-en-numbers], [French][S-fr-numbers], [German][S-de-numbers],
[Spanish][S-es-numbers], [Italian][S-it-numbers]. French `zéro` retains normal orthography
rather than SRE's unaccented `zero`. Each locale's `math_symbols.json` entries U+002C,
U+002E, U+003A and U+003B provide punctuation names; French colon/semicolon hyphens retain
normal orthography. German now uses SRE's `Strichpunkt` in place of `Semikolon`.
English uses MathCAT's [U+002E `point`][M-en-unicode] name,
without adopting its context-dependent pronunciation logic. The U+0020 space names come
from the whitespace maps: [English][S-en-space], [French][S-fr-space], [German][S-de-space],
[Spanish][S-es-space], [Italian][S-it-space]. Reading numeric cells individually and announcing
coordinates is MathMLLayout's structural policy; the component vocabulary is sourced.

### Implementation validation

On 2026-10-12 with Swift 6.4, Xcode 27.1 and macOS 27, the structural implementation's full debug and release
suites each completed **451 tests with zero failures and one skip**. The skipped test is the
optional licensed external corpus, which was not configured. Release used
`-Xswiftc -enable-testing`. SwiftPM used `--disable-sandbox --build-system native`, writable
module caches and scratch paths under `/tmp`.

All **55 selected speech and elementary-speech acceptance tests passed** on an iPhone 17 Pro
with iOS 27.0. `SpeechStructureTests` adds 16 tests covering positional geometry, every
localized spatial entry, all division forms and aliases, inherited/overridden accents and
strikes, prime aliases and longer sequences, symbols, ordinals/elision policies, extreme
attributes and truncation. Updated fixtures retain row order, selected-child behavior,
whole-language fallback and source budgets. Documentation targets and `git diff --check`
also passed. These checks validate the implementation and selected text, not linguistic
naturalness or usability with particular voices.

The source-backed wording follow-up on the same date passed **59 selected tests in both
debug and release**, and **57 selected tests on iOS 27.0**, with zero failures. Two new
`SpeechWordingTests` cases cover the adopted underbar/brace names and root fixtures/fallback;
Italian caron joins the existing audited accent test. All **73 immutable source-file targets**
were checked against the extracted pinned revisions; audit references, local document targets
and `git diff --check` passed. These focused runs follow the full structural suites above.

### Accepted evidence and remaining human-review scope

The source-backed wording work is complete. Exact upstream forms and adaptations with a
matching construct rule are accepted for this implementation; they do not wait for a second
translation review. Source support and fresh human validation are distinct statuses.
The completed implementation and audit can be reviewed and shipped on this basis; the remaining
novel descriptions can be followed up separately. Do not describe them as native-speaker approved.

| Accepted wording | Evidence and limits |
| --- | --- |
| Accent and symbol names in the table above, including Italian caron | Actual accent rules/fixtures where available; otherwise explicit symbol-name evidence applied to the established accent template. Equivalent spacing/combining aliases share a name. |
| Underbar and brace names | Exact SRE underbar actions or enclosure labels and U+23DE/U+23DF maps, listed below. No new descriptive translations are needed. |
| Bounded ordinal roots | Upstream root templates, numeric ordinal rules and root fixtures; Spanish `n` deliberately falls back to the explicit index phrase. |
| Positional multiscript labels | Exact SRE labels, now including French `indice droite` / `exposant droite`; compound closing phrases remain adaptations requiring the limited review below. |
| Digit and punctuation names | SRE number/whitespace/symbol maps and MathCAT's English `point` name; literal character naming is a structural policy, not a claim about decimal or grouping intent. |
| Ordinary French vowel elision | The Canadian language guide supports the grammar. Its application to mathematical letter tokens is a separate joining policy below. |

Fresh linguistic review is needed only for these **novel complete descriptions or policies**:

1. Elementary-math narration: stack/working-row introductions and endings, signed logical
   column coordinates, alignment and full-width/endpoint line phrases, and the ten division
   frame descriptions. Upstream table or enclosure labels do not validate these complete readings.
2. Carry/borrow descriptions: the combined category label, compass locations, column-digit
   strike association, direction-specific crossout descriptions, and their combined order.
   Regional carry/borrow terms are assessed here in context. German line descriptions include
   endpoints or a whole-width qualifier, separating them from prime readings.
3. Scoped compositions without a matching full utterance: positional compound-script endings,
   arbitrary compound-index descriptions and combined lower/upper accent descriptions.
   Their source-backed component nouns do not need to be retranslated.
4. French joining of arbitrary formula readings, especially vowel-letter variables and
   author text whose spelling does not reveal pronunciation. Normal-word elision is sourced;
   letter-name and regional conventions remain outside that evidence.

The current novel templates are available in the [English](../Sources/MathMLLayout/Speech/English.swift),
[French](../Sources/MathMLLayout/Speech/French.swift), [German](../Sources/MathMLLayout/Speech/German.swift),
[Spanish](../Sources/MathMLLayout/Speech/Spanish.swift) and [Italian](../Sources/MathMLLayout/Speech/Italian.swift)
vocabularies. [Structural speech cases](../Tests/MathMLLayoutTests/SpeechStructureTests.swift)
provide parsed examples for checking how their labels combine. Review these complete descriptions
in context; a terminology change alone does not validate their sequence or scope.

Listening with host voices and screen-reader users remains useful usability QA, especially
for these descriptions. It is not a blanket prerequisite for accepting every upstream word.
No new native-speaker approval or voice certification is claimed by this audit.

Issue #31 also references #16. Existing tests verify that `maction` and `semantics` speech
follows the child selected for drawing. The new structural shortcuts use the same selection.

## Multiscript follow-up (#55)

The [MathML 3 paired-slot definition](https://www.w3.org/TR/MathML3/chapter3.html#presm.mmultiscripts)
places subscripts before superscripts in each pair and orders both pair lists
left to right in an LTR context. Thus right pairs go outward from the base,
and left pairs go toward it. MathMLLayout reads the base, right pairs, then left pairs,
preserving source order within each side. Silent `none` elements occupy slots; `mprescripts`
starts the left subscript slot. This source-order policy avoids buffering or revisiting
children and retains the bounded speech traversal from #46. All pairs receive explicit
side and kind labels, including those beyond upstream special-case counts.

### Pinned vocabulary and fixture evidence

The revisions at the top of this audit also apply to these additional inspected files.
MathCAT's `default` rule tagged `mmultiscripts` in each language's
`SharedRules/default.yaml` distinguishes subscript and superscript, skips `none`,
and reads the base, prescripts, then postscripts. Its limited positional special cases
and its prescript-first order are not copied. The `shared.rs::tensor_mmultiscripts`
fixture exercises alternating occupied/empty slots across four right pairs:

- English [rules][M-en-scripts] and [fixture][M-en-test] supply `subscript` / `superscript`.
- French [rules][M-fr-scripts] and [fixture][M-fr-test] supply `indice` / `exposant`.
  SRE's `leftSubscriptVerbose` and `leftSuperscriptVerbose` [S-fr-script] directly
  supply `indice gauche` / `exposant gauche`. ClearSpeak
  `right-sub` / `right-super` [S-fr-roots] supply `indice droite` /
  `exposant droite`; these exact labels now replace MathMLLayout's composed
  `indice droit` / `exposant droit` counterparts.
- German [rules][M-de-scripts] and [fixture][M-de-test] use `Index` / `Hochstellung`.
  MathMLLayout instead adopts SRE's `left-sub` / `left-super` and
  `right-sub` / `right-super` ClearSpeak action labels [S-de-roots], including
  `linker unterer Index` / `linker oberer Index` and their explicit right counterparts.
- Spanish [rules][M-es-scripts] retain English `subscript` / `superscript` strings.
  The [tensor fixture][M-es-test] explicitly calls `test_prefs("en", ...)`, so it is
  structural evidence only. SRE's Spanish `MS.SUBSCRIPT` / `MS.SUPERSCRIPT`
  [S-es-messages] supply `subíndice` / `superíndice`. Its prefix actions
  `leftsub`, `leftsuper`, `rightsub`, `rightsuper` [S-es-prefix] directly supply
  all four complete positional labels adopted here.
- MathCAT has no Italian directory at this revision. SRE's Italian
  `MS.SUBSCRIPT` / `MS.SUPERSCRIPT` [S-it-messages] supply `pedice` / `apice`. Its prefix actions
  `leftsub`, `leftsuper`, `rightsub`, `rightsuper` [S-it-prefix] directly supply
  all four complete positional labels adopted here.

SRE's `mathspeak_tensors.json::PartialTensorABCD_default` fixtures also provide
actual four-slot utterances in [English][S-en-tensors], [French][S-fr-tensors],
[German][S-de-tensors], [Spanish][S-es-tensors] and [Italian][S-it-tensors].
French explicitly uses left `indice gauche` / `exposant gauche`; Spanish and Italian
confirm their subscript/superscript nouns in complete readings. German Mathspeak uses
`Index` / `hoch`, so the more positional German wording is adopted from ClearSpeak
rules instead. These SRE fixtures read left slots, base, then right slots and use a
baseline announcement; MathMLLayout deliberately keeps its base-first source order
and explicit side labels. The fixture comparison does not claim identical utterances.

The complete four-corner templates and reading order are in the
[speech guide](../doc/speech.md#multiscripts). Compound expressions close with
language-specific subscript/superscript endings (German uses `Ende Index` for both).
These closing phrases are MathMLLayout compositions, following its existing explicit
fraction, power and radical closure policy; they are not claimed as complete upstream
utterances. A selected single token through `semantics` or `maction` stays simple.
A nested multiscript closes before its next outer partner, so the outer side labels
can be interpreted without guessing where the nested expression ends.

The source comparison is sufficient to accept the chosen positional labels. Only the
composed closing descriptions stay in the human-review queue; there is no blanket requirement
to re-review supported labels. Neither source agreement nor this implementation claims
regional or voice certification. The limited review scope is recorded above.

`MultiscriptSpeechTests` checks parsed formulas in all five languages, every combination
of occupied/empty corners, five pairs on each side, empty pairs, the adapted tensor
fixture, incomplete partners and repeated markers, compound/nested expressions,
selected simple tokens, silent expressions, regional/script language tags and whole-language
fallback. `SpeechBoundsRegressionTests` retains all #46 tests and adds the last allowed
positional script, depth cutoff, UTF-16 text cutoff and absence of dangling labels.
Neither the node, depth nor source-text budgets have changed.

Follow-up validation on 2026-10-12 with Swift 6.4, Xcode 27.1 and macOS 27:
full debug and release suites each completed 435 tests with zero failures and one skip
(the optional licensed external corpus was not configured). Release used
`-Xswiftc -enable-testing`. All 38 selected speech tests passed on the iPhone 17 Pro
with iOS 27.0. SwiftPM used `--disable-sandbox --build-system native`, scratch paths
and writable module caches under `/tmp`; the iOS run used `MathMLLayout-Package`.
All 45 pinned source-file links were checked against the downloaded immutable
revisions; local documentation targets and `git diff --check` also passed.

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

Initial #53 audit validation on 2026-10-12 with Swift 6.4 on macOS: the full debug and release suites
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

[M-en-scripts]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/en/SharedRules/default.yaml
[M-fr-scripts]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/fr/SharedRules/default.yaml
[M-de-scripts]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/de/SharedRules/default.yaml
[M-es-scripts]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/es/SharedRules/default.yaml
[M-en-test]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/tests/Languages/en/shared.rs
[M-es-test]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/tests/Languages/es/shared.rs
[S-es-messages]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/messages/messages.json

[S-en-tensors]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/en/mathspeak/mathspeak_tensors.json
[S-fr-tensors]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/fr/mathspeak/mathspeak_tensors.json
[S-de-tensors]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/de/mathspeak/mathspeak_tensors.json
[S-es-tensors]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/es/mathspeak/mathspeak_tensors.json
[S-it-tensors]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/it/mathspeak/mathspeak_tensors.json

[S-es-prefix]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/rules/prefix_spanish_actions.json
[S-it-prefix]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/rules/prefix_italian_actions.json

[S-en-numbers]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/en/messages/numbers.json

[S-en-number-code]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/l10n/numbers/numbers_en.ts

[S-en-delimiters]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/en/symbols/math_delimiters.json

[S-en-space]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/en/symbols/math_whitespace.json

[S-fr-numbers]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/messages/numbers.json

[S-fr-number-code]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/l10n/numbers/numbers_fr.ts

[S-fr-delimiters]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/symbols/math_delimiters.json

[S-fr-space]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/symbols/math_whitespace.json

[S-de-numbers]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/messages/numbers.json

[S-de-number-code]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/l10n/numbers/numbers_de.ts

[S-de-delimiters]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/symbols/math_delimiters.json

[S-de-space]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/de/symbols/math_whitespace.json

[S-es-numbers]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/messages/numbers.json

[S-es-number-code]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/l10n/numbers/numbers_es.ts

[S-es-delimiters]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/symbols/math_delimiters.json

[S-es-space]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/es/symbols/math_whitespace.json

[S-it-numbers]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/messages/numbers.json

[S-it-number-code]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/ts/l10n/numbers/numbers_it.ts

[S-it-delimiters]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/symbols/math_delimiters.json

[S-it-space]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/symbols/math_whitespace.json

[S-en-actions]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/en/rules/mathspeak_english_actions.json

[S-fr-actions]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/rules/mathspeak_french_actions.json

[S-fr-messages]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/fr/messages/messages.json

[S-it-latin]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/mathmaps/it/symbols/latin-lower-single-accent.json

[S-de-root-tests]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/de/clearspeak/clearspeak_roots.json

[S-it-root-tests]: https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/it/clearspeak/clearspeak_roots.json

[M-fr-root-rules]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/fr/ClearSpeak_Rules.yaml

[M-en-unicode]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/en/unicode.yaml

[M-es-definitions]: https://github.com/daisy/MathCAT/blob/85c89a37073d6efdb08efba5765dd69c7efddaf9/Rules/Languages/es/definitions.yaml
