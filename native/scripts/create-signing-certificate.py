"""Create an Apple signing identity and save it directly into GitHub Secrets.

All private files stay inside a temporary directory. No certificate artifact or
downloadable file is published. Requires PyJWT[crypto], PyNaCl, and openssl.
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
from signing_secrets import SigningSecrets, NoRedirect


def create() -> None:
    store = SigningSecrets.from_environment()
    password = os.environ["APPLE_DISTRIBUTION_P12_PASSWORD"]
    if len(password) < 32:
        raise RuntimeError("Use a randomly generated certificate password of at least 32 characters.")
    if not store.prepare():
        print("Signing bundle is already configured. No new certificate was created.")
        return
    try:
        token = jwt.encode(
            {"iss": os.environ["APP_STORE_CONNECT_ISSUER_ID"], "iat": int(time.time()),
             "exp": int(time.time()) + 1190, "aud": "appstoreconnect-v1"},
            os.environ["APP_STORE_CONNECT_KEY_P8"], algorithm="ES256",
            headers={"kid": os.environ["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"},
        )
    except Exception:
        raise RuntimeError("Could not authenticate with the Apple API key. Check the key, issuer ID, and key ID secrets.") from None
    with tempfile.TemporaryDirectory(prefix="ledger-signing-") as directory:
        scratch = Path(directory)
        key, csr, certificate, pem, bundle = [scratch / name for name in ["private.pem", "request.csr", "distribution.cer", "distribution.pem", "distribution.p12"]]
        subprocess.run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-out", str(csr), "-subj", "/CN=Time Ledger Cloud Signing"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        body = {"data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr.read_text()}}}
        request = urllib.request.Request("https://api.appstoreconnect.apple.com/v1/certificates", data=json.dumps(body).encode(), headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.build_opener(NoRedirect()).open(request, timeout=60) as response:
                result = json.load(response)["data"]
        except urllib.error.HTTPError as error:
            raise RuntimeError(f"Apple rejected certificate creation (HTTP {error.code}). Check API key role and available distribution-certificate slots.") from None
        certificate.write_bytes(base64.b64decode(result["attributes"]["certificateContent"]))
        subprocess.run(["openssl", "x509", "-inform", "DER", "-in", str(certificate), "-out", str(pem)], check=True)
        subprocess.run(["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(pem), "-out", str(bundle), "-passout", "env:APPLE_DISTRIBUTION_P12_PASSWORD"], check=True)
        store.save_bundle(base64.b64encode(bundle.read_bytes()).decode("ascii"))
    print("Saved the encrypted signing bundle directly into GitHub environment secrets. No downloadable file was published.")
    try:
        store.remove_temporary_token()
        print("Removed SIGNING_SECRET_WRITE_TOKEN from the environment. Revoke the temporary token in your GitHub account settings.")
    except Exception:
        print("Signing bundle was saved. Remove SIGNING_SECRET_WRITE_TOKEN manually and revoke the temporary token in GitHub settings.")


if __name__ == "__main__":
    os.umask(0o077)
    create()
