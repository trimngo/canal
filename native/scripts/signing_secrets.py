"""Private signing-bundle delivery to GitHub environment secrets.

No artifacts, logs, release assets, or repository files contain the bundle.
The temporary token is restricted to Environments:write on this repository.
"""
import base64
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_SECRET = "APPLE_DISTRIBUTION_P12_BASE64"
WRITER_SECRET = "SIGNING_SECRET_WRITE_TOKEN"


class SecretStorageError(RuntimeError):
    def __init__(self, message, status=None):
        super().__init__(message)
        self.status = status


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward the credential to another destination.


def seal(public_key, value):
    from nacl.public import PublicKey, SealedBox
    try:
        key = PublicKey(base64.b64decode(public_key, validate=True))
        encrypted = SealedBox(key).encrypt(value.encode("utf-8"))
        return base64.b64encode(encrypted).decode("ascii")
    except Exception:
        raise SecretStorageError("Could not encrypt the signing bundle for GitHub.") from None


class SigningSecrets:
    def __init__(self, repository, token, run_id):
        if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
            raise SecretStorageError("Invalid GitHub repository identifier.")
        if not run_id.isdigit() or not token:
            raise SecretStorageError("Missing SIGNING_SECRET_WRITE_TOKEN or workflow run ID.")
        self.token = token
        self.base = f"https://api.github.com/repos/{repository}/environments/apple-testflight/secrets"
        self.probe = "_TIME_LEDGER_SIGNING_CHECK_" + run_id
        self.public_key = None
        self.opener = urllib.request.build_opener(NoRedirect())

    @classmethod
    def from_environment(cls):
        if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("GITHUB_REF") != "refs/heads/main":
            raise SecretStorageError("Signing setup must run on the main branch in GitHub Actions.")
        return cls(os.environ.get("GITHUB_REPOSITORY", ""), os.environ.get(WRITER_SECRET, ""), os.environ.get("GITHUB_RUN_ID", ""))

    def request(self, method, suffix, body=None):
        data = None if body is None else json.dumps(body).encode("utf-8")
        request = urllib.request.Request(self.base + suffix, data=data, method=method, headers={
            "Authorization": "Bearer " + self.token,
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "Time-Ledger-private-signing",
        })
        try:
            with self.opener.open(request, timeout=60) as response:
                if response.status not in (200, 201, 204):
                    raise SecretStorageError("Unexpected GitHub secret-storage response.")
                payload = response.read()
                return json.loads(payload) if payload else None
        except urllib.error.HTTPError as error:
            # Never include response bodies, tokens, or encrypted/private values.
            raise SecretStorageError(f"GitHub secret storage failed (HTTP {error.code}). Check the token's Environments:write permission and repository selection.", error.code) from None
        except (urllib.error.URLError, TimeoutError, ValueError):
            raise SecretStorageError("Could not reach GitHub secret storage. No downloadable signing file was published.") from None

    def _put(self, name, value):
        if name not in (BUNDLE_SECRET, self.probe) or self.public_key is None:
            raise SecretStorageError("Signing secret storage has not passed its access check.")
        if len(value.encode("utf-8")) > 48000:
            raise SecretStorageError("Signing bundle exceeds GitHub's secret size limit.")
        body = {"key_id": self.public_key["key_id"], "encrypted_value": seal(self.public_key["key"], value)}
        self.request("PUT", "/" + name, body)

    def prepare(self):
        self.public_key = self.request("GET", "/public-key")
        if not isinstance(self.public_key, dict) or not self.public_key.get("key") or not self.public_key.get("key_id"):
            raise SecretStorageError("GitHub did not return an environment encryption key.")
        try:
            self.request("GET", "/" + BUNDLE_SECRET)
        except SecretStorageError as error:
            if error.status != 404:
                raise
        else:
            return False  # Preserve an existing signing identity; never replace it silently.
        # Prove write access before generating a private key or creating an Apple certificate.
        self._put(self.probe, "Time Ledger signing storage permission check")
        self.request("DELETE", "/" + self.probe)
        return True

    def save_bundle(self, encoded_bundle):
        self._put(BUNDLE_SECRET, encoded_bundle)

    def remove_temporary_token(self):
        self.request("DELETE", "/" + WRITER_SECRET)
