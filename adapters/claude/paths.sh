#!/usr/bin/env bash
# adapters/claude/paths.sh - Claude Code filesystem paths

get_claude_source_dir() {
    echo "${CLAUDE_SKILLS_DIR:-$HOME/Claude-Code}"
}

get_claude_link_dir() {
    echo "${CLAUDE_SKILLS_LINK_DIR:-$HOME/.claude/skills}"
}

get_claude_index_path() {
    local source_dir
    source_dir="$(get_claude_source_dir)"
    echo "${CLAUDE_SKILLS_INDEX_PATH:-$source_dir/installed-skills-index.json}"
}
