"""One-time Apple Distribution certificate creation on a cloud Mac.

Writes only a password-encrypted PKCS#12 artifact; unencrypted private keys
live in a temporary directory and are removed on exit. Never prints secrets.
Requires PyJWT[crypto], openssl, and the protected workflow's environment.
"""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.error
import urllib.request

import jwt


def create(output: Path) -> None:
    password = os.environ["APPLE_DISTRIBUTION_P12_PASSWORD"]
    if len(password) < 32:
        raise RuntimeError("Use a randomly generated certificate password of at least 32 characters.")
    private_key = base64.b64decode(os.environ["APP_STORE_CONNECT_KEY_P8_BASE64"], validate=True)
    token = jwt.encode(
        {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": int(time.time()),
         "exp": int(time.time()) + 1190, "aud": "appstoreconnect-v1"},
        private_key, algorithm="ES256",
        headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
    )
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="ledger-signing-") as directory:
        scratch = Path(directory)
        key, csr, certificate, pem, bundle = [scratch / name for name in ["private.pem", "request.csr", "distribution.cer", "distribution.pem", "distribution.p12"]]
        subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-out", str(csr), "-subj", "/CN=Time Ledger Cloud Signing"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        body = {"data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr.read_text()}}}
        request = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/certificates", data=json.dumps(body).encode(), headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                result = json.load(response)["data"]
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Apple rejected certificate creation (HTTP {error.code}). Check API key role and available distribution-certificate slots.") from None
        certificate.write_bytes(base64.b64decode(result["attributes"]["certificateContent"]))
        subprocess.run(["openssl", "x509", "-inform", "DER", "-in", str(certificate), "-out", str(pem)], check=True)
        subprocess.run(["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(pem), "-out", str(bundle), "-passout", "env:APPLE_DISTRIBUTION_P12_PASSWORD"], check=True)
        (output / "APPLE_DISTRIBUTION_P12_BASE64.txt").write_text(base64.b64encode(bundle.read_bytes()).decode())
        (output / "certificate-info.json").write_text(json.dumps({"id": result["id"], "expirationDate": result["attributes"].get("expirationDate")}, indent=2))
    print("Created encrypted signing bundle. Copy its text into the matching GitHub secret; do not paste it into chat.")


if __name__ == "__main__":
    os.umask(0o077)
    create(Path(os.environ["SIGNING_OUTPUT_DIRECTORY"]))
