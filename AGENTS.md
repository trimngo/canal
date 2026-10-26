# Dash / canal agent handoff

The native iPhone and Apple Watch app is Dash. Start with
[native/README.md](native/README.md) for project commands and architecture.
Preserve uncommitted changes. Keep ongoing work active when discussing new
ideas; friend accountability sharing remains planning only.

## Simulator test setup

Run the full iPhone UI validation on macOS with Xcode:

```sh
LEDGER_UI_TESTS=1 bash native/scripts/validate.sh
```

The validation script boots the selected iPhone simulator, installs the built
app, and grants the Reminders integration tests their prerequisite access:

```sh
xcrun simctl bootstatus "$DEVICE_ID" -b
xcrun simctl install "$DEVICE_ID" build/Build/Products/Debug-iphonesimulator/TimeLedger.app
xcrun simctl privacy "$DEVICE_ID" grant reminders com.trimngo.TimeLedger
```

These commands run from `native/` inside the UI-test block of `validate.sh`.
Keep that setup in the script. The tests exercise real EventKit list transfers,
deletion safety, and persistence; they do not need to test Apple's permission
dialog. Requesting Reminders access while another system permission sheet is
appearing has left cold simulators waiting indefinitely. The `allowReminders`
test helper also drains an initial notification permission sheet.

Clearing Inbox search can already be dismissing the keyboard asynchronously.
Do not use `if keyboard.done.exists { keyboard.done.tap() }` for that setup:
the button can vanish between the query and tap. Tap the stable Inbox navigation
bar and wait for the keyboard's nonexistence. When a test specifically exercises
Done, wait for a visible, hittable Done control before tapping it, then wait for
the resulting UI state.

## CI and release checks

- All 120 iPhone UI tests run across six shards. Keep the complete test set and
  meaningful assertions; do not skip failures to obtain a green run.
- Run Watch UI checks with `bash native/scripts/test-watch-ui.sh` on macOS.
  Repeating WatchKit haptics still require physical-device verification.
- A cancelled Xcode run can leave an incomplete `.xcresult`. Export it only
  when `Info.plist` exists; preserve `validation.log` / `watch-validation.log`
  for diagnosis. An export error after interruption is a secondary failure.
- Merging native changes to `main` starts the Native TestFlight delivery
  workflow. Verify the actual packaged build number, successful Apple
  processing, and distribution to internal testers. An accepted upload alone
  does not complete a TestFlight release task.

## Active handoff snapshot: 2026-10-26

Check live links before relying on this dated status:

- [PR #2](https://github.com/trimngo/canal/pull/2) contains the Watch alarm
  lifecycle fix, current-timer-first screen, upward animated queue navigation,
  compact rows, touch scrolling, and native reordering.
- [Full CI run 40281874588](https://github.com/trimngo/canal/actions/runs/40281874588)
  validates commit `7fa6452` with the simulator setup above. The prior run passed
  437 core tests and all 13 Watch UI tests; three of 120 iPhone tests failed
  during permission or keyboard setup, prompting this harness fix.
- The active release goal is a new processed, available TestFlight build
  containing these changes. Build 78 was the latest verified release before
  this work. Keep working through CI, merge, delivery, and processing.
- The user's separate recent crash remains unidentified. Available crash
  reports were from build 9; do not present them as evidence for a newer crash.

Update this snapshot when the release completes.
