#!/usr/bin/env bash
# 用例 13 —— close 末段「无法确认在线状态 ⇒ 非静默失败」回归护栏（T523）
#
# PRD：docs/prds/2026-10-14-close-guard-coverage.md（§三 范围 1–4 · §五 BR1–BR8 · §七 AC2–AC8）
# 被测对象：.agents/scripts/nao-fleet.sh
#   · offline_verifiable() 三子句（名册可用 / $TMUX 在场 / NAO_TERMINAL ∈ {tmux,screen}）
#   · cmd_close 末段四条出口（名册在线无句柄 / 派生在场歧义 / 静默「未运行（无需回收）」/ 兜底 warn）
#
# 断言编号 ↔ PRD：
#   ① AC3 不可验证环境 ⇒ rc≠0
#   ② AC3 同场景 stdout 不含「未运行（无需回收）」
#   ③ AC3 同场景 stderr（BR4：warn 走 stderr，查 stdout 会得到恒假断言）含「无法确认」「不做静默 no-op」
#   ④ AC3 反向（真离线）⇒ rc=0 + stdout 含「未运行（无需回收）」（= offline_verifiable 子句①名册可用）
#   ⑤ AC4 判据三处（BR5）：NAO_TERMINAL=tmux 成立 / NAO_TERMINAL=foot 不成立 / $TMUX 在场成立
#   ⑥ AC7 锁定现状：--force 不改变本分支 rc 且仍不含「未运行（无需回收）」
#
# BR6 hermetic：一律派生名 `close --task <唯一号> qa`（禁裸 `close qa` —— 本机测试进程
#   自身标题即 `π - qa - <repo>`，裸名会命中调用者自身 pane 而落到 F1「拒绝回收」分支，
#   rc=1 但**原因不同** ⇒ ③ 会因错误原因失败）。唯一号含 $$ 保证隔离；保留 TMUX_PANE。
# 夹具全部落 $T4_CACHE_DIR；只读仓库、不写工作区、不实拉 / 不实回收任何进程。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
C13_T="T4C13$$"                                      # 唯一任务编号（--task 合法字符集）
C13_NAME="qa-$C13_T"                                 # 对应派生会话名
TASKS_NONE="$T4_CACHE_DIR/c13-none.md"               # 不存在 ⇒ 跳过 tasks-state 闸门（不污染本题证据）
EMPTY_PI="$(mktemp -d "$T4_CACHE_DIR/c13-pi.XXXXXX")"  # 空 PI dir ⇒ intercom_list_json 失败（全脚本仅此一处消费）
MARK="未运行（无需回收）"

# ---- 前置探测 1：唯一名意外已存在句柄 / 标题 ⇒ 跳过该组（BR6 隔离兜底，防假 FAIL）----
collide=""
if command -v tmux >/dev/null 2>&1; then
  tmux list-panes -a -F '#{pane_title}' 2>/dev/null | grep -qF " - $C13_NAME - " && collide="pane-title"
  tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -qxF "org.nao.$C13_NAME" && collide="window:org.nao.$C13_NAME"
  tmux has-session -t "=nao-$C13_NAME" 2>/dev/null && collide="session:nao-$C13_NAME"
fi
if [ -z "$collide" ] && command -v screen >/dev/null 2>&1; then
  screen -ls 2>/dev/null | grep -qF "nao-$C13_NAME" && collide="screen:nao-$C13_NAME"
fi
if [ -n "$collide" ]; then
  t4_degrade "唯一名 $C13_NAME 意外已存在句柄（$collide）⇒ 跳过 close 护栏该组（防假 FAIL）"
  t4_exit
fi

# ---- 前置探测 2：④⑤ 需 tsx（名册探针）能力；缺失 ⇒ t4_degrade（BR7，不得静默 PASS/SKIP）----
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
tsx_ok=""
if [ -f "$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then tsx_ok=1; fi

# 不可验证环境跑 close：-u TMUX -u NAO_TERMINAL + 空 PI dir ⇒ offline_verifiable 三子句全假
close_unverifiable() { # 透传额外 fleet 参数（如 --force），恒以派生名收尾
  t4_run_in_dir "$T4_ROOT" env -u TMUX -u NAO_TERMINAL \
    PI_CODING_AGENT_DIR="$EMPTY_PI" NAO_TASKS_STATE="$TASKS_NONE" \
    timeout 60 bash "$FLEET" close "$@" --task "$C13_T" qa
}

# ---------------------------------------------------------------- ①②③ 不可验证 ⇒ 非静默失败
close_unverifiable
RC_UNVER="$T4_RC"
t4_assert_ne "0" "$RC_UNVER" "① 不可验证环境（无 \$TMUX / 无 NAO_TERMINAL / 名册不可用）⇒ close rc≠0"
t4_assert_not_contains "$T4_OUT" "$MARK" "② 同场景 stdout 不得报「$MARK」"
t4_assert_contains "$T4_ERR" "无法确认" "③ 同场景 stderr 含「无法确认…在线状态」（BR4：warn 走 stderr）"
t4_assert_contains "$T4_ERR" "不做静默 no-op" "③ 同场景 stderr 含「不做静默 no-op」（本批核心）"

# ---------------------------------------------------------------- ④⑤ 能力门（BR7）
if [ "$tsx_ok" = "1" ]; then
  # -------------------------------------------------------------- ④ 反向：真离线 ⇒ 静默 rc=0（子句①名册可用）
  C13_FX="$T4_CACHE_DIR/fx13-$$"
  rm -rf "$C13_FX"; mkdir -p "$C13_FX"
  cp -r "$T4_ROOT/.agents" "$C13_FX/.agents" || t4_blocked "用例 13 夹具复制 .agents 失败"
  cat > "$C13_FX/.agents/scripts/intercom-probe.mts" <<'JS'
// T4 case13 hermetic roster fixture（只读 env；不接触真实 pi-intercom 名册）
const raw = process.env.NAO_QA_FAKE_ROSTER || "[]";
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(raw) }));
JS
  t4_run_in_dir "$C13_FX" env -u TMUX -u NAO_TERMINAL NAO_SKILLS="$C13_FX" \
    NAO_TASKS_STATE="$TASKS_NONE" NAO_QA_FAKE_ROSTER='[]' \
    timeout 60 bash "$C13_FX/.agents/scripts/nao-fleet.sh" close --task "$C13_T" qa
  t4_assert_eq "0" "$T4_RC" "④ 名册可用且为空 + 无句柄 ⇒ rc=0（真离线，不过度矫正）"
  t4_assert_contains "$T4_OUT" "$MARK" "④ 同场景 stdout 含「$MARK」（钉 offline_verifiable 子句①）"

  # -------------------------------------------------------------- ⑤ 判据三处（BR5，防定义被收窄/放宽）
  # ⑤a 子句③正：NAO_TERMINAL=tmux（无 $TMUX）⇒ 可验证
  t4_run_in_dir "$T4_ROOT" env -u TMUX NAO_TERMINAL=tmux \
    PI_CODING_AGENT_DIR="$EMPTY_PI" NAO_TASKS_STATE="$TASKS_NONE" \
    timeout 60 bash "$FLEET" close --task "$C13_T" qa
  t4_assert_eq "0" "$T4_RC" "⑤a NAO_TERMINAL=tmux ⇒ offline_verifiable 成立（rc=0）"
  t4_assert_contains "$T4_OUT" "$MARK" "⑤a 同场景 stdout 含「$MARK」"

  # ⑤b 定义边界：NAO_TERMINAL=foot **不**构成可验证 —— 定义精确为 tmux|screen；
  #     foot 属「窗口宿主」（无 tmux 句柄），必须靠名册；名册不可用 ⇒ 非静默 rc≠0。
  #     此断言同时封「把定义放宽到任意终端」与「把定义收窄删掉 NAO_TERMINAL 子句」两个方向。
  t4_run_in_dir "$T4_ROOT" env -u TMUX NAO_TERMINAL=foot \
    PI_CODING_AGENT_DIR="$EMPTY_PI" NAO_TASKS_STATE="$TASKS_NONE" \
    timeout 60 bash "$FLEET" close --task "$C13_T" qa
  t4_assert_ne "0" "$T4_RC" "⑤b NAO_TERMINAL=foot 不构成可验证 ⇒ rc≠0（定义不得被放宽）"
  t4_assert_not_contains "$T4_OUT" "$MARK" "⑤b 同场景 stdout 不得报「$MARK」"

  # ⑤c 子句②正：$TMUX 在场（NAO_TERMINAL 未设）⇒ 可验证
  t4_run_in_dir "$T4_ROOT" env -u NAO_TERMINAL TMUX=/tmp/nao-t4-c13-fake,1,0 \
    PI_CODING_AGENT_DIR="$EMPTY_PI" NAO_TASKS_STATE="$TASKS_NONE" \
    timeout 60 bash "$FLEET" close --task "$C13_T" qa
  t4_assert_eq "0" "$T4_RC" "⑤c \$TMUX 在场 ⇒ offline_verifiable 成立（rc=0）"
  t4_assert_contains "$T4_OUT" "$MARK" "⑤c 同场景 stdout 含「$MARK」"
else
  t4_degrade "缺 tsx / node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ ④⑤ 能力降级（默认豁免、full 计分；BR7）"
fi

# ---------------------------------------------------------------- ⑥ --force 现状锁定（AC7）
# QA 实测：末段不消费 --force（它只作用于闸门① tasks-state / ② 在跑 turn）⇒ 本分支 rc 不变。
close_unverifiable --force
t4_assert_ne "0" "$T4_RC" "⑥ --force 不改变本分支：仍 rc≠0"
t4_assert_eq "$RC_UNVER" "$T4_RC" "⑥ --force 下 rc 与无 --force 逐值一致（=$RC_UNVER）"
t4_assert_not_contains "$T4_OUT" "$MARK" "⑥ --force 下 stdout 仍不得报「$MARK」"

t4_exit
