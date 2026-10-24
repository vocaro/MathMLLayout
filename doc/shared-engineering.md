# Shared engineering

Common rules, technical lessons and reusable engineering tools are maintained in the public MIT-licensed
[vocaro/vocaro-engineering](https://github.com/vocaro/vocaro-engineering) repository. Clone it as
`vocaro-engineering` beside this checkout with
`git clone https://github.com/vocaro/vocaro-engineering.git`, or set
`VOCARO_ENGINEERING_ROOT` to its location. No private repository access is needed for the toolkit.

```sh
python3 scripts/eng doctor
python3 scripts/eng instructions
python3 scripts/eng knowledge background
```

Read the printed shared guidance and this repository's AGENTS.md before work. engineering.json
selects relevant capabilities and records exceptions. Current shared-resource policy comes from
`python3 scripts/eng policy refresh`; read current project main rules before using a shared
resource too. Initialization and guidance commands start no builds, devices or hosted jobs.
Existing commands remain project adapters to the shared source. App fixtures, acceptance
requirements, corpus admission, historical measurements and release decisions remain here.

## Runtime and test support

The public shipping library has no dependency on the engineering toolkit or private runtime packages. The development gallery delegates exact-manifest report validation; MathML outcomes and external-validation expectations stay here.

## Updates and new repositories

The toolkit's [adoption guide](https://github.com/vocaro/vocaro-engineering/blob/main/guides/adoption.md)
describes local checkout updates, isolated trials and rollback. No pin is required. Runtime
package changes are qualified separately with their own suites and affected consumer checks;
local path adoption is also supported where this project's distribution contract permits it.
A new repository can run the toolkit's `bin/eng --project /path/to/NewRepo init`, select its
capabilities and configure its own lanes without copying maintained implementations.

Reusable findings go in the toolkit's subject guide with the source commit and original evidence
link. This project's observed results stay on the owning issue or existing measurement record.
A source move does not expand a qualification to new operating systems or inputs.
