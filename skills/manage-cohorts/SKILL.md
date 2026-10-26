---
name: manage-cohorts
description: "Create, edit, describe, and delete saved cohorts (player segments) with create_cohort, update_cohort, and delete_cohort. Load before any cohort write."
---

# Manage cohorts

Use this skill when the user asks to save a cohort, rename it, write or change its description, change who is in it, or delete it. For the definition AST itself (blocks, groups, conditions, `All time`), load the `cohorts` skill.

## Permissions and approval

- All three tools need the **`cohorts:write`** permission. If they are not in your tool list, the user (or this connection's token) cannot change cohorts — tell them, and do not try another route.
- Every call is a real write. In the Gamebeast assistant the user approves or denies each call on a card; over MCP the client asks for confirmation. Always pass a one-sentence `reason` the user will read.
- Only propose a write when the user asked for it or agreed to your suggestion. Never claim it happened until the result says `created`, `updated`, or `deleted: true`.

## Before you write

1. **Check what exists.** Call `list_cohorts` (with `search`) first. Names are unique per project — creating a duplicate fails with a `conflict`. If a matching cohort exists, offer to update it instead.
2. **Dry-run new definitions.** Run the definition with `run_cohort_definition` and tell the user the member count before you save it (or change a saved cohort's definition). A count of 0 usually means a wrong event name or filter — fix it before saving. Pass a `description` to `run_cohort_definition` too: in the Gamebeast assistant it pre-fills the **Save Cohort** dialog.
3. **Resolve nested references.** A nested cohort condition uses the referenced cohort's numeric id as a string; look it up with `list_cohorts`. A cohort cannot reference itself. Deeplink and experiment conditions likewise take numeric ids as strings — look them up first; an experiment must be a user-unit v2 experiment, and any `groupIds` must be its own groups. A funnel condition takes a saved funnel query's id (`list_queries`) and, optionally, one of its step ids in `metric.step`.

## create_cohort

```json
{
  "reason": "Save the lifetime repeat-buyer segment the user asked for.",
  "name": "Repeat buyers (5+ purchases ever)",
  "description": "Players who have made at least 5 purchases since the game launched. Used to target loyalty offers.",
  "definition": [[{ "operator": "and", "conditions": [ { "...": "see the cohorts skill" } ] }]]
}
```

Returns `{ created: true, cohort: { id, name, description } }`.

**Always include a `description`**, even when the user didn't ask for one: write it yourself from the definition (see [Writing good descriptions](#writing-good-descriptions)). A cohort saved without one is hard for teammates to reuse.

## update_cohort

Partial: pass `cohortId` plus only the fields to change. Omitted fields keep their current value.

- **Describe only:** `{ "cohortId": 42, "description": "...", "reason": "..." }` — the way to document existing cohorts.
- **Clear a description:** `"description": null` (or `""`).
- **Rename:** `"name": "..."` (must stay unique).
- **Change membership rules:** `"definition"` replaces the whole saved definition. Start from `list_cohorts` (`cohortId` set) — its `definition` — change only what the user asked for, and dry-run it with `run_cohort_definition` first. If the saved description no longer matches the new rules (or there is none), pass an updated `description` in the same call.

Changing a definition changes membership everywhere the cohort is used: saved queries, dashboards, and experiment targeting. Say so on the approval reason when the cohort is in use.

Returns `{ updated: true, cohort, changes }`.

## delete_cohort

`{ "cohortId": 42, "reason": "..." }`. Destructive and permanent.

- **Blocked while an active or upcoming experiment targets the cohort.** The error names the experiments; tell the user to end them or change their targeting first.
- Saved queries and other cohorts that reference a deleted cohort keep the reference but it becomes unresolved (`metric.unresolved: true`) — mention this before deleting a cohort others depend on.
- Confirm the exact cohort by name with the user before proposing a delete.

## Writing good descriptions

- Say **who is in it** in plain language, including the time window: "Players who purchased at least 5 times, ever." beats "Whales."
- Add **what it is for** when known: "Used for the VIP-offer experiment."
- One or two sentences, max 1000 characters. No raw JSON, ids, or marketing language.
- When describing many existing cohorts, read each definition with `list_cohorts` (`includeDefinitions: true`) and describe what it actually does — do not guess from the name.

## Errors

| `code` | Meaning | What to do |
|--------|---------|-----------|
| `not_found` | No cohort with that id in this project | Re-check with `list_cohorts` |
| `conflict` | Name taken, or delete blocked by an experiment | Pick another name / explain the blocking experiments |
| `invalid_definition` | Definition rejected (bad nesting, cycle, empty group) | Fix the definition and dry-run it again |
| `invalid_request` | Nothing to change | Pass at least one field |
| `forbidden` / `unavailable` / `failed` | Not allowed here, or a transient failure | Do not retry in a loop; tell the user |
