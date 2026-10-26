---
name: understand-community-pulse
description: "Understand and query the Community Pulse feature: sentiment sources, topic trends, player complaints, praise, and representative quotes."
---

# Understand Community Pulse

Use this skill when the user asks about community pulse, player sentiment, what players are complaining or excited about, which topics are hot, player feedback, or anything related to analyzed chat/feedback data.

## What Community Pulse is

**Community Pulse** is the Gamebeast feature that automatically processes player messages (chat, feedback, bug reports, support tickets) to extract structured sentiment signals. A three-stage pipeline runs on each configured **source**:

1. **Load** — messages are pulled from `gamebeast.markers_local` per source configuration.
2. **Classify** — FastText + heuristics filter irrelevant messages; a relevance score is assigned.
3. **Analyze** — an LLM (Gemini) reads batches of messages and extracts per-message fields: sentiment score, topics, loves, hates, feature mentions.

A daily **synthesizer** job aggregates analyzed content into topic-level rollups that the Community Pulse dashboard page shows. These live in Postgres (`sentiment_synthesis`).

The raw per-message extractions live in ClickHouse (`sentiment.analyzed_content`).

## What a sentiment source is

A **source** is a configured data stream — e.g. "Roblox Group Chat", "Bug Reports", "Player Feedback". Each source:
- Has a `contentSource` type: `chat`, `feedback`, `bug-reports`, or `support-tickets`.
- Is either `active` (being processed) or `paused`.
- Has a unique `id` used to filter queries.

Use `list_sentiment_sources` to see what sources exist before querying.

## Key field semantics

| Field | Meaning |
|-------|---------|
| `sentiment_score` | -1.0 (very negative) to 1.0 (very positive) per message |
| `topics` | 0–2 topic keys per message (closed vocabulary, see below) |
| `hates` | Extracted complaint phrases — the direct "what users dislike" signal |
| `loves` | Extracted praise phrases |
| `feature_mentions` | Named in-game features the player referenced |
| `llm_dropped` | `true` means a filler/failed row — always excluded from queries |
| `llm_relevance_score` | LLM confidence that the message is relevant (0–1) |
| `translation_en` | English translation when the original was non-English |

## Controlled topic vocabulary

The LLM tags each message with 0–2 topics from this fixed list:

| Key | Meaning |
|-----|---------|
| `gameplay_progression` | Stats, leveling, grinding, quests, skill trees |
| `items_cosmetics` | Capes, pets, skins, trading, inventory |
| `social_interaction` | Friends, greetings, guilds, banter |
| `bugs_issues` | Bugs, lag, crashes, connection problems |
| `new_feature_reaction` | Reactions to newly launched features |
| `off_topic` | Unrelated content (often noise) |
| `toxic_behavior` | Harassment, spam, offensive content |
| `monetization` | Purchases, prices, Robux, paywalls |

Topics outside this list may appear if the model inferred a new category from data.

## Tool workflow

### Step 1 — Understand available data

```
list_sentiment_sources
```

Always call this first. It tells you which sources exist, their type, state, and how many messages have been analyzed. Note the source `id` values for later filtering.

### Step 2 — Get the high-level picture

```
get_community_pulse
```

Returns the latest **synthesized snapshot** — the same view as the dashboard Community Pulse page. It is fast (no ClickHouse query) and gives you:
- Topic summaries with volume, love/hate/neutral counts, and trend (`hot`/`active`/`steady`).
- LLM-written insight clusters under `loves` and `hates` per topic: a `summary`, phrase count, source phrases, and `quoteContentIds`.
- Universe stats: total analyzed messages and unique users in the synthesis window.

**Caveat:** The snapshot is updated daily by the synthesizer. It may be up to 24 hours stale. Use `query_sentiment` for live data.

### Step 3 — Drill down with query_sentiment

```
query_sentiment({ operation, filters?, ...operationParams })
```

Six operations, all scoped to the current project:

#### `overview` — headline numbers
```json
{ "operation": "overview", "filters": { "days": 7 } }
```
Returns: message count, unique users, unique threads, avg sentiment, positive/negative/neutral counts.

#### `topics` — which topics are active and trending
```json
{ "operation": "topics", "limit": 8, "filters": { "days": 14 } }
```
Returns: per-topic volume + sentiment split + recent vs previous window volumes (for trend context).

#### `phrases` — what exactly are players saying (most important for complaints)
```json
{
  "operation": "phrases",
  "phraseColumn": "hates",
  "filters": { "days": 30, "topics": ["bugs_issues"] },
  "limit": 20
}
```
- **`phraseColumn: "hates"`** = complaint phrases. Use this to answer "what are players complaining about".
- **`phraseColumn: "loves"`** = praise phrases. Use for "what do players enjoy".
- **`phraseColumn: "feature_mentions"`** = named features regardless of sentiment.
- **`groupByTopic: true`** = return top N phrases *per topic* rather than globally.

#### `over_time` — volume and sentiment trend
```json
{ "operation": "over_time", "granularity": "day", "filters": { "days": 14 } }
```
- Add `"breakdown": "topic"` to see each topic's daily volume as separate series.
- Add `"breakdown": "source"` to compare sources over time.

#### `breakdown` — distribution by a categorical dimension
```json
{ "operation": "breakdown", "dimension": "country", "filters": { "days": 30 } }
```
Dimensions: `topic`, `source`, `country`, `device`, `lang`.

#### `quotes` — real player messages as evidence
```json
{
  "operation": "quotes",
  "filters": { "days": 14, "topics": ["bugs_issues"], "sentiment": "negative" },
  "limit": 10
}
```
Or resolve quote ids from `get_community_pulse`:
```json
{
  "operation": "quotes",
  "contentIds": ["abc123", "def456"],
  "limit": 10
}
```
Quotes show the `pseudonym` (not the real user id), message text (translated if available), timestamp, topics, and sentiment score. **Always cite real quotes when making claims about what players are saying.**

## Common workflows

### "What are players complaining about?"
1. `list_sentiment_sources` — confirm data exists.
2. `get_community_pulse` — scan `hates` clusters per topic for the synthesized picture.
3. `query_sentiment({ operation: "phrases", phraseColumn: "hates", limit: 20 })` — live top complaint phrases.
4. `query_sentiment({ operation: "quotes", filters: { sentiment: "negative" }, limit: 10 })` — example messages.

### "Which topics are hot this week?"
1. `query_sentiment({ operation: "topics", filters: { days: 7 }, limit: 10 })`
2. Compare `lastWindowVolume` vs `prevWindowVolume` — a large jump = trending.
3. Drill into the hot topic with phrases or quotes.

### "How is sentiment trending?"
1. `query_sentiment({ operation: "over_time", granularity: "day", filters: { days: 14 } })`
2. Look at `avgSentiment` over time; a drop below 0 means more negative than positive messages.
3. If a dip is visible, drill into that window with `phrases({ phraseColumn: "hates" })`.

### "Show me bug complaints"
1. `query_sentiment({ operation: "phrases", phraseColumn: "hates", filters: { topics: ["bugs_issues"] } })`
2. Follow up with quotes: `query_sentiment({ operation: "quotes", filters: { topics: ["bugs_issues"], sentiment: "negative" } })`

### "Resolve quote ids from the pulse page"
If `get_community_pulse` returned cluster `quoteContentIds`:
```json
{ "operation": "quotes", "contentIds": ["<id1>", "<id2>"] }
```

## Caveats

- **Data lag:** `get_community_pulse` is a daily snapshot (up to ~24 h stale). `query_sentiment` is live ClickHouse but pipeline analysis also has a lag of several minutes to hours depending on volume.
- **`llm_dropped = true` rows** are always excluded. These are filler or failed-chunk reconciliation rows with no extracted signals.
- **Sentiment score** is per-message (-1 to 1). It can be null when the LLM didn't assess relevance for a chunk.
- **Off-topic messages** (`off_topic` key) are usually noise (greetings, memes). Filter them out with `filters.topics` if they dominate.
- **Source coverage:** if `list_sentiment_sources` shows no active sources, there is no data to query — tell the user their sources need to be configured and set to active.
