#!/usr/bin/env bash
# 用例 24 —— `ensure` 多目标时每个 pane 用**其目标自己的**角色卡（Issue #75 · fix 轻通道）
#
# 缺陷（既存 · P1）：`cmd_ensure` 相位 1 用 `resolve_role` 把卡写进全局 `PROMPT`（每目标覆写、
#   最后一个胜出），`spawn_one` 用 `${PROMPT:-}` 回落 ⇒ 多目标时**全体角色卡 = 最后一个目标的卡**
#   （`ensure arch rd-fe` 两个 pane 都是 frontend-developer.md）。单目标不受影响（长期未被发现）。
# 修法（本用例的被测契约）：卡名**按目标**收集（`t_prompts` 与 `t_roles` 同批下发），
#   `spawn_one <name> <repo> <model> <card_override> <role_id> <card_name>`：
#   `card_override`（`--card` 的**完整路径**）优先；否则 `PROMPTS_DIR/<card_name>`（清单**相对名**）。
#   ⇒ 两个参数**互不混用**（override 不被当路径外的任何语义、常驻卡不被当绝对路径）。
#
# 断言映射（PRD/Issue AC）：
#   AC1 多目标每个 pane 的 `--append-system-prompt` 与其目标卡**逐字一致**
#       （3 目标 `arch rd-fe rd-infra` = README 标准用法 + 2 目标 `rd-be qa` = Issue 原始形态）
#   AC2 零回归：① 单目标 `ensure --task <编号> arch` ② `--card` 下游卡路径 ③ 同一批混合
#       （`--card` + 常驻）—— 命令行逐字重建 diff 为空 + 提示文件逐字等于对应卡
#   AC3 负控：把「按目标收卡」改回全局 `PROMPT` 回落（两处：`spawn_one` 取卡 / 调用点传空）
#       ⇒ 本用例必须翻红并点名 AC1 断言；还原后复绿（变异只在 `$T4_CACHE_DIR` 的副本上做）
#
# 夹具纪律（沿用 T515/T523 血训）：
#   - 真 tmux **隔离 socket**（显式硬护栏：≠ 生产默认候选）+ `env -u TMUX -u TMUX_PANE` + `TMUX_TMPDIR` 指向夹具
#   - 桩 `pi`（记录 argv 后长驻，绝不拉起真 pi 会话）；名册离线（`PI_CODING_AGENT_DIR` 指向空目录）
#   - 桩 `tmux`（把 `split-window` 的**末位实参原样落盘**后转发真 tmux）⇒ 断言取 fleet 交给 tmux 的原始字节
#   - 夹具根不得落在任何 git 仓内；收尾走机制 `cleanup -S <隔离 socket>`
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
if [ "$BE_NAME" = "tmux" ]; then
  command -v tmux >/dev/null 2>&1 \
    || t4_skip "环境缺少 tmux（tmux 后端需真隔离 socket 观察 ensure 命令行）"
fi
BASH_BIN="$(command -v bash)"
# 变异子进程会继承父进程的 PATH（含 $LAB/bin 桩 tmux）⇒ 必须优先用父进程解析好的真 tmux，
#   否则桩会 exec 自己（实测：子进程里 split.log 递归，用例挂死）。
REAL_TMUX="${NAO_T24_REAL_TMUX:-$(command -v tmux || true)}"
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
MUT_CHILD="${T524_MUTATION_CHILD:-0}"
LAB="$T4_CACHE_DIR/lab24-$$"
SPLIT_LOG="$LAB/split.log"
PI_LOG="$LAB/fake-pi.log"

# ---- 硬护栏（先于一切后端操作）：夹具根不得落 git 仓内（socket/私有根护栏由 be_init 单点负责）----
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：夹具根不在任何 git 仓内（后端场护栏由 be_init 负责）"

# ---- 夹具 ----
mkdir -p "$LAB" "$LAB/bin" "$LAB/pi-empty"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
# 被测脚本默认取夹具副本（与仓库工作区逐字节一致 ⇒ 变异只在副本上做，仓库只读）
FLEET_BIN="${T524_FLEET:-$LAB/.agents/scripts/nao-fleet.sh}"
REPO_MD5="$(md5sum "$T4_ROOT/.agents/scripts/nao-fleet.sh" | awk '{print $1}')"
if [ -z "${T524_FLEET:-}" ]; then
  t4_assert_eq "$REPO_MD5" "$(md5sum "$FLEET_BIN" | awk '{print $1}')" \
    "夹具：被测脚本副本与仓库工作区逐字节一致（read-only 纪律前提）"
fi

# 下游卡夹具（AC2② / AC2③）：`--card` 传的是**完整/相对路径**，与常驻卡的相对名是两条通道
DOWN_CARD="$LAB/.agents/prompts/downstream-reviewer.md"
cat > "$DOWN_CARD" <<'MD'
---
description: 用例 24 下游卡（--card 路径通道）
role: code-reviewer
version: 1
updated: 2026-11-03
---

# 下游角色 code-reviewer

正文：仅用于用例 24 区分「--card 完整路径」与「清单相对名」两条取卡通道。
MD
DOWN_PHYS="$(cd "$LAB/.agents/prompts" && pwd -P)/downstream-reviewer.md"
LAB_PHYS="$(cd "$LAB" && pwd -P)"   # resolve_card 用 realpath(repo) ⇒ 命令行里的仓路径是绝对物理路径

# pi 桩：记录 argv（每参一行、块尾 END）后长驻；--version 供前置校验
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
{ printf 'cwd=%s\n' "\$PWD"; printf '%q\n' "\$@"; printf 'END\n'; } >> "$PI_LOG"
exec sleep 900
SH
chmod +x "$LAB/bin/pi"

# tmux 桩：split-window 的末位实参（fleet 交给 tmux 的**原始字节**）落盘后再转发真 tmux
cat > "$LAB/bin/tmux" <<'SH'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "split-window" ]; then
  args=("$@")
  printf '%s\n' "${args[${#args[@]}-1]}" >> "$D/../split.log"
fi
exec "${NAO_T24_REAL_TMUX:?}" "$@"
SH
chmod +x "$LAB/bin/tmux"

BASE="$(basename "$LAB")"
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }
CALLER="$(be_caller_pane)"
t4_assert_ne "" "$CALLER" "夹具：调用者 pane 建立（$CALLER；后端=$BE_NAME）"

# ---- 收尾：先拆后端场，再复刻 lib 缓存清理语义（保真退出码）----
t524_teardown() {
  [ -n "${LAB:-}" ] && [ -d "$LAB" ] || return 0
  be_teardown >/dev/null 2>&1 || true
  return 0
}
t524_exit_trap() {
  local rc=$?
  t524_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t524_exit_trap EXIT

# ---- 调用封装 ----
export NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty"
export NAO_T24_REAL_TMUX="${REAL_TMUX:-}" PATH="$LAB/bin:$PATH"
export T4_HERDR_SPAWN_LOG="$SPLIT_LOG"
run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR（*_ANSI = 去色后版本）
  BE_FLEET_SCRIPT="$FLEET_BIN" be_run_fleet "$LAB" "$@"
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT"; T4_ERR="$BE_ERR"
  T4_OUT_ANSI="$BE_OUT_ANSI"; T4_ERR_ANSI="$BE_ERR_ANSI"
}
split_count() { [ -f "$SPLIT_LOG" ] && wc -l < "$SPLIT_LOG" || echo 0; }
new_split() { [ -f "$SPLIT_LOG" ] && sed -n "$(( $1 + 1 )),\$p" "$SPLIT_LOG" || true; }
launch_lines() { grep -cF -- "[$BE_NAME] 已拉起" <<< "$T4_OUT_ANSI" || true; }
unwrap() { printf '%s' "$1" | tr -d '\\'; }
diff_assert() {
  local exp="$1" act="$2" tag="$3" d
  d="$(diff <(printf '%s\n' "$exp") <(printf '%s\n' "$act") 2>&1 || true)"
  if [ -z "$d" ]; then t4_ok "$tag（diff 为空）"; else t4_bad "$tag：diff 非空"; printf '%s\n' "$d" | sed 's/^/    /'; fi
}
# 从命令行取 `--append-system-prompt` 的提示文件路径（去反斜杠后按空白截断；路径无空格）
prompt_file_of() {
  local flat; flat="$(unwrap "$1")"
  printf '%s' "$flat" | sed -nE 's#.*--append-system-prompt (/tmp/nao-fleet-[^ ]*\.md).*#\1#p'
}
# 清单角色 → 卡文件名（读夹具 roles.yaml，不硬编码 · 与 roles.yaml 单一事实对齐）
card_file_of() {
  awk -v id="$1" '
    $0 ~ ("^  " id ":$") { f=1; next }
    f && /^  [a-z0-9-]+:$/ { f=0 }
    f && /^    card: / { sub(/^    card: /, ""); print; exit }
  ' "$LAB/.agents/roles.yaml"
}
card_path_of() { printf '%s/.agents/prompts/%s' "$LAB" "$(card_file_of "$1")"; }
# 提示文件 = 卡正文逐字 + `## 环境锚点`（build_system_prompt）⇒ 前 N 行须与卡逐字相同
prompt_card_head() { sed -n "1,$(wc -l < "$1")p" "$2"; }
# expect_card <prompt_file> <card_path> <label>
expect_card() {
  local pf="$1" card="$2" tag="$3"
  t4_assert_file "$pf" "$tag：提示文件存在（$(basename "${pf:-?}")）"
  [ -f "$pf" ] || return 0
  diff_assert "$(cat "$card")" "$(prompt_card_head "$card" "$pf")" "$tag：提示正文与目标卡逐字一致"
  t4_assert_match "$(basename "$pf")" "^nao-fleet-$(basename "$card" .md)-[A-Za-z0-9]+\.md$" \
    "$tag：提示文件名由**该目标卡**的 stem 生成（$(basename "$card")）"
  t4_assert_eq "1" "$(grep -cF -- "NAO_SKILLS=$LAB" "$pf" || true)" \
    "$tag：环境锚点行仍在（build_system_prompt 未被绕开）"
}
expected_inner() { # <repo> <name> <prompt_file>
  printf 'cd %s && export CODEGRAPH_TELEMETRY=0 && exec pi --name %s --append-system-prompt %s' \
    "$(printf %q "$1")" "$(printf %q "$2")" "$(printf %q "$3")"
}
# 后端差异只在「外层包装」：tmux split-window 收 `bash -lc %q(inner)`；herdr pane run 收 inner 本体
expected_wrapped() {
  if [ "$BE_NAME" = "tmux" ]; then printf 'bash -lc %s' "$(printf %q "$(expected_inner "$1" "$2" "$3")")"
  else printf '%s' "$(expected_inner "$1" "$2" "$3")"; fi
}

# ============================================================ 静态接线（修复形状）
t4_assert_eq "0" "$(grep -cF -- '${PROMPT:-}' "$FLEET_BIN" || true)" \
  "AC1 静态：spawn_one 不再回落全局 \${PROMPT:-}（缺陷机制已移除）"
t4_assert_eq "1" "$(grep -cF -- 't_prompts+=("$PROMPT")' "$FLEET_BIN" || true)" \
  "AC1 静态：cmd_ensure 按目标把**当次解析出的**卡名收进 t_prompts"
t4_assert_eq "1" "$(grep -cF -- 'card="$PROMPTS_DIR/${card_name:-}"' "$FLEET_BIN" || true)" \
  "AC1 静态：常驻卡通道 = PROMPTS_DIR/<相对名>（与 override 的完整路径分参数）"

# ============================================================ AC1① 3 目标（README 标准用法）
BEFORE="$(split_count)"
run_fleet ensure arch rd-fe rd-infra
t4_assert_eq "0" "$T4_RC" "AC1① ensure arch rd-fe rd-infra rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_eq "3" "$(launch_lines)" "AC1① 三目标 ⇒ 3 行 [tmux] 已拉起"
NEWS="$(new_split "$BEFORE")"
t4_assert_eq "3" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC1① 捕获 3 条 split-window 命令串"
_i=1
for pair in "arch-designer:arch-designer" "rd-fe:rd-fe" "rd-infra:rd-infra"; do
  _nm="${pair%%:*}"; _rid="${pair#*:}"
  _cmd="$(printf '%s\n' "$NEWS" | sed -n "${_i}p")"
  _pf="$(prompt_file_of "$_cmd")"
  _card="$(card_path_of "$_rid")"
  t4_assert_contains "$(unwrap "$_cmd")" "--name $_nm" "AC1① 第 ${_i} 个 pane 的会话名 = $_nm"
  expect_card "$_pf" "$_card" "AC1①[$_nm]"
  _i=$((_i + 1))
done
PFS_3="$(printf '%s\n' "$NEWS" | while IFS= read -r l; do printf '%s\n' "$(prompt_file_of "$l")"; done)"
t4_assert_eq "3" "$(printf '%s\n' "$PFS_3" | sort -u | grep -c .)" \
  "AC1① 三个 pane 的提示文件互不相同（不再共用一个卡）"

# ============================================================ AC1② 2 目标（Issue #75 原始形态）
BEFORE="$(split_count)"
run_fleet ensure rd-be qa
t4_assert_eq "0" "$T4_RC" "AC1② ensure rd-be qa rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_eq "2" "$(launch_lines)" "AC1② 两目标 ⇒ 2 行 [tmux] 已拉起"
NEWS="$(new_split "$BEFORE")"
t4_assert_eq "2" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC1② 捕获 2 条 split-window 命令串"
_i=1
for pair in "rd-be:rd-be" "qa:qa"; do
  _nm="${pair%%:*}"; _rid="${pair#*:}"
  _cmd="$(printf '%s\n' "$NEWS" | sed -n "${_i}p")"
  _pf="$(prompt_file_of "$_cmd")"
  _card="$(card_path_of "$_rid")"
  t4_assert_contains "$(unwrap "$_cmd")" "--name $_nm" "AC1② 第 ${_i} 个 pane 的会话名 = $_nm"
  expect_card "$_pf" "$_card" "AC1②[$_nm]"
  _i=$((_i + 1))
done

# ============================================================ AC2 零回归（单目标 / --card / 混合）
if [ "$MUT_CHILD" != "1" ]; then
  # ---- AC2① 单目标：命令行逐字重建 diff 为空 ----
  BEFORE="$(split_count)"
  run_fleet ensure --task T24A arch
  t4_assert_eq "0" "$T4_RC" "AC2① ensure --task T24A arch rc=0"
  t4_assert_eq "1" "$(launch_lines)" "AC2① 单目标 ⇒ 1 行 [tmux] 已拉起"
  CMD_S="$(new_split "$BEFORE" | head -1)"
  PF_S="$(prompt_file_of "$CMD_S")"
  t4_assert_ne "" "$PF_S" "AC2① 命令串含 --append-system-prompt 文件（$PF_S）"
  expect_card "$PF_S" "$(card_path_of arch-designer)" "AC2①[arch]"
  diff_assert "$(expected_wrapped . arch-designer-T24A "$PF_S")" "$CMD_S" \
    "AC2① 单目标命令行 = 逐字重建（cd . + name + append-system-prompt，零新增参数）"

  # ---- AC2② --card 下游卡（完整路径通道）：override 不得被当相对名 ----
  BEFORE="$(split_count)"
  run_fleet ensure --card .agents/prompts/downstream-reviewer.md --task T24B
  t4_assert_eq "0" "$T4_RC" "AC2② ensure --card … rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
  t4_assert_eq "1" "$(launch_lines)" "AC2② --card ⇒ 1 行 [tmux] 已拉起"
  CMD_C="$(new_split "$BEFORE" | head -1)"
  PF_C="$(prompt_file_of "$CMD_C")"
  t4_assert_ne "" "$PF_C" "AC2② 命令串含 --append-system-prompt 文件（$PF_C）"
  expect_card "$PF_C" "$DOWN_PHYS" "AC2②[code-reviewer]"
  diff_assert "$(expected_wrapped "$LAB_PHYS" code-reviewer-T24B "$PF_C")" "$CMD_C" \
    "AC2② --card 命令行 = 逐字重建（卡路径仍是**完整路径**，未被当清单相对名拼成 PROMPTS_DIR/<path>）"

  # ---- AC2③ 同批混合：--card 目标 + 常驻目标各走各的通道 ----
  BEFORE="$(split_count)"
  run_fleet ensure --card .agents/prompts/downstream-reviewer.md rd-be --task T24C
  t4_assert_eq "0" "$T4_RC" "AC2③ ensure --card … rd-be rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
  t4_assert_eq "2" "$(launch_lines)" "AC2③ 混合批次 ⇒ 2 行 [tmux] 已拉起"
  NEWS="$(new_split "$BEFORE")"
  CMD_M1="$(printf '%s\n' "$NEWS" | sed -n '1p')"
  CMD_M2="$(printf '%s\n' "$NEWS" | sed -n '2p')"
  expect_card "$(prompt_file_of "$CMD_M1")" "$DOWN_PHYS" "AC2③[card 目标]"
  expect_card "$(prompt_file_of "$CMD_M2")" "$(card_path_of rd-be)" "AC2③[常驻目标 rd-be]"
  t4_assert_ne "$(prompt_file_of "$CMD_M1")" "$(prompt_file_of "$CMD_M2")" \
    "AC2③ 混合批次两条通道产出不同提示文件（路径通道 ≠ 相对名通道）"
fi

# ============================================================ AC3 负控：改回全局 PROMPT 必红
# 子进程模式：只跑上面 AC1（不再嵌套变异），父进程据 rc / FAIL 点名判定。
if [ "$MUT_CHILD" != "1" ]; then
  MUT_DIR="$T4_CACHE_DIR/mut24-$$"
  mkdir -p "$MUT_DIR"
  MD5_BEFORE="$(md5sum "$FLEET_BIN" | awk '{print $1}')"
  GS_BEFORE="$(git -C "$T4_ROOT" status --porcelain 2>/dev/null | sort || true)"
  MUT="$MUT_DIR/global-prompt.sh"
  if cp "$FLEET_BIN" "$MUT"; then
    # 复原缺陷 = 两处：① spawn_one 取卡回落全局 PROMPT ② 调用点不再按目标传卡名
    sed -i -e 's|card="$PROMPTS_DIR/${card_name:-}"|card="$PROMPTS_DIR/${PROMPT:-}"|' \
           -e 's|"${t_prompts\[\$i\]:-}"|""|' "$MUT"
    t4_assert_eq "1" "$(grep -cF -- 'card="$PROMPTS_DIR/${PROMPT:-}"' "$MUT" || true)" \
      "AC3 变异已写入副本（spawn_one 回落全局 PROMPT）"
    t4_assert_eq "0" "$(grep -cF -- '"${t_prompts[$i]:-}"' "$MUT" || true)" \
      "AC3 变异已写入副本（调用点不再按目标传卡名）"
    t4_assert_eq "0" "$("$BASH_BIN" -n "$MUT" 2>&1 | grep -c . || true)" \
      "AC3 变异副本语法有效（bash -n 无输出）"
    t4_assert_ne "$MD5_BEFORE" "$(md5sum "$MUT" | awk '{print $1}')" \
      "AC3 副本 md5 ≠ 真脚本（确在副本上变异）"
    run_child() {  # <fleet 脚本> ⇒ CHILD_OUT / CHILD_RC / CHILD_FAILS
      CHILD_OUT="$(env T524_FLEET="$1" T524_MUTATION_CHILD=1 \
        T4_CACHE_DIR="$T4_CACHE_DIR" T4_ROOT="$T4_ROOT" \
        T4_REQUIRE_FULL="$T4_REQUIRE_FULL" T4_ALLOW_MISSING="$T4_ALLOW_MISSING" \
        "$BASH_BIN" "$SELF" 2>&1)"
      CHILD_RC=$?
      CHILD_FAILS="$(printf '%s\n' "$CHILD_OUT" | grep -c '^  \[FAIL\]' || true)"
    }
    run_child "$MUT"
    t4_assert_ne "0" "$CHILD_RC" "AC3 改回全局 PROMPT ⇒ 用例翻红（rc≠0）"
    t4_assert_contains "$CHILD_OUT" "RESULT: FAIL" "AC3 改回全局 PROMPT ⇒ 输出 RESULT: FAIL"
    t4_assert_ge "1" "$CHILD_FAILS" "AC3 改回全局 PROMPT ⇒ 至少 1 条断言翻红（实际 $CHILD_FAILS 条）"
    t4_assert_contains "$CHILD_OUT" "AC1①[arch-designer]：提示正文与目标卡逐字一致" \
      "AC3 负控点名：AC1① arch pane 的卡（未修时 = 最后一个目标的卡）"
    t4_assert_contains "$CHILD_OUT" "AC1②[rd-be]：提示正文与目标卡逐字一致" \
      "AC3 负控点名：AC1② 两目标场景（Issue #75 原始形态）"
    printf '%s\n' "$CHILD_OUT" | grep '^  \[FAIL\]' | sed 's/^  \[FAIL\] /    · /' \
      | while IFS= read -r l; do t4_info "AC3 FAIL $l"; done

    # 还原后复绿：未变异的原脚本再跑一遍 ⇒ PASS
    run_child "$FLEET_BIN"
    t4_assert_eq "0" "$CHILD_RC" "AC3 还原后（原脚本）复绿：rc=0"
    t4_assert_contains "$CHILD_OUT" "RESULT: PASS" "AC3 还原后（原脚本）复绿：RESULT: PASS"
  else
    t4_bad "AC3 变异副本创建失败（$MUT_DIR/global-prompt.sh）"
  fi

  t4_assert_eq "$MD5_BEFORE" "$(md5sum "$FLEET_BIN" | awk '{print $1}')" \
    "AC3 被测脚本 md5 前后一致（变异只在副本）"
  t4_assert_eq "$GS_BEFORE" "$(git -C "$T4_ROOT" status --porcelain 2>/dev/null | sort || true)" \
    "AC3 真仓库 git status 前后一致（零新增脏改）"
fi

t4_exit
