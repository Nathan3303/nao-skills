#!/usr/bin/env bash
# =============================================================================
# T516 波4 · screen 侧行为用例（本机无 screen 二进制 ⇒ PATH 注入 stub screen）
#
# 判据（唯一）：PRD docs/prds/2026-10-13-close-anchor-safe-clean.md §三（AC1–AC4 屏侧同源）
#   + docs/reports/2026-10-13-T516-arch-review.md §五（F1/F2 修复验收）+ PM 波4 (e) 边界契约判定。
# 被测：<root>/.agents/scripts/nao-fleet.sh（本脚本不修改机制源码；stub 只在 /tmp 经 PATH）
#
# 覆盖：
#   AC-屏 (a) 仅派生 nao-<名>-T2 在场 → close 令牌空、零 -X quit、拒绝回收
#   AC-屏 (b) 仅精确 nao-<名> 在场   → 令牌 pid.nao-<名>、quit 恰 1 次且目标=精确
#   AC-屏 (c) 精确+派生并存          → 只 quit 精确、派生存活（F2 核心）
#   AC-屏 (d) spawn_screen 失败清理  → 仅派生在场时令牌空、零 quit（F1）
#   AC-屏 (e) 边界：-ls 行 pid.Xnao-<名>（名字以 nao-<名> 结尾但 ≠ nao-<名>）
#            契约：不得被当精确令牌（非目标会话不可回收/不误杀）；当前实现若取为令牌 ⇒ 红
#   F3-B3     cleanup -S 归一化：// 变体 / symlink / 真默认常量 ⇒ rc=2；隔离不存在 socket ⇒ rc=0 幂等
#
# 实验纪律（T515 血训）：全程 env -u TMUX；本脚本**不创建/不操作任何 tmux server**；
#   screen 仅 stub（PATH 注入 /tmp）；禁 kill-server / pkill 宽匹配；勿在承载自己会话的 tmux 内直接跑。
#
# 用法：env -u TMUX bash docs/reports/2026-10-13-T516-screen-regression.sh
#   输出：PASS/FAIL 明细 + 末行汇总；FAIL>0 ⇒ exit 1
# =============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLEET="$ROOT/.agents/scripts/nao-fleet.sh"
LAB="${T516_SCRLAB:-/tmp/t516-scr}"
STUB="$LAB/stub"
SOCKDIR="$LAB/sock"          # TMUX_TMPDIR 隔离位（无 server；裸 tmux 调用 rc=1 无害）
LOG="$LAB/screen.log"
STATE="$LAB/state.txt"

if [[ -n "${TMUX:-}" ]]; then
  echo "警告：检测到 $TMUX —— 勿在承载自己会话的 tmux 内跑本脚本（见纪律）" >&2
fi
[[ -f "$FLEET" ]] || { echo "未找到被测脚本: $FLEET" >&2; exit 2; }

rm -rf "$LAB"
mkdir -p "$STUB" "$SOCKDIR" "$LAB/.agents/scripts" "$LAB/.agents/prompts"
cp "$FLEET" "$LAB/.agents/scripts/"
cat > "$LAB/.agents/roles.yaml" <<'EOF'
roles:
  bugz:
    card: bugz.md
    aliases: [big, bugz]
EOF
printf -- '---\nrole: bugz\nversion: 1\nupdated: 2026-10-13\n---\n# bugz\n' > "$LAB/.agents/prompts/bugz.md"

# ---- stub screen（记录 argv；-ls 按 state 回放 pid.name；-S <token> -X quit 模拟销毁）----
cat > "$STUB/screen" <<'SH'
#!/usr/bin/env bash
log="${T516_SCR_LOG:-/dev/null}"; st="${T516_SCR_STATE:-/dev/null}"
printf 'screen %s\n' "$*" >>"$log"
case "${1:-}" in
  -ls)
    n=0
    while IFS= read -r nm; do
      [[ -n "$nm" ]] || continue
      n=$((n+1)); printf '     %d.%s    (Detached)\n' "$((10000+n))" "$nm"
    done <"$st"
    printf '1 Socket in /run/screen/S-%s.\n' "$(id -un)"
    exit 0 ;;
  -dmS) exit 0 ;;                                  # 记录于 log；在场与否由测试预置 state 决定
  -S)  # -S <token> -X quit：从 state 移除 token 中第一个点之后的会话名（模拟销毁）
    t="${2:-}"
    case "$t" in
      *.*) nm="${t#*.}" ;;
      *)   nm="$t" ;;
    esac
    if [[ -s "$st" ]]; then
      grep -vxF -- "$nm" "$st" > "$st.tmp" 2>/dev/null || true
      mv "$st.tmp" "$st"
    fi
    exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$STUB/screen"

P=0; F=0
ok()  { P=$((P+1)); printf '  PASS  %s\n' "$1"; }
bad() { F=$((F+1)); printf '  FAIL  %s\n' "$1"; }

OUT=""; RC=0
run_fleet() {  # 在 lab 仓以 stub PATH + 隔离 TMUX_TMPDIR 跑 fleet
  OUT="$(cd "$LAB" && env -u TMUX -u TMUX_PANE TMUX_TMPDIR="$SOCKDIR" PATH="$STUB:$PATH" \
         NAO_TERMINAL=screen T516_SCR_LOG="$LOG" T516_SCR_STATE="$STATE" \
         bash .agents/scripts/nao-fleet.sh "$@" 2>&1)"; RC=$?
}
reset() { : >"$LOG"; : >"$STATE"; }
set_state() { printf '%s\n' "$1" >"$STATE"; grep -v '^$' "$STATE" >"$STATE.t" 2>/dev/null && mv "$STATE.t" "$STATE"; }
state_has() { grep -qxF "$1" "$STATE" 2>/dev/null; }
quit_lines() { grep -c " -X quit" "$LOG" 2>/dev/null || true; }
quit_tokens() { grep -- "-S " "$LOG" | sed -E 's/.*-S ([^ ]+) -X quit.*/\1/' ; }

echo "== (a) 仅派生 nao-bugz-T2 在场：close bugz → 令牌空、零 -X quit（AC3 屏侧重） =="
reset; set_state "nao-bugz-T2"
run_fleet close bugz
if [[ "$(quit_lines)" == 0 ]] && [[ "$OUT" != *已回收* ]] && [[ "$OUT" == *拒绝回收* ]]; then
  ok "(a) 令牌空+0 quit+拒绝回收（rc=$RC）"
else bad "(a)（rc=$RC / quits=$(quit_lines)）$OUT"; fi
if state_has "nao-bugz-T2"; then ok "(a) 派生 nao-bugz-T2 存活"; else bad "(a) 派生被误杀"; fi

echo "== (b) 仅精确 nao-bugz 在场：close bugz → quit 恰 1 次、目标=精确令牌 =="
reset; set_state "nao-bugz"
run_fleet close bugz
qt="$(quit_tokens)"
if [[ "$RC" == 0 && "$(quit_lines)" == 1 && "$qt" == "10001.nao-bugz" ]] && [[ "$OUT" == *已回收* ]]; then
  ok "(b) rc=0 已回收 · quit=$qt"
else bad "(b)（rc=$RC / quits=$(quit_lines) / token=$qt）$OUT"; fi
if ! state_has "nao-bugz"; then ok "(b) 精确会话已销毁"; else bad "(b) 精确仍存活"; fi

echo "== (c) 精确+派生并存：close bugz → 只 quit 精确，派生存活（F2 核心） =="
reset; set_state "nao-bugz
nao-bugz-T2"
run_fleet close bugz
qt="$(quit_tokens)"
if [[ "$(quit_lines)" == 1 && "$qt" == "10001.nao-bugz" ]] && [[ "$OUT" == *已回收* ]]; then
  ok "(c) 只 quit 精确（$qt）"
else bad "(c)（rc=$RC / quits=$(quit_lines) / token=$qt）$OUT"; fi
if state_has "nao-bugz-T2" && ! state_has "nao-bugz"; then
  ok "(c) 派生存活、精确已销毁"
else bad "(c) 会话状态：$(tr '\n' ' ' < "$STATE")"; fi

echo "== (d) spawn_screen 失败清理（F1）：仅派生在场 → 零 quit（令牌空不误伤） =="
reset; set_state "nao-bugz-T2"
run_fleet ensure bugz
if grep -q -- "-dmS nao-bugz" "$LOG"; then ok "(d) 有拉起尝试（-dmS nao-bugz）"; else bad "(d) 未见 -dmS 尝试"; fi
if [[ "$(quit_lines)" == 0 ]]; then ok "(d) 失败清理 0 次 -X quit（令牌空）"; else bad "(d) quits=$(quit_lines)：$(quit_tokens)"; fi
if [[ "$OUT" != *已拉起* ]]; then ok "(d) 未谎报已拉起"; else bad "(d) 幻影成功：$OUT"; fi

echo "== (e) 边界：-ls 行 pid.Xnao-bugz（名字以 nao-bugz 结尾但 ≠ nao-bugz） =="
echo "   契约：Xnao-bugz 不是目标会话 ⇒ 不得取为令牌、不得 quit、不得误回收（PM 波4 逐条判定）"
reset; set_state "Xnao-bugz"
run_fleet close bugz
qt="$(quit_tokens)"
if [[ "$(quit_lines)" == 0 ]] && [[ "$OUT" != *已回收* ]]; then
  ok "(e1) close：Xnao-bugz 未被当精确令牌（0 quit）"
else bad "(e1) 误杀非目标会话：quit=$qt · rc=$RC · $OUT"; fi
if state_has "Xnao-bugz"; then ok "(e1) Xnao-bugz 存活"; else bad "(e1) 非目标会话被销毁"; fi

reset; set_state "Xnao-bugz"
run_fleet ensure --force bugz
if [[ "$RC" != 0 ]] || [[ "$OUT" != *已拉起* ]]; then
  ok "(e2) spawn（--force）：Xnao-bugz 不构成拉起成功判据（rc=$RC）"
else bad "(e2) 幻影成功：stub -dmS 无动作（nao-bugz 未真实出现）但 rc=0 已拉起（把 Xnao-bugz 当 nao-bugz）"; fi

reset; set_state "Xnao-bugz
nao-bugz"
run_fleet close bugz
qt="$(quit_tokens)"
if [[ "$(quit_lines)" == 1 && "$qt" == "10002.nao-bugz" ]] && state_has "Xnao-bugz" && ! state_has "nao-bugz"; then
  ok "(e3) 混排：令牌解析到精确（10002.nao-bugz）、junk 存活、精确销毁"
else bad "(e3)（quits=$(quit_lines) / token=$qt / state=$(tr '\n' ' ' < "$STATE")）——head -1 序依赖会把 junk 当令牌"; fi

# ---- F3-B3：cleanup -S 归一化（不经任何 server；拒绝路径不会碰到 socket）----
echo "== F3-B3 cleanup -S 归一化 =="
FC() {  # $1=sock → 输出 "rc|首行"
  local o r
  o="$(cd "$LAB" && env -u TMUX -u TMUX_PANE bash .agents/scripts/nao-fleet.sh cleanup -S "$1" 2>&1)"; r=$?
  printf '%s|%s' "$r" "$(printf '%s' "$o" | head -1)"
}
ln -sf /tmp/tmux-$(id -u)/default "$LAB/symlink-default" 2>/dev/null || true
mkdir -p "$LAB/f3b3"
r="$(FC "/tmp//tmux-$(id -u)/default")"
if [[ "$r" == 2* && "$r" == *"默认 socket"* ]]; then ok "F3-B3 // 变体 ⇒ rc=2 拒绝（$r）"; else bad "F3-B3 // 变体（$r）"; fi
r="$(FC "$LAB/symlink-default")"
if [[ "$r" == 2* && "$r" == *"默认 socket"* ]]; then ok "F3-B3 symlink⇒生产候选 ⇒ rc=2 拒绝（$r）"; else bad "F3-B3 symlink（$r）"; fi
r="$(FC "/tmp/tmux-$(id -u)/default")"
if [[ "$r" == 2* && "$r" == *"默认 socket"* ]]; then ok "F3-B3 真默认常量 ⇒ rc=2 拒绝"; else bad "F3-B3 真默认常量（$r）"; fi
r="$(FC "$LAB/f3b3/nonexistent.sock")"
if [[ "$r" == 0* && ( "$r" == *幂等* || "$r" == *不存在* || "$r" == *"无 server"* ) ]]; then
  ok "F3-B3 隔离不存在 socket ⇒ rc=0 幂等（$r）"
else bad "F3-B3 幂等（$r）"; fi

printf '== T516 屏侧回归汇总：PASS=%d FAIL=%d ==\n' "$P" "$F"
(( F == 0 )) || exit 1