#!/usr/bin/env python3
"""Validate shipped iPhone HealthKit purpose strings without reading keys."""
import argparse
import plistlib
import sys
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile


def check_info(info):
    if info.get("CFBundleIdentifier") != "com.trimngo.TimeLedger":
        raise ValueError("Dash iPhone bundle is missing")
    for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
        value = info.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"Missing HealthKit purpose string: {key}")


def check_ipa(path):
    with ZipFile(path) as archive:
        for name in archive.namelist():
            parts = PurePosixPath(name).parts
            if len(parts) == 3 and parts[0] == "Payload" and parts[1].endswith(".app") and parts[2] == "Info.plist":
                check_info(plistlib.loads(archive.read(name)))
                return
    raise ValueError("Dash iPhone Info.plist is missing from the IPA")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--app")
    group.add_argument("--ipa")
    args = parser.parse_args()
    try:
        if args.ipa:
            check_ipa(args.ipa)
        else:
            check_info(plistlib.loads((Path(args.app) / "Info.plist").read_bytes()))
    except (ValueError, OSError, KeyError, BadZipFile, plistlib.InvalidFileException) as error:
        print(f"HealthKit packaging validation failed: {error}", file=sys.stderr)
        return 1
    print("Verified both HealthKit purpose strings in the iPhone bundle.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
