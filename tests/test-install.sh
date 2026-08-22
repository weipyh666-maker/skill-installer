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
grep -q 'keep me' "$CLAUDE_SKILLS_DIR/minimal-skill/sentinel.txt"

echo 'PASS: installer regression tests'
