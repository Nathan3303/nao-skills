#!/usr/bin/env bash
# 用例 31 —— herdr 集成缺失必须 fail loud（#96 二期 B4 · AC2.1 尾句 · PRD 附二 D4）
#
# 缺陷类：`agent_session == null` / 生命周期钩子权威缺（`screen_detection_skipped=false`）时，
#   状态「看起来是 idle」但没有可投递证据。若退化成 idle/unknown 静默处理，PM 会把消息投给一个
#   没有 pi-intercom 身份的会话（丢消息），`ensure` 也会误判「已拉起」。
#
# 判据：
#   ① `status`：显式点名「集成缺失」，判**不可投递**，且**不**打 ✓ 在线（不退化成 idle）；
#   ② `ensure`：不得静默跳过/冒充已拉起，必须 fail loud 且逐条点名缺项；
#   ③ 反向对照：把 agent_session 与钩子权威补上 ⇒ status 判在线、ensure 判「已在运行」；
#   ④ 静态面：BR7 映射里 `unknown` 保守不可投递（禁把无证据的状态当可投递）。
#
# 夹具：`tests/t4/fixtures/herdr-double`（确定性替身，旋钮 pi_session/pi_skip）+ 私有 XDG 根。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
if [ "$BE_NAME" != "herdr" ]; then
  t4_note backend-gate "herdr 集成缺失（agent_session / 钩子权威）是 herdr 专有证据面；tmux 侧由名册离线 + 标题契约路径覆盖"
  t4_exit
fi
LAB="$T4_CACHE_DIR/lab31-$$"; mkdir -p "$LAB"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }

STATE="$BE_CFGROOT/herdr/sessions/$BE_SESSION/double-state.json"
set_knob() { # <键> <JSON 值>
  node -e '
const fs=require("fs");const p=process.argv[1];const k=process.argv[2];const v=JSON.parse(process.argv[3]);
const st=JSON.parse(fs.readFileSync(p,"utf8"));st.knobs=st.knobs||{};st.knobs[k]=v;
fs.writeFileSync(p,JSON.stringify(st));' "$STATE" "$1" "$2" || t4_bad "夹具：旋钮写入失败（$1=$2）"
}

# ---- 夹具：在线 pi pane（label + argv 正确），但**集成缺失**（agent_session=null ∧ 钩子权威缺）----
P="$(be_new_pane "$LAB")"
be_fixture_session "$P" "rd-fe" "$(basename "$LAB")" || t4_bad "夹具：身份写入失败"
set_knob pi_session false
set_knob pi_skip false

# ---- ① status：点名集成缺失 + 不可投递 + 不打在线 ----
be_run_fleet "$LAB" status
t4_assert_eq "0" "$BE_RC" "① status rc=0"
t4_assert_contains "$BE_OUT" "集成缺失" "① status 显式点名「集成缺失」（不静默）"
t4_assert_contains "$BE_OUT" "不可投递" "① 集成缺失判不可投递（BR7）"
t4_assert_not_contains "$BE_OUT" "✓ rd-fe" "① 不得把集成缺失打成「✓ 在线」"
t4_assert_contains "$BE_OUT" "agent_session 空或生命周期钩子权威缺" "① 诊断点名根因（agent_session / 钩子权威）"
t4_assert_contains "$BE_OUT" "pi-intercom/herdr 集成" "① 给可执行指路（核对集成）"

# ---- ② ensure：不得退化/静默，必须 fail loud 且计数 ----
be_run_fleet "$LAB" ensure "rd-fe@$LAB"
t4_assert_eq "0" "$BE_RC" "② ensure rc=0（失败只进计数，D3）"
t4_assert_eq "0" "$(grep -cF -- '[herdr] 已拉起' <<< "$BE_OUT" || true)" "② 零假成功行"
t4_assert_contains "$BE_ERR_ANSI" "不判「已在运行」" "② 显式拒绝「已在运行」判定（fail loud）"
t4_assert_contains "$BE_OUT" "（成功 0 / 跳过 0 / 失败 1）" "② 摘要计失败 1"

# ---- ③ 反向对照：补上 agent_session + 钩子权威 ⇒ 在线 / 已在运行 ----
set_knob pi_session true
set_knob pi_skip true
be_run_fleet "$LAB" status
t4_assert_contains "$BE_OUT" "✓ rd-fe" "③ 证据补全后判「✓ rd-fe 在线」（对照成立）"
t4_assert_not_contains "$BE_OUT" "集成缺失" "③ 证据补全后不再报集成缺失"
be_run_fleet "$LAB" ensure "rd-fe@$LAB"
t4_assert_contains "$BE_ERR_ANSI" "已在运行" "③ ensure 判「已在运行」（与②形成反向对照）"

# ---- ④ 静态：BR7 映射 unknown ⇒ 不可投递 ----
t4_assert_contains "$(sed -n '/^term_deliverable() {/,/^}/p' "$FLEET")" "idle|done" \
  "④ term_deliverable 只放行 idle|done（纯谓词单点）"
t4_assert_not_contains "$(sed -n '/^term_deliverable() {/,/^}/p' "$FLEET")" "unknown" \
  "④ unknown 不在可投递分支里（保守不可投递）"
t4_assert_eq "" "$(t4_scan_term_herdr_forbidden "$FLEET")" \
  "④ herdr 实现区不读终端标题/不碰 tmux 句柄（BR2/BR6）"

be_teardown >/dev/null 2>&1 || true
t4_exit
