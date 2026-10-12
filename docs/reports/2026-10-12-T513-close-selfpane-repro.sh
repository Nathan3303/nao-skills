#!/usr/bin/env bash
# =============================================================================
# T513 事故复现夹具：close 自伤（kill 调用者自己的 tmux pane / 窗口消失）
#
# 结论摘要（本脚本可独立复跑）：
#   - H1 成立：close 走 find_pane_for_any_repo() 层②（名册 tmuxPane）时，若该 pane
#     等于调用者自己的 $TMUX_PANE（子进程派生时继承了 TMUX_PANE 并据此注册名册），
#     close 会 `tmux kill-pane -t <调用者自己的 pane>` ⇒ 自杀；若该 pane 是同窗口
#     最后一个 pane，则整个 tmux 窗口消失。
#   - 既有缺陷，非 T513 引入：main(0.13.0) / a28b11d / 04baea2 三版同一夹具下均复现。
#   - T513 放大触发面：新增 ④ xdg-window / nao:foot|ghostty|ptyxis 等「从 pane 内
#     派生可见窗口」路径，子进程同样继承 TMUX_PANE。
#   - T513-S2 修复（HEAD）：F1 close 自 pane 不变量 + F2 窗口/screen 宿主派生前清
#     TMUX/TMUX_PANE ⇒ A 段不再自伤、B 段 pi 侧不再继承（见下表，修复前/后同产物对照）。
#
# 安全性：全程只用 /tmp 夹具 + PATH 前置的桩（真实 tmux server / 真实名册零接触）；
#   `kill` 由 BASH_ENV 注入的日志桩接管（只记录 argv，不执行）。
#
# 用法：bash docs/reports/2026-10-12-T513-close-selfpane-repro.sh [rev ...]
#   默认 rev：main a28b11d 04baea2 HEAD（HEAD=修复后；需在 nao-skills 仓库内运行）
# =============================================================================
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SBX="${T513_SBX:-/tmp/nao-t513-repro}"
CALLER_PANE='%99'          # 模拟调用者（pm）自己的 tmux pane

if [[ $# -gt 0 ]]; then REVS=("$@"); else REVS=(main a28b11d 04baea2 HEAD); fi
is_fix() { [[ "$1" == HEAD || "$1" == fix ]]; }
# 收尾用：记录脚本启动前已有的 /tmp nao-fleet 临时件（prompt .md + pidfile），结束时只清本夹具新产生的
ls -1 /tmp/nao-fleet-*.md /tmp/nao-fleet-*-pid-* 2>/dev/null | sort -u > /tmp/.t513-pre.$$ || :

rm -rf "$SBX"
mkdir -p "$SBX"/{bin,minbin,agent/npm/node_modules/tsx/dist,versions,home,repo,fakebin} "$SBX/fixture"
FIX="$SBX/fixture"; AGENT="$SBX/agent"; BIN="$SBX/bin"
NODEDIR="$(dirname "$(command -v node)")"

# 最小 PATH（无 tmux，用于强制 ④ xdg-window）
for c in awk sed grep mktemp setsid sleep cat rm wc head tail ps pgrep pkill tr \
         dirname basename env timeout screen nohup date id uname sh bash readlink \
         realpath stat find xargs sort uniq cut tee mkdir chmod mv ln; do
  p="$(command -v "$c" 2>/dev/null)" && ln -sf "$p" "$SBX/minbin/$c" || true
done

cp -r "$ROOT/.agents" "$FIX/.agents"
printf 'fake tasks state\n' > "$FIX/tasks-state.md"
touch "$FIX/.agents/scripts/intercom-probe.mts"

# ---- 桩 tmux：调用者自己的 pane = 桩自身 env 的 $TMUX_PANE；记录全部 argv ----
cat > "$BIN/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'TMUX_ARGV: %s\n' "$*" >> "${SBX_LOG:?}"
case "$1 $2" in
  "list-panes -a")
      fmt=""; for a in "$@"; do case "$a" in \#\{*) fmt="$a";; esac; done
      if [[ "$fmt" == *pane_title* ]]; then exit 0; fi
      if [[ "$fmt" == *pane_current_command* ]]; then exit 0; fi
      [[ -n "${NAO_SBX_PANE:-${TMUX_PANE:-}}" ]] && echo "${NAO_SBX_PANE:-$TMUX_PANE}"; exit 0 ;;
  "list-panes -F")   [[ -n "${TMUX_PANE:-}" ]] && echo "${TMUX_PANE#%}"; exit 0 ;;
  "capture-pane -p") exit 0 ;;
  "display-message -p")
      for a in "$@"; do
        case "$a" in *pane_current_path*) echo "${SBX_REPO:-/tmp}"; exit 0;;
                     *pane_pid*) echo "${SBX_PANE_PID:-}"; exit 0;; esac
      done; exit 0 ;;
  "kill-pane -t")
      printf 'KILL-PANE-TARGET: %s\n' "$3" >> "${SBX_KILLPANE_LOG:-$SBX_LOG}"
      [[ -n "${SBX_KILLPANE_FAIL:-}" ]] && exit 1; exit 0 ;;
  "has-session -t") exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$BIN/tmux"

# ---- 窗口宿主桩：记录自身 env，并真正 exec 其承载的命令（使下游 pi 桩可观测其 env）----
make_host_stub() {
cat > "$BIN/$1" <<'EOF'
#!/usr/bin/env bash
{ echo "== $(basename "$0") argv: $*"; env | grep -E '^(TMUX|TMUX_PANE|NAO_TERMINAL|WAYLAND_DISPLAY)=' | sort; } >> "${SBX_ENVLOG:?}"
case " $* " in *" --print-id "*) echo "sbx-id"; exit 0;; esac   # 探针不承载 pi，不参与断言
args=("$@"); exec_args=(); i=0
while (( i < ${#args[@]} )); do
  case "${args[i]}" in -e|--) exec_args=("${args[@]:i+1}"); break;; esac
  i=$((i+1))
done
if (( ${#exec_args[@]} )); then exec "${exec_args[@]}"; fi
exec sleep 3
EOF
chmod +x "$BIN/$1"
}
for w in foot ghostty ptyxis xdg-terminal-exec; do make_host_stub "$w"; done
for f in "$BIN"/*; do b="$(basename "$f")"; [[ "$b" == tmux ]] && continue; ln -sf "$f" "$SBX/minbin/$b"; done

# pi 桩：落盘「将成为 pi 的进程」所见 env（B 段断言以此为据）
cat > "$BIN/pi" <<'EOF'
#!/usr/bin/env bash
{ echo "== pi argv: $*"; env | grep -E '^(TMUX|TMUX_PANE|NAO_TERMINAL|WAYLAND_DISPLAY)=' | sort; } >> "${SBX_PI_ENVLOG:?}"
exec sleep 3
EOF
chmod +x "$BIN/pi"
ln -sf "$BIN/pi" "$SBX/minbin/pi"

# screen-bg 专用 bin：无 tmux/xdg/窗口宿主，仅 stateful screen 桩（QA 的 screen 桩无条件回放
# nao-qa 会话 ⇒ running 短路不派生；此处用状态文件避免该陷阱）
mkdir -p "$SBX/bin-sbg"
for f in "$SBX/minbin"/*; do b="$(basename "$f")"; case "$b" in foot|ghostty|ptyxis|xdg-terminal-exec|screen) continue;; esac; ln -sf "$f" "$SBX/bin-sbg/$b"; done
cat > "$SBX/bin-sbg/screen" <<'EOF'
#!/usr/bin/env bash
{ echo "== screen argv: $*"; env | grep -E '^(TMUX|TMUX_PANE|NAO_TERMINAL)=' | sort; } >> "${SBX_ENVLOG:-/dev/null}"
st="${SBX_SCREEN_STATE:-/tmp/sbx-screen.state}"
case "${1:-}" in
  -ls) [[ -f "$st" ]] && echo "    12345.nao-qa   (Detached)"; exit 0 ;;
  -dmS) shift; echo "${1:-}" > "$st"; shift || true; setsid -f "$@" >/dev/null 2>&1; exit 0 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$SBX/bin-sbg/screen"

# 假名册：tmuxPane = 该进程继承到的 $TMUX_PANE（等价于 pi-intercom 注册时读 TMUX_PANE）
cat > "$AGENT/npm/node_modules/tsx/dist/cli.mjs" <<'EOF'
const pane = (process.env.NAO_SBX_PANE || process.env.TMUX_PANE || "").trim();
const sessions = [{ name: process.env.NAO_SBX_TARGET || "rd-be", id: "fake", model: "m",
  status: "idle", cwd: process.env.NAO_SBX_CWD || "/tmp", tmuxPane: pane || null, pid: 0 }];
process.stdout.write(JSON.stringify({ ok: true, sessions }, null, 2));
EOF

# BASH_ENV：接管 builtin `kill`，只记录 argv（不执行任何 kill）
cat > "$SBX/kill-log.bash" <<'EOF'
if [[ -n "${SBX_KILL_LOG:-}" ]]; then
  kill() { printf 'KILL-ARGV: %s\n' "$*" >> "$SBX_KILL_LOG"; return 0; }
fi
EOF

cd "$ROOT"
for rev in "${REVS[@]}"; do
  if is_fix "$rev" && [[ -n "${T513_FIX_FROM_WORKTREE:-}" ]]; then
    cp "$ROOT/.agents/scripts/nao-fleet.sh" "$SBX/versions/${rev}.sh"   # 未提交时先验证工作树
  else
    git show "$rev:.agents/scripts/nao-fleet.sh" > "$SBX/versions/${rev}.sh"
  fi
done

run_close() {  # <rev> <label> [close args...]
  local rev="$1" label="$2"; shift 2
  local log="$SBX/argv-$label.log" kl="$SBX/kill-$label.log"
  : > "$log"; : > "$kl"
  env -i PATH="$BIN:$NODEDIR:/usr/bin:/bin" HOME="$SBX/home" \
      NAO_SKILLS="$FIX" PI_CODING_AGENT_DIR="$AGENT" NAO_TASKS_STATE="$FIX/tasks-state.md" \
      SBX_LOG="$log" SBX_KILL_LOG="$kl" SBX_KILLPANE_LOG="$log" SBX_REPO="$SBX/repo" \
      NAO_SBX_TARGET=rd-be NAO_SBX_CWD="$SBX/repo" NAO_SBX_PANE="${NAO_SBX_PANE:-}" \
      SBX_KILLPANE_FAIL="${SBX_KILLPANE_FAIL:-}" SBX_PANE_PID="${SBX_PANE_PID:-}" \
      TMUX="/tmp/nao-sbx-fake-sock,4242,0" TMUX_PANE="$CALLER_PANE" \
      BASH_ENV="$SBX/kill-log.bash" \
      bash "$SBX/versions/$rev.sh" close rd-be "$@" >"$SBX/out-$label.txt" 2>&1 || true
}

run_spawn() {  # <rev> <ladder: foot|ghostty|xdg|screen>
  local rev="$1" ladder="$2" envlog="$SBX/env-$rev-$ladder.log" pielog="$SBX/pienv-$rev-$ladder.log"
  : > "$envlog"; : > "$pielog"
  local nao="" way="" prefix="$BIN:$NODEDIR:/usr/bin:/bin"; local -a extra=()
  case "$ladder" in
    xdg)    prefix="$SBX/minbin:$NODEDIR"; way="WAYLAND_DISPLAY=wayland-sbx" ;;
    screen) prefix="$SBX/bin-sbg:$NODEDIR"; : > "$SBX/screen.state"; if grep -q -- '--background' "$SBX/versions/$rev.sh"; then extra=(--background); fi ;;
    *)      nao="NAO_TERMINAL=$ladder" ;;
  esac
  env -i PATH="$prefix" HOME="$SBX/home" NAO_SKILLS="$FIX" PI_CODING_AGENT_DIR="$AGENT" \
      NAO_TASKS_STATE="$FIX/tasks-state.md" SBX_ENVLOG="$envlog" SBX_PI_ENVLOG="$pielog" \
      SBX_SCREEN_STATE="$SBX/screen.state" $nao $way \
      TMUX="/tmp/nao-sbx-fake-sock,4242,0" TMUX_PANE="$CALLER_PANE" \
      bash "$SBX/versions/$rev.sh" ensure "${extra[@]}" rd-be >>"$SBX/spawn-$rev-$ladder.txt" 2>&1 || true
  local tries=60; while (( tries-- > 0 )); do [[ -s "$pielog" ]] && break; sleep 0.1; done
}

echo "==================== A. close 自伤（修复前/后同产物对照）===================="
printf '%-10s %-14s %s\n' REV 判定 证据
A_RC=0
for rev in "${REVS[@]}"; do
  run_close "$rev" "$rev" --force
  tgt="$( { grep -h 'KILL-PANE-TARGET' "$SBX/argv-$rev.log" || true; } | awk '{print $2}' | head -1)"
  if is_fix "$rev"; then
    if grep -q '拒绝回收' "$SBX/out-$rev.txt" && [[ "$tgt" != "$CALLER_PANE" ]]; then
      printf '%-10s %-14s %s\n' "$rev" '不再自伤 ✓' "close 打印拒绝诊断；未 kill-pane（tgt=${tgt:-<无>}）"
    else
      printf '%-10s %-14s %s\n' "$rev" '未修复 ✗' "kill-pane -t ${tgt:-<无>}"; A_RC=1
    fi
  else
    if [[ "$tgt" == "$CALLER_PANE" ]]; then
      printf '%-10s %-14s %s\n' "$rev" '自伤复现 ✓' "kill-pane -t $CALLER_PANE（调用者自己的 pane）"
    else
      printf '%-10s %-14s %s\n' "$rev" '未复现 ✗' "kill-pane -t ${tgt:-<无>}"; A_RC=1
    fi
  fi
done

echo
echo "==================== B. 派生窗口 pi 进程 env（TMUX_PANE 继承面）===================="
spawn_matrix() { case "$1" in main) echo 'ghostty screen';; a28b11d) echo 'ghostty foot screen';; *) echo 'ghostty foot screen xdg';; esac; }
printf '%-10s %-8s %s\n' REV 宿主 '子进程(pi)侧'
for rev in "${REVS[@]}"; do
  for ladder in $(spawn_matrix "$rev"); do
    run_spawn "$rev" "$ladder"
    has=no; grep -q "^TMUX_PANE=$CALLER_PANE\$" "$SBX/pienv-$rev-$ladder.log" && has=yes
    if is_fix "$rev"; then
      if [[ "$has" == no ]]; then v='已清除 ✓（pi 无 TMUX_PANE）'; else v='仍继承 ✗'; A_RC=1; fi
    else
      if [[ "$has" == yes ]]; then v='继承 TMUX_PANE ✓'; else v='未继承 ✗'; A_RC=1; fi
    fi
    printf '%-10s %-8s %s\n' "$rev" "$ladder" "$v"
  done
done

echo
echo "==================== C. kill 兜底 argv（kill-pane 失败时；目标 pane=%77 ≠ 调用者 %99）===================="
NAO_SBX_PANE='%77' SBX_KILLPANE_FAIL=1 run_close "${REVS[-1]}" pidsempty --force   # 非自身 pane；无 pi 子进程 ⇒ pids 空
printf 'pids 空：kill(1) 调用 = %s（guard `[[ -n $pids ]]` 应拦住 → no-arg 未发生）\n' \
  "$(grep -c 'KILL-ARGV' "$SBX/kill-pidsempty.log" || true)"
cp /usr/bin/sleep "$SBX/fakebin/pi"; chmod +x "$SBX/fakebin/pi"
"$SBX/fakebin/pi" 120 & PIDP=$!; sleep 0.3
NAO_SBX_PANE='%77' SBX_KILLPANE_FAIL=1 SBX_PANE_PID="$PIDP" run_close "${REVS[-1]}" pidspresent --force
printf 'pids 非空：kill(1) argv = %s（应为真实 pid，非 0/空）\n' \
  "$( { grep -h 'KILL-ARGV' "$SBX/kill-pidspresent.log" || true; } | head -1 | awk '{print $2}')"
kill "$PIDP" 2>/dev/null || true

echo
echo "==================== 原始证据（修复前 vs 修复后 argv 日志）===================="
for rev in "${REVS[@]}"; do echo "--- $rev ---"; cat "$SBX/argv-$rev.log"; done
echo "夹具目录: $SBX"
echo "总判定: $([[ $A_RC -eq 0 ]] && echo PASS || echo 'FAIL（见上 ✗）')"
# 收尾：只删本夹具新产生的 /tmp nao-fleet 临时件（prompt .md + pidfile；避免污染 verify.sh AC6/AC14 的快照断言）
ls -1 /tmp/nao-fleet-*.md /tmp/nao-fleet-*-pid-* 2>/dev/null | sort -u > /tmp/.t513-post.$$ || :
comm -13 /tmp/.t513-pre.$$ /tmp/.t513-post.$$ 2>/dev/null | while IFS= read -r f; do [[ -n "$f" ]] && rm -f -- "$f"; done
rm -f /tmp/.t513-pre.$$ /tmp/.t513-post.$$
exit "$A_RC"
