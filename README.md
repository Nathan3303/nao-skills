# nao-skills

Agent skills, role prompts and fleet automation for multi-agent development with [pi](https://pi.dev). Made by [Nathan Lee](https://github.com/nathan).

## Skills

Domain-Driven Design guides used by the role prompts. Each skill is a self-contained `SKILL.md` invoked on demand.

| Skill | Applies to | Core content |
| --- | --- | --- |
| [`nao-frontend-ddd`](.agents/skills/nao-frontend-ddd/SKILL.md) | Vue 3 / React + TypeScript | Progressive 3-level DDD framework (L1 lightweight → L2 basic DDD → L3 full DDD), per-domain stores + UseCases, red lines |
| [`nao-golang-ddd`](.agents/skills/nao-golang-ddd/SKILL.md) | Golang backend | 4-layer architecture with dependency inversion, pragmatic leveling (transaction script / L1–L3), Go idioms and red lines |
| [`backend-ddd`](.agents/skills/backend-ddd/SKILL.md) | NestJS / Spring Boot | Backend DDD architecture guide for JVM/Node stacks: new domains, project refactors, structural conventions |

## Prompts

Role prompts in `.agents/prompts/`. Use as a role system prompt in a session (e.g. `--append-system-prompt .agents/prompts/product-manager.md`), reference inline with `@.agents/prompts/<name>.md`, or load as a template.

| Prompt | Role | Highlights |
| --- | --- | --- |
| [`product-manager`](.agents/prompts/product-manager.md) | 产品经理（调度者） | 需求全生命周期：grill-me 澄清、9 模块 PRD、RICE 优先级、AC 五覆盖、零代码红线；§12 pi-intercom 多会话调度（开工确认卡 → fleet.sh 拉起 → send/ask 派发 → 验收闭环），§13 docs/prds 交付归档 |
| [`architecture-designer`](.agents/prompts/architecture-designer.md) | 系统架构师（评审/咨询） | 分布式系统架构设计：业务驱动五原则、技术选型四步法、架构模式速查、交付红线与检查清单 |
| [`frontend-developer`](.agents/prompts/frontend-developer.md) | 前端研发（RD） | 基于 `nao-frontend-ddd`：五层分层、DDD 等级选择、代码审查红线（通用/Vue/React）、序列化边界 |
| [`backend-developer`](.agents/prompts/backend-developer.md) | 后端研发（RD） | 基于 `nao-golang-ddd`：Go 标准布局与依赖倒置、事务脚本 / L1–L3 决策、手工 DI、哨兵错误、上下文传递 |
| [`test-engineer`](.agents/prompts/test-engineer.md) | 测试工程师（QA） | 质量保障全流程、测试金字塔与 DDD 分层对齐、AC=测试用例、CI/CD 门禁 |

## Scripts

### `nao-fleet.sh`

按角色一键拉起 pi 会话窗口，供产品经理在开工确认后自动补齐缺线的 RD/架构师/QA 会话（见 `product-manager.md` §12「舰队启动」）。

```bash
scripts/nao-fleet.sh status                                    # 列出本机可识别的角色会话
scripts/nao-fleet.sh ensure arch rd-fe                         # 拉起缺失角色（工作区=当前目录）
scripts/nao-fleet.sh ensure rd-be@/path/to/nao-todo-server     # 前后端分离：显式指定后端 repo
scripts/nao-fleet.sh ensure -m deepseek-v4-flash:high arch     # 仅当用户指定模型时才传 --model
```

- 角色别名 → 角色卡：`pm`→product-manager、`arch`/`arch-designer`→architecture-designer、`rd-fe`→frontend-developer、`rd-be`→backend-developer、`qa`→test-engineer。
- 角色卡经 `--append-system-prompt` 在启动期注入；`--name` 注册 intercom 身份（名字+工作区）。
- **模型纪律**：默认不传 `--model`（走 pi 全局默认），不继承 PM 自身模型，仅在显式 `-m` 时拼参数。
- 终端宿主自动探测 `ghostty → ptyxis → screen`；无 GUI 环境用 `NAO_TERMINAL=screen` 后台运行（`screen -r nao-<别名>` 附着）。
- 内置 `--name` 判重跳过（`--force` 覆盖）；权威在线名单仍以 `intercom({ action: "list" })` 为准。

## Project Structure

```text
nao-skills/
├── .agents/
│   ├── skills/                 # Agent skills (DDD guides)
│   │   ├── nao-frontend-ddd/   # Frontend DDD (Vue/React)
│   │   │   └── SKILL.md
│   │   ├── nao-golang-ddd/     # Golang DDD
│   │   │   └── SKILL.md
│   │   └── backend-ddd/        # Backend DDD (NestJS / Spring Boot)
│   │       └── SKILL.md
│   ├── prompts/                # Role prompts (PM / architect / RD / QA)
│   │   ├── product-manager.md
│   │   ├── architecture-designer.md
│   │   ├── frontend-developer.md
│   │   ├── backend-developer.md
│   │   └── test-engineer.md
│   └── commands/               # Slash commands
│       ├── commit.md
│       ├── nao-frontend-review.md
│       └── nao-golang-review.md
├── scripts/
│   └── nao-fleet.sh            # Role session launcher (multi-session fleet)
└── package.json
```

## License

MIT © 2026 Nathan Lee
