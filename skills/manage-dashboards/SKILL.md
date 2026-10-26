---
name: manage-dashboards
description: "Create, edit, lay out, organize, copy, and delete analytics dashboards and saved queries: saving an ad-hoc chart, editing a saved query's definition, placing and sizing panels on the grid, text panels, folders, and what each write keeps or deletes. Load before any dashboard or saved-query change."
---

# Manage dashboards and saved queries

## The model

- A **saved query** is one chart: a name, an optional description, and a definition (an insight, funnel, retention, or heatmap spec plus its chart type). Saved queries live in the project, independent of dashboards (`list_queries`).
- A **dashboard** is a name, a description, an optional icon (a lucide name like `chart-line`) and color (`#rrggbb`), and a set of **panels** on a **24-column grid**. Rows are about 30px tall. Each panel has an `id` and a box `{x, y, w, h}` in grid units.
- Panel types: **query** (one saved query's chart), **heading** (a one-line plain-text section title, no card), **markdown** (a card of notes), and **image** (an uploaded picture — agents can reference existing images but not upload new ones).
- The grid compacts vertically: panels float up into empty space, and a panel placed on top of another pushes it down. The server does this on every write, so read back the layout the tool returns rather than assuming your request landed exactly.
- "Order" means **reading order**: top-to-bottom, then left-to-right. `get_dashboard`'s `queries` list is the query panels in that order.
- Dashboards can live in **folders** (nested up to 6 levels). The folder tree and its order are shared by the whole project. Pins and each user's private sidebar order are personal settings; agents don't change them.
- One query can appear on **several** dashboards. Editing it changes it everywhere it appears.
- Dashboards and queries belong to the project, not to an environment.
- A **heatmap query** is a saved query too. The **heatmap** it draws on (the map definition on the Data page, from `list_heatmaps`) is not — agents cannot create, edit, or delete heatmaps, only the queries that use them. See the heatmap-queries skill.

| You want to… | Use | What happens |
|---|---|---|
| Save a chart you just built | `create_insight_query` / `create_funnel_query` / `create_retention_query` / `create_heatmap_query` (with `dashboardId` to put it on a dashboard) | a new saved query |
| Change what a saved query measures | `get_query`, then `update_insight_query` / `update_funnel_query` / `update_retention_query` / `update_heatmap_query` | changes it on every dashboard |
| Rename a saved query, or change its description | `update_query` | changes it on every dashboard |
| Put an existing query on a dashboard | `add_query_to_dashboard` | the query is shared, not copied |
| Take a query off one dashboard | `remove_query_from_dashboard` | the query is **kept** |
| Delete a query everywhere | `delete_query` | removed from **every** dashboard |
| Reorder, or add/remove several at once | `update_dashboard` with the full `queryIds` list | queries left out are taken off, not deleted |
| Rename, re-describe, or restyle a dashboard | `update_dashboard` with `name` / `description` / `icon` / `color` | — |
| Move or resize panels | `get_dashboard`, then `update_dashboard_layout` | the server compacts and returns the final layout |
| Add a section heading | `add_heading_panel` with plain `text` | a heading panel |
| Edit a section heading | `update_heading_panel` | — |
| Add a note explaining nearby charts | `add_markdown_panel` | a text panel |
| Edit a text panel | `update_markdown_panel` | — |
| Take any panel off | `remove_panel` with its `panelId` | a query panel's saved query is **kept** |
| New dashboard | `create_dashboard` (optionally in a `folderId`) | empty, or with existing `queryIds` |
| See or organize folders | `list_dashboard_folders`, `create_dashboard_folder`, `update_dashboard_folder`, `move_dashboard` | — |
| Delete a folder | `delete_dashboard_folder` | its dashboards and subfolders move **up** a level; nothing else is deleted |
| Copy a dashboard | `duplicate_dashboard` | its queries are copied too, so the copy can be edited independently |
| Delete a dashboard | `delete_dashboard` | the dashboard goes; its queries are **kept** |

Every write asks for a `reason` — one sentence the user reads before approving.

## Saving an ad-hoc chart

1. Build and run the chart first (`run_insight_query`, `run_funnel_query`, `run_retention_query`, or `run_heatmap_query`) so you know it works and the user has seen it.
2. Pass the **exact spec you ran** to the create tool for its query type: an insight spec to `create_insight_query`, a funnel spec to `create_funnel_query`, a retention spec to `create_retention_query`, a heatmap spec to `create_heatmap_query`. A chart's result carries the spec as `savableSpec`, tagged with its `queryType` — that tag tells you which tool to call; the spec you pass does not need it. For example, `create_insight_query` with this `spec`:

<!-- example:insight-spec -->
```json
{
  "time": { "step": "day", "relative": { "step": "day", "value": 30 } },
  "metrics": [
    {
      "visible": true, "id": "m1",
      "data": { "name": "session_start", "type": "event",
                "measurement": { "math": { "function": "unique" }, "perPlayerAggregation": "count" } },
      "display": { "name": "Daily active players", "unit": "User" }
    }
  ],
  "display": "line"
}
```

3. Name it after what it measures ("Daily active players"), without the time range — the dashboard can change the range.
4. **Always write a `description`**, even when the user didn't ask for one (see [Writing descriptions](#writing-descriptions)).
5. To put several new charts on a new dashboard: `create_dashboard` first (with its own description), then the create tool with its `dashboardId` for each chart, in the order they should appear.

The save tools check that the dashboard can draw the chart and reject it otherwise, with a message saying what to change:

- A `stacked_bar` chart needs at least one breakdown — use `bar` without one.
- An experiment breakdown is numeric: give it `"dataType": "number"`.

<!-- example:breakdown -->
```json
{ "data": { "name": "Summer Pricing", "type": "experiment", "dataType": "number",
            "experiment": { "version": "v2", "level": "group", "experimentId": 42 } } }
```

Relative time ranges keep a saved chart current ("last 30 days" always means the latest 30 days); prefer them over absolute dates unless the user wants a fixed period.

## Editing a saved query

1. `get_query` returns its definition as an editable `spec`, plus the dashboards it appears on. If it returns `notEditable` instead, the query uses options agents cannot author — tell the user to edit it in the query builder.
2. Change only what the user asked for, and keep everything else as it was.
3. Run the changed spec (`run_*_query`) to check it, then pass the **complete** spec to the update tool for its query type (`get_query`'s `queryType` says which: `update_insight_query`, `update_funnel_query`, `update_retention_query`, or `update_heatmap_query`). It replaces the saved definition; the query type cannot change (create a new query instead). To only rename it or change its description, use `update_query`.
4. If the saved description no longer matches what the query measures, or there is none, pass an updated `description` in the same call.
5. Say which dashboards will show the change.

## Laying out a dashboard

`get_dashboard` returns every panel with its `id` and `{x, y, w, h}`. To change the layout, pass the boxes you want to `update_dashboard_layout`; panels you leave out keep theirs. Sizing guide:

| Panel | Size (w×h) | Fits per row |
|---|---|---|
| KPI / single number | 6×4 | 4 |
| Two charts side by side | 12×8 | 2 |
| Wide trend chart | 16×9 (or 24×9 full width) | 1, with an 8-wide table or note beside it |
| Table | 8×9 | 3 |
| Section heading (`heading` panel) | 24×1 | 1 |
| Note explaining nearby charts (`markdown` panel) | 6×8 | — |

- Put KPIs in the top row, then the charts that explain them. Separate sections with a heading panel rather than a gap.
- Keep each row's widths adding up to 24 so the board has no ragged edges.
- New query panels default to 12×8, appended in reading order. `add_query_to_dashboard` takes a `gridPos` to place and size one directly, or a `position` to insert it among the query panels (0 = first).
- `update_dashboard` with the full `queryIds` list still reorders query panels (they trade places, keeping their sizes) — use it when only the order matters.
- Markdown renders headings, lists, bold/italic, links and tables. Raw HTML and images from other websites are dropped.

## Folders

- `list_dashboard_folders` shows the tree with each folder's path and dashboards. Check it before creating a folder so you don't make a duplicate.
- Name folders after the team or question ("Economy", "Live ops", "New players"), not after dates. Don't nest deeper than you need — two levels is usually plenty.
- `move_dashboard` puts a dashboard in a folder (`folderId: null` = top level) and/or at an `index` among its siblings. `update_dashboard_folder` renames or moves a folder; it refuses moving a folder into itself or past 6 levels.

## Writing descriptions

Every query and dashboard you create gets a `description`, even when the user didn't ask for one. Write it yourself from the spec. Without one, teammates have to open the chart to work out what it shows.

- **Query:** say what it measures and how, in plain language: the event or events, the aggregation, and any filter, cohort, or breakdown that changes its meaning. For example: "Unique players who completed a purchase each day, split by new vs returning players." Leave out the time range (the dashboard can change it).
- **Dashboard:** say what question it answers and who it is for. For example: "Daily health of the new-player funnel: tutorial completion, first purchase, and day-1 retention."
- One or two sentences, at most 1000 characters. No raw JSON, ids, or marketing language.
- When you change what a query or dashboard shows, update its description if it no longer matches.

## Etiquette

- Only propose a write the user asked for or agreed to. Confirm dashboards and queries by **name** before changing or deleting them, and never guess an id.
- Check `list_dashboards` before creating one — dashboard names are unique in a project.
- Prefer the smallest change: remove from one dashboard rather than deleting, update rather than delete-and-recreate.
- After a write succeeds, tell the user where to find the result (the dashboard's name).
