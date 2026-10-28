# CI iteration and TestFlight delivery

PRs run **Native Apple checks**: 486 core tests, all 132 iPhone UI tests across
four shards, and all 18 Watch UI tests. The sharding unit test reads the actual
workflow matrix and checks that every iPhone case appears exactly once.
Native source changes must go through a PR with the full checks green. The
release merge must contain the validated native source. Main does not repeat
the full UI suite: build 80's redundant main checks occupied all five Mac slots
and queued delivery for about 32 minutes. TestFlight still validates core and
builds both apps before its signed archive. Manual full checks remain available.
Feature branch pushes do not duplicate the PR workflow.

## AlarmKit trial checks

Use `ci/alarmkit-sdk` for core/packaging and both app builds. Use
`ci/alarmkit-ui` for six focused iPhone trial flows: schedule/restart/persist,
API failure fallback, default Stop without task completion, permission denial,
saved haptics-only preference, and opted-in Stop completion/automatic next.
These use a DEBUG mock at the system API boundary; production never uses it.
Real Watch forwarding, buttons, and repeating haptics need physical testing.
Focused checks never replace all 132 iPhone and 18 Watch tests before release.
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
Verify the packaged build number and both successful processing and internal
distribution in the delivery log. Build 79's delivery took about 36 minutes;
that is separate from the preceding CI validation.

Delivery does not cancel an in-flight upload/processing wait when another main
commit arrives. If processing times out after upload, check the existing build
before starting another upload. Keep the release objective active until the new
build is actually processed and available.

## Urgent check-in checks

Read [check-in-urgent-tasks.md](check-in-urgent-tasks.md). Push `ci/checkin-*`
for all core tests, both simulator builds, and the two focused phone checks of
real scheduled content, completion removal, stable dates, and relaunch. The
Watch prompt regression runs in the complete PR Watch suite. Keep every full
release check; focused success alone never authorizes a release.
