---
name: skill-installer
description: Use when installing, downloading, refreshing, or linking a Claude Code skill from a GitHub repository or local directory, especially when the source should be validated, optionally pinned, and installed without an interactive session.
---

# Skill Installer

## Core principle

Treat every downloaded repository as untrusted until its source, ref, files, and install target are validated. Keep destructive and executable side effects explicit.

## Use this skill when

- The user asks to install, download, refresh, or link a Claude Code skill.
- The source is a GitHub repository, tag, commit, or local skill directory.
- The user needs a dry-run, backup, digest check, or source/link verification.

Do not use it to discover or rank candidate skills. Use a marketplace or skill-finder first, then pass the selected repository here.

## Workflow

1. Validate exactly one source mode: GitHub, local directory, or existing source link refresh.
2. Validate the skill name, repository, ref, digest, and path boundaries.
3. Reject local or downloaded sources containing secrets, key material, .git, or secrets/.
4. Run a dry-run when the target or source is unfamiliar.
5. Stage the source before replacing an existing install; require --force and keep a backup.
6. Create a junction or symlink and report copy fallback explicitly.
7. Validate SKILL.md frontmatter and compare source/link hashes.
8. Run a smoke test only when the user explicitly requests it for a reviewed source.
9. Update memory only when explicitly requested, and do so idempotently.
10. Refresh the installed-skill catalog after success unless the user opts out.

## Safety gates

- Never accept path traversal or absolute values as the skill name.
- Never replace an existing install silently.
- Never execute downloaded code by default.
- Prefer an immutable commit SHA and verify ExpectedSha256 when available.
- Stop if the source does not contain a valid root SKILL.md.
- Report usage as unknown unless the host provides a trustworthy invocation event.

## Output contract

Report: mode, source path, link path, install mode, resolved commit, source/link verification, smoke-test status, memory status, catalog status, and timestamp.
