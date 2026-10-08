# Release notes

## 0.1.0

- First release, moved out of [EPUBLib](https://github.com/vocaro/EPUBLib) (at `35f7fdc`), where it
  was written for the native EPUB viewer
  ([vocaro/EPUBLib#3](https://github.com/vocaro/EPUBLib/issues/3)).
- Presentation-MathML layout and drawing with CoreText and the OpenType MATH table; parser,
  spoken readings, bounds on untrusted input. See the [README](README.md) for what is supported.
- Every one of the 1,798 formulas in EPUBLib's real-book corpus lays out without a fallback.
