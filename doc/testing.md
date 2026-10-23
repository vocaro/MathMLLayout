# Testing

These are plain commands for contributors on their own machines. Sessions on the shared Mac run
them through
[heavy-work admission](https://github.com/vocaro/apple-engineering/blob/main/guides/shared-host.md#heavy-work-admission).

```sh
swift test --jobs 2
```

Run the optimized build as well, after the debug run; the reasons are in
[shared debug and optimized runs](https://github.com/vocaro/apple-engineering/blob/main/guides/simulator-testing.md#debug-and-optimized-swift-test-runs).

```sh
swift test --jobs 2 -c release -Xswiftc -enable-testing
```

For iOS, run the same tests on a simulator created for the run. Address it by the UDID that
`xcrun simctl create` printed, and delete it afterwards
([shared simulator lifecycle](https://github.com/vocaro/apple-engineering/blob/main/guides/simulator-testing.md#simulator-lifecycle)):

```sh
xcodebuild test -scheme MathMLLayout-Package -destination 'platform=iOS Simulator,id=UDID'
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

## Spelling

Everything the project writes is spelled in American English, identifiers included. The shared
[spelling check](https://github.com/vocaro/apple-engineering/blob/main/guides/maintenance.md#spelling-check)
reads every tracked text file and fails on a British form. What is kept as others spell it, such
as MathML's `bevelled` attribute, is listed with its reason in the `spelling` section of
[engineering.json](../engineering.json).

```sh
python3 scripts/eng spelling
```

The [pre-push hook](../scripts/hooks/pre-push) runs the check and refuses a push that fails it or
that it could not run. Install it once per clone:

```sh
git config core.hooksPath scripts/hooks
```

The check reads the working tree, so the hook accepts only a push of the checked-out commit from a
clean tree.

## Bidirectional text

The [bidi text regressions](bidi-text-tests.md) use a checksum-pinned synthetic font and
explicit Unicode-derived expected visual order. They run in the regular suite without Python
or a font download. The font generator is optional. The general method is in
[shared synthetic fixture oracles](https://github.com/vocaro/apple-engineering/blob/main/guides/external-validation.md#synthetic-fixture-oracles).

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
actual size, because
[Darwin pads a requested stack size](https://github.com/vocaro/apple-engineering/blob/main/knowledge/apple/stack-and-work-bounds.md#darwin-pads-a-requested-thread-stack-size).
The asserted coverage and limitations are in
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
`MATHML_MEASURE_WORKER_DEPTH=1`. Pass it with xcodebuild's `TEST_RUNNER_` prefix, which sets it
in every test runner process
([shared test environment](https://github.com/vocaro/apple-engineering/blob/main/guides/simulator-testing.md#test-environment)).
To run the sweep separately:

```sh
TEST_RUNNER_MATHML_MEASURE_WORKER_DEPTH=1 xcodebuild test -scheme MathMLLayout-Package \
  -destination 'platform=iOS Simulator,id=UDID' \
  -only-testing:MathMLLayoutTests/WorkerDepthTests/testMeasureWorkerDepth \
  -parallel-testing-enabled NO
```
