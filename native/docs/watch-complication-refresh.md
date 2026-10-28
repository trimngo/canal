# Watch timer complication refresh

A saved current-timer summary and WidgetKit's displayed timeline are separate
caches. Previously, a foreground refresh skipped `reloadTimelines` when the
shared Keychain summary was unchanged. An earlier reload could have been
deferred while an old timeline still contained its Finished entry. The timer
provider's `.never` policy offered no independent recovery request.

Foreground refresh now requests a current-timer timeline reload even when the
saved summary is already correct. Ordinary saves still request a reload only
when their timer snapshot changes. The running countdown and explicit expiry
entry are retained. The current-timer provider also requests recovery within
15 minutes while running and 30 minutes for other states; imminent expiry can
request an earlier refresh, with a one-minute minimum to avoid tight loops.
WidgetKit controls actual scheduling and can defer requests. The static Timers
launch complication retains its no-refresh timeline.

Waiting timers display Ready instead of Finished. Paused timers retain their
paused display, including when a stale deadline is also present. Snapshot
storage remains backwards compatible; no user data or timer ownership changes.

Seven core regressions cover Ready, paused precedence, restarting an expired
snapshot, finite recovery dates, and expiry boundaries. Focused
`ci/complication-*` checks run all 493 core tests, packaging checks, and both app
builds. Full 132 iPhone and 18 Watch UI cases remain required before release.
Physical verification must install the Watch update, run/restart a timer from
each device, and verify that opening Dash requests recovery of a stale face.
Simulator results do not establish watchOS face refresh timing.
