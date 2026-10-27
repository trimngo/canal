# Phone system alarm trial

This opt-in trial adds AlarmKit on physical iPhones running iOS 26 or later.
Enable **Timers → Timer settings → iPhone system alarms (trial)** on iPhone,
and grant the system alarm permission. Existing installations stay on their
previous alert behavior until enabled. Older iPhones keep notification alerts.

Phone-owned timers then use a fixed AlarmKit alarm with the task title, Stop,
and a custom Restart action. Stop silences the alert; it never completes a task
or advances the queue. Done & Next stays in Dash. A scheduling/permission failure
leaves the ordinary one-time notification fallback. The app displays which
path succeeded instead of equating connectivity with a scheduled alarm.
Watch haptic presets apply to Watch-owned alarms; forwarded iPhone system alarms
use Apple's alarm feedback and need a physical check for repeating behavior.

The existing ActivityKit countdown remains the shared iPhone/Mac display. The
AlarmKit alert does not request a second countdown Live Activity. Mac forwarding
still depends on Apple's mirroring delivery and a powered-on iPhone. An offline
Watch continues locally; other devices receive changed state when sync resumes.

## Starting on Watch

The Watch first saves the task and arms its existing local alarm. With the trial
enabled, a foreground start/restart/resume or Done & Next offers the current
timer to the phone. Timers with less than 15 seconds left stay local, allowing
time for the handover. Merely opening the app never changes alert ownership.

The phone merges the bounded timer snapshot, prepares a candidate without
publishing ownership, and schedules its actual AlarmKit alarm. It then probes
the Watch again: Dash must still be active, the timer token must still match,
and any scheduled Watch alarm must have a cancellable session handle. The offer also has a unique request ID and a ten-second expiry; readiness must
match the still-pending Watch request. Late replies cannot authorize a new
handover. The phone also rejects any intervening ledger change. Only then does it atomically commit
the phone destination and return the confirmed timer. The Watch cancels its old
alarm when applying that state while active. Failed scheduling/readiness leaves
the original Watch control and alarm in place; staged phone alarms are cancelled.

The Watch timer options show the outcome. **Use Watch for alerts** takes over
locally and preserves the deadline. This explicit choice lasts for that task,
including its restarts; a subsequent queued task can try automatic selection.
**Use iPhone system alarm** retries a confirmed transfer while Dash is open.

This is automatic selection during user actions, not guaranteed background
failover. WatchKit cannot arm/cancel its scheduled session while Dash is inactive.
A later disconnected phone therefore requires opening Dash on Watch and choosing
Watch alerts. A very late foreground transition after readiness confirmation can
leave the old Watch alarm pending and produce a second alert. Reopening reconciles
it. Do not claim perfect failover, exact mirroring latency, or no possible duplicate.

## Verification

Core regressions cover opt-in migration/sync, destination eligibility, retained
manual Watch choice, immutable deadlines/queue, stale/concurrent actions, and
foreground/session readiness. iPhone UI tests inject an alarm API boundary for
schedule/restart/persistence, explicit Stop without completion, permission denial,
and API failure fallback. The Watch UI test exercises manual takeover and failed
phone confirmation while keeping its task. Production ignores the DEBUG fixtures.

Simulator checks cannot validate physical haptics or Apple's forwarded Watch UI.
After installing the new TestFlight build on phone and Watch, test:

1. Enable the trial and start a one-minute phone timer. With the phone locked,
   inspect the Watch alert's task title and actual Stop/Restart buttons. Verify
   repeating alert behavior, Stop leaving the task open, and Restart using the
   full duration. Check the phone Live Activity and Mac mirror too.
2. Start on Watch with the phone available. Keep Dash open until timer options
   report phone confirmation. Verify deadline/queue stay unchanged and there is
   only the expected alarm. Repeat while lowering the wrist during preparation:
   a failed readiness probe should retain the Watch alarm.
3. Turn the phone off before starting on Watch. Verify a local repeating alarm
   and direct Watch Restart/Done, then reconnect and inspect shared state.
4. Confirm phone ownership, then disconnect the phone mid-timer. Open Watch and
   use Watch alerts. Verify the original deadline and local repeats; reconnect
   and verify eventual phone cancellation. Do not expect an inactive Watch to
   arm a new alarm automatically.
5. Repeat Stop/Restart/Done after expiry, quick successive edits, relaunch, and
   permission revocation. Old action tokens must never change a newer timer.

References: [AlarmKit](https://developer.apple.com/documentation/alarmkit),
[Apple's alarm sample](https://developer.apple.com/documentation/alarmkit/scheduling-an-alarm-with-alarmkit),
[Watch session lifecycle](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions),
and [Mac Live Activities](https://support.apple.com/120684).
