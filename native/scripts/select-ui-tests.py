#!/usr/bin/env python3
"""Partition the full iPhone UI suite without duplicating or dropping tests."""
import argparse
import json
import math
from pathlib import Path
import re
from statistics import median

DEFAULT_DURATIONS = Path(__file__).with_name("ui-test-durations.json")


def select_tests(source, index, count, durations=None):
    names = sorted(re.findall(r"^    func (test\w+)\(", source, re.MULTILINE))
    if not names or len(set(names)) != len(names):
        raise ValueError("Expected uniquely named UI test methods")
    if not 1 <= count <= len(names) or not 0 <= index < count:
        raise ValueError("Shard index/count would omit tests or select an empty shard")
    durations = {} if durations is None else durations
    if not isinstance(durations, dict) or any(
        isinstance(value, bool) or not isinstance(value, (int, float))
        or not math.isfinite(value) or value <= 0 for value in durations.values()
    ):
        raise ValueError("Test durations must be positive finite numbers")
    # Newly added tests still run, with the median observed cost as an estimate.
    known = [durations[name] for name in names if name in durations]
    fallback = median(known) if known else 1
    cost = {name: durations.get(name, fallback) for name in names}
    capacities = [len(names) // count + (shard < len(names) % count) for shard in range(count)]
    shards, loads = [[] for _ in range(count)], [0.0] * count
    for name in sorted(names, key=lambda name: (-cost[name], name)):
        target = min((shard for shard in range(count) if len(shards[shard]) < capacities[shard]),
                     key=lambda shard: (loads[shard], len(shards[shard]), shard))
        shards[target].append(name)
        loads[target] += cost[name]
    return sorted(shards[index])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--index", required=True, type=int)
    parser.add_argument("--count", required=True, type=int)
    parser.add_argument("--durations", type=Path, default=DEFAULT_DURATIONS)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / "Tests/TimeLedgerUITests.swift"
    try:
        durations = json.loads(args.durations.read_text())["seconds"]
        if not isinstance(durations, dict):
            raise ValueError("Expected a seconds mapping in the timings file")
        tests = select_tests(source.read_text(), args.index, args.count, durations)
    except (OSError, ValueError, KeyError, TypeError) as error:
        parser.error(str(error))
    for test in tests:
        print(f"-only-testing:TimeLedgerUITests/TimeLedgerUITests/{test}")


if __name__ == "__main__":
    main()
