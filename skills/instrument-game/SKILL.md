---
name: instrument-game
description: "Playbook for instrumenting a game or app with Gamebeast: design a tracking plan of events and the tuning values worth moving into a remote configuration, hand the code changes to a coding agent (or make them, if you can edit the code), and verify each event against live data and each value against the config. Load when the user wants to set up or extend their analytics events, make their game tunable or experiment-ready, or asks what they should track."
---

# Instrument a game

An approach, not a script: start from what the user asked and what the project already sends,
and skip the steps that don't apply. If they only want a handful of events, design those.

The outcome to aim for: the project sends the events the studio needs to answer its core
questions, each one is documented in Gamebeast before it ships, and each one is verified against
real data. Where the project has values a studio would want to tune (prices, rewards, drop rates,
timers, feature switches), they live in a remote configuration the code reads through the SDK,
so they can be changed — and experimented on — without a new build. Events tell the studio what
happened; configuration values are what it can change in response. Experiments need both.

Work out which surface you are on first:

- **You can't edit the project's code** (the Gamebeast assistant in the dashboard): Part A.
- **You can edit the code** (a coding agent with the repo open, or connected to Roblox Studio,
  Unity, or an Unreal Engine or Godot project): Part B.

## Part A — design the plan and hand it off

1. Read what exists: `list_event_types` (both `results` and `pendingEventTypes`) and
   `get_tracking_plan` with no id. An open plan may already exist; continue it rather than
   starting another. The platform is in the project context (Roblox, Unity, Unreal, Godot,
   Discord, JavaScript, or none). Discord and JavaScript projects are often not games: design for what the project
   actually is.
2. Work out what the project is from its name, its data, and what the user said. If you can't
   tell what a typical session looks like, ask that one question. Never ask for event names:
   designing them is your job.
3. Design the events, usually 8–20. For a game, cover what applies, in this order:
   - **Core loop**: the action players repeat (round started/ended, level started/completed).
   - **Progression**: level ups, unlocks, tutorial steps (`TutorialStep` with a `step` number).
   - **Economy**: currency earned and spent, with `currency`, `amount`, and `source` or `sink`.
   - **Monetization**: purchase prompted / completed with product id and price.
   - **Social**: invites, party joins, trades.
   For anything else, start from the questions the user wants answered and design the fewest
   events that answer them. Skip what the SDK already sends by default (sessions, logins,
   playtime — check `search_docs` for the platform's default markers). Use PascalCase names.
   Give every property a type, and give numbers a unit.
4. **Tuning values.** Alongside the events, list the values worth making remote: the ones the
   events measure and a studio would change after launch (currency rewards and prices, round
   length, cooldowns, spawn and drop rates, difficulty, feature switches). Usually 5–15. Group
   them into folders by area (`economy`, `progression`, `rounds`, `features`) with camelCase
   keys. You can't see the code, so these are proposals: the coding agent finds the real
   hardcoded values and their current numbers. Skip this step when the user only asked for
   events, and for projects with nothing to tune.
5. `create_tracking_plan` with the events, each with a description, rationale, placement hint,
   and typed properties. Then `describe_event_types` with the same descriptions (load
   `manage-events`), so the dashboard explains each event before the first one arrives. When
   the plan is large or the user hasn't seen your approach yet, show it with `propose_plan`
   first, if you have it. If you planned tuning values, save them too (load
   `understand-configurations`): `create_configuration` named `Game tuning (proposed)` with
   the keys set to your best-guess defaults, then `update_configuration_descriptions` with what
   each one controls. A new configuration is never primary, so nothing reaches players. End the
   plan's `summary` with "Tuning values: see the Game tuning (proposed) configuration." so the
   coding agent finds them.
6. Tell the user, in two sentences, what the plan covers and that **Implement with…** on the
   plan card sets up their coding agent (Cursor, Claude Code, Codex, Roblox Studio, Unity,
   Unreal Engine, Godot, or any MCP client). Don't paste code for them to copy unless they ask: a
   coding agent can make the edits and check its own work.
7. When the user comes back, or events arrive, call `get_tracking_plan`. For every item that is
   `received` or `verified`, check its properties with `get_property_values`. Report mismatches
   (a missing property, or a wrong type, such as a price sent as a string) as one fix list.
   If tuning values were planned, check the configuration the game reads (load
   `understand-configurations`): the keys exist, each has a description, and the values look
   like the game's real numbers.
8. When the required items are verified, offer starter dashboards (load `manage-dashboards`)
   built from the events that arrived. If the game now reads tuning values, say what that
   unlocks: a change can ship as an experiment (load `manage-experiments`), or go through the
   `tune-economy` or `launch-liveops-event` playbooks.

## Part B — implement the plan in the code

1. `get_tracking_plan` (the plan id you were given, or omit it for the latest open plan). Read
   every item before touching code.
2. **SDK key.** Look for an existing Gamebeast key first: `.env*` files, secret or config
   modules, CI variables, an existing `Gamebeast:Setup({ key = ... })` (Roblox) or
   `GamebeastSdk.Setup(...)` (Unity) call, or on Unreal a `UGamebeastSubsystem` `Setup` call or
   an `ApiKey` under `[/Script/Gamebeast.GamebeastSettings]` in `Config/*Game.ini`, or on Godot a `Gamebeast.setup(...)` call or
   `gamebeast/general/api_key` in `project.godot`. Reuse it if
   you find one. Only if there is none, call `ensure_sdk_key` with a reason, and store the key where its `storageGuidance` says. On Roblox
   that means server-side only (ServerScriptService or ServerStorage), never in a LocalScript or
   ReplicatedStorage. Never print it in chat, and never commit it to a public file.
3. **SDK.** If the SDK isn't installed, use `search_docs` and `read_doc` for the platform's
   install guide, and install it the way the project already manages dependencies (Wally or Rojo
   packages, a Toolbox model in Studio, the Unity package manifest, the Unreal project's
   `Plugins/` folder, the Godot project's `addons/` folder, npm). Initialize it once, on the server where the platform has one.
4. **Events.** For each item, find the code that matches its placement hint and add the marker
   call with exactly the planned name and properties. Send numbers as numbers. Don't duplicate
   default markers. Put shared values (like a currency enum) in one place.
5. After each event, call `update_tracking_plan_items` with `implemented` and the file or script
   path you changed.
6. **Tuning values** (skip if the plan has none and the user didn't ask). Load
   `understand-configurations` first.
   - Read the plan's summary. If it points at a proposed tuning configuration, read it with
     `get_configuration`: those are the keys to wire.
   - Find each value in the code: the planned ones, plus obvious constants next to the events
     you just wired (a reward amount beside `CurrencyEarned`, a price beside
     `PurchaseCompleted`). Note its current value. Prefer values that already sit in one place
     (a constants or settings module); don't pull every literal out of the codebase.
   - `list_configurations` to see what exists. Roblox reads only the primary configuration, so
     add the keys there. Unity, Unreal, Godot and JavaScript read a configuration by its alias, so a
     dedicated one (for example `game-tuning`) is fine; create it with `create_configuration` if it doesn't
     exist. If the project has no primary configuration yet, create one and ask the developer
     before calling `set_primary_configuration`. Move the proposed keys into the configuration
     the game reads (with the code's real values), then offer to delete the proposed one with
     `delete_configuration`.
   - Add the keys with `update_configuration`, set to the values the code uses today, so
     switching the code over changes nothing for players. Saving the primary configuration
     pushes it to game servers immediately; new keys are harmless (nothing reads them yet), but
     say so. Describe every key with `update_configuration_descriptions`: what it controls, its
     unit, and a sane range.
   - Change the code to read each value through the SDK (`search_docs` and `read_doc` for the
     platform's configs API: `Configs:Get` on Roblox, `Configs.Get` on Unity,
     `GetConfigs()->GetFloat` and the other typed getters on Unreal,
     `Gamebeast.configs.get_float` and the other typed getters on Godot, `configs.get` in
     JavaScript). Keep the current value as the fallback for when the configuration hasn't
     loaded or the key is missing, so the game behaves the same offline or on an old config. On
     Roblox, read on the server for anything players could exploit (prices, rewards); use the
     SDK's change callback (`:Observe` / `:OnChanged`) where a value should update live.
   - Don't write experiment logic into the code: the SDK already returns each player's
     experiment group values from the same calls.

7. **Verify.** Run the project if you can: in Roblox Studio, start a playtest, trigger each flow,
   and read the console for SDK errors. If you can't run it, ask the developer to play through
   the flows (an Unreal Play In Editor session, or a Godot project run from the editor, reports to
   development). Then
   `list_event_types` and `get_property_values` for each event. Mark an item `verified` only
   once the data matches the plan; otherwise mark it `mismatch` with a note, fix the code, and
   check again. For tuning values, change one in the development configuration,
   confirm the running game picks it up, then set it back.
8. Finish with a short summary: the files changed, the events verified, the configuration keys
   added (with their paths), and anything still waiting (for example, purchase events that need
   a real purchase to fire, or copying the configuration to production from its **⋯** menu once
   the build ships).

Verification happens in the environment the connection is pinned to, normally development.
Studio playtests report there. Production events arrive after the game is published.
