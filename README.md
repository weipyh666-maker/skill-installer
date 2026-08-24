# skill-manager

A multi-agent Skill Manager for discovering, searching, diagnosing, and safely managing installed Agent Skills across AI agents (Claude Code, Antigravity CLI, Codex CLI, DeepSeek Harness).

## What it solves

1. **我装了什么？ (What skills are installed?)**
   Lists and groups all active skills across agent directories (`~/.claude/skills`, `~/Claude-Code`, `~/.agents/skills`) by category, with health status and per-agent visibility.

2. **我记得功能但忘了名字？ (Search by capability, not just exact name)**
   Indexes multi-lingual keywords, aliases, and explicit or derived capabilities so you can find skills by intent (e.g. `图片识别`, `做网页 UI`, `document converter`, `data analytics`).

3. **明明装了，为什么 Agent 没发现？ (Diagnose discovery issues & broken skills)**
   Scans the local filesystem for unlinked skills, invalid `SKILL.md` frontmatter, missing files, or duplicated names via `doctor` and `capabilities` commands.

- **Schema v3 Multi-Agent Catalog**: Categorizes skills (`Documents`, `Development`, `Browser`, `Research`, `Data`, `Media`, `Other`) with granular health, capability tags, and cross-agent visibility checks (`claude`, `antigravity`, `codex`).
- **High-Accuracy Find Engine**: Multilingual intent search backed by a 50-query benchmark suite achieving 96% Top-1 and 100% Top-3 accuracy with transparent `matched:` explainability reasons.
- **Trigger Quality Diagnosis & Repair**: Automated `doctor` and `fix` workflows that detect sub-optimal frontmatter descriptions and bulk-repair them into standard `"Use when the user wants to..."` syntax.
- **Deep Scanning & Ingestion**: Automatically scans and ingests manually placed skills into the index while maintaining installer provenance (`commit`, `sha256`, `installed_at`).
- **Safe Installation & Refresh**: Installs skills from public or private GitHub repos and local paths, with staging, atomic backups, sensitive file checks, and reparse-point rejection.
- **Cross-Platform**: Full parity across PowerShell (Windows) and Bash (macOS/Linux/WSL).

## Multi-Agent Support

| Agent | Adapter | Status | Default Global Skills Directory |
| :--- | :--- | :--- | :--- |
| **Claude Code** | `adapters/claude/` | **Supported** (v1.0) | `~/.claude/skills/` (links to `~/Claude-Code/`) |
| **Antigravity** | `adapters/antigravity/` | **Supported** (v1.0 / v3.2.0) | `~/.agents/skills/` |
| **OpenAI Codex** | `adapters/codex/` | **Supported** (Codex 1.0) | `~/.agents/skills/` |
| **DeepSeek Harness** | `adapters/deepseek-harness/` | **Experimental** | `~/.dsh/skills/` |

Codex uses multiple discovery roots. The documented user root is `~/.agents/skills/`; repository ancestors use `.agents/skills/`; `$CODEX_HOME/skills/` is the compatibility/official-installer root; `$CODEX_HOME/skills/.system/` is read-only protected. Duplicate names retain all paths and report `precedence=unknown`.

DeepSeek Harness (Experimental, not yet Supported) discovers from `project-dsh` (`<gitRoot>/.dsh/skills`, rank 100), `project-agents` (`<gitRoot>/.agents/skills`, 200), `custom` (preset `customSkillDirs`, 300), `user-dsh` (`$DSH_HOME/skills`, 400), `user-agents` (`$DSH_AGENTS_HOME`/`~/.agents/skills`, 500), and `bundled` (`bundledSkillDir`/`$DSH_BUNDLED_SKILL_DIR`, 600) roots. Rank resolves duplicates only within a provider layer (verified DSH rule); the catalog reports a predicted within-layer winner and never claims a cross-layer runtime winner. `~/.dsh/skills` is the default install target; `~/.agents/skills` alone never makes the harness `usable`. The reserved `$DSH_HOME/skills/.system` namespace is skipped, not a system-skill root, and no DSH root is marked protected (skill-manager's own write policy is carried per variant as `write_policy`).

## Requirements

### Windows

- PowerShell 5.1 or newer.
- `tar` for GitHub archives.
- GitHub CLI (`gh`) and `gh auth login` for private repositories. Public repositories download via built-in `Invoke-WebRequest` without `gh`.

### macOS / Linux / WSL

- Bash.
- `tar`.
- `curl` (or `gh`) for GitHub sources. `gh auth login` is only required for private repositories.
- Python 3 for safe path normalization and Bash catalog commands (`--capabilities`, `--list`, `--find`, `--show`, `--doctor`, `--refresh`, `--fix`).
- `sha256sum` or `shasum` for digest verification.

Public GitHub installs, local installs, and dry-runs do not require GitHub authentication.

## Quick start

### Inspecting capabilities and inventory

~~~powershell
# Show summary of capabilities grouped by category with health count
pwsh -File lib\catalog.ps1 -Command capabilities

# Query specifically for Antigravity skills
pwsh -File lib\catalog.ps1 -Command capabilities -Agent antigravity

# Full tabular listing
pwsh -File lib\catalog.ps1 -Command list

# Search by capability / intent with score ranking and limit
pwsh -File lib\catalog.ps1 -Command find -Query '做网页 UI' -Limit 5
pwsh -File lib\catalog.ps1 -Command find -Query '图片识别' -Agent antigravity

# Inspect detailed metadata, provenance, and multi-agent visibility
pwsh -File lib\catalog.ps1 -Command show -Name frontend-design

# Run global health check and inventory diagnosis
pwsh -File lib\catalog.ps1 -Command doctor
pwsh -File lib\catalog.ps1 -Command doctor -Agent antigravity

# Run single skill deep inspection and trigger quality check
pwsh -File lib\catalog.ps1 -Command doctor -Name frontend-design

# Re-scan filesystem and refresh catalog index
pwsh -File lib\catalog.ps1 -Command refresh
pwsh -File lib\catalog.ps1 -Command refresh -Agent antigravity

# DeepSeek Harness (Experimental): doctor with provider/consumer state
pwsh -File lib\catalog.ps1 -Command doctor -Agent deepseek-harness
~~~

~~~bash
# Show summary of capabilities grouped by category with health count
bash lib/catalog.sh --capabilities

# Query specifically for Antigravity skills
bash lib/catalog.sh --capabilities --agent antigravity

# Full tabular listing
bash lib/catalog.sh --list

# Search by capability / intent with score ranking and limit
bash lib/catalog.sh --find '做网页 UI' --limit 5
bash lib/catalog.sh --find 'image recognition' --agent antigravity

# Inspect detailed metadata, provenance, and multi-agent visibility
bash lib/catalog.sh --show frontend-design

# Run global health check and inventory diagnosis
bash lib/catalog.sh --doctor
bash lib/catalog.sh --doctor --agent antigravity

# Run single skill deep inspection and trigger quality check
bash lib/catalog.sh --doctor --name frontend-design

# Re-scan filesystem and refresh catalog index
bash lib/catalog.sh --refresh
bash lib/catalog.sh --refresh --agent antigravity

# DeepSeek Harness (Experimental): doctor with provider/consumer state
bash lib/catalog.sh --doctor --agent deepseek-harness
~~~

### Installing and updating skills

~~~powershell
# Install a public repository to Claude Code (default)
pwsh -File lib\install.ps1 -Repo owner/skill-name -Ref v1.0.0

# Install directly to Antigravity global skill directory (~/.agents/skills)
pwsh -File lib\install.ps1 -Repo owner/skill-name -Ref v1.0.0 -Agent antigravity

# Install from a local directory into Antigravity
pwsh -File lib\install.ps1 -LocalPath ./my-local-skill -Name my-local-skill -Agent antigravity

# Install into DeepSeek Harness (Experimental): user root (~/.dsh/skills, default) or shared target
pwsh -File lib\install.ps1 -Repo owner/skill-name -Agent deepseek-harness
pwsh -File lib\install.ps1 -Repo owner/skill-name -Agent deepseek-harness -Scope user-agents
pwsh -File lib\install.ps1 -Repo owner/skill-name -Agent deepseek-harness -Scope project

# Install a reviewed, pinned ref with expected digest
pwsh -File lib\install.ps1 -Repo owner/skill-name -Ref 0123456789abcdef0123456789abcdef01234567 -ExpectedSha256 64-character-sha256
~~~

~~~bash
# Install a public repository to Claude Code (default)
bash lib/install.sh --repo owner/skill-name --ref v1.0.0

# Install directly to Antigravity global skill directory (~/.agents/skills)
bash lib/install.sh --repo owner/skill-name --ref v1.0.0 --agent antigravity

# Install from a local directory into Antigravity
bash lib/install.sh --local ./my-local-skill --name my-local-skill --agent antigravity

# Install into DeepSeek Harness (Experimental): user root (~/.dsh/skills, default) or shared target
bash lib/install.sh --repo owner/skill-name --agent deepseek-harness
bash lib/install.sh --repo owner/skill-name --agent deepseek-harness --scope user-agents
~~~

## Environment variables

| Variable | Default | Purpose |
| :--- | :--- | :--- |
| `SKILL_MANAGER_AGENT` / `CLAUDE_SKILLS_AGENT` | `claude` | Default AI agent harness (`claude`, `antigravity`, `codex`) |
| `SKILL_MANAGER_STORE_DIR` | unset | Global store directory override across agents |
| `ANTIGRAVITY_SKILLS_DIR` | `~/.agents/skills` | Antigravity global skill directory |
| `ANTIGRAVITY_SKILLS_LINK_DIR` | `~/.agents/skills` | Antigravity discovery root |
| `ANTIGRAVITY_BUILTIN_DIR` | `~/.gemini/antigravity-cli/builtin/skills` | Antigravity builtin skills (protected) |
| `CLAUDE_SKILLS_DIR` | `~/Claude-Code` | Claude Code source directory |
| `CLAUDE_SKILLS_LINK_DIR` | `~/.claude/skills` | Claude Code link directory |
| `CLAUDE_SKILLS_INDEX_PATH` | `CLAUDE_SKILLS_DIR/installed-skills-index.json` | Catalog index path override |
| `SKIP_SMOKE_TEST` | unset | Compatibility override for smoke tests |
| `SKIP_MEMORY_UPDATE` | unset | Compatibility override for memory updates |
| `SKIP_CATALOG_UPDATE` | unset | Compatibility override for catalog refresh |
| `SKILL_MANAGER_DSH_HOME` | `$DSH_HOME` / `~/.dsh` | DeepSeek Harness home override (user-dsh root, index, backups) |
| `SKILL_MANAGER_DSH_AGENTS_HOME` | `$DSH_AGENTS_HOME` / `~/.agents` | Shared agents root override (user-agents root) |
| `SKILL_MANAGER_DSH_BUNDLED_DIR` | `$DSH_BUNDLED_SKILL_DIR` | Bundled skill root override (diagnostic-only) |
| `SKILL_MANAGER_DSH_CWD` / `SKILL_MANAGER_DSH_INDEX_PATH` / `SKILL_MANAGER_DSH_CLI_PATH` / `SKILL_MANAGER_DSH_SETTINGS_PATH` / `SKILL_MANAGER_DSH_PRESET` | unset | DeepSeek Harness test/diagnostic overrides (mirror the Codex pattern) |

## Repository layout

~~~text
skill-manager/
├── .github/workflows/ci.yml
├── SKILL.md
├── README.md
├── SECURITY.md
├── CHANGELOG.md
├── LICENSE
├── adapters/
│   ├── _base.ps1 / _base.sh
│   ├── claude/ (paths, detect)
│   ├── antigravity/ (paths, detect, README.md)
│   └── codex/ (paths, detect, README.md)
│   └── deepseek-harness/ (paths, detect, README.md) — Experimental
├── core/
│   ├── scanner.ps1 / scanner.sh
│   ├── search.ps1 / search.sh
│   └── doctor.ps1 / doctor.sh
├── lib/
│   ├── install.ps1
│   ├── install.sh
│   ├── catalog.ps1
│   └── catalog.sh
└── tests/
    ├── test-install.ps1 / test-install.sh
    ├── test-catalog.ps1 / test-catalog.sh
    ├── test-find-benchmark.ps1 / test-find-benchmark.sh
    ├── test-auto-trigger.ps1 / test-auto-trigger.sh
    ├── test-graduation.ps1 / test-graduation.sh
    ├── test-antigravity.ps1 / test-antigravity.sh
    ├── test-codex.ps1 / test-codex.sh
    ├── test-deepseek-harness.ps1 / test-deepseek-harness.sh — Experimental
    └── fixtures/
~~~

## Development and verification

~~~powershell
pwsh -NoProfile -File tests\test-install.ps1
pwsh -NoProfile -File tests\test-catalog.ps1
pwsh -NoProfile -File tests\test-find-benchmark.ps1
pwsh -NoProfile -File tests\test-auto-trigger.ps1
pwsh -NoProfile -File tests\test-graduation.ps1
pwsh -NoProfile -File tests\test-antigravity.ps1
pwsh -NoProfile -File tests\test-deepseek-harness.ps1
~~~

~~~bash
bash tests/test-install.sh
bash tests/test-catalog.sh
bash tests/test-find-benchmark.sh
bash tests/test-auto-trigger.sh
bash tests/test-graduation.sh
bash tests/test-antigravity.sh
bash tests/test-deepseek-harness.sh
~~~

## License

MIT. See LICENSE.
