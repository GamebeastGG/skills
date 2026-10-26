---
name: cohorts
description: "Full reference for cohorts: reading definition JSON and building new player segment definitions. Load to inspect/explain existing cohorts or understand the AST."
---

# Cohorts

A **cohort** is a saved or ad-hoc player segment defined by behavioral rules (event history, property values, nesting, deeplink use, experiment enrollment, saved-funnel completion). Cohorts are used for filtering and breakdown in insight/funnel queries. Users save them in the dashboard; agents with `cohorts:write` can save, edit, and delete them too (see `manage-cohorts`).

**Reach for a cohort whenever an analysis is about a group of players defined by what they did** ("players who bought X", "players who reached level 10", "spenders vs non-spenders", "players who churned"). Check `list_cohorts` for a saved one first. Otherwise build and run the definition, save it, and use it as a cohort filter (`Is in` / `Is not in`) or breakdown on the insight, funnel, or retention query. Event-level filters only limit which events count, not which players are in the segment, so they are not a substitute.

Always present cohorts to the user by **display name**, not raw id. When a definition references cohort IDs, use `list_cohorts` to resolve names before narrating. Never show raw definition JSON to the user unless they explicitly ask.

In saved analytics queries, cohorts appear as filters (`Is in` / `Is not in`) or breakdowns where the cohort column's `name` is the **numeric cohort id as a string**.

## Definition structure

A cohort `definition` is `Block[]` (a JSON array of blocks).

| Level | Type | Combines as |
|-------|------|-------------|
| Root | `Block[]` | **OR** — player in any block is in the cohort |
| Block | `Group[]` | **AND** — player must satisfy every group in the block |
| Group | `{ operator, conditions }` | operator = "and" or "or" across conditions |
| Condition | event, nested-cohort, deeplink, experiment, any-deeplink, any-experiment, or funnel | `positive: false` = NOT |

Most segments use a single block with a single group. Use multiple blocks for "segment A **or** segment B".

Minimal shape:
```json
[
  [
    {
      "operator": "and",
      "conditions": [
        { ... condition ... }
      ]
    }
  ]
]
```

## Event conditions

```json
{
  "positive": true,
  "metric": {
    "type": "event",
    "name": "purchase",
    "filter": { ... optional per-event filters ... }
  },
  "math": {
    "function": "total",
    "column": {
      "name": "count",
      "type": "property",
      "dataType": "number",
      "condition": { "numeric": { "operation": "Greater than or equal to", "value": [1] } }
    }
  },
  "date": {
    "operation": "In the last",
    "interval": { "step": "day", "value": 30 }
  }
}
```

### math.function

`math.column` names the value being aggregated **and** carries the threshold. Every function except `total` aggregates the named column, so pick the function by what you are measuring:

| Function | Aggregates | Use when |
|----------|-----------|----------|
| total | the number of matching events (the column `name` is ignored — use the conventional `"count"`) | "did X at least N times" (most common) |
| sum / average / median / minimum / maximum | the named numeric property/argument | "spent more than 50 in total", "average level above 10" |
| percentile | the named numeric column; the **threshold value is the percentile** (e.g. 95) | rarely needed — this is a percentile of *one player's own* values. For "top 5% of players" use a ranked condition (`math.relative`) instead |
| distinct / distinct_count / unique | distinct values of the named column | "bought at least 3 different items" (column = item id) |
| first / first_value / last / last_value / most_frequent | the named column's first/last/most common value | "first platform is Mobile" — these may use a string or boolean column |

Do not use `count`, `unique`, or `dau`/`wau`/`mau` to count events — use `total`. With `count`/`unique` the named column is aggregated (for the conventional `"count"` column that is usually empty), and `dau`/`wau`/`mau` have no special meaning in cohorts.

`total` is for cohort conditions only. In insight and heatmap query metrics it is the other way round: count events with `count` (the query builder shows a blank aggregation for `total`).

Every function except the pass-through ones (first/first_value/last/last_value/most_frequent) needs a **numeric** `math.column`.

**Per-session aggregation** — `"perSessionAggregation": "<function>"` inside `math` first aggregates each session, then applies the threshold to the player's sessions. "Played at least 5 sessions with a purchase":
```json
"math": {
  "function": "total",
  "perSessionAggregation": "count",
  "column": { "name": "count", "type": "property", "dataType": "number",
              "condition": { "numeric": { "operation": "Greater than or equal to", "value": [5] } } }
}
```

### math.relative — ranked conditions (compare a player to everyone else)

By default the threshold compares each player's aggregate to a fixed number. Add `math.relative` to compare it to the **other players** instead — "top 1% of spenders", "playtime above average", "more than twice the median number of sessions". The aggregate is computed per player exactly as above, then turned into a relative value, and `math.column.condition` (always numeric) is applied to that relative value:

| `math.relative` | Relative value | Example threshold |
|-----------------|----------------|-------------------|
| `{ "type": "percentile_rank" }` | the player's percentile rank, 0–100 | `>= 99` = top 1%; `Between [90, 99]` = the 90th–99th percentile band; `< 50` = bottom half |
| `{ "type": "ratio", "statistic": "average" }` | value ÷ population average | `> 1` = above average; `> 2` = more than twice the average |
| `{ "type": "ratio", "statistic": "median" }` | value ÷ population median | `>= 2` = at least twice the median |
| `{ "type": "ratio", "statistic": "percentile", "percentile": 90 }` | value ÷ population 90th percentile | `>= 1` = at or above the p90 value |

- **Population**: players with at least one matching event in the condition's `date` window (after `metric.filter`). Players who never did the event are not ranked — "top 1% of spenders" means the top 1% of players who spent. Say so when you narrate the cohort.
- `positive: false` inverts membership against *all* players, so "not in the top 1% of spenders" also includes players who never spent.
- Works with `total`, `sum`, `average`, `median`, `minimum`, `maximum`, `distinct_count`, and with `perSessionAggregation`. Not allowed with `percentile` as `math.function`, with pass-through functions, or with `Exists` / `Does not exist`.
- `percentile` is required with `"statistic": "percentile"` and not allowed otherwise.
- Ties share a rank, and a population of one player has rank 0. A ratio to a statistic of 0 matches nobody.

### math.column — the threshold

Always required. For a numeric column, `condition.numeric.operation` selects the comparison:

| Operation | Meaning |
|-----------|---------|
| Greater than or equal to | ≥ N (most common — "at least N times") |
| Greater than | > N |
| Equal | = N |
| Not equal | ≠ N |
| Less than | < N |
| Less than or equal to | ≤ N |
| Between | between N and M (value = [N, M]) |
| Not between | outside range |
| Exists | property exists |
| Does not exist | property absent |

For a pass-through function on a string column use a `string` condition (e.g. `{ "string": { "operation": "Is", "value": ["Mobile"] } }` with `"dataType": "string"`); on a boolean column use `{ "boolean": true }`.

**"Did this event at least once"** pattern (most common):
```json
"math": {
  "function": "total",
  "column": {
    "name": "count",
    "type": "property",
    "dataType": "number",
    "condition": { "numeric": { "operation": "Greater than or equal to", "value": [1] } }
  }
}
```

### date — when the event must have occurred

**Prefer relative intervals.** Only use absolute dates when the user specifies exact calendar dates. Use the current date to interpret "last month", "this week", etc. as relative intervals, never hardcoded ISO dates.

`date` is **required** on every event condition. It is either a window (`operation` + `interval`) or the unbounded **All time** option, which has no `interval`:

```json
"date": { "operation": "All time" }
```

"All time" counts every matching event the project has ever recorded — use it for "at least N times ever", "has ever purchased", "never completed the tutorial" (with `positive: false`). Never approximate all-time with a huge look-back like 10 years.

**Default window: when the user does NOT specify any time window, default to the last 30 days** — `{ "operation": "In the last", "interval": { "step": "day", "value": 30 } }`. For example "players who logged in more than 5 times" (no window given) means in the last 30 days, NOT all-time. Only use All time when the user explicitly asks for "ever" / "all-time" / "of all time" / "lifetime" / "never".

Common mappings:
- "in the last month" → `{ "operation": "In the last", "interval": { "step": "month", "value": 1 } }`
- "in the last 30 days" → `{ "operation": "In the last", "interval": { "step": "day", "value": 30 } }`
- "in the last week" → `{ "operation": "In the last", "interval": { "step": "week", "value": 1 } }`
- no time window specified → default to the last 30 days: `{ "operation": "In the last", "interval": { "step": "day", "value": 30 } }`
- "ever" / "all-time" / "lifetime" / "never" (explicitly requested) → `{ "operation": "All time" }`

Relative: `"date": { "operation": "In the last", "interval": { "step": "day", "value": 30 } }`

Absolute (only when user gives exact dates): `"date": { "operation": "Between", "interval": { "start": "2025-01-01T00:00:00.000Z", "end": "2025-01-31T23:59:59.000Z" } }`

Date operations: `All time` (no `interval`), `On`, `Not on`, `Between`, `Not between`, `Before`, `Since`, `In the last`, `Not in the last`. Every operation except `All time` requires an `interval`.

All-time conditions scan the project's whole event history, so they are slower on large projects than a short window — prefer a window when the user's intent allows it.

### metric.filter — optional per-event property filters

Narrow which event instances count (e.g. only purchases above $5):
```json
"metric": {
  "type": "event",
  "name": "purchase",
  "filter": {
    "operation": "and",
    "conditions": [
      { "name": "amount", "type": "property", "dataType": "number",
        "condition": { "numeric": { "operation": "Greater than", "value": [5] } } }
    ]
  }
}
```

## Nested cohort conditions

Reference an existing saved cohort by its numeric id (as a string):
```json
{
  "positive": true,
  "metric": {
    "type": "cohort",
    "name": "42",
    "definition": []
  }
}
```

- `metric.name` is the cohort's numeric id as a string — never a display name.
- `metric.definition` is always `[]` when you provide it.
- `metric.filter` (optional) — same shape as an event condition's `metric.filter` — restricts which events count toward the nested cohort.
- `positive: false` = "is NOT in cohort 42".
- Max nesting depth: 3.
- `metric.unresolved: true` — the referenced cohort no longer exists; treat the reference as broken.

## Deeplink conditions

"Players who used (or never used) a deeplink." Read from the deeplink's conversions — over the project's whole history by default, or within an optional `date` window. There is no `math` or `filter`, and adding either is rejected:
```json
{ "positive": true, "metric": { "type": "deeplink", "name": "12" } }
```

- `metric.name` is the deeplink's numeric id as a string — look it up with the deeplink tools (see `understand-deeplinks`), never a display name.
- `positive: false` = "did not use deeplink 12" (every player the project has seen, minus those who converted through it).
- Add a `date` (same shapes as an event condition's) to count only conversions inside it — "used deeplink 12 in the last 7 days". Omit it (or use `All time`) for ever. Unlike event conditions, do **not** default to 30 days: no window is the right reading when the user gives none.
```json
{ "positive": true, "metric": { "type": "deeplink", "name": "12" },
  "date": { "operation": "In the last", "interval": { "step": "day", "value": 7 } } }
```

## Experiment conditions

"Players currently enrolled (or not enrolled) in an experiment", optionally narrowed by group. Only **user-unit, experiments v2** experiments are allowed (cohorts are sets of players). Enrolled means the player's latest assignment is active, so players who were unenrolled no longer match. No `math` or `filter`:
```json
{ "positive": true, "metric": { "type": "experiment", "name": "7" } }
```

Narrow to members in (or not in) specific groups with `metric.groups` — `operation` is `"In groups"` or `"Not in groups"`, and `groupIds` (numeric group ids, non-empty) must belong to the experiment:
```json
{ "positive": true,
  "metric": { "type": "experiment", "name": "7",
              "groups": { "operation": "In groups", "groupIds": [31] } } }
```

- `metric.name` is the experiment's numeric id as a string — find it with `list_experiments`.
- `"Not in groups"` is scoped to members: "enrolled, but not in Control". It does not match players outside the experiment.
- `positive: false` negates the whole condition, groups included: `positive: false` with `"In groups": [31]` is everyone *except* members currently in group 31.
- Add a `date` window to require that the player's **current** assignment was made inside it — "currently enrolled in experiment 7, assigned in the last 7 days". Players assigned in the window and unenrolled since do **not** match: only each player's latest assignment is kept. Omit it (or use `All time`) for current enrollment regardless of when.

## Funnel conditions

"Players who completed (or did not complete) a saved funnel", or who reached at least a given step of it. `metric.name` is the saved funnel query's numeric id as a string (find it with `list_queries`; it must be a funnel). A `date` window is required and uses the same shapes as an event condition's `date` — the funnel's own saved time range is ignored. No `math` or `metric.filter`:
```json
{ "positive": true,
  "metric": { "type": "funnel", "name": "88" },
  "date": { "operation": "In the last", "interval": { "step": "day", "value": 30 } } }
```

Add `metric.step` (a step's `id` from the funnel's `metrics`, as returned by `get_query`) to require reaching at least that step instead of the whole funnel:
```json
{ "positive": true,
  "metric": { "type": "funnel", "name": "88", "step": "<metrics[1].id>" },
  "date": { "operation": "All time" } }
```

- The funnel's steps, step filters, global filters, conversion window, ordering, and constant attributes all apply. Breakdowns and measurement do not.
- It is a live reference: editing the saved funnel changes the cohort.
- `metric.definition` / `metric.unresolved` are filled in when the cohort is read; never send them. `unresolved: true` means the funnel was deleted and the condition matches nobody.
- Funnels that filter by a cohort or by new/first-time users cannot be used in a cohort.
- `positive: false` = "did not complete funnel 88 in the window".
## Any-deeplink and any-experiment conditions

The deeplink and experiment conditions without the id check: a player qualifies through **any** of the project's deeplinks (`any_deeplink`) or **any** of its user-unit v2 experiments (`any_experiment`). Same rules as above otherwise — deeplink use is all-time unless windowed, enrollment means a currently active assignment, an optional `date` window applies the same way, and there is no `math` or `filter`:
```json
{ "positive": true, "metric": { "type": "any_deeplink" } }
```

Narrow either one to a selection with `deeplinkIds` / `experimentIds` (numeric ids, non-empty). This is the shortcut for an `"or"` group of one deeplink / experiment condition per id — prefer it over writing those conditions out:
```json
{ "positive": true, "metric": { "type": "any_experiment", "experimentIds": [7, 9] } }
```

- The ids are **numbers** here, not strings (unlike `metric.name` on the single-id conditions). Every id must exist in the project; experiments must be user-unit v2.
- `any_experiment` has no `groups` — groups belong to one experiment; use an `experiment` condition to narrow by group.
- `positive: false` = "never used any (of these) deeplinks" / "not currently enrolled in any (of these) experiments".

## Negation (positive: false)

"Players who did NOT purchase in the last 30 days":
```json
{
  "positive": false,
  "metric": { "type": "event", "name": "purchase" },
  "math": { "function": "total", "column": { "name": "count", "type": "property", "dataType": "number",
            "condition": { "numeric": { "operation": "Greater than or equal to", "value": [1] } } } },
  "date": { "operation": "In the last", "interval": { "step": "day", "value": 30 } }
}
```

## Boolean logic patterns

**AND within a group:** `[[{ "operator": "and", "conditions": [condA, condB] }]]`

**OR within a group:** `[[{ "operator": "or", "conditions": [condA, condB] }]]`

**AND between groups (same block):** `[[{ "operator": "and", "conditions": [condA] }, { "operator": "and", "conditions": [condB] }]]`

**OR between segments (multiple blocks):** `[ [{ "operator": "and", "conditions": [condA] }], [{ "operator": "and", "conditions": [condB] }] ]`

## Recipes

### Churned players (active then inactive)

<!-- example:cohort-definition -->
```json
[[{
  "operator": "and",
  "conditions": [
    { "positive": true, "metric": { "type": "event", "name": "session_start" },
      "math": { "function": "total", "column": { "name": "count", "type": "property", "dataType": "number",
                "condition": { "numeric": { "operation": "Greater than or equal to", "value": [1] } } } },
      "date": { "operation": "In the last", "interval": { "step": "day", "value": 90 } } },
    { "positive": false, "metric": { "type": "event", "name": "session_start" },
      "math": { "function": "total", "column": { "name": "count", "type": "property", "dataType": "number",
                "condition": { "numeric": { "operation": "Greater than or equal to", "value": [1] } } } },
      "date": { "operation": "In the last", "interval": { "step": "day", "value": 14 } } }
  ]
}]]
```

### High-value players (big spenders)

<!-- example:cohort-definition -->
```json
[[{
  "operator": "and",
  "conditions": [
    { "positive": true, "metric": { "type": "event", "name": "purchase" },
      "math": { "function": "sum", "column": { "name": "amount", "type": "property", "dataType": "number",
                "condition": { "numeric": { "operation": "Greater than", "value": [50] } } } },
      "date": { "operation": "In the last", "interval": { "step": "day", "value": 30 } } }
  ]
}]]
```

### Repeat buyers ever (at least 5 purchases, all time)

<!-- example:cohort-definition -->
```json
[[{
  "operator": "and",
  "conditions": [
    { "positive": true, "metric": { "type": "event", "name": "purchase" },
      "math": { "function": "total", "column": { "name": "count", "type": "property", "dataType": "number",
                "condition": { "numeric": { "operation": "Greater than or equal to", "value": [5] } } } },
      "date": { "operation": "All time" } }
  ]
}]]
```

### Top 1% of spenders (ranked)

<!-- example:cohort-definition -->
```json
[[{
  "operator": "and",
  "conditions": [
    { "positive": true, "metric": { "type": "event", "name": "purchase" },
      "math": { "function": "sum",
                "column": { "name": "amount", "type": "argument", "dataType": "number",
                  "condition": { "numeric": { "operation": "Greater than or equal to", "value": [99] } } },
                "relative": { "type": "percentile_rank" } },
      "date": { "operation": "In the last", "interval": { "step": "day", "value": 30 } } }
  ]
}]]
```

### Playtime above average (ranked)

Total `sessionLength` of `Logout` events above the average player's:

<!-- example:cohort-definition -->
```json
[[{
  "operator": "and",
  "conditions": [
    { "positive": true, "metric": { "type": "event", "name": "Logout" },
      "math": { "function": "sum",
                "column": { "name": "sessionLength", "type": "argument", "dataType": "number",
                  "condition": { "numeric": { "operation": "Greater than", "value": [1] } } },
                "relative": { "type": "ratio", "statistic": "average" } },
      "date": { "operation": "In the last", "interval": { "step": "day", "value": 30 } } }
  ]
}]]
```

For "more than twice the median playtime", use `"relative": { "type": "ratio", "statistic": "median" }` with `"value": [2]`.

## Common errors

- **Empty definition** — the root array must have at least one block. An empty `[]` will always error.
- **Wrong id type for nested cohort** — `metric.name` must be the numeric id as a string (e.g. `"42"`), never a display name.
- **Unknown event name** — re-check the exact marker name with `list_event_types`. Names are case-sensitive.
- **Depth limit exceeded** — nested cohorts can only be 3 levels deep.
- **Unknown deeplink / experiment id** — the id must exist in this project, the experiment must be a user-unit v2 experiment, and every `groupIds` entry must belong to it.
- **Extra fields on deeplink / experiment conditions** — they take only `positive`, `metric`, and an optional `date`; `math` and `metric.filter` are rejected. `any_deeplink` / `any_experiment` take only an optional non-empty `deeplinkIds` / `experimentIds` array of numbers.
- **Unknown funnel id or step** — the id must be a saved funnel query in this project, and `metric.step` must be one of its `metrics[].id`. Funnel conditions require `date` and reject `math`.
- **Missing math.column** — all `math.function` values require a `column` with a valid `condition`.
- **Missing date** — every event condition requires a `date`. Default to the last 30 days when the user gives no window; use `{ "operation": "All time" }` only when they explicitly ask for all-time / ever.
- **Interval on All time / missing interval** — `All time` takes no `interval`; every other operation requires one.
- **Between value length** — Between / Not between require `value` to be exactly 2 numbers: `[10, 100]`.
- **Ranked threshold in the wrong units** — with `math.relative` the threshold is a rank (0–100) or a ratio (1 = the statistic), never the raw amount: top 1% of spenders is `>= 99`, not the dollar amount.

## Descriptions

Saved cohorts can carry a `description` (plain text, max 1000 characters) saying who is in the cohort and what it is for. `list_cohorts` returns it, and its `search` matches descriptions as well as names. Use it to pick the right cohort when names are ambiguous, and quote it when explaining a cohort to the user.

Always write one for a cohort you build: pass `description` to `run_cohort_definition` (and to `create_cohort` when saving). One or two plain sentences on who is in it, including the time window and thresholds — "Players who made at least 5 purchases in the last 30 days." — plus what it is for when known. No raw JSON or ids.

## Saving cohorts

When the user asks to save, rename, describe, change, or delete a cohort, load the `manage-cohorts` skill and use `create_cohort` / `update_cohort` / `delete_cohort` — they need the `cohorts:write` permission and, in the assistant, the user's approval on a card. If those tools are not available to you, the user lacks permission to change cohorts: say so instead of retrying.

In the Gamebeast assistant, an ad-hoc cohort result card also has "Save Cohort" (saves with the suggested name and description) and "Edit Cohort" (opens the full cohort builder); when directing the user there, use those exact button labels — never say "Create Cohort".
