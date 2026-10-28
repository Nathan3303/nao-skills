#!/usr/bin/env bash
# 用例 15 —— 子代理会话（subagent-*）在 status/close 的显式识别与排除（T525）
#
# PRD：docs/prds/2026-10-14-subagent-isolation.md（§三 范围 1–8 · §五 BR1–BR9 · §七 AC2–AC8）
# 被测对象：.agents/scripts/nao-fleet.sh
#   · cmd_status 汇总行（新增 helper subagent_in_field，与 derived_in_field 同源）
#   · cmd_close 目标解析最前的 subagent-* 显式拒绝（只判 $target、--force 不旁路、不触任何 pane）
#   · unattributed_pi_panes 的 claimed 改「条目感知」（新增 helper roster_pane_claims，排除 ^subagent-）
#   · check_alias_resolution 折入 subagent- 保留前缀守卫（canonical id 与 alias 都查）
#
# 断言编号 ↔ PRD/QA 清单 T1–T10：
#   T1  status 汇总计数=2 且不列具体名 + 角色区不误报在线
#   T2  父 pane + 子代理共用 tmuxPane ⇒ 父 pane 存活（危险夹具成立且不被误伤）
#   T3  close subagent-qa-<id> ⇒ rc≠0 + 输出含 subagent-/pi-subagents + 父 pane 存活
#   T4  close subagent-chat-<id18> ⇒ 同上
#   T5  close --task <唯一号> qa（父+子在场）不触父 pane
#   T6  正控 close qa 正常回收父 pane
#   T7  ensure 负向（仅子代理不判「已在运行」）+ 正控（精确 qa 判「已在运行」）
#   T8  E2：未认领 comm=pi pane + 名册仅有以其 tmuxPane 为值的 subagent-* 条目 ⇒ 仍告警
#   T9  前缀边界：subagentfoo/mysubagent-x 不入排除面且 close 文案形态不同；qa-subagent-x 仍入派生区
#   T10 check 守卫：构造非法 roles.yaml ⇒ rc≠0
#
# 夹具纪律（BR9）：真 tmux 隔离 socket（≠ 生产默认候选）+ env -u TMUX -u TMUX_PANE +
#   假名册逐字段一行 pretty-print（探针 JSON.stringify(...,null,2)；紧凑 JSON 会被名册解析贪婪匹配
#   只取末条）+ 收尾走机制 cleanup -S；桩 pi 用**复制**的 sleep 二进制（exec 会丢 comm=pi）。
#   T529：status/close 需在 tmux 内 —— 用隔离 socket 作 $TMUX（见 $FTMUX）。
#   能力门：tmux 缺 ⇒ t4_skip；tsx 缺 ⇒ t4_degrade（T10 等纯 bash 断言照跑）。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

BASH_BIN="$(command -v bash)"
REAL_PATH="$PATH"
REAL_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

# ---- 能力门 1：tmux（T2–T6/T8 为真 tmux 实验；缺则整例 SKIP）----
command -v tmux >/dev/null 2>&1 \
  || t4_skip "环境缺少 tmux（T525 需真 tmux 隔离 socket 证明父 pane 存活 + E2 孤儿 pane）"

# ---- 夹具路径 + 硬护栏（先于一切 tmux 操作）----
LAB="$T4_CACHE_DIR/lab"
STUBBIN="$LAB/bin"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
# T529：ensure/status/close 只接受「tmux 内」。tmux 客户端优先按 $TMUX 里的 socket 路径连接
#   ⇒ 用隔离 socket 作 $FTMUX 既过入口闸门、又仍落在夹具 server（不碰生产默认 server）。
FTMUX="$SOCK,0,0"
GUARD=0
_TM="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${_TM%%,*}"; do
  [ -n "$p" ] && [ "$SOCK" = "$p" ] && GUARD=1
done
[[ "$SOCK" == "$LAB"/* ]] || GUARD=1
if [ "$GUARD" != 0 ]; then
  t4_bad "护栏触发：夹具 SOCK=$SOCK 不在 \$LAB 下或与生产默认候选冲突"
  t4_exit
fi

# ---- 能力门 2：tsx（名册探针夹具）；缺 ⇒ 名册注入组 DEGRADE，T10 纯 bash 照跑 ----
TSX_OK=0
if [ -f "$REAL_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then
  TSX_OK=1
fi

# ---- 收尾：EXIT trap 链（先机制 cleanup -S，再复刻 lib 缓存清理语义；BR5 保真退出码）----
t525_teardown() {
  [ -n "${SOCK:-}" ] && [ -d "$LAB" ] || return 0
  ( cd "$LAB" 2>/dev/null || cd /tmp
    env -u TMUX "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$SOCK" >/dev/null 2>&1 ) || true
  return 0
}
t525_exit_trap() {
  local rc=$?
  t525_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t525_exit_trap EXIT

# ---- 夹具构造 ----
mkdir -p "$LAB" "$STUBBIN" "$SOCKDIR/tmux-$(id -u)"
chmod 700 "$SOCKDIR/tmux-$(id -u)"                 # tmux 3.7+ 校验默认 socket 目录权限（0700）
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
# 名册假探针（只读 env；绝不接触真实 pi-intercom 名册/broker）；pretty-print 逐字段一行
cat > "$LAB/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
cp "$(command -v sleep)" "$STUBBIN/pi" && chmod +x "$STUBBIN/pi" \
  || { t4_bad "桩 pi（复制二进制保 comm=pi）失败"; t4_exit; }
LAB_BASE="$(basename "$LAB")"

# ---- 调用 / 观察封装 ----
RC=0; OUT=""
run_fleet() {  # <roster-json> <fleet 参数...>；$TMUX 指向隔离 server（T529 唯一运行前提）
  local roster="$1"; shift
  local of="$LAB/out.$$"
  ( cd "$LAB" && timeout 90 env -u TMUX_PANE TMUX="$FTMUX" \
      TMUX_TMPDIR="$SOCKDIR" \
      NAO_SKILLS="$LAB" NAO_TASKS_STATE="$LAB/.no-tasks-state.md" \
      PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER="$roster" \
      PATH="$STUBBIN:$REAL_PATH" \
      "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" "$@" ) >"$of" 2>&1
  RC=$?
  OUT="$(cat "$of")"; rm -f "$of"
}
run_check() {  # <fixture-root> [额外 fleet 参数，如 -v]
  local fx="$1"; shift
  local of="$LAB/check.$$"
  ( cd "$fx" && env -u TMUX NAO_SKILLS="$fx" \
      timeout 60 "$BASH_BIN" "$fx/.agents/scripts/nao-fleet.sh" check "$@" ) >"$of" 2>&1
  RC=$?
  OUT="$(cat "$of")"; rm -f "$of"
}
mk_session() { printf '{"name":"%s","cwd":"%s","tmuxPane":"%s","status":"%s"}' "$1" "$2" "$3" "$4"; }
roster() { local s="[" e; for e in "$@"; do s="$s$e,"; done; printf '%s' "${s%,}]"; }
TX() { tmux -S "$SOCK" "$@"; }
pane_alive() { TX list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF -- "$1"; }
assert_pane_alive() { if pane_alive "$1"; then t4_ok "$2"; else t4_bad "$2（pane $1 已消失）"; fi; }
assert_pane_dead()  { if pane_alive "$1"; then t4_bad "$2（pane $1 仍存活）"; else t4_ok "$2"; fi; }
tx_parent() {  # fresh server + 一个标题契约为 π - qa - <lab> 的父 pane；echo pane_id
  t525_teardown; sleep 0.2
  TX new-session -d -s fx -x 220 -y 50 -c "$LAB" >/dev/null 2>&1 || return 9
  sleep 0.3
  TX set-option -g automatic-rename off >/dev/null 2>&1 || true
  TX set-option -g allow-rename off >/dev/null 2>&1 || true
  local p
  p="$(TX list-panes -t fx -F '#{pane_id}' | head -1)"
  TX select-pane -t "$p" -T "π - qa - $LAB_BASE" >/dev/null 2>&1 || true
  printf '%s' "$p"
}

SUB1="subagent-qa-aaa$$"
SUB2="subagent-chat-bbb$$"

# ============================================================ 名册注入组（T1–T9，需 tsx）
if [ "$TSX_OK" = "1" ]; then

  # ---------------------------------------------------------------- T1 汇总行
  R_SUB="$(roster "$(mk_session "$SUB1" "$LAB" "" idle)" "$(mk_session "$SUB2" "$LAB" "" idle)")"
  run_fleet "$R_SUB" status
  t4_assert_eq "0" "$RC" "T1 status rc=0"
  t4_assert_contains "$OUT" "另有 2 个子代理会话（subagent-*）· 生命周期由 pi-subagents 管理，nao 不回收" \
    "T1 汇总行逐字措辞 + 计数=2"
  t4_assert_not_contains "$OUT" "$SUB1" "T1 不列具体子代理名（subagent-qa-<id>）"
  t4_assert_not_contains "$OUT" "$SUB2" "T1 不列具体子代理名（subagent-chat-<id18>）"
  t4_assert_match "$OUT" '· qa +未运行' "T1 角色区 qa 不误报在线"
  t4_assert_not_contains "$OUT" "✓ qa" "T1 角色区无「✓ qa」"

  # ---------------------------------------------------------------- T7 ensure 前提负控（T529）
  # 非 tmux ⇒ 入口闸门直接 exit 3（不建 pane/lock、不写状态）；子代理在场也绝不构成「已在运行」假成功。
  FTMUX_SAVE="$FTMUX"; FTMUX=""
  run_fleet "$R_SUB" ensure qa
  FTMUX="$FTMUX_SAVE"
  t4_assert_eq "3" "$RC" "T7 负向：非 tmux ⇒ ensure exit 3（前提不满足，不假成功）"
  t4_assert_not_contains "$OUT" "已在运行" "T7 负向：不得判「已在运行」"
  t4_assert_not_contains "$OUT" "已拉起" "T7 负向：不得报「已拉起」"

  # ---------------------------------------------------------------- T2/T3/T4 父 pane 存活
  P="$(tx_parent)"; rc9=$?
  t4_assert_eq "0" "$rc9" "T2 夹具：父 pane 建立（fresh 隔离 server）"
  R_PARENT="$(roster "$(mk_session qa "$LAB" "$P" idle)" \
                      "$(mk_session "$SUB1" "$LAB" "$P" idle)" \
                      "$(mk_session "$SUB2" "$LAB" "$P" idle)")"
  t4_assert_match "$R_PARENT" "\"tmuxPane\":\"$P\"" "T2 危险夹具成立：父+子代理共用同一 tmuxPane"
  run_fleet "$R_PARENT" close "$SUB1"
  t4_assert_ne "0" "$RC" "T3 close $SUB1 ⇒ rc≠0（显式拒绝）"
  t4_assert_contains "$OUT" "subagent-" "T3 文案点名 subagent-"
  t4_assert_contains "$OUT" "pi-subagents" "T3 文案点名 pi-subagents"
  t4_assert_contains "$OUT" "不归 nao 回收" "T3 说明子代理生命周期不归 nao"
  assert_pane_alive "$P" "T2/T3 父 pane 存活（拒绝分支绝不触 pane）"
  run_fleet "$R_PARENT" close "$SUB2"
  t4_assert_ne "0" "$RC" "T4 close $SUB2 ⇒ rc≠0（显式拒绝）"
  t4_assert_contains "$OUT" "pi-subagents" "T4 文案点名 pi-subagents"
  assert_pane_alive "$P" "T4 父 pane 仍存活"

  # ---------------------------------------------------------------- T5 close --task（合法派生，不误杀）
  run_fleet "$R_PARENT" close --task "T4C15X$$" qa
  t4_assert_eq "0" "$RC" "T5 close --task <唯一号> qa ⇒ rc=0（走正常路径）"
  t4_assert_contains "$OUT" "未运行（无需回收）" "T5 走正常「未运行（无需回收）」出口"
  assert_pane_alive "$P" "T5 不触父 pane"

  # ---------------------------------------------------------------- T6 正控 close qa
  run_fleet "$R_PARENT" close qa
  t4_assert_eq "0" "$RC" "T6 正控：close qa 正常回收父 pane（rc=0）"
  t4_assert_contains "$OUT" "已回收 qa" "T6 日志含「已回收 qa」"
  assert_pane_dead "$P" "T6 父 pane 已被回收"

  # ---------------------------------------------------------------- T8 E2 孤儿 pane 非静默
  t525_teardown; sleep 0.2
  TX new-session -d -s e2 -x 220 -y 50 -c "$LAB" "$STUBBIN/pi" 600 >/dev/null 2>&1
  sleep 0.5
  ORA="$(TX list-panes -t e2 -F '#{pane_id}' | head -1)"
  TX set-option -g automatic-rename off >/dev/null 2>&1 || true
  TX select-pane -t "$ORA" -T "t8-orphan" >/dev/null 2>&1 || true
  sleep 0.2
  t4_assert_eq "pi" "$(TX list-panes -t e2 -F '#{pane_current_command}' | head -1)" \
    "T8 夹具：pane 当前命令为 pi（复制二进制保 comm=pi）"
  SUB8="subagent-qa-zzz$$"
  R_E2="$(roster "$(mk_session "$SUB8" "$LAB" "$ORA" idle)")"
  run_fleet "$R_E2" status
  t4_assert_contains "$OUT" "无法归属会话名" "T8 E2：仅被子代理 tmuxPane 认领的孤儿 pi pane 仍告警（非静默）"
  t4_assert_contains "$OUT" "$ORA" "T8 告警点名孤儿 pane"
  t4_assert_contains "$OUT" "另有 1 个子代理会话" "T8 汇总计数=1"

  # ---------------------------------------------------------------- T9 前缀边界
  SUBFOO="subagentfoo"; MYSUB="mysubagent-x"; QASUB="qa-subagent-x"
  R_T9="$(roster "$(mk_session "$SUBFOO" "$LAB" "" idle)" \
                  "$(mk_session "$MYSUB" "$LAB" "" idle)" \
                  "$(mk_session "$QASUB" "$LAB" "" idle)")"
  run_fleet "$R_T9" status
  t4_assert_not_contains "$OUT" "另有" "T9 前缀边界：subagentfoo/mysubagent-x 不入排除面（无汇总行）"
  t4_assert_contains "$OUT" "$QASUB" "T9 正控：qa-subagent-x 仍列入派生区"
  run_fleet "$R_T9" close "$SUBFOO"
  t4_assert_ne "0" "$RC" "T9 close subagentfoo ⇒ rc≠0"
  t4_assert_contains "$OUT" "未知角色或派生会话名" "T9 subagentfoo 走通用未知名文案"
  t4_assert_not_contains "$OUT" "pi-subagents" "T9 subagentfoo 不得被归类为 subagent-*"
  run_fleet "$R_T9" close "$MYSUB"
  t4_assert_ne "0" "$RC" "T9 close mysubagent-x ⇒ rc≠0"
  t4_assert_not_contains "$OUT" "pi-subagents" "T9 mysubagent-x 不得被归类为 subagent-*"
  run_fleet "$R_T9" close --task subagent-x qa
  t4_assert_not_contains "$OUT" "pi-subagents" "T9 close --task subagent-x qa 不得命中 subagent- 拒绝面"
  t4_assert_not_contains "$OUT" "以 subagent- 开头" "T9 同上（check 守卫形态也不得出现）"
else
  t4_degrade "缺 tsx/node（$REAL_AGENT_DIR/npm/node_modules/tsx）⇒ T1–T9 名册注入组能力降级（默认豁免、full 计分）；T10 纯 bash 断言照跑"
fi

# ============================================================ T10 check 守卫（纯 bash）
run_check "$T4_ROOT" -v
t4_assert_eq "0" "$RC" "T10 正控：合法 roles.yaml ⇒ check rc=0"
t4_assert_contains "$OUT" "无 subagent- 保留前缀" "T10 正控：成功行含「+ 无 subagent- 保留前缀」"

FXA="$LAB/checkfx-a"
rm -rf "$FXA"; mkdir -p "$FXA"
cp -r "$T4_ROOT/.agents" "$FXA/.agents"
sed -i 's/^    aliases: \[qa\]$/    aliases: [qa, subagent-x]/' "$FXA/.agents/roles.yaml"
t4_assert_contains "$(cat "$FXA/.agents/roles.yaml")" "subagent-x" "T10 夹具：别名 subagent-x 已注入"
run_check "$FXA"
t4_assert_ne "0" "$RC" "T10a alias 以 subagent- 开头 ⇒ check rc≠0"
t4_assert_contains "$OUT" "角色 id/别名 subagent-x 以 subagent- 开头（该前缀保留给 pi-subagents 子代理会话，nao 不接管）" \
  "T10a 失败文案逐字"

FXB="$LAB/checkfx-b"
rm -rf "$FXB"; mkdir -p "$FXB"
cp -r "$T4_ROOT/.agents" "$FXB/.agents"
printf '\n  subagent-y:\n    aliases: [subagent-y]\n    card: test-engineer.md\n    workspace: .\n' \
  >> "$FXB/.agents/roles.yaml"
t4_assert_contains "$(cat "$FXB/.agents/roles.yaml")" "subagent-y" "T10 夹具：canonical id subagent-y 已注入"
run_check "$FXB"
t4_assert_ne "0" "$RC" "T10b canonical id 以 subagent- 开头 ⇒ check rc≠0"
t4_assert_contains "$OUT" "角色 id/别名 subagent-y 以 subagent- 开头" "T10b 失败文案"

t4_exit
