# nao-skills

Agent skills collection for OpenCode / Sisyphus. Made by [Nathan Lee](https://github.com/nathan).

## Skills

### `nao-frontend-ddd`

Frontend Domain-Driven Design architecture guide based on **Vue 3 + TypeScript / React + TypeScript**. Provides a progressive 3-level DDD framework:

| Level                     | Scope                | Key Patterns                               |
| ------------------------- | -------------------- | ------------------------------------------ |
| **Level 1** — Lightweight | < 5k LOC, 1–2 devs   | Composable-based business logic            |
| **Level 2** — Basic DDD   | 5k–20k LOC, 3–5 devs | Per-domain stores (Pinia/Zustand) + UseCase |
| **Level 3** — Full DDD    | > 20k LOC, monorepo  | Domain / Application / Presentation layers |

When invoked, the skill assesses project size, selects the appropriate DDD level, and provides the minimal structure and code patterns with clear graduation criteria for when to level up.

See [nao-frontend-ddd/SKILL.md](.agents/skills/nao-frontend-ddd/SKILL.md) for the full architecture guide, patterns, and migration paths.

### `my-nueui`

Build Vue 3 business components and pages with the **NueUI** component library (~30+ components). Covers the full component catalog with progressive building levels:

| Level       | Scope                               | Deliverable                                   |
| ----------- | ----------------------------------- | --------------------------------------------- |
| **Level 0** | Single component                    | One `<nue-*>` tag with correct props          |
| **Level 1** | Simple composition (2–3 components) | Small UI fragment                             |
| **Level 2** | Form building                       | Login, settings, filter forms                 |
| **Level 3** | Layout composition                  | Admin panels, card grids, multi-section pages |
| **Level 4** | Overlay composition                 | Modals, drawers, tooltips, dropdowns          |
| **Level 5** | Full business components            | Complete features with all states             |

Includes theming, dark mode (single CSS variable toggle), iconfont, and design token usage.

See [my-nueui/SKILL.md](.agents/skills/my-nueui/SKILL.md) for the full guide, component catalog, and business recipes.

## Prompts

### `frontend-developer`

前端开发工程师角色 Prompt，基于 `nao-frontend-ddd` 技能生成：定义五层分层架构、DDD 等级选择工作流、代码审查红线（通用/Vue/React）、序列化边界、职责分工、代码骨架、迁移路径与交付检查清单。可作为角色系统提示词，或作为 `/frontend-developer` 模板复用。

See [frontend-developer.md](.agents/prompts/frontend-developer.md).

### `backend-developer`

后端开发工程师角色 Prompt，基于 `nao-golang-ddd` 技能生成：定义 Go 标准布局与依赖倒置、决策工作流（事务脚本 / Level 1–3）、代码审查红线、Go 特有落地约定（手工 DI、哨兵错误、零值工厂、context 传递）、职责分工、代码骨架、演进条件与交付检查清单。可作为角色系统提示词，或作为 `/backend-developer` 模板复用。

See [backend-developer.md](.agents/prompts/backend-developer.md).

### `product-manager`

产品经理角色 Prompt：覆盖需求全生命周期（收集 → 分析 → 优先级 → PRD → 评审 → 跟进 → 验收复盘），含 PRD 8 模块、优先级框架（RICE / MoSCoW / Kano）、用户故事与验收标准、需求红线与交付检查清单，并与仓库 DDD 技能对齐（需求语言转领域语言、验收标准可测试化）。可作为角色系统提示词，或作为 `/product-manager` 模板复用。

See [product-manager.md](.agents/prompts/product-manager.md).

### `test-engineer`

测试工程师角色 Prompt：覆盖质量保障全流程（计划 → 用例设计 → 评审 → 执行 → 缺陷管理 → 回归 → 报告），含测试金字塔与 DDD 分层对齐表、用例设计方法（等价类/边界值/判定表/场景法）、缺陷生命周期与分级、自动化与 CI/CD 门禁，并与产品（AC=测试用例）和研发（领域测试）对齐。可作为角色系统提示词，或作为 `/test-engineer` 模板复用。

See [test-engineer.md](.agents/prompts/test-engineer.md).

## Project Structure

```text
nao-skills/
├── .agents/
│   ├── skills/                 # Agent skills
│   │   ├── nao-frontend-ddd/   # Frontend DDD architecture skill
│   │   │   └── SKILL.md        # Main skill definition
│   │   ├── my-nueui/           # NueUI component library skill
│   │   │   ├── SKILL.md        # Main skill definition
│   │   │   └── reference/      # Component & API reference docs
│   │   │       ├── components-*.md
│   │   │       ├── recipes.md
│   │   │       ├── programmatic-api.md
│   │   │       ├── theme-packages.md
│   │   │       └── ...
│   │   ├── backend-ddd/        # Backend DDD skill
│   │   └── nao-golang-ddd/     # Golang DDD skill
│   ├── prompts/                # Role prompts
│   │   ├── frontend-developer.md
│   │   ├── backend-developer.md
│   │   ├── product-manager.md
│   │   └── test-engineer.md
│   └── commands/               # Slash commands
│       └── commit.md
└── package.json
```

## License

MIT © 2026 Nathan Lee
