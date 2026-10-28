#!/usr/bin/env bash
# 用例 13 —— close 的前提闸门与末段判定（T529 收窄后）
#
# PRD：docs/prds/2026-10-27-strict-tmux-pi.md（§七 AC1/AC4）· ADR `docs/adr/2026-10-27-strict-tmux-pi.md`
# 被测对象：.agents/scripts/nao-fleet.sh
#   · 入口 require_tmux：非 tmux ⇒ rc=3 单行提示（含 `tmux new -s nao`），无副作用（不建 session/pane/lock）
#   · cmd_close 末段：tmux 内 + 名册可用且为空 + 无任何句柄 ⇒ 「未运行（无需回收）」rc=0
#   · --force 不改变末段判定；「无法确认在线状态」分支已随 T529 退役（静态 grep 归零）
#
# 断言编号 ↔ 依据：
#   ① AC1 非 tmux 跑 close ⇒ rc=3（前提不满足 ⇒ 命令未执行）
#   ② AC1 同场景 stdout 无输出（提示走 stderr）、且不含「未运行（无需回收）」（无副作用谎报）
#   ③ AC1 提示 = 单行且含 `tmux new -s nao`
#   ④ AC4 静态：`nao-fleet.sh` 内 `grep -c '无法确认在线'` = 0（T523 分支已删）
#   ⑤ AC2 静态：宿主阶梯删除面 grep = 0（NAO_TERMINAL/xdg-terminal-exec/hyprctl/swaymsg/xdotool/wmctrl/screen_*）
#   ⑥ AC4 tmux 内 + 名册可用且为空 + 无句柄 ⇒ rc=0 + 「未运行（无需回收）」（不过度矫正为恒失败）
#   ⑦ AC4 --force 不改变末段：rc 与 ⑥ 逐值一致、仍含「未运行（无需回收）」
#
# BR6 hermetic：一律派生名 `close --task <唯一号> qa`（禁裸 `close qa` —— 本机测试进程自身标题即
#   `π - qa - <repo>`，裸名会命中调用者自身 pane 而落到 F1「拒绝回收」分支，rc=1 但**原因不同**）。
#   唯一号含 $$ 保证隔离。夹具全部落 $T4_CACHE_DIR；只读仓库、不写工作区、不实拉 / 不实回收任何进程。
#   tmux 句柄用**不存在的假 socket**（`/tmp/nao-t4-c13-*`）：所有 tmux 调用由机制自身 2>/dev/null 兜底，
#   不接触调用者的真 server（T516 血训：不裸 tmux）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
C13_T="T4C13$$"                                      # 唯一任务编号（--task 合法字符集）
C13_TMUX="/tmp/nao-t4-c13-$$,1,0"                    # 假 $TMUX：过入口闸门，但无 server 可连
TASKS_NONE="$T4_CACHE_DIR/c13-none.md"               # 不存在 ⇒ 跳过 tasks-state 闸门（不污染本题证据）
EMPTY_PI="$(mktemp -d "$T4_CACHE_DIR/c13-pi.XXXXXX")"  # 空 PI dir ⇒ intercom_list_json 失败
MARK="未运行（无需回收）"

# ---- 前置探测：④⑤ 能力门（tsx 名册探针）；缺失 ⇒ t4_degrade（BR7）----
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
tsx_ok=""
if [ -f "$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then tsx_ok=1; fi

# ---------------------------------------------------------------- ①②③ 非 tmux ⇒ exit 3
t4_run_in_dir "$T4_ROOT" env -u TMUX -u NAO_TERMINAL \
  PI_CODING_AGENT_DIR="$EMPTY_PI" NAO_TASKS_STATE="$TASKS_NONE" \
  timeout 60 bash "$FLEET" close --task "$C13_T" qa
t4_assert_eq "3" "$T4_RC" "① 非 tmux 跑 close ⇒ rc=3（前提不满足，命令未执行）"
t4_assert_eq "" "$T4_OUT" "② 同场景 stdout 为空（提示只走 stderr，不谎报结果）"
t4_assert_not_contains "$T4_OUT" "$MARK" "② 同场景不得报「$MARK」"
t4_assert_contains "$T4_ERR" "tmux new -s nao" "③ stderr 含可操作提示「tmux new -s nao」"
t4_assert_eq "1" "$(printf '%s\n' "$T4_ERR" | grep -c .)" "③ 提示恰为单行（可复制，不刷屏）"

# ---------------------------------------------------------------- ④⑤ 静态归零
t4_assert_eq "0" "$(grep -c '无法确认在线' "$FLEET" 2>/dev/null || true)" \
  "④ AC4：nao-fleet.sh 内「无法确认在线状态」分支已删（grep=0）"
t4_assert_eq "0" "$(grep -cE 'NAO_TERMINAL|xdg-terminal-exec|hyprctl|swaymsg|xdotool|wmctrl|screen_present|screen_token_for|spawn_screen|spawn_xdg_window|spawn_tmux_attach|wait_for_tmux_client|app_class_visible|wait_for_app_class|spawn_fork_window' "$FLEET" 2>/dev/null || true)" \
  "⑤ AC2：宿主阶梯删除面在脚本内 grep=0"

# ---------------------------------------------------------------- ⑥⑦ tmux 内末段（名册可用且为空）
if [ "$tsx_ok" = "1" ]; then
  C13_FX="$T4_CACHE_DIR/fx13-$$"
  rm -rf "$C13_FX"; mkdir -p "$C13_FX"
  cp -r "$T4_ROOT/.agents" "$C13_FX/.agents" || t4_blocked "用例 13 夹具复制 .agents 失败"
  cat > "$C13_FX/.agents/scripts/intercom-probe.mts" <<'JS'
// T4 case13 hermetic roster fixture（只读 env；不接触真实 pi-intercom 名册）
const raw = process.env.NAO_QA_FAKE_ROSTER || "[]";
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(raw) }));
JS
  c13_close() { # 透传额外 fleet 参数（如 --force），恒以派生名收尾
    t4_run_in_dir "$C13_FX" env TMUX="$C13_TMUX" NAO_SKILLS="$C13_FX" \
      NAO_TASKS_STATE="$TASKS_NONE" NAO_QA_FAKE_ROSTER='[]' \
      timeout 60 bash "$C13_FX/.agents/scripts/nao-fleet.sh" close "$@" --task "$C13_T" qa
  }
  c13_close
  t4_assert_eq "0" "$T4_RC" "⑥ tmux 内 + 名册可用且为空 + 无句柄 ⇒ rc=0（真离线不误判）"
  t4_assert_contains "$T4_OUT" "$MARK" "⑥ 同场景 stdout 含「$MARK」"
  C13_RC_PLAIN="$T4_RC"
  c13_close --force
  t4_assert_eq "$C13_RC_PLAIN" "$T4_RC" "⑦ --force 不改变末段判定（rc 逐值一致 = $C13_RC_PLAIN）"
  t4_assert_contains "$T4_OUT" "$MARK" "⑦ --force 下 stdout 仍含「$MARK」"
else
  t4_degrade "缺 tsx / node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ ⑥⑦ 能力降级（默认豁免、full 计分；BR7）"
fi

t4_exit
