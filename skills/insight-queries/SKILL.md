---
name: insight-queries
description: "Full reference for ad-hoc insight queries: spec format, metric types, aggregations, formulas, filters (incl. cohort, experiment, deeplink, array), breakdowns and breakdown limits, first-time/new-user filters, and per-metric value formatting (display.unit, compact, decimals). Load to build, read, or explain an insight spec, or before setting a metric's unit."
---

# Insight queries

An **insight query** is a time-series or aggregate chart built from one or more event metrics. You build a spec; the `run_insight_query` tool executes it against the event store. To keep it on a dashboard, save the same spec with `create_insight_query` (see the manage-dashboards skill).

## Spec shape

<!-- example:insight-spec -->
```json
{
  "time": { "step": "day", "relative": { "step": "day", "value": 30 } },
  "metrics": [
    {
      "visible": true,
      "id": "m1",
      "data": { "name": "purchase", "type": "event", "measurement": { "math": { "function": "count" } } },
      "display": { "name": "Purchases", "unit": "Event" }
    }
  ],
  "display": "line"
}
```

`metrics` requires 1–15 entries. `filters`, `breakdowns`, and `breakdownOptions` are optional.

## time

Two forms. Optional `timezone` defaults to the project's timezone; when set it must be a supported IANA name (e.g. `"America/New_York"`).

**Default window: when the user does NOT specify a time range, default to the last 30 days** — `{ "step": "day", "relative": { "step": "day", "value": 30 } }`. Only widen the window when the user explicitly asks for a longer period ("this year", "all-time", etc.).

Relative (rolling look-back from now):
```json
{ "step": "day", "relative": { "step": "day", "value": 30 } }
```
- Top-level `step` = bucket granularity: second, minute, hour, day, week, month, quarter, year.
- `relative.step` + `relative.value` = look-back window. `value` is a positive number, not a string.
- `relative.offset` moves only the **start** of the window further back; the end stays at now (midnight today for a `day` window). It does **not** produce "the previous period" — for a previous-period comparison use an absolute range.
- `relative.truncate` is accepted but not applied — never rely on it for calendar alignment.

Common mappings:
- "last month" (rolling) → `{ "step": "day", "relative": { "step": "month", "value": 1 } }`
- "last 7 days" → `{ "step": "day", "relative": { "step": "day", "value": 7 } }`

Absolute (exact dates, or calendar-aligned / to-date periods like "this month", "this quarter"):
```json
{ "step": "day", "range": { "start": "2025-01-01 00:00:00", "end": "2025-01-31 23:59:59" } }
```
- `YYYY-MM-DD HH:mm:ss` strings; omit `end` (or null) for "until now".
- Strings without an offset are wall-clock time in the query `timezone`. An ISO timestamp with an explicit offset (`2026-09-30T18:28:51Z`, `…+02:00`) is the exact instant and is converted into the query timezone, so `Z` stays UTC even when `timezone` is `"America/New_York"`.
- A `start` in the future, or an `end` at or before `start`, returns an error rather than an empty chart.
- "This month" = an absolute range whose `start` is the first day of the month (from the current date).

Step choice: ≤2 days → hour; up to ~90 days → day; beyond → week or month.

## metrics

Each metric is wrapped: `{ "visible": true, "id": "m1", "data": { ... }, "display": { "name": "…" } }` — `visible` always true, `id` unique ("m1", "m2", …). **Always set `display.name`** to a concise, human-readable label — without it the chart shows the raw id.

**Event metric** — aggregates occurrences of one tracked event (`data.name` must exactly match an event from `list_event_types`).

**Stats metric** — platform stats; the only stat is concurrent users, `"name": "CCUs"`:
<!-- example:insight-metric -->
```json
{
  "visible": true, "id": "m1",
  "data": { "name": "CCUs", "type": "stats", "measurement": { "math": { "function": "average" } } },
  "display": { "name": "Avg concurrent users", "unit": "User" }
}
```
CCUs honour only the time range: **filters and breakdowns are ignored** for stats metrics (every breakdown value shows "N/A").

**Formula metric** — computed from the other metrics:
<!-- example:insight-metric -->
```json
{
  "visible": true, "id": "m3",
  "data": { "name": "conversion_rate", "type": "formula", "expression": "B/A*100" },
  "display": { "name": "Conversion rate", "unit": "Percentage", "decimals": 2 }
}
```
- Letters reference the **non-formula** metrics in spec order: A = first, B = second, … (A–Z).
- Supported: `+ - * / ^`, parentheses, number literals, unary minus, and implicit multiplication (`2A`, `A(B+C)`).
- An invalid expression is rejected with "Invalid formula expression".
- Division by zero gives 0 (for that bucket, or that breakdown value), never an error — no need to guard the denominator with an epsilon.

Cohort metrics are not supported in agent-built specs — to segment by cohort, use a cohort filter or breakdown.

### Aggregation (measurement.math.function)

| Function | Meaning | Needs `measurement.column` |
|---|---|---|
| count | total event occurrences | no |
| unique + `perPlayerAggregation: "count"` | **unique players** (see recipe below) | no |
| unique + `perSessionAggregation: "count"` | unique sessions | no |
| dau / wau / mau | rolling 1 / 7 / 30-day unique players, averaged over each bucket | no (column and per-player settings are ignored) |
| unique (with a column) | number of distinct values of the column | yes |
| sum / average / median / minimum / maximum | aggregate a numeric property or argument | yes |
| percentile | Nth percentile — **`math.value` is required** (e.g. 95 for p95) | yes |
| first / last | first/last value in the bucket | yes |
| most_frequent | the most common value | yes |

Use these spellings. `total`, `distinct`, `distinct_count`, `first_value`, and `last_value` are cohort spellings: they compute the same thing, but the query builder has no label for them.

**Unique players** — prefer pairing `unique` with a per-player count (column-less `unique` also counts unique players, but the explicit form is what the dashboard builds):
<!-- example:insight-metric -->
```json
{
  "visible": true, "id": "m1",
  "data": {
    "name": "session_start", "type": "event",
    "measurement": { "math": { "function": "unique" }, "perPlayerAggregation": "count" }
  },
  "display": { "name": "Active players", "unit": "User" }
}
```

### Column descriptor (measurement.column)

```json
{ "name": "amount", "type": "property", "dataType": "number" }
```
- `type`: `property` or `argument` (exactly as listed by `list_event_types`: its `defaultProperties` are the platform properties every event carries, such as `device` and `country`; each event's `properties` / `arguments` are its custom ones). Also `user`, `cohort`, `experiment`, `deeplink`, and `direct` in the places described below.
- `dataType`: string, number, boolean, date (arrays: "string[]", "number[]", "boolean[]", "date[]").
- `direct` is only for raw event columns such as `userId`, `sessionId`, `markerType`, `timestamp`. Device, platform, country, and every game-specific dimension are properties or arguments — never `direct`.

### Per-player / per-session pre-aggregation

Two-stage aggregation: first aggregate per player (or per session), then apply `math.function` across them. Allowed per-player/per-session values: sum, average, count, unique, minimum, maximum, first, last. Set only one of the two.

"Average total spend per player":
<!-- example:insight-metric -->
```json
{
  "visible": true, "id": "m1",
  "data": {
    "name": "purchase", "type": "event",
    "measurement": {
      "math": { "function": "average" },
      "column": { "name": "amount", "type": "property", "dataType": "number" },
      "perPlayerAggregation": "sum"
    }
  },
  "display": { "name": "Avg spend per player", "unit": "Robux" }
}
```

### Cumulative sum (running total)

`"cumulativeSum": true` inside `math` turns an event or stats metric into a running total across time buckets. It only applies to time-series displays (line, stacked_line, column, stacked_column, table); bar/pie/metric ignore it.

### Per-metric filters (data.filter)

Scope filters to ONE metric with `"filter": { "operation": "and", "conditions": [ …filters… ] }` inside `data`. Conditions use the same shapes as global filters. Use a per-metric filter only when the condition should not apply to every metric. Otherwise use a global filter (see [Filter and breakdown scope](#filter-and-breakdown-scope)).

### Value formatting (`display`)

`display` controls how a metric's numbers are rendered — it never changes what is computed. Every field except `name` is optional: `name`, `unit`, `compact`, `decimals`, `prefix`, `suffix`.

**`unit` — must be one of these exact values. Case-sensitive PascalCase and singular: `"Day"`, NEVER `"day"`, `"days"`, or `"DAY"`.** An off-list value is rejected.

| Group | Values | Rendering |
|---|---|---|
| Counts | `Number`, `Event`, `User`, `Session` | plain number; the last three append "Events"/"Users"/"Sessions" |
| Percentage | `Percentage` | appends `%` (value is already 0–100, not 0–1) |
| Time | `Millisecond`, `Second`, `Minute`, `Hour`, `Day`, `Week`, `Month`, `Year` | appends the unit name and auto-rescales |
| Currency | `Robux`, `USD`, `Euro`, `Pounds` | `R$` / `$` / `€` / `£` |
| Custom | `Custom` | uses your `prefix` / `suffix` verbatim |

- **Time units declare the unit the raw values are already in**, not a conversion target. A `session_length` stored in seconds is `"unit": "Second"`; the chart rescales on its own.
- **`prefix` / `suffix` are only used when `unit` is `"Custom"`.**
- `compact` (default true) abbreviates large values (`1200` → `1.2K`). `decimals` (0–9, default 0): 2 for rates and currency, 0 for counts.

## Global filters

Optional `filters` array; every entry is `{ "data": { "name", "type", "dataType", "condition" } }`.

**string** — Is, Is not, Contains, Does not contain (with `value: string[]`), or Exists / Does not exist:
<!-- example:filter -->
```json
{ "data": { "name": "platform", "type": "property", "dataType": "string",
            "condition": { "string": { "operation": "Is", "value": ["Mobile"] } } } }
```

**number** — Equal, Not equal, Greater than, Greater than or equal to, Less than, Less than or equal to (`value: number[]`); Between / Not between (`value` = exactly 2 numbers); Exists / Does not exist:
<!-- example:filter -->
```json
{ "data": { "name": "amount", "type": "property", "dataType": "number",
            "condition": { "numeric": { "operation": "Between", "value": [10, 100] } } } }
```

**boolean** — the condition is a plain boolean:
<!-- example:filter -->
```json
{ "data": { "name": "is_premium", "type": "property", "dataType": "boolean",
            "condition": { "boolean": true } } }
```

**date** — On, Not on, Between, Not between, Before, Since (with `range: { start, end? }`); In the last / Not in the last (with `relative: { step, value }`); Exists / Does not exist:
<!-- example:filter -->
```json
{ "data": { "name": "first_seen", "type": "property", "dataType": "date",
            "condition": { "date": { "operation": "In the last", "relative": { "step": "day", "value": 7 } } } } }
```

**cohort** — players in (`Is in`) or not in (`Is not in`) a cohort; `name` is the cohort id as a string from `list_cohorts`:
<!-- example:filter -->
```json
{ "data": { "name": "42", "type": "cohort", "dataType": "cohort",
            "condition": { "cohort": { "operation": "Is not in" } } } }
```

**user (New User / First Occurrence)** — built-in player dimensions:
<!-- example:filter -->
```json
{ "data": { "name": "New User", "type": "user", "dataType": "user", "condition": { "boolean": true } } }
```
- `"New User"`: true = player's first-ever session. `"First Occurrence"`: true = player's first-ever occurrence of this event type.

**experiment** — scope to an A/B experiment or some of its groups (ids from `list_experiments` / `get_experiment`):
<!-- example:filter -->
```json
{ "data": { "name": "Summer Pricing", "type": "experiment", "dataType": "experiment",
            "experiment": { "version": "v2", "level": "group", "experimentId": 42 },
            "condition": { "experiment": { "operation": "In groups", "groupIds": [107] } } } }
```
Always include `"version": "v2"`. Operations: `In groups` / `Not in groups` (level `group`, `groupIds` required), `In experiment` / `Not in experiment` (level `experiment`, `experimentId` required), `In any experiment` / `In no experiments` (level `experiment`, no `experimentId`). Load the understand-experiments skill for the full model.

**deeplink** — only events attributed to a given deeplink (`Was Used`), or events not attributed to it (`Was not Used`); `name` is the deeplink id as a string from `list_deeplinks`:
<!-- example:filter -->
```json
{ "data": { "name": "12", "type": "deeplink", "dataType": "deeplink",
            "condition": { "deeplink": { "operation": "Was Used" } } } }
```
Operations: `Was Used`, `Was not Used`.

**array** — for array-typed properties ("string[]", "number[]", …). `array.operation` is one of: Some, Every, None (paired with an element condition), Length, Average, Sum, Minimum, Maximum (paired with a `numeric` condition on the result), or Exists / Does not exist:
<!-- example:filter -->
```json
{ "data": { "name": "tags", "type": "property", "dataType": "string[]",
            "condition": { "array": { "operation": "Some" },
                           "string": { "operation": "Is", "value": ["vip"] } } } }
```

## breakdowns

Splits every metric by a dimension. Use LOW-cardinality dimensions — never raw ids.

<!-- example:breakdown -->
```json
{ "data": { "name": "country", "type": "property", "dataType": "string" } }
```

- New vs returning: `{ "data": { "name": "New User", "type": "user", "dataType": "boolean" } }`. First vs repeat: `"name": "First Occurrence"`.
- By cohort membership: `{ "data": { "name": "42", "type": "cohort", "dataType": "cohort" } }`.
- By experiment group (one series per group, plus a "Not in <experiment>" series):
<!-- example:breakdown -->
```json
{ "data": { "name": "Summer Pricing", "type": "experiment", "dataType": "number",
            "experiment": { "version": "v2", "level": "group", "experimentId": 42 } } }
```
  Experiment breakdowns always use `"dataType": "number"`. With `"level": "experiment"` and no `experimentId`, you get one series per experiment plus "No experiment" / "Multiple experiments".
- Country and language values arrive as readable names.
- When a breakdown has more values than the limit, the rest are grouped into an "Other <breakdown>" series.

### breakdownOptions — limiting and ordering breakdown values

`levels` is parallel to `breakdowns` (entry 0 controls breakdown 0). Every field is optional.

<!-- example:breakdown-options -->
```json
{ "levels": [{ "limit": 10, "limitMetricId": "m1", "limitOrder": "desc", "sortBy": "value", "sortOrder": "desc" }] }
```
- `limit` (1–1000) + `limitMetricId` + `limitOrder` decide **which** values are kept ("top 10 countries by purchases" = `limitOrder: "desc"`, bottom = `"asc"`). Without `limitMetricId` the first eligible metric ranks them.
- `sortBy` (`value` / `name`) + `sortOrder` only order the kept values in the chart.
- Without `breakdownOptions` the default cap of 1000 values applies.

<!-- shared:query-scope -->
## Filter and breakdown scope

Global `filters` and `breakdowns` apply to the whole query: every metric, funnel step, or retention event (unless this skill notes an exception). A per-metric `data.filter` applies to that one metric only. Decide the scope before you build the spec:

- **A global filter or breakdown needs a column that every event metric shares.** A property or argument used globally must exist on the event of *every* event metric in the query, with the same `dataType`. If even one metric's event lacks it, or has it with a different `dataType`, the query is invalid. Check every metric's event in `list_event_types` before going global. Always safe: the `defaultProperties` (every event carries them) and `user`, `cohort`, `experiment`, and `deeplink` columns. Formula and stats metrics don't count.
- **Prefer global filters; fall back to per-metric ones.** When a condition should apply to every metric, put it in `filters` once, and nowhere else. Never repeat a global condition in each metric's `data.filter` as well: the copy is redundant and drifts when one side is edited. Use a per-metric filter only when the condition should limit some metrics and not others, or when its column is not on every metric's event.
- **Breakdowns have no per-metric form.** When the dimension isn't on every metric's event, break down by one that is, run a separate query per event, or leave out the metric that lacks it. Don't add a breakdown that some metrics can't honour.
- **New User and First Occurrence follow the same rule.** New User keeps only events from each player's first-ever session; First Occurrence keeps only each player's first occurrence of that event. Apply one once, at the scope the question needs: globally when the whole question is about new players, on one metric when only that metric should be limited. Never both. Before you run, check it matches the question: neither means "players who joined recently, across all their sessions". For that, use a cohort.
- **Segment players by behavior with a cohort.** When the question is about players defined by what they did ("players who bought the starter pack", "players who reached level 10", "spenders vs non-spenders", "players who churned"), use a cohort. Look for a saved one with `list_cohorts`. If none fits, build the definition (see the `cohorts` skill) and save it (see the `manage-cohorts` skill; in the Gamebeast assistant the user can also save it from the cohort card). Then filter by it (`Is in` / `Is not in`) or break down by it. Don't approximate a player segment with event filters, extra metrics, or formulas: an event filter limits which events count, not which players. A cohort filter or breakdown takes a saved cohort's id.
<!-- /shared:query-scope -->

## display

The top-level `display` is a **chart type** (not the per-metric `display` object):

- line / stacked_line / column / stacked_column — trends over time
- bar / stacked_bar — category comparisons over the whole window. `stacked_bar` stacks breakdown values, so it needs at least one breakdown; without one, use `bar`.
- pie — proportional breakdown over the whole window
- metric — a single number
- table — exact values

## Experiment coverage

Results for a spec with an experiment filter or breakdown carry `experimentCoverage: { unresolvedRows, totalRows }`. Unresolved rows are excluded from every experiment series; if coverage is low, say so before drawing conclusions.

<!-- shared:after-adhoc-chart -->
## After you show a chart

When you show the user a new ad-hoc chart, end your reply with one short offer to take it further: adjust it (a different time range, a filter, a breakdown, or a segment such as new players), or save it so it stays current, on an existing dashboard or a new one. If you have the create tool for its query type, offer to save it yourself (see the manage-dashboards skill) and save only once the user agrees. If you don't, point to the chart's **Add to dashboard** action in the Gamebeast assistant. Skip the offer when the chart is one step in a bigger answer, and leave it to the caller when you are building the chart for another agent.
<!-- /shared:after-adhoc-chart -->

## Common errors

- Missing display name — every metric must carry `display.name`.
- Invalid `display.unit` — one of the fixed values, case-sensitive and singular.
- "Invalid formula expression" — letters reference non-formula metrics by position; check they exist.
- Missing column — sum/average/median/minimum/maximum/percentile/first/last/most_frequent, and `unique` for distinct values, need `measurement.column`.
- Percentile without `math.value`.
- Counting unique players — prefer `unique` + `perPlayerAggregation: "count"`; plain `unique` with no column gives the same number.
- Wrong display for shape — bar/pie/metric aggregate the whole window; line/column need a time `step`.
- `stacked_bar` without a breakdown — rejected; use `bar`, or add a breakdown.
- Unknown property/argument — verify the exact name and dataType with `list_event_types`; verify values with `get_property_values`.
- Global breakdown or filter on a property/argument that not every event metric has (with the same dataType) — see [Filter and breakdown scope](#filter-and-breakdown-scope).
- The same condition both globally and in every metric's `data.filter` — keep only the global one.
- Using `type: "direct"` for device/platform/country — these are properties or arguments. Always verify with `list_event_types`.
