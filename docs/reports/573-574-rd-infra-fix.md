# T573 返修 —— 分级 fail-open / 点名污染 / effect fail-open

- 状态：待验收 · 更新：2026-11-26 · Owner：rd-infra
- 指针：Issue [#206](https://github.com/Nathan3303/nao-skills/issues/206) · 返修输入 `docs/reports/573-574-qa-verify.md`（QA 不放行 T573）· 上游 PR [#210](https://github.com/Nathan3303/nao-skills/pull/210)（QA 测试侧修正，已 squash 进本分支）

## TL;DR

- **D1（P1）已修**：`done`/`force` 只认**本仓台账**且必须落在**该代窗口**内（本代 `spawn` 之后、下一同名 `spawn` 之前），带 `task` 的行按 task 逐字比对；`spawn` 缺失 ⇒ 判不出 ⇒ 异常（fail-closed）。
- **D2（P2）已修**：异常点名改落**记录所在 state 子目录** `<state>/sessions/--<编码 cwd>--/.retention.log`，不再写仓内 `docs/tasks-state.md`（真机 purge 后 `git status` 干净）。
- **D7 已修**：`logs` 摘要时间加 `Z` 后缀（`06:20Z`），明确 UTC。
- **D8 已修**：`_term_app_reclaim` 的 rm 重试与 effect 复核，`ls` 失败/错误 payload ⇒ **不判成功**（rc=1 + fail loud），不再把「读不到」当「已消失」。
- D9（`.ledger` 只增不减）不在本批，仍记观察。

## 改动面

| 文件 | 改动 |
| --- | --- |
| `.agents/scripts/fleet/lib/sessions.sh` | `_fleet_ledger_scan` 新增 `next` 模式 + outcome 上界/task 过滤；`_fleet_session_spawn_row` 去掉跨仓兜底；`_fleet_session_grade` 按代次窗口判；`_fleet_session_anomaly_note` 改写 state 目录；`logs` 时间加 `Z` |
| `.agents/scripts/fleet/lib/term-app.sh` | `_term_app_reclaim` 两处 `ls` 判据加 `payload_ok` + rc 检查，读不到 ⇒ 失败 |
| `docs/INSTALL.md` | 保留分级口径：点名落 state 目录、只认本仓台账 + 代次窗口 |
| `tests/t4/cases/51-fleet-session-store.sh` | ④/⑤ 断言改 `.retention.log` + 断言 `tasks-state.md` 零写入；新增 ⑦ 跨代、⑧ 跨仓、⑨⑩ 编号顺延 |
| `tests/t4/cases/52-close-live-done.sh` | 新增 ⑦ D8 守卫演练（注入 `kill` 后 `ls` 失败 ⇒ 不宣称成功）+ 同夹具正控 |
| `tests/t4/fixtures/hc-double/hc` | 新调参 `ls_fail_after_kill`（`kill` 后建 `ls_fail_now` ⇒ `ls` 返 error payload + rc=1） |

**修法口径（D1 一句话）**：把「同名 `done` 生效」收紧成「**本仓台账 + 该代 spawn 之后、下一同名 spawn 之前**」——上一代的崩溃记录不再被后一代的 `done` 升级成正常。

## 证据（先红后绿）

D1 两条新用例（`--case 51`，功能代码回退到返修前）：

```
[FAIL] ⑦ 同名旧代（崩溃无 close）仍在 —— 不被新代 done 升级（留 7 天）（文件不存在: …/2026-11-23T00-00-00-000Z_gen1.jsonl）
[FAIL] ⑦ 旧代被点名（判不出 = 异常）（未包含: 2026-11-23T00-00-00-000Z_gen1.jsonl）
[FAIL] ⑧ 他仓 done 不影响本仓分级 ⇒ 本仓记录仍留（7 天）（文件不存在: …/2026-11-23T02-00-00-000Z_xrepo.jsonl）
[FAIL] ⑧ 本仓记录被点名（不被他仓 done 升级成正常）（未包含: 2026-11-23T02-00-00-000Z_xrepo.jsonl）
```

修后：`--case 51` 全绿（含 ⑦⑧：旧代留 + 点名、新代按自身 `done` 删除、跨仓 `done` 不升级）。

D8（`--case 52`，`term-app.sh` 回退到返修前）：

```
[FAIL] ⑦ hc ls 读不到 ⇒ close 不判成功（rc≠0）（不应等于 0）
[FAIL] ⑦ fail loud：点名「回收结果不可判定」（不当已消失）（未包含: 不可判定）
[FAIL] ⑦ 不打印成功行（不假成功）（不应包含: 已回收 app 终端）
```

修后：`--case 52` 全绿（注入段 rc≠0 + 点名 + 无成功行；同夹具不注入 ⇒ 正常回收 = 正控）。

**D2 真机证据**（本仓真实 state 根、真实 `logs --purge`）：

```
[fleet] 会话记录清理：删除 0 条 · 保留 2 条（异常 2 条；范围 = nao-skills；策略 = 正常 24h / 异常 7 天）
[fleet]   · 异常点名落 state 目录：…/nao-fleet/sessions/<编码 仓路径>/.retention.log（不写仓内 docs/tasks-state.md）
$ git status --short docs/      # 只显示本次提交的 docs/INSTALL.md
（无 docs/tasks-state.md 变更；连跑第二次 `.retention.log` 行数 2 → 2 = 幂等）
```

> 说明：`ensure` 与 `logs --purge` 共用同一清理函数（`fleet_sessions_purge`），点名唯一调用点在 `_fleet_session_purge_one`；本次以真机 `logs --purge` 取证（本会话在 app 终端内，`ensure` 需要真 herdr pane，起新会话去测 purge 属高副作用）。

## 自查（单条命令，不替代 QA 全量）

- `check`：rc=0 · `check: OK · roles=7 · files=68` · 台账 0 条
- `--case 51` PASS · `--case 52` PASS · `--case 06` PASS · `--case 28` PASS · `--case 40` PASS · `--case 44/45/13/15/10` PASS
- `bash -n` 四个改动脚本通过；改动集内 `grep /home/nathan` 零命中（零机器特定值）

## 未覆盖与风险

- 「目录不可建 ⇒ fail loud」仍无用例（沿用 QA 上一轮结论）。
- D8 的**非破坏**分支（rm 尚未成功时 `ls` 失败 ⇒ 终端确实保留）没有独立场景：现有注入点在 `kill` 之后，`rm` 已达成，因此该段只能断言「不宣称成功」而不是「终端仍在」。
- D9 `.ledger` 只增不减：仍为设计残留，量小，建议到期接受。
