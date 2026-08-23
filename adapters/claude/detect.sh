#!/usr/bin/env bash
# adapters/claude/detect.sh - Claude Code environment detection

detect_claude() {
    local source_dir
    local link_dir
    source_dir="${CLAUDE_SKILLS_DIR:-$HOME/Claude-Code}"
    link_dir="${CLAUDE_SKILLS_LINK_DIR:-$HOME/.claude/skills}"
    if [ -d "$link_dir" ] || [ -d "$source_dir" ]; then
        return 0
    fi
    return 1
}
