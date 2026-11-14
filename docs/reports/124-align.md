# 机制后端口径对齐（#124 · M20261114-align）实现报告

- 状态：待 PM 验收（RD 自验完成，待 qa 非作者复核）· 更新：2026-11-14 · Owner：rd-infra
- 指针：Issue [#124](https://github.com/Nathan3303/nao-skills/issues/124) · 上游依据 `docs/reports/118-mechanism-review.md` §四 T1/T2/T3/T5 + §七（批次 A）+ §八 D4 · 分支 `nao/M20261114-align` · 测试用例 `tests/t4/cases/34-backend-premise-warn.sh` · 本批不发版

## 结论（TL;DR）

- 目标：把三处「运行前提 / 默认后端」口径收敛到实现事实（默认 herdr、tmux 回退），回填 ADR 状态，并给 `check` 加一条 **warn-only** 的一致性单点校验。
- 做法：文本改口径 + 脚本新增 `check_backend_premise`（比对声明 vs 唯一赋值点，**只 warn、不进 rc、一致时零输出**）+ ADR 正文/索引回填；先写可失败用例 `cases/34` 再实现（先红后绿）。
- 结果：AC1–AC8 全过；`check` rc=0 ×2 输出逐字一致（roles=7 · files=**54** 不变）· `npm test` **双后端** rc=0（tmux 组 PASS / herdr 组 PASS·PENDING 0）· 敏感值 grep 0。
- 影响：纯文本 + 一处 warn；未碰 `docs/tasks-state.md`（PM 治理面）、未改 hotfix 白名单/卡预算/三段阶梯（均归批次 C）。
- 回退：`git revert <合并 sha>` 一条命令（无数据/契约/迁移影响）。

## 改动

- `intercom-protocol.md`（运行前提行）：改为「默认 herdr（`NAO_TERMINAL` 未设/空串）· 回退 tmux」，两端前提分别一句话；细节给 `README.md`「前置环境」+ `docs/INSTALL.md`「herdr 后端」「tmux 布局」**指针**（不复制）。
- `AGENTS.md:18` / `:33`：同口径（「pi ≥1.4.0 + tmux」→「pi ≥1.4.0；终端后端默认 herdr、`NAO_TERMINAL=tmux` 回退」；布局按后端分述）。
- `.agents/skills/pm-operations.md`：**既有矛盾口径订正** —— 原文「默认 2 行摘要」在 herdr 默认下是事实错误（与 PM 卡同一事实的副本，不修即双源）；同处补「端前提」一句。
- `.agents/skills/nao-fleet/SKILL.md`：**新增指针**（原无任何后端声明，回退该句不会留下矛盾口径）—— 内容正确、无害，但**非必需**，此处按 QA 复核口径如实标注。
- `.agents/prompts/product-manager.md`：`:66` 改「默认 **3 行**摘要（摘要 + codegraph + 生效后端；显式 `=tmux` 无第三行）」· `version 36 → **37**` · `updated 2026-11-14`。
- `nao-fleet.sh`：新增 `SELF_SH`（读回自身以解析默认值，不重述字面量）+ `premise_declared_backend` + `check_backend_premise`（warn-only，`cmd_check` 内**单点调用** `|| true`）；顺带订正同批次同事实的陈旧文案：`check` 段标题（去掉「tmux 内」）、`✓ tmux 可用（唯一受支持宿主）`→`（回退后端）`、usage/摘要注释「2 行」→「2–3 行」（herdr 版另加生效后端行）。
- ADR：正文 6 篇「待落地 vX.Y.Z」→「已落地 vX.Y.Z」（v0.17.2 / 0.18.0 / 0.18.3 / 0.18.5 / 0.20.0 / 0.21.0，`docs/releases/` 均在）+ `strict-tmux-pi` 加**被 herdr 默认取代（v0.23.x）**注记（正文保留历史）+ `derived-pane-window-addressing` 正文补「已落地 v0.16.2 · T517」（`git tag --contains 536d030` 实证）；`docs/adr/README.md` 索引 10 行同步（含 `:21`/`:23`/`:25` 三处矛盾行）。
- 用户可见文档（PM 验收前小补 ②③）：`docs/INSTALL.md` §前置环境「不满足时的表现」第 2 条加限定「且 `HERDR_ENV` 未被继承时」；`docs/ARCHITECTURE.md` 在「工具层 · 运行前提（v0.19.0）」段**下方加一行注**（v0.23.0 起默认 herdr + ADR 取代注记指针，**正文不动**，尊重版本戳快照）。
- 测试：新增 `cases/34`（4 组 32 条断言）+ `run.sh` 注册 + `backends/herdr.txt` 登记（shared）+ `tests/README.md` 计数同步（共享 20→21 · 32→33 例）；`cases/06` 两处随本批事实更新（小节标题插值常量仍命中；扫描面 32→33 个用例文件）。

## AC 逐条

- **AC1 材料面**：`grep -rn herdr .agents --include=*.md | wc -l` = **4**（协议 1 + 技能 2 + `SKILL.md` 1）≥3；`grep -rn '唯一路径.*tmux' .agents --include=*.md` = **0**；声明与 `nao-fleet.sh` 的 `NAO_TERMINAL` 唯一赋值点（`grep -nE '^NAO_TERMINAL=' .agents/scripts/nao-fleet.sh` ⇒ 现 `:145`）实际默认（herdr）一致（新 warn 实跑零输出）。
- **AC2 AGENTS.md 同口径 + check 认这两处**：`cases/34` C 组把夹具 `AGENTS.md` 的「默认 herdr」改成「默认 tmux」⇒ 恰 1 条 warn 且点名 `AGENTS.md` + `nao-fleet.sh`，协议文件不被误点名（C5）。「只认协议文件」的反向被该组排除。
- **AC3 ADR 16 篇「正文 == 索引」逐篇对照**（列 = 正文 / 索引，判定见行尾）：
  - `2026-09-25-new-rd-infra-role`：已落地 v0.9.0 / 同 ✓
  - `2026-09-25-tmux-fleet-layout-modes`：已落地 v0.9.0 / 同 ✓
  - `2026-10-08-nao-skills-single-skill-pi-package`：已接受 / 已接受 ✓
  - `2026-10-08-migrate-shim-and-marker`：已落地 v0.13.0 · T510 / 同 ✓
  - `2026-10-12-non-tmux-host-spawn`：已废弃（被 2026-10-27-strict-tmux-pi 取代）/ 同 ✓
  - `2026-10-13-derived-pane-window-addressing`：**已落地 v0.16.2 · T517** / 同 ✓（索引原写「待 RD 落地」= 陈旧）
  - `2026-10-13-close-anchor-cleanup-guard`：已接受（随 T516 / 0.16.0；随 PR #30 入库）/ 同义 ✓（正文措辞含「落地」二字，语义一致）
  - `2026-10-14-adr-structure-contract`：**已落地 v0.17.2** / 同 ✓
  - `2026-10-14-npm-test-gate-scope`：**已落地 v0.18.0** / 同 ✓
  - `2026-10-14-subagent-session-identity-exclusion`：**已落地 v0.18.3** / 同 ✓
  - `2026-10-14-role-agents-runtime-registration`：**已落地 v0.18.5** / 同 ✓
  - `2026-10-27-strict-tmux-pi`：已落地 v0.19.1 + **被 herdr 默认取代（v0.23.x）** 注记 / 同 ✓（索引原写「待落地」= 与正文矛盾）
  - `2026-10-28-codegraph-plugin-adoption`：**已落地 v0.20.0** / 同 ✓
  - `2026-10-31-fleet-status-repo-attribution`：已落地 v0.20.2 / 同 ✓（索引原写「待落地」）
  - `2026-11-01-downstream-card-sessions`：**已落地 v0.21.0** / 同 ✓（`docs/releases/v0.21.0.md` 明列本 ADR）
  - `2026-11-13-herdr-workspace-scope-key`：已落地 v0.23.1 / 同 ✓（索引原写「待落地」）
  - 「全库 `待落地` 与已发版本不一致项」= **0**：`grep -rn 待落地 docs/adr` = 9 → **0**（另 1 处 `docs/research/2026-10-14-code-review-role.md`「决策待落地」是调研文档状态、非 ADR、不指版本，不动）。
- **AC4 PM 卡**：`version=37` + `updated=2026-11-14` + `:66` 三行摘要。**广播文本**：`card pm v37` —— 「check 默认摘要 2 行 → **3 行**（摘要 + codegraph + 生效后端；显式 `NAO_TERMINAL=tmux` 时无第三行）；同时把「运行前提」表述改为『终端后端默认 herdr、`NAO_TERMINAL=tmux` 回退』（细节指针 `README.md`「前置环境」/`docs/INSTALL.md`「herdr 后端」）」。
- **AC5 先红后绿（双向）**：三段证据 —— ① **实现缺失**：`cases/34` 落笔后 `RESULT: FAIL` —— **数字随「脚本版本 × 文档版本」变**：`23f76e9`（实现前）脚本 × **当时文档**（协议仍旧口径）= **13 条未过**（B2/B3/B3b/B4/B5 · C2/C3/C4 + D1/D2 + D4）；同脚本 × **当前文档** = **9 条未过**（QA 复核口径：D4/D5 类「当时文档也旧」的项已随文档修复消失）；② **文档未对齐**：实现后直接 `check -v` ⇒ **2 条 warn**（协议 = tmux 旧口径 · `AGENTS.md` = nodecl）+ 摘要 `warn=2`；③ **对齐后**：warn 0 · `cases/34` **tmux 32 PASS / 默认 herdr 31 PASS + 1 NOTE**（herdr 侧 `cases/34:75` 的 `if` 让 A4 只在 tmux 后端执行，herdr 走 `t4_note backend-gate` ⇒ 断言数不同轴，不是漏跑）。双向：一致 ⇒ 零输出/无 `warn=`；不一致 ⇒ 1 条 warn 且摘要 `warn=1`；还原 ⇒ warn 消失（B8/C6）。
- **AC6 负控**：协议改回「唯一路径 … tmux」⇒ warn 出现（B2/B3/B7）；还原 ⇒ 消失（B8）。`AGENTS.md` 负控按 **P2-1 后**口径分三形态（**每个声明行各判各的**）：仅 `:18` 回退旧文 ⇒ 1 条点名 `AGENTS.md:18`；仅 `:33` 改成 tmux ⇒ 1 条点名 `:33`；两行都改 ⇒ **2 条**（= 声明行数，不刷屏、不合并吞行号）；还原 ⇒ 消失。全部 `rc=0` ⇒ warn 不改 rc。
- **P2-1（QA 复核 · 本批必修）**：旧实现只取「第一条能解析出后端的前提行」⇒ 仅回退 `AGENTS.md:18`（#124 **原始症状行**）时 `check: OK`、warn 0（守护静默失效）。修法 = `premise_declared_backend` 改为**逐声明行**输出 `<行号>\t<herdr|tmux|nodecl>`、`check_backend_premise` 逐行判定并按 `文件:行号` 报；**先红后绿**：新断言在旧实现上 `RESULT: FAIL` 11 条（关键红点 = `C1c 仅 :18 回退：期望 1 实际 0`、`C2c/C2d 仅 :33`、`C3b 期望 2 实际 1`、`C3e label 重复`），改实现后 tmux **44 PASS** / 默认 herdr **43 PASS + 1 NOTE**。
- **AC7 门禁**：`check` rc=0 ×2 且输出 `diff` 空（roles=7 · files=54 · layout=main-row2；`files=` 未变 = 本批未增删 `.agents/` 下文件）· `npm test`：`NAO_TEST_TERMINAL=tmux` rc=0（33 例全 PASS · SKIP=0 DEGRADE=0 · NOTE 9 全白名单）· 默认（herdr）rc=0（共享 21 / 专有 10 / tmux 专有 2 / PENDING 0 = 33 · SKIP=0 DEGRADE=0 · NOTE 10 全白名单）· 敏感值 grep（新增行：家目录绝对路径 · 令牌 · 私钥 · API 凭据字面量）= **0**（命令与正则见下「门禁命令」）。
- **AC8 T1 实测**：见下节（结论：**条件性 exit 3**，非无条件）。

## 门禁命令（可复跑）

```bash
bash .agents/scripts/nao-fleet.sh check                      # rc=0 ×2 且输出逐字一致
NAO_TEST_TERMINAL=tmux npm test                              # tmux 后端全量（33 例）
npm test                                                     # 默认后端 = herdr（共享 21 / 专有 10 / tmux 专有 2）
grep -rn 'herdr' .agents --include=*.md | wc -l              # AC1 正向（= 4）
grep -rn '唯一路径.*tmux' .agents --include=*.md | wc -l     # AC1 负向（= 0）
grep -rn '待落地' docs/adr | wc -l                           # AC3（= 0）
git diff <base>..HEAD | grep '^+' | grep -cE '<家目录前缀>|<令牌前缀>|BEGIN .*PRIVATE KEY|api[_-]?key'   # = 0
# cases/34 两后端断言数（44 / 43 不同轴：A4 只在 tmux 后端跑，herdr 走 NOTE backend-gate）
NAO_TERMINAL=tmux bash tests/t4/run.sh --case 34 | grep -c '\[PASS\]'   # = 44
bash tests/t4/run.sh --case 34 | grep -c '\[PASS\]'                     # = 43（另 1 条 NOTE backend-gate）
```

## T1 实测：tmux 内 `ensure` 是否 exit 3（#118 §五-5）

环境：本机 pi 1.5.2 / herdr 0.9.1 / tmux 3.8；隔离 socket（`mktemp -d` + `tmux -S <sock> -f /dev/null`），不碰用户 server；`HERDR_*` 显式枚举处理。

- **A（tmux 内 + `HERDR_*` 全部清除 ⇒ 真「普通 tmux 用户」）**：`env -u HERDR_ENV -u HERDR_SESSION -u HERDR_SOCKET_PATH … bash .agents/scripts/nao-fleet.sh ensure rd-fe`
  - pane 内回显：`TMUX=set HERDR_ENV=<unset>`
  - **rc=3** · stderr：`需要 herdr pane：HERDR_ENV=1 缺失（herdr 后端只在其 pane 内运行…）—— 在该 herdr 会话的 pane 内重试，或 NAO_TERMINAL=tmux 回退`
- **B（tmux 内 + 继承 `HERDR_ENV=1` + 语法合法的会话名/socket 落在私有 `XDG_CONFIG_HOME` 根下）**：同命令前置 `HERDR_ENV=1 HERDR_SESSION=nao-t1-probe HERDR_SOCKET_PATH=<私有根>/herdr/sessions/nao-t1-probe/herdr.sock`
  - pane 内回显：`TMUX=set HERDR_ENV=1 HERDR_SESSION=nao-t1-probe`
  - **rc=0**（不是 3）：stderr `herdr pane list 失败（server 未就绪？）` ×2；stdout `已拉起 0 个会话（成功 0 / 跳过 0 / 失败 1）`
  - 原因：`herdr --session <名> api schema` **不需要活 server 即返回** `protocol: 22`（实测原文：`Herdr API schema` / `protocol: 22` / `schema_version: 1`）⇒ 前提闸门放行，失败后移到放置面，按既有裁定 D3 计 `SPAWN_FAIL` 而不改 rc。
- **结论**：`ensure` 在 tmux 内 **exit 3 成立但带条件** —— 条件是「`HERDR_ENV` 未被继承（或 `HERDR_SESSION`/`HERDR_SOCKET_PATH` 不合规）」。若宿主从 herdr pane 起 tmux（server 继承 `HERDR_*`），tmux 内跑默认后端**不会** exit 3，而是进入 herdr 后端并在放置面失败（rc 仍 0）。
- 因此 `docs/INSTALL.md`「默认 herdr 但不在 herdr pane 内（例如你在 tmux 里跑）⇒ `exit 3`」这句**缺限定**（继承态反例已实测）。未在本批修正（超出 Issue §范围 6 项，且属用户可见文档措辞）⇒ 见下节遗留。

## 未覆盖 / 风险 / 遗留

- 未跑：B 的「真实 `HERDR_SESSION` + 真实 socket 继承进 tmux」组合 —— 结构上与 B 同形（前提闸门只读 env 字符串 + 静态 schema），且会在用户真实 workspace 里建 pane（越安全边界），故不实跑。
- 声明解析契约（注意）：`check` 只认「默认 herdr / 默认 tmux」原文（`默认` 与后端名之间允许空格 / `=`/`＝`）。改文案若插 `**` 等标记 ⇒ 解析为 `nodecl` ⇒ **warn**（fail loud，不会静默放过）；断言在 `cases/34` A/B/C。
- ~~遗留 1~~ **已修（同批）**：`docs/INSTALL.md` §前置环境「不满足时的表现」第 2 条已加限定「且 `HERDR_ENV` 未被继承时」（依据 AC8 B 组实测）。
- ~~遗留 2~~ **已修（同批）**：`docs/ARCHITECTURE.md`「工具层 · 运行前提（v0.19.0）」正文不动，**段下加一行注**：v0.23.0 起默认后端为 herdr（`NAO_TERMINAL=tmux` 回退），见 ADR `2026-10-27-strict-tmux-pi` 取代注记。
- 遗留 3（**接受**，PM 2026-11-14 裁定「不用动」）：`cases/06` 的 `CHECK_GOLD_LINE`/md5 golden 依赖「一致时零输出」；若未来把端前提 warn 改为 `✓` 正向行，会同时打破 tmux golden 与 `README` 口径 ⇒ 须同批评审（当前不改）。
