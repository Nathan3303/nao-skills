#!/usr/bin/env bash
# 用例 13 —— close 的前提闸门与末段判定（T555 纯 herdr 化后）
#
# PRD：docs/prds/2026-11-22-herdr-only.md（AC3/AC4）· ADR `docs/adr/2026-11-22-herdr-only.md`
# 被测对象：.agents/scripts/nao-fleet.sh
#   · 旧调用面 fail loud：`NAO_TERMINAL=tmux` ⇒ rc=2 + 单行 stderr（点名「已移除」+ herdr 指路），
#     命令未执行（不建 session/pane/lock，零副作用）
#   · herdr 前提：`HERDR_ENV`/`HERDR_SESSION` 缺 ⇒ exit 3 单行提示（命令未执行）
#   · cmd_close 末段：herdr 内 + pane list 空 + 名册空 + 无任何句柄 ⇒ 「未运行（无需回收）」rc=0
#   · --force 不改变末段判定；「无法确认在线状态」分支已随 T529 退役（静态 grep 归零）
#
# 断言编号 ↔ 依据：
#   ① AC3 旧后端变量跑 close ⇒ rc=2（用法守卫 ⇒ 命令未执行）
#   ② AC3 同场景 stdout 无输出（提示走 stderr）、且不含「未运行（无需回收）」（不谎报结果）
#   ③ AC3 提示 = 单行且点名「已移除」+ 唯一后端 herdr（可断言文案）
#   ④ AC4 静态：`nao-fleet.sh` 内 `grep -c '无法确认在线'` = 0（T523 分支已删）
#   ⑤ AC2 静态：宿主阶梯删除面 grep = 0（xdg-terminal-exec/hyprctl/swaymsg/xdotool/wmctrl/screen_*）
#      （#96 B1 起 `NAO_TERMINAL` 是后端开关；T555 起只用于拒绝旧值）
#   ⑥ herdr 前提：无 `HERDR_ENV`/`HERDR_SESSION`（BE_FLEET_NO_HANDLES=1）⇒ rc=3（命令未执行）
#   ⑥ AC4 herdr 内 + pane list 空 + 名册空 + 无句柄 ⇒ rc=0 + 「未运行（无需回收）」（不过度矫正为恒失败）
#   ⑦ AC4 --force 不改变末段：rc 与 ⑥ 逐值一致、仍含「未运行（无需回收）」
#
# BR6 hermetic：一律派生名 `close --task <唯一号> qa`（禁裸 `close qa` —— 本机测试进程自身标题即
#   `π - qa - <repo>`，裸名会命中调用者自身 pane 而落到 F1「拒绝回收」分支，rc=1 但**原因不同**）。
#   唯一号含 $$ 保证隔离。夹具全部落 $T4_CACHE_DIR；只读仓库、不写工作区、不实拉 / 不实回收任何进程。
#   后端场用 `tests/t4/fixtures/herdr-double`（确定性替身 + 私有 XDG 根），不碰真 herdr/用户 default。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
C13_T="T4C13$$"                                      # 唯一任务编号（--task 合法字符集）
TASKS_NONE="$T4_CACHE_DIR/c13-none.md"               # 不存在 ⇒ 跳过 tasks-state 闸门（不污染本题证据）
EMPTY_PI="$(mktemp -d "$T4_CACHE_DIR/c13-pi.XXXXXX")"  # 空 PI dir ⇒ intercom_list_json 失败
MARK="未运行（无需回收）"

# ---------------------------------------------------------------- ①②③ 旧后端变量 ⇒ exit 2
t4_run_in_dir "$T4_ROOT" env NAO_TERMINAL=tmux \
  PI_CODING_AGENT_DIR="$EMPTY_PI" NAO_TASKS_STATE="$TASKS_NONE" \
  timeout 60 bash "$FLEET" close --task "$C13_T" qa
t4_assert_eq "2" "$T4_RC" "① 旧后端变量跑 close ⇒ rc=2（用法守卫，命令未执行）"
t4_assert_eq "" "$T4_OUT" "② 同场景 stdout 为空（提示只走 stderr，不谎报结果）"
t4_assert_not_contains "$T4_OUT" "$MARK" "② 同场景不得报「$MARK」"
t4_assert_match "$T4_ERR" '已移除 tmux 后端.*herdr' "③ stderr 点名「已移除 tmux 后端」并指路 herdr（唯一后端）"
t4_assert_eq "1" "$(printf '%s\n' "$T4_ERR" | grep -c .)" "③ 提示恰为单行（可复制，不刷屏）"

# ---------------------------------------------------------------- ④⑤ 静态归零
t4_assert_eq "0" "$(grep -c '无法确认在线' "$FLEET" 2>/dev/null || true)" \
  "④ AC4：nao-fleet.sh 内「无法确认在线状态」分支已删（grep=0）"
t4_assert_eq "0" "$(grep -cE 'xdg-terminal-exec|hyprctl|swaymsg|xdotool|wmctrl|screen_present|screen_token_for|spawn_screen|spawn_xdg_window|spawn_tmux_attach|wait_for_tmux_client|app_class_visible|wait_for_app_class|spawn_fork_window' "$FLEET" 2>/dev/null || true)" \
  "⑤ AC2：宿主阶梯删除面在脚本内 grep=0（#96 B1 起 NAO_TERMINAL 已改作后端开关，移出本交替式）"
t4_assert_eq "0" "$(grep -cE 'NAO_TERMINAL=(screen|xdg|hypr|sway|foot|ghostty|ptyxis|kitty|alacritty|wezterm|wmctrl|xdotool)' "$FLEET" 2>/dev/null || true)" \
  "⑤ AC2：旧宿主阶梯的 NAO_TERMINAL 取值域仍为 0（原语义不被改名带走；含历史真实值 ghostty/ptyxis）"
# 负控（P3-3 · QA 第二轮）：历史真实值来自 cda59b0 的 NAO_TERMINAL_ALLOWED=(tmux foot ghostty ptyxis screen)
#   ⇒ 注入 ghostty / ptyxis 必须被上面那条断言抓到（否则「旧值域仍为 0」是空话）。
for _v in ghostty ptyxis; do
  _fx="$T4_CACHE_DIR/f13-term-$_v.sh"
  cp "$FLEET" "$_fx"
  printf '\nNAO_TERMINAL=%s\n' "$_v" >> "$_fx"
  t4_assert_eq "1" "$(grep -cE 'NAO_TERMINAL=(screen|xdg|hypr|sway|foot|ghostty|ptyxis|kitty|alacritty|wezterm|wmctrl|xdotool)' "$_fx" || true)" \
    "⑤ 负控：注入 NAO_TERMINAL=$_v ⇒ 取值域断言必中（判据非空转）"
  rm -f "$_fx"
done

# ---------------------------------------------------------------- ⑥⑦ herdr 前提与末段（空场 = 真离线）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
LAB="$T4_CACHE_DIR/fx13-$$"
rm -rf "$LAB"; mkdir -p "$LAB"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || t4_blocked "用例 13 夹具复制 .agents 失败"
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }

c13_close() { # 透传额外 fleet 参数（如 --force），恒以派生名收尾
  NAO_QA_FAKE_ROSTER='[]' be_run_fleet "$LAB" close "$@" --task "$C13_T" qa
}

# ⑥a 前提：不注入后端句柄 ⇒ HERDR_ENV/HERDR_SESSION 缺 ⇒ exit 3（命令未执行，单行提示）
BE_FLEET_NO_HANDLES=1 be_run_fleet "$LAB" close --task "$C13_T" qa
t4_assert_eq "3" "$BE_RC" "⑥ herdr 前提：缺 HERDR_ENV/HERDR_SESSION ⇒ rc=3（命令未执行）"
t4_assert_contains "$BE_ERR_ANSI" "需要 herdr pane" "⑥ 前提提示点名「需要 herdr pane」（可操作，不静默）"

# ⑥b 末段：pane list 空 + 名册空 + 无任何句柄 ⇒ 「未运行（无需回收）」rc=0
c13_close
t4_assert_eq "0" "$T4_RC" "⑥ herdr 内 + pane list 空 + 名册空 ⇒ rc=0（真离线不误判）"
t4_assert_contains "$T4_OUT" "$MARK" "⑥ 同场景 stdout 含「$MARK」"
C13_RC_PLAIN="$T4_RC"
c13_close --force
t4_assert_eq "$C13_RC_PLAIN" "$T4_RC" "⑦ --force 不改变末段判定（rc 逐值一致 = $C13_RC_PLAIN）"
t4_assert_contains "$T4_OUT" "$MARK" "⑦ --force 下 stdout 仍含「$MARK」"

be_teardown >/dev/null 2>&1 || true
t4_exit
