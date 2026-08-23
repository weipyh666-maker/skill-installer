# Codex Native Adapter Implementation Plan

> **For agentic workers:** Execute inline in this task with one verification checkpoint after each task. Steps use checkbox syntax for tracking.

**Goal:** Replace the Codex stub with a safe multi-discovery-root adapter that scans, indexes, finds, diagnoses, and installs Codex Skills without deciding duplicate precedence.

**Architecture:** The Codex adapter supplies structured discovery-root and environment-status data; the existing PowerShell and Bash catalog implementations consume the same conceptual root records. Schema v3 remains intact and gains only Codex agent fields needed to retain multiple paths. The existing Find scorer, staged installer, SHA256 verification, and backup logic remain shared.

**Tech stack:** PowerShell 5.1+, Bash, embedded Python in `lib/catalog.sh`, GitHub Actions, temporary filesystem/Git fixtures.

---

## Non-negotiable acceptance rules

- `CODEX_HOME/skills` is an explicit **install target** named `codex-home`; it is not user or project scope.
- User and project discovery use only `.agents/skills`; project `.codex/skills` is never scanned.
- Duplicate names retain every discovered path and state `precedence = unknown`; no winner is selected.
- `$CODEX_HOME/skills/.system` is hard-protected after canonical path resolution: no install, force overwrite, fix, replacement, or backup relocation.
- Plugin cache entries are represented as `conditional` visibility, never visible merely because cached.
- `--subdir` resolves only inside an already-downloaded staging tree and rejects traversal, absolute/outside paths, and reparse/symlink escapes.
- Find scoring/ranking functions are unchanged.
- No test may write to real `%USERPROFILE%\.agents\skills`, `%USERPROFILE%\.codex\skills`, or system Skills.

## Target files

- Create: `adapters/codex/detect.ps1`
- Create: `adapters/codex/detect.sh`
- Replace: `adapters/codex/paths.ps1`
- Replace: `adapters/codex/paths.sh`
- Modify: `lib/catalog.ps1`
- Modify: `lib/catalog.sh`
- Modify: `lib/install.ps1`
- Modify: `lib/install.sh`
- Create: `tests/test-codex.ps1`
- Create: `tests/test-codex.sh`
- Modify: `tests/test-install.ps1`, `tests/test-install.sh`
- Modify: `.github/workflows/ci.yml`
- Replace after passing tests: `adapters/codex/stub-note.md` → `adapters/codex/README.md`
- Modify after passing tests: `README.md`, `SKILL.md`, `CHANGELOG.md`

## Task 1: Establish the non-regression baseline

**Files:** none.

- [ ] Run the current PowerShell regression suite before changes.

  Run:

  ```powershell
  pwsh -NoProfile -File tests/test-install.ps1
  pwsh -NoProfile -File tests/test-catalog.ps1
  pwsh -NoProfile -File tests/test-find-benchmark.ps1
  pwsh -NoProfile -File tests/test-auto-trigger.ps1
  pwsh -NoProfile -File tests/test-graduation.ps1
  pwsh -NoProfile -File tests/test-antigravity.ps1
  ```

  Expected: all commands exit `0`; Find meets 85% Top-1 / 95% Top-3; Claude is 11/11.

- [ ] Run the Bash equivalents.

  ```bash
  bash tests/test-install.sh
  bash tests/test-catalog.sh
  bash tests/test-find-benchmark.sh
  bash tests/test-auto-trigger.sh
  bash tests/test-graduation.sh
  bash tests/test-antigravity.sh
  ```

  Expected: all exit `0`.

## Task 2: Define Codex roots and environment detection

**Files:**

- Replace: `adapters/codex/paths.ps1`, `adapters/codex/paths.sh`
- Create: `adapters/codex/detect.ps1`, `adapters/codex/detect.sh`
- Test: `tests/test-codex.ps1`, `tests/test-codex.sh`

- [ ] Write failing adapter tests that create only temporary roots and assert the root-record shape:

  ```text
  user          = $HOME/.agents/skills
  compatibility = $CODEX_HOME/skills
  system        = $CODEX_HOME/skills/.system (protected)
  project       = every .agents/skills from CWD through Git root
  admin         = /etc/codex/skills on POSIX only (protected)
  ```

  Tests must set `SKILL_MANAGER_CODEX_HOME`, `SKILL_MANAGER_CODEX_USER_HOME`, and `SKILL_MANAGER_CODEX_CWD` only as skill-manager test overrides. They must not call them Codex variables.

- [ ] Implement PowerShell root functions:

  ```powershell
  Get-CodexHome
  Get-CodexUserSkillRoot
  Get-CodexCompatibilitySkillRoot
  Get-CodexSystemSkillRoot
  Get-CodexProjectSkillRoots([string] $WorkingDirectory)
  Get-CodexAdminSkillRoot
  Get-CodexDiscoveryRoots([string] $WorkingDirectory)
  ```

  Each discovery result is a `[pscustomobject]` with `path`, `scope`, `class`, `writable`, `protected`, and `source`. Canonicalize paths before deduplicating. Project-root traversal stops at the Git top-level when available and otherwise checks only CWD.

- [ ] Implement Bash equivalents that emit a stable tab-separated/JSON-safe root representation consumed by `catalog.sh`; use the same root names and no project `.codex` path.

- [ ] Implement detection without invoking `codex --version`:

  ```text
  cli_resolved, cli_path, codex_home, user_root_exists,
  compatibility_root_exists, system_root_exists, usable,
  executable_test = not-run
  ```

  `usable` is true if a command resolves or any Codex root exists. A non-runnable resolved WindowsApps executable must remain detected and be reported as executable-unavailable, not missing.

- [ ] Run `tests/test-codex.ps1` and `.sh` until root and detection assertions pass.

## Task 3: Add Codex multi-root catalog ingestion without altering Find

**Files:**

- Modify: `lib/catalog.ps1`
- Modify: `lib/catalog.sh`
- Test: `tests/test-codex.ps1`, `tests/test-codex.sh`

- [ ] Add a failing test fixture repository with:

  ```text
  repo/.agents/skills/root-skill/SKILL.md
  repo/apps/.agents/skills/app-skill/SKILL.md
  repo/apps/web/                         # synthetic CWD
  user/.agents/skills/duplicate/SKILL.md
  codex-home/skills/duplicate/SKILL.md
  codex-home/skills/.system/openai-docs/SKILL.md
  plugin-cache/example/skills/plugin-skill/SKILL.md
  ```

  Assert that ancestor project paths are retained, duplicate has two path records, system is protected, and plugin cache is `conditional` rather than visible.

- [ ] In each catalog implementation, load the Codex adapter alongside Claude and Antigravity. Build Codex inventory from root records, not source/link pairs. Do not change `score_skill_entry` / Find term extraction/ranking.

- [ ] Extend only `agents.codex` in Schema v3:

  ```json
  {
    "visible": true,
    "reason": "discovered-in-user-root",
    "paths": [{"path":"...","scope":"user","class":"agents","protected":false}],
    "scopes": ["user"],
    "precedence": "unknown"
  }
  ```

  For a duplicate, append paths in deterministic canonical-path order and retain `precedence: "unknown"`. The top-level Skill identity must not discard locations.

- [ ] Represent plugin cache Skills with `visible: false`, `reason: "plugin-enablement-dependent"`, and a path record class `plugin-cache` unless an explicit enabled-plugin signal exists.

- [ ] Run Codex catalog tests: refresh, list, show JSON/text, capabilities, and unchanged Find query behavior.

## Task 4: Parse the limited Codex `skills.config` enablement contract

**Files:**

- Modify: `adapters/codex/paths.ps1`, `adapters/codex/paths.sh` or a focused helper co-located with them
- Modify: `lib/catalog.ps1`, `lib/catalog.sh`
- Test: `tests/test-codex.ps1`, `tests/test-codex.sh`

- [ ] Add a failing fixture `config.toml` containing only:

  ```toml
  [[skills.config]]
  path = "<absolute fixture path>/SKILL.md"
  enabled = false
  ```

  Assert `discoverable_on_disk=true`, `enabled=false`, `visible=false`, and `reason=disabled-by-codex-config`.

- [ ] Implement a narrow parser for `[[skills.config]]`, `path`, and `enabled`. Do not read auth, history, logs, arbitrary config sections, or secrets. Canonicalize configured Skill paths before matching discovered records.

- [ ] Test `enabled=true`, absent entry, invalid/outside entry ignored with an explicit diagnostic, and two matching root records.

## Task 5: Make Doctor Codex-aware and hard-protect system Skills

**Files:**

- Modify: `lib/catalog.ps1`, `lib/catalog.sh`
- Modify only if necessary: `core/doctor.ps1`, `core/doctor.sh`
- Test: `tests/test-codex.ps1`, `tests/test-codex.sh`

- [ ] Add failing Doctor assertions for CLI resolved/unavailable, home, all root classes, duplicate count/list, disabled entries, conditional plugin entries, and protected system Skills.

- [ ] Implement a Codex doctor section that reports discovery semantics with language such as `discoverable`, `eligible`, and `model-selected`; do not promise automatic invocation.

- [ ] Implement canonical protection predicate:

  ```text
  IsPathWithinCanonicalRoot(candidate, protectedRoot)
  ```

  It must resolve existing links/reparse points before containment checking and reject a target equal to or below system/admin protected roots. String `contains` matching is forbidden.

- [ ] Ensure `fix --agent codex`, including dry-run and force paths, refuses protected System Skills with `Refusing to modify protected Codex SYSTEM Skill.` The normal `fix` scope should initially only operate on explicitly writable Codex user-target records; project/admin/system/plugin entries are diagnostic-only.

- [ ] Re-run Codex Doctor tests and existing Claude/Antigravity doctor tests.

## Task 6: Support safe Codex installs and staging-only `--subdir`

**Files:**

- Modify: `lib/install.ps1`, `lib/install.sh`
- Test: `tests/test-install.ps1`, `tests/test-install.sh`, `tests/test-codex.ps1`, `tests/test-codex.sh`

- [ ] Write failing Codex install tests using temporary HOME/USERPROFILE/CODEX_HOME:

  ```text
  --agent codex                    -> user .agents/skills
  --agent codex --scope codex-home -> CODEX_HOME/skills
  --dry-run                         -> no writes
  --force                           -> backup under selected writable target
  system target                     -> rejected, including --force
  ```

- [ ] Add `-Scope` / `--scope` with values `user` and `codex-home`; validate it is accepted only for Codex. The default is `user`. Codex has no link target and must use copy/stage installation directly into the selected root.

- [ ] Add `-Subdir` / `--subdir` only for repository downloads after the existing archive is downloaded and extracted. Do not change repository authentication, ref resolution, tarball retrieval, SHA256, or extraction protocol.

- [ ] Implement staging-only subdirectory validation:

  ```text
  reject empty, rooted, drive-qualified, or .. traversal input;
  canonicalize staging root and candidate;
  require candidate to remain beneath staging root;
  reject a candidate or descendants containing symlink/reparse escapes;
  require candidate/SKILL.md to be a regular readable file.
  ```

  The installed name defaults to the final subdirectory basename unless the existing explicit `Name` option is supplied.

- [ ] Preserve existing sensitive-file, archive traversal, SHA256, pinned-ref, staging, backup, and atomic verification behavior. Add `--subdir` unit coverage using a locally constructed staging fixture/helper rather than network access.

- [ ] Update existing installer regressions that currently assert Codex stub failure: they must instead assert Codex dry-run succeeds in an isolated environment.

## Task 7: Add CI coverage and run the complete regression matrix

**Files:**

- Modify: `.github/workflows/ci.yml`
- Test: all `tests/test-*.ps1` and `tests/test-*.sh`

- [ ] Add `test-codex.ps1` to the Windows PowerShell job and `test-codex.sh` to the Unix Bash job. Fixtures must provide fake `codex` executables where command resolution is tested; CI never installs real Codex.

- [ ] Run the full local matrix:

  ```text
  test-install, test-catalog, test-find-benchmark, test-auto-trigger,
  test-graduation, test-antigravity, test-codex
  ```

  on both PowerShell and Bash.

- [ ] Record results. Required gates: Find Top-1 >= 85%, Top-3 >= 95%, auto-trigger positive/negative remain 100%, Claude Graduation 11/11, Antigravity PASS, Codex PASS.

## Task 8: Run real Codex read-only smoke verification

**Files:** none.

- [ ] Do not invoke install, fix, force, remove, or overwrite against the real profile. Run only:

  ```text
  detect, refresh/scan only if its index target is a temporary override,
  list, capabilities, find, show, doctor
  ```

- [ ] Prefer a temporary catalog-index override for real-profile read operations; if the existing application cannot separate index writes from scan, do not run refresh against the real profile and report the limitation.

- [ ] Collect read-only counts for `.agents`, codex-home non-system, system, conditional plugins, duplicate names, and Codex-visible Skills. Exercise `frontend-design`, `officecli`, `openai-docs`, `skill-creator`, and `skill-installer` with show/doctor only.

- [ ] Run five Find queries: `做网页 UI`, `处理 PDF`, `制作 PPT`, `图片识别`, `代码审查`; capture top three name/score/path/scope/duplicate/system fields.

## Task 9: Remove stub and document only verified behavior

**Files:**

- Replace: `adapters/codex/stub-note.md` with `adapters/codex/README.md`
- Modify: `README.md`, `SKILL.md`, `CHANGELOG.md`

- [ ] Only after Tasks 1–8 pass, remove every `not-yet-implemented` Codex branch and the stub note.
- [ ] Document exact roots, explicit `--scope codex-home`, system protection, conditional plugin visibility, duplicate precedence unknown, and the known unresolved runtime questions.
- [ ] Mark Codex as Supported only if all graduation gates pass; otherwise mark Partial with exact blockers.

## Plan self-review

- Scope covers all requested Phase B roots, detection, config, duplicates, system protection, install, `--subdir`, tests, CI, smoke, and documentation.
- Find is explicitly kept unchanged.
- No step silently chooses precedence or writes to real user/system roots.
- No placeholders remain; Phase B.2 is unnecessary because staging-only `--subdir` has a bounded implementation and test surface.
