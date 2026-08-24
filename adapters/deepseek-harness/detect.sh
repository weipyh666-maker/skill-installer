#!/usr/bin/env bash
# adapters/deepseek-harness/detect.sh - DeepSeek Harness environment detection without CLI execution
#
# Two-stage detection so "something DSH-shaped exists" is not confused with
# "the skill runtime is ready to surface skills to a model":
#   detected            = cli_detected OR package_detected OR dsh_home_detected OR config_detected
#   skill_runtime_ready = provider_enabled AND consumer_detected (tool-skill / skill-search)
#   usable              = detected AND skill_runtime_ready
# A bare ~/.agents/skills directory, or a ~/.dsh home with no active preset
# provider+consumer, yields usable=false. The CLI is resolved but never executed.

get_dsh_cli_path() {
  if [[ -n "${SKILL_MANAGER_DSH_CLI_PATH:-}" ]]; then [[ -f "$SKILL_MANAGER_DSH_CLI_PATH" ]] && printf '%s\n' "$SKILL_MANAGER_DSH_CLI_PATH"; return 0; fi
  command -v dsh 2>/dev/null || true
}

# Best-effort npm package marker probe (no execution). Tests override via
# SKILL_MANAGER_DSH_PACKAGE_DETECTED=true|false; otherwise a local
# node_modules/@deepseek-ai/dsh* package.json marker counts as detected.
get_dsh_package_detected() {
  local override="${SKILL_MANAGER_DSH_PACKAGE_DETECTED:-}"
  if [[ "$override" == 'true' ]]; then return 0; fi
  if [[ "$override" == 'false' ]]; then return 1; fi
  local cwd
  cwd="$(get_dsh_cwd)"
  [[ -f "$cwd/node_modules/@deepseek-ai/dsh/package.json" ]] && return 0
  [[ -f "$cwd/node_modules/@deepseek-ai/dsh-cli/package.json" ]] && return 0
  return 1
}

get_dsh_status() {
  local cli_path state consumer provider dsh_home_detected agents_home_detected config_detected package_detected
  local cli_detected detected consumer_detected skill_runtime_ready usable usable_reason preset_name preset_file
  cli_path="$(get_dsh_cli_path)"
  state="$(get_dsh_preset_state)"
  provider="$(printf '%s\n' "$state" | sed -n 's/.*provider=\([^ ]*\).*/\1/p')"
  consumer="$(printf '%s\n' "$state" | sed -n 's/.*consumer=\([^ ]*\).*/\1/p')"
  dsh_home_detected=false; [[ -d "$(get_dsh_home)" ]] && dsh_home_detected=true
  agents_home_detected=false; [[ -d "$(get_dsh_agents_home)" ]] && agents_home_detected=true
  preset_name="$(printf '%s\n' "$state" | sed -n 's/^preset=\([^ ]*\).*/\1/p')"
  preset_file=""
  if [[ -n "$preset_name" ]]; then preset_file="$(get_dsh_home)/.agent-presets/$preset_name/agent.cordis.yml"; fi
  config_detected=false
  { [[ -f "$(get_dsh_settings_path)" ]] || { [[ -n "$preset_file" ]] && [[ -f "$preset_file" ]]; }; } && config_detected=true
  package_detected=false; get_dsh_package_detected && package_detected=true
  cli_detected=false; [[ -n "$cli_path" ]] && cli_detected=true
  detected=false; { [[ "$cli_detected" == true || "$package_detected" == true || "$dsh_home_detected" == true || "$config_detected" == true ]]; } && detected=true
  consumer_detected=false; { [[ "$consumer" == 'tool-skill' || "$consumer" == 'skill-search' ]]; } && consumer_detected=true
  skill_runtime_ready=false; { [[ "$provider" == true && "$consumer_detected" == true ]]; } && skill_runtime_ready=true
  usable=false; { [[ "$detected" == true && "$skill_runtime_ready" == true ]]; } && usable=true
  usable_reason='not-detected'
  if [[ "$detected" != true ]]; then usable_reason='not-detected'
  elif [[ "$provider" != true ]]; then usable_reason='provider-not-enabled'
  elif [[ "$consumer_detected" != true ]]; then
    usable_reason='consumer-unknown'; [[ "$consumer" == 'none' ]] && usable_reason='no-catalog-consumer-mounted'
  else usable_reason='detected-and-runtime-ready'; fi
  printf 'cli_resolved=%s cli_detected=%s cli_path=%s executable_test=not-run package_detected=%s dsh_home=%s dsh_home_detected=%s config_detected=%s detected=%s agents_home=%s agents_home_detected=%s user_root_exists=%s shared_root_exists=%s provider_enabled=%s consumer=%s consumer_detected=%s skill_runtime_ready=%s usable=%s usable_reason=%s\n' \
    "$([[ -n "$cli_path" ]] && echo true || echo false)" "$cli_detected" "$cli_path" "$package_detected" \
    "$(get_dsh_home)" "$dsh_home_detected" "$config_detected" "$detected" \
    "$(get_dsh_agents_home)" "$agents_home_detected" \
    "$([[ -d "$(get_dsh_user_skill_root)" ]] && echo true || echo false)" \
    "$([[ -d "$(get_dsh_shared_skill_root)" ]] && echo true || echo false)" \
    "$provider" "$consumer" "$consumer_detected" "$skill_runtime_ready" "$usable" "$usable_reason"
}

detect_dsh() { [[ "$(get_dsh_status)" == *'usable=true'* ]]; }
