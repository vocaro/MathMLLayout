# External MathML validation

This is a partial implementation of [#52](https://github.com/vocaro/MathMLLayout/issues/52).
It establishes a reproducible baseline, without changing production layout code or claiming
complete MathML conformance. [The initial report](external-validation-report.md) lists measured
outcomes and unfinished work.

## Pinned standards subset

[`ExternalFixtures/manifest.json`](../Tests/MathMLLayoutTests/ExternalFixtures/manifest.json)
contains **81 individual numeric assertions from five WPT files**, at revision
`38d608e1005d6d7f0fecefb3b7b14109ab3c3b1d`. Cases cover fraction/stack parameters,
script shifts/gaps, under/over limits, and radical parameters. This is a count of assertions,
not 81 distinct upstream HTML documents.

Each case records its upstream assertion name and URL, specification section, original markup,
normalized standalone XML, SHA-256 hashes, transformations, expected value, and upstream tolerance.
The original upstream HTML files and BSD license are included. Thirty-six purpose-built fonts
are repackaged from WOFF as sfnt using fontTools, with unchanged MATH bytes and glyph metrics.
Their original/font/MATH hashes and PostScript names are recorded and checked at test time.
No STIX font is distributed.

CSS backgrounds become MathML `mathbackground`; CSS `mspace {font-size:10px}` becomes
`mathsize="10px"`. These measured rectangles have the same geometric meaning as the upstream
DOM boxes. The two measured backgrounds are red and blue. For measurements the library's
foreground glyphs/rules are drawn transparently: an opaque radical glyph or bar can otherwise
hide the very background whose box we are measuring. This extra draw must preserve all layout
dimensions. The ordinary opaque draw still supplies bounds checks and gallery images.

Coordinates in reports are points/CSS pixels, relative to the baseline, with **y down**.
This requires negating CoreGraphics y-up top/bottom coordinates. Fraction/script expectations
come directly from upstream numeric expressions, not from `MathFont` or regenerated screenshots.
The 1-point upstream tolerance is retained; it exceeds the 0.25-point raster quantization.

The manifest records specific exclusion policies for CSS/DOM integration, table spans,
MathKernInfo, unary/lone operators, delimiter sizing, and stretchy-arrow labels. The latter
choices remain documented in [markup.md](markup.md) and tested by the existing operator/script
suite. One symbolic radical-width assertion awaits a separate reviewed port. This subset does
not enumerate every unselected WPT test; its exclusion records are not a denominator for a
conformance percentage.

Known discrepancies live in `reviewed-outcomes.json`. Their classification, issue link, and
observed measurement survive re-import. Tests still evaluate the original standards expectation,
report `bug`, and ensure the observed discrepancy has not changed. Set `MATHML_STRICT_EXTERNAL=1`
to fail against the original expectation. A newly passing case requires review of the outcome
record; automatic re-baselining cannot turn a discrepancy into evidence of correctness.

## Batch rendering and reference gallery

Run from the repository root on supported macOS/Xcode:

```sh
swift run MathMLExternalRender \
  Tests/MathMLLayoutTests/ExternalFixtures/manifest.json external-validation-output
```

The renderer exports PNGs and `mathmllayout.json`: root width/ascent/descent, rows, unbreakable
width, ink bounds by color, measured background rectangles, readings, clipping observations,
registered font identity, platform, a hash of the input manifest, and the actual baseline origin
in each PNG's pixel coordinates. Errors are retained per case; very large
images are rejected by a separate batch raster budget. Root ink-covering bounds, row advances,
DOM boxes, and ink bounds are distinct measurements.

The reference adapter uses pinned Playwright **1.62.1**, including its pinned browser revisions.
Install Node 20+ and pnpm, then:

```sh
cd Tools/ExternalValidation
pnpm install --frozen-lockfile
pnpm exec playwright install chromium
cd ../..
node Tools/ExternalValidation/references.cjs \
  Tests/MathMLLayoutTests/ExternalFixtures/manifest.json external-validation-output chromium
```

Use `firefox` or `webkit` as the final argument after installing those Playwright engines.
Only Chromium has been executed for the initial report; these engine adapters are available
but are not claims of equivalent support. The tool explicitly selects each original font,
awaits `FontFace.load()` and `document.fonts.ready`, and records the actual browser version.
It parses input as XML and allows only presentation elements/attributes into an isolated DOM;
external resources, event handlers, arbitrary scripts, DOCTYPE, and entity declarations do not run.
Unsupported elements, namespaces and presentation attributes are reported as per-case reference
errors instead of silently removed. Unknown reference features need review and must not be
counted as library failures. The system-font fallback must load explicitly through FontFace.

Install the Python tool dependencies in a virtual environment:

```sh
python3 -m venv /tmp/mathml-validation-venv
/tmp/mathml-validation-venv/bin/pip install -r Tools/ExternalValidation/requirements.txt
/tmp/mathml-validation-venv/bin/python Tools/ExternalValidation/gallery.py \
  Tests/MathMLLayoutTests/ExternalFixtures/manifest.json external-validation-output
```

Open `external-validation-output/index.html`. It is a standalone gallery with source markup,
engine metadata, side-by-side images, baseline-aligned overlays, absolute RGB difference maps,
outcome filtering, and numeric discrepancies. `comparison.json` groups results by feature and
includes exclusions, errors and issue links. Reports must match the supplied manifest's hash
and contain every case ID exactly once. Regenerate older reports that lack PNG origin metadata
before creating overlays. Clipped results and changed/newly passing known discrepancies require
review; a failed reference assertion is categorized as an unsuitable reference/test.
Geometry determines standards outcomes; pixels are for
review. Antialiasing, font rendering, hinting, and layout-box conventions can produce harmless
image differences. Cross-engine width differences are observations, not automatic failures.

For arbitrary inputs the renderer accepts a manifest with `cases` containing safe unique `id`,
standalone `markup`, optional `fontSize` (default 20), and optional `maximumWidth`.
Sizes and width constraints must be finite and positive; invalid values are reported per case.
An optional `fonts` array supplies local paths, PostScript names and SHA-256 hashes. Corpus
cases without registered fonts use system STIX Two Math. The browser adapter reports cases with
`maximumWidth` constraints as unsupported references; matching browser line breaking requires
separate implementation and review.

## Independently decoded font data

`stix-fonttools.json` records fontTools **4.63.0** expectations for the installed STIX Two Math:
all 56 constants, coverage-keyed italic/accent values, minimum connector overlap, variants,
assemblies, and glyph IDs. Tests query every glyph, including absent coverage entries.
Lengths in constants are em units; percentages remain percentages; glyph measurements remain
font design units. MathKernInfo and device/variation adjustments remain excluded.

The MATH table hash must match the installed font. A mismatch is an explicit skip, never a
substitution of another font's metrics. To run against an updated installed font, independently
decode it into a temporary oracle (review changes before updating the pinned JSON):

```sh
/tmp/mathml-validation-venv/bin/python Tools/ExternalValidation/font_oracle.py \
  /System/Library/Fonts/Supplemental/STIXTwoMath.otf /tmp/stix-oracle.json
MATHML_FONT_ORACLE=/tmp/stix-oracle.json MATHML_REQUIRE_FONT_ORACLE=1 \
  swift test --filter IndependentFontTests
```

`MATHML_REQUIRE_FONT_ORACLE=1` makes a font mismatch fail instead of skip. Do not regenerate
this oracle with MathMLLayout's own decoder.

## Real-world corpus

The [ar5iv April 2024 release](https://sigmathling.kwarc.info/resources/ar5iv-dataset-2024/)
requires its license agreement and download access. **No ar5iv dataset was acquired in this
implementation**, and no 1,000-equation validation result is claimed. Supply a licensed local
subset of its `no_problem` HTML files, or another appropriately licensed HTML+presentation
MathML corpus. The importer does not accept agreements or download data. It expects UTF-8 HTML; other encodings are excluded.

```sh
/tmp/mathml-validation-venv/bin/python Tools/ExternalValidation/sample_corpus.py \
  /path/to/licensed/html /tmp/mathml-corpus --count 1000 --seed 52 \
  --release ar5iv-04-2024-no_problem --license C-UDA-1.0 \
  --source-url https://sigmathling.kwarc.info/resources/ar5iv-dataset-2024/
MATHML_CORPUS_MANIFEST=/tmp/mathml-corpus/manifest.json \
  MATHML_CORPUS_REPORT=/tmp/corpus-results.json swift test --filter ExternalCorpusTests
swift run MathMLExternalRender /tmp/mathml-corpus/manifest.json /tmp/corpus-gallery
```

Sampling is deterministic: deduplicate normalized XML, retain every source occurrence, stratify
by inline/display mode, logarithmic node count, and rarest element, and select round-robin across
strata in seeded SHA-256 order. IDs, source-file hashes, equation indices, original source files,
element/attribute usage, complexity, dataset release, license and transformations are recorded.
Token text/annotations are retained. Built-in HTML entities resolve to Unicode; no external
entity loads. Library parser/resource protections are unchanged. Input-limit exclusions and
shortfalls below the requested sample count are explicit. Start with a bounded source subset;
this importer keeps candidate markup in memory and does not stream the full 318 GB dataset.

Corpus tests verify each markup hash and check finite/bounded dimensions, determinism, and ink containment when the raster
budget permits. At 2x, they allow one point (the public contract's two device pixels) for
bitmap quantization/smoothing. Input limit errors are categorized separately, including available-stack limits.
Robustness success remains `unreviewed` for typography. Differential comparisons and manual
review must classify **pass**, **bug**, **intentional difference**, **unsupported feature**,
**invalid/out-of-bounds input**, or **unsuitable reference/test** with specific evidence.
Minimize unexpected failures and file them; do not change production code as part of this work.

## Updating fixtures and CI

Obtain a WPT checkout at the exact manifest revision, including the selected `mathml` sources
and `fonts/math` files. The importer is deliberately restricted to reviewed arithmetic expressions
and rectangle assertions; it never executes upstream JavaScript.

```sh
/tmp/mathml-validation-venv/bin/python Tools/ExternalValidation/import_wpt.py \
  /path/to/pinned/wpt Tests/MathMLLayoutTests/ExternalFixtures
/tmp/mathml-validation-venv/bin/python Tools/ExternalValidation/convert_fonts.py \
  /path/to/pinned/wpt Tests/MathMLLayoutTests/ExternalFixtures
/tmp/mathml-validation-venv/bin/python -m unittest discover \
  -s Tools/ExternalValidation -p test_tools.py
```

The importer and converter reject source/font hash mismatches using `wpt-pins.json`.
Changing the WPT revision and pins is an explicit source review: inspect upstream assertions, fonts,
license and normalization, rerun debug/release, regenerate the browser comparison, review the
gallery, and retain original failures. Review `reviewed-outcomes.json` independently of imports.
Reviewed entries can change only bug classification, issue link and observed measurement; they
cannot replace upstream expectations. Absent case IDs and observations that already satisfy
the assertion are rejected.

Run tooling regressions with the pinned dependencies. The optional integration tests exercise
per-case renderer errors and PNG origins; without these environment variables they skip:

```sh
swift build --product MathMLExternalRender
MATHML_NATIVE_RENDERER="$(swift build --show-bin-path)/MathMLExternalRender" \
  MATHML_BROWSER_NODE="$(command -v node)" \
  /tmp/mathml-validation-venv/bin/python -m unittest discover \
  -s Tools/ExternalValidation -p test_tools.py
```

The optional CI workflow targets a configured **macOS 27/Xcode 27** runner. It runs the pinned
subset in debug/release and uploads JSON reports. The normal `swift test` suite includes it as
well. Broader corpus/browser/fuzz jobs remain on demand. No periodic scheduler or hosted-runner
installation is configured. iOS simulator commands remain in [testing.md](testing.md).
