# Contributing

The skills in `skills/` are authored in Gamebeast's service monorepo
(`packages/agent-skills/skills`), where the in-dashboard assistant and the MCP server already
load them. This repo republishes the same files for plugin marketplaces, so **don't edit
`skills/` here directly**: your change would be overwritten on the next sync and would never
reach the assistant or the MCP server.

To update the skills:

1. Change the skill in the monorepo and merge it to `main`.
2. Here, run `scripts/sync-skills.sh` (defaults to `../service-monorepo` at `origin/main`).
3. Bump `version` in every manifest that carries one (`plugin.json`, `.cursor-plugin/plugin.json`,
   `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`), then open a PR.

Changes to plugin packaging (manifests, MCP declaration, README, logo) are made here.

Skills are written to work on every surface: they describe Gamebeast MCP tools by name, refer to
other skills by name, and label anything that only exists in the Gamebeast dashboard. See the
monorepo's `packages/agent-skills/README.md` for the authoring rules.
