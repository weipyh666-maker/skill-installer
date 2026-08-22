#!/usr/bin/env bash
# Optional template for a reviewed CLI bundle.

set -euo pipefail

SKILL_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/Claude-Code}/{{SKILL_NAME}}"
BIN="$SKILL_ROOT/{{BINARY_REL_PATH}}"

[[ -d "$SKILL_ROOT" ]] || { echo "Skill not installed at $SKILL_ROOT" >&2; exit 1; }
[[ -f "$BIN" ]] || { echo "Binary not found: $BIN" >&2; exit 1; }

exec node "$BIN" "$@"

