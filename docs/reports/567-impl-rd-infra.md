# T567-B 实现报告：nao-orch 阶段 2 —— tick daemon 与无人值守调度（AC5–AC9 + systemd）

- 日期：2026-11-25
- 角色：rd-infra
- Issue：[#182](https://github.com/Nathan3303/nao-skills/issues/182)
- 分支：`feat/567-orch-daemon` · base `origin/main` = `e82d8b6`（批次 A 拆分已合并）
- 规格（唯一源）：`docs/adr/2026-11-24-orch-stage2-and-script-split.md`（D1/D2/D4/D5/D6/D7）· PRD `docs/prds/2026-11-24-orchestrator.md`（§五 接口 · §六 失败模式 · §七 AC5–AC9 · §十 拍板）

## TL;DR

- 交付 `bin/nao-orch`（Node ≥18 零依赖）+ `bin/lib/queue.mjs`（队列/状态表/渲染单源）+ `bin/lib/orch/{fleet,wal,tick,systemd}.mjs`，`status --json`（`schema:1`）成为唯一跨进程契约。
- AC5–AC8 全部**可机械测**：时钟靠 `--now`（零 `sleep 900`）、fleet 靠 PATH 桩（调用次数即判据）、崩溃靠可注入钩子（`NAO_ORCH_HOOK`）。
- AC9 双闸：结构层 `bin/lib/orch/fleet.mjs` 是**唯一** `child_process` 宿主（argv-only、零 shell、子命令白名单），静态闸 `t4_scan_orch_forbidden` 8 条判据逐条承重 + 三条注入必红。
- systemd：单元模板随包分发，`install-systemd` 先跑 `doctor`（失败 **exit 3 且不落单元/不 enable**），默认**不 enable**（`--enable` 才启用），连装两次 `diff -r` 为空。
- 门禁：`check` rc=0 ×2 逐字一致（`files=67` = 拆分后 65 + 2 个单元模板）· `--case 46` 107 断言全绿 · 新增 `--case 47` 32 条 / `--case 48` 112 条 · `status` 文本与 `e82d8b6` **逐字一致**。

## 一、交付物（逐项状态）

- **`bin/lib/queue.mjs`**（379 行）：从 `bin/nao-queue` 抽出状态表 / 字段表 / 队列解析校验 / 回执校验 / 渲染 / CAS 相关纯函数；`bin/nao-queue`（608 → 253 行）改为同引，**行为零变更**（`--case 46` 仍是 107 断言全绿）。状态机注释与表都只在本模块出现一处（复制 = 双源，禁用）。
- **`status --json`**（`schema:1`）：加在 `fleet/lib/status.sh`（文本路径 `cmd_status` **一行未改**），入口 `nao-fleet.sh` 只加 `--json` 解析与分发；`functions.txt` 174 → 176 并同步 `cases/06` 的守恒断言。字段清单见 §三（长期契约）。
- **`bin/nao-orch`**（可执行，Node ≥18 零依赖）：`tick | board | dispatch | reap | doctor | install-systemd | uninstall-systemd`。`tick` 是一次性执行（无内存态、无常驻），由 timer 或人工驱动。
- **WAL + 锁 + CAS**：`docs/queue/.orch/{wal.jsonl,lock}` + 目录自带 `.gitignore`（`*` + `!.gitignore`，根 `.gitignore` 未动）。WAL append-only + 每条 `fsync`，只存**派单意图/目标/时刻**（不存 state）；幂等键 `<id>#attempt=<n>#at=<ISO秒>`。锁 = `flock -n -E 42`（内核释锁，无 stale 锁；第二实例 rc=1 并点名持锁 pid）。写队列前记 sha、落盘前重读比对（变了 ⇒ rc=1 零写入）。
- **AC9 双闸**：结构层 `fleetExec(sub, argv)`（白名单 `status/ensure/close/session-start`、argv token 白名单、禁旗标吃参数）+ 静态闸 `t4_scan_orch_forbidden`（`tests/t4/lib.sh`，扫 `bin/nao-orch` + `bin/lib/orch/**`）+ 新例 `cases/47-orch-static-gate.sh`。
- **systemd**：`.agents/systemd/nao-orch.{service,timer}.in`（`Type=oneshot` · `TimeoutStartSec=120` · `OnCalendar=*:0/<N>` · `Persistent=true` · `RandomizedDelaySec=15s`）· `install-systemd [--interval Nm] [--session <名>] [--linger] [--enable]` · `uninstall-systemd`。
- **用例 + 报告 + 台账**：`cases/47`（32 条）· `cases/48`（112 条）· 本报告 · `docs/tasks-state.md` 手写区 1 行。

## 二、tick 的执行模型（怎么读这段代码）

一次 `tick` 的顺序（任何一步失败都不留半截状态）：

1. 解析注入时钟（`--now` / `NAO_ORCH_NOW`），拿仓根（`git rev-parse --show-toplevel`，兜底 cwd），`mkdir -p docs/queue/.orch`。
2. 读 `docs/queue.jsonl` 并**跑阶段 1 的同一套校验**（`queue.mjs`）。任一行非法 ⇒ rc=1 **零写入**（不尽力而为、不渲染）。
3. `nao-fleet.sh status --json`（单次 30s 硬超时）：rc=127（fleet 不可达）⇒ rc=1；rc=3（pane/socket/protocol 前提）⇒ rc=3 环境级失败，**不写 blocked**；契约不符（`schema≠1`）⇒ rc=1。
4. **恢复相位**（AC8）：WAL 有 intent 而 row 仍 `queued` ⇒ 用 `session_id + cwd` 去 `status --json` 探：命中 ⇒ 补提交 `dispatched`；未命中 ⇒ `blocked(dispatch_unknown)` + 通知 PM，**绝不自动重派**。
5. **追问相位**（AC7）：`dispatched` 且距 `updated` ≥15m 且无 `docs/queue/<id>.receipt.json` ⇒ `blocked(no_ack)` + 追问一次（WAL 记 `nudge`），`attempt` 不变。
6. **派单相位**：候选 = `queued` + deps 全在 `{qa_pass,merging,merged,released}` + `owner` 非空。目标角色 `working|unknown|absent`（或不可投递）⇒ **零 ensure**、只记等待（AC6）。否则：写 intent（fsync）→ `ensure --task <id> <role>` → 重取 status 拿真实会话身份（可能落槽位）→ 写 `ensured` → **CAS 提交** → 写 `committed` → 通知 PM。
7. 有落盘时重渲染 `docs/tasks-state.md` 两个标记区（best-effort；目标不存在只 NOTICE，不改 rc）。
8. 恒打印单行 journald 口径：`orch tick=<ISO> repo=<基名> scanned= dispatched= blocked= skipped= waiting= recovered= nudged= rc=`。

测试注入面（**只在显式 env 下生效**，无隐式开关）：

- `NAO_ORCH_NOW` / `--now <ISO>`：时钟。AC7 的 15m 判据全程走注入时钟，用例里**没有** `sleep 900` 一类真实等待。
- `NAO_ORCH_FLEET`：fleet 可执行路径；不设则按 `PATH` → 机制包内路径解析（用例用 PATH 桩）。`NAO_ORCH_NOTIFY`：通知器（默认无 ⇒ 只 journald + 队列留证）。
- `NAO_ORCH_HOOK`：可执行钩子，参数 = 相位名（当前只有 `before-commit`），环境里给 `NAO_ORCH_TICK_PID`。用例用它复现「intent 后、提交前被 `kill -9`」（AC8）与「提交前队列被外部改」（CAS）。

## 三、`status --json` 字段清单（长期契约 · `schema:1`）

顶层：

- `schema`：恒 `1`。不兼容变更须换 `schema` 值（调用方按值拒绝）。
- `backend`：`herdr` | `app`。
- `repo_root`：当前仓的 git 顶层（非 git 仓 ⇒ cwd 的物理路径）。
- `sessions[]`：每会话一条（见下）。
- `roles[]`：`{role, online, sessions[name...]}`，**含未在线的常驻角色**（缺席也是事实，orch 据此判 `absent`）。

`sessions[]` 单条：

- `name`：会话名（= `pi --name`，也是 intercom 的会话标识）。
- `kind`：`resident` | `derived` | `card` | `other`（`fleet_name_parse` 的结果，未识别为 `other`）。
- `role` / `task`：解析出的角色与任务号（无则空串）。
- `pane_id`：pane/terminal id（无则空串；**server 局部命名空间**，禁跨 server 比较）。
- `cwd`：pane 的 cwd（取该会话首个 pane；无 pane 则空串）。
- `repo`：归属仓（`local` ⇒ 本仓顶层；`other` ⇒ 他仓基名；`unknown` ⇒ 空串）。
- `own`：是否本仓（布尔）。
- `online`：是否有在线证据（布尔；`ghost/dead/mismatch/integration-missing` 一律 false）。
- `agent`：**三态** `working` | `idle` | `unknown`。`unknown` 覆盖「非在线」与「在线但状态不可判」（fail-closed：不等于空闲）。
- `busy`：`agent === working`。
- `deliverable`：`online && term_deliverable(state)`（`idle|done` 才可投递）。
- `verdict`：归属原始判据 `local|other|unknown`（诊断用，不参与决策）。

约束：文本 `status` 输出**逐字不变**（AC1）；`--json` 只增。`--json` 用于非 `status` 子命令 ⇒ 用法错（rc=1，不静默吞参）。

## 四、AC5–AC8 的实测命令与结果（`--case 48` 内可重放）

以下命令均在用例的临时仓（`$LAB/repo`，`git init` + `docs/queue.jsonl`）+ PATH 桩 `nao-fleet.sh` 下执行；`ensure` 调用次数取自桩的调用日志。

- **AC5（并发只派一次）**：先起 `( cd repo && SLOW_STATUS=1 node bin/nao-orch tick --now … ) &`（桩 `status` 睡 1.2s 制造重叠窗口），等锁文件出现持锁人后跑第二个 tick。
  - 结果：第二个 `rc=1`，stderr `另一个 orch tick 正在运行（持锁 pid=<pid> started=<ISO>）`，报的 pid == 锁文件里的 pid；首个 tick `rc=0`；`ensure` **总调用数 = 1**；row 只落一次 `dispatched`；WAL 只一条 `intent`。
- **AC6（working/unknown 不投递）**：
  - `status` 里 `rd-infra` agent=`working` ⇒ `ensure` 调用 **0**，row 仍 `queued`，journal `waiting=1`。
  - agent=`idle` 但 `online=false`（absent）⇒ 同样 **0** ensure。
  - `online=true` 但 agent=`unknown` ⇒ 同样 **0** ensure。
- **AC7（15m 无回执）**：T0 派单（row `updated` = `--now` 的注入时刻，非墙钟）→ `--now T0+14m` 仍 `dispatched` → `--now T0+16m` ⇒ `blocked` + `blocked_reason=no_ack`，`attempt` 仍 0，WAL `nudge` 恰 1 条，通知恰 1 次（消息带 `pm=<name>` 与 cwd）；再 tick（T0+40m）⇒ `nudge` 仍 1、通知仍 1，全程 `ensure` 仍 1 次。
- **AC8（崩在 intent 后、提交前）**：`NAO_ORCH_HOOK=<kill 脚本>` 在 `before-commit` 相位 `kill -9` 掉 tick。
  - 结果：tick 非 0 退出；row 仍 `queued`；`ensure` 已执行 1 次；WAL 有 `intent`（含 `session_id=rd-infra(T900)` 与 `cwd`）与 `ensured`。
  - 下 tick：`status` 里出现 `rd-infra(T900)` @ 该 cwd ⇒ row 变 `dispatched`，WAL 记 `recovered`，**`ensure` 仍 1 次**（零重复派单）。
  - 未命中变体：`status` 里没有该会话 ⇒ `blocked(dispatch_unknown)`，WAL 记 `dispatch_unknown`，通知 PM，**`ensure` 仍 1 次**（绝不自动重派）。
- **CAS（附加）**：钩子在 `before-commit` 往队列插一行 ⇒ tick `rc=1`，stderr 点名「sha 不符」，目标行仍 `queued`，人工插入的行完整保留（零写入，不覆盖人的编辑）。
- **队列非法（附加）**：缺字段的行 ⇒ `rc=1` 点名缺失字段，WAL **一个字节都没加**。

## 五、AC9 双闸：结构层 + 静态闸

- **结构层（AC9①）**：`child_process` 只出现在 `bin/lib/orch/fleet.mjs`（`cases/47` 断言）。该文件内所有调用都是「固定命令名 + argv 数组」：`fleetExec` 走子命令白名单（`status/ensure/close/session-start`）+ 旗标白名单 + token 白名单（`[A-Za-z0-9._:@()/+-]`），零 shell、零字符串拼命令；队列里的字符串最多成为一个 argv 元素。运行时负控：`fleetExec('merge', …)` 抛错、`fleetExec('status', ['--nope'])` 抛错。
- **静态闸（AC9②）**：`t4_scan_orch_forbidden` 扫 `bin/nao-orch` + `bin/lib/orch/**`，8 条判据：`gh pr merge` · `gh release create` · `git push …(main|master|--tags|--all)` · `git tag` · `git merge` · `npm publish` · `execSync(` · `shell: true`。注释行（行首 `//`/`#`/`*`/`/*`）豁免，行内注释之前的真代码仍受管。
- **用例双向**：真件 0 命中；8 条判据逐条注入必中；**删掉 npm 判据后同一条注入不再命中**（判据承重，不是空转绿）；三条 ADR 原文注入（`gh pr merge 1 --squash` / `npm publish` / `cp.execSync('git push origin main')`）逐条必红；每个被扫文件都逐个注入过（少扫一个文件 = 假绿）。

## 六、systemd：安装 / 卸载 / doctor

- 单元形态：`Type=oneshot` + `ExecStart=<绝对 node> <仓内绝对 nao-orch> tick` + `WorkingDirectory=<git 顶层>` + `TimeoutStartSec=120`；timer `OnCalendar=*:0/<N>`（`--interval` 默认 2）+ `Persistent=true`（**只对日历式生效**）+ `RandomizedDelaySec=15s` + `WantedBy=timers.target`。
- `Environment=`：安装时把当时的 `PATH`（含 node 所在目录）与 `NAO_ORCH_NODE` 写死（user unit 的默认 PATH 不含它们）；给 `--session <名>` 时另写 `HERDR_ENV=1` / `HERDR_SESSION=<名>`，并在 `$XDG_CONFIG_HOME/herdr/sessions/<名>/` 下发现唯一 `*.sock` 时写 `HERDR_SOCKET_PATH`。
- `doctor`（安装前置，任一 fail ⇒ **exit 3、不落单元、不 enable**）：`node ≥18` · `git`/`flock`/`herdr`/`pi` 可达（PATH）· **在 git 仓内**（非 git 仓直接拒）· 队列可校验 · `nao-fleet.sh` 可达 · `status --json` rc=0 且 `schema=1`（**protocol=22 / pane / socket 三件套的判据内含在 fleet `term_require` 里**，不在 orch 重写一份）· `flock` 可运行。
- 幂等：渲染内容 sha 相同 ⇒ 不写盘、不 `daemon-reload`、不 enable；连装两次 `diff -r` 为空。
- **默认不 enable**（阶段 2 默认关闭，ADR D6 / PRD §九）：`install-systemd` 只落单元 + `daemon-reload`；要启用显式 `--enable`（此时才 `systemctl --user enable --now nao-orch.timer`，`--linger` 才 `loginctl enable-linger`）。
- `uninstall-systemd`：`disable --now`（未启用时 rc≠0 不算失败）→ 删两个单元 → `daemon-reload`；再跑一次 `removed=0` 仍 rc=0。

## 七、门禁与数字

- `bash .agents/scripts/nao-fleet.sh check`：**rc=0 ×2，`cmp` 逐字一致**；摘要 `check: OK · roles=7 · files=67`（拆分后基线 65 + `.agents/systemd/nao-orch.{service,timer}.in` 两个新文件；ADR「AC1 口径订正」允许的唯一差异类）。
- `status` 文本：与 `e82d8b6` 在**同一替身场景**下逐字相同（904 B vs 904 B，`diff` 为空；见 §九 证据）。
- `--help`：唯一差异 = `status` 那一行加了 `[--json]` 与两行说明（新能力的文档面，AC1 的文本面仍是 `status`/`check` 输出）。
- `bash tests/t4/run.sh --case 46`：**107 断言全绿**（`bin/nao-queue` 抽取后行为零变更的硬证据；状态表新增 `queued → blocked` 边不改变既有 5 条非法转换判据）。
- `bash tests/t4/run.sh --case 47`：**32 条全绿**。
- `bash tests/t4/run.sh --case 48`：**112 条全绿**。
- `npm test`：全量见 §九（43 + 2 = 45 例）。
- 用例注册：`tests/t4/run.sh` 的 `CASE_IDS`/`CASE_TITLES` 加 `47`/`48`；快档分类 47 → `FAST_SKIP_PRICE`（契约档）、48 → `FAST_SKIP_DOUBLE`（多场 + 真 herdr 替身，单价超 15s）—— 快档自检（未分类即硬错）通过。

## 八、已知未覆盖 / 明确不做（不静默略过）

- **90m `stalled`（HEAD 未变）未纳入本批**：ADR 允许「可做可不做」。理由：判据需要「派单时的 HEAD」这一事实，而 PRD §四 明确不新增 `dispatch_at` 类字段；落法应是「WAL intent 记 `head`」+ 对 `working` 行比对 `git rev-parse HEAD`。本批先把 AC5–AC8 的崩溃/并发/时钟三条主线做扎实，`stalled` 单独一批（可与阶段 3 的 board 指标同批）。当前代码**不会**误判：`working` 行没有任何超时自动动作。
- **`reap` 是只读的**：只点名「终态/孤儿 intent」，不做破坏性回收（会话回收仍归 `nao-fleet.sh close`，PRD §九 回滚面）。自动回收需先有「谁在用什么会话」的稳定判据，不在本批范围。
- **通知器的默认取值**：`NAO_ORCH_NOTIFY` 未设时 orch 不调任何 intercom 客户端（零依赖不引包），此时通知只落 journald + `queue.jsonl` 留证（ADR D7 的「两者都做」在部署侧需把 `NAO_ORCH_NOTIFY` 写进 unit 的 `Environment=`；本次安装器暂未写，属部署待办）。
- **systemd 下的 herdr socket 仍是最脆一环**：`--session` 只在 `$XDG_CONFIG_HOME/herdr/sessions/<名>/` 下恰好一个 `*.sock` 时写入 `HERDR_SOCKET_PATH`；发现不到就不写并靠 `doctor`/journald 点名。默认不 enable，下游不会被动调度。
- **跨仓（AC10）/ 看板数值一致性（AC11）**：阶段 3（Issue #183），本批不做。
- **`install-systemd` 处理 `--enable` 的失败面**：`systemctl enable` 失败 ⇒ rc=3 并报错，但已落的单元文件不自动回滚（再跑 `uninstall-systemd` 即清）。

## 九、证据（原始输出摘录）

`status` 文本与基线逐字对照（同一替身场景、同一 lab 路径，先后各跑一次）：

```
$ diff /tmp/cmp-base.txt /tmp/cmp-new.txt && echo IDENTICAL
IDENTICAL
$ wc -c /tmp/cmp-base.txt /tmp/cmp-new.txt
 904 /tmp/cmp-base.txt
 904 /tmp/cmp-new.txt
```

`check` ×2：

```
$ bash .agents/scripts/nao-fleet.sh check > /tmp/ck1.log 2>&1; echo rc=$?   # 0
$ bash .agents/scripts/nao-fleet.sh check > /tmp/ck2.log 2>&1; echo rc=$?   # 0
$ cmp /tmp/ck1.log /tmp/ck2.log && echo CHECK_X2_IDENTICAL
CHECK_X2_IDENTICAL
$ cat /tmp/ck1.log
check: OK · roles=7 · files=67
  ! codegraph 已就绪但当前仓无索引（codegraph init；索引后每会话约 +70–90MB PSS）
  · 生效后端 NAO_TERMINAL=herdr（…）
```

tick 的真实单行输出（夹具仓，注入时钟）：

```
orch tick=2026-11-25T10:00:00Z repo=lab scanned=1 dispatched=1 blocked=0 skipped=0 waiting=0 recovered=0 nudged=0 rc=0
orch tick=2026-11-25T10:16:00Z repo=lab scanned=1 dispatched=0 blocked=1 skipped=0 waiting=0 recovered=0 nudged=1 rc=0
orch tick=2026-11-25T12:05:00Z repo=lab scanned=1 dispatched=1 blocked=0 skipped=0 waiting=0 recovered=1 nudged=0 rc=0
```

AC5 的第二实例输出：

```
nao-orch: 另一个 orch tick 正在运行（持锁 pid=2932960 started=2026-11-25T02:13:40.475Z）⇒ 本实例不执行（rc=1）
```

## 十、边界遵守

- 未改 `fleet/lib/{core,term,term-herdr,term-app,manifest,session,check,close,cleanup,ensure}.sh`（只改 `status.sh` 加 `--json`）；未改 `bin/nao-queue` 的输出/退出码/文本；未改 `package.json`；未动根 `.gitignore`；ADR 只加 D4 的一处**契约补记**（`queued → blocked`）。
- `docs/queue.jsonl` / `T566.receipt.json` 未动；台账只在 `docs/tasks-state.md` 手写区加 1 行。
- 工作树在 `/tmp/orch567`（worktree），未在主工作区 checkout。

## 十一、契约补记（需 PM/arch 认可的一条）

`bin/lib/queue.mjs` 的 `TRANSITIONS` 新增 `queued → blocked`。理由：AC8 的「WAL 有 intent 而 row 仍 queued、探不到目标会话 ⇒ `blocked(dispatch_unknown)`」必须能落到合法状态；否则只剩「自动重派」（违反「绝不双派」）或「留一个无人知的 queued」。既有边与 `cases/46` 的 5 条非法转换判据全部不变（`queued → merged` 仍红，允许集回显从 `dispatched` 变为 `dispatched/blocked`，断言用的是 `contains "允许：dispatched"` ⇒ 仍绿）。ADR 已同步一行补记。
