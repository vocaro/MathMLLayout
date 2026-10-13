# Testing

```sh
swift test --jobs 2
```

Run configurations sequentially in the same checkout. Run the optimized build as well. A test
that passes in a debug build can fail there, or end the
test process: references are dropped sooner and the stack is used differently.

```sh
swift test --jobs 2 -c release -Xswiftc -enable-testing
```

For iOS, run the same tests on a simulator, for example:

```sh
xcodebuild test -scheme MathMLLayout-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The suite runs the line-breaking fuzzer over seeds 0 to 119. A wider range takes a few minutes
in a release build:

```sh
MATHML_FUZZ_SEEDS=0-40000 swift test --jobs 2 -c release -Xswiftc -enable-testing \
  --filter LineBreakingFuzzTests/testRandomFormulasBreakAsTheyMust
```

The fuzzer also checks that laying a formula out at its reported `widestUnbreakableWidth`
succeeds and that every row fits that width, including formulas with wrapping units side by side.

[Documentation index](../README.md#documentation)

## Bidirectional text

The [bidi text regressions](bidi-text-tests.md) use a checksum-pinned synthetic font and
explicit Unicode-derived expected visual order. They run in the regular suite without Python
or a font download. The font generator is optional.

## External validation

The pinned subset added for [#52](https://github.com/vocaro/MathMLLayout/issues/52) is described
in [external-validation.md](external-validation.md). Its 81 WPT-derived numeric assertions and
independent real-font checks run in the normal test suite without network access or Python.
Eight supplemental WPT operator/table checks also run there, using the preserved Ahem font.
Set `MATHML_EXTERNAL_SUPPLEMENT_REPORT` to export their measurements. The
corpus invariant test runs offline by default using 100 textbook equations from a pinned
CC-BY-4.0 Precalculus 2e snapshot and 296 Apache-2.0 SRE regression inputs (293 renderings and
three explicit invalid-markup rejections). Sources, licenses and regeneration instructions are
in the [bundled corpus README](../Tests/MathMLLayoutTests/ExternalFixtures/Corpus/README.md).
`MATHML_CORPUS_MANIFEST` adds a locally supplied corpus; it does not replace the bundled cases.
The older CC-BY-NC-SA-4.0 Calculus sample remains available on demand; see the
[sample commands](external-validation.md#modest-openstax-sample) and
[measured results](external-validation/report.md#best-effort-follow-up-for-52).
All 81 assertions pass after fixing inline large-operator centering in
[#54](https://github.com/vocaro/MathMLLayout/issues/54). The eight former discrepancies now
check the original upstream expectations directly. Any future reviewed discrepancy must
retain its upstream expectation and issue-linked observed value.

```sh
MATHML_EXTERNAL_REPORT=/tmp/external-debug.json swift test --jobs 2 \
  --filter 'ExternalValidationTests|IndependentFontTests'
MATHML_EXTERNAL_REPORT=/tmp/external-release.json swift test --jobs 2 -c release \
  -Xswiftc -enable-testing --filter 'ExternalValidationTests|IndependentFontTests'
```

To require every original standards expectation, including any future known discrepancy:

```sh
MATHML_STRICT_EXTERNAL=1 swift test --jobs 2 --filter ExternalValidationTests
```

The batch renderer, Chromium/Firefox/WebKit adapter, gallery, corpus importer, fixture-update
commands, and reporting limits are documented in [external-validation.md](external-validation.md).
The optional [CI workflow](../.github/workflows/external-validation.yml) can be called by normal
CI or invoked manually after configuring a macOS 27/Xcode 27 runner with label `mathml-xcode27`.
It does not assume that a hosted macOS 26 runner can execute this package.

## Worker depth

`WorkerDepthTests` allocates pthread stacks explicitly, with guard pages and an assertion of the
actual size. This avoids Darwin's extra allocation for a requested `Thread.stackSize` or
`pthread_attr_setstacksize`. The asserted coverage and limitations are in
[limits.md](limits.md#worker-stack-coverage).

The optional sweep reports the deepest successful pure chain in each fixture; it does not replace
the assertions of the documented 64-level mixed-shape matrix. After integration changes, run it
with each complete suite and retain the output for the actual compiler/platform:

```sh
MATHML_MEASURE_WORKER_DEPTH=1 swift test --jobs 2
MATHML_MEASURE_WORKER_DEPTH=1 swift test --jobs 2 -c release -Xswiftc -enable-testing
```

For a focused worker-depth rerun:

```sh
MATHML_MEASURE_WORKER_DEPTH=1 swift test --jobs 2 --filter WorkerDepthTests
MATHML_MEASURE_WORKER_DEPTH=1 swift test --jobs 2 -c release \
  -Xswiftc -enable-testing --filter WorkerDepthTests
```

For iOS, the measurement flag must reach the test process. A plain `xcodebuild test` runs
the fixed worker assertions but skips `testMeasureWorkerDepth` unless that process has
`MATHML_MEASURE_WORKER_DEPTH=1`. To run the sweep separately, use `xcodebuild build-for-testing`
with the same scheme, destination and derived-data directory. In the generated `.xctestrun`
under `Build/Products`, set that flag in each applicable test target's `EnvironmentVariables`
(`TestConfigurations` → `TestTargets`). Keep the edited file in the same directory so its
relative product paths still resolve. Then run:

```sh
xcodebuild test-without-building -xctestrun /path/to/edited.xctestrun \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MathMLLayoutTests/WorkerDepthTests/testMeasureWorkerDepth \
  -parallel-testing-enabled NO
```

## 0.3.0 release verification

The source released as [0.3.0](https://github.com/vocaro/MathMLLayout/releases/tag/0.3.0)
(`77fca0623f4273ce5a50971e9e5420eb47fcf04c`) was verified on 2026-10-13 with Apple Swift 6.4
(`swiftlang-6.4.0.34.1`), Xcode 27.1 (`27A9269`), arm64 macOS 27.0 (`26A428`) and the iOS
27.0 iPhone 17 Pro simulator. The release commit changes the changelog; the tested implementation
is `50f8cee62f122298dc4d7c2cabbcd8bf77fa2a40`.

| Run | Result |
| --- | --- |
| Full macOS debug suite, `--jobs 2` | 722 passed; zero failures or skips |
| Full macOS optimized suite, `--jobs 2 -c release -Xswiftc -enable-testing` | 722 passed; zero failures or skips |
| Full iOS simulator suite, parallel testing disabled | 721 passed; zero failures; optional measurement skipped |
| Separate iOS worker-depth measurement, flag enabled through `.xctestrun` | One passed; zero failures or skips, completing all 722 tests |
| Python validation-tool regressions, including native renderer and Chromium integration | 12 passed; zero failures or skips |
| Deterministic bundled corpus regeneration, `--verify` with cached pinned sources and lxml 6.0.2 | Both datasets matched the checked-in files |

Both complete macOS runs enabled `MATHML_MEASURE_WORKER_DEPTH=1`,
`MATHML_REQUIRE_FONT_ORACLE=1` and `MATHML_STRICT_EXTERNAL=1`, and exported the standards,
supplemental and corpus JSON reports. Each report contained 81 passing standards assertions,
eight passing supplemental checks and 396 passing corpus invariants: 100 rendered OpenStax
equations, 293 rendered SRE inputs and three expected malformed-script rejections. The full
iOS run passed those same standards, supplemental, corpus and independent-font tests.
Corpus success establishes robustness and ink containment, not visual conformance.

The validation tools used their pinned Python dependencies (fontTools 4.63.0, lxml 6.1.1,
Pillow 12.3.0), Playwright 1.62.1 and Chromium 151.0.7922.34. Both integration-test environment
variables documented in [external validation](external-validation.md) were supplied.
Corpus regeneration used its separately documented lxml 6.0.2 environment.
The regular seeded fuzz tests ran as part of each full suite; the optional expanded
`MATHML_FUZZ_SEEDS=0-40000` sweep was not part of this release verification.

All eleven optional pure-chain worker measurements reached 64 element levels in macOS debug,
macOS optimized and iOS: row, fraction, superscript, subscript, under-over, square root, root,
style, padding and semantics each reached 63 wrappers; tables reached 21 three-element wrappers.
The complete suites also passed the fixed geometry, ink, pixels and readings assertions on
the documented exact worker stacks. These results do not establish universal 64-level coverage;
the restrictions in [worker stack coverage](limits.md#worker-stack-coverage) still apply.
