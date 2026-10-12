# Third-party notices

MathMLLayout's original code is licensed under the [MIT license](LICENSE).
Selected localized speech vocabulary and regression expectations are adapted from
the following projects. Their notices and license conditions apply to the adapted
material; no third-party speech engine is bundled or required at runtime.

## MathCAT

[DAISY MathCAT](https://github.com/daisy/MathCAT), revision
`85c89a37073d6efdb08efba5765dd69c7efddaf9`.

Copyright (c) 2022 NSoiffer

Licensed under MIT; the complete copyright and permission notice is retained in
[Licenses/MathCAT-MIT.txt](Licenses/MathCAT-MIT.txt).

Adapted material: French and German accent names and ∂ names, German ∮ name,
French comparison wording, Spanish double-dot accent name, and selected regression
expectations. References for retained wording are also recorded in the
[speech wording audit](Documentation/SpeechWordingAudit.md).

## Speech Rule Engine

[Speech Rule Engine](https://github.com/Speech-Rule-Engine/speech-rule-engine), revision
`28cac44da8eba13bce646823183e959d6d943e79`.

Copyright 2014-2018 Volker Sorge

Licensed under Apache License, Version 2.0. The complete license is retained in
[Licenses/SRE-Apache-2.0.txt](Licenses/SRE-Apache-2.0.txt), and the upstream NOTICE
is retained unchanged in [Licenses/SRE-NOTICE.txt](Licenses/SRE-NOTICE.txt).

Adapted material: selected accent and operator names from the French, German, Spanish
and Italian `mathmaps` files; German overbar wording; Italian ClearSpeak bar wording;
and selected regression expectations. In MathMLLayout these are incorporated into Swift
phrase templates and isolated test formulas, with existing operand and alias handling.
The affected vocabulary and test files prominently identify this adaptation.
The [audit](Documentation/SpeechWordingAudit.md) records exact source files and decisions.
These adaptations retain the Apache license and notice obligations.

The adapted ClearSpeak fixtures also carry these attribution notices, retained here
from the pinned source files:

- German [adornments fixtures](https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/de/clearspeak/clearspeak_part3_adornments.json): "This work was sponsored by ETH Zurich".
- Italian [adornments fixtures](https://github.com/Speech-Rule-Engine/speech-rule-engine/blob/28cac44da8eba13bce646823183e959d6d943e79/testsuite/expected/it/clearspeak/clearspeak_part3_adornments.json): "With support from TextHelp."

SRE's full original NOTICE is included for preservation. MathMLLayout does not use
SRE's browser or Node dependencies, including wicked good XPath.

## Redistributing MathMLLayout

For source distributions, retain this file, [LICENSE](LICENSE), the three files in
[Licenses](Licenses), and the adaptation notices in the affected Swift files.
Keep those notices when modifying the adapted material, and identify further changes.

For compiled libraries or apps containing the adapted speech material, include readable
copies of this file, LICENSE, MathCAT-MIT.txt, SRE-Apache-2.0.txt and SRE-NOTICE.txt
with the distribution, for example in the app's bundled acknowledgments or accompanying
documentation. A link to this repository alone does not supply those copies.
SwiftPM does not automatically copy these root-level files into an app bundle;
the distributing app or binary package must include them.

These instructions preserve the upstream MIT notice condition and Apache-2.0
[section 4](https://www.apache.org/licenses/LICENSE-2.0) requirements.
The MIT license for MathMLLayout's original code does not replace those conditions.
