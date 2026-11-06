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

# ---- 能力门 1：tmux（三态夹具都建立在 pane cwd 上；缺则整例 SKIP）----
command -v tmux >/dev/null 2>&1 \
  || t4_skip "环境缺少 tmux（T535 需真 tmux 隔离 socket 构造 pane 归属三态）"

# ---- 夹具路径 + 硬护栏（先于一切 tmux 操作）----
LAB="$T4_CACHE_DIR/lab19-$$"
OTHER="$T4_CACHE_DIR/otherrepo19-$$"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
FTMUX="$SOCK,0,0"
GUARD=0
_TM="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${_TM%%,*}"; do
  [ -n "$p" ] && [ "$SOCK" = "$p" ] && GUARD=1
done
[[ "$SOCK" == "$LAB"/* ]] || GUARD=1
if [ "$GUARD" != 0 ]; then
  t4_bad "护栏触发：夹具 SOCK=$SOCK 不在 \$LAB 下或与生产默认候选冲突"
  t4_exit
fi

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

# ---- 收尾：EXIT trap 链（先机制 cleanup -S，再复刻 lib 缓存清理语义；BR5 保真退出码）----
t519_teardown() {
  [ -n "${SOCK:-}" ] && [ -d "$LAB" ] || return 0
  ( cd "$LAB" 2>/dev/null || cd /tmp
    env -u TMUX "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$SOCK" >/dev/null 2>&1 ) || true
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
mkdir -p "$LAB" "$OTHER" "$SOCKDIR/tmux-$(id -u)"
chmod 700 "$SOCKDIR/tmux-$(id -u)"                 # tmux 3.7+ 校验默认 socket 目录权限（0700）
# #90 P3-①：pane 启动器 —— 标题**只经 argv 传入**（`"$1"`），不做任何字符串内插/转义
#   ⇒ 标题含单引号 / 双引号 / `$` / 空格都安全（旧写法把 title 拼进 `bash -c` 脚本串，含 `'` 即破）。
PANE_LAUNCH="$LAB/pane-title.sh"
cat > "$PANE_LAUNCH" <<'SH'
#!/usr/bin/env bash
printf '\033]0;%s\007' "$1"
exec sleep 1800
SH
chmod +x "$PANE_LAUNCH"
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
run_status() {  # [roster-json] [agent-dir] [被测脚本]；$TMUX 指向隔离 server
  local roster="${1:-"[]"}" agent="${2:-$PI_AGENT_DIR}" script="${3:-$LAB/.agents/scripts/nao-fleet.sh}" of="$LAB/out.$$"
  ( cd "$LAB" && timeout 90 env -u TMUX -u TMUX_PANE TMUX="$FTMUX" \
      TMUX_TMPDIR="$SOCKDIR" \
      NAO_SKILLS="$LAB" NAO_TASKS_STATE="$TASKS_FIX" \
      PI_CODING_AGENT_DIR="$agent" NAO_QA_FAKE_ROSTER="$roster" \
      PATH="$REAL_PATH" \
      "$BASH_BIN" "$script" status ) >"$of" 2>&1
  RC=$?
  OUT="$(cat "$of")"; rm -f "$of"
}
mk_session() { printf '{"name":"%s","cwd":"%s","status":"%s"}' "$1" "$2" "${3:-idle}"; }
roster() { local s="[" e; for e in "$@"; do s="$s$e,"; done; printf '%s' "${s%,}]"; }
TX() { tmux -S "$SOCK" "$@"; }
# #90：标题**由 pane 内进程自己一次性输出 OSC 0** 后常驻 idle —— 不再用 `select-pane -T`。
#   根因（负载下 6/6 复现）：`select-pane -T` 设的 pane_title 会被 pane 内 shell 的 prompt
#   （PS1 里的 `\e]0;\u@\h:\w`）随后重设回 `user@host:/cwd`；负载高时 prompt 重绘晚到，
#   竞态由「我们赢」翻成「prompt 赢」⇒ 标题契约丢失 ⇒ fleet 无法把 pane 映射到会话名 ⇒
#   pane cwd 权威失效 ⇒ 回落到名册 cwd（AC3 冲突场景于是被判「本仓」）。
#   状态稳定后 pid 换成 `sleep`（不再有进程改标题）⇒ 标题恒定。
# 有界等待（AC4）：等 pane_title == 期望契约，上限 5s（50×0.1s）；等不到 ⇒ return 8（调用方判红）。
wait_title() {  # <pane_id> <expected> → 0 就绪 / 1 超时
  local p="$1" want="$2" i got
  for i in $(seq 1 50); do
    got="$(TX display-message -p -t "$p" '#{pane_title}' 2>/dev/null)"
    [ "$got" = "$want" ] && return 0
    sleep 0.1
  done
  return 1
}
start_pane() {  # <session> <cwd> <pane-title-契约>；echo pane_id（标题未就绪 ⇒ 空 + rc=8）
  local sess="$1" dir="$2" title="$3" p
  TX new-session -d -s "$sess" -x 200 -y 50 -c "$dir" "$PANE_LAUNCH" "$title" >/dev/null 2>&1 || return 9
  p="$(TX list-panes -t "$sess" -F '#{pane_id}' 2>/dev/null | head -1)"
  [ -n "$p" ] || return 9
  wait_title "$p" "$title" || return 8
  printf '%s' "$p"
}
line_of() {  # <会话名> ⇒ 该会话在 status 派生区的整行（空 = 未列出）
  printf '%s\n' "$OUT" | grep -F -m1 -e "  · $1" -e "  ~ $1" -e "  ? $1" || true
}

# ---- 夹具：先只建本仓 pane（cwd = LAB）⇒ 单仓场景；再补他仓 pane 与不可判定会话 ----
P_LOCAL="$(start_pane fxlocal "$LAB" "π - $LOCAL_NAME - $LAB_BASE")"
t4_assert_ne "" "$P_LOCAL" "夹具：本仓派生 pane 建立且标题契约就绪（π - $LOCAL_NAME - $LAB_BASE；等不到标题 ⇒ 空 ⇒ 本断言红）"

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
P_OTHER="$(start_pane fxother "$OTHER" "π - $OTHER_NAME - $OTHER_BASE")"
t4_assert_ne "" "$P_OTHER" "夹具：他仓派生 pane 建立且标题就绪（pane cwd = 仓外目录 $OTHER_BASE）"
# 不可判定会话：legacy `nao-*` detached 会话（无标题契约 ⇒ 无 pane cwd），名册亦无 cwd
# ③ legacy `nao-*` detached 会话：标题**显式**设成非契约形态（同样由进程 OSC 0 输出，恒定），
#   不再依赖 shell prompt 偶然不回写标题。这样「无 pane cwd 可用」是确定性事实，不是竞态产物。
TX new-session -d -s "nao-$UNK_NAME" -x 200 -y 50 -c "$LAB" "$PANE_LAUNCH" "legacy-detached" >/dev/null 2>&1 || true
P_UNK="$(TX list-panes -t "nao-$UNK_NAME" -F '#{pane_id}' 2>/dev/null | head -1)"
t4_assert_ne "" "${P_UNK:-}" "夹具：不可判定会话 pane 建立"
wait_title "${P_UNK:-%0}" "legacy-detached" \
  && t4_ok "夹具：不可判定会话标题 = legacy-detached（非契约，确定性）" \
  || t4_bad "夹具：不可判定会话标题未在 5s 内就绪（等不到 ⇒ 红）"

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
L_UNK="$(line_of "$UNK_NAME")"
t4_assert_match "$L_UNK" "^  \? $UNK_NAME" "③ 归属不可判定会话行走 ?"
t4_assert_contains "$L_UNK" "归属不可判定" "③ 归属不可判定行含「归属不可判定」"
t4_assert_not_contains "$L_UNK" "close --task" "③ 归属不可判定整行不含可执行 close --task"

# 单仓断言在混合场景的对照（~/? 行只应来自他仓/不可判定两态，恰 2 行）
t4_assert_eq "2" "$(printf '%s\n' "$OUT" | grep -cE '^  [~?] ' || true)" \
  "②③ 混合场景恰有 2 条 ~/? 行（他仓 + 不可判定，各 1）"
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
L_UNK_NO="$(line_of "$UNK_NAME")"
t4_assert_match "$L_UNK_NO" "^  \? $UNK_NAME" "AC4 两路 cwd 皆无 ⇒ 仍走 ?（fail-closed 未退化）"
t4_assert_contains "$L_UNK_NO" "归属不可判定" "AC4 不可判定行含「归属不可判定」"
t4_assert_not_contains "$L_UNK_NO" "close --task" "AC4 不可判定整行不给可执行 close --task"

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
if [ "$TSX_OK" = "1" ]; then
  run_status "$R_MULTI" "$PI_AGENT_DIR" "$BASE_SCRIPT"
  t4_assert_eq "0" "$RC" "AC5① 基线（fixture $BASELINE_SHA）status rc=0"
  # P3-2（QA）：FAIL 文案要能直接指导「怎么办」+ 给出定位差异的行，不只两个 md5
  AC51_MSG="AC5① 名册正常路径：新版 status 输出与 fixture 基线（$BASELINE_SHA）逐字等价（md5 相同）"
  AC51_HINT="若为有意改动 \`status\` 输出 ⇒ 更新 tests/t4/fixtures/nao-fleet-baseline-<sha>.sh（用**改动前**那一版脚本、新 \`<sha>\` 文件名）并在 PR 说明；见 tests/README.md「用例 19」"
  if [ "$(printf '%s' "$OUT_MIXED" | md5sum | awk '{print $1}')" = "$(printf '%s' "$OUT" | md5sum | awk '{print $1}')" ]; then
    t4_ok "$AC51_MSG"
  else
    AC51_BASE_OUT="$T4_CACHE_DIR/case19-ac51-baseline.out"
    AC51_CUR_OUT="$T4_CACHE_DIR/case19-ac51-current.out"
    printf '%s\n' "$OUT_MIXED" > "$AC51_BASE_OUT" 2>/dev/null || true
    printf '%s\n' "$OUT" > "$AC51_CUR_OUT" 2>/dev/null || true
    t4_bad "$AC51_MSG（期望=$(printf '%s' "$OUT_MIXED" | md5sum | awk '{print $1}') 实际=$(printf '%s' "$OUT" | md5sum | awk '{print $1}')）· $AC51_HINT · 两份输出已落 $AC51_BASE_OUT 与 $AC51_CUR_OUT"
    printf '%s\n' "--- diff -u（前 20 行；左=基线 fixture / 右=当前被测）---"
    diff -u "$AC51_BASE_OUT" "$AC51_CUR_OUT" 2>/dev/null | head -20 | sed 's/^/    /'
  fi
  t4_info "AC5① 对照口径：fixture 整文件 md5=$BASE_MD5 · 正文 md5=$FIX_BODY_MD5 · 被测整文件 md5=$SUBJ_MD5 · 被测正文 md5=$SUBJ_BODY_MD5"
  if [ "$FIX_BODY_MD5" = "$SUBJ_BODY_MD5" ]; then
    t4_note baseline-selfequiv "AC5① 本轮为自等价（护栏触发：fixture 正文 == 被测脚本正文）⇒ 该组对照是恒绿同义反复，不得当零回归证据；更新 fixture 请保留旧基线文件并用新 <sha> 文件名"
  fi
else
  t4_degrade "缺 tsx/node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ AC5① 名册正常路径逐字等价对照降级（fixture 存在/非空/来源头三条断言已跑）"
fi

# ============================================================ AC3 冲突优先级（pane 优先于名册）
CONFLICT_NAME="qa-T9004"
P_CONFLICT="$(start_pane fxconflict "$OTHER" "π - $CONFLICT_NAME - $OTHER_BASE")"
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
    sed -i 's/read -r pname pn pcwd/read -r pn pname pcwd/' "$KEY_MUT"
    t4_assert_eq "1" "$(grep -cF 'read -r pn pname pcwd' "$KEY_MUT" || true)" \
      "AC5② 变异已写入副本（键口径回退为 pane_id，单处）"
    t4_assert_eq "0" "$(grep -cF 'read -r pname pn pcwd' "$KEY_MUT" || true)" \
      "AC5② 副本已无修复后的读序（变异确实生效）"
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
