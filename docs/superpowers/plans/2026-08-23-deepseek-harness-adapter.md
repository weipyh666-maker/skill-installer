# DeepSeek Harness Adapter Implementation Plan

Baseline: `master` @ `bc09af8` (docs: graduate Codex adapter), working tree clean.

Source of truth: `DEEPSEEK_HARNESS_ANALYSIS.md` (Phase A investigation, evidence classes: REAL ENV / SOURCE / OFFICIAL DOC / TEST FIXTURE).

## Non-negotiable acceptance rules

1. Status is **Experimental**; never claim DeepSeek Harness is "Supported".
2. Default install target = `~/.dsh/skills` (user-dsh root, rank 400).
3. `~/.agents/skills` is an optional shared target; its existence alone must never yield `usable=true`.
4. Preserve the six-layer distinction: filesystem root != provider != registry candidate != catalog visibility != model selection != loaded skill.
5. Duplicates follow the verified DSH rules: within-layer rank (asc) -> provider order -> local order -> first-wins; across-layer nearest scope wins. Rank is a within-layer tiebreak, not a global precedence.
6. Claim a runtime winner only when scope/preset information is sufficient. Filesystem-level catalog: predicted winner (within-layer) only; `runtime_winner` stays `null`.
7. Bundled roots are NOT officially protected: `protected` stays `false`; skill-manager's own write policy is represented separately via per-variant `write_policy`.
8. DSH `.system` is a reserved skipped namespace under the user-dsh root only, not a Codex-style system-skill root; it is not scanned and not protected.
9. Distinguish discoverable / eligible / expected-visible / confirmed-visible / invoked in the schema.
10. Detect provider AND consumer state (preset composition) for visibility.
11. The shared Find scorer is not modified.
12. No Docker, no Update/Remove, no MCP, no AGENTS.md management, no telemetry, no fifth agent.

## Target files

| Action | File |
|---|---|
| add | `adapters/deepseek-harness/paths.ps1` / `paths.sh` |
| add | `adapters/deepseek-harness/detect.ps1` / `detect.sh` |
| add | `adapters/deepseek-harness/README.md` |
| add | `tests/test-deepseek-harness.ps1` / `test-deepseek-harness.sh` |
| add | `docs/superpowers/plans/2026-08-23-deepseek-harness-adapter.md` |
| edit | `adapters/_base.ps1` / `_base.sh` (SupportedAgents) |
| edit | `lib/catalog.ps1` / `catalog.sh` (agent branch, builder, doctor, fix, show, backup) |
| edit | `lib/install.ps1` / `install.sh` (agent branch, scopes) |
| edit | `.github/workflows/ci.yml` (bash + PowerShell test steps) |
| edit | `README.md`, `SKILL.md`, `CHANGELOG.md` |

## Schema (per skill, `agents['deepseek-harness']`)

- Ladder: `discoverable` (disk+parse+valid kebab+no legacy invocation keys) / `eligible` (`model_invocable` && not shadowed within layer) / `expected_visible` (= `visible`: eligible && consumer mounted) / `confirmed_visible` (null; session not observable) / `invoked` (null; no telemetry).
- `paths[]` variants: `{path, skill_path, scope, class, rank, protected:false, enabled, write_policy('writable'|'conditional'|'diagnostic-only'), model_invocable, user_invocable, dsh_valid, description, category, capabilities, frontmatter, sha256}`.
- Duplicate facts: `duplicate`, `metadata_conflict`, `precedence='within-layer-rank'`, `predicted_winner` (rank asc -> root order -> name order), `winner_confidence='single-candidate'|'within-layer-only'`, `runtime_winner=null`.
- Policy facts: `invocation{model_invocable,user_invocable}`, `protected=false` (DSH has no protected roots), `conditional`, `consumer`.
- Index extras: `dsh_preset{active_preset, settings_path, preset_path, provider_enabled, consumer, include_default_roots, custom_dirs, watch, evidence}`, `dsh_reserved_namespace[]`.

## Roots / ranks (verified Phase A facts)

project-dsh 100 (`<gitRoot>/.dsh/skills`), project-agents 200 (`<gitRoot>/.agents/skills`), custom 300 (preset `customSkillDirs`), user-dsh 400 (`$DSH_HOME/skills`, skips `.system`), user-agents 500 (`$DSH_AGENTS_HOME`/`~/.agents/skills`), bundled 600 (`bundledSkillDir`/`$DSH_BUNDLED_SKILL_DIR`). Directory bundles `<name>/SKILL.md` and flat `<name>.md`; project root = nearest `.git` ancestor else cwd.

## Detect logic

`detect.{ps1,sh}`: CLI resolution without execution (`executable_test=not-run`), env overrides `SKILL_MANAGER_DSH_*` first, `DSH_HOME`/`DSH_AGENTS_HOME`/`DSH_BUNDLED_SKILL_DIR` next, defaults. Preset state from `settings.yaml` (`agent-presets.default`) + `<DSH_HOME>/.agent-presets/<name>/agent.cordis.yml`: `provider_enabled` (skill-filesystem row), `consumer` (tool-skill / skill-search / none / unknown), `include_default_roots`, `customSkillDirs`, `watch`. `usable = cli_resolved || dsh_home_detected || provider_enabled`; never from `~/.agents/skills` alone.

## Writer/winner logic

- Within-layer predicted winner: variants sorted by `rank asc -> root order -> name asc`, first-wins; all paths retained; losers reported in doctor without removal.
- Cross-layer shadowing: not observable from disk -> `runtime_winner=null`; doctor prints the verified within-layer rule and states no runtime winner is claimed.
- Consumer gate: no mounted consumer -> `visible=false`, `conditional=true`; unknown consumer -> visible=eligible with `conditional=true`.

## Doctor rules

provider disabled / consumer missing (conditional) / invalid skill (kebab, required fields, legacy invocation keys) / duplicate with predicted winner / `.system` reserved namespace note / bundled write_policy=diagnostic-only / model-invocation restricted.

## Fix & write policy

`fix` targets exactly one writable variant: scope `user`, class `user-dsh`; refuses bundled (diagnostic-only), `.system` reserved, and cross-root ambiguity (project/custom = conditional, never auto-fixed). `protected` field stays false for all DSH variants per Phase A facts.

## Install targets

`-Scope user` (default -> `~/.dsh/skills`), `user-agents` (shared -> `~/.agents/skills`), `project` (-> `<gitRoot>/.dsh/skills`). `-LinkOnly` unsupported (direct roots). Backups under `$DSH_HOME/skill-manager/backups`. Never install into bundled/custom/`.system`.

## PowerShell/Bash tests (sandbox-only)

Temp `DSH_HOME`/`DSH_AGENTS_HOME`/`DSH_BUNDLED_DIR`, temp git repo, temp preset fixtures (settings.yaml + agent.cordis.yml): detection (incl. `~/.agents`-only != usable, fake CLI without execution), root discovery, duplicate 6-root fixture -> predicted winner project-dsh + all paths retained + precedence/confidence, `.system` skip, legacy-key and kebab rejection, flat `.md`, consumer gate (preset without tool-skill -> conditional invisible), model-disabled eligibility, fix refusal for bundled, find reuse.

## CI changes

Add `bash tests/test-deepseek-harness.sh` to `bash-tests` (ubuntu/macos) and `pwsh -NoProfile -File tests/test-deepseek-harness.ps1` to `powershell-tests` (windows), after the codex steps.

## Real read-only smoke plan

With env overrides (`SKILL_MANAGER_DSH_INDEX_PATH` -> temp, `SKILL_MANAGER_DSH_CWD` = repo): `detect`, roots listing, `refresh -Agent deepseek-harness` writing only the temp index, `find`/`show`/`doctor` against it. No writes to real `~/.dsh/skills`, `~/.agents/skills`, or project dirs.

## Plan self-review

- Mirrors the graduated Codex adapter (native multi-root + direct discovery), with DSH-specific verified semantics (rank rules, `.system` reserved namespace, invocation policy, provider+consumer detection).
- Every acceptance rule maps to at least one implementation point and one test assertion.
- No shared-scorer, Docker, telemetry, MCP, AGENTS.md, or Update/Remove surface is touched.