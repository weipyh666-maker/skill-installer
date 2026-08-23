#!/usr/bin/env bash
# adapters/antigravity/detect.sh - Antigravity CLI environment detection

detect_antigravity() {
    if [ -n "${ANTIGRAVITY_SKILLS_DIR:-}" ] || [ -n "${ANTIGRAVITY_SKILLS_LINK_DIR:-}" ]; then
        return 0
    fi
    if command -v antigravity >/dev/null 2>&1 || command -v agy >/dev/null 2>&1; then
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
