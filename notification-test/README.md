# Time Ledger — today

The active, owner-private app is hosted at
https://time-ledger.mistymint8.chatgpt.site. The `notification-test` directory name
is retained because it is the existing Sites source subtree.

## Use

Connect Google Calendar to see today's elapsed time, from midnight to the last
refresh, in the phone's timezone. Google is read directly using the existing
public OAuth client ID. Choose calendars with **Settings**; the initial selection
follows the calendars displayed in Google, including the primary calendar.
Future appointments do not appear. Ongoing events only account for elapsed time.

Tap a gap, describe the activity, optionally shorten the interval, and explicitly
save it to a writable Google Calendar. Google requests event-write permission on
the first save. Remaining portions stay as gaps. Overlaps count once. All-day
labels appear separately because they cannot establish hours spent. Cancelled
and self-declined events do not record time.

All selected calendars must load successfully before the app offers gaps. It
refreshes before each save to catch newly added events. Unconfirmed saves retain
their IDs and can be checked rather than creating another event. Recovery details
stay in session storage; calendar-selection preferences stay in device storage,
both scoped to the Google account. Tokens stay only in memory, so reconnect after
reopening or session expiry. Activities themselves are stored at Google.

Google Cloud must have Calendar API enabled, this HTTPS origin authorized, and
the account included as a test user if OAuth consent is in testing mode.
Google sign-in on the installed iPhone PWA still needs an on-device check; if the
popup fails, try the same app address in Safari.

Tap an event, then **Delete from Google Calendar**, and confirm to remove it from Google Calendar. Only
the displayed occurrence of a recurring event is removed. Read-only calendars
cannot be changed. The app rechecks permissions and the event version before
deletion, requests no guest updates, and checks uncertain deletions before
allowing another attempt. Uncovered time becomes a gap after refresh.

## Grid, time format, and categories

The elapsed day uses an hourly grid at 75 pixels per hour. Every interval's height
is proportional to its duration; overlap segments share the same time interval.
Short intervals retain their true height and can be hard to tap, so **Fill the
first gap** also opens the next missing interval. A local-noon line appears only
once noon is in the elapsed portion. Settings offers a persisted AM/PM display
preference. Native date/time input controls follow the phone's locale.

Tap an event, choose its category, and preview before confirming. Categories are
stored as a readable trailing description line, `Time Ledger category: Work`,
plus private metadata holding a stable category ID, name, and exact managed line.
Existing description text and unrelated private/shared metadata are preserved.
If the managed line was edited or moved externally, categorization is blocked.
Only description and private properties are patched; titles, times, recurrence,
and attendees are never submitted by category updates. No guest updates are
requested. Recurring masters are blocked; individual occurrences are supported.

Settings lets the user create and rename categories. Renaming queries calendars
for that exact stable ID, includes only past tagged events (up to 100 per review),
and lists every affected event with its original and proposed description. A
read-only tagged calendar or incomplete scan blocks the rename. Future events
are excluded. Category definitions are stored on the device; events carry their
own readable labels at Google.

Category updates save an account-scoped Undo journal to local storage **before**
any PATCH. A missing/failed backup blocks writes. Every PATCH uses the previewed
ETag with If-Match; conflicts stop the batch. Bulk updates run sequentially and
are not atomic. Confirmed changes remain reversible if another update fails.
Lost responses are checked against saved before/after states without replaying
PATCH requests. **Undo last category edit** first verifies all event versions and
states, then restores only their description and private category fields. Newer
external edits block Undo instead of being overwritten. Undo history is limited
to this device and can be downloaded from Settings; it is not a Google Calendar
backup and does not undo event deletion or creation.

## Notifications

The successful notification test remains at `/notifications`. The existing
manifest ID `/notification-test`, service-worker scope, VAPID keys, and private
audience are preserved. The installed icon may retain its old label. No production
timer or scheduled notification has been added.

The VAPID private key remains in Sites secret configuration. Immediate push
requests require the Sites authenticated identity and same-origin POST; push
endpoints are allowlisted. The bounded 15-second background test remains a demo,
not a durable scheduler for long timers.

## Development

Run `npm test`; it builds and runs 35 tests for time accounting, Google API
requests, simulated UI save/recovery flows, and the notification Worker. Fixtures
are synthetic, with no real Calendar writes or device pushes. Browser preview
is unverified because Chromium was blocked by the execution sandbox.

`npm run build` embeds `web/` into a dependency-free Worker at
`dist/server/index.js`. `worker/today-assets.mjs` is a generated, ignored adapter
for source Worker tests. The hosting manifest retains the existing project ID.
The broader earlier dashboard in `../time-ledger` is archived.
