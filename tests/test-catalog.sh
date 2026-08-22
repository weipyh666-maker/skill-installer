#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/lib/catalog.sh"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export CLAUDE_SKILLS_DIR="$SANDBOX/sources"
export CLAUDE_SKILLS_LINK_DIR="$SANDBOX/links"
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

sed -i '/"name": "image-skill"/,/"source":/ s/"source": "unknown"/"source": "local"/' "$CLAUDE_SKILLS_DIR/installed-skills-index.json"
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

set +e
doctor_output="$(bash "$CATALOG" --doctor)"
doctor_status=$?
set -e
[[ "$doctor_status" -ne 0 ]]
doctor_output="${doctor_output//$'\r'/}"
[[ "$doctor_output" == *broken-skill* ]]

echo 'PASS: catalog regression tests'
