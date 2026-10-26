---
name: experiment-rollouts
description: "Gradual (staged) rollouts for Gamebeast experiments: how the rollout gate and its smooth ramp curve work, the curve presets, turning a ramp request into rollout steps for create_experiment, reading a rollout from get_experiment and get_experiment_results, and operating one with update_experiment_rollout (set, advance, pause, resume, replaceSteps). Load before designing, changing, or explaining any experiment rollout."
---

# Experiment Rollouts

A **gradual rollout** (also called a staged rollout) releases an experiment to more units over
time. It starts with a small share of eligible units allowed to enroll, then ramps that share up
on a schedule. It can also be set, advanced, paused, and resumed by hand while the experiment runs.
For the rest of the experiment model (groups, changesets, targeting, results), load the
understand-experiments skill; for authoring the rest of a definition, load manage-experiments.

## How it works

- **A gate in front of assignment, separate from the weights.** The rollout percentage is the
  share of *eligible* units (those that pass targeting) allowed to enroll at all. The group weights
  stay fixed and split whoever enrolls. At 10% with a 50/50 split, 5% of eligible units land in
  each group and 90% stay on the base configuration.
- **Every group ramps together.** Both arms get the same mix of early and late enrollees, so the
  comparison stays fair and the sample-ratio check still tests against the configured weights.
  Ramping only the treatment against a fixed control is not supported.
- **Raising only adds units.** Each unit gets a rollout bucket from its own hash (independent of
  its group bucket). A unit admitted at 5% is still admitted at 25% and 100%.
- **Nobody is evicted.** The gate only decides whether a unit *without* an assignment may enroll.
  Lowering, pausing, or setting 0% stops **new** enrollment; every enrolled unit keeps its group.
  To take units out, terminate the experiment (everyone) or unenroll units one at a time with
  `assign_experiment_unit`.
- **Manual assignment bypasses the gate.** `assign_experiment_unit` with `assign` or `reactivate`
  works even at 1%, which is how a QA tester gets into a group during a small canary.
- **Server experiments ramp servers.** For `unitType: "server"` the percentage is the share of
  eligible servers; every player on an admitted server gets that server's group.
- **Takes effect on the next SDK request.** Nothing needs to be republished.
- **Only the rollout is editable.** After creation the rollout can change while the experiment is
  `scheduled` or `active`; groups, weights, targeting, and changesets cannot.

### The curve

The rollout is a smooth curve, not a staircase.

- The **anchor** is the last manual value (`rolloutBps` at `rolloutSetAt`). A new experiment is
  anchored at its **start** (`startsAt`), not when it was created, so a scheduled experiment
  starts at its initial percentage.
- Each scheduled **step** (a *stage* in the dashboard) is a point the curve passes through at its
  `startsAt`. Between points it follows a monotone spline: it rises gradually toward the next step
  instead of jumping on the hour, and it never dips or overshoots.
- With a single step the ramp is a straight line from the anchor. After the last step, the last
  percentage holds. Before the anchor, the anchor holds.
- **Plateaus are allowed.** Percentages may repeat but never decrease. To hold at 5% for a day and
  then climb, add a step at 5% just before the climb starts (see the staircase example below).
- While paused, time stops: the held value is the curve at the moment of the pause.

## Designing a ramp

Agree on the starting share, the target (usually 100%), and how long the climb takes. Suggest a
rollout when the change is risky (economy, monetization, progression) or the audience is large; it
limits the damage while the team watches metrics. It does not replace a control group.

| Preset | Start | Steps (after the experiment starts) |
| --- | --- | --- |
| Gentle week | 1% | 10% at 2 days, 50% at 4 days, 100% at 7 days |
| Linear 3 days | 5% | 100% at 3 days |
| Fast day | 5% | 25% at 4 hours, 100% at 24 hours |
| Cautious canary | 1% | 5% at 3 days, 25% at 7 days, 100% at 14 days |

These are the presets the Gamebeast dashboard offers. Use one when the user has no preference, and
name it so they can find it in the dashboard.

### Writing it into a definition

Add `rollout` to the `experiment` object you pass to `preview_experiment` and `create_experiment`:

<!-- example:experiment-rollout -->
```json
{
  "initialPercent": 5,
  "steps": [
    { "percent": 25, "startsAt": "2026-10-03T16:00:00Z" },
    { "percent": 100, "startsAt": "2026-10-05T16:00:00Z" }
  ]
}
```

- `initialPercent` is the share at the start: more than 0, up to 100, at most two decimals.
- `steps` are absolute ISO times with an offset. Work them out from the experiment's `startsAt`,
  or from the current date when it starts now ("25% after 1 day" = start + 24 hours). Say the times
  back in the user's timezone if you know it.
- Rules: up to 20 steps, times strictly increasing and after the start, percentages never
  decreasing and never below `initialPercent`, and every step strictly before `endsAt` when the
  experiment has one. A step at or after the end never takes effect, so it is refused.
- Omit `rollout` for 100% from the start.

A staircase (hold at 5% for a day, then climb to 25% over the next hour) uses a plateau point:

<!-- example:experiment-rollout -->
```json
{
  "initialPercent": 5,
  "steps": [
    { "percent": 5, "startsAt": "2026-10-03T15:00:00Z" },
    { "percent": 25, "startsAt": "2026-10-03T16:00:00Z" },
    { "percent": 100, "startsAt": "2026-10-06T16:00:00Z" }
  ]
}
```

### Single-group rollouts

To try a change on a slice of players with no control (the rest stay on the base configuration and
are not measured), use one group at `weightPercent: 100` with a rollout below 100%, fixed or
ramping. A lone group below 100% with no `rollout` is an older shorthand that is converted to
exactly that; combining a lone group below 100% *with* a `rollout` is refused. If the user wants to
know whether the change helped, recommend a control group as well: a single group gives nothing to
compare against.

## Reading a rollout

`get_experiment` returns `rollout`, in basis points (divide by 100 for a percentage):

| Field | Meaning |
| --- | --- |
| `effectiveBps` | The percentage in force right now. Lead with this. |
| `initialBps` | What the experiment was created with. Never changes. |
| `rolloutBps`, `rolloutSetAt` | The curve's anchor: the last manual value and when it was set. |
| `pausedAt` | Non-null while paused. |
| `steps` | Every step in time order, including ones already reached (history). |

Steps still ahead are those after `rolloutSetAt` and after now (or after `pausedAt` while
paused). Describe a rollout as "at 12% now, heading to 25% on Oct 3 and 100% on Oct 5", or
"paused at 12%". A rollout at 100% with nothing pending is just a normal experiment; don't call it
staged.

`get_experiment_results` adds `rollout` and `rolloutTimeline`: the rollout's history, oldest
first. Each event has `kind` (`created`, a manual action `set` / `advance` / `pause` / `resume` /
`replaceSteps`, or `step` for a scheduled step the curve reached), `fromBps`, `toBps`, `reason`,
and `occurredAt`. Use it to explain why enrollment moved when it did.

When interpreting results during a ramp:

- Low enrollment is expected, not a bug, and lifts and the sample-ratio check stay valid because
  every group ramps together. A sample-ratio mismatch is still a real problem.
- Small samples early in a ramp usually mean `insufficient_data` or `inconclusive`. Don't call a
  winner because the ramp reached 100%; wait for the verdict.
- Checking results again and again during a ramp raises the chance of a false positive, and no
  correction is applied. Prefer a decision point agreed up front (for example, a week at 100%).

## Changing a rollout

Every change affects live players. Make one only when the user asks for it or agrees to your plan,
and never claim it is done until the result says `updated: true`. In the Gamebeast assistant the
user approves each change on a card first; other clients may ask the user to confirm the call.
Call the tool rather than routing around it through the HTTP API.

`update_experiment_rollout({ experimentId, experimentName, action, percent?, steps?, reason })`:

- Needs `experiments:write`. Works only while the experiment is `scheduled` or `active`.
- `experimentName` must be the exact name from `get_experiment`, as a confirmation.
- `reason` is required and recorded in the rollout history.
- Read the current rollout with `get_experiment` first, and say what it goes from and to.

| `action` | Takes | Effect |
| --- | --- | --- |
| `set` | `percent` only (0–100) | Becomes the rollout from now. Raising it keeps pending steps above the new value and drops the rest; lowering it clears the remaining schedule (each step would raise it straight back). `0` stops new enrollment. Allowed while paused: the rollout stays paused at the new value. |
| `advance` | nothing | Jumps to the next pending step now and removes it from the schedule; the curve then continues toward the remaining steps. Refused while paused or with nothing pending. |
| `pause` | nothing | Holds the current percentage. Pending steps wait. Refused if already paused. |
| `resume` | nothing | Continues from the held value. Every step still pending when the pause began moves later by the length of the pause, so the schedule keeps its spacing. Refused if not paused. |
| `replaceSteps` | `steps` only | Re-anchors at the current percentage and replaces the pending schedule. New steps must be after now, strictly increasing in time, never below the current percentage, and before the experiment ends. `[]` clears the schedule and holds the current value. Refused while paused; resume first. |

Already-reached steps stay in the history whatever you do.

### Common requests

| The user says | Do |
| --- | --- |
| "Metrics look bad, stop it spreading" | `pause` (or `set` to `0`). Say that enrolled players keep their group; to roll them back, terminate the experiment. |
| "Looks good, speed it up" | `advance` to the next step, or `set` a higher percentage. |
| "Go to 100% now" | `set` with `percent: 100`. Pending steps are dropped. |
| "Slow it down" / "stretch it over two weeks" | `replaceSteps` with a later schedule from the current percentage. |
| "Hold here for now" | `pause` if the rest of the schedule should keep its spacing when resumed; `replaceSteps` with `[]` to drop it. |
| "Roll it back to 10%" | `set` with `percent: 10`. Only new enrollment is limited; nobody already enrolled leaves. Say so. |

Example: pause a ramp because of a regression.

<!-- example:experiment-rollout-update -->
```json
{
  "experimentId": 42,
  "experimentName": "Sword price +50%",
  "action": "pause",
  "reason": "Purchase rate in Higher price dropped 9% at the 25% stage; holding while we investigate."
}
```

Example: stretch the rest of the ramp out.

<!-- example:experiment-rollout-update -->
```json
{
  "experimentId": 42,
  "experimentName": "Sword price +50%",
  "action": "replaceSteps",
  "steps": [
    { "percent": 50, "startsAt": "2026-10-06T16:00:00Z" },
    { "percent": 100, "startsAt": "2026-10-10T16:00:00Z" }
  ],
  "reason": "Slow the ramp to give support time to watch tickets before full release."
}
```

### Errors

| `code` | Meaning | What to do |
| --- | --- | --- |
| `invalid_request` | The action doesn't apply (advance with nothing pending, pause while paused, `replaceSteps` while paused), a step breaks a rule, the wrong fields for the action, or the experiment isn't running | Fix what the message names; for paused rollouts, `resume` first |
| `name_mismatch` | `experimentName` doesn't match the id | Confirm which experiment the user means |
| `not_found` | No experiment with that id in this project | Find the id with `list_experiments` |
| `disabled` | The project isn't on this experiments system | Tell the user |
| `forbidden` | This connection can't make the change | Tell the user to make it in the dashboard |

A missing tool means the user's role doesn't allow the change. Say so rather than working around it.

## In the dashboard

In the Gamebeast dashboard, the experiment composer puts **Gradual rollout** under the Allocation
step's **Advanced** section (it opens by itself when a draft already has a rollout). It has the
presets above, a curve you can drag, and stages written as "after N hours/days". On an
experiment's page, the **Rollout** card shows the current percentage, a chart of the ramp (solid
for what has happened, dashed for what is scheduled), a countdown to the next stage, and
**Advance**, **Pause**, **Resume**, **Set %**, and **Edit curve** controls, plus the history. Point
users there when they would rather make the change themselves.
