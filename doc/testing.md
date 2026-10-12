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
xcodebuild test -scheme MathMLLayout -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
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
