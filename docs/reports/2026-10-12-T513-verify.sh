#!/usr/bin/env bash
# =============================================================================
# T513 独立断言脚本 —— 非 tmux 宿主的舰队派生（宿主阶梯 / 失败语义 / 非 tmux 句柄）
#
# 判据来源（唯一）：docs/prds/2026-10-12-non-tmux-host-spawn.md
#   §7 AC1–AC9 · §5 BR1–BR8 · §6 NFR1–NFR6；方法参照
#   docs/adr/2026-10-12-non-tmux-host-spawn.md（实施闸门判定式）与
#   docs/adr/2026-09-25-tmux-fleet-layout-modes.md（AC7 几何实测命令）。
# 被测：<root>/.agents/scripts/nao-fleet.sh（**本脚本不修改机制源码/测试/构建配置**）
#
# 用法:
#   bash docs/reports/2026-10-12-T513-verify.sh --baseline   # 基线体检（修复前；FA0 属预期，恒 exit 0）
#   bash docs/reports/2026-10-12-T513-verify.sh              # 修复后验收（有 FAIL 即 exit 1）
#   bash docs/reports/2026-10-12-T513-verify.sh --verify
#   bash docs/reports/2026-10-12-T513-verify.sh --root <dir> # 对任意树运行（如 git archive 的冻结基线）
#   bash docs/reports/2026-10-12-T513-verify.sh --only AC3,AC7
#   bash docs/reports/2026-10-12-T513-verify.sh --t4         # 以 tests/t4 case 兼容口径输出（exit 0/1/77/78）
#   KEEP=1 保留夹具（默认清理）
#
# 退出码: 0 = 无非预期 FAIL（--baseline/--t4 见下）；1 = FAIL；2 = 脚本自身环境错误
#   --t4: 0=全过 / 1=有 FAIL / 77=全 SKIP
#
# 断言分组（与 AC 逐条映射）:
#   AC1 阶梯③（tmux 会话 + 可见窗口 attach）        AC2 阶梯④（xdg-terminal-exec 直开窗）
#   AC3 NAO_TERMINAL 负向 + P4 回归（未安装宿主）    AC4 P3 回归（六宿主全不可用 ⇒ exit 2）
#   AC5 D4（无图形：--background 显式）              AC6 失败路径零残留（AC6）
#   AC7 tmux 内逐值零回归（真 tmux 隔离服务器）      AC8 非 tmux 句柄降级（app-id/pid + status 标注）
#   AC9 文档一致性（usage/intercom-protocol/README/ARCHITECTURE + check）
#   AC10 T513f 层③ 收紧（未认领 pi pane 跨全部角色唯一 + 名册 cwd 匹配；隔离 tmux + 桩 pi · comm=pi）
#
# 覆盖限制（NFR5，必须随报告一同披露）:
#   本机仅 foot + Hyprland ⇒ ghostty/ptyxis/其它合成器路径**无法真测**。AC1/AC2/AC5/AC8 采用
#   **受控桩**（PATH 替身）驱动真实 nao-fleet.sh 控制流，断言「调用与副作用」而非「真实窗口像素」；
#   脚本**不得**声称这些路径「已验证」。AC7 使用**真 tmux**（独立 socket + 桩 pi）做几何逐值比对。
#
# 安全边界:
#   - 绝不写本仓 .agents/roles.yaml / nao-fleet.sh / tests/**（全部改动落在 $FXROOT 夹具副本）
#   - 零网络；默认不打开真实窗口、不拉起真实 pi；AC7 用独立 tmux server（结束即 kill）
#   - 名册走夹具内嵌假探针（NAO_QA_FAKE_ROSTER），不读取/不污染真实 pi-intercom 名册
# =============================================================================
set -uo pipefail

SELF="$0"
ROOT=""
MODE="verify"
T4_MODE=0
ONLY=""
for a in "$@"; do
  case "$a" in
    --baseline)  MODE="baseline" ;;
    --verify)    MODE="verify" ;;
    --t4)        T4_MODE=1 ;;
    --root)      ROOT="__NEXT__" ;;
    --only)      ONLY="__NEXT__" ;;
    --only=*)    ONLY="${a#--only=}" ;;
    -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
    *) if [[ "$ROOT" == "__NEXT__" ]]; then ROOT="$a";
       elif [[ "$ONLY" == "__NEXT__" ]]; then ONLY="$a";
       else printf '未知参数: %s\n' "$a" >&2; exit 2; fi ;;
  esac
done
[[ "$ROOT" == "__NEXT__" ]] && { printf -- '--root 需要目录参数\n' >&2; exit 2; }
[[ -n "$ROOT" ]] || ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"
ROOT="$(cd "$ROOT" && pwd)"
FLEET="$ROOT/.agents/scripts/nao-fleet.sh"
README="$ROOT/README.md"
ARCH="$ROOT/docs/ARCHITECTURE.md"
PROTO="$ROOT/.agents/common/intercom-protocol.md"
BASH_BIN="$(command -v bash)"
REAL_PATH="$PATH"
REAL_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"

[[ -f "$FLEET" ]] || { printf '未找到被测脚本: %s\n' "$FLEET" >&2; exit 2; }

# ----------------------------------------------------------------------------- 断言/输出
PASS_N=0 FAIL_N=0 SKIP_N=0 WARN_N=0
declare -A AC_P AC_F AC_S AC_W
declare -a FAILED=()
AC_ORDER=(AC1 AC2 AC3 AC4 AC5 AC6 AC7 AC8 AC9 AC10)
only_match(){ [[ -z "$ONLY" ]] && return 0; [[ ",$ONLY," == *",$1,"* ]]; }
pass(){ local ac="$1"; shift; PASS_N=$((PASS_N+1)); AC_P[$ac]=$(( ${AC_P[$ac]:-0}+1 )); printf '  [PASS] %-4s %s\n' "$ac" "$*"; }
bad(){  local ac="$1"; shift; FAIL_N=$((FAIL_N+1)); AC_F[$ac]=$(( ${AC_F[$ac]:-0}+1 )); FAILED+=("$ac $*"); printf '  [FAIL] %-4s %s\n' "$ac" "$*"; }
skip(){ local ac="$1"; shift; SKIP_N=$((SKIP_N+1)); AC_S[$ac]=$(( ${AC_S[$ac]:-0}+1 )); printf '  [SKIP] %-4s %s\n' "$ac" "$*"; }
warn2(){ local ac="$1"; shift; WARN_N=$((WARN_N+1)); AC_W[$ac]=$(( ${AC_W[$ac]:-0}+1 )); printf '  [WARN] %-4s %s\n' "$ac" "$*"; }
note(){ printf '  [NOTE] %s\n' "$*"; }
sec(){ printf '\n== %s ==\n' "$*"; }
strip_ansi(){ perl -pe 's/\e\[[0-9;]*m//g' 2>/dev/null || cat; }
oneline(){ strip_ansi <<< "${1:-}" | tr '\n' '|' | cut -c1-240; }
occur(){ # $1=text $2=needle → 出现次数
  local n; n="$(printf '%s' "$1" | grep -oF -- "$2" | wc -l | tr -d ' ')"; printf '%s' "$n"
}

# ----------------------------------------------------------------------------- 夹具/环境
FXROOT="$(mktemp -d "${TMPDIR:-/tmp}/t513-verify.XXXXXX")" || { echo "mktemp 失败" >&2; exit 2; }
PROMPT_BASELINE="$(ls -1 /tmp/nao-fleet-*.md 2>/dev/null | sort)"   # 脚本启动前已有的 prompt 临时件（禁止误删 PM/RD 的）
declare -a CLEAN_TMUX=() CLEAN_PIDS=() CLEAN_FILES=()
cleanup(){
  local d p f
  for d in "${CLEAN_TMUX[@]:-}"; do [[ -n "$d" ]] && { tmux -S "$d/sock" kill-server 2>/dev/null || true; rm -rf "$d"; }; done
  for p in "${CLEAN_PIDS[@]:-}"; do [[ -n "$p" ]] && kill "$p" 2>/dev/null || true; done
  for f in "${CLEAN_FILES[@]:-}"; do [[ -n "$f" ]] && rm -f -- "$f"; done
  # 本轮 ensure 产生的 prompt 临时件（夹具桩宿主不会消费；机制自身 60s 后才删 ⇒ 此处兜底收尾）
  local cur
  cur="$(ls -1 /tmp/nao-fleet-*.md 2>/dev/null | sort)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    grep -qxF "$f" <<< "$PROMPT_BASELINE" && continue
    rm -f -- "$f"
  done <<< "$(comm -13 <(printf '%s\n' "$PROMPT_BASELINE") <(printf '%s\n' "$cur") 2>/dev/null || true)"
  if [[ "${KEEP:-0}" == 1 ]]; then printf '\n（KEEP=1：夹具保留于 %s）\n' "$FXROOT"; return 0; fi
  rm -rf "$FXROOT"
}
trap cleanup EXIT

# 受限 PATH：/usr/{local/,}bin 全量软链，**剔除宿主命令**（detect_host 可见性完全可控）
MINBIN="$FXROOT/minbin"; mkdir -p "$MINBIN"
for d in /usr/local/bin /usr/bin /bin; do
  [[ -d "$d" ]] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    case "$b" in tmux|screen|ghostty|ptyxis|foot|footclient|xdg-terminal-exec|hyprctl|swaymsg|xdotool|wmctrl) continue ;; esac
    [[ -e "$MINBIN/$b" ]] && continue
    ln -s "$f" "$MINBIN/$b" 2>/dev/null || true
  done
done
# node 常不在 /usr/bin（mise/nvm）⇒ 显式补链，供名册探针（intercom-probe）使用
NODE_BIN="$(command -v node || true)"
[[ -n "$NODE_BIN" ]] && ln -sf "$NODE_BIN" "$MINBIN/node"

write_probe(){ # $1 = fixture 根；内嵌假名册探针（读 NAO_QA_FAKE_ROSTER）
  cat > "$1/.agents/scripts/intercom-probe.mts" <<'JS'
// T513 QA hermetic roster fixture（只读 env；绝不接触真实 pi-intercom 名册）
process.stdout.write(JSON.stringify(
  { ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
}
mk_fixture(){ # $1 = 名字 → 打印夹具根
  local d="$FXROOT/$1"
  rm -rf "$d"; mkdir -p "$d"
  cp -r "$ROOT/.agents" "$d/.agents" || { echo "夹具复制失败: $d" >&2; return 2; }
  write_probe "$d"
  printf '%s' "$d"
}

FXENV=() RUN_OF="" RUN_RC=0
set_env(){ FXENV=( "$@" ); }
run_fleet(){ # $1 = 夹具根；其余 fleet 参数
  local fut="$1"; shift
  RUN_OF="$(mktemp "$FXROOT/out.XXXXXX")"
  ( cd "$fut" && env "${FXENV[@]}" "$BASH_BIN" "$fut/.agents/scripts/nao-fleet.sh" "$@" </dev/null ) >"$RUN_OF" 2>&1
  RUN_RC=$?
}
out(){ cat "$RUN_OF"; }
out_s(){ strip_ansi < "$RUN_OF"; }

# 宿主替身（桩）：tmux / xdg-terminal-exec / hyprctl
write_tmux_stub(){ cat > "$1/tmux" <<'SH'
#!/usr/bin/env bash
log="${T513_TMUX_LOG:-/dev/null}"; state="${T513_TMUX_STATE:-/dev/null}"
printf 'tmux %s\n' "$*" >>"$log"
cmd="${1:-}"; [ $# -gt 0 ] && shift
get_t(){ local t=""; while [ $# -gt 0 ]; do case "$1" in -t) t="${2:-}"; shift 2;; *) shift;; esac; done; printf '%s' "$t"; }
get_s(){ local s=""; while [ $# -gt 0 ]; do case "$1" in -s) s="${2:-}"; shift 2;; *) shift;; esac; done; printf '%s' "$s"; }
case "$cmd" in
  new-session) n="$(get_s "$@")"; [ -n "$n" ] && printf '%s\n' "$n" >>"$state"; exit 0 ;;
  has-session) n="$(get_t "$@")"; grep -qxF "$n" "$state" 2>/dev/null; exit $? ;;
  kill-session) n="$(get_t "$@")"; if [ -f "$state" ]; then grep -vxF "$n" "$state" >"$state.t" 2>/dev/null || :; mv "$state.t" "$state"; fi; exit 0 ;;
  list-sessions) cat "$state" 2>/dev/null; exit 0 ;;
  list-clients) printf '%s\n' "/dev/pts/0: 1 (attached)"; exit 0 ;;
  list-panes|capture-pane|display-message) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$1/tmux"; }
write_xdg_stub(){ cat > "$1/xdg-terminal-exec" <<'SH'
#!/usr/bin/env bash
printf 'xdg %s\n' "$*" >>"${T513_XDG_LOG:-/dev/null}"
case " $* " in
  *" --print-id "*)   printf 'foot.desktop\n'; exit 0 ;;
  *" --print-path "*) printf '/usr/share/applications/foot.desktop\n'; exit 0 ;;
  *" --print-cmd"*)   printf 'foot\n--app-id=org.nao.qa\n'; exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$1/xdg-terminal-exec"; }
write_hypr_stub(){ cat > "$1/hyprctl" <<'SH'
#!/usr/bin/env bash
printf 'hyprctl %s\n' "$*" >>"${T513_HYPR_LOG:-/dev/null}"
case " $* " in
  *" clients "*) printf '[{"address":"0x1","class":"org.nao.qa","initialClass":"org.nao.qa","title":"π - qa - repo","pid":%s,"workspace":{"id":1}}]\n' "${T513_WIN_PID:-0}" ;;
esac
exit 0
SH
chmod +x "$1/hyprctl"; }

dummy_pi(){ # $1 = 目录 → 打印 pid（可执行名 = pi ⇒ /proc/<pid>/comm=pi）
  cp /bin/sleep "$1/pi" 2>/dev/null || return 1
  "$1/pi" 900 >/dev/null 2>&1 &
  printf '%s' "$!"
}
mk_stubs(){ # $1 = 名字 → 打印 stub 目录
  local d="$FXROOT/stub-$1"; mkdir -p "$d"; printf '%s' "$d"
}

# 常用 env 片段
BASE_ENV(){ # $1 = 夹具根；开启名册探针与角色清单根
  set_env -u TMUX -u NAO_TERMINAL -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE \
    NAO_SKILLS="$1" NAO_TASKS_STATE="$1/.no-tasks-state.md" \
    PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" \
    NAO_QA_FAKE_ROSTER="${ROSTER:-[]}"
}
graphical(){ FXENV+=( WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" DISPLAY="${DISPLAY:-:0}" XDG_SESSION_TYPE=wayland ); }

printf '################ T513 非 tmux 宿主派生 —— 独立断言 ################\n'
printf '模式      : %s%s\n' "$MODE" "$( [[ $MODE == baseline ]] && echo ' （基线体检：FAIL 属预期）' )"
printf '被测树    : %s\n' "$ROOT"
printf '机制版本  : %s\n' "$(node -p "require('$ROOT/package.json').version" 2>/dev/null || echo '?')"
printf 'git HEAD  : %s\n' "$(cd "$ROOT" && git rev-parse --short HEAD 2>/dev/null || echo '?')"
printf 'tmux      : %s\n' "$(command -v tmux >/dev/null 2>&1 && tmux -V || echo '缺失')"
printf '夹具目录  : %s\n' "$FXROOT"
[[ -n "$ONLY" ]] && printf '仅跑      : %s\n' "$ONLY"

# =============================================================================
if only_match AC1; then
sec "AC1 阶梯③：非 tmux + tmux 可用 + 图形 ⇒ tmux 会话 + 可见窗口 attach（桩驱动）"
FIX="$(mk_fixture ac1)"; ST="$FXROOT/stub-ac1"; mkdir -p "$ST"
write_tmux_stub "$ST"; write_xdg_stub "$ST"; write_hypr_stub "$ST"
: > "$FXROOT/ac1.tmux.log"; : > "$FXROOT/ac1.xdg.log"; : > "$FXROOT/ac1.tmux.state"
set_env -u TMUX -u NAO_TERMINAL \
  NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' \
  PATH="$ST:$MINBIN" HOME="$FXROOT/home" T513_TMUX_LOG="$FXROOT/ac1.tmux.log" T513_TMUX_STATE="$FXROOT/ac1.tmux.state" \
  T513_XDG_LOG="$FXROOT/ac1.xdg.log" T513_HYPR_LOG="$FXROOT/ac1.hypr.log" T513_WIN_PID=0
graphical
mkdir -p "$FXROOT/home"
run_fleet "$FIX" ensure qa
o="$(out_s)"; log_tmux="$(cat "$FXROOT/ac1.tmux.log" 2>/dev/null)"; log_xdg="$(cat "$FXROOT/ac1.xdg.log" 2>/dev/null)"
if (( RUN_RC == 0 )); then pass AC1 "ensure qa rc=0（桩宿主，无真实窗口）"; else bad AC1 "ensure qa rc=$RUN_RC（$(oneline "$o")）"; fi
if grep -q 'new-session' <<< "$log_tmux" && grep -q 'nao-qa' <<< "$log_tmux"; then
  pass AC1 "已建 tmux 会话 nao-qa（new-session -s nao-qa 调用命中）"
else bad AC1 "未见 new-session nao-qa（tmux 桩日志: $(oneline "$log_tmux")）"; fi
if grep -q 'org\.nao\.qa' <<< "$log_xdg"; then
  pass AC1 "可见窗口标识含 org.nao.qa（xdg-terminal-exec 调用）"
else bad AC1 "未调用 xdg-terminal-exec --app-id=org.nao.qa（看到: $(oneline "$log_xdg")）⇒ 阶梯③未开可见窗口"; fi
n="$(occur "$o" '已拉起')"
if [[ "$n" == 1 ]]; then pass AC1 "成功日志 1 处「已拉起」（句柄前置校验后）"; else bad AC1 "「已拉起」出现 $n 处（期望 1）"; fi
fi

# =============================================================================
if only_match AC2; then
sec "AC2 阶梯④：非 tmux + 无 tmux + 图形 ⇒ xdg-terminal-exec 直开窗（桩驱动）"
FIX="$(mk_fixture ac2)"; ST="$FXROOT/stub-ac2"; mkdir -p "$ST"
write_xdg_stub "$ST"; write_hypr_stub "$ST"
mkdir -p "$FXROOT/home2"; PID2="$(dummy_pi "$FXROOT/home2")"; CLEAN_PIDS+=("$PID2")
: > "$FXROOT/ac2.xdg.log"
set_env -u TMUX -u NAO_TERMINAL \
  NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' \
  PATH="$ST:$MINBIN" HOME="$FXROOT/home2" T513_XDG_LOG="$FXROOT/ac2.xdg.log" T513_HYPR_LOG="$FXROOT/ac2.hypr.log" \
  T513_WIN_PID="$PID2"
graphical
run_fleet "$FIX" ensure qa
o="$(out_s)"; log_xdg="$(cat "$FXROOT/ac2.xdg.log" 2>/dev/null)"
if (( RUN_RC == 0 )); then pass AC2 "ensure qa rc=0（桩宿主，无真实窗口）"; else bad AC2 "ensure qa rc=$RUN_RC（$(oneline "$o")）"; fi
if grep -q 'org\.nao\.qa' <<< "$log_xdg" && grep -q -- '--dir=' <<< "$log_xdg"; then
  pass AC2 "xdg-terminal-exec --app-id=org.nao.qa --dir=… 调用命中"
else bad AC2 "未以 --app-id=org.nao.qa --dir=<repo> 开窗（看到: $(oneline "$log_xdg")）"; fi
if grep -q 'clients' "$FXROOT/ac2.hypr.log" 2>/dev/null; then
  pass AC2 "按 hyprctl clients -j 定位窗口 class=org.nao.qa（桩回放）"
else bad AC2 "未按 hyprctl clients -j 定位 app-id/class 句柄"; fi
fi

# =============================================================================
if only_match AC3; then
sec "AC3 NAO_TERMINAL 负向 + P4 回归：未安装/未知宿主 ⇒ rc≠0 且 0 处「已拉起」"
FIX="$(mk_fixture ac3)"
mkdir -p "$FXROOT/home3"
run_neg(){ # $1=宿主名 $2=期望 rc
  set_env -u TMUX NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" \
    PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' PATH="$MINBIN" HOME="$FXROOT/home3" \
    NAO_TERMINAL="$1"
  graphical
  run_fleet "$FIX" ensure qa
}
run_neg ghostty 2; o="$(out_s)"; n="$(occur "$o" '已拉起')"
if (( RUN_RC != 0 )); then pass AC3 "NAO_TERMINAL=ghostty（未安装）→ rc=$RUN_RC（≠0，非 P4 假成功）"; else bad AC3 "NAO_TERMINAL=ghostty（未安装）→ rc=0 假成功（P4 回归未修）"; fi
if [[ "$n" == 0 ]]; then pass AC3 "NAO_TERMINAL=ghostty：0 处「已拉起」"; else bad AC3 "NAO_TERMINAL=ghostty：出现 $n 处「已拉起」（P4 回归）"; fi
if grep -qE '宿主不可用|不支持的宿主|无可用宿主|环境不足|exit 2' <<< "$o"; then pass AC3 "输出含失败诊断（宿主不可用/环境不足/exit 2）"; else bad AC3 "输出无失败诊断（$(oneline "$o")）"; fi
run_neg wezterm 2; o="$(out_s)"; n="$(occur "$o" '已拉起')"
if (( RUN_RC == 2 )); then pass AC3 "NAO_TERMINAL=wezterm（未知宿主）→ rc=2（BR3 环境不足）"; else bad AC3 "NAO_TERMINAL=wezterm → rc=$RUN_RC（期望 2；裸中断/其他码均不合格）"; fi
if [[ "$n" == 0 ]]; then pass AC3 "NAO_TERMINAL=wezterm：0 处「已拉起」"; else bad AC3 "NAO_TERMINAL=wezterm：出现 $n 处「已拉起」"; fi
fi

# =============================================================================
if only_match AC4; then
sec "AC4 P3 回归：六个宿主全不可用 ⇒ rc=2 + 单行诊断 + 可复制恢复命令（禁裸 127）"
FIX="$(mk_fixture ac4)"; mkdir -p "$FXROOT/home4"
set_env -u TMUX -u NAO_TERMINAL \
  NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' \
  PATH="$MINBIN" HOME="$FXROOT/home4"
graphical
run_fleet "$FIX" ensure qa
o="$(out_s)"; n="$(occur "$o" '已拉起')"
if (( RUN_RC == 2 )); then pass AC4 "六宿主全不可用 → rc=2（非 127 裸中断，P3 回归已修）"; else bad AC4 "六宿主全不可用 → rc=$RUN_RC（期望 2；P3 回归未修则常见 127）"; fi
if grep -qE '未找到命令|command not found|: line [0-9]+:|行 [0-9]+:' <<< "$o"; then
  bad AC4 "输出含裸报错（$(oneline "$o")）"
else pass AC4 "输出无裸报错（无 command not found / 行 N:）"; fi
if [[ "$n" == 0 ]]; then pass AC4 "0 处「已拉起」"; else bad AC4 "出现 $n 处「已拉起」"; fi
if grep -qE 'NAO_TERMINAL=|--background' <<< "$o"; then
  pass AC4 "含可复制恢复命令（NAO_TERMINAL=/--background 提示）"
else bad AC4 "无恢复命令提示（$(oneline "$o")）"; fi
fi

# =============================================================================
if only_match AC5; then
sec "AC5 D4：无图形会话 ⇒ 默认 exit 2；显式 --background 才建 detached 会话"
FIX="$(mk_fixture ac5)"; ST="$FXROOT/stub-ac5"; mkdir -p "$ST"; write_tmux_stub "$ST"
mkdir -p "$FXROOT/home5"
: > "$FXROOT/ac5.tmux.state"
set_env -u TMUX -u NAO_TERMINAL -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE \
  NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' \
  PATH="$ST:$MINBIN" HOME="$FXROOT/home5" T513_TMUX_LOG="$FXROOT/ac5.tmux.log" T513_TMUX_STATE="$FXROOT/ac5.tmux.state"
run_fleet "$FIX" ensure qa
o="$(out_s)"; n="$(occur "$o" '已拉起')"
if (( RUN_RC == 2 )); then pass AC5 "无图形 + 无 --background → rc=2（拒绝静默后台，D4）"; else bad AC5 "无图形 + 无 --background → rc=$RUN_RC（期望 2；rc=0 即静默后台会话）"; fi
if grep -q 'nao-qa' "$FXROOT/ac5.tmux.state" 2>/dev/null; then
  bad AC5 "无 --background 仍建了 detached 会话 nao-qa（BR4/D4 违规）"
else pass AC5 "无 --background 未建任何会话（无残留）"; fi
[[ "$n" == 0 ]] && pass AC5 "默认失败路径 0 处「已拉起」" || bad AC5 "默认失败路径出现 $n 处「已拉起」"
: > "$FXROOT/ac5.tmux.log"; : > "$FXROOT/ac5.tmux.state"
run_fleet "$FIX" ensure --background qa
o="$(out_s)"; log_tmux="$(cat "$FXROOT/ac5.tmux.log" 2>/dev/null)"
if (( RUN_RC == 0 )); then pass AC5 "无图形 + --background qa → rc=0"; else bad AC5 "无图形 + --background qa → rc=$RUN_RC（期望 0；未知参数退出即未实现 --background）"; fi
if grep -q 'nao-qa' <<< "$log_tmux"; then pass AC5 "--background 建 detached 会话 nao-qa"; else bad AC5 "--background 未见 new-session nao-qa"; fi
if grep -qE 'tmux attach -t nao-qa' <<< "$o"; then pass AC5 "打印可复制 attach 命令（tmux attach -t nao-qa）"; else bad AC5 "未打印 attach 命令（$(oneline "$o")）"; fi
fi

# =============================================================================
if only_match AC6; then
sec "AC6 失败路径零残留（无孤儿会话/窗口/临时件；status 不误报在线）"
FIX="$(mk_fixture ac6)"; mkdir -p "$FXROOT/home6"
: > "$FXROOT/ac6.tmux.state"
# 6a. P4 失败路径：不得留 prompt 临时件
before="$(ls -1 /tmp/nao-fleet-*.md 2>/dev/null | sort)"
set_env -u TMUX NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" \
  PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' PATH="$MINBIN" HOME="$FXROOT/home6" NAO_TERMINAL=ghostty
graphical
run_fleet "$FIX" ensure qa
after="$(ls -1 /tmp/nao-fleet-*.md 2>/dev/null | sort)"
newfiles="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep . || true)"
if [[ -z "$newfiles" ]]; then pass AC6 "失败路径未残留 /tmp prompt 临时件（AC6）"; else
  bad AC6 "失败路径残留 prompt 临时件: $(printf '%s' "$newfiles" | tr '\n' ' ')"
  while IFS= read -r f; do [[ -n "$f" ]] && CLEAN_FILES+=("$f"); done <<< "$newfiles"
fi
# 6b. 无图形无 --background 失败路径：不得半开 detached 会话
ST="$FXROOT/stub-ac6"; mkdir -p "$ST"; write_tmux_stub "$ST"
set_env -u TMUX -u NAO_TERMINAL -u WAYLAND_DISPLAY -u DISPLAY -u XDG_SESSION_TYPE \
  NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' \
  PATH="$ST:$MINBIN" HOME="$FXROOT/home6" T513_TMUX_LOG="$FXROOT/ac6.tmux.log" T513_TMUX_STATE="$FXROOT/ac6.tmux.state"
run_fleet "$FIX" ensure qa
if grep -q 'nao-qa' "$FXROOT/ac6.tmux.state" 2>/dev/null; then
  bad AC6 "失败路径残留 detached 会话 nao-qa（应清理）"
else pass AC6 "失败路径无残留 detached 会话"; fi
run_fleet "$FIX" status
so="$(out_s)"
if grep -qE 'qa[[:space:]]+在线' <<< "$so"; then bad AC6 "失败后 status 仍报 qa 在线（误报）"; else pass AC6 "失败后 status 未报 qa 在线"; fi
fi

# =============================================================================
if only_match AC7; then
sec "AC7 tmux 内逐值零回归（真 tmux 隔离 socket + 桩 pi；几何 golden = cec4461 实测）"
GEO_MAINROW2_152_N4='1:52x34@0,0 2:49x16@53,0 3:49x17@53,17 4:49x34@103,0'
GEO_MAINROW2_80_N6='1:27x34@0,0 2:52x6@28,0 3:52x6@28,7 4:52x6@28,14 5:52x6@28,21 6:52x6@28,28'
GEO_MAINCOL_152_N4='1:52x34@0,0 2:99x11@53,0 3:99x11@53,12 4:99x10@53,24'
GEO_GRID_152_N4='1:75x16@0,0 2:76x16@76,0 3:75x17@0,17 4:76x17@76,17'
FIX="$(mk_fixture ac7)"
STPI="$FXROOT/stub-pi7"; mkdir -p "$STPI"
printf '#!/bin/bash\nexec sleep 600\n' > "$STPI/pi"; chmod +x "$STPI/pi"
FH="$(FXROOT_HOME="$FXROOT/home7"; mkdir -p "$FXROOT_HOME"; printf '%s' "$FXROOT_HOME")"
printf 'export PATH=%q\n' "$STPI:$REAL_PATH" > "$FH/.bash_profile"
ac7(){ # $1=layout $2=W $3=H $4..roles
  local layout="$1" W="$2" H="$3"; shift 3
  local sockd; sockd="$(mktemp -d "$FXROOT/sock.XXXXXX")"; CLEAN_TMUX+=("$sockd")
  tmux -S "$sockd/sock" new-session -d -s fx -x "$W" -y "$H" >/dev/null 2>&1 || return 9
  sleep 0.3
  local pid sid; pid="$(tmux -S "$sockd/sock" display -p '#{pid}' 2>/dev/null)"; sid="$(tmux -S "$sockd/sock" display -p '#{session_id}' 2>/dev/null)"
  set_env "TMUX=$sockd/sock,$pid,$sid" NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" \
    PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' PATH="$STPI:$REAL_PATH" HOME="$FH" \
    NAO_TMUX_LAYOUT="$layout" NAO_TMUX_MAIN_WIDTH=35 NAO_TMUX_MIN_PANE_WIDTH=30
  run_fleet "$FIX" ensure --force "$@"
  AC7_RC=$RUN_RC
  AC7_GEO="$(tmux -S "$sockd/sock" list-panes -F '#{pane_index}:#{pane_width}x#{pane_height}@#{pane_left},#{pane_top}' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ $//')"
  AC7_OUT="$(out_s)"
}
ac7 main-row2 152 34 pm arch-designer rd-fe
if [[ "$AC7_GEO" == "$GEO_MAINROW2_152_N4" ]]; then pass AC7 "main-row2 W=152 N=4 几何逐值一致"; else bad AC7 "main-row2 W=152 N=4 几何漂移（期望「$GEO_MAINROW2_152_N4」实际「$AC7_GEO」）"; fi
ac7 main-row2 80 34 pm arch-designer rd-fe rd-be qa
if [[ "$AC7_GEO" == "$GEO_MAINROW2_80_N6" ]]; then pass AC7 "main-row2 W=80 N=6 窄列守卫几何逐值一致（回退 main-col）"; else bad AC7 "窄列守卫几何漂移（期望「$GEO_MAINROW2_80_N6」实际「$AC7_GEO」）"; fi
if grep -qE '最窄列 [0-9]+ < 最小 [0-9]+ → 回退 main-col' <<< "$AC7_OUT"; then
  pass AC7 "窄列守卫提示含三数字且指名回退 main-col"
else bad AC7 "窄列守卫提示缺失/格式不符（$(oneline "$AC7_OUT")）"; fi
ac7 main-col 152 34 pm arch-designer rd-fe
if [[ "$AC7_GEO" == "$GEO_MAINCOL_152_N4" ]]; then pass AC7 "main-col W=152 N=4 几何逐值一致"; else bad AC7 "main-col 几何漂移（期望「$GEO_MAINCOL_152_N4」实际「$AC7_GEO」）"; fi
ac7 grid 152 34 pm arch-designer rd-fe
if [[ "$AC7_GEO" == "$GEO_GRID_152_N4" ]]; then pass AC7 "grid W=152 N=4 几何逐值一致"; else bad AC7 "grid 几何漂移（期望「$GEO_GRID_152_N4」实际「$AC7_GEO」）"; fi
# 判重跳过（名册报在线 ⇒ 不新开 pane）
sockd="$(mktemp -d "$FXROOT/sock.XXXXXX")"; CLEAN_TMUX+=("$sockd")
tmux -S "$sockd/sock" new-session -d -s fx -x 152 -y 34 >/dev/null 2>&1; sleep 0.3
pid="$(tmux -S "$sockd/sock" display -p '#{pid}' 2>/dev/null)"; sid="$(tmux -S "$sockd/sock" display -p '#{session_id}' 2>/dev/null)"
ROSTER='[{"name":"qa","id":"qa","status":"idle","cwd":"'"$FIX"'","tmuxPane":""}]'
set_env "TMUX=$sockd/sock,$pid,$sid" NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" \
  PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER="$ROSTER" PATH="$STPI:$REAL_PATH" HOME="$FH" \
  NAO_TMUX_LAYOUT=main-row2 NAO_TMUX_MAIN_WIDTH=35 NAO_TMUX_MIN_PANE_WIDTH=30
run_fleet "$FIX" ensure qa rd-be
o="$(out_s)"; np="$(tmux -S "$sockd/sock" list-panes 2>/dev/null | wc -l | tr -d ' ')"
if grep -q '已在运行' <<< "$o" && [[ "$np" == 2 ]] && ! grep -q '已拉起 qa' <<< "$o"; then
  pass AC7 "判重跳过（名册在线 ⇒ qa 未新开 pane；rd-be 正常新开）"
else bad AC7 "判重行为漂移（pane 数=$np；$(oneline "$o")）"; fi
ROSTER='[]'
fi

# =============================================================================
if only_match AC8; then
sec "AC8 句柄降级（D2）：app-id/pid 回收 + status「turn 判定来源 = 名册」标注"
FIX="$(mk_fixture ac8)"; ST="$FXROOT/stub-ac8"; mkdir -p "$ST"
write_xdg_stub "$ST"; write_hypr_stub "$ST"
mkdir -p "$FXROOT/home8"; PID8="$(dummy_pi "$FXROOT/home8")"; CLEAN_PIDS+=("$PID8")
: > "$FXROOT/ac8.hypr.log"
set_env -u TMUX -u NAO_TERMINAL \
  NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' \
  PATH="$ST:$MINBIN" HOME="$FXROOT/home8" T513_XDG_LOG="$FXROOT/ac8.xdg.log" T513_HYPR_LOG="$FXROOT/ac8.hypr.log" \
  T513_WIN_PID="$PID8"
graphical
run_fleet "$FIX" status
o="$(out_s)"
if grep -qE 'turn 判定来源[[:space:]]*=[[:space:]]*名册' <<< "$o"; then
  pass AC8 "status 含降级标注「turn 判定来源 = 名册」"
else bad AC8 "status 缺降级标注（BR6/AC8；$(oneline "$o")）"; fi
run_fleet "$FIX" close qa
o="$(out_s)"
if (( RUN_RC == 0 )); then pass AC8 "close qa rc=0（app-id/pid 句柄）"; else bad AC8 "close qa rc=$RUN_RC（$(oneline "$o")）"; fi
sleep 0.2
if kill -0 "$PID8" 2>/dev/null; then bad AC8 "close 未按 pid 回收（pid $PID8 仍存活）"; else pass AC8 "close 已按 class→pid 回收（pid $PID8 结束）"; fi
if grep -q 'clients' "$FXROOT/ac8.hypr.log" 2>/dev/null; then pass AC8 "close 经 hyprctl clients -j 取 class=org.nao.qa 句柄"; else bad AC8 "close 未经 app-id/class 句柄定位"; fi
fi

# =============================================================================
if only_match AC9; then
sec "AC9 文档一致性：usage / intercom-protocol / README / ARCHITECTURE 与 BR1 阶梯逐条一致"
usage_head(){ awk '/^# =+$/ { c++; if (c==2) exit; next } c==1 && /^#/ { sub(/^# ?/,""); print }' "$FLEET"; }
uh="$(usage_head)"
for pair in "nao-fleet.sh usage头:--background" "nao-fleet.sh usage头:xdg-terminal-exec"; do
  f="${pair%%:*}"; kw="${pair##*:}"
  if grep -qF -- "$kw" <<< "$uh"; then pass AC9 "$f 含 $kw"; else bad AC9 "$f 缺 $kw"; fi
done
for f in "$PROTO" "$README" "$ARCH"; do
  nm="$(basename "$f")"
  if [[ ! -f "$f" ]]; then bad AC9 "$nm 缺失"; continue; fi
  miss=""
  grep -qF -- '--background' "$f" || miss+='--background '
  grep -qF 'xdg-terminal-exec' "$f" || miss+='xdg-terminal-exec '
  if [[ -z "$miss" ]]; then pass AC9 "$nm 含 --background + xdg-terminal-exec（BR1 阶梯）"; else bad AC9 "$nm 缺: $miss"; fi
done
FIX="$(mk_fixture ac9)"
set_env -u TMUX -u NAO_TERMINAL NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" \
  PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER='[]' PATH="$REAL_PATH" HOME="$FXROOT/home9"
mkdir -p "$FXROOT/home9"
run_fleet "$FIX" check -v
o="$(out_s)"
if grep -qE 'xdg-terminal-exec|--background|宿主阶梯|宿主段' <<< "$o"; then
  pass AC9 "check 含宿主阶梯对应断言/说明"
else bad AC9 "check 未含宿主阶梯断言（AC9 尾款）"; fi
fi

# =============================================================================
if only_match AC10; then
sec "AC10 T513f 层③ 收紧：未认领 pi pane 跨全部角色唯一 + 名册 cwd 匹配（隔离 tmux + 桩 pi，绝不触碰真实 pane/名册）"
FIX="$(mk_fixture ac10)"
STPI="$FXROOT/stub-pi10"; mkdir -p "$STPI"
printf '#!/bin/bash\nexec -a pi sleep 600\n' > "$STPI/pi"; chmod +x "$STPI/pi"
FH10="$FXROOT/home10"; mkdir -p "$FH10"
printf 'export PATH=%q\n' "$STPI:$REAL_PATH" > "$FH10/.bash_profile"
AC10_SOCK=""
ac10_setup(){ # 建隔离 tmux server（独立 socket；不碰共享 tmux）
  local pid sid
  [[ -n "$AC10_SOCK" ]] && tmux -S "$AC10_SOCK/sock" kill-server 2>/dev/null || true
  AC10_SOCK="$(mktemp -d "$FXROOT/sock.XXXXXX")"; CLEAN_TMUX+=("$AC10_SOCK")
  tmux -S "$AC10_SOCK/sock" new-session -d -s fx -x 200 -y 40 -c "$FIX" || return 1
  sleep 0.3
  pid="$(tmux -S "$AC10_SOCK/sock" display -p '#{pid}' 2>/dev/null)"; sid="$(tmux -S "$AC10_SOCK/sock" display -p '#{session_id}' 2>/dev/null)"
  AC10_TMUX="$AC10_SOCK/sock,$pid,$sid"
}
ac10_canary(){ # 造 1 个「未认领 pi pane」（cmd=pi · cwd=$FIX）；打印 pane_id
  tmux -S "$AC10_SOCK/sock" split-window -h -t fx -c "$FIX" "$STPI/pi" >/dev/null 2>&1
  sleep 0.3
  tmux -S "$AC10_SOCK/sock" list-panes -t fx -F '#{pane_id}' 2>/dev/null | tail -1
}
ac10_panes(){ tmux -S "$AC10_SOCK/sock" list-panes -t fx -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' '; }
ac10_env(){ set_env "TMUX=$AC10_TMUX" NAO_SKILLS="$FIX" NAO_TASKS_STATE="$FIX/.no-tasks-state.md" \
    PI_CODING_AGENT_DIR="$REAL_AGENT_DIR" NAO_QA_FAKE_ROSTER="$1" \
    PATH="$STPI:$REAL_PATH" HOME="$FH10" \
    NAO_TMUX_LAYOUT=main-row2 NAO_TMUX_MAIN_WIDTH=35 NAO_TMUX_MIN_PANE_WIDTH=30; }

# 10.① 歧义：2 个未认领 pi pane ⇒ warn + 不认领 + 真拉起
ac10_setup; ac10_canary >/dev/null; ac10_canary >/dev/null; n0="$(ac10_panes)"; ac10_env '[]'
run_fleet "$FIX" ensure qa
o="$(out_s)"; n1="$(ac10_panes)"
if grep -qE '无法唯一确定|多个未认领 pi pane' <<< "$o"; then pass AC10 "① 2 个未认领 pane → warn 歧义"; else bad AC10 "① 未 warn 歧义（$(oneline "$o")）"; fi
if grep -q '已在运行' <<< "$o"; then bad AC10 "① 歧义时误判已在运行（跳过）"; else pass AC10 "① 歧义时未认领（未跳过）"; fi
if grep -q '已拉起 qa' <<< "$o"; then pass AC10 "① 歧义时 ensure 真拉起 qa"; else bad AC10 "① 歧义时未拉起 qa（$(oneline "$o")）"; fi
if [[ "$n1" == "$((n0+1))" ]]; then pass AC10 "① pane 数 $n0→$n1（+1 真拉起）"; else bad AC10 "① pane 数 $n0→$n1（期望 +1）"; fi

# 10.② cwd 不匹配：名册登记 qa 于其它仓 ⇒ 不认领本仓未认领 pane
ac10_setup; c1="$(ac10_canary)"; n0="$(ac10_panes)"
OTHER_REPO="$FXROOT/otherrepo10"; mkdir -p "$OTHER_REPO"
ac10_env '[{"name":"qa","id":"qa","status":"idle","cwd":"'"$OTHER_REPO"'","tmuxPane":""}]'
run_fleet "$FIX" ensure qa
o="$(out_s)"; n1="$(ac10_panes)"
if grep -q '已在运行' <<< "$o"; then bad AC10 "② 名册 cwd 不匹配仍误判已在运行"; else pass AC10 "② 名册 cwd 不匹配 → 不认领"; fi
if grep -q '已拉起 qa' <<< "$o"; then pass AC10 "② 真拉起 qa"; else bad AC10 "② 未拉起 qa（$(oneline "$o")）"; fi
if [[ "$n1" == "$((n0+1))" ]]; then pass AC10 "② pane 数 $n0→$n1（+1）"; else bad AC10 "② pane 数 $n0→$n1（期望 +1）"; fi

# 10.③ 端到端：1 未认领 pane + 目标不在线 ⇒ 真拉起（修复前误跳过）
ac10_setup; c1="$(ac10_canary)"; n0="$(ac10_panes)"; ac10_env '[]'
run_fleet "$FIX" ensure qa
o="$(out_s)"; n1="$(ac10_panes)"
if grep -q '已在运行' <<< "$o"; then bad AC10 "③ 1 未认领 pane + 不在线 仍误判已在运行（T513f 回归）"; else pass AC10 "③ 未误判已在运行"; fi
if grep -q '已拉起 qa' <<< "$o"; then pass AC10 "③ 真拉起 qa（端到端）"; else bad AC10 "③ 未拉起 qa（$(oneline "$o")）"; fi
if [[ "$n1" == "$((n0+1))" ]]; then pass AC10 "③ pane 数 $n0→$n1（+1 真拉起的 pane 存活）"; else bad AC10 "③ pane 数 $n0→$n1（期望 +1）"; fi

# 10.④ 回归：目标在线 + 名册 tmuxPane 命中 ⇒ 判重跳过（层②完好）
ac10_setup; c1="$(ac10_canary)"; n0="$(ac10_panes)"
ac10_env '[{"name":"qa","id":"qa","status":"idle","cwd":"'"$FIX"'","tmuxPane":"'"$c1"'"}]'
run_fleet "$FIX" ensure qa
o="$(out_s)"; n1="$(ac10_panes)"
if grep -q '已在运行' <<< "$o"; then pass AC10 "④ 名册 tmuxPane 命中 → 判重跳过（层②完好）"; else bad AC10 "④ 未判重跳过（$(oneline "$o")）"; fi
if [[ "$n1" == "$n0" ]]; then pass AC10 "④ pane 数不变（$n0）"; else bad AC10 "④ pane 数 $n0→$n1（不应新增）"; fi
if tmux -S "$AC10_SOCK/sock" list-panes -t fx -F '#{pane_id}' 2>/dev/null | grep -qxF "$c1"; then pass AC10 "④ 被认领 pane $c1 仍存活（未误杀）"; else bad AC10 "④ 被认领 pane $c1 消失"; fi
[[ -n "$AC10_SOCK" ]] && tmux -S "$AC10_SOCK/sock" kill-server 2>/dev/null || true
fi

# =============================================================================
printf '\n==================== T513 汇总（模式=%s）====================\n' "$MODE"
for ac in "${AC_ORDER[@]}"; do
  p=${AC_P[$ac]:-0}; f=${AC_F[$ac]:-0}; s=${AC_S[$ac]:-0}; w=${AC_W[$ac]:-0}
  if (( f > 0 )); then st="RED"
  elif (( p > 0 )); then st="PASS"
  elif (( s > 0 )); then st="SKIP"
  else st="—"; fi
  printf '  %-4s %-5s PASS=%s FAIL=%s SKIP=%s WARN=%s\n' "$ac" "$st" "$p" "$f" "$s" "$w"
done
printf '\n  合计: PASS=%s FAIL=%s SKIP=%s WARN=%s\n' "$PASS_N" "$FAIL_N" "$SKIP_N" "$WARN_N"
if (( ${#FAILED[@]} > 0 )); then
  printf '  FAIL 明细:\n'
  for x in "${FAILED[@]}"; do printf '    - %s\n' "$x"; done
fi

if (( T4_MODE == 1 )); then
  if (( FAIL_N > 0 )); then printf '\nRESULT: FAIL · exit 1\n'; exit 1; fi
  if (( PASS_N == 0 )); then printf '\nRESULT: SKIP · exit 77\n'; exit 77; fi
  printf '\nRESULT: PASS · exit 0\n'; exit 0
fi
if (( FAIL_N > 0 )); then
  if [[ "$MODE" == baseline ]]; then
    printf '\nRESULT: %d FAIL（基线模式：修复前现树，FAIL 属预期）· exit 0\n' "$FAIL_N"; exit 0
  fi
  printf '\nRESULT: FAIL · exit 1\n'; exit 1
fi
printf '\nRESULT: PASS · exit 0\n'; exit 0
