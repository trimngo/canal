# Today's calendar plan preview

Dash previews the remaining timed events in the calendars selected under
Settings → Calendars. Today’s Breakdown and Pie combine recorded time with this
tentative plan. Pale segments identify planned time; the breakdown also uses
stripes. Each affected category shows its recorded and planned amounts. The
summary shows the planned share of the preview and opens the contributing events.

The existing offline AutomaticCategories actor matches event titles using the
same phrase rules, category hierarchy, confirmed examples, coverage setting and
optional on-device embeddings as logs, Inbox ideas and calendar review. An
unmatched event stays Uncategorized. Changes to rules/categories refresh the
preview, without changing existing recorded assignments.

Only the remainder of the current reporting day is included. An in-progress
event contributes from now onward; an overnight event stops at the day boundary.
The reporting time zone and DST determine that boundary. Canceled, declined,
free and all-day events are excluded from the plan. Shared-calendar copies of
one occurrence are counted once. Concurrent events share their overlap, and
multiple categories share their event's time. Parent/child conflicts prefer the
child. Unscheduled hours are not invented.

Forecast amounts remain transient and never create samples or goal progress.
Manual category corrections are saved in pending calendar records and included
in backups and existing sync. Trends, heatmap, day comparison and historical
ranges continue using recorded data. After an event ends, its forecast disappears
and the existing Review logs flow asks whether it happened; only confirmation
creates recorded time. A calendar event that was skipped or confirmed is not
reintroduced as a plan. No calendar content is modified.

Changing selected calendars or losing access clears the corresponding preview.
Actor results are generation-checked so an older classification cannot restore
removed events. Opening Dash, EventKit changes and the existing minute/background
refresh paths update events; background execution remains best effort.

## Correct an upcoming event

Tap an event in Rest of today, choose one or more categories, and tap Save.
Cancel leaves its categories unchanged. The choice belongs to that occurrence,
not every event with the same title. It updates the forecast immediately and
survives classification, refresh, rescheduling, and relaunch. Uncategorized is an
explicit choice; Use suggested categories returns to automatic matching.

Corrections do not confirm an event or change the source calendar. Future manual
records stay out of Review logs until they end. Review then starts with the saved
choice; you can adjust it again before confirming. Unknown/deleted choices remain
Uncategorized rather than silently reverting to a prediction.

## Validation

Eight core regressions cover clipping, overlapping and multi-category shares,
occurrence deduplication, parent rollups/missing categories, actual-data isolation,
explicit confirmation after expiry, reporting-zone/DST boundaries, and invalid
or empty periods. Three phone UI cases cover category matching and parent/child
display, planned pie selection versus recorded history/relaunch, source removal
and the absence of premature confirmations.

The DEBUG fixture uses the actual classifier and accounting code with a fake
selected-calendar source. It does not request access to a user's calendars.
Its real clock and fixed reporting zone keep the fixture away from midnight.
The signed Release application uses EventKit and the real clock.

Focused checks use the `ci/calendar-*` branch workflow. Full release validation
requires all 514 core tests, all 141 phone UI tests, and all 18 Watch UI tests.
The native pipeline improvements remain included: balanced complete phone shards,
the stable Native validation gate, and no automatic uploads for test/docs-only
commits. This feature changes application code and needs a new TestFlight build.
