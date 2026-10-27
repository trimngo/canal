# Dash / canal agent handoff

The native iPhone and Apple Watch app is Dash. Start with
[native/README.md](native/README.md) for project commands and architecture.
Preserve uncommitted changes. Keep ongoing work active when discussing new
ideas; friend accountability sharing remains planning only.

## Active work: AlarmKit trial (2026-10-27)

The user approved trying phone-primary AlarmKit with Watch fallback while keeping
independent Watch timers and the iPhone/Mac Live Activity. Build 80 remains the
latest release; this new work must reach a new processed/distributed TestFlight
build. Release actions remain authorized. Preserve all uncommitted files/index.

Work checkpoint: `/workspace/work/alarmkit-81/state.json`. SDK candidate
`0441f21e280de0064454d12a21b898155b3cdf2b` on `ci/alarmkit-sdk` passed Native
timer trial checks run `40469308688`: both apps compile and 448 legacy core tests
pass. The latest complete trial now requires 465 core / 128 phone / 17 Watch
tests. The focused phone run `40471490507` passed 463 core, both builds, and
Stop/fallback UI flows; its two switch taps are being corrected without changing
assertions. The Watch focused run is `40471493251` (six cases). Follow the
checkpoint for the latest focused retry and full PR; do not release on focused
checks alone. Read [native/docs/alarmkit-trial.md](native/docs/alarmkit-trial.md). Finish core/UI regressions and focused SDK/UI checks
before opening the feature PR's full suite. Do not repeatedly cancel full CI.

Trial is opt-in (iPhone Timers → Timer settings → iPhone system alarms). Phone
alarms use Stop (silence, never complete) and Restart. Watch starts locally, then
offers phone takeover while active; the phone must actually schedule AlarmKit
before publishing ownership. Failure leaves Watch alerts in place. Explicit
Watch takeover stays available and persists for that task. There is no guaranteed
background switch after a later lost connection: WatchKit cannot arm/cancel while
inactive. A late handover can leave an old Watch alarm pending until reopening;
do not claim perfect failover or no possible duplicate alerts. Live Activity stays
independent of the alarm engine. Real Watch button/repeat behavior needs testing.

Native full checks now run on PR/manual dispatch, without a duplicate full main
UI run competing with delivery. Merge only after all full PR checks are green
and verify the native merge source equals the tested source. Release still runs
core tests and app builds before archiving. Watch UI step budget is 35 minutes
inside a 45-minute job. Focused `ci/alarmkit-ui` checks never replace the full PR.

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

- All 128 iPhone UI tests run across four shards. Keep the complete test set and
  meaningful assertions; do not skip failures to obtain a green run.
- Run Watch UI checks with `bash native/scripts/test-watch-ui.sh` on macOS.
  Run all 17 Watch UI tests. Repeating WatchKit haptics still require
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
Use an isolated `ci/watch-*` branch for the six focused Watch paging/queue
regressions before moving another Watch fix onto the feature PR. This keeps a
healthy full iPhone run active. Focused checks never replace the full release
checks: all 465 core, 128 iPhone UI, and 17 Watch UI tests must pass.

Full PR checks use four phone shards plus Watch. Branch pushes do not duplicate
PR runs. Simulator boot overlaps compilation. TestFlight delivery must finish
processing/distribution even if another main commit arrives.

## Release handoff snapshot: 2026-10-26

Release objective **COMPLETE**: TestFlight **1.0 (80)** is processed and available
to internal testers. The user explicitly authorized merging/uploading and asked
for a new available build; do not repeat that upload or treat build 79 as latest.
Keep existing work active when discussing new ideas.

- PR #3: https://github.com/trimngo/canal/pull/3 — merged as
  `a150fdd79dffa0cc6b91bcc3fa934fb3b0777a31`.
- Validated feature head: `3667af4b1f9879023a8728defbc4f9e720367aa9`.
  Its tree `0787170525c4975efa1626c7d8dd4a6ccb677604` exactly matches the merge.
- Full PR CI: https://github.com/trimngo/canal/actions/runs/40389281497 —
  **SUCCESS**, all **448 core, 124 iPhone UI, and 16 Watch UI tests** passed.
  A single XCTest activation-point error was retried in its phone shard on
  unchanged source/assertions; the pinned goal-unit-picker case then passed.
  Local Python validation passed all 22 tests.
- Delivery: https://github.com/trimngo/canal/actions/runs/40402462192 —
  **SUCCESS**, job `121851600612`. Packaged build **80** verified at 21:55:03 UTC;
  Apple processing and internal distribution both succeeded at
  **2026-10-26 22:00:51 UTC**. Upload acceptance alone was not used as proof.
- Automatic main CI https://github.com/trimngo/canal/actions/runs/40402462395 —
  **SUCCESS**, all **448 core, 124 iPhone UI, and 16 Watch UI tests** passed again
  on the merged source. Its initial Watch step hit the 30-minute limit after
  15 passing tests with no assertion failure. One Watch-only retry, job
  `121873487321`, passed all 16 tests (429.9 seconds of UI tests); the successful
  phone shards were retained. Both full CI runs and TestFlight delivery are
  complete; no validation or upload remains pending.

Implemented in build 80:

- Watch: circular progress, full wrapping titles in every state, sole new timer
  auto-start, complication opening the current task, native vertical paging,
  compact queue-only list with scrolling/reordering/deletion and return swipes.
  Main-screen options expose haptic presets, preview, and repeat intervals.
- Today: urgent original Inbox tasks grouped by category below the time dashboard,
  help popover, Review logs toolbar action, and category management in the filter.
- iPhone and mirrored Mac Live Activity: Restart with stale-action protection.
  Watch Restart/Done prioritize timer delivery over history/backoff. Latest timer
  context, atomic merge, ActivityKit-first refresh, coalescing, and finite phone
  background time improve the forwarding path. Apple controls the Mac hop;
  physical timing and repeating haptics still need a device check.
- iPhone/Mac Restart preserves an existing Watch alert destination and adds one
  phone backup alert. **Open Dash on Watch once to rearm repeating haptics after
  remote restart.** The phone timer and expanded Live Activity explain this.
  watchOS cannot rearm that alarm while Dash is inactive; an old scheduled alarm
  can still ring at its original deadline until reopening reconciles it.

Deployment findings and follow-up:

- Build 80 delivery spent about **32 minutes queued** behind all five occupied
  standard Mac slots, then about **16 minutes** building/uploading/processing.
  This fits the normal macOS concurrency limit, with no observed API rate-limit
  or billing error. See https://docs.github.com/en/actions/reference/limits.
- Already changed: four complete phone shards plus Watch, no duplicate native
  feature-push run, isolated focused Watch branches, early simulator boot,
  interrupted-result export guards, and non-cancelling TestFlight delivery.
- Remaining CI cleanup: automatic main-push full validation repeats the already
  validated PR tree and competes with delivery. Also, the Watch's 30-minute step
  budget can be too short for cold startup plus all 16 tests; consider 35 minutes
  within its 40-minute job budget. These are follow-ups, not changes in build 80.
  Keep all PR tests and assertions. Do not restart full runs to iterate on Watch.

The workspace still preserves uncommitted copies of published implementation.
Compare dirty files with current remote source before edits. Preserve local files
and the original Git index; do not reset or discard them. The index SHA-256 at
this handoff is `665903eef15410b31774c99b1869fe0e8ed8b7c92475752beb2a42d72343c6cf`.

The separate recent crash remains unidentified. The latest diagnostic run
`40385505398` still found only two submitted reports, both from build 9; do not
present those as evidence for a newer crash. Friend accountability sharing
remains planning only.

Refresh this snapshot when release, CI, or diagnostic status changes.

