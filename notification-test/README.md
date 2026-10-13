# PWA notification test

This minimal iPhone-first test replaces the first deployment scope. The Calendar
implementation remains in `../time-ledger` and is paused.

## Test on an iPhone

1. Open the published private URL in Safari and sign in to ChatGPT if prompted.
2. Share → Add to Home Screen. Open Notify Test from the Home Screen.
3. Enable notifications and allow them in the iPhone permission prompt.
4. Send test now. Check Notification Center.
5. Send in 15 seconds and lock the phone. A server-originated Web Push should
   wake the service worker and display the notification.

Notification permission and push-service acceptance do not prove device display.
Check Focus and notification settings if a notification does not appear.

## Implementation

- Single dependency-free Worker, installable manifest, PNG icon, service worker.
- VAPID keypair is stored in Sites runtime configuration. The private key is a
  secret and is absent from source, client code, and build artifacts.
- No Calendar reads or writes are needed. No subscription is persisted server-side.
- Immediate sends require an authenticated visitor and a same-origin explicit
  POST. Push endpoints are restricted to supported browser push services.
- Empty Web Push messages trigger a visible notification in the service worker.
- The 15-second test uses a bounded Worker background task. Long production
  focus timers will require a durable scheduler; this does not implement one.
- The app remains owner-private through Sites access controls.

Run `npm test` and `npm run build`. No package installation is required.
The tests use synthetic subscriptions and mocked push services; they never send
notifications to real devices. Actual iPhone delivery must be checked on-device.
