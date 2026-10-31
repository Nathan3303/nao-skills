# PRD：舰队闸门小批（跨仓残留误报 + 合并前 push 核对 + 探针识别放宽）

- 状态：已交付并发布（v0.20.2）· Owner：PM · 更新：2026-10-31
- 指针：Issue [#56](https://github.com/Nathan3303/nao-skills/issues/56) · 来源 = T533 收尾实测（O5/O4/O2 转办）· L1 复盘 `docs/reports/2026-10-30-T533-retro.md`
- 优先级：高（A 项安全类）· RICE 结论 ≈ 30（附录）

## TL;DR（≤5 行）

- **做什么**：① 修「本仓 `status` 把他仓派生会话报成本仓残留、并提示跨仓回收」的误杀隐患 ② 合并闸门补「分支无未推送提交」核对 ③ 放宽一次性探针的文档提交识别口径。
- **给谁**：PM（闸门与验收）、所有跑舰队的仓（A 项安全面）、后续按新规则执行文档随 PR 的角色。
- **成功标准**：A 项他仓会话在本仓 `status` 中不再被报残留且**零影响**；B 项四处文本齐备；C 项探针自证 PASS 且覆盖限制显式标注；`check`/`npm test` rc=0。
- **不做什么**：不删 `close` 的跨仓定位能力；不改 `tasks-state` 分类语义核心（`task_state_class()`）；不动 `tests/t4`。

## 一、问题证据

- **A 项（实测 · 2026-10-30）**：本仓 `nao-fleet.sh status` 输出 `· qa-T596  ! 残留（tasks-state 无 T596 记录）→ 核对后 close --task T596 qa`；同一提示在更早时点报的是 `qa-T580`。`intercom list` 实测两者 **cwd = `/home/nathan/Projects/nao-todo`**，均属**另一仓库**任务。
- **A 项危害链**：`status` 按 tmux 标题全机匹配派生会话，再用**本仓** `tasks-state` 判归属；而 `close` **支持跨仓定位**（usage 明写）⇒ 提示的第二半句直接引导用户执行 `close --task T596 qa`，**实际回收的是 nao-todo 的在飞会话**（误杀：丢上下文、断交付）。
- **B 项（实测 · 2026-10-30 · 自曝）**：T533 中 PM 在需求分支提交 `da34de5`（三项收口）后**未 push 即授权合并**，RD 合并远端 head ⇒ 该提交成孤儿，main 缺 3 项收口（详见 L1 复盘）。根因 = 合并闸门四条核对**全部以远端为准**，本地提交不在视野内。
- **C 项（实测 · QA R2）**：`docs/reports/2026-10-28-docs-ride-pr-probe.sh` 只认半角 `(` + 半角 `:` 的 `docs(<编号>):`；全角括号、全角冒号、无编号 `docs:`、大写 `Docs(` 均漏判 PASS（假阴性），且「任务提交完全无 docs」也 PASS —— 覆盖限制未在输出中声明。
- **5 Whys（A）**：误报 ← 残留判定只用 tmux 标题全机匹配 + 本仓台账 ← 派生会话名（`<别名>-<编号>`）不含仓信息 ← `close` 跨仓定位是刻意能力（回收他仓旧会话）← 两处各自合理、合起来产生「本仓提示引导跨仓误杀」的危险组合。

## 二、目标指标

- **北极星**：误杀概率 0 —— 本仓 `status` 的残留提示**永不**指向他仓会话；即便用户照提示操作，也只会命中本仓会话或（最坏）拒绝执行。
- 预期：他仓派生会话在本仓 `status` 中**不出现**于残留节（或出现且明确标注「他仓会话，勿在本仓回收」）。
- 观测：跨仓夹具（临时 `tasks-state` + 他仓会话名）下 `status` 输出断言；`check` / `npm test` 精确数字。

## 三、范围 / 非范围

- **范围**
  1. **A · 残留判定加仓维度**：`nao-fleet.sh` 的残留判定改为「只统计**本仓**派生会话」—— 判据须由 arch 定稿（候选：会话 pane 的 `pane_current_path` 与仓根比对 / `NAO_SKILLS` 或 `--task` 记录仓 / 名册文件名带仓栈）；**提示文案同步**：他仓会话若仍展示，必须显式「他仓会话，勿在本仓回收」，且**不得**给出可直接执行的 `close --task` 命令。
  2. **B · 合并闸门 push 核对**：`product-manager.md` §六 合并闸门 + `checklists/pm.md` 合并项 各 +1 条（三条命令 + 判据），并指回 L1 复盘。
  3. **C · 探针识别放宽**：`docs/reports/2026-10-28-docs-ride-pr-probe.sh` 支持全角 `（）`/`：`、无编号 `docs:`、大小写变体；输出显式声明「任务提交完全无 docs」不判 FAIL（覆盖限制）。
- **非范围**（各带理由）
  - 不删 `close` 的跨仓定位能力：理由 回收他仓旧会话是既有刻意能力（T516/T509 相关回归用例依赖），删能力属破坏性变更。
  - 不改 `task_state_class()` 判定语义：理由 T519 已把该函数定为**契约不变量**（`docs/prds/2026-10-14-tasks-state-slim.md` AC4 探针），本批只改「会话归属」维度。
  - 不改 `ensure` 的会话命名格式（`<别名>-<编号>`）：理由 改名会破坏 `close --task` 与既有回归用例；仓维度信息改用可查询属性（pane cwd）承载。
  - 不动 `tests/t4`：理由 本批验证走一次性只读探针（V1），常态用例另议（`T534-O1`）。
  - 不处理「本仓与他仓同名任务编号」的歧义：理由 归属靠 pane cwd 判定后歧义消失，无需额外编号空间。

## 四、用户场景

- **画像 A（PM，多仓并行）**：n 个仓各有派生会话；在本仓跑 `status` 只看本仓残留，不再被他仓会话干扰，也不会照提示误杀。
- **画像 B（PM，批间验收）**：贴验收评论前跑三条 push 核对命令，本地未推送提交当场暴露 ⇒ 孤儿提交在合并前被发现。
- **画像 C（接手者/QA）**：探针识别口径放宽后，`docs(T123):`、`docs：T123：`、`docs:` 等写法不再假阴；输出里能看出「无 docs 提交」属未覆盖而非通过。
- **关键路径**：`status` → 残留节 → 判定归属 → 提示（本仓可执行 / 他仓仅告知）。
- **页面状态**：不适用：命令行输出，无 UI。

## 五、业务规则

- **BR1 归属优先于名称**：残留判定的第一判据是**会话所属仓**，不是会话名/编号；名称匹配只在同仓内作为补充。
- **BR2 提示即可执行性**：凡提示里给出 `close ...` 命令，该命令必须**只影响本仓**；他仓对象只做告知（「他仓会话，勿在本仓回收」），不给可复制命令。
- **BR3 能力不缩水**：`close` 跨仓定位保留；本批只收紧「`status` 的提示与判定」，不改 `close` 语义。
- **BR4 闸门可判**：B 项三条命令必须逐字可执行并给判据（任一不满足 ⇒ 不得贴验收评论/授权合并），不写「注意一致性」这类不可判要求。
- **BR5 单源**：push 核对条款单写在 `checklists/pm.md`，PM 卡 §六 只给指针（避免双写漂移）。
- **BR6 探针诚实**：C 项探针必须在输出中列出**未覆盖情形**（不得让「未覆盖」看起来像「通过」）。

## 六、NFRs

- **安全**：本批 A 项的验收必须含**他仓会话零影响**的双向证据（误杀防护）。
- **可核性**：全部判据可机械核（`status` 输出断言 + 三条 git 命令 + 探针 PASS/FAIL 计数）。
- **兼容性**：单仓场景行为不变（无他仓会话时 `status` 输出逐字不变）。
- **不适用**：性能 / 并发 —— 理由 判定维度变化不引入额外 I/O 循环（pane cwd 查询已在名册路径内）。

## 七、AC

- **验证接缝**：一次性只读探针 `docs/reports/2026-10-30-T534-guards-probe.sh`（不进 `tests/`）+ `nao-fleet.sh check` + `npm test` + `tests/t4/run.sh` 全量（A 项触及 `nao-fleet.sh`，必须跑常态用例）。
- **AC1（主路径 · A 项归属判定）**：构造他仓派生会话名（`<别名>-<编号>`，其 pane cwd = 临时目录模拟他仓）⇒ 本仓 `status` **不把它列入本仓残留节**（或列入但标注「他仓」且**无** `close --task` 可执行命令）；同一夹具下**本仓**派生会话（cwd = 本仓）仍按原样报残留并可被 `close --task` 回收。
- **AC2（负向闭环 · 零误杀）**：① 他仓会话在 A 项改动后**进程/pane 存活**（改动只读，不触任何 pane）；② 负控：把归属判据反转为「恒真（全部算本仓）」⇒ AC1 首句 FAIL；反转为「恒假（全部算他仓）」⇒ 本仓残留检测失效，`close --task` 闸门用例 FAIL（须点名）；③ `tests/t4` 全量 rc=0（含 `cases/09`、`cases/13`、`cases/15` 相关残留/回收用例）。
- **AC3（边界 · B 项闸门文本）**：`checklists/pm.md` 合并项含三条命令 + 判据（`rev-list --count` = 0 · `status --porcelain` 空 · `HEAD == @{u}`），PM 卡 §六 仅指针（BR5）；文本明确适用「在分支上提交过的任何角色」。
- **AC4（异常 · C 项探针口径）**：探针对 `docs(T1):` / `docs（T1）：` / `docs:` / `Docs(T1):` 四种写法均判为**文档提交**（与他仓/独立 PR 的组合负例仍 FAIL）；输出含「未覆盖：任务提交完全无 docs」一行；自证 = 变异 2 次（收窄正则 ⇒ 四种写法里至少 2 种翻为漏判；删未覆盖声明行 ⇒ 专项断言 FAIL）。
- **AC6（设计一致性 · 文档单源与 ADR）**：新增 ADR `docs/adr/2026-10-31-fleet-status-repo-attribution.md`（≤60 行 · 必写 5 节 · 含「三段判据 / 优先级 / fail-closed」决策 + 三个不采纳备选及理由）· 评审报告 `docs/reports/2026-10-31-T534-arch-review.md` 入库 · `pm-operations.md` 残留自检条目加半句「他仓会话单列、勿在本仓回收」（**单源**：`checklists/pm.md` 只给指针，不双写）· `AGENTS.md` 零改动。
- **AC7（边界 · 逐字等价与路径陷阱，arch ⑤⑦⑧）**：① **兼容机械证明**：以 `git show main:.agents/scripts/nao-fleet.sh` 存旧版，在同一「仅本仓 pane」夹具下，改前/改后 `status` 输出**逐字相同**（diff 为空）；② **组件级前缀**：pane cwd = `<夹具根>-sibling` 必判**他仓**（裸 string prefix 会误判本仓）；③ **子目录锚**：在 `<夹具根>/.agents` 内跑 `status`，本仓 pane 仍判本仓（`rev-parse --show-toplevel` 并入锚集）；④ **软链归一**：经 symlink 指向夹具根的 pane cwd 判本仓；⑤ 判据抽为单行谓词 `repo_contains_path <root> <cwd>`，供 AC2 单行变异。
- **AC5（设计一致性 · 版本与门禁）**：`nao-fleet.sh` 改动后 `check` rc=0（roles=6 · files 精确数字须报旧→新）· `npm test` rc=0 · `tests/t4/run.sh` 全量 `PASS/FAIL/SKIP/DEGRADE` 精确数字；PM 卡若因 B 项 bump 则 `version` 递增且 `updated` 更新 + 广播登记；`AGENTS.md` 仅在有项目级需要时加 1 条指针（否则零改动并说明）。

## 八、上线闭环

- **灰度**：单仓用户无感（无他仓会话时输出不变）。
- **监控**：多仓并行时 `status` 残留节的正确率（下批实测 1 次）；误杀告警 = 他仓会话被本仓回收（0 容忍）。
- **回滚**：`git revert <main-squash-sha>`（单条）。
- **发布**：**v0.20.2（PATCH）**；tag 指向 main 合并提交；release notes 落 `docs/releases/v0.20.2.md`；**npm 重发 = 待拍板**（`nao-fleet.sh` + 机制文本在包内 ⇒ 倾向重发）。

## 九、变更治理

- **流程**：Issue [#56](https://github.com/Nathan3303/nao-skills/issues/56) → 分支 `feat/56-fleet-guards` → PM 在分支路径级提交文档（`docs(T534):`）→ RD `wip(T534):` → QA 独立复核 → PM 验收 → RD squash → 发布 v0.20.2。
- **本批夹带**：T533 遗留的 `docs/tasks-state.md` 工作区改动（npm 0.20.1 核验事实）**随本批 PR 首次提交**（BR5：发布后事实进下一任务 PR）。
- **文件归属**：`nao-fleet.sh` + 探针 + 卡/清单 = rd-infra；本 PRD + `tasks-state` + PR 验收评论 = PM；QA 报告由 QA 落盘随 PR 提交。
- **版本记录**：v0.20.2 = 本批（A 安全修正 + B 闸门 + C 探针口径）。
- **Hotfix**：24h 内补单；已 push 的 tag 不删。

## 附录：战略筛子 / RICE / 待拍板

- **战略筛子**：命中（安全 + 闸门可判性）；不做则多仓并行时持续存在误杀提示。
- **RICE**：Reach 8（多仓舰队使用者）× Impact 3（安全 · 误杀代价高）× Confidence 0.85 ÷ Effort 0.5 人日 ≈ **30** ⇒ 高优先。
- **D1（用户 2026-10-30 · ask-me）**：A 项判据方向 = **按 pane 实际工作目录判仓**（拿 pane cwd 与仓根前缀比对，只把本仓内 pane 计入残留）；具体实现与边界由 **arch 轻量评审定稿**。
- **D2（用户 2026-10-30）**：**走轻量 arch 评审**（A 项触及 `ensure`/`status`/`close` 三处语义）。
- **D3（用户 2026-10-30）**：**npm 重发 0.20.2**（判据 = registry 实测 `latest` + `dist.integrity` 与本地 tarball 逐字节一致）。
- **D4（用户 2026-10-30）**：**开工**（rd-infra 实施 A/B/C + qa 独立复核；分支 `feat/56-fleet-guards`）。
- **D5（PM 2026-10-31 · 采纳 arch ①）**：他仓会话**列出并标注**（`~ <名>（他仓 @ <仓名>）他仓会话，勿在本仓回收`，整行不含可执行 `close` 命令），**不静默隐藏**；归属不可判定 ⇒ `? <名>（归属不可判定）→ 人工核对`（fail-closed，T530 对偶）。
- **D6（PM 2026-10-31 · 采纳 arch ②）**：**不给 `close` 加「跨仓需 `--force`」硬闸**（BR3；会破坏 `cases/09` 跨仓真回收契约）。
- **D7（PM 2026-10-31 · 采纳 arch ③）**：`pm-operations.md` 残留自检半句文案**随本批 PR** 由 rd-infra 改，**单源在 `pm-operations.md`**，`checklists/pm.md` 只给指针。
- **D8（PM 2026-10-31 · 采纳 arch ⑥）**：**出 ADR**（`docs/adr/2026-10-31-fleet-status-repo-attribution.md`）+ 评审报告入库；两份文档由 **arch 落盘并路径级提交到本需求分支**（`docs(T534):`），rd-infra 只写实现与探针。
- **必进验收（arch 条件）**：④ 不可判定 fail-closed；⑤ 变异与逐字等价两条机械证明（已并入 AC1/AC2/AC7）。
- **arch 已定稿要点（实现须照此，勿另立）**：本仓锚 = `pwd -P` + `git rev-parse --show-toplevel`（当 cwd 的严格祖先时并入；**不用** `roles.yaml` workspace）；pane cwd 取 **一次** `tmux list-panes -a -F '#{pane_id}\t#{pane_title}\t#{pane_current_path}'` 快照建 name→(pane,cwd)（禁逐名 `find_pane_for` 的 O(N) tmux 调用）；兜底名册 `intercom_roster` 的 name→cwd（优先级 pane > 名册，冲突取 pane 不 warn）；物理归一（`pwd -P` → `readlink -f` → 原串）+ **组件级**前缀；同名多 pane：本仓 ≥1 ⇒ 本仓，本仓 0 且他仓 ≥1 ⇒ 他仓，两侧皆无 ⇒ 不可判定；`status` **先定归属再查本仓台账**（本仓行 cls tag 逐字不变）；`close` 与 `ensure` **零改动**。

- **修订：2026-10-31 交付闭环** —— Issue [#56](https://github.com/Nathan3303/nao-skills/issues/56) · PR [#57](https://github.com/Nathan3303/nao-skills/pull/57) squash `df3f2cb`（main 恰 1 条 · 无 `wip()` · 分支删净）· arch 轻量评审 `done(full)`（有条件可行 → D5–D8 采纳） · QA `done(full)` **GO**（报告 `docs/reports/2026-10-31-T534-qa-verify.md`）· AC1–AC7 全过 · 探针 `PASS=42 FAIL=0` · `check` files 50（50→50）· `tests/t4` 17/17 SKIP=0/DEGRADE=0 · PM 卡 **v30**（红线 34 / 清单 43） · tag `v0.20.2` + Release 已发 · npm 0.20.2 已重发并核验。遗留：`T534-O1`（t4 常态覆盖）/`T534-O2`（case16 flake），到期 2026-12-31。
