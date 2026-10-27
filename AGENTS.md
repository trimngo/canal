# Dash / canal agent handoff

The native iPhone and Apple Watch app is Dash. Start with
[native/README.md](native/README.md) for project commands and architecture.
Preserve uncommitted changes. Keep ongoing work active when discussing new
ideas; friend accountability sharing remains planning only.

## Latest release: TestFlight 81 (2026-10-27)

Release objective **COMPLETE**: TestFlight **1.0 (81)** finished Apple processing
and was distributed to internal testers at **2026-10-27 10:12:08 UTC**. Do not
repeat this upload. The user authorized continuing through merge and a new
available TestFlight build; that release is now complete. Preserve local files
and the original Git index when beginning further work.

- PR #4: https://github.com/trimngo/canal/pull/4 — merged as
  `1bfad1bd3a1cd782d44002f7e0fcca842d618289`, the build 81 app source.
- Validated head `4bb1d1e35ebf8202faa1ec2ca16d8871c31f2868` and merge have the
  identical tree `a559db87222ac4437c108380c5c04f3616abe997`.
- Full CI: https://github.com/trimngo/canal/actions/runs/40478588242 — **SUCCESS**:
  **465 core, all 128 iPhone UI, and all 17 Watch UI tests**. Source coverage was
  checked with no omitted or duplicated UI cases. All passed on the first full
  attempt. Focused phone (4) and Watch (6) checks also passed before the PR.
- Delivery: https://github.com/trimngo/canal/actions/runs/40484970675 — **SUCCESS**,
  job `122124371983`. The actual packaged build **81** was verified at 10:07:38 UTC;
  processing and internal distribution both succeeded at 10:12:08 UTC. An accepted
  upload alone was not used as release proof.
- Post-merge signing checks `40484970670` passed all 23 packaging/CI tests.
- The later diagnostics-only commit `7a6b86943816078c9607ac0a7d877ed2231cac18`
  preserves the app's native tree `e8173430e63985dbbdae607b57cfbff52a69bb06`.
  It does not trigger another TestFlight upload. Root handoff updates also leave
  app source unchanged.

Read [native/docs/alarmkit-trial.md](native/docs/alarmkit-trial.md). Enable the
opt-in trial on an iPhone running iOS 26 or later: **Timers → Timer settings →
iPhone system alarms (trial)**, then grant alarm permission. Existing installs
retain their previous behavior until enabled. Test with a new phone timer.
Phone-owned timers use a fixed AlarmKit alarm with the task title, Stop (silence
only, never complete), and Restart. The existing iPhone/Mac ActivityKit countdown
remains the shared display. Permission/API failure retains notification fallback.

Watch timers first arm locally. A foreground start/restart/resume/Done & Next can
offer phone takeover with at least 15 seconds remaining. Phone ownership is
published only after actual scheduling and a matching, still-active Watch offer
and cancellable session. Failed confirmation retains Watch alerts. **Use Watch
for alerts** persists for that task; **Use iPhone system alarm** retries transfer
in Watch timer options. Enabling the trial alone does not move an existing
Watch-owned alarm while Watch is inactive. Open Watch to choose a destination.

There is no guaranteed background switch after a later lost connection: WatchKit
cannot arm/cancel while inactive. A late transition after readiness can leave an
old Watch alarm pending until reopening and cause a duplicate. Do not claim
perfect failover or instant Mac mirroring. Watch haptic presets apply to Watch
alarms; Apple controls forwarded system alarm feedback. **Physical verification
of forwarded Watch buttons, repeating haptics, and device-to-device timing remains
necessary**; simulator success does not establish those behaviors.

All five full-CI Macs started without a queue. Full validation took about 50
minutes: the four phone shards spent about 26–33 minutes in UI tests plus cold
setup/build time. Removing duplicate post-merge full UI checks let delivery get
a Mac immediately and finish in about 13 minutes. No GitHub API throttling error
was observed. Watch UI has a 35-minute step inside a 45-minute job; phone
validation has a 50-minute step inside a 60-minute job. Keep every full PR test.

Crash diagnostics were repaired to count an individual missing Apple crash log
(HTTP 404) and continue checking other reports and release status. Auth, rate
limit, and server errors still fail visibly; output remains allowlisted. All
14 privacy tests passed locally and in run `40485421706`, job `122125879664`.
At 10:03 UTC it found **3 submissions: two available logs from build 9 and one
unavailable log**. The user's recent crash remains unidentified; do not attribute
it to build 9 or treat the missing log as proof of a particular build.

Detailed checkpoint: `/workspace/work/alarmkit-81/state.json`. The local branch
still intentionally preserves uncommitted copies of published work; compare
against current remote source before edits. Original index SHA-256:
`665903eef15410b31774c99b1869fe0e8ed8b7c92475752beb2a42d72343c6cf`.

## Device follow-up: Watch handoff (2026-10-27)

The user initially suspected a Watch-started timer was not accepted by iPhone,
then clarified that Watch showed **iPhone system alarm confirmed**. After checking,
the user reported that it works properly. Basic handoff is therefore confirmed
on their devices; the cause of the earlier one-off observation remains unknown.
No app code has been changed for this report. Do not present a speculative timing
race as its established cause or repeat the already-complete build 81 release.

The user also asked about haptic-only AlarmKit alerts. Apple's documented sound
API exposes default/custom audio, with no direct haptic-only or independent
Watch-sound setting. A silent bundled sound is only a possible workaround and
needs physical verification of retained/repeating Watch haptics. The scope question
(Watch only versus both iPhone and Watch) is still pending. Keep this preference
active without changing existing alarm behavior on an assumption. Investigation
notes: `/workspace/work/alarmkit-82/state.json`; no build 82 has been started.

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

## Previous release: build 80 (2026-10-26)

Historical release: TestFlight **1.0 (80)** was processed and available before
build 81. The latest release and remaining physical checks are documented above.
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
- Resolved in build 81: removed the redundant main-push full UI run and raised
  Watch validation to a 35-minute step inside a 45-minute job. The full PR checks
  remain required. Keep all tests/assertions and do not restart healthy full runs
  to iterate on Watch.

The workspace still preserves uncommitted copies of published implementation.
Compare dirty files with current remote source before edits. Preserve local files
and the original Git index; do not reset or discard them. The index SHA-256 at
this handoff is `665903eef15410b31774c99b1869fe0e8ed8b7c92475752beb2a42d72343c6cf`.

The historical successful diagnostic run `40385505398` found two build 9
reports. The current diagnostic status is documented above; the recent user
crash remains unidentified. Friend accountability sharing remains planning only.

Refresh this snapshot when release, CI, or diagnostic status changes.

