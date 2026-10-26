---
name: understand-experiments
description: "Understand Gamebeast A/B experiments: the model (groups, weights, unit types, targeting, lifecycle), how to measure results with get_experiment_results and read its statistics, and how to filter or break down insight/funnel queries by experiment group. Load before analyzing any experiment."
---

# Understand Experiments

<!-- shared:experiment-model -->

## The model

An **experiment** runs on one **base configuration** and splits eligible **units** into
**groups**. Each group applies its own **changeset** (edits to the base configuration) to the units
assigned to it. Everything else in the game stays the same, which is what makes the groups
comparable.

- **Unit type.** `user` assigns individual players. `server` assigns whole game servers: every
  player on a server gets that server's group, and the unit id is the server's JobId.
- **Groups.** 1–10 per experiment. Each has an `id` (the join key everywhere), a `label`, a
  `color`, and a `weightPercent`. The weights total exactly 100, so a single group is 100. To
  enroll only some eligible units — the rest stay on the base configuration — use the staged rollout.
- **Changeset.** Ordered operations `{ op, path, value, baseValue }`: `set` replaces an existing
  value, `add` creates a missing key, `delete` removes one. `baseValue` is the value it replaced.
  The changeset *is* the diff; nothing needs computing. An empty changeset is a real group (the
  control serving the base configuration unchanged), not missing data.
- **Assignment.** `weightedHash` (default) hashes the unit id, so a unit always lands in the same
  group. `roundRobin` deals units into groups in turn, which keeps the split exact on small
  populations. `autoAssignment: false` means units only enter by manual assignment.
- **Targeting.** Optional conditions on unit context (e.g. `roblox.country is one of US, CA`,
  `unit.isNewUser = true`) or on membership in a saved cohort. A cohort condition uses the
  cohort's definition as of the experiment's creation; later edits to the cohort do not change it.
  An untargeted experiment covers
  every unit. `permanentEnrollment: true` keeps a unit in its group once assigned, even if it stops
  matching.
- **Path locks.** From creation until it ends, an experiment reserves every configuration path its
  changesets touch. No other experiment and no configuration edit can change those paths.
- **Exclusive experiments.** `exclusive: true` keeps an experiment apart from every other active
  experiment of the same unit type in the environment: a unit already enrolled in another active
  experiment is not enrolled into it, and a unit enrolled in it is not enrolled into any other.
  This only gates new enrollment; enrolled units are never moved, and the block lifts when the
  other experiment ends.
- **Staged rollout.** A separate dial from the weights: the share of *eligible* units allowed to
  enroll at all (`rollout.effectiveBps`, basis points). It can start low and ramp up along a smooth
  curve through scheduled steps, or be set, advanced, paused, and resumed while the experiment runs. Every group ramps
  together (at 10% with a 50/50 split, 5% of eligible units land in each), so the comparison stays
  fair. Lowering or pausing only stops new enrollment: enrolled units keep their group.
- **Lifecycle.** `state` is derived from the schedule: `scheduled` (starts later), `pending`
  (started, but waiting for a targeted cohort to be computed — nobody is enrolled yet), `active`,
  `ended` (reached `endsAt`), or `terminated` (stopped early). Only the rollout can change after
  creation; to change groups, weights, targeting, or changesets, terminate it and create a new one.
- **Enrolled is not exposed.** A unit counts as enrolled once assigned, whether or not it ever
  reached the part of the game that changed.

<!-- /shared:experiment-model -->

## Tools

| Question | Tool |
| --- | --- |
| Which experiments exist? | `list_experiments` (defaults to active + pending + scheduled; pass `state` for more) |
| What does one change, for whom? | `get_experiment` — groups, weights, staged rollout, enrolled counts, changesets, targeting |
| Which group is a given player in? | `list_experiment_members` (search by unit id) |
| Is it working? | `get_experiment_results` — per-group metrics with lift and significance |
| Custom analysis (time series, funnels, segments) | insight/funnel queries filtered or broken down by group (below) |

`assignedUnitCount` / `enrolledUnits` of `null` means the count could not be read, not zero. Say
so rather than reporting zero.

A `pending` experiment has zero enrolled units because it has not started: it targets a cohort
whose membership is still being computed, and starts on its own when that finishes. That is not a
broken experiment and not a result.

## Measuring results

`get_experiment_results({ experimentId, metrics, controlGroupId?, range? })` compares every group
to a control (default: the first group). Pick 1–5 metrics that match the experiment's intent:

| Kind | Measures | Example |
| --- | --- | --- |
| `conversion` | Share of units that fired `event` at least once | `{ "kind": "conversion", "event": "Purchase" }` |
| `count_per_unit` | Average number of `event` per unit | `{ "kind": "count_per_unit", "event": "LevelComplete" }` |
| `sum_per_unit` | Average total of a numeric value on `event` per unit | `{ "kind": "sum_per_unit", "event": "Purchase", "value": { "name": "price", "type": "argument" } }` |

Every enrolled unit is in the denominator, including units that never fired the event (they count
as zero). Only events after the unit was assigned, inside the experiment's run, count. Metrics can
take `filters` (property/argument filters, same shape as insight filters). Find event and argument
names with `list_event_types` and `get_property_values` first; a misspelled event returns all zeros.

**Reading the output:**

- `relativeLift` is a fraction (`0.12` = +12% vs control); `relativeLiftCi` is its 95% interval.
- `verdict`: `significant_positive` / `significant_negative` (p < 0.05), `inconclusive` (no
  detectable difference yet — not "no effect"), or `insufficient_data` (fewer than 100 units in a
  group, or no variance).
- `sampleRatio.mismatch: true` means the enrolled split does not match the weights (p < 0.001).
  That points at a bug (targeting, assignment, or data loss). Lead with it and treat the lifts as
  unreliable.
- `rollout` and `rolloutTimeline` show a staged rollout's current percentage and how it moved.
  Low enrollment during a ramp is expected, not a bug. Every group ramps together, so the lifts
  and the sample-ratio check stay valid; only the totals are smaller. Load the
  experiment-rollouts skill to read the rollout fields and timeline in detail.
- Read the `caveats` and pass on the relevant ones. With several groups or metrics, some
  "significant" results are expected by chance; one significant metric out of five is weak
  evidence.
- Say what the numbers mean for the decision ("Higher Prices raised revenue per player 8% [3%, 13%]
  with no drop in purchase rate"), and whether it is safe to call yet. Do not declare a winner on an
  `inconclusive` or `insufficient_data` verdict.

## Analytics join

Markers carry three enriched properties: `experimentIds` (sorted), `experimentGroupIds`
(positionally aligned with it), and `experimentGroupsKnown`. A server experiment's group is
attributed to every player marker on that server.

**`experimentGroupsKnown = false` means unknown, not "in no experiments"** (that case is
`true` with empty arrays). Filters and breakdowns exclude unresolved rows, and the result carries
an `experimentCoverage` figure. If coverage is low, say so before drawing any conclusion.

`get_experiment_results` does not use these properties (it joins assignments directly), so it works
even when marker enrichment coverage is low.

## Filtering an insight/funnel query by group

Put this in the `filters` array of an insight or funnel spec:

```json
{
  "data": {
    "name": "<experiment name>",
    "type": "experiment",
    "dataType": "experiment",
    "experiment": { "version": "v2", "level": "group", "experimentId": 42 },
    "condition": {
      "experiment": { "operation": "In groups", "groupIds": [107] }
    }
  }
}
```

Always include `"version": "v2"`. The target experiment lives in `experiment`, **not** in the
condition; the condition carries only the selected group ids. Operations:

| Intent | `level` | `experimentId` | `operation` | `groupIds` |
| --- | --- | --- | --- | --- |
| In these groups | `group` | required | `In groups` | required |
| In the experiment, not these groups | `group` | required | `Not in groups` | required |
| In the experiment, any group | `experiment` | required | `In experiment` | — |
| Not in this experiment | `experiment` | required | `Not in experiment` | — |
| In any experiment | `experiment` | omit | `In any experiment` | — |
| In no experiments | `experiment` | omit | `In no experiments` | — |

`Not in groups` is scoped to members: a unit not in the experiment at all does **not** match.

## Breaking down by group

Put the descriptor in `breakdowns` instead, with no condition:

- One series per group: `{ "data": { "name": "<experiment name>", "type": "experiment", "dataType": "number", "experiment": { "version": "v2", "level": "group", "experimentId": 42 } } }`, plus a `Not in <experiment name>` series. Experiment breakdowns always use `"dataType": "number"`.
- One series per experiment across the project: `"level": "experiment"` and no `experimentId`, plus `No experiment` and `Multiple experiments` series.

Scope the time range to the experiment's `startsAt` → `endsAt` (or now).

## Example: "Is the Higher Prices test working?"

1. `list_experiments({ search: "price" })` → "Summer Pricing" (id 42), active, 6 400 enrolled.
2. `get_experiment({ experimentId: 42 })` → "Control" (id 106) and "Higher Prices" (id 107,
   `set shop.prices.sword: 50 → 75`).
3. `get_experiment_results({ experimentId: 42, metrics: [{ "kind": "conversion", "event": "Purchase" }, { "kind": "sum_per_unit", "event": "Purchase", "value": { "name": "price", "type": "argument" } }] })`.
4. Report: purchase rate and revenue per player per group, the lift with its interval, the verdict,
   the sample-ratio check, and what it means for keeping or reverting the price change.
