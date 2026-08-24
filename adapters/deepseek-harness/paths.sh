#!/usr/bin/env bash
# adapters/deepseek-harness/paths.sh - DeepSeek Harness multi-root Skill discovery
#
# Mirrors the verified DSH semantics (Phase A analysis):
#   roots: project-dsh 100 / project-agents 200 / custom 300 / user-dsh 400 /
#          user-agents 500 / bundled 600; rank decides duplicates only within
#          one provider layer (rank asc -> root order -> name order, first wins).
#   user-dsh root skips the reserved `.system` namespace (not a system-skill root).

get_dsh_user_home() { if [[ -n "${SKILL_MANAGER_DSH_USER_HOME:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_DSH_USER_HOME"; else printf '%s\n' "$HOME"; fi; }

get_dsh_home() {
  if [[ -n "${SKILL_MANAGER_DSH_HOME:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_DSH_HOME"
  elif [[ -n "${DSH_HOME:-}" && -n "${DSH_HOME// /}" ]]; then printf '%s\n' "$DSH_HOME"
  else printf '%s/.dsh\n' "$(get_dsh_user_home)"; fi
}

get_dsh_agents_home() {
  if [[ -n "${SKILL_MANAGER_DSH_AGENTS_HOME:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_DSH_AGENTS_HOME"
  elif [[ -n "${DSH_AGENTS_HOME:-}" ]]; then printf '%s\n' "$DSH_AGENTS_HOME"
  else printf '%s/.agents\n' "$(get_dsh_user_home)"; fi
}

get_dsh_bundled_dir() {
  if [[ -n "${SKILL_MANAGER_DSH_BUNDLED_DIR:-}" ]]; then printf '%s\n' "$SKILL_MANAGER_DSH_BUNDLED_DIR"
  elif [[ -n "${DSH_BUNDLED_SKILL_DIR:-}" ]]; then printf '%s\n' "$DSH_BUNDLED_SKILL_DIR"; fi
}

get_dsh_cwd() { printf '%s\n' "${SKILL_MANAGER_DSH_CWD:-$(pwd)}"; }
get_dsh_user_skill_root() { printf '%s/skills\n' "$(get_dsh_home)"; }
get_dsh_shared_skill_root() { printf '%s/skills\n' "$(get_dsh_agents_home)"; }
get_dsh_user_system_root() { printf '%s/.system\n' "$(get_dsh_user_skill_root)"; }
get_dsh_settings_path() { printf '%s\n' "${SKILL_MANAGER_DSH_SETTINGS_PATH:-$(get_dsh_home)/settings.yaml}"; }
get_dsh_index_path() { printf '%s\n' "${SKILL_MANAGER_DSH_INDEX_PATH:-$(get_dsh_home)/skill-manager-catalog.json}"; }

# Nearest `.git` ancestor, else the working directory itself (DSH projectRoot rule).
get_dsh_project_root() {
  local current="${1:-}"
  [[ -n "$current" ]] || current="$(get_dsh_cwd)"
  while [[ -n "$current" ]]; do
    [[ -e "$current/.git" ]] && { printf '%s\n' "$current"; return 0; }
    [[ "$current" == "/" || "$current" == *":\\"* ]] && break
    current="$(dirname "$current")"
  done
  printf '%s\n' "${1:-$(get_dsh_cwd)}"
}

# Best-effort preset state: preset name, provider flag, consumer, includeDefaultRoots.
# Output lines: preset=... provider=true|false consumer=... include_default=true|false
get_dsh_preset_state() {
  local settings preset="" provider=false consumer=unknown include_default=true cmd
  settings="$(get_dsh_settings_path)"
  if [[ -n "${SKILL_MANAGER_DSH_PRESET:-}" ]]; then
    preset="$SKILL_MANAGER_DSH_PRESET"
  elif [[ -f "$settings" ]]; then
    preset="$(awk '
      /^agent-presets:/ { inblock=1; next }
      inblock && /^[a-zA-Z0-9_.-]+:/ { inblock=0 }
      inblock && /^[[:space:]]*default:/ { gsub(/^[[:space:]]*default:[[:space:]]*/, ""); gsub(/["'"'"']/, ""); gsub(/[[:space:]]+.*$/, ""); print; exit }
    ' "$settings")"
  fi
  if [[ -z "$preset" ]]; then
    printf 'preset= provider=%s consumer=%s include_default=%s\n' "$provider" "$consumer" "$include_default"
    return 0
  fi
  local preset_file
  preset_file="$(get_dsh_home)/.agent-presets/$preset/agent.cordis.yml"
  if [[ ! -f "$preset_file" ]]; then
    printf 'preset=%s provider=%s consumer=%s include_default=%s\n' "$preset" "$provider" "$consumer" "$include_default"
    return 0
  fi
  if grep -qE '^\s*- id:[[:space:]]*skill-filesystem[[:space:]]*$|@deepseek-ai/dsh-skill-filesystem' "$preset_file"; then provider=true; fi
  if grep -qE '^\s*- id:[[:space:]]*tool-skill[[:space:]]*$|@deepseek-ai/dsh-tool-skill' "$preset_file"; then
    consumer='tool-skill'
  elif grep -qE '^\s*- id:[[:space:]]*skill-search[[:space:]]*$' "$preset_file"; then
    consumer='skill-search'
  elif [[ "$provider" == true ]]; then
    consumer='none'
  fi
  cmd=$(awk '
    /^[[:space:]]*- id:[[:space:]]*skill-filesystem[[:space:]]*$/ { inroot=1; next }
    inroot && /^[[:space:]]*- id:/ { inroot=0 }
    inroot && /includeDefaultRoots:[[:space:]]*(true|false)/ { gsub(/.*includeDefaultRoots:[[:space:]]*/, ""); gsub(/[[:space:]].*$/, ""); print; exit }
  ' "$preset_file")
  if [[ -n "$cmd" ]]; then include_default="$cmd"; fi
  printf 'preset=%s provider=%s consumer=%s include_default=%s\n' "$preset" "$provider" "$consumer" "$include_default"
}

# customSkillDirs from the skill-filesystem row of the active preset config.
get_dsh_custom_dirs() {
  local preset_file preset_name
  preset_name="$(get_dsh_preset_state | sed -n 's/^preset=\([^ ]*\).*/\1/p')"
  preset_file="$(get_dsh_home)/.agent-presets/$preset_name/agent.cordis.yml"
  [[ -f "$preset_file" ]] || return 0
  awk '
    /^[[:space:]]*- id:[[:space:]]*skill-filesystem[[:space:]]*$/ { inroot=1; next }
    inroot && /^[[:space:]]*- id:/ { inroot=0 }
    inroot && /customSkillDirs:/ { incustom=1; next }
    inroot && incustom && /^[[:space:]]*-[[:space:]]/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); gsub(/["'"'"']/, ""); print; next }
    inroot && incustom && /^[a-zA-Z0-9_.-]+:/ { incustom=0 }
  ' "$preset_file"
}

# Discovery roots as TSV: scope  class  writable  protected  rank  write_policy  path
get_dsh_discovery_roots() {
  local working_directory="${1:-$(get_dsh_cwd)}" root state include_default
  state="$(get_dsh_preset_state)"
  include_default="$(printf '%s\n' "$state" | sed -n 's/.*include_default=//p')"
  if [[ "$include_default" == true ]]; then
    local project_root
    project_root="$(get_dsh_project_root "$working_directory")"
    printf 'project\tproject-dsh\tfalse\tfalse\t100\tconditional\t%s/.dsh/skills\n' "$project_root"
    printf 'project\tproject-agents\tfalse\tfalse\t200\tconditional\t%s/.agents/skills\n' "$project_root"
  fi
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && printf 'custom\tcustom\tfalse\tfalse\t300\tdiagnostic-only\t%s\n' "$dir"
  done < <(get_dsh_custom_dirs)
  if [[ "$include_default" == true ]]; then
    printf 'user\tuser-dsh\ttrue\tfalse\t400\twritable\t%s\n' "$(get_dsh_user_skill_root)"
    printf 'user\tuser-agents\ttrue\tfalse\t500\twritable/shared\t%s\n' "$(get_dsh_shared_skill_root)"
  fi
  root="$(get_dsh_bundled_dir || true)"
  if [[ -n "$root" ]]; then printf 'deployment\tbundled\tfalse\tfalse\t600\tdiagnostic-only\t%s\n' "$root"; fi
  return 0
}

# Install target resolution by scope: user (default) / user-agents / project.
get_dsh_install_root() {
  local scope="${1:-user}" working_directory="${2:-$(get_dsh_cwd)}"
  if [[ "$scope" == 'user-agents' ]]; then printf '%s\n' "$(get_dsh_shared_skill_root)"; return 0; fi
  if [[ "$scope" == 'project' ]]; then printf '%s/.dsh/skills\n' "$(get_dsh_project_root "$working_directory")"; return 0; fi
  printf '%s\n' "$(get_dsh_user_skill_root)"
}

# skill-manager's own write-policy guards (not DSH protection facts): refuse
# bundled roots and the reserved `.system` namespace.
is_dsh_protected_target() {
  local candidate="$1" root
  candidate="$(readlink -f "$candidate" 2>/dev/null || printf '%s\n' "$candidate")"
  for root in "$(get_dsh_bundled_dir || true)" "$(get_dsh_user_system_root)"; do
    [[ -n "$root" ]] || continue
    root="$(readlink -f "$root" 2>/dev/null || printf '%s\n' "$root")"
    case "$candidate" in
      "$root"|"$root"/*) return 0 ;;
    esac
  done
  return 1
}