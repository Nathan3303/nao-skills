# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 归档后的历史见 `docs/prds/` 与 `docs/adr/`；本文件只记**运行时**任务状态，保持精简。

## PM 接续快照（会话重开后**先读本区**）

- 当前阶段：**批次终态**（已合并 / 已 tag+Release / **npm 已发布** / 下游通知已发；待发布后核验报告）
- 当前 PRD：`docs/prds/2026-10-08-nao-skills-pi-package.md`（状态：已交付）
- 未决决策点：无（D1–D8 已拍板；F1/F2 已修；npm 发布已由用户完成）
- 待用户回答：无
- 未派发队列：见下方「待派发队列」（仅独立批次 #19 · #21）
- 下次唤醒条件：worker 回执 **T4-发布后核验**（qa）→ 落盘报告 → 归档并重开 PM 会话
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
- 需求分支：`feat/18-pi-package`（已合并；远端 + 本地分支已删）
- PR owner / Reviewer：rd-infra / **arch-designer**（评审 GO ×2）
- PR：[#20](https://github.com/Nathan3303/nao-skills/pull/20)（**已 MERGED** · Issue #18 已随合并关闭）· 预览环境：无
- 合并：**已 squash 合并**（main `197dd6e`，本需求恰好 1 条、无 `wip()`）· 分支已删：是
- 版本 / Tag：v0.12.0 · **tag + GitHub Release 已发布**（notes 落 `docs/releases/v0.12.0.md`）
- **npm 发布**：✅ **已发布**（`@nathan33/nao-skill@0.12.0` · 用户执行 · `published 2026-10-08T11:37:27Z` · `dist-tags.latest = 0.12.0` · registry `pi.skills` = 2 条按文件声明）；发布后短暂 404 属 npmjs **异步处理窗口**（日志：`PUT 202` + 「being processed」）
- **下游通知**：✅ 已发 3 个通知 Issue（迁移可选）— [nao-todo#188](https://github.com/Nathan3303/nao-todo/issues/188) · [nao-todo-server#48](https://github.com/Nathan3303/nao-todo-server/issues/48) · [nue-ui#72](https://github.com/Nathan3303/nue-ui/issues/72)（`nao-todo-minimal` 无远端，不通知）
- 降级标注：无（`gh` 可用，exit 0）
- 特例提交（白名单）：无

## 待派发队列

| 任务编号 | 目标会话 | 概要 | 排队原因 |
| :--- | :--- | :--- | :--- |
| #19 | rd-infra | 修角色别名解析（`ALIAS_ROLE` 键值写反）+ `check` 增加「别名可解析」回归守卫 | **独立批次**：需用户另行确认开工 |
| #21 | rd-infra | migrate 收尾：`.nao-migrated` 只写不读（F3）+ `migrate` 无条件装 shim 与 minimal 零 shim 特例冲突（F4） | **独立批次**（arch 评审引出） |

## 进行中

| 任务编号 | 目标会话 | 概要 | 派发时间 | 对应 AC | WIP 提交 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T4-发布后核验 | qa | 对**已发布** `0.12.0` 做真实安装对照 + 发布物 tarball 内容核验（仅写 `docs/reports/2026-10-08-T4-postpublish-verify.md`） | 2026-10-08 | 发布后闸门 | — |

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |
| — | — | — | — |

> T2 验收注意事项（已归档，见下）：① 零网络断言为「代理阻断 + npm offline」，非内核级隔离（已披露，接受）；② `.pi/npm/.gitignore` 由 pi 自生成 → D2 无需本仓额外配置。

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
| T3-修 | **验收通过**：`5537270` 仅 `README.md` + `bin/nao-skill.js`（未越界）；版本仍冻结 0.12.0 · 工作区干净；F1 → **文本级删单条**（实测 `git diff` 仅删 6 行、缩进保 4 空格）· F2 → `init` rc=1 拒绝 / `init --force` 走 migrate（prompts 与 frontend-design 残留 = 0，无混装无双注册）· F5 → README 写死 pin 为准；`npm test` exit=0 · 全套 7/7 · 94 断言 | `5537270` | 发布产物重新冻结（后续 `tests/` 新增不计入发布产物） |
| T3-收尾 | **验收通过**：`2f953c3` 仅改 `package-lock.json` 2 行；`package.json`/`package-lock.json` 均 0.12.0、`0.11.0` 残留计数 **0**；`npm test` exit=0 | `2f953c3` | 曾为冻结基线；因 F1/F2 修复而解冻，改由 `5537270` 重新冻结 |
| T4-跑批 | **验收通过**：`T4_ALLOW_MISSING=0 tests/t4/run.sh` → exit 0 · **7/7 PASS · 94 断言 0 红 · SKIP 0 · BLOCKED 0**；真实 `pi install -l` 与 tarball 布局逐文件一致；无产品缺陷 | `tests/t4/` · `docs/reports/2026-10-08-T4-qa-report.md`（`eee6e06`） | 首跑 3 处 FAIL 均为**测试自身缺陷**（已修复复跑全绿）；越界检查 ✓（12 文件仅 `tests/` + `docs/reports/`） |
| T3 | **验收通过**：README（新 pin 完整性判据 + 闸门 A/B + 下游迁移）· ARCHITECTURE 分层放宽 · `docs/releases/v0.12.0.md`（规范达标）· version bump 0.12.0 · **AC5 四仓只读验证**（check rc=0，`status` 0→0 ×4）· minimal 零 shim 佐证（`.agents/{commands,prompts}` 非 skill 扫描面） | `37bde60` | 残留① lockfile 版本 → 已由 T3-收尾 关闭；残留② 数字口径已统一到 PRD 口径（334/34） |
| T2 | **验收通过**：全门禁绿（`check` exit=0 files=43 · `npm test` exit=0 · 注册 skill=2 collision=0 · 无网 exit=0 · 删包 exit 2+`DEGRADED:` · D7 双防护 · init 幂等 · migrate 精准删）；条件① 已由 T4-最终跑批（0.12.0）关闭 · 条件② 已由 T3 关闭 | `6f21e54` | — |
| T4-最终跑批 | **验收通过**：冻结产物 `2f953c3`/0.12.0 上 `T4_ALLOW_MISSING=0` → exit 0 · **7/7 PASS · 94/94 断言 0 红**；已贴 PR 评论（QA of record） | PR #20 [comment](https://github.com/Nathan3303/nao-skills/pull/20#issuecomment-6058379378) | 额外严谨性：在 `2f953c3` 独立复跑，证明 tip 差异仅 `tasks-state.md`、被测路径逐字节一致 |
| T0-评审2 | **验收通过 · GO**：D1–D8 与闸门 A–D 逐条符合；D7 绕过推演（`env -u` 清标记后有守卫②兜底、shim→shim 最多 2 跳被拦）**未发现无限递归路径**；BR1/BR2 守住；独立复跑 7/7 · 94 断言 | PR #20 [review](https://github.com/Nathan3303/nao-skills/pull/20#pullrequestreview-5455520693) | 处置：F1/F2 → 合并前修（T3-修）· F5 → 顺手修 · **F3/F4 → #21** · F6 已在 ADR 备案 |
| T4-复跑 | **验收通过**：冻结产物 `5537270`/0.12.0 上 `T4_ALLOW_MISSING=0` → exit 0 · **8/8 PASS · 109/109 断言 0 红 · SKIP 0 · BLOCKED 0**；新增 T4-08 覆盖 F1（`git diff --numstat` = `0 4` 纯删、逐字节一致、keep-me 行不变、仍合法 JSON）与 F2（`init` rc=1 无部分动作 / `--force` 走 migrate 无混装无双注册） | PR #20 [comment](https://github.com/Nathan3303/nao-skills/pull/20#issuecomment-6058635005)（`34094ce`） | 越界检查 ✓（仅 `tests/` + `docs/reports/`）；首现 1 处 FAIL 为测试自身硬编码缩进，改逐字节判据后全绿 |
| T-合并 | **验收通过**：PR #20 `--squash` → main `197dd6e`；本需求**恰好 1 条**、无 `wip()`、标题可读；远端+本地分支已删；发布物与已测产物 `34094ce` **零差异**（故未重跑门禁） | `197dd6e` · tag `v0.12.0` | `--delete-branch` 因当时工作区有 PM 未提交文件而在本地 checkout 阶段中止；远端合并成功，分支由 `git push --delete` 删除（未强切、未碰他人文件） |
| T0-复核 | **验收通过 · GO**：F1/F2/F5 按建议落实、无新回归；AC1「注册数==2」不变式与 BR5 守住；独立复跑 7/7 · 94 断言 + 定向夹具（F1 末位属性/单行压缩两边界；F2 双路径 + 共享 `nue-ui-dev` 保留）；与 rd-infra 证据交叉核**无分歧** | PR #20 [comment](https://github.com/Nathan3303/nao-skills/pull/20#issuecomment-6058492163) | 新发现（低）：单行压缩 lock 下文本级删条**静默跳过去重** → 已追记 **#21 F7**；另（非阻塞）建议固化 F1/F2 回归断言 → 已在 T4-复跑 要求中 |
