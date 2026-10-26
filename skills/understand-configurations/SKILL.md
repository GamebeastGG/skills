---
name: understand-configurations
description: "Navigate, read, and search remote configurations — large JSON blobs rendered as a file tree in the dashboard."
---

# Understand configurations

Use this skill when the user asks about configuration values, config structure, where a key is set, what a setting does, or any question that requires reading config data.

## Mental model

A configuration is a single JSON object stored per project+environment. The Gamebeast dashboard renders it as a **file tree**:

- **Nested objects** → **folders** (you can drill into them)
- **Arrays and primitives** → **files** (leaf values)
- Paths are expressed as a **segments array**, e.g. `["settings", "ranked"]`

The **primary configuration** is the one SDKs receive. Other configurations exist and can be checked — check `isPrimary` in the list result.

Configurations can be very large (thousands of keys, deep nesting). **Never try to load a whole config at once.** Navigate progressively using the workflow below.

## Tool workflow

### 1. Discover what exists

```
list_configurations
```

Returns all configs with: id, name, alias, isPrimary, structure summary (topLevelKeys, totalNodes, maxDepth).
Use `search` to filter by name. Check `isPrimary` to identify the live config the SDK uses.

### 2. Explore structure (file-tree outline)

```
get_configuration({ configurationId, mode: "structure" })
```

Returns a depth-3 file-tree outline — folder names, child counts, array lengths, primitive previews. **Always start here.** It is cheap regardless of config size.

To see deeper into a folder:
```
get_configuration({ configurationId, path: ["settings", "ranked"], mode: "structure", depth: 4 })
```

### 3. Read values for a specific subtree

```
get_configuration({ configurationId, path: ["settings"], mode: "values" })
```

Returns actual values within a 20 KB budget. If the subtree is still too large, the response includes `truncatedPaths` — a list of dot-paths that were elided. Call again with a narrower `path` from that list.

**Never omit `path` for mode "values" on a large config** — always drill down to the relevant subtree first.

### 4. Find where a key or value is set

```
search_configuration({ query: "maxPlayers" })
// Across all configs in this environment

search_configuration({ query: "maxPlayers", configurationId: 42 })
// Just one config

search_configuration({ query: "^ranked", isRegex: true, target: "keys" })
// Regex on keys only

search_configuration({ query: "hard", target: "values", path: ["settings"] })
// Value search within a sub-folder

search_configuration({ query: "respawn", target: "descriptions" })
// Find a key by what its description says, when you don't know its name
```

Returns matches with their full `segments` path, key name, match type (key/value/description), and value preview.

## Path addressing

All paths are **string arrays** — the same format the frontend `?path=` URL uses:

- `[]` → root
- `["settings"]` → the "settings" folder
- `["settings", "ranked"]` → the "ranked" folder inside "settings"

The `deepLinkPath` in `get_configuration` responses is a ready-to-use URL fragment (`?path=["settings","ranked"]`) you can append to the configuration page URL to link the user directly to that node in the dashboard.

## Descriptions

Configurations and their keys can carry **descriptions** — documentation people (or you) wrote about what a key controls, its units, and valid ranges. `get_configuration` returns the configuration's `description` and the `keyDescriptions` within the subtree you read (each `{ path, description }`; structure mode limits them to the requested `depth`). Use them to interpret values before explaining or changing them, and prefer them over guessing from key names.

Descriptions are **metadata**: they are never sent to game servers and don't affect the `contentHash`.

## Privacy

Some keys are marked private (`_hidden: true` in values responses, or `hidden: true` on structure nodes). This means they are **hidden from game clients via the SDK** — they are NOT hidden from dashboard users. Feel free to read and reason about them; just mention the hidden flag when relevant so the user knows those values won't be exposed to players.

## Efficiency rules

- Always start with `list_configurations` to get ids and size signals.
- Always use `structure` mode first to understand the shape before reading values.
- Use `search_configuration` to find a key rather than expanding the entire tree.
- Use `path` to scope every `get_configuration` call — never read the root in values mode for a large config.
- If `truncatedPaths` is non-empty, pick the relevant path(s) and drill in with another call.

## Changing values (update_configuration)

Only when the user asks for a change or agrees to one you suggested. The call makes the change itself: it is not a draft or a proposal, and the change is saved when the call runs. Your `reason` is recorded with the change. In the Gamebeast assistant, the user approves each call on a card before it runs; other clients may ask the user to confirm the tool call. Either way, call the tool — don't route around it through the HTTP API.

1. Read the exact values you will change: `get_configuration({ configurationId, path, mode: "values" })` (or `search_configuration`). Keep the response's `contentHash`. `preview_configuration_change`, where available, is an optional dry run with the same validation.
2. Make one call per configuration with every related change in it:

```
update_configuration({
  configurationId: 42,
  reason: "Lower the ranked Elo gate from 100 to 80 so more new players reach ranked in their first week.",
  baseContentHash: "<contentHash from step 1>",
  changes: [
    { op: "set", path: ["settings", "ranked", "eloThreshold"], value: 80 },
    { op: "set", path: ["regions", "-"], value: "APAC" },          // "-" appends to an array
    { op: "set", path: ["weapons", 1, "damage"], value: 35 },       // numbers index arrays
    { op: "remove", path: ["events", "halloween2025"] }
  ]
})
```

Rules the tool enforces (it returns an error you can fix rather than failing silently):
- `set` overwrites an existing key or creates a new one, but the **parent must already exist** — to add a new folder, `set` the folder to an object first, in the same call, or set it with its full contents.
- `remove` needs the path to exist. Paths may not overlap (don't set `settings` and `settings.mode` together).
- **Private keys** (`_hidden` / `hidden`) can be edited like any other key — set the plain value, not the `{ _value, _hidden }` wrapper. They stay private after the change.
- **Making keys private or public** uses `privacy`, applied after `changes` (so a key added in the same call can be made private). `changes` may be empty for a privacy-only update. Each path must be an existing object key — not an array item or a key containing `.`. Private means hidden from game clients, not from dashboard users: use it for values clients shouldn't see (a random seed, server-only tuning), not as a secret store. Changing privacy changes what game servers receive, so on the primary configuration it goes live immediately.

```
update_configuration({
  configurationId: 42,
  reason: "Keep the loot seed server-side so clients can't predict drops.",
  baseContentHash: "<contentHash>",
  changes: [{ op: "set", path: ["loot", "seed"], value: 918273 }],
  privacy: [{ path: ["loot", "seed"], private: true }]   // private: false makes it public
})
```
- **Paths reserved by a running experiment** are locked — explain which experiment instead of retrying.
- A `stale` error means someone saved in between: re-read and re-plan against the current values.

Keep changes minimal: set the leaf values that must change rather than replacing a whole folder. If the configuration `isPrimary`, tell the user that saving it pushes it live to game servers immediately. After an `applied` result, share the `deepLinkPath` so they can review it in the editor. If the user declines the change, don't make it again unless they ask.

## Describing keys (update_configuration_descriptions)

Write descriptions when the user asks you to document a configuration (or agrees to your offer). The call saves immediately and needs no approval, because it changes no values and deploys nothing.

1. Read the keys first (`get_configuration`, structure then values) so every path exists and each description matches the actual value.
2. Make one call per configuration:

```
update_configuration_descriptions({
  configurationId: 42,
  reason: "Document the ranked settings the user asked about.",
  description: "Gameplay tuning for matchmaking and ranked.",                 // optional; "" clears it
  keyDescriptions: [
    { path: ["settings", "ranked", "eloThreshold"], description: "Minimum Elo a player needs to queue ranked." },
    { path: ["settings", "legacyMode"], description: "" }                      // "" removes a description
  ]
})
```

- Only object keys can be described — not array items or keys inside arrays (`invalid_change` otherwise).
- Keep each description to a sentence or two: what it controls, units, valid range. Don't invent behavior you can't see in the values or in code/docs the user shared.
- Afterwards, list what you wrote. Descriptions follow their key when it is renamed in the dashboard and are removed when the key is deleted.

## Creating, deleting, and switching the primary

These work the same way: each call makes the change when it runs, with your `reason` recorded. Only make them when the user asks for them.

- **`create_configuration({ name, description, configuration?, privateKeys?, reason })`** — a new configuration with optional initial JSON (top level must be an object). Call `list_configurations` first: names must be unique (`name_conflict` otherwise). **Always pass a `description`**, even when the user didn't ask for one: a sentence or two on what the configuration controls and what it is for. A new configuration is never primary, so nothing goes live. Pass `privateKeys` (key paths in the initial content, e.g. `[["rng", "seed"]]`) to mark keys private. Describe keys afterwards with `update_configuration_descriptions`.
- **`delete_configuration({ configurationId, reason })`** — cannot be undone from here. Refused for the primary configuration (`is_primary`: switch the primary first) and for a configuration a scheduled or running experiment is based on (`experiment_locked`: name the experiment instead of retrying). Confirm the exact configuration by name before deleting.
- **`set_primary_configuration({ configurationId, reason })`** — makes it the configuration game servers receive, **immediately**. Before switching, say which configuration it replaces (the current `isPrimary` one from `list_configurations`). Calling it for the configuration that is already primary is a no-op.
