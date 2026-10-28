# Urgent tasks in check-ins

Each existing check-in can show one unfinished urgent Inbox task below the
logging prompt. No additional alert, action, ranking step, or category selection
is introduced. With no eligible task, the ordinary check-in text is unchanged.
The phone notification and Watch custom notification both show the task title;
the existing Dictate log action still saves a log directly.

Eligibility uses the same explicit ASAP/due dates and offline urgency suggestions
as Today. Uncategorized and unranked captures are eligible. Completed, deleted,
reference, and currently snoozed captures are excluded. Snoozed captures become
eligible at their existing return time. Reminders date/alert import and expanded
phrase recognition are separate proposals, not part of this change.

## Selection and history

Unseen eligible tasks get a turn first, ordered by deadline (dated before ASAP),
then capture age and ID for deterministic ties. Afterwards, elapsed time since
the last appearance is weighted 3x for overdue tasks, 2x for deadlines within
24 hours, and 1x for other tasks. This gives deadlines more attention while
allowing older items to return. Consecutive repeats are excluded when another
task is available. One eligible task can appear at every check-in.

History is local to the device scheduling check-ins and survives app relaunch.
Future assignments are stored separately from elapsed appearances. Rebuilding
a queue never marks its future tasks as already seen. History uses elapsed
scheduled notification times, not proof of delivery, reading, or task progress.
Daily and hourly repeating slots are reconciled using calendar arithmetic,
including daylight-saving changes. Mirrored phone notifications carry the same
task to Watch; switching the scheduling device uses that device's local history.

## Preserve delivery behavior

Regular check-ins retain their existing repeating clock schedule, including
hourly slots for all-day intervals. Randomized/frequent-window queues retain
their existing absolute times and IDs when content changes or the queue refills.
Notification count, sound, quiet hours, delivery choice, and reply actions stay
the same. Timer alerts and the separate delivery-test notification are untouched.

Task edits/merges refresh pending content through the existing save observer.
Foreground/background refresh and logs refresh assignments too; routine saves
are throttled to once a minute when task content has not changed. Background
execution is best effort. While Dash cannot run, local notifications use their
already assigned text, and repeating slots retain their assigned rotation.
Already delivered notifications cannot be rewritten by editing a task.

## Verification

Core regressions cover eligibility, deadlines, fair rotation, future snooze,
cancelled/future assignments, relaunch, and hourly/daily history across DST.
Phone UI checks inspect real UNNotificationCenter requests, including task
payload, unchanged reply action, repeating/queued triggers, stable times,
completion removal, and relaunch. The inspector and fixture are DEBUG-only and
require explicit UI-test arguments. Watch UI covers the actual prompt view with
task text and quick saving; real system notification dictation retains the
existing implementation and requires a physical-device check.

Use `ci/checkin-*` for the focused phone checks and both app builds. These never
replace full PR validation: all 486 core, 132 phone UI, and 18 Watch UI cases.
