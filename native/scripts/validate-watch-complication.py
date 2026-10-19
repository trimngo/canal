#!/usr/bin/env python3
"""Check the shipped complication and its launch route using public metadata."""
import argparse
from pathlib import Path
import plistlib
import sys
from zipfile import ZipFile

WATCH = "com.trimngo.TimeLedger.watchkitapp"
WIDGET = WATCH + ".widgets"


def validate(bundles):
    watches = [(path, info) for path, info in bundles.items() if info.get("CFBundleIdentifier") == WATCH]
    if len(watches) != 1:
        raise ValueError("Expected one embedded Dash Watch app")
    watch_path, watch = watches[0]
    widgets = [(path, info) for path, info in bundles.items() if info.get("CFBundleIdentifier") == WIDGET]
    if len(widgets) != 1:
        raise ValueError("Dash Watch complication extension is missing")
    path, widget = widgets[0]
    if not path.startswith(watch_path + "PlugIns/"):
        raise ValueError("Complication must be embedded inside the Watch app")
    if widget.get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
        raise ValueError("Complication must use the WidgetKit extension point")
    if not watch.get("CFBundleVersion") or widget.get("CFBundleVersion") != watch["CFBundleVersion"]:
        raise ValueError("Watch and complication build numbers must match")
    schemes = [scheme for entry in watch.get("CFBundleURLTypes", []) for scheme in entry.get("CFBundleURLSchemes", [])]
    if "canal-dash" not in schemes:
        raise ValueError("Watch complication launch URL is not registered")


def check_ipa(path):
    with ZipFile(path) as archive:
        bundles = {name[:-len("Info.plist")]: plistlib.loads(archive.read(name))
                   for name in archive.namelist() if name.startswith("Payload/") and name.endswith("/Info.plist")}
        validate(bundles)


def check_apps(paths):
    bundles = {}
    for root in map(Path, paths):
        for path in root.rglob("Info.plist"):
            bundles[str(path.parent) + "/"] = plistlib.loads(path.read_bytes())
    validate(bundles)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apps", nargs="+")
    group.add_argument("--ipa")
    args = parser.parse_args()
    try:
        check_ipa(args.ipa) if args.ipa else check_apps(args.apps)
    except (ValueError, OSError, KeyError) as error:
        print(f"Watch complication validation failed: {error}", file=sys.stderr)
        return 1
    print("Verified embedded Watch complication, matching build number, and direct logging route.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
