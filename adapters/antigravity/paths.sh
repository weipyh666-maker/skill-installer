#!/usr/bin/env bash
# adapters/antigravity/paths.sh - Antigravity CLI filesystem paths

get_antigravity_source_dir() {
    echo "${ANTIGRAVITY_SKILLS_DIR:-$HOME/.agents/skills}"
}

get_antigravity_link_dir() {
    echo "${ANTIGRAVITY_SKILLS_LINK_DIR:-$HOME/.gemini/antigravity-cli/skills}"
}

detect_antigravity() {
    echo "not-yet-implemented: see adapters/antigravity/stub-note.md" >&2
    return 1
}
