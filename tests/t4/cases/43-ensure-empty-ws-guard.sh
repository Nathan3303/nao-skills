#!/usr/bin/env bash
# 用例 43 —— 破坏性守卫：#160 P0（ensure 不得把「只有用户自己 pane 的 workspace」判空并关掉）· T558
#
# 缺陷（v0.28.0 · 已连挂两次用户会话）：
#   放置快照 `_TERM_PLACE_PANE_ROWS` 的字段分隔符是 TAB —— **TAB 属 IFS 空白类** ⇒ `IFS=$'\t' read`
#   会折叠掉空字段（无 label 的 pane = 用户自己手起的会话），整行左移：wsid 位读到 tab_id。
#   ⇒ `hit_ws == wsid` 恒假 ⇒ `first` 空 ⇒ 判成「空 workspace」⇒ `workspace close` ⇒ 连带杀掉用户 pi 会话。
#
# 判据（编号 ↔ 依据）：
#   ① 访问器语义（先红后绿的单位面）：空 label / 空 cwd / 空 fgcwd 的自造行 ⇒ **不左移**（字段取值逐位命中）；
#      分隔符必须非空白（`\x1f`）；行构造点唯一（`_TERM_PLACE_PANE_ROWS+=(` 恰 1 处且走 `_term_place_pane_row`）。
#   ② 静态闸（防回潮）：每个 `_TERM_PLACE_PANE_ROWS` 消费循环必须经单点访问器，且循环体内 **0 个裸 read**；
#      正控：把访问器换成 `IFS=$'\t' read` ⇒ 必红；删掉访问器调用 ⇒ 必红（两向）。
#   ③ 主场景（P0 正控）：目标 ws 内**只有用户自己的无 label pane** ⇒ `ensure` 全程**不发出 `workspace.close`**、
#      用户 pane 存活、fleet pane 正常放置（同一 ws 新建角色 tab，不搬走/不关闭任何东西）。
#   ④ 护栏自证（三向）：
#      a) 根因回退（分隔符改回 TAB）+ 护栏在 ⇒ **不关** + fail loud（护栏兜住解析缺陷）；
#      b) 根因回退 + 拆掉「关前复核」 ⇒ 用户 pane 被杀（拆护栏必红）；
#      c) 根因回退 + 复核恒「0 pane」 ⇒ 用户 pane 被杀（复用快照/恒真复核必红）。
#   ⑤ 真·空 ws 仍要能关（否则旧行为回不去）：0 pane 的旧 ws ⇒ 允许 `workspace close` 重建；ensure rc=0。
#   ⑥ 同族消费点（防「只修 P0 那行」）：
#      · 判重（spawn 同名 label）：ws 内已有 `rd-fe2`（元数据 task=T1）⇒ `ensure --task T1 rd-fe` 判「已在运行」跳过（不新建）；
#      · 槽位/名字：同 ws `ensure --task T2 rd-fe` ⇒ 取最小空闲槽位 1 取名 `rd-fe`（槽位号不承载语义，不复用已占槽位）（`_ensure_pick_num` /
#        `_ensure_task_name_in_ws` 读到的是 label 字段而不是 pane_id）；
#      · 仓归属（`_ensure_ws_panes_in_repo`）：base label 的 ws 里 pane 全在**仓外** ⇒ 让号建 `<base>2`，
#        不把新 pane 塞进别的仓的 ws、也不关那个 ws。
#
# 夹具：`tests/t4/fixtures/herdr-double`（确定性替身）+ 私有 XDG 根；不碰真 herdr / 用户 default。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab43-$$"; OTHER="$T4_CACHE_DIR/c43-other-$$"
mkdir -p "$LAB" "$OTHER"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

CALL_LOG="$T4_CACHE_DIR/c43-calls-$$.log"; : > "$CALL_LOG"
export T4_HERDR_CALL_LOG="$CALL_LOG"
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败"; t4_exit; }

# base label（与 .agents/scripts/nao-fleet.sh::place_key_label 同口径；非 git 仓 ⇒ 路径 basename）
c43_label() {
  local base; base="$(basename "$LAB")"
  printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-16 | sed -e 's/-$//'
}
LBL="$(c43_label)"
t4_assert_ne "" "$LBL" "夹具：base label 可计算（$LBL）"

c43_ws_count() { # 本场 workspace 数
  be_herdr "$BE_SESSION" workspace list 2>/dev/null | _be_json_lines '(r.workspaces||[]).map(w=>w.workspace_id)' | grep -c . || true
}
c43_ws_label_of() { # <wsid> → label
  local ws="$1"
  be_herdr "$BE_SESSION" workspace list 2>/dev/null | _be_json_lines "(r.workspaces||[]).filter(w=>w.workspace_id==='$ws').map(w=>w.label)"
}
c43_panes_in() { # <wsid> → 每行一个 pane_id
  be_herdr "$BE_SESSION" pane list --workspace "$1" 2>/dev/null | _be_json_lines '(r.panes||[]).map(p=>p.pane_id)'
}
c43_close_count() { grep -c 'workspace close' "$CALL_LOG" 2>/dev/null || true; }

# 起场：先让替身落一份空状态，再走 be_start_server。
#   为什么先落状态：`be_start_server` 的「已就绪?」探测在**无状态**时要空转到 50×100ms（实测 ≈8s/次），
#   本用例要重置 5 次场 ⇒ 光探测就吃掉 40s（本批是 P0 热修，门禁时长也要克制）。
c43_boot() {
  be_herdr "$BE_SESSION" server >/dev/null 2>&1 || true
  be_start_server >/dev/null || { t4_bad "起场：be_start_server 失败"; return 1; }
  return 0
}

# 干净场（每个场景一个）：只清替身状态（panes/workspaces/tabs），不重启 server。
c43_reset() {
  local f; f="$(be_sessions_dir)/$BE_SESSION/double-state.json"
  [ -f "$f" ] || { c43_boot; return $?; }
  F="$f" node -e '
const fs = require("fs");
const p = process.env.F;
const st = JSON.parse(fs.readFileSync(p, "utf8"));
st.panes = {}; st.workspaces = {}; st.tabs = {};
fs.writeFileSync(p, JSON.stringify(st));' || { t4_bad "场景重置：改替身状态失败"; return 1; }
  return 0
}

# 造「只有用户自己 pane」的目标 ws（无 label 的 root pane，cwd=本仓）
c43_user_only_ws() { # [cwd] → 打印 "wsid<TAB>pane_id"
  local cwd="${1:-$LAB}" js ws pane
  js="$(be_herdr "$BE_SESSION" workspace create --cwd "$cwd" --label "$LBL" --no-focus 2>/dev/null)" || return 1
  ws="$(printf '%s' "$js" | _be_json_lines '[(r.workspace||{}).workspace_id].filter(Boolean)')"
  [ -n "$ws" ] || return 1
  pane="$(c43_panes_in "$ws" | head -1)"
  [ -n "$pane" ] || return 1
  # 替身的 root pane label 本来就空；显式断言场景前提，防夹具漂移把用例变成空转
  [ "$(be_pane_label "$pane" 2>/dev/null)" = "" ] || return 1
  printf '%s\t%s\n' "$ws" "$pane"
}

# 起场必须在 c43_boot/c43_reset 定义**之后**：早调 = command not found + 零断言假绿（本用例自己踩过）
c43_boot || t4_exit

# ---------------------------------------------------------------- ① 访问器语义（单点提取真件函数）
# T567-A：放置快照实现整组在 fleet/lib/term-herdr.sh（入口不再含实现）
C43_MOD="$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_place_pane_row)"
t4_assert_ne "" "${C43_MOD:-}" "① 定位到 pane 行构造/访问器所在模块"
eval "$(grep -E '^_TERM_PLACE_FS=' "$C43_MOD")" || { t4_bad "① 无法提取 _TERM_PLACE_FS"; t4_exit; }
C43_FNS="$(awk '/^_term_place_pane_row\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$C43_MOD")
$(awk '/^_term_place_pane_fields\(\) \{/{f=1} f{print} f&&/^\}$/{exit}' "$C43_MOD")"
eval "$C43_FNS" 2>/dev/null || { t4_bad "① 无法提取构造/访问器函数"; t4_exit; }

case "$_TERM_PLACE_FS" in
  ' '|$'\t'|$'\n') t4_bad "① 字段分隔符是 IFS 空白类（$'$_TERM_PLACE_FS'）⇒ 空字段必被折叠（#160 根因未修）" ;;
  *) t4_ok "① 字段分隔符非空白（US \\x1f）⇒ read 不折叠空字段" ;;
esac

_term_place_pane_fields "$(_term_place_pane_row "" "w1:p1" "w1" "w1:t1" "/repo" "/repo")"
t4_assert_eq "" "$_TP_LABEL" "① 空 label 保真（不左移）"
t4_assert_eq "w1:p1" "$_TP_PANE" "① 空 label ⇒ pane_id 仍在第 2 位"
t4_assert_eq "w1" "$_TP_WS" "① 空 label ⇒ wsid 仍在第 3 位（P0：不得读到 tab_id）"
t4_assert_eq "w1:t1" "$_TP_TAB" "① 空 label ⇒ tab_id 仍在第 4 位"
t4_assert_eq "/repo" "$_TP_CWD" "① 空 label ⇒ cwd 仍在第 5 位"

_term_place_pane_fields "$(_term_place_pane_row "rd-fe" "w2:p3" "w2" "w2:t2" "" "")"
t4_assert_eq "w2" "$_TP_WS" "① 空 cwd/fgcwd 不左移（wsid 命中）"
t4_assert_eq "" "$_TP_CWD" "① 空 cwd 保真（真空值，不补哨兵）"
t4_assert_eq "" "$_TP_FGCWD" "① 空 fgcwd 保真"
t4_assert_eq "w2:t2" "$_TP_TAB" "① 空 cwd/fgcwd 不左移（tab_id 命中）"

_term_place_pane_fields "$(_term_place_pane_row "rd-be" "w3:p1" "" "w3:t1" "/r" "/r")"
t4_assert_eq "" "$_TP_WS" "① 空 wsid 取到空（不串到 tab_id）"
t4_assert_eq "w3:t1" "$_TP_TAB" "① 空 wsid 后续字段不左移"

# 行构造点唯一（否则双写 ⇒ 下次有人改一处漏一处）
t4_assert_eq "1" "$(grep -cF -- '_TERM_PLACE_PANE_ROWS+=(' "$C43_MOD" || true)" \
  "① pane 行构造点恰 1 处"
t4_assert_eq "1" "$(grep -F -- '_TERM_PLACE_PANE_ROWS+=(' "$C43_MOD" | grep -cF -- '_term_place_pane_row' || true)" \
  "① 唯一构造点走 _term_place_pane_row（不是手拼分隔符）"

# ---------------------------------------------------------------- ② 静态闸（含两向正控）
t4_assert_eq "" "$(t4_scan_place_pane_rows "$T4_ROOT/.agents/scripts")" "② 静态闸（文件集）：裸 read 消费点 = 0，且每循环经访问器"

MUT_DIR="$LAB/.agents/scripts"
MUT_READ="$MUT_DIR/c43-mut-read-$$.sh"
awk '{ if ($0 ~ /_term_place_pane_fields "\$line"/ && !done) { print "      IFS=$'"'"'\\t'"'"' read -r a b c <<< \"$line\" # 正控注入"; done=1; print; next } print }' \
  "$C43_MOD" > "$MUT_READ"
t4_assert_ge "1" "$(t4_scan_place_pane_rows "$MUT_READ" | grep -c . || true)" \
  "② 正控①：把访问器换成裸 IFS=TAB 的 read ⇒ 闸必红"

MUT_NOACC="$MUT_DIR/c43-mut-noacc-$$.sh"
awk '{ if ($0 ~ /^[[:space:]]*_term_place_pane_fields "\$line"$/ && !done) { done=1; print "      # 正控注入：访问器被删"; next } print }' \
  "$C43_MOD" > "$MUT_NOACC"
t4_assert_ge "1" "$(t4_scan_place_pane_rows "$MUT_NOACC" | grep -cF -- '缺访问器' || true)" \
  "② 正控②：删掉访问器调用 ⇒ 闸必红（缺访问器）"

# ---------------------------------------------------------------- ③ 主场景：只有用户自己的 pane
c43_reset || { t4_bad "③ 场景重置失败"; t4_exit; }
SC="$(c43_user_only_ws)" || { t4_bad "③ 无法构造「只有用户 pane 的 ws」场景"; t4_exit; }
WS="${SC%%$'\t'*}"; USER_PANE="${SC#*$'\t'}"
t4_assert_ne "" "$WS" "③ 夹具：用户 ws=$WS / pane=$USER_PANE（label 为空）"
: > "$CALL_LOG"

be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_eq "0" "$BE_RC" "③ ensure rc=0（P0：不得因空判据失败或杀场）"
t4_assert_eq "0" "$(c43_close_count)" "③ **全程未发出 workspace close**（P0 主判据）"
be_pane_alive "$USER_PANE" && t4_ok "③ 用户 pane 存活（$USER_PANE）" || t4_bad "③ 用户 pane 被杀（$USER_PANE —— #160 缺陷复现）"
t4_assert_eq "$LBL" "$(c43_ws_label_of "$WS")" "③ 用户 ws 仍在（label=$LBL，未被关掉重建）"
C43_FLEET_PANE="$(be_pane_by_name "rd-fe")"
t4_assert_ne "" "$C43_FLEET_PANE" "③ fleet pane 正常放置（rd-fe）"
t4_assert_eq "$WS" "$(be_herdr "$BE_SESSION" pane list 2>/dev/null | _be_json_lines "(r.panes||[]).filter(p=>p.pane_id==='$C43_FLEET_PANE').map(p=>p.workspace_id)")" \
  "③ fleet pane 落在用户同一 ws（1 workspace/仓，不另起）"
t4_assert_contains "$BE_OUT" "（成功 1 / 跳过 0 / 失败 0）" "③ 摘要计成功 1（放置成功而非失败）"
C43_MAIN_DONE=1

# ---------------------------------------------------------------- ④ 护栏自证（三向）
# T567-A：变异副本必须是**完整包根**（入口 + fleet/lib）—— 入口用自身位置推 SKILLS_DIR
#   （=<入口>/../..），只克隆 scripts/ 会把 SKILLS_DIR 指到 .agents 下（roles.yaml 缺失 ⇒ 假红）。
c43_mut_root() { # <tag> [src 包根] → 打印 <root>/.agents/scripts（新副本，互不覆盖）
  local tag="$1"
  local srcroot="${2:-$T4_ROOT}"
  local root="$T4_CACHE_DIR/c43-mut-$tag-$$"
  mkdir -p "$root" || return 1
  cp -r "$srcroot/.agents" "$root/.agents" || return 1
  printf '%s\n' "$root/.agents/scripts"
}
C43_MUT_SEP_SCRIPTS="$(c43_mut_root tab)" || { t4_bad "④ 克隆失败"; t4_exit; }
C43_MUT_SEP_ROOT="${C43_MUT_SEP_SCRIPTS%/.agents/scripts}"   # 后续变异从「已回退分隔符」的包根继续派生
C43_MUT_SEP="$C43_MUT_SEP_SCRIPTS/nao-fleet.sh"
C43_MUT_SEP_MOD="$(t4_fleet_file_for "$C43_MUT_SEP_SCRIPTS" _term_place_pane_row)"
t4_assert_ne "" "${C43_MUT_SEP_MOD:-}" "④ 变异夹具：定位到放置快照实现模块"
awk -v q="'" '{ if ($0 ~ /^_TERM_PLACE_FS=/) print "_TERM_PLACE_FS=$" q "\\t" q; else print }' "$C43_MUT_SEP_MOD" > "$C43_MUT_SEP_MOD.new" \
  && mv "$C43_MUT_SEP_MOD.new" "$C43_MUT_SEP_MOD"
t4_assert_eq "1" "$(awk '/^_TERM_PLACE_FS=\$'"'"'\\t'"'"'$/ { n++ } END { print n + 0 }' "$C43_MUT_SEP_MOD")" \
  "④ 变异夹具：分隔符已回退为 TAB（根因复现）"

c43_reset || { t4_bad "④a 场景重置失败"; t4_exit; }
SC="$(c43_user_only_ws)" || { t4_bad "④a 无法构造场景"; t4_exit; }
WS="${SC%%$'\t'*}"; USER_PANE="${SC#*$'\t'}"
: > "$CALL_LOG"
BE_FLEET_SCRIPT="$C43_MUT_SEP" be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_eq "0" "$(c43_close_count)" "④a 根因回退 + 护栏在 ⇒ **仍不关**（护栏兜住解析缺陷）"
be_pane_alive "$USER_PANE" && t4_ok "④a 用户 pane 存活（护栏生效）" || t4_bad "④a 用户 pane 被杀（护栏未生效）"
t4_assert_contains "$BE_ERR_ANSI" "空 workspace 判据与实测冲突" "④a fail loud 点名「快照判 0 pane / 实测非空」"
t4_assert_contains "$BE_ERR_ANSI" "不关" "④a 显式声明不关（点名 wsid 与 pane 数）"

C43_MUT_NOGUARD_SCRIPTS="$(c43_mut_root noguard "$C43_MUT_SEP_ROOT")" || { t4_bad "④b 克隆失败"; t4_exit; }
C43_MUT_NOGUARD="$C43_MUT_NOGUARD_SCRIPTS/nao-fleet.sh"
C43_MUT_NOGUARD_MOD="$(t4_fleet_file_with "$C43_MUT_NOGUARD_SCRIPTS" '空 workspace 判据与实测冲突')"
t4_assert_ne "" "${C43_MUT_NOGUARD_MOD:-}" "④b 变异夹具：定位到关前复核所在模块"
awk '
  { if ($0 ~ /if ! live_n=/) { skip=1 }
    if (skip) { if ($0 ~ /^      fi$/) c++; if (c == 2) { skip=0; c=0 }; next }
    print }' "$C43_MUT_NOGUARD_MOD" > "$C43_MUT_NOGUARD_MOD.new" \
  && mv "$C43_MUT_NOGUARD_MOD.new" "$C43_MUT_NOGUARD_MOD"
t4_assert_eq "0" "$(grep -cF -- '空 workspace 判据与实测冲突' "$C43_MUT_NOGUARD_MOD" || true)" \
  "④b 变异夹具：关前复核调用已拆掉（定义仍在，调用点 0）"

c43_reset || { t4_bad "④b 场景重置失败"; t4_exit; }
SC="$(c43_user_only_ws)" || { t4_bad "④b 无法构造场景"; t4_exit; }
WS="${SC%%$'\t'*}"; USER_PANE="${SC#*$'\t'}"
: > "$CALL_LOG"
BE_FLEET_SCRIPT="$C43_MUT_NOGUARD" be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_ge "1" "$(c43_close_count)" "④b 拆掉关前复核 ⇒ 必红：workspace close 被发出"
be_pane_alive "$USER_PANE" && t4_bad "④b 拆分护栏后用户 pane 仍活（负控未生效，判据空转）" \
  || t4_ok "④b 拆分护栏后用户 pane 被杀（证明护栏是最后一道防线）"

C43_MUT_ALWAYS0_SCRIPTS="$(c43_mut_root always0 "$C43_MUT_SEP_ROOT")" || { t4_bad "④c 克隆失败"; t4_exit; }
C43_MUT_ALWAYS0="$C43_MUT_ALWAYS0_SCRIPTS/nao-fleet.sh"
C43_MUT_ALWAYS0_MOD="$(t4_fleet_file_with "$C43_MUT_ALWAYS0_SCRIPTS" 'live_n')"
awk '{ if ($0 ~ /if \[\[ "\$live_n" != "0" \]\]; then/) { print "      live_n=0  # 变异：复核恒「0 pane」"; print "      if false; then"; next } print }' \
  "$C43_MUT_ALWAYS0_MOD" > "$C43_MUT_ALWAYS0_MOD.new" && mv "$C43_MUT_ALWAYS0_MOD.new" "$C43_MUT_ALWAYS0_MOD"
t4_assert_ge "1" "$(grep -cF -- 'live_n=0  # 变异' "$C43_MUT_ALWAYS0_MOD" || true)" \
  "④c 变异夹具：复核改为恒「0 pane」"

c43_reset || { t4_bad "④c 场景重置失败"; t4_exit; }
SC="$(c43_user_only_ws)" || { t4_bad "④c 无法构造场景"; t4_exit; }
WS="${SC%%$'\t'*}"; USER_PANE="${SC#*$'\t'}"
: > "$CALL_LOG"
BE_FLEET_SCRIPT="$C43_MUT_ALWAYS0" be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_ge "1" "$(c43_close_count)" "④c 复核恒真 ⇒ 必红：workspace close 被发出"
be_pane_alive "$USER_PANE" && t4_bad "④c 恒真复核下用户 pane 仍活（负控未生效）" \
  || t4_ok "④c 恒真复核下用户 pane 被杀（证明判据落在后端原始结果上）"

# ---------------------------------------------------------------- ⑤ 真·空 ws 仍要能关
c43_reset || { t4_bad "⑤ 场景重置失败"; t4_exit; }
SC="$(c43_user_only_ws)" || { t4_bad "⑤ 无法构造场景"; t4_exit; }
WS="${SC%%$'\t'*}"; USER_PANE="${SC#*$'\t'}"
# herdr（真机与替身一致）：关掉最后一个 pane 会连带删掉 ws ⇒ 空 ws 只能直接落在后端状态里
#   （真实场景 = 用户在别处关掉了 pane / 进程退出，ws 条目暂留）⇒ 改替身状态文件造这个态。
c43_make_ws_empty() { # <wsid>
  local f; f="$(be_sessions_dir)/$BE_SESSION/double-state.json"
  F="$f" WS="$1" node -e '
const fs = require("fs");
const p = process.env.F, w = process.env.WS;
const st = JSON.parse(fs.readFileSync(p, "utf8"));
for (const k of Object.keys(st.panes || {})) if (st.panes[k].workspace_id === w) delete st.panes[k];
for (const k of Object.keys(st.tabs || {})) if (st.tabs[k].workspace_id === w) delete st.tabs[k];
fs.writeFileSync(p, JSON.stringify(st));'
}
c43_make_ws_empty "$WS" || { t4_bad "⑤ 夹具：造空 ws 失败"; t4_exit; }
t4_assert_eq "0" "$(c43_panes_in "$WS" | grep -c . || true)" "⑤ 夹具：ws 真的 0 pane（条目仍在）"
t4_assert_eq "$LBL" "$(c43_ws_label_of "$WS")" "⑤ 夹具：空 ws 的 label 仍在（ensure 找得到它）"
: > "$CALL_LOG"
be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_eq "0" "$BE_RC" "⑤ 真·空 ws ⇒ ensure rc=0"
t4_assert_ge "1" "$(c43_close_count)" "⑤ 真·空 ws ⇒ 允许 workspace close（旧行为可回退）"
new_ws="$(be_herdr "$BE_SESSION" pane list 2>/dev/null | _be_json_lines '(r.panes||[]).map(p=>p.workspace_id)' | grep -c . || true)"
t4_assert_ge "1" "$new_ws" "⑤ 重建后仍有可用 pane"
t4_assert_contains "$BE_OUT" "（成功 1 / 跳过 0 / 失败 0）" "⑤ 摘要计成功 1（重建 ws 后放置成功）"

# ---------------------------------------------------------------- ⑥a 判重 / ⑥b 槽位与名字（同族消费点）
c43_reset || { t4_bad "⑥ 场景重置失败"; t4_exit; }
SC="$(c43_user_only_ws)" || { t4_bad "⑥ 无法构造场景"; t4_exit; }
WS="${SC%%$'\t'*}"; USER_PANE="${SC#*$'\t'}"
js="$(be_herdr "$BE_SESSION" pane split "$USER_PANE" --direction down --cwd "$LAB" --no-focus 2>/dev/null)"
ROLE_PANE="$(printf '%s' "$js" | _be_json_lines '[(r.pane||{}).pane_id].filter(Boolean)')"
be_herdr "$BE_SESSION" pane rename "$ROLE_PANE" "rd-fe2" >/dev/null 2>&1
# v3：task 在 sidecar（不是名字）—— 为槽位 2 写入 task=T1，证明判重认元数据
mkdir -p "$LAB/.t4-home/.local/state/nao-fleet/session-meta/${BE_SESSION}__${WS}" 2>/dev/null || true
printf 'task=T1
name=rd-fe2
' > "$LAB/.t4-home/.local/state/nao-fleet/session-meta/${BE_SESSION}__${WS}/$ROLE_PANE" 2>/dev/null || true
t4_assert_eq "rd-fe2" "$(be_pane_label "$ROLE_PANE")" "⑥ 夹具：槽位 2 的派生 pane 就位（task 在 sidecar）"

: > "$CALL_LOG"
n_before="$(c43_panes_in "$WS" | grep -c . || true)"
be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_eq "0" "$BE_RC" "⑥a 判重：ensure rc=0"
t4_assert_contains "$BE_ERR_ANSI" "已在运行" "⑥a 判重：同 (role,task) 已在 ⇒ 判「已在运行」"
t4_assert_eq "$n_before" "$(c43_panes_in "$WS" | grep -c . || true)" "⑥a 判重：未新建重复 pane（label 字段读对）"
t4_assert_eq "0" "$(c43_close_count)" "⑥a 判重：全程未关 ws（用户 pane 存活）"
be_pane_alive "$USER_PANE" && t4_ok "⑥a 用户 pane 仍存活" || t4_bad "⑥a 用户 pane 被杀"

: > "$CALL_LOG"
be_run_fleet "$LAB" ensure --task T2 rd-fe
t4_assert_eq "0" "$BE_RC" "⑥b 槽位：ensure rc=0"
t4_assert_ne "" "$(be_pane_by_name "rd-fe")" "⑥b 槽位/名字：取最小空闲槽位 1 取名 rd-fe（槽位号不承载语义；不复用已占槽位 2）"
t4_assert_eq "0" "$(c43_close_count)" "⑥b 槽位：全程未关 ws"

# ---------------------------------------------------------------- ⑥c 仓归属（`_ensure_ws_panes_in_repo`）
c43_reset || { t4_bad "⑥c 场景重置失败"; t4_exit; }
js="$(be_herdr "$BE_SESSION" workspace create --cwd "$OTHER" --label "$LBL" --no-focus 2>/dev/null)"
FOREIGN_WS="$(printf '%s' "$js" | _be_json_lines '[(r.workspace||{}).workspace_id].filter(Boolean)')"
FOREIGN_PANE="$(c43_panes_in "$FOREIGN_WS" | head -1)"
t4_assert_ne "" "$FOREIGN_PANE" "⑥c 夹具：同名 base label 的「他仓」ws 就位（pane cwd=$OTHER）"
: > "$CALL_LOG"
be_run_fleet "$LAB" ensure --task T1 rd-fe
t4_assert_eq "0" "$BE_RC" "⑥c 仓归属：ensure rc=0"
t4_assert_eq "2" "$(c43_ws_count)" "⑥c 仓归属：让号新建第二个 ws（不塞进他仓的 ws）"
FOREIGN_LABEL="$(be_herdr "$BE_SESSION" workspace list 2>/dev/null | _be_json_lines "(r.workspaces||[]).filter(w=>w.workspace_id==='$FOREIGN_WS').map(w=>w.label)")"
t4_assert_eq "$LBL" "$FOREIGN_LABEL" "⑥c 他仓 ws 仍用 base label（未被改名/未关）"
t4_assert_eq "$FOREIGN_WS" "$(be_herdr "$BE_SESSION" pane list 2>/dev/null | _be_json_lines '(r.panes||[]).map(p=>p.workspace_id)' | sed -n '1p')" "⑥c 他仓 pane 仍在原 ws"
t4_assert_eq "0" "$(c43_close_count)" "⑥c 仓归属：未关任何 ws（护栏 + 归属判据同向）"
new_label="$(be_herdr "$BE_SESSION" workspace list 2>/dev/null | _be_json_lines "(r.workspaces||[]).map(w=>w.label)" | grep -vx -- "$LBL" | head -1)"
t4_assert_eq "${LBL:0:15}2" "$new_label" "⑥c 仓归属：新 ws 取号段 label（${LBL:0:15}2）"

t4_assert_eq "1" "${C43_MAIN_DONE:-0}" "假绿护栏：用例完整跑到 ③ 主场景（防夹具/ordering 早退变成「零断言 PASS」）"

be_teardown >/dev/null 2>&1 || true
t4_exit
