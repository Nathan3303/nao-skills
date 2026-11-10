# #96 二期 B1 · 终端后端门面与 `status` 判定面（交付报告）

> 分支 `feat/96p2-b1-status` · 范围 = PRD `docs/prds/2026-11-10-herdr-base.md` 附二 B1
> （**只做判定面**：`NAO_TERMINAL` 单点默认 + `term_*` 门面 + `status` 双实现 + herdr 侧 fail loud）。
> 本报告不含实现代码，只给契约、判据与实测数字。

## 一、交付面（一句话）

`status` 的身份/归属/忙闲证据层改为**门面 + 双实现**：tmux 走既有证据链（逐字零回归），herdr 走
`pane list` + `agent list` 结构化事实；`ensure`/`close`/`cleanup` 在 herdr 后端 **exit 4 + 点名未实现**
（不静默回退 tmux）；后端差异只允许出现在脚本内两个标记区，由静态 lint + 台账机械兜住。

## 二、契约（唯一事实）

### 2.1 后端开关

- `NAO_TERMINAL="${NAO_TERMINAL:-tmux}"` —— 全脚本 `grep -cE '^NAO_TERMINAL='` **恰 1 处**（用例 06 断言）。
  未设与显式 `=tmux` 是**同一处**赋值 ⇒ 两种拼写不可分叉；三期 herdr 转默认只改这一行。
- 非法取值（非 `tmux|herdr`）⇒ **rc=2** fail loud，不静默回落。
- **空串 = 未设**（PM 2026-11-10 拍板）：`NAO_TERMINAL=` 走 tmux 默认（`:-` 是 shell 标准语义，profile 里
  残留空串的用户期望的正是默认）；大小写敏感 ⇒ `=TMUX` 仍 rc=2。两条都用例 06 钉住。

### 2.2 门面四函数 + 一个纯谓词

| 符号 | 输入 | 输出 / 语义 |
| :-- | :-- | :-- |
| `term_require` | — | 前提闸门。tmux = 既有 `require_tmux` 逐字（exit 3）；herdr = `HERDR_ENV=1` ∧ `HERDR_SESSION` 非空/≠`default`/`^[A-Za-z0-9._-]+$` ∧ `HERDR_SOCKET_PATH` 在 `*/sessions/<session>/*` ∧ `protocol==22`，任一不满足 ⇒ **exit 3**（命令未执行） |
| `term_snapshot` | — | **每命令 ≤1 次** `pane list` + `agent list`；只对带 label 的 pane 各取一次 `process-info`。11 列 TSV：`name pane_id terminal_id cwd foreground_cwd fg_process agent_status state_change_seq agent_session argv_name hook_authority` |
| `term_liveness` | `<name> [repo]` | 只读快照、零外部调用 ⇒ `<verdict>\t<state>\t<seq>\t<hook_authority>`；verdict ∈ `online / absent / ghost / dead / mismatch / integration-missing` |
| `term_argv` | `<pane_id>` | 每行 `process-name<TAB>argv`（herdr 取**全部**前台进程；tmux 只给命令名，argv 列留空，**不用 `ps` 兜底**） |
| `term_deliverable` | `<state>` | BR7 纯谓词：`idle|done` ⇒ 0；`working|blocked|unknown`（含空值）⇒ 1。`done` 注明「无 pi 路径的死分支」 |

**判定阶梯**（`term_liveness`，定序，避免一条残留同时进多桶）：
`absent`（无 label 命中）→ `ghost`（label 在、`agent list` 无该 pane 条目）→ `dead`（前台非 pi）→
`mismatch`（`argv --name` ≠ label）→ `integration-missing`（`agent_session` 空 ∨ `hook_authority=0`）→ `online`。

### 2.3 herdr 侧纪律（BR2/BR3/BR6）

- 身份 = `pane.label` + `process-info.argv --name` 交叉校验；归属 = `pane.cwd`/`foreground_cwd` + 既有
  `repo_contains_path`（谓词不变）；忙闲 = `agent_status` + `state_change_seq`（权威源只取 `pane list`/`agent list`）。
- **不读终端标题**、**不把宿主 tmux 句柄当证据**（从 tmux shell 起的 herdr server 会把外层句柄渗进 pane）。
  两条都由静态 lint 机械兜（herdr 实现区禁字 `TMUX` / `terminal_title` / `pane_title`）。
- 所有 herdr 调用经唯一入口 `_term_herdr_exec`（注入 `--session`）；会话名来源 = `HERDR_SESSION`
  （herdr pane 内天然存在），**不从 `session list`/`pane current` 反推**。
- 名册（pi-intercom 探针）在 herdr 模式**不参与**身份/归属/忙闲（`node` 桩 0 命中断言）；
  否则会带回「双源矛盾 + 名册陈旧」两套旧病。

### 2.4 rc 语义（新增 4）

`0` 成功 · `1` 已执行但失败 · `2` 用法守卫 · `3` 前提不满足（命令未执行）·
**`4` 本后端未实现该子命令（命令未执行）** —— herdr 后端的 `ensure`/`close`/`cleanup`。
理由：1 会与「真失败」混淆；3 已被「不在 tmux 内」占用（脚本可能据此自动回退 tmux 而静默成功）。

## 三、静态机械保证（B1 立起来的护栏）

- **门面外禁裸后端调用**：`tests/t4/lib.sh::t4_scan_term_bare_calls` —— 命令行位 `tmux|herdr` 只允许出现在
  两个标记区（`term-impl-tmux` / `term-facade-herdr`）或显式台账内的函数；herdr 额外要求命中行在
  `_term_herdr_exec` 体内（`herdr --version` 白名单除外）。
- **台账只减不增**：`tests/t4/fixtures/term-legacy-allowlist.txt`，B1 立账 **8** 条（B2 两条 / B3 三条 /
  B4 三条），每条可验（函数存在 · 函数体仍含裸调用 · 去重 · ≤ baseline · 不收录渲染层/标记区内函数）。
- **herdr 区禁字**：`t4_scan_term_herdr_forbidden`（`TMUX` / `terminal_title` / `pane_title`）。
- **动态面（比静态更硬）**：用例 28 的双向 PATH 桩 —— tmux 模式下 `herdr` 桩 0 命中、herdr 模式下
  `tmux` 桩 0 命中 + `node`（名册探针）0 命中；并对比基线脚本的 **逐子命令调用次数**（C2 只比 md5，抓不到次数漂移）。

## 四、验收数字（本机实测）

- `bash .agents/scripts/nao-fleet.sh check` **rc=0 ×2，输出逐字相同**（md5 `31b5978e95e7f5b4dc7a9fd861548065`）。
- `npm test` **rc=0**：27 用例全 PASS（`SKIP=0 · DEGRADE=0 · NOTE=2`，两条 NOTE 均为既有的
  `06:static-contract` 白名单项，非本批新增）。
- `NAO_TEST_TERMINAL=herdr npm test` **rc=0**：`共享 15 / 本后端专有 1 / PENDING 11`
  （与 `tests/t4/backends/herdr.txt` 对账一致；本批**未**新增 herdr 用例/登记）。
- **BR1 双拼写 md5**（同一隔离夹具、C2 golden 9 目标）：
  未设 `NAO_TERMINAL` = `144f3447c9ff406d6aed828d9c9720e5`；显式 `=tmux` = `144f3447c9ff406d6aed828d9c9720e5`；
  C2 基线 fixture = `144f3447c9ff406d6aed828d9c9720e5` —— 三者相等。
- **双向 PATH 桩负控**：tmux 模式 status ⇒ `herdr` 桩 0 命中；herdr 模式 status ⇒ `tmux` 桩 0 命中、`node` 桩 0 命中。
- **tmux 调用次数零漂移**：status 的 `list-panes` / `list-sessions` / `display-message` / `capture-pane` /
  `has-session` 逐项与基线 fixture 相等，总次数相等。
- **门面单测**（抽取 `term-facade` 区到子进程，桩 JSON）：`FACADE_OK 16` —— 五档 verdict + BR7 五态映射 +
  快照缓存（7 次 liveness 后 `pane list`/`agent list` 仍各 1 次）+ `protocol≠22 ⇒ exit 3`。
- **幽灵 pane / 集成缺失实测**：用例 28 桩造各一条（`ghost` / `integration-missing`，后者文案含「**不可投递**」）；
  另在**真 herdr 0.9.1** 隔离会话里实测一次（私有 `XDG_CONFIG_HOME`，pi 真跑）：
  `online idle 1 1`（label + argv `--name` + `agent_session` + hook 权威）与 `ghost unknown - 0`（label 在、agent 条目缺）；
  拆场后 `sessions/` 为空、无残留进程。
- **零回归证据**：C2① status 全文 md5 与基线相等；C2② `ensure` 的「已拉起」行 + pi `--name` 值拼接 md5 相等。
- **断言增量**（只增本批新增）：用例 06 **+36**、用例 28 **+26**（另门面子进程内 `chk` 16 条，自报 `FACADE_OK 16`）、
  用例 13 **净 +1**（原交替式移出 `NAO_TERMINAL` + 新增「旧取值域仍为 0」，见 §六.7）。

## 五、与 arch 评审（2026-11-10）逐条落地

- **1a** herdr 前提用 **exit 3**（不用 1）；补齐 `HERDR_ENV` / `HERDR_SESSION` 格式 / `HERDR_SOCKET_PATH` 前缀；
  版本只打印（`-v`）、**protocol 22 是唯一硬判据**；注释显式禁止把宿主 tmux 句柄当证据。
- **1b** 快照**每命令一次**（`status` 入口显式 prime；子 shell 复用同一临时文件）；11 列（含 `terminal_id` /
  `hook_authority`）；tmux 分支**不改** `visible_session_names` / `pane_cwd_snapshot` 的签名与行为（快照去**调**它们）。
- **1c** `online` 合取式且显式含 `fg_process == pi`；新增 `dead`（前台非 pi）；阶梯定序；
  `integration-missing` 接受 `agent_session` 空 **∨** `hook_authority=0`；返回值四段。
- **1d** `term_argv` 取全部前台进程；tmux 侧 argv 列 `-`，不用 `ps`。
- **1e** `term_deliverable` 独立纯函数（不并进 liveness）；`done` 行注明死分支。
- **2** `HERDR_SESSION` 作会话名来源，三条加固全落地；复用一期两个扫描器的前缀集，未新造第三套正则。
- **3** 台账四条可验（存在/仍含裸调用/去重/只减不增）+ 不收录渲染层与标记区内函数；herdr 区禁字加
  `terminal_title`/`pane_title`；负控含「台账 stale」。
- **4** herdr 模式 `ensure`/`close`/`cleanup` **rc=4**；`--help` 仍可用；桩负控扩到
  `pane list`/`agent list`/`process-info` 0 次；`check` 的生效后端行**仅 herdr 模式**打印（tmux 路径零新增输出）。
  **rc 口径（P3-4 订正，代码未变、文档改准）**：显式 `NAO_TERMINAL=herdr` 却**缺 herdr 可执行文件** ⇒ **rc=1**
  （明确错配，不能装没看见）；缺 `HERDR_SESSION`（未在 herdr pane 内，CI 常见）⇒ **只提示不置红**；
  `protocol≠22` ⇒ rc=1（唯一可置红的机械项）。
- **补** 「herdr 模式 status 不依赖名册探针」+ 「tmux 侧调用次数不变」两条均已成用例。

## 六、遗留与观察项（不夹带，按三出口登记）

1. **B2/B3/B4 台账**（8 条）：`pane_hosts_caller` / `pane_busy` / `cmd_close`（B3）· `apply_main_col` /
   `apply_tmux_layout` / `cmd_check`（B4）· `resolve_host_window` / `spawn_tmux`（B2）。每迁一个删一条（lint 强制）。
2. **herdr 侧未列「无 label 的 pi pane」**：tmux 的 orphan 告警是标题契约的产物，herdr 无标题；无 label 的
   pi pane 可能属用户自己的 agent，B1 不列（幽灵 pane 已单列）。是否在 B4 加「非舰队 pane」提示，留给 PM/arch 定。
3. **`done` 对 pi 不可达**：映射保留（兼容非 pi agent），用例禁伪造 `done` 当验收（PRD BR7）。
4. **`blocked` 真机触发未验**（PRD「未验」清单同项）：映射已保守（不可投递），B3 回收闸门接入时再验。
5. **静态 lint 的判据边界**：与 `t4_scan_host_pane_refs` 同一命令行位前缀集 ⇒ `if ! tmux …` / `env tmux …` /
   `command tmux …` / 变量间接拼装**不纳管**（行级静态固有边界，已在 `lib.sh`、`tests/README.md` 与台账头逐条声明）。
   status 路径由动态桩兜住。
6. **herdr 每命令额外 1 次 `api schema`**（protocol 闸门，实测 5ms 级）：属「破坏性变更必须 fail loud」的成本。
7. **AC2.2 的闭环归 B2/B3**：B1 只交付 `term_deliverable` 这个**纯谓词**（映射单源、可单测），
   `status` 的在线行**不**显示忙闲 —— 加字段会改输出格式、直接破 BR1 md5。可投递判定的**消费者**
   （派活闸门 / 回收闸门）在 B2/B3 接入；PM 已在 PRD 标注。
8. **`NAO_TERMINAL` 语义变更的断言订正**：用例 13 的「宿主阶梯删除面 grep=0」原把 `NAO_TERMINAL` 列入交替式；
   该名字已被 PM 设计改作后端开关 ⇒ 从交替式移出，并**新增**一条「旧宿主阶梯取值域（screen/xdg/hypr/…）仍为 0」
   把原语义钉住（净 +1 断言）。属**有意变更**，非漂移。

## 七、第二轮（QA P1/P2/P3）修复与证据

QA 结论 P1 + P2 + 5 P3；PM 裁定本批修 P1 / P2 / P3-1 / P3-3 / P3-4 / P3-5（P3-2 按其拍板改为「空串=未设 + 文档 + 断言」）。

1. **P1 带 scope 常驻「假在线」（AC2.1 语义破口）**：`scoped_resident` 渲染循环原先只看「字段名是 resident+scope」
   就打印 ✓；tmux 侧该名单来自标题/会话/名册（是证据），herdr 侧来自 `pane.label`（**不是**证据）⇒ 四档非在线
   全被打成「✓ 在线」，与「终端证据异常」节自相矛盾。
   **修法**：该循环加 `backend == herdr && hv[<全名>] != online ⇒ continue`（证据不足不打 ✓），`a_ok` 只在真正打印 ✓ 时置位。
   修后输出（桩：`rd-fe` 在线 + `rd-be@todo` ghost + `qa@todo` 集成缺失）：
   ```
     ✓ rd-fe          在线（--name rd-fe；卡片 frontend-developer.md）
     · rd-be          未运行（ensure 拉起）
     · qa             未运行（ensure 拉起）
   == 终端证据异常（herdr 后端：label 命中 ≠ 在线）==
     ! rd-be@todo 幽灵 pane：label 在、agent 条目缺（label 命中 ≠ 在线；勿当「已在运行」，判重/回收归 B2/B3）
     ! qa@todo 集成缺失：agent_session 空或生命周期钩子权威缺（状态 idle）→ **不可投递**；请核对 pi-intercom/herdr 集成
   ```
   用例 28 新增 7 条断言（四档至少覆盖 ghost + integration-missing 的带 scope 负控，含「不得出现 `--name rd-be@todo；`」）。
2. **P2 `term_argv` 分派名错**：定义是 `__term_tmux_argv`（双下划线）而分派写 `_term_tmux_argv` ⇒ 实测 rc=127。
   修法：定义改名（1 字符级 diff）；门面单测新增 **tmux 分支三条分派断言**（`term_argv` / `term_liveness` /
   `term_snapshot` 各一条，用同名 stub 抓错名），`FACADE_OK` 由 16 升到 19。
3. **P3-1「每命令 ≤1 次」在无 label 会话下失效**：缓存判据原用 `-s`（非空），空快照 ⇒ 每次重建
   （实测 `pane list ×7 / agent list ×7`）。修法：判据改「文件存在」（`-e`），构建失败才删。
   用例 28 新增空 label 夹具（pane list/agent list 各 1 条无 label pane）⇒ 断言次数仍 = 1。
4. **P3-3 用例 13 新断言漏 `ghostty|ptyxis`**：历史真实值来自 `cda59b0` 的
   `NAO_TERMINAL_ALLOWED=(tmux foot ghostty ptyxis screen)`。修法：补进交替式 + 两条负控（注入 `=ghostty` /
   `=ptyxis` ⇒ 断言必中）。
5. **P3-4 文档与实现不符**：原写「探不到只提示不置红」；实际「显式 herdr 但缺可执行文件」⇒ rc=1（代码正确）。
   修法：报告 §五.4 与 `cmd_check` 注释改准（三分支口径见上）。
6. **P3-5 测试卫生**：门面子进程走 fallback 快照路径且无 trap ⇒ 每次在 `/tmp` 留 `nao-fleet-term-snap.<pid>`。
   修法：子进程显式 `_TERM_SNAP_PATH` + EXIT trap；用例 28 的 herdr 运行统一用**私有 `TMPDIR`**，并断言
   ① 私有 TMPDIR 跑完为空 ② 系统 `/tmp` 的快照文件**净增 = 0**（不误伤并发/历史遗留）。
7. **P3-2（PM 拍板）**：`NAO_TERMINAL=`（空串）= 未设 ⇒ tmux 默认（文档 + 用例 06 断言）；`=TMUX` 仍 rc=2。

### 7.8 第二轮后门禁（运行时口径）

- `check` rc=0 **×2 输出逐字相同**（md5 `31b5978e95e7f5b4dc7a9fd861548065`）。
- `npm test` rc=0：**27/27 PASS**，`SKIP=0 · DEGRADE=0 · NOTE=2`（既有白名单项）；全量 **`[PASS]` 行 = 1258**。
- 断言增量（**运行时 `[PASS]` 行数**，对比上一轮提交 `467958a`）：用例 06 `167 → 170`（+3）·
  用例 13 `12 → 14`（+2）· 用例 28 `94 → 108`（+14）· 合计 **+19**；其余 24 例源码零 diff（`git diff` 只碰 3 个用例文件 + `lib.sh` 的 lint 函数）。
  门面子进程断言（不出 `[PASS]` 行）由 `FACADE_OK` 计数：**16 → 19**（新增 tmux 分支三条分派断言）。
- `NAO_TEST_TERMINAL=herdr npm test` rc=0：`共享 15 / 本后端专有 1 / PENDING 11`。
- BR1 双拼写 md5 仍三者相等（`144f3447c9ff406d6aed828d9c9720e5`）；tmux 逐子命令调用次数与基线一致。
