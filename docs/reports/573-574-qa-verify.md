# QA 批次验证 —— T573 session 记录治理 + T574 close 假成功

- 状态：待确认 · 更新：2026-11-26 · Owner：qa
- 指针：Issue [#206](https://github.com/Nathan3303/nao-skills/issues/206) / [#207](https://github.com/Nathan3303/nao-skills/issues/207) · 被测 tip `c2621de`（`fix/574-close-done-reclaim`，含 `32d601b`）

## TL;DR

- **T574 放行**：代码面无缺陷（效果判据、修前必红、既有语义三项全绿）；门禁曾红是**测试锚未同步**（D5，本 PR 修）。
- **T573 不放行**：分级判据 1×P1（D1：异常记录被后续同名 `done` 判成正常 ⇒ 24h 删、不点名）+ 1×P2（D2：仍**在跑**的会话每天被当异常点名，写进仓内 `docs/tasks-state.md`）。
- 全量终判 49/49 PASS（2919 断言），`check` rc=0 `files=68`；本 PR 只含测试侧修正，未碰功能代码。

## 范围 / 不测

- 测：T573 独立目录 + 分级保留 + `logs` 入口；T574 `live+done` 真回收 / 修前必红 / 忙闲语义回归；全量门禁 + 目标用例。
- 不测：真机 app 终端回收（本会话不在 app 终端内；以替身 + 私有 core 覆盖，PM 真机证据作补充）；`~/.pi/agent/sessions/` 既有 25 条（PRD 非范围）。

## 环境与命令（逐字）

```bash
export XDG_CONFIG_HOME=/tmp/xdgqa574 && mkdir -p $XDG_CONFIG_HOME/herdr/sessions/h1 && : > $XDG_CONFIG_HOME/herdr/sessions/h1/sock
E="env -u HC_TERMINAL_SOCKET -u HC_TERMINAL_ID -u HC_SCOPE -u NAO_TERMINAL HERDR_ENV=1 HERDR_SESSION=h1 HERDR_SOCKET_PATH=$XDG_CONFIG_HOME/herdr/sessions/h1/sock"
$E bash .agents/scripts/nao-fleet.sh check
$E npm test                                   # 全量：修测试前一次 / 修后终判一次
$E bash tests/t4/run.sh --case 06             # 06 · 28 · 40 · 51 · 52 各单跑一次
# /tmp 隔离造数探针（NAO_FLEET_META_DIR 指 /tmp）：分级 24h/7 天、跨代/跨仓 done、在跑会话点名、幂等
```

- ⚠️ `--case A --case B` 原实现**静默只跑最后一个**（PM 给的 `--case 06 --case 44 …` 原样执行只会跑 41）。本 PR 已改成 fail loud（rc=1 + 点名），多例请分次跑。

## 结果（数字）

- `check`：rc=0 · `check: OK · roles=7 · files=68` · 生效后端 herdr
- 全量终判（含本 PR 测试修正）：`npm test` rc=0 · **49/49 例 PASS** · 断言 PASS=2919 / FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=17（全白名单）
- 全量首跑（tip 原样、未修测试）：rc=1 · 48/49 · PASS=2918 · **FAIL=1** = case 28 `C3⑤ 身份还原顺序`（D5）
- 单跑：06 PASS（360 断言）· 28 PASS（101）· 40 PASS（53）· 51 PASS（52）· 52 PASS（22）；13/15/37/38/41/44/45 在全量内 PASS

## 缺陷

- **D1（P1 · T573 功能）分级判据 fail-open**：`_fleet_session_outcome_rows` 按**名字**匹配 done/force，不含代次、仓、task ⇒ 上一代崩溃记录被后续同名 `done` 判「正常」⇒ 24h 删除且不点名（与文档「判不出 = 异常」相反）。复现：同名 `qa` 两条记录（3 天前崩溃无 close / 6 小时前正常 close）⇒ purge 删掉 3 天前那条、`tasks-state.md` 点名 0 行；跨仓同理（repo2 的 `done` 让 repo1 记录升级）。状态：Open。
- **D2（P2 · T573 功能）异常点名不区分「仍在跑」**：只需无 done 即点名，与 1h 忙闲闸只保护删除无关 ⇒ 每个在跑会话每天往**记录 cwd 的跟踪文件**写一行。现场：本仓 `docs/tasks-state.md` 在真机 `ensure` 后多出 `- [session-retention] … qa …`（本 PR 已回滚该行）。状态：Open。
- **D3（P2 · 测试隔离）case 40 S8 环境未净化**：手写 `env` 未带 lab `HOME` ⇒ ensure 把 session 台账/`--session-dir` 落到跑测试者真实 `~/.local/state/nao-fleet/sessions/`（实测造出 `--tmp-nao-t4.*--` 垃圾目录）。已修（改走 `be_clean_env`），污染已清。状态：Fixed(this PR)。
- **D4（P3 · 文档）`tests/README.md` 例数 43 → 实为 49**（两处）。已修。状态：Fixed(this PR)。
- **D5（P2 · 测试锚）574 改 `_term_app_identity` 后 case 28 静态锚失效**：锚仍 grep `_term_app_field "$g" name` ⇒ 全量红（这正是 RD 不跑套件、QA 把关的意义）。已改锚为 `_term_app_name "$g"`（顺序契约不变），case 28 PASS。状态：Fixed(this PR)。
- **D6（P3 · 易错）`--case` 重复静默丢参** ⇒ 假绿。已加 fail loud 守卫。状态：Fixed(this PR)。
- **D7（P3 · UX）`logs` 摘要时间为 UTC 且无标注**（本机 +8 看起来像 8 小时前）。状态：Open(建议)。
- **D8（P3 · 健壮性）`_term_app_reclaim` 的 rm 重试/effect 复核均以 `ls --all | grep` 判消失**：`ls` 本身失败（错误 payload）会被读成「已消失」⇒ 可能假成功。建议 effect 复核前加 `_term_app_payload_ok`。状态：Open(建议)。
- **D9（P3 · 设计残留）`<仓>/.ledger` 只增不减**，记录删后空目录/台账行长期保留；量小，建议到期接受。状态：Open(建议)。

## 独立核验（PM 指定两点）

1. **`functions.txt` total = 232 一致**：清单 232 行 = 头 `total:` = 13 个模块顶层函数并集（自写 `comm` 三向 diff：漏登记 0 / 孤儿 0 / 重名 0；分模块计数和恰 232，`sessions.sh` 30）。注：T573 实际 **+31**（`sessions.sh` 30 + `nao-fleet.sh::_need_logs` 1），不是 +30；231+1=232 与清单自洽。
2. **case 06 `files=68` 一致**：`find .agents -type f ! -path '*/.nao-obsolete/*' | wc -l` = 68；`git ls-tree` 67（`32d601b^`）→ 68（`32d601b`）→ 68（`c2621de`）；与 golden 行同步。
3. 另核：`--session-dir` 只在 `spawn_one` 构造一次（`exec pi --name` 全仓 1 处），实体串由 `term_spawn` 分派给 `_term_app_spawn`（`hc run … bash -lc "$inner"`）与 `_term_herdr_spawn`（`pane run "$inner"`）—— 两后端共用同一串，成立。
4. 另核：`hc-double` 的 `get_order=real` **默认关**（无状态文件即 legacy 键序），全仓仅 `cases/52` 两处开启 —— 符合 PM 的判断。

## 键序盲区结论（PM 要的一句）

一句话：**真问题不是「漏了 done」，而是整套后端 JSON 抽取都是位置相关的扁平匹配**（首匹配 `_term_app_field`、末匹配的 greedy `sed`、herdr `_term_json_str`、`logs` 摘要），`name` 只是被真机咬到的第一颗牙。同类点仍「靠字母序侥幸正确」：`term-app.sh:263` 的 `cwd`（顶层 vs `foreground.cwd`）、`term-app.sh:221` argv 兜底（取**最后**一个 argv）、`term-app.sh:96` `term_state`（取**最后** `live|finished`）、`term-herdr.sh:90` `_term_json_str`（末匹配）+ `:96` 按 `},{` 切对象、`sessions.sh:400+` 依赖 Pi jsonl 键序（真记录已验证可读）。建议：① 夹具把 `get_order=real` 设为**默认**（legacy 留旋钮）⇒ 现有 app 用例自动咬同类回归；② 把「剔嵌套块再取键」抽成通用 helper，逐个替换 cwd/argv/state；③ 可选用 `node -e` 解析（仓内已有 node 依赖）彻底去掉键序假设。附：`_term_app_name` 的 `sed` 仍假定 `labels`/`foreground` 块内无 `}`（取 name 不受影响，但属同类脆点）。

## 未覆盖与风险

- 「目录不可建 ⇒ fail loud」只做单元级验证（`fleet_sessions_prepare` rc=1 + `spawn_one` 的 die 在 `term_spawn` 之前），**无用例**（需不可写根 + 真 ensure 场）。
- 真机 app `live+done` 回收未复跑（替身 + 私有 core 覆盖）；长期空闲但仍存活的会话（>7 天无写入）会被删记录（无进程存活判据）—— 设计取舍。

## 发布建议

- **T574：可合并**（代码 PASS；本 PR 补齐门禁锚）。
- **T573：不放行**。D1 修法：outcome 匹配限定「同仓台账 + 该代 spawn 之后、下一同名 spawn 之前」，`done` 带 task 时按 task 比对；补 2 条用例（跨代 / 跨仓 done 不得升级）。D2：点名只在 mtime 超出写窗口（或仅在删除前）才写，且优先写 state 目录而非仓内跟踪文件。
- 本 PR 只含测试侧修正（D3–D6）+ 本报告；未碰功能代码、未改 `docs/tasks-state.md`。

- 修订：2026-11-26 首版
