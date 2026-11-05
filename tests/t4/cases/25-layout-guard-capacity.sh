#!/usr/bin/env bash
# 用例 25 —— 布局守卫容量判据（#82 B）：n 必须按「角色数 + 调用者」计
#
# 判据来源：Issue #82 · `docs/prds/2026-11-05-uiux-designer-role.md` §六（公式由 arch 定量、PM 复核）
#   零 warn 最小宽度 = 满足 floor((right_w-(cols-1))/cols) ≥ NAO_TMUX_MIN_PANE_WIDTH，
#   cols=⌈(n-1)/2⌉ · right_w=(w-1)-floor((w-1)*pct/100)（pct=33 / min=30）
#   ⇒ n=7→137 · n=8→184（7 角色 + 调用者 = #80 暴露的夹层）· n=9→184 · n=10→230
#
# 三组断言：
#   M1 数学边界（从**真脚本**抽取 main_row2_geom / main_row2_min_col 实跑，不另写公式）
#   M2 语义（n = 宿主窗口实际 pane 数 = 角色数 + 调用者）：静态（取自 list-panes）+ 活体（183/184 列）
#   M3 变异负控：把守卫改回「按角色数」（n-1）⇒ 活体判定必须改变 ⇒ 断言能捕获该类回归
# 零网络（NAO_UPDATE_ON_ENSURE=0）· 隔离 socket（不碰生产 server）· 桩 pi（不拉起真会话）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd tmux
t4_require_cmd awk

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
t4_assert_file "$FLEET" "M1: 被测脚本存在"

LAB="$(mktemp -d "$T4_CACHE_DIR/lab25.XXXXXX")" || t4_blocked "夹具目录创建失败"
SOCKDIR="$LAB/sock"; SOCK="$SOCKDIR/tmux-$(id -u)/default"
mkdir -p "$SOCKDIR/tmux-$(id -u)" "$LAB/bin" "$LAB/pi-empty"
chmod 700 "$SOCKDIR/tmux-$(id -u)"

# 硬护栏：socket 不得命中生产候选（与既有 tmux 用例同纪律）
GUARD=0
_TM="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${_TM%%,*}"; do
  [ -n "$p" ] && [ "$SOCK" = "$p" ] && GUARD=1
done
[[ "$SOCK" == "$LAB"/* ]] || GUARD=1
[ "$GUARD" = 0 ] || { t4_bad "护栏触发：夹具 SOCK=$SOCK 不在 \$LAB 下或撞生产默认 socket"; t4_exit; }
t4_ok "护栏：隔离 socket（$SOCK）"

TX() { tmux -S "$SOCK" "$@"; }
cleanup25() { TX kill-server >/dev/null 2>&1 || true; rm -rf "$LAB"; }
trap cleanup25 EXIT

# 桩 pi：--version 供前提校验；其余记录后长驻（绝不拉起真会话）
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
exec sleep 300
SH
chmod +x "$LAB/bin/pi"

# ---------------------------------------------------------------- M1 数学边界
# 从真脚本抽取纯函数（fail-closed：抽不到即红，不静默跳过）
MATH="$LAB/math.sh"
{
  awk '/^main_row2_geom\(\)/,/^}/' "$FLEET"
  awk '/^main_row2_min_col\(\)/,/^}/' "$FLEET"
} > "$MATH"
g1="$(grep -c '^main_row2_geom()' "$MATH" || true)"
g2="$(grep -c '^main_row2_min_col()' "$MATH" || true)"
t4_assert_eq "1/1" "$g1/$g2" "M1: 从真脚本抽到 main_row2_geom + main_row2_min_col（几何单源）"
# shellcheck disable=SC1090
. "$MATH"

min_w_for() { # $1=pane 总数 → 零 warn 的最小窗口宽度（100..400 扫描）
  local n="$1" w v
  for (( w = 100; w <= 400; w++ )); do
    v="$(main_row2_min_col "$w" "$n" 33)"
    if (( v >= 30 )); then printf '%s' "$w"; return 0; fi
  done
  printf 'none'
}

t4_assert_eq "137" "$(min_w_for 7)" "M1: n=7 ⇒ 零 warn 最小 137 列（#80 前 6 角色 + 调用者）"
t4_assert_eq "184" "$(min_w_for 8)" "M1: n=8 ⇒ 184 列（7 角色 + 调用者 = #80 暴露的夹层）"
t4_assert_eq "184" "$(min_w_for 9)" "M1: n=9 ⇒ 184 列（同一 cols 台阶）"
t4_assert_eq "230" "$(min_w_for 10)" "M1: n=10 ⇒ 230 列（跨 cols 台阶抬一档）"
# 边界两侧逐值（防「阈值对但方向反」）
t4_assert_eq "29" "$(main_row2_min_col 136 7 33)" "M1: n=7 @136 列 ⇒ 最窄 29（< 30 ⇒ 回退）"
t4_assert_eq "30" "$(main_row2_min_col 137 7 33)" "M1: n=7 @137 列 ⇒ 最窄 30（= 阈值 ⇒ 保持 main-row2）"
t4_assert_eq "29" "$(main_row2_min_col 183 8 33)" "M1: n=8 @183 列 ⇒ 最窄 29（回退）"
t4_assert_eq "30" "$(main_row2_min_col 184 8 33)" "M1: n=8 @184 列 ⇒ 最窄 30（保持）"
t4_assert_eq "29" "$(main_row2_min_col 229 10 33)" "M1: n=10 @229 列 ⇒ 最窄 29（回退）"
t4_assert_eq "30" "$(main_row2_min_col 230 10 33)" "M1: n=10 @230 列 ⇒ 最窄 30（保持）"

# ---------------------------------------------------------------- M2 语义
# 静态：n 的唯一来源是宿主窗口的实际 pane 列表（≠ 角色数 / ROLE_ORDER）
t4_assert_contains "$(cat "$FLEET")" 'list-panes -t "$HOST_WINDOW" -F '"'"'#{pane_id}'"'"'' \
  "M2: 守卫的 n 取自宿主窗口 list-panes（角色数 + 调用者）"
t4_assert_eq "0" "$(awk '/^apply_tmux_layout\(\)/,/^}/' "$FLEET" | grep -c 'ROLE_ORDER' || true)" \
  "M2: 布局路径不引用 ROLE_ORDER（不按角色清单计宽）"

# 活体：7 目标 ⇒ 8 pane；183 列 warn / 184 列不 warn
live_probe() { # $1=脚本 $2=宽度 → stdout: "panes=<n> rc=<rc> warn=<0|1>"
  local fleet="$1" w="$2" out rc panes warn=0
  TX kill-server >/dev/null 2>&1 || true
  TX new-session -d -s fx -x "$w" -y 40 -c "$LAB" >/dev/null 2>&1 || { printf 'panes=0 rc=9 warn=0'; return 0; }
  sleep 0.2
  local pid sid caller
  pid="$(TX display -p '#{pid}' 2>/dev/null)"
  sid="$(TX display -p '#{session_id}' 2>/dev/null)"
  caller="$(TX list-panes -t fx -F '#{pane_id}' 2>/dev/null | head -1)"
  out="$( cd "$LAB" && env -u NAO_TMUX_LAYOUT PATH="$LAB/bin:$PATH" \
      TMUX="$SOCK,$pid,$sid" TMUX_PANE="$caller" NAO_SKILLS="$LAB" \
      NAO_TASKS_STATE="$LAB/.none.md" NAO_UPDATE_ON_ENSURE=0 PI_CODING_AGENT_DIR="$LAB/pi-empty" \
      timeout 120 bash "$fleet" ensure pm arch-designer uiux-designer rd-fe rd-be qa rd-infra 2>&1 )"
  rc=$?
  panes="$(TX list-panes -t fx -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' ')"
  printf '%s' "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -q '回退 main-col' && warn=1
  printf 'panes=%s rc=%s warn=%s' "${panes:-0}" "$rc" "$warn"
}

cp -r "$T4_ROOT/.agents" "$LAB/.agents" || t4_bad "M2: 夹具复制 .agents 失败"
p183="$(live_probe "$LAB/.agents/scripts/nao-fleet.sh" 183)"
t4_assert_contains "$p183" "panes=8" "M2: 7 目标 + 调用者 ⇒ 8 pane（183 列）"
t4_assert_contains "$p183" "warn=1" "M2: n=8 @183 列 ⇒ 出「回退 main-col」warn（按 8 计，非 7）"
p184="$(live_probe "$LAB/.agents/scripts/nao-fleet.sh" 184)"
t4_assert_contains "$p184" "warn=0" "M2: n=8 @184 列 ⇒ 零 warn 保持 main-row2"

# ---------------------------------------------------------------- M3 变异负控
# 模拟「按角色数算」：把守卫实参改成 n-1（复制脚本上改，仓库只读）⇒ 同一 183 列必须**不再** warn
MUT="$LAB/fleet-mut.sh"
sed 's/narrow="$(main_row2_min_col "$win_w" "$n" "$pct")"/narrow="$(main_row2_min_col "$win_w" "$(( n - 1 ))" "$pct")"/' \
  "$LAB/.agents/scripts/nao-fleet.sh" > "$MUT"
t4_assert_eq "1" "$(grep -c 'main_row2_min_col "$win_w" "$(( n - 1 ))"' "$MUT" || true)" \
  "M3: 变异夹具已把守卫实参改为 n-1（按角色数）"
pmut="$(live_probe "$MUT" 183)"
t4_assert_contains "$pmut" "warn=0" "M3: 「按角色数」实现 @183 列不 warn ⇒ 与本用例 M2 断言冲突（可被捕获）"
t4_assert_ne "$p183" "$pmut" "M3: 变异后判定与真脚本不同（断言对该语义敏感，非空转）"

t4_exit
