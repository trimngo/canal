# Time Ledger for iPhone and Apple Watch

Native SwiftUI apps, with no Google Calendar connection and no notification server.
Supports iOS 17+ and watchOS 10+. Source is on `main`; the existing
website is separate and remains available.

## First version

- Log an instantaneous sample anytime, or respond to prompts every 15 minutes
  during a configurable same-day window; default 7 AM–10 PM. A response records
  what is happening at its saved timestamp, not a fixed 15-minute interval.
- Today shows the time breakdown first, then an inline logging form. There are no
  tabs or Summary/Calendar selector. Calendar has its own navigation button;
  Inbox and Settings remain accessible through More.
- Offline phrase matching and previous confirmations suggest groups. Every new
  log stays Uncategorized until the user accepts a suggestion or chooses a group.
  Suggestions are visible during logging and review. Explicit batch confirmation
  can group matching pending descriptions; other confirmed choices stay intact.
- Tap the Uncategorized queue to confirm a suggestion, choose an existing group,
  or create one. Groups can be renamed from Today or Settings. Device-local Undo
  covers the latest categorization, including batch confirmations.
- Earlier automatic assignments return to Uncategorized with suggestions;
  explicit choices, original descriptions, and timestamps are preserved. The
  original local file is backed up before this migration.
- Estimate daily time with midpoint interpolation (default) or carry-forward.
  Midpoint puts activity changes halfway between observations. Percentages cover
  the first log until now today, and the first to last log on closed days. There
  is no Unestimated row or assumed overnight extension. Zero-duration samples
  remain accessible for categorization without producing invalid percentages.
- Preserve raw timestamps, activities, and categories when changing estimation
  methods. Upgrade schema-1 logs with a local backup before writing schema 2.
- iPhone inbox for thoughts/tasks, completion and reopening. Captures do not count
  as time spent. Timed task reminders are a later feature.
- Watch notifications focus on input. Tap Dictate log, finish system text input,
  and the sample saves immediately, shows a checkmark, plays a success haptic,
  and dismisses. No category or summary blocks the reply. watchOS controls its
  keyboard/dictation chooser, so exact hardware tap counts need device testing.
  Notification text-reply actions also save directly; ordinary taps open logging.
- Siri notes: try “Create a note in Ledger called try shorter lessons.” The
  built-in note intent carries title/body together, saves to the local inbox
  with a timestamp, and syncs with the paired device. Nothing counts as time
  spent. The existing Capture a thought App Shortcut remains available.
  Siri recognition and invocation on a physical Watch still need device testing;
  the native simulator checks cannot prove single-utterance voice recognition.
- The Watch Siri extension writes individual thoughts to a shared Keychain queue.
  The app imports them atomically, preserves IDs/timestamps, then removes the
  queued copies. Replaying after a crash cannot duplicate or reopen a thought.
  Existing ledger files and backups are not moved into shared storage.
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

## One-time setup

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
   | `APPLE_DISTRIBUTION_P12_BASE64` | Encrypted signing bundle, copied from your Mac in step 5 |

5. Create the signing identity on your Mac using the [manual instructions
   below](#manual-signing-on-your-mac). Paste the encrypted bundle directly into
   the `APPLE_DISTRIBUTION_P12_BASE64` environment secret. No additional GitHub
   token is needed and no signing file is published as an artifact. The cloud
   certificate generator is disabled; **Apple signing setup guide** only shows
   instructions and has no access to secrets. If you already have a suitable
   distribution identity with its private key, export that instead of creating
   another certificate.
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

TestFlight signing runs only on `main`. For an additional GitHub-side
restriction, open Settings → Environments → `apple-testflight` → Deployment
branches and tags, select only branch `main`, and do not allow tags. This account
setting must be configured by the repository owner; workflow checks alone do
not replace it. Keep write access to this repository limited to people you trust,
because a person who can change trusted signing code can change how it uses
credentials. Making the repository public does not expose GitHub secret values.

`Signing security checks` verifies that the setup guide has no credentials or
exports, that cloud certificate creation is disabled, and that TestFlight signing
is restricted to `main`. It uses no Apple credentials and creates no certificate.

## Manual signing on your Mac

This is a one-time setup. Subsequent cloud builds reuse the saved identity until
its certificate expires (normally after one year) or is revoked. Your Mac does
not need to stay on and you do not need to plug in your phone for builds.

1. Open **Keychain Access** on your Mac. In its menu choose **Certificate
   Assistant → Request a Certificate From a Certificate Authority**. Enter your
   email address and a common name such as `Time Ledger Signing`; select
   **Saved to disk**. Save the certificate signing request (`.certSigningRequest`).
   Its matching private key remains in your Mac's keychain.
2. Open [Apple Certificates](https://developer.apple.com/account/resources/certificates/list),
   press **+**, select **Apple Distribution**, and upload that signing request.
   Download the issued `.cer` file. In Keychain Access select the local **login**
   keychain (unlock it if needed), choose **File → Import Items**, select the
   `.cer`, and explicitly choose **login** as the destination keychain before
   importing. Click **Options** if the destination selector is hidden. This avoids
   Finder's double-click import defaulting to an unsuitable keychain. Error
   `-25294` means the destination keychain cannot be found; retry with the local
   `login` destination before creating another certificate. See [Apple's guidance
   on this error](https://developer.apple.com/forums/thread/675290).
   Do not choose Developer ID, which is for a different distribution path.
3. In Keychain Access → **My Certificates**, find the new **Apple Distribution**
   identity. Expand it and verify there is a private key underneath. Select the
   identity and use **File → Export Items** to export a `.p12` file. Save it as
   `TimeLedgerSigning.p12` in Downloads. Set its export password to the same
   password you already stored in `APPLE_DISTRIBUTION_P12_PASSWORD`.
4. In your Mac's Terminal run the following. It copies the encoded encrypted
   bundle to the clipboard without printing it:

   ```sh
   base64 < "$HOME/Downloads/TimeLedgerSigning.p12" | tr -d '\n' | pbcopy
   ```

5. Open [the GitHub environment settings](https://github.com/trimngo/canal/settings/environments),
   select `apple-testflight`, add secret `APPLE_DISTRIBUTION_P12_BASE64`, paste,
   and save. Do not paste it into chat or commit it as a source file. Keep a secure
   backup of the identity and its password, and clear the clipboard after saving.

Base64 is only an encoding. The `.p12` export password provides encryption;
GitHub additionally protects the secret in its storage. GitHub does not provide
an API to read a saved secret's value. The trusted TestFlight build runner must
receive signing secrets to sign an app, but the assistant does not need their
values or permission to manage them. Anyone able to modify trusted build code
could change how credentials are used, so limit repository write access.

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

The iPhone schedules up to 61 repeating daily calendar notifications, leaving
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

## Crash diagnostics

TestFlight already collects crash reports for Apple. `Native crash diagnostics`
checks submitted TestFlight crash feedback hourly, using the existing Apple API
key inside the GitHub environment. It emits only fixed allowlisted exception and
component indicators. Raw reports, tester metadata, comments, and activity text
are never printed or uploaded as artifacts. This feedback API may not expose all
automatically collected Apple crash reports, and new reports may be delayed.
