# Dash / canal agent handoff

The native iPhone and Apple Watch app is Dash. Start with
[native/README.md](native/README.md) for project commands and architecture.
Preserve uncommitted changes. Keep ongoing work active when discussing new
ideas; friend accountability sharing remains planning only.

## Active work: calendar categorization and release validation (2026-10-28)

The user's calendar request is implemented: Review logs uses the same offline
AutomaticCategories actor as ordinary logs and Inbox ideas, including custom
phrase rules, multiple categories, child precedence, confirmed examples, matching
coverage, and optional sentence embeddings. Late matches preserve manual choices,
including Uncategorized. Confirmation and original event periods remain intact.
Read [native/docs/calendar-categorization.md](native/docs/calendar-categorization.md).

PR #8: https://github.com/trimngo/canal/pull/8. The earlier calendar source
`45ebc04540888a726861d5960f2fcd97cde888e0` passed all focused calendar checks,
and every calendar regression passed in full iPhone runs. Full run `40743216270`
was delayed by cold setup/timeouts and explicit GitHub macOS ARM capacity. Its
final attempt had three green phone shards (102 tests), one phone review-action
failure (32 passed), and 16/18 Watch tests. Those partial results do not complete
the final release gate. Keep every assertion and run all 493 core, 135 phone UI,
and 18 Watch UI cases on the final candidate before merge and delivery.

The candidate also fixes the phone review Mark done/Reopen label's 18-point touch
area with a 44-point rectangular target. All five focused repetitions passed on
`b6fd443a54b445fbb9cb9104b1930aec69fd5c7d`, run `40773007096`, job
`123114890781`, alongside 493 core tests and both builds. The Watch test harness
clears a prior Dash notification only after its actual contents load, waits for
hittable controls, and preserves permission interactions. The one-tap Home timer
flow passed twice; the revised notification-isolation sequence passed all three
flows twice on `b24ae57f23a5da6b969fd3b8eb865892eef78759`, run `40777796685`,
job `123131483870`.
Six timer regressions passed on `cc49c55efbd8094c7bfa14364d8d3d9d9af4b147` in
run `40771490706`, job `123109984950`. No Watch production code changed.

Simulator validation compiles only the host architecture; archive settings stay
separate. All 25 local packaging/CI checks passed after that change. Read
[native/docs/ci-and-testflight.md](native/docs/ci-and-testflight.md) for the focused
notification and review workflows and the required full release checks.

Checkpoint, exact candidate identities, results, and backups:
`/workspace/work/calendar-categories-84/state.json`. Combined worktree:
`/workspace/canal-calendar-release`; isolated source worktrees:
`/workspace/canal-watch-recovery` and `/workspace/canal-inbox-recovery`.
Focused checks are green. Publish the combined candidate for the complete PR
checks; never cancel healthy checks to iterate.
Preserve original uncommitted files and index. Continue through processed and
internal TestFlight delivery under the user's standing authorization; build 83
remains latest until the new build actually completes. Planned build 84 must be
verified from the package and Apple processing, not assumed from the plan.

The separate iPhone crash remains open; the user already sent its TestFlight
report. Friend accountability sharing remains planning only. Keep existing work
active when discussing new ideas.

## Latest release: TestFlight 83 (2026-10-28)

Release objective **COMPLETE**: TestFlight **1.0 (83)** finished Apple processing
and was distributed internally at **2026-10-28 14:19:05 UTC**. Do not repeat this
upload. Keep the separate iPhone crash investigation below active. Preserve
uncommitted work and the original index before further changes.

- PR #7: https://github.com/trimngo/canal/pull/7 — merged as
  `1a5575d59bd0d319ce3cdcb225bb75bb291266ae`, the build 83 application source.
- Validated head `ee58c13bb5f7927a3a7db568346671ec683bb9b6` and merge share the
  complete tree `dbb83da845852d15e99c57debd89440d1362ffa0`. Native subtree:
  `32abc8dd43261ac69b9187987d047a42e02418c8`. This final root-only handoff
  update leaves app source unchanged and does not trigger another upload.
- Full CI: https://github.com/trimngo/canal/actions/runs/40645207614 — **SUCCESS**
  (attempt 3): **493 core, all 132 iPhone UI, and all 18 Watch UI tests**.
  UI coverage was compared with source: no missing or duplicated cases. The
  successful phone results were retained; final Watch job `122850086412` passed.
- Focused complication checks `40643861526`, job `122668016143`, passed all core
  tests and both app builds. All **25 local packaging/CI tests** passed.
  PR #6 was closed as covered; do not merge it separately. Its full run
  `40641800079` also passed 486 core, 132 phone UI, and 18 Watch UI cases.
- Delivery: https://github.com/trimngo/canal/actions/runs/40701754693 — **SUCCESS**,
  job `122863127982`. Actual packaged build **83** verified at 14:10:12 UTC;
  upload accepted at 14:10:53 UTC; processing and internal distribution both
  succeeded at **14:19:05 UTC**. Delivery also passed all 493 core tests and
  signed-package checks. Upload acceptance alone was not release proof.
- Initial Watch validation passed its 18 cases but reached the 35-minute step
  limit during result finalization. Retry `122841096893` never acquired a runner:
  GitHub annotations reported macOS ARM capacity constraints and an internal
  server error. The next Watch-only retry passed. No API rate-limit or billing
  error was observed. Delivery took about 19 minutes, including about eight
  minutes waiting for Apple's build listing/processing. Keep all full tests.

Implemented in build 83:

- Each existing check-in can show one unfinished urgent Inbox task, selected by
  deadline and elapsed appearance history. Preserve cadence, quick logging,
  and ordinary prompts when none qualify. Completed/snoozed tasks leave upcoming
  prompts. The Watch displays the same hint beside logging. Scheduling history
  does not prove a notification was read; OS background refresh is best effort.
  Reminders date/alert import and broader organizational ideas remain planning
  only. Ignore the accidental Watch trial-status reply. Read
  [native/docs/check-in-urgent-tasks.md](native/docs/check-in-urgent-tasks.md).
- Foreground refresh and timer-complication launch retry WidgetKit reload even
  when the shared snapshot is unchanged. Current-timer timelines request bounded
  recovery refreshes; waiting timers show Ready. Actual face refresh timing is
  controlled by WidgetKit and still needs hardware verification. No alarm owner
  or transport protocol changed. Read
  [native/docs/watch-complication-refresh.md](native/docs/watch-complication-refresh.md).

Update **both phone and Watch** to 83 and open Dash on each once. Check that an
urgent prompt still allows quick logging, and the Watch complication reflects
running/restarted timers and Ready waiting tasks. The separately reported iPhone
crash was not reproduced or fixed by this release.

Checkpoints: `/workspace/work/checkin-urgent-83/state.json` and
`/workspace/work/complication-refresh-84/state.json`. The latter name was
provisional: both features shipped in build 83. Isolated worktree:
`/workspace/canal-complication`. Original uncommitted copies were preserved and
updated only after target-file hash checks. The local original branch still
intentionally stays at its old HEAD with uncommitted copies of published work;
do not reset it or use its index to publish. Original index SHA-256 remains
`665903eef15410b31774c99b1869fe0e8ed8b7c92475752beb2a42d72343c6cf`.

## Active incident: iPhone crash after Watch restart (2026-10-28)

The user reported that iPhone crashed while restarting a timer on Apple Watch.
The timer originally alerted using the Watch mechanism, not phone AlarmKit.
Installed phone/Watch build numbers remain unverified; do not infer the cause
from unrelated reports or assume the phone-owned AlarmKit Stop path was used.

Apple diagnostics were most recently refreshed in run `40721752796`,
job `123124473273`, at 2026-10-28T21:54:37.0631636Z. Build 83 was independently confirmed
VALID and IN_BETA_TESTING; its upload was COMPLETE. Apple still listed three
submitted reports: two available logs from build 9 and one unavailable log (404). No current
matching crash was found. Read-only code review covered WatchConnectivity receive/
merge and reply paths, serialized ActivityKit refresh/background time, timer
notification scheduling, and optional alarm takeover; no reproducible fault or
established cause was found. No speculative crash fix was included in PR #7.
The user confirmed on 2026-10-28 that they sent this crash report through
TestFlight. Do not ask them to submit it again. Apple has not yet exposed a
matching current log through this API; a device .ips report can bypass that gap.
A separate diagnostic-only simulator branch `ci/crash-repro-watch-restart`
(head `37cbd5579bdb7937207c0bccdd706cefd2422f5c`) exercises real nonisolated
WatchConnectivity receive callbacks on a background queue, atomic commit/receipt,
ActivityKit update, duplicate/older contexts, repeated restart, and relaunch.
It uses a Watch-owned fixture with the phone alarm trial off. It bypasses radio
transport and cannot establish physical background wake, WatchKit expiry, or
optional AlarmKit handoff behavior. Focused run `40699031896`, job
`122853494797`, passed all 493 core tests,
both app builds, and its actual receipt/relaunch UI case (three restarts). It did
not reproduce the reported crash. It is not in the release merge. Checkpoint:
`/workspace/work/crash-restart-repro/state.json`; worktree `/workspace/canal-crash-repro`.
Keep this incident active after the completed release. The feedback
API may lag or omit automatically collected crashes; a matching current report
or reproduction is needed for a targeted fix.

## Previous release: TestFlight 82 (2026-10-27)

Release objective **COMPLETE**: TestFlight **1.0 (82)** finished Apple processing
and was distributed to internal testers at **2026-10-27 13:20:16 UTC**. Do not
repeat this upload. The user's requested settings are shipped; physical checks
of silent/repeating haptics and forwarded Watch Stop behavior remain below.
Preserve all local files and the original Git index before further work.

- PR #5: https://github.com/trimngo/canal/pull/5 — merged as
  `5b73e0d3fc7d1e91c7b2c5be0bc67fdc83255deb`, the build 82 app source.
- Validated head `0b766b67e802e0d54e3d4c39c86124d0ef7a474f` and merge have the
  identical tree `b9ad6079a88099d3498fb14bc5acbcb20752d117`. The native subtree is
  `bb07581a9ade33f7d4b8f0b1fb5bf555367f3c79`; later root handoff changes do not
  change application source or trigger another upload.
- Full CI: https://github.com/trimngo/canal/actions/runs/40503598254 — **SUCCESS**:
  **473 core, all 130 iPhone UI, and all 17 Watch UI tests**, on the first full
  attempt. Source coverage was checked with no missing or duplicated UI cases.
- Focused checks: `40500673769`, job `122177265755`, passed all 473 core tests,
  both app builds, and all six phone alarm flows. Apple's decoder confirmed the
  bundled CAF as mono PCM16, 44100 Hz, 0.5 seconds. Release validation checks
  that its audio samples are all zero and that the signed IPA includes it.
- Delivery: https://github.com/trimngo/canal/actions/runs/40509629042 — **SUCCESS**,
  job `122207796373`. Actual packaged build **82** verified at 13:16:39 UTC;
  Apple processing and internal distribution both succeeded at 13:20:16 UTC.
  Accepted upload alone was not used as release proof.
- Local and post-merge signing checks (`40509629011`, job `122207795660`) passed
  all **25 packaging/CI tests**. Full checks took about 44 minutes; delivery got
  a Mac immediately and finished in about 11 minutes, without a duplicate main
  UI run. Phone validation allows 55 minutes inside a 65-minute job; Watch UI
  allows 35 minutes inside a 45-minute job. Keep all full PR tests.

### Enable the new settings

On iPhone, open **Timers → Timer settings** with **iPhone system alarms (trial)**
enabled. Two additional switches are available; **both default off** and persist
in backups/settings sync:

- **Haptics only (trial)** requests silent audio for iPhone system alarms and
  their paired-Watch alerts. Dash uses the bundled `DashSilent.caf` through the
  supported custom-sound API, with the filename extension included. Apple exposes
  no direct haptic-only or custom mirrored-Watch vibration control. Test silence
  and repeating haptics on both physical devices before relying on it. Future
  alarms keep their existing deadline when sound changes; ringing alarms keep
  their original sound until Restart, and stopped alarms stay silenced.
  Watch-owned fallback alarms and notification backups keep existing sound rules.
- **Stop completes task** lets Stop on the expired phone-owned system alarm
  complete its matching queued task, including Stop on the forwarded Watch alert.
  Leave **Start next after Done** on to start the next task and schedule its
  AlarmKit alarm directly on iPhone without opening Dash on Watch. Turning
  auto-start off leaves the next task waiting. Hardware-button dismissals can
  also invoke Stop; the settings footer explains that. Early, repeated, stale,
  and Watch-owned callbacks cannot complete another task. Restart stays separate.

Read [native/docs/alarmkit-trial.md](native/docs/alarmkit-trial.md). Install the
update on phone and Watch, queue two one-minute timers, and check silence,
repeating haptics, Watch Stop advancing exactly once, Restart retaining the same
task, and phone/Mac Live Activity updates. Those physical behaviors cannot be
established by simulator checks. Basic Watch → phone handoff was already
confirmed by the user on build 81; no handoff protocol change was made in 82.
The earlier one-off observation remains unexplained. Existing inactive-Watch
and mid-timer disconnection limits still apply; do not claim perfect failover.

The separate recent crash remains unidentified. The repaired diagnostic check
last documented 3 feedback submissions: two available logs from build 9 and one
unavailable log. Do not attribute a current crash to build 9 or infer the missing
log's build. Friend accountability sharing remains planning only.

Detailed checkpoint: `/workspace/work/alarmkit-82/state.json`. Local uncommitted
copies of published work and the original index are intentionally preserved.
Original index SHA-256:
`665903eef15410b31774c99b1869fe0e8ed8b7c92475752beb2a42d72343c6cf`.

## Previous release: TestFlight 81 (2026-10-27)

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
needs physical verification of retained/repeating Watch haptics. The user chose both iPhone and Watch and requested a setting. The optional
feedback and Stop settings are now shipped in build 82 as documented above;
the basic handoff report itself did not require a fix.

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

- All 135 iPhone UI tests run across four shards. Keep the complete test set and
  meaningful assertions; do not skip failures to obtain a green run.
- Run Watch UI checks with `bash native/scripts/test-watch-ui.sh` on macOS.
  Run all 18 Watch UI tests. Repeating WatchKit haptics still require
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
checks: all 493 core, 135 iPhone UI, and 18 Watch UI tests must pass.

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

