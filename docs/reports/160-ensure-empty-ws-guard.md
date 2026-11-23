# #160 P0 修复报告：ensure 不再把「只有用户自己 pane 的 workspace」判空并关掉

- 状态：待验收 · 更新：2026-11-23 · Owner：rd-infra
- 指针：Issue #160 · 任务 T558 · 上游缺陷现场 = v0.28.0（`ccd89e7`）· 分支 `fix/160-ensure-empty-ws-guard`

## TL;DR

- **缺陷**：`ensure` 的放置快照用 TAB 拼字段 → 无 label 的 pane 行被 `read` 折叠后整体左移，wsid 位读到 tab_id
  ⇒ 判成「空 workspace」⇒ `workspace close` ⇒ **连带杀掉用户自己的 pi 会话**（上游已连挂两次）。
- **修法**：字段分隔符改非空白 `US(\x1f)` + **单一构造器 `_term_place_pane_row` / 单一访问器 `_term_place_pane_fields`**
  （10 个消费点全部改走访问器 · 其中**真实行为差异 3 处**，其余 7 处为语义净化/防回潮，见「消费点：A 组 / B 组」）；
  `workspace close` 前加**破坏性护栏**（原始 `pane list --workspace` 复核 0 pane，冲突即不关 + fail loud）。
- **证据**：v0.28.0 脚本在同一场景下 `workspace close` ×1、用户 pane 被杀、ws 被重建（w1→w2）；
  修复后同场景 `workspace close` ×0、用户 pane 存活、ws 仍是 w1。回归用例 43（60 项断言，含 3 个变异副本自证）。
- **门禁**：`npm test` rc=0 · 2513 PASS / 0 FAIL（40 例）· `check` rc=0 · 全量 62s→本批新增单例 20.7s。
- **待办（PM）**：验收 + 与 T557（`d8e4d09`）一并发 v0.29.0（发布动作归 PM；本批未 bump 版本）。

## 根因（三对照，静态 + 合成 + 真件）

- `TAB` **属 IFS 空白类** ⇒ `IFS=$'\t' read -r a b c` 对空首字段**折叠**，不是赋值空串：
  `\t w1:p1 \t w1 \t w1:t1` ⇒ `a=w1:p1, b=w1, c=w1:t1`（整体左移一格）。
- 对照一（`awk -F'\t'`）：不折叠（空字段保留）—— 既有 `_term_herdr_place_set_tab` 因此没爆，但两套语义并存是隐患。
- 对照二（`IFS=$'\x1f'`）：不折叠（US 非空白）⇒ 本次采用。
- 对照三（`${line#*$'\t'}` 前缀切）：同样把空 label 行切错（`_term_herdr_place_set_pane/drop_pane` 原写法）。

## 修改面（`.agents/scripts/nao-fleet.sh`）

- 快照编码：`_TERM_PLACE_FS=$'\x1f'`（`nao-fleet.sh:927`）；`_term_place_pane_row`（唯一构造点）·
  `_term_place_pane_fields`（唯一解析点，输出 `_TP_LABEL/_TP_PANE/_TP_WS/_TP_TAB/_TP_CWD/_TP_FGCWD`）。
- 破坏性护栏：`_term_herdr_ws_pane_count_live`（`nao-fleet.sh:976`：原始 `pane list --workspace` 计 pane 数）·
  关前复核（`nao-fleet.sh:1348`：读不到 ⇒ 不关；实测非 0 ⇒ 不关 + 点名 wsid 与 pane 数）。
- 同族 TSV 归一：`_term_tsv_norm`（`nao-fleet.sh:435`）接入 `term_snapshot` 的 label/tid/cwd/fgcwd/wsid
  （空 ⇒ `-`，字段内 TAB/CR/LF ⇒ 空格），堵住 `_term_herdr_liveness` 那一族的左移/串列面。

## 消费点：A 组（真实行为差异 · 3 处）

行号 = 现文件（`_TERM_PLACE_PANE_ROWS` 消费循环起始行）。差异均在**无 label 的 pane 行**上出现。

- `1331` spawn 的 `first`（**P0 本体**）：修前 `first` 恒空 ⇒ 「空 workspace」⇒ `workspace close` ⇒ 用户 pi 会话被杀；
  修后 `first` 命中用户 pane ⇒ 走绿路径（不关）。
- `4068` `_ensure_ws_panes_in_repo`：**他仓 base-label 的 ws** —— 修前该 ws 内无 label 的 pane 全被跳过
  （ws 位读到 tab_id ⇒ 不符 wsid）⇒ 误判「pane 全在仓内」⇒ 复用该 ws（并在后续空 ws 判据里**关掉它**）；
  修后正确认到 pane 属他仓 ⇒ 不判「全在仓内」⇒ 让号 `<base>2`，**他仓 ws 保留**。
- `1088` `_term_herdr_pane_tab`：**无 label 的 pane** —— 修前输出错位（wsid 位读到 tab_id / 取不到归属）；
  修后输出正确的 `tab_id` + `workspace_id`。

## 消费点：B 组（语义净化 / 防回潮 · 7 处，**无行为变化**）

这 7 处在「有 label 的行」上修前修后一致；在「空 label 行」上两版也都**不匹配合法舰队名**，故无实测差异。
仍必须改的理由：统一走单一访问器、删掉第二套 `awk -F'\t'` / 前缀切语义、避免下次新增空值字段再被咬。

- `993` `_term_herdr_place_set_pane` · `1008` `_term_herdr_place_drop_pane` · `1107` `_term_herdr_place_set_tab`：
  三者只按 `pane_id` 匹配与回填；修前的前缀切 `${line#*$'\t'}` 对空 label 行仍能命中（去掉首个 TAB 后正好以 pane_id 起头）
  ⇒ 行为无差异。改动 = 去掉前缀切 / 内嵌 `awk -F'\t'`，统一构造器 + 访问器。
- `1239` spawn 同名判重 · `4131` `_ensure_slot_taken` · `4158` `_ensure_task_name_in_ws` · `4186` `_ensure_pick_num`：
  比对对象是**合法舰队名**（非空 label）。空 label 行在修前读到 `name=pane_id`、修后读到 `name=` —— 二者都不等于合法名
  ⇒ 判重/槽位/派生复用结论一致。改动 = 统一取值入口（消除左移隐患，防未来空值字段回潮）。
- `_ensure_slot_taken` 当前**无调用点**（既有死代码）：本批只修不删，清理另立单（不夹带在 P0 热修里）。

## 静态闸（防回潮）

- `tests/t4/lib.sh::t4_scan_place_pane_rows`：逐消费循环断言 ① 无消费行变量的裸 `read`（`<<< "$line"`）
  ② 必含访问器调用 ③ 无 `$'\t'` 字段运算。
- 真件 0 命中；两向正控（用例 43 ②）：换回裸 read ⇒ 必红；删访问器 ⇒ 必红（缺访问器）。
- 构造点唯一：`_TERM_PLACE_PANE_ROWS+=(` 恰 1 处且走 `_term_place_pane_row`（用例 43 ①）。

## 回归证据（用例 43，先红后绿）

- **红（v0.28.0 真件，同场景）**：`workspace close` ×1 · 用户 pane 已被杀 · ws 由 w1 变 w2 · `ensure` rc=0（用户毫不知情）。
- **绿（本批）**：`workspace close` ×0 · 用户 pane 存活 · ws 仍 w1 · 角色 tab 落同一 ws · 摘要「成功 1 / 跳过 0 / 失败 0」。
- **护栏三向（④a/b/c）**：根因回退 + 护栏在 ⇒ 不关 + fail loud「快照判 0 pane，实测 1 pane」；
  根因回退 + 拆护栏 ⇒ `workspace close` 发出、用户 pane 被杀；根因回退 + 复核恒 0 ⇒ 同上（证明判据落在后端原始结果）。
- **同族（①/⑤/⑥）**：空 label/空 cwd/空 fgcwd/空 wsid 四组行字段逐位命中；真·空 ws 仍允许 close 重建；
  判重（`rd-fe2(T1)` 已在 ⇒ 判「已在运行」不新建）· 槽位（同 ws 取 `rd-fe2(T2)`）· 仓归属（他仓同名 base ⇒ 让号 `<base>2`，不碰他仓 ws）。

## 风险与遗留

- 空 ws 判据分支在**非快照路径**会多 1 次 `pane list --workspace`（仅「判空」稀有分支；`ensure` 查询上限从 ±0 变为 +1，仍 ≤2 次 `pane list`）。
- 静态闸按「首层 `done` 收尾」的简单循环建模；未来在消费循环内嵌套新循环时须同步扩展闸（已写在函数注释）。
- 用例 43 实测 20.7s ⇒ 登记 `FAST_SKIP_DOUBLE`（超 15s 预算），不在 `test:fast` 白名单；P0 相关断言在 PR CI 全量覆盖。
  PM 已拍板：保持不进快档（破坏性路径回归，值这个时间；不为单例放宽全仓预算，PRD #143 不改）。
- **已知边界（静态闸，QA P3-3，PM 判「接受」）**：`t4_scan_place_pane_rows` 的正则只匹配
  `for … in "${_TERM_PLACE_PANE_ROWS[@]:-}"` 这一形态（当前全仓 10 个循环全部如此，无实际绕过路径）；
  日后出现其他消费写法（如 `mapfile`/子 shell 复制数组）须同步扩正则。
- `docs/research/2026-11-22-herdr-desktop-app.md`（PM 的 T556 笔记）与 `.pi/` 未暂存、未提交。

- 修订：2026-11-23 初版（#160 P0 修复 + 护栏 + 静态闸 + 用例 43）；
  2026-11-23 二版（按 QA P3 更正准确性）：消费点拆 A 组 3 处真实行为差异 / B 组 7 处语义净化（删掉「10 处都有差异」表述）
  · 行号校正为实测值 · 补静态闸已知边界 + `_ensure_slot_taken` 死代码说明；同步 `tests/t4/lib.sh` 闸注释（6 → 实扫 10 个循环）。
