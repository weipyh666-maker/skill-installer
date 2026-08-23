#!/usr/bin/env bash
# adapters/codex/paths.sh - Codex multi-root Skill discovery

get_codex_user_home() { if [[ -n "${SKILL_MANAGER_CODEX_USER_HOME:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_CODEX_USER_HOME"; else printf '%s\n' "$HOME"; fi; }
get_codex_home() { if [[ -n "${SKILL_MANAGER_CODEX_HOME:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_CODEX_HOME"; elif [[ -n "${CODEX_HOME:-}" ]]; then printf '%s\n' "$CODEX_HOME"; else printf '%s/.codex\n' "$(get_codex_user_home)"; fi; }
get_codex_user_skill_root() { if [[ -n "${SKILL_MANAGER_CODEX_USER_ROOT:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_CODEX_USER_ROOT"; else printf '%s/.agents/skills\n' "$(get_codex_user_home)"; fi; }
get_codex_compatibility_skill_root() { printf '%s/skills\n' "$(get_codex_home)"; }
get_codex_system_skill_root() { printf '%s/.system\n' "$(get_codex_compatibility_skill_root)"; }
get_codex_plugin_skill_roots() { if [[ -n "${SKILL_MANAGER_CODEX_PLUGIN_ROOT:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_CODEX_PLUGIN_ROOT"; elif [[ -d "$(get_codex_home)/plugins/cache" ]]; then printf '%s\n' "$(get_codex_home)/plugins/cache"; fi; }
get_codex_index_path() { printf '%s\n' "${SKILL_MANAGER_CODEX_INDEX_PATH:-$(get_codex_home)/skill-manager-catalog.json}"; }

get_codex_project_root() {
  local current="$1"
  while [[ -n "$current" && "$current" != "/" ]]; do [[ -e "$current/.git" ]] && { printf '%s\n' "$current"; return 0; }; current="$(dirname "$current")"; done
}
get_codex_project_skill_roots() {
  local current="$1" repo_root candidate
  repo_root="$(get_codex_project_root "$current" || true)"; [[ -n "$repo_root" ]] || return 0
  while :; do candidate="$current/.agents/skills"; [[ -d "$candidate" ]] && printf '%s\n' "$candidate"; [[ "$current" == "$repo_root" ]] && break; current="$(dirname "$current")"; done
}
get_codex_admin_skill_root() { if [[ -n "${SKILL_MANAGER_CODEX_ADMIN_ROOT:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_CODEX_ADMIN_ROOT"; elif [[ "${OS:-}" != "Windows_NT" ]]; then printf '/etc/codex/skills\n'; fi; }
get_codex_discovery_roots() {
  local working_directory="${1:-${SKILL_MANAGER_CODEX_CWD:-$(pwd)}}" root
  printf 'user\tagents\ttrue\tfalse\t%s\n' "$(get_codex_user_skill_root)"
  printf 'compatibility\tcompatibility\ttrue\tfalse\t%s\n' "$(get_codex_compatibility_skill_root)"
  printf 'system\tsystem\tfalse\ttrue\t%s\n' "$(get_codex_system_skill_root)"
  while IFS= read -r root; do printf 'project\tagents\tfalse\tfalse\t%s\n' "$root"; done < <(get_codex_project_skill_roots "$working_directory")
  while IFS= read -r root; do printf 'plugin\tplugin-cache\tfalse\tfalse\t%s\n' "$root"; done < <(get_codex_plugin_skill_roots)
  root="$(get_codex_admin_skill_root || true)"; if [[ -n "$root" ]]; then printf 'admin\tadmin\tfalse\ttrue\t%s\n' "$root"; fi; return 0
}
