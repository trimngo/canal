#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
python3 -m unittest discover -s TestsPython -p 'test_*packaging.py' -v
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

if [[ "${LEDGER_UI_TESTS:-0}" == "1" ]]; then
  DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; d=json.load(sys.stdin); print(next(x["udid"] for runtime,devices in d["devices"].items() if "iOS" in runtime for x in devices if x["name"].startswith("iPhone")))')
  xcrun simctl boot "$DEVICE_ID" || true
  xcrun simctl bootstatus "$DEVICE_ID" -b
  xcrun simctl ui "$DEVICE_ID" appearance dark
  xcodebuild -project TimeLedger.xcodeproj -scheme TimeLedger \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testGoalUnitsShowOneValueAndHourEditsConvertToFixedPercentages \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testOptionalGoalsAndOtherActivitiesShowCapacityWithoutAllocating100 \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testTimeModeWithoutCompletedDataPreservesExistingPercentageGoals \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testInvalidHoursStayEditableAndUnitSwitchDoesNotDiscardThem \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testHistoricalAverageUsesCompletedDaysWhileTodayStaysLive \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testGoalsAutosaveNestedValuesAndUnfinishedTotalsAcrossRestart \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testCopyMeasuredWeekMakesFixedGoalsAndContextualHelpStaysHidden \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testNestedCalculatedGoalsAndDirectRowsHaveNoEditableTarget \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testBulkGroupingIntoExistingParentPreviewsGoalsAndCanUndo \
    -only-testing:TimeLedgerUITests/TimeLedgerUITests/testSingleTapCategoryActionsAndExplicitMultipleSelection \
    -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build \
    -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO test
fi
