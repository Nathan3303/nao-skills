# QA 目标复核报告 · herdr desktop app 第二后端（T562 / #168）

- 状态：定稿 · 更新：2026-11-24 · Owner：qa
- 指针：对象 = 分支 `feat/168-app-backend` @ `d6fa0ab`（PR #169 Draft）· 判据单源 = PRD `docs/prds/2026-11-24-herdr-app-backend.md`（AC1–AC10 + AC3b + §六之二）· ADR `docs/adr/2026-11-24-herdr-app-backend.md` · arch `docs/reports/168-arch-review.md`

## TL;DR

- **结论：CONDITIONAL（AC7）** —— AC1 / AC3b / AC4 / 四条硬护栏 / AC8 主判据 均以独立桩复核通过；**AC7 静态闸存在单向漏检（P2）**，按派单判定口径「删掉唯一入口也必红」不成立。
- 另有 1 条 P3 与派单预期不符（AC8 的「仅缺 `labels`」子形态），3 条 P3 观察项（文案陈旧 / ensure 全败仍 rc=0 / 探针白名单加固），需 PM 裁定或转办。
- 门禁数字（本机复跑）：`bash .agents/scripts/nao-fleet.sh check` **rc=0**；`bash tests/t4/run.sh --case 44` **PASS · 58 断言 / 0 FAIL**（42.4s）。**全量未跑**（用户加速令）；RD 报的 41 例 / 2574 断言未复核。

## 范围 / 不测

- 只做派单 6 项；不改实现文件（本报告是唯一新增）。
- 不测：真 app 窗口的收养与 `ensure`/`close` 的 UI 可见效果（arch R1 ③ 已划 `[SKIP]` → 人工验收）；全量用例；真 pi 会话行为。

## 环境与命令

- 全部 app 面用**自造桩**（`hc` / `herdr-app` 均非仓库夹具），真实 unix socket 落在私有 `XDG_RUNTIME_DIR`；AC1 用**私有 herdr session**（`XDG_CONFIG_HOME` 独立 + 独立 server）。
- 真 `hc` 只跑一次子集往返：私有 `XDG_RUNTIME_DIR` + `XDG_STATE_HOME` + `HC_SESSION=nao-t4-qa-real`（`/tmp`），跑完 `kill` → `rm` → `hc server stop` → 删目录。
- 证据脚本与日志：`/tmp/qa562/`（临时）；关键行号见下。

## 结果（逐项）

### ① AC7 静态闸 —— **CONDITIONAL（P2）**

- 现判据 `tests/t4/lib.sh:600 t4_scan_app_bare_hc`：真件基线 **0 命中（绿）**；区间首插 `hc ls` ⇒ **红且行号正确 `1611:hc ls`**；`_term_app_spawn` 内改 `out="$(hc run …)"` ⇒ **红 `2003:…`**。注入向的正控成立。
- **漏检三形（均实测绿 ⇒ 判据失效）**：`command hc ls`（`1611` 注入，0 命中）；`HC_SOCKET=/tmp/x hc ls`（env 前缀，0 命中）；**整删/改名 `_term_app_exec` 定义**（0 命中 —— 函数体内的 `command hc` 因「前置 env 赋值 + `command` 前缀」本就不匹配正则，删了入口只剩「无命中」）。
- 已验证的修法（候选实现在 `/tmp/qa562/ac7/scan2.sh` 跑过 7 份样本）：正则加 `([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(command[[:space:]]+)?` + 断言 `grep -cE '^_term_app_exec\(\) \{' == 1`。基线仍绿（唯一命中 = 入口体内 `nao-fleet.sh:1630`，被 allow-range 放过），`command hc` / env 前缀 / 删入口 / 改名 全部转红。
- 影响：不是活缺陷（当前 app 臂 0 处裸调），是**回潮检测**变弱；P2。建议在 #169 内补（改动仅 `tests/t4/lib.sh` + `cases/44` 一条正控）。

### ② AC8 契约缺失 —— 主判据通过；「仅缺 labels」与派单预期不符（P3）

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

## 未覆盖与风险

- 全量 41 例未跑（加速令）；本报告只对 6 项与 case 44 负责。
- 真 app 窗口收养 / R-b（关窗期间起的终端是否补收养）仍未验，仍属人工验收项。
- QA 抽查纪律补充：`ensure`/`close` 一律在**私有 herdr session**（`XDG_CONFIG_HOME` + 独立 server）下跑；只读命令（`status`/`check`）可直接用真实 env。

## 派单风险判定：默认值探针白名单 2 → 3 是否构成判据放松

- **不构成放松**。规则本体是「块外禁用 unset/`env -u`/空串」，由 `t4_scan_nao_terminal_default_probe` 机械执行（`cases/06:1107` 断言块外 0 处仍为 0）；`cases/44:183-188` 的块**确实只验默认值**（未设 ⇒ 断言 `NAO_TERMINAL=herdr` 子串），用途与 `cases/06`、`cases/28` 同族，属「验默认值」的合法第四例。
- **但白名单机制偏弱（P3，建议加固）**：`cases/06:1113` 只钉「含 BEGIN 标记的文件数 = 3」，不钉文件名；任何人新增文件 + 把数字 +1 即可通过，而标记块内**内容不受任何约束**（`lib.sh:660-680` 是整块豁免）。建议改显式文件名允许列表，并（可选）静态断言块内出现 `herdr` 期望子串，使「加白名单」变成必须点名的评审动作。
- RD 的替代方案（不写 marker、改显式 env 面）会丢掉「未设 ⇒ herdr」这条唯一默认值证据，**不建议采纳**。

## 建议

1. **AC7（P2）**：在 #169 内补 ① 正则扩展 ② 入口唯一性断言 + 两向正控（`command hc` / 删入口），改后重跑 `--case 44` 与 `--case 06`。
2. AC8「仅缺 labels」：PM 二选一 —— 收紧为 unknown/不可投递，或在 PRD 注明 labels 非必需（本报告倾向：加 warn、不判在线）。
3. 文案「唯一后端」与 `ensure` 全败仍 rc=0（`v0.29.1` 同形）登记为后续批次观察项，不在本批夹带。

- 修订：2026-11-24 初版（复核 6 项 + 探针白名单判定）
