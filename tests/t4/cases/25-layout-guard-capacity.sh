#!/usr/bin/env bash
# 用例 25 —— 布局守卫容量判据（#82 B · #84 C）：n = 角色数 + 调用者，默认值从脚本常量抽取
#
# 判据来源：Issue #82/#84 · `docs/prds/2026-11-05-uiux-designer-role.md` §六（arch 定量、PM 复核）
#   零 warn 最小宽度 = 满足 floor((right_w-(cols-1))/cols) ≥ NAO_TMUX_MIN_PANE_WIDTH，
#   cols=⌈(n-1)/2⌉ · right_w=(w-1)-floor((w-1)*pct/100)
#   默认 (pct=33, min=30) ⇒ n=7→137 · n=8→184（7 角色 + 调用者 = #80 暴露的夹层）· n=9→184 · n=10→230
#
# #84 C：`pct` / `min` **不再重敲字面量**，一律 `grep` 自 `nao-fleet.sh` 的 `*_DEFAULT` 常量 ⇒
#   改默认值后本用例自动跟随（拍板表 137/184/184/230 仅在默认值仍为 33/30 时钉值，否则自跳过）。
#
# 断言分组：
#   M1 数学边界（公式独立实现 vs 从**真脚本**抽取的 main_row2_min_col 实跑）
#   M2 语义（n = 宿主窗口实际 pane 数 = 角色数 + 调用者）：静态 + 活体（阈值两侧各一档）
#   M3 变异负控：守位实参改回「按角色数」（n-1）⇒ 活体判定必须改变 ⇒ 断言能捕获
#   M4 默认值跟随：副本改 `*_DEFAULT` ⇒ 公式断言仍绿、拍板表自跳过（不假红）
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

# ---------------------------------------------------------------- 常量抽取（#84 C）
main_width_default() { sed -n 's/^TMUX_MAIN_WIDTH_DEFAULT=\([0-9][0-9]*\)$/\1/p' "$1" | head -1; }
min_width_default()  { sed -n 's/^TMUX_MIN_PANE_WIDTH_DEFAULT=\([0-9][0-9]*\)$/\1/p' "$1" | head -1; }

PCT="$(main_width_default "$FLEET")"
MIN="$(min_width_default "$FLEET")"
t4_assert_match "$PCT" '^[0-9]+$' "C: 从脚本抽取 TMUX_MAIN_WIDTH_DEFAULT（得到「$PCT」）"
t4_assert_match "$MIN" '^[0-9]+$' "C: 从脚本抽取 TMUX_MIN_PANE_WIDTH_DEFAULT（得到「$MIN」）"
PCT="${PCT:-33}"; MIN="${MIN:-30}"

# ---------------------------------------------------------------- 数学参考实现（PM 公式，独立于被测脚本）
# 零 warn 最小宽度（100..400 扫描）：cols=⌈(n-1)/2⌉ · right_w=(w-1)-floor((w-1)*pct/100)
ref_min_w() { # $1=pane 数 → 最小宽度；用 PCT/MIN
  local n="$1" w cols rw v
  cols=$(( (n - 1 + 1) / 2 )); (( cols < 1 )) && cols=1
  for (( w = 100; w <= 400; w++ )); do
    rw=$(( (w - 1) - (w - 1) * PCT / 100 )); (( rw < 1 )) && rw=1
    v=$(( (rw - (cols - 1)) / cols ))
    (( v >= MIN )) && { printf '%s' "$w"; return 0; }
  done
  printf 'none'
}

# 抽被测脚本的纯函数（fail-closed：抽不到即红，不静默跳过）
load_math() { # $1=脚本 $2=输出文件
  { awk '/^main_row2_geom\(\)/,/^}/' "$1"; awk '/^main_row2_min_col\(\)/,/^}/' "$1"; } > "$2"
  local a b
  a="$(grep -c '^main_row2_geom()' "$2" || true)"; b="$(grep -c '^main_row2_min_col()' "$2" || true)"
  [ "$a" = "1" ] && [ "$b" = "1" ]
}

MATH="$LAB/math.sh"
if load_math "$FLEET" "$MATH"; then
  t4_ok "M1: 从真脚本抽到 main_row2_geom + main_row2_min_col（几何单源）"
else
  t4_bad "M1: 未抽到几何函数（脚本结构已变？）"
fi
# shellcheck disable=SC1090
. "$MATH"

# ---------------------------------------------------------------- M1 边界（公式 vs 实现）
for n in 7 8 9 10; do
  want="$(ref_min_w "$n")"
  got_ok="$(main_row2_min_col "$want" "$n" "$PCT")"
  got_low="$(main_row2_min_col "$(( want - 1 ))" "$n" "$PCT")"
  t4_assert_eq "1" "$(( got_ok >= MIN ? 1 : 0 ))" "M1: n=$n @${want} 列 ⇒ 最窄 $got_ok ≥ 最小 $MIN（保持 main-row2）"
  t4_assert_eq "1" "$(( got_low < MIN ? 1 : 0 ))" "M1: n=$n @$(( want - 1 )) 列 ⇒ 最窄 $got_low < $MIN（回退）"
done
# 拍板表（仅当默认值仍为 33/30 时钉值；默认值变了就走上面的公式断言，不假红）
if [ "$PCT" = "33" ] && [ "$MIN" = "30" ]; then
  t4_assert_eq "137" "$(ref_min_w 7)" "M1: 拍板表 n=7 ⇒ 137（默认 33/30）"
  t4_assert_eq "184" "$(ref_min_w 8)" "M1: 拍板表 n=8 ⇒ 184（7 角色 + 调用者 = #80 夹层）"
  t4_assert_eq "184" "$(ref_min_w 9)" "M1: 拍板表 n=9 ⇒ 184（同 cols 台阶）"
  t4_assert_eq "230" "$(ref_min_w 10)" "M1: 拍板表 n=10 ⇒ 230（跨 cols 台阶抬一档）"
  t4_assert_eq "137" "$(for (( w = 100; w < 400; w++ )); do main_row2_min_col "$w" 7 "$PCT" | grep -qx "$MIN" && { printf '%s' "$w"; break; }; done)" \
    "M1: 实现与拍板表同源（n=7 首个 ≥$MIN 的宽度 = 137）"
else
  t4_info "默认值已非 33/30（pct=$PCT min=$MIN）⇒ 拍板表钉值自跳过，公式断言仍生效"
fi

# ---------------------------------------------------------------- M2 语义
t4_assert_contains "$(cat "$FLEET")" 'list-panes -t "$HOST_WINDOW" -F '"'"'#{pane_id}'"'"'' \
  "M2: 守卫的 n 取自宿主窗口 list-panes（角色数 + 调用者）"
t4_assert_eq "0" "$(awk '/^apply_tmux_layout\(\)/,/^}/' "$FLEET" | grep -c 'ROLE_ORDER' || true)" \
  "M2: 布局路径不引用 ROLE_ORDER（不按角色清单计宽）"

live_probe() { # $1=脚本 $2=宽度 → "panes=<n> rc=<rc> warn=<0|1>"
  local fleet="$1" w="$2" out rc panes warn=0
  TX kill-server >/dev/null 2>&1 || true
  mkdir -p "$SOCKDIR/tmux-$(id -u)"; chmod 700 "$SOCKDIR/tmux-$(id -u)"
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
W_OK="$(ref_min_w 8)"; W_LOW="$(( W_OK - 1 ))"
p_low="$(live_probe "$LAB/.agents/scripts/nao-fleet.sh" "$W_LOW")"
t4_assert_contains "$p_low" "panes=8" "M2: 7 目标 + 调用者 ⇒ 8 pane（${W_LOW} 列）"
t4_assert_contains "$p_low" "warn=1" "M2: n=8 @${W_LOW} 列 ⇒ 出「回退 main-col」warn（按 8 计，非 7）"
p_ok="$(live_probe "$LAB/.agents/scripts/nao-fleet.sh" "$W_OK")"
t4_assert_contains "$p_ok" "warn=0" "M2: n=8 @${W_OK} 列 ⇒ 零 warn 保持 main-row2"

# ---------------------------------------------------------------- M3 变异负控
MUT="$LAB/fleet-mut.sh"
sed 's/narrow="$(main_row2_min_col "$win_w" "$n" "$pct")"/narrow="$(main_row2_min_col "$win_w" "$(( n - 1 ))" "$pct")"/' \
  "$LAB/.agents/scripts/nao-fleet.sh" > "$MUT"
t4_assert_eq "1" "$(grep -c 'main_row2_min_col "$win_w" "$(( n - 1 ))"' "$MUT" || true)" \
  "M3: 变异夹具已把守卫实参改为 n-1（按角色数）"
p_mut="$(live_probe "$MUT" "$W_LOW")"
t4_assert_contains "$p_mut" "warn=0" "M3: 「按角色数」实现 @${W_LOW} 列不 warn（与本用例 M2 断言冲突 ⇒ 可被捕获）"
t4_assert_ne "$p_low" "$p_mut" "M3: 变异后判定与真脚本不同（断言对该语义敏感，非空转）"

# ---------------------------------------------------------------- M4 默认值跟随（#84 C）
DEF="$LAB/fleet-def.sh"
sed -e 's/^TMUX_MAIN_WIDTH_DEFAULT=[0-9][0-9]*$/TMUX_MAIN_WIDTH_DEFAULT=40/' \
    -e 's/^TMUX_MIN_PANE_WIDTH_DEFAULT=[0-9][0-9]*$/TMUX_MIN_PANE_WIDTH_DEFAULT=24/' \
    "$FLEET" > "$DEF"
PCT2="$(main_width_default "$DEF")"; MIN2="$(min_width_default "$DEF")"
t4_assert_eq "40/24" "$PCT2/$MIN2" "M4: 副本默认值已改 33/30 → 40/24（抽取器跟随）"
PCT_SAVE="$PCT"; MIN_SAVE="$MIN"
PCT="$PCT2"; MIN="$MIN2"
W2="$(ref_min_w 8)"
MATH2="$LAB/math-def.sh"
load_math "$DEF" "$MATH2" || t4_bad "M4: 未从副本抽到几何函数"
(
  # 子 shell 内换用副本的几何函数，验证「断言只跟常量走」
  # shellcheck disable=SC1090
  . "$MATH2"
  v_ok="$(main_row2_min_col "$W2" 8 "$PCT2")"
  v_low="$(main_row2_min_col "$(( W2 - 1 ))" 8 "$PCT2")"
  [ "$v_ok" -ge "$MIN2" ] && [ "$v_low" -lt "$MIN2" ]
) && t4_ok "M4: 新默认值下「阈值两侧」断言仍成立（不因改默认值假红）" \
  || t4_bad "M4: 新默认值下阈值断言不成立（抽取或几何口径有误）"
PCT="$PCT_SAVE"; MIN="$MIN_SAVE"
t4_assert_eq "33/30" "$PCT/$MIN" "M4: 真脚本默认值未被改动（33/30）"

t4_exit
