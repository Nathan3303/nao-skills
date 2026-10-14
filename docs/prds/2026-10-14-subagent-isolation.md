# PRD：子代理会话（`subagent-*`）在 `status` / `close` 中的显式识别与排除

- 状态：**已交付并合并（待发布 v0.18.3）** · Owner：PM · 更新：2026-10-14
- **验收记录** = 2026-10-14 PM 验收**通过（AC2–AC8 全过）**：PR [#43](https://github.com/Nathan3303/nao-skills/pull/43) squash **`fbddd0d`**（main 恰 1 条 · 无 `wip()` · 分支删净）· QA 独立复跑 **GO**（`check` rc=0 ×2（roles=6 · files=46）· `npm test` rc=0 · 108s · **15/15 PASS · 断言 313→360** · SKIP=0/DEGRADE=0/NOTE=2 · 空载 `test:t4:full` rc=0）+ 独立探针 **36/36** + 负控 M-A（恰 T8 2 条）/ M-B（恰 T3×2+T4×1）+ 紧凑 JSON 名册不塌缩 · 验收评论见 PR #43
- 开工确认卡（2026-10-14 · ask-me 用户拍板 5 项）：D1 范围 = **完整**（`status` 汇总行 + `close` 显式拒绝且点名 + `running`/`ensure` 负向护栏 + `check` 守卫 + `cases/15` + 两份 QA 报告落盘）· D2 E2 = **收口**（`claimed` 排除 `^subagent-` 条目 ⇒ 非静默优先）· D3 arch = **需要（轻量）**· D4 立项 = **降级 `nao/subagent-isolation` + v0.18.3（PATCH）**· D5 npm = **发布时重发 0.18.3**（用户执行 `npm publish`）
- 指针：上游 = 用户 2026-10-14 选定台账待裁量项 **⑥（T512-①）** · 来源证据 `docs/reports/2026-10-12-pi-subagents-compat-review.md` §2.2 / §2.3 / §4.3 / 附录 A · 成熟度判定 = 命中 `pm-to-spec.md` §一.4（用户明示 + QA 已做现状复现）· **QA 接缝复核** = 2026-10-14 `done(full)`（采 **C1** 新增 `cases/15`；**现状危害面 ≈ 0**，但安全是**隐式的**；发现 1 个真边界缺口 **E2**）
- **arch 结构评审（轻量 · 用户 D3 拍板需要）** = 2026-10-14 arch-designer `done(full)`：**有条件可行**，6 项全定稿 —— 排除点置于 `cmd_close` 解析**第一条**（只查 `$target`、不查 `--task` 值、`--force` 不旁路）· `status` 汇总行**逐字措辞 + 派生节末独立行 + N=0 不打印**· **E2 必须改「条目感知」claimed**（纯值提取无法按条目名排除）且**只改 `unattributed_pi_panes`**· `check` 守卫折入 `check_alias_resolution`（id+alias 都查）· **ADR 达标**（`docs/adr/2026-10-14-subagent-session-identity-exclusion.md`，arch 落盘）· 协议加一行**身份模型边界指针**。**PM 裁定 D-A/B/C = 均采纳 arch 默认建议**（D-A：`fallback_pane_for` 的 claimed **保持含子代理条目**，arch 反对两处一致已记录在案）。
- 优先级：中低（身份模型显式化 + 护栏 · 低成本）· 战略筛子：命中「机制可信度 / 会话语义安全」→ 做 · MoSCoW：Should · Kano：基本型 · RICE ≈6.8（附录）

## TL;DR（≤5 行）

- **做什么**：把「子代理会话（`subagent-*` / `subagent-chat-*`）不进入舰队会话身份模型」从**偶然成立**变为**显式契约** —— `status` 出汇总一行（只计数）、`close` 显式拒绝并点名 `pi-subagents`、`running`/`ensure` 加负向护栏、收口 E2 的孤儿 pane 掩盖、加 `check` 守卫防未来角色名冲突。
- **给谁**：本仓维护者（改 `status`/`close` 的人）、交付批次 QA、下游三仓维护者（照抄「子代理不属舰队会话」口径）。
- **成功标准**：`cases/15` 全绿；`close subagent-*` rc≠0 且输出点名 `subagent-` + `pi-subagents` 且**父 pane 存活**；仅子代理在场时 `status` 不误报在线、`ensure` 不判「已在运行」；前缀边界不误伤（`qa-subagent-x` 仍正常）；断言只增不减（基线 **313**）。
- **不做什么**：不改 pi-subagents 集成 · 不动 F1 自 pane 闸门与 `offline_verifiable` 语义 · 不改 `close` 对正常角色/派生会话的行为 · 协议「子代理结果不替代 done」归 **⑦** 另批 · 不做脚本拆分（⑫后半）。

## 一、问题证据

- **来源（T512 调研 · 2026-10-12）**：§2.2 —— 子会话以 `subagent-<agent>-<runid>`（无名时 `subagent-chat-<id18>`）进入 pi-intercom 名册，而 `visible_session_names` 读名册 ⇒ **污染 `status` 枚举**；§2.3 —— 原生子会话无独立 pane，若子代理也用 pi-intercom 注册会**继承父进程 `$TMUX_PANE`** ⇒ **父子 pane 句柄串扰**：对子会话 `close` 可能命中父 pane；§4.3 —— 建议立项（脚本类，中风险，需回归）。
- **本轮 QA 现状复现（2026-10-14 · hermetic：`/tmp` 夹具 + 真 tmux 隔离 socket + 假名册探针 + 桩 `pi`）**：① `status` 注入 `subagent-qa-<id>` / `subagent-chat-<id18>` ⇒ **不出现**在角色区/派生区/告警区（派生区按 `"$name" == "$role"-*` 过滤，`subagent-*` 不以任何角色开头 ⇒ 被 `continue`）；② `close subagent-*` / `close subagent-chat-*` ⇒ **rc=1 ·「未知角色或派生会话名」· 父 pane 存活**（在解析段即 `die`，进不到 pane 定位）；`close --task <id> qa`（父有子代理在场）⇒ rc=0「未运行（无需回收）」· 父 pane 存活；`close qa` 正常回收父 pane（正控）；③ `ensure qa` 在「名册仅子代理」时**不**误判「已在运行」（`intercom_online` 等均精确名匹配）；④ **E2 = 真边界缺口**：`unattributed_pi_panes` 的 `claimed` 集合会被**子代理条目的继承 `tmuxPane`** 认领 ⇒ 一个本应触发「无法归属会话名」告警的孤儿 `comm=pi` pane **告警消失**（低危：真实场景该 pane 多已被父条目认领）。
- **判定**：**核心危害面 ≈ 0，但安全是隐式的** —— 全靠「角色前缀匹配 + 别名解析」的**偶然**成立，`nao-fleet.sh` 内 `grep -c subagent` = **0**（零显式处理、零断言）。且 `die` 文案泛化（「未知角色」）不点名 `subagent-*`，使用者无从得知「子代理生命周期归 pi-subagents」。
- **5 Whys**：子代理不会误伤舰队 ← 角色解析/前缀过滤恰好把它们挡在外面 ← 两处机制都不是为子代理设计的 ← 引入 pi-subagents（T512）时只做了**只读调研**、未落任何脚本侧识别 ← 当时判断「危害面≈0 ⇒ 不必立项」，但**未把结论固化为断言或显式识别**（隐性安全 = 未来加一个以 `subagent-` 开头的角色 id/别名即失守）。
- 证据留痕：上述报告路径 · QA 本轮只读复现（intercom `done(full)` 2026-10-14；报告将随批落盘 `docs/reports/2026-10-14-T525-subagent-recon.md`）· `docs/tasks-state.md` 待裁量项 ⑥。

## 二、目标指标

- **北极星**：「**子代理会话不属舰队会话身份模型**」成为**显式**契约 —— 由代码分支 + 输出契约 + 断言共同固定，而非依赖命名巧合。
- **预期**：① `status` 汇总行计数正确（`N=0` 不打印；仅计数、不列名）② `close subagent-*` 显式拒绝 rc≠0 + 点名 `subagent-`/`pi-subagents` + **绝不触碰任何 pane**（父 pane 存活）③ 仅子代理在场时 `ensure` 不判「已在运行」、`status` 不误报在线 ④ E2 收口后孤儿 pane 告警**回归**（非静默优先）⑤ 前缀边界不误伤：`subagentfoo` / `mysubagent-x` / 裸 `subagent` 不入排除面，`qa-subagent-x`（合法派生名）**仍正常列出并可 close** ⑥ 断言只增不减（基线 **313**）。
- **观测**：`npm test` rc + `cases/15` 逐条（T1–T10）+ `check` rc + 前缀边界正/负控 + 隔离 socket 下父 pane 存活证据。

## 三、范围 / 非范围

- **范围**
  1. `status`：新增**汇总一行**（只计数不列名）—— **逐字措辞**（arch 冻结）：「另有 N 个子代理会话（`subagent-*`）· 生命周期由 pi-subagents 管理，nao 不回收」；位置 = 「任务派生会话」节**之后**、孤儿 pane 告警**之前**，**独立一行**；`N` = **可见会话名**（`visible_session_names`，真实来源为名册）中 `^subagent-` 去重计数（新增 helper `subagent_in_field`，与 `derived_in_field` 同源）；**`N=0` 不打印**；`intercom list` 头行**不呼应**。
  2. `close`：在**目标解析最前**加 `^subagent-` 分支 ⇒ 专门 `die`（rc≠0）+ 文案**点名** `subagent-*` 与 `pi-subagents`（stop/retention），**绝不进入任何 pane 定位**（把「偶然 die」固化为「显式拒绝 + 定位」）。
  3. `running` / `ensure`：**负向护栏**（语义不变）—— 断言「仅 `subagent-*` 在场时不判已在运行 / `status` 不误报在线」，防未来把子代理计入 `running`。
  4. **E2 收口（用户拍板 = 收口）**：`unattributed_pi_panes` 的 `claimed` 集合改为**条目感知**（`name\ttmuxPane` 配对后过滤 `^subagent-` 条目）—— 现实现是**纯值提取**（无法按条目名排除）⇒ 新增单点 helper `roster_pane_claims()`，复用仓内对象边界切分惯用法（`sed 's/},/}\n/g'`，**兼容紧凑/pretty 两种 JSON**，纯状态机 awk 会在紧凑名册塌缩成末条 ⇒ 假告警）⇒ 孤儿 `comm=pi` pane 回到「非静默」告警。**边界（D-A · arch 反对两处一致，PM 采纳）**：`fallback_pane_for` 的 claimed **保持含子代理条目**（那里 = 「该 pane 已被占用」，排除会致兜底**误认领父 pane**，比告警更糟）；E2 **只改 `unattributed_pi_panes`**；与 F1 自 pane 闸门 / `offline_verifiable` **无交互**。代价 = 某 pane **仅**被子代理条目认领时回到告警（真「不可归属」）。
  5. `check` 守卫：角色 id / 别名**不得以 `subagent-` 开头**（否则排除面会吃掉该角色）⇒ 构造非法 `roles.yaml` 时 `check` rc≠0；**折入 `check_alias_resolution`**（唯一枚举点，避第二处遍历漂移；**canonical id 与 alias 都查**；与缩进/别名唯一性各自累积 rc）；文案（arch 定稿）：`  ✗ 角色 id/别名 <name> 以 subagent- 开头（该前缀保留给 pi-subagents 子代理会话，nao 不接管）`。**注**：`load_manifest` 的 id 正则 `^[a-z0-9][a-z0-9-]*$` 不拦 `subagent-*` ⇒ 必须新增守卫。
  6. 新增 `tests/t4/cases/15-subagent-isolation.sh`（断言 T1–T10，见 §七）+ `run.sh` 注册 `"15"` / usage `<01-14>` → `<01-15>`。
  7. 文档与报告：`tests/README.md`（用例表 + 15 行 + 「子代理不属舰队会话」口径）· **`.agents/common/intercom-protocol.md` 加一行身份模型边界指针**（`subagent-*` 不属舰队会话身份模型：status 只计数、close 拒绝、生命周期归 pi-subagents；**仅归属口径，不得掺 ⑦ 条款**）· `docs/releases/v0.18.3.md` · QA 报告 `docs/reports/2026-10-14-T525-subagent-recon.md`（现状复现证据）+ `docs/reports/2026-10-14-T525-qa-verify.md`（独立验证）+ arch 报告 `docs/reports/2026-10-14-T525-arch-review.md`（实施闸门/用例集/接线清单下沉于此）。
  8. 台账：⑥ 收口（`docs/tasks-state.md`）。
- **非范围**（各带理由）
  - **协议补「子代理结果不替代 done」**：理由 属台账 **⑦（T512-②）**——产物（协议文档 vs 脚本）、风险、回归面、审阅人均不同，另批。
  - **不改 pi-subagents 集成 / 不新增子代理钩子**：理由 本批只做 fleet 侧识别与排除；子代理生命周期交 pi-subagents。
  - **不动 F1 自 pane 闸门与 `offline_verifiable` 语义**：理由 T513/T516 已定不变量，本批只在其外围加识别与护栏。
  - **不改 `close` 对正常角色 / 派生会话的行为**：理由 防误伤是本批核心约束（正控 T6）。
  - **不做脚本拆分（⑫后半）**：理由 未立项，待 arch 评审后另议。

## 四、用户场景

- 画像 A（本仓维护者）：`status` 末尾看到「另有 2 个子代理会话 · 由 pi-subagents 管理」⇒ 不再怀疑舰队多出幽灵会话。
- 画像 B（误操作者/PM）：手滑 `close subagent-chat-xxx` ⇒ 明确被拒 + 被告知去 pi-subagents stop，**父会话毫发无损**。
- 画像 C（交付批次 QA）：`cases/15` 以真 tmux 隔离 socket 证明「父 pane 存活」这一行为契约，可被证伪。
- 画像 D（未来改 `roles.yaml` 的人）：若把角色 id 起成 `subagent-*`，`check` 当场拦住。
- 状态清单（语义）：**仅子代理在场** = 不算在线 / 不算已在运行 / `status` 汇总计数 +1；**`close subagent-*`** = rc≠0 + 点名 + 无 pane 操作；**`close` 正常会话** = 行为不变（正控）；**孤儿 `comm=pi` pane** = 非静默告警（E2 收口后）；**无子代理** = 汇总行不出现（零噪音）。

## 五、业务规则

- **BR1 显式优先**：对 `subagent-*` 的识别必须是**显式分支**，不得依赖「角色前缀恰好不匹配」的偶然性（`grep -c subagent` 从 0 变为有处理 + 有断言）。
- **BR2 排除点位置**：`close` 的 `subagent-` 判定必须位于**角色/别名解析之前**（防未来角色名与排除面互相吞噬）；`status` 的计数取名为 `^subagent-`。
- **BR3 非静默**：`status` 不得「看不见即无视」—— 出**汇总一行**（计数）；`N=0` 不打印。
- **BR4 绝不触 pane**：对 `subagent-*` 目标，`close` 在任何分支、任何环境（含名册 `tmuxPane` 指向父 pane）下**不得** kill/捕获/定位任何 pane；父 pane 必须存活（T2/T3/T4/T5）。
- **BR5 拒绝要指路**：`close` 的拒绝文案必须**点名** `subagent-*` 与 `pi-subagents`（stop/retention），并说明「子代理生命周期不归 nao 回收」。
- **BR6 前缀精确**：排除面 = `^subagent-`（覆盖 `subagent-<agent>-<runid>` 与 `subagent-chat-<id>`）；**不误伤** `subagentfoo`、`mysubagent-x`、裸 `subagent`；`qa-subagent-x` 属合法派生名，**必须仍列出并可 close**。
- **BR7 不误判在线**：`running` / `ensure` 判重与 `status` 角色区**只认精确会话名**，子代理在场不得产生「在线 / 已在运行」。
- **BR8 E2 非静默优先**：孤儿 `comm=pi` pane 的可归属判定**不得**被子代理的继承 `tmuxPane` 掩盖（claimed 只认非 `subagent-` 条目）。
- **BR9 只增不减与夹具纪律**：`cases/15` 断言只增（基线 313）；夹具用**真 tmux 隔离 socket**（≠ 生产默认候选）+ `env -u TMUX -u TMUX_PANE` + 假名册**逐字段一行 pretty-print**（实测：紧凑 JSON 会被名册解析的贪婪匹配只取到末条）+ 收尾走机制 `cleanup -S <隔离 socket>`；能力门 = `tmux` 缺 `t4_skip`、`tsx` 缺 `t4_degrade`。

## 六、NFRs

- **时长**：`cases/15` 为隔离 socket 上的本地断言，量级与既有 11/12 用例相当（全量门禁仍 ≈2min 量级）。
- **可移植性**：`tmux` 缺失 ⇒ `t4_skip`；`tsx` 缺失 ⇒ 名册注入组 `t4_degrade`（默认豁免、`test:t4:full` 计分）；**不得**触碰真实会话/生产 socket。
- **网络**：不适用（零网络）。
- **可诊断**：`close` 拒绝与 `status` 汇总行均须指名原因与去向；失败断言可定位到用例编号。
- **安全**：一切夹具限于 `/tmp` 与隔离 socket；`close` 相关断言必须先证「父 pane 存活」再判其它；禁止在生产 socket 上执行 `kill-server`。

## 七、AC

- **验证接缝（QA 已确认 2026-10-14）**：`npm test` rc=0（复用唯一机械门禁，接缝数不增）+ 新增 `tests/t4/cases/15-subagent-isolation.sh`（真 tmux 隔离 socket，行为契约需真句柄链才可证伪）。QA 改定 = 采 C1（否决 C2/C3）；并要求 `run.sh` 注册 `"15"`。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA 复核候选，Then 确认/改定并记录日期 —— **已完成 2026-10-14**（QA `done(full)`：C1 + 现状复现 + E2 发现）。
- **AC2（主路径 · `status` 显式计数）**：Given 名册含 `subagent-qa-<id>` 与 `subagent-chat-<id18>`，When `status`，Then 二者**不出现在**角色区/派生区，**且**出现汇总行且计数 = 2；Given 无子代理，Then 汇总行**不出现**（T1）。
- **AC3（主路径 · `close` 显式拒绝且不触 pane）**：Given 父 pane + 子代理共用 `tmuxPane`，When `close subagent-qa-<id>` / `close subagent-chat-<id18>`，Then rc≠0、输出含 `subagent-` 与 `pi-subagents`、**父 pane 存活**；When `close --task <唯一号> qa`（父+子在场），Then 绝不触父 pane（T2/T3/T4/T5）。
- **AC4（业务规则 · 不误伤正控）**：When `close qa`（裸常驻名，父有子代理在场），Then **正常回收父 pane**（排除面不得过宽）；When `close subagentfoo` / `close mysubagent-x`，Then rc≠0 但**不得**被归类为 `subagent-*`（文案形态不同）；When `status` 含 `qa-subagent-x`，Then **列入派生区**且 `close --task subagent-x qa` 走正常非静默路径（T6/T9）。
- **AC5（边界 · 不误判在线）**：Given 名册仅 `subagent-qa-<id>`，When `ensure qa`，Then **不**判「已在运行」；When `status`，Then 角色区**不**报 `qa` 在线（T7 负向 + 正控）。
- **AC6（异常 · E2 孤儿 pane 回归非静默）**：Given 一个未认领的 `comm=pi` pane 且名册仅有以该 `tmuxPane` 为值的 `subagent-*` 条目，When `status`，Then **仍触发**「无法归属会话名」告警（T8，按 E2 裁量取值）。
- **AC7（设计一致性 · 守卫与文档）**：Given 角色 id/别名以 `subagent-` 开头（构造非法 `roles.yaml`，桩测），Then `check` rc≠0；且 `tests/README.md` 含用例 15 与口径说明、`.agents/common/intercom-protocol.md` 含边界指针、`docs/releases/v0.18.3.md` 已落盘、`docs/reports/2026-10-14-T525-subagent-recon.md`（现状复现）与 `…-qa-verify.md`（独立验证）已落盘；断言只增不减（基线 313 ⇒ 交付后 > 313）。
- **AC8（一致性闸门）**：Given PRD 接缝/AC 范围与 QA 用例范围（T1–T10），When 比对，Then 一致（不一致即验收打回）。

## 八、上线闭环

- **版本**：**v0.18.3（PATCH）** —— 改动含 `.agents/scripts/nao-fleet.sh`（**在 npm tarball 内**）⇒ 是否重发 npm 见开工确认卡（先例：T522/T524 涉及包内文件 ⇒ 重发；T520/T521/T523 仅文档/测试 ⇒ 不重发）。
- **灰度**：不适用（本仓内部门禁/工具语义）。
- **回滚**：revert 分支改动（识别 + 汇总行 + claimed 收口 + 用例）并发下一 PATCH；已 push tag 不删。
- **发布前置**：`npm run test:t4:full` **rc=0**（**空载**跑，O-1）。
- **监控**：不适用；指标 = `npm test` rc + `cases/15` 逐条 + 断言数 + 父 pane 存活证据。

## 九、变更治理

- **流程**：降级批次分支 `nao/subagent-isolation`（无 Issue，与 T518–T524 一致）→ PR → QA 独立复跑 + 前缀/正控/负控 → PM 验收 → RD `--squash` 合并（显式 `--subject` + `--match-head-commit`）→ PM 发 tag/Release（按 §八 决定 npm）→ PRD 归档。
- **实现分工（同分支顺序写，禁并发）**：① **rd-infra** 落 `nao-fleet.sh`（`status` 汇总行 · `close` 显式拒绝 + 文案 · E2 claimed 收口 · 可选 `check` 守卫）+ `tests/t4/cases/15-subagent-isolation.sh` + `run.sh` 注册 + `tests/README.md` + `docs/releases/v0.18.3.md` → 回执；② **qa** 独立复跑（T1–T10 全量 + 现状复现报告落盘 + 独立验证报告）→ `done(full)`。
- **架构评审闸门**：**已完成 2026-10-14**（用户拍板「轻量评审」· arch `done(full)`）：结论**有条件可行** + 6 项定稿（排除点位置 / `status` 输出契约（逐字）· E2 条目感知且只改 `unattributed_pi_panes` · `check` 折入 `check_alias_resolution` · ADR 达标 · 协议边界指针）；**PM 裁定 D-A/B/C 均采纳 arch 默认建议**（D-A arch 反对「两处 claimed 一致」已记录）；**ADR 落盘待授权**（`docs/adr/2026-10-14-subagent-session-identity-exclusion.md` · 状态 `已接受（待落地 v0.18.3）` · Owner arch-designer · ≤60 行 · 必写 5 节 + 对照备选 + 参考来源），**ADR 已落盘**（`docs/adr/2026-10-14-subagent-session-identity-exclusion.md` · 49 行 · 状态 `已接受（待落地 v0.18.3）` · Owner arch-designer）+ `docs/adr/README.md` 索引一行 + 评审报告 `docs/reports/2026-10-14-T525-arch-review.md`（76 行）。
- **交付记录**：PR [#43](https://github.com/Nathan3303/nao-skills/pull/43) squash **`fbddd0d`**（main 恰 1 条 · 无 `wip()` · 分支删净）· RD 3 条 + arch 1 条 + QA 1 条 `wip(T525)` 提交（11 文件 / +564 −4）· ADR + arch 报告 + QA 报告（recon 37 / verify 66 行）· 未 bump 版本（发布节点 PM 执行）。
- **本批残差（已记录）**：**R-1** 负载偶发 SKIP/DEGRADE ⇒ 发布判据须空载跑 `test:t4:full` · **R-2** E2 收口后「仅被子代理认领的 pane 回告警」= ADR 已记边界 · 未拉真实 pi-subagents 子会话（夹具注入）· 合并 body 一字偏差（「守卫」→「校验」，无实质影响，PM 裁定忽略）。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-subagent-isolation.md`（本文件；归档时登记 `docs/prds/README.md`）；运行时状态记 `docs/tasks-state.md`（⑥ 收口）。
- **待裁量项**：本批关闭 ⑥；维持 ⑦⑧⑨（T512 余项）· ⑫后半 · ①②④⑤ 等更早遗留 · O-1 观察项。

## 附：RICE 与依据

- Reach 2（本仓维护者 + 交付批次 QA）· Impact 3（把「偶然安全」变「契约安全」，防未来角色命名冲突与父 pane 误杀）· Confidence 0.9（QA 已 hermetic 复现全部路径 + 给出 T1–T10 断言清单）· Effort 0.8（脚本识别 4 处 + 新用例 + 2 报告 + 文档）⇒ **RICE ≈6.8**。
- 战略筛子：命中「机制可信度 + 会话语义安全」→ 本批做；「协议条款（⑦）· pi-subagents 集成 · 脚本拆分」被筛除（各自另批）。
