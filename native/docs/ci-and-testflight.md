# CI iteration and TestFlight delivery

PRs run **Native Apple checks**: 501 core tests, all 138 iPhone UI tests across
four shards, and all 18 Watch UI tests. The sharding unit test reads the actual
workflow matrix and checks that every iPhone case appears exactly once.
Phone shards use recorded passing test durations, placing expensive cases on
different workers while keeping their case counts within one. New tests receive
the median known cost and still run; timing entries for removed tests are ignored.
Refresh `native/scripts/ui-test-durations.json` from a complete passing run when
the suite changes materially. Timings estimate work; they cannot guarantee runner
speed. The preceding full run had 25–29 minutes of UI work on three phone workers
and 38 minutes on the fourth, despite almost equal case counts.
Native source changes must go through a PR with the full checks green. The
release merge must contain the validated native source. Main does not repeat
the full UI suite: build 80's redundant main checks occupied all five Mac slots
and queued delivery for about 32 minutes. TestFlight still validates core and
builds both apps before its signed archive. Manual full checks remain available.
Feature branch pushes do not duplicate the PR workflow.
The always-present **Native validation** gate selects the complete suite for
native code, resources, build configuration, tests, or validation workflow changes.
Documentation-only and root handoff edits pass through two small Ubuntu jobs;
their Mac jobs are skipped. Routing failures fail the gate. Manual dispatch
always runs all Apple checks. A rename/removal is checked using both paths.

Simulator builds and UI test bundles use the Mac runner's architecture through
`ARCHS` and `ONLY_ACTIVE_ARCH`. Generic simulator destinations otherwise compile
both arm64 and x86_64 even though tests execute on one host. These arguments stay
inside the simulator scripts; signed archives retain their own build settings.

## AlarmKit trial checks

Use `ci/alarmkit-sdk` for core/packaging and both app builds. Use
`ci/alarmkit-ui` for six focused iPhone trial flows: schedule/restart/persist,
API failure fallback, default Stop without task completion, permission denial,
saved haptics-only preference, and opted-in Stop completion/automatic next.
These use a DEBUG mock at the system API boundary; production never uses it.
Real Watch forwarding, buttons, and repeating haptics need physical testing.
Focused checks never replace all 138 iPhone and 18 Watch tests before release.
The full Watch step has 35 minutes within its 45-minute job; a cold 17-minute
setup plus the full UI suite exceeded the previous 30-minute step budget.
Phone validation has 55 minutes within a 65-minute job: build 81 needed up to
about 49 minutes including cold setup and 32 UI cases; retain margin for the
additional preference/Stop regressions. Every case is still required.

## Iterate on Watch without restarting phone validation

Use an isolated branch named `ci/watch-<description>` for a Watch fix. Push the
candidate code there before updating the feature PR. **Native Watch UI checks**
runs six focused regressions covering full titles, single-swipe navigation,
dictation, three visible rows, scrolling, return navigation, deletion, and native
reordering. Its concurrency group is independent of the feature PR's full run.
There is no need to open a PR for this temporary check branch.

On macOS, the same script accepts explicit Xcode test selectors:

```sh
bash native/scripts/test-watch-ui.sh \
  -only-testing:TimeLedgerWatchUITests/WatchQuickLogUITests/testUpcomingRowsCanBeDraggedWithoutMovingCurrentOrNavigatingAway
```

The Watch workflow also supports manual dispatch with a `focus` checkbox. The
full workflow calls it with `focus: false`, so every Watch test still runs for
release. Focused success is diagnostic evidence, not a release gate. After the
fix passes focused checks, bring it onto the feature PR and complete its full
iPhone and Watch checks before merging. Let healthy full runs finish rather
than repeatedly cancelling them while trying small Watch changes.

## Why the previous process was slow

The completed run 40362837457 took about an hour. It scheduled six phone shards
plus Watch while observed Mac concurrency was about five jobs. Some shards
waited for a runner, then repeated cold simulator startup. Every new feature
push cancelled that full run and began again, and both push and PR events
created workflow runs for the same commit.

Four phone shards plus Watch fit that observed concurrency. Recorded timings
for 124 cases total about 102 minutes of serial UI work; partitioning those
timings into four shards gives roughly 21–30 minutes of UI work per shard.
This is an estimate, not a runtime promise. Simulator boot now starts before
compilation, with `bootstatus` still awaited before installation or testing.

Cancelled runs retain raw logs and skip expensive result exports. Completed
runs retain compact screenshots and summaries; failures additionally retain
the full simulator apps and result bundle. Do not export an interrupted bundle
or treat its secondary export error as the original failure.

## Release completion

Merging native changes to `main` starts **Native TestFlight delivery**. It
archives and checks the signed IPA, uploads it, waits for Apple processing, and
distributes to internal testers. An accepted upload is not the end of delivery.
Main pushes containing only tests, documentation, or validation scripts do not
upload another copy of the app. Application source, resources, package/build
settings, and signing-lane changes remain eligible. Workflow-only edits can be
checked without an upload; use manual dispatch for an intentional rebuild.
Verify the packaged build number and both successful processing and internal
distribution in the delivery log. Build 79's delivery took about 36 minutes;
that is separate from the preceding CI validation.

Delivery does not cancel an in-flight upload/processing wait when another main
commit arrives. If processing times out after upload, check the existing build
before starting another upload. Keep the release objective active until the new
build is actually processed and available.

## Automatic handoff

At the 2026-10-29 inspection, repository auto-merge was disabled and `main` was
unprotected. CI success therefore did not merge a PR or start delivery. The
connected GitHub tools can enable auto-merge per PR, but cannot change repository
admin settings. An owner can require **Native validation** for `main`, require
the branch to be current, and enable Allow auto-merge in repository settings:

- https://github.com/trimngo/canal/settings/branches
- https://github.com/trimngo/canal/settings#pull-requests

Use the single gate as the required check: documentation PRs still produce it,
and code PRs cannot pass it unless the complete phone and Watch jobs succeed.
After those settings are configured, enable auto-merge only for a concrete PR
whose merge/release is authorized. Keep active monitoring until then. These
pipeline changes preserve every application release test and installed feature.

## Urgent check-in checks

Read [check-in-urgent-tasks.md](check-in-urgent-tasks.md). Push `ci/checkin-*`
for all core tests, both simulator builds, and the two focused phone checks of
real scheduled content, completion removal, stable dates, and relaunch. The
Watch prompt regression runs in the complete PR Watch suite. Keep every full
release check; focused success alone never authorizes a release.

## Complication refresh checks

Use `ci/complication-*` for all 501 core tests, packaging checks, and both app
builds. Read [watch-complication-refresh.md](watch-complication-refresh.md).
These checks do not replace all 135 phone and 18 Watch UI cases before release.
WidgetKit face refresh timing still needs a physical Watch check.

## Calendar categorization checks

Push `ci/calendar-*` for all 501 core tests, both app builds, and the three new
calendar category regressions plus existing calendar period/goal accounting.
These exercise the real shared matcher, including a DEBUG-only async delay that
checks manual choices against late results. Read [calendar-categorization.md](calendar-categorization.md).
Full release checks still require every one of the 135 phone and 18 Watch UI cases.

## Notification and review-control recovery checks

Push `ci/notification-ui-*` to repeat the Watch automatic-delivery, Cancel/no-log,
and one-tap Home timer-input flows twice. This is separate from the six timer
regressions, so notification-test iteration does not restart a healthy full run.
Carousel can expose a notification before its Dash/Dismiss contents exist and
can deliver it after the preceding test ends. The UI harness waits for that
specific notification and clears it before input; its interruption handler also
catches a later arrival. Permission prompts retain their explicit test actions.
Wait for a hittable Watch control before its first tap on a cold simulator.

On iPhone, notification permission dismissal does not finish the asynchronous
Save operation. Wait until Save is enabled again before inspecting the resulting
schedule, and reveal the status row in the lazy Form before reading it. Keep the
queued/repeating/off assertions and the unchanged-queue refill assertion. A status
timeout alone cannot establish an app scheduling fault; capture the actual status
and save state on failure.

The phone reveal helper recognizes hittable navigation/tab-bar controls without
scrolling the page beneath them. Such controls sit outside the body viewport;
body scrolling cannot improve their visibility. When a lazy row is absent, the
backward search covers the forward travel plus rows preceding the starting
position. A symmetric forward/back count can finish near its starting point and
miss an earlier Settings row. Keep destination and persistence assertions.

The `ci/inbox-review-regression` branch repeats the phone category-review flow
five times with core tests and both builds. Keep its exact next-item, notes,
delete/undo, and persistence assertions. Review's Mark done/Reopen label has a
44-point rectangular touch target; use a hittable semantic tap and record the
actual review position and hierarchy if advancement fails. Focused checks never
replace all 135 phone and 18 Watch tests on the final release candidate.
