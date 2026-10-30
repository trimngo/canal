import importlib.util
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ui_selection", ROOT / "scripts/select-ui-tests.py")
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class UIShardingTests(unittest.TestCase):
    def test_every_actual_ui_test_runs_exactly_once_across_ci_shards(self):
        source = (ROOT / "Tests/TimeLedgerUITests.swift").read_text()
        expected = re.findall(r"func (test\w+)\(", source)
        workflow = (ROOT.parent / ".github/workflows/native-checks.yml").read_text()
        indices = json.loads(re.search(r"shard: (\[[^\]]+\])", workflow).group(1))
        count = int(re.search(r"LEDGER_UI_TEST_SHARDS: '(\d+)'", workflow).group(1))
        self.assertEqual(indices, list(range(count)))
        shards = []
        for index in indices:
            output = subprocess.check_output([sys.executable, str(ROOT / "scripts/select-ui-tests.py"),
                                              "--index", str(index), "--count", str(count)], text=True)
            prefix = "-only-testing:TimeLedgerUITests/TimeLedgerUITests/"
            self.assertTrue(all(line.startswith(prefix) for line in output.splitlines()))
            shards.append([line.removeprefix(prefix) for line in output.splitlines()])
        self.assertCountEqual([test for shard in shards for test in shard], expected)
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 1)

    def test_test_order_does_not_change_shard_assignment(self):
        first = "    func testB() {}\n    func testA() {}\n    func testC() {}"
        second = "    func testC() {}\n    func testB() {}\n    func testA() {}"
        for index in range(2):
            self.assertEqual(selection.select_tests(first, index, 2), selection.select_tests(second, index, 2))

    def test_slow_cases_are_spread_across_workers_without_changing_coverage(self):
        source = "\n".join(f"    func test{letter}() {{}}" for letter in "ABCDEF")
        durations = {"testA": 100, "testB": 1, "testC": 100, "testD": 1, "testE": 1, "testF": 1}
        shards = [selection.select_tests(source, index, 2, durations) for index in range(2)]
        self.assertCountEqual([name for shard in shards for name in shard], durations)
        self.assertEqual([len(shard) for shard in shards], [3, 3])
        self.assertEqual([sum(durations[name] for name in shard) for shard in shards], [102, 102])

    def test_new_tests_run_and_removed_timing_entries_do_not_create_tests(self):
        source = "    func testA() {}\n    func testNew() {}\n    func testB() {}"
        durations = {"testA": 100, "testB": 20, "testRemoved": 500}
        shards = [selection.select_tests(source, index, 2, durations) for index in range(2)]
        self.assertCountEqual([name for shard in shards for name in shard], ["testA", "testB", "testNew"])
        reordered = "    func testB() {}\n    func testA() {}\n    func testNew() {}"
        for index in range(2):
            self.assertEqual(shards[index], selection.select_tests(reordered, index, 2, durations))

    def test_invalid_timings_fail_visibly(self):
        for value in [0, -1, float("nan"), float("inf"), True, "10"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                selection.select_tests("    func testA() {}", 0, 1, {"testA": value})

    def test_invalid_or_empty_shards_fail_instead_of_skipping_coverage(self):
        source = "    func testA() {}"
        for index, count in [(-1, 1), (1, 1), (0, 0), (0, 2)]:
            with self.subTest(index=index, count=count), self.assertRaises(ValueError):
                selection.select_tests(source, index, count)
        with self.assertRaises(ValueError):
            selection.select_tests("", 0, 1)
