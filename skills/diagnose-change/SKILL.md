---
name: diagnose-change
description: "Playbook for investigating why a metric moved (or why events stopped): pin the change in time, localize it to a segment, check configuration edits and experiments around that date, and recommend a fix with evidence. Load when the user asks why something changed, dropped, spiked, or stopped."
---

# Diagnose a change

An approach, not a script. Treat it as an investigation, not a lookup, and start from the
change the user named. Only go looking for one when they ask what changed in general.

1. **Find the change.** If the user pointed at an event, query, or dashboard, start there.
   Otherwise compare the last 7 days with the 7 days before for active players, sessions, the
   project's most-sent non-default event, and revenue if there are purchase events, and pick the
   biggest unexplained move. Say which one you picked.
2. **Pin it down in time.** Run the metric daily over 28 days to find the day it changed. Is it
   a step change, a gradual drift, or a weekday pattern? A weekday pattern isn't an incident:
   say so and stop.
3. **Localize it.** Break it down by platform, country, game or place version (if tracked), and
   new vs returning players. Find the segment that accounts for most of the change. When the
   segment is defined by behavior (spenders, players past the tutorial, players in a given
   event), break down or filter by a cohort (`list_cohorts`, or build one with the `cohorts`
   skill) rather than by event filters. Use a funnel when the metric is a conversion.
4. **Find the cause.**
   - `list_configurations` and `get_configuration`: configuration edits near the change date.
   - `list_experiments`: experiments started or ramped near that date, then their results.
   - When events stopped entirely, check which event types stopped and whether they stopped
     together (an SDK or deploy problem) or one at a time (a code path that changed).
   - If a Community Pulse source exists, `query_sentiment` around the date.
5. **Recommend the fix, with evidence**: "Reverting `Shop.GemPrice` from 120 to 100 restores the
   conversion the change took away." If you can make the change, propose it with the matching
   write tool — a configuration revert with `update_configuration`, a bad experiment ramped down
   with `update_experiment_rollout`, or a holdout experiment when the cause is uncertain. Each
   goes through its own approval.
6. End with your confidence and what would confirm it.
