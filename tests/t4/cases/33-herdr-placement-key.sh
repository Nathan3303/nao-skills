#!/usr/bin/env bash
# 用例 33 —— 舰队身份单一来源（T547 · ADR 2026-11-17-fleet-identity-source）
#
# 缺陷类（现场复刻）：把**可选的身份字段**当**必需的放置键** —— 空值借 `HERDR_SESSION` 兜底 ⇒
#   多仓并行时别仓会话被塞进「会话名 workspace」；或身份键不取默认值 ⇒ 第二仓 `ensure` fail loud。
#
# 拍板口径（T547 · D1/D-1/D-3/D-4）：
#   放置键 label = **入参 fleet**（spawn 不再反解名字）；fleet 默认 = 目标仓 slug，可用 `--fleet`/
#   `<仓>/.agents/fleet-scope` 覆盖；名字**恒带** `@<fleet>`；保留前缀只限 core；默认 tier 超长自动截短。
#
# 判据（U1–U5；断言作用域 = 单字段 `workspace.label` / `pane.workspace_id` + 计数，禁「整段文本包含」）：
#   U1 跨仓默认 tier 且**会话名 == 调用方 workspace label** ⇒ label=仓 slug、pane 不在调用方 workspace、
#      无**新增** label=会话名 的 workspace（调用方自己那 1 个 = 基线，不算）；pane label = rd-fe@<slug>
#   U2 同仓默认 tier（另一角色）⇒ 复用同一 slug workspace（条数不增）；pane label = qa@<slug>
#   U3 worktree 与主仓同键（`git --git-common-dir` 的父目录名）⇒ 两次 ensure 只 1 个 workspace
#   U4 fleet 优先两来源：`--scope`（弃用别名，warn 一条）与 `<目标仓>/.agents/fleet-scope` 各 1 条 ⇒ label 分别为 `bk` / `todo`
#   U5 两仓默认 tier（无配置）⇒ **并存**（AC1 正路径，各自 label = 各自 slug）；撞车负控 = 两仓同 `--fleet dup`
# 负控（N1/N2，真跑）：spawn 忽略入参 label 回退会话名 / resolver 默认 slug 返回空 ⇒ U5/U1 判据必红
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
# 唯一运行入口 = `be_run_fleet`：它按**单源清单**（`tests/t4/lib.sh::T4_HERDR_ENV_VARS`，8 个）清 `HERDR_*`
#   再注入**本实验场**的句柄（用例进程自己在真 herdr pane 里跑 ⇒ 直接继承 env 会打到用户真 server，实测该误用会把
#   「pane list 失败」吃成 rc=0 而掩盖判据）。变异副本经 `BE_FLEET_SCRIPT` 换脚本，句柄仍走同一入口。
#   #130 返修 P3⑤：不是「枚举清」—— 固定 8 个名单靠 golden「只增不减」纪律兜（herdr 新增 `HERDR_*`
#   必须登记进单源，否则不会被清；`cases/06` 的并集 golden 会在有人删变量时红，新增则靠评审纪律 + cases/35
#   的动态枚举旁证）。
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
t4_assert_eq "GREEN" "$(u1_verdict "repo-b" "rd-fe@repo-b")" \
  "U1 跨仓默认 tier：label=仓 slug(repo-b) · pane 不在调用方 workspace · 无新增 label=会话名 的 workspace"
t4_info "U1 实测：workspaces=[$(split_objs <<< "$(ws_json)" | grep -F '"workspace_id"' | while IFS= read -r o; do printf '%s/%s ' "$(fld "$o" workspace_id)" "$(fld "$o" label)"; done)]（id/label）· rd-fe pane 的 workspace=$(pane_ws_by_label 'rd-fe@repo-b')"

# ---------------------------------------------------------------- U2 同仓空 scope（复用同键）
fleet ensure "qa@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U2 ensure rc=0"
t4_assert_eq "1" "$(ws_label_count "repo-b")" "U2 同仓空 scope：label=repo-b 的 workspace 仍恰 1 个（复用同键，不分裂）"
t4_assert_eq "$(ws_id_by_label "repo-b")" "$(pane_ws_by_label "qa@repo-b")" "U2 qa pane 落在同一个 slug workspace"

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
  t4_assert_eq "$(ws_id_by_label "git-repo")" "$(pane_ws_by_label "arch-designer@git-repo")" \
    "U3 worktree 的 pane 落在主仓 workspace（--git-common-dir 同键；pane label = arch-designer@git-repo）"
fi

# ---------------------------------------------------------------- U4 scope 优先（两个来源各 1 条）
mkdir -p "$LAB/repo-scope-b/.agents" || t4_bad "U4 夹具：建 repo-scope-b 失败"
printf 'todo\n' > "$LAB/repo-scope-b/.agents/fleet-scope"
fleet ensure --scope bk "uiux-designer@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "U4a ensure --scope bk rc=0"
t4_assert_eq "1" "$(ws_label_count "bk")" "U4a --scope 优先：label=bk 的 workspace 恰 1 个"
t4_assert_eq "$(ws_id_by_label "bk")" "$(pane_ws_by_label "uiux-designer@bk")" "U4a pane 落在 --scope 的 workspace（pane label = 会话名 uiux-designer@bk）"
t4_assert_eq "1" "$(grep -c '已弃用' <<< "$BE_ERR_ANSI" || true)" "AC9 --scope 弃用 warn 恰一条（等价 --fleet）"
fleet ensure "pm@$LAB/repo-scope-b"
t4_assert_eq "0" "$BE_RC" "U4b ensure（fleet-scope=todo）rc=0"
t4_assert_eq "1" "$(ws_label_count "todo")" "U4b 文件 scope 优先：label=todo 的 workspace 恰 1 个"
t4_assert_eq "$(ws_id_by_label "todo")" "$(pane_ws_by_label "pm@todo")" "U4b pane 落在文件 scope 的 workspace（pane label = 会话名 pm@todo）"

# ---------------------------------------------------------------- D4 体检面：fleet-scope 存在 ⇒ · 信息行（不计 warn/不改 rc）
printf 'todo\n' > "$LAB/.agents/fleet-scope"
be_run_fleet "$LAB" check -v
t4_assert_eq "0" "$BE_RC" "D4 fleet-scope 存在时 check rc=0（信息行不改 rc）"
t4_assert_contains "$BE_OUT_ANSI" "fleet 生效值 = todo" "D4 体检面给出生效 fleet 值"
t4_assert_contains "$BE_OUT_ANSI" "来源：.agents/fleet-scope" "D4 体检面给出来源 tier"
t4_assert_not_contains "$BE_OUT_ANSI" "warn=" "D4 信息行不计入 warn=N"
rm -f "$LAB/.agents/fleet-scope"

# ---------------------------------------------------------------- U5 两仓默认 tier ⇒ 并存（AC1 正路径）
mkdir -p "$LAB/repo-dup-1" "$LAB/repo-dup-2"
fleet ensure "rd-infra@$LAB/repo-dup-1"
t4_assert_eq "0" "$BE_RC" "U5 第一个仓默认 tier ensure rc=0（基线）"
t4_assert_eq "$(ws_id_by_label "repo-dup-1")" "$(pane_ws_by_label "rd-infra@repo-dup-1")" \
  "U5 第一个仓 pane 落在 label=repo-dup-1 的 workspace"
fleet ensure "rd-infra@$LAB/repo-dup-2"
t4_assert_eq "0" "$BE_RC" "U5 第二个仓同 core 默认 tier ⇒ rc=0（不同 fleet 天然不同名，AC1 并存）"
t4_assert_eq "$(ws_id_by_label "repo-dup-2")" "$(pane_ws_by_label "rd-infra@repo-dup-2")" \
  "U5 第二个仓 pane 落在**自己的** slug workspace（不共用）"

# ---------------------------------------------------------------- U5 负控：两仓同 --fleet ⇒ 撞车（fail loud）
mkdir -p "$LAB/repo-same-1" "$LAB/repo-same-2"
fleet ensure --fleet dup "rd-infra@$LAB/repo-same-1"
t4_assert_eq "0" "$BE_RC" "U5 负控第一个仓 --fleet dup rc=0（基线）"
fleet ensure --fleet dup "rd-infra@$LAB/repo-same-2"
t4_assert_ne "0" "$BE_RC" "U5 负控第二个仓同 --fleet dup ⇒ rc≠0（单例边界不因新参数放宽）"
t4_assert_contains "$BE_ERR_ANSI" "与在场会话同 core" "U5 负控点名 P11 冲突文案（与在场会话同 core）"
t4_assert_contains "$BE_ERR_ANSI" "两仓同 --fleet" "U5 负控指路（两仓同 --fleet 才会互相顶掉）"

# ---------------------------------------------------------------- AC3/4/5/7：优先级 · D-1 正向 · 非法/歧义 · 单例
# AC3：`--fleet` > 文件 > 默认 slug（三条各一断言；文件/Slug 已在 U4/U1 覆盖，这里补显式胜出）
PRIO="$LAB/repo-priority"; mkdir -p "$PRIO/.agents"; printf 'todo\n' > "$PRIO/.agents/fleet-scope"
fleet ensure --fleet cli "pm@$PRIO"
t4_assert_eq "0" "$BE_RC" "AC3 --fleet 覆盖文件 ⇒ rc=0"
t4_assert_eq "$(ws_id_by_label "cli")" "$(pane_ws_by_label "pm@cli")" "AC3 --fleet 胜出（label=pane label=pm@cli）"

# AC4 正向（D-1）：目录名 nao-skills（保留前缀）零配置 ⇒ 成功，名字 pm@nao-skills
NAODIR="$LAB/nao-skills"; mkdir -p "$NAODIR"
fleet ensure "pm@$NAODIR"
t4_assert_eq "0" "$BE_RC" "AC4 正向：nao-skills 目录名零配置可用（前缀只限 core）"
t4_assert_eq "$(ws_id_by_label "nao-skills")" "$(pane_ws_by_label "pm@nao-skills")" "AC4 正向：名字 pm@nao-skills，落 label=nao-skills"

# AC4 异常：显式 fleet 非法 ⇒ fail loud + 不建 pane
AC4_BEFORE="$(be_pane_count)"
fleet ensure --fleet 'BAD' "rd-be@$PRIO"
t4_assert_ne "0" "$BE_RC" "AC4 异常：--fleet BAD ⇒ fail loud（rc≠0）"
t4_assert_eq "$AC4_BEFORE" "$(be_pane_count)" "AC4 异常：零 pane 副作用"
t4_assert_contains "$BE_ERR_ANSI" "--fleet 不可用" "AC4 异常：点名 --fleet 不可用"

# AC5：--fleet 与 --scope 同时给 ⇒ 拒绝（歧义）
AC5_BEFORE="$(be_pane_count)"
fleet ensure --fleet x --scope y "rd-be@$PRIO"
t4_assert_ne "0" "$BE_RC" "AC5 --fleet + --scope ⇒ 拒绝（rc≠0）"
t4_assert_contains "$BE_ERR_ANSI" "只能给一个" "AC5 文案说明二者等价、只能给一个"
t4_assert_eq "$AC5_BEFORE" "$(be_pane_count)" "AC5 零 pane 副作用"

# AC7：同仓同 fleet 重复 ensure ⇒ 仍跳过（不因新参数放宽单例）
AC7_BEFORE="$(be_pane_count)"
fleet ensure "qa@$LAB/repo-b"
t4_assert_eq "0" "$BE_RC" "AC7 重复 ensure rc=0"
t4_assert_contains "$BE_ERR_ANSI" "已在运行" "AC7 点名已在运行（不静默起第二个）"
t4_assert_eq "$AC7_BEFORE" "$(be_pane_count)" "AC7 pane 数不变（单例边界未放宽）"

# ---------------------------------------------------------------- AC11 同仓 legacy 裸名 ≡ core@<slug>
# D-3（安全关键）：默认 tier 下旧裸名 `pm` 与 `pm@<该仓 slug>` 视为同一会话 ⇒ 不得起出第二个 PM。
# 先回收其他 fleet 的 pm（全名 close），让本场景只剩同仓 legacy 裸名（AC6/R2 的口径）。
for _pm in pm@todo pm@cli pm@nao-skills; do
  fleet close "$_pm"
  t4_assert_eq "0" "$BE_RC" "AC11 夹具：先回收 $_pm（全名 close）"
done
LEGACY_REPO="$LAB/repo-legacy"; mkdir -p "$LEGACY_REPO"
P_LEG="$(be_new_pane "$LEGACY_REPO")" || t4_bad "AC11 夹具：建 legacy pane 失败"
be_fixture_session "$P_LEG" "pm" "repo-legacy" || t4_bad "AC11 夹具：legacy 裸名 pm 未就绪"
AC11_BEFORE="$(be_pane_count)"
fleet ensure "pm@$LEGACY_REPO"
t4_assert_eq "0" "$BE_RC" "AC11 legacy 裸名在场时 ensure pm rc=0（跳过，不是冲突/失败）"
t4_assert_eq "$AC11_BEFORE" "$(be_pane_count)" "AC11 现场 pane 数与操作前一致（不产生第二个 PM）"
t4_assert_contains "$BE_ERR_ANSI" "legacy 裸名 pm" "AC11 点名既有 legacy 会话（pm）"
t4_assert_contains "$BE_OUT_ANSI" "（成功 0 / 跳过 1 / 失败 0）" "AC11 摘要计跳过 1（不冒充拉起）"

# AC6（R2）：同仓 legacy 裸名在场 / 无 pm@<slug> 时，close pm 必须命中裸名 —— 禁 rc=0 假成功
be_run_fleet "$LEGACY_REPO" close pm
t4_assert_eq "0" "$BE_RC" "AC6 close pm（legacy 裸名）rc=0"
t4_assert_contains "$BE_OUT_ANSI" "已回收 pm" "AC6 close 命中并回收裸名 pm"
t4_assert_not_contains "$BE_OUT_ANSI" "未运行（无需回收）" "AC6 不得打印 rc=0 假成功「未运行」"

# ---------------------------------------------------------------- AC12 名长双态（默认 tier 截短 / 显式 tier fail loud）
CARD32="$(printf 'c%.0s' $(seq 1 32))"                 # 卡 core 32（上限）
LONGDIR="$LAB/$(printf 'd%.0s' $(seq 1 20))"           # 目录 20 位 ⇒ slug 先截 16
TRUNC15="$(printf 'd%.0s' $(seq 1 15))"                # 32 + '@' + 15 = 48
mkdir -p "$LONGDIR/.agents/prompts"
printf -- '---\nrole: %s\n---\n# 32 字符卡（AC12 名长夹具）\n' "$CARD32" > "$LONGDIR/.agents/prompts/$CARD32.md"

AC12_BEFORE="$(be_pane_count)"
fleet ensure --card ".agents/prompts/$CARD32.md@$LONGDIR"
t4_assert_eq "0" "$BE_RC" "AC12 默认 tier：core 32 + 长目录 ⇒ 自动截短后 rc=0"
t4_assert_eq "$((AC12_BEFORE + 1))" "$(be_pane_count)" "AC12 默认 tier：会话正常拉起（+1 pane）"
t4_assert_contains "$BE_OUT_ANSI" "$CARD32@$TRUNC15" "AC12 默认 tier：名字截短到 48（core 32 + '@' + fleet 15）"
t4_assert_eq "1" "$(grep -c 'fleet 值超长' <<< "$BE_OUT_ANSI" || true)"   "AC12 默认 tier：**恰一行**截短提示（非 -v 也可见）"

AC12_EXPL_BEFORE="$(be_pane_count)"
fleet ensure --fleet "$(printf 's%.0s' $(seq 1 16))" --card ".agents/prompts/$CARD32.md@$LONGDIR"
t4_assert_ne "0" "$BE_RC" "AC12 显式 tier：32 + '@' + 16 = 49 ⇒ fail loud（rc≠0）"
t4_assert_eq "$AC12_EXPL_BEFORE" "$(be_pane_count)" "AC12 显式 tier：零副作用（不建 pane）"
t4_assert_contains "$BE_ERR_ANSI" "显式 fleet" "AC12 显式 tier：点明不自动截短"
t4_assert_contains "$BE_ERR_ANSI" "49 字符 > 48" "AC12 显式 tier：回显长度（49 > 48）"

# 三条冻结上限未改（48 / core≤32 / fleet≤16）
t4_assert_eq "1" "$(grep -cF '(( ${#name} <= 48 ))' "$FLEET_MAIN" || true)" "AC12 常量未改：总长上限 48"
t4_assert_eq "1" "$(grep -cF '(( ${#s} <= 16 ))' "$FLEET_MAIN" || true)" "AC12 常量未改：fleet ≤16"
t4_assert_eq "1" "$(grep -cF '(( ${#core} > 32 ))' "$FLEET_MAIN" || true)" "AC12 常量未改：core ≤32（卡）"

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
# N1 变异锚：spawn 的 label 入参（改回从会话名取 ⇒ 放置键回退）
LABEL_ANCHOR='label="${5-}"'
# N2 变异锚：resolver 默认 tier 的仓 slug
SLUG_ANCHOR='slug="$(fleet_scope_slug "$repo")"'
MAIN_MD5="$(md5sum < "$FLEET_MAIN" | awk '{print $1}')"

NEG1="$LAB/neg1"; mkdir -p "$NEG1/repo-neg1"
N1_MD5="$(mutate_copy "$NEG1" "$LABEL_ANCHOR" 'label="$name"')" || N1_MD5=""
if [ -n "$N1_MD5" ] && [ "$N1_MD5" != "$MAIN_MD5" ]; then
  t4_ok "N1 变异：副本忽略入参 label、回退会话名（锚点命中，md5 与主脚本不同）"
  BE_FLEET_SCRIPT="$NEG1/.agents/scripts/nao-fleet.sh"
  fleet ensure --task N1 "rd-fe@$NEG1/repo-neg1"
  N1_RC="$BE_RC"; N1_ERR="$BE_ERR_ANSI"
  unset BE_FLEET_SCRIPT
  N1_VERDICT="$(u1_verdict "repo-neg1" "rd-fe-N1")"
  t4_assert_ne "GREEN" "$N1_VERDICT" "N1 负控：spawn 忽略入参 label 回退会话名 ⇒ U1 判据必红（实测 $N1_VERDICT）"
  t4_info "N1 实测：$N1_VERDICT · ensure rc=$N1_RC · stderr 首行=$(printf '%s' "$N1_ERR" | head -1)"
else
  t4_bad "N1 变异锚点未命中或副本与主脚本同文（用例锚点须跟随实现）"
fi

NEG2="$LAB/neg2"; mkdir -p "$NEG2/repo-neg2"
N2_MD5="$(mutate_copy "$NEG2" "$SLUG_ANCHOR" 'slug=""')" || N2_MD5=""
if [ -n "$N2_MD5" ] && [ "$N2_MD5" != "$MAIN_MD5" ]; then
  t4_ok "N2 变异：resolver 默认 slug 返回空（锚点命中，md5 与主脚本不同）"
  BE_FLEET_SCRIPT="$NEG2/.agents/scripts/nao-fleet.sh"
  fleet ensure --task N2 "qa@$NEG2/repo-neg2"
  N2_RC="$BE_RC"; N2_OUT="$BE_OUT_ANSI"; N2_ERR="$BE_ERR_ANSI"
  unset BE_FLEET_SCRIPT   # 绝不让变异副本继续服务后续断言（单点污染会变成恒红/恒绿）
  t4_assert_eq "0" "$(ws_label_count "repo-neg2")" "N2 负控：默认 slug 空 ⇒ 不静默落到任何 workspace（repo-neg2 条数 0）"
  t4_assert_contains "$N2_ERR" "slug 计算失败" "N2 负控：fail loud 点名「slug 计算失败」（不静默落）"
  t4_assert_ne "0" "$N2_RC" "N2 负控：resolver 失败 ⇒ ensure rc≠0（不建 pane）"
  t4_assert_eq "0" "$(grep -c '已拉起' <<< "$N2_OUT" || true)" "N2 负控：无成功行（不冒充拉起）"
  t4_info "N2 实测：ensure rc=$N2_RC · stderr 首行=$(printf '%s' "$N2_ERR" | head -1)"
else
  t4_bad "N2 变异锚点未命中或副本与主脚本同文（用例锚点须跟随实现）"
fi

# ---------------------------------------------------------------- 静态面（与用例 28 C3④ 同源，独立复核）
t4_assert_eq "0" "$(awk '/^_term_herdr_spawn\(\)/,/^}/' "$FLEET_MAIN" | grep -c 'HERDR_SESSION' || true)" \
  "静态：_term_herdr_spawn 函数体 0 处取会话名（含文案；白名单为空）"
t4_assert_eq "0" "$(awk '/^_term_herdr_spawn\(\)/,/^}/' "$FLEET_MAIN" | grep -c 'fleet_scope_slug' || true)" \
  "静态：函数体内仓 slug 调用点 0 处（D1 收紧：放置键只认入参 label）"

be_teardown >/dev/null 2>&1 || true
t4_exit
