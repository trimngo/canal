# Time Ledger — 15-minute check-ins

Active owner-private app: https://time-ledger.mistymint8.chatgpt.site
The existing `notification-test` source subtree and PWA manifest identity are
retained. The former Google Calendar implementation remains archived in `web/`
and `../time-ledger`; the new front page makes no Calendar requests.

## Behavior

- A check-in records one completed, preceding 15-minute interval.
- Answers can be saved without a category, categorized later, and edited with
  optimistic version checks. Duplicate retries do not create another interval.
- Missed prompts remain unlogged; later responses never stretch over missed time.
- Categories have stable IDs. Renaming a category updates displayed names across
  all entries while preserving the original answers and timestamps.
- Today/history Log and Breakdown views use a 1,440-minute denominator. The
  uncategorized and not-yet-logged portions stay visible. Percentages are sample
  estimates. DST day bounds use the configured timezone; the denominator follows
  the user's explicit full-24-hour rule.
- Notification defaults: 7 AM–10 PM, first at 7:15 AM, last at 10 PM. Hours,
  pause, AM/PM format, and timezone are persisted server-side. Saving settings
  takes the current phone timezone. Sleep Focus is controlled by iOS.

## Storage and identity

Six D1 tables use the stable Sites authenticated user ID to isolate account data.
API writes require authenticated identity, same-origin JSON, valid categories,
and completed intervals. SQL uses bound parameters. Activity/version updates
are conditional. Categories are shared by reference rather than copied into
individual entries. Neither Google OAuth nor a Calendar write occurs.

The tracked schema is `db/schema.ts`; `npm run db:generate` generated the first
migration and Drizzle metadata. Builds copy migrations into
`dist/.openai/drizzle/`. The hosted `DB` binding is declared in the retained
`.openai/hosting.json`. Migration SQL is schema-only; user defaults are initialized
through the application's normal account setup. Hosted migrations are applied
by Sites before Worker upload.

## Notifications and the remaining scheduler connection

The original VAPID keypair, manifest ID `/notification-test`, and `/sw.js` scope
are preserved. The page registers the existing push subscription with its signed-in
account; it is persisted in D1. An empty Web Push wakes the service worker, which
reads that device's last prompted interval and shows a visible notification.
Tapping it opens that exact interval, including delayed or earlier-day prompts.
A generic visible prompt is the fallback for offline/expired-auth delivery.

`POST /api/checkins/tick` is an unattended writer. It requires owner-private Sites
service access AND a separate secret `X-Checkin-Scheduler-Token` header. Tokens
are stored only in supported runtime/secret configuration, never source or client
bundles. The handler filters local active hours and answered periods, claims a
unique device/slot key before sending, and never blindly retries an unknown push
result. Expired subscriptions are disabled. Runtime heartbeat allows the UI to
report a stale scheduler. A native Worker scheduled handler calls the same writer
if a hosting environment supports a Cron Trigger.

Automatic delivery remains disabled until a 15-minute scheduler is connected and
verified. `CHECKIN_SCHEDULER_ENABLED=0` makes this explicit in the app. Native
ChatGPT/Sites cloud tasks support at most hourly cadence and are not used as a
15-minute replacement. The suggested Supabase plugin is not assumed connected.
The free Supabase project can run the cron job in `scheduler/supabase.sql` using
pg_cron + pg_net and Vault secrets. Free projects may pause after a week of
inactivity; the app's stale heartbeat should reflect stalled delivery. A project
and plugin connection require the user. No paid plan is provisioned.

After connecting the user-selected project: verify identity/access, inspect
existing cron jobs, configure Vault credentials securely, exercise the intended
HTTP writer and read the persisted heartbeat, schedule the existing job at
`*/15 * * * *`, verify the saved job and result, then enable the Sites runtime flag
and deploy the current saved source version. No credentials belong in job text.
Do not create a duplicate schedule or claim reminder delivery until verified.

Manual check-ins and explicit push tests work independently of recurring setup.
`/notifications` retains the older bounded 15-second push test; this is not a
production timer or scheduler.

## Development

Run `npm test` for the active API, SQLite persistence, schedule, UI, and push tests.
Tests use synthetic users, answers, subscriptions, and mocked push transport.
No real Calendar writes or real user check-ins are used as fixtures. Actual iPhone
layout/sign-in and background delivery require on-device verification.

`npm run build` embeds the page, assets, service worker, shared domain code, and
D1 backend into the dependency-free `dist/server/index.js` Worker. Drizzle is a
build-time development dependency. Generated `worker/today-assets.mjs` is ignored.
The completed log can be exported by the owner from app Settings.
