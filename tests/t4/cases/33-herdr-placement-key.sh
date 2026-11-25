#!/usr/bin/env bash
# 用例 33 —— 放置键 = 仓（T554 · ADR 2026-11-20-workspace-as-binding-unit）
#
# 判据：docs/reports/554-lite-spec.md §一.1/§一.5 · §三 S1/S2/S5/S6/S7/S12 · §四「33」迁移清单
# 被测对象：.agents/scripts/nao-fleet.sh（放置键 place_key_label / ensure 相位 1 / manifest @ 解析）
#
# 旧→新（断言口径）：
#   U1 跨仓默认：旧 `label = slug` + 名字 `rd-fe@repo-b` → 新 `label = 仓基键 repo-b` + 名字 `rd-fe`
#   U2 同仓追加：旧 `qa@repo-b` → 新 `qa`（同一 workspace）
#   U3 worktree：名字去 `@`；ws 仍 `git-repo`（同键不分裂）
#   U4 `--scope bk` / `fleet-scope=todo`：旧「label=bk / todo」→ 新「弃用 warn + label=仓基键」
#   U5 两仓同 `--fleet dup`：旧「撞车 fail loud」→ 新「双 warn + 两仓 rc=0（忽略）」
#
# 夹具：`tests/t4/fixtures/herdr-double`（确定性替身）+ 私有 XDG 根 ⇒ 不碰真 herdr / 用户 default。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="herdr"   # T555：唯一后端（be_backend 已删）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
  t4_note backend-gate "tmux 面已删除（T555 / ADR 2026-11-22-herdr-only）：唯一后端 = herdr，本组原为 tmux 专有夹具/语义，随后端整组退役；等价覆盖见 herdr 侧断言"

FLEET_MAIN="$T4_ROOT/.agents/scripts/nao-fleet.sh"
LAB="$T4_CACHE_DIR/lab33-$$"
mkdir -p "$LAB" "$LAB/repo-b" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab33" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "夹具：调用方 scene 建立失败"; t4_exit; }

ws_json() { be_herdr "$BE_SESSION" workspace list 2>/dev/null; }
pane_json() { be_herdr "$BE_SESSION" pane list 2>/dev/null; }
tab_json() { be_herdr "$BE_SESSION" tab list 2>/dev/null; }
split_objs() { sed 's/},{/}\n{/g'; }
obj_for() { split_objs <<< "$1" | grep -F "\"$2\":\"$3\"" | head -1; }
fld() { sed -nE "s/.*\"$2\":\"([^\"]+)\".*/\\1/p" <<< "${1:-}" | head -1; }
ws_id_by_label() { fld "$(obj_for "$(ws_json)" label "${1:-}")" workspace_id; }
ws_label_count() { split_objs <<< "$(ws_json)" | grep -cF "\"label\":\"${1:-}\"" || true; }
ws_id_of_pane() { fld "$(obj_for "$(pane_json)" pane_id "${1:-}")" workspace_id; }
pane_ws_by_label() { fld "$(obj_for "$(pane_json)" label "${1:-}")" workspace_id; }
pane_cwd_by_label() { fld "$(obj_for "$(pane_json)" label "${1:-}")" cwd; }
pane_label_by_cwd() { fld "$(obj_for "$(pane_json)" cwd "$(phys "$1")")" label; }
phys() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
pane_ws_by_cwd() { fld "$(obj_for "$(pane_json)" cwd "$(phys "$1")")" workspace_id; }
tab_label_of_name() { local o t; o="$(obj_for "$(pane_json)" label "$1")"; t="$(fld "$o" tab_id)"; fld "$(obj_for "$(tab_json)" tab_id "$t")" label; }
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

u1_verdict() { # <slug> <pane-label>
  local slug="$1" pl="$2" ws n pws ns
  ws="$(ws_id_by_label "$slug")"; n="$(ws_label_count "$slug")"
  pws="$(pane_ws_by_label "$pl")"; ns="$(ws_label_count "$BE_SESSION")"
  [[ -n "$ws" && "$n" = "1" ]] || { printf 'RED:无唯一仓基键 workspace（label=%s 条数=%s）' "$slug" "${n:-0}"; return 0; }
  [[ "$ws" != "$CALLER_WS" ]] || { printf 'RED:目标 workspace 就是调用方 workspace（%s）' "$ws"; return 0; }
  [[ "$pws" = "$ws" ]] || { printf 'RED:pane %s 不在仓基键 workspace（在 %s）' "$pl" "${pws:-<无>}"; return 0; }
  [[ "$ns" = "1" ]] || { printf 'RED:label=会话名 的 workspace 条数 %s ≠ 1' "$ns"; return 0; }
  printf 'GREEN'
}

# ---------------------------------------------------------------- U1 跨仓默认（放置键 = 仓）
fleet ensure "rd-fe@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U1 ensure rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
t4_assert_eq "GREEN" "$(u1_verdict "repo-b" "rd-fe")" \
  "U1 跨仓：ws label=仓基键(repo-b) · pane 名=rd-fe（不含 @）· 不在调用方 ws · 不新增会话名 workspace"
t4_assert_eq "rd-fe" "$(tab_label_of_name "rd-fe")" "U1 tab label = 名字（组前缀退役）"

# ---------------------------------------------------------------- U2 同仓追加（复用同键）
fleet ensure "qa@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U2 ensure rc=0"
t4_assert_eq "1" "$(ws_label_count "repo-b")" "U2 同仓追加：label=repo-b 的 workspace 仍恰 1 个"
t4_assert_eq "$(ws_id_by_label "repo-b")" "$(pane_ws_by_label "qa")" "U2 qa 落在同一个仓 workspace"
t4_assert_eq "qa" "$(tab_label_of_name "qa")" "U2 tab label = qa"

# ---------------------------------------------------------------- U3 worktree 与主仓同键
if ! command -v git >/dev/null 2>&1; then
  t4_degrade "环境缺少 git ⇒ U3（worktree 同键）未执行"
else
  GITREPO="$LAB/git-repo"; mkdir -p "$GITREPO"
  ( cd "$GITREPO" && git init -q . && git config user.email t@t.invalid && git config user.name t \
      && : > f && git add -A && git commit -qm init ) >/dev/null 2>&1 || t4_bad "U3 夹具：git 仓初始化失败"
  git -C "$GITREPO" worktree add -q "$LAB/wt" -b wtb >/dev/null 2>&1 || t4_bad "U3 夹具：worktree add 失败"
  fleet ensure "rd-be@$GITREPO"; t4_assert_eq "0" "$BE_RC" "U3 ensure 主仓 rc=0"
  fleet ensure "arch-designer@$LAB/wt"; t4_assert_eq "0" "$BE_RC" "U3 ensure worktree rc=0"
  t4_assert_eq "1" "$(ws_label_count "git-repo")" "U3 worktree 同键：label=git-repo 仍恰 1 个"
  t4_assert_eq "$(ws_id_by_label "git-repo")" "$(pane_ws_by_cwd "$LAB/wt")" "U3 worktree pane 落主仓 workspace（同 git common-dir）"
fi

# ---------------------------------------------------------------- U4 弃用来源（--scope / fleet-scope）
mkdir -p "$LAB/repo-scope-b/.agents" || t4_bad "U4 夹具失败"
printf 'todo\n' > "$LAB/repo-scope-b/.agents/fleet-scope"
fleet ensure --scope bk "uiux-designer@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U4a --scope bk rc=0（弃用忽略）"
t4_assert_eq "1" "$(grep -c '弃用：--scope' <<< "$BE_ERR_ANSI" || true)" "U4a --scope 恰一行弃用 warn"
t4_assert_eq "1" "$(ws_label_count "repo-b")" "U4a 放置仍 = 仓基键（label=repo-b 恰 1 个；不建 bk）"
t4_assert_eq "0" "$(ws_label_count "bk")" "U4a 不按 --scope 放置（label=bk 条数 0）"
t4_assert_eq "$(ws_id_by_label "repo-b")" "$(pane_ws_by_label "uiux-designer")" "U4a pane 落仓基键 ws"
fleet ensure "pm@$LAB/repo-scope-b"
t4_assert_eq "0" "$BE_RC" "U4b fleet-scope=todo rc=0（忽略）"
t4_assert_eq "1" "$(grep -c '弃用：.agents/fleet-scope' <<< "$BE_ERR_ANSI" || true)" "U4b fleet-scope 恰一行弃用 warn"
t4_assert_eq "1" "$(ws_label_count "repo-scope-b")" "U4b 放置 = 仓基键（label=repo-scope-b）"
t4_assert_eq "0" "$(ws_label_count "todo")" "U4b 不按文件值放置（label=todo 条数 0）"

# ---------------------------------------------------------------- D4 体检行
printf 'todo\n' > "$LAB/.agents/fleet-scope"
be_run_fleet "$LAB" check -v
t4_assert_eq "0" "$BE_RC" "D4 fleet-scope 存在时 check rc=0"
t4_assert_contains "$BE_OUT_ANSI" "弃用：.agents/fleet-scope 已忽略" "D4 体检面给弃用行"
t4_assert_not_contains "$BE_OUT_ANSI" "fleet 生效值" "D4 旧「生效值」行退役"
rm -f "$LAB/.agents/fleet-scope"

# ---------------------------------------------------------------- U5 两仓并存 / 同 --fleet（忽略）
mkdir -p "$LAB/repo-dup-1" "$LAB/repo-dup-2"
fleet ensure "rd-infra@$LAB/repo-dup-1"; t4_assert_eq "0" "$BE_RC" "U5 第一仓 rc=0"
t4_assert_eq "$(ws_id_by_label "repo-dup-1")" "$(pane_ws_by_cwd "$LAB/repo-dup-1")" "U5 第一仓 pane 落自己仓"
fleet ensure "rd-infra@$LAB/repo-dup-2"; t4_assert_eq "0" "$BE_RC" "U5 第二仓 rc=0"
t4_assert_eq "$(ws_id_by_label "repo-dup-2")" "$(pane_ws_by_cwd "$LAB/repo-dup-2")" "U5 第二仓 pane 落自己仓（跨仓同名合法）"
mkdir -p "$LAB/repo-same-1" "$LAB/repo-same-2"
fleet ensure --fleet dup "qa@$LAB/repo-same-1"; t4_assert_eq "0" "$BE_RC" "U5 负控：第一仓 --fleet dup rc=0（忽略）"
fleet ensure --fleet dup "rd-fe@$LAB/repo-same-2"; t4_assert_eq "0" "$BE_RC" "U5 负控：第二仓 --fleet dup 也 rc=0（不再撞车）"
t4_assert_eq "$(ws_id_by_label "repo-same-2")" "$(pane_ws_by_cwd "$LAB/repo-same-2")" "U5 负控：第二仓仍落自己仓基键"

# ---------------------------------------------------------------- AC3/AC4/AC5/AC7
PRIO="$LAB/repo-priority"; mkdir -p "$PRIO/.agents"; printf 'todo\n' > "$PRIO/.agents/fleet-scope"
fleet ensure --fleet cli "pm@$PRIO"
t4_assert_eq "0" "$BE_RC" "AC3 --fleet + 文件：rc=0（两来源都忽略）"
t4_assert_eq "1" "$(grep -c '弃用：--fleet' <<< "$BE_ERR_ANSI" || true)" "AC3 --fleet 弃用 warn 恰一条"
t4_assert_eq "1" "$(ws_label_count "repo-priority")" "AC3 放置 = 仓基键（label=repo-priority）"
t4_assert_eq "0" "$(ws_label_count "cli")" "AC3 不按 --fleet 放置"

NAODIR="$LAB/nao-skills"; mkdir -p "$NAODIR"
fleet ensure "pm@$NAODIR"
t4_assert_eq "0" "$BE_RC" "AC4 正向：nao-skills 目录零配置可用"
t4_assert_eq "1" "$(ws_label_count "nao-skills")" "AC4 正向：label=nao-skills"

AC4_BEFORE="$(be_pane_count)"; fleet ensure --fleet 'BAD' "rd-be@$PRIO"
t4_assert_eq "0" "$BE_RC" "AC4 异常：--fleet BAD 本版忽略（rc=0）"
t4_assert_eq "$((AC4_BEFORE + 1))" "$(be_pane_count)" "AC4 异常：忽略后正常拉起（+1 pane）"
t4_assert_eq "1" "$(grep -c '弃用：--fleet' <<< "$BE_ERR_ANSI" || true)" "AC4 异常：弃用 warn 恰一条"

AC5_BEFORE="$(be_pane_count)"; fleet ensure --fleet x --scope y "qa@$NAODIR"
t4_assert_eq "0" "$BE_RC" "AC5 --fleet + --scope：rc=0（双弃用）"
t4_assert_eq "2" "$(grep -c '弃用：' <<< "$BE_ERR_ANSI" || true)" "AC5 双 warn（各恰一行）"
t4_assert_eq "$((AC5_BEFORE + 1))" "$(be_pane_count)" "AC5 正常拉起（+1 pane）"

# S3：同角色重复 ensure ⇒ 递增槽位（pm → pm2）
AC7_BEFORE="$(be_pane_count)"
fleet ensure "pm@$NAODIR"
t4_assert_eq "0" "$BE_RC" "AC7 重复 ensure pm rc=0"
t4_assert_eq "$((AC7_BEFORE + 1))" "$(be_pane_count)" "AC7 重复 ensure ⇒ 新槽位（+1 pane，S3）"
t4_assert_contains "$BE_OUT_ANSI" "已拉起 pm2 " "AC7 新会话名 = pm2"

# ---------------------------------------------------------------- AC11/AC12（v2 名长）
LEGACY_REPO="$LAB/repo-legacy"; mkdir -p "$LEGACY_REPO"
fleet ensure "pm@$LEGACY_REPO"
t4_assert_eq "0" "$BE_RC" "AC11 ensure pm rc=0"
be_run_fleet "$LEGACY_REPO" close pm
t4_assert_eq "0" "$BE_RC" "AC11 close pm rc=0（v2 裸名，锚=本仓）"
t4_assert_contains "$BE_OUT_ANSI" "已回收 pm" "AC11 close 命中 pm"

CARD32="$(printf 'c%.0s' $(seq 1 32))"
LONGDIR="$LAB/cardrepo"; mkdir -p "$LONGDIR/.agents/prompts"
printf -- '---\nrole: %s\n---\n# 32 字符卡（AC12 名长夹具）\n' "$CARD32" > "$LONGDIR/.agents/prompts/$CARD32.md"
AC12_BEFORE="$(be_pane_count)"
fleet ensure --card ".agents/prompts/$CARD32.md@$LONGDIR"
t4_assert_eq "0" "$BE_RC" "AC12 默认 tier：32 字卡 role 直接可用（≤48）"
t4_assert_eq "$((AC12_BEFORE + 1))" "$(be_pane_count)" "AC12 默认 tier：会话拉起（+1 pane）"
t4_assert_eq "1" "$(ws_label_count "cardrepo")" "AC12 放置 = 仓基键（cardrepo）"

I_TASK="$(printf 'T%.0s' $(seq 1 18))"
AC12E_BEFORE="$(be_pane_count)"
fleet ensure --task "$I_TASK" --card ".agents/prompts/$CARD32.md@$LONGDIR"
t4_assert_ne "0" "$BE_RC" "AC12 显式 tier：32 字 role + (T×18) ⇒ name>48 fail loud"
t4_assert_contains "$BE_ERR_ANSI" "48" "AC12 显式 tier：点名总长预算（48）"
t4_assert_eq "$AC12E_BEFORE" "$(be_pane_count)" "AC12 显式 tier：零 pane"

# ---------------------------------------------------------------- 负控 N1/N2（真跑）
# T567-A：变异落在**所有含该锚的模块**（实现不在入口；同锚可能在两个后端模块里各有一份）
#   生效判据 = 副本 scripts 文件集的整集 md5 与真件不同（单文件 md5 会漏「改了另一个模块」）。
MAIN_DIR_MD5="$(t4_fleet_md5 "$T4_ROOT/.agents/scripts")"
mutate_copy() { # <dst-dir> <old-literal> <new-literal> → 打印「改动文件数」
  local dst="$1" old="$2" new="$3" f n=0
  mkdir -p "$dst" || return 1
  cp -r "$T4_ROOT/.agents" "$dst/.agents" || return 1
  while IFS= read -r f; do
    grep -qF -- "$old" "$f" || continue
    MUT_OLD="$old" MUT_NEW="$new" awk '
      BEGIN { n = 0 }
      { i = index($0, ENVIRON["MUT_OLD"])
        if (i > 0) { print substr($0, 1, i - 1) ENVIRON["MUT_NEW"] substr($0, i + length(ENVIRON["MUT_OLD"])); n++ }
        else print }
      END { exit (n ? 0 : 1) }' "$f" > "$f.new" || return 1
    mv "$f.new" "$f" || return 1
    n=$((n + 1))
  done < <(t4_fleet_files "$dst/.agents/scripts")
  printf '%s\n' "$n"
}
LABEL_ANCHOR='label="${5-}"'

NEG1="$LAB/neg1"; mkdir -p "$NEG1/repo-neg1"
N1_N="$(mutate_copy "$NEG1" "$LABEL_ANCHOR" 'label="$name"')" || N1_N=0
N1_MD5="$(t4_fleet_md5 "$NEG1/.agents/scripts")"
if [ "${N1_N:-0}" -ge 1 ] && [ "$N1_MD5" != "$MAIN_DIR_MD5" ]; then
  t4_ok "N1 变异：副本忽略入参 label、回退会话名"
  BE_FLEET_SCRIPT="$NEG1/.agents/scripts/nao-fleet.sh"
  fleet ensure --task N1 "rd-fe@$NEG1/repo-neg1"
  N1_VERDICT="$(u1_verdict "repo-neg1" "rd-fe")"
  unset BE_FLEET_SCRIPT
  t4_assert_ne "GREEN" "$N1_VERDICT" "N1 负控：label 回退名字 ⇒ 必红（$N1_VERDICT）"
else
  t4_bad "N1 变异锚点未命中或副本与主脚本同文"
fi

NEG2="$LAB/neg2"; mkdir -p "$NEG2/repo-neg2"
# 变异 = 把归一结果清空（`slug` 停在空 ⇒ 函数末尾回落 repo；改为在中途返回空 ⇒ 调用方 fail loud）
N2_N="$(mutate_copy "$NEG2" '[[ -n "$slug" ]] || slug="repo"' 'slug=""')" || N2_N=0
N2_MD5="$(t4_fleet_md5 "$NEG2/.agents/scripts")"
if [ "${N2_N:-0}" -ge 1 ] && [ "$N2_MD5" != "$MAIN_DIR_MD5" ]; then
  t4_ok "N2 变异：副本放置键返回空"
  BE_FLEET_SCRIPT="$NEG2/.agents/scripts/nao-fleet.sh"
  fleet ensure --task N2 "qa@$NEG2/repo-neg2"
  N2_RC="$BE_RC"; N2_ERR="$BE_ERR_ANSI"
  unset BE_FLEET_SCRIPT
  t4_assert_eq "0" "$(ws_label_count "repo-neg2")" "N2 负控：放置键空 ⇒ 不落任何 workspace"
  t4_assert_contains "$N2_ERR" "放置键计算失败" "N2 负控：fail loud 点名放置键计算失败"
  t4_assert_ne "0" "$N2_RC" "N2 负控：rc≠0（不建 pane）"
else
  t4_bad "N2 变异锚点未命中或副本与主脚本同文"
fi

# ---------------------------------------------------------------- AC13：pane cwd = 目标仓物理路径
AC13_SERVER="$LAB/server-dir"; mkdir -p "$AC13_SERVER"
AC13_REL="$LAB/repo-rel"; mkdir -p "$AC13_REL"; cp -r "$T4_ROOT/.agents" "$AC13_REL/.agents" || t4_bad "AC13 夹具失败"
AC13_PHYS="$(cd "$AC13_REL" && pwd -P)"
export HERDR_DOUBLE_SERVER_CWD="$AC13_SERVER"
AC13_BEFORE="$(be_pane_count)"
be_run_fleet "$AC13_REL" ensure rd-fe
t4_assert_eq "0" "$BE_RC" "AC13 相对仓 ensure rc=0"
t4_assert_eq "$((AC13_BEFORE + 1))" "$(be_pane_count)" "AC13 会话拉起（+1 pane）"
t4_assert_eq "rd-fe" "$(pane_label_by_cwd "$AC13_PHYS")" "AC13 pane 名 = rd-fe（按 cwd 定位，不与跨仓同名 pane 混淆）"
t4_assert_eq "$(ws_id_by_label "repo-rel")" "$(pane_ws_by_cwd "$AC13_PHYS")" "AC13 pane cwd = 目标仓物理绝对路径"
AC13_CNT="$(be_pane_count)"
be_run_fleet "$AC13_REL" ensure rd-fe
t4_assert_eq "0" "$BE_RC" "AC13 重复 ensure rc=0（新槽位）"
t4_assert_eq "$((AC13_CNT + 1))" "$(be_pane_count)" "AC13 重复 ensure 走槽位递增（+1 pane）"
unset HERDR_DOUBLE_SERVER_CWD

# ---------------------------------------------------------------- 静态面
t4_assert_eq "0" "$(awk '/^_term_herdr_spawn\(\)/,/^}/' "$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_herdr_spawn)" | grep -c 'HERDR_SESSION' || true)" \
  "静态：_term_herdr_spawn 函数体 0 处取会话名"
t4_assert_eq "0" "$(awk '/^_term_herdr_spawn\(\)/,/^}/' "$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_herdr_spawn)" | grep -c 'place_key_label' || true)" \
  "静态：函数体内仓基键调用点 0 处（放置键只认入参 label）"

be_teardown >/dev/null 2>&1 || true
t4_exit
