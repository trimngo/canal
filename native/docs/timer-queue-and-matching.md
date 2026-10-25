# Timer queue and offline matching

## Timer queue

The first queued task starts immediately. Further tasks wait in creation order.
Expiry never advances the queue: Done & Next completes the current task and
starts the next; Restart repeats the original duration. Pause preserves the
remaining time. Timers do not create activity logs or alter Inbox rankings.

Timer settings includes **Start next after Done**, enabled by default. Turning
it off completes the current task without starting another; **Start next task**
then begins the oldest waiting task. Capturing another task during this wait
does not start the queue. This setting uses shared settings revisions/sync and
backups. Old files default to the previous automatic-next behavior.

On Watch, the **Timers** and **Current task** complications open the single-timer screen. The upper-right **+** opens dictation directly: “Practice guitar” creates a five-minute timer, while “Practice guitar for twenty minutes” uses that duration. Finishing dictation saves the task. Watch Home also has a direct Add timer action. The Watch saves and schedules locally, without needing the phone.

Siri registers the full-sentence phrases **Add a Dash timer to [task]** and **Add a Dash timer for [task]**. Try “Hey Siri, add a Dash timer to eat food” (five minutes), or “Hey Siri, add a Dash timer to cook food for ten minutes.” A string-query entity resolves the spoken task into a draft without saving during lookup; the intent saves only when it runs. This avoids the unsupported free-form String parameter in an App Shortcut phrase. Apple SDK metadata validation passes, but actual one-sentence Siri recognition still needs a physical Watch check. The older **Add a Dash timer**, **Add Dash timer**, **Add a timer to Dash**, and **Queue a timer in Dash** triggers remain available; when no task is supplied, Siri asks what the timer is for.

The iPhone has a dedicated **Timers** tab, with quick text entry, current countdown and progress, Pause/Resume, Restart, Done & Next, editing, and an upcoming queue. Log is accessible at the top of Today. Tap a timer title to edit its task and minutes; changing the current duration preserves elapsed time. Starting, restarting, resuming, or changing the running duration uses that device for alerts. Opening the screen alone leaves alert ownership unchanged. Device-to-device controls require delivery; a disconnected Watch keeps its locally scheduled timer until it receives the change. Watch smart alarms can only be armed while Dash is active on that Watch, so use the Watch's existing alert takeover control to move a phone timer back there.

Only upcoming timers can be reordered. Drag their rows on iPhone (Edit also exposes reorder handles); on Watch hold an upcoming row and drag it above or below another. The current timer stays fixed and its deadline does not change. Queue order has its own revision, travels through companion quick delivery, full sync, iCloud, and backups, and never overwrites concurrent timer text edits. New captures not yet present in a reordered snapshot remain queued. Old files without an order keep creation order.

Swipe down from the current timer to the separate queue page; swipe up to return. Only the first timer runs. Upcoming rows are dimmed and show their full duration. Swipe a row left to delete any timer. Deleting the current timer cancels its alarm and leaves the next task waiting for Start, independently of the Done & Next setting. Deleting an upcoming task leaves the running countdown untouched.

Repeating haptics use WatchKit's scheduled smart-alarm extended runtime session,
not a workout, audio loop, or Apple Timers integration. The active app displays
Done & Next and Restart directly. In the background, watchOS owns the alarm UI
and its Stop/Open buttons; they cannot be replaced by app actions. Stop silences
the alarm without completing the task. Open goes to the timer controls. The
system limits the alarm session to roughly 30 minutes. Haptic pattern and repeat
interval are under Timer queue → Timer settings. Sound follows Watch settings.
On supported Watches, double-tap is assigned to Restart while Dash's timer
screen is visible. Apple owns gestures on the background system alarm screen.

The iPhone mirrors received state through a Lock Screen Live Activity. Initial
creation requires opening the phone app; an existing activity updates across
task transitions. Sync and display updates depend on system delivery. Neither
phone availability nor the Live Activity is required for the Watch alarm.
The compact Live Activity includes a single-line task name beside the countdown; system-controlled compact widths can truncate long task names. The expanded view retains the complete task context.

Physical-device checks still needed:

1. Queue a one-minute task and a second task, turn the phone off, and lower the
   wrist. Verify repeating expiry haptics, Stop/Open, Restart, and Done & Next.
2. Reopen after the app leaves the foreground and verify the persisted deadline
   and queue. Check system cancellation/reboot behavior; do not assume a force
   quit or reboot preserves a scheduled system alarm.
3. Add both complications and verify the current task refreshes after queue changes.
4. Reconnect the phone, open Dash once, and verify Lock Screen updates, including
   expiry and advancing to the next task. Check actual Siri recognition separately
   from the simulator's synthetic dictation fixture.

## Inbox urgency and categories

Capture timing is independent of ranking, categories and snooze: **No date**,
**ASAP**, or an actual **Due date**. ASAP is not encoded as a fictitious date.
All active dated/ASAP items appear in Urgent, including unranked ideas. Dated
items sort by deadline; ASAP items sort oldest first. Completed, deleted,
reference and currently snoozed items are excluded. Ranking data stays intact.

Offline action phrases can suggest ASAP for replies/follow-ups, scheduling, and
payments. Suggestions show a reason in the item editor. Choosing No date in that editor clears the suggestion. Editing the text does not undo that choice. Choose Automatic timing in the editor to enable suggestions again.

Settings → Automatic matching exposes editable urgency phrases, category phrase
rules, a matching preview, and broader/cautious category matching. Built-in
urgency phrases recognize common wording variants; custom phrases match literal
whole words, ignoring capitalization, accents and punctuation.

Confirmed categories and corrections in logs and Inbox provide training examples.
Broader matching learns distinctive words from fewer examples and accepts weaker
unique semantic matches. OS-provided sentence embeddings are optional; phrase
rules and learned vocabulary still work if no embedding is available. Automatic
guesses do not train the model. Suggestions count toward totals and stay marked
for review. Existing confirmed assignments are never rewritten. Rules apply to
uncategorized/unassigned entries; existing suggestions can be corrected in review.

Timing, matching settings and phrase rules use existing capture/settings revisions,
cloud/companion synchronization and backups. Older files without these fields
continue to decode without resetting existing data.

## Watch layout

The current timer has its own page with large task text, countdown, progress, completion and restart controls, and an upper-right +. Pause/Resume sits beside the countdown. Swipe down opens native-style queue rows and timer settings; swipe up returns immediately. The Digital Crown scrolls long queues. The two timer screens switch directly within one navigation stack, so row drags do not compete with the Watch Home pager and no modal queue covers system input. The queue’s upper-left back button returns to Watch Home. Restart keeps the system double-tap shortcut while the app is open.

Timer settings offers Standard pulse, Attention pulse, and Light tap, a preview, and repeat intervals of 2, 3, 5, or 10 seconds. These existing Watch haptic choices apply to the system's repeating alarm. Sound follows system settings; Dash cannot install arbitrary alarm sounds or remap Apple's background alarm gestures.
