import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("healthkit_validation", ROOT / "scripts/validate-healthkit.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class HealthKitPackagingTests(unittest.TestCase):
    def info(self):
        return {"CFBundleIdentifier": "com.trimngo.TimeLedger", "NSHealthShareUsageDescription": "Read recorded daylight.",
                "NSHealthUpdateUsageDescription": "Dash does not write health data."}

    def test_missing_update_description_reproduces_rejected_upload(self):
        info = self.info()
        del info["NSHealthUpdateUsageDescription"]
        with self.assertRaisesRegex(ValueError, "NSHealthUpdateUsageDescription"):
            validation.check_info(info)

    def test_both_purposes_must_be_nonempty_strings(self):
        for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
            for bad in (None, " ", 1):
                with self.subTest(key=key, value=bad):
                    info = self.info()
                    info[key] = bad
                    with self.assertRaisesRegex(ValueError, key):
                        validation.check_info(info)

    def test_signed_archive_checks_phone_rather_than_watch_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.ipa"
            with ZipFile(path, "w") as archive:
                archive.writestr("Payload/Dash.app/Info.plist", plistlib.dumps(self.info()))
                archive.writestr("Payload/Dash.app/Watch/DashWatch.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": "com.trimngo.TimeLedger.watchkitapp"}))
            validation.check_ipa(path)
            with ZipFile(path, "w") as archive:
                archive.writestr("Payload/Dash.app/Watch/DashWatch.app/Info.plist", plistlib.dumps(self.info()))
            with self.assertRaisesRegex(ValueError, "missing from the IPA"):
                validation.check_ipa(path)


if __name__ == "__main__":
    unittest.main()
