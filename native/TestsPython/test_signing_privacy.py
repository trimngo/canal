import os
from pathlib import Path
import subprocess
import sys
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]


class SigningPrivacyTests(unittest.TestCase):
    def test_setup_guide_has_no_credentials_or_signing_exports(self):
        path = ROOT.parent / ".github/workflows/native-signing-setup.yml"
        source = path.read_text()
        workflow = yaml.safe_load(source)
        self.assertEqual(workflow["permissions"], {})
        self.assertNotIn("secrets.", source)
        self.assertNotIn("environment:", source)
        self.assertNotIn("upload-artifact", source)
        self.assertNotIn("create-signing-certificate.py", source)
        for job in workflow["jobs"].values():
            self.assertIn("github.ref == 'refs/heads/main'", job["if"])

    def test_cloud_certificate_generator_fails_without_reading_credentials(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / "scripts/create-signing-certificate.py")],
            env={"PATH": os.defpath}, capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Cloud certificate creation is disabled", result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertNotIn("Traceback", result.stderr)

    def test_testflight_delivery_is_main_only(self):
        path = ROOT.parent / ".github/workflows/native-testflight.yml"
        workflow = yaml.safe_load(path.read_text())
        self.assertIn("github.ref == 'refs/heads/main'", workflow["jobs"]["deliver"]["if"])


if __name__ == "__main__":
    unittest.main()
