# Notices

The MathMLLayout library contains no third-party code. Its layout follows the W3C MathML Core and OpenType
MATH table specifications and appendix G of *The TeXbook*. It draws with the copy of STIX Two
Math (SIL Open Font License 1.1, Copyright 2001–2021 The STIX Fonts Project Authors) that Apple's
platforms install; it does not distribute the font.

The external-validation tests contain WPT-derived assertions and purpose-built test fonts
from web-platform-tests, pinned to revision `38d608e1005d6d7f0fecefb3b7b14109ab3c3b1d`.
Copyright © web-platform-tests contributors; the test fonts also retain their embedded
Copyright (c) 2016 MathML Association notices. They are distributed under the
[WPT 3-Clause BSD license](../Tests/MathMLLayoutTests/ExternalFixtures/WPT-LICENSE.md).
Only their packaging changes from WOFF to sfnt; original MATH metrics are preserved.
The independent fontTools oracle contains decoded numeric data from Apple's installed
STIX Two Math (Copyright 2001–2021 The STIX Fonts Project Authors, SIL OFL 1.1), not a font file.
Optional tooling uses fontTools (MIT), lxml (BSD), Pillow (HPND), and Playwright (Apache-2.0)
as separately installed development dependencies.

[Documentation index](../README.md#documentation)
