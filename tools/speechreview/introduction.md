# Native-speaker review packet for issue #63

This packet supports [issue #63](https://github.com/vocaro/MathMLLayout/issues/63):
the remaining novel descriptions in English, French, German, Spanish and Italian.
**Every language is awaiting human review.** Generated examples and automated checks do
not count as linguistic approval.

The [wording audit](../speech-wording-audit.md#accepted-evidence-and-remaining-human-review-scope)
already accepts matching upstream rules, locale maps and fixtures as evidence. Review the
complete descriptions and joining policies below. Their component accent, symbol, digit,
punctuation, ordinal and positional script names do not need a new blanket translation review.
If a supported component makes a complete description ambiguous, report that interaction.

## How to review

1. Choose your language and state the region or mathematical teaching convention you know.
   Review S, C, D and P cases; French reviewers also review F cases. A partial review is useful:
   record exactly which case IDs you covered.
2. Read the utterance aloud, or listen through a host voice if available. Before consulting the
   image or intended structure, paraphrase what you understood. Then compare the input/image
   and check whether columns, positions, crossouts and expression boundaries are recoverable.
3. Mark each case **accept**, **revise**, **unclear** or **not reviewed**. For a revision, give the
   complete replacement utterance and explain the ambiguity or regional preference. Do not
   silently replace literal author text or infer an arithmetic operation from a spatial label.
4. Submit the response template below to issue #63. Translation review and listening/user
   findings are recorded separately; listening is useful QA, not a gate on sourced vocabulary.

Column numbers are logical coordinates, not digit values: zero is the alignment reference,
negative numbers lie to its left, and numbers increase to the right. A carry annotation's
crossout applies to the associated column digit, even when the annotation sits beside it.
MathML uses the same carry element for carries and borrows; the engine describes both and
does not guess which arithmetic operation was intended. Division frames describe presentation,
not a calculation method or correctness. See the [speech guide](../speech.md).

## Review checklist

- [ ] **Stacks (S):** one/multiple row introductions and endings sound natural; negative/zero/positive
  column coordinates cannot be mistaken for values; left/center/right/decimal alignment is clear;
  shifts, blank cells, full-width lines and inclusive endpoints are recoverable.
- [ ] **Carries (C):** the combined carry/borrow category is appropriate in the reviewer's region;
  all eight locations are relative to the column digit; every strike direction is distinct;
  combined strikes and child overrides are understandable; the struck digit is not mistaken
  for the annotation. In German, line/strike descriptions remain distinct from a prime reading.
- [ ] **Division (D):** all ten frame descriptions communicate the divisor and result placement;
  full/medium/short right vertical lines remain distinct; zero/one/multiple working rows and
  their ending are clear; operand labels and shared columns do not imply extra arithmetic meaning.
- [ ] **Scope (P):** all four compound-script endings delimit their expressions; nested scripts
  close before the next outer partner; compound/nested root indices are separable from the
  radicand; lower then upper accents remain associated with the intended base.
- [ ] **French joining (F, French only):** assess letter-name conventions and arbitrary author text
  in root and limit phrases, including vowel letters, consonant letters with vowel-initial names,
  accented/capitalized tokens, mute/aspirated h and the sourced disjunctive-word controls.
  Recommend any needed explicit joining or pronunciation policy; ordinary word elision is sourced.
- [ ] Record acceptable regional alternatives and unresolved cases rather than declaring universal approval.

## Response template

Copy this into a response on issue #63. Do not check a whole scope item on the issue until
the reviewed language/case coverage and unresolved findings have been recorded.

```text
Language and region/teaching convention:
Reviewer attribution (name/handle, or agreed anonymous attribution):
Relevant experience (native speaker, math teaching, screen-reader use, etc.):
Packet/library revision:
Case IDs reviewed:

Repeat for each case or explicitly listed group of accepted cases:
  Case ID(s):
  Verdict: accept / revise / unclear / not reviewed
  What I understood from the current reading:
  Complete suggested replacement (if revise):
  Reason, ambiguity, and any regional alternatives:

Still unreviewed or unresolved:

Optional listening/user QA (separate from the wording verdict):
  Platform/OS, application or screen reader, voice and locale, speaking rate:
  Case IDs heard and observed pronunciation/pause/navigation problems:
```

## Maintainer completion checklist

- [ ] Record case-level findings and attribution for each of en/fr/de/es/it; F cases need French review only.
- [ ] Resolve proposed corrections, documenting regional choices and any still-unreviewed coverage.
- [ ] Apply accepted changes to vocabulary/joining policy and independent parsed regression expectations.
- [ ] Re-run the relevant structural, multiscript, wording and bounds tests when code changes.
  Preserve source order, selected-child behavior, coordinate semantics and traversal budgets.
- [ ] Regenerate this snapshot after wording changes, update the audit with actual human evidence,
  and retain any outstanding language/region or voice limitations. No review has occurred merely
  because this checklist or the examples were generated.

## Regenerating the examples

From the repository root on macOS with Xcode and STIX Two Math installed:

```sh
python3 tools/speechreview/generate.py
```

The generator compiles the checked-out Swift library sources, parses
[`cases.json`](../../tools/speechreview/cases.json), and writes this packet, exact locale
[`readings.json`](readings.json), and rendered PNG examples. Edit
[`introduction.md`](../../tools/speechreview/introduction.md) for review instructions or
`cases.json` for example inputs/prompts, then regenerate. Example IDs stay stable so feedback
remains attributable across revisions. The snapshot revision identifies library code, not a
claim that uncommitted vocabulary changes have been reviewed.
