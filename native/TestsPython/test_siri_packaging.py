import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("siri_validation", ROOT / "scripts/validate-siri-support.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class SiriPackagingTests(unittest.TestCase):
    def archive(self, path, missing_resource=None, language="en", shortcut_only=False):
        bundles = {
            "Payload/TimeLedger.app/": "com.trimngo.TimeLedger",
            "Payload/TimeLedger.app/Watch/TimeLedgerWatch.app/": "com.trimngo.TimeLedger.watchkitapp",
            "Payload/TimeLedger.app/Watch/TimeLedgerWatch.app/PlugIns/TimeLedgerWatchIntents.appex/": "com.trimngo.TimeLedger.watchkitapp.capture",
        }
        vocabulary = (ROOT / "SiriResources/en.lproj/AppIntentVocabulary.plist").read_bytes()
        if shortcut_only:
            vocabulary = plistlib.dumps({"AppShortcuts": ["Capture in Dash"]})
        with ZipFile(path, "w") as archive:
            for bundle, identifier in bundles.items():
                info = {"CFBundleIdentifier": identifier, "CFBundleDevelopmentRegion": "en"}
                if identifier.endswith(".capture"):
                    info["NSExtension"] = {"NSExtensionAttributes": {"IntentsSupported": ["INCreateNoteIntent"]}}
                else:
                    info["INIntentsSupported"] = ["INCreateNoteIntent"]
                archive.writestr(bundle + "Info.plist", plistlib.dumps(info))
                if identifier != missing_resource:
                    archive.writestr(bundle + language + ".lproj/AppIntentVocabulary.plist", vocabulary)

    def test_exported_ipa_checks_phone_watch_and_extension(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.ipa"
            self.archive(path)
            self.assertEqual(validation.check_ipa(path), validation.EXPECTED)

    def test_watch_extension_without_phrases_cannot_pass_release_check(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.ipa"
            self.archive(path, missing_resource="com.trimngo.TimeLedger.watchkitapp.capture")
            with self.assertRaises(KeyError):
                validation.check_ipa(path)

    def test_other_localization_does_not_satisfy_english_phrases(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.ipa"
            self.archive(path, language="de")
            with self.assertRaises(KeyError):
                validation.check_ipa(path)

    def test_app_shortcut_phrases_do_not_replace_sirikit_note_examples(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.ipa"
            self.archive(path, shortcut_only=True)
            with self.assertRaisesRegex(ValueError, "English note example phrases are missing"):
                validation.check_ipa(path)


if __name__ == "__main__":
    unittest.main()
