#!/usr/bin/env python3
"""Check timer extension packaging and standalone Watch alarm declarations."""
import argparse
from pathlib import Path
import plistlib
import sys
from zipfile import ZipFile

PHONE = "com.trimngo.TimeLedger"
WATCH = PHONE + ".watchkitapp"


def validate(infos):
    for identifier in [PHONE, WATCH, WATCH + ".widgets", PHONE + ".timerwidgets"]:
        if identifier not in infos:
            raise ValueError(f"Missing timer bundle: {identifier}")
    if infos[PHONE].get("NSSupportsLiveActivities") is not True:
        raise ValueError("The iPhone app must support Live Activities")
    if not infos[PHONE].get("NSAlarmKitUsageDescription", "").strip():
        raise ValueError("The iPhone system alarm trial must explain alarm permission")
    if infos[WATCH].get("WKRunsIndependentlyOfCompanionApp") is not True:
        raise ValueError("The Watch app must run independently of the phone")
    if "alarm" not in infos[WATCH].get("WKBackgroundModes", []):
        raise ValueError("The Watch app must declare its alarm background mode")
    group = infos[WATCH].get("LedgerCaptureAccessGroup")
    if not isinstance(group, str) or not group or infos[WATCH + ".widgets"].get("LedgerCaptureAccessGroup") != group:
        raise ValueError("The Watch and complication must share the timer summary access group")
    for identifier in [WATCH + ".widgets", PHONE + ".timerwidgets"]:
        if infos[identifier].get("NSExtension", {}).get("NSExtensionPointIdentifier") != "com.apple.widgetkit-extension":
            raise ValueError(f"Timer extension is not registered with WidgetKit: {identifier}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apps", nargs="+")
    group.add_argument("--ipa")
    args = parser.parse_args()
    try:
        if args.ipa:
            with ZipFile(args.ipa) as archive:
                values = [plistlib.loads(archive.read(name)) for name in archive.namelist() if name.startswith("Payload/") and name.endswith("/Info.plist")]
        else:
            values = [plistlib.loads(path.read_bytes()) for app in args.apps for path in Path(app).rglob("Info.plist")]
        validate({value["CFBundleIdentifier"]: value for value in values if "CFBundleIdentifier" in value})
    except Exception as error:
        print(f"Timer packaging validation failed: {error}", file=sys.stderr)
        return 1
    print("Verified standalone Watch alarm, shared complication summary, and iPhone Live Activity bundles.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
