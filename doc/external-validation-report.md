# Initial external validation report

Measured on **October 12, 2026**, against production code at
`180da1f564c3c4262fd8fd6ef7b833d1ad069a06`, on arm64 macOS 27 with Xcode 27.1 / Swift 6.4.
Production files under `Sources/` are unchanged. This report covers the implemented subset of
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

The [machine-readable comparison](external-validation-results.json) contains per-case
measurements, classifications, reference results, environment, exclusions, and issue links.
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

The ar5iv release requires its license agreement and download access. No dataset was acquired,
so **the approximately 1,000-equation real-world milestone remains unfinished**. The importer
and on-demand invariant runner are implemented, with source hashes, original files,
normalization records, deduplication and feature/complexity strata.

Additional operator, embellished-operator and table assertions, selected MathML 3 elementary
arithmetic cases, MathJax rendering, and SRE/language review remain to be added. Firefox and
WebKit adapters are implemented but have not been executed. The CI subset is provided as an
opt-in workflow requiring a supported macOS 27/Xcode 27 runner; no hosted runner or periodic
broader jobs are configured. These pending validation tasks are not inferred production bugs.
