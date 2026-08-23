## [3.2.0] - 2026-08-23

### Added
- **Antigravity Native Adapter**: First-class support for Antigravity CLI and Agent environment (`adapters/antigravity/paths.{ps1,sh}`, `adapters/antigravity/detect.{ps1,sh}`).
- **Multi-Agent Discovery & Visibility**: Catalog Schema v3 accurately tracks `agents.antigravity.visible`, `agents.antigravity.path`, and discovery reasons alongside Claude Code.
- **Antigravity Global & In-place Install**: Safe installation directly into Antigravity global skill directory (`~/.agents/skills/`) with built-in protection for system builtin skills (`~/.gemini/antigravity-cli/builtin/skills/`).
- **Comprehensive Antigravity Test Suite**: Dedicated automated test suites (`tests/test-antigravity.ps1` and `tests/test-antigravity.sh`) testing detection, path resolution, multi-agent scan, capabilities, find, doctor, and safe install/force-backup.
- **CI Integration**: Added `antigravity-adapter` (Ubuntu) and `antigravity-adapter-ps` (Windows) jobs to GitHub Actions workflow matrix (10/10 jobs).

### Changed
- Standardized environment variable resolution across agents (`SKILL_MANAGER_*` priority over `CLAUDE_SKILLS_*`).
- Generic capability substring matching in search engine hardened against generic tokens (`skill`, `other`, `tools`).

# Changelog

## [3.1.2] — 2026-08-23

### Claude 1.0 毕业冻结

skill-manager v3.1.2 锁定 Claude 1.0 全部核心能力：

- scan / catalog / capabilities / refresh / find / doctor / fix 全部通过 11 项毕业测试
- Find Benchmark：Top-1 96% / Top-3 100%（50 题）
- Auto-trigger：positive 100% / negative 100%（22 题）
- Trigger quality：8 条规则 + 全库评分
- 安全：symlink 拒绝、敏感文件拒绝、token 校验

Claude 1.0 范围外（下阶段）：
- Antigravity / Codex 真实适配器
- 跨 agent 共享 catalog
- Docker 集成测试沙箱
- semantic search / embeddings

## [3.1.1] — 2026-08-23

### Added
- **Doctor Trigger Quality 8-Rule Engine**:
  - Expanded trigger diagnostic rules from 4 to 8:
    1. Explicit trigger prefix (`Use when...`, `when`, `whenever`)
    2. Action verb presence (general domain actions)
    3. Action verb diversity ($\ge 3$ distinct prototype verbs from dictionary)
    4. Concrete trigger examples (`e.g.`, `for example`, `such as`, `例如`, `比如`)
    5. Appropriate length (30–200 characters)
    6. Well-formed first sentence (no list/bullet marker prefix)
    7. Explicit `capabilities` frontmatter tags
    8. Explicit `category` frontmatter classification
- **Trigger Quality Scoring (`trigger_quality_score`)**:
  - Single skill mode: outputs itemized checks, score percentage (e.g. `1 ⚠ / 8 ✓ (score: 87.5%)`), and actionable recommendations.
  - Global scan mode: computes library-wide average score across healthy skills and reports Top 3 skills with lowest scores.
- **Auto-Trigger Heuristic Evaluation Suite**:
  - `tests/fixtures/auto-trigger/queries-pos.json` (12 positive intent queries)
  - `tests/fixtures/auto-trigger/queries-neg.json` (10 negative out-of-domain queries)
  - `tests/test-auto-trigger.sh` & `tests/test-auto-trigger.ps1` evaluation harnesses (100% positive, 100% negative pass rates).
- **Dedicated CI Jobs**:
  - Added `auto-trigger` (Ubuntu Bash) and `auto-trigger-ps` (Windows PowerShell) jobs to `.github/workflows/ci.yml`.

## [3.1.0] — 2026-08-23

### Added
- Standardized 50-query bilingual Find Benchmark suite (`tests/fixtures/find-benchmark/queries.json`) covering 6 test categories: Chinese natural-language memory recall, English natural-language intent, keyword queries, compound queries, negative queries (unmatched domain rejection), and synonym expansion.
- Automated benchmark test harnesses in Bash (`tests/test-find-benchmark.sh`) and PowerShell (`tests/test-find-benchmark.ps1`) enforcing strict accuracy targets (Top-1 >= 85%, Top-3 >= 95%).
- High-precision search scoring engine (`core/search.sh`, `core/search.ps1`, `lib/catalog.sh`, `lib/catalog.ps1`) featuring:
  - Multilingual stop-word filtering (stripping generic query noise like "find a skill that", "我装了一个...但是忘了名字").
  - Bidirectional synonym expansion dictionary mapping cross-domain concepts (e.g. PPT/slides, Excel/table, Audio/transcription, Git guardrails, PRD/issues).
  - Multi-tier scoring hierarchy: exact name / name substring (35-60 pts), explicit capability tags (25 pts), category tags (10 pts), and description keywords (5 pts).
  - Intent domain guards and negative query filters eliminating cross-domain false positives (e.g. distinguishing PRD from document converters).
- Added `match_reason` line to `find` output (e.g. `matched: name="..." hit on ...; capabilities=[...]; description hit on ...`) providing transparent search explainability across human and JSON modes.
- Added CI workflow integration in `.github/workflows/ci.yml` running the 50-query benchmark suite across Ubuntu, macOS, and Windows runners.
- Benchmark achievement: **Top-1 accuracy 96.0% (48/50)** and **Top-3 accuracy 100.0% (50/50)** on real-world 153 installed skills inventory.

## [3.0.0] — 2026-08-23

### Added
- Modular multi-agent architecture with dedicated `adapters/` (`_base`, `claude`, `codex`, `antigravity`) and `core/` subsystems (`scanner`, `search`, `doctor`).
- Added `--agent` CLI option (`--agent` / `-Agent`) and `CLAUDE_SKILLS_AGENT` environment variable to target specific AI agent harnesses (`claude`, `codex`, `antigravity`) with `claude` as default.
- Added initial placeholder adapters for OpenAI Codex CLI and Antigravity CLI before their native implementations.
- Upgraded catalog to `schema_version: 3` featuring top-level `default_agent: "claude"` and per-agent visibility objects (`visible`, `path`, `reason`).
- Automatic backward-compatible migration from Schema v1/v2 to Schema v3.
- Added agent-aware filtering across `capabilities`, `list`, `find`, and `doctor`, plus `--all-agents` / `-AllAgents` flag for full catalog inspection.
- Added 13th trigger condition to `SKILL.md` frontmatter for multi-agent skill catalog management.
- Added regression tests in `tests/test-install.*` and `tests/test-catalog.*` verifying `--agent claude` backward compatibility, agent environment overrides, Schema v3 migration, and agent visibility filtering.

## [2.2.0] — 2026-08-23

### Added
- Added `fix` command (`--fix` / `-Command fix`) to automatically repair `SKILL.md` frontmatter triggers for individual skills (`--name`) or entire inventories in bulk.
- Implemented 5-case description rewrite engine converting legacy, 3rd-person, and imperative descriptions into standard `"Use when the user wants to <base-verb>..."` trigger syntax.
- Added automatic `capabilities` derivation (top 5 deduplicated tags extracted from name, description, and aliases) and `category` derivation (bucketing into documents, development, media, data, browser, research, or other).
- Added safe symlink and junction reparse point detection that refuses in-place modifications and prints suggested patches to stdout.
- Added automatic timestamped backups to `$CLAUDE_SKILLS_DIR/.backups/<skill>-<timestamp>-SKILL.md` before any file modifications.
- Added post-fix doctor verification displaying immediate trigger quality improvement (e.g. `trigger quality: 0 ⚠ (was 3 ⚠)`).
- Added comprehensive regression tests in `tests/test-catalog.ps1` and `tests/test-catalog.sh` verifying `--dry-run`, interactive / `-Yes` confirmations, description rewrite cases A/B/C/D/E, backup retention, and doctor improvement assertions.

## [2.1.0] — 2026-08-23

### Added
- Upgraded `find` command (`--find` / `-Command find`) with score-ranked scoring, `--limit` / `-Limit` top-result selection, and strict compound AND filtering across bilingual Chinese/English queries.
- Added dual-mode `doctor` command:
  - Global mode (`--doctor` / `-Command doctor`) reporting inventory-level `scanned`, `healthy`, `broken`, and `missing` counts.
  - Single-skill deep inspection mode (`--doctor --name <skill>` / `-Command doctor -Name <skill>`) verifying `Installation`, `Structure`, `Discovery`, and `Trigger quality` with actionable suggestions.
- Added 4-rule trigger quality diagnostics assessing description length, action verbs, explicit trigger phrases (`Use when...`), and explicit frontmatter `capabilities` / `category` tags.
- Added 12th trigger condition to `SKILL.md` frontmatter for natural-language skill lookup and intent matching.
- Added regression tests in `tests/test-catalog.ps1` and `tests/test-catalog.sh` for Chinese/English ranked queries, compound filtering, empty results, single-skill doctor blocks, short-description trigger warnings, and global doctor counts.

## [2.0.0] — 2026-08-23

### Changed
- Renamed project from `skill-installer` to `skill-manager` with full repository and remote synchronization.
- Upgraded catalog schema to `schema_version: 2` with automatic legacy v1 migration without data loss.
- Rewrote `SKILL.md` frontmatter description to support 11 distinct agent invocation and diagnosis triggers.
- Removed deprecated `HANDOFF.md`.

### Added
- Added `capabilities` command (`--capabilities` / `-Command capabilities`) grouping skills by category (`Documents`, `Development`, `Browser`, `Research`, `Data`, `Media`, `Other`) with broken skill counting.
- Added deep directory scanning (`scan_entries` / `Get-SkillDirectories`) that discovers manually placed skills in `~/.claude/skills` and `~/Claude-Code` with `discovered_at` timestamps.
- Added health status tracking (`ok`, `broken`, `missing`) preserving uninstalled skills as `missing` across refresh cycles.
- Added explicit Claude Code visibility tracking (`agents.claude.visible`, `agents.claude.link_path`).
- Added placeholder directories `core/` and `adapters/` for V3 multi-agent architecture.
- Added comprehensive regression tests in `tests/test-catalog.ps1` and `tests/test-catalog.sh` for schema v2, capabilities output, manual scan discovery, and missing entry retention.

## [0.5.0] — 2026-08-23

### Added
- Added anonymous download fallback for public GitHub repositories via `curl` (Bash) and `Invoke-WebRequest` / `Invoke-RestMethod` (PowerShell). Users without `gh` or without active `gh auth login` sessions can now install public skills seamlessly.
- Maintained immutable provenance by querying the public commits API to resolve the exact 40-character commit SHA during anonymous installs.
- Added `--require-auth` / `-RequireAuth` switch to strictly require `gh` authentication and reject anonymous fallback.
- Added `--allow-anonymous-fallback` / `-AllowAnonymousFallback` switch (default behavior).
- Added regression test suites mocking unauthenticated `gh` environments and verifying option exclusivity on both Bash and PowerShell.

## [0.4.0] — 2026-08-23

### Security
- Reject any symbolic link or reparse point inside a downloaded or local source. Closed a defense-in-depth gap where a malicious skill could include nested symlinks pointing outside the staged root.
- The Bash installer uses `find -type l`; the PowerShell installer rejects items carrying `ReparsePoint` during the sensitive-file scan.

### Tests
- Ported the four PowerShell-only regression cases (sensitive-file rejection, real install with catalog refresh, force-and-backup, idempotent memory update) into `tests/test-install.sh` so both shells share the same matrix.
- Added symlink-rejection regression to both `tests/test-install.sh` and `tests/test-install.ps1`, with a graceful skip when the runner cannot create real symlinks (for example Windows without Developer Mode).

### CI
- Added `.github/workflows/ci.yml` running Bash syntax validation, Bash + Python install/catalog tests on Ubuntu and macOS, and PowerShell install/catalog tests on Windows.

## [0.3.1] — 2026-08-22

### Fixed
- Parse single-line and folded/literal multi-line YAML descriptions without consuming the frontmatter terminator or body.
- Require both semantic classes for English compound image-recognition searches.
- Added regression coverage for frontmatter boundaries and compound search behavior.

## [0.3.0] — 2026-08-22

### Added
- Added installed-skill index generation with list, find, show, refresh, and doctor commands.
- Added deterministic keyword scoring with common bilingual aliases.
- Redacted user-specific absolute paths from the runtime index.
- Marked provenance as `unknown` when an existing skill was not installed through this installer.
- Reset stale legacy `local` provenance to `unknown` during refresh instead of preserving an unverified guess.
- Tightened Chinese compound search matching to reduce unrelated results.
- Made doctor report broken and duplicate names directly.
- Forced UTF-8 output for Bash catalog JSON on Windows-compatible shells.
- Added explicit unknown usage status instead of inventing invocation counts.
- Added automatic catalog refresh after successful installation with an opt-out flag.

## [0.2.0] — 2026-08-22

### Security and correctness
- Added strict validation for skill names, repository names, refs, hashes, and install path boundaries.
- Added staging, explicit --force, source backups, sensitive-file rejection, and root SKILL.md validation.
- Made smoke tests and memory updates opt-in.
- Added resolved commit and tarball SHA256 reporting.
- Added dry-run support and custom CLAUDE_SKILLS_LINK_DIR.
- Fixed junction/copy-fallback reporting and source/link hash verification.

### Documentation and testing
- Rewrote SKILL.md around trigger conditions, safety gates, and output contract.
- Rewrote README.md with public-install safety guidance, compatibility, options, and repository layout.
- Added SECURITY.md, .gitattributes, and temporary-directory regression tests.
- Aligned PowerShell and Bash flags and behavior.

## [0.1.0] — 2026-08-22

### Added
- PowerShell implementation for Windows.
- Bash fallback for macOS, Linux, and WSL.
- GitHub tarball and local-directory installation.
- Source/link verification, smoke-test heuristic, and optional memory update.
- Wrapper templates for future CLI-bundle support.
## [Codex 1.0] - 2026-08-23

### Added
- Native Codex adapter with user, project-ancestor, compatibility, system, admin, and conditional plugin discovery roots.
- Codex multi-path catalog visibility, duplicate/metadata-conflict diagnostics, `skills.config` enablement handling, and protected system/admin write boundaries.
- Codex install scopes (`user` and explicit `codex-home`), manager-owned backups, staging-only `--subdir` validation, and PowerShell/Bash regression coverage.
- GitHub Actions coverage for Codex tests.

### Security
- Canonical/realpath containment protects system and POSIX admin roots, including ancestor symlink/reparse targets; downloaded package links remain rejected.
