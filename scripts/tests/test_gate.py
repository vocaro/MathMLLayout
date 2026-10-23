"""The release gate's judgments, without running a suite."""
import contextlib
import io
from pathlib import Path
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gate  # noqa: E402


def xctest_log(executed, failures=0, skipped=0, outcome="passed"):
    skips = f"with {skipped} test{'s' if skipped != 1 else ''} skipped and " if skipped else "with "
    return (f"Test Suite 'MathMLLayoutTests.xctest' {outcome} at 2026-10-23 12:00:00.000.\n"
            f"\t Executed {executed} tests, {skips}{failures} failures (0 unexpected) in 1.0 (1.0) seconds\n"
            f"Test Suite 'All tests' {outcome} at 2026-10-23 12:00:00.001.\n"
            f"\t Executed {executed} tests, {skips}{failures} failures (0 unexpected) in 1.0 (1.0) seconds\n")


class SuiteJudgmentTests(unittest.TestCase):
    def test_a_full_suite_with_nothing_skipped_passes(self):
        self.assertEqual(gate.xctest(0, xctest_log(804)), "804 tests passed, none skipped")

    def test_a_failed_test_fails_the_suite(self):
        with self.assertRaisesRegex(gate.Failed, "1 of 804 tests failed"):
            gate.xctest(1, xctest_log(804, failures=1, outcome="failed"))

    def test_a_skipped_test_fails_the_suite(self):
        with self.assertRaisesRegex(gate.Failed, "1 of 804 tests skipped"):
            gate.xctest(0, xctest_log(804, skipped=1))

    def test_fewer_tests_than_the_floor_fail_the_suite(self):
        with self.assertRaisesRegex(gate.Failed, "ran 803 tests, fewer than 804"):
            gate.xctest(0, xctest_log(803))

    def test_a_build_failure_fails_and_a_silent_success_is_unmeasured(self):
        with self.assertRaisesRegex(gate.Failed, "exited 1 before reporting any test totals"):
            gate.xctest(1, "error: compile command failed\n")
        with self.assertRaises(gate.Unmeasured):
            gate.xctest(0, "Build complete!\n")

    def test_unittest_summaries(self):
        self.assertEqual(gate.unittest_result(0, "Ran 12 tests in 3.1s\n\nOK\n", 12), "12 tests passed, none skipped")
        with self.assertRaisesRegex(gate.Failed, "2 of 12 tests skipped"):
            gate.unittest_result(0, "Ran 12 tests in 3.1s\n\nOK (skipped=2)\n", 12)
        with self.assertRaisesRegex(gate.Failed, "failures=1"):
            gate.unittest_result(1, "Ran 12 tests in 3.1s\n\nFAILED (failures=1)\n", 12)
        with self.assertRaisesRegex(gate.Failed, "fewer than 12"):
            gate.unittest_result(0, "Ran 11 tests in 3.1s\n\nOK\n", 12)


class PrerequisiteTests(unittest.TestCase):
    def test_missing_node_leaves_the_tool_tests_unmeasured(self):
        with mock.patch.object(gate.shutil, "which", return_value=None):
            with self.assertRaisesRegex(gate.Unmeasured, "Node 20\\+ is not installed"):
                gate.tool_tests()

    def test_a_missing_environment_or_source_cache_is_unmeasured(self):
        with mock.patch.object(gate, "CORPUS", Path("/nonexistent/corpus-venv")):
            with self.assertRaisesRegex(gate.Unmeasured, "no Python environment"):
                gate.corpus()


class OutcomeTests(unittest.TestCase):
    def outcome(self, *results):
        def step(result):
            def run():
                if isinstance(result, Exception): raise result
                return result
            return run
        with mock.patch.object(gate, "tree", return_value=b""), contextlib.redirect_stdout(io.StringIO()):
            return gate.gate([(f"step {index}", step(result)) for index, result in enumerate(results)])

    def test_only_a_run_of_passed_steps_exits_0(self):
        self.assertEqual(self.outcome("passed", "passed"), 0)
        self.assertEqual(self.outcome("passed", gate.Unmeasured("no Chromium")), 3)
        self.assertEqual(self.outcome(gate.Unmeasured("no Chromium"), gate.Failed("1 failed")), 1)

    def test_a_step_that_changes_the_checkout_fails_the_gate(self):
        states = iter([b"", b" M Sources/MathMLLayout/Glyph.swift\0"])
        with mock.patch.object(gate, "tree", side_effect=lambda: next(states)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(gate.gate([("step", lambda: "passed")]), 1)

    def test_arguments_other_than_setup_are_refused(self):
        self.assertEqual(gate.main(["--filter", "Speech"]), 2)


if __name__ == "__main__":
    unittest.main()
