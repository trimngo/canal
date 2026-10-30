"""Select full Apple validation for code/build/test changes, or a fast docs gate."""
import os
from pathlib import PurePosixPath
import re
import subprocess


def requires_validation(paths):
    for path in paths:
        if path.startswith("native/"):
            if path.startswith("native/docs/") or path == "native/README.md":
                continue
            return True
        if PurePosixPath(path).match(".github/workflows/native-*.yml"):
            return True
        if path in {".github/scripts/native_changes.py", ".github/scripts/test_native_changes.py"}:
            return True
    return False


def main():
    base, head = os.environ.get("PR_BASE_SHA", ""), os.environ.get("PR_HEAD_SHA", "")
    if not base and not head:
        # Manual validation always runs the complete suite.
        native = True
    else:
        if not all(re.fullmatch(r"[0-9a-fA-F]{40}", value) for value in (base, head)):
            raise ValueError("Expected complete pull request commit IDs")
        changed = subprocess.check_output(["git", "diff", "--name-only", "--no-renames", "-z", base, head])
        native = requires_validation(changed.decode().split("\0"))
    print(f"native={str(native).lower()}")


if __name__ == "__main__":
    main()
