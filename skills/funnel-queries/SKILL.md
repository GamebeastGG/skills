---
name: funnel-queries
description: "Full reference for ad-hoc funnel queries: steps, conversion window, measurement, step ordering, constant attributes, filters, breakdowns and breakdown limits, first-time/new-user filters. Load to build, read, or explain a funnel spec."
---

# Funnel queries

A **funnel query** measures how many players complete a sequence of events in order, within a conversion window. It produces a step-by-step conversion chart. The `run_funnel_query` tool executes a spec; `create_funnel_query` saves the same spec to a dashboard (see the manage-dashboards skill).

## Spec shape

<!-- example:funnel-spec -->
```json
{
  "time": { "step": "day", "relative": { "step": "day", "value": 30 } },
  "metrics": [
    { "id": "s1", "visible": true, "data": { "name": "session_start", "type": "event" }, "display": { "name": "Session start" } },
    { "id": "s2", "visible": true, "data": { "name": "shop_open", "type": "event" }, "display": { "name": "Opened shop" } },
    { "id": "s3", "visible": true, "data": { "name": "purchase", "type": "event" }, "display": { "name": "Purchased" } }
  ],
  "conversionCriteria": {
    "timeWindow": { "step": "day", "value": 1 },
    "measurement": { "type": "unique_users" },
    "strictOrder": false
  }
}
```

`metrics` requires 2–32 steps and `conversionCriteria` is required. `filters`, `breakdowns`, and `breakdownOptions` are optional.

## time

**Default window: when the user does NOT specify a time range, default to the last 30 days** — `{ "step": "day", "relative": { "step": "day", "value": 30 } }`.

- Relative: `{ "step": "day", "relative": { "step": "day", "value": 30 } }`. The top-level `step` is unused for funnels (they aggregate over the window); set it to "day".
- Absolute (exact dates or calendar-aligned periods): `{ "step": "day", "range": { "start": "2025-01-01 00:00:00", "end": "2025-01-31 23:59:59" } }`.
- `relative.offset` moves only the start of the window back (the end stays at now) and `relative.truncate` is not applied — use an absolute range for "previous period" or "this month".

## metrics (funnel steps)

Each step is one tracked event, in chronological order. **Always set `display.name`** — it labels the step.

- `data.name` must exactly match an event from `list_event_types` (case-sensitive). Its `defaultProperties` (device, country, …) apply to every event and can be used in any step filter or breakdown; each event's `properties` / `arguments` are its custom ones.
- `data.filter` (optional) scopes the step to a subset: `{ "operation": "and", "conditions": [ …filters… ] }`, same shapes as global filters. Use it only for a condition that should not apply to every step; otherwise use a global filter (see [Filter and breakdown scope](#filter-and-breakdown-scope)).
- `display.unit` is rarely needed (steps are counts). If you set it, use one of the insight-queries units (case-sensitive, singular: `"User"`, not `"users"`).

## conversionCriteria

Strict: only the fields below are accepted.

### timeWindow — required

`{ "step": "<unit>", "value": <positive integer> }` — a player must complete every step within this window of their first step. Units: minute, hour, day, week, month (30 days), quarter (90 days), year (365 days).

There is no same-session window: to approximate "within one session", use a short window such as `{ "step": "hour", "value": 1 }` and say that it is an approximation.

### measurement — required

What the chart plots for each step:

| type | Meaning |
|---|---|
| `conversion_rate` | % of the first step that reached this step. `conversionRateType`: `"uniques"` (unique players, default) or `"totals"` (event counts) |
| `unique_users` | unique players who reached each step |
| `total_conversions` | total conversions (a player can count more than once) |

Every result row carries all of these figures (`unique_users`, `total_conversions`, `unique_users_conversion_rate`, `total_conversion_rate`), so you can report any of them whichever measurement the chart shows. On a dashboard the funnel shows each step's conversion % whichever measurement you pick; `unique_users` is what the query builder writes and the safe default.

### strictOrder — required

- `false` (default, most common): only the step events are considered; other events between steps are ignored. Steps must still happen in order.
- `true`: **any** other event between two steps breaks the funnel. Use it only when the user asks for back-to-back steps.

Steps are always ordered. There is no "any order" funnel and no exclusion steps ("players who did not do X between steps"). For "did not do X", use a cohort filter instead (see the cohorts skill).

### constantAttributes — optional

Properties or arguments that must keep the same value on every step, e.g. the same item from view to purchase:

<!-- example:funnel-conversion-criteria -->
```json
{
  "timeWindow": { "step": "day", "value": 7 },
  "measurement": { "type": "unique_users" },
  "strictOrder": false,
  "constantAttributes": [{ "data": { "name": "itemId", "type": "argument", "dataType": "string" } }]
}
```

## Global filters

Applied to every step. Same shapes as insight filters (string, number, boolean, date, cohort, user, experiment, deeplink, array — see the insight-queries skill for every operation). A property or argument filter must be on every step's event (see [Filter and breakdown scope](#filter-and-breakdown-scope)).

<!-- example:filter -->
```json
{ "data": { "name": "platform", "type": "property", "dataType": "string",
            "condition": { "string": { "operation": "Is", "value": ["Mobile"] } } } }
```

**New User / First Occurrence** — first-session funnels:
<!-- example:filter -->
```json
{ "data": { "name": "New User", "type": "user", "dataType": "user", "condition": { "boolean": true } } }
```
- `"New User"`: true = player's first-ever session. `"First Occurrence"`: true = the player's first-ever occurrence of the event type.

**Experiment** — compare A/B groups (always `"version": "v2"`):
<!-- example:filter -->
```json
{ "data": { "name": "Summer Pricing", "type": "experiment", "dataType": "experiment",
            "experiment": { "version": "v2", "level": "group", "experimentId": 42 },
            "condition": { "experiment": { "operation": "In groups", "groupIds": [107] } } } }
```

## breakdowns

Splits every step by a dimension. Use LOW-cardinality dimensions (platform, country, version, experiment group) — never raw ids.

<!-- example:breakdown -->
```json
{ "data": { "name": "New User", "type": "user", "dataType": "boolean" } }
```

Experiment group breakdown (always `"dataType": "number"`): `{ "data": { "name": "Summer Pricing", "type": "experiment", "dataType": "number", "experiment": { "version": "v2", "level": "group", "experimentId": 42 } } }`.

### breakdownOptions

`levels` is parallel to `breakdowns`:

<!-- example:breakdown-options -->
```json
{ "levels": [{ "limit": 5, "limitOrder": "desc", "sortBy": "value", "sortOrder": "desc" }] }
```
- `limit` (1–1000) + `limitMetricId` (a step id) + `limitOrder` choose which values are kept; values past the limit are grouped into "Other <breakdown>".
- `sortBy` / `sortOrder` only order the kept values in the chart.

<!-- shared:query-scope -->
## Filter and breakdown scope

Global `filters` and `breakdowns` apply to the whole query: every metric, funnel step, or retention event (unless this skill notes an exception). A per-metric `data.filter` applies to that one metric only. Decide the scope before you build the spec:

- **A global filter or breakdown needs a column that every event metric shares.** A property or argument used globally must exist on the event of *every* event metric in the query, with the same `dataType`. If even one metric's event lacks it, or has it with a different `dataType`, the query is invalid. Check every metric's event in `list_event_types` before going global. Always safe: the `defaultProperties` (every event carries them) and `user`, `cohort`, `experiment`, and `deeplink` columns. Formula and stats metrics don't count.
- **Prefer global filters; fall back to per-metric ones.** When a condition should apply to every metric, put it in `filters` once, and nowhere else. Never repeat a global condition in each metric's `data.filter` as well: the copy is redundant and drifts when one side is edited. Use a per-metric filter only when the condition should limit some metrics and not others, or when its column is not on every metric's event.
- **Breakdowns have no per-metric form.** When the dimension isn't on every metric's event, break down by one that is, run a separate query per event, or leave out the metric that lacks it. Don't add a breakdown that some metrics can't honour.
- **New User and First Occurrence follow the same rule.** New User keeps only events from each player's first-ever session; First Occurrence keeps only each player's first occurrence of that event. Apply one once, at the scope the question needs: globally when the whole question is about new players, on one metric when only that metric should be limited. Never both. Before you run, check it matches the question: neither means "players who joined recently, across all their sessions". For that, use a cohort.
- **Segment players by behavior with a cohort.** When the question is about players defined by what they did ("players who bought the starter pack", "players who reached level 10", "spenders vs non-spenders", "players who churned"), use a cohort. Look for a saved one with `list_cohorts`. If none fits, build the definition (see the `cohorts` skill) and save it (see the `manage-cohorts` skill; in the Gamebeast assistant the user can also save it from the cohort card). Then filter by it (`Is in` / `Is not in`) or break down by it. Don't approximate a player segment with event filters, extra metrics, or formulas: an event filter limits which events count, not which players. A cohort filter or breakdown takes a saved cohort's id.
<!-- /shared:query-scope -->

<!-- shared:after-adhoc-chart -->
## After you show a chart

When you show the user a new ad-hoc chart, end your reply with one short offer to take it further: adjust it (a different time range, a filter, a breakdown, or a segment such as new players), or save it so it stays current, on an existing dashboard or a new one. If you have the create tool for its query type, offer to save it yourself (see the manage-dashboards skill) and save only once the user agrees. If you don't, point to the chart's **Add to dashboard** action in the Gamebeast assistant. Skip the offer when the chart is one step in a bigger answer, and leave it to the caller when you are building the chart for another agent.
<!-- /shared:after-adhoc-chart -->

## Common errors

- Missing `display.name` on a step.
- Fewer than 2 steps.
- Unknown event name — re-check with `list_event_types`.
- Global breakdown or filter on a property/argument that not every step's event has (with the same dataType) — see [Filter and breakdown scope](#filter-and-breakdown-scope).
- The same condition both globally and on every step's `data.filter` — keep only the global one.
- `timeWindow.step` of `session` or `second` — not supported; use minute or longer.
- `excludeEvents`, `anyOrder: true`, `time_to_convert`, `total_sessions` — not supported; the spec rejects them. (`anyOrder: false` is accepted and ignored — omit it.)
- Using `type: "direct"` for device/platform/country — these are properties or arguments; verify with `list_event_types`.
