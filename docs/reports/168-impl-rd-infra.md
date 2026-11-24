# #168 实现报告：herdr desktop app 第二后端（`NAO_TERMINAL=app`）

- 状态：待验收 · 更新：2026-11-24 · Owner：rd-infra
- 指针：Issue [#168](https://github.com/Nathan3303/nao-skills/issues/168) · 任务 T562 · PRD `docs/prds/2026-11-24-herdr-app-backend.md` · ADR `docs/adr/2026-11-24-herdr-app-backend.md` · 评审 `docs/reports/168-arch-review.md` · 分支 `feat/168-app-backend`

## TL;DR

- **默认后端不变**：`NAO_TERMINAL` 未设/`herdr` ⇒ TUI 面（AC1 逐字不变：文案、四命令、错误口径）；`app` = **第二后端**，两套程序**不共享 agent**。
- **四个硬护栏全部落地并自证**：① `hc run … --no-parent`（真 hc 实测 `parent:null`）；② 连接只经 `_term_app_exec` 注入 `HC_SOCKET=$HC_TERMINAL_SOCKET`；③ 失败判据 = JSON `error` 字段（不看 rc）；④ 放置验证读 `doc.get herdr-app` 的 `version ≥ 10` 结构（**不用** `hc ls` 的 `where`）。
- **门面同形**：app 臂产出与 herdr **同一 12 列快照** ⇒ status/ensure/close 的业务层零改动（只在措辞层分后端）。
- **证据**：用例 44（51 条断言；含**真 `hc` 私有 core** 子集往返 6 条）+ 静态闸（app 臂裸调 `hc` = 0，两向正控）。
- 门禁与 AC1 两树 diff 见 §六。

## 一、实现面（M1–M7 → AC）

| M | 落点（`nao-fleet.sh`） | 对应 AC | 证据（用例 44） |
|---|---|---|---|
| M1 区间 + 门面 app 臂 | `# >>> term-impl-app`（`_term_app_*`）· `term_backend` 允许 `app` · 各门面分派（`term_require/term_snapshot/term_liveness/term_argv/term_spawn/term_deliver/term_reclaim/term_cleanup/term_place_prime/term_ws_label_rows`）· `cmd_check` app 前提节 | AC1/AC2 | ⑩（herdr 逐字）、②（app 闸门） |
| M2 身份闸门 | `_term_app_require`：三件套齐 + socket 在 `$XDG_RUNTIME_DIR/herdr-core/` 下且确为 socket ⇒ 否则 `exit 3` + 一行指路 | AC3 | ②（5 条） |
| M3 放置 | `_term_app_place_prime`（doc `folder` 权威 + 终端 `cwd` 兜底 → `place_key_label` 让号）· `_term_app_spawn`（写 `herdr.space`/`herdr.tab` → `_term_app_verify_place` 读回 → 不成则 `kill`→`rm` 回滚） | AC4/AC5 | ④（7 条）、⑤（4 条） |
| M4 就绪/忙闲 | `_term_app_wait_ready`（`status.app=pi ∧ state=idle`，50×100ms）· `_term_app_liveness`（`working/blocked` 忙；`idle/done` 可投递；缺失 `unknown`）；**不用** `state_change_seq`（快照 `seq` 位恒 `-`） | AC6 | ⑥（3 条）、⑧（2 条） |
| M5 回收 | `_term_app_reclaim`（`kill` → `rm` 固定顺序 · effect 复核 `ls --all` · 拒回收自身）· `_term_app_cleanup`（只清带放置标签的终端，core 不动） | AC7/BR4 | ⑦（4 条）、⑨（3 条） |
| M6 文档 | 由 PM 提交（`1387c76`：README 前置环境两形态 · INSTALL 新节 · AGENTS 端前提行；均写死「两套程序不共享 agent」） | AC9 | —（PM 面） |
| M7 用例 | `tests/t4/cases/44-app-backend.sh`（11 组断言）· `fixtures/hc-double/{hc,herdr-app}` · `lib-backend.sh::be_app_*` · `lib.sh::t4_scan_app_bare_hc` | AC10 | 全例 |

**AC3b（ensure 前探窗口）**：`term_spawn_preflight` → `_term_app_spawn_preflight` 在**相位 1a 第一步**（任何终端创建之前）判 `herdr-app status`；不在跑 ⇒ `exit 3` + 指路。用例 44③ 断言「未创建任何终端、桩日志无 `hc run`」。

## 二、四条硬护栏：落地 + 自证

| 护栏 | 落地位置 | 自证 |
|---|---|---|
| ① `--no-parent` 必传 | `_term_app_spawn` 命令行固定带 | 真 hc：`get` 回读 `"parent":null`（⑪）；替身：`parent` 文件为空（④） |
| ② 连接只走 `HC_SOCKET=$HC_TERMINAL_SOCKET` | `_term_app_exec`（唯一入口） | 静态闸：区间内裸调 `hc` = 0 + 正控必红（①） |
| ③ 失败判据 = JSON `error` | `_term_app_payload_ok`（所有分支前置） | 回滚分支（⑤）、`send` 失败分支、`rm live` 真 hc `kind:live`（⑪） |
| ④ 放置读回用 doc 结构 | `_term_app_verify_place`（`S/T` 行的 `terminals` 集合含地址） | 命中（④）；`doc_hide` 造「未收养」⇒ 验证失败 + 回滚（⑤） |

### 契约缺失 fail loud（AC8）

| 缺失面 | 行为 | 证据（用例 44） |
|---|---|---|
| `doc.get` `value=null`（窗口未开 / 版本过旧） | `ensure` die：「app 布局文档不可用…不按「空布局」继续」 | ⑫（2 条） |
| `doc.version < 10` | `ensure` die：「version=… < 10：当前 desktop app 版本不支持放置契约」 | ⑫（2 条） |
| `status` / `labels` 字段缺失（契约未上报） | 不判在线、不退化成空闲：status 判「集成缺失 ⇒ 不可投递」 | ⑫（2 条） |

**由 AC8 用例抓到并修掉的自身缺陷**：`_term_app_liveness` 两处 `read` 写了 **13 个变量对 12 列**（多一个 `_`）
⇒ `sess` 位错读到 `argv_name`，`finished` 判定整列错位（真实后果：任何 app 终端都会被判「终端残留」）。
「缺 status ⇒ 集成缺失」这条用例正是它的反证 —— 若无该断言，错位会被「恰好也是非在线」掩盖。

## 三、app 语义 ↔ herdr 对表（同形快照）

12 列语义（app 臂）：`pane_id/terminal_id` = 终端地址（`tN`）；`agent_status` = `status.state`；
`seq` 恒 `-`（无 `state_change_seq` 等价物）；`session` 位 = **终端生命周期** `live|finished`；
`hook` = `reported:true`（状态由程序上报）⇒ `1`；`ws_id` = `labels.herdr.space`。

判活阶梯（`_term_app_liveness`）：`finished` ⇒ **终端残留**（不判在线；只残留时 verdict=`ghost`）→ `status` 缺 ⇒
`integration-missing` → 否则 `online`。忙闲：`working/blocked` ⇒ 拒（`--force` 放行）；`idle/done` ⇒ 放行；缺失 ⇒ 拒。
**注意**：`finished` 不参与同名歧义计数、不占 tab（否则一次退出后的残留会把重建永久阻塞，见 §四-2）。

## 四、与 PRD / 派单的偏差（如实四条）

1. **space 发现顺序**：派单 M3 写「读该仓现有终端 label 取 space id」；实测 label **只存 space id**，`folder` 只在 `doc`
   ⇒ 实现为「doc `folder` 权威 → doc 缺该 space 时才用终端 `cwd` 兜底」，效果等价且更准（子目录起的终端不会伪造 space 归属）。
2. **`finished` 残留处理**（新增，PRD 未写）：`--keep` 下 pi 退出后终端仍存在（`state=finished`）。
   若不处理，同一 tab 会被永久占用（重建判「tab 已有终端」）。实现：重建前 `kill`→`rm` 该残留并打一行日志
   （`finished` = 无 agent 在跑，回收不杀会话）；**不采用**「拒绝并让人工 close」（会破坏幂等重建）。
3. **`session-start` 在 app 下 `exit 2`**：「起 server」= 操作桌面版 core（属用户窗口）⇒ 明确拒绝并指路，不静默成功。
4. **真 `hc` 形状订正**（arch 报告未列全）：`hc get` **没有** `foreground` 块 —— 前台程序在顶层 `"agent"`、命令在顶层
   `"argv"`。⇒ 助手回落取值；并修掉 `_term_app_field` 的**贪婪匹配**缺陷（`sed '.*"name":"…"'` 会取到最后一次
   `foreground.name` = `pi`，把会话名判成 `pi`）—— 改为「首个同名键」。

## 五、AC1 零回归（同夹具两树 diff）

- 方法：`git show acc451e:.agents/scripts/nao-fleet.sh` 取 v0.29.0 脚本，与分支脚本**同一 `herdr-double` 夹具、
  同一私有 XDG 根**跑 `ensure rd-fe` → `status` → `close rd-fe --force` → `ensure qa` → `cleanup --session … --force`，
  输出按「实验根路径 / 缓存根 / 会话名 / 时延 / pid」归一后 `diff`（脚本：`/tmp/ac1-two-tree.sh`）。
- 结果：**`AC1-DIFF: EMPTY`（逐字一致）**，日志 `/tmp/rd-168-ac1.log`。
- 配套证据：`check` 的「生效后端 NAO_TERMINAL=herdr（唯一后端…）」子串逐字断言（用例 44⑩）；herdr `status` 渲染由
  `cases/28` 的 herdr golden（md5）继续钉死（本批未改该 golden）。

## 六、门禁（数字取自落盘日志）

- `check`：rc=0（`check: OK · roles=7 · files=53`）· 日志 `/tmp/rd-168-check.log`。
- `--case 44`：**PASS · 65 条断言**（SKIP=1 真 `hc` 缺席时的分支；本机有 `hc` ⇒ ⑪ 6 条已跑）· 日志 `/tmp/t562d-44.log`。
- `--case 06`：PASS · 331 条断言（NOTE=2 均在白名单）· 日志 `/tmp/t562d-06.log`。
- `npm test` 全量：rc=0 · 全 44 例 PASS · SKIP=0 · DEGRADE=0 · NOTE=18（全白名单）· 日志 `/tmp/rd-168-full5.log`。
- **AC1 两树 diff**：`AC1-DIFF: EMPTY`（显式 `NAO_TERMINAL=herdr`）与 `AC1-UNSET-DIFF: EMPTY`（**未设**，验默认值），
  四命令 × 两路径逐字一致 · 日志 `/tmp/rd-168-ac1.log`、diff 文件 `/tmp/ac1-cache/ac1*.diff`。
- **两处既有闸的**加强**（不是放宽）**：
  ① `cases/06` 「exit 3 站点」改为按 **app 区间内/外** 二分（`APP=7` / `LEGACY=7` / `TOKEN=LEGACY+APP` / `STANDALONE=TOKEN`），
     并补 **app 轴负控 C**（app 区间内改 `cmd || exit 3` ⇒ 独占行 −1、app token 位不变）；顺带订正该组文案（判据一直是 token 位站点）。
  ② `cases/06`「默认值探针块白名单」**2 → 3**：新增 `cases/44` 的 marker 块（断言「`NAO_TERMINAL` 未设 ⇒ herdr」）。
     **维护约束**：该块若哪天改成非默认值断言，必须移出白名单（否则白名单退化成豁免）。marker 处已留注释。
  ③ `cases/14 ⑳` 的 `DEL_ALL=1` **一字未改**：`cases/44` 与 `lib-backend.sh::be_app_teardown` 的删除全部改走
     `lib.sh::_t4_rm_cache_dir`（唯一删除点），没给 14 加路径白名单。

## 七、`[SKIP]` 清单与理由
- **真实收养 / ensure-close 的 UI 效果**：`[SKIP]`。理由（arch R1 定论 ③）：私有 core 能测契约面（三件套、run/kill/rm、
  标签落库、doc version），但「标签被**真实 app 窗口**收养成可见 tab」只有真窗口能验，自动化会污染用户桌面。
  ⇒ 归人工验收（PM 真机复核一次；本批报告已写明「起 1 个、30 秒内 kill+rm」的纪律）。
- **真 `hc` 子集往返**：无 `hc` 的环境 `[SKIP]`（理由写明）；本机有 `hc` ⇒ 已跑（⑪ 6 条）。

## 八、遗留（三出口）

- **关闭**：无（M1–M7 全部落地）。
- **接受（含理由）**：`cleanup` 在 app 下的语义 = 「清掉本 core 内所有带放置标签的舰队终端（core 不动）」——
  与 herdr 的「停整个 session」不同，因为 core 属桌面版（停它 = 关用户窗口）。已写进用法头与本节。
- **转办（建议单开）**：`hc schema` 的**字段级**校验（arch 报告要求「必备方法/字段」）。当前只做「`hc schema` 可执行 +
  `doc.version ≥ 10`」；逐方法/字段探测（`run/get/ls/kill/rm/send` 是否存在）未做 —— 本批按最小可用不扩面。

## 九、QA 整改（一轮收口 · 加速档）

### 1（P2）AC7 静态闸单向漏检 —— 已加严（非放宽）
- **根因**：旧判据只认「语句位 `hc`」且**没有入口存在性断言** ⇒ `command hc ls` / `HC_SOCKET=x hc ls` 不命中，
  **整删或改名 `_term_app_exec`** 后「无命中 = 绿」。
- **修法**（`tests/t4/lib.sh::t4_scan_app_bare_hc`）：
  ① 正则加前置 `env` 赋值 / `command` / `exec` / `env` / `nohup` / `time` 前缀；
  ② 加结构断言 `grep -cE '^_term_app_exec\(\) \{' == 1`（缺失/重复 ⇒ 输出 `MISSING_ENTRY:`，必红）。
- **先红后绿**（`/tmp/ac7-redgreen.sh`，旧闸 = 首版实现，仅作对照）：

  | 变异样本 | 旧闸 | 新闸 | 新闸点名 |
  |---|---|---|---|
  | A 语句位 `hc schema` | RED | RED | `1611:hc schema >/dev/null` |
  | B `command hc schema` | **GREEN（漏）** | RED | `1611:command hc schema >/dev/null` |
  | C `HC_SOCKET=/tmp/x.sock hc ls` | **GREEN（漏）** | RED | `1611:HC_SOCKET=/tmp/x.sock hc ls >/dev/null` |
  | D 入口改名（删唯一入口） | **GREEN（漏）** | RED | `MISSING_ENTRY: … 定义数 = 0` |
  | 基线（未变异） | GREEN | GREEN | —— |

- `cases/44` ① 已补四条正控（A/B/C/D 各必须红）+「入口恰 1 处」正向断言。

### 2（AC8 子形态）只缺 `labels` ⇒ `unknown` + 一行 warn，不判在线
- 判据：快照 `ws_id` 为 `-`（有名字、无放置键）⇒ `verdict=unknown`（**不入在线、不可投递**），
  且仅当名字是**舰队形状**（`fleet_name_parse` = `OK…`）时打一行
  「集成缺 labels：无法确认放置归属（终端 `<name>`；不判在线、不可投递）」。
- **两项都缺**（无 `labels` 且无 `status`）⇒ 仍按 AC8 主形态判 `integration-missing`（更强的缺陷），
  不降级成 `unknown` —— 否则 `status` 的「集成缺失」证据行会被吞掉。
- **告警只一行**：`running()` 是布尔探针（可投递列），已改为 `2>/dev/null`；告警由证据面负责，
  否则同一名字被问两次会刷两条（实测复现后修）。
- 夹具两面：`bare_labels=1` ⇒ warn + 无 ✓；移除后 ⇒ **无该 warn** + ✓（负控）。实测
  「恰一行」/「0 行」见 `/tmp/dbg44.sh` 输出。

### 3（P3）`cases/06` 白名单改**显式文件名**
- 原「文件数 = 3」⇒ 现「文件清单 = `06-contract-guards.sh 28-naming-contract.sh 44-app-backend.sh`」，
  新增文件必须显式改断言，不再随计数漂移悄悄变长。
- 维护约束不变：若 `44` 的 marker 块改成「非默认值断言」，须移出白名单（marker 处有注释）。

### 4 本批不做（已登记 follow-up，未顺手改）
- `check` 仍印「唯一后端」：被 AC1 逐字锁死，需单独批次改允许面。
- `ensure` 全败仍 `rc=0`：v0.29.1 同形，非本批回归（AC4 只要求 fail loud + 回滚）。
- `hc schema` 字段级校验：当前只判可执行 + `doc.version ≥ 10`。
