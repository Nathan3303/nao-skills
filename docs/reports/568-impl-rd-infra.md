# T568 实现报告：nao-orch 阶段 3 —— board 同快照 + 多仓不串仓 + 90m stalled

- 日期：2026-11-25
- 角色：rd-infra
- Issue：[#183](https://github.com/Nathan3303/nao-skills/issues/183)
- 分支：`feat/568-orch-board-multirepo` · base `origin/main` = `718fe2e`（阶段 2 已合并）
- 规格（唯一源）：PRD `docs/prds/2026-11-24-orchestrator.md` §七 AC10/AC11 · §六「超时动作的当前覆盖面」· ADR `docs/adr/2026-11-24-orch-stage2-and-script-split.md`（D1/D2/D4/D5/D6/D7 不变，仅在其上增量）

## TL;DR

- **AC11 `board`**：子命令（无新 `bin` 入口），数据源 = `queue.jsonl` + `docs/queue/*.receipt.json`，**一次运行只读一次队列**；`--json` 字段成为长期契约；人读面按 state 分区 + 阻塞/在飞/最近回执；禁落盘、禁缓存。
- **AC10 多仓不串仓**：派单目标必须同时满足「role(+task) 命中」与「`repo` == 本仓」；`ensure` argv = `<role>@<repo_root>` 且子进程 cwd = 本仓根；通知目标也只用本仓 pm（`to` = 该会话 name，带 cwd）。他仓 / 同名 / repo 不可判定 ⇒ **零 ensure、不猜**，stderr 点名。
- **90m `stalled`**：WAL `intent` 增 `head`（派单时只读 `git rev-parse HEAD`）；`working` 行 `now - intent.at ≥ 90m` **且** HEAD 未变 ⇒ `blocked(stalled)` + 通知（同 `no_ack` 口径，attempt 不递增）；HEAD 已变 ⇒ 不判（有进展迹象）。PRD §六 同步。
- 门禁：`check` rc=0 ×2（`files=67`，`cmp` IDENTICAL）· `--case 46` 107 / `47` 34 / `48` 126 / `49` 23 / `50` 35 全绿 · 全量 `npm test` rc=0（**47 例 · 断言 3038**，SKIP=0 DEGRADE=0 NOTE=18 白名单）· `status` 文本逐字不变（`.agents/**` 零改动 + `cases/48`⑦ 文本断言）。

## 一、交付物（逐项）

- `bin/lib/queue.mjs`：新增导出 `parseQueueText(file, text)`（**只做行解析、不打开文件**）；`parseQueue` 改为读一次后委托 ⇒ 行为零变更，board 才有「只读一次」的实现基础。
- `bin/lib/orch/tick.mjs`：
  - `selectTarget(status, role, task, repoRoot)`（导出）：AC10 归属判定唯一入口；`roleState` 改为单仓口径（他仓 working 不阻塞本仓）。
  - `board()` / `readReceipts()`：队列文本只读一次，之后所有行/计数/任务都从该 text 派生；回执只读不校验（坏 JSON 只计数）。
  - `stalledPhase()` / `gitHead()`：90m 停滞相位；`dispatchPhase` 在 WAL intent 记 `head`、`target`（name/cwd）、`target_repo`，`ensure` argv 加 `@<repo_root>` 且 `cwd` 锚到本仓根。
  - journal 单行增 `stalled=` 字段（既有字段与顺序不变）。
- `bin/lib/orch/fleet.mjs`：`runArgv` 支持显式 `cwd`；`gitExec` 支持 `NAO_ORCH_GIT` 测试注入（argv-only、零 shell 不变）。
- `bin/nao-orch`：`board` 输出改为契约字段 `tick_at/digits/tasks/receipts`；人读面四段（分区 / 阻塞 / 在飞 / 回执）；usage 补 AC10 与 90m 口径。
- 用例：`cases/48` 扩 13 条（②b 90m stalled 三态）；新增 `cases/49-orch-multirepo`（AC10 三变体）与 `cases/50-orch-board`（AC11 契约 + 读一次证明 + 禁落盘）；`run.sh` 注册 49/50（`FAST_SKIP_PRICE`，契约档，零真机）。
- 文档：PRD §六「超时动作的当前覆盖面」改为**已实现（90m 且 HEAD 未变）** + 判据依赖 WAL `head`；本报告；`docs/tasks-state.md` 手写区 1 行。

## 二、`board --json` 契约（`schema:1` · 只增不删）

实测输出（夹具三行队列 + 一条回执）：

```json
{"schema":1,
 "tick_at":"2026-11-25T10:00:00Z",
 "repo":"/abs/repo",
 "digits":{"queued":1,"dispatched":1,"working":0,"qa":0,"qa_fail":0,"qa_pass":0,"merging":0,"merged":0,"released":0,"blocked":1},
 "tasks":[{"id":"T900","title":"x","state":"queued","owner":"rd-infra","qa":"qa","prio":"P1","deps":[],"attempt":0,
           "updated":"2026-11-25","age_min":600,"blocked_reason":"","wal":"","repo":"demo","branch":"feat/x"}],
 "receipts":{"total":1,"ids":["T900"],
             "latest":[{"id":"T900","author":"rd-infra","at":"2026-11-25T12:00:00Z","head":"abcdef1",
                        "pushed":true,"gates":{"check":0,"full":0},"acs":1}],
             "unreadable":0},
 "wal_bad_lines":0}
```

- `schema`：恒 `1`；不兼容变更须换值。
- `tick_at`：本次快照时刻（`--now` 可注入，便于复现）。
- `repo`：本仓根（绝对路径）。
- `digits`：状态表**全集**、缺席补 `0`（形状稳定，调用方不必判键在不在）；来源 = 同一次读到的队列快照。
- `tasks[]`：`id/title/state/owner/qa/prio/deps/attempt/updated/age_min/blocked_reason/wal/repo/branch`；`age_min` 以 `tick_at` 为基准；`wal` ∈ `intent|committed|''`（WAL 只回答派单意图，不推断 state）。
- `receipts`：`total`（可解析条数）/ `ids` / `latest`（按 `at` 倒序；单条含 `id/author/at/head/pushed/gates{check,full}/acs` 计数）/ `unreadable`（坏 JSON 计数；board 不是 validator，判红归 `nao-queue validate`）。
- `wal_bad_lines`：append-only 崩溃尾部的坏行数（只计数，不修）。

## 三、AC11 同快照判据与证据

实现：`board()` 先 `readFileSync` 一次队列文本，随后 `parseQueueText` / `validateQueue` / 计数全部基于该文本；回执与 WAL 各自只读一次；不 `mkdir` `.orch`、不写任何文件、不缓存。

证据（`cases/50` ④，抗「混合快照」）：读队列后、任何后续计算前经 `board-after-queue` 钩子把队列 4 行全改成 `merged`。结果：`digits.queued` 仍 `1`、`blocked` 仍 `1`、`merged` 仍 `1`（不是改写后的 `4`），且 `tasks.length` 仍是同一次读到的 `4`；去掉钩子再跑 ⇒ `merged=4 / queued=0`（证明改写真实生效，上面的「不变」不是夹具失效）。同例 ③ 断言 board 前后 `queue.jsonl` sha 不变、不建 `.orch`、不写 WAL。

## 四、AC10 多仓归属：判定规则（fail-closed）

对每条待派单行（`owner` 角色 + 本行 `id`）：

1. 候选 = `status --json` 中 `online` 且 `role === owner` 的会话；`repo` 与本仓根物理路径相等才算**本仓**。
2. `task === id` 且本仓恰 1 条 ⇒ 目标 = 该会话（`to` = 其 `name`，并带 `cwd`）；该会话 `working`/不可投递 ⇒ 记等待、零 ensure。
3. `task === id` 命中多条目在本仓，或命中项 `repo` 为空（不可判定）⇒ **同名跨仓歧义**：skip + stderr 点名，**零 ensure**。
4. 命中项全在他仓 ⇒ 记 skip、stderr 点名，**零 ensure / 零跨仓通知**。
5. 无 task 命中时按本仓 `role` 会话判忙闲（他仓 working 不阻塞）；本仓无可投递会话且他仓有 ⇒ skip（同上）。
6. 派单调用：`ensure --task <id> <role>@<repo_root>`，子进程 `cwd = repo_root`（argv 与 cwd 双锚）；ensure 后重取 `status --json`，只接受「本仓 + role + task」的唯一命中；多条 ⇒ abort（不提交 row）。

证据：`cases/49` 三变体 —— ① 本仓 `pm(T900)` + 他仓 `pm`：`ensure` 恰 1 次、argv 含 `pm@<本仓>` 不含他仓、调用 cwd = 本仓、通知 `--to pm(T900)`（非裸名）且带 `cwd=<repo_root>`、WAL `ensured` 记同一 name+cwd；② 只有他仓 `pm`：零 ensure、row 仍 `queued`、`skipped=1`、stderr 点名「他仓」、零跨仓通知；③ 同名两条且 `repo` 均不可判定：零 ensure、`skipped=1`、stderr 点名「同名跨仓歧义」+ 冲突会话名。

单仓回归：`cases/48` 全部 AC5–AC8 判据不动（126 条全绿）；`status` 文本路径零改动。

## 五、90m `stalled`（阶段 2 遗留）

- WAL `intent` 增 `head`：派单时 `git rev-parse HEAD`（只读；失败/空输出记空串，则该行永不判停滞 —— fail-closed）。
- 判据：`working` 行 + `now - intent.at ≥ 90m` + `intent.head` 非空 + `当前 HEAD == intent.head` + 无回执 ⇒ `blocked` + `blocked_reason=stalled` + 通知（同 `no_ack` 口径），WAL 记 `stalled` 事件，`attempt` 不变。
- HEAD 已变 ⇒ 不判（stderr 点名「HEAD 已变」留观测）；缺 `head`（阶段 2 旧 WAL）⇒ 不动作。
- 时钟仍 `--now`（tests 用注入时钟，零 `sleep 900`）；HEAD 用夹具仓真 `git`（`git rev-parse` / `--allow-empty` 提交），并提供 `NAO_ORCH_GIT` 注入点。

证据：`cases/48` ②b —— 派单后置 `working`：+89m 仍 `working`（无 stalled 记录）；+91m 且 HEAD 未变 ⇒ `blocked(stalled)` + 通知 + `attempt=0`；另一轮 +91m 但先落一个空提交 ⇒ 仍 `working`、无 stalled、stderr 点名「HEAD 已变」。

## 六、门禁实测（本 worktree · HEAD 见回执）

- `bash .agents/scripts/nao-fleet.sh check`：rc=0 ×2 · `cmp` IDENTICAL · `files=67`。
- `--case 46`：107 PASS（原数不变，阶段 1 契约未动）。
- `--case 47`：34 PASS（AC9 静态闸仍绿；新增代码无 `gh pr merge` / `npm publish` / `git push main` / `shell:true` / `execSync`）。
- `--case 48`：126 PASS（113 + 13 条 stalled 三态）。
- `--case 49`：23 PASS（AC10 三变体）。
- `--case 50`：35 PASS（AC11 契约 + 人读面 + 禁落盘 + 读一次证明）。
- 全量 `npm test`：rc=0 · **47 例** · 断言 **3038** · SKIP=0 · DEGRADE=0 · NOTE=18（全部白名单命中）。
- 边界：不改 `fleet/lib/**`（`status --json` 已就绪）· 不改 `bin/nao-queue` / `bin/lib/queue.mjs` 既有行为（仅加导出 + 纯内部委托）· 不改 `package.json` / 根 `.gitignore`。

## 七、限制与已知边界

- `board` 的回执数值只做摘要（不校验 schema / 不判红）：判红仍是 `nao-queue validate` 的单一职责，避免双源。
- 停滞判据按 tick 采样（timer interval 默认 2m，误差 ≤1 interval）；HEAD 变化只作「不判停滞」的信号，不据此推断进度。
- `ensure` 的 `@<repo_root>` 依赖 fleet 既有 `@<仓路径>` 通道；若仓根含 argv token 白名单外字符（如空格），本 tick 该行 fail-closed 记 `aborted(ensure_argv)` 并点名（不退化裸名跨仓）。
- 目标会话身份以 `status --json` 的 `repo` 字段为准：`repo` 为空（归属不可判定）一律视为歧义 —— 宁愿少派一条，也不猜一次。

## 相关指针

- PRD `docs/prds/2026-11-24-orchestrator.md`（§六 已实现口径 · §七 AC10/AC11）
- ADR `docs/adr/2026-11-24-orch-stage2-and-script-split.md`（D1/D2/D4/D5/D6/D7）
- 阶段 2 实现报告 `docs/reports/567-impl-rd-infra.md`
- 用例 `tests/t4/cases/{48-orch-tick,49-orch-multirepo,50-orch-board}.sh`
