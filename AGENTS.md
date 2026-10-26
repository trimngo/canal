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
dialog. This avoids cold-simulator permission setup failures and interference
between permission sheets. The `allowReminders` test helper also drains an
initial notification permission sheet.

Clearing Inbox search can already be dismissing the keyboard asynchronously.
Do not use `if keyboard.done.exists { keyboard.done.tap() }` for that setup:
the button can vanish between the query and tap. Tap the stable Inbox navigation
bar and wait for the keyboard's nonexistence. When a test specifically exercises
Done, wait for a visible, hittable Done control before tapping it, then wait for
the resulting UI state.

## UI automation details

- Seed the Today urgent-task fixture **after** the generic `--ui-empty-ledger`
  reset. Otherwise the reset erases the fixture before the screen launches.
- DEBUG `--ui-*` fixtures do not exchange their synthetic ledger with the paired
  simulator. The explicit `--ui-companion-unavailable` failure path stays enabled.
  Companion transport has separate core regressions; verify actual device delivery.
- Watch timer pages use the native vertical TabView. Scroll long content first,
  then swipe past the page boundary to navigate. Native reorder requires a held
  row drag; custom gestures must not claim that hold or vertical scrolling.
- Watch haptic picker popup choices are accessibility **Buttons**. The selected
  value in the settings form is a StaticText. Drain the test timer's own system
  notification before launching the next fixture.
- Cold simulators can show Apple’s `UIContinuousPathIntroductionView` over the
  keyboard toolbar. The iPhone suite warms up the keyboard once per runner and
  dismisses only that tutorial’s Continue button. Keep real typing/Done/persistence
  assertions; do not diagnose an onboarding overlay as a missing app toolbar.
- Log inline fields share the parent keyboard toolbar. Wait for a hittable Done
  control and then keyboard disappearance when testing Done itself. Goal-unit
  tests wait for the unit selection before editing the recreated numeric input.
- Today has an intrinsic-height breakdown chart followed by urgent tasks. Avoid
  assertions that every dashboard page has the same height. Scroll the heatmap's
  own rows container after its selected detail increases in height.

## CI and release checks

- All 124 iPhone UI tests run across four shards. Keep the complete test set and
  meaningful assertions; do not skip failures to obtain a green run.
- Run Watch UI checks with `bash native/scripts/test-watch-ui.sh` on macOS.
  Run all 16 Watch UI tests. Repeating WatchKit haptics still require
  physical-device verification.
- A cancelled Xcode run can leave an incomplete `.xcresult`. Skip heavy exports
  after cancellation. For completed runs, export only when `Info.plist` exists.
  Raw `validation.log` / `watch-validation.log` are retained even on cancellation;
  complete simulator results and apps are uploaded for failures.
- Merging native changes to `main` starts the Native TestFlight delivery
  workflow. Verify the actual packaged build number, successful Apple
  processing, and distribution to internal testers. An accepted upload alone
  does not complete a TestFlight release task.

## Faster CI iteration

Read [native/docs/ci-and-testflight.md](native/docs/ci-and-testflight.md).
Use an isolated `ci/watch-*` branch for the five focused Watch paging/queue
regressions before moving another Watch fix onto the feature PR. This keeps a
healthy full iPhone run active. Focused checks never replace the full release
checks: all 448 core, 124 iPhone UI, and 16 Watch UI tests must pass.

Full PR checks use four phone shards plus Watch. Branch pushes do not duplicate
PR runs. Simulator boot overlaps compilation. TestFlight delivery must finish
processing/distribution even if another main commit arrives.

## Release handoff snapshot: 2026-10-26

Current objective: release the Watch timer, Today urgent-task, Live Activity
Restart, haptic options, and faster Watch Restart/Done sync changes in PR #3.
The user explicitly authorized merging and uploading and requested continuing
until a new TestFlight build is processed and available. Keep that objective
active when new ideas are discussed. Build 79 is the previous release.

- PR #3: https://github.com/trimngo/canal/pull/3
- Follow PR #3’s current head and Native Apple checks for the latest source
  and full run; earlier runs were superseded while fixing Watch paging.
- All 448 core tests passed in run 40381141224. The actual phone Live Activity
  restart preserving Watch alerts and explicit phone takeover passed too.
  Full iPhone/Watch validation remains pending; do not release on focused checks.
- After green checks, merge the validated head and follow Native TestFlight
  delivery through Apple processing and internal distribution. Verify the actual
  packaged build number; upload acceptance alone is insufficient.
- Watch options are on the main timer page. The queue page has only timer rows.
  Haptics & timer settings exposes three presets, preview, and repeat intervals.
- Watch Restart/Done use priority interactive delivery and a latest-state
  application context. iPhone refreshes ActivityKit before notifications, with
  pending-state coalescing and finite background time. Apple still controls the
  Mac forwarding hop; physical iPhone/Mac timing and repeating haptics need a
  device check after release.
- iPhone/Mac Restart preserves an existing Watch alert destination and adds a
  one-time iPhone backup notification. Dash must be opened on Watch to rearm
  repeating haptics after remote restart; the expanded Live Activity and phone
  timer explain this. Do not claim watchOS can rearm its alarm while inactive.
- The workspace preserves uncommitted copies of published implementation.
  Compare dirty files with current remote source before edits. Preserve local
  changes and the index; do not reset or discard them.
- The separate recent crash remains unidentified. Available reports were from
  build 9; do not present them as evidence for a newer crash.
- Friend accountability sharing remains planning only.

Refresh this dated snapshot when release or diagnostic status changes.
