# nao-skills

Agent skills, role prompts and fleet automation for multi-agent development with [pi](https://pi.dev). Made by [Nathan Lee](https://github.com/nathan).

## Skills

按需技能，位于 `.agents/skills/`，由角色卡在需要时读取（`@.agents/skills/<name>.md`）。

| Skill | Applies to | Core content |
| --- | --- | --- |
| `frontend-ddd-details.md` | Vue 3 / React + TS | 前端 DDD 落地细节：骨架、场景速决、命名、误区 |
| `backend-ddd-details.md` | Golang | 后端 DDD 落地细节：代码骨架、事务、事件、命名、误区 |
| `arch-patterns.md` | 架构 | 架构模式速查、ADR 模板 |
| `pm-rice.md` | 产品 | RICE 优先级打分 |
| `pm-grill.md` | 产品 | grill-me 需求澄清 |
| `test-design.md` | 测试 | 用例设计、缺陷管理、DDD 分层对齐 |
| `commit.md` | 全角色 | 仅执行 git commit 前读取 |
| `checklists/*.md` | 全角色 | 红线 + 交付检查清单（**按需**：交付/评审前读取，不常驻，省 token） |

常驻规范在 `.agents/common/`：`output-format.md`（输出/回执模板、反模式）、`intercom-protocol.md`（多会话协议、终态回执、卡片版本同步、缓存与 Token 纪律）。

## Prompts

Role prompts in `.agents/prompts/`. Use as a role system prompt in a session (e.g. `--append-system-prompt .agents/prompts/product-manager.md`), reference inline with `@.agents/prompts/<name>.md`, or load as a template.

| Prompt | Role | Highlights |
| --- | --- | --- |
| [`product-manager`](.agents/prompts/product-manager.md) | 产品经理（调度者） | 需求全生命周期：grill-me 澄清、9 模块 PRD、RICE 优先级、AC 五覆盖、零代码红线；§六 pi-intercom 多会话调度（开工确认卡 → 架构评审闸门 → fleet.sh 拉起 → send/ask 派发 → 终态回执闸门 → 验收闭环），§十 docs/prds 交付归档 |
| [`architecture-designer`](.agents/prompts/architecture-designer.md) | 系统架构师（评审/咨询） | 分布式系统架构设计：业务驱动五原则、技术选型四步法、架构模式速查、交付红线与检查清单；§十 评审签字（含终态回执 PM）+ §十一 ADR 归档；§十四 降级 |
| [`frontend-developer`](.agents/prompts/frontend-developer.md) | 前端研发（RD） | 基于 `frontend-ddd-details`：五层分层、DDD 等级选择、代码审查红线（通用/Vue/React）、序列化边界 |
| [`backend-developer`](.agents/prompts/backend-developer.md) | 后端研发（RD） | 基于 `backend-ddd-details`：Go 标准布局与依赖倒置、事务脚本 / L1–L3 决策、手工 DI、哨兵错误、上下文传递 |
| [`test-engineer`](.agents/prompts/test-engineer.md) | 测试工程师（QA） | 质量保障全流程、测试金字塔与 DDD 分层对齐、AC=测试用例、CI/CD 门禁 |

## Scripts

### `nao-fleet.sh`（`.agents/scripts/`）

按角色一键拉起 pi 会话窗口、查看在线状态、静态体检，供产品经理在开工确认后自动补齐缺线的 RD/架构师/QA 会话（见 `product-manager.md` §六「舰队启动」）。角色 id / 别名 / 卡片映射以 `.agents/roles.yaml` 为单一事实来源。脚本与角色卡同处 `.agents/` agent 工作区：

```bash
.agents/scripts/nao-fleet.sh status                                    # 列出本机可识别的角色会话
.agents/scripts/nao-fleet.sh ensure arch rd-fe                         # 拉起缺失角色（工作区=当前目录）
.agents/scripts/nao-fleet.sh ensure rd-be@/path/to/nao-todo-server     # 前后端分离：显式指定后端 repo
.agents/scripts/nao-fleet.sh ensure -m deepseek-v4-flash:high arch     # 仅当用户指定模型时才传 --model
```

- 角色别名 → 角色卡：见 `.agents/roles.yaml`（当前 `pm` / `arch`(arch-designer) / `rd-fe` / `rd-be` / `qa`）。
- `check` 校验：roles.yaml 可解析、卡片 frontmatter（role/version/updated）与 manifest 一致、`@.agents/...` 交叉引用文件齐备、白名单与布局合法性。
- `status` 展示各角色在线状态（pgrep `--name` 探测；权威名单以 `intercom({ action: "list" })` 为准）。
- 角色卡经 `--append-system-prompt` 在启动期注入（含环境锚点：本机绝对路径，供跨仓库会话解析 `@` 引用兜底）；`--name` 注册 intercom 身份（名字+工作区）。
- **模型纪律**：默认不传 `--model`（走 pi 全局默认），不继承 PM 自身模型，仅在显式 `-m` 时拼参数。
- 终端宿主自动探测 `ghostty → ptyxis → screen`；无 GUI 环境用 `NAO_TERMINAL=screen` 后台运行（`screen -r nao-<别名>` 附着）。
- 内置 `--name` 判重跳过（`--force` 覆盖）；权威在线名单仍以 `intercom({ action: "list" })` 为准。

## Project Structure

```text
nao-skills/
├── .agents/
│   ├── common/                 # 常驻规范（全部角色引用）
│   │   ├── output-format.md    # 输出/回执模板、反模式
│   │   └── intercom-protocol.md# 多会话协议、终态回执、卡片版本同步
│   ├── skills/                 # 按需技能（角色卡内 @ 引用，不常驻）
│   │   ├── checklists/         # 红线+交付检查清单（交付前读取，省常驻 token）
│   │   │   ├── pm.md
│   │   │   ├── architecture-designer.md
│   │   │   ├── rd-be.md
│   │   │   ├── rd-fe.md
│   │   │   └── qa.md
│   │   ├── frontend-ddd-details.md
│   │   ├── backend-ddd-details.md
│   │   ├── arch-patterns.md
│   │   ├── pm-rice.md
│   │   ├── pm-grill.md
│   │   ├── test-design.md
│   │   └── commit.md
│   ├── prompts/                # 角色卡（frontmatter: role/version/updated）
│   │   ├── product-manager.md
│   │   ├── architecture-designer.md
│   │   ├── frontend-developer.md
│   │   ├── backend-developer.md
│   │   └── test-engineer.md
│   ├── roles.yaml              # 角色清单（aliases→id→card，单一事实来源）
│   └── scripts/                # Agent operation scripts
│       └── nao-fleet.sh        # 角色会话拉起 / 在线状态 / 静态体检
└── package.json
```

## License

MIT © 2026 Nathan Lee
