# #96 二期 B2 · herdr 后端 `ensure`（放置 / 就绪门 / `session-start`）交付报告

> 分支 `feat/96p2-b2-ensure`（base main `8fabe7a`）· 范围 = PRD `docs/prds/2026-11-10-herdr-base.md` 附二 B2
> 本报告不含实现代码，只给契约、判据与本机实测数字。术语「B1」= 上一批门面/判定面（`docs/reports/96b1-term-facade.md`）。

## 一、交付面（一句话）

herdr 后端第一次**真的起会话**：`ensure` 在专用 session 的（按 label 匹配的）workspace 内放置 pane，**先 `pane rename` 后 `pane run`**，再以**七条件与**就绪门轮询；新增生产侧起 server 入口 `session-start --session <名>`（清宿主终端句柄 + 枚举清 `HERDR_*`）；幽灵 pane / 同名多 pane 一律不判 same、不猜；台账 8 → 6。

## 二、契约（唯一事实）

### 2.1 子命令面

| 命令 | tmux | herdr |
| :-- | :-- | :-- |
| `ensure` | 逐字不变（`spawn_tmux` 迁入 `term-impl-tmux (spawn)` 标记区） | **本批落地**：放置 + 就绪门；失败计入 `SPAWN_FAIL`，**rc 仍 0**（D3） |
| `status` | 逐字不变 | B1 判定面不变（本批只加 `ambiguous` 档） |
| `session-start --session <名>` | 打一行「无需此步」+ rc=0（幂等无害） | 清环境起 server → 轮询就绪 → attach 指路 |
| `close` / `cleanup` | 逐字不变 | **仍 exit 4**（回收归 B3） |

- `--session` 只用于 `session-start`：给参但空 ⇒ die；缺参 ⇒ die（用法守卫）。`session-start` 还硬拒 `default`（rc=2，BR9）与非法字符集。
- 后端差异仍只在门面内：新增 `term_spawn` / `term_session_start` 两个门面函数；业务区（`spawn_one` / `cmd_ensure`）只调门面。

### 2.2 放置（PM 裁定 D2 / Q2-A）

- workspace 匹配键 = **`scope`**（无 scope ⇒ `HERDR_SESSION`）；`WorkspaceInfo` 无 cwd/worktree 字段 ⇒ 只能按 label（一期契约「名字是路由标签」，且重跑幂等）。
- 命中 ⇒ 从该 workspace 的**首个** pane `pane split`；未命中 ⇒ `workspace create --cwd <目标仓> --label <scope|session> --no-focus` 建**恰好一个**根 workspace（不做 tab/拓扑设计，三期范围）。
- 顺序契约：**先 `pane rename <全名>` 后 `pane run`**（否则 `status` 可能抓到无 label 的 pi pane）。用例 28 以桩的 order 行号断言 `rename < run`。
- `_TERM_SNAP_FILE` 在 spawn 后失效 ⇒ 同一命令后续目标的判重/归属看到新 pane（不复用 spawn 前快照）。

### 2.3 就绪门（反假阳性硬判据）

全条件**与**（轮询间隔 100ms、**wall-clock 上限 5000ms**（`NAO_HERDR_READY_TIMEOUT_MS` 可覆盖）、每轮上限 50；**禁用 `agent wait --until idle`**）：

`pane 存在` ∧ `foreground name == pi` ∧ `argv --name == 期望全名` ∧ `agent_session != null` ∧ `agent_status == idle` ∧ `state_change_seq ≥ 1` ∧ `screen_detection_skipped == true`

超时 ⇒ 逐条列出**缺哪一条** + 指路 `herdr --session <s> agent explain <pane>`；pane **保留**（不自动 kill）；计入 `SPAWN_FAIL` + 摘要行；`ensure` rc 仍 0。

### 2.4 幽灵 pane / 同名歧义（PM 裁定 ②）

| 现场 | 行为 |
| :-- | :-- |
| label 命中 0 个 | 正常放置 |
| label 命中 1 个，`ghost`（label 在、agent 条目缺） | **不判 same**；复用该 pane（rename 幂等 + run），不新建同名 label |
| label 命中 1 个，**前台是交互式 shell**（`bash/zsh/sh/dash/fish/ksh/mksh/tcsh/csh/nu/elvish/xonsh`） | **不判 same**；复用该 pane（rename 幂等 + run）。**前台非 shell ⇒ 不注入**（否则会把启动命令写进 `cat`/`vim`/REPL 的输入） |
| label 命中 1 个，`process-info` 不可用（`stop→restart` 回放：pane 不可寻址） | **不判 same**；关闭该幽灵 pane 后重建（实测 `pane run`/`process-info` ⇒ `pane_not_found`，`pane close` 可用） |
| label 命中 1 个，在线 + `--force` | 新建 pane（显式 warn：随后同名 label 会有 2 个，`status` 标歧义） |
| label 命中 1 个，**前台非 shell**（`cat`/`vim`/`sleep`/…）且无 `--force` | **不注入按键、不关闭在场 pane**：warn 点名实际前台 + `SPAWN_FAIL`，给 `--force` 指路 |
| label 命中 >1 个 | warn 点名全部 pane + **不猜**（零 rename/run/split）+ `SPAWN_FAIL`；`status` 单列「同名 label 多 pane」 |

### 2.5 BR6 生产化（PM 裁定 Q1-A）

- `session-start` 是**起 server 的唯一生产入口**：`env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR` + `for v in $(env | grep -o '^HERDR_[A-Z_]*'); do unset "$v"; done`（枚举清），`setsid`（无则降级后台）。
- 宿主终端句柄名表 `_TERM_HOST_HANDLE_VARS` 声明在门面**通用区**：herdr 实现区仍**零** `TMUX` 字面量（`t4_scan_term_herdr_forbidden` 继续咬）。
- 会话名守卫与测试侧同源：非空、≠`default`、`^[A-Za-z0-9._-]+$`。
- **pane 内 `HERDR_SOCKET_PATH` 必须落在目标根**：`realpath -m` 后须以 `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/sessions/<名>/` 为前缀，否则 `exit 3`（stale/外贸 env 必拒）。`session-start` 不再重复校验它自己拼出的 socket 路径（`case "$sock"` 恒真 = 死守卫，已删）。
- 就绪判据 = **`api snapshot`**（真触 server）；`api schema` 是本地静态元数据（无 server 也 rc=0，**禁**作存活判据——本批实测踩到并修正）。
- 所有 herdr 调用仍只经 `_term_herdr_exec`（缺 `--session` ⇒ 拒）。

### 2.6 rc 与台账

- rc 语义不变：`0` 成功 · `1` 已执行但失败 · `2` 用法守卫 · `3` 前提不满足 · `4` 本后端未实现（仅 herdr 的 `close`/`cleanup`）。
- 台账 baseline **8 → 6**：`resolve_host_window` / `spawn_tmux` 已迁入 `# >>> term-impl-tmux (spawn)` 标记区 ⇒ 删除条目。`session-start` 是**已实现项**（写在台账头，不占条目）。

## 三、验收证据（逐条对应 PM 七项）

### ① 真机 smoke（私有 `XDG_CONFIG_HOME` + 独立 session + 真 pi）

`XDG_CONFIG_HOME=/tmp/nao-b2-evi/cfg`，session `nao-b2evi-1772624`，目标仓 `nao-skills`：

```
### 1. session-start（清环境起 server）
[fleet] herdr session=nao-b2evi-1772624 server 已就绪（socket: .../sessions/nao-b2evi-1772624/herdr.sock）
  · attach: herdr session attach nao-b2evi-1772624（在该会话 pane 内用 NAO_TERMINAL=herdr nao-fleet.sh ensure …）
rc=0
--- 幂等复跑 ---
[fleet] herdr session=nao-b2evi-1772624 已在运行（effect=0）；attach: herdr session attach nao-b2evi-1772624
rc=0

### 4. ensure rd-fe（单独计时 = 就绪耗时）
ensure rd-fe elapsed_ms=2811
[fleet] [herdr] 已拉起 rd-fe @ .（pane=w1:p3）
[fleet] 已拉起 1 个会话（成功 1 / 跳过 0 / 失败 0）；就绪后在线状态用 nao-fleet.sh status 查看
### 5. ensure qa（第二次：复用 workspace）
ensure qa elapsed_ms=2840
[fleet] [herdr] 已拉起 qa @ .（pane=w1:p4）

### 6. pane list 关键字段
label=rd-fe    pane=w1:p3   fg_cwd=<repo>
label=qa       pane=w1:p4   fg_cwd=<repo>
### 7. agent list 关键字段（权威源）
pane=w1:p3 status=idle seq=1 skipped=True session=<非空，kind=path>
pane=w1:p4 status=idle seq=2 skipped=True session=<非空，kind=path>

### 8. status
== 角色会话在线状态（本表按 herdr pane label + agent 状态判定；权威源 = pane list / agent list）==
  ✓ rd-fe          在线（--name rd-fe；卡片 frontend-developer.md）
  ✓ qa             在线（--name qa；卡片 test-engineer.md）
  · 其余角色未运行；任务派生节（无）
rc=0

### 9. 收场（B2 close/cleanup 仍 exit 4，直接 stop+delete）
sessions 目录：0 项
残留 herdr/pi 进程（含会话名）：0
### 10. 用户 default 快照（后）
3adb9ffa1f167c1b83226b168c55fbcb  -   （与实验前逐字一致）
USER-DEFAULT-UNCHANGED
```

两道 `ensure` 各约 **2.8s**（含 codegraph 检测 + pi 启动）；就绪门本身在 pi 报 `idle/seq≥1` 后立刻返回。

### ② 反假阳性：已 idle 但 seq 不前进 ⇒ 超时 fail loud（不是 rc=0 假绿）

用有状态 herdr 桩（`ONRUN=idle|seq=0|skip=1|session=有`，前台已是 pi）：

```
[fleet] 就绪门超时（50×0.1s）：rd-fe（pane=w1:p1）未满足以下条件：
[fleet]   · state_change_seq ≥ 1：实际 0（未观测到状态迁移）
[fleet]   · 诊断指路：herdr --session nao-b2-antifp agent explain w1:p1
[fleet] 已拉起 0 个会话（成功 0 / 跳过 0 / 失败 1）
```

只有缺的那一条被报出（前台 pi / idle / session / skipped 均不误报），且不打印成功行。同场景已固化为用例 28 的 B2①（8 条断言）。

### ③ 环境渗透：不清 env 起 server ⇒ 渗透可见；清后 `^TMUX` = 0

```
### 2. 环境渗透：不清 env 从 tmux shell 起 server（负控）
dirty pane: TMUX 行数=2
TMUX_PANE=%37
TMUX=/tmp/tmux-<uid>/default,<pid>,0

### 3. 清环境 server 的 pane 内环境自证
clean pane: TMUX 行数=0
HERDR_SESSION=nao-b2evi-1772624
HERDR_SOCKET_PATH=/tmp/nao-b2-evi/cfg/herdr/sessions/nao-b2evi-1772624/herdr.sock
XDG_CONFIG_HOME=/tmp/nao-b2-evi/cfg
```

（`session-start` 即平反路径；pane 内 `HERDR_SESSION` 与 socket 前缀都指向目标根。）

### ④ 幽灵 pane：不判 same（两种现场）

真幽灵（label 写入但 pane 内不跑 pi；agent list 为空）——复用该 pane 重跑，不新建同名 label：

```
[fleet] 幽灵 pane：rd-fe 的 label 在、agent 条目缺（pane=w1:p1）⇒ 不判「已在运行」，复用该 pane 重跑 agent
[fleet] [herdr] 已拉起 rd-fe @ .（pane=w1:p1）
（panes: 仅 rd-fe w1:p1 idle；agents: w1:p1 idle seq=1 session 有）
```

`stop → restart` 回放（herdr 0.9.1 实测：pane 出现在 `pane list`/`agent list` 但 `pane run` 报 `pane_not_found`）：

```
[fleet] restart 回放幽灵：rd-fe 的 pane=w2:p1 陈旧（verdict=dead seq=0）⇒ 不判「已在运行」，关闭该幽灵 pane 后重建
[fleet] [herdr] 已拉起 rd-fe @ .（pane=w3:p1）
（status: ✓ rd-fe 在线；无同名歧义）
```

### ⑤ 台账 8 → 6 + 负控仍咬

```
$ grep -n '^# baseline' tests/t4/fixtures/term-legacy-allowlist.txt
23:# baseline: 6
$ t4_verify_term_ledger .agents/scripts/nao-fleet.sh tests/t4/fixtures/term-legacy-allowlist.txt   # 正控
（空输出，rc=0）
$ # 负控：自造第 7 条
台账 stale（该函数已无裸后端调用，应删条目）: cmd_ensure
台账行数 7 超过 baseline 6（只允许下降）
```

### ⑥ 门禁（本机实测）

- `bash .agents/scripts/nao-fleet.sh check` **rc=0 ×2，输出逐字相同**（md5 `31b5978e95e7f5b4dc7a9fd861548065`，与 B1 相同 ⇒ check 输出零变化）。
- `npm test`（tmux 默认）**rc=0**：**27 例**全 PASS（`bash tests/t4/run.sh --list | tail -n +2 | wc -l` = 27，编号 01–10 + 12–28）· `SKIP=0 · DEGRADE=0 · NOTE=2`（既有白名单项）· 运行时 **`[PASS]` 行 = 1331**。
- `NAO_TEST_TERMINAL=herdr npm test` **rc=0**：`共享 15 / 本后端专有 1 / PENDING 11`（与 `tests/t4/backends/herdr.txt` 对账一致；PENDING 仍是未登记用例点名，含 28）。
- **BR1 零回归**：用例 28 的 C2 对照仍为 `status` 全文 md5 **`144f3447c9ff406d6aed828d9c9720e5`**、`ensure`「已拉起」行 + pi `--name` 值拼接 md5 **`c2de6533a1826dbf470dcc401cb29063`**（与基线 fixture 逐字相等）；tmux 逐子命令调用次数（`list-panes` / `list-sessions` / `display-message` / `capture-pane` / `has-session` + 总数）与基线全等。
- **断言增量（运行时 `[PASS]` 行数）**：用例 06 `170 → 184`（+14）· 用例 28 `108 → 167`（+59：B1 轮 +28 / QA 第二轮 +31）· 全量 `1258 → 1331`（+73）；其余 25 例源码与断言数零变化（未改其文件）。
- 静态 lint：`t4_scan_term_bare_calls` 0 命中 · `t4_verify_term_ledger` rc=0 · `t4_scan_term_herdr_forbidden` 0 命中（herdr 区无 `TMUX`/标题字段）· `t4_scan_herdr_bare_calls` 0 命中。

### ⑦ 提交形态

见回执（HEAD sha / 工作区静默 / `git diff --shortstat main...HEAD`）。报告与实现同 PR。

## 三之二、QA 第二轮（P2-1 / P2-2 / P3-1 / P3-3）修复证据

### ① P2-1：「`HERDR_SOCKET_PATH` 根未校验」+ 死守卫 —— 选 ①（realpath 后比较**目标根**）

- 实现：`_term_herdr_require` 现按 `realpath -m` 归一后要求 `HERDR_SOCKET_PATH` 以 `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/sessions/<名>/` 为前缀；不符 ⇒ **exit 3**（命令未执行）。测试夹具同步把 socket 放到 `$LAB/cfg/herdr/sessions/<名>/` 并设 `XDG_CONFIG_HOME=$LAB/cfg`。
- 死守卫：`_term_herdr_session_start` 的 `case "$sock"`（socket 由 root+会话名拼出、会话名禁 `/`/glob ⇒ 恒真）**已删除**；防串台由会话名守卫 + `--session` + pane 内 socket 根校验承担。
- 负控（用例 28 · P2-1 四条）：

```
P2-1 错误根的 HERDR_SOCKET_PATH ⇒ exit 3（stale/外贸 env 必拒，不假绿）
P2-1 拒绝理由点名「目标根」（不是任意 */sessions/<名>/*）
P2-1 回显期望根（可定位）
P2-1 根校验先于一切 herdr 调用（stale env 下零后端调用）
```

- 报告口径订正：原文 §2.5 写「必须在 `${XDG_CONFIG_HOME}/herdr/sessions/<名>/` 下」但实现只匹配 `*/sessions/<名>/*`（over-claim）⇒ 现实现与文字一致；`session-start` 的恒真 case 描述同步删除。

### ② P2-2：「幽灵复用直接 `pane run` 会注入用户前台程序」—— 前台 shell 白名单

- 白名单：`bash zsh sh dash fish ksh mksh tcsh csh nu elvish xonsh`（`TERM_SHELL_NAMES`；用 `process-info.foreground_processes[].name`）。
- 非 shell ⇒ **不 `pane run`、不 `pane close`**，warn 点名实际前台 + `SPAWN_FAIL` + `--force` 指路；`--force` 时也只新建 pane，**不向在场程序注入**（会产生同名 label，显式 warn）。
- **真机复现 QA 场景**（label=`rd-fe` 的 pane 前台跑 `cat > captured.txt`，从另一 pane 跑 `ensure`）：

```
[fleet] 前台非 shell（rd-fe ⇒ w1:p1 前台=cat）⇒ **不注入按键**、不判「已在运行」（向正在运行的程序写命令会污染其输入：vim/REPL/cat）
[fleet]   该怎么办：人工核对后关闭该 pane（回收面归 B3），或加 --force 新建（会产生同名 label，需人工收口）
[fleet] 已拉起 0 个会话（成功 0 / 跳过 0 / 失败 1）
rc=0    elapsed_ms=726
captured.txt = 0 字节；含 `exec pi --name rd-fe` 的行数 = 0；残留进程 = 0
```

- 桩负控（`cat` / `vim` / `sleep` 各 7 条，共 21 条）：均断言 `前台非 shell` + 回显实际名 + `--force` 指路 + 无成功行 + **`pane run` 0 次** + **`pane close` 0 次**。
- 回放分支改为 `process-info` 不可用判定（不再用 `seq==0`）：桩负控断言「点名 restart 回放幽灵 + `pane close` 恰 1 + 只在**新** pane 上 run 1 次」。

### ③ P3-1：「28 例」是最大编号不是例数 —— 订正为 27 例

- 本报告与 PR 描述中所有「28 例」⇒ **27 例**（唯一出处 `bash tests/t4/run.sh --list | tail -n +2 | wc -l` = **27**，编号 01–10 + 12–28，无 11）。
- 断言数不变：`[PASS]` 行 **1331**（新增断言来自 P2-1/P2-2/P2-2b，与例数无关）。

### ④ P3-3：就绪门「5s 上限」名不副实 —— 选 ②（wall-clock 上限）

- 实现：`deadline` 用 `date +%s%N` 计 **wall-clock**，默认 `TERM_READY_TIMEOUT_MS=5000`（`NAO_HERDR_READY_TIMEOUT_MS` 可覆盖），每轮含 3 次 CLI 也计入；超时消息口径改为 `wall-clock 上限 ${budget}ms / ≤N 轮 × 0.1s，实际 ${elapsed}ms`。
- 用例 28 B2① 用 `NAO_HERDR_READY_TIMEOUT_MS=400` 覆盖（避免白等 5s）并断言消息含 `wall-clock 上限 400ms`。
- 实测：真机正常路径 `ensure` **2713ms / 2901ms**（含 codegraph + pi 启动，就绪门在 pi 报 `idle/seq≥1` 后立即返回）；QA 观测的 ghost 成功路径 5951ms 属旧实现「只数睡眠」的 wall-clock，现超 5s 会按承诺 fail loud（并逐条报缺），可用 env 提高预算。

## 四、PM 两项裁定落地

- **Q1 → A**：新增 `session-start`（名字按裁定），不破 B1「herdr 只在 pane 内运行」的 `term_require` 契约；tmux 模式幂等无害 rc=0；台账头记为已实现。
- **Q2 → A**：`ensure` 在无 workspace 时建**一个**根 workspace；匹配键按裁定用 **label = scope（无 scope = 会话名）**，不按 cwd（`WorkspaceInfo` 无 cwd）。
- 第三条口径：就绪超时 pane 保留 + `SPAWN_FAIL` + warn + 摘要 + rc 0；`close`/`cleanup` 仍 exit 4（smoke 收场直调 `session stop/delete`）。

## 五、遗留与观察（按三出口，不夹带）

1. **`stop→restart` 回放出的 pane 不可寻址**（herdr 0.9.1 实测：`pane list`/`pane get`/`pane close` 可用，`pane run`/`split`/`process-info` 报 `pane_not_found`）⇒ 本批以「**`process-info` 不可用**判回放 + 关闭重建」处理（不再用 `seq==0` 当判据，QA P3-4 指出稳态重启会恢复 agent 条目并给新 seq，`seq==0` 只在抢进恢复窗口时命中）。**接受（含到期 2027-01-31）**：若 herdr 后续修好虚拟化时机，此分支退化为普通 ghost 复用。
2. **`--force` 在 herdr 会造出同名 label 两个 pane**（现显式 warn，`status` 标歧义）。**转办 B3**：回收面提供「重复 label 清理」；在 B3 落地前以人工 `herdr pane close` 收口。
3. **同名歧义告警在 `status` 里会打两次**（hv 预计算 + `running` 复判），属噪声不属错误。**接受（含到期 2027-01-31）**：B3 接忙闲/回收时可顺手把逐名判定缓存化。
4. **就绪门成本**：wall-clock ≤5s 内每轮（`pane list` + `process-info` + `agent list`）最多 50 轮 = 150 次 CLI。**接受**：只在超时路径付满；正常路径 2–3 次（真机实测 2.7–2.9s 完成）。
5. **`session-start` 不自证 pane 内环境**（只保证机械清环境；① ② 判据由 smoke/用例证）。若三期要把它变成门禁，可加 `--verify` 在首 pane 内跑 `env` 断言 —— **转办三期**（属布局/形态面）。
6. **在待复用 pane 内跑 `ensure` 会排队**（`pane run` 把命令投给正忙的 shell）；这是测试构造 artifact，不是生产路径（PM 从一个 pane 起其它 pane）。**接受**：已在 smoke 报告中标注，用例 28 用独立 caller pane 规避。
7. **`agent wait --until idle` 仍不可作就绪门**（B1 实测 6ms 假阳性）；本批在注释与测试里钉死，禁止后续「优化」回退。
8. **QA P3-4（转 B3 观察）**：回放叙事比实现窄 —— 稳态重启后 herdr 会恢复 agent 条目并给新 seq，本批的「`process-info` 不可用」分支只在「ensure 抢进恢复窗口」命中；窗口内还会观测到 `pane list` 有 pane 但 `process-info` 报 `pane_not_found`（<1s）。B3 接回收时要留意该窗口（不得把恢复中的 pane 当可回收/可复用）。
9. **QA P3-5（观察）**：`/tmp/nao-fleet-<card>-*.md` 在 60s 清理窗口后仍可能残留（既有机制，非 B2 引入）。**接受**，不在本批扩面。

## 六、文件

- `.agents/scripts/nao-fleet.sh`：`term_spawn` / `term_session_start` 门面；herdr 放置 + 就绪门 + 回放处理；`session-start` 命令行与 BR6 唯一入口；`resolve_host_window` / `spawn_tmux` 迁入 `term-impl-tmux (spawn)`；herdr 判重 cwd 只取结构化事实（禁名册探针）。
- `tests/t4/cases/06-contract-guards.sh`：台账 8→6 与负控、门面函数清单、`ensure` 不再 exit 4、`session-start` 守卫。
- `tests/t4/cases/28-naming-contract.sh`：有状态 herdr 桩（就绪超时 / 幽灵复用 / 同名歧义）、`/tmp` 快照净增改 PID+mtime 归属 + 变异自证。
- `tests/t4/fixtures/term-legacy-allowlist.txt`：baseline 6 + 台账头记录 B2 已实现项。
- `tests/README.md`：herdr 生产侧放置/就绪口径一段。
