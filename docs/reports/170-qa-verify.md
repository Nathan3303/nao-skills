# QA 目标复核报告 · #170 收口（T563）

- 状态：定稿 · 更新：2026-11-24 · Owner：qa
- 指针：复核对象 = `nao/t563-followups-170` @ **`4f32584`**（RD 实现 `475ecf8` + PM 两份 docs `4f32584`）· PR #171
- 判据单源 = PM 派单五条 AC（AC1 静态闸 · AC2 fail-closed · AC5 rc · AC4 文案 · AC3 断言）+ 处置台账 `docs/reports/170-followups.md`
- 门禁口径（加速令）：只跑 `check` + `--case 44` + `--case 06` + `--case 28`，不跑全量；日志原件 `/tmp/qa-t563-*.log`（不经 `grep` 管道丢弃）

## TL;DR

- **结论：`CONDITIONAL(P2-1)`** —— 五条 AC 的**行为**全部成立（含 PM 点名的 AC2「warn 是否被 `2>/dev/null` 吞」与 AC5「纯跳过仍 rc=0」），但 **`cases/44` ⑬ 负控**声称验「已在运行 ⇒ 纯跳过 ⇒ rc=0」，实测该场景**真起了一个新终端**（`rd-fe2`）并以「成功 1」通过 ⇒ 纯跳过在本用例里是**空转绿**（P2-1，修法便宜，见 §发现）。
- 另 2 条 P3：① `cases/44:72` 断言消息内反引号未转义 ⇒ 标签被吃掉 + 测试日志多一条 `未找到命令`；② AC1 派单五形态之外仍有 2 类关键字位盲区（`pat) hc` / `sudo hc`）。
- 门禁数字：`check` **rc=0**（roles=7 · files=53）；`--case 44` **PASS · 83 / 0 FAIL**（65→83，+18）；`--case 06` **PASS · 331 / 0 FAIL**（NOTE 2 = `06:static-contract` 白名单）；`--case 28` **PASS · 380 / 0 FAIL**。全量由 PM 在合并前跑，本报告不重复。
- 0 P1。

## 范围 / 不测

- 只验派单五处 + 门禁四条；不改 `.agents/**` / `tests/**` / PM 两份 docs（本报告是唯一新增）。
- 不测：全量用例；真 `hc` 桌面窗口往返（`cases/44` ⑪ 组自有私有 core 路径，本轮未另开真机动作）。
- 为判「是否本批回归」，额外在 `/tmp/qa-v0300` 建 `6e4b396`（v0.30.0）**只读 worktree** 做同型对比，结论见 §发现「非缺陷观察」。

## 结果（逐条，命令 + 输出）

### AC1 静态闸（关键字位 + 入口唯一性）—— 通过

自造变异（`/tmp/qa-t563-ac1.sh`，**不复用** `cases/44` 断言，只调被测实现 `tests/t4/lib.sh:t4_scan_app_bare_hc`）：

- 基线未变异 ⇒ 输出 `[]`（0 命中）
- 12 种注入形态**全红且带行号**（`1611`）：派单五形态 `if hc ls` / `then hc ls` / `! hc ls` / `while hc ls` / `command -p hc ls`，加上同组其余 `elif` / `until` / `do` / `else`，以及上批已收的 `HC_SOCKET=… hc ls` / `command hc ls` / `hc ls`
- 负控 5 形态全绿（`hc_ls x` · `_hc_wrapper ls` · `command -v hc` · `echo "hc ls"` · `hc_count=1`）
- 入口结构断言：改名 ⇒ `MISSING_ENTRY … 定义数 = 0`；**整删函数体** ⇒ 同样 `MISSING_ENTRY`（不是「无命中即绿」）。改名后原函数体内唯一合法调用点 `1630:out="$(HC_SOCKET="$sock" command hc "$@" 2>&1)"` 也转红 —— 纵深比派单要求多一层。
- 判据读码：`lib.sh:611` 前缀组含 `if|then|else|elif|while|until|do|!` 与 `command[[:space:]]+-[a-zA-Z]`；`lib.sh:610` `entry_re='^_term_app_exec\(\) \{'` + `entry_n != 1` ⇒ 打印 `MISSING_ENTRY`（`:615`）。

### AC2 fail-closed（缺 labels ⇒ unknown）—— 通过，且 warn **未被吞**

`/tmp/qa-t563-ac25.sh`（`hc-double` 夹具 + 私有 `XDG_RUNTIME_DIR`，终端 `rd-fe` 已在运行，`bare_labels` 置位）：

```
rc=1  before=1 after=1
[fleet] rd-fe 无法确认放置归属（集成缺 labels）⇒ 不自动拉起；人工核对该终端后在 herdr desktop app 确认，确需重开请加 --force 重试
[fleet] 全部 1 个角色均未拉起（成功 0 / 跳过 0 / 失败 1）；逐条原因见上
'无法确认放置归属' 行数 = 1
'不判在线、不可投递'（liveness 副本）出现 = 0
终端数变化 = 0
```

要害判定（PM 点名）：**恰 1 行，且是 ensure 自己那条**（liveness 的副本「不判在线、不可投递」出现 0 次）—— 说明 `running_verdict` 的 `2>/dev/null` 只压掉了布尔探针的副本，**没有**吞掉 fail-closed 指路；若被吞，此处应是 0 行。

- 同形态走 `status`（未抑制路径）：rc=0 · `集成缺 labels` **1 行** · `✓ rd-fe` 0 行（不判在线）
- 负控（labels 恢复齐全）：`集成缺 labels` **0 行** · `✓ rd-fe` **1 行**（判据不空转）
- 静默面复核：`running_verdict` 的 `2>/dev/null` 与 v0.30.0 的 `running()` **逐字相同**（`git show 6e4b396:…`），未引入新的 stderr 抑制面。

### AC5 rc（全败 ⇒ 1；纯跳过 ⇒ 0）—— 行为通过

- 全败：`run_fail` 置位 ⇒ `rc=1` + 一行 `全部 1 个角色均未拉起（成功 0 / 跳过 0 / 失败 1）`（`nao-fleet.sh:5131`）
- 纯跳过（**真路径** = 同 role+task 派生二次 ensure，与 `cases/22` AC2 同口径）：
  - 1st：`rc=0` 已拉起 `rd-fe(T1)`，成功 1
  - 2nd：`rc=0` · `成功 0 / 跳过 1 / 失败 0` · stderr `rd-fe(T1) 已在运行（终端 name + status 事实命中），跳过`
  - 3rd：同 2nd（幂等 effect=0，终端数恒 1）
- 判据读码：`(( SPAWN_OK == 0 && SPAWN_FAIL > 0 ))` ⇒ `return 1`。推论并已两端实测：**部分成功 + 部分失败仍 rc=0**（红判据只认「成功 0」）—— 与 PM 裁定「全败才红」一致，非缺陷。

### AC4 文案（check / check -v / --help）—— 通过

- `check` 第 3 行与 `check -v` 第 57 行**逐字相同**：`· 生效后端 NAO_TERMINAL=herdr（形态 TUI；desktop app 走 NAO_TERMINAL=app；…）`
- `--help`：`NAO_TERMINAL=<值>  后端形态：herdr（TUI，默认）/ app（desktop app）` —— 合法值枚举齐两值
- `grep -n '唯一后端' .agents/scripts/nao-fleet.sh` ⇒ 6 处，**全部**为「唯一后端**程序** = herdr（形态 TUI / app）」的准确表述，0 处「唯一后端 = herdr」失真断言（含 `:2360` 的 tmux 声明比对提示）
- 仓内其余 `唯一后端 = herdr`：ADR 历史行、`t4_note backend-gate` 退役说明、tmux 存根（`cases/41:187`）—— 均非用户可见契约陈述，不构成失真

### AC3 断言（`grep -c == 1`）—— 通过

`tests/t4/cases/44-app-backend.sh:280`：

```
t4_assert_eq "1" "$(grep -c '集成缺 labels' <<< "$APP_ERR" || true)" "⑫ 子形态：warn **恰 1 行**（同名被问两次会刷两条）"
```

精确等值（`t4_assert_eq`），不是 `≥1`；配套负控在 `:284`（labels 齐全 ⇒ 0 行）。

## 发现

### P2-1 `cases/44` ⑬ 负控的「纯跳过」是空转绿

- 断言原文（`:303`）：`t4_assert_eq "0" "$APP_RC" "⑬ 负控：已在运行 ⇒ 纯跳过 ⇒ rc=0（幂等 effect=0）"`。
- 实测同场景（我 AC5-a 复刻）：`ensure rd-fe` 在 `rd-fe` 已在线时**并不跳过**，而是按槽位递增起 `rd-fe2`（`[app] 已拉起 rd-fe2 …（pane=t2）`，`成功 1`）⇒ `rc=0` 来自**成功**而非**跳过**，`effect ≠ 0`。断言标签与事实相反，纯跳过路径未被本用例覆盖。
- 为什么不是产品缺陷：常驻重复 ensure 递增槽位是**既有设计**（`tests/t4/cases/22-ensure-outcome-lines.sh:124` 明写「v2：常驻重复 ensure 会递增槽位（S3）⇒ 跳过出口 = 同 role+task 的派生再次 ensure」）；纯跳过我已按该口径独立实测通过（见 AC5）。
- 修法（便宜，建议本批或 #171 后紧随）：把 ⑬ 负控改成 `ensure --task T1 rd-fe` 连跑两次（照 `cases/22` AC2），并补一条**终端数不变**断言（`app_addrs | grep -c .` 前后相等）—— 否则「跳过被改坏」这类回归不会被任何断言抓住。

### P3-1 `cases/44:72` 断言消息内反引号未转义

- `t4_assert_eq "1" "$(grep -cE '^_term_app_exec\(\) \{' …)" "① AC7 结构断言：唯一入口 `_term_app_exec` 恰 1 处…"` —— 双引号内的反引号被当作命令替换执行，实测日志：

```
/home/…/tests/t4/cases/44-app-backend.sh: 行 72: _term_app_exec: 未找到命令
[PASS] ① AC7 结构断言：唯一入口  恰 1 处（删/改名必红，不靠「无命中」冒充绿）
```

断言结果不受影响（`grep -c` 先于消息求值），但**恰恰是「入口唯一性」这条断言的标签被吃掉函数名**，并往测试日志里注入一条误导性的 `未找到命令`。修法：`\`` 转义或改单引号消息。同文件 `:118`/`:129` 已正确用 `\``（可对齐）。

### P3-2 AC1 残留关键字位盲区（派单五形态之外）

独立探针（`/tmp/qa-t563-gap.sh`）结果：

```
GREEN(MISS) x) hc ls
GREEN(MISS) sudo hc ls
GREEN(MISS) case $x in up) hc ls;; esac
RED   nocmd && hc ls
RED   while :; do hc ls; done
```

- `case` 分支模式位（`pat) hc`）与 `sudo` 前缀仍漏检。二者均不在 PM 本轮点名的五形态内，属「后续可加严」；注意 `)` 进分隔符类需防误报，建议单独用例验证后再改。
- 与 P3-a（#170 台账已记）同族，不阻塞本批。

### 非缺陷观察（供后来人）

- 常驻重复 ensure 递增槽位（S3）是既有设计，v0.30.0（`6e4b396`）同型，**非本批回归**（`6e4b396` 的临时 worktree 实测三次 ensure = `rd-fe`/`rd-fe2`/`rd-fe3`）。
- 部分成功 + 部分失败仍 rc=0（判据 = 成功 0 才红）；若 CI 想「有失败即红」需另立判据。

## 隔离与边界

- app 面一律 `tests/t4/fixtures/hc-double` + 私有 `XDG_RUNTIME_DIR`（`/tmp/nao-t4.*`），跑完由 `be_app_teardown` 拆场；**未碰真 `hc` core**，用户桌面版零影响。
- 对比 worktree `/tmp/qa-v0300`（`6e4b396`）只读、用后已移除，未改其内容；本仓仅新增本报告。
- 证据脚本（临时，随重启可弃）：`/tmp/qa-t563-ac1.sh` · `/tmp/qa-t563-ac25.sh` · `/tmp/qa-t563-skip2.sh` · `/tmp/qa-t563-gap.sh`；日志 `/tmp/qa-t563-*.log`。

---

## 第二轮复核（2026-11-24 · 目标 `5aeb012` + PM 文档 `5aeb012`）

- 状态：**`done(full)`** · 0 P1 · 0 P2（上轮 P2-1 视为关闭）· 3 P3（均不阻塞合并）· Owner：qa
- 复核对象：RD 整改 `915526b` + PM PRD 指针 `5aeb012`；期间 `HEAD` 由 `5aeb012` 前进到 `e087e77`（仅 `docs/tasks-state.md` +2 行，`git diff --stat 5aeb012..HEAD -- tests/ .agents/ bin/` 为空 ⇒ 被测面字节未变，门禁结果仍有效）。
- 门禁（加速令，日志先落盘）：`check` rc=0（roles=7 · files=53）；`--case 44` **95 PASS / 0 FAIL**（⑪ 真 `hc` 六条在本机实跑，非 SKIP）；`--case 06` **331 / 0**（NOTE=2 白名单 `static-contract`）；`--case 22` **62 / 0**；`--case 23` **104 / 0**；`--case 31` **18 / 0**（NOTE=1 白名单 `backend-gate`）；`--case 28` **380 / 0**。合计 990 例断言，0 FAIL。日志 `/tmp/qa563-r2-*.log`。

### 1. P2-1 的证人是否承重 —— 建成，但只在**一类**缺陷上唯一承重

我在 HEAD 的独立 worktree（`/tmp/qa563-mut` @ `5aeb012`）自造三次变异，每次跑完 `git checkout --` 并以 sha256 逐字节比对还原，工作区 `porcelain` = 0：

```
M-a  running_verdict `online) printf 'same'` → 'absent'         ⇒ 3 红：二次 rc / warn「已在运行」/ 摘要 0/1/0；「终端数不变」绿
M-b  _ensure_task_name_in_ws 首行 return 0（派生判重失效）        ⇒ 5 红：零假行 / 已在运行 / 跳过 / 摘要 / 终端数不变（1→2）
M-x  QA 自造：跳过分支内加一次 _term_app_spawn（不改计数、不打结果行）⇒ **恰 1 红：终端数不变（期望=1 实际=2）**，其余 8 条全绿
```

- **M-a 复现了 RD 的自曝**（它说「M-a 下终端数不变仍 PASS」）：因为二次拉起撞上 `_term_app_spawn` 的「目标 tab 已有终端 ⇒ 不新建第二个」守卫（`nao-fleet.sh:2014`）⇒ 无新终端。**该断言不是 M-a 的证人**，RD 的说明与实测一致。
- **M-x 证明该断言已接线、非空转**：它是该缺陷类（「跳过分支被塞入副作用，而计数/文案仍报跳过」）的**唯一**证人。
- 但也必须如实说：**自然单点变异空间内，该断言不能独立证伪** —— 凡能造出第二个终端的自然缺陷（M-b 类：派生/判重被改坏、`continue` 被去掉、tab 铸造非确定）都会同时撞红 rc / 零假行 / 摘要 / warn（见 M-b 的 5 红）。它的价值 = 兜住「副作用与计数脱钩」，不是兜住「跳过判定被改坏」。
- 结论：P2-1 的**空转绿**已实质消除（M-a 证明本场景现在**确实**依赖跳过决策；上轮该场景根本不进跳过分支），判 **P2-1 关闭**；不再要求这条断言承担它给不出的保证。

### 2. P3-2 假阳风险 —— 未发现假阳（无 P1），但「已知盲区」登记不准

自造探针（`/tmp/qa563-p32-probe.sh` · `/tmp/qa563-p32b.sh`，只调被测实现 `lib.sh:t4_scan_app_bare_hc`）：

- 真件基线 0 命中；整仓 66 个 `.sh` 过闸（`--case` 之外的脚本只作假阳面普查）**0 条非 `MISSING_ENTRY` 输出** ⇒ 无噪声。
- 正控：探针 B 组（RD 8 形态 + QA 追加 `x="$(hc ls)"` / `true | hc ls`，共 14 条）**14/14 红**；E 组追加 12 条中 **11 红 / 1 漏**（漏的 `true; up) hc ls` 在 shell 里是语法非法形态，不算真实漏检）。
- 负控：RD 已测 10 类全绿；**QA 追加 8 类全绿** —— `hc_ls=1` · `echo "up) hc ls"` · `case "$x" in esac) :;; esac` · `*) hc_ls x;;` · `*) echo "[hc] 跳过";;` · `up) # hc ls` · `x="hc ls"` · `warn "sudo hc ls 会被闸抓"`。**未发现假阳**（这是 PM 定的 P1 判据，未触发）。
- 残余**漏检**（方向是闸静音，不是噪音，P3）：`sudo -u root hc ls`（`sudo` 带参）· `up | down) hc ls`（模式内含空格）· `* ) hc ls`（`)` 前有空格）。
- **RD 的「已知盲区」写错一条**：它说「case 模式与其命令分行（`pat)` 下一行才是 `hc ls`）仍漏检」—— 实测**被抓红**（`hc ls` 在行首，走 `^` 分支）。真正的漏检是上面三条。

### 3. AC5 涟漪订正是否过宽 —— 未过宽

- 在 `/tmp/qa563-base`（`209170f` 只读 worktree）复跑：`--case 22` rc=1（60 PASS / **2 FAIL** = `AC3 rc 仍为 0`、`J1 负控 rc 仍 0`）· `--case 23` rc=1（101 / **3** = `P2-3①②③ rc=0`）· `--case 31` rc=1（17 / **1** = `② ensure rc=0`）⇒ **恰 6 条**、逐条「(期望=0 实际=1)」，**无其他失败** ⇒ 改前确实红，且涟漪范围与 6 条一致。
- 「部分成功仍 rc=0」两处**未被碰**且两侧都绿：`22:164` AC4 混合批次 rc=0、`23:368` AC4① 投递失败不改 rc（base 与 HEAD 日志同名 PASS 行）。
- 计数复核：`--case 44` `209170f` = **83** / HEAD = **95** ⇒ +12 = P2-1 块 +9（3 夹具 + 6 判据）+ ① 静态闸循环 +3（`sudo` / `up)` / `*)`）。RD 的 83→95 与「+9」两个数字互不矛盾。

### 4. PRD 指针（`5aeb012`）—— 三条口径与实测一致，但**未收干净**

- 全败 rc=1：`44 ⑭`、`22 AC3`、`31 ②`、`23 P2-3①②③`、`06 B2④` 全部断言 rc=1 且绿。
- 部分成功 rc=0：`22 AC4 混合`、`23 AC4①`、`44 ⑭ 负控` 绿。纯跳过 rc=0：`22 AC2`、`44 ⑬ 纯跳过` 绿。⇒ 新增的 BR4/D4 取代说明**与实测一致**。
- **仍自相矛盾（P3，PM 文档边界）**：同一 PRD 还有三处把旧口径当现行且无指针 —— `:12`（「不做什么：退出码语义 rc 仍为 0」）· `:44`（D 段「失败时 rc 仍为 0」）· **`:78` AC3**（「… · **rc 仍为 0**（BR4）」）。AC3 是**可执行验收条款**（对应 `cases/22` AC3），后来人照它写断言就会重造本批涟漪。建议在 `:78` 补一行取代指针（与 BR4 同写法），`:12`/`:44` 可标「历史理由」。
- 指针目标 `docs/releases/v0.30.1.md` **尚不存在**（`package.json` = 0.30.0）⇒ 属发版前的前向指针，发版时须落地，否则悬空。

### 5. 本轮新发现（P3，上轮同类但未被修）

- `tests/t4/cases/44-app-backend.sh:90` 断言消息内**反引号仍未转义**（`"① 正控B：`command hc` 前缀 ⇒ 必红"`）：运行时真的执行了 `command hc`（替身把 `HC-DOUBLE-GUARD-FAIL: 未设 HC_DOUBLE_STATE…` 打到 stderr ⇒ 每次跑该用例日志多一条**误导性残行**），标签被吃成「① 正控B： 前缀」。**断言结果不受影响**，故 P3。
- 该行来自 `bc6c0c3`（非本批引入），但本批 P3-1 的修法只改了 `:72`，且它的验收方法（`grep -c 未找到命令 = 0`）**结构上看不到这一类** —— 因为用例里 `hc` 在 PATH 上，症状不是「未找到命令」而是上面的 `GUARD-FAIL` 残行。证据：`209170f` 的 `--case 44` 日志 `未找到命令=1`（行 72）且**同样**出现「正控B： 前缀」被吃；HEAD 侧 `未找到命令=0` 但残行仍在。
- 修法：`:90` 同样写成 `` \`command hc\` ``（与 `:72` 一致），或断言消息改单引号。

### 本轮改动

- 本文件新增本节（未提交，留给 PM 折进任务 PR）；`.agents/**` / `tests/**` / `bin/**` 零改动；worktree `/tmp/qa563-base`、`/tmp/qa563-mut` 用后已 `git worktree remove`，变异均逐字节还原。
