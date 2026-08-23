#!/usr/bin/env bash
set -euo pipefail

export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POS_FILE="$ROOT/tests/fixtures/auto-trigger/queries-pos.json"
NEG_FILE="$ROOT/tests/fixtures/auto-trigger/queries-neg.json"
SKILL_MD="$ROOT/SKILL.md"

if command -v python >/dev/null 2>&1 && python -c "import sys" >/dev/null 2>&1; then
    PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1 && python3 -c "import sys" >/dev/null 2>&1; then
    PYTHON_BIN="python3"
else
    PYTHON_BIN="python"
fi

POS_PATH="$POS_FILE"
NEG_PATH="$NEG_FILE"
SKILL_PATH="$SKILL_MD"

if command -v cygpath >/dev/null 2>&1; then
    POS_PATH="$(cygpath -m "$POS_FILE")"
    NEG_PATH="$(cygpath -m "$NEG_FILE")"
    SKILL_PATH="$(cygpath -m "$SKILL_MD")"
fi

"$PYTHON_BIN" -c "
import json, re, sys
from pathlib import Path

pos_queries = json.loads(Path('$POS_PATH').read_text(encoding='utf-8'))
neg_queries = json.loads(Path('$NEG_PATH').read_text(encoding='utf-8'))
skill_md = Path('$SKILL_PATH').read_text(encoding='utf-8')

m = re.search(r'(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)', skill_md)
frontmatter = m.group(1) if m else ''
desc = ''
for line in frontmatter.splitlines():
    if line.startswith('description:'):
        desc = line.split(':', 1)[1].strip()

STOP_WORDS = {
    'a', 'an', 'the', 'in', 'on', 'at', 'to', 'for', 'of', 'and', 'or', 'is', 'are', 'with',
    'by', 'that', 'this', 'from', 'as', 'it', 'its', 'be', 'can', 'do', 'does', 'did', 'have',
    'has', 'had', 'will', 'would', 'shall', 'should', 'may', 'might', 'must', 'what', 'which',
    'how', 'who', 'whom', 'where', 'when', 'why', 'there', 'their', 'them', 'they', 'i', 'me',
    'my', 'we', 'us', 'our', 'you', 'your', 'he', 'him', 'his', 'she', 'her', 'that',
    '我', '你', '他', '她', '它', '我们', '你们', '他们', '的', '了', '在', '是', '有', '和', '就',
    '不', '人', '都', '一', '一个', '上', '也', '很', '到', '说', '要', '去', '会', '着',
    '没有', '看', '好', '自己', '这', '个', '帮我', '一下', '那个', '叫什么', '是不是', '哪些',
    '怎么', '这个', '为什么', '所有', '出来', '句', '成', '一封', '今天', '怎么样', '想', '听个'
}

ALIASES = {
    '装了': ['installed', 'install', '装了'],
    '装过': ['installed', 'previously-installed', 'install', '装过'],
    '能力': ['capabilities', 'capability', 'can do', '能力'],
    '列出': ['list', 'catalog', 'summary', '列出'],
    '列出来': ['list', 'catalog', 'summary', '列出来'],
    '找': ['find', 'searches', 'search', '找'],
    '找一下': ['find', 'searches', 'search', '找一下'],
    '忘记': ['cannot recall', 'forgot', '忘记'],
    '自动调用': ['triggered automatically', 'auto-discover', '自动调用'],
    '没自动调用': ['not being triggered automatically', 'triggered automatically', '没自动调用'],
    '哪个': ['which', '哪个'],
    '网页设计': ['网页 ui', 'frontend', '网页设计'],
    'pdf': ['pdf', 'pdfs'],
    'ppt': ['ppt', 'pptx', 'slide'],
    'summarizes': ['summarize', 'summarizes', 'summary'],
    'find': ['find', 'searches', 'search'],
    'list': ['list', 'catalog', 'summary'],
    'handles': ['handles', 'handle', 'manage'],
}

def extract_keywords(query_str):
    text = query_str.lower()
    tokens = re.findall(r'[a-z0-9_-]+|[\u3400-\u9fff]+', text)
    kws = []
    for t in tokens:
        if t in STOP_WORDS:
            continue
        if re.match(r'[\u3400-\u9fff]+', t):
            matched = False
            for k in ALIASES:
                if k in t:
                    matched = True
                    kws.append(k)
                    break
            if not matched and len(t) >= 1:
                kws.append(t)
        else:
            if t not in STOP_WORDS and len(t) >= 2:
                kws.append(t)
    return list(dict.fromkeys(kws))

def calculate_likelihood(query_str, target_desc):
    kws = extract_keywords(query_str)
    if not kws:
        return 0.0, 0, 0, []
    desc_lower = target_desc.lower()
    hits = 0
    hit_kws = []
    for kw in kws:
        kw_aliases = [kw] + ALIASES.get(kw, [])
        if any(al.lower() in desc_lower for al in kw_aliases):
            hits += 1
            hit_kws.append(kw)
    likelihood = hits / len(kws)
    return likelihood, hits, len(kws), hit_kws

pos_passed = 0
pos_failed = []
for q in pos_queries:
    lh, hits, total, hk = calculate_likelihood(q['query'], desc)
    if lh >= 0.3:
        pos_passed += 1
    else:
        pos_failed.append(f'[{q[\"id\"]}] FAIL (likelihood: {lh:.2f} < 0.3, hits: {hits}/{total} {hk}) query: \"{q[\"query\"]}\"')

neg_passed = 0
neg_failed = []
for q in neg_queries:
    lh, hits, total, hk = calculate_likelihood(q['query'], desc)
    if lh <= 0.2:
        neg_passed += 1
    else:
        neg_failed.append(f'[{q[\"id\"]}] FAIL (likelihood: {lh:.2f} > 0.2, hits: {hits}/{total} {hk}) query: \"{q[\"query\"]}\"')

total_pos = len(pos_queries)
total_neg = len(neg_queries)
pos_pct = round((pos_passed / total_pos) * 100)
neg_pct = round((neg_passed / total_neg) * 100)

print('==========================================')
print('Auto-Trigger Heuristic Evaluation')
print('==========================================')
print(f'Positive Cases: {pos_passed} / {total_pos} ({pos_pct}%) [target >= 83% (10/12)]')
print(f'Negative Cases: {neg_passed} / {total_neg} ({neg_pct}%) [target >= 90% (9/10)]')
print('==========================================')

if pos_failed:
    print('Failed Positive Cases:')
    for pf in pos_failed:
        print(f' - {pf}')
    print()

if neg_failed:
    print('Failed Negative Cases:')
    for nf in neg_failed:
        print(f' - {nf}')
    print()

if pos_passed < 10:
    print(f'FAIL: Positive trigger rate {pos_passed}/{total_pos} is below minimum 10/12')
    sys.exit(1)

if neg_passed < 9:
    print(f'FAIL: Negative rejection rate {neg_passed}/{total_neg} is below minimum 9/10')
    sys.exit(1)

print('PASS: Auto-trigger evaluation passed all criteria')
"
