#!/usr/bin/env python3
"""Check shipped Siri metadata, including the signed IPA, without reading keys."""
import argparse
import plistlib
import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile

EXPECTED = {
    "com.trimngo.TimeLedger",
    "com.trimngo.TimeLedger.watchkitapp",
    "com.trimngo.TimeLedger.watchkitapp.capture",
}
NOTE_INTENT = "INCreateNoteIntent"


def check_bundle(info, read_resource):
    identifier = info.get("CFBundleIdentifier")
    if identifier not in EXPECTED:
        return None
    if info.get("CFBundleDevelopmentRegion") != "en":
        raise ValueError(f"{identifier}: English development region is missing")
    extension = info.get("NSExtension", {}).get("NSExtensionAttributes", {})
    intents = info.get("INIntentsSupported", extension.get("IntentsSupported", []))
    if NOTE_INTENT not in intents:
        raise ValueError(f"{identifier}: note intent is not registered")
    vocabulary = plistlib.loads(read_resource("en.lproj/AppIntentVocabulary.plist"))
    examples = [phrase for item in vocabulary.get("IntentPhrases", [])
                if item.get("IntentName") == NOTE_INTENT
                for phrase in item.get("IntentExamples", [])
                if isinstance(phrase, str) and phrase.strip()]
    if len(examples) < 2 or not all("Dash" in phrase for phrase in examples):
        raise ValueError(f"{identifier}: English note example phrases are missing")
    if not any("idea," in phrase for phrase in examples) or not any("doing," in phrase for phrase in examples):
        raise ValueError(f"{identifier}: idea and activity examples are required")
    return identifier


def check_apps(paths):
    found = set()
    for path in paths:
        root = Path(path)
        if not root.is_dir():
            raise ValueError(f"App bundle does not exist: {root}")
        for bundle in [root] + [p.parent for p in root.rglob("Info.plist")]:
            info_path = bundle / "Info.plist"
            if not info_path.is_file():
                continue
            identifier = check_bundle(plistlib.loads(info_path.read_bytes()),
                                      lambda resource, bundle=bundle: (bundle / resource).read_bytes())
            if identifier:
                found.add(identifier)
    return found


def check_ipa(path):
    found = set()
    # Read only Info.plist and the public vocabulary, never certificates,
    # provisioning profiles, signing keys, or the executable.
    with ZipFile(path) as archive:
        for name in archive.namelist():
            if name.startswith("Payload/") and name.endswith("/Info.plist"):
                prefix = name[:-len("Info.plist")]
                identifier = check_bundle(plistlib.loads(archive.read(name)),
                                          lambda resource, prefix=prefix: archive.read(prefix + resource))
                if identifier:
                    found.add(identifier)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--apps", nargs="+")
    group.add_argument("--ipa")
    args = parser.parse_args()
    try:
        found = check_ipa(args.ipa) if args.ipa else check_apps(args.apps)
        if found != EXPECTED:
            raise ValueError("Missing Siri bundles: " + ", ".join(sorted(EXPECTED - found)))
        print("Verified English Siri note phrases in iPhone, Watch, and Watch Siri extension bundles.")
    except (ValueError, OSError, KeyError, BadZipFile, plistlib.InvalidFileException) as error:
        print(f"Siri support validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
