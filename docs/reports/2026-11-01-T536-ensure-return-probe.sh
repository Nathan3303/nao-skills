#!/usr/bin/env bash
# T536 一次性只读探针 —— `ensure` 返回不再被 60s 后台清理拖住
#
# 用途（PRD docs/prds/2026-11-01-ensure-return.md §七 验证接缝）：
#   AC1 返回不阻塞      : 重定向 vs 经管道（`| cat`）耗时差 < 2s 且管道耗时 < 15s
#   AC2 清理与无副作用  : prompt_file 拉起后存在 → ~65s 后消失；返回后无进程持有调用方 fd；
#                         反例（临时副本回退旧写法）⇒ 管道耗时 ≥55s 且 AC1 判据 FAIL（证明探针有效）
#   AC4 输出契约        : 旧行为输出行 ⊆ 新输出行（顺序不变，只多恰 1 行就绪提示）；
#                         多角色一次调用仍 1 行；跳过分支不打印
#
# 只读纪律：
#   · 不写仓库（只读被测脚本 + 在 $LAB 下建临时副本/夹具）；不开真 pi —— PATH 前置 stub `pi`（sleep），
#     故不产生会话名册注册、不打扰真舰队。
#   · tmux 用**隔离 socket**（$LAB 下，且硬护栏排除生产默认候选），收尾 kill-server。
#   · 零网络。
#
# 用法：bash docs/reports/2026-11-01-T536-ensure-return-probe.sh
# 退出码：0 = 全部 PASS；1 = 有 FAIL
set -uo pipefail

ROOT="${NAO_SKILLS:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SUBJ="$ROOT/.agents/scripts/nao-fleet.sh"
[ -f "$SUBJ" ] || { echo "被测脚本不存在: $SUBJ" >&2; exit 1; }
command -v tmux >/dev/null 2>&1 || { echo "环境缺少 tmux（本探针需要隔离 server）" >&2; exit 1; }

LAB="$(mktemp -d "/tmp/nao-t536-probe.XXXXXX")" || exit 1
SOCK="$LAB/sock"
REPO="$LAB/repo"; mkdir -p "$REPO"
STUB="$LAB/stub"; mkdir -p "$STUB/bin"
printf '#!/bin/sh\nexec sleep 900\n' > "$STUB/bin/pi"; chmod +x "$STUB/bin/pi"
export PATH="$STUB/bin:$PATH"
export NAO_SKILLS="$ROOT"

# ---- 护栏：隔离 socket 不得等于生产默认候选 ---------------------------------
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${TMUX%%,*}"; do
  [ -n "$p" ] && [ "$SOCK" = "$p" ] && { echo "护栏触发：SOCK=$SOCK 等于生产默认候选" >&2; exit 1; }
done

PASS=0; FAIL=0
ok()   { PASS=$((PASS + 1)); printf '  [PASS] %s\n' "$*"; }
bad()  { FAIL=$((FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
info() { printf '  -- %s\n' "$*"; }

NEW_PROMPTS=()
cleanup() {
  tmux -S "$SOCK" kill-server 2>/dev/null || true
  for f in "${NEW_PROMPTS[@]:-}"; do [ -n "$f" ] && rm -f -- "$f"; done
  rm -rf -- "$LAB"
}
trap cleanup EXIT

tmux -S "$SOCK" new-session -d -s t536probe -x 220 -y 60 'sleep 3600' \
  || { echo "隔离 tmux server 启动失败: $SOCK" >&2; exit 1; }
SPID="$(tmux -S "$SOCK" display -p '#{pid}')"
SID="$(tmux -S "$SOCK" display -p -t t536probe '#{session_id}')"; SID="${SID#\$}"
PANE="$(tmux -S "$SOCK" list-panes -t t536probe -F '#{pane_id}' | head -1)"
export TMUX="$SOCK,$SPID,$SID"
export TMUX_PANE="$PANE"
info "隔离 server: $SOCK（pid=$SPID sess=$SID pane=$PANE）· 夹具 repo=$REPO · stub pi（不启动真会话）"

now_ms() { date +%s%3N; }
prompt_set() { ls /tmp/nao-fleet-*.md 2>/dev/null | sort; }
strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g' "$1"; }

# 单次 ensure 计时；<mode>=redir|pipe；任务号复用 <tag>（作 --task）；结果写 $LAB/out-<tag>.txt，耗时写 LAST_MS，新 prompt_file 记入 NEW_PROMPTS
LAST_MS=0
run_ensure() {  # <script> <mode> <tag(=--task 任务号)> [角色@repo...]
  local script="$1" mode="$2" tag="$3"; shift 3
  local base new t0 t1
  base="$(prompt_set)"
  t0="$(now_ms)"
  if [ "$mode" = pipe ]; then
    bash "$script" ensure --task "$tag" "$@" 2>&1 | cat > "$LAB/out-$tag.txt"
  else
    bash "$script" ensure --task "$tag" "$@" > "$LAB/out-$tag.txt" 2>&1
  fi
  t1="$(now_ms)"
  LAST_MS=$((t1 - t0))
  new="$(comm -13 <(printf '%s\n' "$base") <(prompt_set) | grep . || true)"
  if [ -n "$new" ]; then
    local f
    while IFS= read -r f; do NEW_PROMPTS+=("$f"); done <<< "$new"
  fi
  LAST_NEW="$new"
  info "[$tag] $mode 耗时 ${LAST_MS}ms · 新增 prompt_file=$(printf '%s' "$new" | grep -c . || true)"
  # 卫生：回收本次拉起的 pane（均跑 stub pi），避免累计 pane 把宿主窗口漫溢影响后续分屏
  local p
  for p in $(tmux -S "$SOCK" list-panes -t t536probe -F '#{pane_id}' | tail -n +2); do
    tmux -S "$SOCK" kill-pane -t "$p" >/dev/null 2>&1 || true
  done
}

# ---- 反例夹具：临时副本回退旧写法（就地不改仓库）---------------------------
# 回退两处：① 后台清理旧写法（A 项被测对象）② 撤掉就绪提示（C 项），使本副本等价于 T536 前行为 ——
# 其中 ② 让“旧行为输出行”成为 AC4 快照比对的基线（不依赖 git HEAD，探针可长期重跑）。
OLD_LINE_FILE="$LAB/old-line.txt"
cat > "$OLD_LINE_FILE" <<'EOF'
  ( sleep 60; rm -f -- "$prompt_file" ) & disown 2>/dev/null || true
EOF
MUT="$LAB/mutant-nao-fleet.sh"
awk -v oldfile="$OLD_LINE_FILE" '
  BEGIN { while ((getline l < oldfile) > 0) old = l }
  /sleep 60; rm -f/ && /\/dev\/null/ { print old; next }
  /就绪后在线状态用 nao-fleet\.sh status 查看/ { print "    :   # T536 提示已在 mutant 中回退"; next }
  { print }
' "$SUBJ" > "$MUT"
chmod +x "$MUT"

echo "== 0. 反例夹具（旧写法副本）=="
mut_old="$(grep -c 'sleep 60; rm -f -- "\$prompt_file" ) & disown' "$MUT" || true)"
mut_new="$(grep -c '/dev/null 2>&1 </dev/null' "$MUT" || true)"
mut_hint="$(grep -c '就绪后在线状态用 nao-fleet.sh status 查看' "$MUT" || true)"
info "mutant=$MUT · 旧写法命中=$mut_old · 新写法命中=$mut_new · 就绪提示残留=$mut_hint"
if [ "${mut_old:-0}" -eq 1 ] && [ "${mut_new:-0}" -eq 0 ] && [ "${mut_hint:-0}" -eq 0 ]; then
  ok "反例夹具构造成功（1 处旧写法、0 处新写法、0 处就绪提示；仓库文件未被改动）"
else
  bad "反例夹具构造失败（旧写法=$mut_old 新写法=$mut_new；被测脚本已是旧写法？）"
fi

echo "== 1. 修复前（旧写法副本）耗时 =="
run_ensure "$MUT" redir T536O1 rd-infra@"$REPO"
OLD_REDIR_MS=$LAST_MS
run_ensure "$MUT" pipe T536O2 rd-infra@"$REPO"
OLD_PIPE_MS=$LAST_MS
[ "$OLD_PIPE_MS" -ge 55000 ] \
  && ok "反例命中：旧写法经管道 ${OLD_PIPE_MS}ms ≥ 55000ms（60s 窗口被计入返回）" \
  || bad "反例未命中：旧写法经管道仅 ${OLD_PIPE_MS}ms（应 ≥55s）"
OLD_DIFF=$((OLD_PIPE_MS - OLD_REDIR_MS))
[ "$OLD_DIFF" -ge 2000 ] \
  && ok "反例命中：旧写法 AC1 判据 '差值 < 2s' FAIL（差 ${OLD_DIFF}ms）" \
  || bad "反例未命中：旧写法 AC1 差值仅 ${OLD_DIFF}ms"
info "反例耗时对照：重定向 ${OLD_REDIR_MS}ms vs 管道 ${OLD_PIPE_MS}ms"

echo "== 2. 修复后（被测脚本）耗时（AC1）=="
run_ensure "$SUBJ" redir T536F1 rd-infra@"$REPO"
FIX_REDIR_MS=$LAST_MS
run_ensure "$SUBJ" pipe T536F2 rd-infra@"$REPO"
FIX_PIPE_MS=$LAST_MS
FIX_PIPE_NEW="$LAST_NEW"
FIX_DIFF=$((FIX_PIPE_MS - FIX_REDIR_MS))
[ "$FIX_DIFF" -lt 0 ] && FIX_DIFF=$((0 - FIX_DIFF))
info "修复后耗时对照：重定向 ${FIX_REDIR_MS}ms vs 管道 ${FIX_PIPE_MS}ms（差 ${FIX_DIFF}ms）"
[ "$FIX_DIFF" -lt 2000 ] \
  && ok "AC1-① 重定向/管道耗时差 ${FIX_DIFF}ms < 2000ms" \
  || bad "AC1-① 重定向/管道耗时差 ${FIX_DIFF}ms ≥ 2000ms"
[ "$FIX_PIPE_MS" -lt 15000 ] \
  && ok "AC1-② 经管道耗时 ${FIX_PIPE_MS}ms < 15000ms" \
  || bad "AC1-② 经管道耗时 ${FIX_PIPE_MS}ms ≥ 15000ms"

echo "== 3. 清理与无副作用（AC2）=="
[ -n "$FIX_PIPE_NEW" ] \
  && ok "AC2-① 拉起后 prompt_file 存在：$(printf '%s' "$FIX_PIPE_NEW" | tr '\n' ' ')" \
  || bad "AC2-① 拉起后未发现 prompt_file（清理过早或未创建）"

holders="$(pgrep -f "nao-fleet.sh ensure --task T536F2" || true)"
[ -z "$holders" ] \
  && ok "AC2-③ 返回后无残留脚本进程（pgrep -f 'ensure --task T536F2' = 0）" \
  || bad "AC2-③ 返回后仍有脚本进程: $holders"
# 清理进程必须仍在（BR1），且不得持有调用方 pipe fd（按本次 prompt_file 路径精确匹配，不误伤他 run）
f2file="$(printf '%s' "$FIX_PIPE_NEW" | head -1)"
cleaners=""
pipe_fds=0
if [ -n "$f2file" ]; then
  cleaners="$(pgrep -f "$f2file" || true)"
  for p in $cleaners; do
    n="$(ls -l "/proc/$p/fd" 2>/dev/null | awk '{print $NF}' | grep -c 'pipe:' || true)"
    pipe_fds=$((pipe_fds + n))
  done
fi
info "清理进程 pids=[${cleaners//$'\n'/ }] · 其持有的 pipe fd 数=$pipe_fds"
[ -n "$cleaners" ] \
  && ok "AC2-③ 后台清理进程仍在（BR1 未被缩水，argv 为独立 bash -c）" \
  || bad "AC2-③ 返回后找不到 prompt_file 的清理进程（清理丢失？）"
[ "$pipe_fds" -eq 0 ] \
  && ok "AC2-③ 后台清理未持有调用方 pipe fd（=0，disown 不再被误当解耦）" \
  || bad "AC2-③ 后台清理仍持有 $pipe_fds 个 pipe fd"

echo "== 4. 输出契约（AC4）=="
strip_ansi "$LAB/out-T536O2.txt" | sed 's/T536O2/TASKN/g' > "$LAB/lines-old.txt"
strip_ansi "$LAB/out-T536F2.txt" | sed 's/T536F2/TASKN/g' > "$LAB/lines-new.txt"
info "旧行数=$(grep -c . "$LAB/lines-old.txt" || true) · 新行数=$(grep -c . "$LAB/lines-new.txt" || true)"
removed="$(diff "$LAB/lines-old.txt" "$LAB/lines-new.txt" | grep -c '^<' || true)"
added="$(diff "$LAB/lines-old.txt" "$LAB/lines-new.txt" | grep -c '^>' || true)"
info "diff：既有行被改/删=$removed · 新增行=$added"
[ "${removed:-0}" -eq 0 ] && ok "AC4-① 既有输出行内容与顺序不变（0 行被改/删）" \
  || bad "AC4-① 既有输出行被改动 $removed 行"
[ "${added:-0}" -eq 1 ] && ok "AC4-② 新增恰 1 行（就绪提示）" || bad "AC4-② 新增 $added 行（应恰 1 行）"
added_line="$(diff "$LAB/lines-old.txt" "$LAB/lines-new.txt" | sed -n 's/^> //p')"
printf '%s' "$added_line" | grep -q 'status' \
  && ok "AC4-③ 新增行含 status 指引：$added_line" || bad "AC4-③ 新增行不含 status 指引：$added_line"

# 多角色一次调用：仍 1 行提示
run_ensure "$SUBJ" redir T536F3 rd-infra@"$REPO" rd-fe@"$REPO"
multi_hint="$(strip_ansi "$LAB/out-T536F3.txt" | grep -c '在线状态用 nao-fleet.sh status 查看' || true)"
multi_launch="$(strip_ansi "$LAB/out-T536F3.txt" | grep -c '\[tmux\] 已拉起' || true)"
[ "$multi_hint" -eq 1 ] \
  && ok "AC4-④ 多角色（2 个）一次调用仍只 1 行就绪提示（拉起行 $multi_launch 条）" \
  || bad "AC4-④ 多角色提示行数=$multi_hint（应 1）"

# 跳过分支（已在运行）：在隔离 server 里造一个同名会话 nao-<派生名>（running 的第三条判据）⇒ 必走 skip
skip_task="T536F5"
tmux -S "$SOCK" new-session -d -s "nao-rd-infra-$skip_task" 'sleep 60' || true
panes_before="$(tmux -S "$SOCK" list-panes -t t536probe -F '#{pane_id}' | wc -l)"
skip_out="$LAB/out-skip.txt"
bash "$SUBJ" ensure --task "$skip_task" rd-infra@"$REPO" > "$skip_out" 2>&1 || true
skip_hint="$(strip_ansi "$skip_out" | grep -c '在线状态用 nao-fleet.sh status 查看' || true)"
skip_skip="$(strip_ansi "$skip_out" | grep -c '已在运行' || true)"
panes_after="$(tmux -S "$SOCK" list-panes -t t536probe -F '#{pane_id}' | wc -l)"
info "跳过分支：已在运行行=$skip_skip · 就绪提示行=$skip_hint · 宿主窗 pane 数 $panes_before→$panes_after"
[ "$skip_skip" -ge 1 ] && ok "AC4-⑤ 夹具命中「已在运行」跳过分支" || bad "AC4-⑤ 未命中「已在运行」跳过分支（夹具失效）"
[ "$skip_hint" -eq 0 ] && ok "AC4-⑤ 跳过分支（已在运行）不打印就绪提示" \
  || bad "AC4-⑤ 跳过分支误打印 $skip_hint 行就绪提示"
[ "$skip_hint" -eq 0 ] && [ "$panes_before" = "$panes_after" ] \
  && ok "AC4-⑤ 跳过分支未创建 pane（$panes_after → $panes_after）" \
  || bad "AC4-⑤ 跳过分支仍创建了 pane（$panes_before→$panes_after）"

echo "== 5. BR1：~65s 后清理仍发生 =="
wait_left="$(printf '%s\n' "${NEW_PROMPTS[@]:-}" | grep -c . || true)"
info "待清理 prompt_file ${wait_left} 个，最长等 70s..."
gone_at=""
for i in $(seq 1 70); do
  sleep 1
  left=0
  for f in "${NEW_PROMPTS[@]:-}"; do [ -n "$f" ] && [ -e "$f" ] && left=$((left + 1)); done
  if [ "$left" -eq 0 ]; then gone_at=$i; break; fi
done
if [ -n "$gone_at" ]; then
  ok "BR1 prompt_file 在 ${gone_at}s 后全部消失（清理未缩水，60s 窗口未缩短）"
else
  bad "BR1 ${left} 个 prompt_file 70s 后仍残留（清理被削弱）"
fi

echo "== 汇总 =="
printf '  PASS=%d · FAIL=%d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then echo "RESULT: FAIL"; exit 1; fi
echo "RESULT: PASS"
