#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$ROOT/lib/install.sh"
FIXTURE="$ROOT/tests/fixtures/minimal-skill"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export CLAUDE_SKILLS_DIR="$SANDBOX/sources"
export CLAUDE_SKILLS_LINK_DIR="$SANDBOX/links"
export SKIP_SMOKE_TEST=1
export SKIP_MEMORY_UPDATE=1

assert_contains() {
    local haystack="$1"
    local needle="$2"
    [[ "$haystack" == *"$needle"* ]] || {
        echo "ASSERTION FAILED: expected output to contain: $needle" >&2
        exit 1
    }
}

set +e
dry_output="$(bash "$INSTALLER" --local "$FIXTURE" --name minimal-skill --dry-run 2>&1)"
dry_status=$?
set -e
[[ "$dry_status" -eq 0 ]] || {
    echo "ASSERTION FAILED: local dry-run should succeed: $dry_output" >&2
    exit 1
}
assert_contains "$dry_output" "DRY RUN"
[[ ! -e "$CLAUDE_SKILLS_DIR/minimal-skill" ]] || {
    echo "ASSERTION FAILED: dry-run created source files" >&2
    exit 1
}
[[ ! -e "$CLAUDE_SKILLS_LINK_DIR/minimal-skill" ]] || {
    echo "ASSERTION FAILED: dry-run created a link" >&2
    exit 1
}

set +e
invalid_output="$(bash "$INSTALLER" --local "$FIXTURE" --name ../escape --dry-run 2>&1)"
invalid_status=$?
set -e
[[ "$invalid_status" -ne 0 ]] || {
    echo "ASSERTION FAILED: traversal name was accepted" >&2
    exit 1
}
assert_contains "$invalid_output" "invalid"

mkdir -p "$CLAUDE_SKILLS_DIR/minimal-skill"
printf 'keep me\n' > "$CLAUDE_SKILLS_DIR/minimal-skill/sentinel.txt"
set +e
existing_output="$(bash "$INSTALLER" --local "$FIXTURE" --name minimal-skill 2>&1)"
existing_status=$?
set -e
[[ "$existing_status" -ne 0 ]] || {
    echo "ASSERTION FAILED: existing install did not require --force" >&2
    exit 1
}
grep -q 'keep me' "$CLAUDE_SKILLS_DIR/minimal-skill/sentinel.txt" || {
    echo "ASSERTION FAILED: sentinel.txt was deleted or modified" >&2
    exit 1
}

set +e
secret_skill="$SANDBOX/secret-skill"
cp -a "$FIXTURE" "$secret_skill"
printf 'DO_NOT_COPY=1\n' > "$secret_skill/.env"
secret_output="$(bash "$INSTALLER" --local "$secret_skill" --name secret-skill --dry-run 2>&1)"
secret_status=$?
set -e
[[ "$secret_status" -ne 0 ]] || {
    echo "ASSERTION FAILED: sensitive local files were accepted: $secret_output" >&2
    exit 1
}
assert_contains "$secret_output" "refusing"

set +e
symlink_skill="$SANDBOX/symlink-skill"
mkdir -p "$symlink_skill"
cp -a "$FIXTURE/." "$symlink_skill/"
ln -s "$FIXTURE/SKILL.md" "$symlink_skill/leaked.md" 2>/dev/null
set -e
if [[ -L "$symlink_skill/leaked.md" ]]; then
    set +e
    symlink_output="$(bash "$INSTALLER" --local "$symlink_skill" --name symlink-skill --dry-run 2>&1)"
    symlink_status=$?
    set -e
    [[ "$symlink_status" -ne 0 ]] || {
        echo "ASSERTION FAILED: internal symlink was accepted: $symlink_output" >&2
        exit 1
    }
    assert_contains "$symlink_output" "symbolic link"
else
    echo "note: this environment cannot create real symlinks; skipping symlink regression" >&2
fi

if ! fresh_out="$(bash "$INSTALLER" --local "$FIXTURE" --name fresh-skill 2>&1)"; then
    echo "ASSERTION FAILED: fresh-skill install failed: $fresh_out" >&2
    exit 1
fi
[[ -f "$CLAUDE_SKILLS_DIR/fresh-skill/SKILL.md" ]] || {
    echo "ASSERTION FAILED: fresh source SKILL.md missing" >&2
    exit 1
}
[[ -f "$CLAUDE_SKILLS_LINK_DIR/fresh-skill/SKILL.md" ]] || {
    echo "ASSERTION FAILED: fresh link SKILL.md missing" >&2
    exit 1
}
[[ -f "$CLAUDE_SKILLS_DIR/installed-skills-index.json" ]] || {
    echo "ASSERTION FAILED: catalog index not created" >&2
    exit 1
}
grep -q '"fresh-skill"' "$CLAUDE_SKILLS_DIR/installed-skills-index.json" || {
    echo "ASSERTION FAILED: catalog missing fresh-skill entry" >&2
    exit 1
}

forced_output="$(bash "$INSTALLER" --local "$FIXTURE" --name fresh-skill --force 2>&1)"
assert_contains "$forced_output" "backed up"
[[ -d "$CLAUDE_SKILLS_DIR/.backups" ]] || {
    echo "ASSERTION FAILED: backup directory not created" >&2
    exit 1
}
ls "$CLAUDE_SKILLS_DIR/.backups"/fresh-skill-* >/dev/null 2>&1 || {
    echo "ASSERTION FAILED: no backup entry for fresh-skill" >&2
    exit 1
}

unset SKIP_MEMORY_UPDATE
printf '| Skill | Repo | Source | Link | Smoke | Date |\n' > "$CLAUDE_SKILLS_DIR/installed-tools-summary.md"
if ! mem_out="$(bash "$INSTALLER" --local "$FIXTURE" --name memory-skill --update-memory 2>&1)"; then
    echo "ASSERTION FAILED: memory-skill install failed: $mem_out" >&2
    exit 1
fi
if ! mem_out2="$(bash "$INSTALLER" --local "$FIXTURE" --name memory-skill --force --update-memory 2>&1)"; then
    echo "ASSERTION FAILED: memory-skill force install failed: $mem_out2" >&2
    exit 1
fi
memory_rows="$(grep -c '| memory-skill |' "$CLAUDE_SKILLS_DIR/installed-tools-summary.md" || true)"
[[ "$memory_rows" -eq 1 ]] || {
    echo "ASSERTION FAILED: memory update not idempotent (rows=$memory_rows)" >&2
    exit 1
}

echo 'PASS: installer regression tests'
