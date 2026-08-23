#!/usr/bin/env bash
set -euo pipefail

export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERIES="$ROOT/tests/fixtures/find-benchmark/queries.json"
FIXTURE="$ROOT/tests/fixtures/find-benchmark/skills_fixture.json"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

BASH_EXEC="$(which bash 2>/dev/null || echo "bash")"

if command -v cygpath >/dev/null 2>&1; then
    SANDBOX_PATH="$(cygpath -m "$SANDBOX")"
    FIXTURE_PATH="$(cygpath -m "$FIXTURE")"
    QUERIES_PATH="$(cygpath -m "$QUERIES")"
    ROOT_PATH="$(cygpath -m "$ROOT")"
    BASH_EXEC="$(cygpath -m "$BASH_EXEC")"
else
    SANDBOX_PATH="$SANDBOX"
    FIXTURE_PATH="$FIXTURE"
    QUERIES_PATH="$QUERIES"
    ROOT_PATH="$ROOT"
fi

export CLAUDE_SKILLS_DIR="$SANDBOX_PATH/sources"
export CLAUDE_SKILLS_LINK_DIR="$SANDBOX_PATH/links"
mkdir -p "$SANDBOX/sources" "$SANDBOX/links"

if command -v python >/dev/null 2>&1 && python -c "import sys" >/dev/null 2>&1; then
    PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import sys" >/dev/null 2>&1; then
    PYTHON_BIN="python3"
else
    PYTHON_BIN="python"
fi

"$PYTHON_BIN" -c "
import json
from pathlib import Path
fixture = json.loads(Path('$FIXTURE_PATH').read_text(encoding='utf-8'))
link_dir = Path('$CLAUDE_SKILLS_LINK_DIR')
for s in fixture:
    sdir = link_dir / s['name']
    sdir.mkdir(parents=True, exist_ok=True)
    (sdir / 'SKILL.md').write_text('---\n' + s['frontmatter'] + '\n---\n# ' + s['name'], encoding='utf-8')
"

bash "$ROOT/lib/catalog.sh" --refresh >/dev/null

"$PYTHON_BIN" -c "
import json, subprocess, sys, re, os
from pathlib import Path

queries = json.loads(Path('$QUERIES_PATH').read_text(encoding='utf-8'))
root = '$ROOT_PATH'
bash_bin = '$BASH_EXEC'

total_queries = len(queries)
top1_hits = 0
top3_hits = 0
failed_queries = []

for q in queries:
    qid = q['id']
    query = q['query']
    gold1 = q.get('gold_top1')
    gold3 = q.get('gold_top3', [])

    cmd = [bash_bin, f'{root}/lib/catalog.sh', '--find', query, '--limit', '3']
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='ignore', env=os.environ)
        out = proc.stdout
    except Exception as ex:
        out = ''

    top1 = None
    top2 = None
    top3 = None
    for line in out.splitlines():
        m1 = re.match(r'^\s*1\.\s+([^\s]+)', line)
        if m1 and not top1:
            top1 = m1.group(1)
            continue
        m2 = re.match(r'^\s*2\.\s+([^\s]+)', line)
        if m2 and not top2:
            top2 = m2.group(1)
            continue
        m3 = re.match(r'^\s*3\.\s+([^\s]+)', line)
        if m3 and not top3:
            top3 = m3.group(1)
            continue

    is_top1 = False
    is_top3 = False

    if gold1 is None or gold1 == '' or gold1 == 'none':
        if not top1 or 'No matching skills' in out:
            is_top1 = True
            is_top3 = True
    else:
        if top1 == gold1:
            is_top1 = True
        candidates = [x for x in [top1, top2, top3] if x]
        if any(c == gold1 or c in gold3 for c in candidates):
            is_top3 = True

    if is_top1:
        top1_hits += 1
    if is_top3:
        top3_hits += 1
    else:
        failed_queries.append(f'[{qid}] \'{query}\' (expected: {gold1}, got top1: {top1}, top2: {top2}, top3: {top3})')

top1_pct = round((top1_hits / total_queries) * 100) if total_queries > 0 else 0
top3_pct = round((top3_hits / total_queries) * 100) if total_queries > 0 else 0

print('==========================================')
print('Find Benchmark Results')
print('==========================================')
print(f'Total Queries: {total_queries}')
print(f'Top-1 Hits: {top1_hits} / {total_queries} ({top1_pct}%) [target >= 85%]')
print(f'Top-3 Hits: {top3_hits} / {total_queries} ({top3_pct}%) [target >= 95%]')
print('==========================================')

if failed_queries:
    print(f'--- Failed queries ({len(failed_queries)}) ---')
    for f in failed_queries:
        print(f' - {f}')
    print()

if top1_pct < 85:
    print(f'FAIL: Top-1 accuracy {top1_pct}% is below 85% target')
    sys.exit(1)

if top3_pct < 95:
    print(f'FAIL: Top-3 accuracy {top3_pct}% is below 95% target')
    sys.exit(1)

print('PASS: Find benchmark passed all criteria')
"
