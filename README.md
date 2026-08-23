# skill-manager

A Skill Manager for Claude Code that knows what skills are installed, searches by capability, diagnoses discovery issues, and installs/updates safely.

## What it solves

1. **我装了什么？ (What skills are installed?)**
   Lists and groups all active skills across `~/.claude/skills` and `~/Claude-Code` by category, with health status and Claude visibility.

2. **我记得功能但忘了名字？ (Search by capability, not just exact name)**
   Indexes multi-lingual keywords, aliases, and explicit or derived capabilities so you can find skills by intent (e.g. `图片识别`, `document converter`, `data analytics`).

3. **明明装了，为什么 Agent 没发现？ (Diagnose discovery issues & broken skills)**
   Scans the local filesystem for unlinked skills, invalid `SKILL.md` frontmatter, missing files, or duplicated names via `doctor` and `capabilities` commands.

- **Schema v3 Multi-Agent Catalog**: Categorizes skills (`Documents`, `Development`, `Browser`, `Research`, `Data`, `Media`, `Other`) with granular health, capability tags, and cross-agent visibility checks (`claude`, `codex`, `antigravity`).
- **High-Accuracy Find Engine**: Multilingual intent search backed by a 50-query benchmark suite achieving 96% Top-1 and 100% Top-3 accuracy with transparent `matched:` explainability reasons.
- **Trigger Quality Diagnosis & Repair**: Automated `doctor` and `fix` workflows that detect sub-optimal frontmatter descriptions and bulk-repair them into standard `"Use when the user wants to..."` syntax.
- **Deep Scanning & Ingestion**: Automatically scans and ingests manually placed skills into the index while maintaining installer provenance (`commit`, `sha256`, `installed_at`).
- **Safe Installation & Refresh**: Installs skills from public or private GitHub repos and local paths, with staging, atomic backups, sensitive file checks, and reparse-point rejection.
- **Cross-Platform**: Full parity across PowerShell (Windows) and Bash (macOS/Linux/WSL).

## Requirements

### Windows

- PowerShell 5.1 or newer.
- `tar` for GitHub archives.
- GitHub CLI (`gh`) and `gh auth login` for private repositories. Public repositories download via built-in `Invoke-WebRequest` without `gh`.

### macOS / Linux / WSL

- Bash.
- `tar`.
- `curl` (or `gh`) for GitHub sources. `gh auth login` is only required for private repositories.
- Python 3 for safe path normalization and Bash catalog commands (`--capabilities`, `--list`, `--find`, `--show`, `--doctor`, `--refresh`).
- `sha256sum` or `shasum` for digest verification.

Public GitHub installs, local installs, and dry-runs do not require GitHub authentication.

## Quick start

### Inspecting capabilities and inventory

~~~powershell
# Show summary of capabilities grouped by category with health count
pwsh -File lib\catalog.ps1 -Command capabilities

# Full tabular listing
pwsh -File lib\catalog.ps1 -Command list

# Search by capability / intent with score ranking and limit
pwsh -File lib\catalog.ps1 -Command find -Query '做网页 UI' -Limit 5
pwsh -File lib\catalog.ps1 -Command find -Query '图片识别'

# Inspect detailed metadata, provenance, and Claude visibility
pwsh -File lib\catalog.ps1 -Command show -Name skill-name

# Run global health check and inventory diagnosis
pwsh -File lib\catalog.ps1 -Command doctor

# Run single skill deep inspection and trigger quality check
pwsh -File lib\catalog.ps1 -Command doctor -Name frontend-design

# Re-scan filesystem and refresh catalog index
pwsh -File lib\catalog.ps1 -Command refresh
~~~

~~~bash
# Show summary of capabilities grouped by category with health count
bash lib/catalog.sh --capabilities

# Full tabular listing
bash lib/catalog.sh --list

# Search by capability / intent with score ranking and limit
bash lib/catalog.sh --find '做网页 UI' --limit 5
bash lib/catalog.sh --find 'image recognition'

# Inspect detailed metadata, provenance, and Claude visibility
bash lib/catalog.sh --show skill-name

# Run global health check and inventory diagnosis
bash lib/catalog.sh --doctor

# Run single skill deep inspection and trigger quality check
bash lib/catalog.sh --doctor --name frontend-design

# Re-scan filesystem and refresh catalog index
bash lib/catalog.sh --refresh
~~~

### Installing and updating skills

~~~powershell
# Install a public repository (no gh auth login required)
pwsh -File lib\install.ps1 -Repo owner/skill-name -Ref v1.0.0

# Install a reviewed, pinned ref with expected digest
pwsh -File lib\install.ps1 -Repo owner/skill-name -Ref 0123456789abcdef0123456789abcdef01234567 -ExpectedSha256 64-character-sha256

# Install from a local directory
pwsh -File lib\install.ps1 -LocalPath .\my-skill

# Replace an existing install after a backup
pwsh -File lib\install.ps1 -LocalPath .\my-skill -Name my-skill -Force
~~~

~~~bash
# Install a public repository (no gh auth login required)
bash lib/install.sh owner/skill-name --ref v1.0.0

# Install a reviewed, pinned ref with expected digest
bash lib/install.sh owner/skill-name --ref 0123456789abcdef0123456789abcdef01234567 --expected-sha256 64-character-sha256

# Install from a local directory
bash lib/install.sh --local ./my-skill

# Replace an existing install after a backup
bash lib/install.sh --local ./my-skill --name my-skill --force
~~~

## Safety model

1. `--dry-run` performs validation and prints the plan without network, filesystem, link, smoke-test, or memory changes.
2. `--force` is required before replacing an existing source or link. Existing source content is moved into `CLAUDE_SKILLS_DIR/.backups/`.
3. Skill names, repositories, refs, hashes, and install paths are validated against path traversal and forbidden characters.
4. Local and downloaded sources containing `.env`, key files, certificate files, `.git`, `secrets/`, or any symbolic link / reparse point are rejected.
5. GitHub downloads report the resolved commit and tarball SHA256.
6. Smoke tests execute downloaded code and therefore require the explicit `-RunSmokeTest` or `--run-smoke-test` flag.
7. Memory updates are disabled by default and require `-UpdateMemory` or `--update-memory`.

Review a third-party `SKILL.md` before installing it. A skill is instructions for an agent, not a sandbox.

## Catalog operations

The manager maintains a cache index at `CLAUDE_SKILLS_DIR/installed-skills-index.json`. The filesystem remains the ultimate source of truth.

| Operation | PowerShell | Bash | Purpose |
|---|---|---|---|
| Capabilities | `-Command capabilities [-Agent name] [-AllAgents]` | `--capabilities [--agent name] [--all-agents]` | Summary grouped by category with broken count |
| List | `-Command list [-Agent name] [-AllAgents]` | `--list [--agent name] [--all-agents]` | Tabular skill listing |
| Find | `-Command find -Query value [-Limit N] [-Agent name] [-AllAgents]` | `--find value [--limit N] [--agent name] [--all-agents]` | Scored bilingual search with compound AND filtering |
| Show | `-Command show -Name value` | `--show value` | Deep inspection of skill provenance and visibility per agent |
| Doctor | `-Command doctor [-Name value] [-Agent name] [-AllAgents]` | `--doctor [--name value] [--agent name] [--all-agents]` | Global inventory check or single-skill trigger quality diagnosis |
| Fix | `-Command fix [-Name value] [-DryRun] [-Yes]` | `--fix [--name value] [--dry-run] [--yes]` | Rewrite frontmatter triggers and auto-derive capabilities & category |
| Refresh | `-Command refresh` | `--refresh` | Rescan filesystem and update catalog index |

## Improving existing skills with `skill fix`

The `fix` command upgrades legacy or poorly discoverable `SKILL.md` frontmatter so that Claude Code can reliably trigger installed skills on matching user intents.

~~~powershell
# Preview changes for all skills (dry-run)
pwsh -File lib\catalog.ps1 -Command fix -DryRun

# Preview changes for a single skill
pwsh -File lib\catalog.ps1 -Command fix -Name frontend-design -DryRun

# Interactively fix a single skill
pwsh -File lib\catalog.ps1 -Command fix -Name frontend-design

# Fix all skills in bulk without prompts
pwsh -File lib\catalog.ps1 -Command fix -Yes
~~~

~~~bash
# Preview changes for all skills (dry-run)
bash lib/catalog.sh --fix --dry-run

# Preview changes for a single skill
bash lib/catalog.sh --fix --name frontend-design --dry-run

# Interactively fix a single skill
bash lib/catalog.sh --fix --name frontend-design

# Fix all skills in bulk without prompts
bash lib/catalog.sh --fix --yes
~~~

### Rewrite rules & safety

1. **Description normalization**:
   - **Case A** (`Use when...`): Retained as-is.
   - **Case B** (Imperative verbs like `Create`, `Build`, `Analyze`, `Convert`): Prefixed with `Use when the user wants to <base-verb>...`.
   - **Case C** (3rd-person introductory phrases like `This skill should be used when the user needs to...`): Stripped of boilerplate and converted cleanly to `Use when the user needs to...`.
   - **Case D** (Short descriptions < 20 chars): Skipped with a warning explaining that manual editing is required.
   - **Case E** (General sentences): Prefixed with `Use when the user wants to...`.
2. **Auto-derived capabilities & category**:
   - Up to 5 key noun/capability tags are extracted from the name, description, and aliases.
   - Category is bucketed across `documents`, `development`, `media`, `data`, `browser`, `research`, or `other`.
3. **Symlink protection**:
   - Symlinks and NTFS junction reparse points are never modified in-place; a proposed patch is printed to stdout instead.
4. **Automated backups**:
   - Before modifying any file, the original `SKILL.md` is backed up to `$CLAUDE_SKILLS_DIR/.backups/<skill>-<timestamp>-SKILL.md`.
5. **Doctor verification**:
   - After applying fixes, `doctor` automatically verifies that trigger quality warnings (⚠) have decreased.

> [!WARNING]
> `skill fix` modifies `SKILL.md` frontmatter in place. Always run `--dry-run` to preview changes before applying.

## Installer options

| PowerShell | Bash | Purpose |
|---|---|---|
| -Repo owner/name | --repo owner/name or positional | GitHub source |
| -Ref value | --ref value | Branch, tag, or commit |
| -LocalPath path | --local path | Local source |
| -Name value | --name value | Installed name |
| -Agent claude\|codex\|antigravity | --agent claude\|codex\|antigravity | Target AI agent harness (default: claude) |
| -LinkOnly | --link-only | Recreate a link from an existing source |
| -Force | --force | Replace after backing up |
| -DryRun | --dry-run | Validate without changing state |
| -RunSmokeTest | --run-smoke-test | Explicitly execute a reviewed source |
| -UpdateMemory | --update-memory | Append one idempotent memory row |
| -ExpectedSha256 | --expected-sha256 | Verify the archive digest |
| -RequirePinnedRef | --require-pinned-ref | Reject an omitted ref |
| -RequireAuth | --require-auth | Require gh authentication; disable anonymous fallback |
| -AllowAnonymousFallback | --allow-anonymous-fallback | Allow anonymous fallback if gh is not authenticated (default) |
| -SkipCatalogUpdate | --skip-catalog-update | Do not refresh the installed-skill index |

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| CLAUDE_SKILLS_AGENT | claude | Default AI agent harness (`claude`, `codex`, `antigravity`) |
| CLAUDE_SKILLS_DIR | ~/Claude-Code | Source directory |
| CLAUDE_SKILLS_LINK_DIR | ~/.claude/skills | Claude Code link directory |
| CLAUDE_SKILLS_INDEX_PATH | CLAUDE_SKILLS_DIR/installed-skills-index.json | Optional catalog index path |
| SKIP_SMOKE_TEST | unset | Compatibility override for smoke tests |
| SKIP_MEMORY_UPDATE | unset | Compatibility override for memory updates |
| SKIP_CATALOG_UPDATE | unset | Compatibility override for catalog refresh |

## Repository layout

~~~text
skill-manager/
├── .github/workflows/ci.yml
├── SKILL.md
├── README.md
├── SECURITY.md
├── CHANGELOG.md
├── LICENSE
├── .gitattributes
├── adapters/
│   ├── _base.ps1 / _base.sh
│   ├── claude/ (paths, detect)
│   ├── codex/ (paths, stub-note.md)
│   └── antigravity/ (paths, stub-note.md)
├── core/
│   ├── scanner.ps1 / scanner.sh
│   ├── search.ps1 / search.sh
│   └── doctor.ps1 / doctor.sh
├── lib/
│   ├── install.ps1
│   ├── install.sh
│   ├── catalog.ps1
│   └── catalog.sh
├── templates/
│   ├── wrapper.ps1.tpl
│   └── wrapper.sh.tpl
└── tests/
    ├── test-install.ps1
    ├── test-install.sh
    ├── test-catalog.ps1
    ├── test-catalog.sh
    └── fixtures/minimal-skill/SKILL.md
~~~

## Development and verification

~~~powershell
pwsh -NoProfile -File tests\test-install.ps1
pwsh -NoProfile -File tests\test-catalog.ps1
~~~

~~~bash
bash tests/test-install.sh
bash -n lib/install.sh
bash tests/test-catalog.sh
bash -n lib/catalog.sh
~~~

The test suite uses temporary directories and never writes to a user's Claude Code directory.

## Release notes

Version 3.0.0 introduces modular multi-agent adapters (`claude`, `codex`, `antigravity`), CLI `--agent` / `-Agent` options and `CLAUDE_SKILLS_AGENT` environment support, Catalog Schema v3 with per-agent visibility objects and automatic v1/v2 migration, core subsystem breakdown (`scanner`, `search`, `doctor`), and multi-agent filtering across catalog commands.

Version 2.2.0 adds `skill fix` (`--fix` / `-Command fix`) for automated and interactive batch frontmatter trigger repair, 5-case description normalization, automated `capabilities` and `category` derivation, symlink protection, automated backups, and post-fix doctor verification.

Version 2.1.0 adds score-ranked bilingual capability search (`--find` / `-Query` with `--limit`), dual-mode inventory diagnosis (`--doctor` global & `--doctor --name` single-skill trigger quality inspection with actionable suggestions), and a 12th trigger condition for intent matching.

Version 2.0.0 evolves `skill-installer` into `skill-manager` with Catalog Schema v2, capability grouping (`--capabilities`), deep filesystem scanning for manual skills, missing health retention, and enhanced diagnostics.

Version 0.5.0 adds an anonymous public repository installation path (via curl on Linux/macOS and Invoke-WebRequest on Windows) removing the mandatory `gh auth login` requirement for public skills while preserving resolved commit SHA provenance.

Version 0.4.0 hardens the safety model against nested symbolic links and reparse points, aligns the Bash and PowerShell regression matrices, and adds GitHub Actions CI across Ubuntu, macOS, and Windows.

Version 0.3.1 adds the installed-skill catalog, search commands, safe multi-line YAML parsing, and English/Chinese compound search filtering.

## License

MIT. See LICENSE.


> **Note**: Trigger quality rules: 8 (since V3.1.1) — covers prefix, action verbs, verb diversity, concrete examples, length (30-200), prose structure, capabilities, and category.
