#!/usr/bin/env bash
# Copy skills/ from the monorepo's packages/agent-skills/skills at a git ref.
#
# The skills are authored in GamebeastGG/service-monorepo, where the in-app assistant and the MCP
# server load them. This repo republishes them for plugin marketplaces, so never edit
# skills/ here by hand: change them in the monorepo, then run this.
#
# Usage: scripts/sync-skills.sh [path-to-service-monorepo] [ref]
#   defaults: ../service-monorepo, origin/main
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
monorepo="$(cd "${1:-$repo_root/../service-monorepo}" && pwd)"
ref="${2:-origin/main}"
src="packages/agent-skills/skills"

git -C "$monorepo" fetch --quiet origin
sha="$(git -C "$monorepo" rev-parse --short "$ref")"

rm -rf "$repo_root/skills"
mkdir -p "$repo_root/skills"
git -C "$monorepo" archive "$sha" "$src" | tar -x --strip-components=3 -C "$repo_root/skills"

echo "Synced $(ls "$repo_root/skills" | wc -l | tr -d ' ') skills from service-monorepo@$sha"
