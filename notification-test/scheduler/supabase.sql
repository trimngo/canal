-- Configure this only in a user-selected Supabase project.
-- Secrets belong in Supabase Vault, not this file:
--   time_ledger_site_access: the current supported owner-private Site access token
--   time_ledger_scheduler_token: the CHECKIN_SCHEDULER_TOKEN runtime secret
-- Check existing cron.job rows first; update an existing matching job instead
-- of creating duplicate reminders. The app enforces timezone, hours, pause,
-- already-answered slots, and per-device idempotency.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
SELECT cron.schedule(
  'time-ledger-checkins',
  '*/15 * * * *',
  $job$
  SELECT net.http_post(
    url := 'https://time-ledger.mistymint8.chatgpt.site/api/checkins/tick',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'OAI-Sites-Authorization', 'Bearer ' ||
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'time_ledger_site_access'),
      'X-Checkin-Scheduler-Token',
        (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'time_ledger_scheduler_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 10000
  );
  $job$
);
