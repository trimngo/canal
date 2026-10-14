import base64
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import signing_secrets as secrets

spec = importlib.util.spec_from_file_location("certificate_setup", ROOT / "scripts/create-signing-certificate.py")
certificate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(certificate)


class SigningPrivacyTests(unittest.TestCase):
    def store(self):
        return secrets.SigningSecrets("trimngo/canal", "fixture-token-not-a-credential", "123")

    def test_feature_branch_cannot_use_signing_setup(self):
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/feature"}):
            with self.assertRaises(secrets.SecretStorageError):
                secrets.SigningSecrets.from_environment()

    def test_missing_writer_token_prevents_any_certificate_creation(self):
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_REF": "refs/heads/main", "GITHUB_REPOSITORY": "trimngo/canal", "GITHUB_RUN_ID": "123", "SIGNING_SECRET_WRITE_TOKEN": ""}), patch.object(certificate.subprocess, "run") as command:
            with self.assertRaises(secrets.SecretStorageError):
                certificate.create()
            command.assert_not_called()

    def test_existing_bundle_is_preserved(self):
        store = self.store()
        store.request = MagicMock(side_effect=[{"key": "public-fixture", "key_id": "1"}, {"name": secrets.BUNDLE_SECRET}])
        self.assertFalse(store.prepare())
        self.assertEqual([c.args[0] for c in store.request.call_args_list], ["GET", "GET"])

    def test_write_permission_is_checked_before_creating_certificate(self):
        store = self.store()
        store.request = MagicMock(side_effect=[{"key": "public-fixture", "key_id": "1"}, secrets.SecretStorageError("absent", 404), secrets.SecretStorageError("denied", 403)])
        with patch.object(secrets, "seal", return_value="encrypted-fixture"), patch.object(certificate.SigningSecrets, "from_environment", return_value=store), patch.dict(os.environ, {"APPLE_DISTRIBUTION_P12_PASSWORD": "x" * 32}), patch.object(certificate.subprocess, "run") as command:
            with self.assertRaises(secrets.SecretStorageError):
                certificate.create()
            command.assert_not_called()

    def test_permission_probe_is_removed(self):
        store = self.store()
        store.request = MagicMock(side_effect=[{"key": "public-fixture", "key_id": "1"}, secrets.SecretStorageError("absent", 404), None, None])
        with patch.object(secrets, "seal", return_value="encrypted-fixture"):
            self.assertTrue(store.prepare())
        self.assertEqual(store.request.call_args_list[-1].args, ("DELETE", "/_TIME_LEDGER_SIGNING_CHECK_123"))

    def test_secret_write_contains_only_ciphertext(self):
        store = self.store(); store.public_key = {"key": "public-fixture", "key_id": "1"}
        store.request = MagicMock()
        with patch.object(secrets, "seal", return_value="opaque-ciphertext"):
            store.save_bundle("sensitive-fixture")
        method, suffix, body = store.request.call_args.args
        self.assertEqual((method, suffix), ("PUT", "/APPLE_DISTRIBUTION_P12_BASE64"))
        self.assertEqual(body, {"key_id": "1", "encrypted_value": "opaque-ciphertext"})
        self.assertNotIn("sensitive-fixture", json.dumps(body))

    @unittest.skipUnless(importlib.util.find_spec("nacl"), "PyNaCl is installed in cloud CI")
    def test_github_sealed_box_encrypts_and_round_trips(self):
        from nacl.public import PrivateKey, SealedBox
        key = PrivateKey.generate()
        public = base64.b64encode(bytes(key.public_key)).decode()
        encrypted = secrets.seal(public, "private-signing-fixture")
        self.assertNotIn("private-signing-fixture", encrypted)
        self.assertEqual(SealedBox(key).decrypt(base64.b64decode(encrypted)), b"private-signing-fixture")

    def test_api_errors_do_not_expose_tokens_or_response_content(self):
        store = self.store()
        store.opener.open = MagicMock(side_effect=urllib.error.HTTPError(store.base, 403, "fixture-token-not-a-credential", {}, io.BytesIO(b"private-response-fixture")))
        with self.assertRaises(secrets.SecretStorageError) as failure:
            store.request("GET", "/public-key")
        self.assertNotIn("fixture-token-not-a-credential", str(failure.exception))
        self.assertNotIn("private-response-fixture", str(failure.exception))

    def test_authentication_headers_are_not_forwarded_on_redirect(self):
        self.assertIsNone(secrets.NoRedirect().redirect_request(None, None, 302, "redirect", {}, "https://example.com"))

    def test_private_files_are_removed_and_bundle_is_saved_before_token_cleanup(self):
        store = MagicMock(); store.prepare.return_value = True
        response = MagicMock()
        response.__enter__.return_value.read.return_value = json.dumps({"data": {"id": "fixture", "attributes": {"certificateContent": base64.b64encode(b"public-certificate-fixture").decode()}}}).encode()
        temporary_paths = []

        def command(args, **kwargs):
            if args[1] == "req":
                key = Path(args[args.index("-keyout") + 1]); temporary_paths.append(key.parent)
                key.write_bytes(b"private-fixture")
                Path(args[args.index("-out") + 1]).write_text("public-csr-fixture")
            else:
                Path(args[args.index("-out") + 1]).write_bytes(b"encrypted-bundle-fixture")

        values = {"APPLE_DISTRIBUTION_P12_PASSWORD": "x" * 32, "APP_STORE_CONNECT_KEY_P8": "private-api-fixture", "APP_STORE_CONNECT_KEY_ID": "fixture", "APP_STORE_CONNECT_ISSUER_ID": "fixture"}
        output = io.StringIO()
        with patch.dict(os.environ, values), patch.object(certificate.SigningSecrets, "from_environment", return_value=store), patch.object(certificate.jwt, "encode", return_value="jwt-fixture"), patch.object(certificate.urllib.request, "build_opener") as opener, patch.object(certificate.subprocess, "run", side_effect=command), contextlib.redirect_stdout(output):
            opener.return_value.open.return_value = response
            certificate.create()
        self.assertTrue(all(not path.exists() for path in temporary_paths))
        store.save_bundle.assert_called_once_with(base64.b64encode(b"encrypted-bundle-fixture").decode())
        names = [call[0] for call in store.mock_calls]
        self.assertLess(names.index("save_bundle"), names.index("remove_temporary_token"))
        self.assertNotIn("private-api-fixture", output.getvalue())
        self.assertNotIn("encrypted-bundle-fixture", output.getvalue())

    def test_workflows_do_not_export_signing_files_and_are_main_only(self):
        import yaml
        workflow = yaml.safe_load((ROOT.parent / ".github/workflows/native-signing-setup.yml").read_text())
        job = workflow["jobs"]["create"]
        self.assertIn("github.ref == 'refs/heads/main'", job["if"])
        self.assertFalse(any("upload-artifact" in step.get("uses", "") for step in job["steps"]))
        self.assertNotIn("SIGNING_OUTPUT_DIRECTORY", json.dumps(job))
        delivery = yaml.safe_load((ROOT.parent / ".github/workflows/native-testflight.yml").read_text())
        self.assertIn("github.ref == 'refs/heads/main'", delivery["jobs"]["deliver"]["if"])


if __name__ == "__main__":
    unittest.main()
