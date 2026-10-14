"""Retired cloud certificate generator.

Create the signing identity on your Mac and paste the encrypted bundle directly
into GitHub Secrets. This entry point fails closed so old automation cannot
create a certificate or publish its private key.
"""

if __name__ == "__main__":
    raise SystemExit(
        "Cloud certificate creation is disabled. Follow the manual signing "
        "instructions in native/README.md; no additional access token is needed."
    )
