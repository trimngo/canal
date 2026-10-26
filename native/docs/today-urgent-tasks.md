# Today: time and urgent tasks

The Today screen shows the time-spent dashboard followed by urgent Inbox tasks
grouped by their existing categories. The default breakdown and task list share
one vertical scroll area. Long task names wrap completely.

Urgency uses the same `urgentCaptures(at:)` rules as Inbox: explicit ASAP and
dated items, plus enabled offline urgency suggestions. Completed, deleted,
reference, and currently snoozed tasks stay out. Choosing No date suppresses a
suggestion on both screens. Ranking is not required and is never changed here.

Groups follow category order and show full paths for nested categories. Tasks
with multiple categories appear under each assigned category, using the same
underlying capture. Completing one removes every occurrence. The heading counts
unique tasks. Tasks with no remaining category appear under Uncategorized.
Empty categories are omitted; an empty urgent list has an explicit empty state.

Tap a task to edit its existing Inbox details. Today never creates a duplicate
task, goal, or timer. These actions keep the normal persistence and sync behavior.

Review logs is a toolbar action and remains reachable while scrolling. Time
estimation help is in the info popover beside Where your time went. The separate
Categories toolbar button has been removed; category management remains in the
filter menu and Settings.
