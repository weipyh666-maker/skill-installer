# Changelog

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
