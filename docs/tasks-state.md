# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 归档后的历史见 `docs/prds/` 与 `docs/adr/`；本文件只记**运行时**任务状态，保持精简。

## PM 接续快照（会话重开后**先读本区**）

- 当前阶段：**T1 已验收 → 待 arch 终签（T2 放行闸门）**
- 当前 PRD：`docs/prds/2026-10-08-nao-skills-pi-package.md`（状态：已开工）
- 未决决策点：**T2 放行**待 arch 终签（依据：T1 报告 + 用户两项决策 + PM 裁定 5 项）
- 待用户回答：无（A′ 包内布局、`.pi/npm` gitignore 均已拍板）
- 未派发队列：见下方「待派发队列」（#18 共 3 项 + 独立批次 1 项）
- 下次唤醒条件：worker 回执 T0 终签（arch）
- ⚠️ 环境注意：`nao-fleet.sh` 别名解析有缺陷（#19）——`ensure` **必须用 canonical id**（`arch-designer` / `rd-infra`），`arch` / `infra` 会报未知角色
- 口头约束已落盘：PRD §5 业务规则（BR1/BR2 角色模型与常驻注入不变）· §9 变更治理（shim 保留 2 个 MINOR，移除 = 1.0.0）
- 会话体检：contextTokens≈120k（窗口 1000k · 12%）· 压缩次数=0 · cacheRead=待观测

### 已拍板决策（2026-10-08）

| # | 决策点 | 结论 | 来源 |
| :--- | :--- | :--- | :--- |
| D1 | 包内目录布局 | **A′ 保留 `.agents/` 包内命名空间**（引用零重写、`check_cross_refs` 天然绿） | 用户 |
| D2 | `.pi/npm/` Git 策略 | **gitignore**（足迹更干净）；代价 = 「clone 即得」不成立，需一条显式物化命令；将来下游若要 CI 跑 `check` 可再 `git add -f` lockfile | 用户 |
| D3 | `frontend-design` skill 归属 | **随包声明两个 skill** → 注册数 1→2，**增量仍恰 +1**（NFR4 不变） | PM 裁定 |
| D4 | 下游 CI 门禁 | **维持现状 0 改动**（实测 4 仓 CI 不调用 `check`） | PM 裁定 |
| D5 | 不可运行退出码 | **`exit 2` + 单行 `DEGRADED:`**（与「能跑但失败 = 1」区分）；rd-infra 建议的 70 不采纳 | PM 裁定 |
| D6 | shim 解析顺序 | `NAO_SKILLS`（显式覆盖）→ `.pi/npm`（项目 pin，主）→ `~/.pi/agent/npm`（个人兜底，须校验版本 == pin）→ 显式失败 | PM 裁定 |
| D7 | shim 防重入 | **硬要求**：marker env 守卫，命中即报错退出（否则下游 `AGENTS.md` 环境锚点把 `NAO_SKILLS` 记为项目根时会无限递归） | PM 发现 |
| D8 | 环境锚点迁移 | 迁移时必须同步更新 4 仓 `AGENTS.md` 的 `NAO_SKILLS` 环境锚点（旧值迁移后失效） | PM 发现 |

### 实测纠正（作废的早前判断）

- 早前称「下游 CI 依赖 `check`」→ **作废**。实测 4 仓 workflows grep `nao-fleet|nao-skill|.agents` **0 命中**（arch E5 + rd-infra T1 §4 独立复核）→ NFR2 真实影响面 = 0。
- 迁移面确认：4/4 下游已装 `.agents/` + `AGENTS.md`（nao-fleet 引用：nao-todo 14 / server 7 / nue-ui 7 / minimal 0）。

## 需求分支 / PR / 发布（PM 维护）

- Issue：[#18](https://github.com/Nathan3303/nao-skills/issues/18)
- 需求分支：`feat/18-pi-package`（已起）
- PR owner / Reviewer：rd-infra / **arch-designer**
- PR：[#20](https://github.com/Nathan3303/nao-skills/pull/20)（Draft）· 预览环境：无
- 合并：未合并 · 分支已删：否
- 版本 / Tag：v0.12.0 · 待发布
- 降级标注：无（`gh` 可用，exit 0）
- 特例提交（白名单）：无

## 待派发队列

| 任务编号 | 目标会话 | 概要 | 排队原因 |
| :--- | :--- | :--- | :--- |
| T2 | rd-infra | pi package 化：`pi` manifest（按**文件**声明 skill）+ `SKILL.md` + 包内布局 A′ + 薄 CLI（`init`/`exec`/`migrate`）+ 兼容 shim | **待 arch 终签放行** |
| T3 | rd-infra | 迁移治理：4 仓只读验证 + ADR/README/ARCHITECTURE 同步 + release notes + 环境锚点更新指引 | 依赖 T2 |
| T4 | qa | 按 AC 出用例（含 AC3 异常 / AC4 边界 / AC5 只读兼容验证 / NFR2 无网络口径） | 待 T2/T3 并行窗口 |
| #19 | rd-infra | 修角色别名解析（`ALIAS_ROLE` 键值写反）+ `check` 增加「别名可解析」回归守卫 | **独立批次**：需用户另行确认开工（不阻塞 #18） |

## 进行中

| 任务编号 | 目标会话 | 概要 | 派发时间 | 对应 AC | WIP 提交 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| — | — | — | — | — | — |

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |
| T0（终签） | arch 终签请求已发（T1 证据 + D1–D8 + NFR2/NFR3 改写提案） | 回执内容 | 等 done(full) 后放行 T2 |

## 挂起（被抢占 / 降级）

| 任务编号 | 挂起原因 | 恢复方式 |
| :--- | :--- | :--- |
| — | — | — |

## 已验收 / 已归档

| 任务编号 | 结论 | 详情路径 | 备注 |
| :--- | :--- | :--- | :--- |
| T0 | 架构评审回执：**有条件可行**；定 AC1/AC3 形态；§8 六项拍板点（D1–D6 已拍） | 回执内容（未落盘，ADR 要点待转） | 转入终签 |
| T1 | **验收通过**：V1 包落盘路径确定 + `PI_PACKAGE_DIR` 不可用；V2 含 `SKILL.md` 即停递归 ⇒ `references/*.md` 不注册；V3 推荐 `.pi/npm` + 显式 `npm ci`；下游 CI 0 调用 | `docs/reports/2026-10-08-T1-pi-package-verify.md` | 本仓仅 +1 文件、下游 4 仓 0 条（已独立复核）；`/tmp/t1` 临时目录待清理 |
