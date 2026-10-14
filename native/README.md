# Time Ledger for iPhone and Apple Watch

Native SwiftUI apps, with no Google Calendar connection and no notification server.
Supports iOS 17+ and watchOS 10+. Source is on `main`; the existing
website is separate and remains available.

## First version

- Every 15 minutes during a configurable same-day window; default 7:15 AM–10 PM.
  Each answered prompt covers the preceding 15 minutes. Missed prompts stay unlogged.
- Categorize immediately or later, edit a previous answer, and rename categories
  without touching any external calendar.
- Daily minutes and percentages use a fixed 1,440-minute denominator. Unlogged
  time includes future intervals today; DST transition days have 23 or 25 real hours.
- iPhone inbox for thoughts/tasks, completion and reopening. Captures do not count
  as time spent. Timed task reminders are a later feature.
- Watch: dictate check-ins and captures, choose a category, view today's breakdown.
- Siri/Shortcuts: “Capture in Time Ledger,” then answer Siri's text prompt.
- Atomic local storage, JSON backup export, deterministic merge of device edits,
  paired-device file transfers, and optional private CloudKit synchronization.

## What is operational before Apple enrollment

`Native Apple checks` builds both simulator apps and runs domain and iPhone UI
tests on a GitHub macOS runner whenever the native feature branch changes.
Unsigned simulator artifacts cannot be installed on an iPhone or Watch.

`Native TestFlight delivery` is prepared but intentionally disabled until the
repository variable `APPLE_SIGNING_READY` is `true` and signing is configured.
Never put Apple credentials, signing files, or personal log exports in this public
repository. Secrets belong in GitHub's `apple-testflight` environment.

## One-time setup, entirely from a browser

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/)
   with your own Apple Account. Membership costs US$99/year or local pricing.
   Complete Apple's agreements and identity verification.
2. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/),
   register these explicit App IDs: `com.trimngo.TimeLedger` and
   `com.trimngo.TimeLedger.watchkitapp`. Enable iCloud/CloudKit for both and attach
   `iCloud.com.trimngo.TimeLedger`. If those identifiers are unavailable, change
   them together in `project.yml` and `fastlane/Fastfile` before signing.
3. In [App Store Connect](https://appstoreconnect.apple.com/), create the iOS app
   record for `com.trimngo.TimeLedger`. Create a **team API key** with the Admin
   role for certificate/profile setup (individual keys cannot manage provisioning).
   The developer account owner must authorize API access. Download its `.p8` file
   once; store it securely. Reduce access later if your provisioning workflow permits.
4. Create the GitHub environment `apple-testflight`. Add the following secrets;
   values are never committed or pasted into chat. Paste the `.p8` file contents exactly, including its BEGIN/END lines.

   | Environment secret | Value |
   | --- | --- |
   | `APP_STORE_CONNECT_KEY_ID` | API key ID |
   | `APP_STORE_CONNECT_ISSUER_ID` | Team API issuer ID |
   | `APP_STORE_CONNECT_KEY_P8` | Full text of the downloaded `.p8` file |
   | `APPLE_DISTRIBUTION_P12_PASSWORD` | Random password, at least 32 characters |
   | `APPLE_DISTRIBUTION_P12_BASE64` | Existing encrypted signing bundle, or output of step 5 |

5. If you don't have a signing certificate/private key, run **One-time Apple
   signing setup** in GitHub Actions after merging the native workflow to the
   default branch. Select `create_certificate`. It creates one certificate and
   produces a password-encrypted signing bundle, without a local Mac. Download
   the artifact, copy `APPLE_DISTRIBUTION_P12_BASE64.txt` into the secret with that
   name, and delete the artifact. Avoid repeated runs: Apple limits active
   certificates. This workflow never revokes existing certificates.
6. The workflow defaults to Apple Team ID `M3ZCVUVHFT`; the optional repository
   variable `APPLE_TEAM_ID` can override it. Set repository variable
   `APPLE_SIGNING_READY=true` when registration and signing are complete.
   Leave `LEDGER_CLOUD_ENABLED=NO` until step 7 is done.
   Run **Native TestFlight delivery**. It validates both apps, downloads/creates
   provisioning profiles, signs them with your certificate, and uploads the build.
   Add yourself as an internal tester and install it through TestFlight on your
   iPhone and paired Watch. Device identifiers and a USB connection are unnecessary.
7. To activate iCloud, use [CloudKit Console](https://icloud.developer.apple.com/):
   create a `LedgerItem` record type with a `payload` Bytes field, add a QUERYABLE
   index for `recordName`, and deploy the schema to Production. Set repository
   variables `LEDGER_CLOUD_ENABLED=YES` and, if changed,
   `LEDGER_CLOUD_CONTAINER=iCloud.com.trimngo.TimeLedger`. Publish another build.
   TestFlight uses the production CloudKit environment. Use the same iCloud
   account on your phone and Watch; private data uses your iCloud storage quota.

For subsequent updates, change code in GitHub and merge to `main`. The delivery
workflow uploads a new build automatically. Enable automatic updates in
TestFlight or tap Update. Apple still processes uploads; installation is not
instant. TestFlight builds expire after 90 days. Public App Store distribution is
separate and requires review. GitHub runner billing depends on repository type
and plan; standard hosted runners for this public repository are generally free.

## Local or cloud Mac validation

Install Xcode 26.3 and XcodeGen, then:

```sh
bash native/scripts/validate.sh
LEDGER_UI_TESTS=1 bash native/scripts/validate.sh
```

Projects and Info.plists are generated from `project.yml`. Shared business rules
live in `Core`; shared app services live in `Shared`. Both platforms use the same
data format. No account/server credentials are needed for simulator validation.

## Notification and synchronization behavior to verify on your devices

The iPhone schedules up to 60 repeating daily calendar notifications, leaving
capacity for the test alert and future features. Apple can silence notifications
with Focus, Scheduled Summary, or device settings. Watch forwarding follows
Apple's usual routing: a notification may appear on your Watch instead of your
phone. The Watch does not schedule a second set of check-ins. The first version
requires the paired iPhone to deliver check-in prompts; Watch entries themselves
can be saved offline and transferred when the connection returns.

Cloud sync is opportunistic on launch and after changes. Local data is saved
first. Concurrent edits to the same answer resolve deterministically by revision;
separate captures are preserved. Received data is merged instead of replacing
the entire local ledger. Schema/read errors preserve the original local file and
prevent overwriting it. The app currently has no destructive bulk delete operation.

Before relying on it, test locked-phone alerts, Watch forwarding, Siri capture
on both devices, offline Watch capture/reconnection, cloud recovery, timezone
changes, and editing a late notification. Those require real devices and Apple
signing; simulator builds alone do not verify them.
