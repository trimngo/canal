# Time Allocation Planner MVP

The dashboard compares the current long-term percentage budget with today and a rolling seven-calendar-day window. A positive deviation is not graded as success. Categories without targets still appear. Target remainder and actual Uncategorized time are separate.

## Accounting

- Parent totals include direct assignments plus all descendants. Top-level totals form a partition; parent and child totals must not be summed together.
- Multi-category observations divide their inferred duration equally. Parent/descendant combinations are rejected, with an explicit replacement prompt in the shared phone/Watch selector.
- Midpoint or carry-forward transitions operate between instantaneous samples. Estimates start at the first log (per the subsequent product decision), and the last activity extends to bedtime. Time before the first log is excluded from both actual time and the percentage denominator; no activity is invented. Today stops at now or bedtime. A day without observations inside its waking period has insufficient data and contributes neither numerator nor denominator to the seven-day result.
- Waking dates label the day on which waking begins, including overnight periods. The reporting time zone is pinned on first launch and can be changed explicitly in Settings. Wall-clock boundaries use Foundation calendar arithmetic, with the first occurrence of repeated DST times and the next valid time for nonexistent times. Durations use actual elapsed seconds. Adjacent periods are capped at the next wake-up to prevent overlap.
- Observations outside the configured waking period remain in the raw log/history list. They do not invent waking activities; adjust that date’s schedule to include them.

## Persistence and compatibility

Existing schema 1/2 JSON decodes without rewriting sample IDs, timestamps, activity text, inbox items or revisions. New optional fields retain the legacy single-category field as a compatibility mirror. Existing confirmed single-category logs behave as one-element selections; automatic assignments remain unconfirmed suggestions. All changes use the existing atomic commit, Lamport merge, Watch file transfer and backup paths.

Targets are append-only snapshots with effective instants, IDs and revisions. The dashboard uses the current snapshot; older intentions remain in backups/sync. Moving a targeted category under a parent, or deleting it, creates a new current snapshot removing that target, without redistributing the others. Deleted category shares retain their original references and appear as Uncategorized; children are promoted and raw logs remain. A move that would invalidate an existing multi-category selection is rejected. Concurrent offline cycles are resolved deterministically for display/accounting without rewriting user revisions; conflicting old selections prefer the most specific category once.

Date overrides use revisioned reset tombstones. Whole-ledger Watch sync and backups include all added data; optional CloudKit also has per-record budget/override payloads. Update the paired phone and Watch together before editing the new fields.

## Device verification

Core tests cover accounting, hierarchy conflicts, target independence/history, DST/overnight schedules, weighted seven-day coverage, migrations, backups and deterministic merging. Simulator checks build both platforms and exercise phone editing. Physical devices are still required to verify actual notification/dictation delivery, Siri recognition, WatchConnectivity delivery while offline, and iCloud Drive/optional CloudKit behavior with real accounts. No new permissions or progress notifications are introduced.
