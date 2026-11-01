#!/usr/bin/env bash
# 用例 20 —— 下游仓自定义角色会话（`ensure --card`）：主路径 / 命名反冒充 / 语法绑定 / 托管三接线
#
# PRD：docs/prds/2026-11-01-downstream-role-sessions.md（§七 AC1 / AC3 / AC4 / AC6 / AC7）
# 评审：docs/reports/2026-11-01-T537-arch.md（Q1 信任边界 · Q3 close 语义分叉 · Q4-B3 语法绑定）
# ADR：docs/adr/2026-11-01-downstream-card-sessions.md
# 被测对象：.agents/scripts/nao-fleet.sh 的 `ensure --card` / `status` / `close`
#
# 断言映射（PRD AC）：
#   AC1 主路径：① 新 pane 起于调用者宿主窗口 ② `--name <role>-<task>`（标题契约由 pi 侧设置，此处断言 argv）
#             ③ 系统提示文件 = 卡正文逐字节 + `## 环境锚点` 行，且锚点行与常驻角色起出的**逐字相同**
#   AC3 边界：① role 撞常驻 id ⇒ 拒且提示 `--as` ② --as 非法字符 ⇒ 拒 ③ --as 撞常驻 id ⇒ 拒
#             ④ 默认名 + --task 组合不与常驻名冲突（正控：同批 `qa` 走清单、卡走默认名）
#   AC4 托管：① status 列在派生/一次性节且无「他仓/不可判定」标注 ② close rc=0 + pane 消失
#             ③ 常驻/一次性分叉 A–D 四段（A 正向警告 · B 反向不警告 · C 正交 · D 闸门不外溢）
#             ④ 归档 task ⇒ status 给「残留」+ 可执行 close 命令 ⑤ 回收后 status 与名册双清
#   AC6 反冒充：① 常驻前缀 `qa-audit` ② `subagent-review` ③ `nao-x` ④ 大写/尾 `-`/33 字符 ⑤ 正控通过
#   AC7 语法：① `--card` 只绑其后第一个 positional ② 末尾悬挂 ⇒ 用法错 ③ check/status/close 带 --card ⇒ 用法错
#             ④ 两相执行：混合批次前项合法 + 后项卡非法 ⇒ pane 数 0
#
# 夹具纪律（同 T535 用例 19）：隔离 socket（≠ 生产候选）+ `env -u TMUX -u TMUX_PANE` +
#   **宿主窗口/名册全部 hermetic**：pane 标题由用例直接 `select-pane -T` 注入（不依赖真 pi），
#   名册走 `PI_CODING_AGENT_DIR` 空目录（tsx 缺失 ⇒ intercom 离线），零网络、零真会话接触。
#   `pi` 用桩脚本（记录 argv 后 `sleep`），使 ensure 不拉起真 pi 会话。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

command -v tmux >/dev/null 2>&1 \
  || t4_skip "环境缺少 tmux（T537 需真 tmux 隔离 socket 构造 pane/托管夹具）"

BASH_BIN="$(command -v bash)"
LAB="$T4_CACHE_DIR/lab20-$$"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
FTMUX="$SOCK,0,0"
CARDS="$LAB/.agents/prompts"

# ---- 硬护栏（先于一切 tmux 操作）：socket 不得命中生产候选，夹具根不得落 git 仓内 ----
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
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：隔离 socket + 夹具根不在任何 git 仓内"

# ---- 夹具 ----
mkdir -p "$LAB" "$SOCKDIR/tmux-$(id -u)" "$LAB/bin" "$LAB/pi-empty"
chmod 700 "$SOCKDIR/tmux-$(id -u)"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
cp "$T4_ROOT/.agents/scripts/nao-fleet.sh" "$LAB/.agents/scripts/nao-fleet.sh"
# 名册假探针（只读 env；绝不接触真实 pi-intercom）：归属三态需要名册 cwd（T530 既有路径）
cat > "$LAB/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
TSX_OK=0
if [ -f "$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then TSX_OK=1; fi
ROSTER_JSON='[]' 
# pi 桩：记录 argv 后长驻（绝不拉起真 pi 会话）；panes 的 PATH 由 tmux server 全局 env 注入
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
{ printf 'cwd=%s\n' "\$PWD"; printf '%s\n' "\$@"; } >> "$LAB/fake-pi.log"
exec sleep 900
SH
chmod +x "$LAB/bin/pi"
# 卡夹具：正控（code-reviewer / data-reviewer）+ 反冒充负控（各类非法 role）
mk_card() { # <文件名> <role 行内容，留空则不写 role>
  local f="$CARDS/$1"
  {
    printf -- '---\n'
    printf 'description: T537 夹具卡（%s）\n' "$1"
    [ -n "${2:-}" ] && printf 'role: %s\n' "$2"
    printf 'version: 1\nupdated: 2026-11-01\n---\n\n# 夹具角色 %s\n\n正文：仅用于用例断言。\n' "$1"
  } > "$f"
}
mk_card code-reviewer.md code-reviewer
mk_card data-reviewer.md data-reviewer
mk_card role-qa.md qa
mk_card role-qa-prefix.md qa-audit
mk_card role-subagent.md subagent-review
mk_card role-nao.md nao-x
mk_card role-upper.md Qa_Audit
mk_card role-trailing.md 'qa-'
mk_card role-long.md "$(printf 'a%.0s' $(seq 1 33))"

TASKS_FIX="$LAB/tasks-state-fixture.md"
cat > "$TASKS_FIX" <<'MD'
# T4 case20 tasks-state 夹具（只读）

## 进行态

| 任务 | 状态 |
| :-- | :-- |
| T537 | 进行中 |

## 已归档

| 任务 | 状态 |
| :-- | :-- |
| T9001 | v1 |
MD

TX() { tmux -S "$SOCK" "$@"; }
TX new-session -d -s lab -x 240 -y 60 -c "$LAB" >/dev/null 2>&1
sleep 0.3
CALLER="$(TX list-panes -t lab -F '#{pane_id}' | head -1)"
TX setenv -g PATH "$LAB/bin:$PATH" >/dev/null 2>&1   # 新 pane 用桩 pi（server 全局 env）
BASE="$(basename "$LAB")"

t4_assert_ne "" "$CALLER" "夹具：隔离 tmux server + 调用者 pane 建立（$CALLER）"

# ---- 收尾：先机制 cleanup -S，再复刻 lib 缓存清理语义（保真退出码）----
t520_teardown() {
  [ -n "${SOCK:-}" ] && [ -d "${LAB:-/nonexistent}" ] || return 0
  ( cd "$LAB" 2>/dev/null || cd /tmp
    env -u TMUX "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$SOCK" >/dev/null 2>&1 ) || true
  return 0
}
t520_exit_trap() {
  local rc=$?
  t520_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t520_exit_trap EXIT

# ---- 调用封装 ----
ROSTER_JSON='[]'
mk_roster() { # <session-name>... → 名册 JSON（cwd = $LAB，status=idle）
  local s="[" e
  for e in "$@"; do s="$s{\"name\":\"$e\",\"cwd\":\"$LAB\",\"status\":\"idle\"},"; done
  printf '%s' "${s%,}]"
}
run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR（T4_ERR_ANSI 去色后版本，供固定前缀断言）
  t4_run_in_dir "$LAB" env -u TMUX -u TMUX_PANE TMUX="$FTMUX" TMUX_PANE="$CALLER" \
    TMUX_TMPDIR="$SOCKDIR" NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$PI_AGENT_DIR" \
    NAO_QA_FAKE_ROSTER="$ROSTER_JSON" \
    NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
    timeout 90 bash "$LAB/.agents/scripts/nao-fleet.sh" "$@"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
pane_ids() { TX list-panes -a -F '#{pane_id}' 2>/dev/null | sort; }
pane_count() { TX list-panes -a -F '#{pane_id}' 2>/dev/null | grep -c . || true; }
set_title() { # <pane_id> <session-name>
  TX select-pane -t "$1" -T "π - $2 - $BASE" >/dev/null 2>&1 || true
}
new_panes() { # <before-ids> → 新增 pane id（每行一个）
  local before="$1"
  pane_ids | while IFS= read -r p; do printf '%s\n' "$before" | grep -qxF "$p" || printf '%s\n' "$p"; done
}
prompt_of() { # <pane_id> → 该 pane 的 --append-system-prompt 文件路径
  TX list-panes -a -F "#{pane_id}"$'\t'"#{pane_start_command}" 2>/dev/null \
    | awk -F'\t' -v p="$1" '$1 == p { c=$2; gsub(/\\/, "", c); if (match(c, /\/tmp\/nao-fleet-[^ ]*\.md/)) print substr(c, RSTART, RLENGTH) }'
}
name_of() { # <pane_id> → 该 pane 的 --name 实参
  TX list-panes -a -F "#{pane_id}"$'\t'"#{pane_start_command}" 2>/dev/null \
    | awk -F'\t' -v p="$1" '$1 == p { c=$2; gsub(/\\/, "", c); if (match(c, /--name [^ ]+/)) print substr(c, RSTART + 7, RLENGTH - 7) }'
}
last_status_line() { printf '%s\n' "$T4_OUT" | grep -F -- "$1" || true; }

# ============================================================ AC1 主路径
BEFORE="$(pane_ids)"
run_fleet ensure --card .agents/prompts/code-reviewer.md --task T537
t4_assert_eq "0" "$T4_RC" "AC1 ensure --card rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
P_CR="$(new_panes "$BEFORE" | head -1)"
t4_assert_ne "" "$P_CR" "AC1① 新 pane 起于调用者宿主窗口（同一 window 内分屏）"
t4_assert_eq "$(TX display-message -p -t "$CALLER" '#{window_id}')" \
  "$(TX display-message -p -t "${P_CR:-$CALLER}" '#{window_id}')" "AC1① 新 pane 与调用者同窗口"
t4_assert_eq "$LAB" "$(TX display-message -p -t "${P_CR:-$CALLER}" '#{pane_current_path}')" \
  "AC1① 新 pane 工作区 = --card 所属仓（$BASE）"
t4_assert_eq "code-reviewer-T537" "$(name_of "$P_CR")" \
  "AC1② --name 为 <卡 role>-<task>（pi 侧据此设标题 π - code-reviewer-T537 - $BASE）"
t4_assert_contains "$T4_OUT" "已拉起 1 个会话" "AC1 就绪提示恰一行（T536 口径不变）"

# AC1③ 系统提示 = 卡正文逐字节 + 锚点行；锚点行与常驻角色逐字相同
PROMPT_CR="$(prompt_of "$P_CR")"
t4_assert_file "${PROMPT_CR:-/nonexistent}" "AC1③ 卡会话的系统提示文件已生成（$PROMPT_CR）"
CARD_BYTES="$(wc -c < "$CARDS/code-reviewer.md")"
if [ -n "$PROMPT_CR" ] && head -c "$CARD_BYTES" "$PROMPT_CR" | cmp -s - "$CARDS/code-reviewer.md"; then
  t4_ok "AC1③ 提示文件前缀 = 卡正文逐字节（$CARD_BYTES 字节，cmp 无差异）"
else
  t4_bad "AC1③ 提示文件前缀与卡正文不一致"
fi
t4_assert_contains "$(cat "${PROMPT_CR:-/dev/null}" 2>/dev/null)" "## 环境锚点" "AC1③ 提示文件含 ## 环境锚点 行"
t4_assert_contains "$(cat "${PROMPT_CR:-/dev/null}" 2>/dev/null)" "NAO_SKILLS=$LAB" "AC1③ 锚点行指向机制包根（NAO_SKILLS=$LAB）"
ANCHOR_CR="$(grep -F -- 'NAO_SKILLS=' "${PROMPT_CR:-/dev/null}" 2>/dev/null | tail -1)"

# ============================================================ AC3④ 混合批次：qa 走清单、卡走默认名
BEFORE="$(pane_ids)"
run_fleet ensure qa --card .agents/prompts/data-reviewer.md
t4_assert_eq "0" "$T4_RC" "AC3④ 混合批次 ensure（常驻 qa + 卡 data-reviewer）rc=0"
NEWS="$(new_panes "$BEFORE")"
t4_assert_eq "2" "$(printf '%s\n' "$NEWS" | grep -c .)" "AC3④ 混合批次拉起 2 个 pane（qa + data-reviewer）"
NAMES="$(while IFS= read -r p; do [ -n "$p" ] && name_of "$p"; done <<< "$NEWS" | sort | tr '\n' ' ')"
t4_assert_contains "$NAMES" "data-reviewer" "AC3④ 卡目标默认名 = 卡 role（data-reviewer）"
t4_assert_contains "$NAMES" "qa" "AC3④ 同批 qa 仍走清单常驻（不与卡互相污染）"
P_QA="$(while IFS= read -r p; do [ -n "$p" ] || continue; [ "$(name_of "$p")" = "qa" ] && { printf '%s' "$p"; break; }; done <<< "$NEWS")"
ANCHOR_QA="$(grep -F -- 'NAO_SKILLS=' "$(prompt_of "$P_QA")" 2>/dev/null | tail -1)"
t4_assert_eq "$ANCHOR_CR" "$ANCHOR_QA" "AC1③ 卡会话与常驻角色的锚点行**逐字相同**（cross-assert）"

# 收尾：把这两个 pane 关掉，后续各段从干净场开始
for p in $NEWS; do TX kill-pane -t "$p" >/dev/null 2>&1 || true; done
sleep 0.3

# ============================================================ AC4① status 可见
BEFORE="$(pane_ids)"
run_fleet ensure --card .agents/prompts/code-reviewer.md --task T537
P_CR="$(new_panes "$BEFORE" | head -1)"
set_title "$P_CR" "code-reviewer-T537"
if [ "$TSX_OK" = "1" ]; then
  ROSTER_JSON="$(mk_roster code-reviewer-T537)"
  run_fleet status
else
  t4_degrade "缺 tsx/node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ 名册 cwd 不可镜像，AC4①/AC4④ 归属断言降级"
  run_fleet status
fi
t4_assert_eq "0" "$T4_RC" "AC4① status rc=0"
L_CR="$(last_status_line "code-reviewer-T537")"
if [ "$TSX_OK" = "1" ]; then
  t4_assert_match "$L_CR" "^  · code-reviewer-T537" "AC4① 卡会话列在派生/一次性节（行首 ·）"
  t4_assert_contains "$L_CR" "一次性会话" "AC4① 该行标注「一次性会话」"
  t4_assert_contains "$L_CR" "下游卡 code-reviewer" "AC4① 该行点名下游卡 role"
  t4_assert_not_contains "$L_CR" "他仓" "AC4① 本仓卡会话无「他仓」标注"
  t4_assert_not_contains "$L_CR" "不可判定" "AC4① 本仓卡会话无「不可判定」标注"
fi

# ============================================================ AC4④ 残留：归档 task ⇒ 给「残留」+ 可执行命令
TX new-session -d -s fx-residue -x 200 -y 50 -c "$LAB" >/dev/null 2>&1 || true
sleep 0.3
P_RES="$(TX list-panes -t fx-residue -F '#{pane_id}' | head -1)"
set_title "$P_RES" "code-reviewer-T9001"
if [ "$TSX_OK" = "1" ]; then ROSTER_JSON="$(mk_roster code-reviewer-T537 code-reviewer-T9001)"; fi
run_fleet status
L_RES="$(last_status_line "code-reviewer-T9001")"
if [ "$TSX_OK" = "1" ]; then
  t4_assert_contains "$L_RES" "残留" "AC4④ 已归档 task 的卡会话行标「残留」"
  t4_assert_contains "$L_RES" "close --task T9001 code-reviewer" "AC4④ 该行给出可执行 close 命令"
fi

# ============================================================ AC4③B 一次性会话不弹常驻警告 + AC4② 回收
ROSTER_JSON="$(mk_roster code-reviewer-T537)"
run_fleet close --task T537 code-reviewer
t4_assert_eq "0" "$T4_RC" "AC4② close（卡会话）rc=0"
t4_assert_contains "$T4_ERR" "一次性会话 code-reviewer-T537（下游卡）" "AC4③B stderr 含新固定前缀「一次性会话 …（下游卡）」"
if printf '%s\n' "$T4_ERR" | grep -qE '常驻会话 .*ensure --force'; then
  t4_bad "AC4③B 卡会话不应出现常驻警告（stderr 命中「常驻会话 .*ensure --force」）"
else
  t4_ok "AC4③B stderr 不匹配常驻警告「常驻会话 .*ensure --force」"
fi
if TX list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$P_CR"; then
  t4_bad "AC4② 回收后 pane $P_CR 仍存在"
else
  t4_ok "AC4② 回收后 pane $P_CR 已消失"
fi
ROSTER_JSON="$(mk_roster code-reviewer-T9001)"
run_fleet status
t4_assert_eq "" "$(last_status_line "code-reviewer-T537")" "AC4⑤ 回收后 status 不再列出该卡会话"

# ============================================================ AC4③A 常驻仍须警告（正向）
BEFORE="$(pane_ids)"
run_fleet ensure qa
P_QA="$(new_panes "$BEFORE" | head -1)"
set_title "$P_QA" "qa"
run_fleet close qa
t4_assert_eq "0" "$T4_RC" "AC4③A close qa rc=0"
t4_assert_contains "$T4_ERR_ANSI" "[fleet] 常驻会话 qa：任务闭环后应 ensure --force 重开" \
  "AC4③A 常驻会话仍弹固定前缀警告（未被整体静音）"

# ============================================================ AC4③C 正交：B 之后 A 的警告仍在
run_fleet ensure --card .agents/prompts/code-reviewer.md
P_CR2="$(TX list-panes -a -F '#{pane_id}' | grep -vxF "$CALLER" | grep -vxF "$P_RES" | tail -1)"
set_title "$P_CR2" "code-reviewer"
run_fleet close code-reviewer
t4_assert_eq "0" "$T4_RC" "AC4③C （B 路径：裸名卡会话）close rc=0"
t4_assert_contains "$T4_ERR" "一次性会话 code-reviewer（下游卡）" "AC4③C B 路径含一次性标识"
BEFORE="$(pane_ids)"
run_fleet ensure qa
P_QA="$(new_panes "$BEFORE" | head -1)"
set_title "$P_QA" "qa"
run_fleet close qa
t4_assert_contains "$T4_ERR_ANSI" "[fleet] 常驻会话 qa：任务闭环后应 ensure --force 重开" \
  "AC4③C B 之后 A 的常驻警告仍出现（禁整体静音蒙过 B）"

# ============================================================ AC4③D 闸门分叉不外溢
BEFORE="$(pane_ids)"
run_fleet ensure --card .agents/prompts/code-reviewer.md --task T537
P_CR3="$(new_panes "$BEFORE" | head -1)"
set_title "$P_CR3" "code-reviewer-T537"
run_fleet close --task T537 code-reviewer
t4_assert_eq "0" "$T4_RC" "AC4③D 卡会话在 task active 时仍可回收（跳过 tasks-state 闸门）"
BEFORE="$(pane_ids)"
run_fleet ensure qa --task T537
P_QA="$(new_panes "$BEFORE" | head -1)"
set_title "$P_QA" "qa-T537"
run_fleet close --task T537 qa
t4_assert_ne "0" "$T4_RC" "AC4③D 反例：常驻派生 qa-T537 仍被 active 闸门拒绝（放宽只对卡生效）"
t4_assert_contains "$T4_ERR" "tasks-state 中 T537 仍在进行态" "AC4③D 反例拒绝理由为 tasks-state active 闸门"
TX kill-pane -t "$P_QA" >/dev/null 2>&1 || true
TX kill-session -t fx-residue >/dev/null 2>&1 || true

# ============================================================ AC6 反冒充（前缀/保留前缀/字符集）
neg_case() { # <label> <卡文件名> <期望 stderr 子串>
  local label="$1" card="$2" want="$3" before
  before="$(pane_count)"
  run_fleet ensure --card ".agents/prompts/$card"
  t4_assert_ne "0" "$T4_RC" "AC6 $label ⇒ 拒绝（rc≠0）"
  t4_assert_contains "$T4_ERR" "$want" "AC6 $label 拒绝理由点名：$want"
  t4_assert_eq "$before" "$(pane_count)" "AC6 $label 零副作用（pane 数不变）"
}
neg_case "①常驻前缀 qa-audit" role-qa-prefix.md "以常驻前缀 qa- 开头"
neg_case "②subagent- 保留前缀" role-subagent.md "不得以保留前缀 subagent- 开头"
neg_case "③nao- 保留前缀" role-nao.md "不得以保留前缀 nao- 开头"
neg_case "④大写字母" role-upper.md "非法字符"
neg_case "④尾 -" role-trailing.md "不得以 - 结尾"
neg_case "④33 字符" role-long.md "名字过长"
neg_case "①撞常驻 id（role: qa）" role-qa.md "与常驻角色/别名 qa 同名"

# ⑤ 正控：合法卡通过（证明拒绝不是「一律拒」）
run_fleet ensure --card .agents/prompts/data-reviewer.md --task T537
t4_assert_eq "0" "$T4_RC" "AC6⑤ 正控：data-reviewer 通过（拒绝不是一律拒）"
P_OK="$(TX list-panes -a -F '#{pane_id}' | grep -vxF "$CALLER" | grep -vxF "$P_RES" | tail -1)"
TX kill-pane -t "${P_OK:-$CALLER}" >/dev/null 2>&1 || true

# ============================================================ AC3 ①–③ --as 边界
run_fleet ensure --card .agents/prompts/role-qa.md --as audit
t4_assert_ne "0" "$T4_RC" "AC3① role 撞常驻 id 时拒绝"
t4_assert_contains "$T4_ERR" "改用 --as" "AC3① 拒绝文案提示改用 --as"
for bad in 'bad name' 'a/b'; do
  before="$(pane_count)"
  run_fleet ensure --card .agents/prompts/data-reviewer.md --as "$bad"
  t4_assert_ne "0" "$T4_RC" "AC3② --as 非法字符（$bad）⇒ 拒绝"
  t4_assert_contains "$T4_ERR" "--as 不可用" "AC3② 拒绝文案点名 --as"
  t4_assert_eq "$before" "$(pane_count)" "AC3② --as 非法（$bad）零副作用"
done
run_fleet ensure --card .agents/prompts/data-reviewer.md --as qa
t4_assert_ne "0" "$T4_RC" "AC3③ --as 撞 ROLE_ORDER id（qa）⇒ 拒绝"
t4_assert_contains "$T4_ERR" "与常驻角色/别名 qa 同名" "AC3③ 拒绝文案点名冲突角色"

# ============================================================ AC7 语法绑定 + 两相执行
before="$(pane_count)"
run_fleet ensure --card
t4_assert_ne "0" "$T4_RC" "AC7② 末尾悬挂 --card ⇒ 用法错（rc≠0）"
t4_assert_eq "1" "$(printf '%s\n' "$T4_ERR" | grep -c .)" "AC7② 用法错为单行提示"
t4_assert_eq "$before" "$(pane_count)" "AC7② 悬挂修饰符零副作用"
for sub in status close check; do
  run_fleet "$sub" --card .agents/prompts/code-reviewer.md
  t4_assert_ne "0" "$T4_RC" "AC7③ $sub 带 --card ⇒ 用法错（rc≠0）"
  t4_assert_contains "$T4_ERR" "仅用于 ensure 子命令" "AC7③ $sub 的用法错点名 --card 适用范围"
done
before="$(pane_count)"
run_fleet ensure qa --card .agents/prompts/role-qa.md
t4_assert_eq "$before" "$(pane_count)" "AC7④ 两相执行：前项 qa 合法 + 后项卡非法 ⇒ pane 数 0（前项也没拉）"
t4_assert_eq "$before" "$(pane_count)" "AC7④ 零副作用复核（pane 数逐值一致）"

# AC7①：--card 只绑其后第一个 positional —— `qa` 在前、卡在后时 qa 不得被当成卡
before="$(pane_count)"
run_fleet ensure qa --card .agents/prompts/data-reviewer.md --task T537
t4_assert_eq "0" "$T4_RC" "AC7① ensure qa --card <卡> 正常执行（qa 走清单、卡走卡）"
t4_assert_eq "$((before + 2))" "$(pane_count)" "AC7① 恰拉起 2 个 pane（无误绑成 1 个或 0 个）"
NEWS="$(TX list-panes -a -F '#{pane_id}' | grep -vxF "$CALLER" | grep -vxF "$P_RES")"
for p in $NEWS; do TX kill-pane -t "$p" >/dev/null 2>&1 || true; done

t4_exit
