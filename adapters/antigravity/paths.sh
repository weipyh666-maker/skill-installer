#!/usr/bin/env bash
# adapters/antigravity/paths.sh - Antigravity CLI filesystem paths and discovery roots

get_antigravity_global_skill_dir() {
    if [ -n "${ANTIGRAVITY_SKILLS_LINK_DIR:-}" ]; then
        echo "$ANTIGRAVITY_SKILLS_LINK_DIR"
    elif [ -n "${ANTIGRAVITY_SKILLS_DIR:-}" ]; then
        echo "$ANTIGRAVITY_SKILLS_DIR"
    elif [ -n "${SKILL_MANAGER_STORE_DIR:-}" ]; then
        echo "$SKILL_MANAGER_STORE_DIR"
    else
        echo "$HOME/.agents/skills"
    fi
}

get_antigravity_source_dir() {
    if [ -n "${ANTIGRAVITY_SKILLS_DIR:-}" ]; then
        echo "$ANTIGRAVITY_SKILLS_DIR"
    elif [ -n "${SKILL_MANAGER_STORE_DIR:-}" ]; then
        echo "$SKILL_MANAGER_STORE_DIR"
    else
        echo "$HOME/.agents/skills"
    fi
}

get_antigravity_link_dir() {
    if [ -n "${ANTIGRAVITY_SKILLS_LINK_DIR:-}" ]; then
        echo "$ANTIGRAVITY_SKILLS_LINK_DIR"
    elif [ -n "${ANTIGRAVITY_SKILLS_DIR:-}" ]; then
        echo "$ANTIGRAVITY_SKILLS_DIR"
    else
        echo "$HOME/.agents/skills"
    fi
}

get_antigravity_builtin_dir() {
    echo "${ANTIGRAVITY_BUILTIN_DIR:-$HOME/.gemini/antigravity-cli/builtin/skills}"
}

get_antigravity_index_path() {
    if [ -n "${ANTIGRAVITY_SKILLS_INDEX_PATH:-}" ]; then
        echo "$ANTIGRAVITY_SKILLS_INDEX_PATH"
    elif [ -n "${SKILL_MANAGER_INDEX_PATH:-}" ]; then
        echo "$SKILL_MANAGER_INDEX_PATH"
    else
        local s
        s="$(get_antigravity_source_dir)"
        echo "$s/installed-skills-index.json"
    fi
}
