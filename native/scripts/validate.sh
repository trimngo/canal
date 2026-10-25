#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
python3 -m unittest discover -s TestsPython -v
swift test --package-path Core
xcodebuild -project TimeLedger.xcodeproj -scheme TimeLedger \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TimeLedger.xcodeproj -scheme TimeLedgerWatch \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build

python3 scripts/validate-siri-support.py --apps \
  build/Build/Products/Debug-iphonesimulator/TimeLedger.app \
  build/Build/Products/Debug-watchsimulator/TimeLedgerWatch.app

python3 scripts/validate-watch-complication.py --apps \
  build/Build/Products/Debug-watchsimulator/TimeLedgerWatch.app

python3 scripts/validate-healthkit.py --app \
  build/Build/Products/Debug-iphonesimulator/TimeLedger.app

python3 scripts/validate-timer-support.py --apps \
  build/Build/Products/Debug-iphonesimulator/TimeLedger.app \
  build/Build/Products/Debug-watchsimulator/TimeLedgerWatch.app

if [[ "${LEDGER_UI_TESTS:-0}" == "1" ]]; then
  # Keep a nonempty array for macOS's Bash 3.2 with nounset enabled.
  UI_TEST_SELECTION=("-only-testing:TimeLedgerUITests")
  if [[ -n "${LEDGER_UI_TEST_SHARD:-}${LEDGER_UI_TEST_SHARDS:-}" ]]; then
    # Write first so a bad shard configuration fails validation rather than
    # silently falling back to the entire suite via process substitution.
    python3 scripts/select-ui-tests.py --index "${LEDGER_UI_TEST_SHARD:-}" \
      --count "${LEDGER_UI_TEST_SHARDS:-}" > build/ui-test-selection.txt
    UI_TEST_SELECTION=()
    while IFS= read -r selected; do
      UI_TEST_SELECTION+=("$selected")
    done < build/ui-test-selection.txt
  fi
  DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime,devices in d["devices"].items() if "iOS" in runtime for x in devices if x["name"].startswith("iPhone")))')
  xcodebuild -project TimeLedger.xcodeproj -scheme TimeLedger \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build \
    -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO \
    -parallel-testing-enabled NO "${UI_TEST_SELECTION[@]}" test
fi
