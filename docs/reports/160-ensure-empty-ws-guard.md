# #160 P0 修复报告：ensure 不再把「只有用户自己 pane 的 workspace」判空并关掉

- 状态：待验收 · 更新：2026-11-23 · Owner：rd-infra
- 指针：Issue #160 · 任务 T558 · 上游缺陷现场 = v0.28.0（`ccd89e7`）· 分支 `fix/160-ensure-empty-ws-guard`

## TL;DR

- **缺陷**：`ensure` 的放置快照用 TAB 拼字段 → 无 label 的 pane 行被 `read` 折叠后整体左移，wsid 位读到 tab_id
  ⇒ 判成「空 workspace」⇒ `workspace close` ⇒ **连带杀掉用户自己的 pi 会话**（上游已连挂两次）。
- **修法**：字段分隔符改非空白 `US(\x1f)` + **单一构造器 `_term_place_pane_row` / 单一访问器 `_term_place_pane_fields`**
  （10 个消费点全部改走访问器）；`workspace close` 前加**破坏性护栏**（原始 `pane list --workspace` 复核 0 pane，
  冲突即不关 + fail loud）。
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

## 10 个消费点（修前 → 修后，行号 = 现文件）

- `995` `_term_herdr_place_set_pane`：前缀切 `${line#*$'\t'}` → 访问器比 `_TP_PANE`；回填改走构造器。
- `1010` `_term_herdr_place_drop_pane`：同上（幽灵 pane 回收后快照同步）。
- `1090` `_term_herdr_pane_tab`：`read -r _label _pp _ww _tt` → `_TP_PANE/_TP_TAB/_TP_WS`（修前空 label pane 取不到归属）。
- `1113` `_term_herdr_place_set_tab`：内嵌 `awk -F'\t'` 重排 → 访问器 + 构造器（删掉第二套切分语义）。
- `1241` spawn 同名判重：修前空 label 行使 `hit_ws`=tab_id ⇒ 目标 ws 内同名 pane 永不命中 ⇒ 会新建重复 label。
- `1333` spawn 空 ws 判据（**P0**）：修前恒判空 ⇒ 关 ws 杀用户会话；修后 `first` 命中用户 pane + 关前复核。
- `4070` `_ensure_ws_panes_in_repo`：修前该 ws 的 pane 全被跳过 ⇒ 误判「全在仓内」⇒ 把新 pane 塞进**别的仓**的 ws。
- `4133` `_ensure_slot_taken` · `4160` `_ensure_task_name_in_ws` · `4188` `_ensure_pick_num`：
  修前 `name` 读到 pane_id（解析失败）⇒ 槽位判重/派生复用全空转 ⇒ 重复建同槽位会话。

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
- `docs/research/2026-11-22-herdr-desktop-app.md`（PM 的 T556 笔记）与 `.pi/` 未暂存、未提交。

- 修订：2026-11-23 初版（#160 P0 修复 + 护栏 + 静态闸 + 用例 43）
