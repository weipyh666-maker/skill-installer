#!/usr/bin/env bash
#
# install.sh — portable Bash installer for Claude Code skills
#
# Smoke tests and memory writes are opt-in. Downloaded repositories are
# untrusted until the user reviews the source and ref.

set -euo pipefail

REPO=''
REF=''
LOCAL_PATH=''
NAME=''
NAME_WAS_EXPLICIT=0
LINK_ONLY=0
FORCE=0
DRY_RUN=0
RUN_SMOKE=0
SKIP_SMOKE=0
UPDATE_MEMORY=0
SKIP_MEMORY=0
SKIP_CATALOG=0
EXPECTED_SHA256=''
REQUIRE_PINNED=0
REQUIRE_AUTH=0
ALLOW_ANON_SET=0
REQUIRE_AUTH_SET=0
TEMP_ROOT=''
AGENT=''
SCOPE='user'
SUBDIR=''
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../adapters/_base.sh"
source "$SCRIPT_DIR/../adapters/claude/paths.sh"
source "$SCRIPT_DIR/../adapters/claude/detect.sh"
source "$SCRIPT_DIR/../adapters/antigravity/paths.sh"
source "$SCRIPT_DIR/../adapters/antigravity/detect.sh"
source "$SCRIPT_DIR/../adapters/codex/paths.sh"
source "$SCRIPT_DIR/../adapters/codex/detect.sh"

usage() {
    sed -n '1,35p' "$0"
    cat <<'USAGE'

Options:
  --repo owner/name          GitHub repository
  --ref branch|tag|sha       Git ref; pin this for reproducible installs
  --local PATH               Local skill directory
  --name NAME                Installed skill name
  --agent AGENT              Target agent (claude|codex|antigravity, default: claude)
  --link-only                Recreate a link from an existing source
  --force                    Replace an existing install after backing it up
  --dry-run                  Validate and print the plan without changing files
  --run-smoke-test           Explicitly execute a reviewed source's --version/--help
  --skip-smoke-test          Compatibility flag; do not execute source code
  --update-memory            Append an idempotent row to installed-tools-summary.md
  --skip-memory              Compatibility flag; do not update memory
  --skip-catalog-update      Do not refresh the installed-skill index
  --expected-sha256 HASH     Verify the downloaded tarball digest
  --require-pinned-ref       Fail when --ref is omitted
  --require-auth             Require gh CLI authentication; disable anonymous fallback
  --allow-anonymous-fallback Allow curl anonymous download if gh is not authenticated (default)
USAGE
}

fail() {
    echo "INSTALL FAILED: $*" >&2
    exit 1
}

step() { printf '\n[%s/7] %s\n' "$1" "$2"; }
ok() { printf '  + %s\n' "$1"; }
warn() { printf '  ! %s\n' "$1" >&2; }

canonical_path() {
    if command -v readlink >/dev/null 2>&1 && readlink -f -- "$1" >/dev/null 2>&1; then
        readlink -f -- "$1"
        return
    fi
    if command -v realpath >/dev/null 2>&1 && realpath -m -- . >/dev/null 2>&1; then
        realpath -m -- "$1"
        return
    fi
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
        python3 - "$1" <<'PY'
import os, sys
print(os.path.realpath(os.path.expanduser(sys.argv[1])).replace('\\', '/'))
PY
        return
    fi
    if command -v python >/dev/null 2>&1 && python -c 'import sys' >/dev/null 2>&1; then
        python - "$1" <<'PY'
import os, sys
print(os.path.realpath(os.path.expanduser(sys.argv[1])).replace('\\', '/'))
PY
        return
    fi
    fail 'python3, python or realpath is required for safe path validation'
}

valid_name() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]]
}

valid_repo() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,99}/[A-Za-z0-9][A-Za-z0-9._-]{0,99}$ ]]
}

valid_ref() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,127}$ && "$1" != *'..'* ]]
}

valid_hash() {
    [[ -z "$1" || "$1" =~ ^[A-Fa-f0-9]{64}$ ]]
}

assert_safe_name() {
    valid_name "$1" || fail "invalid skill name '$1'; use 1-64 letters, numbers, dots, hyphens, or underscores"
}

assert_safe_repo() {
    valid_repo "$1" || fail "invalid GitHub repository '$1'; expected owner/name"
}

assert_safe_ref() {
    valid_ref "$1" || fail "invalid Git ref '$1'; use a branch, tag, or commit SHA without spaces or traversal"
}

assert_safe_hash() {
    valid_hash "$1" || fail 'expected SHA256 must be exactly 64 hexadecimal characters'
}

assert_child_path() {
    local base child
    base="$(canonical_path "$1")"
    child="$(canonical_path "$2")"
    [[ "$child" == "$base/"* && "$child" != "$base" ]] || fail "$3 escapes its allowed directory: $child"
}

existing_path() {
    [[ -e "$1" || -L "$1" ]]
}

assert_no_sensitive_files() {
    local root="$1"
    local found
    found="$(find "$root" -type f \( -name '.env' -o -name '.env.*' -o -name '*.key' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' \) -print 2>/dev/null | head -n 1 || true)"
    [[ -z "$found" ]] || fail "refusing to copy sensitive file: $found"
    found="$(find "$root" -type d \( -name '.git' -o -name 'secrets' \) -print 2>/dev/null | head -n 1 || true)"
    [[ -z "$found" ]] || fail "refusing to copy repository-internal directory: $found"
    found="$(find "$root" -type l -print 2>/dev/null | head -n 1 || true)"
    [[ -z "$found" ]] || fail "refusing to copy symbolic link inside skill: $found"
}

assert_skill_layout() {
    local root="$1"
    [[ -f "$root/SKILL.md" ]] || fail "SKILL.md not found at $root"
    local header
    header="$(head -n 40 "$root/SKILL.md")"
    echo "$header" | grep -Eq '^---[[:space:]]*$' || fail "SKILL.md has no YAML frontmatter"
    echo "$header" | grep -Eq '^name:[[:space:]]*[a-z0-9][a-z0-9-]{0,63}[[:space:]]*$' || fail "SKILL.md name is invalid"
    echo "$header" | grep -Eq '^description:[[:space:]]*[^[:space:]].*$' || fail "SKILL.md description is missing"
}

copy_contents() {
    mkdir -p "$2"
    cp -a "$1"/. "$2"/
}

remove_install_entry() {
    if [[ -L "$1" ]]; then
        rm -f -- "$1"
    else
        rm -rf -- "$1"
    fi
}

backup_existing() {
    local path="$1" label="$2" backup_root="$3" skill_name="$4"
    [[ -e "$path" || -L "$path" ]] || return 0
    mkdir -p "$backup_root"
    local stamp destination
    stamp="$(date +%Y%m%d-%H%M%S)"
    destination="$backup_root/$skill_name-$stamp-$label"
    mv -- "$path" "$destination"
    printf '%s' "$destination"
}

create_install_link() {
    local source="$1" link="$2"
    if ln -s -- "$source" "$link" 2>/dev/null; then
        printf 'symlink'
    else
        copy_contents "$source" "$link"
        printf 'copy-fallback'
    fi
}

codex_protected_target() {
    [[ "$AGENT" == 'codex' ]] || return 1
    local candidate protected probe resolved
    candidate="$(canonical_path "$1")"
    if [[ -z "$candidate" || "$candidate" == "$1" ]]; then
        local parent leaf resolved_parent
        parent="$(dirname -- "$1")"; leaf="$(basename -- "$1")"
        resolved_parent="$(canonical_path "$parent")"
        [[ -n "$resolved_parent" ]] && candidate="$resolved_parent/$leaf"
    fi
    for protected in "$(get_codex_system_skill_root)" "$(get_codex_admin_skill_root || true)"; do
        [[ -n "$protected" ]] || continue
        protected="$(canonical_path "$protected")"
        [[ "$candidate" == "$protected" || "$candidate" == "$protected/"* ]] && return 0
    done
    probe="$1"
    while [[ -n "$probe" && "$probe" != "/" && "$probe" != "." ]]; do
        if [[ -L "$probe" ]]; then
            resolved="$(canonical_path "$probe")"
            for protected in "$(get_codex_system_skill_root)" "$(get_codex_admin_skill_root || true)"; do
                [[ -n "$protected" ]] || continue
                protected="$(canonical_path "$protected")"
                [[ "$resolved" == "$protected" || "$resolved" == "$protected/"* ]] && return 0
            done
        fi
        probe="$(dirname -- "$probe")"
    done
    return 1
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print toupper($1)}'
    else
        shasum -a 256 "$1" | awk '{print toupper($1)}'
    fi
}

update_memory() {
    local file="$1" skill_name="$2" repo="$3" source="$4" link="$5" smoke="$6"
    [[ -f "$file" ]] || { printf 'memory file not found (skip)'; return; }
    if grep -Fq -- "| $skill_name |" "$file"; then
        printf 'already present'
        return
    fi
    printf '| %s | %s | %s | → %s | %s | %s |\n' \
        "$skill_name" "$repo" "$source" "$link" "$smoke" "$(date +%Y-%m-%d)" >> "$file"
    printf 'appended to %s' "$file"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)              [[ $# -ge 2 ]] || fail '--repo needs owner/name'; REPO="$2"; shift 2 ;;
        --ref)               [[ $# -ge 2 ]] || fail '--ref needs a value'; REF="$2"; shift 2 ;;
        --local)             [[ $# -ge 2 ]] || fail '--local needs a directory'; LOCAL_PATH="$2"; shift 2 ;;
        --name)              [[ $# -ge 2 ]] || fail '--name needs a value'; NAME="$2"; NAME_WAS_EXPLICIT=1; shift 2 ;;
        --agent)             [[ $# -ge 2 ]] || fail '--agent needs a value'; AGENT="$2"; shift 2 ;;
        --scope)             [[ $# -ge 2 ]] || fail '--scope needs user or codex-home'; SCOPE="$2"; shift 2 ;;
        --subdir)            [[ $# -ge 2 ]] || fail '--subdir needs a staging-tree path'; SUBDIR="$2"; shift 2 ;;
        --link-only)         LINK_ONLY=1; shift ;;
        --force)             FORCE=1; shift ;;
        --dry-run)           DRY_RUN=1; shift ;;
        --run-smoke-test)    RUN_SMOKE=1; shift ;;
        --skip-smoke-test)   SKIP_SMOKE=1; shift ;;
        --update-memory)     UPDATE_MEMORY=1; shift ;;
        --skip-memory)       SKIP_MEMORY=1; shift ;;
        --skip-catalog-update) SKIP_CATALOG=1; shift ;;
        --expected-sha256)   [[ $# -ge 2 ]] || fail '--expected-sha256 needs a value'; EXPECTED_SHA256="$2"; shift 2 ;;
        --require-auth)              REQUIRE_AUTH=1; REQUIRE_AUTH_SET=1; shift ;;
        --allow-anonymous-fallback)  ALLOW_ANON_SET=1; shift ;;
        --require-pinned-ref) REQUIRE_PINNED=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        */*)                 [[ -z "$REPO" ]] || fail "unknown argument: $1"; REPO="$1"; shift ;;
        *)                   fail "unknown argument: $1" ;;
    esac
done

[[ -z "$REPO" || -z "$LOCAL_PATH" ]] || fail 'use either --repo or --local, not both'
[[ -z "$REF" || -n "$REPO" ]] || fail '--ref can only be used with a GitHub repository'
[[ -z "$EXPECTED_SHA256" || -n "$REPO" ]] || fail '--expected-sha256 can only be used with a GitHub repository'
[[ "$REQUIRE_PINNED" -eq 0 || -n "$REPO" ]] || fail '--require-pinned-ref can only be used with a GitHub repository'
[[ "$REQUIRE_AUTH_SET" -eq 0 || "$ALLOW_ANON_SET" -eq 0 ]] || fail 'use either --require-auth or --allow-anonymous-fallback, not both'
[[ "$REQUIRE_AUTH_SET" -eq 0 || -n "$REPO" ]] || fail '--require-auth can only be used with a GitHub repository'
[[ "$ALLOW_ANON_SET" -eq 0 || -n "$REPO" ]] || fail '--allow-anonymous-fallback can only be used with a GitHub repository'
[[ "$RUN_SMOKE" -eq 0 || "$SKIP_SMOKE" -eq 0 ]] || fail 'use either --run-smoke-test or --skip-smoke-test, not both'
[[ "$UPDATE_MEMORY" -eq 0 || "$SKIP_MEMORY" -eq 0 ]] || fail 'use either --update-memory or --skip-memory, not both'
[[ "$REQUIRE_PINNED" -eq 0 || -n "$REF" ]] || fail '--require-pinned-ref needs --ref'
[[ -n "$REPO" || -n "$LOCAL_PATH" || "$LINK_ONLY" -eq 1 ]] || fail 'provide a repository, --local path, or --link-only with --name'

MODE='Local'
[[ -n "$REPO" ]] && MODE='GitHub'
[[ "$LINK_ONLY" -eq 1 ]] && MODE='LinkOnly'
[[ -n "$REPO" ]] && assert_safe_repo "$REPO"
[[ -n "$REF" ]] && assert_safe_ref "$REF"
assert_safe_hash "$EXPECTED_SHA256"
if [[ -n "$SUBDIR" ]]; then
    [[ -n "$REPO" ]] || fail '--subdir is supported only with a downloaded GitHub repository'
    [[ "$SUBDIR" != /* && ! "$SUBDIR" =~ ^[A-Za-z]: && "$SUBDIR" != *'..'* && "$SUBDIR" != *'\\'* && -n "$SUBDIR" ]] || fail 'invalid subdir: use a non-empty relative path without traversal'
fi

if [[ -z "$NAME" ]]; then
    if [[ -n "$REPO" ]]; then NAME="${REPO##*/}"; else NAME="$(basename "$(canonical_path "$LOCAL_PATH")")"; fi
fi
assert_safe_name "$NAME"

AGENT="$(resolve_agent "$AGENT")"
validate_agent "$AGENT" || exit 1
BACKUP_ROOT=''
if [[ "$AGENT" == "codex" ]]; then
    [[ "$LINK_ONLY" -eq 0 ]] || fail 'Codex uses direct discovery roots and does not support --link-only'
    [[ "$SCOPE" == 'user' || "$SCOPE" == 'codex-home' ]] || fail '--scope must be user or codex-home for Codex'
    if [[ "$SCOPE" == 'codex-home' ]]; then SKILLS_DIR="$(get_codex_compatibility_skill_root)"; else SKILLS_DIR="$(get_codex_user_skill_root)"; fi
    LINK_BASE="$SKILLS_DIR"
    BUILTIN_DIR="$(get_codex_system_skill_root)"
    BACKUP_ROOT="$(get_codex_home)/skill-manager/backups"
elif [[ "$AGENT" == "antigravity" ]]; then
    SKILLS_DIR="$(get_antigravity_source_dir)"
    LINK_BASE="$(get_antigravity_link_dir)"
    BUILTIN_DIR="$(get_antigravity_builtin_dir)"
else
    SKILLS_DIR="$(get_claude_source_dir)"
    LINK_BASE="$(get_claude_link_dir)"
    BUILTIN_DIR=""
fi

SOURCE_PATH="$SKILLS_DIR/$NAME"
LINK_PATH="$LINK_BASE/$NAME"

if [[ "$AGENT" == "codex" ]]; then
    target_full="$(canonical_path "$SOURCE_PATH")"
    system_full="$(canonical_path "$BUILTIN_DIR")"
    if [[ "$target_full" == "$system_full" || "$target_full" == "$system_full/"* ]]; then
        fail "Refusing to modify protected Codex SYSTEM Skill."
    fi
elif [[ -n "$BUILTIN_DIR" && -d "$BUILTIN_DIR" ]]; then
    target_full="$(canonical_path "$SOURCE_PATH")"
    builtin_full="$(canonical_path "$BUILTIN_DIR")"
    if [[ "$target_full" == "$builtin_full"* ]]; then
        fail "Cannot install into Antigravity builtin skills directory. Use user skill directory $SKILLS_DIR"
    fi
fi
assert_child_path "$SKILLS_DIR" "$SOURCE_PATH" 'source path'
assert_child_path "$LINK_BASE" "$LINK_PATH" 'link path'
codex_protected_target "$SOURCE_PATH" && fail 'Refusing to modify protected Codex SYSTEM/Admin Skill.'

step 1 'Pre-flight and input validation'
USE_ANONYMOUS=0
if [[ "$MODE" == 'GitHub' ]]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        ok 'gh authenticated'
    else
        if [[ "$REQUIRE_AUTH" -eq 1 ]]; then
            command -v gh >/dev/null 2>&1 || fail 'gh CLI not found; install it and run gh auth login (or omit --require-auth for public repositories)'
            fail 'gh is not authenticated; run gh auth login (or omit --require-auth for public repositories)'
        fi
        if [[ "$DRY_RUN" -eq 0 ]]; then
            command -v curl >/dev/null 2>&1 || fail 'neither gh (authenticated) nor curl was found for GitHub downloads'
        fi
        USE_ANONYMOUS=1
        ok 'gh not authenticated; using anonymous public repository fallback'
    fi
else
    ok "mode = $MODE; no GitHub authentication required"
fi
ok "skill name = $NAME"

if [[ "$MODE" == 'Local' ]]; then
    [[ -d "$LOCAL_PATH" ]] || fail "local path is not a directory: $LOCAL_PATH"
    local_full="$(canonical_path "$LOCAL_PATH")"
    source_full="$(canonical_path "$SOURCE_PATH")"
    [[ "$local_full" != "$source_full" && "$source_full" != "$local_full/"* && "$local_full" != "$source_full/"* ]] || fail 'local path cannot be the install target or contain it'
    assert_no_sensitive_files "$LOCAL_PATH"
    assert_skill_layout "$LOCAL_PATH"
fi

if [[ "$MODE" == 'LinkOnly' ]]; then
    existing_path "$SOURCE_PATH" || fail "source is missing for --link-only: $SOURCE_PATH"
    assert_skill_layout "$SOURCE_PATH"
fi

source_exists=0
link_exists=0
existing_path "$SOURCE_PATH" && source_exists=1
existing_path "$LINK_PATH" && link_exists=1

if [[ "$DRY_RUN" -eq 1 ]]; then
    step 2 'Dry-run plan'
    if [[ "$source_exists" -eq 1 || "$link_exists" -eq 1 ]] && [[ "$FORCE" -eq 0 ]]; then
        warn 'existing install detected; a real replacement would require --force'
    fi
    ok "source = $SOURCE_PATH"
    ok "link = $LINK_PATH"
    ok 'DRY RUN: no files, links, network requests, smoke tests, or memory records changed'
    exit 0
fi

if [[ "$source_exists" -eq 1 || "$link_exists" -eq 1 ]] && [[ "$FORCE" -eq 0 ]]; then
    fail "install target already exists; use --force to replace it safely: $NAME"
fi

if [[ "$LINK_ONLY" -eq 0 ]]; then
    step 2 'Prepare source'
    TEMP_ROOT="$(mktemp -d)"
    trap '[[ -n "$TEMP_ROOT" && -d "$TEMP_ROOT" ]] && rm -rf -- "$TEMP_ROOT"' EXIT
    STAGE_PATH="$TEMP_ROOT/stage"

    if [[ "$MODE" == 'Local' ]]; then
        copy_contents "$LOCAL_PATH" "$STAGE_PATH"
        ok "staged local source: $LOCAL_PATH"
    else
        TARBALL="$TEMP_ROOT/source.tar.gz"
        COMMIT_REF="${REF:-HEAD}"
        if [[ "$USE_ANONYMOUS" -eq 0 ]]; then
            API="repos/$REPO/tarball"
            [[ -n "$REF" ]] && API="$API/$REF"
            gh api "$API" > "$TARBALL" || fail 'gh api download failed'
            RESOLVED_COMMIT="$(gh api "repos/$REPO/commits/$COMMIT_REF" --jq '.sha')" || fail 'could not resolve ref to a commit SHA via gh api'
        else
            TARBALL_URL="https://api.github.com/repos/$REPO/tarball"
            [[ -n "$REF" ]] && TARBALL_URL="$TARBALL_URL/$REF"
            curl -fL -s -S -H "User-Agent: skill-installer" -H "Accept: application/vnd.github+json" "$TARBALL_URL" -o "$TARBALL" || fail "anonymous download failed from $TARBALL_URL; repository may be private (requires gh auth login) or rate-limited"
            COMMIT_URL="https://api.github.com/repos/$REPO/commits/$COMMIT_REF"
            COMMIT_JSON="$(curl -fL -s -S -H "User-Agent: skill-installer" -H "Accept: application/vnd.github+json" "$COMMIT_URL")" || fail "could not fetch commit information from $COMMIT_URL; repository may be private or rate-limited"
            RESOLVED_COMMIT="$(python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('sha',''))" <<< "$COMMIT_JSON" 2>/dev/null || python -c "import sys, json; data=json.load(sys.stdin); print(data.get('sha',''))" <<< "$COMMIT_JSON" 2>/dev/null || grep -o '"sha": *"[^"]*"' <<< "$COMMIT_JSON" | head -n 1 | cut -d'"' -f4)"
        fi

        [[ "$RESOLVED_COMMIT" =~ ^[A-Fa-f0-9]{40}$ ]] || fail 'could not resolve ref to a 40-character commit SHA'
        ACTUAL_HASH="$(sha256_file "$TARBALL")"
        if [[ -n "$EXPECTED_SHA256" && "$ACTUAL_HASH" != "${EXPECTED_SHA256^^}" ]]; then
            fail "tarball SHA256 mismatch; expected $EXPECTED_SHA256, got $ACTUAL_HASH"
        fi
        EXTRACT_DIR="$TEMP_ROOT/extract"
        mkdir -p "$EXTRACT_DIR"
        tar -xzf "$TARBALL" -C "$EXTRACT_DIR" || fail 'tar extraction failed'
        INNER="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | head -n 1 || true)"
        [[ -n "$INNER" ]] || fail 'unexpected GitHub tarball layout'
        SELECTED_SOURCE="$INNER"
        if [[ -n "$SUBDIR" ]]; then
            SELECTED_SOURCE="$INNER/$SUBDIR"
            inner_full="$(canonical_path "$INNER")"
            selected_full="$(canonical_path "$SELECTED_SOURCE")"
            [[ "$selected_full" == "$inner_full/"* ]] || fail 'selected subdir escapes the downloaded staging tree'
            [[ -d "$SELECTED_SOURCE" ]] || fail "selected subdir was not found in the downloaded repository: $SUBDIR"
        fi
        copy_contents "$SELECTED_SOURCE" "$STAGE_PATH"
        ok "downloaded $REPO at commit $RESOLVED_COMMIT $([[ "$USE_ANONYMOUS" -eq 1 ]] && echo '(anonymous fallback)' || echo '(gh authenticated)')"
        ok "tarball SHA256 = $ACTUAL_HASH"
    fi

    assert_no_sensitive_files "$STAGE_PATH"
    assert_skill_layout "$STAGE_PATH"
    if [[ -n "$SUBDIR" ]]; then
        declared_name="$(grep -E '^name:' "$STAGE_PATH/SKILL.md" | head -n 1 | cut -d: -f2- | xargs)"
        subdir_basename="${SUBDIR##*/}"
        if [[ "$declared_name" != "$subdir_basename" && "$NAME_WAS_EXPLICIT" -eq 0 ]]; then fail "selected subdir basename '$subdir_basename' does not match SKILL.md name '$declared_name'; pass --name explicitly to acknowledge the mismatch"; fi
        [[ "$declared_name" == "$subdir_basename" ]] || warn "selected subdir basename '$subdir_basename' differs from SKILL.md name '$declared_name'; using explicit name '$NAME'"
    fi
    if [[ "$source_exists" -eq 1 ]]; then
        [[ -n "$BACKUP_ROOT" ]] || BACKUP_ROOT="$SKILLS_DIR/.backups"
        BACKUP="$(backup_existing "$SOURCE_PATH" source "$BACKUP_ROOT" "$NAME")"
        ok "previous source backed up to $BACKUP"
    fi
    mkdir -p "$SKILLS_DIR"
    mv "$STAGE_PATH" "$SOURCE_PATH"
    ok "source installed at $SOURCE_PATH"
else
    step 2 'Use existing source'
fi

step 3 'Create link'
if [[ "$SOURCE_PATH" == "$LINK_PATH" ]]; then
    INSTALL_MODE='in-place'
    ok "installed in-place at $SOURCE_PATH"
else
    mkdir -p "$LINK_BASE"
    if [[ "$link_exists" -eq 1 ]]; then remove_install_entry "$LINK_PATH"; fi
    INSTALL_MODE="$(create_install_link "$SOURCE_PATH" "$LINK_PATH")"
    ok "$INSTALL_MODE: $SOURCE_PATH -> $LINK_PATH"
fi

step 4 'Verify skill contract'
assert_skill_layout "$SOURCE_PATH"
existing_path "$LINK_PATH" || fail "link missing after installation: $LINK_PATH"
SOURCE_HASH="$(sha256_file "$SOURCE_PATH/SKILL.md")"
LINK_HASH="$(sha256_file "$LINK_PATH/SKILL.md")"
[[ "$SOURCE_HASH" == "$LINK_HASH" ]] || fail 'source and link SKILL.md hashes differ'
ok "source and link verified; SKILL.md SHA256 = $SOURCE_HASH"

step 5 'Smoke test'
if [[ "$RUN_SMOKE" -eq 1 && "$SKIP_SMOKE" -eq 0 && -z "${SKIP_SMOKE_TEST:-}" ]]; then
    warn 'Smoke test executes downloaded code. Only use it for a reviewed, trusted source.'
    SMOKE='no executable found (manual test needed)'
    for candidate in "$NAME.sh" "$NAME"; do
        path="$SOURCE_PATH/$candidate"
        if [[ -f "$path" ]]; then
            if output="$("$path" --version 2>/dev/null)"; then SMOKE="pass: $output"; break; fi
            if output="$("$path" --help 2>/dev/null)"; then SMOKE='pass (--help)'; break; fi
        fi
    done
else
    SMOKE='not run (opt-in with --run-smoke-test)'
fi
ok "$SMOKE"

step 6 'Memory update'
if [[ "$UPDATE_MEMORY" -eq 1 && "$SKIP_MEMORY" -eq 0 && -z "${SKIP_MEMORY_UPDATE:-}" ]]; then
    MEMORY_FILE="$SKILLS_DIR/installed-tools-summary.md"
    MEMORY="$(update_memory "$MEMORY_FILE" "$NAME" "$REPO" "$SOURCE_PATH" "$LINK_PATH" "$SMOKE")"
else
    MEMORY='not run (opt-in with --update-memory)'
fi
ok "$MEMORY"

step 7 'Catalog index and final result'
if [[ "$SKIP_CATALOG" -eq 1 || -n "${SKIP_CATALOG_UPDATE:-}" ]]; then
    CATALOG='not run (opt-out)'
else
    CATALOG_ARGS=(--refresh --register-name "$NAME" --register-source "local" --register-installed-at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")
    if [[ -n "$REPO" ]]; then CATALOG_ARGS+=(--register-source "github:$REPO"); fi
    if [[ -n "${RESOLVED_COMMIT:-}" ]]; then CATALOG_ARGS+=(--register-commit "$RESOLVED_COMMIT"); fi
    if [[ -n "${ACTUAL_HASH:-}" ]]; then CATALOG_ARGS+=(--register-sha256 "$ACTUAL_HASH"); fi
    if bash "$SCRIPT_DIR/catalog.sh" "${CATALOG_ARGS[@]}" >/dev/null; then
        CATALOG='refreshed'
    else
        CATALOG='refresh failed'
        warn 'catalog refresh failed; installation itself is complete'
    fi
fi
ok "$CATALOG"
printf '\n| Field | Value |\n|-------|-------|\n'
printf '| Mode | %s |\n' "$MODE"
printf '| Source | %s |\n' "$SOURCE_PATH"
printf '| Link | %s |\n' "$LINK_PATH"
printf '| Install mode | %s |\n' "$INSTALL_MODE"
printf '| Resolved commit | %s |\n' "${RESOLVED_COMMIT:-not applicable}"
printf '| Smoke test | %s |\n' "$SMOKE"
printf '| Memory update | %s |\n' "$MEMORY"
printf '| Catalog index | %s |\n' "$CATALOG"
printf '| Timestamp | %s |\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
printf 'Restart Claude Code so the new skill appears in the system prompt.\n'
