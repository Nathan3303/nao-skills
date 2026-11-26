# QA 批次验证 —— T573 session 记录治理 + T574 close 假成功

- 状态：已定稿 · 更新：2026-11-26 · Owner：qa
- 指针：Issue [#206](https://github.com/Nathan3303/nao-skills/issues/206) / [#207](https://github.com/Nathan3303/nao-skills/issues/207) · 被测链 `32d601b` → `c2621de` → `b5e0f96` → `86d5d8c` → `ccd6711`（`fix/574-close-done-reclaim`）

## TL;DR

- **T574 放行**；**T573 返修后放行**（初判不放行 → 两轮返修闭环：`86d5d8c` D1/D2/D7/D8-1、`ccd6711` D8-2）。
- 全量终判 49/49 例 PASS（2919 断言）；返修复验只跑目标用例：`--case 51` PASS=64 · `--case 52` PASS=35。
- 本 PR 只含测试侧新增（⑧b / ⑧ 与正控）+ 本报告，未碰功能代码。

## 范围 / 不测

- 测：T573 独立目录 + 分级保留 + `logs` 入口；T574 `live+done` 真回收 / 修前必红 / effect 判定；全量门禁 + 目标用例。
- 不测：真机 app 终端回收（本会话不在 app 终端内；替身 + 私有 core 覆盖）；`~/.pi/agent/sessions/` 既有 25 条（PRD 非范围）。

## 环境与命令（逐字）

```bash
export XDG_CONFIG_HOME=/tmp/xdgqa574b && mkdir -p $XDG_CONFIG_HOME/herdr/sessions/h1 && : > $XDG_CONFIG_HOME/herdr/sessions/h1/sock
E="env -u HC_TERMINAL_SOCKET -u HC_TERMINAL_ID -u HC_SCOPE -u NAO_TERMINAL HERDR_ENV=1 HERDR_SESSION=h1 HERDR_SOCKET_PATH=$XDG_CONFIG_HOME/herdr/sessions/h1/sock"
$E bash .agents/scripts/nao-fleet.sh check
$E npm test                                 # 全量：tip 原样一次 / 测试修正后终判一次（首轮）
$E bash tests/t4/run.sh --case 06 / 28 / 40 / 51 / 52 / 06     # 逐个单跑（一次只传一个 --case）
# 返修复验（ccd6711）：只跑 --case 51、--case 52
# /tmp 隔离造数探针（NAO_FLEET_META_DIR=/tmp）：无 spawn / 跨仓 done / 同名两代 / 在跑会话+幂等 / 定位阶段 ls 失败
```

- ⚠️ `--case A --case B` 原实现**静默只跑最后一个**（PM 的清单会假绿）⇒ 已改 fail loud（D6 / #210）。

## 结果（数字）

- `check`：rc=0 · `check: OK · roles=7 · files=68`
- 全量终判（首轮，tip `c2621de`）：`npm test` rc=0 · **49/49 例 PASS** · 断言 PASS=2919 / FAIL=0 · SKIP=0 · DEGRADE=0 · NOTE=17（全白名单）
- 全量首跑（未修测试）：rc=1 · 48/49 · FAIL=1 = case 28 `C3⑤`（D5）
- 返修复验（tip `ccd6711`，目标用例）：`--case 52` **PASS=35 / FAIL=0**（3 条原红全绿 + 正控 3 条 PASS）· `--case 51` **PASS=64 / FAIL=0**（含新增 ⑧b）
- 独立探针（返修后）：无 spawn / 跨仓 done / 同名两代（done 的 task=`-`，只靠代次窗口）三者均 7 天保留+点名；在跑会话点名落 state 目录且连跑两次不重复；定位阶段 `ls` 失败 ⇒ rc=1 + 「不可判定」+ 零成功行 + 终端保留

## 缺陷

- **D1（P1 · 已修 `86d5d8c`）分级 fail-open**：原按名字全仓匹配 done/force ⇒ 上一代崩溃记录被后续同名 `done` 判正常（24h 删、不点名）；跨仓同样生效。修法 = 本仓台账 + 代次窗口 + task 比对，无 spawn ⇒ 判不出 ⇒ 异常。用例 51 ⑦⑧ + 本次新增 ⑧b。
- **D2（P2 · 已修 `86d5d8c`）异常点名污染业务仓**：原写记录 cwd 的 `docs/tasks-state.md`（每个在跑会话每天一行）⇒ 改落 `<state>/sessions/--<编码cwd>--/.retention.log`，按记录路径去重。用例 51 ④⑤。
- **D8（P2 · 已修 `86d5d8c`+`ccd6711`）effect 判定 fail-open**：`kill→rm` 后及**定位阶段**的 `hc ls` 失败曾被当作「已消失/无同名」⇒ 打印「未发现 app 终端（幂等成功）」。修法 = 复核前校验 payload/rc；`find_by_name` 三态（读到/无同名 0 · 读不到 2），`get` 失败零命中同判 2；正控保留「读到且无同名 ⇒ 仍报未发现」。用例 52 ⑦⑧。
- **D3/D4/D5/D6（测试侧 · 已修 `b5e0f96`）**：case 40 S8 未净化 HOME（真实 state 污染）/ README 例数 43→49 / case 28 静态锚未随 `_term_app_name` 更新 / `--case` 重复丢参。
- **D7（P3 · 已修 `86d5d8c`）** `logs` 摘要与点名行时间显式 `Z`。**D9（P3 · 观察）** `<仓>/.ledger` 与 `.retention.log` 只增不减，量小，建议到期接受。

## 独立核验（PM 指定两点）

1. **`functions.txt` total = 232 一致**：清单 232 行 = 头 `total:` = 13 模块顶层函数并集（`comm` 三向 diff：漏登记 0 / 孤儿 0 / 重名 0）。注：T573 实际 **+31**（`sessions.sh` 30 + `_need_logs` 1），不是 +30。
2. **case 06 `files=68` 一致**：`find .agents -type f ! -path '*/.nao-obsolete/*'` = 68；`git ls-tree` 67 → 68 → 68。新 skill 落盘后需 69（合并 order 见下）。
3. 另核：`--session-dir` 只在 `spawn_one` 构造一次（`exec pi --name` 全仓 1 处），同一串由 `term_spawn` 分派给 `hc run … bash -lc "$inner"` 与 `pane run "$inner"` —— 两后端共用。
4. 另核：`get_order=real` 默认关，全仓仅 `cases/52` 开启；**建议下一批设为夹具默认**（见下）。

## 键序盲区（供下一批专项 Issue）

一句话：真问题不是「漏了 done」，而是**整套后端 JSON 抽取都是位置相关的扁平匹配**（首匹配 `_term_app_field` / 末匹配 greedy sed / herdr `_term_json_str` / `logs` 摘要）—— `name` 只是被真机咬到的第一颗牙。

同类位置依赖（5 条）：

1. `term-app.sh:263` `cwd` 取首个同名键 —— 顶层 cwd 先于 `foreground.cwd` 仅因字母序（另有 `_term_app_fg_cwd` 单列，勿混语义）。
2. `term-app.sh:221` argv 兜底 greedy 取**最后**一个 argv（今日恰为 `foreground.argv`）；foreground 之后再出现 argv 即回落错名。
3. `term-app.sh:96` `term_state` 取**最后**一个 `"state":"live|finished"`；`status.state` 一旦取这两个值即被覆盖。
4. `term-herdr.sh:90/96` `_term_json_str/_raw` 取**最后**同名键；`_term_json_objs` 按 `},{` 切对象（假定嵌套内无该序列）。
5. `sessions.sh:400+` + `_fleet_json_field` —— `logs`/元数据依赖 Pi jsonl 键序与缩进行（`"type":"text","text":` / `"type":"session"`）；真记录已验可读，仍属隐式契约。

建议：① 夹具 `get_order=real` 设为默认（legacy 留旋钮）⇒ 现有 app 用例自动咬同类回归；② 「剔嵌套块再取键」抽通用 helper 替换 cwd/argv/state；③ 可选用 `node -e` 解析（仓内已有 node）；附：`_term_app_name` 的 sed 仍假定 labels/foreground 块内无 `}`（取 name 不受影响，同类脆点）。

## 未覆盖与风险

- 「目录不可建 ⇒ fail loud」只做单元级验证（`fleet_sessions_prepare` rc=1 + `spawn_one` 的 die 在 `term_spawn` 之前），**无用例**。
- 真机 app `live+done` 回收未复跑；`--task` 过滤在返修后未单测（改动只碰 spawn 归属，风险低）；长期空闲仍存活的会话（>7 天无写入）会被删记录（无进程存活判据，设计取舍）。

## 发布建议

- **T574：可合并**（AC1 effect / AC2 修前必红 / AC3 忙闲语义 / AC4 `--force` / AC5 文档 全绿）。
- **T573：返修后放行**（AC①独立目录 / ②分级 fail-closed / ③`logs` 入口 / ④用例与文档 全绿；D9 观察）。
- 合并顺序：573 → 574 → 本 PR；之后 **#211(skill) 需 rebase 到新 main 并把 `cases/06` 改 68→69**（那时实际才 69；现在改会立刻红）。

- 修订：2026-11-26 首版 · 2026-11-26 返修闭环（D1/D2/D7/D8 结案 + 键序清单独立成段）
