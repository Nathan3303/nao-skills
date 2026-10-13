# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 历史见 `docs/tasks-archive.md`；权威来源 = `docs/prds/` 与 `docs/releases/`；本文件只记**运行时**状态，保持精简。
> 归档动作 = 从「进行中」**删除** + 归档墙**新增**（同一 id 同时出现在两处会因 `arch` 优先被判 **`closed`**，`close` 闸门保护静默消失）。

## PM 接续快照（会话重开后**先读本区**）

> 本区是 PM 的**悬空状态**（任务状态见下方五栏）；重开后逐行回读确认（当前阶段 · 未决决策 · 口头约束）。

- 当前阶段：**T519 在飞**（tasks-state 台账瘦身 + 历史下沉 → 目标 v0.17.1；上一批 T518 → v0.17.0 已全链路闭环）
- 当前 PRD：`docs/prds/2026-10-14-tasks-state-slim.md`（状态：已开工 · 落地中）
- 未决决策点：无
- 待用户回答：无
- 未派发队列：见下方「待派发队列」（共 0 项）
- 下次唤醒条件：RD `done(full)` 回执 / 用户授意 / 用户要求重开 PM；先读本快照 + `docs/prds/README.md`
- 口头约束已落盘：项目 `AGENTS.md` 项目约束（ask-me 提问）· PRD §5 BR6 格式禁令 + §9 R5/R6
- 需求分支 / PR：见下方「需求分支 / PR / 发布」（降级分支 `nao/tasks-state-slim`）
- 会话体检：本批（T519）PM ctx ≈7%（66.4k/1000k · 无压缩）· 舰队 = pm + `qa-T519`/`rd-infra-T519`

## 需求分支 / PR / 发布（PM 维护）

- Issue：**无（降级批次）** —— 摘要见 `docs/prds/2026-10-14-tasks-state-slim.md`
- 需求分支：`nao/tasks-state-slim`（base `main` = `9329421`；RD 持有）
- PR owner / Reviewer：rd-infra-T519 / **无**（docs-only · 不改解析器 ⇒ 跳过架构评审）
- PR：待 RD 建 Draft PR（主题须用户可读）
- 合并：未合并 · 分支已删：否
- 版本 / Tag：**v0.17.1（PATCH）** 待发布（合并后 PM 执行 tag/Release；`docs/` 不入包 ⇒ npm 不重发）
- 降级标注：无 Issue · 无 Reviewer（用户拍板 D3）
- 特例提交（白名单）：无

## 活约束与遗留跟踪（长期有效 · 不下沉）

- 待用户裁量的后续项（均不阻塞、**未开单**）：① **O1** nao-todo `AGENTS.md:131` 仍把 `.nao-migrated` 列为「0.12.0 起入库面」→ 收敛 ② **B8** `close` 同名跨仓不可定向（工具侧可叠加名册 cwd / `pane_current_path` 约束；使用纪律 = 仓级唯一任务号）③ **D6** `failWarn` 文案措辞（PRD §8.1）④ **B1** legacy 目录名判定过宽（`--dry-run` / 内容白名单）⑤ 三仓 `.agents/.nao-version` 仍 `0.12.0`（0.13.0 无读取方，版本权威 = pin）⑥ **T512-①** `status`/`close` 排除/识别 `subagent-*`（父子 pane 串扰隐患，与 T511-B8 同类；脚本类需回归）⑦ **T512-②** nao 版 `intercomBridge.instructionFile` + 协议补「会话内子代理」条款（自动桥在当前装机**整条死**，仅显式路径可用）⑧ **T512-③** 角色→pi-subagents agent 薄壳（缓，有 `--append-system-prompt` 替代）⑨ **T512 附录** pi-subagents 引入目标流程 A/B（**已登记 · 未立项 · 未落地**；报告附录 105 行）⑩ **宿主检测 ⇒ 已交付（T513 / 0.14.0，见上）**；原问题：`detect_host` 不识别 foot / Hyprland；用户 2026-10-12 拍 **D1–D5**（D1 默认开可见窗口 · D2 非 tmux 宿主 close 支持 / status turn 判定明确降级 · D3 tmux 内仍优先 · D4 无图形会话必须显式 `--background` 否则 exit 2 · **D5 tmux 可用但当前不在 tmux 时可用 tmux，但必须前台可见、禁静默后台会话**）。**D5 使阶梯③保留完整 tmux 句柄 ⇒ 回归面大幅缩小**。P3/P4 已实测（127 裸中断 / rc0 假成功）。PRD：`docs/prds/2026-10-12-non-tmux-host-spawn.md`。⑪ ✅ **npm 发布已执行（2026-10-13）**：只发 `0.16.0`（`latest → 0.16.0`，不补发 0.12.1–0.15.0）· 用户执行 · 已验 tarball sha512 与 dist.integrity 一致。
- 既定口径（长期有效）：**README 视角 = 纯舰队机制，不写具体上下游应用信息（应用仓名/迁移操作细节不入 README；用户 2026-10-13 拍板，已删除「下游仓库迁移」节并中和泛化措辞）**；迁移命令从**仓外**执行；`.pi/settings.json` pin 入库；`.agents/.nao-obsolete/` 加 gitignore；迁移判据 = 机制类归零 + 自有资产保留；历史归档文档不改；不碰源码/测试/构建配置
- **PM 交互约定（用户 2026-10-14 拍板，长期有效）**：**需要用户确认 / 拍板的问题一律用 `ask-me` 提问**（不用自由文本提问）；本约定写入项目 `AGENTS.md` 项目约束（T518 范围内）。
- ⚠️ **合并纪律（T511 教训，已落 `.agents/skills/github-flow.md`）**：PR 只有 1 条提交时 `gh pr merge --squash` 取**该提交 subject**（非 PR 标题）⇒ **必须显式 `--subject "<用户可读主题>"`**，否则 `wip()` 进主干
- ⚠️ **同仓协作纪律**：nao-skills 本仓工作（如 T509/T510）——RD 持有分支期间 PM 不做本仓 git 写操作；台账提交只在「派发前」「合并后」两个时点
- ⚠️ 环境注意：`nao-fleet.sh` 别名解析已修（0.12.1）· `ensure` 会真拉 pane，未信任目录会停在 pi Trust 提示（D7）· `close` 以 intercom 名册为权威在线判定 · `status` 残留识别要求表格内**裸批次号**单元格
- ⚠️ **本仓 remote（2026-10-13 起）**：origin 已改 **HTTPS**（`https://github.com/Nathan3303/nao-skills.git`）——SSH :22 banner 超时持续，HTTPS push 已验证可用（凭据走全局 `credential.https://github.com.helper` = `gh auth git-credential`）。若后续 SSH 恢复可由用户改回
- ⚠️ **npm 发布教训（v0.16.1 首次 + v0.16.2 首次均中招，同型）**：`npm publish` 若 `~/.npmrc` 的 `_authToken` 无发布权限 ⇒ `PUT 401` → CLI 转浏览器 web auth → **`PUT 202` + `exit 0` + "being processed" = 假成功**，registry 永远无该版本。**成功判据 = 输出出现 `+ @nathan33/nao-skill@<ver>`**（或几秒后 `npm view ... dist-tags` 已是新版）；修复 = `npm login` 重授权 **或** 换含 Publish 权限的 Granular Access Token（必要时勾 bypass 2FA）。
- 📌 **台账写法约定（T519 订正）**：`status` 残留识别按**单元格全等**匹配 ⇒ 进行中行须有**裸批次号**单元格（如 `T508`）；带后缀单元格（`T508-QA`/`T508-RD`）实测判 **`absent`**（非「仅散文提及」）。
- **通用既定口径（T506 · 留档见 `docs/tasks-archive.md` §9）**：`.pi/*` + `!.pi/settings.json`；迁移判据 = 机制类归零 + 自有资产保留；旧脚本调用改 `$NAO_SKILLS/…`。

### 上游遗留单（独立批次 · 待用户确认开工）

| 编号 | 概要 | 备注 |
| :--- | :--- | :--- |
| [#19](https://github.com/Nathan3303/nao-skills/issues/19) | 修角色别名解析（`ensure arch`/`ensure infra` 报未知角色）+ `check` 加「别名可解析」回归守卫 | 已实测：`ensure` 必须用 canonical id（`arch-designer`/`rd-infra`） |
| [#21](https://github.com/Nathan3303/nao-skills/issues/21) | migrate 收尾：`.nao-migrated` 只写不读（F3）· `migrate` 无条件装 shim 与 minimal 零 shim 特例冲突（F4）· 单行压缩 lock 静默跳过去重（F7） | 由 T506/PR #20 的 arch 评审引出 |
| （未开单·候选） | `nao-fleet.sh close` 跨仓派生会话回收：宿主定位假阴性（报「未运行」但 pane 存活）→ 需手工 `tmux kill-pane` | T507 / T508 各复现一次；另附：`ensure <role>` 会真拉 tmux pane（AC6 演练后需收尾）—— 是否并入 #19 待用户定 |

> ⚠️ 上表为迁移时点原文（只搬不改）：#19 / #21 已分别由 **T509 / T510** 交付闭环 —— 是否刷新状态由 PM 裁量（未自行改写，守 BR3）。

## 待派发队列

| 任务编号 | 目标会话 | 概要 | 排队原因 |
| :--- | :--- | :--- | :--- |

## 进行中

| 任务编号 | 目标会话 | 概要 | 派发时间 | 对应 AC | WIP 提交 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T519 | qa-T519 → rd-infra-T519 | 台账瘦身 + 历史下沉（降级批次 `nao/tasks-state-slim`；接缝先行 → 单波落地） | 2026-10-14 | AC1–AC8 | 待 RD 首提交（`wip(T519):`） |

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |

## 挂起（被抢占 / 降级）

| 任务编号 | 挂起原因 | 恢复方式 |
| :--- | :--- | :--- |

## 已验收 / 已归档

| 任务编号 | 结论 | 详情路径 | 备注 |
| :--- | :--- | :--- | :--- |
| **T518** | **验收通过 · 已合并归档**（v0.17.0）：to-spec 改造引入（验证接缝 + 对话综合）· AC1–AC9 全过 · 9 文件 +167/−7 · 门禁 `check` rc0 roles=6 files=44 · t4 12/12 · squash `93ffb0a`（main 恰 1 条 · 无 `wip()`）· **已发布** v0.17.0（tag + Release + npm `latest→0.17.0` 对账逐字节一致） | PR [#36](https://github.com/Nathan3303/nao-skills/pull/36) · Issue [#35](https://github.com/Nathan3303/nao-skills/issues/35) · PRD `docs/prds/2026-10-14-pm-to-spec-adoption.md` | 待办：下游三仓唤醒后补发广播 `card pm v24` / `card qa v14` |
| **T517** | **验收通过 · 已合并归档**（v0.16.2）：派生会话 tmux 落点修正（`resolve_host_window()` L1–L4 + `-t` 贯穿 10 处）· AC1–AC9 全过（QA 独立 GO：case12 19 红→36/36；tests 12/12 · 263 例 · 0 红）· squash `536d030` | PR [#34](https://github.com/Nathan3303/nao-skills/pull/34) · Issue [#33](https://github.com/Nathan3303/nao-skills/issues/33) · ADR `docs/adr/2026-10-13-derived-pane-window-addressing.md` | **已发布** v0.16.2（tag + Release + npm 对账一致） |

> 更早批次（T516 及以前）见 `docs/tasks-archive.md`。
