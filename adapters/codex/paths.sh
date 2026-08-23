#!/usr/bin/env bash
# adapters/codex/paths.sh - OpenAI Codex CLI filesystem paths

get_codex_source_dir() {
    echo "${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
}

get_codex_link_dir() {
    echo "${CODEX_SKILLS_LINK_DIR:-$HOME/.config/codex/skills}"
}

detect_codex() {
    echo "not-yet-implemented: see adapters/codex/stub-note.md" >&2
    return 1
}
