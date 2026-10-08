# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 归档后的历史见 `docs/prds/` 与 `docs/adr/`；本文件只记**运行时**任务状态，保持精简。

## PM 接续快照（会话重开后**先读本区**）

- 当前阶段：**T509/T510 均已发布并完成发布后核验**（latest = **0.13.0** · 两版产物与 tag 逐字节一致 · 真实安装可用 · 两处修复行为实测通过）；**下一批 T511（三仓 pin 一次升 0.13.0 + 删 `.nao-migrated`）待开工确认**
- 当前 PRD：上游 `docs/prds/2026-10-08-nao-skills-pi-package.md`（已交付）；此前 T506 权威 PRD 在另一仓：`~/Project/nao-todo/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（已归档）
- 当前 PRD：上游 `docs/prds/2026-10-08-nao-skills-pi-package.md`（已交付且已归档）；**T506 权威 PRD 在另一仓**：`~/Project/nao-todo/docs/prds/2026-10-08-nao-fleet-0.12.0-migration.md`（Issue nao-todo#188）
- 未决决策点：无（D1–D8 已拍板；F1/F2 已修；npm 发布已由用户完成）
- 待用户回答：**无**（T508 已开工；PM 重开已定「本会话继续」）；⚠️ 待用户裁量：`close` 无法回收跨仓派生会话的机制缺陷如何处置（并入 #19 / 新开单 / 暂记）
- 既定口径：迁移命令从**仓外**执行（`cd /tmp && npx --yes @nathan33/nao-skill@0.12.0 migrate <绝对路径> -v`）；`.pi/settings.json` pin 入库；`.agents/.nao-obsolete/` 加 gitignore；判据 = 机制类归零 + 自有资产保留；历史归档文档不改；不碰源码/测试/构建配置
- 未派发队列：见下方「待派发队列」+ 「待启动批次」两节（另两仓迁移 · #19 · #21 · #22）
- 待用户回答：**T511 是否开工**（开工确认卡已出）；`close` 的 D7 边界是否另开单（本会话已记报告，非缺陷）
- PM 已自拍（低风险、采 arch 推荐）：P1 存量 `.nao-migrated` → **手动删（并入三仓 pin PR）** · P2 开关 → **init+migrate 都支持** · P3 F7 → **属性级回退+失败告警** · P6 → **授权 arch 拍板后补 ADR** ✅（ADR 已交）
- 📝 小纰漏（已登记，转 T510-ARCH3 顺手修）：ADR 头部写「落地：rd-infra（T511）」，应为 **T510**（T511 = 下游 pin 批）
- ✅ **`close` 修复已真实复用**：T509 派生会话 `qa-T509`/`rd-infra-T509` 经修复后的 `close --task T509 …` **正常回收**（pane %28/%29）—— 不再需要 `tmux kill-pane` 兜底
- ⚠️ **同仓协作纪律（T509 起）**：T509/T510 工作于**本仓**（`/home/nathan/Project/nao-skills`）——RD 建分支后到合并前，**PM 不在本仓做任何 git 写操作**（同一工作区，避免提交落到 RD 分支）；PM 台账提交只在「派发前」与「合并后」两个时点进行
- 会话体检：contextTokens≈236k（窗口 1000k · **~24%**）· 压缩次数=0 · 记于 2026-10-08T14:59Z（T508 闭环时；三批共用本会话）· 批次终态按纪律默认 `ensure --force pm`；用户已定「本会话继续」（ctx 仍远低 40% 且未压缩）⇒ 三批归档完成后再评估是否重开
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
| — | — | （T510 已闭环，见下方归档表；下一批次 T511 = 三仓 pin 一次升 0.13.0） | — | — | — |

> **会话回收（已完成）**：T507 派生会话 `qa-T507` / `rd-infra-T507` 已回收（验收通过即回收）。
> ⚠️ **机制缺陷发现（2026-10-08，T507/T508 各复现一次）**：`nao-fleet.sh close` 的**跨仓派生会话回收**存在两层问题：
> ① **宿主定位假阴性**：`close --task <批次> <别名>`（在 nao-skills 仓内执行、目标会话在另一仓）→ 报「未运行（无需回收）」，但 `tmux list-panes` 实际存活且标题格式正常（`π - qa-T508 - nue-ui`）⇒ **回收失败且不报错**，需 `tmux kill-pane` 手工兜底。
> ② **派生名不可作目标**：`close --task T508 qa-T508` → 「未知角色」（只接受 roles.yaml 里的角色名）。
> 正常的部分：**tasks-state 闸门工作正常**（未归档时拒收并提示「先把 T 移入已验收/已归档」）；`status` 的残留识别也正确。
> **尚未开单**，待用户裁量是否并入 #19 或新开（PM 未自做修复：零代码边界）。
> 📌 **台账写法约定（实测）**：`nao-fleet.sh status` 的残留识别按**表格单元格全等**匹配任务编号（`task_state_class()`）⇒ 进行中行必须出现一个**裸批次号**单元格（如 `T508`）；仅写 `T508-QA` / `T508-RD` 会被归为「仅散文提及」并误报残留。

## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |
| T508-RD3 | **done(lite) · 已合并**：`master` **`b0a33899`** =「迁移 nao 机制到 0.12.0 pi 包形态，退役逐字节 sha 校验 (#73)」· 本需求**恰好 1 条** · **无 `wip()`** · 工作区干净 · 远端+本地分支均已删 · PR **MERGED** · CI 1m36s pass（等绿后才合）· 合并后 deploy run success · **披露**：首试被「Draft 不可合」拒（机械前置）→ 自行 `gh pr ready 73` 后重试成功（未改标题/正文；PM 派单漏写该步，RD 补位） | PR [#73](https://github.com/Nathan3303/nue-ui/pull/73) | PM 已独立复核 4 项自检（1 条 / 0 `wip()` / 分支 0/0 / MERGED `b0a33899`） |
| T508-RD2 | **done(lite)**：`912cfe44` `wip(T508): PM 验收结论 + PRD 索引` —— 自检 `git diff --name-only HEAD~1..HEAD` = **恰 2 文件**（PRD M + `docs/prds/README.md` A）· 提交前后 `vp fmt --list-different .` 均 **0 文件**（fmt 变化仅表格 dash 对齐 + 末换行；去空白后逐行一致）· pre-push 跑全量 358 例/20.65s（未用 `--no-verify`）· 已推送（`1be46327..912cfe44`）· **未合并** | 分支 `feat/72-nao-fleet-migration` · PR [#73](https://github.com/Nathan3303/nue-ui/pull/73) | PM 已独立复核（恰 2 文件 + §11/索引内容与写定一致）→ **已发合并授权**（RD3） |
| T509-QA | **done(lite)**（用例先行）：脚本 461 行 + 基线报告 · 基线 `--baseline` 18P/10F/5S（FAIL 属预期）· **两条可证伪断言**：三构造夹具下 `check` 均 **rc=0**（守卫缺失）；跨仓 `close --task T508 qa` → **rc=0「未运行」而 pane 存活** · **额外发现第三症状**：`close qa-T508`（无 `--task`）rc=0 静默 no-op · **根因定位**：`ROLE_WS=「.」` ⇒ `find_pane_for` 三级全按本仓匹配 + `offline_verifiable` 真 ⇒ `log+return 0` · 基线：`npm test` 0 · t4 **8 用例/109 断言/0 红** · 三仓 `check` 全 0 | `docs/reports/2026-10-08-T509-*.{sh,md}` | 已随 QA2 入库（`c3b3c2d`） |
| T509-RD | **done(full)**：`febdf8f`（PRD 入库）+ `23d581c`（修复）· 三缺陷全修（别名方向 / `check_alias_resolution` 五点守卫 / `find_pane_for_any_repo` 跨仓定位 + 非静默 + 派生名支持）· 门禁：`check` 0（roles=6/files=43）· `npm test` 0 · t4 **9 用例/136 断言/0 红**（基线 109）· 三仓 NFR4 零影响 · AC1 实拉 pane `%34`/`%35` 已收尾 · AC3 真回收 pane `%36` · 0.12.1 + notes | PR [#23](https://github.com/Nathan3303/nao-skills/pull/23) | 2 项口径裁定已答复（AC8 正则误报→改基线清单比对；AC7 预合并→WARN） |
| T509-QA2 | **done(lite)**：verify **34P/0F/3S/1W** · `--with-tmux` **35P/0F/2S/1W**（WARN=预合并 AC7）· 与 RD **零分歧** · AC1 实拉 pane `%42`/`%43` + 角色卡注入证据 + **用修复后 `close` 收尾成功** · AC3 真回收 pane `%40` · 静默失败 3/3 转非静默 · 门禁连跑一致（136/136） | `c3b3c2d` · PR [#23 comment](https://github.com/Nathan3303/nao-skills/pull/23#issuecomment-6063745977) | 建议 T510 做一次真实跨仓回收闭环（本机无真实跨仓会话） |
| T509-RD2 | **done(lite) · 已合并**：`gh pr ready 23` → `gh pr merge 23 --squash --delete-branch` → `main` **`bcac6f0`**「修复角色别名失效、补齐 check 守卫，并支持跨项目会话回收（#19） (#23)」· 本需求**恰好 1 条** · **无 `wip()`** · 工作区干净 · 远端+本地分支已删 · PR **MERGED** | PR [#23](https://github.com/Nathan3303/nao-skills/pull/23) | PM 已独立复核 4 项自检 |
| T510-RD | **done(full)**：F3/F4/F7+B2 全落地 · `check` 0（roles=6）· `npm test` 0 · t4 **10 用例/179 断言/0 红**（基线 136）· QA 脚本 **60/60** · 三仓 `check` 0 · 真仓 `/tmp` 副本 re-migrate 零变化（shim md5+mtime 不变、未读写 `.nao-migrated`、仅 `.nao-version` 差）· 0.13.0 + notes · 4 条提交（路径级）· QA 产物未纳入 | Draft PR [#24](https://github.com/Nathan3303/nao-skills/pull/24) | 2 项转下游：ADR「已废弃」句口径 → ARCH3（定为保留并拆分）· 60 vs 59 断言口径 → QA2（已澄清） |
| T510-ARCH3 | **done(full) · 终签 GO**（v0.13.0 @ `d1ff9d0`）：ADR 决策 1–6 与判定式 **8/8 逐项核验一致** · 无 ≥ 中严重度偏差 · 5 条低/极低边界（D1–D5）· 要求合并前补 ADR 文字修正 C1–C4 + QA 产物入库（BL1） | 回执内容（已录 PRD §8.1） | 已执行：RD3 落 C1–C4 + 已废弃句拆分 + PRD §8.1/§11 |
| T510-QA2 | **done(full)**：独立复跑 **64/64 PASS rc0**（`--baseline` 翻面 25/13 预期）· 四条断言整体翻面 · F4 判定式 5 例（含 **`.pi/**` 硬排除专项**）· F7 失败路径 2 形态（均 rc0 + 字节不变 + 恰 1 行 warn）· 三仓 + `/tmp` 副本回归 · 门禁连跑两次一致 · 落库 `90a73bf`（仅 2 文件） | PR [#24 comment](https://github.com/Nathan3303/nao-skills/pull/24#issuecomment-6065005463) | 2 条非阻塞观察已记边界（D6 failWarn 文案本批不改 · ADR 标签已修） |
| T510-RD3 | **done(lite) · 已合并**：`b559720`（恰 3 文件：ADR + ADR 索引 + PRD）→ `gh pr ready 24` → `gh pr merge 24 --squash --delete-branch` → `main` **`6eb9b74`**「迁移工具收尾：按需写 shim + lock 去重不再看排版/不再被跳过（v0.13.0） (#24)」· 恰好 1 条 · 无 `wip()` · 工作区干净 · 分支已删 · PR **MERGED** | PR [#24](https://github.com/Nathan3303/nao-skills/pull/24) | PM 已独立复核 4 项自检 |
| T510-QA | **done(full)**（用例先行）：脚本 `docs/reports/2026-10-08-T510-migrate-verify.sh` + 基线报告 · `--baseline` **34/34 全绿**（缺陷全在场）· 默认模式 **30P/29F**（预期，修复后期望 **59/59**）· **四条可证伪断言（0.12.1 实测）**：A1 `.nao-migrated` 被写入 + `MIGRATED_FILE` 2 处 + 存量 `0.0.0-old` 被覆写 · A2 minimal 夹具凭空出现 shim · A3 单行 lock 静默跳过去重（告警 0 行）· A4 B2 无 legacy 时去重也静默跳过 · 门禁基线：`check` 0 · `npm test` 0 · t4 **9 用例/136 断言/0 红** | `docs/reports/2026-10-08-T510-*.{sh,md}`（untracked，待 QA2 入库） | **V1 裁定（PM 采纳）**：不快照 `nao-todo-minimal`（整树 488K / 相关 6 文件 36KB 且会随上游漂移），改用**等价合成夹具**（3 占位 role card + 中性 docs）；V4 同理由用合成「已迁移仓型」，**真实三仓回归改由 QA2 跑 `check` + /tmp 副本 re-migrate** |
| T508-QA2 | **done(full)**：独立复跑 **PASS=133 / FAIL=0 / WARN=0**（1m48s，被测 `1be46327`；含真树缺包负向 + worktree 回滚 5 提交 + 幂等）· 六项门禁全 0（`test:run` 33/358/22s · `vp fmt --list-different .` 0 文件 · `vp check --no-fmt` 468 文件/0 错）· 自测：顶层 6 项 · 裸引用 0 · lock `614a9a49…` = 原−6 行 · `nue-ui-dev` 指纹不变 · `git ls-files .pi` 恰 1 · 非范围命中 0 · 2 条 QA 提交已落库（`4eda198e`/`1be46327`） | PR [#73 comment](https://github.com/Nathan3303/nue-ui/pull/73#issuecomment-6062495117) · `docs/reports/2026-10-08-T508-qa-report.md` | 3 项口径订正（B 类 **6 文件** · 逐行 22/8 · 判据不要求字样消失）已落 PRD；披露 1 项：**未真跑真实角色 `ensure <role>`**（共享宿主 pane 无法安全归属 + `close` 缺陷）→ 以 `status`+守卫+`roles=6` 覆盖，PM **接受**（与 RD 真跑 `ensure rd-infra` 组合覆盖 AC6） |
| T508-RD | **done(full)**：3 条 `wip(T508)` 已推 → Draft PR [#73](https://github.com/Nathan3303/nue-ui/pull/73)（base `master`）· `migrate` rc=0（移除 23 项 / 备份 44 文件）· `AGENTS.md` 改写后**裸引用 0（基线 5）**· lock `48c87184`→`614a9a49` 与「删 `frontend-design` 6 行」逐字节相等 · `nue-ui-dev` 8 文件指纹 `156dec98…` 不变 · `commands/commit.md` `049d054d…` 不变 · 九项门禁全 rc=0（`test:run` 358 例/20.4s · `vp check --no-fmt` **469→468**（差额=被移除的 `intercom-probe.mts`）· **`vp fmt --list-different .` = 0**）· 幂等（二次 install/migrate/check effect=0）· 缺包 fixture rc=2 + 恰 1 行 `DEGRADED:` · worktree 回滚后 `check` rc=0 · PRD fmt 仅空白（75/75，去空白 diff 零差异）· CI pass 1m28s · 未用 `--no-verify` | PR [#73](https://github.com/Nathan3303/nue-ui/pull/73) | 披露 3 项：① AC3 措辞用「机制资产目录」指代仓内 `.agents/**` 以避免引入裸引用 token（PM 已复核：准确且不误导，接受）② PRD 内 2 处机器特定字样属 PM 原文（只许 fmt 不改字）③ `ensure <role>` 真拉 tmux pane（情报，供 #21 参考） |
| T508-QA | **done(full)**（用例先行）：脚本 `docs/reports/2026-10-08-T508-nao-fleet-migration-verify.sh` + 报告 · 基线 **64P/0F/4W**（58s）· 迁移后模式现树 **35P/53F**（预期 RED）· 门禁基线：`test:run` **33 文件/358 例/0 红/21s** · `check:lf` 9s · `vp check --no-fmt` **469 文件/0 错** · **V2 实测**：全树 fmt 差异 **1 文件 = 本批 PRD 自身**（入库口径 0）；`.agents/roles.yaml`/`intercom-probe.mts` 被 `fmt.ignorePatterns` 的 `.agents/**` **排除** · `nue-ui-skill.mjs` 已 fmt 干净 ⇒ AGENTS.md「稳定报 3 个文件」**确属过期** · **V4**：仓内 `npx` 全拦（`EBADDEVENGINES`）· **V5**：pre-push 358 例≈20s，无需 `--no-verify` | `docs/reports/2026-10-08-T508-*.{sh,md}`（**untracked**，待随分支入库） | PM 已裁定 4 项：① AC3 判据 = **裸机制引用 5 行 → 0 行**（非 0→0）② §3 引用面改**逐行口径 22 行/8 文件** ③ nao `*.md` = **13 个**（非 14）④ **AC5 把本批 `docs/**` 纳入 fmt 判据（= 0 文件）**，已全部落 PRD |
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
| **T510** | **验收通过 · 已合并归档**（本仓 `migrate` 收尾 F3/F4/F7 + B2 → 0.13.0）：AC 全过 · 缺陷 0 · F3 写入点归零 · F4 判定式（`.pi/**` 硬排除，arch 实测 8/8 核验）· F7 属性级回退 + 三态告警 · B2 去重提前 · t4 **10 用例/179 断言/0 红** · QA2 **64/64** · **arch 终签 GO** · 三仓 + `/tmp` 副本零回归 · squash **`6eb9b74`**（`main` 恰好 1 条、无 `wip()`）· **tag `v0.13.0` + Release 已发** | 本仓 · PR [#24](https://github.com/Nathan3303/nao-skills/pull/24) · Issue [#21](https://github.com/Nathan3303/nao-skills/issues/21) | 6 项已知边界（D1–D6）已录 PRD §8.1 · npm 发布待用户（**先 0.12.1 后 0.13.0**）· 遗留转 T511（三仓 pin + 删 `.nao-migrated`）· B1/D6 另议 |
| **T509** | **验收通过 · 已合并归档**（本仓工具修复批 #19：别名解析 + `check` 守卫 + 跨仓 `close` 回收）：AC1–AC8 全过 · 缺陷 0 · 别名方向修正 + **真机实拉**（pane `%34`/`%35`/`%42`/`%43`，角色卡注入已证）· 五点守卫夹具全非 0 且指名 · **跨仓真回收 2 次**（pane `%36`/`%40`）+ 静默失败 3/3 转非静默 · t4 **9 用例/136 断言/0 红**（基线 109）· 三仓 NFR4 零影响 · squash **`bcac6f0`**（`main` 恰好 1 条、无 `wip()`）· **tag `v0.12.1` + Release 已发** | 本仓 · PR [#23](https://github.com/Nathan3303/nao-skills/pull/23) · Issue [#19](https://github.com/Nathan3303/nao-skills/issues/19) | npm publish 待用户 · 遗留转 T510：真实跨仓回收闭环 + README 别名表指针改 `$NAO_SKILLS/…` |
| **T508** | **验收通过 · 已合并归档**（仓：nue-ui 迁移到 0.12.0 · 路线 A 最后一批）：AC1–AC8 全过 · `migrate` rc=0（移除 23 项 / 备份 44 文件）· **裸引用 5 → 0** · lock 去重逐字节相等 · `nue-ui-dev` 8 文件指纹不变 · 九项门禁全 0（`vp fmt --list-different .` = 0）· 幂等 · 负向（缺包 rc=2 + 恰 1 行 `DEGRADED:`）· worktree 回滚实测 · QA2 **133P/0F/0W** · squash **`b0a33899`**（`master` 恰好 1 条、无 `wip()`）· CI 双 job 绿 · 非范围命中 0 | `~/Project/nue-ui` · PR [#73](https://github.com/Nathan3303/nue-ui/pull/73) · Issue [#72](https://github.com/Nathan3303/nue-ui/issues/72) | 3 处口径订正（B 类 6 文件 / 逐行 22/8 / 判据不要求字样消失）· AC6 组合覆盖披露 · RD 首试合并被 Draft 拒后自行 `gh pr ready`（PM 派单漏写）· 本仓无 CodeGraph 索引 |
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

## 已闭环批次 · T508：nue-ui 迁移（**已验收并合并**）

> 结果：PR [#73](https://github.com/Nathan3303/nue-ui/pull/73) `--squash` → `master` **`b0a33899`**（恰好 1 条 · 无 `wip()` · 分支已删 · CI `Test and build NueUI packages` pass 1m36s · 合并后 deploy run success）
> 验收：AC1–AC8 全过 · 缺陷 0 · QA2 独立复跑 **133 PASS / 0 FAIL / 0 WARN** · 六项门禁全 0 · PM 独立复核变更 52 文件未越界
> 口径订正：裸引用判据 **5 → 0**（非 0→0，且不要求字样完全消失）· §3 逐行 22 行/8 文件（B 类 **6 文件**）· nao `*.md` = **13 个** · AC5 把本批 `docs/**` 纳入 fmt 判据（= 0 文件）
> 特色项：`AGENTS.md` 机制段改写（退役逐字节 sha 判据 + fmt 豁免段整段作废，改为 pin + `$NAO_SKILLS` 指针）· 自有资产零丢失（`nue-ui-dev`/lock 3 技能/`commands/commit.md`）· `vp check --no-fmt` 469→468（差额 = 移出的 `intercom-probe.mts`）
> AC6 覆盖披露：RD 真跑 `ensure rd-infra` rc=0；QA 出于共享宿主安全取舍未真跑真实角色 → 以 `status`+守卫+`roles=6` 覆盖（PM 接受）
> 过程披露：RD 首试合并被「Draft 不可合」拒（机械前置），自行 `gh pr ready 73` 后重试成功（PM 派单漏写该步，RD 补位）；未用 `--admin/--auto`

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
| （未开单·候选） | `nao-fleet.sh close` 跨仓派生会话回收：宿主定位假阴性（报「未运行」但 pane 存活）→ 需手工 `tmux kill-pane` | T507 / T508 各复现一次；另附：`ensure <role>` 会真拉 tmux pane（AC6 演练后需收尾）—— 是否并入 #19 待用户定 |
