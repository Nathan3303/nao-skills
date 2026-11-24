# QA 目标复核报告 · herdr desktop app 第二后端（T562 / #168）

- 状态：定稿 · 更新：2026-11-24 · Owner：qa
- 指针：初核对象 = `d6fa0ab`；**整改后复验对象 = `685b292`（PR #169 head）** —— 结论见 §⑦
- 判据单源 = PRD `docs/prds/2026-11-24-herdr-app-backend.md`（AC1–AC10 + AC3b + §六之二）· ADR `docs/adr/2026-11-24-herdr-app-backend.md` · arch `docs/reports/168-arch-review.md`

## TL;DR

- **最终结论：`done(full)` — 0 P1 / 0 P2**（整改后复验 @ `685b292`）。初核 `CONDITIONAL(AC7)` 的 P2 已关闭：AC7 闸加严后，派单点名的四类形态（`command hc` / env 前缀 / 整删入口 / 改名入口）全部转红。
- 4 条 P3 全部处置完毕：①**缺 `labels` ⇒ 判 `unknown` + 恰 1 行 warn**（整改为必改，已复验含负控）② 探针白名单 2→3 **改显式文件名允许列表**（不构成判据放松，见原判定段）③ 文案「唯一后端」④ `ensure` 全败仍 rc=0 —— ③④ PM 接受为 **follow-up #170**，不阻塞本批。**后来人勿视为漏判，均已具名归口。**
- 门禁数字：`check` **rc=0**；`--case 44` **PASS · 65 / 0 FAIL**（58→65，+7 条新正控）；`--case 06` **PASS · 331 / 0 FAIL**（NOTE 2 = `06:static-contract` 白名单）；`--case 28` **PASS · 380 / 0 FAIL**。全量门禁由 PM 在本机跑（`685b292`：2581 PASS / 0 FAIL · 41 例 · EXIT=0），本报告不重复。

## 范围 / 不测

- 只做派单 6 项；不改实现文件（本报告是唯一新增）。
- 不测：真 app 窗口的收养与 `ensure`/`close` 的 UI 可见效果（arch R1 ③ 已划 `[SKIP]` → 人工验收）；全量用例；真 pi 会话行为。

## 环境与命令

- 全部 app 面用**自造桩**（`hc` / `herdr-app` 均非仓库夹具），真实 unix socket 落在私有 `XDG_RUNTIME_DIR`；AC1 用**私有 herdr session**（`XDG_CONFIG_HOME` 独立 + 独立 server）。
- 真 `hc` 只跑一次子集往返：私有 `XDG_RUNTIME_DIR` + `XDG_STATE_HOME` + `HC_SESSION=nao-t4-qa-real`（`/tmp`），跑完 `kill` → `rm` → `hc server stop` → 删目录。
- 证据脚本与日志：`/tmp/qa562/`（临时）；关键行号见下。

## 结果（逐项）

### ① AC7 静态闸 —— 初核 CONDITIONAL（P2）→ **整改后通过**（复验见 §⑦）

- 现判据 `tests/t4/lib.sh:600 t4_scan_app_bare_hc`：真件基线 **0 命中（绿）**；区间首插 `hc ls` ⇒ **红且行号正确 `1611:hc ls`**；`_term_app_spawn` 内改 `out="$(hc run …)"` ⇒ **红 `2003:…`**。注入向的正控成立。
- **漏检三形（均实测绿 ⇒ 判据失效）**：`command hc ls`（`1611` 注入，0 命中）；`HC_SOCKET=/tmp/x hc ls`（env 前缀，0 命中）；**整删/改名 `_term_app_exec` 定义**（0 命中 —— 函数体内的 `command hc` 因「前置 env 赋值 + `command` 前缀」本就不匹配正则，删了入口只剩「无命中」）。
- 已验证的修法（候选实现在 `/tmp/qa562/ac7/scan2.sh` 跑过 7 份样本）：正则加 `([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(command[[:space:]]+)?` + 断言 `grep -cE '^_term_app_exec\(\) \{' == 1`。基线仍绿（唯一命中 = 入口体内 `nao-fleet.sh:1630`，被 allow-range 放过），`command hc` / env 前缀 / 删入口 / 改名 全部转红。
- 影响：不是活缺陷（当前 app 臂 0 处裸调），是**回潮检测**变弱；P2。建议在 #169 内补（改动仅 `tests/t4/lib.sh` + `cases/44` 一条正控）。
- **整改复验（P2 关闭）**：`lib.sh` 前缀组已扩为「env 赋值 | `command` | `exec` | `env` | `nohup` | `time`」并加 `^_term_app_exec\(\) \{` 唯一性断言，`cases/44` 补 A/B/C/D 四形态正控。四条变异**旧绿新红**均已验（§⑦）。

### ② AC8 契约缺失 —— 主判据通过；「仅缺 labels」P3 **已整改为 unknown + warn**（复验见 §⑦）

- `doc value=null` ⇒ `ensure` **rc=1**、报「布局文档不可用…不按「空布局」继续」、**`hc run` 调用 0 次**。
- `doc version=9` ⇒ **rc=1**、报「版本不支持放置契约（不降级为「写标签即成功」）」、`hc run` **0 次**。
- `get` 无 `status`（live + labels 在）⇒ `status` 单列「集成缺失 ⇒ 不可投递」+ 投递判定 `不可投递`，**不判 idle、不判在线**。
- `get` 无 `labels`（status 仍 idle）⇒ **判「✓ 在线 / 可投递」，无任何告警**（P3）。理由与残余风险：身份判据 = name + `status.app/state`，labels 只服务放置；真 `hc` 恒给 `"labels":{}`（实测），故「键缺失」确属契约漂移，但单缺 labels 不构成「不支持的 app 版本」。残余风险：同名未放置终端会让 `close` 因同名多命中而拒（不猜），需人工 `hc rm`。若要严格化：live 且键缺失时 warn + 判 unknown；若判「可接受」则在 PRD AC8 注明 labels 非必需。**需 PM/arch 用 PRD 口径裁定**。

### ③ 四条硬护栏（读码 + 桩/真 `hc` 双向证据）

- `--no-parent`：`nao-fleet.sh:2003`（唯一 spawn 调用）；桩记录 `run --bg --no-parent --keep` **1/1**；真 `hc get` 回读 **`"parent":null`**。
- 唯一入口：`hc` 实际执行点仅 `nao-fleet.sh:1630`（`_term_app_exec` 内）；桩记录 11 次调用 **`HC_SOCKET == HC_TERMINAL_SOCKET`，不匹配 0 条**。
- 失败判据读 JSON `error`：`_term_app_payload_ok`（`:1636`）在 12 个消费点全用；桩返回 **rc=0 + `{"error":…}`** ⇒ 判「hc run 失败」并计失败（不因 rc=0 当成功）。
- 放置读 `doc.get herdr-app`：app 区间内 `where` **只出现在注释**；桩令 `run`/`ls`/`get` 全带正确 `where="rd-fe / 1"` 而 doc 不含该终端 ⇒ **「放置验证失败…回滚（kill → rm）」**，调用序列 = run → connect → **kill t2 → rm t2**。

### ④ AC3b —— 通过

- 桩 `herdr-app status` 空输出 + rc=2 ⇒ `ensure` **rc=3**、**总输出恰 1 行**（「desktop app 未在运行…打开后重试」）、`hc` 调用日志**为空（0 次 `hc run`）**，即未先起终端。
- 真 CLI 实测：窗口未开时 `herdr-app status` = stdout 空 + **rc=2**（`Connection refused` 走 stderr）⇒ 闸门所依据的 rc 判据与真实契约一致。假想态（rc=0 但空输出）不属真实契约，且后续 doc 闸仍会 fail loud（不会静默）。

### ⑤ AC1 零回归抽查 —— 通过（8/8 diff 空）

- 两树 `v0.29.1` vs `d6fa0ab`，`NAO_TERMINAL` 未设 / `=herdr` 两路 × `status`、`status -v`、`check`、`check -v` 四命令：**8 组 diff 全 EMPTY**（私有 session；路径/session 名归一后 `check -v` 亦空）。另在真实 pane env 下复跑 `check`/`status`（含 `close`/`cleanup` 抽检）亦 EMPTY。
- 附注（P3）：`check` 的 herdr 行仍写「唯一后端」（`nao-fleet.sh:3691`/`:5261`），已有第二后端 ⇒ 文案陈旧；因 AC1 逐字口径而被锁住，建议后续批次改 AC1 允许面并同步文案。

### ⑥ 隔离纪律 —— 通过（含一次自伤与清理）

- 真 `hc` 子集往返全程私有 core；清理后 `hc ls`（默认 core）**前后逐字相同**、私有 session 进程/socket 0 残留、`/tmp/qa562` 内 0 socket。
- 自伤披露：AC1 抽检 `ensure <role>` 时继承了当前 pane 的 `HERDR_*`，向真实 session 起了 2 个游离 workspace（`wF`/`wG`，各 1 个 shell pane，无 pi 会话）。已 `workspace close wF wG`，复核 pane list 无残留；`v0.29.1` 同形行为，非本批回归。教训写入下节。

## ⑦ 整改后复验（对象 `685b292`）

PM 裁定三条整改（AC7 闸收窄 · 缺 labels 判 unknown · 白名单改显式文件名）落地后复验。**只跑三条用例 + 码审，不跑全量**（合并门禁由 PM 跑，用户加速令）。

- `check`：**rc=0**（`685b292` 清洁树；仅 `?? .pi/` 未跟踪，与本批无关）。
- `--case 44`：**PASS · 65 断言 / 0 FAIL**（58→65，新增的 7 条全在 AC7/AC8 整改面上）。
- `--case 06`：**PASS · 331 / 0 FAIL** · NOTE 2 均命中白名单 `06:static-contract`（文档侧静态替代，非放水）。
- `--case 28`：**PASS · 380 / 0 FAIL** · NOTE 0。
- **AC7 四变异实测**：A `hc schema >/dev/null` 旧红/新红 · B `command hc schema` **旧绿→新红** · C `HC_SOCKET=/tmp/x.sock hc ls` **旧绿→新红** · D 整删/改名 `_term_app_exec` **旧绿→新红**（报 `MISSING_ENTRY` 类断言，`cases/44` 正向断言 `grep -cE '^_term_app_exec\(\) \{' == 1` 同时变 0）。
- **AC8 缺 labels**：`fleet_name_parse` 命中后必发 **恰 1 行** warn「集成缺 labels：无法确认放置归属（……不判在线、不可投递）」，判定为 `unknown` + `integration-missing`，输出中**无 `✓`**；labels 齐全即无 warn（负控）。
- **白名单形态**：`cases/06` 已改为逐字文件名列表 `06-contract-guards.sh 28-naming-contract.sh 44-app-backend.sh`，新增文件必须**点名改断言**，不再靠数字漂移。
- **码审残余（P3-a，非本批回归）**：前缀组仍不覆盖 `if/then/else/elif/while/until/do/!` 与 `command -p` 关键字位；旧版同样漏（`if hc …` 在旧正则下也不红）⇒ **属前置既有盲区**，已并入 #170，不阻碍合并。

## 未覆盖与风险

- 全量 41 例未跑（加速令）；本报告只对 6 项与 case 44 负责。
- 真 app 窗口收养 / R-b（关窗期间起的终端是否补收养）仍未验，仍属人工验收项。
- QA 抽查纪律补充：`ensure`/`close` 一律在**私有 herdr session**（`XDG_CONFIG_HOME` + 独立 server）下跑；只读命令（`status`/`check`）可直接用真实 env。

## 派单风险判定：默认值探针白名单 2 → 3 是否构成判据放松

- **不构成放松**。规则本体是「块外禁用 unset/`env -u`/空串」，由 `t4_scan_nao_terminal_default_probe` 机械执行（`cases/06:1107` 断言块外 0 处仍为 0）；`cases/44:183-188` 的块**确实只验默认值**（未设 ⇒ 断言 `NAO_TERMINAL=herdr` 子串），用途与 `cases/06`、`cases/28` 同族，属「验默认值」的合法第四例。
- **但白名单机制偏弱（P3，建议加固）**：`cases/06:1113` 只钉「含 BEGIN 标记的文件数 = 3」，不钉文件名；任何人新增文件 + 把数字 +1 即可通过，而标记块内**内容不受任何约束**（`lib.sh:660-680` 是整块豁免）。建议改显式文件名允许列表，并（可选）静态断言块内出现 `herdr` 期望子串，使「加白名单」变成必须点名的评审动作。
  - **整改已采纳（PM 裁定 3）**：`685b292` 起改为显式文件名断言（§⑦），本 P3 关闭。
- RD 的替代方案（不写 marker、改显式 env 面）会丢掉「未设 ⇒ herdr」这条唯一默认值证据，**不建议采纳**。

## 建议（已全部处置）

1. ~~**AC7（P2）**：在 #169 内补 ① 正则扩展 ② 入口唯一性断言~~ → **已完成**（`685b292`，复验见 §⑦）。
2. ~~AC8「仅缺 labels」：PM 二选一~~ → **PM 裁定：判 unknown + 恰 1 行 warn，不判在线/不可投递**，已实现并配负控。
3. 文案「唯一后端」（`check` 输出）、`ensure` 全败仍 rc=0（`v0.29.1` 同形）、AC7 关键字位盲区 → **PM 接受为 follow-up #170**，不阻塞本批、不在本批夹带。
4. `ensure`/`close` 抽到私有 core 时**同时迭代隔离 `HERDR_*`**（本轮 AC1 自伤教训，非回归）。

- 修订：2026-11-24 初版（复核 6 项 + 探针白名单判定）· 2026-11-24 复验（`685b292` 整改确认，结论由 CONDITIONAL 转 `done(full)`，P2 关闭 · P3 四条全部归口）
