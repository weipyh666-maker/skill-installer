#!/usr/bin/env bash
# adapters/_base.sh - Base multi-agent adapter specifications

SUPPORTED_AGENTS=("claude" "codex" "antigravity")

resolve_agent() {
    local requested="${1:-}"
    if [ -n "$requested" ]; then
        echo "$requested" | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    if [ -n "${CLAUDE_SKILLS_AGENT:-}" ]; then
        echo "$CLAUDE_SKILLS_AGENT" | tr '[:upper:]' '[:lower:]'
        return 0
    fi
    echo "claude"
}

validate_agent() {
    local agent="$1"
    for a in "${SUPPORTED_AGENTS[@]}"; do
        if [ "$a" = "$agent" ]; then
            return 0
        fi
    done
    echo "Error: Unknown agent '$agent'. Supported agents: ${SUPPORTED_AGENTS[*]}" >&2
    return 1
}
