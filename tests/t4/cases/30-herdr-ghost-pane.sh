#!/usr/bin/env bash
# 用例 30 —— herdr 幽灵 pane（#96 二期 B4 · AC2.1 · PRD 附二「新增缺陷类」）
#
# 缺陷类（arch spike 实测）：`stop → restart` 回放后 **label 还在、agent 条目没有**。
#   若把「label 命中」当「同一会话在线」，`ensure` 会静默跳过（以为拉起来了其实没有），`status` 会谎报在线。
#
# 判据（三档 + 一档反向对照）：
#   ① label 在、agent 无（前台是 shell）⇒ `status` 判「幽灵 pane」且**不**打 ✓ 在线、判不可投递；
#   ② 同一 label 上 `ensure` ⇒ **不判「已在运行」/不静默跳过**，输出必须点明「幽灵/label 命中 ≠ 在线」；
#   ③ 反向对照：同一夹具把前台换成 pi（agent 条目齐备）⇒ `status` 判在线（证明①②不是恒定红）；
#   ④ 静态面：`pane label` 只作路由标签，身份交叉校验必须看 `argv --name`（BR3）。
#
# 夹具：`tests/t4/fixtures/herdr-double`（确定性替身）+ 私有 XDG 根；不碰真 herdr/用户 default。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
if [ "$BE_NAME" != "herdr" ]; then
  t4_note backend-gate "herdr 幽灵 pane 依赖 pane.label + agent 条目二元证据；tmux 侧由用例 21 的未识别节 + 用例 15 的孤儿 pane 覆盖"
  t4_exit
fi
LAB="$T4_CACHE_DIR/lab30-$$"; mkdir -p "$LAB"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }

# ---- ① 幽灵 pane：label 在、前台是 shell（无 agent 条目）----
GHOST="$(be_new_pane "$LAB")"
t4_assert_ne "" "$GHOST" "夹具：幽灵 pane 建立（$GHOST）"
be_set_name "$GHOST" "rd-fe" "$(basename "$LAB")" || t4_bad "夹具：幽灵 pane label 写入失败"
t4_assert_eq "rd-fe" "$(be_pane_label "$GHOST")" "夹具：label 命中 rd-fe（幽灵态的前提）"

be_run_fleet "$LAB" status
t4_assert_eq "0" "$BE_RC" "① status rc=0"
t4_assert_contains "$BE_OUT" "幽灵 pane" "① status 显式判「幽灵 pane」（label 命中 ≠ 在线）"
t4_assert_not_contains "$BE_OUT" "✓ rd-fe" "① status 不得把幽灵 pane 打成「✓ 在线」"
t4_assert_contains "$BE_OUT" "不可投递" "① 幽灵 pane 判不可投递（BR7 无条目 ⇒ 保守拒）"

# ---- ② ensure：不得静默跳过（不判「已在运行」）----
be_run_fleet "$LAB" ensure "rd-fe@$LAB"
t4_assert_eq "0" "$BE_RC" "② ensure rc=0（失败只进计数，D3）"
# 设计（B2）：幽灵 pane **可寻址**时复用并重跑 agent（而不是新建）；关键是**不得**走「已在运行 ⇒ 跳过」。
t4_assert_contains "$BE_ERR_ANSI" "幽灵 pane / stale" "② 显式点名幽灵/stale（label 命中 ≠ 在线）"
t4_assert_contains "$BE_ERR_ANSI" "不判「已在运行」" "② fail loud 点明「不判已在运行」"
t4_assert_not_contains "$BE_OUT" "已在运行（pane label + 结构化事实命中），跳过" \
  "② 不得走「已在运行 ⇒ 跳过」分支（那会把没起过的会话当已起）"
t4_assert_contains "$BE_OUT" "（成功 1 / 跳过 0 / 失败 0）" "② 摘要计成功 1（复用该 pane 重跑，不是跳过）"
be_run_fleet "$LAB" status
t4_assert_contains "$BE_OUT" "✓ rd-fe" "② 复用重跑后 status 判在线（幽灵已被修好）"

# ---- ③ 反向对照：同一 label 换成 pi（agent 齐备）⇒ 在线 ----
be_teardown >/dev/null 2>&1 || true
be_ensure_scene || { t4_bad "③ 重置场失败"; t4_exit; }
LIVE="$(be_new_pane "$LAB")"
be_fixture_session "$LIVE" "rd-fe" "$(basename "$LAB")" || t4_bad "③ 夹具：在线 pane 身份写入失败"
be_run_fleet "$LAB" status
t4_assert_eq "0" "$BE_RC" "③ status rc=0"
t4_assert_contains "$BE_OUT" "✓ rd-fe" "③ 在线 pane 判「✓ rd-fe 在线」（对照成立）"
t4_assert_not_contains "$BE_OUT" "幽灵 pane" "③ 在线 pane 不得被误判幽灵"
be_run_fleet "$LAB" ensure "rd-fe@$LAB"
t4_assert_contains "$BE_ERR_ANSI" "已在运行" "③ 在线时 ensure 判「已在运行」（与②形成反向对照）"

# ---- ④ 静态：身份交叉校验（label ∧ argv --name）----
t4_assert_ge "1" "$(grep -cF -- '_term_argv_name' "$FLEET" || true)" \
  "④ 身份交叉校验存在（argv --name 解析单点）"
t4_assert_contains "$(grep -cF -- 'mismatch' "$FLEET" >/dev/null && echo mismatch)" "mismatch" \
  "④ label 与 argv --name 不符有独立 verdict（禁猜）"
t4_assert_eq "" "$(t4_scan_term_herdr_forbidden "$FLEET")" \
  "④ herdr 实现区不读终端标题/不碰 tmux 句柄（BR2/BR6）"

be_teardown >/dev/null 2>&1 || true
t4_exit
