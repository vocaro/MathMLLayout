# MathMLLayout contributor instructions

## Shared engineering guidance

Before work, run `python3 scripts/eng instructions` to read the common rules and enabled
capabilities, then follow the project-specific instructions below. `engineering.json` locates
the shared `apple-engineering` checkout; set `VOCARO_ENGINEERING_ROOT` for another location.
Before shared device, foreground or runner use, run `python3 scripts/eng policy refresh` and
read this project's current main instructions. Shipping Swift targets do not link the
engineering toolkit, which is public and MIT licensed.

Build and test procedures are in [doc/testing.md](doc/testing.md). Pushes are gated on American
spelling; install the hook once per clone, as [Spelling](doc/testing.md#spelling) describes.
