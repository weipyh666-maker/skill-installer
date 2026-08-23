#!/usr/bin/env bash
#
# catalog.sh — list, search, inspect, and validate installed Claude Code skills

set -euo pipefail

MODE='list'
QUERY=''
NAME=''
LIMIT=10
DRY_RUN=0
ASSUME_YES=0
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
  catalog.sh --find QUERY [--limit N]
  catalog.sh --show NAME
  catalog.sh --doctor [--name NAME]
  catalog.sh --fix [--name NAME] [--dry-run] [--yes]
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
        --fix)        MODE='fix'; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        -y|--yes)     ASSUME_YES=1; shift ;;
        --name)       [[ $# -ge 2 ]] || { echo '--name needs a value' >&2; exit 1; }; NAME="$2"; shift 2 ;;
        --limit)      [[ $# -ge 2 ]] || { echo '--limit needs a number' >&2; exit 1; }; LIMIT="$2"; shift 2 ;;
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

"$PYTHON_BIN" - "$MODE" "$QUERY" "$NAME" "$LIMIT" "$DRY_RUN" "$ASSUME_YES" "$JSON_OUTPUT" "$REGISTER_NAME" "$REGISTER_SOURCE" "$REGISTER_INSTALLED_AT" "$REGISTER_COMMIT" "$REGISTER_SHA256" <<'PY'
import datetime as dt
import json
import os
import re
import sys
import uuid
import hashlib
from pathlib import Path

for stream in (sys.stdout, sys.stderr):
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(encoding="utf-8", errors="replace")

mode, query, requested_name, limit_str, dry_run_str, assume_yes_str, json_output, register_name, register_source, register_installed_at, register_commit, register_sha256 = sys.argv[1:13]
limit = int(limit_str) if limit_str.isdigit() else 10
dry_run = dry_run_str == "1"
assume_yes = assume_yes_str == "1"
json_output = json_output == "1"
home = Path.home()
skills_dir = Path(os.environ.get("CLAUDE_SKILLS_DIR", str(home / "Claude-Code"))).expanduser()
link_dir = Path(os.environ.get("CLAUDE_SKILLS_LINK_DIR", str(home / ".claude" / "skills"))).expanduser()
index_path = Path(os.environ.get("CLAUDE_SKILLS_INDEX_PATH", str(skills_dir / "installed-skills-index.json"))).expanduser()

action_verbs_map = {
    "creating": "create", "building": "build", "generating": "generate", "analyzing": "analyze",
    "inspecting": "inspect", "running": "run", "finding": "find", "checking": "check",
    "converting": "convert", "translating": "translate", "developing": "develop", "managing": "manage",
    "formatting": "format", "testing": "test", "searching": "search", "querying": "query",
    "deploying": "deploy", "fixing": "fix", "scaffolding": "scaffold", "designing": "design",
    "writing": "write", "editing": "edit", "reviewing": "review", "extracting": "extract",
    "summarizing": "summarize", "tracking": "track", "transforming": "transform", "diagnosing": "diagnose",
    "operating": "operate", "providing": "provide", "handling": "handle", "applying": "apply",
    "modifying": "modify", "debugging": "debug", "evaluating": "evaluate", "optimizing": "optimize",
    "refactoring": "refactor", "auditing": "audit", "drafting": "draft", "publishing": "publish",
    "driving": "drive", "automating": "automate", "learning": "learn", "scanning": "scan",
    "creates": "create", "builds": "build", "generates": "generate", "analyzes": "analyze",
    "inspects": "inspect", "runs": "run", "finds": "find", "checks": "check",
    "converts": "convert", "translates": "translate", "develops": "develop", "manages": "manage",
    "formats": "format", "tests": "test", "searches": "search", "queries": "query",
    "deploys": "deploy", "fixes": "fix", "scaffolds": "scaffold", "designs": "design",
    "writes": "write", "edits": "edit", "reviews": "review", "extracts": "extract",
    "summarizes": "summarize", "tracks": "track", "transforms": "transform", "diagnoses": "diagnose",
    "operates": "operate", "provides": "provide", "handles": "handle", "applies": "apply",
    "modifies": "modify", "debugs": "debug", "evaluates": "evaluate", "optimizes": "optimize",
    "refactors": "refactor", "audits": "audit", "drafts": "draft", "publishes": "publish",
    "drives": "drive", "automates": "automate", "learns": "learn", "scans": "scan",
    "create": "create", "build": "build", "generate": "generate", "analyze": "analyze",
    "inspect": "inspect", "run": "run", "find": "find", "check": "check",
    "convert": "convert", "translate": "translate", "develop": "develop", "manage": "manage",
    "format": "format", "test": "test", "search": "search", "query": "query",
    "deploy": "deploy", "fix": "fix", "scaffold": "scaffold", "design": "design",
    "write": "write", "edit": "edit", "review": "review", "extract": "extract",
    "summarize": "summarize", "track": "track", "transform": "transform", "diagnose": "diagnose",
    "operate": "operate", "provide": "provide", "handle": "handle", "apply": "apply",
    "modify": "modify", "debug": "debug", "evaluate": "evaluate", "optimize": "optimize",
    "refactor": "refactor", "audit": "audit", "draft": "draft", "publish": "publish",
    "drive": "drive", "automate": "automate", "learn": "learn", "scan": "scan",
}

aliases = {
    "图片": ["image", "vision", "photo", "screenshot", "ocr"],
    "图像": ["image", "vision", "photo", "screenshot", "ocr"],
    "照片": ["image", "vision", "photo", "screenshot"],
    "截图": ["screenshot", "image", "vision"],
    "识别": ["recognition", "recognize", "ocr", "understanding", "detect", "identify"],
    "理解": ["understanding", "recognition", "recognize", "vision"],
    "ppt": ["presentation", "slides", "deck", "pptx"],
    "演示": ["presentation", "slides", "deck", "pptx"],
    "幻灯片": ["presentation", "slides", "deck", "pptx"],
    "文档": ["document", "docs", "docx", "pdf"],
    "pdf": ["pdf", "document", "docs"],
    "word": ["docx", "document", "word"],
    "表格": ["spreadsheet", "xlsx", "excel", "csv"],
    "excel": ["xlsx", "spreadsheet", "excel", "csv"],
    "网页": ["web", "website", "browser", "frontend", "ui", "page"],
    "前端": ["frontend", "ui", "web", "interface", "design"],
    "界面": ["ui", "interface", "frontend", "gui"],
    "ui": ["ui", "interface", "frontend", "gui", "design"],
    "设计": ["design", "create", "craft", "build"],
    "做": ["design", "create", "build", "make", "develop"],
    "制作": ["create", "build", "design", "make"],
    "代码": ["code", "coding", "development", "programming"],
    "开发": ["develop", "development", "code", "coding", "build"],
    "编程": ["programming", "code", "coding", "develop"],
    "调试": ["debug", "debugging", "diagnosis", "bug"],
    "测试": ["test", "testing", "qa", "e2e"],
    "诊断": ["diagnose", "diagnosis", "debug", "health"],
    "搜索": ["search", "research", "query", "find"],
    "调研": ["research", "survey", "search", "investigate"],
    "技能": ["skill", "agent", "workflow"],
}

def query_terms(value):
    terms = [part.lower() for part in re.split(r"\s+", value.lower()) if part]
    for key, values in aliases.items():
        if key in value.lower():
            terms.extend(values)
    return list(dict.fromkeys(terms))

def extract_frontmatter_field(frontmatter, field_name):
    lines = frontmatter.splitlines()
    desc_idx = -1
    style = None
    for idx, line in enumerate(lines):
        trimmed = line.strip()
        m = re.match(rf"^{field_name}:\s*([>|][+-]?)$", trimmed)
        if m:
            desc_idx = idx
            style = m.group(1)
            break
        if re.match(rf"^{field_name}:\s*$", line):
            desc_idx = idx
            style = "list"
            break
        if re.match(rf"^{field_name}:\s*\S", line):
            desc_idx = idx
            break
    if desc_idx == -1:
        return ""
    if style is None:
        val = lines[desc_idx].split(":", 1)[1].strip().strip("\"'")
        if val in (">", "|", ">-", "|-", ">+", "|+"):
            return ""
        return val
    collected = []
    for line in lines[desc_idx + 1:]:
        if not line.strip():
            continue
        if line.startswith(" ") or line.startswith("\t"):
            item = line.strip().lstrip("-").strip().strip("\"'")
            if item:
                collected.append(item)
        else:
            break
    if style == "list":
        return ", ".join(collected)
    return " ".join(collected)

def derive_keywords(name, description):
    text = f"{name} {description}".lower()
    matches = re.findall(r"[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}", text)
    words = list(matches)
    for term in query_terms(text):
        if term not in words:
            words.append(term)
    return list(dict.fromkeys(words))

def infer_category(explicit, name, description, keywords):
    if explicit:
        cat = explicit.strip().lower()
        if cat in ("documents", "development", "browser", "research", "data", "media", "other"):
            return cat
        if cat in ("doc", "document", "office"):
            return "documents"
        if cat in ("dev", "coding", "code"):
            return "development"
        if cat in ("web", "browsing"):
            return "browser"
        if cat in ("analysis", "analytics"):
            return "data"
        if cat in ("audio", "video", "image"):
            return "media"

    text = f"{name} {description} {' '.join(keywords)}".lower()
    doc_words = ("document", "docs", "docx", "pdf", "ppt", "pptx", "presentation", "slides", "excel", "xlsx", "csv", "spreadsheet", "markdown", "文档", "幻灯片", "表格", "演示", "office")
    dev_words = ("code", "coding", "develop", "dev", "git", "github", "api", "test", "testing", "debug", "diagnose", "lint", "compile", "build", "refactor", "backend", "frontend", "react", "vue", "node", "python", "rust", "go", "flutter", "typescript", "javascript", "hook", "architecture", "代码", "开发", "调试", "编译", "重构")
    browser_words = ("browser", "browsing", "scrape", "scraping", "crawl", "crawler", "puppeteer", "playwright", "stagehand", "selenium", "navigate", "网页", "浏览器", "抓取")
    research_words = ("research", "search", "exa", "query", "lookup", "paper", "papers", "survey", "arxiv", "huggingface", "intel", "调研", "搜索", "论文", "检索")
    data_words = ("data", "analysis", "analytics", "database", "sql", "parquet", "dataset", "datasets", "metrics", "chart", "数据", "数据库", "分析", "统计")
    media_words = ("image", "vision", "photo", "screenshot", "audio", "video", "transcribe", "transcript", "tts", "speech", "ocr", "art", "music", "fal.ai", "图像", "图片", "音频", "视频", "语音", "视觉", "艺术")

    for w in doc_words:
        if w in text: return "documents"
    for w in browser_words:
        if w in text: return "browser"
    for w in media_words:
        if w in text: return "media"
    for w in data_words:
        if w in text: return "data"
    for w in research_words:
        if w in text: return "research"
    for w in dev_words:
        if w in text: return "development"
    return "other"

def derive_capabilities(frontmatter, name, category, keywords):
    explicit = extract_frontmatter_field(frontmatter, "capabilities")
    if explicit:
        parts = [p.strip().strip("\"'") for p in re.split(r"[,;]", explicit.strip("[]")) if p.strip()]
        if parts:
            return list(dict.fromkeys(parts))
    derived = [name, category]
    for kw in keywords:
        if len(kw) >= 3 and len(derived) < 8 and kw not in derived:
            derived.append(kw)
    return list(dict.fromkeys(derived))

def scan_entries():
    candidates = {}
    for root in (link_dir, skills_dir):
        if not root.is_dir():
            continue
        try:
            for item in sorted(root.iterdir()):
                if item.name.startswith("."):
                    continue
                if item.is_dir() and item.name not in candidates:
                    candidates[item.name] = (item, root)
        except Exception:
            pass
    return candidates

def read_skill_entry(name, item_path, root_dir):
    skill_file = item_path / "SKILL.md"
    has_link = (link_dir / name).exists()
    link_path = f"$CLAUDE_SKILLS_LINK_DIR/{name}" if has_link else ""
    source_path = f"$CLAUDE_SKILLS_DIR/{name}"
    now_iso = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")

    if not skill_file.is_file():
        return {
            "name": name,
            "install_name": name,
            "description": "",
            "capabilities": [name, "other"],
            "keywords": [name],
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

    try:
        content = skill_file.read_text(encoding="utf-8")
    except Exception:
        content = ""

    frontmatter_match = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", content)
    frontmatter = frontmatter_match.group(1) if frontmatter_match else content

    name_match = re.search(r"(?m)^name:\s*([a-z0-9][a-z0-9-]{0,63})\s*$", content)
    description = extract_frontmatter_field(frontmatter, "description")
    explicit_category = extract_frontmatter_field(frontmatter, "category")
    skill_name = name_match.group(1) if name_match else name

    status = "ok" if name_match and description else "broken"
    health = "ok" if status == "ok" else "broken"
    keywords = derive_keywords(skill_name, description)
    category = infer_category(explicit_category, skill_name, description, keywords)
    capabilities = derive_capabilities(frontmatter, skill_name, category, keywords)

    return {
        "name": skill_name,
        "install_name": name,
        "description": description,
        "capabilities": capabilities,
        "keywords": keywords,
        "category": category,
        "discovered_at": now_iso,
        "installed_at": None,
        "source": "unknown",
        "provenance": "unknown",
        "source_path": source_path,
        "link_path": link_path,
        "commit": None,
        "sha256": None,
        "status": status,
        "health": health,
        "usage": {"status": "unknown", "last_seen": None, "invocation_count": None},
        "agents": {"claude": {"visible": has_link, "link_path": link_path}},
    }

def read_old_index():
    if not index_path.is_file():
        return None
    try:
        data = json.loads(index_path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and isinstance(data.get("skills"), list):
            return data
    except Exception:
        return None
    return None

def build_index():
    old_index = read_old_index()
    old_map = {}
    if old_index and isinstance(old_index.get("skills"), list):
        for item in old_index["skills"]:
            if isinstance(item, dict) and "name" in item:
                old_map[item["name"]] = item
                if item.get("install_name"):
                    old_map[item["install_name"]] = item

    scanned = scan_entries()
    entries = []
    scanned_names = set()
    now_iso = dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")

    for name, (item_path, root_dir) in scanned.items():
        entry = read_skill_entry(name, item_path, root_dir)
        scanned_names.add(entry["name"])
        scanned_names.add(entry["install_name"])

        old = old_map.get(entry["name"]) or old_map.get(entry["install_name"])
        if old:
            if old.get("discovered_at"):
                entry["discovered_at"] = old["discovered_at"]
            elif old.get("installed_at"):
                entry["discovered_at"] = old["installed_at"]

            if old.get("installed_at"):
                entry["installed_at"] = old["installed_at"]
            if old.get("source") and old.get("source") != "local":
                entry["source"] = old["source"]
                if old["source"].startswith("github:"):
                    entry["provenance"] = "installer"
            else:
                entry["source"] = "unknown"
                entry["provenance"] = "unknown"
            if old.get("provenance"):
                entry["provenance"] = old["provenance"]
            if old.get("commit"):
                entry["commit"] = old["commit"]
            if old.get("sha256"):
                entry["sha256"] = old["sha256"]
            if old.get("usage"):
                entry["usage"] = old["usage"]

        entries.append(entry)

    if old_index and isinstance(old_index.get("skills"), list):
        for old_skill in old_index["skills"]:
            old_name = old_skill.get("name")
            old_inst = old_skill.get("install_name")
            if old_name not in scanned_names and (not old_inst or old_inst not in scanned_names):
                missing_entry = {
                    "name": old_name,
                    "install_name": old_inst or old_name,
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

    entries.sort(key=lambda item: item["name"].lower())
    return {
        "schema_version": 2,
        "generated_at": now_iso,
        "skills": entries,
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

def score(entry, search_query):
    terms = query_terms(search_query)
    name_lower = entry["name"].lower()
    install_lower = entry.get("install_name", "").lower()
    desc_lower = entry.get("description", "").lower()
    kw_list = [k.lower() for k in entry.get("keywords", [])]
    cap_list = [c.lower() for c in entry.get("capabilities", [])]
    cat_lower = entry.get("category", "").lower()
    search_text = f"{name_lower} {install_lower} {desc_lower} {' '.join(kw_list)} {' '.join(cap_list)} {cat_lower}".lower()

    # Compound AND filters
    image_words = ("image", "vision", "photo", "screenshot", "picture", "图片", "图像", "照片", "截图")
    recog_words = ("recogni", "ocr", "detect", "identif", "understand", "classif", "识别", "理解", "分类")
    query_lower = search_query.lower()

    q_has_image = any(w in query_lower for w in image_words)
    q_has_recog = any(w in query_lower for w in recog_words)
    if q_has_image and q_has_recog:
        t_has_image = any(w in search_text for w in image_words)
        t_has_recog = any(w in search_text for w in recog_words)
        if not (t_has_image and t_has_recog):
            return 0

    ui_words = ("web", "website", "frontend", "ui", "interface", "page", "网页", "前端", "界面")
    design_words = ("design", "create", "build", "craft", "make", "设计", "做", "制作", "构建")
    q_has_ui = any(w in query_lower for w in ui_words)
    q_has_design = any(w in query_lower for w in design_words)
    if q_has_ui and q_has_design:
        t_has_ui = any(w in search_text for w in ui_words)
        t_has_design = any(w in search_text for w in design_words)
        if not (t_has_ui and t_has_design):
            return 0

    total = 0
    if name_lower == query_lower:
        total += 20
    elif query_lower in name_lower:
        total += 15

    for term in terms:
        if name_lower == term:
            total += 12
        elif term in name_lower:
            total += 8
        if term in desc_lower:
            total += 3
        if any(term in kw for kw in kw_list):
            total += 3
        if any(term in cap for cap in cap_list):
            total += 3
        if cat_lower == term or term in cat_lower:
            total += 5
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

def doctor_global(index_data):
    skills = index_data.get("skills", [])
    scanned_count = len(skills)
    broken_list = [s for s in skills if s.get("status") != "ok" or s.get("health") == "broken"]
    missing_list = [s for s in skills if s.get("health") == "missing"]
    healthy_count = max(0, scanned_count - len(broken_list) - len(missing_list))

    print(f"doctor: scanned {scanned_count} skills")
    print(f"  healthy: {healthy_count}")
    if broken_list:
        broken_names = ", ".join(s["name"] for s in broken_list)
        print(f"  broken: {len(broken_list)} ({broken_names})")
    else:
        print("  broken: 0")

    if missing_list:
        missing_names = ", ".join(s["name"] for s in missing_list)
        print(f"  missing: {len(missing_list)} ({missing_names})")
    else:
        print("  missing: 0")

    if broken_list or missing_list:
        raise SystemExit(1)

def doctor_single(skill_name, index_data):
    entry = next((s for s in index_data.get("skills", []) if s["name"] == skill_name or s.get("install_name") == skill_name), None)
    dir_name = entry.get("install_name", skill_name) if entry else skill_name

    source_disk = skills_dir / dir_name
    link_disk = link_dir / dir_name
    source_file = source_disk / "SKILL.md"
    link_file = link_disk / "SKILL.md"

    source_exists = source_disk.is_dir()
    link_exists = link_disk.exists()
    source_file_exists = source_file.is_file()
    link_file_exists = link_file.is_file()

    raw_content = ""
    if source_file_exists:
        try: raw_content = source_file.read_text(encoding="utf-8")
        except Exception: pass
    elif link_file_exists:
        try: raw_content = link_file.read_text(encoding="utf-8")
        except Exception: pass

    frontmatter_match = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", raw_content)
    frontmatter = frontmatter_match.group(1) if frontmatter_match else ""

    declared_name = extract_frontmatter_field(frontmatter, "name")
    declared_desc = extract_frontmatter_field(frontmatter, "description")
    declared_cat = extract_frontmatter_field(frontmatter, "category")
    declared_caps = extract_frontmatter_field(frontmatter, "capabilities")

    suggestions = []

    print(f"{skill_name}\n")

    print("Installation")
    if source_exists:
        print(f"  ✓ Source at $CLAUDE_SKILLS_DIR/{dir_name}")
    else:
        print(f"  ✗ Source missing at $CLAUDE_SKILLS_DIR/{dir_name}")

    if link_exists:
        print(f"  ✓ Link at $CLAUDE_SKILLS_LINK_DIR/{dir_name}")
    else:
        print(f"  ✗ Link missing at $CLAUDE_SKILLS_LINK_DIR/{dir_name}")

    if source_file_exists and link_file_exists:
        src_hash = hashlib.sha256(source_file.read_bytes()).hexdigest()
        lnk_hash = hashlib.sha256(link_file.read_bytes()).hexdigest()
        if src_hash == lnk_hash:
            print("  ✓ SKILL.md hashes match")
        else:
            print("  ✗ SKILL.md hashes differ between source and link")
    elif source_file_exists or link_file_exists:
        print("  ⚠ Single copy found (no link hash comparison)")
    else:
        print("  ✗ SKILL.md missing")
    print()

    print("Structure")
    if source_file_exists or link_file_exists:
        print("  ✓ SKILL.md present")
    else:
        print("  ✗ SKILL.md missing")

    if frontmatter_match:
        print("  ✓ YAML frontmatter valid")
    else:
        print("  ✗ YAML frontmatter missing or invalid")

    if declared_name:
        print(f"  ✓ name = {declared_name}")
    else:
        print("  ✗ name field missing in frontmatter")

    if declared_desc:
        print("  ✓ description present")
    else:
        print("  ✗ description missing in frontmatter")
    print()

    print("Discovery")
    if link_exists:
        print("  ✓ Claude link path visible")
    else:
        print("  ✗ Claude link path not visible")

    if raw_content:
        print("  ✓ File readable")
    else:
        print("  ✗ File unreadable or empty")
    print()

    print("Trigger quality")
    trigger_warnings = 0
    if declared_desc:
        words = declared_desc.split()
        if len(declared_desc) < 20:
            print("  ⚠ Description too short (< 20 characters)")
            suggestions.append("Expand description to at least 20 characters explaining what the skill does and when to use it")
            trigger_warnings += 1
        else:
            print(f"  ✓ Description has {len(words)} words")

        desc_lower = declared_desc.lower()
        if desc_lower.startswith("use when"):
            print('  ✓ Description starts with explicit trigger phrase ("Use when...")')
        elif any(w in desc_lower for w in ("when", "当用户", "当", "用于")):
            print('  ✓ Description contains trigger phrase ("when")')
        else:
            print('  ⚠ Description doesn\'t start with "Use when..." — Claude\'s auto-discovery benefits from explicit trigger phrases')
            suggestions.append('Start description with "Use when the user wants to..." for better auto-discovery')
            trigger_warnings += 1

        action_words = ("use", "create", "analyze", "build", "check", "inspect", "run", "extract", "convert", "manage", "format", "test", "search", "query", "deploy", "fix", "scaffold", "design", "write", "edit", "review", "translate", "summarize", "crawl", "scrape", "monitor", "转换", "提取", "创建", "分析", "构建", "检查", "运行", "调试", "搜索", "编写", "审查", "设计", "做")
        if any(act in desc_lower for act in action_words):
            pass
        else:
            print("  ⚠ Description lacks clear action verbs (use, create, analyze, build, inspect, convert...)")
            suggestions.append("Include specific action verbs (e.g. create, convert, analyze) in the description")
            trigger_warnings += 1
    else:
        print("  ✗ No description found to assess trigger quality")
        trigger_warnings += 1

    if declared_caps:
        print(f"  ✓ Capabilities declared: {declared_caps}")
    else:
        print("  ⚠ No explicit capabilities tags in frontmatter — auto-derived only")
        suggestions.append('Add "capabilities:" to SKILL.md frontmatter for explicit tagging')
        trigger_warnings += 1

    inferred_cat = entry.get("category", "other") if entry else "other"
    if declared_cat:
        print(f"  ✓ Category declared: {declared_cat}")
    else:
        print(f"  ⚠ No explicit category in frontmatter — auto-bucketed to {inferred_cat}")
        suggestions.append(f'Add "category: {inferred_cat}" to SKILL.md frontmatter')
        trigger_warnings += 1

    if trigger_warnings == 0:
        print("  ✓ Trigger description looks Claude-discoverable")
    print()

    if suggestions:
        print("Suggestions:")
        for s in suggestions:
            print(f"  - {s}")

def get_trigger_warning_count(frontmatter, desc, caps, cat):
    count = 0
    if not desc or len(desc.strip()) < 20:
        count += 1
    elif not desc.strip().lower().startswith("use when"):
        count += 1

    action_words = ('use', 'create', 'analyze', 'build', 'check', 'inspect', 'run', 'extract', 'convert', 'manage', 'format', 'test', 'search', 'query', 'deploy', 'fix', 'scaffold', 'design', 'write', 'edit', 'review', 'translate', 'summarize', 'crawl', 'scrape', 'monitor', '转换', '提取', '创建', '分析', '构建', '检查', '运行', '调试', '搜索', '编写', '审查', '设计', '做')
    desc_lower = desc.lower() if desc else ""
    if not any(act in desc_lower for act in action_words):
        count += 1

    if not caps:
        count += 1
    if not cat:
        count += 1
    return count

def is_symlink_or_reparse(path_obj):
    if path_obj.is_symlink():
        return True
    try:
        if sys.platform == "win32":
            import ctypes
            FILE_ATTRIBUTE_REPARSE_POINT = 0x400
            attrs = ctypes.windll.kernel32.GetFileAttributesW(str(path_obj))
            if attrs != -1 and (attrs & FILE_ATTRIBUTE_REPARSE_POINT):
                return True
    except Exception:
        pass
    return False

def rewrite_description(desc):
    trimmed = desc.strip()
    if len(trimmed) < 20:
        return trimmed, False, True, "description too short to fix automatically; manual edit needed"
    if trimmed.lower().startswith("use when"):
        clean = "Use when " + re.sub(r"^use when\s*", "", trimmed, flags=re.IGNORECASE)
        return clean, (clean != trimmed), False, "already compliant"

    pattern_c_when = r"^(?:(?:you\s+)?must\s+use\s+(?:this\s+(?:skill|before)\s+)?(?:when|before)\s+|this skill\s+(?:should be used|is used|can be used)\s+when\s+|use this skill\s+(?:when|whenever)\s+|used\s+(?:when|whenever)\s*)"
    if re.search(pattern_c_when, trimmed, flags=re.IGNORECASE):
        stripped = re.sub(pattern_c_when, "", trimmed, flags=re.IGNORECASE).strip()
        if re.search(r"^(?:the\s+)?user\b", stripped, flags=re.IGNORECASE):
            clean_user = re.sub(r"^(?:the\s+)?user\b", "the user", stripped, flags=re.IGNORECASE)
            return f"Use when {clean_user}", True, False, "case c: 3rd person when user"
        else:
            trimmed = stripped

    pattern_c2 = r"^(?:this skill\s+(?:should be used|is used|can be used)\s+(?:to|for)\s*|use this skill\s+(?:to|for)\s*|this skill\s+(?:provides|allows|helps with|helps to)\s*|used\s+(?:to|for)\s*)"
    if re.search(pattern_c2, trimmed, flags=re.IGNORECASE):
        trimmed = re.sub(pattern_c2, "", trimmed, flags=re.IGNORECASE).strip()

    words = trimmed.split()
    if words:
        first_word = words[0].lower().rstrip(",.:;")
        if first_word in action_verbs_map:
            base_verb = action_verbs_map[first_word]
            rest = " ".join(words[1:]) if len(words) > 1 else ""
            new_text = f"Use when the user wants to {base_verb} {rest}".strip()
            return new_text, True, False, "case b: action verb"

    first_char = trimmed[0].lower()
    rest_chars = trimmed[1:] if len(trimmed) > 1 else ""
    return f"Use when the user wants to {first_char}{rest_chars}", True, False, "case e: default"

def get_top_capabilities(frontmatter, name, description, category):
    explicit = extract_frontmatter_field(frontmatter, "capabilities")
    if explicit:
        trimmed = explicit.strip("[]")
        parts = [p.strip().strip("'\"") for p in re.split(r"[,;]", trimmed) if p.strip()]
        if parts:
            return list(dict.fromkeys(parts))

    stop_words = {'use', 'when', 'the', 'user', 'wants', 'to', 'for', 'and', 'or', 'in', 'on', 'with', 'a', 'an', 'is', 'are', 'this', 'skill', 'should', 'be', 'can', 'needs', 'any', 'from', 'into', 'by', 'that', 'as', 'it', 'of', 'at', 'so', 'more', 'reliably', 'auto', 'discover', 'whenever', 'about', 'also', 'all', 'will', 'then', 'than', 'such', 'not', 'out', 'up', 'down', 'only', 'both', 'each', 'how', 'what', 'which', 'who', 'whom', 'whose', 'why', 'where', 'there', 'their', 'they', 'them', 'these', 'those'}

    name_words = re.findall(r"[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}", name.lower())
    desc_words = re.findall(r"[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]{2,}", description.lower())
    alias_words = query_terms(f"{name} {description}")

    counts = {}
    for w in name_words:
        if w not in stop_words and len(w) >= 2:
            counts[w] = counts.get(w, 0) + 10
    for w in desc_words:
        if w not in stop_words and len(w) >= 2:
            counts[w] = counts.get(w, 0) + 2
    for w in alias_words:
        if w not in stop_words and len(w) >= 2:
            counts[w] = counts.get(w, 0) + 3

    sorted_words = sorted(counts.keys(), key=lambda k: counts[k], reverse=True)
    selected = []
    for k in sorted_words:
        if len(selected) < 5:
            selected.append(k)
    if not selected:
        selected.append(name)
        if category and category != "other":
            selected.append(category)
    return selected

def build_fixed_frontmatter(raw_content, name, new_desc, new_caps, new_cat):
    m = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", raw_content)
    old_frontmatter = m.group(1) if m else ""
    body = raw_content[m.end():] if m else raw_content

    lines = ["---", f"name: {name}", f"description: {new_desc}", "capabilities:"]
    for cap in new_caps:
        lines.append(f"  - {cap}")
    lines.append(f"category: {new_cat}")

    known_fields = {"name", "description", "capabilities", "category"}
    in_skipped_block = False
    for line in old_frontmatter.splitlines():
        trimmed = line.strip()
        if not trimmed:
            continue
        if line.startswith(" ") or line.startswith("\t"):
            if in_skipped_block:
                continue
            lines.append(line)
            continue
        key = line.split(":", 1)[0].strip()
        if key in known_fields:
            in_skipped_block = True
        else:
            in_skipped_block = False
            lines.append(line)
    lines.append("---")
    new_fm_text = "\n".join(lines)
    return f"{new_fm_text}\n{body}"

def fix_skill(entry, is_dry_run, is_assume_yes):
    dir_name = entry.get("install_name") or entry["name"]
    source_disk = skills_dir / dir_name
    link_disk = link_dir / dir_name
    source_file = source_disk / "SKILL.md"
    link_file = link_disk / "SKILL.md"

    target_file = None
    if source_file.is_file():
        target_file = source_file
    elif link_file.is_file():
        target_file = link_file
    else:
        print(f"skipping {entry['name']}: SKILL.md not found")
        return

    is_symlink = is_symlink_or_reparse(target_file)
    try:
        raw_content = target_file.read_text(encoding="utf-8", errors="replace")
    except Exception as exc:
        print(f"skipping {entry['name']}: read error: {exc}")
        return

    fm_match = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", raw_content)
    if not fm_match:
        print(f"skipping {entry['name']}: invalid or missing YAML frontmatter")
        return
    frontmatter = fm_match.group(1)
    old_name = extract_frontmatter_field(frontmatter, "name") or entry["name"]
    old_desc = extract_frontmatter_field(frontmatter, "description")
    old_caps = extract_frontmatter_field(frontmatter, "capabilities")
    old_cat = extract_frontmatter_field(frontmatter, "category")

    if not old_desc:
        print(f"skipping {entry['name']}: description missing in frontmatter")
        return

    new_desc, changed, skip, reason = rewrite_description(old_desc)
    if skip:
        print(f"skipping {entry['name']}: {reason}")
        return

    new_caps = get_top_capabilities(frontmatter, old_name, new_desc, entry.get("category"))
    new_cat = old_cat or entry.get("category") or "other"

    backup_dir = skills_dir / ".backups"
    timestamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup_path = backup_dir / f"{entry['name']}-{timestamp}-SKILL.md"

    fixed_content = build_fixed_frontmatter(raw_content, old_name, new_desc, new_caps, new_cat)

    if is_symlink:
        print(f"refusing to modify symlink: {target_file}; suggested patch for {entry['name']}:")
        print("---")
        print(f"name: {old_name}")
        print(f"description: {new_desc}")
        print("capabilities:")
        for c in new_caps:
            print(f"  - {c}")
        print(f"category: {new_cat}")
        print("---")
        return

    if is_dry_run:
        print(f"[proposed] {entry['name']}\n")
        print("description (before):")
        print(f"  {old_desc}\n")
        print("description (after):")
        print(f"  {new_desc}\n")
        print("capabilities (added):")
        for c in new_caps:
            print(f"  - {c}")
        print("\ncategory (added):")
        print(f"  {new_cat}\n")
        print(f"no symlink. backup would go to: $CLAUDE_SKILLS_DIR/.backups/{entry['name']}-{timestamp}-SKILL.md\n")
        return

    if not is_assume_yes:
        try:
            resp = input(f"Apply fix to {entry['name']}? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            resp = "n"
        if resp not in ("y", "yes"):
            print(f"Skipped {entry['name']}.")
            return

    backup_dir.mkdir(parents=True, exist_ok=True)
    backup_path.write_text(raw_content, encoding="utf-8")
    target_file.write_text(fixed_content, encoding="utf-8")

    # verify
    try:
        written_check = target_file.read_text(encoding="utf-8", errors="replace")
        check_match = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", written_check)
        if not check_match:
            print(f"ERROR: verification failed after writing {target_file}. Restoring backup...")
            target_file.write_text(raw_content, encoding="utf-8")
            return
    except Exception as exc:
        print(f"ERROR: verification failed: {exc}. Restoring backup...")
        target_file.write_text(raw_content, encoding="utf-8")
        return

    before_warnings = get_trigger_warning_count(frontmatter, old_desc, old_caps, old_cat)
    after_warnings = get_trigger_warning_count(check_match.group(1), new_desc, ",".join(new_caps), new_cat)

    print(f"fixed {entry['name']}: description rewritten, capabilities + category added")
    print(f"  trigger quality: {after_warnings} ⚠ (was {before_warnings} ⚠)")

try:
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
        scored = []
        for entry in index.get("skills", []):
            sc = score(entry, query)
            if sc > 0:
                scored.append({"score": sc, "entry": entry})
        scored.sort(key=lambda item: item["score"], reverse=True)

        if not scored:
            print(f'No matching skills for "{query}".')
            raise SystemExit(0)

        if json_output:
            print(json.dumps([item["entry"] for item in scored], ensure_ascii=False, indent=2))
            raise SystemExit(0)

        top_list = scored[:limit]
        print(f'Matches for "{query}":\n')
        for idx, item in enumerate(top_list):
            num = idx + 1
            entry = item["entry"]
            sc_val = item["score"]
            desc = entry.get("description") or "(no description)"
            if len(desc) > 75:
                desc = desc[:72] + "..."
            print(f"  {num:>2}. {entry['name']:<28} (score: {sc_val})")
            print(f"     {desc}\n")
        print(f"Found {len(scored)} matches. Showing top {len(top_list)}.")
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
        if requested_name:
            doctor_single(requested_name, fresh)
        else:
            doctor_global(fresh)
    elif mode == "fix":
        fresh = build_index()
        if requested_name:
            entry = next((item for item in fresh.get("skills", []) if item["name"] == requested_name or item.get("install_name") == requested_name), None)
            if entry is None:
                raise SystemExit(f"Skill not found: {requested_name}")
            fix_skill(entry, dry_run, assume_yes)
            if not dry_run:
                write_index(build_index())
        else:
            ok_skills = [s for s in fresh.get("skills", []) if s.get("status") == "ok" and s.get("health") == "ok"]
            if dry_run:
                for s in ok_skills:
                    fix_skill(s, True, True)
            else:
                if not assume_yes:
                    try:
                        ans = input(f"This will rewrite {len(ok_skills)} skills. Continue? [y/N] ").strip().lower()
                    except (EOFError, KeyboardInterrupt):
                        ans = "n"
                    if ans not in ("y", "yes"):
                        print("Operation cancelled.")
                        raise SystemExit(0)
                for s in ok_skills:
                    fix_skill(s, False, True)
                write_index(build_index())
except (BrokenPipeError, IOError, OSError):
    try:
        sys.stdout.close()
    except Exception:
        pass
    try:
        sys.stderr.close()
    except Exception:
        pass
    sys.exit(0)
PY

