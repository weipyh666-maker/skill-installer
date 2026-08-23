#!/usr/bin/env bash
#
# catalog.sh — list, search, inspect, and validate installed skills across agents

set -euo pipefail

export PYTHONIOENCODING="${PYTHONIOENCODING:-utf-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"
export LANG="${LANG:-C.UTF-8}"

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
AGENT="${CLAUDE_SKILLS_AGENT:-claude}"
ALL_AGENTS=0

usage() {
    cat <<'USAGE'
Usage:
  catalog.sh --capabilities [--agent AGENT] [--all-agents]
  catalog.sh --list [--agent AGENT] [--all-agents]
  catalog.sh --refresh [--agent AGENT]
  catalog.sh --find QUERY [--limit N] [--agent AGENT] [--all-agents]
  catalog.sh --show NAME
  catalog.sh --doctor [--name NAME] [--agent AGENT]
  catalog.sh --fix [--name NAME] [--dry-run] [--yes] [--agent AGENT]
  catalog.sh --json --list

Supported agents: claude (default), codex, antigravity
Catalog commands require Python 3. Installation itself does not.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../adapters/_base.sh"

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
        --agent)      [[ $# -ge 2 ]] || { echo '--agent needs a value' >&2; exit 1; }; AGENT="$2"; shift 2 ;;
        --all-agents) ALL_AGENTS=1; shift ;;
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

AGENT="$(resolve_agent "$AGENT")"
validate_agent "$AGENT" || exit 1

PYTHON_BIN=''
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python3'
elif command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN='python'
else
    echo 'catalog.sh requires a working Python 3 interpreter; install Python or use catalog.ps1 on Windows.' >&2
    exit 1
fi

"$PYTHON_BIN" - "$MODE" "$QUERY" "$NAME" "$LIMIT" "$DRY_RUN" "$ASSUME_YES" "$JSON_OUTPUT" "$REGISTER_NAME" "$REGISTER_SOURCE" "$REGISTER_INSTALLED_AT" "$REGISTER_COMMIT" "$REGISTER_SHA256" "$AGENT" "$ALL_AGENTS" <<'PY'
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

mode, query, requested_name, limit_str, dry_run_str, assume_yes_str, json_output, register_name, register_source, register_installed_at, register_commit, register_sha256, selected_agent, all_agents_str = sys.argv[1:15]
limit = int(limit_str) if limit_str.isdigit() else 10
dry_run = dry_run_str == "1"
assume_yes = assume_yes_str == "1"
json_output = json_output == "1"
all_agents = all_agents_str == "1"
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
    "drive": "drive", "automate": "automate", "learn": "learn", "scan": "scan"
}

STOP_WORDS = {
    "a", "an", "the", "in", "on", "at", "to", "for", "of", "and", "or", "is", "are", "with",
    "by", "that", "this", "from", "as", "it", "its", "be", "can", "do", "does", "did", "have",
    "has", "had", "will", "would", "shall", "should", "may", "might", "must", "find", "skill",
    "skills", "handles", "handled", "handling", "what", "which", "how", "who", "whom", "where",
    "when", "why", "there", "their", "them", "they", "i", "me", "my", "we", "us", "our", "you",
    "your", "he", "him", "his", "she", "her", "claude", "code", "agent", "assistant",
    "我", "你", "他", "她", "它", "我们", "你们", "他们", "的", "了", "在", "是", "有", "和", "就",
    "不", "人", "都", "一", "一个", "上", "也", "很", "到", "说", "要", "去", "会", "着",
    "没有", "看", "好", "自己", "这", "个", "装", "装过", "我装了", "我记得", "记得", "但是",
    "但是忘了名字", "忘了名字", "但是忘了", "帮我找", "帮我", "有没有", "能够", "可以", "能", "处理",
    "做", "用", "使用"
}

SYNONYMS = {
    "ppt": ["pptx", "presentation", "slides", "deck", "powerpoint", "slide"],
    "pptx": ["presentation", "slides", "deck", "powerpoint", "slide"],
    "powerpoint": ["pptx", "presentation", "slides", "deck"],
    "幻灯片": ["pptx", "presentation", "slides", "deck", "powerpoint"],
    "演示": ["presentation", "slides", "deck", "pptx"],
    "excel": ["xlsx", "spreadsheet", "spreadsheets", "csv", "table"],
    "xlsx": ["spreadsheet", "spreadsheets", "excel", "csv"],
    "表格": ["xlsx", "spreadsheet", "spreadsheets", "excel", "csv"],
    "电子表格": ["xlsx", "spreadsheet", "spreadsheets", "excel"],
    "word": ["docx", "document", "doc", "word"],
    "docx": ["document", "doc", "word"],
    "文档": ["document", "docs", "docx", "pdf"],
    "pdf": ["pdf", "document"],
    "图片": ["image", "vision", "photo", "screenshot", "picture"],
    "图像": ["image", "vision", "photo", "screenshot", "picture"],
    "照片": ["image", "vision", "photo", "screenshot"],
    "截图": ["screenshot", "image", "vision"],
    "识别": ["recognition", "recognize", "detect", "ocr", "identify", "understanding"],
    "理解": ["understanding", "recognition", "vision"],
    "语音": ["audio", "speech", "transcribe", "transcription", "transcript", "voice"],
    "录音": ["audio", "recording", "transcribe", "transcription"],
    "音频": ["audio", "sound", "speech"],
    "转文字": ["transcribe", "transcription", "transcript", "audio"],
    "转录": ["transcribe", "transcription", "transcript"],
    "视频": ["video", "clip", "editing", "ffmpeg"],
    "剪辑": ["video", "editing", "edit", "ffmpeg", "cut"],
    "字幕": ["transcript", "transcription", "subtitles", "youtube"],
    "youtube": ["youtube", "video", "transcript", "summarizer"],
    "总结": ["summarize", "summarizer", "summary", "digest"],
    "网页": ["web", "website", "frontend", "ui", "interface", "page"],
    "前端": ["frontend", "ui", "web", "interface", "design", "layout"],
    "界面": ["ui", "interface", "frontend", "gui"],
    "ui": ["ui", "interface", "frontend", "gui", "design"],
    "设计": ["design", "craft", "create", "layout"],
    "测试": ["test", "testing", "e2e", "qa", "tdd"],
    "端到端": ["e2e", "playwright", "end-to-end", "testing"],
    "playwright": ["e2e", "playwright", "browser", "testing"],
    "e2e": ["e2e", "playwright", "testing", "end-to-end"],
    "git": ["git", "github", "guardrails", "commit", "push", "branch"],
    "误推": ["guardrails", "dangerous", "push", "prevent", "block"],
    "安全": ["security", "audit", "auth", "authentication", "secrets"],
    "鉴权": ["authentication", "auth", "security", "secrets"],
    "认证": ["authentication", "auth", "security"],
    "防泄漏": ["secrets", "security", "guardrails"],
    "代码评审": ["review", "code review", "spec", "standards"],
    "评审": ["review", "code review", "spec"],
    "审查": ["review", "audit", "inspection"],
    "发布": ["ship", "deploy", "release", "publish"],
    "发版": ["ship", "release", "bump version", "deploy"],
    "ship": ["ship", "release", "deploy", "publish"],
    "prd": ["prd", "product", "requirements", "issues", "specification"],
    "需求": ["prd", "requirements", "issues", "spec"],
    "工单": ["issues", "triage", "tickets"],
    "issues": ["issues", "triage", "github", "tickets"],
    "提示词": ["prompt", "prompts", "prompt-engineer", "system prompt"],
    "prompt": ["prompt", "prompts", "prompt-engineer"],
    "prompts": ["prompt", "prompts", "prompt-engineer"],
    "知识库": ["vault", "notes", "obsidian", "knowledge"],
    "笔记": ["notes", "vault", "obsidian", "notebook"],
    "obsidian": ["obsidian", "vault", "notes", "second-brain"],
    "调研": ["research", "survey", "investigate", "intel"],
    "研究": ["research", "study", "papers", "survey"],
    "竞品": ["competitive", "market", "competitor", "analysis"],
    "市场": ["market", "industry", "research"],
    "战略": ["strategic", "strategy", "mckinsey", "executive"],
    "咨询": ["consulting", "strategist", "mckinsey"],
    "麦肯锡": ["mckinsey", "mckinsey-strategist", "strategy"],
    "架构": ["architecture", "architect", "senior-solution-architect", "c4", "adr"],
    "c4": ["c4", "architecture", "senior-solution-architect", "diagram"],
    "adr": ["adr", "architecture", "senior-solution-architect", "decision"],
    "rest": ["rest", "api", "api-design", "endpoint"],
    "api": ["api", "rest", "endpoint", "interface"],
    "后端": ["backend", "database", "server", "express", "node"],
    "数据库": ["database", "sql", "backend", "db"],
    "压缩": ["compress", "caveman", "compressed", "cut"],
    "token": ["token", "tokens", "caveman", "compression"],
    "caveman": ["caveman", "compressed", "tokens"],
    "数据集": ["dataset", "datasets", "parquet", "huggingface"],
    "dataset": ["dataset", "datasets", "parquet", "huggingface"],
    "datasets": ["dataset", "datasets", "parquet", "huggingface"],
    "论文": ["paper", "papers", "arxiv", "huggingface-papers"],
    "arxiv": ["arxiv", "papers", "paper", "research"],
    "股票": ["stock", "stocks", "finance", "financial", "fincept"],
    "行情": ["market", "ticker", "finance", "stock"],
    "金融": ["finance", "financial", "fincept", "market"],
    "终端": ["terminal", "fincept"],
    "克隆": ["clone", "cloner", "website-cloner", "copy"],
    "复刻": ["clone", "cloner", "website-cloner"],
}

def stem_word(word):
    w = word.lower().strip(",.?!:;()[]{}'\"")
    if len(w) > 5 and w.endswith("ing"):
        return w[:-3]
    if len(w) > 4 and w.endswith("ed"):
        return w[:-2]
    if len(w) > 4 and w.endswith("es"):
        return w[:-2]
    if len(w) > 3 and w.endswith("s"):
        return w[:-1]
    if len(w) > 6 and w.endswith("tion"):
        return w[:-4]
    return w

def extract_search_terms(q_str):
    raw = q_str.lower()
    raw_tokens = re.findall(r'[a-z0-9][a-z0-9_-]{1,}|[\u3400-\u9fff]+', raw)
    terms = []
    
    for t in raw_tokens:
        if t in STOP_WORDS:
            continue
        if re.match(r'[\u3400-\u9fff]+', t):
            matched_syns = False
            for k, syn_list in SYNONYMS.items():
                if k in t:
                    matched_syns = True
                    for s in syn_list:
                        if s not in terms:
                            terms.append(s)
                    if k not in terms:
                        terms.append(k)
            if not matched_syns and len(t) >= 2:
                terms.append(t)
        else:
            st = stem_word(t)
            if t not in terms:
                terms.append(t)
            if st not in terms and len(st) >= 2:
                terms.append(st)
            if t in SYNONYMS:
                for s in SYNONYMS[t]:
                    if s not in terms:
                        terms.append(s)
            elif st in SYNONYMS:
                for s in SYNONYMS[st]:
                    if s not in terms:
                        terms.append(s)
                        
    return [t for t in terms if t not in STOP_WORDS and len(t) >= 2]

def query_terms(raw_query):
    return extract_search_terms(raw_query)

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

    agents_obj = {
        "claude": {
            "visible": has_link,
            "path": link_path if has_link else None,
            "reason": "link present" if has_link else "link missing or broken"
        },
        "codex": {
            "visible": False,
            "path": None,
            "reason": "stub adapter / not installed"
        },
        "antigravity": {
            "visible": False,
            "path": None,
            "reason": "stub adapter / not installed"
        }
    }

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
            "agents": agents_obj,
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
        "agents": agents_obj,
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
            if not isinstance(old_skill, dict):
                continue
            old_name = old_skill.get("name")
            old_inst = old_skill.get("install_name")
            if old_name and (old_name not in scanned_names) and (old_inst not in scanned_names):
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
                    "agents": {
                        "claude": {"visible": False, "path": None, "reason": "missing"},
                        "codex": {"visible": False, "path": None, "reason": "stub adapter / not installed"},
                        "antigravity": {"visible": False, "path": None, "reason": "stub adapter / not installed"}
                    },
                }
                entries.append(missing_entry)

    entries.sort(key=lambda item: item["name"].lower())
    return {
        "schema_version": 3,
        "default_agent": "claude",
        "updated_at": now_iso,
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
                entry["provenance"] = "installer" if register_source.startswith("github:") else "local"
            if register_installed_at:
                entry["installed_at"] = register_installed_at
                entry["discovered_at"] = register_installed_at
            if register_commit:
                entry["commit"] = register_commit
            if register_sha256:
                entry["sha256"] = register_sha256
            entry["status"] = "ok"
            entry["health"] = "ok"
    return index

def migrate_index(data):
    if not isinstance(data, dict):
        return {"schema_version": 3, "default_agent": "claude", "updated_at": None, "skills": []}
    skills = data.get("skills", [])
    if not isinstance(skills, list):
        skills = []
    migrated_skills = []
    for entry in skills:
        if not isinstance(entry, dict):
            continue
        e = dict(entry)
        if "category" not in e or not e["category"]:
            kws = derive_keywords(e.get("name", ""), e.get("description", ""))
            e["category"] = infer_category("", e.get("name", ""), e.get("description", ""), kws)
        if "capabilities" not in e or not isinstance(e["capabilities"], list):
            kws = derive_keywords(e.get("name", ""), e.get("description", ""))
            e["capabilities"] = derive_capabilities("", e.get("name", ""), e.get("category", "other"), kws)
        if "status" not in e:
            e["status"] = "ok"
        if "health" not in e:
            e["health"] = "ok"

        raw_agents = e.get("agents")
        if not isinstance(raw_agents, dict):
            raw_agents = {}
        
        claude_obj = raw_agents.get("claude")
        if not isinstance(claude_obj, dict):
            claude_vis = (e.get("status") == "ok" and e.get("health") == "ok")
            claude_path = e.get("link_path") or e.get("source_path")
            raw_agents["claude"] = {
                "visible": claude_vis,
                "path": claude_path if claude_vis else None,
                "reason": "link present" if claude_vis else "link missing or broken"
            }
        else:
            if "visible" not in claude_obj:
                claude_obj["visible"] = (e.get("status") == "ok" and e.get("health") == "ok")
            if "path" not in claude_obj:
                claude_obj["path"] = e.get("link_path") or e.get("source_path")
            if "reason" not in claude_obj:
                claude_obj["reason"] = "link present" if claude_obj["visible"] else "link missing or broken"

        if "codex" not in raw_agents or not isinstance(raw_agents["codex"], dict):
            raw_agents["codex"] = {
                "visible": False,
                "path": None,
                "reason": "stub adapter / not installed"
            }
        if "antigravity" not in raw_agents or not isinstance(raw_agents["antigravity"], dict):
            raw_agents["antigravity"] = {
                "visible": False,
                "path": None,
                "reason": "stub adapter / not installed"
            }
        e["agents"] = raw_agents
        migrated_skills.append(e)

    return {
        "schema_version": 3,
        "default_agent": data.get("default_agent", "claude"),
        "updated_at": data.get("updated_at", data.get("generated_at")),
        "skills": migrated_skills
    }

def load_index():
    old = read_old_index()
    if old is not None and old.get("schema_version", 1) >= 3:
        return old
    if old is not None:
        return migrate_index(old)
    index = build_index()
    write_index(index)
    return index

def filter_skills_by_agent(skills, agent_name, all_ag=False):
    if all_ag:
        return skills
    return [
        s for s in skills
        if isinstance(s, dict) and s.get("agents", {}).get(agent_name, {}).get("visible") is True
    ]

def score_skill_entry(entry, query, terms):
    name = entry["name"].lower()
    desc = entry.get("description", "").lower()
    caps = [c.lower() for c in entry.get("capabilities", [])]
    cat = entry.get("category", "").lower()
    
    negative_words = ("无人机", "蓝牙", "3d 打印", "3d打印", "量子计算", "自动驾驶")
    q_lower = query.lower()
    if any(nw in q_lower for nw in negative_words):
        return 0, ""

    is_image_recog = any(w in q_lower for w in ("图片", "image", "vision", "screenshot")) and any(w in q_lower for w in ("识别", "recognition", "recognize", "understanding", "ocr", "detect"))
    if is_image_recog:
        skill_text = f"{name} {desc} {' '.join(caps)} {cat}"
        has_recog = any(w in skill_text for w in ("recognition", "recognize", "understand", "ocr", "detect", "identif", "vision", "trainer"))
        if not has_recog:
            return 0, ""

    score_val = 0
    hit_name = []
    hit_caps = []
    hit_desc = []
    hit_cat = []
    
    query_clean = re.sub(r'[\s_-]+', '', q_lower)
    name_clean = re.sub(r'[\s_-]+', '', name)
    if query_clean == name_clean:
        score_val += 60
        hit_name.append("exact")
    elif name_clean in query_clean:
        score_val += 35
        hit_name.append("name-substring")
        
    name_parts = name.split("-")
    for t in terms:
        t_stem = stem_word(t)
        if t == name or (len(t) >= 3 and t in name_parts):
            score_val += 30
            if t not in hit_name:
                hit_name.append(t)
        elif len(t) >= 3 and t in name:
            score_val += 18
            if t not in hit_name:
                hit_name.append(t)
            
        for c in caps:
            if t == c or t_stem == stem_word(c):
                score_val += 25
                if c not in hit_caps:
                    hit_caps.append(c)
                break
            elif len(t) >= 3 and (t in c or c in t):
                score_val += 15
                if c not in hit_caps:
                    hit_caps.append(c)
                break
                
        if t == cat:
            score_val += 10
            if t not in hit_cat:
                hit_cat.append(t)
            
        if len(t) >= 3 and (t in desc or t_stem in desc):
            score_val += 5
            if t not in hit_desc:
                hit_desc.append(t)
            
    is_ppt = any(w in q_lower for w in ("ppt", "pptx", "幻灯片", "powerpoint", "presentation", "slide"))
    if is_ppt and name not in ("pptx", "frontend-slides", "pptx-translator", "theme-factory", "storytelling-expert"):
        score_val -= 20
        
    is_excel = any(w in q_lower for w in ("excel", "xlsx", "表格", "电子表格", "spreadsheet", "spreadsheets"))
    if is_excel and name not in ("xlsx", "officecli", "data-analysis-workflow"):
        score_val -= 20
        
    is_pdf = "pdf" in q_lower
    if is_pdf and name not in ("pdf", "document-converter", "docx", "officecli", "webpage-reader"):
        score_val -= 20
        
    is_video = any(w in q_lower for w in ("video", "视频", "剪辑", "ffmpeg"))
    if is_video and name not in ("video-editing", "fal-ai-media", "mmx-cli", "youtube-summarizer"):
        score_val -= 20
        
    is_audio = any(w in q_lower for w in ("audio", "transcribe", "transcription", "语音", "录音", "转文字", "转录"))
    if is_audio and name not in ("audio-transcriber", "youtube-summarizer", "fal-ai-media"):
        score_val -= 20
        
    is_obsidian = any(w in q_lower for w in ("obsidian", "vault", "双链"))
    if is_obsidian and name not in ("obsidian-vault", "obsidian-second-brain", "memory-recall"):
        score_val -= 25

    is_prd = any(w in q_lower for w in ("prd", "需求文档"))
    if is_prd:
        if "对话" in query or "整理" in query or "turn conversation" in q_lower:
            if name == "to-prd":
                score_val += 70
            elif name == "to-issues":
                score_val += 30
        elif "issue" in q_lower or "工单" in query or "拆解" in query:
            if name == "to-issues":
                score_val += 70
        else:
            if name in ("to-prd", "to-issues", "product-capability"):
                score_val += 50
        if name in ("pdf", "docx", "xlsx"):
            score_val -= 40

    if ("图片" in query and "视频" in query) or ("image" in q_lower and "video" in q_lower):
        if name == "fal-ai-media":
            score_val += 45

    if ("audio" in q_lower or "语音" in query) and "youtube" not in q_lower and "视频" not in query:
        if name == "audio-transcriber":
            score_val += 40

    if score_val < 8:
        return 0, ""

    reasons = []
    if hit_name:
        reasons.append(f'name="{name}" hit on {list(set(hit_name))}')
    if hit_caps:
        reasons.append(f'capabilities={list(set(hit_caps))}')
    if hit_desc:
        reasons.append(f'description hit on {list(set(hit_desc))[:3]}')
    if hit_cat:
        reasons.append(f'category="{cat}"')
        
    reason_str = "matched: " + ("; ".join(reasons) if reasons else "relevance match")
    return score_val, reason_str

def score(entry, search_query):
    sc, _ = score_skill_entry(entry, search_query, extract_search_terms(search_query))
    return sc

def print_entries(skills):
    if json_output:
        print(json.dumps(skills, ensure_ascii=False, indent=2))
        return
    print(f"Skills: {len(skills)}")
    for entry in skills:
        name = entry["name"]
        status = entry.get("status", "unknown")
        desc = entry.get("description", "")
        if len(desc) > 80:
            desc = desc[:77] + "..."
        print(f"{name:<38} [{status:<7}] {desc}")

def print_capabilities(index_data, target_skills=None):
    skills = target_skills if target_skills is not None else index_data.get("skills", [])
    categories = [
        ("documents", "Documents"),
        ("development", "Development"),
        ("media", "Media"),
        ("data", "Data"),
        ("browser", "Browser"),
        ("research", "Research"),
        ("other", "Other"),
    ]

    by_cat = {c[0]: [] for c in categories}
    broken = []

    for s in skills:
        if s.get("status") != "ok" or s.get("health") != "ok":
            broken.append(s)
        else:
            cat = s.get("category", "other").lower()
            if cat not in by_cat:
                cat = "other"
            by_cat[cat].append(s)

    total_count = len(skills)
    broken_count = len(broken)
    print(f"Your Agent currently has {total_count} Skills ({broken_count} broken)\n")

    for cat_key, cat_name in categories:
        group = by_cat[cat_key]
        if group:
            print(f"{cat_name} ({len(group)})")
            for s in sorted(group, key=lambda x: x["name"].lower()):
                desc = s.get("description", "")
                if len(desc) > 60:
                    desc = desc[:57] + "..."
                elif not desc:
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

PROTOTYPE_VERBS = {
    "use": ["use", "using", "used", "uses"],
    "create": ["create", "creating", "created", "creates", "creation"],
    "build": ["build", "building", "built", "builds"],
    "generate": ["generate", "generating", "generated", "generates", "generation"],
    "analyze": ["analyze", "analyzing", "analyzed", "analyzes", "analysis", "analytics"],
    "find": ["find", "finding", "found", "finds"],
    "check": ["check", "checking", "checked", "checks"],
    "inspect": ["inspect", "inspecting", "inspected", "inspects", "inspection"],
    "run": ["run", "running", "ran", "runs"],
    "convert": ["convert", "converting", "converted", "converts", "conversion"],
    "translate": ["translate", "translating", "translated", "translates", "translation"],
    "design": ["design", "designing", "designed", "designs"],
    "write": ["write", "writing", "written", "writes", "wrote"],
    "read": ["read", "reading", "reads"],
    "manage": ["manage", "managing", "managed", "manages", "management"],
    "deploy": ["deploy", "deploying", "deployed", "deploys", "deployment"],
    "test": ["test", "testing", "tested", "tests"],
    "validate": ["validate", "validating", "validated", "validates", "validation"],
    "summarize": ["summarize", "summarizing", "summarized", "summarizes", "summary"],
    "search": ["search", "searching", "searched", "searches"]
}

def evaluate_trigger_quality(frontmatter, desc, caps, cat):
    passed_rules = 0
    warnings = 0
    details = []
    recommendations = []
    desc_clean = desc.strip() if desc else ""
    desc_lower = desc_clean.lower()

    # Rule 1: Trigger prefix
    if desc_clean and (desc_lower.startswith("use when") or desc_lower.startswith("this skill should be used when") or desc_lower.startswith("trigger when")):
        passed_rules += 1
        details.append(('✓', 'Description starts with explicit trigger phrase ("Use when...")'))
    elif desc_clean and ("when" in desc_lower or "whenever" in desc_lower):
        passed_rules += 1
        details.append(('✓', 'Description contains trigger phrase ("when")'))
    else:
        warnings += 1
        details.append(('⚠', 'Description lacks explicit trigger phrase ("Use when...")'))
        recommendations.append('Start description with "Use when the user wants to..."')

    # Rule 2: Contains action verbs
    action_words = ('use', 'create', 'analyze', 'build', 'check', 'inspect', 'run', 'extract', 'convert', 'manage', 'format', 'test', 'search', 'query', 'deploy', 'fix', 'scaffold', 'design', 'write', 'edit', 'review', 'translate', 'summarize', 'crawl', 'scrape', 'monitor', '转换', '提取', '创建', '分析', '构建', '检查', '运行', '调试', '搜索', '编写', '审查', '设计', '做')
    if any(act in desc_lower for act in action_words):
        passed_rules += 1
        details.append(('✓', 'Description contains action verbs'))
    else:
        warnings += 1
        details.append(('⚠', 'Description lacks clear action verbs'))
        recommendations.append('Add action verbs (e.g. create, analyze, convert, manage) to description')

    # Rule 3: Verb diversity (>=3 distinct prototype verbs)
    found_verbs = []
    for pverb, forms in PROTOTYPE_VERBS.items():
        if any(re.search(r'\b' + re.escape(form) + r'\b', desc_lower) for form in forms):
            found_verbs.append(pverb)
    if len(found_verbs) >= 3:
        passed_rules += 1
        details.append(('✓', f'Rich verb diversity ({len(found_verbs)} action verbs: {", ".join(found_verbs[:5])})'))
    elif len(found_verbs) in (1, 2):
        warnings += 1
        details.append(('⚠', f'Consider more action verbs (found {len(found_verbs)}: {", ".join(found_verbs)})'))
        recommendations.append('Include at least 3 distinct action verbs to broaden trigger recognition')
    else:
        warnings += 1
        details.append(('⚠', 'No action verbs detected'))
        recommendations.append('Include at least 3 distinct action verbs (e.g. use, create, manage)')

    # Rule 4: Concrete examples
    example_markers = ("e.g.", "例如", "比如", "such as", "examples include", "for example")
    if any(m in desc_lower for m in example_markers):
        passed_rules += 1
        details.append(('✓', 'Concrete examples present'))
    else:
        warnings += 1
        details.append(('⚠', 'No concrete examples; consider adding (e.g., "for example, ...")'))
        recommendations.append('Consider adding concrete examples (e.g., "for example, ...", "such as ...")')

    # Rule 5: Appropriate length (30-200 chars)
    char_len = len(desc_clean)
    if 30 <= char_len <= 200:
        passed_rules += 1
        details.append(('✓', f'Appropriate length ({char_len} chars)'))
    elif char_len < 30:
        warnings += 1
        details.append(('⚠', f'Description too short ({char_len} chars, recommend 30-200)'))
        recommendations.append('Expand description to between 30 and 200 characters')
    else:
        warnings += 1
        details.append(('⚠', f'Description too long ({char_len} chars, recommend 30-200; risk of dilution)'))
        recommendations.append('Trim description to between 30 and 200 characters to avoid trigger dilution')

    # Rule 6: Well-formed first sentence (no list/bullet prefix)
    is_list_start = bool(re.match(r'^\s*(?:[-*•]|\d+[\.\)])\s+', desc_clean))
    if not is_list_start and char_len > 0:
        passed_rules += 1
        details.append(('✓', 'Well-formed first sentence'))
    else:
        warnings += 1
        details.append(('⚠', 'First sentence looks like a list; rewrite as prose'))
        recommendations.append('Rewrite initial bullet list as a continuous prose sentence')

    # Rule 7: Explicit capabilities
    if caps:
        passed_rules += 1
        details.append(('✓', f'Capabilities declared: [{caps}]'))
    else:
        warnings += 1
        details.append(('⚠', 'No explicit capabilities tags in frontmatter — auto-derived only'))
        recommendations.append('Add "capabilities: [...]" to SKILL.md frontmatter')

    # Rule 8: Explicit category
    if cat:
        passed_rules += 1
        details.append(('✓', f'Category declared: {cat}'))
    else:
        warnings += 1
        details.append(('⚠', 'No explicit category in frontmatter — auto-bucketed'))
        recommendations.append('Add "category: <cat>" to SKILL.md frontmatter')

    score_pct = round((passed_rules / 8.0) * 100.0, 1)
    return {
        "passed": passed_rules,
        "warnings": warnings,
        "score": score_pct,
        "details": details,
        "recommendations": recommendations
    }

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

    healthy_scores = []
    healthy_skills = [s for s in skills if s.get("status") == "ok" and s.get("health") == "ok"]
    for s in healthy_skills:
        dir_name = s.get("install_name", s["name"])
        s_file = skills_dir / dir_name / "SKILL.md"
        l_file = link_dir / dir_name / "SKILL.md"
        raw = ""
        if s_file.is_file():
            try: raw = s_file.read_text(encoding="utf-8")
            except Exception: pass
        elif l_file.is_file():
            try: raw = l_file.read_text(encoding="utf-8")
            except Exception: pass
        m = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n|$)", raw)
        fm = m.group(1) if m else ""
        d_desc = extract_frontmatter_field(fm, "description")
        d_caps = extract_frontmatter_field(fm, "capabilities")
        d_cat = extract_frontmatter_field(fm, "category")
        ev = evaluate_trigger_quality(fm, d_desc, d_caps, d_cat)
        healthy_scores.append({"name": s["name"], "score": ev["score"], "warnings": ev["warnings"]})

    avg_score = round(sum(item["score"] for item in healthy_scores) / len(healthy_scores), 1) if healthy_scores else 0.0
    print(f"trigger quality: avg {avg_score:.1f}% across healthy skills")

    lowest_top3 = sorted(healthy_scores, key=lambda x: (x["score"], x["name"]))[:3]
    if lowest_top3:
        print("Top 3 skills with lowest score:")
        for low in lowest_top3:
            print(f"  - {low['name']} ({low['score']:.1f}%)")

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

    if source_exists and link_exists:
        if source_file_exists and link_file_exists:
            try:
                s_hash = hashlib.sha256(source_file.read_bytes()).hexdigest()
                l_hash = hashlib.sha256(link_file.read_bytes()).hexdigest()
                if s_hash == l_hash:
                    print("  ✓ Source and link SKILL.md match")
                else:
                    print("  ✗ Source and link SKILL.md differ (out of sync)")
                    suggestions.append(f"Re-link with: bash lib/install.sh --local \"$CLAUDE_SKILLS_DIR/{dir_name}\" --link-only --force")
            except Exception:
                pass
    else:
        print("  ⚠ Single copy found (no link hash comparison)")
    print()

    print("Structure")
    if source_file_exists or link_file_exists:
        print("  ✓ SKILL.md present")
    else:
        print("  ✗ SKILL.md missing")
        suggestions.append(f"Create $CLAUDE_SKILLS_DIR/{dir_name}/SKILL.md")

    if frontmatter_match:
        print("  ✓ YAML frontmatter valid")
    else:
        print("  ✗ YAML frontmatter missing or unparseable")

    if declared_name:
        if declared_name == skill_name or (entry and declared_name == entry.get("name")):
            print(f"  ✓ name = {declared_name}")
        else:
            print(f"  ⚠ name ({declared_name}) differs from directory name ({skill_name})")
    else:
        print("  ✗ name missing in frontmatter")

    if declared_desc:
        print("  ✓ description present")
    else:
        print("  ✗ description missing in frontmatter")
    print()

    print("Discovery")
    if link_exists:
        print("  ✓ Claude link path visible")
    else:
        print("  ✗ Not visible in Claude link path")
        suggestions.append(f"Create symlink: ln -s \"$CLAUDE_SKILLS_DIR/{dir_name}\" \"$CLAUDE_SKILLS_LINK_DIR/{dir_name}\"")

    if (source_file_exists and os.access(source_file, os.R_OK)) or (link_file_exists and os.access(link_file, os.R_OK)):
        print("  ✓ File readable")
    else:
        print("  ✗ File not readable (permission issue)")
    print()

    print("Trigger quality")
    ev = evaluate_trigger_quality(frontmatter, declared_desc, declared_caps, declared_cat)
    for icon, msg in ev["details"]:
        print(f"  {icon} {msg}")
    print()
    print(f"  trigger quality: {ev['warnings']} ⚠ / 8 ✓ (score: {ev['score']:.1f}%)")
    if ev["warnings"] == 0 or ev["score"] >= 70.0:
        print("  ✓ Trigger description looks Claude-discoverable")
    print()

    if ev["recommendations"]:
        print("Recommendations:")
        for r in ev["recommendations"]:
            print(f"  - {r}")
        print()

    if suggestions:
        print("Suggestions:")
        for s in suggestions:
            print(f"  - {s}")

def get_trigger_warning_count(frontmatter, desc, caps, cat):
    ev = evaluate_trigger_quality(frontmatter, desc, caps, cat)
    return ev["warnings"]

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
        if k not in selected:
            selected.append(k)
        if len(selected) >= 5:
            break
    if not selected:
        selected = [name, category]
    return selected

def build_fixed_frontmatter(original_frontmatter, new_desc, new_caps, new_cat):
    lines = original_frontmatter.splitlines()
    desc_line_indices = []
    i = 0
    while i < len(lines):
        line = lines[i]
        trimmed = line.strip()
        m_scalar = re.match(r"^description:\s*([>|][+-]?)$", trimmed)
        if m_scalar or re.match(r"^description:\s*$", line):
            desc_line_indices.append(i)
            j = i + 1
            while j < len(lines):
                subline = lines[j]
                if not subline.strip():
                    j += 1
                    continue
                if subline.startswith(" ") or subline.startswith("\t"):
                    desc_line_indices.append(j)
                    j += 1
                else:
                    break
            i = j
            continue
        elif re.match(r"^description:\s*\S", line):
            desc_line_indices.append(i)
        i += 1

    caps_line_indices = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^capabilities:\s*$", line) or re.match(r"^capabilities:\s*([>|][+-]?)$", line.strip()):
            caps_line_indices.append(i)
            j = i + 1
            while j < len(lines):
                subline = lines[j]
                if not subline.strip():
                    j += 1
                    continue
                if subline.startswith(" ") or subline.startswith("\t"):
                    caps_line_indices.append(j)
                    j += 1
                else:
                    break
            i = j
            continue
        elif re.match(r"^capabilities:\s*\S", line):
            caps_line_indices.append(i)
        i += 1

    cat_line_indices = [idx for idx, l in enumerate(lines) if re.match(r"^category:\s*", l)]
    indices_to_remove = set(desc_line_indices + caps_line_indices + cat_line_indices)

    preserved = []
    for idx, l in enumerate(lines):
        if idx not in indices_to_remove:
            preserved.append(l)

    name_idx = -1
    for idx, l in enumerate(preserved):
        if re.match(r"^name:\s*", l):
            name_idx = idx
            break

    insert_lines = [f"description: {new_desc}", "capabilities:"]
    for c in new_caps:
        insert_lines.append(f"  - {c}")
    insert_lines.append(f"category: {new_cat}")

    if name_idx >= 0:
        new_lines = preserved[:name_idx+1] + insert_lines + preserved[name_idx+1:]
    else:
        new_lines = insert_lines + preserved

    return "\n".join(new_lines)

def fix_skill(entry, is_dry_run, confirm_yes):
    dir_name = entry.get("install_name", entry["name"])
    source_disk = skills_dir / dir_name
    link_disk = link_dir / dir_name
    target_file = None
    target_disk = None

    if (source_disk / "SKILL.md").is_file():
        target_file = source_disk / "SKILL.md"
        target_disk = source_disk
    elif (link_disk / "SKILL.md").is_file():
        target_file = link_disk / "SKILL.md"
        target_disk = link_disk
    else:
        print(f"Skipping {entry['name']}: SKILL.md not found")
        return

    try:
        raw_content = target_file.read_text(encoding="utf-8")
    except Exception as ex:
        print(f"Skipping {entry['name']}: unable to read SKILL.md: {ex}")
        return

    check_match = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n(.*))?$", raw_content)
    if not check_match:
        print(f"Skipping {entry['name']}: frontmatter missing or invalid")
        return

    frontmatter = check_match.group(1)
    body = check_match.group(2) or ""

    old_desc = extract_frontmatter_field(frontmatter, "description")
    old_caps = extract_frontmatter_field(frontmatter, "capabilities")
    old_cat = extract_frontmatter_field(frontmatter, "category")

    new_desc, changed, skip, reason = rewrite_description(old_desc)
    if skip:
        print(f"Skipping {entry['name']}: {reason}")
        return

    new_cat = infer_category(old_cat, entry["name"], new_desc, derive_keywords(entry["name"], new_desc))
    new_caps = get_top_capabilities(frontmatter, entry["name"], new_desc, new_cat)

    new_frontmatter = build_fixed_frontmatter(frontmatter, new_desc, new_caps, new_cat)
    is_symlink = is_symlink_or_reparse(target_disk) or is_symlink_or_reparse(target_file)

    if is_symlink:
        print(f"refusing to modify symlink: {target_file}; suggested patch for {entry['name']}:")
        print("---\n" + new_frontmatter + "\n---")
        return

    if is_dry_run:
        print(f"[proposed] {entry['name']}\n")
        print(f"description (before):\n  {old_desc}\n")
        print(f"description (after):\n  {new_desc}\n")
        print("capabilities (added):")
        for c in new_caps:
            print(f"  - {c}")
        print(f"\ncategory (added):\n  {new_cat}\n")
        ts = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        print(f"no symlink. backup would go to: $CLAUDE_SKILLS_DIR/.backups/{entry['name']}-{ts}-SKILL.md\n")
        return

    if not confirm_yes:
        print(f"[proposed] {entry['name']}\n")
        print(f"description (after):\n  {new_desc}\n")
        print(f"capabilities (added):\n  {', '.join(new_caps)}\n")
        print(f"category (added):\n  {new_cat}\n")
        try:
            ans = input("Apply changes to this skill? [y/N] ").strip().lower()
        except (EOFError, KeyboardInterrupt):
            ans = "n"
        if ans not in ("y", "yes"):
            print(f"Skipped {entry['name']}.")
            return

    backup_dir = skills_dir / ".backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    ts = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_file = backup_dir / f"{entry['name']}-{ts}-SKILL.md"
    try:
        backup_file.write_text(raw_content, encoding="utf-8")
    except Exception as ex:
        print(f"Failed to create backup for {entry['name']}: {ex}")
        return

    new_full_content = "---\n" + new_frontmatter + "\n---\n" + body
    try:
        target_file.write_text(new_full_content, encoding="utf-8")
    except Exception as ex:
        print(f"Failed to write changes for {entry['name']}: {ex}")
        return

    try:
        verify_content = target_file.read_text(encoding="utf-8")
        verify_match = re.search(r"(?ms)^---\s*\r?\n(.*?)\r?\n---(?:\s*\r?\n(.*))?$", verify_content)
        if not verify_match or not extract_frontmatter_field(verify_match.group(1), "name"):
            raise ValueError("Verification failed: corrupted frontmatter")
    except Exception as ex:
        print(f"CRITICAL: verification failed after modifying {entry['name']}, restoring from backup: {ex}")
        target_file.write_text(raw_content, encoding="utf-8")
        return

    before_warnings = get_trigger_warning_count(frontmatter, old_desc, old_caps, old_cat)
    after_warnings = get_trigger_warning_count(new_frontmatter, new_desc, ",".join(new_caps), new_cat)

    print(f"fixed {entry['name']}: description rewritten, capabilities + category added")
    print(f"  trigger quality: {after_warnings} ⚠ (was {before_warnings} ⚠)")

try:
    index = load_index()

    if mode == "refresh":
        if selected_agent != "claude":
            raise SystemExit(f"not-yet-implemented: see adapters/{selected_agent}/stub-note.md")
        index = build_index()
        index = apply_registration(index)
        write_index(index)
        print_entries(index["skills"])
    elif mode == "capabilities":
        target_skills = filter_skills_by_agent(index.get("skills", []), selected_agent, all_agents)
        if not target_skills and not all_agents:
            print(f"No visible skills for agent '{selected_agent}' (use --all-agents to inspect all catalog skills).")
            raise SystemExit(0)
        print_capabilities(index, target_skills)
    elif mode == "list":
        target_skills = filter_skills_by_agent(index.get("skills", []), selected_agent, all_agents)
        print_entries(target_skills)
    elif mode == "find":
        if not query or not query.strip():
            raise SystemExit("query is required for find")
        target_skills = filter_skills_by_agent(index.get("skills", []), selected_agent, all_agents)
        terms = extract_search_terms(query)
        scored = []
        for entry in target_skills:
            sc, reason = score_skill_entry(entry, query, terms)
            if sc > 0:
                scored.append({"score": sc, "reason": reason, "entry": entry})
        scored.sort(key=lambda item: item["score"], reverse=True)
        if not scored:
            print(f'No matching skills for "{query}".')
            raise SystemExit(0)
        if json_output:
            out_list = []
            for item in scored:
                e = dict(item["entry"])
                e["score"] = item["score"]
                e["match_reason"] = item["reason"]
                out_list.append(e)
            print(json.dumps(out_list, ensure_ascii=False, indent=2))
            raise SystemExit(0)
        top_list = scored[:limit]
        print(f'Matches for "{query}":\n')
        for idx, item in enumerate(top_list):
            num = idx + 1
            entry = item["entry"]
            sc_val = item["score"]
            reason = item.get("reason", "")
            desc = entry.get("description") or "(no description)"
            if len(desc) > 75:
                desc = desc[:72] + "..."
            print(f"  {num:>2}. {entry['name']:<28} (score: {sc_val})")
            print(f"     {desc}")
            if reason:
                print(f"     {reason}\n")
            else:
                print()
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
            for ag in ("claude", "codex", "antigravity"):
                ag_info = entry.get("agents", {}).get(ag, {})
                print(f"agents.{ag}.visible: {ag_info.get('visible', False)}")
            print(f"usage.status: {entry.get('usage', {}).get('status', 'unknown')}")
            print("invocation_hint: Ask Claude Code to use the named skill for a matching task. Automatic invocation is not observable by this catalog.")
    elif mode == "doctor":
        if selected_agent != "claude" and not all_agents:
            print(f"doctor: agent '{selected_agent}' is a stub adapter (not-yet-implemented). No skills installed.")
            raise SystemExit(0)
        fresh = build_index()
        if requested_name:
            doctor_single(requested_name, fresh)
        else:
            doctor_global(fresh)
    elif mode == "fix":
        if selected_agent != "claude":
            raise SystemExit(f"not-yet-implemented: see adapters/{selected_agent}/stub-note.md")
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
