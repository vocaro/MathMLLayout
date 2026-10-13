# Testing

```sh
swift test
```

Run the optimized build as well. A test that passes in a debug build can fail there, or end the
test process: references are dropped sooner and the stack is used differently.

```sh
swift test -c release -Xswiftc -enable-testing
```

For iOS, run the same tests on a simulator, for example:

```sh
xcodebuild test -scheme MathMLLayout-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The suite runs the line-breaking fuzzer over seeds 0 to 119. A wider range takes a few minutes
in a release build:

```sh
MATHML_FUZZ_SEEDS=0-40000 swift test -c release -Xswiftc -enable-testing \
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
Set `MATHML_EXTERNAL_SUPPLEMENT_REPORT` to export their measurements. The reproducible
100-equation OpenStax corpus remains on demand; see the
[sample commands](external-validation.md#modest-openstax-sample) and
[measured results](external-validation/report.md#best-effort-follow-up-for-52).
All 81 assertions pass after fixing inline large-operator centering in
[#54](https://github.com/vocaro/MathMLLayout/issues/54). The eight former discrepancies now
check the original upstream expectations directly. Any future reviewed discrepancy must
retain its upstream expectation and issue-linked observed value.

```sh
MATHML_EXTERNAL_REPORT=/tmp/external-debug.json swift test \
  --filter 'ExternalValidationTests|IndependentFontTests'
MATHML_EXTERNAL_REPORT=/tmp/external-release.json swift test -c release \
  -Xswiftc -enable-testing --filter 'ExternalValidationTests|IndependentFontTests'
```

To require every original standards expectation, including any future known discrepancy:

```sh
MATHML_STRICT_EXTERNAL=1 swift test --filter ExternalValidationTests
```

The batch renderer, Chromium/Firefox/WebKit adapter, gallery, corpus importer, fixture-update
commands, and reporting limits are documented in [external-validation.md](external-validation.md).
The optional [CI workflow](../.github/workflows/external-validation.yml) can be called by normal
CI or invoked manually after configuring a macOS 27/Xcode 27 runner with label `mathml-xcode27`.
It does not assume that a hosted macOS 26 runner can execute this package.
