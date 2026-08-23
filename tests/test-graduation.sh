#!/usr/bin/env bash
set -euo pipefail

export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT/lib/catalog.sh"
FIXTURE="$ROOT/tests/fixtures/find-benchmark/skills_fixture.json"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

if command -v cygpath >/dev/null 2>&1; then
    SANDBOX_PATH="$(cygpath -m "$SANDBOX")"
    FIXTURE_PATH="$(cygpath -m "$FIXTURE")"
    ROOT_PATH="$(cygpath -m "$ROOT")"
else
    SANDBOX_PATH="$SANDBOX"
    FIXTURE_PATH="$FIXTURE"
    ROOT_PATH="$ROOT"
fi

export CLAUDE_SKILLS_DIR="$SANDBOX_PATH/sources"
export CLAUDE_SKILLS_LINK_DIR="$SANDBOX_PATH/links"
export CLAUDE_SKILLS_INDEX_PATH="$SANDBOX_PATH/sources/installed-skills-index.json"
mkdir -p "$SANDBOX/sources" "$SANDBOX/links"

if command -v python >/dev/null 2>&1 && python -c "import sys" >/dev/null 2>&1; then
    PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import sys" >/dev/null 2>&1; then
    PYTHON_BIN="python3"
else
    PYTHON_BIN="python"
fi

# Populate fixture skills + skill-manager
"$PYTHON_BIN" -c "
import json
from pathlib import Path
fixture = json.loads(Path('$FIXTURE_PATH').read_text(encoding='utf-8'))
link_dir = Path('$CLAUDE_SKILLS_LINK_DIR')
for s in fixture:
    sdir = link_dir / s['name']
    sdir.mkdir(parents=True, exist_ok=True)
    (sdir / 'SKILL.md').write_text('---\n' + s['frontmatter'] + '\n---\n# ' + s['name'], encoding='utf-8')
sm_dir = link_dir / 'skill-manager'
sm_dir.mkdir(parents=True, exist_ok=True)
(sm_dir / 'SKILL.md').write_text(Path('$ROOT_PATH/SKILL.md').read_text(encoding='utf-8'), encoding='utf-8')
"

pass_count=0
fail_count=0

echo "================================="
echo "Claude 1.0 Graduation Test"
echo "================================="

# [A] scan finds manually-installed skills
mkdir -p "$SANDBOX/links/manual-test-skill"
cat > "$SANDBOX/links/manual-test-skill/SKILL.md" <<'EOF'
---
name: manual-test-skill
description: Use when testing manual installation detection.
capabilities: [manual, test]
category: other
---
# manual
EOF

bash "$CATALOG" --refresh >/dev/null
if grep -q "manual-test-skill" "$SANDBOX/sources/installed-skills-index.json"; then
    echo "[A] scan finds manually-installed skills        ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[A] scan finds manually-installed skills        ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [B] catalog is complete
out_list="$(bash "$CATALOG" --list)"
out_show="$(bash "$CATALOG" --show manual-test-skill)"
if [[ -n "$out_list" ]] && [[ "$out_show" =~ "name:" ]] && [[ "$out_show" =~ "description:" ]] && [[ "$out_show" =~ "capabilities:" ]] && [[ "$out_show" =~ "category:" ]]; then
    echo "[B] catalog is complete                        ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[B] catalog is complete                        ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [C] capabilities categorized reasonably
out_caps="$(bash "$CATALOG" --capabilities)"
cat_count="$(echo "$out_caps" | grep -E '^[A-Z][a-z]+ \([0-9]+\)' | wc -l)"
if [ "$cat_count" -ge 4 ]; then
    echo "[C] capabilities categorized reasonably        ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[C] capabilities categorized reasonably        ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [D] refresh is stable (deterministic)
bash "$CATALOG" --refresh >/dev/null
hash1="$("$PYTHON_BIN" -c "import hashlib, json, sys; d=json.load(open('$SANDBOX_PATH/sources/installed-skills-index.json', encoding='utf-8')); print(hashlib.sha256(json.dumps(d.get('skills', []), sort_keys=True).encode('utf-8')).hexdigest())")"
bash "$CATALOG" --refresh >/dev/null
hash2="$("$PYTHON_BIN" -c "import hashlib, json, sys; d=json.load(open('$SANDBOX_PATH/sources/installed-skills-index.json', encoding='utf-8')); print(hashlib.sha256(json.dumps(d.get('skills', []), sort_keys=True).encode('utf-8')).hexdigest())")"
if [ "$hash1" = "$hash2" ]; then
    echo "[D] refresh is stable (deterministic)          ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[D] refresh is stable (deterministic)          ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [E] find supports natural language queries
out_find1="$(bash "$CATALOG" --find "我装了哪些 Skill")"
out_find2="$(bash "$CATALOG" --find "find a skill that handles PDFs")"
if [[ "$out_find1" =~ "1." ]] && [[ "$out_find2" =~ "1." ]]; then
    echo "[E] find supports natural language queries     ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[E] find supports natural language queries     ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [F] Top-1 >= 85% / Top-3 >= 95%
out_bm="$(bash "$ROOT/tests/test-find-benchmark.sh")"
top1_bm="$(echo "$out_bm" | grep -o 'Top-1 Hits: [0-9]* / [0-9]* ([0-9]*%)' | grep -o '([0-9]*%)' | tr -d '()%')"
top3_bm="$(echo "$out_bm" | grep -o 'Top-3 Hits: [0-9]* / [0-9]* ([0-9]*%)' | grep -o '([0-9]*%)' | tr -d '()%')"
if [ -n "$top1_bm" ] && [ "$top1_bm" -ge 85 ] && [ -n "$top3_bm" ] && [ "$top3_bm" -ge 95 ]; then
    echo "[F] Top-1 ≥ 85% / Top-3 ≥ 95%                  ✓ PASS (${top1_bm}% / ${top3_bm}%)"
    pass_count=$((pass_count + 1))
else
    echo "[F] Top-1 ≥ 85% / Top-3 ≥ 95%                  ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [G] find returns match reason
out_reason="$(bash "$CATALOG" --find "PPT")"
if [[ "$out_reason" =~ "matched:" ]]; then
    echo "[G] find returns match reason                  ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[G] find returns match reason                  ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [H] doctor diagnoses common issues
out_doc="$(bash "$CATALOG" --doctor --name manual-test-skill)"
if [[ "$out_doc" =~ "Installation" ]] && [[ "$out_doc" =~ "Structure" ]] && [[ "$out_doc" =~ "Discovery" ]] && [[ "$out_doc" =~ "Trigger quality" ]]; then
    echo "[H] doctor diagnoses common issues             ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[H] doctor diagnoses common issues             ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [I] fix handles security issues
mkdir -p "$SANDBOX/links/sensitive-test-skill"
cat > "$SANDBOX/links/sensitive-test-skill/SKILL.md" <<'EOF'
---
name: sensitive-test-skill
description: Use when testing sensitive rejection.
---
# sensitive
EOF
echo "SECRET_KEY=123" > "$SANDBOX/links/sensitive-test-skill/.env"
bash "$CATALOG" --refresh >/dev/null
out_sec="$(bash "$CATALOG" --fix --name sensitive-test-skill --yes 2>&1 || true)"
if [[ "$out_sec" =~ "refusing to copy sensitive file" ]] || [[ "$out_sec" =~ "Refusing to copy sensitive" ]]; then
    echo "[I] fix handles security issues                ✓ PASS"
    pass_count=$((pass_count + 1))
else
    echo "[I] fix handles security issues                ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [J] skill-manager triggers on intent
out_at="$(bash "$ROOT/tests/test-auto-trigger.sh")"
pos_pct="$(echo "$out_at" | grep -o 'Positive Cases: [0-9]* / [0-9]* ([0-9]*%)' | grep -o '([0-9]*%)' | tr -d '()%')"
if [ -n "$pos_pct" ] && [ "$pos_pct" -ge 83 ]; then
    echo "[J] skill-manager triggers on intent           ✓ PASS (${pos_pct}%)"
    pass_count=$((pass_count + 1))
else
    echo "[J] skill-manager triggers on intent           ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

# [K] skill-manager avoids false triggers
neg_pct="$(echo "$out_at" | grep -o 'Negative Cases: [0-9]* / [0-9]* ([0-9]*%)' | grep -o '([0-9]*%)' | tr -d '()%')"
if [ -n "$neg_pct" ] && [ "$neg_pct" -ge 90 ]; then
    echo "[K] skill-manager avoids false triggers        ✓ PASS (${neg_pct}%)"
    pass_count=$((pass_count + 1))
else
    echo "[K] skill-manager avoids false triggers        ✗ FAIL"
    fail_count=$((fail_count + 1))
fi

echo "================================="
if [ "$fail_count" -eq 0 ] && [ "$pass_count" -eq 11 ]; then
    echo "Result: 11 / 11 PASS — Claude 1.0 GRADUATED"
    exit 0
else
    echo "Result: $pass_count / 11 PASS ($fail_count FAILED) — NOT GRADUATED"
    exit 1
fi
