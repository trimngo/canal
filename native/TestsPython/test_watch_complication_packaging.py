import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("complication_validation", ROOT / "scripts/validate-watch-complication.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class ComplicationPackagingTests(unittest.TestCase):
    def fixture(self):
        watch = "Payload/TimeLedger.app/Watch/TimeLedgerWatch.app/"
        return {
            watch: {"CFBundleIdentifier": validation.WATCH, "CFBundleVersion": "41",
                    "CFBundleURLTypes": [{"CFBundleURLSchemes": ["canal-dash"]}]},
            watch + "PlugIns/TimeLedgerWatchWidgets.appex/": {
                "CFBundleIdentifier": validation.WIDGET, "CFBundleVersion": "41",
                "NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}},
        }

    def test_ipa_contains_a_launchable_watch_complication(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "app.ipa"
            with ZipFile(path, "w") as archive:
                for prefix, info in self.fixture().items():
                    archive.writestr(prefix + "Info.plist", plistlib.dumps(info))
            validation.check_ipa(path)

    def test_missing_extension_cannot_pass_delivery(self):
        bundles = self.fixture(); bundles.pop(next(path for path in bundles if "PlugIns" in path))
        with self.assertRaisesRegex(ValueError, "missing"): validation.validate(bundles)

    def test_phone_embedded_extension_cannot_replace_watch_complication(self):
        bundles = self.fixture(); key = next(path for path in bundles if "PlugIns" in path)
        bundles["Payload/TimeLedger.app/PlugIns/Widgets.appex/"] = bundles.pop(key)
        with self.assertRaisesRegex(ValueError, "inside the Watch"): validation.validate(bundles)

    def test_unregistered_url_cannot_pass_delivery(self):
        bundles = self.fixture(); next(info for info in bundles.values() if info["CFBundleIdentifier"] == validation.WATCH).pop("CFBundleURLTypes")
        with self.assertRaisesRegex(ValueError, "URL"): validation.validate(bundles)

    def test_wrong_extension_type_and_build_number_cannot_pass(self):
        for key, value in [("NSExtension", {}), ("CFBundleVersion", "40")]:
            bundles = self.fixture(); widget = next(info for info in bundles.values() if info["CFBundleIdentifier"] == validation.WIDGET)
            widget[key] = value
            with self.assertRaises(ValueError): validation.validate(bundles)


if __name__ == "__main__": unittest.main()
