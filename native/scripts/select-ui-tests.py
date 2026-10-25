#!/usr/bin/env python3
"""Partition the full iPhone UI suite without duplicating or dropping tests."""
import argparse
from pathlib import Path
import re


def select_tests(source, index, count):
    names = sorted(re.findall(r"^    func (test\w+)\(", source, re.MULTILINE))
    if not names or len(set(names)) != len(names):
        raise ValueError("Expected uniquely named UI test methods")
    if not 1 <= count <= len(names) or not 0 <= index < count:
        raise ValueError("Shard index/count would omit tests or select an empty shard")
    return names[index::count]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", required=True, type=int)
    parser.add_argument("--count", required=True, type=int)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / "Tests/TimeLedgerUITests.swift"
    try:
        tests = select_tests(source.read_text(), args.index, args.count)
    except ValueError as error:
        parser.error(str(error))
    for test in tests:
        print(f"-only-testing:TimeLedgerUITests/TimeLedgerUITests/{test}")


if __name__ == "__main__":
    main()
