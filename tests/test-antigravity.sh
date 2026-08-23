#!/usr/bin/env bash
set -euo pipefail

export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/lib/catalog.sh"
INSTALL="$ROOT/lib/install.sh"

source "$ROOT/adapters/_base.sh"
source "$ROOT/adapters/antigravity/paths.sh"
source "$ROOT/adapters/antigravity/detect.sh"

assert_true() {
    local condition="$1"
    local message="$2"
    if [ "$condition" != "1" ]; then
        echo "ASSERTION FAILED: $message" >&2
        exit 1
    fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

if command -v cygpath >/dev/null 2>&1; then
    SANDBOX_PATH="$(cygpath -m "$SANDBOX")"
else
    SANDBOX_PATH="$SANDBOX"
fi

export ANTIGRAVITY_SKILLS_DIR="$SANDBOX_PATH/agents_skills"
export ANTIGRAVITY_SKILLS_LINK_DIR="$SANDBOX_PATH/agents_skills"
export ANTIGRAVITY_BUILTIN_DIR="$SANDBOX_PATH/builtin_skills"
export ANTIGRAVITY_SKILLS_INDEX_PATH="$SANDBOX_PATH/agents_skills/installed-skills-index.json"

export CLAUDE_SKILLS_DIR="$SANDBOX_PATH/claude_skills"
export CLAUDE_SKILLS_LINK_DIR="$SANDBOX_PATH/claude_links"
export CLAUDE_SKILLS_INDEX_PATH="$SANDBOX_PATH/claude_skills/installed-skills-index.json"

mkdir -p "$SANDBOX/agents_skills" "$SANDBOX/builtin_skills" "$SANDBOX/claude_skills" "$SANDBOX/claude_links" "$SANDBOX/fixtures"

echo "=========================================="
echo "Running Antigravity Adapter Tests (Bash)"
echo "=========================================="

# 1. Detection test
if detect_antigravity; then
    echo "  + Antigravity detect: PASS"
else
    echo "ASSERTION FAILED: Antigravity should be detected with env override" >&2
    exit 1
fi

# 2. Populate sample skills in Antigravity global dir
mkdir -p "$SANDBOX/agents_skills/frontend-design"
cat > "$SANDBOX/agents_skills/frontend-design/SKILL.md" <<'EOF'
---
name: frontend-design
description: Use when the user asks to build web components, pages, artifacts, or web UI.
capabilities: [frontend, ui, web, design]
category: development
---
# Frontend Design
EOF

mkdir -p "$SANDBOX/agents_skills/pdf"
cat > "$SANDBOX/agents_skills/pdf/SKILL.md" <<'EOF'
---
name: pdf
description: Use when the user wants to do anything with PDF files.
capabilities: [pdf, document]
category: documents
---
# PDF
EOF

# 3. Refresh and Scan
bash "$CATALOG" --refresh --agent antigravity >/dev/null

if [ -f "$SANDBOX/agents_skills/installed-skills-index.json" ]; then
    echo "  + Refresh & scan: PASS"
else
    echo "ASSERTION FAILED: Antigravity index file not generated" >&2
    exit 1
fi

# 4. List and Capabilities
list_out="$(bash "$CATALOG" --list --agent antigravity)"
if [[ "$list_out" =~ "frontend-design" ]] && [[ "$list_out" =~ "pdf" ]]; then
    echo "  + List command: PASS"
else
    echo "ASSERTION FAILED: List output missing skills" >&2
    exit 1
fi

caps_out="$(bash "$CATALOG" --capabilities --agent antigravity)"
if [[ "$caps_out" =~ "Development" ]] && [[ "$caps_out" =~ "Documents" ]]; then
    echo "  + Capabilities command: PASS"
else
    echo "ASSERTION FAILED: Capabilities missing categories" >&2
    exit 1
fi

# 5. Show command
show_out="$(bash "$CATALOG" --show frontend-design --agent antigravity)"
if [[ "$show_out" =~ "agents.antigravity.visible: True" ]]; then
    echo "  + Show command: PASS"
else
    echo "ASSERTION FAILED: Show output missing antigravity visibility" >&2
    exit 1
fi

# 6. Find command
find_out="$(bash "$CATALOG" --find "做网页 UI" --agent antigravity)"
if [[ "$find_out" =~ "frontend-design" ]]; then
    echo "  + Find command: PASS"
else
    echo "ASSERTION FAILED: Find output missing frontend-design" >&2
    exit 1
fi

# 7. Doctor command
doc_global="$(bash "$CATALOG" --doctor --agent antigravity)"
if [[ "$doc_global" =~ "antigravity" ]] && [[ "$doc_global" =~ "healthy: 2" ]]; then
    echo "  + Doctor global: PASS"
else
    echo "ASSERTION FAILED: Doctor global output incorrect" >&2
    exit 1
fi

# 8. Install Dry-Run & Real Install
mkdir -p "$SANDBOX/fixtures/new-helper-skill"
cat > "$SANDBOX/fixtures/new-helper-skill/SKILL.md" <<'EOF'
---
name: new-helper-skill
description: Use when the user asks for helper utilities.
---
# Helper
EOF

# Dry-Run
dry_out="$(bash "$INSTALL" --local "$SANDBOX/fixtures/new-helper-skill" --name new-helper-skill --agent antigravity --dry-run)"
if [[ "$dry_out" =~ "DRY RUN" ]]; then
    echo "  + Install dry-run: PASS"
else
    echo "ASSERTION FAILED: Install dry-run failed" >&2
    exit 1
fi

# Real Install
inst_out="$(bash "$INSTALL" --local "$SANDBOX/fixtures/new-helper-skill" --name new-helper-skill --agent antigravity)"
if [[ "$inst_out" =~ "source installed at" ]] && [ -f "$SANDBOX/agents_skills/new-helper-skill/SKILL.md" ]; then
    echo "  + Real install: PASS"
else
    echo "ASSERTION FAILED: Real install failed" >&2
    exit 1
fi

# Force re-install
force_out="$(bash "$INSTALL" --local "$SANDBOX/fixtures/new-helper-skill" --name new-helper-skill --agent antigravity --force)"
if [[ "$force_out" =~ "previous source backed up to" ]] && [ -d "$SANDBOX/agents_skills/.backups" ]; then
    echo "  + Force install & backup: PASS"
else
    echo "ASSERTION FAILED: Force install failed to backup" >&2
    exit 1
fi

echo "=========================================="
echo "PASS: All Antigravity Adapter Tests Passed"
echo "=========================================="
exit 0
