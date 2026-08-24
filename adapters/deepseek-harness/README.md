# DeepSeek Harness Adapter (Experimental)

DeepSeek Harness discovers Skills from multiple roots scanned by its `skill-filesystem` provider:

| Rank | Source | Root |
| --- | --- | --- |
| 100 | `project-dsh` | `<gitRoot>/.dsh/skills` |
| 200 | `project-agents` | `<gitRoot>/.agents/skills` |
| 300 | `custom` | preset `customSkillDirs` |
| 400 | `user-dsh` | `$DSH_HOME/skills` (default `~/.dsh/skills`) |
| 500 | `user-agents` | `$DSH_AGENTS_HOME/skills` (default `~/.agents/skills`) |
| 600 | `bundled` | `bundledSkillDir` / `$DSH_BUNDLED_SKILL_DIR` |

The project root is the nearest ancestor containing `.git`; without one the working directory itself is used. Directory bundles (`<name>/SKILL.md`) and flat Markdown files (`<name>.md`) are scanned as direct children of each root; nested `**/SKILL.md` discovery is not supported. The user-dsh root skips its reserved `.system` namespace, which is **not** a system-skill root and is never scanned or indexed.

**Status: Experimental.** Tested against DeepSeek Harness `0.1.0-rc.5`. DeepSeek Harness is a pre-release (`0.1.0-rc.x`) platform whose on-disk formats may change; this adapter records preset composition evidence (`dsh_preset.evidence`) rather than a harness version string, and never claims "Supported".

## Verified semantics implemented here

- **Rank is a within-layer tiebreak, not a global precedence.** Duplicates inside one provider layer resolve by rank (asc) -> provider registration order -> provider local order, first-wins. For the `skill-filesystem` provider the registration order is the filesystem root order (`root_order`), so the within-layer winner is deterministic from disk. Across scope layers the nearest layer wins; that cross-layer runtime outcome is **not observable from disk**, so the catalog reports a `predicted_winner` with `winner_basis='filesystem-rank-root-order'`, `winner_confidence='within-layer-only'` (or `'single-candidate'`), and keeps `runtime_winner=null`. `precedence='within-layer-rank'` is never a global precedence claim. Every path of a duplicate is retained.
- **Six-layer distinction** is preserved in the schema: filesystem root (variants' `scope`/`class`/`rank`), provider (`providers`), registry candidate (each `paths[]` variant), catalog visibility (`visible`/`expected_visible`), model selection (`eligible`, `model_invocable`), and loaded skill (`invoked`, always null — DSH provides no invocation telemetry). `confirmed_visible` is null because the session catalog of another process is not observable, so every catalog-visible entry carries `visibility_confidence='inferred'` and `visibility_status='expected'`; Doctor prose says "expected to be visible", never "visible in DeepSeek Harness" unless a live session confirms it.
- **Invocation policy** comes from frontmatter: `disable-model-invocation` / `user-invocable`. Legacy keys `disableModelInvocation` / `modelInvocable` / `userInvocable` make DSH reject the whole skill; the adapter marks such variants `dsh_valid=false`. Skill names must match kebab-case `^[a-z0-9]+(?:-[a-z0-9]+)*$`.
- **Provider and consumer state are detected** from `$DSH_HOME/settings.yaml` (`agent-presets.default`) and `<DSH_HOME>/.agent-presets/<name>/agent.cordis.yml`: `provider_enabled` (skill-filesystem row) and the mounted consumer (`tool-skill` catalog / `skill-search` search tool / `none` / `unknown`). Without a mounted consumer, skills are discoverable but not catalog-visible (`conditional=true`).
- **No protected roots; platform protection and manager write policy are separate dimensions.** DSH defines no write-protection API, so the boolean `protected` stays `false` for every variant. A separate `platform_protected` string records what DSH has *defined*: `'false'` for user/project roots DSH scans as unprotected, `'unknown'` for `bundled` and `custom` roots whose mutability DSH has not defined. skill-manager's own write policy is a third field, `write_policy`: `writable` (user-dsh), `writable/shared` (user-agents, shared with other agent platforms), `conditional` (project-dsh / project-agents), `diagnostic-only` (custom / bundled — diagnose only, never auto-fixed), and `refuse` (the reserved `.system` namespace, enforced at install/fix target checks). Manager policy is never presented as a DSH official fact.

## Detection

`detect.{ps1,sh}` resolves the CLI without executing it (`executable_test=not-run`) and reports DSH-specific state on two stages so "something DSH-shaped exists" is not confused with "the skill runtime is ready":

- `detected = cli_detected OR package_detected OR dsh_home_detected OR config_detected`
- `skill_runtime_ready = provider_enabled AND consumer_detected` (`tool-skill` / `skill-search`)
- `usable = detected AND skill_runtime_ready`

A bare `~/.agents/skills` shared directory never makes DeepSeek Harness usable, and a `~/.dsh` home with no active preset provider+consumer yields `usable=false` with `usable_reason` explaining which stage failed. `package_detected` is a best-effort local `node_modules/@deepseek-ai/dsh*` marker probe (overridable via `SKILL_MANAGER_DSH_PACKAGE_DETECTED`); the CLI is never executed.

Environment overrides (tests and diagnostics): `SKILL_MANAGER_DSH_HOME`, `SKILL_MANAGER_DSH_AGENTS_HOME`, `SKILL_MANAGER_DSH_BUNDLED_DIR`, `SKILL_MANAGER_DSH_CWD`, `SKILL_MANAGER_DSH_INDEX_PATH`, `SKILL_MANAGER_DSH_CLI_PATH`, `SKILL_MANAGER_DSH_SETTINGS_PATH`, `SKILL_MANAGER_DSH_PRESET`, `SKILL_MANAGER_DSH_USER_HOME`; the native `DSH_HOME`, `DSH_AGENTS_HOME`, `DSH_BUNDLED_SKILL_DIR` are honored next.

## Install targets

`install.{ps1,sh} -Agent deepseek-harness` supports `-Scope user` (default, `~/.dsh/skills`), `user-agents` (shared `~/.agents/skills`), and `project` (`<gitRoot>/.dsh/skills`). `-LinkOnly` is not supported (DSH uses direct discovery roots). Backups go to `$DSH_HOME/skill-manager/backups`, outside all discovery roots. Install and `fix` refuse bundled roots and the reserved `.system` namespace.