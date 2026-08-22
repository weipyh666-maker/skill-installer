#!/usr/bin/env bash
#
# catalog.sh — list, search, inspect, and validate installed Claude Code skills

set -euo pipefail

MODE='list'
QUERY=''
NAME=''
JSON_OUTPUT=0
REGISTER_NAME=''
REGISTER_SOURCE=''
REGISTER_INSTALLED_AT=''
REGISTER_COMMIT=''
REGISTER_SHA256=''

usage() {
    cat <<'USAGE'
Usage:
  catalog.sh --list
  catalog.sh --refresh
  catalog.sh --find QUERY
  catalog.sh --show NAME
  catalog.sh --doctor
  catalog.sh --json --list

Catalog commands require Python 3. Installation itself does not.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list)       MODE='list'; shift ;;
        --refresh)    MODE='refresh'; shift ;;
        --find)       [[ $# -ge 2 ]] || { echo '--find needs a query' >&2; exit 1; }; MODE='find'; QUERY="$2"; shift 2 ;;
        --show)       [[ $# -ge 2 ]] || { echo '--show needs a skill name' >&2; exit 1; }; MODE='show'; NAME="$2"; shift 2 ;;
        --doctor)     MODE='doctor'; shift ;;
        --json)       JSON_OUTPUT=1; shift ;;
        --register-name) [[ $# -ge 2 ]] || { echo '--register-name needs a value' >&2; exit 1; }; REGISTER_NAME="$2"; shift 2 ;;
        --register-source) [[ $# -ge 2 ]] || { echo '--register-source needs a value' >&2; exit 1; }; REGISTER_SOURCE="$2"; shift 2 ;;
        --register-installed-at) [[ $# -ge 2 ]] || { echo '--register-installed-at needs a value' >&2; exit 1; }; REGISTER_INSTALLED_AT="$2"; shift 2 ;;
        --register-commit) [[ $# -ge 2 ]] || { echo '--register-commit needs a value' >&2; exit 1; }; REGISTER_COMMIT="$2"; shift 2 ;;
        --register-sha256) [[ $# -ge 2 ]] || { echo '--register-sha256 needs a value' >&2; exit 1; }; REGISTER_SHA256="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *)            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

PYTHON_BIN=''
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python3'
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python'
else
    echo 'catalog.sh requires a working Python 3 interpreter; install Python or use catalog.ps1 on Windows.' >&2
    exit 1
fi

"$PYTHON_BIN" - "$MODE" "$QUERY" "$NAME" "$JSON_OUTPUT" "$REGISTER_NAME" "$REGISTER_SOURCE" "$REGISTER_INSTALLED_AT" "$REGISTER_COMMIT" "$REGISTER_SHA256" <<'PY'
import datetime as dt
import json
import os
import re
import sys
import uuid
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

mode, query, requested_name, json_output, register_name, register_source, register_installed_at, register_commit, register_sha256 = sys.argv[1:10]
json_output = json_output == "1"
home = Path.home()
skills_dir = Path(os.environ.get("CLAUDE_SKILLS_DIR", str(home / "Claude-Code"))).expanduser()
link_dir = Path(os.environ.get("CLAUDE_SKILLS_LINK_DIR", str(home / ".claude" / "skills"))).expanduser()
index_path = Path(os.environ.get("CLAUDE_SKILLS_INDEX_PATH", str(skills_dir / "installed-skills-index.json"))).expanduser()

aliases = {
    "图片": ["image", "vision", "photo", "screenshot", "ocr"],
    "识别": ["recognition", "ocr", "understanding", "detect", "identify"],
    "ppt": ["presentation", "slides", "deck", "pptx"],
    "演示": ["presentation", "slides", "deck", "pptx"],
    "幻灯片": ["presentation", "slides", "deck", "pptx"],
    "文档": ["document", "docs", "docx", "pdf"],
    "表格": ["spreadsheet", "xlsx", "excel", "csv"],
    "网页": ["web", "website", "browser", "frontend"],
    "代码": ["code", "coding", "development", "programming"],
    "调试": ["debug", "debugging", "diagnosis", "bug"],
    "技能": ["skill", "agent", "workflow"],
}

def query_terms(value):
    terms = [part.lower() for part in re.split(r"\s+", value.lower()) if part]
    for key, values in aliases.items():
        if key in value:
            terms.extend(values)
    return list(dict.fromkeys(terms))

def keywords(name, description):
    text = f"{name} {description}".lower()
    words = re.findall(r"[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}", text)
    return list(dict.fromkeys(words + query_terms(text)))

def parse_skill(directory, from_link_root):
    skill_file = directory / "SKILL.md"
    link_path = directory if from_link_root else (link_dir / directory.name if (link_dir / directory.name).exists() else None)
    source_path = directory.resolve() if from_link_root else directory
    entry = {
        "name": directory.name,
        "install_name": directory.name,
        "description": "",
        "keywords": [],
    "source": "unknown",
    "source_path": f"$CLAUDE_SKILLS_DIR/{directory.name}",
    "link_path": f"$CLAUDE_SKILLS_LINK_DIR/{directory.name}",
        "installed_at": None,
        "commit": None,
        "sha256": None,
        "status": "broken",
        "usage": {"status": "unknown", "last_seen": None, "invocation_count": None},
    }
    if not skill_file.is_file():
        return entry
    text = skill_file.read_text(encoding="utf-8-sig", errors="replace")
    name_match = re.search(r"(?m)^name:\s*([a-z0-9][a-z0-9-]{0,63})\s*$", text)
    description_text = parse_description(text)
    if name_match:
        entry["name"] = name_match.group(1)
    if description_text:
        entry["description"] = description_text
    if name_match and description_text:
        entry["status"] = "ok"
        entry["keywords"] = keywords(entry["name"], entry["description"])
    return entry


def parse_description(text):
    """Extract description from YAML frontmatter, handling single-line,
    folded (>) and literal (|) block scalars, without swallowing the next
    frontmatter key or the closing --- / body headings."""
    frontmatter = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", text)
    scope = frontmatter.group(1) if frontmatter else text
    line_list = scope.splitlines()
    # Locate the description line and read its block style marker if present.
    desc_index = None
    style = None
    for i, line in enumerate(line_list):
        m = re.match(r"^description:\s*([>|])$", line.strip())
        if m:
            desc_index = i
            style = m.group(1)
            break
        if re.match(r"^description:\s*\S", line):
            desc_index = i
            break
    if desc_index is None:
        return ""
    if style is None:
        value = line_list[desc_index].split(":", 1)[1].strip().strip('"')
        return "" if value in (">", "|", ">-", "|-", ">+", "|+") else value
    # Collect indented continuation lines. Blank lines stay inside the block;
    # an unindented non-blank line ends the block (next frontmatter key).
    collected = []
    for line in line_list[desc_index + 1:]:
        if not line.strip():
            continue
        if line[0] in (" ", "\t"):
            collected.append(line.strip())
        else:
            break
    return " ".join(collected)

def scan_entries():
    selected = {}
    for root, from_link_root in ((link_dir, True), (skills_dir, False)):
        if not root.is_dir():
            continue
        for directory in sorted(root.iterdir(), key=lambda item: item.name.lower()):
            if directory.is_dir() and not directory.name.startswith(".") and directory.name not in selected:
                selected[directory.name] = parse_skill(directory, from_link_root)
    return list(selected.values())

def read_old_index():
    try:
        return json.loads(index_path.read_text(encoding="utf-8-sig"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return None

def build_index():
    old = read_old_index() or {}
    old_by_name = {item.get("name"): item for item in old.get("skills", [])}
    entries = scan_entries()
    for entry in entries:
        previous = old_by_name.get(entry["name"])
        if previous:
            entry["installed_at"] = previous.get("installed_at")
            previous_source = previous.get("source")
            if previous_source and previous_source != "local":
                entry["source"] = previous_source
            entry["commit"] = previous.get("commit")
            entry["sha256"] = previous.get("sha256")
            entry["usage"] = previous.get("usage", entry["usage"])
    return {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "skills": sorted(entries, key=lambda item: item["name"].lower()),
    }

def write_index(index):
    index_path.parent.mkdir(parents=True, exist_ok=True)
    temp = index_path.with_name(index_path.name + ".tmp-" + uuid.uuid4().hex)
    temp.write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, index_path)

def apply_registration(index):
    if not register_name:
        return index
    for entry in index["skills"]:
        if entry["name"] == register_name or entry.get("install_name") == register_name:
            if register_source:
                entry["source"] = register_source
            if register_installed_at:
                entry["installed_at"] = register_installed_at
            if register_commit:
                entry["commit"] = register_commit
            if register_sha256:
                entry["sha256"] = register_sha256
    return index

def load_index():
    old = read_old_index()
    if old is not None:
        return old
    index = build_index()
    write_index(index)
    return index

def score(entry, value):
    terms = query_terms(value)
    name_text = entry["name"].lower()
    search_text = " ".join([entry["name"], entry["install_name"], entry["description"], " ".join(entry["keywords"])]).lower()
    # Compound query detection: requires BOTH an image-class word AND a
    # recognition-class word (English or Chinese). Without this, multi-word
    # queries collapse to substring OR and return noisy hits.
    image_words = ("image", "vision", "photo", "screenshot", "picture", "图片", "图像", "照片", "截图")
    recog_words = ("recogni", "ocr", "detect", "identif", "understand", "classif",
                   "识别", "理解", "分类")
    query_lower = value.lower()
    is_compound = (
        any(k in query_lower for k in image_words) and
        any(k in query_lower for k in recog_words)
    )
    if is_compound:
        image_hit = any(term in search_text for term in image_words)
        recog_hit = any(term in search_text for term in recog_words)
        if not (image_hit and recog_hit):
            return 0
    total = 0
    for term in terms:
        if name_text == term:
            total += 12
        elif term in name_text:
            total += 8
        elif term in search_text:
            total += 3
    return total

def print_entries(entries):
    if json_output:
        print(json.dumps(entries, ensure_ascii=False, indent=2))
        return
    print(f"Skills: {len(entries)}")
    for entry in sorted(entries, key=lambda item: item["name"].lower()):
        description = entry["description"]
        if len(description) > 78:
            description = description[:75] + "..."
        display_name = entry["name"]
        if entry.get("install_name") and entry["install_name"] != entry["name"]:
            display_name += f" (install: {entry['install_name']})"
        print(f"{display_name:<38} [{entry['status']:<7}] {description}")

index = load_index()

if mode == "refresh":
    index = build_index()
    index = apply_registration(index)
    write_index(index)
    print_entries(index["skills"])
elif mode == "list":
    print_entries(index.get("skills", []))
elif mode == "find":
    if not query.strip():
        raise SystemExit("--find needs a query")
    matches = [entry for entry in index.get("skills", []) if score(entry, query) > 0]
    matches.sort(key=lambda entry: score(entry, query), reverse=True)
    if not matches:
        print(f"No matching skills for '{query}'.")
        raise SystemExit(1)
    print_entries(matches)
elif mode == "show":
    entry = next((item for item in index.get("skills", []) if item["name"] == requested_name or item.get("install_name") == requested_name), None)
    if entry is None:
        raise SystemExit(f"Skill not found: {requested_name}")
    if json_output:
        print(json.dumps(entry, ensure_ascii=False, indent=2))
    else:
        for key in ("name", "install_name", "description", "source", "source_path", "link_path", "installed_at", "status"):
            print(f"{key}: {entry.get(key)}")
        print(f"commit: {entry.get('commit')}")
        print(f"sha256: {entry.get('sha256')}")
        print(f"usage.status: {entry.get('usage', {}).get('status', 'unknown')}")
        print("invocation_hint: Ask Claude Code to use the named skill for a matching task. Automatic invocation is not observable by this catalog.")
elif mode == "doctor":
    fresh = build_index()
    broken = [entry for entry in fresh["skills"] if entry["status"] != "ok"]
    names = [entry["name"] for entry in fresh["skills"]]
    duplicate_count = len(names) - len(set(names))
    if broken or duplicate_count:
        if broken:
            print("broken: " + ", ".join(entry["name"] for entry in broken))
        if duplicate_count:
            print("duplicates: " + ", ".join(sorted(set(name for name in names if names.count(name) > 1))))
        print(f"doctor: issues found; {len(fresh['skills'])} skills scanned")
        raise SystemExit(1)
    print(f"doctor: OK; {len(fresh['skills'])} skills indexed; usage status is unknown unless the host provides invocation events.")
PY
