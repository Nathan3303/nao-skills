#!/usr/bin/env bash
# 用例 32 —— 真机整轮 herdr（#96 三期 P1 · AC3.5 + AC3.1 布局 A + AC3.2 J1/J4）
#
# 为什么要有这一例：其余 herdr 用例都跑**确定性替身**（`tests/t4/fixtures/herdr-double`），
#   回答不了「真 herdr + 真 pi + 真生命周期钩子」这一层的问题。本用例用**真** herdr 0.9.1 跑一轮
#   完整生命周期，并把「不碰用户环境」变成**结构性**保证（四件私有 env ⇒ 碰不到）。
#
# 判据（逐段）：
#   ① 隔离底座：`XDG_CONFIG_HOME` + `HOME` + `PI_CODING_AGENT_DIR` + `TMPDIR` **四件全私有**；
#      `herdr integration install pi` 装到私有 agent dir（实测尊重 PI_CODING_AGENT_DIR，不写用户 `~/.pi`）；
#   ② `session-start --session <s>` 起专用 server（BR6：清宿主终端句柄 + 枚举清 HERDR_*）；
#   ③ `ensure` 2 角色（pm + rd-fe，控时长）⇒ 布局 A：1 workspace/仓 + 1 tab/角色 + 每 tab 恰 1 pane
#      （结构判据：`tab list` 的 pane_count == 1 ∧ `pane list` 的 tab_id 对应 ∧ pane_id 唯一）；
#      就绪七条件在**权威源**（`agent list`）上逐条复核；
#   ④ `status` 双在线；
#   ⑤ 迁移无损（AC3.1）：对一个**已起**的会话 `pane move … --tab … --split right` ⇒
#      pane_id 不变 + 被搬空的 tab 自动关闭 + `status` 仍在线；
#   ⑥ `close` 一个 ⇒ pane 消失；`cleanup` ⇒ `sessions/` 空 + 零残留 + 用户 `default` 不可见；
#   ⑦ J1/J4（真 herdr 小空间）：`[server] headless_cols/headless_rows` 注入 60×20 ⇒ 不 warn（旋钮生效）·
#      40×8 ⇒ warn + 三件套指路 + **无 0 尺寸 pane**（真 herdr 的 0 行 pane 只在多 pane 挤压下出现；
#      布局 A 每 tab 1 pane 结构上不可达 ⇒「0 尺寸 ⇒ SPAWN_FAIL」负控在用例 22 的替身上做）；
#   ⑧ 用户侧零副作用：`~/.pi` 与 `~/.config/herdr` 的**路径集合**前后一致
#      （比内容会恒假红：并发运行的真实舰队会持续追加自己的 session 日志）。
#
# 前提缺失（AC1.5）：herdr 未安装 / protocol ≠ 22 ⇒ **SKIP 并给原因**（不 FAIL）。
# 本用例是 herdr 专有面（登记在 tests/t4/backends/herdr.txt 的 own 表）⇒ tmux 后端按后端门控 NOTE。
#
# 造价：wall clock 目标 3–6s（上限断言 90s）；不写用户 `~/.pi`、不碰用户 `default` session。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
if [ "$BE_NAME" != "herdr" ]; then
  t4_note backend-gate "真 herdr 整轮（session-start/ensure/status/close/cleanup）在 tmux 后端无对应物；tmux 侧由用例 01/20/22 的隔离 socket 覆盖"
  t4_exit
fi

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
BASH_BIN="$(command -v bash)"
REAL_HOME="${HOME:-}"
REAL_PI="$REAL_HOME/.pi"
REAL_HERDR_ROOT="$REAL_HOME/.config/herdr"

# ---- 前提（AC1.5 第一类：协议/版本不兼容 ⇒ SKIP 给原因，不 FAIL）----
command -v herdr >/dev/null 2>&1 || t4_skip "环境缺少 herdr（需 ≥0.9.1）；装好后重跑，或 NAO_TERMINAL=tmux 回退"
CASE_T0="$(date +%s%N)"
SESS="nao-t4-real-$$"
LAB="$T4_CACHE_DIR/real32-$$"
mkdir -p "$LAB" "$LAB/home" "$LAB/tmp" "$LAB/pi/extensions" "$LAB/repo"
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "$SESS" || { t4_bad "be_init 失败"; t4_exit; }

PROTO="$(be_herdr "$SESS" api schema 2>/dev/null | sed -nE 's/^protocol:[[:space:]]*([0-9]+).*/\1/p' | head -1)"
[ "$PROTO" = "22" ] \
  || t4_skip "herdr protocol=${PROTO:-<不可读>} ≠ 22（破坏性变更 ⇒ 本用例 SKIP 而非 FAIL；请升级 nao-skill 或 NAO_TERMINAL=tmux 回退）"
t4_assert_eq "22" "$PROTO" "① 前提：herdr protocol=22（AC1.5 第一类）"

# ---- ① 四件私有 env（结构性隔离：不是「小心别碰」，是「碰不到」）----
REAL_PI_SNAP_BEFORE="$(find "$REAL_PI" \( -type f -o -type d \) 2>/dev/null | sort)"
REAL_HERDR_SNAP_BEFORE="$(find "$REAL_HERDR_ROOT" \( -type f -o -type d \) 2>/dev/null | sort)"
export XDG_CONFIG_HOME="$LAB/config"
export HOME="$LAB/home"
export PI_CODING_AGENT_DIR="$LAB/pi"
export TMPDIR="$LAB/tmp"
t4_assert_eq "$BE_CFGROOT" "$XDG_CONFIG_HOME" "① 隔离：测试侧 herdr 根 = 生产侧 XDG_CONFIG_HOME（同一根）"
t4_assert_eq "$LAB/home" "$HOME" "① 隔离：HOME 私有（$HOME）"
t4_assert_eq "$LAB/pi" "$PI_CODING_AGENT_DIR" "① 隔离：PI_CODING_AGENT_DIR 私有（$PI_CODING_AGENT_DIR）"
t4_assert_eq "$LAB/tmp" "$TMPDIR" "① 隔离：TMPDIR 私有（$TMPDIR）"

# `integration install pi` 尊重 PI_CODING_AGENT_DIR（PRD 附三实测）⇒ 装到私有目录，不写用户 ~/.pi
be_herdr "$SESS" integration install pi >"$LAB/install.log" 2>&1 \
  || { t4_bad "① herdr integration install pi 失败：$(tail -1 "$LAB/install.log")"; t4_exit; }
t4_assert_file "$PI_CODING_AGENT_DIR/extensions/herdr-agent-state.ts" \
  "① pi 集成装到私有 agent dir（尊重 PI_CODING_AGENT_DIR）"
t4_assert_contains "$(cat "$LAB/install.log")" "$PI_CODING_AGENT_DIR" \
  "① 安装日志回显私有路径（不是用户 ~/.pi）"
t4_assert_eq "" "$(find "$REAL_PI" -name 'herdr-agent-state.ts' -newermt "@$(( $(date +%s) - 180 ))" 2>/dev/null | head -1)" \
  "① 用户 ~/.pi 未被写入 herdr 集成（近 3 分钟窗口内零新增）"

# ---- 收尾（失败/中断也拆场；cleanup 幂等，判 effect）----
r32_cleanup() {
  XDG_CONFIG_HOME="$LAB/config" HOME="$LAB/home" PI_CODING_AGENT_DIR="$LAB/pi" TMPDIR="$LAB/tmp" \
    NAO_TERMINAL=herdr timeout 30 "$BASH_BIN" "$FLEET" cleanup --session "$SESS" >/dev/null 2>&1 || true
}
r32_exit_trap() {
  local rc=$?
  r32_cleanup
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap r32_exit_trap EXIT

export NAO_TERMINAL=herdr HERDR_ENV=1
export HERDR_SESSION="$SESS"
export HERDR_SOCKET_PATH="$XDG_CONFIG_HOME/herdr/sessions/$SESS/herdr.sock"
export NAO_SKILLS="$T4_ROOT"
export NAO_TASKS_STATE="$LAB/tasks-state.md"
printf '# 用例 32 tasks-state（空表：不阻塞回收）\n\n## 进行中\n\n（无）\n' > "$NAO_TASKS_STATE"

run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR（*_ANSI 去色）
  t4_run_in_dir "$LAB" timeout 90 "$BASH_BIN" "$FLEET" "$@"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
json_rows() { be_herdr "$SESS" "$@" 2>/dev/null; }
split_objs() { sed 's/},{/}\n{/g'; }
obj_for() { # <json> <key> <value> → 首个匹配对象（单行；无则空）
  split_objs <<< "$1" | grep -F "\"$2\":\"$3\"" | head -1
}
fld() { # <object> <key> → 字符串值（无则空）
  sed -nE "s/.*\"$2\":\"([^\"]+)\".*/\\1/p" <<< "$1" | head -1
}
fldnum() { # <object> <key> → 数字/布尔值（无则空）
  sed -nE "s/.*\"$2\":([0-9]+|[a-z]+).*/\\1/p" <<< "$1" | head -1
}
residue_procs() { # <VAR=VALUE> → argv0 ∈ {herdr,pi} 且精确持有该 env 的 pid（每行一个）
  #   只看 herdr/pi：本用例**自己**也持有这些 env（导出给生产脚本），不过滤 argv0 会把自己当残留。
  local want="$1" d a0
  for d in /proc/[0-9]*; do
    [ -r "$d/environ" ] && [ -r "$d/cmdline" ] || continue
    a0="$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null | head -1)"; a0="${a0##*/}"
    case "$a0" in herdr|pi) ;; *) continue ;; esac
    if tr '\0' '\n' < "$d/environ" 2>/dev/null | grep -qxF -- "$want"; then printf '%s\n' "${d##*/}"; fi
  done
  return 0
}

# ---- ② session-start（BR6 唯一入口）----
ROUNDTRIP_T0="$(date +%s%N)"
run_fleet session-start --session "$SESS"
t4_assert_eq "0" "$T4_RC" "② session-start rc=0（T4_ERR=$(printf '%s' "$T4_ERR_ANSI" | head -1)）"
t4_assert_contains "$T4_OUT_ANSI" "server 已就绪" "② server 就绪行在位（轮询，非固定 sleep）"
t4_assert_eq "1" "$([ -S "$HERDR_SOCKET_PATH" ] && echo 1 || echo 0)" "② socket 落在私有根内（$HERDR_SOCKET_PATH）"

# ---- ③' 调用方场（T545）：模拟「用户在自己的 pane 里对其余仓 ensure」----
#   调用方 workspace 必须先在场，否则「不落进调用方 workspace」这条断言无从判定（空转）。
#   注意：三条断言能同时成立的前提是调用方 label ≠ 会话名（下面 rename 为 `caller`）——
#   否则反向断言「无 label=会话名 的 workspace」会被调用方自己撞上（口径见 ADR 2026-11-13）。
CALLER_PANE="$(be_new_pane "$LAB")" || { t4_bad "③ 调用方夹具：建 pane 失败"; t4_exit; }
CALLER_WS="$(fld "$(obj_for "$(json_rows pane list)" pane_id "$CALLER_PANE")" workspace_id)"
t4_assert_ne "" "$CALLER_WS" "③ 调用方夹具：pane=$CALLER_PANE 落在 workspace $CALLER_WS"
json_rows workspace rename "$CALLER_WS" caller >/dev/null 2>&1 \
  || t4_bad "③ 调用方夹具：workspace rename 失败（真 herdr ≥0.9.1 才有）"
t4_assert_eq "caller" "$(fld "$(obj_for "$(json_rows workspace list)" workspace_id "$CALLER_WS")" label)" \
  "③ 调用方夹具：调用方 workspace label=caller（≠ 会话名，反向断言才不是自撞）"

# ---- ③ ensure 2 角色（pm + rd-fe）----
ENSURE_T0="$(date +%s%N)"
run_fleet ensure "pm@$LAB/repo" "rd-fe@$LAB/repo"
ENSURE_MS=$(( ($(date +%s%N) - ENSURE_T0) / 1000000 ))
t4_assert_eq "0" "$T4_RC" "③ ensure rc=0（T4_ERR=$(printf '%s' "$T4_ERR_ANSI" | head -1)）"
t4_assert_contains "$T4_OUT_ANSI" "（成功 2 / 跳过 0 / 失败 0）" "③ 摘要三类计数 = 2/0/0"
t4_assert_contains "$T4_OUT_ANSI" "[herdr] 已拉起 pm @ $LAB/repo" "③ pm 成功行在位"
t4_assert_contains "$T4_OUT_ANSI" "[herdr] 已拉起 rd-fe @ $LAB/repo" "③ rd-fe 成功行在位"
t4_assert_eq "1" "$([ "$ENSURE_MS" -le 90000 ] && echo 1 || echo 0)" "③ 两角色 ensure wall clock ${ENSURE_MS}ms ≤ 90s（目标 3–6s）"
t4_info "实测：ensure 2 角色 ${ENSURE_MS}ms（整轮含 session-start/status/close/cleanup 见末行）"

# 布局 A（AC3.1）：1 workspace/仓（label = 已声明 scope，否则仓 slug）+ 1 tab/角色，每 tab 恰 1 pane
#   放置键判据（ADR 2026-11-13-herdr-workspace-scope-key）：目标仓 $LAB/repo **不是 git 仓** ⇒
#   slug = realpath 的 basename = `repo`。旧缺陷把「label = 会话名」写成了期望值，此处按判据改：
#   ① 存在 label=repo 的 workspace · ② 新 pane 不在调用方 workspace · ③ 没有 label=会话名 的 workspace
WS_JSON="$(json_rows workspace list)"
WS_OBJ="$(obj_for "$WS_JSON" label repo)"
WS_ID="$(fld "$WS_OBJ" workspace_id)"
t4_assert_ne "" "$WS_ID" "③ 布局 A：workspace（label=repo：非 git 仓 ⇒ slug=repo）已建立（$WS_ID）"
t4_assert_ne "$CALLER_WS" "$WS_ID" "③ 放置键：新 workspace ≠ 调用方 workspace（$CALLER_WS）"
t4_assert_eq "" "$(obj_for "$WS_JSON" label "$SESS")" \
  "③ 放置键：无 label=$SESS 的 workspace（不得取会话名作放置键）"
TABS_JSON="$(json_rows tab list --workspace "$WS_ID")"
TAB_PM="$(obj_for "$TABS_JSON" label pm)"
TAB_FE="$(obj_for "$TABS_JSON" label rd-fe)"
t4_assert_ne "" "$TAB_PM" "③ 布局 A：tab label = pm"
t4_assert_ne "" "$TAB_FE" "③ 布局 A：tab label = rd-fe"
t4_assert_eq "1" "$(fldnum "$TAB_PM" pane_count)" "③ 布局 A：pm tab pane_count == 1（结构判据，非几何）"
t4_assert_eq "1" "$(fldnum "$TAB_FE" pane_count)" "③ 布局 A：rd-fe tab pane_count == 1"
t4_assert_ne "$(fld "$TAB_PM" tab_id)" "$(fld "$TAB_FE" tab_id)" "③ 布局 A：两角色各占一个 tab（tab_id 不同）"
PANES_JSON="$(json_rows pane list)"
PANE_PM="$(obj_for "$PANES_JSON" label pm)"
PANE_FE="$(obj_for "$PANES_JSON" label rd-fe)"
P_PM="$(fld "$PANE_PM" pane_id)"; P_FE="$(fld "$PANE_FE" pane_id)"
t4_assert_ne "" "$P_PM" "③ pane list：pm 的 pane_id 可定位（$P_PM）"
t4_assert_ne "" "$P_FE" "③ pane list：rd-fe 的 pane_id 可定位（$P_FE）"
t4_assert_ne "$P_PM" "$P_FE" "③ 布局 A：两角色 pane_id 唯一（不共享 pane）"
t4_assert_eq "$(fld "$TAB_PM" tab_id)" "$(fld "$PANE_PM" tab_id)" "③ 布局 A：pm pane 的 tab_id 与其角色 tab 一致"
t4_assert_eq "$(fld "$TAB_FE" tab_id)" "$(fld "$PANE_FE" tab_id)" "③ 布局 A：rd-fe pane 的 tab_id 与其角色 tab 一致"
T_PM="$(fld "$PANE_PM" tab_id)"
t4_info "布局 A 实测：workspace=$WS_ID · tabs=[$(split_objs <<< "$TABS_JSON" | grep -F '"tab_id"' | while IFS= read -r o; do printf '%s/%s/%s ' "$(fld "$o" tab_id)" "$(fld "$o" label)" "$(fldnum "$o" pane_count)"; done)]（tab_id/label/pane_count）"
t4_info "布局 A 实测：panes=[$(split_objs <<< "$PANES_JSON" | grep -E '"label":"(pm|rd-fe)"' | while IFS= read -r o; do printf '%s→%s(%s) ' "$(fld "$o" label)" "$(fld "$o" pane_id)" "$(fld "$o" tab_id)"; done)]（label→pane_id(tab_id)）"

# 就绪七条件（在**权威源** agent list 上逐条复核；ensure 就绪门内部已全条件与一次）
AGENTS_JSON="$(json_rows agent list)"
for pid in "$P_PM" "$P_FE"; do
  AL="$(obj_for "$AGENTS_JSON" pane_id "$pid")"
  t4_assert_ne "" "$AL" "③ 就绪：$pid 在 agent list 有条目"
  t4_assert_contains "$AL" '"agent_session":{' "③ 就绪：$pid 有 agent_session（集成在岗）"
  t4_assert_contains "$AL" '"agent_status":"idle"' "③ 就绪：$pid agent_status=idle"
  t4_assert_contains "$AL" '"screen_detection_skipped":true' "③ 就绪：$pid 状态来自生命周期钩子（非屏幕启发式）"
  _seq="$(sed -nE 's/.*"state_change_seq":([0-9]+).*/\1/p' <<< "$AL" | head -1)"
  t4_assert_ge "1" "${_seq:-0}" "③ 就绪：$pid state_change_seq ≥ 1（观测到状态迁移；实际 ${_seq:-0}）"
done

# ---- ④ status 双在线 ----
run_fleet status
t4_assert_eq "0" "$T4_RC" "④ status rc=0"
t4_assert_contains "$T4_OUT_ANSI" "✓ pm" "④ status：pm 在线"
t4_assert_contains "$T4_OUT_ANSI" "✓ rd-fe" "④ status：rd-fe 在线"

# 幂等（同一条 ensure 连跑 2 次 ⇒ effect=0：不新建 tab/pane，全部判「已在运行」）
TABS_BEFORE="$(json_rows tab list --workspace "$WS_ID")"
run_fleet ensure "pm@$LAB/repo" "rd-fe@$LAB/repo"
t4_assert_eq "0" "$T4_RC" "③ 幂等：重跑 ensure rc=0"
t4_assert_contains "$T4_OUT_ANSI" "（成功 0 / 跳过 2 / 失败 0）" "③ 幂等：重跑摘要 0/2/0（不重复拉起）"
t4_assert_eq "$TABS_BEFORE" "$(json_rows tab list --workspace "$WS_ID")" \
  "③ 幂等：tab 结构零变化（布局 A 重入安全）"

# ---- ⑤ 迁移无损（AC3.1）：把一个**已起**的会话搬进另一个 tab ----
SCRATCH_JSON="$(json_rows tab create --workspace "$WS_ID" --cwd "$LAB/repo" --label mig-scratch --no-focus)"
SCRATCH_TAB="$(split_objs <<< "$SCRATCH_JSON" | grep -F '"tab_id"' | head -1 | sed -nE 's/.*"tab_id":"([^"]+)".*/\1/p')"
t4_assert_ne "" "$SCRATCH_TAB" "⑤ 夹具：临时 tab 建立（$SCRATCH_TAB）"
json_rows pane move "$P_PM" --tab "$SCRATCH_TAB" --split right >/dev/null 2>&1
MOVE_OBJ="$(obj_for "$(json_rows pane list)" pane_id "$P_PM")"
t4_assert_eq "$SCRATCH_TAB" "$(fld "$MOVE_OBJ" tab_id)" "⑤ 迁移：pm pane 已在目标 tab（pane_id 仍是 $P_PM）"
t4_assert_eq "" "$(obj_for "$(json_rows tab list --workspace "$WS_ID")" tab_id "$T_PM")" \
  "⑤ 迁移：被搬空的 tab 自动关闭（$T_PM 已消失）"
t4_info "迁移实测：pane move ${P_PM} --tab ${SCRATCH_TAB} --split right ⇒ pane_id=${P_PM}（不变）· 源 tab ${T_PM} 已自动关闭 · tab 现=${SCRATCH_TAB}"
run_fleet status
t4_assert_eq "0" "$T4_RC" "⑤ 迁移后 status rc=0"
t4_assert_contains "$T4_OUT_ANSI" "✓ pm" "⑤ 迁移后 status 仍判 pm 在线（会话未受影响）"

# ---- ⑥ close 一个 + cleanup 拆场 ----
_r32_no_residue() {
  [ -z "$(residue_procs "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" | head -1)" ] \
    && [ -z "$(residue_procs "PI_CODING_AGENT_DIR=$PI_CODING_AGENT_DIR" | head -1)" ]
}
run_fleet close rd-fe
t4_assert_eq "0" "$T4_RC" "⑥ close rd-fe rc=0（T4_ERR=$(printf '%s' "$T4_ERR_ANSI" | head -1)）"
t4_assert_eq "" "$(obj_for "$(json_rows pane list)" pane_id "$P_FE")" \
  "⑥ close 后 rd-fe 的 pane 已消失（effect 判据）"
run_fleet cleanup --session "$SESS"
t4_assert_eq "0" "$T4_RC" "⑥ cleanup rc=0（stop+delete；判 effect 不看 rc）"
t4_assert_eq "0" "$(ls -A "$XDG_CONFIG_HOME/herdr/sessions" 2>/dev/null | wc -l | tr -d ' ')" \
  "⑥ 拆场后 sessions/ 为空（$XDG_CONFIG_HOME/herdr/sessions）"
# 拆场是异步的（server 自行退出）⇒ 有界轮询，不写死 sleep
be_wait_until 50 0.1 _r32_no_residue >/dev/null 2>&1 || true
t4_assert_eq "" "$(residue_procs "XDG_CONFIG_HOME=$XDG_CONFIG_HOME" | head -1)" \
  "⑥ 零残留：无常驻 herdr server 持有本实验根"
t4_assert_eq "" "$(residue_procs "PI_CODING_AGENT_DIR=$PI_CODING_AGENT_DIR" | head -1)" \
  "⑥ 零残留：无 pi 进程持有私有 agent dir"
t4_assert_eq "" "$(find "$REAL_HERDR_ROOT/sessions" -maxdepth 1 -name "$SESS" 2>/dev/null | head -1)" \
  "⑥ 用户 herdr 根不可见本场会话（BR9：default 碰不到）"

ROUNDTRIP_MS=$(( ($(date +%s%N) - ROUNDTRIP_T0) / 1000000 ))
t4_assert_eq "1" "$([ "$ROUNDTRIP_MS" -le 90000 ] && echo 1 || echo 0)" \
  "⑥ 整轮（session-start→ensure→status→迁移→close→cleanup）${ROUNDTRIP_MS}ms ≤ 90s（AC3.5 造价）"
t4_info "整轮 wall clock ${ROUNDTRIP_MS}ms（目标 3–6s 量级；含两次 status 与迁移段）"

# ---- ⑦ J1/J4（真 herdr 小空间）：[server] headless_cols/headless_rows 可注入 ----
sp_install_pi() { # <cfgroot> <pi-dir> <session>
  local cfg="$1" pi="$2" sess="$3" old="${BE_CFGROOT:-}"
  BE_CFGROOT="$cfg"
  PI_CODING_AGENT_DIR="$pi" be_herdr "$sess" integration install pi >/dev/null 2>&1
  local rc=$?
  BE_CFGROOT="$old"
  return "$rc"
}
sp_run() { # <cfgroot> <home> <pi> <tmp> <session> <workdir> <fleet 参数...>
  local cfg="$1" h="$2" pi="$3" tmp="$4" sess="$5" wd="$6"; shift 6
  t4_run_in_dir "$wd" env XDG_CONFIG_HOME="$cfg" HOME="$h" PI_CODING_AGENT_DIR="$pi" TMPDIR="$tmp" \
    NAO_TERMINAL=herdr HERDR_ENV=1 HERDR_SESSION="$sess" \
    HERDR_SOCKET_PATH="$cfg/herdr/sessions/$sess/herdr.sock" \
    NAO_SKILLS="$T4_ROOT" NAO_TASKS_STATE="$LAB/tasks-state.md" \
    timeout 90 "$BASH_BIN" "$FLEET" "$@"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
sp_field() { # <几何场根> <cols> <rows> <session>：建私有根 + config.toml + pi 集成
  local d="$1" cols="$2" rows="$3" sess="$4"
  mkdir -p "$d/home" "$d/tmp" "$d/repo" "$d/config/herdr" "$d/pi/extensions"
  printf '[server]\nheadless_cols = %s\nheadless_rows = %s\n' "$cols" "$rows" > "$d/config/herdr/config.toml"
  sp_install_pi "$d/config" "$d/pi" "$sess"
}

# 场 2：60×20（≥ 阈值 60×10 ⇒ 不 warn：证明旋钮生效且判据不误报）
SP2="$LAB/sp60"; SP2_SESS="nao-t4-real32-s60-$$"
sp_field "$SP2" 60 20 "$SP2_SESS" || t4_bad "⑦ 夹具：60×20 场 pi 集成安装失败"
sp_run "$SP2/config" "$SP2/home" "$SP2/pi" "$SP2/tmp" "$SP2_SESS" "$SP2/repo" session-start --session "$SP2_SESS"
t4_assert_eq "0" "$T4_RC" "⑦ 60×20 场：session-start rc=0"
sp_run "$SP2/config" "$SP2/home" "$SP2/pi" "$SP2/tmp" "$SP2_SESS" "$SP2/repo" ensure "qa@$SP2/repo"
t4_assert_eq "0" "$T4_RC" "⑦ 60×20 场：ensure rc=0"
t4_assert_eq "0" "$(printf '%s' "$T4_ERR_ANSI" | grep -c '空间不足' || true)" \
  "⑦ J4 60×20：不触发空间 warn（pane 60×20 ≥ 阈值 60×10 ⇒ 旋钮生效）"
t4_assert_contains "$T4_OUT_ANSI" "（成功 1 / 跳过 0 / 失败 0）" "⑦ 60×20 场：摘要成功 1"
sp_run "$SP2/config" "$SP2/home" "$SP2/pi" "$SP2/tmp" "$SP2_SESS" "$SP2/repo" cleanup --session "$SP2_SESS"
t4_assert_eq "0" "$(ls -A "$SP2/config/herdr/sessions" 2>/dev/null | wc -l | tr -d ' ')" \
  "⑦ 60×20 场：拆场后 sessions/ 为空"

# 场 3：40×8（< 阈值 ⇒ warn + 三件套 + 无 0 尺寸 pane）
SP3="$LAB/sp40"; SP3_SESS="nao-t4-real32-s40-$$"
sp_field "$SP3" 40 8 "$SP3_SESS" || t4_bad "⑦ 夹具：40×8 场 pi 集成安装失败"
sp_run "$SP3/config" "$SP3/home" "$SP3/pi" "$SP3/tmp" "$SP3_SESS" "$SP3/repo" session-start --session "$SP3_SESS"
t4_assert_eq "0" "$T4_RC" "⑦ 40×8 场：session-start rc=0"
sp_run "$SP3/config" "$SP3/home" "$SP3/pi" "$SP3/tmp" "$SP3_SESS" "$SP3/repo" ensure "qa@$SP3/repo"
t4_assert_eq "0" "$T4_RC" "⑦ 40×8 场：ensure rc=0（空间不足只 warn 不 die）"
t4_assert_contains "$T4_ERR_ANSI" "空间不足" "⑦ J1 40×8：warn「空间不足」在位"
t4_assert_contains "$T4_ERR_ANSI" "列=40" "⑦ J1 40×8：点名实际列数（真 herdr 量测）"
t4_assert_contains "$T4_ERR_ANSI" "行=8" "⑦ J1 40×8：点名实际行数"
t4_assert_contains "$T4_ERR_ANSI" "headless_cols/headless_rows" "⑦ J5 40×8：指路「调 [server] headless_*」"
t4_assert_contains "$T4_ERR_ANSI" "attach 后重排" "⑦ J5 40×8：指路「attach 后重排」"
t4_assert_contains "$T4_ERR_ANSI" "NAO_TERMINAL=tmux" "⑦ J5 40×8：指路「切布局（回退 tmux）」"
t4_assert_contains "$T4_OUT_ANSI" "（成功 1 / 跳过 0 / 失败 0）" "⑦ 40×8 场：warn 不改三态（仍计成功）"
t4_assert_eq "0" "$(printf '%s' "$T4_ERR_ANSI" | grep -cE '列=0|行=0' || true)" \
  "⑦ J4 40×8：无 0 尺寸 pane（0 行只在多 pane 挤压下出现；布局 A 每 tab 1 pane 结构上不可达）"
t4_info "J1/J4 实测：headless 60×20 ⇒ 无 warn（pane 60×20 ≥ 60×10）· headless 40×8 ⇒ warn「列=40 行=8」+ 三件套 + 无 0 尺寸 pane"
sp_run "$SP3/config" "$SP3/home" "$SP3/pi" "$SP3/tmp" "$SP3_SESS" "$SP3/repo" cleanup --session "$SP3_SESS"
t4_assert_eq "0" "$(ls -A "$SP3/config/herdr/sessions" 2>/dev/null | wc -l | tr -d ' ')" \
  "⑦ 40×8 场：拆场后 sessions/ 为空"

# ---- ⑧ 用户侧零副作用：~/.pi 与 ~/.config/herdr 的路径集合前后一致 ----
REAL_PI_SNAP_AFTER="$(find "$REAL_PI" \( -type f -o -type d \) 2>/dev/null | sort)"
REAL_HERDR_SNAP_AFTER="$(find "$REAL_HERDR_ROOT" \( -type f -o -type d \) 2>/dev/null | sort)"
t4_assert_eq "$REAL_PI_SNAP_BEFORE" "$REAL_PI_SNAP_AFTER" "⑧ 用户 ~/.pi 路径集合前后一致（本用例零新增/零删除）"
t4_assert_eq "$REAL_HERDR_SNAP_BEFORE" "$REAL_HERDR_SNAP_AFTER" \
  "⑧ 用户 ~/.config/herdr 路径集合前后一致（未新建会话/未写 config）"

CASE_MS=$(( ($(date +%s%N) - CASE_T0) / 1000000 ))
t4_assert_eq "1" "$([ "$CASE_MS" -le 90000 ] && echo 1 || echo 0)" "⑧ 整轮 wall clock ${CASE_MS}ms ≤ 90s（含 3 场 session-start/ensure/cleanup）"
t4_info "整轮 wall clock ${CASE_MS}ms"
t4_exit
