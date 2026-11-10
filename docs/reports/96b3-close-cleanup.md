# #96 二期 B3 · herdr 回收面（`close` / `cleanup`）交付报告

> 分支 `feat/96p2-b3-close`（base main `e98ed49`）· 范围 = PRD `docs/prds/2026-11-10-herdr-base.md`
> 附二 B3 + §五 BR7/BR9 + §七 AC2.2/AC2.4。前两批：`96b1-term-facade.md` / `96b2-ensure-spawn.md`。
> 本报告不含实现代码，只给契约、判据与本机实测数字。术语「B1/B2」指前两批交付面。

## 一、交付面（一句话）

herdr 后端第一次**真的回收会话**：`close` 的句柄层（定位 / self 判据 / liveness / 忙闲证据 / 回收句柄）
与 `cleanup` 姊妹入口（`session stop` + `session delete`）双实现落地，**共用闸门层不动**；
忙闲闸门改按 **BR7 `agent_status`** 并保留 **pi-intercom 名册第二信号（OR）**；同一 label 多 pane
默认拒（不猜）、`--force` 时**逐 pane 按安全判据**清理；唯一回收句柄 = `pane close` + **effect 复核**；
台账 **6 → 3**；tmux 路径逐字零回归（golden md5 钉死）。

## 二、契约（唯一事实）

### 2.1 子命令面与 rc

- `close`：tmux = 原实现逐字（迁入 `# >>> term-impl-tmux (回收 / 自身判定 / 忙闲)` 标记区）；herdr = 本批实现。
- `cleanup`：tmux = 原实现逐字（`-S <socket>` 显式目标）；herdr = **`cleanup --session <名>`**（stop+delete）。
- rc 语义不变：`0` 成功/幂等 · `1` 已执行但失败（含 effect 未达成）· `2` 用法守卫 ·
  `3` 前提不满足（tmux 不在会话内 / herdr 会话或 protocol 不兼容 / socket 根不符）· `4` **保留**（B3 后无未实现子命令）。
- 业务区只调门面：新增 `term_reclaim` / `term_cleanup`（业务区禁裸后端调用由 lint 继续咬）。
- 后端按显式目标分派（用法守卫在一切后端调用之前）：herdr 的 `cleanup` 必给 `--session`、给 `-S` ⇒ rc=2；
  tmux 的 `cleanup` 给 `--session` ⇒ rc=2。

### 2.2 herdr `close` 决策链（定序，任一环 fail-closed 即停）

1. **快照**：`term_snapshot` 不可用 ⇒ 拒（**不**谎报「未运行」）。
2. **定位**：`pane.label` 精确匹配（跨仓，不按 `repo` 过滤 —— label 即路由标签）。
   0 命中 ⇒ 名册若报在线 → 非 0 + 诊断；否则 `未运行（无需回收）` rc=0（幂等成功）。
3. **同名多 pane**（>1）：默认 warn 点名全部 + **零动作** + 指路；`--force` ⇒ 见 2.4。
4. **硬拒档（`--force` 也不越过）**：`mismatch`（argv `--name` ≠ label）⇒ 定位到的不一定是目标会话 ⇒ 拒。
5. **self 判据**（F1）：`process-info.shell_pid` 是否本进程（`$$`）的祖先 —— 三态：
   `0` 是自己 ⇒ 拒；`1` 不是 ⇒ 放行；`2` 不可判定 ⇒ **只对「(session, pane) 全等」拒**
   （`HERDR_SESSION` 已确定，比 `HERDR_PANE_ID` 即可；跨 (session,pane) 撞号一律放行，避免 B1 的 T530 式误拒）。
6. **忙闲闸门**（BR7，见 2.3）。
7. **恢复窗口 / 回放幽灵**：`process-info` **明确 `pane_not_found`** ⇒ **不回收**（不可寻址 ≠ 可回收）；
   其它错误/空输出 ⇒ 拒（`--force` 可显式越过，仍做 effect 复核）。
8. **落地**：唯一回收句柄 = `pane close`（**不做** `kill -9` 兜底）⇒ 失效快照 ⇒ **新 `pane list` 复核**：
   pane 已消失 ⇒ rc=0 + 成功行（附 pane 真实 `foreground_cwd`/`cwd`）；仍在 ⇒ **非 0 + 诊断，不静默成功**，
   且**不自动重试**（防误关）。`pane list` 失败 ⇒ effect 不可复核 ⇒ 非 0。

### 2.3 忙闲闸门（BR7）+ 名册第二信号（OR）

- `agent_status`：`idle`/`done` ⇒ 放行；`working`/`blocked` ⇒ 拒；`unknown` ⇒ 拒（保守）。
- 无 agent 条目（幽灵）/ 集成缺失（`agent_session` 空或钩子权威缺）/ 前台非 pi（dead）⇒ 拒（fail-closed）+ `--force` + 指路。
- **第二信号（OR，按目标仓取）**：名册 `thinking` / `tool:*` 等非 `idle` 状态 ⇒ 拒。
  理由：prompt 后 ~300–400ms `agent_status` 仍 `idle`（arch 实测 744ms 才见 `working`）⇒ 单信号会误杀。
- `--force` 越过忙闲闸门时**明确 warn**（「可能丢失在跑 turn」），越过仍走恢复窗口与 effect 复核。

### 2.4 同名 label 多 pane（B2 转办 ②/③）

- 默认：warn 点名命中数与全部 `pane_id` + **不猜** + 零 `pane close`（rc=1）。
- `--force`：**逐 pane 按安全判据清理**（不猜「哪个是目标」）。绝对护栏保留：
  调用者自身不关 · `pane_not_found`（恢复窗口）不关 · `mismatch`（身份不一致）不关。
  跳过任一个 ⇒ rc=1（**部分完成不谎报全成功**），其余照常回收。
- `status` 已单列「同名 label 多 pane」（B1），本批不动其行格式。

### 2.5 `cleanup`（herdr 姊妹入口）

- **`session stop` + `session delete`**；**判 effect 不看 rc**：`stop` 非幂等（第二次 rc=1，实测），
  `delete` 幂等；effect 判据 = `session list --json` 无该名 **且** `$XDG_CONFIG_HOME/herdr/sessions/<名>` 已消失。
- 幂等前置：两项都满足 ⇒ 直接 `effect=0` rc=0（零动作）。
- 守卫（与 `session-start` 同源）：显式 `--session` 必给 · ≠`default`（BR9）· `^[A-Za-z0-9._-]+$` ·
  `HERDR_SOCKET_PATH`（若设置）必须在 `${XDG_CONFIG_HOME:-$HOME/.config}/herdr/sessions/<名>/` 下（否则 rc=3）。
- 不要求「在 herdr pane 内」（拆场是外部动作）；`cleanup` 仍豁免终端前提。

### 2.6 `status` 的投递判定（AC2.2 闭环）

- 消费者：`close` 忙闲闸门 + `status`。映射单源 = `term_deliverable`（`idle`/`done` 可投递，其余含 `unknown` 不可）。
- **不改任何既有行格式**（BR1 md5 逐字）：herdr 模式新增**独立节**
  `== 投递判定（BR7：…）==`，一行一个非 absent 会话：`· <名>：可投递/不可投递（agent_status=… / verdict=…）`。

### 2.7 台账（只减不增）

`tests/t4/fixtures/term-legacy-allowlist.txt` **6 → 3**：`pane_hosts_caller` / `pane_busy` / `cmd_close`
三条删除（前两条迁入 tmux 标记区；`cmd_close` 只剩门面调用）。剩 `apply_main_col` / `apply_tmux_layout` /
`cmd_check`（B4）。`baseline: 3`；负控改为「自造第 4 条 ⇒ 必红」。

## 三、验收证据（逐条对应 PM 八项）

### ① 真机 smoke（私有 `XDG_CONFIG_HOME` + 独立 session + 真 pi）

环境：`XDG_CONFIG_HOME=/tmp/nao-b3-evi/cfg`，session `nao-b3evi-3453658`，目标仓 `nao-skills`，
控制 pane 与角色 pane 同一 workspace（label = 会话名），所有 fleet 调用都在 herdr pane 内（`pane run`）。

```
### session-start（清宿主终端句柄 + 枚举清 HERDR_*）
[fleet] herdr session=nao-b3evi-3453658 server 已就绪（socket: .../sessions/nao-b3evi-3453658/herdr.sock）
rc=0

### ensure rd-fe qa（真 pi，B2 就绪门）
[fleet] [herdr] 已拉起 rd-fe @ .（pane=w1:p2）
[fleet] [herdr] 已拉起 qa @ .（pane=w1:p3）
[fleet] 已拉起 2 个会话（成功 2 / 跳过 0 / 失败 0）
rc=0
（pane list：w1:p2 label=rd-fe status=idle · w1:p3 label=qa status=idle）

### status（AC2.2 独立节）
  ✓ rd-fe          在线（--name rd-fe；卡片 frontend-developer.md）
  ✓ qa             在线（--name qa；卡片 test-engineer.md）
== 投递判定（BR7：idle/done 可投递；working/blocked/unknown 不可投递）==
  · rd-fe：可投递（agent_status=idle）
  · qa：可投递（agent_status=idle）
rc=0

### busy 拒（真 turn：agent prompt → sleep 40 ⇒ working）
[fleet] 拒绝回收 rd-fe：agent_status=working（BR7：working/blocked/unknown ⇒ 不可投递）
rc=1        （pane w1:p2 仍在）

### idle 放行（真 close）
[fleet] 已回收 rd-fe（herdr pane w1:p2）@ /home/nathan/Projects/nao-skills
rc=0        （pane w1:p2 消失；`pgrep -af -- "--name rd-fe$"` ⇒ none）
[fleet] 已回收 qa（herdr pane w1:p3）@ /home/nathan/Projects/nao-skills
rc=0        （pane w1:p3 消失；qa 的 pi 进程消失）

### cleanup（stop+delete，连跑 2 次）
[fleet] 已终结 herdr session=nao-b3evi-3453658（stop+delete；effect=已消失）   rc=0
[fleet] herdr session=nao-b3evi-3453658 已清理（effect=0；stop+delete 均无动作） rc=0

### 收场
sessions/ 目录为空（总计 0）· herdr/pi 残留进程 0 · `herdr session list`（私有根）只剩 default(stopped)
用户 `~/.config/herdr` 前后快照 diff **空**（6 文件，路径/大小/mtime 全等）· 用户 `default` 仍 running
```

### ② 误杀防线

- `working` / `blocked` ⇒ 拒（桩：`blocked` 与 `working` 各一组，零 `pane close`）。
- `idle` ⇒ 放行（桩 + 真机各一；真机两角色如实回收）。
- `unknown` / 无 agent 条目 / 集成缺失 / 前台非 pi ⇒ 拒（fail-closed）+ `--force` + 指路；桩各一组。
- `--force` 越过忙闲闸门 ⇒ 成功且**明确 warn**（桩：unknown + `--force`）。
- **第二信号**：桩构造 `agent_status=idle` + 名册 `thinking` ⇒ **拒**，理由含
  `名册状态=thinking` 与「第二信号」（确定性用例，不靠运气）；名册 `idle` ⇒ 放行（OR 另一侧正控）。
  真机 3/3 次「prompt 后立刻 close」在忙闲检查点已见 `agent_status=working`（拒），
  第二信号属滞后窗口兜底（每次 0.1s 轮询观察：第 1 拍 idle、第 2 拍即 working）。

### ③ self 判据

- 真机：在自己所在 pane 内 `close --force --task B3SELF rd-fe`（pane label 即目标）⇒
  `拒绝回收 … 判为调用者自身` rc=1，pane 仍在（未自灭）。
- 桩：`shell_pid = 用例进程（fleet 的祖先）` ⇒ 拒；不可判定 + `HERDR_PANE_ID` 与目标 pane 全等 ⇒ 保守拒；
  不可判定 + 不撞号 ⇒ 放行（不误拒）。

### ④ effect 判据

- `pane close` rc=0 但 pane 仍在 ⇒ **rc=1** + 点名「复核 pane 仍在」+ 恰 1 次 close 尝试（不重试）。
- `cleanup` 连跑 2 次：第 2 次 `effect=0` 且零 stop/delete 调用。
- `session stop` rc=1（已 stopped）但 delete 生效 ⇒ rc=0（判 effect）。
- `session delete` 无 effect（条目仍可见）⇒ rc=1 + 点名「effect 未达成」。

### ⑤ 台账 6 → 3 + 只减不增

`t4_verify_term_ledger` / `t4_scan_term_bare_calls` / `t4_scan_term_herdr_forbidden` 三支 lint 输出**空**；
用例 06 断言 `baseline: 3`；负控「自造第 4 条 ⇒ 台账行数 4 超过 baseline 3」必红。

### ⑥ 门禁（本次交付的精确数字）

- `bash .agents/scripts/nao-fleet.sh check`：**rc=0 ×2，输出逐字相同**
  （`check: OK · roles=7 · files=54 · layout=main-row2` + codegraph 齐备行）。
- `npm test`：**rc=0**；运行时 `[PASS]` 行 **1522**（改动前基线 1347 ⇒ **+175**）；
  `[FAIL]` 0；`RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`。
  增量按用例：06 **184 → 197（+13）**；28 **183 → 345（+162，含内嵌 B3 节）**。
- `NAO_TEST_TERMINAL=herdr bash tests/t4/run.sh`：**rc=0**；`[PASS]` 行 **640**（基线 627 ⇒ **+13**，全部来自 06）；
  后端索引 **共享 15 / 本后端专有 1 / PENDING 11**（登记集未改；B3 节随用例 28 在 tmux 全量跑，用例 28 仍 PENDING —— 同 B1/B2 先例，D 类迁移归 B4）。
- **BR1 零回归**：`status` 全文 md5 = **144f3447c9ff406d6aed828d9c9720e5**（未设 / 显式 `=tmux` / C2 golden 三者相等）；
  `ensure` blob md5 = **c2de6533a1826dbf470dcc401cb29063**（9 条已拉起行 + 9 个 `--name` 值）；
  tmux 逐子命令次数（`list-panes` / `list-sessions` / `display-message` / `capture-pane` / `has-session` 与总数）与基线**全等**。
- **tmux 落地段逐字**（golden md5，取自 B3 之前 `e98ed49`）：句柄层 `9549f513b7a66fbced68bc1a1fa1dc10` ·
  cleanup 体 `d8937134bb3ed4ceca29fb581d4acf2c` · socket 候选 `e4950f3897670a97d7baaea8f54727c3`；
  另带变异自证（段内加一个空格 ⇒ 同判据必红）。

### ⑦ 仓库状态

见回执：HEAD sha / `git status --porcelain` 空 / `git diff --shortstat main...HEAD`。

## 四、遗留与观察（三出口）

1. **`pane report-agent` 在 herdr 0.9.1 不能合成忙闲状态**（本批实测）：无论 `--source` 用 `pi` / `herdr:pi` /
   自造 ID，`agent list` 的 `agent_status` 与 `state_change_seq` 均不变（`agent explain` 仍报
   `full_lifecycle_hook_authority`）。**接受（含到期 2027-01-31）**：本批 busy 证据改用**真 turn**（`agent prompt`）；
   `report-agent` 的合成路径不可依赖，若后续版本修好可复用。文档（PRD 附二「未验」）无需改。
2. **真机「prompt 后立刻 close」在忙闲检查点已见 `working`**（3/3）。第二信号（名册 `thinking`/`tool:*`）
   仍保留为滞后窗口兜底，并由桩用例**确定性**覆盖（`agent_status=idle` + 名册 `thinking` ⇒ 拒）。
   **接受**：属时序观测量，不是行为缺陷；不为此加 sleep 或放宽闸门。
3. **同名 label 多 pane 的 `--force` 语义**：逐 pane 清理，但**自身 / `pane_not_found` / `mismatch` 永不关**，
   跳过即 rc=1（部分完成）。**接受**：与「宁可少关一个，不要误关一个」一致；不提供「一键全杀」。
4. **`pane close` 关掉 workspace 最后一个 pane 后 workspace 壳仍在**（pane 列表为空）。**接受**：B2 的
   `ensure` 已把「空 workspace」当重建条件处理；三期做 workspace/tab 拓扑时统一收口。
5. **`cleanup` 的 effect 复核依赖 `session list --json` 格式**（`"name":"<名>"`）。**接受**：随 protocol=22
   的 fail loud 契约约束；protocol 变更时 `term_require`/cleanup 根校验会先 fail loud。
6. **B2 转办三项已承载**：① 恢复窗口 `pane_not_found` ⇒ close 一律不回收（含 `--force`）；
   ② `--force` 同名 label 两 pane 清理（见 2.4）；③ 歧义默认 warn 点名 + 不猜（同一 label 的全部 `pane_id` 回显）。
7. **同名歧义告警在 `status` 会打两次**（B2 转办 ③ 的噪声项）：**接受（到期 2027-01-31）**，
   本批未动 `status` 的快照/判定结构（避免破 BR1）。

## 五、文件

- `.agents/scripts/nao-fleet.sh`：门面 `term_reclaim` / `term_cleanup`；herdr 回收面
  （`_term_herdr_{pane_shell_pid,shell_is_caller,self_refuse,busy,close_pane,row_verdict,reclaim_dup,reclaim,session_absent,cleanup}`）；
  `status` 投递判定独立节；tmux 句柄层 / cleanup 体迁入 `term-impl-tmux` 标记区；命令行 `cleanup --session` 分派。
- `tests/t4/cases/06-contract-guards.sh`：门面清单 + 台账 baseline 3 + close/cleanup 的 B3 断言（含用法守卫零后端调用）。
- `tests/t4/cases/28-naming-contract.sh`：内嵌 B3 节（162 条新断言：BR1 golden md5 / 忙闲三态 / 第二信号 /
  五档证据 / self 三态 / 恢复窗口 / effect / cleanup 幂等与守卫 / `--force` 重复 label 清理）。
- `tests/t4/fixtures/term-legacy-allowlist.txt`：baseline 6 → 3。
- `tests/README.md`：B3 契约与台账口径（只留指针，不复制实现）。
