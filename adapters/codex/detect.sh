#!/usr/bin/env bash
# adapters/codex/detect.sh - Codex environment detection without CLI execution

get_codex_cli_path() {
  if [[ -n "${SKILL_MANAGER_CODEX_CLI_PATH:-}" ]]; then [[ -f "$SKILL_MANAGER_CODEX_CLI_PATH" ]] && printf '%s\n' "$SKILL_MANAGER_CODEX_CLI_PATH"; return 0; fi
  command -v codex 2>/dev/null || true
}

get_codex_status() {
  local cli_path user_root compatibility_root system_root usable=false
  cli_path="$(get_codex_cli_path)"
  user_root="$(get_codex_user_skill_root)"
  compatibility_root="$(get_codex_compatibility_skill_root)"
  system_root="$(get_codex_system_skill_root)"
  [[ -n "$cli_path" || -d "$(get_codex_home)" ]] && usable=true
  printf 'cli_resolved=%s cli_path=%s executable_test=not-run codex_home=%s user_root_exists=%s compatibility_root_exists=%s system_root_exists=%s usable=%s\n' \
    "$([[ -n "$cli_path" ]] && echo true || echo false)" "$cli_path" "$(get_codex_home)" \
    "$([[ -d "$user_root" ]] && echo true || echo false)" "$([[ -d "$compatibility_root" ]] && echo true || echo false)" \
    "$([[ -d "$system_root" ]] && echo true || echo false)" "$usable"
}

detect_codex() { [[ "$(get_codex_status)" == *'usable=true'* ]]; }
