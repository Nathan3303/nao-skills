#!/usr/bin/env bash
# 用例 19 —— 派生会话归属三态常态回归 + 单行谓词双向变异（T535 · Issue #58）
#
# PRD：docs/prds/2026-10-31-attribution-regression.md（§三 范围 1–2 · §五 BR1–BR6 · §七 AC1/AC2）
# ADR：docs/adr/2026-10-31-fleet-status-repo-attribution.md（判据已定稿，本用例不改判定逻辑，只固化护栏）
# 被测对象：.agents/scripts/nao-fleet.sh 的 `cmd_status` 归属三态
#   · `repo_contains_path <root> <cwd>` 单行谓词（组件级前缀）
#   · `session_repo_verdict`：pane cwd（权威）> 名册 cwd；local / other / unknown（fail-closed）
#
# 断言映射（PRD AC1/AC2）：
#   ① 本仓派生会话 ⇒ 行走 `·`、tag 含 `! 残留`、行含可执行 `close --task T9001 rd-infra`
#   ② 他仓派生会话（pane cwd = 仓外目录 + 名册 cwd 同）⇒ 行走 `~`、含「他仓」、**整行不含 `close --task`**
#   ③ 不可判定会话（pane/名册均无 cwd）⇒ 行走 `?`、含「归属不可判定」、**整行不含 `close --task`**
#   ④ 单仓场景（仅本仓会话）⇒ 零 `~` / `?` 行
#   M 双向变异（BR1/BR2）：`repo_contains_path` 恒真 / 恒假各跑一遍本用例（临时副本上的子进程）⇒ 必须 FAIL 且点名；
#     真仓库零改动（脚本 md5 前后一致 + `git status` 前后一致）；还原（原脚本）后复绿
#
# M20261101（PRD docs/prds/2026-11-01-status-pane-cwd-key.md · AC1–AC5）追加：
#   ⑤ pane-only（名册不可用：agent-dir 无 tsx）⇒ 本仓 pane 判 `·` + 可执行 close（AC1）/ 他仓 pane 仍 `~`（AC2）
#   ⑥ 两路 cwd 皆无 ⇒ 仍 `?（归属不可判定）` 且不给命令（AC4 · fail-closed 未退化）
#   ⑦ 名册正常路径：新版输出与**固化 fixture 基线**逐字等价（AC5① · Issue #78：不再 `git show main:`）
#   ⑧ 冲突：名册本仓 cwd vs pane 他仓 cwd ⇒ pane 优先（AC3）
#   ⑨ 键口径变异负控：把 `pane_cwds` 建键改回 pane_id（复原缺陷）⇒ AC1 断言必须点名 FAIL（AC5②）
#
# 夹具纪律（BR5/NFR）：
#   · 夹具根（$T4_CACHE_DIR/lab19-*）**不得落在任何 git 仓内** —— 否则 `repo_anchor_roots` 的 toplevel 锚
#     会把「他仓」目录拉回本仓，② 假绿（T534 arch 已警示）；开跑前硬断言。
#   · 真 tmux **隔离 socket**（≠ 生产默认候选）+ `env -u TMUX -u TMUX_PANE` + 收尾走机制 `cleanup -S`。
#   · 名册走假探针（只读 env，绝不接触真实 pi-intercom）；缺 tsx/node ⇒ 名册镜像降级，pane/会话名路径照跑。
#   · 变异只在 `$T4_CACHE_DIR` 的**副本**上做：不写仓库工作区、不碰真脚本。
#   · 零网络、确定性：不依赖真实他仓会话，连跑两次逐字一致。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

BASH_BIN="$(command -v bash)"
REAL_PATH="$PATH"
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
SELF="${BASH_SOURCE[0]}"
SUBJECT="${T519_SUBJECT:-$T4_ROOT/.agents/scripts/nao-fleet.sh}"
MUTATION_CHILD="${T519_MUTATION_CHILD:-0}"

# ---- 能力门（B4：后端无关）----
# tmux 后端需真隔离 socket；herdr 后端用 `tests/t4/fixtures/herdr-double`（确定性替身，见其文件头），
# 不依赖真 herdr/真 pi ⇒ 两种后端都零真会话、零网络。
source "$T4_ROOT/tests/t4/lib-backend.sh"
BE_NAME="herdr"   # T555：唯一后端（be_backend 已删）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH

# ---- 夹具路径（后端场由 be_init 单点决定：tmux 隔离 socket / herdr 私有根）----
LAB="$T4_CACHE_DIR/lab19-$$"
OTHER="$T4_CACHE_DIR/otherrepo19-$$"

# BR5：夹具根不得落在任何 git 仓内（否则 toplevel 锚把「他仓」拉回本仓 ⇒ ② 假绿）
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 归属夹具会被 toplevel 锚误判；请把 TMPDIR 指到仓外（BR5）"
  t4_exit
fi
t4_ok "BR5 夹具根不在任何 git 仓内（他仓场景不会被 toplevel 锚拉回本仓）"

# ---- 名册探针能力门（tsx）；缺 ⇒ 名册镜像断言降级，pane 路径照跑 ----
TSX_OK=0
if [ -f "$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then
  TSX_OK=1
fi

# ---- 收尾：EXIT trap 链（先拆后端场，再复刻 lib 缓存清理语义；BR5 保真退出码）----
t519_teardown() {
  [ -n "${LAB:-}" ] && [ -d "$LAB" ] || return 0
  be_teardown >/dev/null 2>&1 || true
  return 0
}
t519_exit_trap() {
  local rc=$?
  t519_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t519_exit_trap EXIT

# ---- 夹具构造 ----
mkdir -p "$LAB" "$OTHER"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
cp "$SUBJECT" "$LAB/.agents/scripts/nao-fleet.sh" || { t4_bad "夹具写入被测脚本失败（$SUBJECT）"; t4_exit; }
# 名册假探针（只读 env；绝不接触真实 pi-intercom 名册/broker）；pretty-print 逐字段一行
cat > "$LAB/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS

# tasks-state 夹具：T9001 已归档（⇒ 本仓行 tag = `! 残留` + 可执行 close）；T9002/T9003 无记录
TASKS_FIX="$LAB/tasks-state-fixture.md"
cat > "$TASKS_FIX" <<'MD'
# T4 case19 tasks-state 夹具（只读）

## 已归档

| 任务 | 状态 |
| :-- | :-- |
| T9001 | v0.1 |
MD

LAB_BASE="$(basename "$LAB")"
OTHER_BASE="$(basename "$OTHER")"
LOCAL_NAME="rd-infra-T9001"
OTHER_NAME="qa-T9002"
UNK_NAME="rd-infra-T9003"

# ---- 调用 / 观察封装 ----
RC=0; OUT=""
# 后端句柄（TMUX/TMUX_PANE 或 HERDR_*/XDG_CONFIG_HOME）由 be_run_fleet 单点注入；
#   本用例只补业务 env（机制包根 / tasks-state / 名册镜像 / agent-dir）。
export NAO_SKILLS="$LAB" NAO_TASKS_STATE="$TASKS_FIX"
run_status() {  # [roster-json] [agent-dir] [被测脚本]
  local roster="${1:-"[]"}" agent="${2:-$PI_AGENT_DIR}" script="${3:-$LAB/.agents/scripts/nao-fleet.sh}"
  export PI_CODING_AGENT_DIR="$agent" NAO_QA_FAKE_ROSTER="$roster"
  BE_FLEET_SCRIPT="$script" be_run_fleet "$LAB" status
  RC=$BE_RC; OUT=$BE_OUT
}
mk_session() { printf '{"name":"%s","cwd":"%s","status":"%s"}' "$1" "$2" "${3:-idle}"; }
roster() { local s="[" e; for e in "$@"; do s="$s$e,"; done; printf '%s' "${s%,}]"; }
start_pane() {  # <cwd> <会话名> [仓标签]；echo pane_id（建 pane + 写身份，后端无关）
  local dir="$1" name="$2" repo="${3:-$(basename "$1")}" p
  p="$(be_new_pane "$dir")" || return 9
  [ -n "$p" ] || return 9
  be_fixture_session "$p" "$name" "$repo" || return 9
  printf '%s' "$p"
}
line_of() {  # <会话名> ⇒ 该会话在 status 派生区的整行（空 = 未列出）
  printf '%s\n' "$OUT" | grep -F -m1 -e "  · $1" -e "  ~ $1" -e "  ? $1" || true
}

# ---- 夹具：先只建本仓 pane（cwd = LAB）⇒ 单仓场景；再补他仓 pane 与不可判定会话 ----
# 场（server/session 根）由 be_ensure_scene 起；后端差异只在 lib-backend 内。
be_init "$LAB" "lab" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }
P_LOCAL="$(start_pane "$LAB" "$LOCAL_NAME" "$LAB_BASE")"
t4_assert_ne "" "$P_LOCAL" "夹具：本仓派生 pane 建立且身份就绪（$LOCAL_NAME @ $LAB_BASE；后端=$BE_NAME）"

R_LOCAL="$(roster "$(mk_session "$LOCAL_NAME" "$LAB")")"
R_MULTI="[]"

# ============================================================ ④ + ① 单仓场景
run_status "$R_LOCAL"
t4_assert_eq "0" "$RC" "④ 单仓场景 status rc=0"
t4_assert_eq "0" "$(printf '%s\n' "$OUT" | grep -cE '^  [~?] ' || true)" \
  "④ 单仓场景零 ~/? 行（仅本仓会话时不产生他仓/不可判定行）"
L_LOCAL="$(line_of "$LOCAL_NAME")"
t4_assert_match "$L_LOCAL" "^  · $LOCAL_NAME( |\$)" "① 本仓会话行走 ·（不被判他仓）"
t4_assert_contains "$L_LOCAL" "! 残留" "① 本仓会话 tag 走 ! 分支（归档态）"
t4_assert_contains "$L_LOCAL" "close --task T9001 rd-infra" "① 本仓会话行含可执行 close --task <编号> <别名>"

# ---- 夹具：补他仓 pane（cwd = 仓外目录）+ 不可判定会话 ----
P_OTHER="$(start_pane "$OTHER" "$OTHER_NAME" "$OTHER_BASE")"
t4_assert_ne "" "$P_OTHER" "夹具：他仓派生 pane 建立且身份就绪（pane cwd = 仓外目录 $OTHER_BASE）"
# ③ 不可判定归属（两路 cwd 皆无）：**tmux 专有**夹具 —— legacy `nao-*` detached 会话（无标题契约
#   ⇒ 无 pane cwd）+ 名册无 cwd。herdr 侧该态**结构上不可达**：身份 = pane.label，归属 = pane.cwd，
#   每个在线 pane 必有 cwd（本仓/他仓两态穷尽）⇒ 该组按后端门控，绝不伪造 third state。
  P_UNK=""
  t4_ok "夹具：herdr 侧不建「不可判定归属」pane（该态结构上不可达，见上）"

if [ "$TSX_OK" = "1" ]; then
  # ② 名册 cwd 与 pane 同为他仓目录；③ 名册条目在但 cwd 为空（pane/名册均无 cwd ⇒ unknown）
  R_MULTI="$(roster "$(mk_session "$LOCAL_NAME" "$LAB")" \
                    "$(mk_session "$OTHER_NAME" "$OTHER")" \
                    "$(mk_session "$UNK_NAME" "")")"
  t4_assert_contains "$R_MULTI" "\"cwd\":\"$OTHER\"" "② 夹具：名册 cwd 与 pane 同为他仓目录"
  t4_assert_contains "$R_MULTI" '"cwd":""' "③ 夹具：名册条目存在但无 cwd"
else
  t4_degrade "缺 tsx/node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ ② 名册 cwd 镜像 / ③ 名册无 cwd 夹具降级（pane/会话名路径照跑）"
fi

# ============================================================ ② + ③ 混合场景（本仓 + 他仓 + 不可判定）
run_status "$R_MULTI"
t4_assert_eq "0" "$RC" "②③ 混合场景 status rc=0"
L_LOCAL2="$(line_of "$LOCAL_NAME")"
t4_assert_contains "$L_LOCAL2" "close --task T9001 rd-infra" "① 混合场景本仓行仍含可执行 close --task（不被他仓会话带偏）"
L_OTHER="$(line_of "$OTHER_NAME")"
t4_assert_match "$L_OTHER" "^  ~ $OTHER_NAME" "② 他仓会话行走 ~"
t4_assert_contains "$L_OTHER" "他仓" "② 他仓会话行含「他仓」"
t4_assert_contains "$L_OTHER" "$OTHER_BASE" "② 他仓会话行点名他仓仓名（$OTHER_BASE）"
t4_assert_not_contains "$L_OTHER" "close --task" "② 他仓会话整行不含可执行 close --task"
  # herdr：归属只有本仓/他仓两态 ⇒ 混合场景恰 1 条 ~ 行、零 ? 行
  t4_assert_eq "1" "$(printf '%s\n' "$OUT" | grep -cE '^  ~ ' || true)" \
    "② 混合场景恰有 1 条 ~ 行（他仓；herdr 无第三态）"
  t4_assert_eq "0" "$(printf '%s\n' "$OUT" | grep -cE '^  \? ' || true)" \
    "③ herdr 侧零 ? 行（归属两态穷尽，不伪造第三态）"
OUT_MIXED="$OUT"   # AC5① 基线对照（此时夹具仅 3 个 pane，旧版/新版应逐字一致）

# ============================================================ AC1/AC2/AC4 pane-only（名册不可用）
# 名册不可用 = PI_CODING_AGENT_DIR 指向**无 tsx** 的目录 ⇒ `intercom_list_json` 首步即失败
#   （≡ pi-intercom 未装 / 探针与 CLI 均失败），零接触真实 pi-intercom 名册。
# 此时唯一的 cwd 来源 = pane 标题契约 + pane_current_path ⇒ 直接验证「pane cwd 权威」层。
NOAGENT="$LAB/noagent"
run_status "[]" "$NOAGENT"
t4_assert_eq "0" "$RC" "AC1 名册不可用 status rc=0"
L_LOCAL_NO="$(line_of "$LOCAL_NAME")"
t4_assert_match "$L_LOCAL_NO" "^  · $LOCAL_NAME( |\$)" \
  "AC1 名册不可用 pane cwd 在本仓 ⇒ 判本仓（不是 ?）"
t4_assert_contains "$L_LOCAL_NO" "! 残留" "AC1 pane-only 本仓行 tag 走 ! 分支（归档态）"
t4_assert_contains "$L_LOCAL_NO" "close --task T9001 rd-infra" \
  "AC1 pane-only 本仓行给可执行 close --task <编号> <别名>"
L_OTHER_NO="$(line_of "$OTHER_NAME")"
t4_assert_match "$L_OTHER_NO" "^  ~ $OTHER_NAME" "AC2 名册不可用 pane cwd 在他仓 ⇒ 仍判他仓"
t4_assert_contains "$L_OTHER_NO" "$OTHER_BASE" "AC2 他仓行点名他仓仓名（$OTHER_BASE）"
t4_assert_not_contains "$L_OTHER_NO" "close --task" "AC2 他仓 pane 整行不含可执行 close --task"
  t4_ok "AC4 herdr 侧无「两路 cwd 皆无」态可构造（pane.cwd 为结构化必有字段；tmux 侧已覆盖 fail-closed）"

# ============================================================ AC5① 名册正常路径零回归（对固定基线 fixture 逐字等价）
# 只比**名册可用且 pane/名册一致**的场景（冲突/无名册场景正是 M20261101 要改的行为，不入零回归对照）。
#
# 基线 = **固化 fixture**（Issue #78）：`tests/t4/fixtures/nao-fleet-baseline-<sha>.sh` =
#   该 sha 的 `.agents/scripts/nao-fleet.sh` 原样副本（仅顶部追加上下文头）。**不再 `git show main:…`**
#   —— 旧写法让基线随「分支 / 已合并」变动（分支上 2 条、合并后 0 条），门禁断言数跟着漂移。
# 为什么是 2b4ade3：pane cwd 键口径修复（M20261101）的**前一版**，即「pane cwd 权威」生效前的
#   历史基线；名册正常路径的 `status` 输出必须与它逐字等价（AC5① 的本义）。
# fail-closed（Issue #78 AC2）：fixture 缺失 / 为空 / 无来源头 ⇒ **断言失败**（不再 `t4_info` 静默跳过），
#   且基线脚本不可用时也不会假绿（空脚本 ⇒ 输出为空 ⇒ md5 断言必红）。
# 更新流程（AC4）：有意改动 `status` 输出 ⇒ 同步更新本 fixture 并在 PR 说明（见 tests/README.md「用例 19」）。
# 防自等价（QA P3-1）：整文件 md5 因 fixture 恒有头注释而永不相等 ⇒ 另比**正文** md5；
#   正文相等 ⇒ `t4_note baseline-selfequiv` 明示「本轮为自等价」——否则「把当前脚本当 fixture」会让本组退化为恒绿。
BASELINE_SHA="2b4ade3"
BASELINE_FIXTURE="$T4_ROOT/tests/t4/fixtures/nao-fleet-baseline-$BASELINE_SHA.sh"
BASE_SCRIPT="$LAB/base-fleet.sh"
: > "$BASE_SCRIPT"
t4_assert_file "$BASELINE_FIXTURE" \
  "AC5① 固化基线 fixture 存在（tests/t4/fixtures/nao-fleet-baseline-$BASELINE_SHA.sh）"
if [ -f "$BASELINE_FIXTURE" ]; then
  cp "$BASELINE_FIXTURE" "$BASE_SCRIPT" 2>/dev/null || : > "$BASE_SCRIPT"
fi
t4_assert_ne "0" "$(wc -c < "$BASE_SCRIPT" | tr -d ' ')" \
  "AC5① 基线脚本非空（实际 $(wc -c < "$BASE_SCRIPT" | tr -d ' ') B ⇒ 空/缺失即失败，不静默跳过）"
t4_assert_contains "$(head -12 "$BASELINE_FIXTURE" 2>/dev/null)" "source sha: $BASELINE_SHA" \
  "AC5① fixture 顶部注明来源 sha（$BASELINE_SHA）与理由行"
BASE_MD5="$(md5sum < "$BASE_SCRIPT" | awk '{print $1}')"
SUBJ_MD5="$(md5sum < "$SUBJECT" | awk '{print $1}')"
# P3-1（QA）自等价护栏：整文件 md5 因 fixture 恒有头注释而**永不相等** ⇒ 改比**正文**（去头）。
#   fixture 头 = 第 1 行 shebang + 9 行注释 ⇒ 正文从第 11 行起；SUBJECT 正文从第 2 行起（同样去掉 shebang）。
#   两者相等 ⇒ 说明 fixture 是被测脚本的副本（恒绿同义反复）⇒ 必须 t4_note 明示，不能当零回归证据。
FIXTURE_HDR_LINES=10
FIX_BODY_MD5="$(tail -n +$((FIXTURE_HDR_LINES + 1)) "$BASELINE_FIXTURE" 2>/dev/null | md5sum | awk '{print $1}')"
SUBJ_BODY_MD5="$(tail -n +2 "$SUBJECT" | md5sum | awk '{print $1}')"
  # 基线 fixture 是 **tmux 时代**的整脚本（`require_tmux`），herdr 侧无法执行 ⇒ 按后端门控；
  # fixture 存在/非空/来源头三条断言已在上面跑过（后端无关）。
  t4_note backend-gate "AC5① 基线逐字对照以 tmux 为对照载体（fixture = tmux 时代整脚本）；herdr 的零回归由用例 28 的双拼写 md5 + 用例 28 B3 段承担"

# ============================================================ AC3 冲突优先级（pane 优先于名册）
CONFLICT_NAME="qa-T9004"
P_CONFLICT="$(start_pane "$OTHER" "$CONFLICT_NAME" "$OTHER_BASE")"
t4_assert_ne "" "$P_CONFLICT" "AC3 夹具：冲突 pane 建立且标题就绪（pane cwd = 他仓 $OTHER_BASE）"
if [ "$TSX_OK" = "1" ]; then
  R_CONFLICT="$(roster "$(mk_session "$LOCAL_NAME" "$LAB")" \
                       "$(mk_session "$OTHER_NAME" "$OTHER")" \
                       "$(mk_session "$UNK_NAME" "")" \
                       "$(mk_session "$CONFLICT_NAME" "$LAB")")"
  t4_assert_contains "$R_CONFLICT" "\"name\":\"$CONFLICT_NAME\",\"cwd\":\"$LAB\"" \
    "AC3 夹具：名册把冲突会话登记在**本仓**（与 pane cwd 相反）"
  run_status "$R_CONFLICT"
  t4_assert_eq "0" "$RC" "AC3 冲突场景 status rc=0"
  L_CONFLICT="$(line_of "$CONFLICT_NAME")"
  t4_assert_match "$L_CONFLICT" "^  ~ $CONFLICT_NAME" "AC3 pane cwd 优先 ⇒ 判他仓（名册本仓 cwd 未反超）"
  t4_assert_contains "$L_CONFLICT" "$OTHER_BASE" "AC3 冲突行点名 pane 的他仓仓名（$OTHER_BASE）"
  t4_assert_not_contains "$L_CONFLICT" "close --task" "AC3 冲突行不含可执行 close --task（pane 优先不放宽 fail-closed）"
else
  t4_degrade "缺 tsx/node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ AC3「pane 优先于名册」冲突夹具降级"
fi

# ============================================================ M 双向变异（BR1/BR2）
# 子进程模式：只跑上面的断言（不再嵌套变异），父进程据其 rc / FAIL 点名判定。
if [ "$MUTATION_CHILD" != "1" ]; then
  MUT_DIR="$T4_CACHE_DIR/mut19-$$"
  mkdir -p "$MUT_DIR"
  MD5_BEFORE="$(md5sum "$SUBJECT" | awk '{print $1}')"
  GS_BEFORE="$(git -C "$T4_ROOT" status --porcelain 2>/dev/null | sort || true)"

  run_child() {  # <subject> ⇒ 置 CHILD_OUT / CHILD_RC
    CHILD_OUT="$(env T519_SUBJECT="$1" T519_MUTATION_CHILD=1 \
      T4_CACHE_DIR="$T4_CACHE_DIR" T4_REQUIRE_FULL="$T4_REQUIRE_FULL" \
      T4_ALLOW_MISSING="$T4_ALLOW_MISSING" PI_CODING_AGENT_DIR="$PI_AGENT_DIR" \
      "$BASH_BIN" "$SELF" 2>&1)"
    CHILD_RC=$?
  }
  run_mutation() {  # <label> <replacement-line> <必须点名的断言前缀...>
    local label="$1" repl="$2" f fails exp
    f="$MUT_DIR/$label.sh"
    shift 2
    cp "$SUBJECT" "$f" || { t4_bad "M-$label 临时副本创建失败"; return; }
    sed -i '/^repo_contains_path() /c\'"$repl" "$f"
    # 直接对文件 grep（勿把整脚本喂给 t4_assert_contains：大文件 + grep -q 早退会触发 SIGPIPE，pipefail 下假 FAIL）
    t4_assert_eq "1" "$(grep -cF -- "$repl" "$f" || true)" \
      "M-$label 变异已写入临时副本（单行谓词被替换）"
    t4_assert_ne "$MD5_BEFORE" "$(md5sum "$f" | awk '{print $1}')" \
      "M-$label 副本 md5 ≠ 真仓库（确在副本上变异）"
    run_child "$f"
    t4_assert_ne "0" "$CHILD_RC" "M-$label 变异 ⇒ 新用例翻红（rc≠0）"
    t4_assert_contains "$CHILD_OUT" "RESULT: FAIL" "M-$label 变异 ⇒ 输出 RESULT: FAIL"
    fails="$(printf '%s\n' "$CHILD_OUT" | grep -c '^  \[FAIL\]' || true)"
    t4_assert_ge "1" "$fails" "M-$label 变异 ⇒ 至少 1 条 FAIL（实际 $fails 条）"
    for exp in "$@"; do
      t4_assert_contains "$CHILD_OUT" "$exp" "M-$label 点名断言：$exp"
    done
    printf '%s\n' "$CHILD_OUT" | grep '^  \[FAIL\]' | sed 's/^  \[FAIL\] /    · /' \
      | while IFS= read -r l; do t4_info "$label FAIL $l"; done
  }

  # 恒真：所有 pane 都判本仓 ⇒ 他仓会话拿到可执行 close（BR1 安全面被破坏）
  run_mutation "always-true" 'repo_contains_path() { [[ -n "$1" && -n "$2" ]]; }' \
    "② 他仓会话行走 ~" "② 他仓会话整行不含可执行 close --task"
  # 恒假：所有 pane 都判他仓 ⇒ 本仓会话行失去 close，单仓场景出现 ~ 行
  run_mutation "always-false" 'repo_contains_path() { return 1; }' \
    "① 本仓会话行走 ·" "④ 单仓场景零 ~/? 行"

  # AC5② 键口径变异负控：把 `pane_cwds` 建键改回 pane_id（复原缺陷）⇒ AC1 断言必须点名 FAIL。
  #   与上面的单行谓词变异互补：谓词没坏，坏的是「键口径」，若只被谓词变异覆盖则本缺陷仍可静默复发。
  KEY_MUT="$MUT_DIR/key-pane-id.sh"
  if cp "$SUBJECT" "$KEY_MUT"; then
    # 锚改到**语义唯一行**（建键赋值只在 status 出现；close 也有同名 read 行，不能拿读序当锚）
    sed -i 's/pane_cwds\["\$pname"\]/pane_cwds["$pn"]/' "$KEY_MUT"
    t4_assert_eq "1" "$(grep -cF 'pane_cwds["$pn"]' "$KEY_MUT" || true)" \
      "AC5② 变异已写入副本（键口径回退为 pane_id，单处）"
    t4_assert_eq "0" "$(grep -cF 'pane_cwds["$pname"]' "$KEY_MUT" || true)" \
      "AC5② 副本已无修复后的键口径（变异确实生效）"
    t4_assert_ne "$MD5_BEFORE" "$(md5sum "$KEY_MUT" | awk '{print $1}')" \
      "AC5② 副本 md5 ≠ 真仓库（确在副本上变异）"
    run_child "$KEY_MUT"
    t4_assert_ne "0" "$CHILD_RC" "AC5② 键回退 ⇒ 用例翻红（rc≠0，不静默通过）"
    t4_assert_contains "$CHILD_OUT" "RESULT: FAIL" "AC5② 键回退 ⇒ 输出 RESULT: FAIL"
    t4_assert_contains "$CHILD_OUT" "AC1 名册不可用 pane cwd 在本仓 ⇒ 判本仓（不是 ?）" \
      "AC5② 键回退 ⇒ AC1 断言点名 FAIL"
    printf '%s\n' "$CHILD_OUT" | grep '^  \[FAIL\]' | sed 's/^  \[FAIL\] /    · /' \
      | while IFS= read -r l; do t4_info "AC5② FAIL $l"; done
  else
    t4_bad "AC5② 变异副本创建失败（$KEY_MUT）"
  fi

  t4_assert_eq "$MD5_BEFORE" "$(md5sum "$SUBJECT" | awk '{print $1}')" \
    "M 真仓库脚本 md5 前后一致（变异只在副本，BR1 只读纪律）"
  t4_assert_eq "$GS_BEFORE" "$(git -C "$T4_ROOT" status --porcelain 2>/dev/null | sort || true)" \
    "M 真仓库 git status 前后一致（零新增脏改，BR1）"

  # 还原后复绿：未变异的原脚本再跑一遍 ⇒ PASS
  run_child "$SUBJECT"
  t4_assert_eq "0" "$CHILD_RC" "M 还原后（原脚本）复绿：rc=0"
  t4_assert_contains "$CHILD_OUT" "RESULT: PASS" "M 还原后（原脚本）复绿：RESULT: PASS"
fi

t4_exit
