#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/lib/catalog.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export CLAUDE_SKILLS_DIR="$SANDBOX/sources"
export CLAUDE_SKILLS_LINK_DIR="$SANDBOX/links"
export SKILL_MANAGER_CODEX_HOME="$SANDBOX/codex-home"
export SKILL_MANAGER_CODEX_USER_HOME="$SANDBOX/codex-user"
export SKILL_MANAGER_CODEX_CWD="$SANDBOX"
export SKILL_MANAGER_CODEX_INDEX_PATH="$SANDBOX/codex-index.json"
mkdir -p "$CLAUDE_SKILLS_DIR" "$CLAUDE_SKILLS_LINK_DIR/image-skill" "$CLAUDE_SKILLS_LINK_DIR/slides-skill"
mkdir -p "$CLAUDE_SKILLS_LINK_DIR/document-skill" "$CLAUDE_SKILLS_LINK_DIR/broken-skill"
mkdir -p "$CLAUDE_SKILLS_LINK_DIR/multiline-skill"
mkdir -p "$CLAUDE_SKILLS_LINK_DIR/literal-skill"

cat > "$CLAUDE_SKILLS_LINK_DIR/image-skill/SKILL.md" <<'EOF'
---
name: image-skill
description: Use when identifying images, reading screenshots, or performing image understanding.
---
# image-skill
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/document-skill/SKILL.md" <<'EOF'
---
name: document-skill
description: 用于文档转换和嵌入 image assets。
---
# document-skill
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/slides-skill/SKILL.md" <<'EOF'
---
name: slides-skill
description: Use when creating presentations, slide decks, or PPTX files.
---
# slides-skill
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/multiline-skill/SKILL.md" <<'EOF'
---
name: multiline-skill
description: >
  Use when handling multi-line descriptions.
  This text should remain in the description.
---
# Body must not enter the description.
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/literal-skill/SKILL.md" <<'EOF'
---
name: literal-skill
description: |
  Literal descriptions remain searchable.
  Body text must stay outside.
---
# Literal body
EOF

refresh_output="$(bash "$CATALOG" --refresh)"
[[ -f "$CLAUDE_SKILLS_DIR/installed-skills-index.json" ]]
grep -q '"name": "image-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"status": "unknown"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"source": "unknown"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
! grep -Eq '"source_path": "([A-Za-z]:|/)|"link_path": "([A-Za-z]:|/)' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"

PYTHON_BIN=''
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python3'
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python'
fi
"$PYTHON_BIN" - <<'PY'
import os, re, pathlib
skills_dir = pathlib.Path(os.environ.get("CLAUDE_SKILLS_DIR", "")).expanduser()
index_path = skills_dir / "installed-skills-index.json"
text = index_path.read_text(encoding="utf-8")
text = re.sub(r'("name":\s*"image-skill"[\s\S]*?"source":\s*)"unknown"', r'\1"local"', text, count=1)
index_path.write_text(text, encoding="utf-8")
PY
bash "$CATALOG" --refresh >/dev/null
awk '/"name": "image-skill"/,/"source":/ { if ($0 ~ /"source":/) print }' "$CLAUDE_SKILLS_DIR/installed-skills-index.json" | grep '"source": "unknown"' >/dev/null
grep -A 8 '"name": "multiline-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json" | grep -v -- '---' >/dev/null
! grep -A 8 '"name": "multiline-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json" | grep -q '# Body must not'
! grep -A 8 '"name": "literal-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json" | grep -q '# Literal body'

find_output="$(bash "$CATALOG" --find image)"
[[ "$find_output" == *"image-skill"* ]]
find_chinese_output="$(bash "$CATALOG" --find 图片识别)"
[[ "$find_chinese_output" == *"image-skill"* ]]
[[ "$find_chinese_output" != *"document-skill"* ]]

json_output="$(bash "$CATALOG" --json --list)"
[[ "$json_output" == *'"description"'* ]]

show_output="$(bash "$CATALOG" --show slides-skill)"
[[ "$show_output" == *"presentations"* ]]
[[ "$show_output" == *"unknown"* ]]

# V3.0 Schema & Capabilities & Manual Scan Verification
grep -q '"schema_version": 3' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"capabilities":' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"discovered_at":' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"category": "media"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"visible": true' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"

# Manual skill discovery test
mkdir -p "$CLAUDE_SKILLS_DIR/manual-skill"
cat > "$CLAUDE_SKILLS_DIR/manual-skill/SKILL.md" <<'EOF'
---
name: manual-skill
description: Use when testing manual skill placement.
---
# manual-skill
EOF
bash "$CATALOG" --refresh >/dev/null
grep -q '"name": "manual-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"provenance": "unknown"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"

# Capabilities command test
cap_output="$(bash "$CATALOG" --capabilities)"
[[ "$cap_output" =~ "Your Agent currently has" ]]
[[ "$cap_output" =~ "broken" ]]
[[ "$cap_output" =~ "Broken (" ]]
[[ "$cap_output" =~ "broken-skill" ]]

# Missing skill retention test
rm -rf "$CLAUDE_SKILLS_LINK_DIR/slides-skill"
bash "$CATALOG" --refresh >/dev/null
grep -q '"name": "slides-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
grep -q '"health": "missing"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"

# V2.1 Enhancements
mkdir -p "$CLAUDE_SKILLS_LINK_DIR/frontend-design" "$CLAUDE_SKILLS_LINK_DIR/short-skill"
cat > "$CLAUDE_SKILLS_LINK_DIR/frontend-design/SKILL.md" <<'EOF'
---
name: frontend-design
description: Create high-quality frontend interfaces with web UI layouts and styles.
---
# frontend-design
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/short-skill/SKILL.md" <<'EOF'
---
name: short-skill
description: Short desc
---
# short-skill
EOF

bash "$CATALOG" --refresh >/dev/null

# 1. Chinese find query
find_ui_output="$(bash "$CATALOG" --find "做网页 UI")"
[[ "$find_ui_output" =~ "frontend-design" ]]
[[ "$find_ui_output" =~ "score:" ]]

# 2. English image recognition compound AND filtering
find_img_output="$(bash "$CATALOG" --find "image recognition")"
[[ "$find_img_output" =~ "image-skill" ]]
[[ ! "$find_img_output" =~ "document-skill" ]]

# 3. Empty find query
find_empty_output="$(bash "$CATALOG" --find "nonexistent-query-xyz")"
[[ "$find_empty_output" =~ 'No matching skills for "nonexistent-query-xyz"' ]]

# 4. Doctor single skill
doctor_single_output="$(bash "$CATALOG" --doctor --name frontend-design)"
[[ "$doctor_single_output" =~ "Installation" ]]
[[ "$doctor_single_output" =~ "Structure" ]]
[[ "$doctor_single_output" =~ "Discovery" ]]
[[ "$doctor_single_output" =~ "Trigger quality" ]]

# 5. Doctor trigger quality check on short description
doctor_short_output="$(bash "$CATALOG" --doctor --name short-skill)"
[[ "$doctor_short_output" =~ "Description too short" ]]

# 6. Doctor global output format
set +e
doctor_output="$(bash "$CATALOG" --doctor)"
doctor_status=$?
set -e
[[ "$doctor_status" -ne 0 ]]
doctor_output="${doctor_output//$'\r'/}"
[[ "$doctor_output" =~ "doctor: scanned" ]]
[[ "$doctor_output" =~ "healthy:" ]]
[[ "$doctor_output" =~ "broken:" ]]
[[ "$doctor_output" =~ "missing:" ]]

# V2.2 Enhancements
# 1. fix --dry-run --name frontend-design
fix_dry_output="$(bash "$CATALOG" --fix --dry-run --name frontend-design)"
[[ "$fix_dry_output" =~ "[proposed] frontend-design" ]]
[[ "$fix_dry_output" =~ "description (before):" ]]
[[ "$fix_dry_output" =~ "description (after):" ]]
[[ "$fix_dry_output" =~ "capabilities (added):" ]]
[[ "$fix_dry_output" =~ "category (added):" ]]
[[ "$fix_dry_output" =~ "backup would go to:" ]]

# 2. fix --name frontend-design --yes
fix_apply_output="$(bash "$CATALOG" --fix --name frontend-design --yes)"
[[ "$fix_apply_output" =~ "fixed frontend-design:" ]]
[[ "$fix_apply_output" =~ "trigger quality:" ]]

ls "$CLAUDE_SKILLS_DIR/.backups/frontend-design-"*"-SKILL.md" >/dev/null 2>&1
grep -q 'Use when the user wants to create' "$CLAUDE_SKILLS_LINK_DIR/frontend-design/SKILL.md"
grep -q 'capabilities:' "$CLAUDE_SKILLS_LINK_DIR/frontend-design/SKILL.md"
grep -q 'category:' "$CLAUDE_SKILLS_LINK_DIR/frontend-design/SKILL.md"

# 3. fix on short-skill (Case D)
fix_short_output="$(bash "$CATALOG" --fix --name short-skill --yes)"
[[ "$fix_short_output" =~ "description too short" ]]

# 4. Description rewrite cases A, B, C, E
mkdir -p "$CLAUDE_SKILLS_LINK_DIR/case-a-skill" "$CLAUDE_SKILLS_LINK_DIR/case-b-skill" "$CLAUDE_SKILLS_LINK_DIR/case-c-skill" "$CLAUDE_SKILLS_LINK_DIR/case-e-skill"
cat > "$CLAUDE_SKILLS_LINK_DIR/case-a-skill/SKILL.md" <<'EOF'
---
name: case-a-skill
description: Use when testing case a description already compliant.
---
# case-a-skill
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/case-b-skill/SKILL.md" <<'EOF'
---
name: case-b-skill
description: Build and deploy full-stack web applications with modern architecture, automated CI/CD pipelines, and high-quality frontend styling.
---
# case-b-skill
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/case-c-skill/SKILL.md" <<'EOF'
---
name: case-c-skill
description: This skill should be used when the user needs to transcribe audio recordings.
---
# case-c-skill
EOF

cat > "$CLAUDE_SKILLS_LINK_DIR/case-e-skill/SKILL.md" <<'EOF'
---
name: case-e-skill
description: General purpose helper that performs specialized tasks for workflows.
---
# case-e-skill
EOF

bash "$CATALOG" --refresh >/dev/null

fix_batch_output="$(bash "$CATALOG" --fix --yes)"
[[ "$fix_batch_output" =~ "fixed case-b-skill:" ]]
[[ "$fix_batch_output" =~ "fixed case-c-skill:" ]]

grep -q 'Use when the user needs to transcribe audio recordings' "$CLAUDE_SKILLS_LINK_DIR/case-c-skill/SKILL.md"
grep -q 'Use when the user wants to build and deploy' "$CLAUDE_SKILLS_LINK_DIR/case-b-skill/SKILL.md"

# 5. Doctor verification after fix
doctor_after_output="$(bash "$CATALOG" --doctor --name case-b-skill)"
[[ "$doctor_after_output" =~ "Trigger description looks Claude-discoverable" ]]

# 6. V3.0 Multi-Agent Tests
# A. Default agent claude
caps_claude="$(bash "$CATALOG" --capabilities --agent claude)"
[[ "$caps_claude" =~ "Development" ]]

# B. Stub agent codex in capabilities
caps_codex="$(bash "$CATALOG" --capabilities --agent codex)"
[[ "$caps_codex" =~ "No visible skills for agent 'codex'" ]]

# C. Isolated Codex roots do not borrow Claude entries.
caps_all="$(bash "$CATALOG" --capabilities --agent codex --all-agents)"
[[ ! "$caps_all" =~ "Development" ]]

# D. CLAUDE_SKILLS_AGENT=codex environment variable
caps_codex_env="$(CLAUDE_SKILLS_AGENT=codex bash "$CATALOG" --capabilities)"
[[ "$caps_codex_env" =~ "No visible skills for agent 'codex'" ]]

# E. Show command displays per-agent visibility
show_out="$(bash "$CATALOG" --show case-b-skill)"
[[ "$show_out" =~ "agents.claude.visible: True" ]]
[[ "$show_out" =~ "agents.codex.visible: False" ]]
[[ "$show_out" =~ "agents.antigravity.visible: False" ]]

# F. Schema v3 migration from legacy v2 JSON
cat > "$CLAUDE_SKILLS_DIR/installed-skills-index.json" <<'EOF'
{
  "schema_version": 2,
  "generated_at": "2026-08-23T00:00:00Z",
  "skills": [
    {
      "name": "legacy-skill",
      "install_name": "legacy-skill",
      "description": "Legacy test skill",
      "status": "ok",
      "health": "ok"
    }
  ]
}
EOF

# 7. V3.1 Find & Match Reason Tests
mkdir -p "$CLAUDE_SKILLS_LINK_DIR/slides-skill"
cat > "$CLAUDE_SKILLS_LINK_DIR/slides-skill/SKILL.md" <<'EOF'
---
name: slides-skill
description: Use when creating presentations, slide decks, or PPTX files.
---
# slides-skill
EOF
bash "$CATALOG" --refresh >/dev/null

# A. Match reason line presence
find_reason_out="$(bash "$CATALOG" --find "image" --limit 2)"
[[ "$find_reason_out" =~ "matched:" ]]

# B. Chinese query synonym expansion (PPT -> slides-skill)
find_ppt_out="$(bash "$CATALOG" --find "PPT" --limit 2)"
[[ "$find_ppt_out" =~ "slides-skill" ]]

# C. Compound AND filtering (image recognition does not match document)
find_compound_out="$(bash "$CATALOG" --find "image recognition")"
[[ "$find_compound_out" =~ "image-skill" ]]
[[ ! "$find_compound_out" =~ "document-skill" ]]

echo 'PASS: catalog regression tests'


