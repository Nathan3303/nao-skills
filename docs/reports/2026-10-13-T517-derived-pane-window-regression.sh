#!/usr/bin/env bash
# =============================================================================
# T517 独立断言脚本 —— 派生会话 tmux 落点：宿主窗口显式寻址（AC1–AC5）
#
# 判据来源（唯一）：docs/prds/2026-10-13-t517-derived-pane-window.md
#   §四 用户场景 · §五 业务规则 · §七 AC1–AC5（AC9 全范围回归属实施后的独立验收轮）
# 方法参照：docs/reports/2026-10-12-T513-verify.sh（AC7 几何 golden 实测口径）
#           docs/reports/2026-10-13-T516-close-anchor-regression.sh（隔离 socket 安全纪律）
# 被测：<root>/.agents/scripts/nao-fleet.sh（**本脚本不修改机制源码/测试/构建配置**）
#
# 覆盖（与 AC 逐条映射）：
#   AC1 单窗口零回归：152x34 单窗口 + 有效 TMUX_PANE ⇒ 新 pane 落该窗口；
#                     main-row2/main-col/grid 几何逐值等于 T513-AC7 golden
#   AC2 缺陷修复（无 client，核心）：session current window=W2、调用者 pane 在 W1
#                     ⇒ 新 pane 必须落 W1；负向：W2 pane 数与 window_layout 均未变化
#   AC3 缺陷修复（有 client）：attach 假 client 且视图切 W2 ⇒ 仍落 W1、W2 几何不变
#   AC4 布局/选项不外溢：layout + 几何落 W1（main-col golden）；W1 main-pane-width=35%；
#                     W2 main-pane-width 前后一致、W2 layout 不变
#   AC5 边界/负向：a) NAO_TMUX_HOST_WINDOW 指向已关闭窗口 ⇒ warn、W2 不被污染、rc 不劣化
#                  b) TMUX 已设但 TMUX_PANE 空 ⇒ 明确降级（warn，不静默）
#                  c) 跨 session（调用 pane 在 A、client 视图在 B）⇒ 落 A 的窗口、B 不变
#                  d) 宿主窗口极窄（W1=80、W2=152）⇒ 窄列守卫按宿主窗口宽生效，几何 = 80 列 golden
#   AC6 幂等：连跑 2 次 ensure（第 2 次命中 running 跳过；--force +1 且布局收敛 golden）
#   AC7 同源：常驻 ensure 与 --task 派生在 AC2/AC4 场景行为一致（无人工分叉）
#
# 实验纪律（T515/T516 血训，硬约束）：
#   - 全程 `env -u TMUX` 运行；一切 tmux 命令显式 `-S <隔离 socket>`；
#   - 收尾/重置一律经机制自有 `nao-fleet.sh cleanup -S <隔离 socket>`（不裸 kill-server）；
#   - 硬护栏：夹具 socket 必须落在 $LAB 下且 ≠ 全部生产默认候选（常量独立复算）；
#   - 夹具 = sleep 桩 pi（不派生真实 pi），名册走夹具内嵌假探针（不读取/污染真实名册）。
#
# 用法：
#   env -u TMUX bash docs/reports/2026-10-13-T517-derived-pane-window-regression.sh
#   env -u TMUX bash docs/reports/2026-10-13-T517-derived-pane-window-regression.sh --only AC2,AC4
#   env -u TMUX bash docs/reports/2026-10-13-T517-derived-pane-window-regression.sh --t4
#   KEEP=1 保留夹具（默认清理）
#   T517_FLEET=<path> 用指定 nao-fleet.sh 作为被测脚本（默认仓内脚本）——仅用于
#     复现「修复前基线」（如 git show <pre-fix>:… > /tmp/pre.sh 后指向它）
#
# 退出码：0 = 全过；1 = 有 FAIL；2 = 脚本自身环境错误（护栏/前置缺失）
#   --t4（tests/t4 case 兼容口径）：0 = 全过；1 = 有 FAIL；77 = 全 SKIP
# =============================================================================
set -u

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"
FLEET="$ROOT/.agents/scripts/nao-fleet.sh"
BASH_BIN="$(command -v bash)"
REAL_PATH="$PATH"
REAL_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

T4_MODE=0; ONLY=""; KEEP="${KEEP:-0}"
for a in "$@"; do
  case "$a" in
    --t4) T4_MODE=1 ;;
    --only) : ;;                                   # 值随下一个参数
    --only=*) ONLY="${a#--only=}" ;;
    *) [[ "${prev:-}" == "--only" ]] && ONLY="$a" ;;
  esac
  prev="$a"
done

if [[ -n "${TMUX:-}" ]]; then
  echo "警告：检测到 \$TMUX=$TMUX —— 本脚本一切 tmux 调用均显式 -S，仍建议在 tmux 外运行（纪律见头注）" >&2
fi
[[ -f "$FLEET" ]] || { echo "未找到被测脚本: $FLEET" >&2; exit 2; }
if ! command -v tmux >/dev/null 2>&1; then
  (( T4_MODE )) && { echo "SKIP: 环境缺少 tmux（AC1–AC5 均为真 tmux 实验）" >&2; exit 77; }
  echo "环境缺少 tmux，无法执行（AC1–AC5 均为真 tmux 实验）" >&2; exit 2
fi

# ---- 夹具路径 + 硬护栏（先于一切 tmux 操作）--------------------------------
LAB="${T517_LAB:-/tmp/t517-reg}"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
GUARD=0
_TM="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${_TM%%,*}"; do
  [[ -n "$p" && "$SOCK" == "$p" ]] && GUARD=1
done
[[ "$SOCK" == "$LAB"/* ]] || GUARD=1
if (( GUARD )); then
  echo "护栏触发：夹具 SOCK=$SOCK 与生产默认 socket 候选冲突或不在 \$LAB 下 ⇒ 拒绝运行（exit 2）" >&2
  exit 2
fi

# ---- 计数/输出 --------------------------------------------------------------
P=0; F=0; SK=0
ok(){   P=$((P+1));  printf '  PASS  %s\n' "$1"; }
bad(){  F=$((F+1));  printf '  FAIL  %s\n' "$1"; }
skip(){ SK=$((SK+1)); printf '  SKIP  %s\n' "$1"; }
sec(){  printf '\n== %s ==\n' "$*"; }
only_match(){ [[ -z "$ONLY" ]] && return 0; [[ ",$ONLY," == *",$1,"* ]]; }
strip_ansi(){ sed 's/\x1b\[[0-9;]*m//g'; }
oneline(){ strip_ansi <<< "${1:-}" | tr '\n' '|' | cut -c1-300; }
# 可观测诊断计数：含 [fleet] 前缀但非良性 log（CodeGraph 索引 / 已拉起 / 已创建）的行数。
# 对 warn 的着色方式不敏感（rd-infra 降级说明曾以纯文本 [fleet] 前缀输出），只判「有诊断、不静默」。
diag_n(){ strip_ansi <<< "${1:-}" | grep '\[fleet\]' | grep -vcE 'CodeGraph|已拉起|已创建|已终结|幂等清理' || true; }

# ---- 夹具构造 --------------------------------------------------------------
STUBBIN="$LAB/bin"; FIXHOME="$LAB/home"
TX(){ tmux -S "$SOCK" "$@"; }
cleanup_fleet(){ ( cd "$LAB" 2>/dev/null || cd /tmp; env -u TMUX "$BASH_BIN" "$FLEET" cleanup -S "$SOCK" >/dev/null 2>&1 || true ); }
CLIENT_PIDS=()
teardown(){
  local p
  for p in "${CLIENT_PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null || true; done
  [[ -d "$LAB" ]] && cleanup_fleet
  if [[ "$KEEP" == 1 ]]; then printf '\n（KEEP=1：夹具保留于 %s）\n' "$LAB"; return 0; fi
  rm -rf "$LAB"
}
trap teardown EXIT

setup_lab(){
  rm -rf "$LAB"
  mkdir -p "$SOCKDIR/tmux-$(id -u)" "$STUBBIN" "$FIXHOME" "$LAB/.codegraph"
  chmod 700 "$SOCKDIR/tmux-$(id -u)"     # tmux 3.7+ 校验默认 socket 目录权限（0700）
  cp -r "$ROOT/.agents/." "$LAB/.agents/" || { echo "夹具复制失败" >&2; exit 2; }
  # 基线复现：允许用修复前的 nao-fleet.sh 替换夹具内被测脚本（默认 = 仓内当前脚本）
  if [[ -n "${T517_FLEET:-}" ]]; then
    [[ -f "$T517_FLEET" ]] || { echo "T517_FLEET 不存在: $T517_FLEET" >&2; exit 2; }
    cp "$T517_FLEET" "$LAB/.agents/scripts/nao-fleet.sh"
  fi
  # 名册假探针（只读 env；绝不接触真实 pi-intercom 名册/broker）
  cat > "$LAB/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
  # 桩 pi（spawn 的 pane 只 sleep，不拉起真实 pi）
  printf '#!/bin/bash\nexec sleep 600\n' > "$STUBBIN/pi"; chmod +x "$STUBBIN/pi"
  # 桩 codegraph（消除 check_codegraph 的黄色 warn 噪声 ⇒ warn 计数只反映被测逻辑）
  printf '#!/bin/bash\necho "Index is up to date"\n' > "$STUBBIN/codegraph"; chmod +x "$STUBBIN/codegraph"
  # 派生 pane 走 `bash -lc` ⇒ 经 .bash_profile 把桩目录置于 PATH 前
  printf 'export PATH=%q\n' "$STUBBIN:$REAL_PATH" > "$FIXHOME/.bash_profile"
}
setup_lab

# ---- 被测调用 --------------------------------------------------------------
OUT=""; RC=0
EXTRA_ENV=()                       # 可选附加 env（如 NAO_TMUX_HOST_WINDOW）
FAKE_ROSTER='[]'                   # 名册桩内容（AC6 模拟已注册会话用于判重跳过）
TMUX_LAYOUT="main-row2"; TMUX_MAIN_WIDTH=35; TMUX_MIN_PANE_WIDTH=30
run_fleet(){ # $1=TMUX 值 $2=TMUX_PANE（空=不设）; 其余= fleet 参数
  # 经临时文件取输出（而非 $(...)）：机制内 `(sleep 60; rm prompt)&` 会占住命令替换管道 ⇒ 单次必然阻塞 60s
  local tm="$1" tp="$2"; shift 2
  local -a opts=( -u TMUX_TMPDIR ) assigns=( "TMUX=$tm" )
  if [[ -n "$tp" ]]; then assigns+=( "TMUX_PANE=$tp" ); else opts+=( -u TMUX_PANE ); fi
  local of="$LAB/out.$$"
  ( cd "$LAB" && timeout 90 env "${opts[@]}" "${assigns[@]}" \
      NAO_SKILLS="$LAB" NAO_TASKS_STATE="$LAB/.no-tasks-state.md" \
      PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER="$FAKE_ROSTER" \
      PATH="$STUBBIN:$REAL_PATH" HOME="$FIXHOME" \
      NAO_TMUX_LAYOUT="$TMUX_LAYOUT" NAO_TMUX_MAIN_WIDTH="$TMUX_MAIN_WIDTH" NAO_TMUX_MIN_PANE_WIDTH="$TMUX_MIN_PANE_WIDTH" \
      ${EXTRA_ENV[@]+"${EXTRA_ENV[@]}"} \
      "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" "$@" ) >"$of" 2>&1
  RC=$?
  OUT="$(cat "$of")"; rm -f "$of"
}

# ---- tmux 观察/夹具会话 ----------------------------------------------------
TMUX_ENV=""
new_server(){ # $1=W $2=H [narrow：设置 manual]；打印调用方 pane
  cleanup_fleet; sleep 0.2
  TX new-session -d -s fx -x "$1" -y "$2" -c "$LAB" >/dev/null 2>&1 || return 9
  sleep 0.4
  TMUX_ENV="$SOCK,$(TX display -p '#{pid}'),$(TX display -p '#{session_id}')"
  W1="$(TX display-message -t fx -p '#{window_id}')"
  CALLER="$(TX list-panes -t "$W1" -F '#{pane_id}' | head -1)"
}
add_window(){ # 新建窗口并使其成为 session current window；打印其 window_id
  TX new-window -t fx: -c "$LAB" >/dev/null 2>&1 || return 9
  sleep 0.3
  TX display-message -t fx -p '#{window_id}'
}
geo(){ TX list-panes -t "$1" -F '#{pane_index}:#{pane_width}x#{pane_height}@#{pane_left},#{pane_top}' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//'; }
np(){ TX list-panes -t "$1" -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' '; }
wl(){ TX display-message -t "$1" -p '#{window_layout}' 2>/dev/null; }
wopt(){ TX show-window-options -t "$1" -v main-pane-width 2>/dev/null; }
pane_count_in(){ TX list-panes -a -F '#{window_id}' 2>/dev/null | grep -cxF -- "$1"; }

# T513-AC7 几何 golden（本轮单窗口零回归与宿主窗口布局的逐值基准）
GEO_MAINROW2_152_N4='1:52x34@0,0 2:49x16@53,0 3:49x17@53,17 4:49x34@103,0'
GEO_MAINCOL_152_N4='1:52x34@0,0 2:99x11@53,0 3:99x11@53,12 4:99x10@53,24'
GEO_GRID_152_N4='1:75x16@0,0 2:76x16@76,0 3:75x17@0,17 4:76x17@76,17'
GEO_MAINROW2_80_N6='1:27x34@0,0 2:52x6@28,0 3:52x6@28,7 4:52x6@28,14 5:52x6@28,21 6:52x6@28,28'

# ---- 假 client（AC3/AC5c 用；无 pty 能力时该 AC 记 SKIP，不误报 PASS）-------
start_client(){ # $1=session；成功=0
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$SOCK" "$1" <<'PY' >/dev/null 2>&1 &
import pty, os, sys, time
sock, sess = sys.argv[1], sys.argv[2]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("tmux", ["tmux", "-S", sock, "attach", "-t", sess])
time.sleep(120)
PY
  CLIENT_PIDS+=("$!")
  local i=0
  while (( i++ < 40 )); do
    [[ -n "$(TX list-clients -F '#{client_name}' 2>/dev/null | head -1)" ]] && return 0
    sleep 0.25
  done
  return 1
}
client_name(){ TX list-clients -F '#{client_name}' 2>/dev/null | head -1; }

# =============================================================================
sec "AC1 单窗口零回归（真 tmux 隔离 socket + 桩 pi；几何 golden = T513-AC7）"
if only_match AC1; then
  ac1(){ # $1=layout $2=golden
    TMUX_LAYOUT="$1"
    new_server 152 34 || { bad "AC1 $1：隔离 server 创建失败"; return; }
    run_fleet "$TMUX_ENV" "$CALLER" ensure --force pm arch-designer rd-fe
    local g; g="$(geo "$W1")"
    if [[ "$RC" == 0 && "$(np "$W1")" == 4 && "$g" == "$2" ]]; then
      ok "AC1 $1：单窗口 pane=4 几何逐值一致"
    else
      bad "AC1 $1：零回归漂移（rc=$RC pane=$(np "$W1") 期望「$2」实际「$g」）"
    fi
    # 新 pane 必须全部落在唯一窗口内（无外溢）
    if [[ "$(pane_count_in "$W1")" == 4 ]]; then ok "AC1 $1：全部 pane 在该窗口（无外溢）"; else bad "AC1 $1：pane 外溢（W1 计数 $(pane_count_in "$W1")）"; fi
  }
  ac1 main-row2 "$GEO_MAINROW2_152_N4"
  ac1 main-col  "$GEO_MAINCOL_152_N4"
  ac1 grid      "$GEO_GRID_152_N4"
fi

# =============================================================================
sec "AC2 缺陷修复（无 client，核心）：session current window=W2、调用者 pane 在 W1"
if only_match AC2; then
  TMUX_LAYOUT="main-row2"
  new_server 152 34 || bad "AC2：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC2：新建 W2 失败"
  BEFORE_W1="$(TX list-panes -t "$W1" -F '#{pane_id}' | sort)"
  LAY_W2_BEFORE="$(wl "$W2")"
  N_W2_BEFORE="$(np "$W2")"
  CURRENT="$(TX display-message -t fx -p '#{window_id}')"
  if [[ "$CURRENT" == "$W2" && "$CALLER" == "$(TX list-panes -t "$W1" -F '#{pane_id}' | head -1)" ]]; then
    ok "AC2 夹具前置：current window=W2（$W2）、调用者 pane=$CALLER 在 W1（$W1）"
  else
    bad "AC2 夹具前置不成立（current=$CURRENT W2=$W2 caller=$CALLER W1=$W1）"
  fi
  run_fleet "$TMUX_ENV" "$CALLER" ensure --force pm arch-designer rd-fe
  NEW="$(comm -13 <(printf '%s\n' "$BEFORE_W1") <(TX list-panes -t "$W1" -F '#{pane_id}' | sort) | grep . || true)"
  # 正向：新 pane 落 W1（3 个）
  if [[ "$(printf '%s\n' "$NEW" | grep -c .)" == 3 && "$(np "$W1")" == 4 ]]; then
    ok "AC2 新 pane 全部落 §宿主窗口 W1（1→4；new=$(printf '%s' "$NEW" | tr '\n' ' ')）"
  else
    bad "AC2 新 pane 未落 W1（rc=$RC W1 计数=$(np "$W1")；$(oneline "$OUT")）"
  fi
  # 负向：W2 pane 数与 window_layout 均未变化
  if [[ "$(np "$W2")" == "$N_W2_BEFORE" ]]; then ok "AC2 负向：W2 pane 数未变（$N_W2_BEFORE）"; else bad "AC2 负向：W2 pane 数变化 $N_W2_BEFORE→$(np "$W2")（缺陷复现：拆了用户窗口）"; fi
  if [[ "$(wl "$W2")" == "$LAY_W2_BEFORE" ]]; then ok "AC2 负向：W2 window_layout 未变"; else bad "AC2 负向：W2 layout 变化「$LAY_W2_BEFORE」→「$(wl "$W2")」"; fi
fi

# =============================================================================
sec "AC3 缺陷修复（有 client，视图在 W2）"
if only_match AC3; then
  TMUX_LAYOUT="main-row2"
  new_server 152 34 || bad "AC3：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC3：新建 W2 失败"
  if start_client fx; then
    CN="$(client_name)"
    TX switch-client -c "$CN" -t "$W2" >/dev/null 2>&1 || TX select-window -t "$W2" >/dev/null 2>&1 || true
    sleep 0.4
    VIEW="$(TX display-message -p -t "$CN" '#{window_id}' 2>/dev/null)"
    if [[ "$VIEW" != "$W2" ]]; then
      skip "AC3 client 视图未切到 W2（view=${VIEW:-<空>}）—— 环境限制，交实施后验收轮复跑"
    else
      ok "AC3 夹具前置：client=$CN 视图=W2（$W2）、调用者 pane 在 W1（$W1）"
      LAY_W2_BEFORE="$(wl "$W2")"; N_W2_BEFORE="$(np "$W2")"
      run_fleet "$TMUX_ENV" "$CALLER" ensure --force pm arch-designer rd-fe
      if [[ "$(np "$W1")" == 4 ]]; then ok "AC3 有 client 仍落 W1（1→4）"; else bad "AC3 有 client 未落 W1（W1 计数=$(np "$W1")；$(oneline "$OUT")）"; fi
      if [[ "$(np "$W2")" == "$N_W2_BEFORE" && "$(wl "$W2")" == "$LAY_W2_BEFORE" ]]; then
        ok "AC3 负向：W2 pane 数（$N_W2_BEFORE）与 layout 均未变"
      else
        bad "AC3 负向：W2 变化（pane $N_W2_BEFORE→$(np "$W2")；layout「$LAY_W2_BEFORE」→「$(wl "$W2")」）"
      fi
    fi
  else
    skip "AC3 无 pty/python3 能力创建假 client —— 环境限制，交实施后验收轮复跑"
  fi
fi

# =============================================================================
sec "AC4 布局/选项不外溢（main-col：layout 落 W1、W2 main-pane-width 零变化）"
if only_match AC4; then
  TMUX_LAYOUT="main-col"
  new_server 152 34 || bad "AC4：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC4：新建 W2 失败"
  MPW_W2_BEFORE="$(wopt "$W2")"; LAY_W2_BEFORE="$(wl "$W2")"
  run_fleet "$TMUX_ENV" "$CALLER" ensure --force pm arch-designer rd-fe
  g="$(geo "$W1")"
  if [[ "$g" == "$GEO_MAINCOL_152_N4" ]]; then ok "AC4 布局作用于 W1：main-col 几何 = golden"; else bad "AC4 W1 几何漂移（期望「$GEO_MAINCOL_152_N4」实际「$g」）"; fi
  if [[ "$(wopt "$W1")" == "35%" ]]; then ok "AC4 W1 main-pane-width=35%（布局选项作用于宿主窗口）"; else bad "AC4 W1 main-pane-width 异常（实际「$(wopt "$W1")」）"; fi
  if [[ "$(wopt "$W2")" == "$MPW_W2_BEFORE" ]]; then ok "AC4 负向：W2 main-pane-width 前后一致（「${MPW_W2_BEFORE:-<空>}」）"; else bad "AC4 负向：W2 main-pane-width 泄漏 ${MPW_W2_BEFORE:-<空>}→$(wopt "$W2")"; fi
  if [[ "$(wl "$W2")" == "$LAY_W2_BEFORE" && "$(np "$W2")" == 1 ]]; then ok "AC4 负向：W2 layout 与 pane 数均未变"; else bad "AC4 负向：W2 变化（layout「$LAY_W2_BEFORE」→「$(wl "$W2")」 pane=$(np "$W2")）"; fi
fi

# =============================================================================
sec "AC5 边界/负向"
if only_match AC5; then
  # ---- AC5a 宿主窗口已关闭（显式覆盖指向不存在窗口）：warn + W2 不被污染 + rc 不劣化 ----
  TMUX_LAYOUT="main-row2"
  new_server 152 34 || bad "AC5a：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC5a：新建 W2 失败"
  N_W2_BEFORE="$(np "$W2")"; LAY_W2_BEFORE="$(wl "$W2")"
  EXTRA_ENV=( "NAO_TMUX_HOST_WINDOW=@99" )
  run_fleet "$TMUX_ENV" "$CALLER" ensure --force pm
  EXTRA_ENV=()
  if [[ "$RC" == 0 ]]; then ok "AC5a rc 语义不劣化（rc=0）"; else bad "AC5a rc=$RC（期望 0，pane 创建失败应 warn 而非失败整轮）"; fi
  if (( $(diag_n "$OUT") >= 1 )); then ok "AC5a 有可观测诊断（diag=$(diag_n "$OUT")，不静默）"; else bad "AC5a 无可观测诊断（$(oneline "$OUT")）"; fi
  if [[ "$(np "$W2")" == "$N_W2_BEFORE" && "$(wl "$W2")" == "$LAY_W2_BEFORE" ]]; then
    ok "AC5a 负向：宿主窗口已关不得回退拆用户窗口（W2 未变）"
  else
    bad "AC5a 负向：W2 被污染（pane $N_W2_BEFORE→$(np "$W2")；layout「$LAY_W2_BEFORE」→「$(wl "$W2")」）"
  fi

  # ---- AC5b TMUX 已设但 TMUX_PANE 空：明确降级 warn（不静默），rc 不劣化 ----
  new_server 152 34 || bad "AC5b：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC5b：新建 W2 失败"
  run_fleet "$TMUX_ENV" "" ensure --force pm
  if [[ "$RC" == 0 ]]; then ok "AC5b rc=0（语义不劣化）"; else bad "AC5b rc=$RC（期望 0）"; fi
  if (( $(diag_n "$OUT") >= 1 )) && grep -qE 'TMUX_PANE|降级|名册|HOST_WINDOW' <<< "$(strip_ansi <<< "$OUT")"; then
    ok "AC5b TMUX_PANE 空 ⇒ 明确降级（diag=$(diag_n "$OUT")，指名原因，不静默）"
  else
    bad "AC5b 静默降级或无原因诊断（diag=$(diag_n "$OUT")；$(oneline "$OUT")）"
  fi

  # ---- AC5c 跨 session：调用 pane 在 A、client 视图在 B ⇒ 落 A 的窗口、B 不变 ----
  cleanup_fleet; sleep 0.2
  if TX new-session -d -s sa -x 152 -y 34 -c "$LAB" >/dev/null 2>&1; then
    sleep 0.4
    A1="$(TX display-message -t sa -p '#{window_id}')"
    A_CALLER="$(TX list-panes -t "$A1" -F '#{pane_id}' | head -1)"
    TMUX_ENV_A="$SOCK,$(TX display -p '#{pid}'),$(TX display-message -t sa -p '#{session_id}')"
    if TX new-session -d -s sb -x 152 -y 34 -c "$LAB" >/dev/null 2>&1; then
      sleep 0.4
      B1="$(TX display-message -t sb -p '#{window_id}')"
      if start_client sb; then
        CN="$(client_name)"
        TX switch-client -c "$CN" -t "$B1" >/dev/null 2>&1 || true
        sleep 0.3
        N_B_BEFORE="$(np "$B1")"; LAY_B_BEFORE="$(wl "$B1")"
        run_fleet "$TMUX_ENV_A" "$A_CALLER" ensure --force pm arch-designer rd-fe
        if [[ "$(geo "$A1")" == "$GEO_MAINROW2_152_N4" ]]; then ok "AC5c 落调用者所在 session A 的窗口（几何 golden）"; else bad "AC5c 未落 A 窗口（A 计数=$(np "$A1") 几何「$(geo "$A1")」；$(oneline "$OUT")）"; fi
        if [[ "$(np "$B1")" == "$N_B_BEFORE" && "$(wl "$B1")" == "$LAY_B_BEFORE" ]]; then ok "AC5c 负向：client 视图 session B 的 pane 数与 layout 未变"; else bad "AC5c 负向：B 被污染（pane $N_B_BEFORE→$(np "$B1")；layout「$LAY_B_BEFORE」→「$(wl "$B1")」）"; fi
      else
        skip "AC5c 无 pty/python3 创建跨 session client —— 环境限制，交实施后验收轮复跑"
      fi
    else
      bad "AC5c：session B 创建失败"
    fi
  else
    bad "AC5c：session A 创建失败"
  fi

  # ---- AC5d 宿主窗口极窄（W1=80、W2=152）：窄列守卫按宿主宽生效 ----
  TMUX_LAYOUT="main-row2"
  cleanup_fleet; sleep 0.2
  if TX new-session -d -s fx -x 152 -y 34 -c "$LAB" >/dev/null 2>&1; then
    sleep 0.4
    TX set-option -t fx window-size manual >/dev/null 2>&1
    TMUX_ENV="$SOCK,$(TX display -p '#{pid}'),$(TX display -p '#{session_id}')"
    W1="$(TX display-message -t fx -p '#{window_id}')"
    TX resize-window -t "$W1" -x 80 -y 34 >/dev/null 2>&1
    CALLER="$(TX list-panes -t "$W1" -F '#{pane_id}' | head -1)"
    W2="$(add_window)" || bad "AC5d：新建 W2 失败"
    TX resize-window -t "$W2" -x 152 -y 34 >/dev/null 2>&1
    sleep 0.3
    if [[ "$(TX display-message -t "$W1" -p '#{window_width}')" == 80 ]]; then
      N_W2_BEFORE="$(np "$W2")"; LAY_W2_BEFORE="$(wl "$W2")"
      run_fleet "$TMUX_ENV" "$CALLER" ensure --force pm arch-designer rd-fe rd-be qa
      if [[ "$(geo "$W1")" == "$GEO_MAINROW2_80_N6" ]]; then ok "AC5d 窄列守卫按宿主窗口宽（W1=80）生效：几何 = 80 列 golden"; else bad "AC5d W1 几何漂移（期望「$GEO_MAINROW2_80_N6」实际「$(geo "$W1")」）"; fi
      if grep -qE '最窄列 [0-9]+ < 最小 [0-9]+ → 回退 main-col' <<< "$(strip_ansi <<< "$OUT")"; then ok "AC5d 窄列守卫 warn 指名回退 main-col"; else bad "AC5d 窄列守卫 warn 缺失（$(oneline "$OUT")）"; fi
      if [[ "$(np "$W2")" == "$N_W2_BEFORE" && "$(wl "$W2")" == "$LAY_W2_BEFORE" ]]; then ok "AC5d 负向：宽 W2 未被布局/新建污染"; else bad "AC5d 负向：W2 被污染（pane $N_W2_BEFORE→$(np "$W2")；layout「$LAY_W2_BEFORE」→「$(wl "$W2")」）"; fi
    else
      bad "AC5d 夹具前置失败：W1 宽=$(TX display-message -t "$W1" -p '#{window_width}')（期望 80；window-size manual 未生效？）"
    fi
  else
    bad "AC5d：隔离 server 创建失败"
  fi
fi

# =============================================================================
sec "AC6 幂等：2 次 ensure 第 2 次命中 running 跳过；--force +1 且布局收敛 golden（PRD §七 AC6）"
if only_match AC6; then
  TMUX_LAYOUT="main-row2"
  new_server 152 34 || bad "AC6：隔离 server 创建失败"
  FAKE_ROSTER='[]'
  # ① 首次 ensure（名册空 ⇒ 不判重）：2 角色 → W1 1→3（rc=0）
  run_fleet "$TMUX_ENV" "$CALLER" ensure pm arch-designer
  if [[ "$RC" == 0 && "$(np "$W1")" == 3 ]]; then ok "AC6 ① 首次 ensure：W1 1→3（rc=0）"; else bad "AC6 ① 首次 ensure（rc=$RC W1=$(np "$W1")；$(oneline "$OUT")）"; fi
  # 模拟 pi 上线注册（等价真实：名册 cwd=本仓 + tmuxPane=实际 pane，按创建序映射角色）
  newp="$(comm -13 <(printf '%s\n' "$CALLER") <(TX list-panes -t "$W1" -F '#{pane_id}' | sort) | grep . || true)"
  FAKE_ROSTER='[{"name":"pm","id":"pm","status":"idle","cwd":"'"$LAB"'","tmuxPane":"'"$(printf '%s\n' "$newp" | sed -n 1p)"'"},{"name":"arch-designer","id":"arch-designer","status":"idle","cwd":"'"$LAB"'","tmuxPane":"'"$(printf '%s\n' "$newp" | sed -n 2p)"'"}]'
  # ② 第 2 次 ensure（名册在线 ⇒ 命中 running 跳过）：pane 数不变、2 处「已在运行」
  N2="$(np "$W1")"
  run_fleet "$TMUX_ENV" "$CALLER" ensure pm arch-designer
  if [[ "$RC" == 0 && "$(np "$W1")" == "$N2" ]]; then ok "AC6 ② 第 2 次 ensure：命中 running 跳过（pane 不变 $N2，rc=0）"; else bad "AC6 ② 第 2 次未跳过（$N2→$(np "$W1")；$(oneline "$OUT")）"; fi
  nskip="$(strip_ansi <<< "$OUT" | grep -c '已在运行' || true)"
  if [[ "$nskip" == 2 ]]; then ok "AC6 ② 恰 2 处「已在运行」跳过诊断"; else bad "AC6 ②「已在运行」=$nskip（期望 2）"; fi
  # ③ --force：未注册角色（qa）真拉起 +1，布局收敛 4 pane golden（连跑后收敛性证明）
  N3_BEFORE="$(np "$W1")"
  run_fleet "$TMUX_ENV" "$CALLER" ensure --force qa
  G3="$(geo "$W1")"
  if [[ "$RC" == 0 && "$(np "$W1")" == "$((N3_BEFORE+1))" ]]; then ok "AC6 ③ --force：pane 数 +1（$N3_BEFORE→$((N3_BEFORE+1))）"; else bad "AC6 ③ --force 未 +1（$N3_BEFORE→$(np "$W1")）；$(oneline "$OUT") "; fi
  if [[ "$G3" == "$GEO_MAINROW2_152_N4" ]]; then ok "AC6 ③ --force 后布局收敛 golden（4 pane 几何逐值一致）"; else bad "AC6 ③ 布局未收敛 golden（期望「$GEO_MAINROW2_152_N4」实际「$G3」）"; fi
  FAKE_ROSTER='[]'
fi

# =============================================================================
sec "AC7 同源一致：常驻 ensure 与 --task 派生在 AC2/AC4 场景行为一致（无人工分叉）"
if only_match AC7; then
  # ① AC2 场景 + --task 派生：新 pane 落 W1、W2 不变、几何 = golden（与常驻 ensure 对照）
  TMUX_LAYOUT="main-row2"
  new_server 152 34 || bad "AC7 ①：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC7 ①：新建 W2 失败"
  LAY_W2_BEFORE="$(wl "$W2")"; N_W2_BEFORE="$(np "$W2")"
  run_fleet "$TMUX_ENV" "$CALLER" ensure --force --task T77 pm arch-designer rd-fe
  if [[ "$(geo "$W1")" == "$GEO_MAINROW2_152_N4" ]]; then ok "AC7 ① --task 派生落 W1 且几何 = golden（与 AC2 常驻一致）"; else bad "AC7 ① 派生落点/布局与常驻不一致（几何「$(geo "$W1")」；$(oneline "$OUT")）"; fi
  if [[ "$(np "$W2")" == "$N_W2_BEFORE" && "$(wl "$W2")" == "$LAY_W2_BEFORE" ]]; then ok "AC7 ① --task 派生未污染 W2（与 AC2 负向一致）"; else bad "AC7 ① 派生污染 W2（pane $N_W2_BEFORE→$(np "$W2")；layout「$LAY_W2_BEFORE」→「$(wl "$W2")」）"; fi
  # ② AC4 场景 + --task 派生：main-col 几何 + main-pane-width 落 W1、W2 选项不变（与常驻 ensure 对照）
  TMUX_LAYOUT="main-col"
  new_server 152 34 || bad "AC7 ②：隔离 server 创建失败"
  W2="$(add_window)" || bad "AC7 ②：新建 W2 失败"
  MPW_W2_BEFORE="$(wopt "$W2")"; LAY_W2_BEFORE="$(wl "$W2")"
  run_fleet "$TMUX_ENV" "$CALLER" ensure --force --task T77 pm arch-designer rd-fe
  if [[ "$(geo "$W1")" == "$GEO_MAINCOL_152_N4" && "$(wopt "$W1")" == "35%" ]]; then ok "AC7 ② --task 派生 main-col 几何 + main-pane-width 落 W1（与 AC4 常驻一致）"; else bad "AC7 ② 派生 main-col 不一致（几何「$(geo "$W1")」 mpw=「$(wopt "$W1")」）"; fi
  if [[ "$(wopt "$W2")" == "$MPW_W2_BEFORE" && "$(wl "$W2")" == "$LAY_W2_BEFORE" ]]; then ok "AC7 ② --task 派生未泄漏选项到 W2（与 AC4 负向一致）"; else bad "AC7 ② 派生泄漏到 W2（mpw「$MPW_W2_BEFORE」→「$(wopt "$W2")」）"; fi
fi

# ---- 汇总 ------------------------------------------------------------------
printf '\n== T517 派生会话落点回归汇总：PASS=%d FAIL=%d SKIP=%d ==\n' "$P" "$F" "$SK"
if (( F > 0 )); then exit 1; fi
if (( T4_MODE )) && (( P == 0 )); then exit 77; fi
exit 0
