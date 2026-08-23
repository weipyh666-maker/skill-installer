---
name: skill-manager
description: Use when the user wants to know what skills their agent has installed, asks what the agent can do, searches for a skill by capability rather than by name, suspects an installed skill is not being triggered automatically, asks whether a skill exists for a task, cannot recall the name of a previously-installed skill, says an installed skill looks broken or is not working, wants to inspect skill health, wants to install/update/remove a skill, wants to scan a directory for previously-installed skills not yet cataloged, asks for a summary of installed capabilities by category, asks which installed skill can perform a task by natural-language description (e.g. 哪个 skill 能做网页 UI, is there a skill that handles PDFs), wants to improve an existing skill's SKILL.md frontmatter so AI agents can auto-discover it more reliably, or wants to manage skills across Claude Code, Antigravity CLI, and Codex CLI from a single catalog.
---

# Skill Manager

## Core principle

Know what skills your agent has installed, organize and inspect them by capability and category, diagnose broken or unlinked skills, and install or update skills safely across supported agent platforms (Claude Code and Antigravity CLI). Treat downloaded code as untrusted until validated.

## Use this skill when

- The user wants an overview of available capabilities or installed skills across agents (`claude`, `antigravity`).
- The user asks what the agent can do or wants to search for a skill by capability.
- The user cannot recall the exact name of a previously installed skill.
- The user suspects an installed skill is broken, missing, or not being triggered by the agent.
- The user wants to scan skill directories (`~/.claude/skills`, `~/Claude-Code`, `~/.agents/skills`) for previously installed or manual skills.
- The user wants to improve or repair an existing skill's frontmatter triggers (`fix`).
- The user wants to install, update, refresh, or link a skill safely from GitHub or a local directory.

## Workflow

1. **Querying Capabilities & Inventory**:
   - Run `catalog.ps1 -Command capabilities [-Agent AGENT]` (or `catalog.sh --capabilities [--agent AGENT]`) to view skills grouped by category with health and broken counts.
   - Run `catalog.ps1 -Command list [-Agent AGENT]` (or `catalog.sh --list [--agent AGENT]`) for full tabular index output.
   - Run `catalog.ps1 -Command find -Query <keyword> [-Agent AGENT]` (or `catalog.sh --find <query> [--agent AGENT]`) for bilingual keyword search with ranking and match explanations.
   - Run `catalog.ps1 -Command show -Name <skill>` (or `catalog.sh --show <skill>`) to inspect deep metadata, provenance, and multi-agent visibility (`agents.claude.visible`, `agents.antigravity.visible`, `agents.codex.visible`).

2. **Scanning & Diagnosing**:
   - Run `catalog.ps1 -Command refresh [-Agent AGENT]` (or `catalog.sh --refresh [--agent AGENT]`) to scan agent directories, ingest manual skills, and update `installed-skills-index.json`.
   - Run `catalog.ps1 -Command doctor [-Agent AGENT]` (or `catalog.sh --doctor [--agent AGENT]`) to verify environment status, discovery roots, broken frontmatter, and evaluate the 8 trigger quality rules.
   - Run `catalog.ps1 -Command doctor -Name <skill>` (or `catalog.sh --doctor --name <skill>`) to assess individual skill trigger quality.

3. **Improving & Repairing Frontmatter (`fix`)**:
   - Run `catalog.ps1 -Command fix -DryRun [-Agent AGENT]` (or `catalog.sh --fix --dry-run [--agent AGENT]`) to preview proposed frontmatter improvements.
   - Run `catalog.ps1 -Command fix -Name <skill> [-Agent AGENT]` (or `catalog.sh --fix --name <skill> [--agent AGENT]`) to rewrite descriptions into standard trigger format and append capabilities and categories.

4. **Installing & Linking**:
   - Install public GitHub skills directly (anonymous fallback supported) or use `-RequireAuth` / `--require-auth` for private repos.
   - Specify target agent with `-Agent antigravity` (installs to `~/.agents/skills`) or default `-Agent claude` (installs to `~/Claude-Code` with link to `~/.claude/skills`).
   - Pin refs and check hashes where available (`-Ref`, `-ExpectedSha256`).
   - Back up existing versions automatically on `-Force`.

## Safety gates

- Never replace an existing install silently without `-Force` and a backup in `.backups/`.
- Never execute downloaded code without explicit `-RunSmokeTest`.
- Reject symbolic links, junctions, or other reparse points inside downloaded sources.
- Block installations into protected agent directories (e.g. Antigravity builtin skills `~/.gemini/antigravity-cli/builtin/skills/`).
- Support anonymous public repository downloads, with `--require-auth` available to enforce authentication.
- Track provenance accurately (`installer`, `manual`, `unknown`).

## Output contract

Report: category distribution, total and broken skill counts, discovery roots, agent visibility status, source paths, link paths, provenance, and invocation hints.
