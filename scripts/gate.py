#!/usr/bin/env python3
"""MathMLLayout's release gate: every check doc/testing.md requires for a release, on one tree.

Run it as the heavy `gate` lane, `python3 scripts/eng run gate`, beside other sessions' work.
Admission counts it as one job, so every build it starts takes JOBS jobs and each suite runs its
tests in one process. It passes only when every step passed: the full Swift suite in macOS debug
and optimized builds and on a disposable iOS simulator, each with at least SWIFT_TESTS tests and
none skipped or failed; the validation-tool tests, the native-renderer and Chromium integration
included, with none skipped; deterministic regeneration of the bundled corpus; the documentation
and spelling checks; and the gate's own tests. No test holds a wall-clock limit that a busy host
can break, and a step that gives no result within its hang bound is unmeasured, as is one whose
prerequisite is missing, such as Playwright's Chromium; the gate then exits 3, never 0. `--setup`
prepares those prerequisites and is the only part that downloads anything.
"""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from _engineering import toolkit_location  # noqa: E402

TOOLKIT = toolkit_location(ROOT)
sys.path.insert(0, str(TOOLKIT / "src/python"))
from vocaro_engineering.simulators import lifecycle  # noqa: E402

# Floors: a suite that runs fewer tests fails. Lower one only in the commit that removes tests.
SWIFT_TESTS = 806
TOOL_TESTS = 13
# Admission counts the gate as one job, so every build it starts takes this many jobs.
JOBS = "2"
TEST_ENVIRONMENT = {"MATHML_MEASURE_WORKER_DEPTH": "1", "MATHML_REQUIRE_FONT_ORACLE": "1",
                    "MATHML_STRICT_EXTERNAL": "1"}
DEVICE = "iPhone 17 Pro"
CACHE = Path(os.environ.get("MATHML_GATE_CACHE", Path.home() / "Library/Caches/MathMLLayout/gate"))
TOOLS, CORPUS, SOURCES = CACHE / "tools-venv", CACHE / "corpus-venv", CACHE / "corpus-sources"
VALIDATION = ROOT / "tools/externalvalidation"
BUILD = ROOT / ".build/gate"
SETUP = "python3 scripts/gate.py --setup"


class Failed(Exception):
    """The step ran and did not meet its expectations."""


class Unmeasured(Exception):
    """The step produced no valid result; the message gives the cause."""


class Stopped(BaseException):
    """The lane was told to stop."""


def run(command, *, timeout, env=None, cwd=ROOT):
    """Run a command, streaming its output, and return its status and output.

    A stop or a timeout ends the command's whole process group: TERM, then KILL."""
    print("$ " + " ".join(str(part) for part in command), flush=True)
    process = subprocess.Popen([str(part) for part in command], cwd=cwd, env={**os.environ, **(env or {})},
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
                               start_new_session=True)
    lines = []
    def read():
        for line in process.stdout:
            sys.stdout.write(line)
            lines.append(line)
        sys.stdout.flush()
    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    try:
        status = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop(process)
        raise Unmeasured(f"`{command[0]}` gave no result within {timeout} s")
    except BaseException:
        stop(process)
        raise
    reader.join()
    return status, "".join(lines)


def stop(process):
    for sent in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sent)
            process.wait(timeout=10)
            return
        except ProcessLookupError:
            return
        except subprocess.TimeoutExpired:
            continue


XCTEST = re.compile(r"^Test Suite '(?:All tests|Selected tests)' (passed|failed) at [^\n]*\n\s*Executed (\d+) "
                    r"tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", re.M)
UNITTEST = re.compile(r"^Ran (\d+) tests? in [^\n]*\n+(OK|FAILED)(?: \(([^)]*)\))?", re.M)


def xctest(status, output, minimum=SWIFT_TESTS):
    """Judge an XCTest run by its top-level totals."""
    totals = XCTEST.findall(output)
    executed = sum(int(total[1]) for total in totals)
    skipped = sum(int(total[2] or 0) for total in totals)
    failures = sum(int(total[3]) for total in totals)
    if failures or any(total[0] == "failed" for total in totals):
        raise Failed(f"{failures} of {executed} tests failed")
    if status:
        raise Failed(f"exited {status}" + ("" if totals else " before reporting any test totals"))
    if not totals:
        raise Unmeasured("reported no test totals")
    if skipped:
        raise Failed(f"{skipped} of {executed} tests skipped")
    if executed < minimum:
        raise Failed(f"ran {executed} tests, fewer than {minimum}")
    return f"{executed} tests passed, none skipped"


def unittest_result(status, output, minimum):
    """Judge a unittest run by its summary."""
    summary = UNITTEST.findall(output)
    if not summary:
        raise Failed(f"exited {status} with no test summary") if status else Unmeasured("reported no test summary")
    executed = int(summary[-1][0])
    details = dict(item.split("=") for item in summary[-1][2].split(", ") if "=" in item)
    if summary[-1][1] == "FAILED" or status:
        raise Failed(f"{summary[-1][2] or f'exited {status}'} in {executed} tests")
    if int(details.get("skipped", 0)):
        raise Failed(f"{details['skipped']} of {executed} tests skipped")
    if executed < minimum:
        raise Failed(f"ran {executed} tests, fewer than {minimum}")
    return f"{executed} tests passed, none skipped"


def checked(command, timeout=600):
    status, _ = run(command, timeout=timeout)
    if status:
        raise Failed(f"exited {status}")
    return "passed"


def inspected(environment):
    """Refuse an environment holding a quarantined native file before anything imports from it."""
    if not (environment / "bin/python").exists():
        raise Unmeasured(f"no Python environment at {environment}; run `{SETUP}`")
    status = subprocess.run(["/usr/bin/python3", TOOLKIT / "src/python/vocaro_engineering/native_python.py",
                             environment], timeout=300).returncode
    if status:
        raise Unmeasured(f"{environment} has a quarantined native file or could not be inspected; "
                         f"run `{SETUP}` to reinstall it")
    return environment / "bin/python"


def own_tests():
    return unittest_result(*run([sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests", "-v"],
                                timeout=300), minimum=1)


def swift_suite(name, *configuration):
    return xctest(*run(["swift", "test", "--jobs", JOBS, "--scratch-path", BUILD / name, *configuration],
                       timeout=5400, env=TEST_ENVIRONMENT))


def simulator_identities():
    """The newest available iOS runtime that offers DEVICE, and that device type."""
    listed = json.loads(lifecycle.command("list", "runtimes", "--json"))
    for runtime in sorted((r for r in listed["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")),
                          key=lambda r: [int(part) for part in r["version"].split(".")], reverse=True):
        for device_type in runtime.get("supportedDeviceTypes", []):
            if device_type["name"] == DEVICE:
                return runtime, device_type
    raise Unmeasured(f"no available iOS runtime offers an {DEVICE} simulator")


def ios_suite():
    runtime, device_type = simulator_identities()
    print(f"iOS {runtime['version']} ({runtime['buildversion']}), {DEVICE}", flush=True)
    results = BUILD / "ios.xcresult"
    shutil.rmtree(results, ignore_errors=True)
    environment = {f"TEST_RUNNER_{key}": value for key, value in TEST_ENVIRONMENT.items()}
    with lifecycle.disposable(device_type["identifier"], runtime["identifier"], prefix="MathMLLayout-gate") as device:
        print(f"Simulator {device.udid}", flush=True)
        try:
            device.boot()
        except subprocess.TimeoutExpired:
            raise Unmeasured(f"simulator {device.udid} did not finish booting within 600 s")
        except subprocess.CalledProcessError as error:
            raise Unmeasured(f"simulator {device.udid} did not boot: {error}")
        return xctest(*run(["xcodebuild", "test", "-scheme", "MathMLLayout-Package",
                            "-destination", f"platform=iOS Simulator,id={device.udid}", "-destination-timeout", "600",
                            "-jobs", JOBS, "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                            "-derivedDataPath", BUILD / "ios-derived-data", "-resultBundlePath", results],
                           timeout=7200, env=environment))


def chromium():
    """Node and the pinned Playwright's Chromium, which the reference integration test drives."""
    node = shutil.which("node")
    if not node:
        raise Unmeasured("Node 20+ is not installed; install Node and pnpm, then run `" + SETUP + "`")
    if not (VALIDATION / "node_modules/playwright/package.json").exists():
        raise Unmeasured(f"Playwright is not installed in this checkout; run `{SETUP}`")
    probe = subprocess.run([node, "-e", "const p = require('playwright').chromium.executablePath();"
                            "process.exit(require('fs').existsSync(p) ? 0 : 1)"], cwd=VALIDATION, timeout=60)
    if probe.returncode:
        raise Unmeasured(f"Playwright's Chromium is not installed; run `{SETUP}`")
    return node


def tool_tests():
    node = chromium()
    python = inspected(TOOLS)
    if run(["swift", "build", "--product", "MathMLExternalRender", "--jobs", JOBS, "--scratch-path", BUILD / "debug"],
           timeout=3600)[0]:
        raise Failed("the native renderer did not build")
    binaries = subprocess.run(["swift", "build", "--show-bin-path", "--scratch-path", BUILD / "debug"],
                              cwd=ROOT, capture_output=True, text=True, timeout=300, check=True).stdout.strip()
    return unittest_result(*run([python, "-m", "unittest", "discover", "-s", VALIDATION, "-p", "test_tools.py", "-v"],
                                timeout=1800, env={"MATHML_NATIVE_RENDERER": f"{binaries}/MathMLExternalRender",
                                                   "MATHML_BROWSER_NODE": node}), minimum=TOOL_TESTS)


def corpus():
    python = inspected(CORPUS)
    pins = json.loads((VALIDATION / "bundled-corpus-pins.json").read_text())
    missing = [entry["path"] for dataset in pins["datasets"] for entry in dataset["files"]
               if not (SOURCES / dataset["id"] / entry["path"]).is_file()]
    if missing:
        raise Unmeasured(f"{len(missing)} pinned corpus sources are not in {SOURCES}; run `{SETUP}`")
    status, _ = run([python, VALIDATION / "bundle_corpora.py", "--cache", SOURCES, "--verify"], timeout=1800)
    if status:
        raise Failed("the bundled corpus differs from its pinned regeneration")
    return "both datasets match their pinned regeneration"


def tree():
    """The checkout's tracked and untracked state, which no step may change."""
    return subprocess.run(["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"], cwd=ROOT,
                          capture_output=True, check=True, timeout=60).stdout + \
        subprocess.run(["git", "diff", "HEAD", "--binary"], cwd=ROOT, capture_output=True, check=True, timeout=60).stdout


def spelling():
    status, _ = run([sys.executable, "scripts/eng", "spelling"], timeout=600)
    if status == 2:
        raise Unmeasured("the spelling check could not read the tree")
    if status:
        raise Failed("British spellings found")
    return "passed"


STEPS = [
    ("gate tests", own_tests),
    ("documentation", lambda: checked([sys.executable, "scripts/eng", "docs", "check"])),
    ("spelling", spelling),
    ("macOS debug", lambda: swift_suite("debug")),
    ("macOS optimized", lambda: swift_suite("release", "-c", "release", "-Xswiftc", "-enable-testing")),
    ("iOS simulator", ios_suite),
    ("validation tools", tool_tests),
    ("bundled corpus", corpus),
]


def gate(steps=STEPS):
    """Run every step and return the exit status: 1 if any failed, else 3 if any is unmeasured."""
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True,
                            check=True, timeout=60).stdout.strip()
    before = tree()
    results = []
    for name, step in steps:
        print(f"\n=== {name}", flush=True)
        try:
            results.append((name, "passed", step()))
        except Failed as error:
            results.append((name, "failed", str(error)))
        except Unmeasured as error:
            results.append((name, "unmeasured", str(error)))
        except subprocess.TimeoutExpired as error:
            # A hang bound expired, which a busy host can also do: no result, not a failure.
            command = error.cmd[0] if isinstance(error.cmd, (list, tuple)) else error.cmd
            results.append((name, "unmeasured", f"`{command}` gave no result within {error.timeout:g} s"))
    if tree() != before:
        results.append(("checkout", "failed", "a step changed the checkout"))
    print(f"\n=== Gate for {commit}" + ("" if before == b"" else ", with local changes"))
    for name, outcome, detail in results:
        print(f"{outcome:>10}  {name}: {detail}")
    outcomes = {outcome for _, outcome, _ in results}
    return 1 if "failed" in outcomes else 3 if "unmeasured" in outcomes else 0


def setup():
    """Prepare what the gate reads but never fetches: two Python environments, the corpus sources and
    Playwright's Chromium. Pinned versions come from the repository; this is the only step that downloads."""
    uv = shutil.which("uv")
    if not uv:
        print("Setup needs uv (https://docs.astral.sh/uv/) to create the pinned Python environments.")
        return 2
    for environment, packages in [(TOOLS, ["-r", VALIDATION / "requirements.txt"]), (CORPUS, ["lxml==6.0.2"])]:
        subprocess.run([uv, "venv", "--python", "3.12", "--allow-existing", environment], check=True)
        install = [uv, "pip", "install", "--python", environment / "bin/python", *packages]
        subprocess.run(install, check=True)
        try:
            inspected(environment)
        except Unmeasured:
            # Reinstall the exact pins from fresh downloads once; never remove a quarantine attribute.
            subprocess.run([*install, "--reinstall", "--no-cache"], check=True)
            try:
                inspected(environment)
            except Unmeasured as error:
                print(f"Setup stopped: {error}")
                return 2
    subprocess.run([CORPUS / "bin/python", VALIDATION / "bundle_corpora.py", "--cache", SOURCES, "--download",
                    "--verify"], check=True)
    pnpm = shutil.which("pnpm")
    if not (shutil.which("node") and pnpm):
        print("Install Node 20+ and pnpm, then run setup again for Playwright's Chromium.")
        return 3
    subprocess.run([pnpm, "install", "--frozen-lockfile"], cwd=VALIDATION, check=True)
    subprocess.run([pnpm, "exec", "playwright", "install", "chromium"], cwd=VALIDATION, check=True)
    return 0


def main(arguments):
    if arguments == ["--setup"]:
        return setup()
    if arguments:
        # The gate is whole: a filter passed through `eng run gate -- …` would select part of it.
        print("gate.py takes no arguments but --setup; filter `swift test` directly instead (doc/testing.md)",
              file=sys.stderr)
        return 2
    def stopped(*_):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise Stopped()
    signal.signal(signal.SIGTERM, stopped)
    signal.signal(signal.SIGINT, stopped)
    try:
        return gate()
    except Stopped:
        print("\nThe gate was stopped: what it started has ended, and its result is unmeasured.", flush=True)
        return 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
