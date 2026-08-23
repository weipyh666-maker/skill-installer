# Antigravity Environment Analysis

## 1. 安装状态与环境探测

- **Antigravity CLI 命令**：
  - Windows (PowerShell): 注册为函数 `antigravity`，调用 `D:\Antigravity\cli\bin\agy.exe --dangerously-skip-permissions @args`。
  - Bash / POSIX: `/c/Users/weipyh/bin/agy`（通过 PATH 访问 `agy`，支持 `antigravity` 别名/包装）。
- **核心数据与配置目录**：
  - 核心应用数据目录：`~/.gemini/antigravity-cli/`（包含 `bin/`, `brain/`, `builtin/`, `cache/`, `log/`, `mcp/`, `conversations/` 等）。
  - 用户全局配置目录：`~/.antigravity/`（包含 `argv.json`, `extensions/`）与 `~/.gemini/config/`。
  - 用户全局技能目录：`~/.agents/skills/`（实测已安装 210 个技能）。
  - 内置技能目录：`~/.gemini/antigravity-cli/builtin/skills/`（包含 `agy-customizations` 等内置体系）。

## 2. Skill 存储路径

- **Global Scope (全局范围)**：
  - 默认路径：`~/.agents/skills/`（Windows: `$env:USERPROFILE\.agents\skills`，POSIX: `$HOME/.agents/skills`）。
  - 自定义路径：支持在 `~/.gemini/config/skills.json` 中声明自定义 entries / inherits。
- **Project / Workspace Scope (项目工作区范围)**：
  - 默认路径：项目根目录下的 `.agents/skills/`（同时兼容 `.agent/skills/`、`_agents/skills/`、`_agent/skills/`）。
  - 声明路径：支持在工作区根目录 `.agents/skills.json` 中显式指定。

## 3. SKILL.md 格式规范与 Claude 兼容性

- **frontmatter 兼容 Claude**：**完全兼容（100% Compatible）**。
- **规范说明**（源自官方内置文档 `agy-customizations/docs/skills.md`）：
  - 每个 Skill 独立成文件夹：`<skills_dir>/<skill_name>/SKILL.md`。
  - 必须以 YAML frontmatter 开始：
    ```markdown
    ---
    name: <skill-name>
    description: >-
      Use when the user wants to...
    ---
    ```
  - **差异点与扩展点**：
    - `name`：全小写连字符命名（与 Claude 一致）。
    - `description`：用于意图匹配与自动触发判定（与 Claude 一致）。
    - 进阶子目录：原生支持 `scripts/`（辅助脚本）、`references/`（手册）、`examples/`（参考实现）、`resources/`（模板资源），与 Claude 生态结构完全一致。

## 4. 详细问题解答 (10 项清单)

| # | 问题 | 调查结论 |
|---|---|---|
| 1 | **Skill 存储路径（Global scope）** | `~/.agents/skills/`（环境变量支持 `ANTIGRAVITY_SKILLS_DIR` / `ANTIGRAVITY_SKILLS_LINK_DIR`） |
| 2 | **Skill 存储路径（Project scope）** | `<workspace_root>/.agents/skills/` 或 `.agents/skills.json` 声明路径 |
| 3 | **SKILL.md 格式** | 严格兼容标准 YAML frontmatter（`name` + `description` + `capabilities` + `category`） |
| 4 | **Skill discovery 机制** | 分层文件遍历 + 渐进式披露（启动/切目录时读取 frontmatter 摘要，调用时按需加载正文） |
| 5 | **自动触发机制** | 基于 LLM 决策与 description 意图匹配（`trigger: model_decision`） |
| 6 | **symlink / junction 支持** | 支持。Windows 下可使用 Junction / Symlink，POSIX 下使用 Symlink；亦支持直接复制安装 |
| 7 | **skills / rules / workflows 的关系** | Skills（按需工作流指引）、Rules（全局/项目规范约束）、Plugins（打包聚合单元）、Hooks（生命周期钩子） |
| 8 | **Claude Adapter 可复用逻辑** | 路径安全校验、原子备份、SHA256 校验、Catalog Schema v3、Find 语义检索算法、Doctor 8 规则引擎 **全部 100% 复用** |
| 9 | **需针对 Antigravity 修改之处** | `paths.sh/ps1` 适配 `~/.agents/skills` 目录；`detect.sh/ps1` 探测 `antigravity`/`agy`/`~/.agents`；Catalog 中 `agents.antigravity.visible` 设为真实探测 |
| 10 | **应增加的测试套件** | `tests/test-antigravity.sh` 与 `tests/test-antigravity.ps1`，验证 Antigravity 路径解析、安装、可见性与 Catalog 操作 |

## 5. 关键设计问题分析

- **Antigravity 是否支持 `skill install` 命令行？**
  - Antigravity 自身 CLI 提供了 `agy plugin install`，但针对独立 Skill，其原生机制依赖自动发现。`skill-manager` 的 `install` 命令（支持 GitHub 仓库拉取、分支/commit/tag 解析、SHA256 验签、原子备份与软链接）能够为 Antigravity 补充专业级 Skill 包管理能力。
- **Antigravity 安装 Skill 是否需要重启？**
  - 在新会话或切换目录时自动装载；对当前会话，已链接的技能文件可直接通过文件读取工具热加载。
- **Antigravity 的 description 是否会被自动触发引用？**
  - **是**。Antigravity 系统提示词采用渐进式披露，系统常驻列表仅包含各 Skill 的 `name` 与 `description`，Agent 依据 `description` 质量判断何时调用对应 Skill。
- **Antigravity 环境变量规范**：
  - 建议支持 `ANTIGRAVITY_SKILLS_DIR` 与 `ANTIGRAVITY_SKILLS_LINK_DIR`，默认回退到 `~/.agents/skills`。

## 6. 实施建议 (Implementation Plan for Phase B)

1. **`adapters/antigravity/paths.sh` & `paths.ps1`**：
   - 默认源目录：`$HOME/.agents/skills` / `$env:USERPROFILE\.agents\skills`
   - 默认链接目录：`$HOME/.agents/skills` / `$env:USERPROFILE\.agents\skills`
   - 支持环境变量 `ANTIGRAVITY_SKILLS_DIR` 与 `ANTIGRAVITY_SKILLS_LINK_DIR` 覆盖。
2. **`adapters/antigravity/detect.sh` & `detect.ps1`**：
   - 检查 `command -v antigravity`、`command -v agy` 或 `~/.agents/skills` 目录是否存在。若存在返回 `installed=true`。
3. **移除 Stub 拦截**：
   - 移除 `adapters/antigravity/stub-note.md`，替换为 Antigravity 适配说明文档。
   - 在 `adapters/_base.sh` / `_base.ps1` 以及 `lib/catalog.sh` / `catalog.ps1` 中开放 `antigravity` adapter（与 `claude` 具备同等第一公民能力）。
4. **Catalog 多 Agent 可见性检测 (`agents.antigravity.visible`)**：
   - 在 `scan_entries` 与 `build_index` 时，检查 `$ANTIGRAVITY_SKILLS_LINK_DIR/<skill-name>` 是否存在有效且健康的 `SKILL.md`。
   - 若存在则 `agents.antigravity.visible = true`，否则为 `false`。
5. **双平台自动化测试**：
   - 编写 `tests/test-antigravity.sh` 与 `tests/test-antigravity.ps1`，并在 `.github/workflows/ci.yml` 中集成测试矩阵。
