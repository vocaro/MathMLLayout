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

It fails on a known set of seeds, all for one property and listed in
[#26](https://github.com/vocaro/MathMLLayout/issues/26). A failure on any other seed, or for
another property, is new.

[Documentation index](../README.md#documentation)
