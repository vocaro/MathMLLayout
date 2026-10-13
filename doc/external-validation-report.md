# Initial external validation report

**Best-effort follow-up for #52:** a reproducible 100-equation OpenStax sample and
eight additional operator/table WPT cases are now measured. See the
[follow-up results below](#best-effort-follow-up-for-52) and
[machine-readable follow-up report](external-validation-best-effort-results.json).

**Current result after the #54 fix:** all 81 pinned assertions pass their unchanged upstream
expectations, including all eight under/over limit checks. Strict mode passes as well.
The [machine-readable comparison](external-validation-results.json) reflects the fixed code.
The measurements and review notes below preserve the historical pre-fix baseline.

Measured on **October 12, 2026**, against production code at
`180da1f564c3c4262fd8fd6ef7b833d1ad069a06`, on arm64 macOS 27 with Xcode 27.1 / Swift 6.4.
Production files under `Sources/` were unchanged at that baseline. This report covers the implemented subset of
[#52](https://github.com/vocaro/MathMLLayout/issues/52), not the whole first milestone.

## Standards measurements

WPT revision: `38d608e1005d6d7f0fecefb3b7b14109ab3c3b1d`. Five upstream HTML files provide
81 individually traceable numeric assertions, with 36 original metric fonts repackaged for
CoreText. Re-import and font conversion reproduced the committed manifest byte-for-byte.

| Feature | Standards pass | Bug | Chromium standards pass |
| --- | ---: | ---: | ---: |
| Fractions with rules | 20 | 0 | 20 |
| Fractions without rules / stack parameters | 13 | 0 | 13 |
| Subscripts, superscripts, multiscripts | 30 | 0 | 30 |
| Under/over limits | 0 | 8 | 8 |
| Radical parameters | 10 | 0 | 10 |

All 73 passing library measurements exactly equal the expected values at the measured 4x
raster resolution. All 81 Chromium assertions pass the upstream tolerance. Chromium was
**151.0.7922.34**, via pinned Playwright **1.62.1**, using the same test fonts. All 81 batch
cases rendered without errors or detected clipping. Width differences remain observations
because root ink bounds and browser DOM boxes have different meanings.

The eight known failures are one defect:
[#54 — Large operators are centered on the math axis in inline style, shifting under/over limits](https://github.com/vocaro/MathMLLayout/issues/54).
A square summation glyph moves downward by 5 points, changing lower-limit measurements from
30/110 to 35/115 and upper-limit measurements from 50/70 to 45/65. The tests preserve the
upstream expectations and track the observed values with the issue link. No fix was made.

One symbolic radical-width assertion is explicitly excluded pending a reviewed port. The
manifest also records policies for browser integration, table spans, MathKernInfo, and specific
intentional typography differences. The remaining WPT population was not enumerated; there
is no whole-suite conformance rate. No unsupported or excluded case is counted as a pass.

The current [machine-readable comparison](external-validation-results.json) contains per-case
measurements, classifications, reference results, environment, exclusions, and issue links;
it supersedes this baseline's eight bug classifications after the #54 fix.
The generated `external-validation-output/index.html` gallery shows source markup, aligned
renderings, overlays and difference maps; regenerate it with the
[documented commands](external-validation.md#batch-rendering-and-reference-gallery).

## Independent font checks

fontTools **4.63.0** independently decoded the system STIX Two Math font. MathMLLayout matched
all **56 constants** and coverage-keyed italic corrections, accent attachments, variants,
assemblies and minimum connector overlap across **6,760 glyph IDs**, including negative
coverage lookups. The test verifies the original MATH-table hash before comparing metrics.
No font-decoding defect was found. MathKernInfo and device/variation adjustments remain outside
this comparison.

## Execution evidence

- Full macOS debug suite: **393 tests, zero failures, one optional corpus test skipped**.
- Full macOS release suite with `-enable-testing`: **393 tests, zero failures, one optional corpus test skipped**.
- iOS 27 / iPhone 17 Pro simulator: **both new standards and independent-font test methods passed**, without skips.
- Strict standards mode: **eight expected failures**, all linked to #54.
- Importer/tool checks: **three Python tests passed**, covering deterministic sampling,
  duplicate provenance, namespaces/entities, retained originals, and refusal to execute
  unreviewed expressions or resolve external entities.
- Corpus pipeline smoke check: three explicitly **synthetic** equations exercise extraction,
  parsing and invariants. They are not an independently sourced corpus or typography baseline.

The regular XCTest run passes while retaining issue-linked standards discrepancies. It fails
if an unclassified standards assertion fails, a known discrepancy changes, or its original
expectation begins passing without review. Strict mode exposes the standards failures directly.

## Remaining work

This section describes the original broader milestone. The best-effort follow-up below
adds a modest real-world sample; it does not complete the original 1,000-equation plan.

The ar5iv release requires its license agreement and download access. No dataset was acquired,
so **the approximately 1,000-equation real-world milestone remains unfinished**. The importer
and on-demand invariant runner are implemented, with source hashes, original files,
normalization records, deduplication and feature/complexity strata.

Additional operator, embellished-operator and table assertions, selected MathML 3 elementary
arithmetic cases, MathJax rendering, and SRE/language review remain to be added. Firefox and
WebKit adapters are implemented but have not been executed. The CI subset is provided as an
opt-in workflow requiring a supported macOS 27/Xcode 27 runner; no hosted runner or periodic
broader jobs are configured. These pending validation tasks are not inferred production bugs.

## Tooling review follow-up

The PR review tightened report integrity, discrepancy classification and image alignment.
The gallery now rejects stale/incomplete/duplicate reports, uses actual PNG baseline origins,
and requires review for clipping or changed/newly passing known discrepancies. Reference
adapters report unsupported markup and width constraints explicitly, verify font loading,
and bound raster area. Corpus sampling preserves token/annotation whitespace and limits file
reads; corpus tests verify markup hashes and bound both raster dimensions. Independent font
tests use the installed glyph count, and reviewed outcome imports cannot overwrite standards
expectations. Font-conversion checks remain active under Python optimization.

Ten tooling regression tests, including the native/Chromium integrations, pass. Debug and
release standards/font tests pass, and synthetic corpus checks cover integrity and raster
exclusion. Deliberately corrupted corpus hashes and a truncated oracle fail as intended.
Reimport/conversion still reproduce the manifest byte-for-byte. Regenerated native/Chromium
reports and the gallery retain **73 passes and eight unchanged #54 discrepancies**, with all
81 Chromium assertions passing and no native clipping. Strict mode still reports exactly
the eight #54 failures. Production code and the #54 defect remain unchanged.

## #54 fix verification

Inline large operators now retain the font's baseline, while display-style centering is
preserved. Two regression methods use the WPT square summation glyph to check bare and
embellished operators, scripts, fixed limits, display-style overrides, and `largeop="false"`.
Both methods and all eight limit assertions failed against the pre-fix code. The eight cases
now run as ordinary passing assertions; their upstream expectations and font data did not change.

- Full macOS debug and release suites, with strict standards checks and the required font
  oracle: **423 tests each, zero failures, one optional corpus test skipped**.
- iOS 27 / iPhone 17 Pro simulator: **68 operator, script, standards and font tests pass**, no skips.
- Regenerated native/Chromium comparison: **81 of 81 assertions pass**, no native clipping.
- All ten tooling regressions pass; fixture reimport/conversion reproduce the updated
  manifest byte-for-byte.

## Best-effort follow-up for #52

Measured October 12, 2026, on arm64 macOS 27, Xcode 27.1 / Swift 6.4, against base
`4ca33a78e106b2344d6f56bc544b43de57417fff` plus validation-only changes.

Eight new checks port two more files at the same pinned WPT revision:

- Six embellished/non-embellished operator cases for `mrow`, `mstyle` and `mpadded`.
  The original Ahem font is preserved. Both upstream spacing assertions pass in each
  case: outer/inner gaps are 50/0 or 0/50 points at 25-point type, tolerance 1 point.
- Two table-cell checks compare implicit/explicit `mrow` child geometry. Every
  child rectangle agrees exactly after translation; ink width/height are 30/60 points.
  Table baseline placement is deliberately outside the cell-equivalence assertion.

The original 81 numeric assertions still pass in strict mode. The supplement preserves
source files, hashes, original markup, specific upstream test names, transformations,
specification links and Ahem's public-domain/CC0 declaration. It does not port CSS
out-of-flow children, unknown grouping elements, or phantom/error wrappers.

Six pinned OpenStax Calculus modules supplied 2,888 equation occurrences, or 1,807
unique normalized inputs. Seed 52 selected **100 equations: 58 inline and 42 display**,
stratified by display mode, complexity and rarest element. The sample contains fractions,
scripts, radicals, integrals/limits, tables, fences, accents and Unicode operators.
CNXML equation wrappers supply display mode when MathML omits it; this transformation
is recorded. Original modules, hashes, occurrence indices and normalizations survive
local import. No input-limit or raster-budget exclusions occurred.

- All 100 pass finite/bounded dimensions, deterministic layout and 2x ink-containment
  checks. Native 4x batch rendering has zero errors or detected clipping.
- Pinned Chromium 151.0.7922.34 / Playwright 1.62.1 renders all 100 without errors,
  using the same system STIX Two Math font.
- A limited visual review inspected 24 pairs, prioritizing rare constructs and complex
  equations: **12 had no obvious defect**, **two had unsuitable reference renderings**,
  and **ten retain unadjudicated differences**. The remaining 76 were not visually inspected.
  These are a lightweight model review, not human expert validation or a conformance rate.
- Chromium omits `mfenced` delimiters in the two relevant inputs, so those renderings
  cannot validate native fence geometry. Nine inspected table constructions show
  spacing/alignment or script/limit differences. One inherited bold `mstyle` construction
  differs in font treatment. These remain uncertain rather than inferred native bugs.

The machine report records every input hash, source occurrence, feature profile,
invariant result, native/browser dimensions and review disposition. Its corpus `pass`
means only that the limited visual check found no obvious defect; 86 inputs remain
`unreviewed` and two are `unsuitable reference/test`. No new production bug was confirmed.
DOM box widths and native ink-covering bounds are still different quantities.

The OpenStax sources and derived corpus retain **CC-BY-NC-SA-4.0**, separate from
MathMLLayout's MIT license. They are generated locally outside the package and are not
included in this repository or binary resources. The repository retains source pins,
import commands and measurement/review data; local outputs retain the original license
and attribution. No ar5iv license agreement or dataset access was needed.

Validation: the six selected XCTest methods (standards, corpus and required independent
font oracle) pass in debug and release, without skips. All twelve tooling tests, including
native/Chromium integrations, pass. Corpus and supplemental WPT reimports reproduce
their manifests byte-for-byte. Production files under `Sources/` are unchanged.

The initial release build ran out of disk space during compilation. After space recovered,
the retry on October 12, 2026, at merged revision
`d80c4b02f83ea92f9c2a7a29055ca3d7b4255304` built successfully and ran **six tests with
zero failures and zero skips**, using `swift test -c release -Xswiftc -enable-testing`
with filter `ExternalValidationTests|ExternalCorpusTests|IndependentFontTests`,
`MATHML_STRICT_EXTERNAL=1`, `MATHML_REQUIRE_FONT_ORACLE=1` and the pinned corpus manifest
in `MATHML_CORPUS_MANIFEST`. All 100 corpus cases passed invariants and 2x ink containment;
all eight supplemental standards cases and the original 81 numeric assertions passed.
This successful focused release run supersedes the disk-space limitation; it covers the
selected validation tests, not the full release suite.

Larger corpora, further MathML 3 cases, MathJax/Firefox/WebKit runs, speech validation and
[human review of novel wording](https://github.com/vocaro/MathMLLayout/issues/63),
regular supported-runner CI and adjudication of the noted differences remain follow-up work.
