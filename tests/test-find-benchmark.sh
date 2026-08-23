set -euo pipefail

export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUERIES="$ROOT/tests/fixtures/find-benchmark/queries.json"

if [[ ! -f "$QUERIES" ]]; then
    echo "ERROR: queries fixture not found: $QUERIES" >&2
    exit 1
fi

TOTAL=0
TOP1_HIT=0
TOP3_HIT=0
FAILED=()

QUERIES_WIN="$(cygpath -w "$QUERIES" 2>/dev/null || echo "$QUERIES")"

while IFS=$'	' read -r QID QUERY LANG CAT GOLD1 GOLD3_JSON; do
    TOTAL=$((TOTAL + 1))
    
    RESULT="$(bash "$ROOT/lib/catalog.sh" --find "$QUERY" --limit 3 2>&1 || true)"
    
    TOP1="$(echo "$RESULT" | awk '/^[[:space:]]*1\./ {print $2; exit}' || true)"
    TOP2="$(echo "$RESULT" | awk '/^[[:space:]]*2\./ {print $2; exit}' || true)"
    TOP3="$(echo "$RESULT" | awk '/^[[:space:]]*3\./ {print $2; exit}' || true)"
    
    IS_TOP1=0
    IS_TOP3=0
    
    if [[ "$GOLD1" == "null" || -z "$GOLD1" ]]; then
        if [[ "$RESULT" == *"No matching skills"* || -z "$TOP1" ]]; then
            IS_TOP1=1
            IS_TOP3=1
        fi
    else
        if [[ "$TOP1" == "$GOLD1" ]]; then
            IS_TOP1=1
        fi
        
        if [[ "$TOP1" == "$GOLD1" || "$TOP2" == "$GOLD1" || "$TOP3" == "$GOLD1" ]]; then
            IS_TOP3=1
        elif echo "$GOLD3_JSON" | grep -q ""$TOP1""; then
            IS_TOP3=1
        fi
    fi
    
    if [[ $IS_TOP1 -eq 1 ]]; then
        TOP1_HIT=$((TOP1_HIT + 1))
    fi
    
    if [[ $IS_TOP3 -eq 1 ]]; then
        TOP3_HIT=$((TOP3_HIT + 1))
    else
        FAILED+=("[$QID] '$QUERY' (expected: $GOLD1, got top1: '${TOP1:-none}', top2: '${TOP2:-none}', top3: '${TOP3:-none}')")
    fi
done < <(python -c '
import json, sys
queries_file = r"""'"$QUERIES_WIN"'"""
data = json.load(open(queries_file, encoding="utf-8"))
for q in data:
    gold1 = q.get("gold_top1") or "null"
    gold3 = json.dumps(q.get("gold_top3", []))
    qid = q["id"]
    query = q["query"]
    lang = q.get("language", "")
    cat = q.get("category", "")
    print(qid + "	" + query + "	" + lang + "	" + cat + "	" + str(gold1) + "	" + gold3)
')

TOP1_PCT=$((TOP1_HIT * 100 / TOTAL))
TOP3_PCT=$((TOP3_HIT * 100 / TOTAL))

echo "=========================================="
echo "Find Benchmark Results"
echo "=========================================="
echo "Total Queries: $TOTAL"
echo "Top-1 Hits: $TOP1_HIT / $TOTAL ($TOP1_PCT%) [target >= 85%]"
echo "Top-3 Hits: $TOP3_HIT / $TOTAL ($TOP3_PCT%) [target >= 95%]"
echo "=========================================="

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "--- Failed queries (${#FAILED[@]}) ---"
    printf ' - %s
' "${FAILED[@]}"
    echo ""
fi

if [[ $TOP1_PCT -lt 85 ]]; then
    echo "FAIL: Top-1 accuracy $TOP1_PCT% is below 85% target" >&2
    exit 1
fi

if [[ $TOP3_PCT -lt 95 ]]; then
    echo "FAIL: Top-3 accuracy $TOP3_PCT% is below 95% target" >&2
    exit 1
fi

echo "PASS: Find benchmark passed all criteria"
