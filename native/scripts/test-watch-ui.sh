#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
DASH_SIMULATOR_ARCH=$(uname -m)
xcodegen generate
mkdir -p build
python3 - <<'PY' > build/watch-test-devices.json
import json, subprocess
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
pairs = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'pairs', '-j']))['pairs']
available = {item['udid'] for group in devices.values() for item in group}
pair = next((p for p in pairs.values() if p.get('watch', {}).get('udid') in available and p.get('phone', {}).get('udid') in available), None)
if pair:
    watch, phone = pair['watch']['udid'], pair['phone']['udid']
else:
    used = {p[k]['udid'] for p in pairs.values() for k in ('watch', 'phone') if k in p}
    watch = next(d['udid'] for runtime, group in devices.items() if 'watchOS' in runtime for d in group if d['udid'] not in used)
    phone = next(d['udid'] for runtime, group in devices.items() if 'iOS' in runtime for d in group if d['name'].startswith('iPhone') and d['udid'] not in used)
    subprocess.check_output(['xcrun', 'simctl', 'pair', watch, phone])
print(json.dumps({'watch': watch, 'phone': phone}))
PY
WATCH_DEVICE_ID=$(python3 -c 'import json; print(json.load(open("build/watch-test-devices.json"))["watch"])')
PHONE_DEVICE_ID=$(python3 -c 'import json; print(json.load(open("build/watch-test-devices.json"))["phone"])')
# Start simulator warmup while the unsigned app compiles. bootstatus below
# remains the synchronization point if a paired device could not boot yet.
xcrun simctl boot "$PHONE_DEVICE_ID" || true
xcrun simctl boot "$WATCH_DEVICE_ID" || true
xcodebuild -project TimeLedger.xcodeproj -scheme TimeLedger \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build \
  ARCHS="$DASH_SIMULATOR_ARCH" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build
xcrun simctl bootstatus "$PHONE_DEVICE_ID" -b
xcrun simctl bootstatus "$WATCH_DEVICE_ID" -b
xcrun simctl install "$PHONE_DEVICE_ID" build/Build/Products/Debug-iphonesimulator/TimeLedger.app
xcodebuild -project TimeLedger.xcodeproj -scheme TimeLedgerWatch \
  -destination "platform=watchOS Simulator,id=$WATCH_DEVICE_ID" -derivedDataPath build \
  -resultBundlePath build/WatchUITests.xcresult CODE_SIGNING_ALLOWED=NO \
  ARCHS="$DASH_SIMULATOR_ARCH" ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 300 "$@" test
