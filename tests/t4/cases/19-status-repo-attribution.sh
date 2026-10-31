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
run_status() {  # <roster-json>；$TMUX 指向隔离 server
  local roster="$1" of="$LAB/out.$$"
  ( cd "$LAB" && timeout 90 env -u TMUX -u TMUX_PANE TMUX="$FTMUX" \
      TMUX_TMPDIR="$SOCKDIR" \
      NAO_SKILLS="$LAB" NAO_TASKS_STATE="$TASKS_FIX" \
      PI_CODING_AGENT_DIR="$PI_AGENT_DIR" NAO_QA_FAKE_ROSTER="$roster" \
      PATH="$REAL_PATH" \
      "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" status ) >"$of" 2>&1
  RC=$?
  OUT="$(cat "$of")"; rm -f "$of"
}
mk_session() { printf '{"name":"%s","cwd":"%s","status":"%s"}' "$1" "$2" "${3:-idle}"; }
roster() { local s="[" e; for e in "$@"; do s="$s$e,"; done; printf '%s' "${s%,}]"; }
TX() { tmux -S "$SOCK" "$@"; }
start_pane() {  # <session> <cwd> <pane-title-契约>；echo pane_id
  TX new-session -d -s "$1" -x 200 -y 50 -c "$2" >/dev/null 2>&1 || return 9
  sleep 0.3
  local p
  p="$(TX list-panes -t "$1" -F '#{pane_id}' | head -1)"
  TX select-pane -t "$p" -T "$3" >/dev/null 2>&1 || true
  printf '%s' "$p"
}
line_of() {  # <会话名> ⇒ 该会话在 status 派生区的整行（空 = 未列出）
  printf '%s\n' "$OUT" | grep -F -m1 -e "  · $1" -e "  ~ $1" -e "  ? $1" || true
}

# ---- 夹具：先只建本仓 pane（cwd = LAB）⇒ 单仓场景；再补他仓 pane 与不可判定会话 ----
P_LOCAL="$(start_pane fxlocal "$LAB" "π - $LOCAL_NAME - $LAB_BASE")"
t4_assert_ne "" "$P_LOCAL" "夹具：本仓派生 pane 建立（标题契约 π - $LOCAL_NAME - $LAB_BASE）"

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
t4_assert_ne "" "$P_OTHER" "夹具：他仓派生 pane 建立（pane cwd = 仓外目录 $OTHER_BASE）"
# 不可判定会话：legacy `nao-*` detached 会话（无标题契约 ⇒ 无 pane cwd），名册亦无 cwd
TX new-session -d -s "nao-$UNK_NAME" -x 200 -y 50 -c "$LAB" >/dev/null 2>&1 || true
sleep 0.3

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
