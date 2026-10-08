# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 归档后的历史见 `docs/prds/` 与 `docs/adr/`；本文件只记**运行时**任务状态，保持精简。

## PM 接续快照（会话重开后**先读本区**）

- 当前阶段：**T2 实施中**（T4 用例并行；ADR 落盘中）
- 当前 PRD：`docs/prds/2026-10-08-nao-skills-pi-package.md`（状态：已开工 · **§11 决策台账 + §12 实施闸门已定稿**）
- 未决决策点：无（D1–D8 全部拍板；arch 终签已放行 T2）
- 待用户回答：无
- 未派发队列：见下方「待派发队列」（T3 + 独立批次 #19）
- 下次唤醒条件：worker 回执 **T2**（rd-infra）/ **T4**（qa）
- ⚠️ 环境注意：`nao-fleet.sh` 别名解析有缺陷（#19）——`ensure` **必须用 canonical id**；`arch` / `infra` 会报未知角色
- 口头约束已落盘：PRD §5（BR1/BR2 角色模型与常驻注入不变）· §§11–13（决策台账 + 闸门 + 特例）
- 会话体检：contextTokens≈150k（窗口 1000k · 15%）· 压缩次数=0 · cacheRead=待观测

### 已拍板决策（2026-10-08）

见 PRD §11 决策台账（D1–D8）+ §12 实施闸门（A–D）+ §13 特例与待办。摘要：

| # | 决策 | 结论 |
| :--- | :--- | :--- |
| D1 | 包内布局 | **A′ 保留 `.agents/` 包内命名空间**（引用零重写）— 用户 |
| D2 | `.pi/npm/` Git | **gitignore**（代价：clone 即得不成立）— 用户 |
| D3 | skill 声明 | 按**文件**声明两个 → 注册数 1→2，增量恰 +1 |
| D4 | 下游 CI | 维持 **0 改动** |
| D5 | 不可运行退出码 | **`exit 2` + 单行 `DEGRADED:`** |
| D6 | shim 解析序 | `NAO_SKILLS` → `.pi/npm`(pin) → `~/.pi/agent/npm`(校验版本) → 显式失败 |
| D7 | shim 防重入 | **硬要求**（marker env + 包根≠自身项目根 双重防护） |
| D8 | 环境锚点 | 落点**三处**：fleet `build_system_prompt()` 语义 + 模板/角色卡表述 + **不主动写下游 AGENTS.md** |

### 实测纠正（已在 PRD §11 留痕）

- 「下游 CI 依赖 `check`」→ **作废**（4 仓 workflows 0 命中）。
- 「下游 `AGENTS.md` 记录 `NAO_SKILLS` 环境锚点」→ **作废**（4 仓 AGENTS.md 中 0 次；锚点由 fleet 注入**系统提示**，且 fleet 不 export `NAO_SKILLS`）。D7 守卫仍保留（防 stale 导出）。

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
| T3 | rd-infra | 迁移治理：4 仓只读验证 + 连带同步清单（ADR/README/ARCHITECTURE/索引）+ release notes + `nao-todo-minimal` 零 shim 处理 | 依赖 T2 完成 |
| #19 | rd-infra | 修角色别名解析（`ALIAS_ROLE` 键值写反）+ `check` 增加「别名可解析」回归守卫 | **独立批次**：需用户另行确认开工 |

## 进行中

| 任务编号 | 目标会话 | 概要 | 派发时间 | 对应 AC | WIP 提交 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T2 | rd-infra | pi package 化：manifest（按文件声明 2 skill）+ `SKILL.md` + A′ 布局 + 薄 CLI（init/exec/migrate）+ shim（D6/D7）+ 迁移精准删除（§12-C/D）+ 清 `/tmp/t1` | 2026-10-08 | AC1/AC2/AC3/AC4/AC6/AC8 | `wip(T2): …` |
| T4 | qa | 用例与独立验证：仅新增 `tests/` + `docs/reports/2026-10-08-T4-*.md`（不碰 `package.json`/`bin/`/`.agents/`） | 2026-10-08 | AC1/AC3/AC4/AC5 + NFR2/NFR3 | — |

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |
| — | — | — | — |

## 挂起（被抢占 / 降级）

| 任务编号 | 挂起原因 | 恢复方式 |
| :--- | :--- | :--- |
| — | — | — |

## 已验收 / 已归档

| 任务编号 | 结论 | 详情路径 | 备注 |
| :--- | :--- | :--- | :--- |
| T0 | 架构评审：**有条件可行** → 终签**放行 T2**（附 4 条实施闸门 A–D + 3 条 PM 待办，已全部处理）；NFR2/NFR3 口径已定稿 | 回执内容 | 纠正 T1 的 exit 70 与 AC1 足迹 |
| T0-ADR | **验收通过**（done(lite) 已核）：ADR 正文 59 行 + `docs/adr/README.md` 索引 +1；`check` exit=0；commit `7512da2` 已 push；仅动两路径，未影响 T2 | `docs/adr/2026-10-08-nao-skills-single-skill-pi-package.md` | T3 收尾：统一引用数口径（ADR「290 处/45 文件」 vs PRD「334 处/34 文件」，统计模式不同） |
| T1 | **验收通过**：V1 包落盘路径确定 + `PI_PACKAGE_DIR` 不可用；V2 含 `SKILL.md` 即停递归 ⇒ `references/*.md` 不注册；V3 推荐 `.pi/npm` + 显式 `npm ci`；下游 CI 0 调用 | `docs/reports/2026-10-08-T1-pi-package-verify.md` | 本仓仅 +1 文件、下游 4 仓 0 条（已独立复核）；`/tmp/t1` 已在 T2 收尾项 |
