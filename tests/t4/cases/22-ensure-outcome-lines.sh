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
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
if [ "$BE_NAME" = "tmux" ]; then
  command -v tmux >/dev/null 2>&1 \
    || t4_skip "环境缺少 tmux（tmux 后端需真隔离 socket 构造成功/跳过夹具）"
fi
BASH_BIN="$(command -v bash)"
REAL_TMUX="${NAO_T22_REAL_TMUX:-$(command -v tmux || true)}"
LAB="$T4_CACHE_DIR/lab22-$$"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH

# ---- 硬护栏（先于一切后端操作）：夹具根不得落 git 仓内（场护栏由 be_init 负责）----
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：夹具根不在任何 git 仓内（后端场护栏由 be_init 负责）"

# ---- 夹具 ----
mkdir -p "$LAB" "$LAB/bin" "$LAB/pi-empty"
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

BASE="$(basename "$LAB")"
BE_CACHE_ROOT="$T4_CACHE_DIR"
export PATH="$LAB/bin:$PATH"   # 桩 pi 让 tmux pane 继承（herdr 侧不执行 pi，由替身从命令行推导）
be_init "$LAB" "lab" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }
CALLER="$(be_caller_pane)"

t4_assert_ne "" "$CALLER" "夹具：调用者 pane 建立（$CALLER；后端=$BE_NAME）"

# ---- 收尾：先拆后端场，再复刻 lib 缓存清理语义（保真退出码）----
t522_teardown() {
  [ -n "${LAB:-}" ] && [ -d "$LAB" ] || return 0
  be_teardown >/dev/null 2>&1 || true
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
T539_FAIL_NAME=""   # 非空 ⇒ 只让该名字的 spawn 失败（tmux 桩 split-window / herdr 替身 pane run 同口径）
export NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty"
export NAO_T22_REAL_TMUX="${REAL_TMUX:-}"
run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR（*_ANSI = 去色后版本）
  export NAO_T539_FAIL_SPLIT="$T539_FAIL_NAME" T4_HERDR_FAIL_NAME="$T539_FAIL_NAME"
  be_run_fleet "$LAB" "$@"
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT"; T4_ERR="$BE_ERR"
  T4_OUT_ANSI="$BE_OUT_ANSI"; T4_ERR_ANSI="$BE_ERR_ANSI"
}
pane_ids() { be_panes 2>/dev/null | cut -f1 | sort; }
set_title() { be_set_name "$1" "$2" "$BASE" >/dev/null 2>&1 || true; }
new_panes() { # <before-ids> → 新增 pane id（每行一个）
  local before="$1"
  pane_ids | while IFS= read -r p; do printf '%s\n' "$before" | grep -qxF "$p" || printf '%s\n' "$p"; done
}
launch_lines() { grep -cF -- "[$BE_NAME] 已拉起" <<< "$T4_OUT_ANSI" || true; }
summary_lines() { grep -cE -- '已拉起 [0-9]+ 个会话（成功' <<< "$T4_OUT_ANSI" || true; }
summary_text() { grep -E -- '已拉起 [0-9]+ 个会话（成功' <<< "$T4_OUT_ANSI" | tail -1; }

# ============================================================ AC1 成功：恰 1 行 + 逐字不变
BEFORE="$(pane_ids)"
run_fleet ensure "arch@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1 成功路径 rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_eq "1" "$(launch_lines)" "AC1 成功 ⇒ 恰 1 行 [$BE_NAME] 已拉起"
if [ "$BE_NAME" = "tmux" ]; then
  t4_assert_contains "$T4_OUT_ANSI" \
    "[tmux] 已拉起 arch-designer @ $LAB（layout=main-row2）" \
    "AC1 成功行内容逐字不变（BR1：name @ repo（layout=…））"
else
  # herdr 结果行形态（BR1 只钉 tmux 逐字）：name @ repo（+ pane=…），**没有** layout 段
  t4_assert_contains "$T4_OUT_ANSI" "[herdr] 已拉起 arch-designer @ $LAB" \
    "AC1 herdr 成功行形态：name @ repo（无 layout 段）"
  t4_assert_not_contains "$T4_OUT_ANSI" "layout=" "AC1 herdr 成功行不含 tmux layout 字段"
fi
t4_assert_eq "1" "$(summary_lines)" "AC1 摘要恰一行（BR5）"
t4_assert_contains "$(summary_text)" "（成功 1 / 跳过 0 / 失败 0）" \
  "AC1 摘要三类计数 = 1/0/0"
NEWS="$(new_panes "$BEFORE")"
t4_assert_eq "1" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC1 真创建 1 个 pane"
P_ARCH="$(printf '%s\n' "$NEWS" | head -1)"

# ============================================================ AC2 跳过：零假行
# 两后端都有「已在运行 ⇒ 跳过」出口：tmux = 标题命中；herdr = pane label + 结构化事实命中。
[ "$BE_NAME" = "tmux" ] && set_title "$P_ARCH" "arch-designer"
BEFORE="$(pane_ids)"
run_fleet ensure "arch@$LAB"
t4_assert_eq "0" "$T4_RC" "AC2 跳过路径 rc=0"
t4_assert_eq "0" "$(launch_lines)" "AC2 跳过 ⇒ 0 行 [$BE_NAME] 已拉起（零假行，BR2）"
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
if [ "$BE_NAME" = "tmux" ]; then
  t4_assert_contains "$T4_ERR_ANSI" "pane 创建失败" "AC3 失败诊断 warn ①在位（pane 创建失败）"
  t4_assert_contains "$T4_ERR_ANSI" "已跳过该 pane" "AC3 失败诊断 warn ②在位（不合并）"
  t4_assert_eq "1" "$(grep -cF -- 'pane 创建失败' <<< "$T4_ERR_ANSI" || true)" \
    "AC3 失败诊断 warn 恰 1 条（不是每个目标重复）"
else
  t4_assert_contains "$T4_ERR_ANSI" "pane run 失败" "AC3 herdr 失败诊断 warn 在位（pane run 失败，指名 pane/name）"
  t4_assert_eq "1" "$(grep -cF -- 'pane run 失败' <<< "$T4_ERR_ANSI" || true)" \
    "AC3 herdr 失败诊断 warn 恰 1 条（不是每个目标重复）"
fi
t4_assert_eq "1" "$(summary_lines)" "AC3 摘要恰一行（BR5）"
t4_assert_contains "$(summary_text)" "（成功 0 / 跳过 0 / 失败 1）" \
  "AC3 摘要三类计数 = 0/0/1"
if [ "$BE_NAME" = "tmux" ]; then
  t4_assert_eq "$BEFORE" "$(pane_ids)" "AC3 失败不新增 pane"
else
  # herdr：pane 先建后注入，run 失败时**保留**该 pane（fail loud 不自动 kill，见 B2 报告）⇒ 恰 +1
  t4_assert_eq "$(( $(printf '%s\n' "$BEFORE" | grep -c .) + 1 ))" \
    "$(pane_ids | grep -c .)" "AC3 herdr 失败保留 pane（先建后注入；+1 且不计成功）"
fi

# ============================================================ AC4 混合：1 成功 + 1 跳过 + 1 失败
# 跳过来源分后端：tmux 靠标题预置（把 arch pane 改名为 rd-fe）；herdr 靠 label 命中（arch 仍在场）。
if [ "$BE_NAME" = "tmux" ]; then set_title "$P_ARCH" "rd-fe"; fi
T539_FAIL_NAME="rd-be"
BEFORE="$(pane_ids)"
run_fleet ensure "arch@$LAB" "rd-fe@$LAB" "rd-be@$LAB"
T539_FAIL_NAME=""
t4_assert_eq "0" "$T4_RC" "AC4 混合批次 rc=0（含失败目标，BR4）"
t4_assert_eq "1" "$(launch_lines)" "AC4 混合 ⇒ 结果行恰 1 条（仅成功目标）"
if [ "$BE_NAME" = "tmux" ]; then
  t4_assert_contains "$T4_OUT_ANSI" "[tmux] 已拉起 arch-designer @ $LAB" "AC4 成功行归 arch-designer"
  t4_assert_not_contains "$T4_OUT_ANSI" "[tmux] 已拉起 rd-be" "AC4 失败目标 rd-be 无假成功行"
  t4_assert_not_contains "$T4_OUT_ANSI" "[tmux] 已拉起 rd-fe" "AC4 跳过目标 rd-fe 无假成功行"
  t4_assert_contains "$T4_ERR_ANSI" "pane 创建失败" "AC4 失败目标走既有诊断 warn（tmux）"
else
  t4_assert_contains "$T4_OUT_ANSI" "[herdr] 已拉起 rd-fe @ $LAB" "AC4 成功行归 rd-fe（arch 已在场 ⇒ 跳过）"
  t4_assert_not_contains "$T4_OUT_ANSI" "已拉起 rd-be" "AC4 失败目标 rd-be 无假成功行"
  t4_assert_not_contains "$T4_OUT_ANSI" "已拉起 arch-designer" "AC4 跳过目标 arch 无假成功行"
  t4_assert_contains "$T4_ERR_ANSI" "pane run 失败" "AC4 失败目标走既有诊断 warn（herdr）"
fi
if [ "$BE_NAME" = "tmux" ]; then
  t4_assert_contains "$T4_ERR_ANSI" "rd-fe 已在运行" "AC4 跳过目标走既有跳过 warn（tmux：rd-fe 标题命中）"
else
  t4_assert_contains "$T4_ERR_ANSI" "arch-designer 已在运行" "AC4 跳过目标走既有跳过 warn（herdr：arch 在场）"
fi
t4_assert_eq "1" "$(summary_lines)" "AC4 摘要恰一行（BR5）"
SUM="$(summary_text)"
t4_assert_contains "$SUM" "（成功 1 / 跳过 1 / 失败 1）" "AC4 三类计数 = 1/1/1"
read -r _n_s _n_k _n_f <<< "$(sed -nE 's/.*（成功 ([0-9]+) \/ 跳过 ([0-9]+) \/ 失败 ([0-9]+)）.*/\1 \2 \3/p' <<< "$SUM")"
t4_assert_eq "3" "$(( ${_n_s:-0} + ${_n_k:-0} + ${_n_f:-0} ))" \
  "AC4 计数守恒：三类之和 = 目标数 3（BR3）"
NEWS="$(new_panes "$BEFORE")"
if [ "$BE_NAME" = "tmux" ]; then
  t4_assert_eq "1" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC4 混合批次真创建 1 个 pane（只有成功目标）"
else
  # herdr：成功目标 1 + 失败目标保留 pane 1（跳过目标不建）= 2
  t4_assert_eq "2" "$(printf '%s\n' "$NEWS" | grep -c .)" \
    "AC4h 混合批次 pane 增量 = 2（成功 1 + 失败保留 1；跳过 0）"
fi

t4_exit
