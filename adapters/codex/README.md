# Codex Native Adapter

Codex Skills are discovered from multiple roots:

- User: `$HOME/.agents/skills`
- Project: every ancestor `.agents/skills` from the working directory to the repository root
- Compatibility/install target: `$CODEX_HOME/skills` (default `~/.codex/skills`)
- System: `$CODEX_HOME/skills/.system` (hard-protected)
- POSIX admin: `/etc/codex/skills` (scan-only and protected)
- Plugin cache: conditional visibility because cache presence does not prove plugin enablement

The adapter preserves every path for duplicate Skill names and reports `precedence=unknown`; it never selects a winner. `skills.config` `enabled=false` entries remain indexed on disk but are not visible. Codex installs default to the user root; pass `-Scope codex-home` or `--scope codex-home` to target the compatibility root explicitly.

Downloaded `--subdir` selections are validated only inside the staging tree with canonical containment and package reparse/link rejection. Forced replacements use the manager-owned `$CODEX_HOME/skill-manager/backups` store, outside all discovery roots.
