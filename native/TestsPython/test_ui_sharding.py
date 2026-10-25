import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("ui_selection", ROOT / "scripts/select-ui-tests.py")
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)


class UIShardingTests(unittest.TestCase):
    def test_every_actual_ui_test_runs_exactly_once_across_ci_shards(self):
        source = (ROOT / "Tests/TimeLedgerUITests.swift").read_text()
        expected = re.findall(r"func (test\w+)\(", source)
        shards = [selection.select_tests(source, index, 6) for index in range(6)]
        self.assertCountEqual([test for shard in shards for test in shard], expected)
        self.assertLessEqual(max(map(len, shards)) - min(map(len, shards)), 1)

    def test_test_order_does_not_change_shard_assignment(self):
        first = "    func testB() {}\n    func testA() {}\n    func testC() {}"
        second = "    func testC() {}\n    func testB() {}\n    func testA() {}"
        for index in range(2):
            self.assertEqual(selection.select_tests(first, index, 2), selection.select_tests(second, index, 2))

    def test_invalid_or_empty_shards_fail_instead_of_skipping_coverage(self):
        source = "    func testA() {}"
        for index, count in [(-1, 1), (1, 1), (0, 0), (0, 2)]:
            with self.subTest(index=index, count=count), self.assertRaises(ValueError):
                selection.select_tests(source, index, count)
        with self.assertRaises(ValueError):
            selection.select_tests("", 0, 1)
