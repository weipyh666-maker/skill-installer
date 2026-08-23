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
  catalog.sh --capabilities
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
        --capabilities) MODE='capabilities'; shift ;;
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

def get_category(explicit_category, name, description, kw_list):
    if explicit_category:
        cat = explicit_category.strip().lower()
        if cat in ("documents", "development", "browser", "research", "data", "media", "other"):
            return cat
        if cat in ("doc", "document", "office"): return "documents"
        if cat in ("dev", "coding", "code"): return "development"
        if cat in ("web", "browsing"): return "browser"
        if cat in ("analysis", "analytics"): return "data"
        if cat in ("audio", "video", "image"): return "media"

    text = f"{name} {description} {' '.join(kw_list)}".lower()
    doc_words = ("document", "docs", "docx", "pdf", "ppt", "pptx", "presentation", "slides", "excel", "xlsx", "csv", "spreadsheet", "markdown", "文档", "幻灯片", "表格", "演示", "office")
    dev_words = ("code", "coding", "develop", "dev", "git", "github", "api", "test", "testing", "debug", "diagnose", "lint", "compile", "build", "refactor", "backend", "frontend", "react", "vue", "node", "python", "rust", "go", "flutter", "typescript", "javascript", "hook", "architecture", "代码", "开发", "调试", "编译", "重构")
    browser_words = ("browser", "browsing", "scrape", "scraping", "crawl", "crawler", "puppeteer", "playwright", "stagehand", "selenium", "navigate", "网页", "浏览器", "抓取")
    research_words = ("research", "search", "exa", "query", "lookup", "paper", "papers", "survey", "arxiv", "huggingface", "intel", "调研", "搜索", "论文", "检索")
    data_words = ("data", "analysis", "analytics", "database", "sql", "parquet", "dataset", "datasets", "metrics", "chart", "数据", "数据库", "分析", "统计")
    media_words = ("image", "vision", "photo", "screenshot", "audio", "video", "transcribe", "transcript", "tts", "speech", "ocr", "art", "music", "fal.ai", "图像", "图片", "音频", "视频", "语音", "视觉", "艺术")

    if any(w in text for w in doc_words): return "documents"
    if any(w in text for w in browser_words): return "browser"
    if any(w in text for w in media_words): return "media"
    if any(w in text for w in data_words): return "data"
    if any(w in text for w in research_words): return "research"
    if any(w in text for w in dev_words): return "development"
    return "other"

def parse_frontmatter_field(text, field):
    frontmatter = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", text)
    scope = frontmatter.group(1) if frontmatter else text
    line_list = scope.splitlines()
    desc_index = None
    style = None
    for i, line in enumerate(line_list):
        m = re.match(rf"^{field}:\s*([>|])$", line.strip())
        if m:
            desc_index = i
            style = m.group(1)
            break
        if re.match(rf"^{field}:\s*\S", line):
            desc_index = i
            break
    if desc_index is None:
        return ""
    if style is None:
        value = line_list[desc_index].split(":", 1)[1].strip().strip('"').strip("'")
        return "" if value in (">", "|", ">-", "|-", ">+", "|+") else value
    collected = []
    for line in line_list[desc_index + 1:]:
        if not line.strip():
            continue
        if line[0] in (" ", "\t"):
            collected.append(line.strip())
        else:
            break
    return " ".join(collected)

def get_capabilities(text, name, category, kw_list):
    explicit = parse_frontmatter_field(text, "capabilities")
    if explicit:
        trimmed = explicit.strip("[]")
        parts = [p.strip().strip('"').strip("'") for p in re.split(r"[,;]", trimmed) if p.strip()]
        if parts:
            return list(dict.fromkeys(parts))
    derived = [name, category]
    for kw in kw_list:
        if len(kw) >= 3 and len(derived) < 8 and kw not in derived:
            derived.append(kw)
    return list(dict.fromkeys(derived))

def parse_skill(directory, from_link_root):
    skill_file = directory / "SKILL.md"
    has_link = (link_dir / directory.name).exists()
    link_path = f"$CLAUDE_SKILLS_LINK_DIR/{directory.name}" if has_link else ""
    source_path = f"$CLAUDE_SKILLS_DIR/{directory.name}"
    now_iso = dt.datetime.now(dt.timezone.utc).isoformat()

    entry = {
        "name": directory.name,
        "install_name": directory.name,
        "description": "",
        "capabilities": [directory.name, "other"],
        "keywords": [directory.name],
        "category": "other",
        "discovered_at": now_iso,
        "installed_at": None,
        "source": "unknown",
        "provenance": "unknown",
        "source_path": source_path,
        "link_path": link_path,
        "commit": None,
        "sha256": None,
        "status": "broken",
        "health": "broken",
        "usage": {"status": "unknown", "last_seen": None, "invocation_count": None},
        "agents": {"claude": {"visible": has_link, "link_path": link_path}},
    }
    if not skill_file.is_file():
        return entry
    text = skill_file.read_text(encoding="utf-8-sig", errors="replace")
    name_match = re.search(r"(?m)^name:\s*([a-z0-9][a-z0-9-]{0,63})\s*$", text)
    description_text = parse_frontmatter_field(text, "description")
    explicit_category = parse_frontmatter_field(text, "category")

    skill_name = name_match.group(1) if name_match else directory.name
    entry["name"] = skill_name
    entry["description"] = description_text
    entry["status"] = "ok" if (name_match and description_text) else "broken"
    entry["health"] = entry["status"]
    entry["keywords"] = keywords(entry["name"], entry["description"])
    entry["category"] = get_category(explicit_category, entry["name"], entry["description"], entry["keywords"])
    entry["capabilities"] = get_capabilities(text, entry["name"], entry["category"], entry["keywords"])
    return entry

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
    old_by_install = {item.get("install_name"): item for item in old.get("skills", []) if item.get("install_name")}
    now_iso = dt.datetime.now(dt.timezone.utc).isoformat()

    entries = scan_entries()
    scanned_names = set()
    for entry in entries:
        scanned_names.add(entry["name"])
        scanned_names.add(entry["install_name"])
        previous = old_by_name.get(entry["name"]) or old_by_install.get(entry["install_name"])
        if previous:
            entry["discovered_at"] = previous.get("discovered_at") or previous.get("installed_at") or now_iso
            entry["installed_at"] = previous.get("installed_at")
            previous_source = previous.get("source")
            if previous_source and previous_source != "local":
                entry["source"] = previous_source
                if previous_source.startswith("github:"):
                    entry["provenance"] = "installer"
            else:
                entry["source"] = "unknown"
                entry["provenance"] = "unknown"
            if previous.get("provenance"):
                entry["provenance"] = previous["provenance"]
            entry["commit"] = previous.get("commit")
            entry["sha256"] = previous.get("sha256")
            entry["usage"] = previous.get("usage", entry["usage"])

    # Keep missing entries
    for old_skill in old.get("skills", []):
        old_name = old_skill.get("name")
        old_install = old_skill.get("install_name", old_name)
        if old_name not in scanned_names and old_install not in scanned_names:
            missing_entry = {
                "name": old_name,
                "install_name": old_install,
                "description": old_skill.get("description", ""),
                "capabilities": old_skill.get("capabilities", [old_name, "other"]),
                "keywords": old_skill.get("keywords", [old_name]),
                "category": old_skill.get("category", "other"),
                "discovered_at": old_skill.get("discovered_at", now_iso),
                "installed_at": old_skill.get("installed_at"),
                "source": old_skill.get("source", "unknown") if old_skill.get("source") != "local" else "unknown",
                "provenance": old_skill.get("provenance", "unknown"),
                "source_path": old_skill.get("source_path", f"$CLAUDE_SKILLS_DIR/{old_name}"),
                "link_path": "",
                "commit": old_skill.get("commit"),
                "sha256": old_skill.get("sha256"),
                "status": "broken",
                "health": "missing",
                "usage": old_skill.get("usage", {"status": "unknown", "last_seen": None, "invocation_count": None}),
                "agents": {"claude": {"visible": False, "link_path": ""}},
            }
            entries.append(missing_entry)

    return {
        "schema_version": 2,
        "generated_at": now_iso,
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
                if register_source.startswith("github:"):
                    entry["provenance"] = "installer"
            if register_installed_at:
                entry["installed_at"] = register_installed_at
                if not entry.get("discovered_at"):
                    entry["discovered_at"] = register_installed_at
            if register_commit:
                entry["commit"] = register_commit
            if register_sha256:
                entry["sha256"] = register_sha256
    return index

def load_index():
    old = read_old_index()
    if old is not None and old.get("schema_version", 1) >= 2:
        return old
    index = build_index()
    write_index(index)
    return index

def score(entry, value):
    terms = query_terms(value)
    name_text = entry["name"].lower()
    search_text = " ".join([entry["name"], entry["install_name"], entry["description"], " ".join(entry["keywords"]), " ".join(entry.get("capabilities", []))]).lower()
    image_words = ("image", "vision", "photo", "screenshot", "picture", "图片", "图像", "照片", "截图")
    recog_words = ("recogni", "ocr", "detect", "identif", "understand", "classif", "识别", "理解", "分类")
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

def print_capabilities(index_data):
    if json_output:
        print(json.dumps(index_data, ensure_ascii=False, indent=2))
        return
    skills = index_data.get("skills", [])
    broken = [s for s in skills if s.get("status") != "ok" or s.get("health") in ("broken", "missing")]
    ok_skills = [s for s in skills if s not in broken]

    total = len(skills)
    broken_count = len(broken)

    if broken_count > 0:
        print(f"Your Agent currently has {total} Skills ({broken_count} broken)\n")
    else:
        print(f"Your Agent currently has {total} Skills\n")

    categories = [
        ("Documents", "documents"),
        ("Development", "development"),
        ("Browser", "browser"),
        ("Research", "research"),
        ("Data", "data"),
        ("Media", "media"),
        ("Other", "other"),
    ]

    for display_cat, cat_key in categories:
        group = [s for s in ok_skills if s.get("category") == cat_key]
        if group:
            print(f"{display_cat} ({len(group)})")
            for s in sorted(group, key=lambda x: x["name"].lower()):
                desc = s.get("description", "")
                if len(desc) > 60:
                    desc = desc[:57] + "..."
                if not desc:
                    desc = "(no description)"
                print(f"  {s['name']:<20} {desc}")
            print()

    if broken:
        print(f"Broken ({len(broken)})")
        for s in sorted(broken, key=lambda x: x["name"].lower()):
            desc = s.get("description", "")
            health = s.get("health", s.get("status", "broken"))
            if not desc:
                desc = f"({health})"
            elif len(desc) > 60:
                desc = desc[:57] + "..."
            print(f"  {s['name']:<20} {desc}")
        print()

index = load_index()

if mode == "refresh":
    index = build_index()
    index = apply_registration(index)
    write_index(index)
    print_entries(index["skills"])
elif mode == "capabilities":
    print_capabilities(index)
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
        for key in ("name", "install_name", "description", "category", "source", "provenance", "source_path", "link_path", "discovered_at", "installed_at", "commit", "sha256", "status", "health"):
            val = entry.get(key)
            if key == "capabilities":
                val = ", ".join(entry.get("capabilities", []))
            print(f"{key}: {val}")
        print(f"agents.claude.visible: {entry.get('agents', {}).get('claude', {}).get('visible')}")
        print(f"usage.status: {entry.get('usage', {}).get('status', 'unknown')}")
        print("invocation_hint: Ask Claude Code to use the named skill for a matching task. Automatic invocation is not observable by this catalog.")
elif mode == "doctor":
    fresh = build_index()
    broken = [entry for entry in fresh["skills"] if entry.get("status") != "ok" or entry.get("health") in ("broken", "missing")]
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

