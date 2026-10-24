"""Read submitted TestFlight crash feedback; publish only allowlisted signals.

Raw reports and tester metadata never leave process memory or appear in output.
Signing credentials stay in GitHub Secrets; this uses only the Apple API key.
"""
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request


SIGNALS = {
    "main_actor_assertion": ("_dispatch_assert_queue_fail", "swift_task_checkIsolated", "swift_task_isCurrentExecutor"),
    "watch_sync": ("WatchConnectivity", "CompanionSync"),
    "local_save": ("LedgerStore",),
    "sample_editor": ("CheckInEditor", "CheckInView"),
    "notification_handler": ("NotificationScheduler",),
    "notification_response": ("didReceiveNotificationResponse", "didReceive response", "didReceive:"),
    "notification_presentation": ("willPresentNotification", "willPresent notification", "willPresent:"),
    "completion_handler_violation": ("completion handler was never called", "completion handler more than once", "completion handler was called more than once"),
    "main_thread_violation": ("must be used from main thread only", "must be called on the main thread", "must be performed on the main thread"),
    "objc_internal_inconsistency": ("NSInternalInconsistencyException",),
    "objc_range_exception": ("NSRangeException",),
    "abort_signal": ("SIGABRT",),
    "notification_async_bridge": ("async completion handler block", "@objc completion handler block"),
    "keyboard_focus": ("UIKeyboard", "FocusState", "becomeFirstResponder"),
    "dispatch_queue_assertion": ("dispatch_assert_queue", "_dispatch_assert_queue_fail"),
    "swiftui": ("SwiftUI",),
    "invalid_argument": ("NSInvalidArgumentException",),
    "swift_runtime_trap": ("_assertionFailure", "swift_dynamicCastFailure", "swift_unexpectedError"),
}
EXCEPTIONS = ("EXC_BAD_ACCESS", "EXC_CRASH", "EXC_BREAKPOINT", "EXC_RESOURCE", "EXC_GUARD", "EXC_SOFTWARE")


def summarize(log):
    # Emit only constants from these allowlists, never strings from a report.
    return {
        "exception": next((kind for kind in EXCEPTIONS if kind in log), "unknown"),
        "signals": [name for name, needles in SIGNALS.items() if any(needle in log for needle in needles)],
    }


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class AppleAPI:
    def __init__(self, token):
        self.token = token
        self.opener = urllib.request.build_opener(NoRedirect())

    def get(self, path, query=None):
        if not re.fullmatch(r"/v1/[A-Za-z0-9/_-]+", path):
            raise RuntimeError("Invalid Apple API resource path.")
        url = "https://api.appstoreconnect.apple.com" + path
        if query:
            url += "?" + urllib.parse.urlencode(query)
        request = urllib.request.Request(url, headers={"Authorization": "Bearer " + self.token, "Accept": "application/json"})
        try:
            with self.opener.open(request, timeout=45) as response:
                data = response.read(2_000_001)
                if len(data) > 2_000_000:
                    raise RuntimeError("Apple diagnostic response exceeded the size limit.")
                return json.loads(data)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Apple diagnostic request failed (HTTP {error.code}). No private response content was printed.") from None
        except (urllib.error.URLError, TimeoutError, ValueError):
            raise RuntimeError("Could not read Apple crash feedback. No private response content was printed.") from None


def collect(api):
    apps = api.get("/v1/apps", {"filter[bundleId]": "com.trimngo.TimeLedger", "limit": 1})["data"]
    if not apps:
        raise RuntimeError("Time Ledger app record was not found.")
    app_id = apps[0]["id"]
    reports = api.get(f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions", {"limit": 10, "fields[betaFeedbackCrashSubmissions]": "crashLog"})["data"]
    summaries = []
    for report in reports:
        crash = api.get(f"/v1/betaFeedbackCrashSubmissions/{report['id']}/crashLog", {"fields[betaCrashLogs]": "logText"})
        log = crash.get("data", {}).get("attributes", {}).get("logText", "")
        summaries.append(summarize(log if isinstance(log, str) else ""))
    return {"submitted_reports_checked": len(reports), "summaries": summaries}


def collect_build_status(api):
    """Read release availability without emitting tester data or API identifiers."""
    apps = api.get("/v1/apps", {"filter[bundleId]": "com.trimngo.TimeLedger", "limit": 1})["data"]
    if not apps:
        raise RuntimeError("Time Ledger app record was not found.")
    builds = api.get("/v1/builds", {"filter[app]": apps[0]["id"], "sort": "-uploadedDate", "limit": 3,
                                   "fields[builds]": "version,processingState,expired"})["data"]
    processing_states = {"PROCESSING", "FAILED", "INVALID", "VALID"}
    beta_states = {"PROCESSING", "PROCESSING_EXCEPTION", "MISSING_EXPORT_COMPLIANCE", "READY_FOR_BETA_TESTING",
                   "IN_BETA_TESTING", "EXPIRED", "IN_EXPORT_COMPLIANCE_REVIEW"}
    statuses = []
    for build in builds:
        attributes = build.get("attributes", {})
        version = attributes.get("version", "")
        if not isinstance(version, str) or not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version):
            continue
        state = attributes.get("processingState")
        status = {"build": version, "processing": state if state in processing_states else "UNKNOWN",
                  "expired": attributes.get("expired") is True}
        detail = api.get(f"/v1/builds/{build['id']}/buildBetaDetail").get("data") or {}
        internal = detail.get("attributes", {}).get("internalBuildState")
        status["internal_testing"] = internal if internal in beta_states else "UNKNOWN"
        statuses.append(status)
    return statuses


def main():
    import jwt
    try:
        token = jwt.encode(
            {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
            os.environ["APP_STORE_CONNECT_KEY_P8"], algorithm="ES256", headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"]},
        )
    except Exception:
        raise RuntimeError("Could not authenticate the Apple diagnostic request. Check the configured API key secrets.") from None
    try:
        api = AppleAPI(token)
        result = collect(api)
        result["recent_builds"] = collect_build_status(api)
    except (KeyError, TypeError):
        raise RuntimeError("Unexpected Apple diagnostic response. No private response content was printed.") from None
    output = json.dumps(result, sort_keys=True)
    print(output)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as summary:
            summary.write("## TestFlight diagnostic signals\n\nOnly allowlisted indicators are shown. Full reports and tester data remain private.\n\n```json\n" + output + "\n```\n")
            if not result["submitted_reports_checked"]:
                summary.write("\nNo submitted crash feedback is available yet. This API may not include every automatically collected Apple crash.\n")


if __name__ == "__main__":
    main()
