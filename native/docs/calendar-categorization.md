# Calendar event categorization

Pending calendar events in Review logs use the same AutomaticCategories service
as normal logs and Inbox ideas: saved phrase rules, child-category precedence,
multiple matching categories, confirmed examples, the selected cautious/broader
setting, and optional on-device sentence embeddings. Matching stays offline.

Suggested categories and their reason appear in calendar review. The user still
confirms whether the event happened before its period counts. Edited titles are
matched again. Late results never replace a user's category choices, including
Uncategorized. Confirming the review saves those choices as manual confirmations,
so the background classifier cannot replace an explicitly empty selection.
Existing manually categorized logs keep their choices. No calendar record,
transport, or backup schema changes; original event times remain unchanged.

Push an isolated `ci/calendar-*` branch for all 493 core tests, both simulator
app builds, and four focused phone cases (three new regressions plus existing
calendar period/goal accounting). Full PR checks still require all 135 phone UI
and 18 Watch UI cases. See [ci-and-testflight.md](ci-and-testflight.md).
