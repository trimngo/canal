import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("timer_validation", ROOT / "scripts/validate-timer-support.py")
validation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validation)


class TimerPackagingTests(unittest.TestCase):
    def fixture(self):
        group = "TEAM.com.trimngo.TimeLedger.watchkitapp"
        widget = {"NSExtension": {"NSExtensionPointIdentifier": "com.apple.widgetkit-extension"}}
        return {validation.PHONE: {"NSSupportsLiveActivities": True, "NSAlarmKitUsageDescription": "Timer alarms"},
                validation.WATCH: {"WKRunsIndependentlyOfCompanionApp": True, "WKBackgroundModes": ["alarm"], "LedgerCaptureAccessGroup": group},
                validation.WATCH + ".widgets": dict(copy.deepcopy(widget), LedgerCaptureAccessGroup=group),
                validation.PHONE + ".timerwidgets": widget}

    def test_complete_phone_and_standalone_watch_timer_package(self):
        validation.validate(self.fixture())

    def test_bundled_alarm_sound_is_valid_pcm_and_entirely_silent(self):
        validation.validate_silent_sound((ROOT / "iOS" / validation.SILENT_SOUND).read_bytes())

    def test_audible_or_damaged_sound_cannot_pass_release_validation(self):
        sound = (ROOT / "iOS" / validation.SILENT_SOUND).read_bytes()
        audible = bytearray(sound); audible[-1] = 1
        for bad in [bytes(audible), sound[:-1], b"not-a-sound"]:
            with self.subTest(length=len(bad)), self.assertRaises(ValueError):
                validation.validate_silent_sound(bad)

    def test_missing_phone_extension_cannot_pass_release_validation(self):
        fixture = self.fixture(); del fixture[validation.PHONE + ".timerwidgets"]
        with self.assertRaisesRegex(ValueError, "Missing timer bundle"):
            validation.validate(fixture)

    def test_system_alarm_permission_description_is_required(self):
        fixture = self.fixture(); del fixture[validation.PHONE]["NSAlarmKitUsageDescription"]
        with self.assertRaisesRegex(ValueError, "explain alarm permission"):
            validation.validate(fixture)

    def test_phone_dependent_or_wrong_alarm_mode_fails(self):
        for key, value in [("WKRunsIndependentlyOfCompanionApp", False), ("WKBackgroundModes", ["smart-alarm"])]:
            fixture = self.fixture(); fixture[validation.WATCH][key] = value
            with self.assertRaises(ValueError): validation.validate(fixture)

    def test_complication_must_be_able_to_read_shared_timer_summary(self):
        fixture = self.fixture(); fixture[validation.WATCH + ".widgets"]["LedgerCaptureAccessGroup"] = "other"
        with self.assertRaisesRegex(ValueError, "share the timer summary"):
            validation.validate(fixture)
