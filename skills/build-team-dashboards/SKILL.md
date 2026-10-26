---
name: build-team-dashboards
description: "Playbook for building a project's first or missing dashboards from the events it actually sends: engagement, retention, and (when the data exists) economy and monetization boards, each chart run and checked before it's saved. Load when the user wants dashboards built, or asks what they should be tracking on a board."
---

# Build team dashboards

An approach, not a script. Build what the user asked for. When they ask for "dashboards" in
general, build a small set that answers each team's questions with the events this project
actually sends. Load `manage-dashboards` for the save and ordering rules.

1. `list_dashboards` with `includeQueries`, and `list_event_types`. Don't duplicate a board that
   exists: extend it.
2. Decide the boards from the data. For a game:
   - **Engagement**: active players, sessions per player, session length, the core-loop event
     per player.
   - **Retention**: day-1, day-7, and day-30 retention, plus a new-player funnel through the
     first-session steps you can find (tutorial and first core-loop action).
   - **Economy** (only with currency events): earned against spent by currency, top sources and
     sinks.
   - **Monetization** (only with purchase events): revenue, paying players, prompt-to-purchase
     conversion, top products.
   For a project that isn't a game, pick the boards from its own events: activity, retention, and
   the conversion its most important events describe.
   Tell the user which boards and charts you'll build before building more than one board.
3. Build each chart's spec, run it, and check the result is non-empty and sensible before saving.
   Drop or fix any chart with no data. Lines for trends, a single number for KPIs, a funnel for
   funnels.
4. Save each chart as a query and create each board with its queries, then lay it out (see
   `manage-dashboards` for sizes): a top row of four 6×4 KPI panels, then the trend charts (16×9
   or 12×8 side by side), then tables. Add a 24×1 section heading (`add_heading_panel`) between
   sections on a long
   board. Give every query and board a description, and each board an icon and color (Engagement
   `activity`, Retention `repeat`, Economy `coins`, Monetization `badge-dollar-sign`).
5. When you build more than two boards, put them in one folder (for example "Team dashboards")
   with `create_dashboard_folder` and `move_dashboard`, unless the project already organizes its
   dashboards differently (`list_dashboard_folders`).
6. Finish with the boards and the one insight that stood out while building them.
