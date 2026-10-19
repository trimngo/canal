# Time Allocation Planner MVP

The dashboard compares the current long-term percentage budget with today and a rolling seven-calendar-day window. A positive deviation is not graded as success. Categories without targets still appear. Target remainder and actual Uncategorized time are separate.

## Accounting

- Parent totals include direct assignments plus all descendants. Top-level totals form a partition; parent and child totals must not be summed together.
- Multi-category observations divide their inferred duration equally. Parent/descendant combinations are rejected, with an explicit replacement prompt in the shared phone/Watch selector.
- Midpoint or carry-forward transitions operate between instantaneous samples. Each local calendar day starts at its first log and extends to now for today or the next midnight for completed days. Every log is eligible, regardless of its clock time. Empty days contribute neither numerator nor denominator; there are no sleep/wake windows or schedule overrides.
- The reporting time zone is pinned on first launch and can be changed explicitly in Settings. Calendar day boundaries preserve DST (23/24/25-hour days); durations use actual elapsed seconds. Raw observation timestamps are never rewritten.
- Legacy sleep/wake settings and overrides are ignored on import. Existing private-cloud schedule records are skipped; all logs, categories, targets, commitments, and inbox data continue to merge normally.

## Persistence and compatibility

Existing schema 1/2 JSON decodes without rewriting sample IDs, timestamps, activity text, inbox items or revisions. New optional fields retain the legacy single-category field as a compatibility mirror. Existing confirmed single-category logs behave as one-element selections; automatic assignments remain unconfirmed suggestions. All changes use the existing atomic commit, Lamport merge, Watch file transfer and backup paths.

Targets are append-only snapshots with effective instants, IDs and revisions. The dashboard uses the current snapshot; older intentions remain in backups/sync. Moving a targeted category under a parent, or deleting it, creates a new current snapshot removing that target, without redistributing the others. Deleted category shares retain their original references and appear as Uncategorized; children are promoted and raw logs remain. A move that would invalidate an existing multi-category selection is rejected. Concurrent offline cycles are resolved deterministically for display/accounting without rewriting user revisions; conflicting old selections prefer the most specific category once.

Whole-ledger Watch sync and backups preserve logs, categories, target budgets, commitments and inbox data. Optional CloudKit retains per-record budget payloads. Deprecated schedule payloads are ignored. The reporting time zone retains its existing wire key for compatibility with older Watch versions.

## Device verification

Core tests cover accounting, hierarchy conflicts, target independence/history, DST/calendar boundaries, weighted seven-day coverage, migrations, backups and deterministic merging. Simulator checks build both platforms and exercise phone editing. Physical devices are still required to verify actual notification/dictation delivery, Siri recognition, WatchConnectivity delivery while offline, and iCloud Drive/optional CloudKit behavior with real accounts. No new permissions or progress notifications are introduced.
