#!/usr/bin/env python3
"""Check timer extension packaging and standalone Watch alarm declarations."""
import argparse
from pathlib import Path
import plistlib
import struct
import sys
from zipfile import ZipFile

PHONE = "com.trimngo.TimeLedger"
WATCH = PHONE + ".watchkitapp"
SILENT_SOUND = "DashSilent.caf"


def validate_silent_sound(data):
    """A missing or invalid custom sound can fall back to a loud system tone."""
    if data[:8] != b"caff\x00\x01\x00\x00":
        raise ValueError("Haptics-only alarm sound must be a valid CAF")
    chunks = {}
    offset = 8
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("Incomplete silent sound chunk")
        kind, size = struct.unpack(">4sq", data[offset:offset + 12])
        offset += 12
        if size < 0 or offset + size > len(data) or kind in chunks:
            raise ValueError("Invalid silent sound chunk")
        chunks[kind] = data[offset:offset + size]
        offset += size
    desc = chunks.get(b"desc", b"")
    if len(desc) != 32:
        raise ValueError("Missing silent sound format")
    rate, codec, flags, packet_bytes, frames, channels, bits = struct.unpack(">d4sIIIII", desc)
    samples = chunks.get(b"data", b"")
    if (rate, codec, flags, packet_bytes, frames, channels, bits) != (44100.0, b"lpcm", 2, 2, 1, 1, 16):
        raise ValueError("Silent sound must use mono PCM16 at 44100 Hz")
    if len(samples) != 44104 or any(samples):
        raise ValueError("Haptics-only sound must contain 0.5 seconds of silent audio")


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
                sounds = [name for name in archive.namelist() if name.startswith("Payload/") and name.count("/") == 2 and name.endswith("/" + SILENT_SOUND)]
                if len(sounds) != 1:
                    raise ValueError("The iPhone app must bundle its haptics-only alarm sound")
                validate_silent_sound(archive.read(sounds[0]))
        else:
            values = [plistlib.loads(path.read_bytes()) for app in args.apps for path in Path(app).rglob("Info.plist")]
            phone = next((Path(app) for app in args.apps if plistlib.loads((Path(app) / "Info.plist").read_bytes()).get("CFBundleIdentifier") == PHONE), None)
            if phone is None:
                raise ValueError("Missing iPhone timer app")
            validate_silent_sound((phone / SILENT_SOUND).read_bytes())
        validate({value["CFBundleIdentifier"]: value for value in values if "CFBundleIdentifier" in value})
    except Exception as error:
        print(f"Timer packaging validation failed: {error}", file=sys.stderr)
        return 1
    print("Verified standalone Watch alarm, shared complication summary, iPhone Live Activity, and silent alarm sound.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
