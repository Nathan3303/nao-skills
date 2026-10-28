# T529 QA 独立复核：舰队绑死 tmux + pi ≥1.4.0（#48）

- 状态：已定稿（done(full)）· 更新：2026-10-28 · Owner：qa
- 指针：PRD `docs/prds/2026-10-27-strict-tmux-pi.md`（AC1–AC9 / D5–D9）· 删除面权威 `docs/reports/48-arch-review.md` · 验收对象 `da50fcc`（base `4958d47`）· Issue #48

## 范围与不测

- 复核 AC1–AC7 与 AC9 的文件面；AC8 的写操作（真拉会话）由 `cases/12` 隔离 socket 夹具覆盖，本报告不重复实拉。
- 不测：发布动作（tag / npm）· 下游三仓。只读仓库；唯一新增 = 本文件。负控期间的临时改动已即时还原（md5 见下）。
- 结论：主路径、删除面、门禁、ADR、release notes 全部通过；**1 项一般缺陷（回执断言数字不可复现）+ 2 项轻微文档口径问题**。

## 环境与命令

- 本机：tmux 3.8 · `pi --version` = 1.4.0 · node/tsx 可用 · 复核在活体 tmux（4 pane / 1 session）内进行。
- 命令：`bash .agents/scripts/nao-fleet.sh check`（含 `-v`）· `npm test` · `npm run test:t4:full` · `bash tests/t4/run.sh --case 13` · `env -u TMUX` 变体 · base 侧用 `git worktree`（4958d47，已移除）跑同套 t4 取基线。

## 结果（自跑数字，不采信 RD）

- `check`：rc=0 · roles=6 · files=50 · layout=main-row2（`env -u TMUX` 下同样 rc=0，下游无 tmux 时静态体检与 `npm test` 不受阻）。
- `npm test`：rc=0 · 16/16 PASS · SKIP=0 · DEGRADE=0 · NOTE=2。
- `test:t4:full`：rc=0 · 16/16 PASS · SKIP=0 · DEGRADE=0 · NOTE=2。
- AC1：`env -u TMUX` 跑 `ensure pm` / `status` / `close pm` 均 **rc=3**，输出**恰 1 行**（stdout 空，提示只走 stderr）。前后实测不变：panes 4 · sessions 1 · clients 1；`/tmp` 相关残留 38 项列表哈希 `7760e088…` 前后一致；无 lock / 无 `.nao*` / `docs/tasks-state.md` md5 不变；`find /tmp -newer` 只命中我自己写的快照文件。
- AC1 静态证：`require_tmux` 定义 `nao-fleet.sh:103-107`；入口闸门 `:1546-1550`，其中 `:1550` = `ensure|status|close) require_tmux; load_manifest` ⇒ 先于 `load_manifest`；`load_manifest` 定义 `:112`，仅被 `:1550` 与 `cmd_check` 内 `:1035` 调用；顶层可执行段自 `:1524` 起只有变量赋值、参数解析与 `usage`，无任何建 session / 写状态 / `mktemp` 动作。
- AC1 cleanup 豁免：无 `-S` ⇒ rc=2（单行拒绝）；不存在的 socket ⇒ rc=0，连跑两次同结果（幂等）。
- AC2：PRD §七 全名单 `grep -cE` = **0**（base = 82）；`无法确认在线` = **0**（base 1 处，原 `:1747`）；`wc -l` 1947 → **1591**（净减 356 ≥ 180）。10 项清单外漏项复核：`app_client_pid` / `pi_descendant_of` / `app_pid_for` / `TMUX_ENV_SCRUB` / `NAO_TERMINAL_LIST` / `offline_verifiable` / `--background` / `BACKGROUND` / `new-session -d` / `screen` 均为 0；`visible_session_names` 保留但其 screen 分支已删（现为 tmux + 名册）。
- AC3：伪 `pi` 1.3.9 ⇒ 输出 `✗ pi 版本 1.3.9 < 1.4.0`、**rc=1**，且其后的「tmux 布局」段照常输出（证不早退，其余体检跑完）；`1.4.0-beta.1` ⇒ rc=1；真实 1.4.0 ⇒ 该断言 PASS 且 `check` rc=0。
- AC4：`run.sh` `CASE_IDS` 16 项、无 `"11"`，`CASE_TITLES` 同步删一项（`--list` 标题逐条对位），usage 由 `<01-17>` 改为 `<用例编号>`（区间失去连续性后的自洽写法）；`tests/t4/cases/11-host-ladder.sh` 已删（`git log --diff-filter=D` 命中）；`docs/reports/2026-10-12-T513-verify.sh` 的 `--numstat` = **1/0**（仅加 1 行「随 T529 退役」，原文 971 行未改写）。
- AC4 断言有效性：`cases/13` 11 条断言实跑全 PASS；负控下 ①②③ 立刻翻红（见下），非空转；⑥ 断言的「未运行（无需回收）」仅在 `nao-fleet.sh:1393` 出现，确为末段分支。
- AC5 / ADR：`docs/adr/2026-10-27-strict-tmux-pi.md` 54 行（≤60）· 5 必写节标题逐字且 `## 参考来源` 恒末 · 头部恰 4 字段 · 状态「已接受（待落地）」· 对照模式第 1 条 = 「维持现状」基线 · 全文 0 表格、逐函数删除表下沉（正文仅一句指针 `:43`）。索引净 +1 行（旧宿主阶梯行状态同步改「已废弃」）；`2026-10-12-non-tmux-host-spawn.md` 仅状态行 diff；`2026-10-13-derived-pane-window-addressing.md` 零 diff。
- AC9：`docs/releases/v0.19.0.md` 30 行，首屏即写「必须在 tmux 会话里用 + pi ≥ 1.4.0」（标题 + 状态行 + 「本次更新」），两句迁移指引齐（① `tmux new -s nao`；② 旧 `--background`/screen 会话本版不可见 ⇒ `screen -ls` 手工清理）；全文 0 表格，内部编号全部下沉「技术细节」。
- 负控（证明断言非空转）：① `require_tmux` 的 `exit 3` → `return 0` ⇒ `--case 13` 的 ①②③ 三条 FAIL（`RESULT: FAIL (3 项断言未过)`）；② `pi_version_check` 下限 `c2 >= 4` → `c2 >= 9` ⇒ `check` rc=1 + `✗ pi 版本 1.4.0 < 1.4.0`。两处均即时还原：文件 md5 前后同为 `9e3d7577b1b7c5a31533079a52e64722`，`git status` 干净，还原后 `check` rc=0。

## 断言差额（口径必须说清）

- 口径 A「断言调用点」（`git show <rev>:tests/t4/cases/*` 内 `t4_assert_*` 出现数）：base **261** → head **252**，Δ **-9**；去处全部为 `cases/13` -8、`cases/15` -1，其余 14 个用例逐例 0 变动。
- 口径 B「运行期 PASS 行」（全量 t4 跑批日志内 `^\s*(\[PASS\]|PASS\b)`，含 `cases/12` 自有 `PASS ` 格式）：base **483** → head **391**，Δ **-92**；去向 = `cases/11` -83 · `cases/13` -8 · `cases/15` -1，其余逐例 0。base 侧 `cases/11` 在本机活体 tmux 下有 2 条 F1 断言 FAIL（自 pane `%42` 未命中，属该用例与「已承载自身会话的 tmux」不兼容，与 head 无关）；按「全绿」口径 base = 485 ⇒ Δ **-94**，去处 = `cases/11` -85 · `cases/13` -8 · `cases/15` -1。
- 两口径共同结论：**去处成立**（`cases/13` -8、`cases/15` -1，其余零漂移），**RD 的「438→280（-158）」无法复现**；`cases/11` 的断言量在本机实测上限为 85（83 PASS + 2 FAIL；静态 `pass` 调用点 74 + 定义行），与 RD 声称的 -149 相差 ≥64。

## 缺陷

- **D1（一般 · P2 · 回执/台账准确性）**：RD 回执与 `docs/tasks-state.md:167` 的「断言 438→280（-158）· cases/11 -149」不可复现，违反 AC4 / BR6「须报旧基线 → 新基线 + 差额去处」的可复核要求。正确值按口径 A = 261→252（-9），按口径 B = 483→391（-92；全绿 -94）。建议 PM 在 PR 与台账改为「261→252（-9 · 调用点口径）/ 483→391（-92 · PASS 行口径）」并注明口径。
- **D2（轻微 · P3 · 文档口径）**：`tests/README.md` 的 `13` 行写「`tsx`（缺则 ③④ DEGRADE）」，实现与 `cases/13` 注释亦写「④⑤ 能力门」，实际缺失时降级的是 **⑥⑦**（④⑤ 是纯静态 grep，无依赖）。属陈旧编号，建议随 D1 一并订正。
- **D3（轻微 · P3 · 可维护性建议）**：`nao-fleet.sh:1225` 的失败文案硬编码「< 1.4.0」，而阈值逻辑用 `c1/c2` 魔术数（`:311-316`）。负控把下限抬到 9.9.9 时输出「✗ pi 版本 1.4.0 < 1.4.0」自相矛盾。本批 AC3 不受影响，建议后续提炼 `MIN_PI_VERSION` 常量并复用于文案与比较。

## 未覆盖与风险

- 未实拉真会话验证 AC8（`cases/12` 的 36 条隔离 socket + 桩 pi 断言已全绿，覆盖布局/幂等/`--force`）；未验 `pi` 缺失时 `<缺失>` 占位分支（仅静态读码确认）。
- 风险：`check` 的 pi 版本判定只在 `c1/c2` 两位上比较（`1.4` vs `1.10` 之类跨位边界未测），当前基线 1.4.0 下无影响。

## 发布建议

- 代码/文档面 **可发布**（v0.19.0）。合并前须先由 RD/PM 更正 D1 的台账与 PR 数字（AC4/BR6 硬要求），D2 可同批带上；D3 建议开后续小项。
- 回滚面与 PRD 一致：`git revert` 单提交即可恢复（旧路径已删，回滚即恢复）。

## 追加：为什么我绿、PM 红（`cases/09` §真回收）

- **同提交同命令复现**：`TMUX_PANE=%0 bash tests/t4/run.sh --case 09` ⇒ 与 PM 完全同一条 FAIL（`跨仓 pane %0 仍存活（rc=1）`）；同样命令换成 `TMUX_PANE=%5`（我的 pane）⇒ PASS。差异变量只有一个：调用者 pane id。
- **根因修正一处**：tmux 客户端**认 `$TMUX`**（实测 `TMUX=/tmp/nao-fake,1,0 tmux list-sessions` ⇒ `error connecting to /tmp/nao-fake`），`close` 并未落到默认 server。真正触发点是 **F1 自 pane 守卫**（`nao-fleet.sh:1366`；`:554` 的 `pane_busy` 同源）：拿调用者所在**默认 server** 的 `$TMUX_PANE=%0` 去比**隔离 server** 的 `%0`，跨 server pane id 撞号 ⇒ 拒杀 rc=1。手工 A/B（隔离 socket + 名册 `tmuxPane=%0`）：`TMUX_PANE=%0` ⇒ rc=1 +「解析出的 pane %0 与调用者自己的 pane 相同」、pane 存活；`TMUX_PANE=%9` ⇒ rc=0「已回收 qa-AB1」、pane 消失。方向是**误拒（安全侧）**，全程无 pane 被误杀（前后 pane 清单逐项一致）。
- **答 1（是否真执行）**：**是**。我两次全量跑的 NOTE=2 均来自 `cases/06`（AC6 文档侧、AC2 静态替代），无 `cases/09` 的 NOTE；刚才在本 pane 重跑 `--case 09` ⇒ `[PASS] AC3: 真回收跨仓 pane %0（已关闭）`、NOTE=0。
- **答 2（NOTE 掩盖）**：**存在，且就在本案**。该断言有两条 NOTE 出口——`tests/t4/cases/09-alias-guard.sh:177`（夹具会话建不起来）与 `:180`（无 tmux）；而 `tests/t4/run.sh:163` 的 full 判据只算 SKIP+DEGRADE ⇒ **NOTE 永不判红**（无 tmux 的机器上此断言从未执行也报绿）。另 `:170-173` 的通过判据是「`t09 list-panes` 未列出」而非「server 可达且 pane 已销毁」，命令失败同样走 `t4_ok`（假绿通道）。其余 NOTE 均不跳过断言：`cases/06:51`（T3 范围说明）、`cases/06:63`（静态替代证据）、`cases/07:17`（改用已发布 latest 做布局对照）；能力缺失走 `t4_skip`/`t4_degrade` 的用例是 12/13/15/16/17，**仅 `cases/09` 用 NOTE 跳过断言**。
- **答 3（差异）**：命令同一条（我 `npm test` 与 `npm run test:t4:full` 各一次，均 rc=0 · 16/16 · SKIP=0 · DEGRADE=0 · NOTE=2）。`T4_REQUIRE_FULL` 对本例无影响（它只对 SKIP/DEGRADE 判红）；差异 100% 来自 `$TMUX_PANE`（我 `%5` / 你 `%0`）。两侧 summary 数字相同，也反证我侧未被 NOTE 掩盖。
- **结论与加固**：不是「我的门禁宽松」，而是用例**对调用者 pane id 敏感**（缺 `env -u TMUX_PANE`，`cases/13/15` 已有）**且失败出口用 NOTE**。建议 T530 同批：`cases/09` 加 `-u TMUX_PANE`、两条 NOTE 改 `t4_skip`、「已关闭」判据改为「server 可达且 pane 不在」。我的复核清单加固：全量跑后**逐条归因 NOTE 行**；环境维度增加「同机换 `TMUX_PANE` 复跑一次」。
