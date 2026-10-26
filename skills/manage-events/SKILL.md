---
name: manage-events
description: "Describe analytics events (markers) and their arguments, and hide or show them in the query builder — including events the game does not send yet. Load before calling describe_event_types."
---

# Manage events

Use this skill when the user asks to document, describe, rename-for-humans, hide, or show analytics events (markers) or their arguments — or when you are setting up Gamebeast tracking for a game and want the dashboard to explain the events you are adding.

## The model

Every marker type, and every argument on a marker type, can carry two pieces of metadata per project **environment**:

- **description** — plain text (max 1000 characters) shown in the dashboard's Markers page, the query builder, and returned by `list_event_types`.
- **hidden** — hides the event or argument from query-builder listings. The data is still ingested and queryable; this only declutters pickers.

Metadata is keyed by the exact, case-sensitive marker/argument name. It does **not** require the event to have been sent: you can describe an event before the game ships the code that sends it. Until data arrives, such events appear in `list_event_types` under `pendingEventTypes` and in the dashboard under "Awaiting data". When the first event with that name arrives, the description is already attached.

Metadata is per environment. Describing an event in development does not describe it in production — make the call in each environment you set up.

## Setup flow: instrument, describe, send

When helping a studio add tracking:

1. Decide the event names and arguments with the user (or read them from their code).
2. Call `describe_event_types` with a description for each new event and each meaningful argument.
3. The studio ships the instrumentation. Data starts flowing and lines up with the descriptions — no window where events show up undocumented, and no need to wait for data before documenting.

## describe_event_types

One call applies one atomic batch: up to 100 marker types and 500 arguments.

```json
{
  "reason": "Document the new shop funnel events before the update ships.",
  "types": [
    { "markerType": "ShopOpened", "description": "Player opened the in-game shop UI." },
    { "markerType": "DebugTick", "hidden": true }
  ],
  "arguments": [
    {
      "markerType": "ShopOpened",
      "argumentName": "source",
      "description": "Where the shop was opened from: 'hud', 'npc', or 'prompt'."
    }
  ]
}
```

Rules:

- **Partial updates.** Omit a field to leave it unchanged. `{ "markerType": "X", "hidden": true }` keeps X's description.
- **Clearing.** Pass `"description": null` (or an empty string) to remove a description.
- **Exact names.** Names are case-sensitive. Check `list_event_types` (both `results` and `pendingEventTypes`) before describing an existing event, so you do not create metadata for a misspelled twin.
- **Batch related changes.** Put every change for a request in one call — the user approves one card.

## Writing good descriptions

- Say **when it fires** and **what it means**: "Fired once when a round ends, win or lose." beats "Round end event."
- For arguments, give the unit or allowed values: "Seconds since the round started.", "One of 'wood', 'stone', 'gold'."
- Keep it to one or two sentences. No marketing language.

## Reading metadata back

- `list_event_types` returns `description` on each event and on each of its arguments, plus `pendingEventTypes` for described events with no data yet.
- Arguments with `pending: true` are described but not seen on that event yet.
