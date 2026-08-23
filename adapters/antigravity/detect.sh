#!/usr/bin/env bash
# adapters/antigravity/detect.sh - Antigravity CLI environment detection

detect_antigravity_cli() {
    if [ -n "${ANTIGRAVITY_CLI_PATH:-}" ] && [ -f "$ANTIGRAVITY_CLI_PATH" ]; then
        echo "$ANTIGRAVITY_CLI_PATH"
        return 0
    fi
    if command -v antigravity >/dev/null 2>&1; then
        command -v antigravity
        return 0
    fi
    if command -v agy >/dev/null 2>&1; then
        command -v agy
        return 0
    fi
    for cand in "$HOME/bin/agy" "$HOME/bin/antigravity" "$HOME/.local/bin/agy" "$HOME/.local/bin/antigravity"; do
        if [ -f "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

detect_antigravity() {
    if [ -n "${ANTIGRAVITY_SKILLS_DIR:-}" ] || [ -n "${ANTIGRAVITY_SKILLS_LINK_DIR:-}" ]; then
        return 0
    fi
    if detect_antigravity_cli >/dev/null 2>&1; then
        return 0
    fi
    local global_skills
    global_skills="${ANTIGRAVITY_SKILLS_DIR:-$HOME/.agents/skills}"
    if [ -d "$global_skills" ]; then
        return 0
    fi
    if [ -d "$HOME/.gemini/antigravity-cli" ] || [ -d "$HOME/.antigravity" ]; then
        return 0
    fi
    return 1
}
