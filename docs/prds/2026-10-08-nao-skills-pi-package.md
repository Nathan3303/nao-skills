# PRD：nao-skills 单 SKILL 化 + pi 原生分发

> Issue：[#18](https://github.com/Nathan3303/nao-skills/issues/18) · 分支：`feat/18-pi-package` · 目标版本：**0.12.0**（MINOR，含兼容层）
> 状态：已开工（T1 前置验证中）· PM 维护 · 正文为权威（Issue 只放摘要与指针）

## 0. 背景与决策留痕

用户诉求：安装后机制平铺到 `.agents/` 下多个顶层目录，**不够内聚**，希望改成一个 SKILL。

澄清结论（2026-10-08）：

| 决策点 | 结论 | 理由 |
| --- | --- | --- |
| 主目标 | **pi 原生安装**（skill 走 pi package 分发） | 用户选择：不只目录内聚，要原生化安装/升级 |
| 安装作用域 | **项目级 `--local`**（`.pi/settings.json` 记录 pin 版本） | 团队 clone 即得、版本可 pin、CI 可复现 |
| 本次深度 | **分阶段：只原生化分发** | fleet 编排（1289 行 / 87 处 tmux / 62 处 pi·intercom）搬进 extension 会破坏无 pi 环境的 CI 体检，且生命周期模型与「常驻 pane」冲突 |
| 下游兼容 | **保留转发层** | 下游 4 仓（nao-todo / nao-todo-minimal / nao-todo-server / nue-ui）迁移期零改动 |
| 角色模型 | **不变**（6 会话） | SKILL 只做入口 + 说明书，不合并角色 |

## 1. 问题证据（实测）

| 证据 | 数据 |
| --- | --- |
| 安装后项目根平铺 6 项 | `.agents/{prompts,common,checklists,skills,templates,scripts}` + `AGENTS.md` |
| 无单一 AI 入口 | pi skill 列表中无舰队入口（仅第三方 `frontend-design`） |
| 自研安装器维护面 | `bin/nao-skill.js` 303 行（install / 合并 / 废弃清理） |
| 迁移成本 | 334 处 `.agents/…` 引用，散在 34 个文件（skills 98 / scripts 58 / checklists 54 / common 31 / prompts 20 / templates 16 / roles.yaml 12） |
| 兼容约束 | `README.md`：下游完整性判据 =「脚本与上游逐字节 sha 一致」；`check` 被 `npm test` / `prepack` / 下游 CI 调用 |

## 2. 目标指标

| 指标 | 现状 | 目标 |
| --- | --- | --- |
| 项目内机制足迹 | 6 项平铺 | ≤2 项：`.pi/settings.json` + `.agents/`（仅 shim） |
| AI 入口 | 无 | 普通 pi 会话可发现并加载舰队说明书 |
| 升级方式 | `nao-skill update` 覆盖项目内文件 | `pi install/update`；升级后项目 `git status` 干净 |
| 下游兼容 | — | 旧路径 100% 可用，下游仓零改动 |

## 3. 范围 / 非范围

| IN | OUT（本次不做） |
| --- | --- |
| pi package 化（`pi` manifest + 单 `SKILL.md`） | ❌ fleet 编排重写为 extension（独立 Issue） |
| 机制目录重排为包内命名空间 | ❌ 角色卡注入方式变更（**必须**保持常驻注入） |
| 薄 CLI：`init` / `exec` / 迁移 | ❌ 角色数量与职责变更 |
| `.agents/` 兼容转发 shim + 一次性迁移提示 | ❌ tmux 布局与闸门语义变更 |
| 334 处引用重写 + `check` 交叉引用绿 | ❌ 下游 4 仓的**实际改造**（仅只读兼容验证，改造另立 Issue） |
| README / ARCHITECTURE.md / 模板同步 | ❌ 移除兼容层（留给 1.0.0） |

## 4. 用户场景

| # | 场景 | 期望 |
| --- | --- | --- |
| S1 | 新项目接入 | `pi install --local npm:@nathan33/nao-skill@0.12.0` + `npx @nathan33/nao-skill init` → 2 项足迹，`check` 绿 |
| S2 | 老用户升级 | 迁移命令 → 旧机制文件备份 `.agents/.nao-obsolete/`、shim 就位、旧命令照跑、提示一次 |
| S3 | 团队 / CI | `.pi/settings.json` 带 pin 版本进仓库；CI 有明确机制获取步骤，结果与今天一致 |
| S4 | 普通 pi 会话 | 用户说「想加个导出功能」→ 路由到舰队 skill → 引导拉起舰队 |

## 5. 业务规则

| # | 规则 |
| --- | --- |
| BR1 | **角色仍是 6 个独立会话**；SKILL 只做入口与说明书，不合并角色 |
| BR2 | 角色卡**必须**继续 `--append-system-prompt` 常驻注入；不得改为按需 skill 加载（会丢红线常驻） |
| BR3 | 项目根 `AGENTS.md` 仍是项目级单一事实来源，由 PM 维护、pi 自动注入 |
| BR4 | 迁移期旧路径可用；每条旧路径提示迁移，每版本最多一次（禁刷屏） |
| BR5 | 机制文件单一事实来源在 npm 包内；项目内不存机制副本（shim 除外） |
| BR6 | `.pi/settings.json` 记录 pin 版本，不用浮动版本 |

## 6. NFRs（业务视角基线 → 待架构师转译技术指标并回执）

| # | 业务 NFR | 可接受下限 |
| --- | --- | --- |
| NFR1 | 迁移期下游可用性 | 下游 4 仓零改动，`check` 仍绿 |
| NFR2 | CI 可复现性 | 给定 pin 版本 + 明确步骤，结果与今天一致；**不允许隐式依赖网络**（需 arch 给方案） |
| NFR3 | 离线可用性 | **允许退化但必须显式**：可读错误 + 降级路径，不得静默失败 |
| NFR4 | 常驻 token 增量 | 仅 +1 条 skill description（≤1024 字符）；角色卡不回归膨胀 |
| NFR5 | 安装/升级耗时 | 不引入需人工介入的多步流程 |

> 依赖 V1–V3 验证结论 + arch 评审回执后定稿。

## 7. AC

| AC | 类型 | Given / When / Then |
| --- | --- | --- |
| AC1 | 主路径 | Given 干净项目，When `pi install --local` + `init`，Then 足迹 = `AGENTS.md` + `.pi/settings.json` + `.agents/`(shim)，且 `bash .agents/scripts/nao-fleet.sh check` exit=0 |
| AC2 | 主路径 | Given 普通 pi 会话（未跑 fleet），When 用户提需求，Then 舰队 skill 可被发现/加载，并给出「拉起舰队」指引 |
| AC3 | 异常 | Given pi 未装 / npm 不可达，When 执行 `init` 或 shim，Then 可读错误 + 降级指引 + 非 0 exit（不静默成功） |
| AC4 | 边界 | Given 已装旧版（全套 `.agents/` + `.nao-version`），When 迁移，Then 旧文件备份 `.agents/.nao-obsolete/`、shim 就位、旧路径全部可用、迁移提示仅一次 |
| AC5 | 负向闭环 | Given 下游 nao-todo 与 nue-ui（**不改任何文件**），When 跑 `check`/`ensure`，Then 正常；main 上本需求恰好 1 条提交、无 `wip()` |
| AC6 | 设计一致性 | Then 全仓 `.agents/**` 引用与 `check` 交叉引用校验一致；README / ARCHITECTURE.md / 模板与新形态对齐 |
| AC7 | 治理 | Then 作为一次明确基线变更发布：sha 基线变化说明 + 下游通知清单 + 迁移指引落 `docs/` |
| AC8 | 非范围守护 | Then diff 审查确认：角色数量、注入方式、闸门语义未变（BR1/BR2） |

## 8. 待验证项（前置，不验证不实现）

| # | 待验证 | 影响 |
| --- | --- | --- |
| V1 | pi 项目级 npm 包**实际落盘路径**；`PI_PACKAGE_DIR` 能否稳定解析 | 决定 shim / `exec` 实现 |
| V2 | skill 目录内 `references/*.md` 是否被登记为独立 skill | 决定 checklists 能否内聚（现行决策是「移出 skills/ 避注册」） |
| V3 | **无 pi 会话的 CI** 如何跑 `check`（npx 转发 / 本地缓存 / 最小副本） | 决定 NFR2 与下游 CI 影响面 |

## 9. 上线闭环 / 变更治理

| 项 | 内容 |
| --- | --- |
| 闭环 | Issue #18 → `feat/18-pi-package` Draft PR → CI 绿 → PM 核 AC → RD squash 合并 → tag `v0.12.0` + release notes → 下游通知 |
| 降级 | 无 `gh`/无远端时本地 `merge --squash`，流程不变，`tasks-state` 标注降级 |
| 治理 | shim 保留 **2 个 MINOR**；移除 = `1.0.0`；extension 化独立立项 |

## 10. 优先级

| 环节 | 结论 |
| --- | --- |
| 战略筛子 | **通过（工程基座类）**——不属于「Token 优先」主轴，不宣称 token 收益 |
| MoSCoW | Must：包化 + skill 入口 + 兼容 shim + 引用重写；Should：CLI 迁移命令；Could：pi gallery 元数据；Won't：extension 化 |
| RICE | R=6 · I=1（中）· C=0.6 · E=4 人周 → **≈0.9**（偏低 → 靠 T1 验证抬升 Confidence） |
| Kano | 目录内聚 = Must-be；skill 入口 = Attractive |
