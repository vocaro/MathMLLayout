# Notices

Selected speech vocabulary and test expectations are adapted from MathCAT (MIT) and Speech
Rule Engine (Apache-2.0); see [third-party notices](../THIRD_PARTY_NOTICES.md) for attribution
and retained licenses. Its layout follows the W3C MathML Core and OpenType MATH table
specifications and appendix G of *The TeXbook*. It draws with the copy of STIX Two
Math (SIL Open Font License 1.1, Copyright 2001–2021 The STIX Fonts Project Authors) that Apple's
platforms install; it does not distribute the font.

When distributing source, compiled libraries or apps, follow the
[redistribution instructions](../THIRD_PARTY_NOTICES.md#redistributing-mathmllayout).
SwiftPM does not automatically put the license and attribution files into an app bundle.

The external-validation tests contain WPT-derived assertions and purpose-built test fonts
from web-platform-tests, pinned to revision `38d608e1005d6d7f0fecefb3b7b14109ab3c3b1d`.
Copyright © web-platform-tests contributors; the test fonts also retain their embedded
Copyright (c) 2016 MathML Association notices. They are distributed under the
[WPT 3-Clause BSD license](../Tests/MathMLLayoutTests/ExternalFixtures/WPT-LICENSE.md).
Only their packaging changes from WOFF to sfnt; original MATH metrics are preserved.
The supplemental operator tests include the original Ahem.ttf unchanged. Ahem belongs
to the public domain; its embedded name-table declaration provides CC0 for jurisdictions
that do not recognize that status. The sampled OpenStax inputs retain CC-BY-NC-SA-4.0
and attribution in local corpus outputs; those inputs and renderings are not distributed
with this repository or library. Source pins and measured results are retained here.
The independent fontTools oracle contains decoded numeric data from Apple's installed
STIX Two Math (Copyright 2001–2021 The STIX Fonts Project Authors, SIL OFL 1.1), not a font file.
Optional tooling uses fontTools (MIT), lxml (BSD), Pillow (HPND), and Playwright (Apache-2.0)
as separately installed development dependencies.

[Documentation index](../README.md#documentation)
