# Gamebeast Skills

Official [Agent Skills](https://agentskills.io/specification) and MCP server for [Gamebeast](https://gamebeast.gg), the analytics, experimentation, and LiveOps platform for games.

Connect your agent to your Gamebeast projects to query player behavior, build dashboards and cohorts, run and read out A/B experiments, tune remote configurations, and instrument your Roblox, Unity, Unreal, Godot, or web game.

## Installing

Use the native plugin where supported to install both the Gamebeast skills and the Gamebeast MCP server. On first use, your client opens a browser: sign in with your Gamebeast account and choose which organizations, projects, and permissions the connection gets. Agents that only support the Agent Skills standard can install the skills separately.

### Cursor

Install from the Cursor Marketplace, or add manually via **Settings > Rules > Add Rule > Remote Rule (Github)** with `GamebeastGG/skills`.

### Claude Code

Install using the [plugin marketplace](https://code.claude.com/docs/en/plugins/install#add-a-marketplace):

```
/plugin marketplace add GamebeastGG/skills
/plugin install gamebeast@gamebeast
```

### Codex

Install from the Gamebeast plugin marketplace:

```sh
codex plugin marketplace add GamebeastGG/skills
codex plugin add gamebeast@gamebeast
```

Start a new Codex session after installation.

### VS Code / GitHub Copilot

Install directly from this repository:

1. Enable `chat.plugins.enabled` in VS Code settings.
2. Open the Command Palette and run **Chat: Install Plugin From Source**.
3. Enter `https://github.com/GamebeastGG/skills`.

For marketplace installation or troubleshooting, see [VS Code's agent plugin documentation](https://code.visualstudio.com/docs/agent-customization/agent-plugins).

### ChatGPT and Claude Desktop

Add Gamebeast as a custom connector using the MCP server URL `https://api.gamebeast.gg/mcp`. The skills are served by the MCP server itself (as `skill://` resources and through the `load_skill` tool), so a connector-only install still gets them.

### npx skills

Install using the [`npx skills`](https://skills.sh) CLI:

```
npx skills add https://github.com/GamebeastGG/skills
```

### Clone / Copy

Clone this repo and copy the skill folders into the appropriate directory for your agent:

| Agent | Skill Directory | Docs |
|-------|-----------------|------|
| Claude Code | `~/.claude/skills/` | [docs](https://code.claude.com/docs/en/skills) |
| Cursor | `~/.cursor/skills/` | [docs](https://cursor.com/docs/context/skills) |
| OpenCode | `~/.config/opencode/skills/` | [docs](https://opencode.ai/docs/skills/) |
| OpenAI Codex | `~/.codex/skills/` | [docs](https://developers.openai.com/codex/skills/) |

Then add the MCP server yourself (see [MCP Server](#mcp-server)).

## Skills

Skills are contextual and auto-loaded based on your conversation. When a request matches a skill's triggers, the agent loads and applies it.

### Playbooks

Multi-step jobs. Each is an approach the agent adapts to what you asked, not a fixed script.

| Skill | Useful for |
|-------|------------|
| instrument-game | Designing a tracking plan and remote configuration, wiring the SDK calls, and verifying each event against live data |
| build-team-dashboards | Building a project's first engagement, retention, economy, and monetization dashboards from the events it actually sends |
| weekly-review | A two-minute weekly summary: what moved and why, running experiments, player sentiment, and what to do next |
| diagnose-change | Investigating why a metric moved or an event stopped, down to the segment, config edit, or experiment behind it |
| fix-instrumentation | Auditing event data for stopped events, drifting property types, high cardinality, and tracking-plan mismatches |
| ship-or-kill-experiments | Deciding running experiments (ship, end, extend, or ramp) with sample-ratio, power, and duration checks |
| launch-liveops-event | Running a measurable LiveOps event as a holdout experiment with a staged rollout, KPI dashboard, and readout |
| tune-economy | Finding and fixing in-game economy imbalances and shipping the fix as a reversible experiment |
| target-segment | Finding the players a change should reach, as a cohort, and targeting an experiment at it |
| player-voice-to-action | Turning community feedback into a testable change backed by behavioral data |

### References

| Skill | Useful for |
|-------|------------|
| insight-queries | Insight specs: metrics, aggregations, formulas, filters, breakdowns, and value formatting |
| funnel-queries | Funnel specs: steps, conversion windows, ordering, and breakdowns |
| retention-queries | Retention specs: start and return events, day-N / week-N windows, and displays |
| heatmap-queries | Heatmaps and heatmap queries: counting an event's positions on a map and reading hotspots |
| run-analytics-query | Running saved queries with time or breakdown overrides and interpreting the results |
| cohorts | Reading and building cohort (player segment) definitions |
| manage-cohorts | Creating, editing, and deleting saved cohorts |
| manage-dashboards | Creating, laying out, organizing, and deleting dashboards and saved queries |
| manage-events | Describing analytics events and their arguments, and hiding or showing them |
| understand-experiments | The experiment model and how to measure and read results |
| manage-experiments | Designing, previewing, creating, ending, and assigning A/B experiments |
| experiment-rollouts | Staged rollouts: ramp curves, rollout steps, and operating a ramp |
| understand-configurations | Navigating, reading, and searching remote configurations |
| understand-deeplinks | Deeplink definitions and their interaction, conversion, and LTV analytics |
| understand-community-pulse | Community Pulse: sentiment sources, topic trends, complaints, praise, and quotes |

## MCP Server

This plugin includes the Gamebeast remote MCP server:

| Server | URL | Purpose |
|--------|-----|---------|
| gamebeast | `https://api.gamebeast.gg/mcp` | Query analytics, manage dashboards, cohorts, configurations, and experiments, and read community sentiment across your Gamebeast projects |

The server signs you in with OAuth; there's no token to copy. The connection is read-only apart from configurations, experiments, and analytics assets (dashboards, saved queries, cohorts, event descriptions), and only if you grant write permissions when connecting. Your own role is re-checked on every request, so the agent can never do more than you can. MCP calls don't use your Gamebeast AI credits.

For personal access tokens, per-project URLs, and the full permission model, see the [MCP server docs](https://docs.gamebeast.gg/docs/mcp).

## License

[Apache-2.0](LICENSE)
