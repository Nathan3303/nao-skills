#!/usr/bin/env bash
# 用例 33 —— herdr 放置键与 scope 解耦（T545 · ADR 2026-11-13-herdr-workspace-scope-key）
#
# 缺陷类（现场复刻 · ADR §二）：把**可选的身份字段** scope 当**必需的放置键** —— 空 scope 时借
#   `HERDR_SESSION` 兜底 ⇒ 多仓并行时别仓会话被塞进「会话名 workspace」（现场恰等于调用方窗口）：
#   `w1 label=nao-skills panes=1→2`，新 pane 落在调用方 workspace 且**零新 workspace**。
#
# 拍板口径（D1=A · D3=scope 优先 · 用户 2026-11-13）：
#   放置键 label = 会话名 parse 出的 scope（**已声明**）否则 `fleet_scope_slug(目标仓)`；**删除**会话名回退。
#   scope 只承担会话名身份（`<core>[@<scope>]`）⇒ 命名契约零改动。
#
# 判据（U1–U5；断言作用域 = 单字段 `workspace.label` / `pane.workspace_id` + 计数，禁「整段文本包含」）：
#   U1 跨仓空 scope 且**会话名 == 调用方 workspace label** ⇒ label=仓 slug、pane 不在调用方 workspace、
#      无**新增** label=会话名 的 workspace（调用方自己那 1 个 = 基线，不算）
#   U2 同仓空 scope（另一角色）⇒ 复用同一 slug workspace（条数不增）
#   U3 worktree 与主仓同键（`git --git-common-dir` 的父目录名）⇒ 两次 ensure 只 1 个 workspace
#   U4 scope 优先两来源：`--scope` 与 `<目标仓>/.agents/fleet-scope` 各 1 条 ⇒ label 分别为 `bk` / `todo`
#   U5 两仓同 core 无 scope ⇒ 第二次 ensure 仍 fail loud（P11 文案不变；放置键解耦不放宽名字撞车判据）
# 负控（N1/N2，真跑）：把放置键改回会话名 / 把 slug 兜底改成空操作 ⇒ U1 判据必红（证明 U1 不是同义反复）
#
# 夹具：`tests/t4/fixtures/herdr-double`（确定性替身）+ 私有 XDG 根 ⇒ 不碰真 herdr / 用户 default。
# 调用方场景 = `be_ensure_scene` 的首个 workspace（label = 会话名）——正是现场「会话名 == 调用方 label」。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
if [ "$BE_NAME" != "herdr" ]; then
  t4_note backend-gate "放置键（workspace label）是 herdr 结构面：tmux 无 workspace 概念（落点由宿主窗口/split-window 决定）；tmux 侧命名契约由用例 28 覆盖"
  t4_exit
fi

FLEET_MAIN="$T4_ROOT/.agents/scripts/nao-fleet.sh"
LAB="$T4_CACHE_DIR/lab33-$$"
mkdir -p "$LAB" "$LAB/repo-b" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab33" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "夹具：调用方 scene 建立失败"; t4_exit; }

# ---------------------------------------------------------------- 判据工具（单字段 + 计数）
ws_json() { be_herdr "$BE_SESSION" workspace list 2>/dev/null; }
pane_json() { be_herdr "$BE_SESSION" pane list 2>/dev/null; }
split_objs() { sed 's/},{/}\n{/g'; }
obj_for() { # <json> <key> <value> → 首个匹配对象（无则空）
  split_objs <<< "$1" | grep -F "\"$2\":\"$3\"" | head -1
}
fld() { sed -nE "s/.*\"$2\":\"([^\"]+)\".*/\\1/p" <<< "${1:-}" | head -1; }
ws_id_by_label() { fld "$(obj_for "$(ws_json)" label "${1:-}")" workspace_id; }
ws_label_count() { split_objs <<< "$(ws_json)" | grep -cF "\"label\":\"${1:-}\"" || true; }
ws_id_of_pane() { fld "$(obj_for "$(pane_json)" pane_id "${1:-}")" workspace_id; }
pane_ws_by_label() { fld "$(obj_for "$(pane_json)" label "${1:-}")" workspace_id; }
# 唯一运行入口 = `be_run_fleet`：它枚举清 `HERDR_*` 再注入**本实验场**的句柄
#   （用例进程自己在真 herdr pane 里跑 ⇒ 直接继承 env 会打到用户真 server，实测该误用会把
#    「pane list 失败」吃成 rc=0 而掩盖判据）。变异副本经 `BE_FLEET_SCRIPT` 换脚本，句柄仍走同一入口。
fleet() { be_run_fleet "$LAB" "$@"; }

CALLER_PANE="$(be_caller_pane)"
CALLER_WS="$(ws_id_of_pane "$CALLER_PANE")"

w33_exit_trap() {
  local rc=$?
  be_teardown >/dev/null 2>&1 || true
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap w33_exit_trap EXIT

# U1 的三条判据合成一把尺子（正控与负控共用；返回 GREEN 或 RED:<原因>）
u1_verdict() { # <slug> <pane-label>
  local slug="$1" pl="$2" ws n pws ns
  ws="$(ws_id_by_label "$slug")"; n="$(ws_label_count "$slug")"
  pws="$(pane_ws_by_label "$pl")"; ns="$(ws_label_count "$BE_SESSION")"
  [[ -n "$ws" && "$n" = "1" ]] || { printf 'RED:无唯一 slug workspace（label=%s 条数=%s）' "$slug" "${n:-0}"; return 0; }
  [[ "$ws" != "$CALLER_WS" ]] || { printf 'RED:目标 workspace 就是调用方 workspace（%s）' "$ws"; return 0; }
  [[ "$pws" = "$ws" ]] || { printf 'RED:pane %s 不在 slug workspace（在 %s）' "$pl" "${pws:-<无>}"; return 0; }
  [[ "$ns" = "1" ]] || { printf 'RED:label=会话名 的 workspace 条数 %s ≠ 1（= 把会话名当放置键）' "$ns"; return 0; }
  printf 'GREEN'
}

# ---------------------------------------------------------------- 前提自证（调用方场景就是现场形态）
t4_assert_eq "$BE_SESSION" "$(fld "$(obj_for "$(ws_json)" workspace_id "$CALLER_WS")" label)" \
  "前提：调用方 workspace 的 label == 会话名（$BE_SESSION）—— 复刻现场「会话名恰等于调用方 label」"

# ---------------------------------------------------------------- U1 跨仓空 scope（核心缺陷面）
fleet ensure "rd-fe@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U1 ensure rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
t4_assert_eq "GREEN" "$(u1_verdict "repo-b" "rd-fe")" \
  "U1 跨仓空 scope：label=仓 slug(repo-b) · pane 不在调用方 workspace · 无新增 label=会话名 的 workspace"
t4_info "U1 实测：workspaces=[$(split_objs <<< "$(ws_json)" | grep -F '"workspace_id"' | while IFS= read -r o; do printf '%s/%s ' "$(fld "$o" workspace_id)" "$(fld "$o" label)"; done)]（id/label）· rd-fe pane 的 workspace=$(pane_ws_by_label rd-fe)"

# ---------------------------------------------------------------- U2 同仓空 scope（复用同键）
fleet ensure "qa@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U2 ensure rc=0"
t4_assert_eq "1" "$(ws_label_count "repo-b")" "U2 同仓空 scope：label=repo-b 的 workspace 仍恰 1 个（复用同键，不分裂）"
t4_assert_eq "$(ws_id_by_label "repo-b")" "$(pane_ws_by_label "qa")" "U2 qa pane 落在同一个 slug workspace"

# ---------------------------------------------------------------- U3 worktree 与主仓同键
if ! command -v git >/dev/null 2>&1; then
  t4_degrade "环境缺少 git ⇒ U3（worktree 同键）未执行"
else
  GITREPO="$LAB/git-repo"; mkdir -p "$GITREPO"
  ( cd "$GITREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t \
      && : > f && git add -A && git commit -qm init ) >/dev/null 2>&1 \
    || t4_bad "U3 夹具：git 仓初始化失败"
  git -C "$GITREPO" worktree add -q "$LAB/wt" -b wtb >/dev/null 2>&1 \
    || t4_bad "U3 夹具：git worktree add 失败"
  fleet ensure "rd-be@$GITREPO"
  t4_assert_eq "0" "$BE_RC" "U3 ensure 主仓 rc=0"
  fleet ensure "arch-designer@$LAB/wt"
  t4_assert_eq "0" "$BE_RC" "U3 ensure worktree rc=0"
  t4_assert_eq "1" "$(ws_label_count "git-repo")" \
    "U3 worktree 同键：label=git-repo 的 workspace 仍恰 1 个（不因 worktree 分裂）"
  t4_assert_eq "$(ws_id_by_label "git-repo")" "$(pane_ws_by_label "arch-designer")" \
    "U3 worktree 的 pane 落在主仓 workspace（--git-common-dir 同键）"
fi

# ---------------------------------------------------------------- U4 scope 优先（两个来源各 1 条）
mkdir -p "$LAB/repo-scope-b/.agents" || t4_bad "U4 夹具：建 repo-scope-b 失败"
printf 'todo\n' > "$LAB/repo-scope-b/.agents/fleet-scope"
fleet ensure --scope bk "uiux-designer@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U4a ensure --scope bk rc=0"
t4_assert_eq "1" "$(ws_label_count "bk")" "U4a --scope 优先：label=bk 的 workspace 恰 1 个"
t4_assert_eq "$(ws_id_by_label "bk")" "$(pane_ws_by_label "uiux-designer@bk")" "U4a pane 落在 --scope 的 workspace（pane label = 会话名 uiux-designer@bk）"
fleet ensure "pm@$LAB/repo-scope-b"
t4_assert_eq "0" "$BE_RC" "U4b ensure（fleet-scope=todo）rc=0"
t4_assert_eq "1" "$(ws_label_count "todo")" "U4b 文件 scope 优先：label=todo 的 workspace 恰 1 个"
t4_assert_eq "$(ws_id_by_label "todo")" "$(pane_ws_by_label "pm@todo")" "U4b pane 落在文件 scope 的 workspace（pane label = 会话名 pm@todo）"

# ---------------------------------------------------------------- U5 两仓同 core 无 scope ⇒ 仍 fail loud
mkdir -p "$LAB/repo-dup-1" "$LAB/repo-dup-2"
fleet ensure "rd-infra@$LAB/repo-dup-1"
t4_assert_eq "0" "$BE_RC" "U5 第一个仓 ensure rc=0（基线）"
fleet ensure "rd-infra@$LAB/repo-dup-2"
t4_assert_ne "0" "$BE_RC" "U5 第二个仓同 core 无 scope ⇒ rc≠0（名字撞车判据不因放置键解耦而放宽）"
t4_assert_contains "$BE_ERR_ANSI" "与在场会话同 core" "U5 点名 P11 冲突文案（与在场会话同 core）"
t4_assert_contains "$BE_ERR_ANSI" "两仓并发" "U5 P11 指路不变（两仓并发必须设 scope）"

# ---------------------------------------------------------------- 负控 N1/N2（真跑：证明 U1 判据不作假）
#   副本 = 独立 lab（.agents 副本 + 变异后的 nao-fleet.sh），仍走**同一** herdr 场（同 server），
#   但目标仓目录名不同（repo-neg1 / repo-neg2）⇒ slug 是新键，判据可分辨。
mutate_copy() { # <dst-dir> <old-literal> <new-literal> → 打印副本 md5（锚点未命中 ⇒ rc≠0）
  local dst="$1" old="$2" new="$3"
  mkdir -p "$dst" || return 1
  cp -r "$T4_ROOT/.agents" "$dst/.agents" || return 1
  MUT_OLD="$old" MUT_NEW="$new" awk '
    BEGIN { n = 0 }
    { i = index($0, ENVIRON["MUT_OLD"])
      if (i > 0) { print substr($0, 1, i - 1) ENVIRON["MUT_NEW"] substr($0, i + length(ENVIRON["MUT_OLD"])); n++ }
      else print }
    END { exit (n ? 0 : 1) }' "$T4_ROOT/.agents/scripts/nao-fleet.sh" > "$dst/.agents/scripts/nao-fleet.sh" || return 1
  md5sum < "$dst/.agents/scripts/nao-fleet.sh" | awk '{print $1}'
}
SLUG_ANCHOR='[[ -n "$label" ]] || label="$(fleet_scope_slug "$repo")"'
MAIN_MD5="$(md5sum < "$FLEET_MAIN" | awk '{print $1}')"

NEG1="$LAB/neg1"; mkdir -p "$NEG1/repo-neg1"
N1_MD5="$(mutate_copy "$NEG1" "$SLUG_ANCHOR" 'label="${HERDR_SESSION:-}"')" || N1_MD5=""
if [ -n "$N1_MD5" ] && [ "$N1_MD5" != "$MAIN_MD5" ]; then
  t4_ok "N1 变异：副本把放置键改回会话名（锚点命中，md5 与主脚本不同）"
  BE_FLEET_SCRIPT="$NEG1/.agents/scripts/nao-fleet.sh"
  fleet ensure --task N1 "rd-fe@$NEG1/repo-neg1"
  N1_RC="$BE_RC"; N1_ERR="$BE_ERR_ANSI"
  unset BE_FLEET_SCRIPT
  N1_VERDICT="$(u1_verdict "repo-neg1" "rd-fe-N1")"
  t4_assert_ne "GREEN" "$N1_VERDICT" "N1 负控：把放置键改回会话名 ⇒ U1 判据必红（实测 $N1_VERDICT）"
  t4_info "N1 实测：$N1_VERDICT · ensure rc=$N1_RC · stderr 首行=$(printf '%s' "$N1_ERR" | head -1)"
else
  t4_bad "N1 变异锚点未命中或副本与主脚本同文（用例锚点须跟随实现）"
fi

NEG2="$LAB/neg2"; mkdir -p "$NEG2/repo-neg2"
N2_MD5="$(mutate_copy "$NEG2" "$SLUG_ANCHOR" ':')" || N2_MD5=""
if [ -n "$N2_MD5" ] && [ "$N2_MD5" != "$MAIN_MD5" ]; then
  t4_ok "N2 变异：副本把 slug 兜底改成空操作（锚点命中，md5 与主脚本不同）"
  BE_FLEET_SCRIPT="$NEG2/.agents/scripts/nao-fleet.sh"
  fleet ensure --task N2 "qa@$NEG2/repo-neg2"
  N2_RC="$BE_RC"; N2_OUT="$BE_OUT_ANSI"; N2_ERR="$BE_ERR_ANSI"
  unset BE_FLEET_SCRIPT   # 绝不让变异副本继续服务后续断言（单点污染会变成恒红/恒绿）
  t4_assert_eq "0" "$(ws_label_count "repo-neg2")" "N2 负控：label 空 ⇒ 不静默落到任何 workspace（repo-neg2 条数 0）"
  t4_assert_contains "$N2_ERR" "slug 计算失败" "N2 负控：fail loud 点名「slug 计算失败」（不静默落）"
  t4_assert_contains "$N2_OUT" "失败 1" "N2 负控：ensure 摘要计失败 1（不是成功）"
  t4_info "N2 实测：ensure rc=$N2_RC · 摘要行=$(printf '%s' "$N2_OUT" | grep -F '成功' | head -1)"
else
  t4_bad "N2 变异锚点未命中或副本与主脚本同文（用例锚点须跟随实现）"
fi

# ---------------------------------------------------------------- 静态面（与用例 28 C3④ 同源，独立复核）
t4_assert_eq "0" "$(awk '/^_term_herdr_spawn\(\)/,/^}/' "$FLEET_MAIN" | grep -c 'HERDR_SESSION' || true)" \
  "静态：_term_herdr_spawn 函数体 0 处取会话名（含文案；白名单为空）"
t4_assert_eq "1" "$(awk '/^_term_herdr_spawn\(\)/,/^}/' "$FLEET_MAIN" | grep -c 'fleet_scope_slug' || true)" \
  "静态：函数体内仓 slug 调用点恰 1 处（O2 关闭判据）"

be_teardown >/dev/null 2>&1 || true
t4_exit
