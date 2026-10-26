---
name: run-analytics-query
description: "Execute saved analytics queries (insights, funnels, retention, heatmaps) with optional time/breakdown overrides, and interpret insight, funnel, retention, and heatmap results."
---

# Run analytics query

Use this skill when the user asks you to run, show, or analyze a **saved** analytics query, metric, funnel, retention chart, or heatmap. For NEW ad-hoc charts, build and run a spec instead (see the `insight-queries`, `funnel-queries`, `retention-queries`, `heatmap-queries`, and `cohorts` skills). To change what a saved query measures, see the `manage-dashboards` skill.

## Workflow

1. **Locate the saved query first.** Use `list_queries` with a `search` term, or `get_dashboard` if the user named a dashboard. Confirm you have the correct `queryId`.
2. **Execute with `execute_query`.** Pass the saved query's `id` as `queryId`. Override `time` and/or `breakdowns` only when the user asks for a different window or slice.
3. **Analyze, don't transcribe.** Do **not** restate raw numbers bucket-by-bucket — where the client renders the chart (the Gamebeast assistant does, inline), the user already sees them; elsewhere, quote only the few numbers that support your point. **Analyze** the data: trends over time, spikes/dips, breakdown comparisons, anomalies, and actionable takeaways.

## Time range override (`time`)

`time` is either a **relative** window or an **absolute** range. Optional `timezone` (a supported IANA name, e.g. `"America/New_York"`) defaults to the project's timezone.

### Relative window

```json
{ "step": "day", "relative": { "step": "day", "value": 30 } }
```

- Top-level `step` is the **bucket/granularity** for the chart (hour, day, week, month, etc.).
- `relative.step` + `relative.value` (a positive number, not a string like `"-30d"`) = a **rolling** look-back from now.
- `relative.offset` moves only the **start** of the window further back — the end stays at now (midnight today for a `day` window). It does not give "the previous period"; use an absolute range for that.
- `relative.truncate` is accepted but not applied — for "this month" / "this quarter" use an absolute range starting on the first day of the period.

Allowed `step` values: `second`, `minute`, `hour`, `day`, `week`, `month`, `quarter`, `year`.

### Absolute range

```json
{ "step": "day", "range": { "start": "2025-01-01 00:00:00", "end": "2025-01-31 23:59:59" } }
```

- `YYYY-MM-DD HH:mm:ss` strings (project timezone unless `timezone` is set); omit `end` (or null) for "until now".
- An ISO timestamp with an explicit offset (`2026-09-30T18:28:51Z`, `…+02:00`) is the exact instant and is converted into that timezone, so `Z` stays UTC.
- A `start` in the future, or an `end` at or before `start`, returns an error rather than an empty result.

### Step choice guidance

| Window length | Recommended `step` |
|---|---|
| ≤ 2 days | `hour` |
| up to ~90 days | `day` |
| beyond ~90 days | `week` or `month` |

## Breakdown override (`breakdowns`)

```json
[{ "data": { "name": "country", "type": "property", "dataType": "string" } }]
```

- Any breakdown the insight-queries skill describes is valid (property, argument, user, cohort, experiment).
- Discover names via `list_event_types`. Prefer **low-cardinality** dimensions over ids.
- A property or argument breakdown must exist, with the same dataType, on the event of **every** metric in the saved query (`get_query` shows them). Default properties, New User, cohorts, and experiment groups work on any query.
- To compare a behavioral player segment, break down by a cohort (`list_cohorts`) rather than by an event property.
- Passing `breakdowns` **replaces** the saved query's breakdowns entirely. Omit it to keep the saved ones.

## Reading results

**Insight** — time-series displays return `series[]` of `{ time, metrics: { <metricId>: { value, breakdowns } } }` plus `seriesAggregates` (min/max/average/sum per metric). bar/pie/metric displays return one aggregated `value` per metric. With an experiment filter or breakdown, `experimentCoverage: { unresolvedRows, totalRows }` reports how much traffic could not be attributed to a group — flag low coverage before concluding anything.

**Funnel** — `series` keyed by breakdown value (`"default"` without breakdowns); each is a list of steps with `unique_users`, `total_conversions`, `unique_users_conversion_rate`, and `total_conversion_rate` (rates are 0–100). The biggest drop between consecutive steps is usually the insight.

**Retention** — the shape depends on the saved display:
- `line`: `series[]` of `{ time, value: { all_users, retained_users, retention_rate } }`.
- `retention_curve`: `series[]` of `{ bucket_number, value: { cohort_size, retained_users, retention_rate } }` — bucket 0 is the start, 1 the next window, and so on.
- `metric`: a single `{ all_users, retained_users, retention_rate }` (per breakdown value when broken down).
- `retention_rate` is already a percentage. In look-ahead mode the newest buckets have not had time to return and read low.

**Heatmap** — a summary of an event's positions on a map: `grid` (columns, rows, cell size in studs), `aggregates` (`sum` is the total count), and `hotspots` — the busiest cells with their world `x`/`z` and `share` of the total. The heatmap-queries skill explains how to read them; `get_heatmap_image` shows the map underneath.

## Caveats

- Overrides use **replace semantics** — a provided field fully replaces the saved value; omitted fields keep the saved value.
- **Heatmap queries ignore `breakdowns` overrides** — only `time` applies.
- Results may be **cached** or **filled** (interpolated) for incomplete buckets — note this when interpreting the latest bucket.
