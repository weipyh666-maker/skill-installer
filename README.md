# skill-installer

Install, validate, and link a Claude Code skill from a GitHub repository or a local directory.

The installer is designed for public distribution: downloaded content is treated as untrusted, replacement requires explicit --force, smoke tests are opt-in, and memory updates are opt-in.

## What it solves

Installing a skill usually involves locating the source, downloading it, placing it in a stable directory, linking it into Claude Code, checking the SKILL.md contract, and recording the result. This project turns that sequence into one repeatable command for Windows, macOS, Linux, and WSL.

## Supported inputs

- A GitHub repository in owner/name form.
- A local directory whose root contains a valid SKILL.md.
- An existing extracted source when only the link needs to be recreated.

This release installs one skill at a time. Discovery and ranking of skills belongs in a marketplace or skill-finder tool; this installer expects an exact source.

## Requirements

### Windows

- PowerShell 5.1 or newer.
- GitHub CLI (gh) and gh auth login for GitHub sources.
- tar for GitHub archives.

### macOS / Linux / WSL

- Bash.
- gh and gh auth login for GitHub sources.
- tar.
- realpath or Python 3 for safe path normalization.
- sha256sum or shasum for digest verification.
- Python 3 for Bash catalog commands (`--list`, `--find`, `--show`, `--doctor`, `--refresh`).

Local installs and dry-runs do not require GitHub authentication.

## Quick start

### PowerShell

~~~powershell
# Validate without changing files
pwsh -File lib\install.ps1 -LocalPath .\my-skill -DryRun

# Install a reviewed, pinned ref
pwsh -File lib\install.ps1 -Repo owner/skill-name -Ref 0123456789abcdef0123456789abcdef01234567

# Add -ExpectedSha256 <trusted-64-character-digest> when one is available

# Install from a local directory
pwsh -File lib\install.ps1 -LocalPath .\my-skill

# Replace an existing install after a backup
pwsh -File lib\install.ps1 -LocalPath .\my-skill -Name my-skill -Force

# Explicitly run a reviewed CLI smoke test
pwsh -File lib\install.ps1 -Repo owner/cli-skill -Ref v1.2.3 -RunSmokeTest
~~~

### Bash

~~~bash
# Validate without changing files
bash lib/install.sh --local ./my-skill --dry-run

# Install a reviewed, pinned ref
bash lib/install.sh owner/skill-name --ref 0123456789abcdef0123456789abcdef01234567 --expected-sha256 64-character-sha256

# Install from a local directory
bash lib/install.sh --local ./my-skill

# Replace an existing install after a backup
bash lib/install.sh --local ./my-skill --name my-skill --force
~~~

## Safety model

1. --dry-run performs validation and prints the plan without network, filesystem, link, smoke-test, or memory changes.
2. --force is required before replacing an existing source or link. Existing source content is moved into CLAUDE_SKILLS_DIR/.backups/.
3. Skill names, repositories, refs, hashes, and install paths are validated.
4. Local and downloaded sources containing .env, key files, certificate files, .git, or secrets/ are rejected.
5. GitHub downloads report the resolved commit and tarball SHA256.
6. Smoke tests execute downloaded code and therefore require the explicit -RunSmokeTest or --run-smoke-test flag.
7. Memory updates are disabled by default and require -UpdateMemory or --update-memory.

Review a third-party SKILL.md before installing it. A skill is instructions for an agent, not a sandbox.

## Skill catalog

The installer maintains an index at `CLAUDE_SKILLS_DIR/installed-skills-index.json` after a successful install. The index is a cache; the filesystem remains the source of truth.

~~~powershell
pwsh -File lib\catalog.ps1 -Command list
pwsh -File lib\catalog.ps1 -Command find -Query '图片识别'
pwsh -File lib\catalog.ps1 -Command show -Name skill-name
pwsh -File lib\catalog.ps1 -Command doctor
pwsh -File lib\catalog.ps1 -Command refresh
~~~

~~~bash
bash lib/catalog.sh --list
bash lib/catalog.sh --find 'image recognition'
bash lib/catalog.sh --show skill-name
bash lib/catalog.sh --doctor
bash lib/catalog.sh --refresh
~~~

Catalog results include the name, install directory name, description, source/link display paths, status, and an invocation hint. Paths are stored with environment placeholders rather than user-specific absolute paths. Existing skills not installed through this installer use source `unknown` and null provenance fields; the catalog does not guess. Refreshing also converts legacy `source: local` entries from older index versions to `unknown` unless a trusted installer registration replaces them.

The two shells expose the same operations with their native argument style:

| Operation | PowerShell | Bash |
|---|---|---|
| List | `-Command list` | `--list` |
| Find | `-Command find -Query value` | `--find value` |
| Show | `-Command show -Name value` | `--show value` |
| Doctor | `-Command doctor` | `--doctor` |
| Refresh | `-Command refresh` | `--refresh` |

Usage is reported as `unknown` unless the host provides a trustworthy invocation event; the catalog never invents usage counts.

## Pipeline

| Step | Behavior |
|---|---|
| 1. Pre-flight | Validate source mode, name, ref, hash, and required tools |
| 2. Prepare source | Stage a local directory or fetch a GitHub tarball |
| 3. Create link | Create a junction/symlink, or report a copy fallback |
| 4. Verify | Validate frontmatter and compare source/link SKILL.md hashes |
| 5. Smoke test | Optional and explicit; never the default |
| 6. Memory | Optional and idempotent; never the default |
| 7. Catalog/result | Refresh the index and print paths, mode, commit, digest, and verification status |

## Options

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
skill-installer/
├── SKILL.md
├── README.md
├── SECURITY.md
├── CHANGELOG.md
├── LICENSE
├── .gitattributes
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

The current release is a standalone installer skill. A future collection repository can place additional skills under skills/<skill-name>/ and add a selector without changing this install contract.

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

Version 0.3.1 adds the installed-skill catalog, search commands, safe multi-line YAML parsing, and English/Chinese compound search filtering. It refreshes the index after successful installation while keeping usage status explicitly unknown when the host exposes no invocation events.

## License

MIT. See LICENSE.
