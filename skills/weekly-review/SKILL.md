---
name: weekly-review
description: "Playbook for a two-minute weekly review: what moved in the last 7 days and why, how running experiments are doing, what players are saying, and the one or two things to do next, saved to a dashboard so next week starts from the same view. Load when the user asks for a weekly review, a status summary, or how the project is doing."
---

# Weekly review

An approach, not a script. Aim for a review a studio lead can read in two minutes: what moved,
why, and what to do next. Shorten it when the user asked a narrower question ("how did last week
go for retention?").

1. **Pick the metrics from the data**; don't ask for them. `list_event_types` and
   `list_dashboards` show what the project actually uses. Sensible defaults:
   - Daily active players, and new vs returning (session or login events).
   - Day-1 and day-7 retention.
   - Revenue and paying players, if there are purchase events.
   - The most-sent non-default event (usually the core loop).
   Compare the last 7 days with the 7 days before, in the project timezone, and say so.
2. Build and run the specs. For any metric that moved more than 10%, break it down by platform,
   country, and new vs returning to find where the change came from.
3. **Experiments**: `list_experiments` for running ones and `get_experiment_results` for each.
   Flag any that are significant, any with a sample-ratio mismatch, and any running more than 21
   days with no verdict.
4. **Players**: if a Community Pulse source exists (`list_sentiment_sources`), pull this week's
   top rising topic with `get_community_pulse`.
5. **Write the review**: a two-sentence summary; "What moved", each item with its cause;
   "Experiments"; "Players are saying" (when there's a source); "Do next", at most 2 concrete
   actions.
6. Offer to save the charts to a "Weekly review" dashboard (load `manage-dashboards`), updating
   the existing board instead of creating a duplicate.
