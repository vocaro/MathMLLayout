# Bundled MathML corpora

These resources belong to the test target, and are not distributed by the library target.
`swift test` runs the corpus invariants without downloads, Python, or environment setup.

| Dataset | Cases | License |
| --- | --- | --- |
| OpenStax Precalculus 2e | 100 textbook equations | CC-BY-4.0 |
| Speech Rule Engine Mathspeak | 296 distinct regression inputs | Apache-2.0 |

The textbook sample contains 52 inline and 48 display equations selected from 2,100
distinct formulas in eight modules. Topics include functions, complex numbers, logarithms,
trigonometric identities, matrices, geometric sequences, limits and derivatives. The SRE
inputs add roots, embellished operators, semantics and tensors. All 393 valid inputs must
render with finite/bounded deterministic dimensions and covered raster ink. Three SRE
inputs have an unmatched final prescript; they explicitly require
`MathLayoutError.invalidMarkup("mmultiscripts")`. No bundled input can silently skip due to
layout limits or raster budgets. Success establishes robustness, not visual conformance.

## Licenses and provenance

OpenStax, Rice University; *Precalculus 2e*, Jay Abramson and contributing authors.
Access for free at https://openstax.org/details/books/precalculus-2e.

The textbook data comes exclusively from revision
[`4922e46ebc04326979e19392ccc2384cb8b9076c`](https://github.com/openstax/osbooks-college-algebra-bundle/tree/4922e46ebc04326979e19392ccc2384cb8b9076c).
Its LICENSE, original README, and Precalculus collection metadata explicitly specify
CC-BY-4.0 and are retained byte-for-byte under `openstax-precalculus/`. Current upstream
editions have different terms; they must not be substituted when regenerating this bundle.
See [CC's explanation of license irrevocability](https://creativecommons.org/faq/#what-if-i-change-my-mind-about-using-a-cc-license).

Speech Rule Engine, Copyright 2014-2018 Volker Sorge, revision
[`28cac44da8eba13bce646823183e959d6d943e79`](https://github.com/Speech-Rule-Engine/speech-rule-engine/tree/28cac44da8eba13bce646823183e959d6d943e79).
Its complete Apache-2.0 license and unchanged upstream NOTICE are retained under
`sre-mathspeak/`. No SRE executable or runtime dependencies are bundled.

Each dataset has a separate adaptation NOTICE and a manifest with original source hashes,
URLs, and per-equation or per-test provenance. The data retains these licenses separately
from MathMLLayout's original MIT code. Preserve these credits and licenses when
redistributing the corpus files.

## Regeneration

Use Python with `lxml==6.0.2`. From the repository root:

```sh
python3 tools/externalvalidation/bundle_corpora.py --cache /tmp/mathml-corpus-sources --download --verify
```

The script downloads missing files only when `--download` is supplied, verifies every source
against `tools/externalvalidation/bundled-corpus-pins.json`, and compares deterministic
regeneration with the checked-in resources. Run without `--verify` to write the regenerated
bundle. With the cache populated, omit `--download` for a fully offline regeneration.
The textbook sampler uses seed 52 and round-robin display/complexity/rare-element strata;
SRE includes every distinct input in the four pinned files, merging speech-preference
duplicates. Cases are not selected based on renderer results.

`MATHML_CORPUS_MANIFEST=/path/to/manifest.json` adds external cases to the default corpora.
`MATHML_CORPUS_REPORT=/path/to/report.json` writes the combined invariant results. The
separate CC-BY-NC-SA-4.0 Calculus sample remains an optional external dataset.
