# Time Ledger — today

The active, owner-private app is hosted at
https://time-ledger.mistymint8.chatgpt.site. The `notification-test` directory name
is retained because it is the existing Sites source subtree.

## Use

Connect Google Calendar to see today's elapsed time, from midnight to the last
refresh, in the phone's timezone. Google is read directly using the existing
public OAuth client ID. Choose calendars with **Calendars**; the initial selection
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

Tap **Delete** on an event and confirm to remove it from Google Calendar. Only
the displayed occurrence of a recurring event is removed. Read-only calendars
cannot be changed. The app rechecks permissions and the event version before
deletion, requests no guest updates, and checks uncertain deletions before
allowing another attempt. Uncovered time becomes a gap after refresh.

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

Run `npm test`; it builds and runs 27 tests for time accounting, Google API
requests, simulated UI save/recovery flows, and the notification Worker. Fixtures
are synthetic, with no real Calendar writes or device pushes. Browser preview
is unverified because Chromium was blocked by the execution sandbox.

`npm run build` embeds `web/` into a dependency-free Worker at
`dist/server/index.js`. `worker/today-assets.mjs` is a generated, ignored adapter
for source Worker tests. The hosting manifest retains the existing project ID.
The broader earlier dashboard in `../time-ledger` is archived.
