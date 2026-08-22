# Changelog

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
