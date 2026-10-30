import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import textwrap
import unittest

SCRIPT = Path(__file__).with_name("native_changes.py")
spec = importlib.util.spec_from_file_location("native_changes", SCRIPT)
changes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(changes)


class NativeChangeTests(unittest.TestCase):
    def test_every_application_build_resource_and_test_change_requires_full_validation(self):
        for path in ["native/iOS/App.swift", "native/Watch/App.swift", "native/Shared/Store.swift",
                     "native/Core/Sources/Model.swift", "native/Core/Package.swift", "native/project.yml",
                     "native/Watch/Assets.xcassets/icon.png", "native/Tests/UITests.swift",
                     "native/scripts/select-ui-tests.py", "native/TestsPython/test_ui_sharding.py"]:
            with self.subTest(path=path):
                self.assertTrue(changes.requires_validation([path]))

    def test_docs_only_and_root_handoff_changes_use_the_fast_gate(self):
        self.assertFalse(changes.requires_validation(["AGENTS.md", "README.md", "native/README.md",
                                                      "native/docs/ci-and-testflight.md"]))
        self.assertFalse(changes.requires_validation([]))

    def test_mixed_docs_and_code_cannot_skip_the_full_suite(self):
        self.assertTrue(changes.requires_validation(["native/docs/notes.md", "native/Shared/Store.swift"]))

    def test_validation_workflow_or_routing_changes_require_the_full_suite(self):
        for path in [".github/workflows/native-checks.yml", ".github/workflows/native-watch.yml",
                     ".github/scripts/native_changes.py", ".github/scripts/test_native_changes.py"]:
            with self.subTest(path=path):
                self.assertTrue(changes.requires_validation([path]))

    def test_manual_dispatch_requires_all_checks(self):
        env = dict(os.environ, PR_BASE_SHA="", PR_HEAD_SHA="")
        self.assertEqual(subprocess.check_output([sys.executable, str(SCRIPT)], env=env, text=True), "native=true\n")

    def test_incomplete_commit_metadata_fails_instead_of_skipping(self):
        env = dict(os.environ, PR_BASE_SHA="invalid", PR_HEAD_SHA="")
        result = subprocess.run([sys.executable, str(SCRIPT)], env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("native=false", result.stdout)

    def test_actual_gate_requires_successful_app_jobs_or_a_complete_docs_skip(self):
        workflow = SCRIPT.parent.parent / "workflows/native-checks.yml"
        gate = workflow.read_text().split("  native-validation:\n", 1)[1]
        command = textwrap.dedent(gate.split("        run: |\n", 1)[1])
        cases = [
            ("success", "true", "success", "success", True),
            ("success", "true", "failure", "success", False),
            ("success", "true", "success", "cancelled", False),
            ("failure", "true", "success", "success", False),
            ("success", "false", "skipped", "skipped", True),
            ("success", "false", "success", "skipped", False),
            ("success", "", "skipped", "skipped", False),
        ]
        for routing, changed, phone, watch, success in cases:
            with self.subTest(routing=routing, changed=changed, phone=phone, watch=watch):
                env = dict(os.environ, CHANGE_RESULT=routing, NATIVE_CHANGED=changed,
                           PHONE_RESULT=phone, WATCH_RESULT=watch)
                result = subprocess.run(["bash", "-e", "-c", command], env=env, capture_output=True)
                self.assertEqual(result.returncode == 0, success)
