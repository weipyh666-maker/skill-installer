#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/adapters/_base.sh"
source "$ROOT/adapters/codex/paths.sh"
source "$ROOT/adapters/codex/detect.sh"

new_test_skill() {
  mkdir -p "$1"
  printf '%s\n' '---' "name: $2" "description: $3" '---' '' "# $2" > "$1/SKILL.md"
}

assert_eq() {
  [[ "$1" == "$2" ]] || { echo "ASSERTION FAILED: $3 (expected '$2', got '$1')" >&2; exit 1; }
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

export SKILL_MANAGER_CODEX_USER_HOME="$SANDBOX_PATH/user-home"
export SKILL_MANAGER_CODEX_HOME="$SANDBOX_PATH/codex-home"
export SKILL_MANAGER_CODEX_CWD="$SANDBOX_PATH/repo/apps/web"
export SKILL_MANAGER_CODEX_INDEX_PATH="$SANDBOX_PATH/index/codex-index.json"
export SKILL_MANAGER_CODEX_CLI_PATH="$SANDBOX_PATH/missing-codex"
export SKILL_MANAGER_CODEX_PLUGIN_ROOT="$SANDBOX_PATH/plugin-cache"
export SKILL_MANAGER_CODEX_ADMIN_ROOT="$SANDBOX_PATH/admin-root"
mkdir -p "$SANDBOX/user-home/.agents/skills" \
  "$SANDBOX/repo/.git" \
  "$SANDBOX/repo/.agents/skills" \
  "$SANDBOX/repo/apps/.agents/skills" \
  "$SANDBOX/repo/apps/web"
mkdir -p "$SKILL_MANAGER_CODEX_ADMIN_ROOT/child"

roots="$(get_codex_discovery_roots "$SKILL_MANAGER_CODEX_CWD")"
status="$(get_codex_status)"
[[ "$status" == *'usable=false'* ]] || { echo 'ASSERTION FAILED: .agents root alone made Codex usable' >&2; exit 1; }
mkdir -p "$SANDBOX/codex-home/skills/.system"
roots="$(get_codex_discovery_roots "$SKILL_MANAGER_CODEX_CWD")"
[[ "$roots" == *$'user\tagents'* ]] || { echo 'ASSERTION FAILED: user root missing' >&2; exit 1; }
[[ "$roots" == *$'compatibility\tcompatibility'* ]] || { echo 'ASSERTION FAILED: compatibility root missing' >&2; exit 1; }
[[ "$roots" == *$'system\tsystem'* ]] || { echo 'ASSERTION FAILED: system root missing' >&2; exit 1; }
[[ "$roots" == *$'admin\tadmin\tfalse\ttrue'* ]] || { echo 'ASSERTION FAILED: admin root missing or not protected' >&2; exit 1; }

status="$(get_codex_status)"
[[ "$status" == *'usable=true'* ]] || { echo 'ASSERTION FAILED: Codex-specific home state was not usable' >&2; exit 1; }

new_test_skill "$SANDBOX/user-home/.agents/skills/frontend-design" frontend-design 'Use when the user asks to build web UI from the user root.'
new_test_skill "$SANDBOX/user-home/.agents/skills/duplicate-skill" duplicate-skill 'Use when the user needs the user variant.'
new_test_skill "$SANDBOX/codex-home/skills/duplicate-skill" duplicate-skill 'Use when the user needs the compatibility variant.'
new_test_skill "$SANDBOX/repo/.agents/skills/project-helper" project-helper 'Use when the repository root helper is needed.'
new_test_skill "$SANDBOX/repo/apps/.agents/skills/app-helper" app-helper 'Use when the application helper is needed.'
new_test_skill "$SANDBOX/codex-home/skills/.system/openai-docs" openai-docs 'Use when official Codex documentation is needed.'
new_test_skill "$SANDBOX/plugin-cache/example/skills/plugin-helper" plugin-helper 'Use when a plugin supplied workflow is needed.'
external_skill_path="$SANDBOX_PATH/external/external-helper/SKILL.md"
export EXTERNAL_SKILL_PATH="$external_skill_path"
cat > "$SANDBOX/codex-home/config.toml" <<EOF
[[skills.config]]
path = "$SANDBOX_PATH/repo/apps/.agents/skills/app-helper/SKILL.md"
enabled = false

[[skills.config]]
path = "$external_skill_path"
enabled = true
EOF

refresh_output="$(bash "$ROOT/lib/catalog.sh" --refresh --agent codex 2>&1)" || { echo "ASSERTION FAILED: Codex refresh failed: $refresh_output" >&2; exit 1; }
"$PYTHON_BIN" - "$SKILL_MANAGER_CODEX_INDEX_PATH" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding='utf-8'))
by_name = {item['name']: item for item in data['skills']}
duplicate = by_name['duplicate-skill']['agents']['codex']
assert len(duplicate['paths']) == 2
assert duplicate['precedence'] == 'unknown'
assert duplicate['metadata_conflict'] is True
disabled = by_name['app-helper']['agents']['codex']
assert disabled['visible'] is False and disabled['enabled'] is False and disabled['reason'] == 'disabled-by-codex-config'
ext_expected = os.path.realpath(os.environ['EXTERNAL_SKILL_PATH']).replace('\\', '/').lower()
assert any(os.path.realpath(x['path']).replace('\\', '/').lower() == ext_expected and x['status'] == 'unknown' for x in data['codex_config_external'])
assert by_name['openai-docs']['agents']['codex']['protected'] is True
plugin = by_name['plugin-helper']['agents']['codex']
assert plugin['visible'] is False and plugin['reason'] == 'plugin-enablement-dependent'
PY
find_output="$(bash "$ROOT/lib/catalog.sh" --find '做网页 UI' --agent codex)"
[[ "$find_output" == *frontend-design* ]] || { echo 'ASSERTION FAILED: Codex Find missing frontend-design' >&2; exit 1; }
doctor_output="$(bash "$ROOT/lib/catalog.sh" --doctor --agent codex)"
[[ "$doctor_output" == *'Duplicate Codex Skill name'* ]] || { echo 'ASSERTION FAILED: Codex Doctor missing duplicate warning' >&2; exit 1; }
set +e
protected_fix_output="$(bash "$ROOT/lib/catalog.sh" --fix --agent codex --name openai-docs --dry-run 2>&1)"
protected_fix_status=$?
set -e
[[ "$protected_fix_status" -ne 0 && "$protected_fix_output" == *'protected Codex SYSTEM Skill'* ]] || { echo 'ASSERTION FAILED: Codex fix dry-run did not refuse a system skill' >&2; exit 1; }

mkdir -p "$SANDBOX/bin"
printf '#!/usr/bin/env sh\nexit 0\n' > "$SANDBOX/bin/codex"
chmod +x "$SANDBOX/bin/codex"
export SKILL_MANAGER_CODEX_CLI_PATH="$SANDBOX_PATH/bin/codex"
status="$(get_codex_status)"
[[ "$status" == *'cli_resolved=true'* && "$status" == *'usable=true'* && "$status" == *'executable_test=not-run'* ]] || {
  echo 'ASSERTION FAILED: fake CLI detection status incorrect' >&2; exit 1;
}

echo 'PASS: Codex root and detection tests'
