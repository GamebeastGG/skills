---
name: manage-experiments
description: "Create, terminate, and manage Gamebeast A/B experiments: how to design a definition (groups, weights, changesets, targeting, staged rollout), check it with preview_experiment, create it with create_experiment, end it with terminate_experiment, ramp it with update_experiment_rollout, and pin or exclude individual units with assign_experiment_unit. Load before making any experiment change."
---

# Manage Experiments

Every write here changes what live players get. Make one only when the user asks for it or
agrees to your plan, give a concrete `reason` (it is recorded with the change), and never claim a
change is done until the tool result says so. Each tool makes the change itself when it runs; it is
not a draft or a proposal. In the Gamebeast assistant the user approves each call on a card before
it runs; other clients may ask the user to confirm the tool call. Either way, call the tool rather
than routing around it through the HTTP API. If the user declines, ask what to change instead of
making the same call again.

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

| Action | Tool | Permission |
| --- | --- | --- |
| Check a definition without creating it | `preview_experiment` | experiments:read, configurations:read |
| Create an experiment | `create_experiment` | experiments:write |
| Stop an experiment now | `terminate_experiment` | experiments:write |
| Set, advance, pause, resume, or reschedule a staged rollout | `update_experiment_rollout` | experiments:write |
| Pin, un-pin, exclude, or re-include one unit | `assign_experiment_unit` | experiments:assign |
| See reserved configuration paths | `list_experiment_locks` | experiments:read |

A tool you do not have is one the user's role does not allow. Say so and suggest who can do it,
rather than working around it.

## Creating an experiment

### 1. Design it with the user

Agree on: the hypothesis, which configuration keys change and to what, the group split, the unit
type, who is eligible (targeting), and how long it runs. Keep the first group as the control with
no operations unless the user wants every group changed. Each group should differ in the one thing
being tested.

### 2. Read what you are changing

1. `list_configurations` → the base configuration's id. Usually the project's primary
   configuration, since that is the one games are running.
2. `get_configuration` (mode `values`) or `search_configuration` → the **exact current value** at
   every path you will change. Each `set`/`delete` operation's `baseValue` must equal it exactly, and
   an `add` path must not exist yet.
3. `list_experiment_locks({ configurationId })` → paths already reserved by another experiment.
   A change on or under a reserved path is refused.
4. `list_experiments` → make sure the name is not already taken.

### 3. Write the definition

```json
{
  "reason": "Test whether a 50% sword price increase raises revenue per player without hurting purchase rate.",
  "experiment": {
    "name": "Sword price +50%",
    "description": "Sword 50 → 75 coins for half of new and returning players.",
    "baseConfigurationId": 12,
    "unitType": "user",
    "groups": [
      { "label": "Control", "weightPercent": 50, "operations": [] },
      {
        "label": "Higher price",
        "weightPercent": 50,
        "operations": [
          { "op": "set", "path": "shop.prices.sword", "baseValue": 50, "value": 75 }
        ]
      }
    ]
  }
}
```

- **Description**: always write one, even when the user didn't ask: the hypothesis and what each
  group changes, in a sentence or two ("Sword 50 → 75 coins for half of players, to test whether
  revenue per player rises without hurting purchase rate.").
- **Paths** are dot-separated from the configuration root (`shop.prices.sword`). Escape a literal
  dot in a key as `\.`. Array items are addressed by index (`rewards.0.amount`).
- **Weights** are percentages with up to two decimals. With 2+ groups they total exactly 100.
- **Operations** within one group must not overlap (no `a` and `a.b` in the same group). Different
  groups may change the same path to different values; that is the point.
- **Schedule.** Omit `startsAt` to start now. `endsAt` is optional; without it the experiment runs
  until terminated. A future `startsAt` creates a `scheduled` experiment, which already holds its
  path locks.
- **Colors** are optional; the default palette is used otherwise.
- **Staged rollout** (optional): add `"rollout": { "initialPercent": 5, "steps": [{ "percent": 25,
  "startsAt": "..." }, { "percent": 100, "startsAt": "..." }] }` to start with 5% of eligible units
  and ramp up. Step times must strictly increase and come after `startsAt`; percentages never
  decrease. Suggest one when the user is nervous about a risky change; it does not replace a
  control group. Load the experiment-rollouts skill for presets, the curve, and ramp design.
- **Exclusive** (optional): `"exclusive": true` when the user wants this experiment's players kept
  out of every other experiment (and vice versa). Warn them that it cannot enroll anyone who is
  already in another active experiment of the same unit type, so on a busy project it may start
  with little traffic. `preview_experiment` lists those experiments in `exclusionConflicts`.

### 4. Targeting (optional)

Omit `targeting` to include everyone. Otherwise pass an AST:

```json
{
  "version": 1,
  "root": {
    "type": "all",
    "conditions": [
      {
        "id": "country",
        "type": "property",
        "path": "roblox.country",
        "valueType": "string",
        "operator": "in",
        "value": ["US", "CA"],
        "stickiness": "whileMatched"
      },
      {
        "id": "new-players",
        "type": "property",
        "path": "unit.isNewUser",
        "valueType": "boolean",
        "operator": "equals",
        "value": true,
        "stickiness": "whileMatched"
      }
    ]
  }
}
```

- Group nodes: `all` (AND), `any` (OR), `not` (with a single `condition`).
- `id` is unique per condition (letters, digits, `.`, `-`, `_`).
- Paths: well-known platform fields (`roblox.country`, `roblox.language`, `roblox.device`,
  `roblox.inputType`, `roblox.placeId`, ...; on Unreal projects `unreal.platform`,
  `unreal.device`, `unreal.country`, `unreal.language`, `unreal.appVersion`,
  `unreal.engineVersion`), unit fields (`unit.distinctId`, `unit.isNewUser`,
  `unit.daysSinceFirstSeen`, `unit.firstSeenAt`), or custom properties the game sends
  (`properties.<name>`).
- `valueType` is `string`, `number`, `boolean`, `date` (epoch ms), or `stringArray` /
  `numberArray` / `booleanArray`. Operators depend on it: `equals`, `notEquals`, `in`, `notIn`,
  `contains`, `startsWith`, `gt`/`gte`/`lt`/`lte`, `between`, `inLast` (date, value in ms),
  `containsAny`/`containsAll`/`containsNone` (arrays), `exists`/`doesNotExist` (any, no value).
- Country and language use ISO codes (`US`, `en`), never names.
- `stickiness` must be `whileMatched`; `permanentOnceMatched` is not available yet.
- `unit.*` first-seen fields only apply to `user` experiments.

#### Cohort conditions

Target players by membership in a saved cohort (`list_cohorts` for ids):

```json
{ "id": "whales", "type": "cohort", "cohortId": 17, "operator": "in", "stickiness": "whileMatched" }
```

- `operator` is `in` or `notIn`. `user` experiments only, and the cohort must belong to this
  project. Cohort conditions may be disabled for the project; `preview_experiment` says so.
- Membership is precomputed in the background, not evaluated live. An experiment whose cohorts
  have not been computed yet is created in the **`pending`** state: nobody is enrolled until every
  targeted cohort is ready, then it starts automatically (usually minutes; large cohorts longer).
  `preview_experiment` returns `cohorts[].cached` — `true` means it will start immediately.
  Tell the user when it will be pending. `cohorts[].suspended: true` means that cohort repeatedly
  failed to compute (`failureReason: "too_expensive"`: it exceeded the compute time or memory
  limit) and automatic refreshes stopped. Creating the experiment retries it once, but it will
  probably stay pending: warn the user and suggest a cheaper cohort (shorter time window, fewer
  conditions).
- Membership refreshes periodically (about every 15 minutes). A player who joins the cohort is
  eligible after the next refresh, not instantly.
- If membership is missing or too stale, the condition matches nobody — for `notIn` as well as
  `in`. It never fails open.
- The definition is frozen when the experiment is created. Editing the cohort afterwards changes
  only experiments created after the edit; a running one keeps its original audience. To change
  who a running experiment targets, terminate it and create a new one. A cohort a live experiment
  targets cannot be deleted.

### 5. Preview, then create

Call `preview_experiment` with the same `experiment` object to check it (optional: `create_experiment`
runs the same checks and refuses an invalid definition). Fix every listed problem (a stale
`baseValue` means the configuration changed; re-read it). Then call `create_experiment`. Tell the
user exactly what will happen: who is affected, what changes for them, and when it starts.

## Terminating an experiment

`terminate_experiment({ experimentId, experimentName, reason })`:

- Takes effect immediately: every unit goes back to the base configuration on its next fetch.
- Releases the experiment's path locks, so those keys can be edited again.
- Cannot be undone. A follow-up needs a new experiment.
- `experimentName` must be the exact name from `get_experiment`. It guards against ending the
  wrong one.

To **ship the winning group**, terminate the experiment and then apply the winner's changeset to
the base configuration with a configuration update (only after termination releases the locks).
Say both steps up front.

## Changing the rollout

Load the experiment-rollouts skill for the full rollout guide: the curve, presets, reading the
rollout state, and which action fits a request. In short:

`update_experiment_rollout({ experimentId, experimentName, action, percent?, steps?, reason })`
works on scheduled or active experiments. Read the current rollout from `get_experiment` first.
The rollout follows a smooth curve from its last manual value through each scheduled step, so it
rises gradually between steps rather than jumping at them.

| `action` | Effect |
| --- | --- |
| `set` | `percent` (and only `percent`) becomes the rollout from now. Raising it drops pending steps it already meets; lowering it clears the remaining schedule. `0` stops new enrollment. |
| `advance` | Jumps to the next scheduled step now. Not while paused. |
| `pause` | Holds the current percentage; scheduled steps wait. |
| `resume` | Continues; remaining steps move later by however long it was paused. |
| `replaceSteps` | Replaces the remaining schedule with `steps` (and only `steps`): never below the current percentage, after now, before the experiment ends. Not while paused. |

- It never moves an enrolled unit. To take people out, terminate the experiment (everyone) or
  `assign_experiment_unit` with `unenroll` (one unit).
- Takes effect on the next SDK request. Say what it goes from and to.
- `experimentName` is a confirmation, as for terminate.

## Changing one unit

`assign_experiment_unit({ experimentId, action, unitType, distinctId, groupId?, reason })` works
on scheduled or active experiments. `unitType` must match the experiment.

| `action` | Effect |
| --- | --- |
| `assign` | Pins the unit to `groupId`, overriding its automatic group. `ignoreTargeting: true` pins it even if it does not match the targeting; `ignoreExclusion: true` pins it even if it is held by an exclusive experiment. |
| `clear_override` | Removes a pin; the unit goes back to its automatic group. |
| `unenroll` | Takes the unit out of the experiment; it gets the base configuration. |
| `reactivate` | Undoes `unenroll`. `ignoreExclusion: true` re-activates it across an exclusion conflict. |

Typical uses: putting a QA tester or developer in a specific group, or excluding a player who
should not see the change. Check the unit's current state with `list_experiment_members` first.
Changes apply on the unit's next configuration fetch.

## Errors

| `code` | Meaning | What to do |
| --- | --- | --- |
| `invalid_definition` | The definition breaks a rule (weights, paths, stale `baseValue`, targeting) | Fix what the message names; re-read the configuration for stale values |
| `path_locked` | Another experiment owns a changed path (`conflicts` names it) | Tell the user; that experiment must end first |
| `exclusion_conflict` | Assigning or re-activating the unit would cross an exclusive experiment's boundary | Tell the user which experiment holds the unit; use `ignoreExclusion` only if they insist |
| `name_taken` | Another experiment has the name | Pick a new name |
| `name_mismatch` | `experimentName` does not match the id | Confirm which experiment the user means |
| `already_terminated` | Nothing to terminate | Say so |
| `invalid_request` | Wrong unit type, group not in the experiment, experiment not running, or a rollout action that does not apply (e.g. advance with nothing scheduled) | Fix the input |
| `disabled` | The project is not on this experiments system | Tell the user |
| `forbidden` | This connection can't make the change (missing write context) | Tell the user to make it in the dashboard |
