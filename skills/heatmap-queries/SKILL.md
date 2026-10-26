---
name: heatmap-queries
description: "Full reference for heatmaps: the difference between a heatmap (the map definition on the Data page) and a heatmap query (a chart that counts an event's positions on that map), the spec, fetching the map image, saving heatmap queries, and how to read hotspots. Load to build, read, save, or explain anything heatmap."
---

# Heatmaps and heatmap queries

"Heatmap" means two different things in Gamebeast. Keep them apart — users mix them up, and the tools take different ids.

| | **Heatmap** (map definition) | **Heatmap query** |
|---|---|---|
| What it is | A region of the game world: two corner points, a resolution, and a top-down background image | A chart: one event's recorded positions counted per cell of a heatmap |
| Who creates it | The game, through the Roblox SDK (the Studio plugin). Agents cannot create one | Users in the query builder, or you with `create_heatmap_query` |
| Where users see it | Data page → **Heatmaps** tab (rename, re-describe, delete, preview the image) | On dashboards and in the query builder, like any other saved query |
| Id | a UUID string (`list_heatmaps`) | a numeric saved-query id (`list_queries`) |
| Tools | `list_heatmaps`, `get_heatmap_image` | `run_heatmap_query`, `create_heatmap_query`, `update_heatmap_query`, `get_query`, `execute_query`, `delete_query` |

One heatmap can back many heatmap queries ("deaths on Arena", "pickups on Arena", "deaths on Arena for new players").

## The heatmap (map definition)

`list_heatmaps` returns each heatmap's `id`, `name`, `description`, `bounds`, `resolutionFactor`, and `hasImage`.

- `bounds` is `{ pointA: {x, y, z}, pointB: {x, y, z} }` — two opposite corners of the region in world studs. The map is **top-down**: its horizontal axis is world **X** and its vertical axis is world **Z**. World Y (height) is ignored.
- `resolutionFactor` is studs per image pixel. A 1000-stud-wide region at resolution 2 has a 500-pixel-wide image.
- `hasImage: false` means the SDK has not uploaded a background yet. Queries still run; there is just no picture under the hotspots.

`get_heatmap_image` returns the background PNG (scaled down to at most 1024 px on its long edge) so you can see the layout — use it to name places ("the north bridge", "spawn") instead of quoting raw coordinates. It is the bare map only: hotspots are drawn by the chat or dashboard, not baked into the image.

## Spec shape

`run_heatmap_query` executes a spec; `create_heatmap_query` saves the same spec (see the manage-dashboards skill).

<!-- example:heatmap-spec -->
```json
{
  "time": { "step": "day", "relative": { "step": "day", "value": 30 } },
  "heatmapId": "3f0c2a6e-8a3b-4a5e-9c1d-1b2c3d4e5f60",
  "metrics": [
    {
      "id": "m1",
      "visible": true,
      "data": { "name": "player_death", "type": "event", "measurement": { "math": { "function": "count" } } },
      "display": { "name": "Deaths" }
    }
  ]
}
```

- `heatmapId` — the heatmap's UUID from `list_heatmaps`. Never a saved-query id.
- `metrics` — **exactly one** event. Its `data.name` must match an event from `list_event_types`, and that event must record a position (the SDK's `position` argument / property). Events without positions produce an empty heatmap.
- `measurement` — use one of the two the query builder offers for heatmaps:
  - every event per cell (the default): `{ "math": { "function": "count" } }`
  - distinct players per cell: `{ "math": { "function": "unique" }, "perPlayerAggregation": "count" }`

  Write `count`, never `total`: `total` is the cohort spelling, and the query builder shows a blank aggregation for it.
- `data.filter` narrows the event: `{ "operation": "and", "conditions": [ …filters… ] }`. For example, only deaths whose `cause` argument is `"fall"`:

<!-- example:filter -->
```json
{ "data": { "name": "cause", "type": "argument", "dataType": "string",
            "condition": { "string": { "operation": "Is", "value": ["fall"] } } } }
```

- `filters` — optional global filters, same shapes as insight filters (property, argument, user, cohort, experiment). A New User filter shows where new players struggle:

<!-- example:filter -->
```json
{ "data": { "name": "New User", "type": "user", "dataType": "user", "condition": { "boolean": true } } }
```

- `time` — **default to the last 30 days** when the user does not say. The `step` does not split the map (a heatmap is one layer for the whole window); `day` is fine.

Not supported: breakdowns, a second metric, custom bounds, or a different resolution. Bounds and resolution always come from the heatmap. To compare two segments, run two queries (one per filter) and compare their hotspots.

## Reading results

You get a compact summary, not every cell:

- `grid` — `{ columns, rows, cellSize, bounds: { minX, maxX, minZ, maxZ } }`; `cellSize` is the width of one cell in studs. `null` when nothing was recorded.
- `aggregates` — `{ sum, maximum, minimum, average, median }` over the non-empty cells. `sum` is the total count on the map.
- `nonEmptyCells` — how many cells recorded anything.
- `concentration` — `{ cells, share }`: the percent of `sum` held by the busiest `cells` cells.
- `hotspots` — the busiest cells, highest first: `{ x, z, value, share }`. `x` and `z` are the **world** coordinates of the cell centre; `share` is that cell's percent of `sum`.

How to analyse it:

- Say where activity concentrates, and how concentrated it is: "the top 10 cells hold 40% of all deaths" (`concentration`) is more useful than one coordinate.
- Match hotspot coordinates to places using the bounds and, where you have it, `get_heatmap_image`.
- An empty result (`sum` 0) usually means the event has no positions, the positions fall outside the bounds, or the time window is empty — say which you suspect.
- The chat and the dashboard draw a smoothed density layer over the map, so the user sees the hotspots. Don't read cells out one by one.

<!-- shared:after-adhoc-chart -->
## After you show a chart

When you show the user a new ad-hoc chart, end your reply with one short offer to take it further: adjust it (a different time range, a filter, a breakdown, or a segment such as new players), or save it so it stays current, on an existing dashboard or a new one. If you have the create tool for its query type, offer to save it yourself (see the manage-dashboards skill) and save only once the user agrees. If you don't, point to the chart's **Add to dashboard** action in the Gamebeast assistant. Skip the offer when the chart is one step in a bigger answer, and leave it to the caller when you are building the chart for another agent.
<!-- /shared:after-adhoc-chart -->

## Saved heatmap queries

- `execute_query` runs a saved heatmap query by id, with an optional `time` override (breakdown overrides do not apply).
- `get_query` returns an editable `spec` with `queryType: "heatmap"`; pass the changed spec to `update_heatmap_query`. A query that overrides bounds or uses breakdowns comes back `notEditable` — tell the user to edit it in the query builder.
- Deleting a heatmap on the Data page breaks every heatmap query that uses it. Agents cannot delete heatmaps.

## Common errors

- Passing a saved-query id (a number) or a heatmap's name as `heatmapId` — use the UUID from `list_heatmaps`.
- More than one metric, or a breakdown.
- `"function": "total"` — runs, but opens in the query builder with no aggregation. Use `count`.
- An event that has no position data.
- Telling the user to "create a heatmap" with a tool — heatmaps are created in-game with the SDK; point them to the Heatmaps docs.
