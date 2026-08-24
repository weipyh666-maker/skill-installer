#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/adapters/_base.sh"
source "$ROOT/adapters/deepseek-harness/paths.sh"
source "$ROOT/adapters/deepseek-harness/detect.sh"

new_test_skill() {
  mkdir -p "$1"
  printf '%s\n' '---' "name: $2" "description: $3" "${4:-}" '---' '' "# $2" > "$1/SKILL.md"
}

assert_contains() {
  [[ "$1" == *"$2"* ]] || { echo "ASSERTION FAILED: $3" >&2; exit 1; }
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

if command -v cygpath >/dev/null 2>&1; then
    SANDBOX_PATH="$(cygpath -m "$SANDBOX")"
else
    SANDBOX_PATH="$SANDBOX"
fi

if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python3'
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python'
else
    echo "Python 3 is required" >&2
    exit 1
fi

export SKILL_MANAGER_DSH_AGENTS_HOME="$SANDBOX_PATH/agents-home"
export SKILL_MANAGER_DSH_HOME="$SANDBOX_PATH/missing-dsh-home"
export SKILL_MANAGER_DSH_CWD="$SANDBOX_PATH/repo/apps/web"
export SKILL_MANAGER_DSH_CLI_PATH="$SANDBOX_PATH/missing-dsh"
export SKILL_MANAGER_DSH_BUNDLED_DIR="$SANDBOX_PATH/bundled"
mkdir -p "$SANDBOX/agents-home/skills"

status="$(get_dsh_status)"
[[ "$status" == *'usable=false'* ]] || { echo 'ASSERTION FAILED: an unrelated agents directory alone made DeepSeek Harness usable' >&2; exit 1; }

export SKILL_MANAGER_DSH_HOME="$SANDBOX_PATH/dsh-home"
export SKILL_MANAGER_DSH_INDEX_PATH="$SANDBOX_PATH/index/index.json"
export SKILL_MANAGER_DSH_SETTINGS_PATH="$SANDBOX_PATH/dsh-home/settings.yaml"
mkdir -p "$SANDBOX/dsh-home/skills" \
  "$SANDBOX/dsh-home/.agent-presets/test-preset" \
  "$SANDBOX/bundled" \
  "$SANDBOX/custom" \
  "$SANDBOX/repo/.git" \
  "$SANDBOX/repo/.dsh/skills" \
  "$SANDBOX/repo/.agents/skills" \
  "$SANDBOX/repo/apps/web"
printf 'agent-presets:\n  default: test-preset\n' > "$SANDBOX/dsh-home/settings.yaml"
cat > "$SANDBOX/dsh-home/.agent-presets/test-preset/agent.cordis.yml" <<EOF
- id: skill-filesystem
  name: '@deepseek-ai/dsh-skill-filesystem'
  config:
    includeDefaultRoots: true
    watch: true
    customSkillDirs:
      - $SANDBOX_PATH/custom
- id: tool-skill
  name: '@deepseek-ai/dsh-tool-skill'
EOF

new_test_skill "$SANDBOX/dsh-home/skills/frontend-design" frontend-design 'Use when the user asks to build web UI from the user root.'
new_test_skill "$SANDBOX/dsh-home/skills/duplicate-skill" duplicate-skill 'Use when the user-dsh variant is needed.'
new_test_skill "$SANDBOX/agents-home/skills/duplicate-skill" duplicate-skill 'Use when the user-agents variant is needed.'
new_test_skill "$SANDBOX/repo/.dsh/skills/duplicate-skill" duplicate-skill 'Use when the project-dsh variant is needed.'
new_test_skill "$SANDBOX/repo/.agents/skills/duplicate-skill" duplicate-skill 'Use when the project-agents variant is needed.'
new_test_skill "$SANDBOX/custom/duplicate-skill" duplicate-skill 'Use when the custom variant is needed.'
new_test_skill "$SANDBOX/bundled/duplicate-skill" duplicate-skill 'Use when the bundled variant is needed.'
new_test_skill "$SANDBOX/repo/.agents/skills/project-helper" project-helper 'Use when the project helper is needed.'
new_test_skill "$SANDBOX/custom/custom-helper" custom-helper 'Use when the custom helper is needed.'
new_test_skill "$SANDBOX/bundled/bundled-helper" bundled-helper 'Use when the bundled helper is needed.'
new_test_skill "$SANDBOX/dsh-home/skills/model-off" model-off 'model invocation disabled' 'disable-model-invocation: true'
new_test_skill "$SANDBOX/dsh-home/skills/legacy-key" legacy-key 'legacy invocation key' 'disableModelInvocation: true'
new_test_skill "$SANDBOX/dsh-home/skills/user-off" user-off 'user invocation disabled' 'user-invocable: false'
new_test_skill "$SANDBOX/dsh-home/skills/.system/sys-hidden" sys-hidden 'reserved namespace'
printf '%s\n' '---' 'name: flat-skill' 'description: flat markdown skill' '---' '' '# flat' > "$SANDBOX/dsh-home/skills/flat-skill.md"

state="$(get_dsh_preset_state)"
assert_contains "$state" 'provider=true' 'preset provider must be detected'
assert_contains "$state" 'consumer=tool-skill' 'preset consumer must be detected'

roots="$(get_dsh_discovery_roots "$SKILL_MANAGER_DSH_CWD")"
assert_contains "$roots" $'project\tproject-dsh\tfalse\tfalse\t100' 'project-dsh root at rank 100'
assert_contains "$roots" $'project\tproject-agents\tfalse\tfalse\t200' 'project-agents root at rank 200'
assert_contains "$roots" $'custom\tcustom\tfalse\tfalse\t300' 'custom root at rank 300'
assert_contains "$roots" $'user\tuser-dsh\ttrue\tfalse\t400\twritable' 'user-dsh root at rank 400 writable'
assert_contains "$roots" $'user\tuser-agents\ttrue\tfalse\t500\twritable' 'user-agents root at rank 500 writable'
assert_contains "$roots" $'deployment\tbundled\tfalse\tfalse\t600\tdiagnostic-only' 'bundled root at rank 600 diagnostic-only'
[[ "$roots" == *$'protected=true'* ]] && { echo 'ASSERTION FAILED: DSH roots must never be protected' >&2; exit 1; }
assert_contains "$roots" $'custom\tcustom\tfalse\tfalse\t300\tdiagnostic-only' 'custom root write_policy diagnostic-only'
assert_contains "$roots" $'user\tuser-agents\ttrue\tfalse\t500\twritable/shared' 'user-agents root write_policy writable/shared'

status="$(get_dsh_status)"
[[ "$status" == *'usable=true'* ]] || { echo 'ASSERTION FAILED: DSH home state was not usable' >&2; exit 1; }
[[ "$status" == *'dsh_home_detected=true'* ]] || { echo 'ASSERTION FAILED: dsh_home_detected missing' >&2; exit 1; }
[[ "$status" == *'consumer=tool-skill'* ]] || { echo 'ASSERTION FAILED: consumer missing from status' >&2; exit 1; }
[[ "$status" == *'detected=true'* ]] || { echo 'ASSERTION FAILED: detected missing' >&2; exit 1; }
[[ "$status" == *'config_detected=true'* ]] || { echo 'ASSERTION FAILED: config_detected missing' >&2; exit 1; }
[[ "$status" == *'package_detected=false'* ]] || { echo 'ASSERTION FAILED: package_detected should be false' >&2; exit 1; }
[[ "$status" == *'consumer_detected=true'* ]] || { echo 'ASSERTION FAILED: consumer_detected missing' >&2; exit 1; }
[[ "$status" == *'skill_runtime_ready=true'* ]] || { echo 'ASSERTION FAILED: skill_runtime_ready missing' >&2; exit 1; }
[[ "$status" == *'usable_reason=detected-and-runtime-ready'* ]] || { echo 'ASSERTION FAILED: usable_reason missing' >&2; exit 1; }

refresh_output="$(bash "$ROOT/lib/catalog.sh" --refresh --agent deepseek-harness 2>&1)" || { echo "ASSERTION FAILED: DSH refresh failed: $refresh_output" >&2; exit 1; }
"$PYTHON_BIN" - "$SKILL_MANAGER_DSH_INDEX_PATH" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
by_name = {item['name']: item for item in data['skills']}
dup = by_name['duplicate-skill']['agents']['deepseek-harness']
assert len(dup['paths']) == 6, 'duplicate must retain every discovery path'
assert dup['precedence'] == 'within-layer-rank', dup['precedence']
assert dup['winner_confidence'] == 'within-layer-only', dup['winner_confidence']
assert dup['runtime_winner'] is None, 'runtime winner must stay null'
assert dup['metadata_conflict'] is True, 'metadata_conflict must be True'
assert dup['predicted_winner']['rank'] == 100, dup['predicted_winner']
assert dup['predicted_winner']['path'].replace('\\', '/').endswith('repo/.dsh/skills/duplicate-skill'), dup['predicted_winner']
assert dup['visible'] is True, dup['reason']
model = by_name['model-off']['agents']['deepseek-harness']
assert model['discoverable'] is True and model['eligible'] is False and model['visible'] is False and model['reason'] == 'not-model-invocable'
legacy = by_name['legacy-key']['agents']['deepseek-harness']
assert legacy['discoverable'] is False and legacy['paths'][0]['dsh_valid'] is False
assert 'sys-hidden' not in by_name, '.system must not be indexed'
assert any(x.replace('\\', '/').endswith('dsh-home/skills/.system') for x in data['dsh_reserved_namespace']), data['dsh_reserved_namespace']
assert 'flat-skill' in by_name, 'flat <name>.md must be discovered'
bundled = by_name['bundled-helper']['agents']['deepseek-harness']
assert bundled['visible'] is True, 'bundled skills are catalog-visible'
assert bundled['protected'] is False, 'bundled must not be marked protected (DSH fact)'
assert bundled['paths'][0]['write_policy'] == 'diagnostic-only', 'write policy is a separate skill-manager field'
assert data['dsh_preset']['consumer'] == 'tool-skill' and data['dsh_preset']['provider_enabled'] is True, data['dsh_preset']
assert dup['visibility_confidence'] == 'inferred', dup
assert dup['visibility_status'] == 'expected', dup
assert dup['winner_basis'] == 'filesystem-rank-root-order', dup
assert dup['providers'] == ['filesystem'], dup
assert dup['paths'][0]['platform_protected'] == 'false', dup['paths'][0]
assert next(p for p in dup['paths'] if p['class'] == 'bundled')['platform_protected'] == 'unknown'
assert next(p for p in dup['paths'] if p['class'] == 'custom')['platform_protected'] == 'unknown'
custom = by_name['custom-helper']['agents']['deepseek-harness']
assert custom['paths'][0]['platform_protected'] == 'unknown' and custom['paths'][0]['write_policy'] == 'diagnostic-only', custom
useroff = by_name['user-off']['agents']['deepseek-harness']
assert useroff['discoverable'] and useroff['eligible'] and useroff['visible'] and (not useroff['invocation']['user_invocable']) and useroff['invocation']['model_invocable'], useroff
s = data['dsh_duplicate_summary']
assert s['physical_skill_entries'] == 14, s
assert s['unique_skill_names'] == 9, s
assert s['duplicate_names'] == 1, s
assert s['duplicate_variants'] == 6, s
assert s['duplicate_candidate_variants'] == 6, s
assert s['predicted_winners'] == 8, s
assert s['confirmed_runtime_winners'] == 0, s
PY

find_output="$(bash "$ROOT/lib/catalog.sh" --find '做网页 UI' --agent deepseek-harness)"
assert_contains "$find_output" 'frontend-design' 'DSH Find must reuse the shared scorer'

doctor_output="$(bash "$ROOT/lib/catalog.sh" --doctor --agent deepseek-harness)"
assert_contains "$doctor_output" 'Duplicate DeepSeek Harness Skill name' 'DSH Doctor must report duplicates'
assert_contains "$doctor_output" 'predicted within-layer winner' 'DSH Doctor must report the predicted winner'
assert_contains "$doctor_output" 'does not claim a runtime winner' 'DSH Doctor must not claim a runtime winner'
assert_contains "$doctor_output" 'reserved .system namespace' 'DSH Doctor must note the reserved namespace'
assert_contains "$doctor_output" 'watch:' 'DSH Doctor must report watch state'
assert_contains "$doctor_output" 'no restart needed' 'watch=true must not recommend a restart'
assert_contains "$doctor_output" 'catalog visibility: expected' 'DSH Doctor must say visibility is expected, not confirmed'

set +e
bundled_fix_output="$(bash "$ROOT/lib/catalog.sh" --fix --agent deepseek-harness --name bundled-helper --dry-run 2>&1)"
bundled_fix_status=$?
legacy_fix_output="$(bash "$ROOT/lib/catalog.sh" --fix --agent deepseek-harness --name legacy-key --dry-run 2>&1)"
legacy_fix_status=$?
set -e
[[ "$bundled_fix_status" -ne 0 && "$bundled_fix_output" == *'diagnostic-only'* ]] || { echo 'ASSERTION FAILED: DSH fix dry-run did not refuse a bundled skill' >&2; exit 1; }
[[ "$legacy_fix_status" -ne 0 && "$legacy_fix_output" == *'DSH would reject'* ]] || { echo 'ASSERTION FAILED: DSH fix dry-run did not refuse a rejected skill' >&2; exit 1; }

mkdir -p "$SANDBOX/dsh-home/.agent-presets/no-consumer"
cat > "$SANDBOX/dsh-home/.agent-presets/no-consumer/agent.cordis.yml" <<EOF
- id: skill-filesystem
  name: '@deepseek-ai/dsh-skill-filesystem'
EOF
export SKILL_MANAGER_DSH_PRESET='no-consumer'
refresh_output="$(bash "$ROOT/lib/catalog.sh" --refresh --agent deepseek-harness 2>&1)" || { echo "ASSERTION FAILED: no-consumer refresh failed: $refresh_output" >&2; exit 1; }
"$PYTHON_BIN" - "$SKILL_MANAGER_DSH_INDEX_PATH" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
entry = next(item for item in data['skills'] if item['name'] == 'frontend-design')['agents']['deepseek-harness']
assert entry['visible'] is False and entry['conditional'] is True and entry['reason'] == 'no-catalog-consumer-mounted', entry
PY
status_nc="$(get_dsh_status)"
[[ "$status_nc" == *'usable=false'* ]] || { echo 'ASSERTION FAILED: no-consumer usable should be false' >&2; exit 1; }
[[ "$status_nc" == *'skill_runtime_ready=false'* ]] || { echo 'ASSERTION FAILED: no-consumer runtime_ready should be false' >&2; exit 1; }
[[ "$status_nc" == *'usable_reason=no-catalog-consumer-mounted'* ]] || { echo 'ASSERTION FAILED: no-consumer usable_reason' >&2; exit 1; }
unset SKILL_MANAGER_DSH_PRESET

mkdir -p "$SANDBOX/bin"
printf '#!/usr/bin/env sh\nexit 0\n' > "$SANDBOX/bin/dsh"
chmod +x "$SANDBOX/bin/dsh"
export SKILL_MANAGER_DSH_CLI_PATH="$SANDBOX_PATH/bin/dsh"
status="$(get_dsh_status)"
[[ "$status" == *'cli_resolved=true'* && "$status" == *'usable=true'* && "$status" == *'executable_test=not-run'* ]] || {
  echo 'ASSERTION FAILED: fake CLI detection status incorrect' >&2; exit 1;
}

# Phase 5: a ~/.dsh home with no preset provider/consumer must NOT be usable.
mkdir -p "$SANDBOX/bare-dsh-home/skills"
export SKILL_MANAGER_DSH_HOME="$SANDBOX_PATH/bare-dsh-home"
export SKILL_MANAGER_DSH_SETTINGS_PATH="$SANDBOX_PATH/bare-dsh-home/settings.yaml"
unset SKILL_MANAGER_DSH_PRESET
export SKILL_MANAGER_DSH_CLI_PATH="$SANDBOX_PATH/missing-dsh.exe"
status_bare="$(get_dsh_status)"
[[ "$status_bare" == *'dsh_home_detected=true'* && "$status_bare" == *'detected=true'* ]] || { echo 'ASSERTION FAILED: bare home detected' >&2; exit 1; }
[[ "$status_bare" == *'provider_enabled=false'* ]] || { echo 'ASSERTION FAILED: bare home no provider' >&2; exit 1; }
[[ "$status_bare" == *'skill_runtime_ready=false'* ]] || { echo 'ASSERTION FAILED: bare home not runtime-ready' >&2; exit 1; }
[[ "$status_bare" == *'usable=false'* ]] || { echo 'ASSERTION FAILED: bare home must not be usable' >&2; exit 1; }
[[ "$status_bare" == *'usable_reason=provider-not-enabled'* ]] || { echo 'ASSERTION FAILED: bare home usable_reason' >&2; exit 1; }

echo 'PASS: DeepSeek Harness root, detection, duplicate, visibility, doctor and fix tests'