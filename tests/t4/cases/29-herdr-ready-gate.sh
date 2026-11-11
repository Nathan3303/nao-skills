#!/usr/bin/env bash
# 用例 29 —— herdr 就绪门反假阳性（#96 二期 B4 · AC2.3 · PRD 附二「反假阳性硬判据」）
#
# 被测缺陷类：「已 idle 时 `agent wait --until idle` 6ms 返回」（arch spike 实测）——就绪门如果只看
#   「现在是不是 idle」，会**在 agent 从没动过**时也判成功（假阳性）。
# 本用例把该缺陷做成可复现夹具：pane 已是 `idle`、`agent_session`/钩子权威齐备，但
#   `state_change_seq == 0`（**从未观测到状态迁移**）⇒ 我们的就绪门必须**超时 fail loud**，
#   而不是 rc=0 假装起来了。
#
# 判据（三档）：
#   ① 红态（seq=0）：`ensure` 超时 ⇒ 逐条点名「state_change_seq ≥ 1」缺失；无假成功行；摘要计失败；
#      **rc 仍 0**（PM 裁定 D3：跨后端 rc 语义一致，失败只进计数）。
#   ② 绿态（seq=1，同一夹具其余不变）：`ensure` 成功 ⇒ 有成功行、摘要成功 1 —— 证明①不是「恒定红」。
#   ③ 静态面：就绪门**禁用** `agent wait`（PRD 附二硬判据）；且门是「全条件与」（七条逐条可点名）。
#
# 夹具：`tests/t4/fixtures/herdr-double`（确定性替身；见其文件头）+ 私有 XDG 根；不碰真 herdr/用户 default。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab29-$$"; mkdir -p "$LAB"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"

nyi() { t4_note backend-gate "$1"; t4_exit; }

# 本用例是 herdr 专有面：tmux 侧没有「agent 状态 / state_change_seq」语义（那里是 5s 标题轮询）。
#   登记在 `tests/t4/backends/herdr.txt` 的 own 表；tmux 后端跑到它时按后端门控（NOTE 点名，不静默 SKIP）。
if [ "$BE_NAME" != "herdr" ]; then
  nyi "就绪门的 state_change_seq / agent 会话证据是 herdr 专有语义；tmux 侧由用例 19 的 5s 标题轮询覆盖"
fi

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }
be_start_server || { t4_bad "be_start_server 失败"; t4_exit; }
CALLER="$(be_caller_pane)"
[ -n "$CALLER" ] || be_new_pane "$LAB" >/dev/null

STATE="$BE_CFGROOT/herdr/sessions/$BE_SESSION/double-state.json"
set_knob() { # <键> <值>（JSON 值；布尔/数字原样）
  node -e '
const fs=require("fs");const p=process.argv[1];const k=process.argv[2];const v=JSON.parse(process.argv[3]);
const st=JSON.parse(fs.readFileSync(p,"utf8"));st.knobs=st.knobs||{};st.knobs[k]=v;
fs.writeFileSync(p,JSON.stringify(st));' "$STATE" "$1" "$2" || t4_bad "夹具：旋钮写入失败（$1=$2）"
}
t4_assert_file "$STATE" "夹具：替身状态文件存在（$STATE）"

run_ensure() { # <args...>
  export TERM_READY_TIMEOUT_MS=600 TERM_READY_POLL_MAX=5 TERM_READY_POLL_INT=0.1
  be_run_fleet "$LAB" ensure "$@"
}
launch_lines() { grep -cF -- '[herdr] 已拉起' <<< "$BE_OUT_ANSI" || true; }

# ============================================================ ① 红态：已 idle 但 seq 从未前进
set_knob pi_seq 0
run_ensure "rd-fe@$LAB"
t4_assert_eq "0" "$BE_RC" "① 就绪超时不该改 rc（PM 裁定 D3：跨后端 rc 语义一致）"
t4_assert_eq "0" "$(launch_lines)" "① 零假成功行（禁把「现在 idle」当就绪）"
t4_assert_contains "$BE_ERR_ANSI" "就绪门超时" "① fail loud 点名「就绪门超时」"
t4_assert_contains "$BE_ERR_ANSI" "state_change_seq ≥ 1" "① 逐条报缺点名「state_change_seq ≥ 1」"
t4_assert_contains "$BE_OUT_ANSI" "（成功 0 / 跳过 0 / 失败 1）" "① 摘要计入失败 1（不冒充成功）"

# ============================================================ ② 绿态：只把 seq 抬到 1 ⇒ 必须成功
#   重置场（① 的失败 pane 会保留并命中 label ⇒ 会被判「已在运行」跳过，污染绿态对照）
be_teardown >/dev/null 2>&1 || true
be_start_server || { t4_bad "② 重置场失败（be_start_server）"; t4_exit; }
be_new_pane "$LAB" >/dev/null
STATE="$BE_CFGROOT/herdr/sessions/$BE_SESSION/double-state.json"
set_knob pi_seq 1
run_ensure "rd-fe@$LAB"
t4_assert_eq "0" "$BE_RC" "② 绿态 ensure rc=0"
t4_assert_eq "1" "$(launch_lines)" "② 绿态恰 1 行 [herdr] 已拉起（门不是恒定红）"
t4_assert_contains "$BE_OUT_ANSI" "（成功 1 / 跳过 0 / 失败 0）" "② 绿态摘要 1/0/0"

# ============================================================ ③ 静态：禁 agent wait 作就绪门 + 全条件与
# 只数**代码行**（注释里写着禁令本身不算违规）
t4_assert_eq "0" "$(grep -nE '(^|[^a-z])agent[[:space:]]+wait' "$FLEET" | grep -vc '^[0-9]*:[[:space:]]*#' || true)" \
  "③ 就绪门禁用「agent wait --until idle」（已 idle 时 6ms 返回 = 假阳性）"
t4_assert_eq "" "$(t4_scan_term_herdr_forbidden "$FLEET")" \
  "③ herdr 实现区不读终端标题/不碰 tmux 句柄（BR2/BR6 机械兜）"
for cond in "pane 存在" "前台进程 name==pi" "argv --name" "agent_session != null" "agent_status == idle" "state_change_seq ≥ 1" "screen_detection_skipped"; do
  t4_assert_contains "$(grep -cF -- "$cond" "$FLEET" >/dev/null && echo "$cond")" "$cond" \
    "③ 就绪门逐条可点名：$cond"
done

be_teardown >/dev/null 2>&1 || true
t4_exit
