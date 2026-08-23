# skill-manager

A Skill Manager for Claude Code that knows what skills are installed, searches by capability, diagnoses discovery issues, and installs/updates safely.

## What it solves

1. **我装了什么？ (What skills are installed?)**
   Lists and groups all active skills across `~/.claude/skills` and `~/Claude-Code` by category, with health status and Claude visibility.

2. **我记得功能但忘了名字？ (Search by capability, not just exact name)**
   Indexes multi-lingual keywords, aliases, and explicit or derived capabilities so you can find skills by intent (e.g. `图片识别`, `document converter`, `data analytics`).

3. **明明装了，为什么 Agent 没发现？ (Diagnose discovery issues & broken skills)**
   Scans the local filesystem for unlinked skills, invalid `SKILL.md` frontmatter, missing files, or duplicated names via `doctor` and `capabilities` commands.

## Features

- **Schema v2 Catalog**: Categorizes skills (`Documents`, `Development`, `Browser`, `Research`, `Data`, `Media`, `Other`) with granular health, capability tags, and visibility checks.
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
| Capabilities | `-Command capabilities` | `--capabilities` | Summary grouped by category with broken count |
| List | `-Command list` | `--list` | Tabular skill listing |
| Find | `-Command find -Query value [-Limit N]` | `--find value [--limit N]` | Scored bilingual search with compound AND filtering |
| Show | `-Command show -Name value` | `--show value` | Deep inspection of skill provenance and visibility |
| Doctor | `-Command doctor [-Name value]` | `--doctor [--name value]` | Global inventory check or single-skill trigger quality diagnosis |
| Refresh | `-Command refresh` | `--refresh` | Rescan filesystem and update catalog index |

## Installer options

| PowerShell | Bash | Purpose |
|---|---|---|
| -Repo owner/name | --repo owner/name or positional | GitHub source |
| -Ref value | --ref value | Branch, tag, or commit |
| -LocalPath path | --local path | Local source |
| -Name value | --name value | Installed name |
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
├── core/
│   └── .gitkeep
├── adapters/
│   └── .gitkeep
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

Version 2.1.0 adds score-ranked bilingual capability search (`--find` / `-Query` with `--limit`), dual-mode inventory diagnosis (`--doctor` global & `--doctor --name` single-skill trigger quality inspection with actionable suggestions), and a 12th trigger condition for intent matching.

Version 2.0.0 evolves `skill-installer` into `skill-manager` with Catalog Schema v2, capability grouping (`--capabilities`), deep filesystem scanning for manual skills, missing health retention, and enhanced diagnostics.

Version 0.5.0 adds an anonymous public repository installation path (via curl on Linux/macOS and Invoke-WebRequest on Windows) removing the mandatory `gh auth login` requirement for public skills while preserving resolved commit SHA provenance.

Version 0.4.0 hardens the safety model against nested symbolic links and reparse points, aligns the Bash and PowerShell regression matrices, and adds GitHub Actions CI across Ubuntu, macOS, and Windows.

Version 0.3.1 adds the installed-skill catalog, search commands, safe multi-line YAML parsing, and English/Chinese compound search filtering.

## License

MIT. See LICENSE.
