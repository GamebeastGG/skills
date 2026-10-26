---
name: understand-deeplinks
description: "Look up deeplink definitions and query interaction, conversion, and LTV analytics for deeplinks."
---

# Understand deeplinks

Use this skill when the user asks about deeplinks — what links exist, how many clicks or conversions they have, where traffic comes from, who converts, or how LTV varies by acquisition source.

## What a deeplink is

A **deeplink** is a shareable tracking link (e.g. `share.gamebeast.gg/{slug}`) that routes players into a Roblox game, or visitors to a website. The platform records two types of events:

- **Click (interaction)** — someone opens the link URL. Recorded in ClickHouse `deeplink_interactions`. For `web_url` links, a click is a **landing**: the JavaScript SDK on the destination page sends a `$deeplink_landing` marker when a visitor arrives.
- **Conversion** — a player who clicked then launches the game and the SDK fires a marker carrying the interaction id. Recorded in `deeplink_conversions` via a materialized view. For `web_url` links, every marker in the visitor's session carries the deeplink, so read conversions as **attributed sessions/users**, not as conversions.

A conversion can only happen after a click, so conversion rate = conversions / clicks × 100. Conversion rate and LTV aren't meaningful for `web_url` links.

Deeplinks have a **type**:
- `roblox_url` — deep link directly into a Roblox game place.
- `roblox_share_url` — uses a Roblox share code.
- `other` — generic URL redirect (clicks only).
- `web_url` — a website running the Gamebeast JavaScript SDK (`@gamebeast/js`). The link redirects instantly to `taggedUrl` (the URL with the link's UTM values and `utm_id=gb_<slug>`), and the SDK attributes the visitor's session to the deeplink (first touch per session). Those markers also carry the UTM values as `$utm_source`, `$utm_medium`, `$utm_campaign`, `$utm_content`, `$utm_term` and `$utm_id` marker arguments, so insight queries can filter or break down web activity by campaign.

## Tool workflow

### 1. Discover deeplinks

```
list_deeplinks
```

Returns all deeplinks with: id, name, type, slug, redirectUrl, and optional description/OG metadata. Use the `search` parameter to filter by name. The `id` is what you pass to `query_deeplink_metrics`.

### 2. Query analytics

```
query_deeplink_metrics({ metric, deeplinkId?, range?, breakdown?, userType?, ltvType? })
```

Do not restate raw numbers row by row (in the Gamebeast assistant the results render as inline charts the user already sees). Analyze trends, spikes, and comparisons instead.

#### metric values and when to use them

| metric | Description | deeplinkId required? |
| --- | --- | --- |
| `clicks_over_time` | Daily click count — shows traffic volume trend | Yes |
| `conversions_over_time` | Daily in-game conversion count | Yes |
| `users_over_time` | New vs returning converted users per day | Yes |
| `sources` | Clicks/conversions by referrer category (Twitter, YouTube, Direct, …) | Yes |
| `geography` | Clicks/conversions by country and region | Yes |
| `kpis` | Summary KPIs: clicks, conversions, conversion rate, users, sessions, revenue | No (all deeplinks) |
| `ltv` | LTV cohort curve by day (D0, D1, D3, D7, D14, D30) | Yes |

#### range

Pick the window that fits the user's question:
- `"7d"`, `"14d"` (default), `"28d"`, `"56d"`, `"90d"` — rolling window
- `"all"` — all-time (ltv automatically clamps to 90d)

#### breakdown (kpis and ltv only)

- `"source"` — split KPIs by referrer category to compare traffic channels.
- `"deeplink"` — compare all deeplinks side-by-side (useful without a deeplinkId).

#### userType (kpis only)

- `"new"` — players whose first session ever is after the conversion.
- `"returning"` — players who had sessions before converting.

#### ltvType (required for ltv)

- `"revenue"` — cumulative Robux revenue per converted user.
- `"playtime"` — cumulative session playtime per converted user.

## Example workflows

### "Show me how my Summer Promo link is performing"

1. `list_deeplinks({ search: "Summer Promo" })` → get the id.
2. `query_deeplink_metrics({ metric: "kpis", deeplinkId: <id>, range: "28d" })` → headline numbers.
3. `query_deeplink_metrics({ metric: "clicks_over_time", deeplinkId: <id>, range: "28d" })` → traffic trend.
4. `query_deeplink_metrics({ metric: "sources", deeplinkId: <id>, range: "28d" })` → where clicks come from.

### "Which of my deeplinks converts best?"

1. `list_deeplinks()` → confirm multiple links exist.
2. `query_deeplink_metrics({ metric: "kpis", breakdown: "deeplink", range: "28d" })` → side-by-side conversion rate.

### "Is the Summer Promo link acquiring new or returning players?"

1. `list_deeplinks({ search: "Summer Promo" })` → get the id.
2. `query_deeplink_metrics({ metric: "users_over_time", deeplinkId: <id>, range: "28d" })` → stacked new vs returning.
3. Optionally: `query_deeplink_metrics({ metric: "kpis", deeplinkId: <id>, userType: "new", range: "28d" })` for a new-user-only summary.

### "What's the LTV from the YouTube campaign link?"

1. `list_deeplinks({ search: "YouTube" })` → get the id.
2. `query_deeplink_metrics({ metric: "ltv", deeplinkId: <id>, ltvType: "revenue", range: "28d" })`.

## Common mistakes to avoid

- **Missing deeplinkId** — all metrics except `kpis` require a `deeplinkId`. Use `list_deeplinks` first.
- **Missing ltvType** — `ltv` metric requires `ltvType: "revenue"` or `"playtime"`.
- **Don't restate raw numbers** — analyze trends and give a 2–4 sentence interpretation.
- **Clicks ≠ conversions** — clicks are counted on link open; conversions require the SDK to fire the in-game marker. Unmatched ids (player opens link but never enters game) count as clicks only.
