#!/usr/bin/env bash
# 用例 41 —— 纯 herdr 化（T555）
#
# PRD：docs/prds/2026-11-22-herdr-only.md（AC2/AC3/AC4/AC5/AC6/AC8）
# ADR：docs/adr/2026-11-22-herdr-only.md（supersede 2026-10-27-strict-tmux-pi）
# 判据：docs/reports/555-lite-spec.md（§2 退役清单 · §3 各态 wired · §4 静态 lint 设计 · §7 PM 拍板 D1–D5）
#
# 断言分组（编号 ↔ 依据）：
#   ①②③ 旧后端变量 fail loud（D2=rc2）：`ensure` / `check` / 任意子命令 ⇒ rc=2 + stderr **恰 1 行**含
#        「已移除」「herdr」，stdout 空，PATH 桩（herdr/tmux）**0 命中** ⇒ 守卫先于一切副作用
#   ④⑤  `cleanup -S`（AC4/D2）：rc=2 + 指路 `--session`；非 cleanup 子命令带 `-S` 同口径
#   ⑥   `cleanup` 缺 `--session` ⇒ rc=2（显式目标必给）
#   ⑦   `cleanup --session default` 无 `--force` ⇒ 拒；`--session <隔离名>` 空场 ⇒ effect=0（与 v0.27.0 一致）
#   ⑧   测试侧 S1 等价：`NAO_TEST_TERMINAL=<任意值>` ⇒ run.sh rc=1 + 指路（fail loud，不静默全跑）
#   ⑨   退役编号：`--case 12` ⇒ rc=1 + 「用例不存在」（**不得**退化为 PENDING/SKIP）
#   ⑩   退役面不存在（AC5/AC6）：`tests/t4/backends/`、`run-dual.sh`、`package.json:test:t4:full:dual`、
#       脚本内 `term-impl-tmux` 区间、run.sh 的 `PENDING|TMUX-ONLY` 概念
#   ⑪   AC8 静态 lint 正控（必红）：命令位调用 / 原样 `tmux)` 臂 / 比较式 / 单行 case 臂 四形态均命中并给行号
#   ⑫   AC8 守卫臂白名单双向：真守卫（含「已移除」）放行；改赋值式或摘掉文案 ⇒ 必红
#   ⑬   AC8 静态 lint 负控（不红）：注释迁移提示 / `command -v tmux` / 注释旧命令 / 名册字段+宿主句柄 / 非 tmux case 臂
#   ⑭   AC8 正控（真件）：真脚本 + run.sh + 其余 `.agents/scripts/*.sh` 全部 0 命中
#   ⑮   D3 删除面：脚本无 `NAO_TMUX_LAYOUT|MAIN_WIDTH|MIN_PANE_WIDTH`，check 无「== tmux 布局 ==」节
#
# 零敏感值：本用例只造临时夹具（$T4_CACHE_DIR）；不写仓库、不碰真 herdr/tmux。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab41-$$"; mkdir -p "$LAB/bin"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
# PATH 桩：记录每一次后端调用（守卫必须**先于**任何后端调用 ⇒ 日志 0 行）
CALL_LOG="$T4_CACHE_DIR/c41-calls-$$.log"; : > "$CALL_LOG"
cat > "$LAB/bin/herdr" <<SH
#!/usr/bin/env bash
printf 'herdr %s\n' "\$*" >> "$CALL_LOG"
exit 0
SH
cat > "$LAB/bin/tmux" <<SH
#!/usr/bin/env bash
printf 'tmux %s\n' "\$*" >> "$CALL_LOG"
exit 0
SH
chmod +x "$LAB/bin/herdr" "$LAB/bin/tmux"

c41() { # <env 前缀…> -- 由调用方内联；这里只做「干净环境 + PATH 桩」的统一入口
  ( cd "$T4_ROOT" && env "${T4_HERDR_UNSET_ARGS[@]}" \
      PATH="$LAB/bin:$PATH" PI_CODING_AGENT_DIR="$T4_CACHE_DIR/c41-pi" "$@" )
}

# ---------------------------------------------------------------- ①②③ 旧后端变量 ⇒ rc=2（D2）
mkdir -p "$T4_CACHE_DIR/c41-pi"
: > "$CALL_LOG"
t4_run_in_dir "$T4_ROOT" env "${T4_HERDR_UNSET_ARGS[@]}" NAO_TERMINAL=tmux PATH="$LAB/bin:$PATH" \
  PI_CODING_AGENT_DIR="$T4_CACHE_DIR/c41-pi" timeout 60 bash "$FLEET" ensure pm
t4_assert_eq "2" "$T4_RC" "① 旧后端变量 ensure ⇒ rc=2（D2：用法守卫，命令未执行）"
t4_assert_eq "" "$T4_OUT" "① stdout 为空（提示只走 stderr，不谎报结果）"
t4_assert_eq "1" "$(printf '%s\n' "$T4_ERR" | grep -c .)" "② stderr **恰 1 行**（D2 文案契约）"
t4_assert_match "$T4_ERR" '已移除 tmux 后端' "② stderr 点名「已移除 tmux 后端」"
t4_assert_match "$T4_ERR" 'herdr' "② stderr 指路唯一后端 herdr"
t4_assert_eq "0" "$(grep -c . "$CALL_LOG" || true)" "③ 零副作用：PATH 桩（herdr/tmux）0 命中"
t4_run_in_dir "$T4_ROOT" env "${T4_HERDR_UNSET_ARGS[@]}" NAO_TERMINAL=tmux PATH="$LAB/bin:$PATH" \
  PI_CODING_AGENT_DIR="$T4_CACHE_DIR/c41-pi" timeout 60 bash "$FLEET" check
t4_assert_eq "2" "$T4_RC" "① 旧后端变量 check ⇒ rc=2（与 ensure 同口径，不做「体检照跑」例外）"
t4_run_in_dir "$T4_ROOT" env NAO_TERMINAL=bogus PATH="$LAB/bin:$PATH" timeout 60 bash "$FLEET" status
t4_assert_eq "2" "$T4_RC" "① 其他非 herdr 值 ⇒ 同样 rc=2（不静默回落）"
t4_assert_eq "0" "$(grep -c . "$CALL_LOG" || true)" "③ 同口径零副作用（桩仍 0 命中）"

# ---------------------------------------------------------------- ④⑤⑥ cleanup 参数面（AC4）
t4_run_in_dir "$T4_ROOT" env NAO_TERMINAL=herdr timeout 60 bash "$FLEET" cleanup -S /tmp/c41-sock
t4_assert_eq "2" "$T4_RC" "④ cleanup -S ⇒ rc=2（旧实验场 socket 面已随 tmux 移除 —— AC4）"
t4_assert_contains "$T4_ERR" "--session" "④ 指路新写法 --session <名>（fail loud，不静默吞参）"
t4_assert_eq "1" "$(printf '%s\n' "$T4_ERR" | grep -c .)" "④ 提示恰 1 行"
t4_run_in_dir "$T4_ROOT" env NAO_TERMINAL=herdr timeout 60 bash "$FLEET" status -S /tmp/c41-sock
t4_assert_eq "2" "$T4_RC" "⑤ 非 cleanup 子命令带 -S ⇒ 仍 rc=2（既有守卫保留，同一口径）"
t4_run_in_dir "$T4_ROOT" env NAO_TERMINAL=herdr timeout 60 bash "$FLEET" cleanup
t4_assert_eq "2" "$T4_RC" "⑥ cleanup 缺 --session ⇒ rc=2（显式目标必给）"
t4_assert_contains "$T4_ERR" "--session" "⑥ 缺参给可执行指路"

# ---------------------------------------------------------------- ⑦ cleanup --session 行为（D5：逐字一致）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }
BE_FLEET_NO_HANDLES=1 be_run_fleet "$LAB" cleanup --session default
t4_assert_eq "2" "$BE_RC" "⑦ cleanup --session default 无 --force ⇒ 拒（BR9，不碰用户会话）"
be_run_fleet "$LAB" cleanup --session "$BE_SESSION"
t4_assert_eq "0" "$BE_RC" "⑦ cleanup --session <隔离名>（空场）⇒ rc=0（幂等 effect=0）"
t4_assert_match "$BE_OUT" 'effect=(0|已消失)' "⑦ 明确报 effect（0 = 无动作 / 已消失 = 真拆；判 effect 不看 rc）"
be_teardown >/dev/null 2>&1 || true

# ---------------------------------------------------------------- ⑧ 测试侧 fail loud（§0）
t4_run_in_dir "$T4_ROOT" env NAO_TEST_TERMINAL=tmux timeout 120 bash tests/t4/run.sh --list
t4_assert_eq "1" "$T4_RC" "⑧ NAO_TEST_TERMINAL=tmux ⇒ run.sh rc=1（测试侧 S1 等价，fail loud）"
t4_assert_contains "$T4_ERR" "已移除" "⑧ stderr 点名「已移除」（不静默按 herdr 跑）"
t4_assert_contains "$T4_ERR" "herdr 是唯一后端" "⑧ 指路唯一后端 herdr"
t4_run_in_dir "$T4_ROOT" env NAO_TEST_TERMINAL=herdr timeout 120 bash tests/t4/run.sh --list
t4_assert_eq "1" "$T4_RC" "⑧ 反向对照：开关本身已删除 ⇒ 任意非空值（含 herdr）一律拒（不保留「合法取值」）"

# ---------------------------------------------------------------- ⑨ 退役编号（§3 态 6）
t4_run_in_dir "$T4_ROOT" timeout 120 bash tests/t4/run.sh --case 12
t4_assert_eq "1" "$T4_RC" "⑨ --case 12（已退役）⇒ rc=1（参数错误，不跑）"
t4_assert_contains "$T4_ERR" "用例不存在" "⑨ 明确报「用例不存在」（不得退化为 PENDING/SKIP）"
t4_assert_not_contains "$T4_OUT" "PENDING" "⑨ 输出无 PENDING 概念（登记集已删 —— D4）"
t4_assert_not_contains "$T4_OUT" "SKIP" "⑨ 也不伪装成 SKIP"

# ---------------------------------------------------------------- ⑩ 退役面不存在（AC5/AC6）
t4_assert_absent "$T4_ROOT/tests/t4/backends" "⑩ 登记集目录 tests/t4/backends/ 已删（D4）"
t4_assert_absent "$T4_ROOT/tests/t4/run-dual.sh" "⑩ run-dual.sh 已删（单后端后双跑编排无对象）"
t4_assert_eq "0" "$(node -e 'const p=require(process.argv[1]);process.stdout.write(Object.keys(p.scripts).includes("test:t4:full:dual")?"1":"0")' "$T4_ROOT/package.json")" \
  "⑩ package.json 无 test:t4:full:dual script（防复活）"
t4_assert_eq "0" "$(grep -c 'term-impl-tmux' "$FLEET" || true)" "⑩ 脚本内 term-impl-tmux 区间标记 0 处"
t4_assert_eq "0" "$(grep -vE '^[[:space:]]*#' "$T4_ROOT/tests/t4/run.sh" | grep -cE 'PENDING|TMUX-ONLY' || true)" \
  "⑩ run.sh 逻辑面无 PENDING/TMUX-ONLY（注释里的历史注记允许保留）"
t4_assert_absent "$T4_ROOT/tests/t4/cases/12-derived-pane-window.sh" "⑩ 用例 12 文件已删（退役不复用编号）"
t4_assert_absent "$T4_ROOT/tests/t4/cases/25-layout-guard-capacity.sh" "⑩ 用例 25 文件已删（D3 整组删）"

# ---------------------------------------------------------------- ⑪⑫⑬ AC8 静态 lint 双向
t4_assert_eq "" "$(t4_scan_tmux_residue "$FLEET")" "⑭ 正控（真件）：nao-fleet.sh 0 处旧面残留"
t4_assert_eq "" "$(t4_scan_tmux_residue "$T4_ROOT/tests/t4/run.sh")" "⑭ 正控（真件）：run.sh 0 处旧面残留"
for _s in "$T4_ROOT"/.agents/scripts/*.sh; do
  t4_assert_eq "" "$(t4_scan_tmux_residue "$_s")" "⑭ 正控（真件）：$(basename "$_s") 0 处旧面残留"
done
# --- ⑪ 正控：三种**真实复活形态**（T555/QA P2-2；旧 lint 只认命令位与赋值字面量 ⇒ 全放过）---
NEG41="$(mktemp "$T4_CACHE_DIR/c41-neg-XXXXXX.sh")"

# ⑪-a 原样 `tmux)` 臂（无「已移除」文案）⇒ 必红（不改写成 lint 认识的其他形状）
cat > "$NEG41" <<'SH'
case "${NAO_TERMINAL:-}" in
  tmux) printf 'tmux 回退已启用\n' >&2; return 0 ;;
esac
SH
out="$(t4_scan_tmux_residue "$NEG41")"
t4_assert_ne "" "$out" "⑪-a 正控（必红）：原样「tmux)」分支 ⇒ 命中（旧 lint 此处漏判）"
t4_assert_match "$out" '^2:tmux\)' "⑪-a 命中带**行号 + 原文**（可定位）"

# ⑪-b 比较式（含参数展开默认值）⇒ 必红
cat > "$NEG41" <<'SH'
if [ "${NAO_TERMINAL:-herdr}" = "tmux" ]; then :; fi
SH
t4_assert_ne "" "$(t4_scan_tmux_residue "$NEG41")" "⑪-b 正控（必红）：\`[ \"\${NAO_TERMINAL:-herdr}\" = \"tmux\" ]\` 比较式 ⇒ 命中"
printf 'if [ "$NAO_TERMINAL" != tmux ]; then :; fi\n' > "$NEG41"
t4_assert_ne "" "$(t4_scan_tmux_residue "$NEG41")" "⑪-b2 正控（必红）：\`\"$NAO_TERMINAL\" != tmux\`（短路/反向比较同样禁止）"

# ⑪-c 单行 case 臂 + 臂内命令位调用 ⇒ 必红
printf 'case "$BE" in tmux) exec tmux new -s nao ;; esac\n' > "$NEG41"
t4_assert_ne "" "$(t4_scan_tmux_residue "$NEG41")" "⑪-c 正控（必红）：单行 \`case … in tmux) exec tmux …\` ⇒ 命中"

# ⑫ 守卫臂白名单双向：真守卫（带「已移除」）⇒ 放行；摘掉文案 ⇒ 必红（白名单不是恒放行）
NEG41B="$T4_CACHE_DIR/c41-neg-b.sh"
sed 's/^    tmux)$/    NAO_TERMINAL=tmux) :/' "$FLEET" > "$NEG41B"
out="$(t4_scan_tmux_residue "$NEG41B")"
t4_assert_ne "" "$out" "⑫ 正控②（必红）：守卫改回赋值式分支 ⇒ 命中规则②"
t4_assert_match "$out" 'NAO_TERMINAL=tmux' "⑫ 命中并回显该字面量"
t4_assert_eq "" "$(t4_scan_tmux_residue "$FLEET")" "⑫ 守卫臂（原样，含「已移除」文案）⇒ 白名单放行（真件 0 命中）"
NEG41D="$T4_CACHE_DIR/c41-neg-d.sh"
sed "s/已移除 tmux 后端/旧后端/" "$FLEET" > "$NEG41D"
out="$(t4_scan_tmux_residue "$NEG41D")"
t4_assert_ne "" "$out" "⑫-b 正控（必红）：守卫臂摘掉「已移除」文案 ⇒ \`tmux)\` 臂立刻命中（白名单非恒放行）"
t4_assert_match "$out" '^[0-9]+:tmux\)' "⑫-b 命中点正是守卫臂（行号 + 原文）"

# --- ⑬ 负控（不红）---
printf '# 迁移提示：旧版可 `command -v tmux` 判断是否装过 tmux（本版已不调用）\n' > "$NEG41"
t4_assert_eq "" "$(t4_scan_tmux_residue "$NEG41")" "⑬-a 负控（不红）：注释里的迁移提示不误伤"
printf '%s\n' 'command -v tmux >/dev/null 2>&1 && echo 旧版 tmux 已移除' > "$NEG41"
t4_assert_eq "" "$(t4_scan_tmux_residue "$NEG41")" "⑬-b 负控（不红）：\`command -v tmux\` 探测（迁移诊断）不误伤"
printf '%s\n' '# tmux list-panes  # 迁移指路示例' > "$NEG41"
t4_assert_eq "" "$(t4_scan_tmux_residue "$NEG41")" "⑬-c 负控（不红）：注释里的旧命令示例不误伤"
printf 'X=1  # 名册字段 "tmuxPane" 是外部契约\n_TERM_HOST_HANDLE_VARS=(TMUX TMUX_PANE TMUX_TMPDIR)\n' > "$NEG41"
t4_assert_eq "" "$(t4_scan_tmux_residue "$NEG41")" "⑬-d 负控（不红）：名册字段与宿主句柄名表在白名单内"
printf 'case "$TERM" in screen) : ;; esac\n' > "$NEG41"
t4_assert_eq "" "$(t4_scan_tmux_residue "$NEG41")" "⑬-e 负控（不红）：非 tmux 的 case 臂（screen）不误伤"
rm -f "$NEG41"

# ---------------------------------------------------------------- ⑮ D3 删除面
t4_assert_eq "0" "$(grep -cE 'NAO_TMUX_LAYOUT|NAO_TMUX_MAIN_WIDTH|NAO_TMUX_MIN_PANE_WIDTH' "$FLEET" || true)" \
  "⑮ 死配置整组删：脚本内 NAO_TMUX_LAYOUT / MAIN_WIDTH / MIN_PANE_WIDTH 0 处（D3）"
t4_assert_eq "0" "$(grep -c '== tmux 布局 ==' "$FLEET" || true)" "⑮ check 的「== tmux 布局 ==」节已删（D3）"
t4_assert_eq "0" "$(grep -cE 'main_row2_geom|_layout_checksum|build_main_row2_layout' "$FLEET" || true)" \
  "⑮ tmux 布局几何函数（checksum / main-row2 算式）已整组删"

t4_exit
