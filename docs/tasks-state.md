# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 归档后的历史见 `docs/prds/` 与 `docs/adr/`；本文件只记**运行时**任务状态，保持精简。

## PM 接续快照（会话重开后**先读本区**）

- 当前阶段：T507 已完全闭环（PR #49 `abc7a22` + 记账 PR #50 `da70a75`）；**T508（nue-ui）开工确认已过，T508-QA 已派（用例先行）**，rd-infra@nue-ui 已拉起待派
- 当前 PRD：上游 `docs/prds/2026-10-08-nao-skills-pi-package.md`（已交付）；此前 T506 权威 PRD 在另一仓：`~/Project/nao-todo/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（已归档）
- 当前 PRD：上游 `docs/prds/2026-10-08-nao-skills-pi-package.md`（已交付且已归档）；**T506 权威 PRD 在另一仓**：`~/Project/nao-todo/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（Issue nao-todo#188）
- 未决决策点：无（D1–D8 已拍板；F1/F2 已修；npm 发布已由用户完成）
- 待用户回答：**无**（T508 已开工；PM 重开已定「本会话继续」）；⚠️ 待用户裁量：`close` 无法回收跨仓派生会话的机制缺陷如何处置（并入 #19 / 新开单 / 暂记）
- 既定口径：迁移命令从**仓外**执行（`cd /tmp && npx --yes @nathan33/nao-skill@0.12.0 migrate <绝对路径> -v`）；`.pi/settings.json` pin 入库；`.agents/.nao-obsolete/` 加 gitignore；判据 = 机制类归零 + 自有资产保留；历史归档文档不改；不碰源码/测试/构建配置
- 未派发队列：见下方「待派发队列」+ 「待启动批次」两节（另两仓迁移 · #19 · #21 · #22）
- 下次唤醒条件：用户对 **T508 开工确认卡**给出答复 → 派 rd-infra@nue-ui + qa@nue-ui（`--task T508`，base **`master`**）；T508 闭环后处理上游 #19 / #21
- 会话体检：contextTokens≈135k（窗口 1000k · **~13%**）· 压缩次数=0 · 记于 2026-10-08T13:45Z（T507 闭环时）· 批次终态按纪律默认 `ensure --force pm`（ctx 远低 40% 且未压缩 ⇒ 已征询用户是否本会话直接做 T508）
- ⚠️ 环境注意：`nao-fleet.sh` 别名解析有缺陷（#19）——`ensure` **必须用 canonical id**；`arch` / `infra` 会报未知角色
- 口头约束已落盘：PRD §5（BR1/BR2 角色模型与常驻注入不变）· §§11–13（决策台账 + 闸门 + 特例）
- 会话体检：contextTokens=311k（窗口 1000k · **31%**）· 压缩次数=0 · cacheRead=待观测 · 记于 2026-10-08T11:55Z（批次归档时）

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
| T508 | qa-T508（`--task T508` @nue-ui） | 用例先行：AC1–AC8 断言脚本（双模式）+ 迁移前基线（V2 `vp check` 差异文件数/rc · V3 `nue-ui-dev` 清单 · V4 仓内 `npx` EBADDEVENGINES 佐证 · 门禁基线）· 本地产出、暂不提交 | 2026-10-08（开工确认后） | AC1–AC8 | 待分支 |
| T508-RD | rd-infra-T508（`--task T508` @nue-ui） | 已拉起待派：建分支 `feat/72-nao-fleet-migration`（**base `master`**）+ PRD 入库 + `pi install -l` + 仓外 `migrate` + **`AGENTS.md` 机制段改写** + `.gitignore` 两处 + 门禁 + Draft PR | 待 T508-QA 回执后派（避免同分支双写） | AC1–AC8 | — |

> **会话回收（已完成）**：T507 派生会话 `qa-T507` / `rd-infra-T507` 已回收（验收通过即回收）。
> ⚠️ **机制缺陷发现（2026-10-08）**：`nao-fleet.sh close` **无法回收跨仓派生会话** —— `close --task T507 qa` → 「未运行（无需回收）」但 `tmux list-panes` 实际存活（标题格式正常）；`close --task T507 qa-T507` → 「未知角色」。本次以 `tmux kill-pane` 手工兜底完成回收（`status` 的残留识别正确）。**尚未开单**，待用户裁量是否并入 #19 或新开（PM 未自做修复：零代码边界）。
> 📌 **台账写法约定（实测）**：`nao-fleet.sh status` 的残留识别按**表格单元格全等**匹配任务编号（`task_state_class()`）⇒ 进行中行必须出现一个**裸批次号**单元格（如 `T508`）；仅写 `T508-QA` / `T508-RD` 会被归为「仅散文提及」并误报残留。

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |
| T507-RD4 | **done(lite)**：记账 PR [#50](https://github.com/Nathan3303/nao-todo-server/pull/50)「文档：PRD 索引状态更新为已交付」→ main **`da70a75`** · 恰 **1 文件 1 行** · 本 PR 恰好 1 条 · 无 `wip()` · 分支已删 · CI 双 job 绿（38s / 1m12s，未用 `--admin/--auto`） | PR [#50](https://github.com/Nathan3303/nao-todo-server/pull/50) | T507 **记账闭合** |
| T507-QA | **done(lite)**（用例先行）：脚本 363 行（AC1–AC8 映射；迁移后模式现树=预期 RED 22P/35F/2W；`--baseline`=**GREEN 27P/0F**）+ 基线：顶层 **8 项**/43 文件 · `.agents/` 外引用 **0** · `.gitignore` L68 裸 `.pi` · `git ls-files .pi`=0 · lock 3 键（无 frontend-design）· V1 `golangci-lint 2.14.0` ✓ · V2 `go test ./...` exit 0（不依赖 MySQL/Redis） | `docs/reports/2026-10-08-T507-nao-fleet-migration-verify.sh` | 已随 QA2 入库（`76035ec`） |
| T507-QA2 | **done(full)**：独立复跑 **PASS=84 / FAIL=0 / WARN=1**（WARN=squash 前提交数>1，预期）**exit 0**（默认 + `T507_ROLLBACK=1 T507_REAL_DEGRADED=1` 全跑）· 口径修正已落（`76035ec` 脚本 + PM PRD 订正 · `16a401f` 报告）· **PR #49 已评论**（QA of record）。自测：顶层 **5 项**/入库 **3 文件** · pin JSON 等价 · 六门禁全 0 · 幂等 · 回滚实测 · AC8 命中 0 · 无 FAIL | `docs/reports/2026-10-08-T507-qa-report.md` · PR [#49 comment](https://github.com/Nathan3303/nao-todo-server/pull/49#issuecomment-6061112837) | 3 处分歧已裁定：① RD 的「顶层 4/入库 5」有误，**以 QA 为准**（磁盘 5 / 入库 3）② AC4 pin 改语义断言（JSON 等价）③ §1/§2「7 项」早已订正为 8 —— 均非实现缺陷，不阻断 |
| T507-RD | **done(full)**：10 步全完成 · `migrate` rc=0（移除 23 项 / 备份 42 文件）· 六门禁全 rc=0（`golangci-lint` v2.14.0 / 0 issues）· md5 不变三项（AGENTS `587f47ce` / CLAUDE `1bab8f84` / APPEND_SYSTEM `8a7082f6`，仍忽略）· 幂等（二次 migrate rc=0 · shim same · 0 effect · 未新增 stamp）· AC6 负向全过（缺包 rc=2 + 恰 1 行 `DEGRADED:`；worktree 回滚后 `check` rc=0 roles=6）· AC8 命中 0 · QA 脚本未被误提交 | 分支 `feat/48-nao-fleet-migration` · PR [#49](https://github.com/Nathan3303/nao-todo-server/pull/49) | 数字订正：其「顶层 8→4 项 / 入库 43→5」不准 → 以 QA 实测为准（磁盘 5 / 入库 3）；AC3 口径已裁定为「入库文件 0→0」 |
| T507-RD3 | **done(lite) · 已合并**：main `abc7a22` =「迁移 nao 舰队机制到 0.12.0 pi 包形态（shim 入口 + 版本 pin 入库） (#49)」· 本需求**恰好 1 条**· **无 `wip()`**· 工作区 clean · 远端+本地分支均已删 · PR state=**MERGED**。过程偏差：首试被 main 保护拒（`integration` pending）→ 未用 `--admin/--auto`，`gh pr checks --watch` 等 CI 绿后重试成功（`build/vet/unit` 45s · `integration` 1m11s pass）· 合并后复验 `check` rc=0/roles=6 · 三处 md5 不变 · `git ls-files .pi` = 恰 1 | PR [#49](https://github.com/Nathan3303/nao-todo-server/pull/49) | 又：磁盘 `.agents/` 由 5 项→**4 项**（空 `skills/` 被 git 清理，符合 AC1/AC2）· **CI 侧门禁已获真实验证**（原「CI 未触发」遗留项关闭） |
| T507-RD2 | **done(lite)**：`4570cd9` `wip(T507): PM 验收结论 + PRD 索引` —— 自检 `git diff --name-only HEAD~1..HEAD` = **恰 2 文件**（PRD M + `docs/prds/README.md` A）· 已推送（`16a401f..4570cd9`，与远端 0/0）· 工作区 clean · **未合并**（`origin/main` 仍 `7c13f0a`）· 全量 diff 50 文件（`.agents/**` 44 + `.gitignore` + `.pi/settings.json` + docs 4），AC8 命中 0 | 分支 `feat/48-nao-fleet-migration` · PR [#49](https://github.com/Nathan3303/nao-todo-server/pull/49) | PM 已独立复核（恰 2 文件 + §11 与写定一致）→ 已发合并授权 |

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
| **T507** | **验收通过 · 已合并归档**（仓：nao-todo-server 迁移到 0.12.0）：AC1–AC8 全过 · `migrate` rc=0（移除 23 项 / 备份 42 文件）· 六门禁全 rc=0（`go test` 21 ok / 44 无测试文件 / 0 fail）· 幂等（0 effect）· 负向闭环（缺包 rc=2 + 恰 1 行 `DEGRADED:`）· worktree 回滚实测 · QA2 独立复跑 **84P/0F/1W** · squash **`abc7a22`**（main 恰好 1 条、无 `wip()`）· CI 双 job 绿 · 非范围命中 0 | `~/Project/nao-todo-server` · PR [#49](https://github.com/Nathan3303/nao-todo-server/pull/49) · Issue [#48](https://github.com/Nathan3303/nao-todo-server/issues/48) | 3 处数字分歧均属文档口径（RD 报「入库 5 文件」不准 → 实测 **3**）· 曾需 `gh pr ready` 先转 ready + 等 `integration` 检查（未用 `--admin`）· 本仓无 CHANGELOG（未新增） |
| T506 | **验收通过 · 已合并归档**（仓：nao-todo 迁移到 0.12.0）：AC1–AC8 全过 · qa 用例 72 PASS/0 FAIL · 全仓门禁（`vp check` 0 · `vp test` 231 文件/1824 例/0 红 · 5 guard 0 · 双端 build 0）· 缺包 exit 2 + `DEGRADED:` · 回滚实测 · squash `3f3da45f`（main 恰好 1 条、无 `wip()`）· main ≡ 已测 head `99b39e8a` 零差异 | `~/Project/nao-todo` · PR #189 · Issue #188（已关） | 我的 2 处 PRD 口径错误由 rd-infra 与 qa 独立发现并订正；另发现该仓 main 历史遗留 `wip(T505b)` 提交（**非本批**，已报备） |
| T4-发布后核验 | **验收通过**：真实安装 `@nathan33/nao-skill@0.12.0` exit 0 · 落盘/pin 正确 · 项目足迹仅 2 文件 · 注册 skill **恰 2** collision **0**（stdout/stderr 双查）· shim `check` exit 0；发布 tarball **48 文件 / 109 211 B / sha256 `8c6b530a…`** 与 tag `v0.12.0` 本地 pack **逐字节一致** · `tests/`+`docs/` 零泄漏 · 包内 `pi.skills`=2 无 `pi.prompts` | `docs/reports/2026-10-08-T4-postpublish-verify.md` | **PM 已独立复核**（自算 sha256=一致、文件数=48、白名单无泄漏、包内 manifest） |
| T0-复核 | **验收通过 · GO**：F1/F2/F5 按建议落实、无新回归；AC1「注册数==2」不变式与 BR5 守住；独立复跑 7/7 · 94 断言 + 定向夹具（F1 末位属性/单行压缩两边界；F2 双路径 + 共享 `nue-ui-dev` 保留）；与 rd-infra 证据交叉核**无分歧** | PR #20 [comment](https://github.com/Nathan3303/nao-skills/pull/20#issuecomment-6058492163) | 新发现（低）：单行压缩 lock 下文本级删条**静默跳过去重** → 已追记 **#21 F7**；另（非阻塞）建议固化 F1/F2 回归断言 → 已在 T4-复跑 要求中 |

## 已闭环批次 · T507：nao-todo-server 迁移（**已验收并合并**）

> 结果：PR [#49](https://github.com/Nathan3303/nao-todo-server/pull/49) `--squash` → main **`abc7a22`**（恰好 1 条 · 无 `wip()` · 分支已删 · CI `build/vet/unit`+`integration` 双绿）
> 验收：AC1–AC8 全过 · 缺陷 0 · QA2 独立复跑 **84 PASS / 0 FAIL / 1 WARN**（WARN=squash 前提交数）· PM 独立复核变更 50 文件未越界
> 口径订正：AC3「入库文件 0→0」（排除 `.pi/npm` 物化产物 / 迁移文档 / `.gitignore` 忽略行）· AC4 pin 改语义断言 · 顶层项数 7→**8**（基线实测）· AC1 补「入库 43→3」

| 项 | 内容 |
| :--- | :--- |
| 权威 PRD | `~/Project/nao-todo-server/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（PM 已写入工作区，**未提交**；由 RD 在需求分支随首提交入库） |
| Issue | [nao-todo-server#48](https://github.com/Nathan3303/nao-todo-server/issues/48)（2026-10-08 由通知单**转实施单**：补 TL;DR / AC1–AC8 / 优先级 / PRD 指针；并订正原「agent-browser 等为本地资产」表述 —— 实测本地无对应目录） |
| 分支 | `feat/48-nao-fleet-migration` |
| 角色 | rd-infra@nao-todo-server（PR owner）· qa@nao-todo-server · Reviewer：无 |
| 本仓实测 | `.agents/` 43 文件入库 · `.nao-version`=0.11.0 · **`.agents/` 外引用 0 命中**（AGENTS/CLAUDE/README/docs/ci.yml）· 无 `package.json`/`devEngines` ⇒ 无 `EBADDEVENGINES` 阻断 · `.gitignore` L68 裸 `.pi` 需改 `.pi/*`+`!.pi/settings.json` · `.pi/APPEND_SYSTEM.md` 现被忽略且不入库（保持） · lock 三项无本地目录、不含 `frontend-design` ⇒ **无去重动作** |
| 待验证项 | V1 本机 `golangci-lint` v2.14.0 是否可用 · V2 `go test ./...` 本机可跑性（MySQL/Redis 依赖）· V3 `.pi/APPEND_SYSTEM.md` 仍被忽略 · V4 无 `package.json` 形态下 migrate 实测行为 |

> 路线 A（迁到 0.12.0 pi 包形态），**每仓一个批次**（Issue → 分支 → PR → 验收 → squash 合并），**每批开工前须出开工确认卡**。
> 可复用 T506 的 PRD 作模板：`~/Project/nao-todo/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（含订正后的判据与 §11 验收结论）。

## 下一批次 · T508：nue-ui 迁移（**未开工** · 待侦察 + 开工确认卡）

| 项 | 内容 |
| :--- | :--- |
| 权威 PRD | `~/Project/nue-ui/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（PM 已写入工作区，**未提交**；由 RD 在需求分支随首提交入库；本仓**原本无 `docs/`**，本批新建） |
| Issue | [nue-ui#72](https://github.com/Nathan3303/nue-ui/issues/72)（2026-10-08 由通知单**转实施单**：TL;DR / AC1–AC8 / 优先级 / PRD 指针 / 4 个本仓特有风险） |
| 分支 / base | `feat/72-nao-fleet-migration` · **base = `master`**（本仓默认分支） |
| 角色 | rd-infra@nue-ui（PR owner）· qa@nue-ui · Reviewer：无（PM 另行复核 `AGENTS.md` 改写文本） |
| 本仓实测 | `.agents/` 顶层 **9 项** · `.nao-version`=0.11.0 · `.agents/` 外引用 **15 处**（三类：A 机制仅 `AGENTS.md` L76–88 / B 自有 skill 包安装目标语义 9 处**不改** / C `vite.config.ts` `fmt.ignorePatterns` 含 `.agents/**`+`.pi/**` **不改**）· `.agents/skills/` 混装自有 `nue-ui-dev` + lock 3 目录 + nao 资产 · lock **含 `frontend-design`**（会被文本级去重）· `devEngines` pnpm 11.21.0 ⇒ **仓外执行** · **无 `.pi/`** · **无 `docs/`** · CI `test-and-deploy.yml` 0 命中 · 钩子 `.vite-hooks/pre-push` 跑全量测试 |
| 关键发现 | `.agents/commands/commit.md` 经查为本仓**自有**（`2986b24c` 从 `.claude/commands` 迁入；nao 包不含 `commands/` ⇒ `migrate` 天然保留）= 正确行为，**非上游缺口**，不收盘 |
| 待验证项 | V1 `migrate` 对自有资产的误删风险 · V2 `vp check` 迁移前差异文件数基线（`AGENTS.md` 称「稳定 3 文件」vs `fmt.ignorePatterns` 含 `.agents/**` **可能不一致**）· V3 `nue-ui-dev/**` 触碰数=0 · V4 仓内 `npx` 应报 `EBADDEVENGINES` · V5 pre-push 耗时 / 是否允许 `--no-verify`（默认不允许）· V6 `pnpm-lock.yaml` 不应被改（仅 +`.pi/settings.json`） |

### 侦察结论（2026-10-08，排除 `.agents/` 内部后）

| 仓 | AGENTS.md 机制引用 | 自有 skill | skills-lock.json | devEngines | tasks-state/prds/adr | 迁移成本 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **nao-todo-server** | **0 处** | `.agents/skills/frontend-design`（nao 资产，会移除）；**lock 三项无本地目录** | 有：`agent-browser`/`find-skills`/`skill-creator`（**不含** frontend-design ⇒ 无需去重） | 无（无 `package.json`） | 无 / `docs/prds` 本批新建 / 0 | **最低**：`migrate` 即可，零文档改动 |
| **nue-ui**（T508 · 未启动） | L81/L84 有引用；另 5 文件含 `packages/nue-ui-skill/README.md`、`apps/document/skill/*.md`（**需判断是否真讲 nao 机制**——可能是其自有 skill 的安装示例） | `nue-ui-dev`/`agent-browser`/`find-skills`/`skill-creator`/`frontend-design` | 有：`agent-browser`/`find-skills`/**`frontend-design`**/`skill-creator` ⇒ **会被 stripLockDuplicate 去重** | **pnpm 11.21.0**（⇒ `npx` 直跑会被 `EBADDEVENGINES` 拦，**须从仓外执行**） | 无 / 0 / 0（闲置） | 中：需判断自有 skill 文档引用 |

### 通用既定口径（沿用 T506，勿再重新讨论）

- `.pi/settings.json`（pin）**入库**；`.pi/*` + `!.pi/settings.json`
- `.agents/.nao-obsolete/` **加 gitignore**（BR4）
- 迁移命令：`cd /tmp && npx --yes @nathan33/nao-skill@0.12.0 migrate <项目绝对路径> -v`（**不要用 `pnpm dlx`**：会改写 `pnpm-workspace.yaml`）
- 判据 = **机制类归零 + 自有资产保留**（不硬记项数）
- 历史归档文档不改（BR3）；不碰源码/测试/构建配置（BR5）
- 旧脚本调用（如 qq-notify）改 `$NAO_SKILLS/.agents/scripts/…`
### 上游遗留单（独立批次 · 待用户确认开工）

| 编号 | 概要 | 备注 |
| :--- | :--- | :--- |
| [#19](https://github.com/Nathan3303/nao-skills/issues/19) | 修角色别名解析（`ensure arch`/`ensure infra` 报未知角色）+ `check` 加「别名可解析」回归守卫 | 已实测：`ensure` 必须用 canonical id（`arch-designer`/`rd-infra`） |
| [#21](https://github.com/Nathan3303/nao-skills/issues/21) | migrate 收尾：`.nao-migrated` 只写不读（F3）· `migrate` 无条件装 shim 与 minimal 零 shim 特例冲突（F4）· 单行压缩 lock 静默跳过去重（F7） | 由 T506/PR #20 的 arch 评审引出 |
