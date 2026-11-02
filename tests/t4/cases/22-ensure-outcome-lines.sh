#!/usr/bin/env bash
# 用例 22 —— `ensure` 输出语义三态互斥（成功 / 跳过 / 失败）+ 摘要三类计数（T539）
#
# PRD：docs/prds/2026-11-02-ensure-outcome-lines.md（§七 AC1–AC4 · BR1–BR6）
# 被测对象：.agents/scripts/nao-fleet.sh 的 `spawn_tmux` / `spawn_one` / `cmd_ensure` 摘要行
#
# 断言映射：
#   AC1 成功：恰 1 行 `[tmux] 已拉起 …`（逐字 = 旧格式）+ 摘要「成功 1 / 跳过 0 / 失败 0」
#   AC2 跳过：跳过 warn 在位 · `已拉起` 结果行 = 0 · 摘要「成功 0 / 跳过 1 / 失败 0」· 不新增 pane
#   AC3 失败：两条诊断 warn 在位 · `已拉起` 结果行 = 0 · 摘要「成功 0 / 跳过 0 / 失败 1」· rc 仍 0（BR4）
#   AC4 混合：1 成功 + 1 跳过 + 1 失败 ⇒ 结果行恰 1 条（成功目标）· 摘要三类 = 1/1/1 · 合计 = 3 = 目标数
#
# 夹具纪律（沿用 T515/T516/T520 血训）：
#   - 真 tmux **隔离 socket**（显式硬护栏：≠ 生产默认候选）+ `env -u TMUX -u TMUX_PANE` + `TMUX_TMPDIR` 指向夹具
#   - 桩 `pi`（记录 argv 后长驻，绝不拉起真 pi 会话）；名册离线（`PI_CODING_AGENT_DIR` 指向空目录 ⇒ 无 tsx）
#   - 失败分支**用 tmux 桩**（选择性让 `split-window` 失败），不依赖真实窗口过窄（不可复现）
#   - 夹具根不得落在任何 git 仓内；收尾走机制 `cleanup -S <隔离 socket>`
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

command -v tmux >/dev/null 2>&1 \
  || t4_skip "环境缺少 tmux（T539 需真 tmux 隔离 socket 构造成功/跳过夹具）"

BASH_BIN="$(command -v bash)"
REAL_TMUX="$(command -v tmux)"
LAB="$T4_CACHE_DIR/lab22-$$"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
FTMUX="$SOCK,0,0"

# ---- 硬护栏（先于一切 tmux 操作）：socket 不得命中生产候选，夹具根不得落 git 仓内 ----
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
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：隔离 socket + 夹具根不在任何 git 仓内"

# ---- 夹具 ----
mkdir -p "$LAB" "$SOCKDIR/tmux-$(id -u)" "$LAB/bin" "$LAB/pi-empty"
chmod 700 "$SOCKDIR/tmux-$(id -u)"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
# pi 桩：记录 argv 后长驻（绝不拉起真 pi 会话）；panes 的 PATH 由 tmux server 全局 env 注入
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
{ printf 'cwd=%s\n' "\$PWD"; printf '%s\n' "\$@"; } >> "$LAB/fake-pi.log"
exec sleep 900
SH
chmod +x "$LAB/bin/pi"
# tmux 桩（T539 关键）：默认逐字转发给真 tmux；仅当 NAO_T539_FAIL_SPLIT=<名字> 且 split-window
#   的命令串含 `--name <名字>` 时返回非 0 —— 精确构造「单目标 pane 创建失败」，不触碰真实窗口几何。
cat > "$LAB/bin/tmux" <<SH
#!/usr/bin/env bash
# 参数串含 printf %q 的反斜杠转义（如 --name\ rd-be）⇒ 先去反斜杠再比对名字
FLAT="\$(printf '%s' "\$*" | tr -d '\\\\')"
if [ "\${1:-}" = "split-window" ] && [ -n "\${NAO_T539_FAIL_SPLIT:-}" ]; then
  case " \$FLAT " in
    *"--name \${NAO_T539_FAIL_SPLIT} "*) printf 'no space for new pane（T539 桩）\n' >&2; exit 1 ;;
  esac
fi
exec "$REAL_TMUX" "\$@"
SH
chmod +x "$LAB/bin/tmux"

TX() { "$REAL_TMUX" -S "$SOCK" "$@"; }
TX new-session -d -s lab -x 240 -y 60 -c "$LAB" >/dev/null 2>&1
sleep 0.3
CALLER="$(TX list-panes -t lab -F '#{pane_id}' | head -1)"
TX setenv -g PATH "$LAB/bin:$PATH" >/dev/null 2>&1   # 新 pane 用桩 pi（server 全局 env）
BASE="$(basename "$LAB")"

t4_assert_ne "" "$CALLER" "夹具：隔离 tmux server + 调用者 pane 建立（$CALLER）"

# ---- 收尾：先机制 cleanup -S，再复刻 lib 缓存清理语义（保真退出码）----
t522_teardown() {
  [ -n "${SOCK:-}" ] && [ -d "${LAB:-/nonexistent}" ] || return 0
  ( cd "$LAB" 2>/dev/null || cd /tmp
    env -u TMUX TMUX_TMPDIR="$SOCKDIR" "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$SOCK" >/dev/null 2>&1 ) || true
  return 0
}
t522_exit_trap() {
  local rc=$?
  t522_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t522_exit_trap EXIT

# ---- 调用封装 ----
T539_FAIL_NAME=""   # 非空 ⇒ tmux 桩只让该名字的 split-window 失败
run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR（*_ANSI = 去色后版本）
  t4_run_in_dir "$LAB" env -u TMUX -u TMUX_PANE TMUX="$FTMUX" TMUX_PANE="$CALLER" \
    TMUX_TMPDIR="$SOCKDIR" NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty" \
    NAO_T539_FAIL_SPLIT="$T539_FAIL_NAME" PATH="$LAB/bin:$PATH" \
    timeout 90 bash "$LAB/.agents/scripts/nao-fleet.sh" "$@"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
pane_ids() { TX list-panes -a -F '#{pane_id}' 2>/dev/null | sort; }
set_title() { TX select-pane -t "$1" -T "π - $2 - $BASE" >/dev/null 2>&1 || true; }
new_panes() { # <before-ids> → 新增 pane id（每行一个）
  local before="$1"
  pane_ids | while IFS= read -r p; do printf '%s\n' "$before" | grep -qxF "$p" || printf '%s\n' "$p"; done
}
launch_lines() { grep -cF -- '[tmux] 已拉起' <<< "$T4_OUT_ANSI" || true; }
summary_lines() { grep -cE -- '已拉起 [0-9]+ 个会话（成功' <<< "$T4_OUT_ANSI" || true; }
summary_text() { grep -E -- '已拉起 [0-9]+ 个会话（成功' <<< "$T4_OUT_ANSI" | tail -1; }

# ============================================================ AC1 成功：恰 1 行 + 逐字不变
BEFORE="$(pane_ids)"
run_fleet ensure "arch@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1 成功路径 rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_eq "1" "$(launch_lines)" "AC1 成功 ⇒ 恰 1 行 [tmux] 已拉起"
t4_assert_contains "$T4_OUT_ANSI" \
  "[tmux] 已拉起 arch-designer @ $LAB（layout=main-row2）" \
  "AC1 成功行内容逐字不变（BR1：name @ repo（layout=…））"
t4_assert_eq "1" "$(summary_lines)" "AC1 摘要恰一行（BR5）"
t4_assert_contains "$(summary_text)" "（成功 1 / 跳过 0 / 失败 0）" \
  "AC1 摘要三类计数 = 1/0/0"
NEWS="$(new_panes "$BEFORE")"
t4_assert_eq "1" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC1 真创建 1 个 pane"
P_ARCH="$(printf '%s\n' "$NEWS" | head -1)"

# ============================================================ AC2 跳过：零假行
set_title "$P_ARCH" "arch-designer"
BEFORE="$(pane_ids)"
run_fleet ensure "arch@$LAB"
t4_assert_eq "0" "$T4_RC" "AC2 跳过路径 rc=0"
t4_assert_eq "0" "$(launch_lines)" "AC2 跳过 ⇒ 0 行 [tmux] 已拉起（零假行，BR2）"
t4_assert_contains "$T4_ERR_ANSI" "已在运行" "AC2 既有跳过 warn 保留（已在运行）"
t4_assert_contains "$T4_ERR_ANSI" "跳过" "AC2 既有跳过 warn 保留（跳过）"
t4_assert_eq "1" "$(summary_lines)" "AC2 摘要恰一行（BR5）"
t4_assert_contains "$(summary_text)" "（成功 0 / 跳过 1 / 失败 0）" \
  "AC2 摘要三类计数 = 0/1/0"
t4_assert_eq "$BEFORE" "$(pane_ids)" "AC2 跳过不新增 pane（零副作用）"

# ============================================================ AC3 失败：零假行 + 桩 + rc 仍 0
T539_FAIL_NAME="qa"
BEFORE="$(pane_ids)"
run_fleet ensure "qa@$LAB"
T539_FAIL_NAME=""
t4_assert_eq "0" "$T4_RC" "AC3 失败路径 rc 仍为 0（BR4）"
t4_assert_eq "0" "$(launch_lines)" "AC3 失败 ⇒ 0 行 [tmux] 已拉起（零假行，BR2）"
t4_assert_contains "$T4_ERR_ANSI" "pane 创建失败" "AC3 失败诊断 warn ①在位（pane 创建失败）"
t4_assert_contains "$T4_ERR_ANSI" "已跳过该 pane" "AC3 失败诊断 warn ②在位（不合并）"
t4_assert_eq "1" "$(grep -cF -- 'pane 创建失败' <<< "$T4_ERR_ANSI" || true)" \
  "AC3 失败诊断 warn 恰 1 条（不是每个目标重复）"
t4_assert_eq "1" "$(summary_lines)" "AC3 摘要恰一行（BR5）"
t4_assert_contains "$(summary_text)" "（成功 0 / 跳过 0 / 失败 1）" \
  "AC3 摘要三类计数 = 0/0/1"
t4_assert_eq "$BEFORE" "$(pane_ids)" "AC3 失败不新增 pane"

# ============================================================ AC4 混合：1 成功 + 1 跳过 + 1 失败
# 跳过目标 rd-fe 用标题预置（不依赖真 pi 设标题）；失败目标 rd-be 用桩；成功目标 arch 正常创建。
set_title "$P_ARCH" "rd-fe"
T539_FAIL_NAME="rd-be"
BEFORE="$(pane_ids)"
run_fleet ensure "arch@$LAB" "rd-fe@$LAB" "rd-be@$LAB"
T539_FAIL_NAME=""
t4_assert_eq "0" "$T4_RC" "AC4 混合批次 rc=0（含失败目标，BR4）"
t4_assert_eq "1" "$(launch_lines)" "AC4 混合 ⇒ 结果行恰 1 条（仅成功目标）"
t4_assert_contains "$T4_OUT_ANSI" "[tmux] 已拉起 arch-designer @ $LAB" "AC4 成功行归 arch-designer"
t4_assert_not_contains "$T4_OUT_ANSI" "[tmux] 已拉起 rd-be" "AC4 失败目标 rd-be 无假成功行"
t4_assert_not_contains "$T4_OUT_ANSI" "[tmux] 已拉起 rd-fe" "AC4 跳过目标 rd-fe 无假成功行"
t4_assert_contains "$T4_ERR_ANSI" "rd-fe 已在运行" "AC4 跳过目标走既有跳过 warn"
t4_assert_contains "$T4_ERR_ANSI" "pane 创建失败" "AC4 失败目标走既有诊断 warn"
t4_assert_eq "1" "$(summary_lines)" "AC4 摘要恰一行（BR5）"
SUM="$(summary_text)"
t4_assert_contains "$SUM" "（成功 1 / 跳过 1 / 失败 1）" "AC4 三类计数 = 1/1/1"
read -r _n_s _n_k _n_f <<< "$(sed -nE 's/.*（成功 ([0-9]+) \/ 跳过 ([0-9]+) \/ 失败 ([0-9]+)）.*/\1 \2 \3/p' <<< "$SUM")"
t4_assert_eq "3" "$(( ${_n_s:-0} + ${_n_k:-0} + ${_n_f:-0} ))" \
  "AC4 计数守恒：三类之和 = 目标数 3（BR3）"
NEWS="$(new_panes "$BEFORE")"
t4_assert_eq "1" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC4 混合批次真创建 1 个 pane（只有成功目标）"

t4_exit
