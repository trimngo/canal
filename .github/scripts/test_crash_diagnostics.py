import io
import json
import unittest
from unittest.mock import MagicMock
import urllib.error

from crash_diagnostics import AppleAPI, NoRedirect, collect, collect_build_status, collect_upload_status, summarize


class DiagnosticPrivacyTests(unittest.TestCase):
    def test_report_content_cannot_appear_in_summary(self):
        private = "tester@example.com PRIVATE_KEY_FIXTURE My private activity /Users/PrivatePerson"
        log = private + " EXC_BREAKPOINT _dispatch_assert_queue_fail CompanionSync LedgerStore"
        result = summarize(log)
        self.assertEqual(result["exception"], "EXC_BREAKPOINT")
        self.assertIn("main_actor_assertion", result["signals"])
        self.assertIn("watch_sync", result["signals"])
        for value in private.split():
            self.assertNotIn(value, json.dumps(result))

    def test_empty_feedback_is_handled_without_private_metadata(self):
        api = MagicMock()
        api.get.side_effect = [{"data": [{"id": "123"}]}, {"data": []}]
        self.assertEqual(collect(api), {"submitted_reports_checked": 0, "summaries": []})

    def test_collection_emits_only_allowlisted_diagnostics(self):
        api = MagicMock()
        api.get.side_effect = [{"data": [{"id": "123"}]}, {"data": [{"id": "private-id", "attributes": {"email": "private@example.com"}}]}, {"data": {"attributes": {"logText": "EXC_CRASH NSInvalidArgumentException private@example.com"}}}]
        output = json.dumps(collect(api))
        self.assertNotIn("private-id", output)
        self.assertNotIn("private@example.com", output)
        self.assertIn("invalid_argument", output)

    def test_api_error_hides_token_and_response_body(self):
        api = AppleAPI("secret-token-fixture")
        api.opener.open = MagicMock(side_effect=urllib.error.HTTPError("https://api.appstoreconnect.apple.com", 403, "secret-token-fixture", {}, io.BytesIO(b"private-response")))
        with self.assertRaises(RuntimeError) as error:
            api.get("/v1/apps")
        self.assertNotIn("secret-token-fixture", str(error.exception))
        self.assertNotIn("private-response", str(error.exception))

    def test_credential_cannot_follow_redirect(self):
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, "", {}, "https://example.com"))

    def test_build_status_distinguishes_upload_processing_and_testing(self):
        api = MagicMock()
        api.get.side_effect = [
            {"data": [{"id": "private-app"}]},
            {"data": [{"id": "private-build", "attributes": {"version": "69", "processingState": "VALID", "expired": False}}]},
            {"data": {"attributes": {"internalBuildState": "IN_BETA_TESTING", "private": "tester@example.com"}}},
        ]
        status = collect_build_status(api)
        self.assertEqual(status, [{"build": "69", "processing": "VALID", "expired": False, "internal_testing": "IN_BETA_TESTING"}])
        self.assertNotIn("private", json.dumps(status))
        self.assertNotIn("tester@example.com", json.dumps(status))

    def test_build_status_hides_unexpected_response_strings(self):
        api = MagicMock()
        api.get.side_effect = [
            {"data": [{"id": "123"}]},
            {"data": [{"id": "build", "attributes": {"version": "69", "processingState": "private-response"}},
                      {"id": "other", "attributes": {"version": "private@example.com"}}]},
            {"data": {"attributes": {"internalBuildState": "private-response"}}},
        ]
        status = collect_build_status(api)
        self.assertEqual(status[0]["processing"], "UNKNOWN")
        self.assertEqual(status[0]["internal_testing"], "UNKNOWN")
        self.assertEqual(len(status), 1)
        self.assertNotIn("private", json.dumps(status))

    def test_no_uploaded_builds(self):
        api = MagicMock()
        api.get.side_effect = [{"data": [{"id": "123"}]}, {"data": []}]
        self.assertEqual(collect_build_status(api), [])

    def test_rejected_upload_is_visible_without_private_error_text(self):
        api = MagicMock()
        api.get.side_effect = [
            {"data": [{"id": "private-app"}]},
            {"data": [{"id": "private-upload", "attributes": {"cfBundleVersion": "69", "state": {
                "state": "FAILED", "errors": [{"description": "ITMS-90683 NSHealthUpdateUsageDescription tester@example.com /Users/Private"}],
                "warnings": []}}}]},
        ]
        self.assertEqual(collect_upload_status(api), [{"build": "69", "state": "FAILED", "error_count": 1,
                         "warning_count": 0, "issue_codes": ["ITMS-90683"], "purpose_keys": ["NSHealthUpdateUsageDescription"]}])

    def test_processing_upload_and_unknown_strings_are_safe(self):
        api = MagicMock()
        api.get.side_effect = [
            {"data": [{"id": "123"}]},
            {"data": [{"attributes": {"cfBundleVersion": "70", "state": {"state": "PROCESSING"}}},
                      {"attributes": {"cfBundleVersion": "68", "state": {"state": "private-response"}}},
                      {"attributes": {"cfBundleVersion": "private@example.com"}}]},
        ]
        statuses = collect_upload_status(api)
        self.assertEqual([s["state"] for s in statuses], ["PROCESSING", "UNKNOWN"])
        self.assertNotIn("private", json.dumps(statuses))


if __name__ == "__main__":
    unittest.main()
