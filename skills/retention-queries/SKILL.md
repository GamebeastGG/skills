---
name: retention-queries
description: "Full reference for ad-hoc retention queries: start and return events, retention window and group (day-N / week-N), look-back vs look-ahead, displays (series, curve, single number), filters, breakdowns, and how to read the results. Load to build, read, or explain a retention spec."
---

# Retention queries

A **retention query** answers "of the players who did a start event, how many came back and did a return event N days (weeks, months) later?". The `run_retention_query` tool executes a spec; `create_retention_query` saves the same spec to a dashboard (see the manage-dashboards skill).

## Spec shape

<!-- example:retention-spec -->
```json
{
  "time": { "step": "day", "relative": { "step": "day", "value": 30 } },
  "metrics": [
    { "id": "r1", "visible": true, "data": { "name": "session_start", "type": "event" }, "display": { "name": "First session" } },
    { "id": "r2", "visible": true, "data": { "name": "session_start", "type": "event" }, "display": { "name": "Returned" } }
  ],
  "retentionCriteria": {
    "measurement": "retention_rate",
    "retentionWindow": "day",
    "retentionGroup": 1
  },
  "display": "line"
}
```

`metrics` is exactly two events; `retentionCriteria` and `display` are required. `filters`, `breakdowns`, and `breakdownOptions` are optional.

## metrics — start and return events

- `metrics[0]` — the **start event** that puts a player into a cohort bucket (e.g. `session_start`, `tutorial_complete`).
- `metrics[1]` — the **return event** that counts them as retained. Often the same event as the start ("came back and played again").
- Both need `display.name`. `data.name` must exactly match an event from `list_event_types`.
- `data.filter` narrows either event: `{ "operation": "and", "conditions": [ …filters… ] }`. Use it only for a condition that should limit one of the two events; a condition for both belongs in the global `filters`. For new-player retention, use a global **New User** filter (it applies to the start event only — see [Filters and breakdowns](#filters-and-breakdowns)), not one on each event:

<!-- example:filter -->
```json
{ "data": { "name": "New User", "type": "user", "dataType": "user", "condition": { "boolean": true } } }
```

## retentionCriteria

Strict: only the fields below are accepted.

| Field | Values | Meaning |
|---|---|---|
| `measurement` | `retention_rate` / `unique_users` | plot the percent retained, or the retained player count |
| `retentionWindow` | `day` / `week` / `month` | the unit of "N later" |
| `retentionGroup` | integer 1–30 | N: which window after the start counts as retained. `1` + `day` = day-1 retention; `7` + `day` = day-7; `4` + `week` = week-4 |
| `computeMode` | `look_back` (default) / `look_ahead` | see below |

<!-- example:retention-criteria -->
```json
{ "measurement": "unique_users", "retentionWindow": "week", "retentionGroup": 1, "computeMode": "look_ahead" }
```

- **look_back** (default): each time bucket shows how many of the players who started N windows earlier came back **in that bucket**. Good for "how is day-1 retention trending?".
- **look_ahead**: each bucket is the cohort that **started** in it, measured N windows forward. The most recent buckets have not had time to return yet and read low — say so.

Retention is always measured "on" day N (the player returned in that exact window).

## display

| display | Shape | Use for |
|---|---|---|
| `line` | a time series of retention per bucket | "is day-1 retention improving?" |
| `retention_curve` | one value per bucket number 0…N across the window (day 0, day 1, day 2, …) | "what does our retention curve look like?" — `retentionGroup` is ignored; the number of buckets comes from the time range |
| `metric` | a single number for the whole window (per breakdown value when broken down) | "what is our day-7 retention?" |

## time

**Default window: when the user does NOT specify a time range, default to the last 30 days** — `{ "step": "day", "relative": { "step": "day", "value": 30 } }`. For week or month windows, widen it so it holds several windows (e.g. 12 weeks for week-4 retention). `relative.offset` and `relative.truncate` do not shift the window — use an absolute range for calendar periods.

## Filters and breakdowns

Global `filters` use the same shapes as insight filters (string, number, boolean, date, cohort, experiment, deeplink, array — see the insight-queries skill). A global New User / First Occurrence filter applies to the start event only (the exception to the scope rules below); to constrain the return event, put it in `metrics[1].data.filter`. A property or argument filter or breakdown must be on both events (see [Filter and breakdown scope](#filter-and-breakdown-scope)).

`breakdowns` split the start cohort by a low-cardinality dimension (platform, country, experiment group, New User). `breakdownOptions.levels[i].limit` caps the values kept; the rest are grouped into "Other <breakdown>".

<!-- example:breakdown -->
```json
{ "data": { "name": "platform", "type": "property", "dataType": "string" } }
```

By experiment group (always `"dataType": "number"`):

<!-- example:breakdown -->
```json
{ "data": { "name": "Summer Pricing", "type": "experiment", "dataType": "number",
            "experiment": { "version": "v2", "level": "group", "experimentId": 42 } } }
```

<!-- shared:query-scope -->
## Filter and breakdown scope

Global `filters` and `breakdowns` apply to the whole query: every metric, funnel step, or retention event (unless this skill notes an exception). A per-metric `data.filter` applies to that one metric only. Decide the scope before you build the spec:

- **A global filter or breakdown needs a column that every event metric shares.** A property or argument used globally must exist on the event of *every* event metric in the query, with the same `dataType`. If even one metric's event lacks it, or has it with a different `dataType`, the query is invalid. Check every metric's event in `list_event_types` before going global. Always safe: the `defaultProperties` (every event carries them) and `user`, `cohort`, `experiment`, and `deeplink` columns. Formula and stats metrics don't count.
- **Prefer global filters; fall back to per-metric ones.** When a condition should apply to every metric, put it in `filters` once, and nowhere else. Never repeat a global condition in each metric's `data.filter` as well: the copy is redundant and drifts when one side is edited. Use a per-metric filter only when the condition should limit some metrics and not others, or when its column is not on every metric's event.
- **Breakdowns have no per-metric form.** When the dimension isn't on every metric's event, break down by one that is, run a separate query per event, or leave out the metric that lacks it. Don't add a breakdown that some metrics can't honour.
- **New User and First Occurrence follow the same rule.** New User keeps only events from each player's first-ever session; First Occurrence keeps only each player's first occurrence of that event. Apply one once, at the scope the question needs: globally when the whole question is about new players, on one metric when only that metric should be limited. Never both. Before you run, check it matches the question: neither means "players who joined recently, across all their sessions". For that, use a cohort.
- **Segment players by behavior with a cohort.** When the question is about players defined by what they did ("players who bought the starter pack", "players who reached level 10", "spenders vs non-spenders", "players who churned"), use a cohort. Look for a saved one with `list_cohorts`. If none fits, build the definition (see the `cohorts` skill) and save it (see the `manage-cohorts` skill; in the Gamebeast assistant the user can also save it from the cohort card). Then filter by it (`Is in` / `Is not in`) or break down by it. Don't approximate a player segment with event filters, extra metrics, or formulas: an event filter limits which events count, not which players. A cohort filter or breakdown takes a saved cohort's id.
<!-- /shared:query-scope -->

## Reading results

- `line`: `series[]` of `{ time, value: { all_users, retained_users, retention_rate } }` (plus `breakdowns`).
- `retention_curve`: `series[]` of `{ bucket_number, value: { cohort_size, retained_users, retention_rate } }`.
- `metric`: `series.total` (or `series.breakdowns`) of `{ all_users, retained_users, retention_rate }`.
- `retention_rate` is already a percentage (0–100).

<!-- shared:after-adhoc-chart -->
## After you show a chart

When you show the user a new ad-hoc chart, end your reply with one short offer to take it further: adjust it (a different time range, a filter, a breakdown, or a segment such as new players), or save it so it stays current, on an existing dashboard or a new one. If you have the create tool for its query type, offer to save it yourself (see the manage-dashboards skill) and save only once the user agrees. If you don't, point to the chart's **Add to dashboard** action in the Gamebeast assistant. Skip the offer when the chart is one step in a bigger answer, and leave it to the caller when you are building the chart for another agent.
<!-- /shared:after-adhoc-chart -->

## Common errors

- Not exactly two metrics.
- `retentionGroup: "all"` or a value outside 1–30 — use a concrete N.
- `retentionWindow` of hour/quarter/year — use day, week, or month.
- `intervalType` — not accepted; retention is measured "on" day N.
- Unknown event name — re-check with `list_event_types`.
- A property or argument filter or breakdown that only one of the two events has — see [Filter and breakdown scope](#filter-and-breakdown-scope).
