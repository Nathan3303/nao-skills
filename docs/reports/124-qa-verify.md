# #124 非作者复核（QA）

- 状态：**建议验收**（1 条 P2 判据盲区，不阻断；无 P1）· 2026-11-14 · Owner：qa
- 被验对象：分支 `nao/M20261114-align` @ `0ee9866`（PR #125 Draft）· 只读复核，未改 RD 文件
- 环境：pi 1.5.2 / herdr 0.9.1 / tmux 3.8 · 工作区复核前后 `git status` 空 · 临时改动全部还原并 md5 自证（见「纪律留痕」）

## AC 逐条（我实际跑出的判据，不采信 RD 自述）

- **AC1 材料面 ✓**：`grep -rn herdr .agents --include=*.md | wc -l` = **4**（4 行 4 文件）；`grep -rn '唯一路径.*tmux' .agents --include=*.md` = **0**。附带：旧口径残留只在 `.sh` 注释（见 P3-4）。
- **AC2 部分达成 ✓/盲区见 P2-1**：协议与 `AGENTS.md` 现文本均声明 herdr，`check` 认这两处（协议负控点名协议；`AGENTS.md` 两行都改时点名 `AGENTS.md`）。
- **AC3 ✓**：`grep -rn 待落地 docs/adr | wc -l` = **0**；`docs/adr/README.md` 16 行索引，**逐篇**正文状态 vs 索引状态比对 16/16 一致（含 `derived-pane-window-addressing`、`strict-tmux-pi`、`fleet-status-repo-attribution`、`herdr-workspace-scope-key` 四处原「待落地/矛盾」）。声称的版本 `v0.9.0/0.13.0/0.16.2/0.17.2/0.18.0/0.18.3/0.18.5/0.19.1/0.20.0/0.20.2/0.21.0/0.23.1` 在 tag 与 `docs/releases/` 均存在。
- **AC4 ✓（文本面）**：`product-manager.md` `version 37` · `updated 2026-11-14` · `:66` 为「默认 **3 行**（显式 `=tmux` 时无第三行）」。**广播是否真发出我无法核**（只有报告里的广播文本）。
- **AC5 先红后绿 ✓**：把 `23f76e9`（实现前）的 `nao-fleet.sh` 装进临时副本跑 `cases/34` ⇒ **9 FAIL / rc=1**（B2/B3/B4/B7/C2/C3/C4/D1/D2）；当前实现 ⇒ 绿。
- **AC6 双向负控 ✓（协议侧）/ 盲区见 P2-1**：协议临时改回 v0.23.0 前整行 ⇒ `check` 摘要 `warn=1` · rc=**0** · `-v` 一条 `! 端前提声明不一致：协议…`；还原 ⇒ 零输出、`warn=` 字段消失（`grep -c '^  ! '` = 0）。
- **AC7 部分复核 ✓**：`check` rc=0 ×2 且输出 `diff` 空（herdr 摘要 3 行 · 显式 `=tmux` 摘要 2 行）；`check -v` rc=0、`!` 行 0。按 PM 口径未重跑全量 `npm test`，只跑受影响 3 例：`cases/06`（golden md5）、`cases/28`（双 golden）tmux 后端 **rc=0 / 0 FAIL**，`cases/34` 见下。
- **AC8 T1 实测 ✓（A 组自复现）**：隔离 socket（`mktemp -d` + `tmux -S` + `-f /dev/null`）+ `HERDR_*` 全清 ⇒ pane 内 `TMUX=set HERDR_ENV=<unset>`，`ensure rd-fe` **rc=3** + 单行「需要 herdr pane：HERDR_ENV=1 缺失…」；隔离 server 已 `kill-server` 并删目录。`INSTALL.md` 现文已带「且 `HERDR_ENV` 未被继承时」限定，与实测相符。

## 计数对账 ✓

- `ls tests/t4/cases/*.sh | wc -l` = **33**；`run.sh --list` = **33**；`backends/herdr.txt` = **21 shared + 10 own = 31**；`# tmux-only: 12 25` = **2**；21+10+2+0 = 33 ✓；`tests/README.md` 记「共享 21 / 专有 10 / tmux 专有 2 / PENDING 0（33 例）」一致。
- `cases/34`：tmux **32 PASS / 0 FAIL**（rc=0）；herdr **31 PASS + 1 NOTE（A4 backend-gate，白名单命中）**（rc=0）——与「A4 只在 tmux 跑」的声明一致，非同轴漏跑。

## 发现

### P2-1 `premise_declared_backend` 只看「第一条有声明的前提行」⇒ `AGENTS.md` 单行回退静默

- 复现（不改仓库永久状态）：把 `AGENTS.md:18` 换回 `c6c684c` 旧文（`机制只支持 **pi ≥1.4.0 + tmux**`），`:33` 保持现文 ⇒
  `bash .agents/scripts/nao-fleet.sh check` = `check: OK …`（**无 `warn=`**）· `-v` 端前提 warn = **0** · rc=0。
- 根因：函数对每个匹配 `运行前提|机制只支持|端前提` 的行取第一条**能解析出后端**的声明就返回；`:18` 解析不出 ⇒ 落到 `:33` 的 `默认 herdr` ⇒ 判「一致」。文件内自相矛盾（`:18` 说 tmux、`:33` 说 herdr）不被发现。
- 影响：`AGENTS.md:18` 正是 Issue #124 的原始症状行；将来只回退这一行 ⇒ 守护**静默失效**，同一问题可再发。`cases/34` C 组用 `s/默认 herdr/默认 tmux/g` 两行同改，故覆盖不到该形态。
- 建议（不属本批可合并范围，由 PM 决定是否同批）：解析改为「收集所有声明行 + 无声明行也算 nodecl」，任一行与实际不符/无声明 ⇒ 一条 warn；补 `cases/34` C3（仅改 `:18`）。

### P3 级

- **P3-1「不修就双源」说法只有一半成立**：`skills/pm-operations.md` 原「默认 2 行摘要」在 herdr 默认下确为事实错误（真双源，必修 ✓）；但给 `pm-operations.md` 与 `skills/nao-fleet/SKILL.md` 各**新增**的「端前提」句是**增量说明**——回退该句不会留下矛盾口径（SKILL.md 原文无任何后端声明，只有测试纪律里的 tmux 隔离 socket 说明）。内容正确、无害，只是报告的理由（「RD 称不修就是双源」）不成立。
- **P3-2 报告数字带条件**：AC5① 写「13 条未过」，我用 `23f76e9` 脚本 + **当前**文档复现为 9 条（差的 D4/D5 等是「当时文档也旧」所致）。数字复核须标「脚本版本 × 文档版本」。
- **P3-3 warn 文案 label 重复**：`AGENTS.md（AGENTS.md）`、`协议（intercom-protocol.md）` 后者正常、前者重复（`label` 与 `basename` 相同）。
- **P3-4 注释/cite rot**：`.agents/scripts/nao-fleet.sh:107` 仍写「tmux 宿主行为（唯一路径）」（tmux 已降为回退通道，易误读）；报告 AC1 引 `nao-fleet.sh:141`，现唯一赋值点在 `:145`。
- **P3-5** `docs/adr/README.md` 中 `strict-tmux-pi` 索引状态嵌套括号（`已接受（… · 已被 herdr 默认取代（v0.23.x））`），可读性小账。

## 禁夹带复核 ✓

`git diff --numstat c6c684c..HEAD` = 23 文件（+337/−41），逐个看过：无 `.agents/skills/commit.md`（S1 hotfix 白名单）、无 `.agents/skills/codegraph.md`/三段阶梯（S3）、diff 内 `CARD_MAX_LINES` 0 命中（E1）；`docs/tasks-state.md` 未改（PM 治理面）。`cases/06` 改动仅「32→33 个用例文件」扫描面 + 标题，属本批必要同事实。

## 敏感值 / 纪律留痕

- 敏感值：`git diff … | grep '^+' | grep -cE '/home/|<令牌>|PRIVATE KEY|api[_-]?key'` = **1**，唯一命中是报告「门禁命令」行里的**占位符**（`<家目录前缀>`、`BEGIN .*PRIVATE KEY`），非真实值 ⇒ 实判 0。
- 临时改动：`intercom-protocol.md` / `AGENTS.md` 各改回旧口径后**已还原**，md5 复原（`c78ae83…` / `262e1d8…`），复核结束时 `git status --porcelain` **空**；未用 `git checkout/switch`（一律 `git show <sha>:<path>` 写回）。隔离 tmux server 已清；自建 `/tmp` 夹具与失败缓存（`/tmp/nao-t4.bBng14`）已删。
- 未复核：全量 `npm test` 双后端（按 PM 口径不重跑）；AC4 广播的实际投递；T1 B 组（RD 亦未跑，理由「会在用户真实 workspace 建 pane」我认同）。

## 十一、二轮点检（`ba7b900`）· **NO-GO**

- 结论：**NO-GO（1 条 P1，新回归）**；报的 P2-1 盲区本体已修好（三形态 1/1/2 + 行号级点名），五条 P3 中四条真落地、一条数字仍对不上。
- **P1-1 `absent` 路径未处理 ⇒ npm 安装态每次 `check` 常驻假 warn（本批新回归）**
  - 机理：`premise_declared_backend` 对不存在/无前提行的文件仍输出单 token `absent`，调用方 `while IFS=$'\t' read -r n decl` 把它读成 `n=absent, decl=""`，落进「不一致」分支（`[[ "$decl" == "absent" ]]` 永远不成立，是死代码）。
  - 复现（真实安装信道）：npm 包 `files` = `bin/ .agents/ README.md LICENSE`（`npm pack --dry-run` 59 文件**无 `AGENTS.md`**）；拷出同布局到 `/tmp` 后 `cd /tmp && node <pkg>/bin/nao-skill.js exec check -v` ⇒ `! 端前提声明不一致：AGENTS.md:absent 声明默认后端 = ，而实现默认 = herdr…` + 摘要 `warn=1`。
  - 是回归：同布局换 `0ee9866` 的脚本 ⇒ `check: OK` 两行、无 warn。rc 仍 0，但（a）用户侧每次体检一条乱码式假 warn、（b）与函数注释「absent ⇒ 不适用（非包根 / 下游 shim 仓 / 包内不带 AGENTS.md）」正面矛盾、（c）PM 的「`warn>0` 就 `-v`」会被永久触发。`cases/34` 无 absent 断言（`grep -c absent` = 0）。
- 已点到 ✓：
  - **三形态**：仅 `:18` 旧文 ⇒ 1 条点名 `AGENTS.md:18`（nodecl）；仅 `:33` 改 tmux ⇒ 1 条点名 `AGENTS.md:33`；两行都改 ⇒ **2 条**（`:18`/`:33` 各 1，无重复）。三者 rc 均 0，摘要 `warn=1/1/2`。条数口径（= 声明行数 = 事实数，不合并吞行号）与我判据自洽。
  - **先红来自判据**：`0ee9866` 旧实现 × 新断言 × **当前文档** ⇒ **11 FAIL / rc=1**，红点 = `C1c`(0≠1)/`C2c`/`C2d`/`C3b`(1≠2)/`C3c`/`C3d`/`C3e` + `B3`/`B3b`（格式），**D 组 0 红** ⇒ 不是「文档旧」凑的。
  - `cases/34` 自跑：tmux **44 PASS / 0 FAIL**；herdr **43 PASS / 0 FAIL + 1 NOTE**（rc=0）。
  - **P3-3 ✓** 文案改 `文件:行号`（`AGENTS.md:18`、`.agents/common/intercom-protocol.md:36`），无 label 重复。
  - **P3-4 ✓** `nao-fleet.sh:107` 已改「tmux 后端行为（回退通道…）」；`124-align.md` 不再裸引 `:141`，改「`NAO_TERMINAL` 唯一赋值点（现 `:145`）」，实测赋值仍在 `:145`。
  - **P3-5 ✓** 索引 = `已接受（已落地 v0.19.1；已被 herdr 默认取代 v0.23.x）`，嵌套括号已去且与正文一致。
  - **P3-1 ✓** `SKILL.md` 改「新增指针…非必需」；`pm-operations.md` 改「既有矛盾口径订正」。
  - **禁夹带 ✓** `ba7b900` 仅 4 文件（脚本注释 + 两函数 / ADR 索引 1 行 / 报告 / `cases/34`），S1/S3/E1 零命中。
- **P3-6（新）AC5①「13 条未过」不可复现**：忠实三元组（`23f76e9` 用例 × `23f76e9` 脚本 × `23f76e9` 文档）实测 **12 FAIL**（连跑两次同形；`RESULT: FAIL`）；可复现的是 9（旧用例 × 旧脚本 × 当前文档）。新用例 × 旧脚本 × 当前文档 = 11。建议写成「旧用例 12 / 当前文档 9」并标用例文件版本。
- 纪律：三形态临时改 `AGENTS.md` 后由 `git show HEAD:AGENTS.md` 写回，md5 = `262e1d8…`（协议未动 = `c78ae83…`），`git status --porcelain` 空；未 `checkout`/`switch`；自建 `/tmp` 夹具与失败缓存已删。

## 十二、三轮点检（`03c8401`）· **GO**

- 结论：**GO**（无 P1/P2；4 条 P3 均不阻断）。P1-1 真修，包根形态我独立复跑。
- **包根形态（自己跑，不引 PM 输出）**：`npm pack` → 解包 `/tmp/qa124-pack/package` ⇒ `AGENTS.md` **不存在**（包 `files` = `bin/ .agents/ README.md LICENSE`）；`cd /tmp && env -u NAO_SKILLS node <pkg>/bin/nao-skill.js exec check -v` ⇒ `^  ! 端前提` = **0** · `absent` = **0** · rc=0；默认摘要 `grep -c 'warn='` = **0**，三行照常（含「生效后端」）。
- 代码面：`premise_declared_backend` 对不存在/无前提行只 `return 0`（不再打印 `absent`），调用方删掉死代码 `[[ "$decl" == "absent" ]]`，仅留空行 `continue` —— 实现与注释「无输出 = 不适用」同口径。
- **先红（P1-1 本体）**：用 **`ba7b900`** 的实现 × 当前断言 = **6 红**，恰为 `E1/E2/E3/E3b/E4/E4b`，实际值 1/1/2/1 + 两条「不应包含」命中 ⇒ **1≠0 / 2≠0 的形态红**，非文档旧。**注**：若按字面把 `0ee9866` 的 `premise_declared_backend` 塞进新调用方，是接口错配（旧函数输出单 token、无行号），实测 21 红（含 A/B/C 组）——不能作为 P1-1 的先红；P1-1 只在 `ba7b900` 成立。
- **E 组作用域逐条**：E1/E2/E3/E3b 断的是**零 warn 计数**（不是「没崩」）；E1b/E2b/E3c 另有 `rc=0`。但 E3（协议+AGENTS 双缺）与 E4/E4b（`not_contains`）**既无 rc 也无正锚** ⇒ 若 check 将来早退且输出为空，这三条会空转通过。实测 E1 形态 check 跑满（`== 运行前提` 在、`-v` 64 行、rc=0），当前不空转 ⇒ P3-7。
- **语义边界（第 4 项）**：正常信道（shim / npm 安装）`nao-skill` 一律 `NAO_SKILLS=PKG_ROOT`，`check` 只读**包内** `intercom-protocol.md` 与包根 `AGENTS.md` ⇒ 下游项目自己的 `AGENTS.md` 不参与判定 ⇒ **不会误报**；shim 写入项目的 AGENTS.md 来自 `.agents/templates/AGENTS.md.example`，模板无三个标记词 ⇒ 也不踩 nodecl。残留误报面 = legacy 全量副本 / `NAO_SKILLS` 指到项目根：实测项目 AGENTS.md 写「## 运行前提 / Node ≥ 20」⇒ `! 端前提声明不可比对：AGENTS.md:3 …`（warn-only、rc=0），且文案把用户的项目前提说成「端前提声明」略有误导 ⇒ P3-8（建议标记词加共现约束：同行须含 `pi ≥` 或 `后端`）。
- **P3-2 三元组 ✓** 与报告文字一致：旧用例×旧脚本×旧文档 = **12** · 旧用例×旧脚本×当前文档 = **9** · 新用例×旧脚本(`0ee9866`)×当前文档 = **11**；小账 = 报告「旧文档」未标 `23f76e9` 版本戳 ⇒ P3-9。
- 门禁面抽核：`cases/34` tmux **53 PASS / 0 FAIL**、herdr **52 PASS / 0 FAIL + 1 NOTE**；`check` rc=0 · files=54 · 工作区 `git status` 空；`03c8401` 仅 3 文件（脚本 11 行 / 报告 / `cases/34`），`CARD_MAX_LINES|hotfix|三段阶梯` 0 命中。
- 纪律：本轮未改仓库任何文件；临时副本（`/tmp/qa124-r3|r4|fx3|fx4|pack`）与自建失败缓存 `nao-t4.mYB0Og` 已删；未 `checkout`/`switch`。
