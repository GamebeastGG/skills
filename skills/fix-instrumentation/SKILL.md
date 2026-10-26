---
name: fix-instrumentation
description: "Playbook for auditing and fixing event data: events that stopped, properties with drifting types, high-cardinality traps, undocumented or noisy events, and tracking-plan mismatches. Load when the user asks why an event looks wrong, whether their data is trustworthy, or to fix what a tracking plan flagged."
---

# Fix instrumentation

An approach, not a script. If the user pointed at specific events or a tracking-plan mismatch,
work on exactly those; run the full audit only when they ask for one.

The outcome to aim for: the events the studio relies on are present, typed consistently,
documented, and free of noise. You find the problems; whoever can edit the code fixes them.

1. **Find the problems.** `list_event_types` (with `pendingEventTypes`), and `get_tracking_plan`
   when a plan exists: its `mismatch` items carry a note on what's wrong. For a full audit, take
   the 15 most-sent events plus anything the studio's dashboards use (`list_dashboards` with
   `includeQueries`) and check:
   - **Silent events**: `lastSeen` more than 3 days ago while other events still flow.
   - **Type drift**: a property seen with more than one data type.
   - **Cardinality traps**: a breakdown property with thousands of values (ids, timestamps).
     Check with `get_property_values`.
   - **Undocumented events**: no description.
   - **Missing defaults**: default markers the platform SDK should send but doesn't (check
     `search_docs` for the platform's default markers).
   - **Pending events**: events a plan describes that never arrived.
2. **Rank by what breaks.** Dashboards and experiments first, then everything else. Say which
   chart or experiment each problem affects.
3. **Fix what you can, hand off the rest.**
   - Documentation: one `describe_event_types` call for descriptions, and for hiding obvious
     debug events (load `manage-events`).
   - Code fixes: if you can't edit the code, put them in `create_tracking_plan`, one item per
     event, with a placement hint that says what's wrong ("`price` is sent as a string — send a
     number"), and point the user to **Implement with…** on the plan card.
   - If you can edit the code, fix each item, call `update_tracking_plan_items`, run the project
     where you can, and re-verify with `get_property_values`.
4. Report what is clean now and what is still waiting on data.
