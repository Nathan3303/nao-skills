#!/usr/bin/env bash
# 用例 21 —— 下游卡会话的零副作用边界 / check 分级 / status 未识别节（`ensure --card` 诊断面）
#
# PRD：docs/prds/2026-11-01-downstream-role-sessions.md（§七 AC2 / AC5⑤ / AC8）
# 评审：docs/reports/2026-11-01-T537-arch.md（Q1 六条边界 · Q2 floor F3/F4 · Q4-B1/B2 · D5/D7）
# 被测对象：.agents/scripts/nao-fleet.sh 的 `ensure --card` 卡校验 / `check` 下游卡节 / `status` 未识别节
#
# 断言映射（PRD AC）：
#   AC2 八种失败输入（卡不存在 / 空文件 / 无 role 且无可退化文件名 / 越目录 / symlink 逃逸 /
#       fifo 或目录 / 超 256 KiB / 缺路径参数）逐个：rc≠0 · stderr 单行含原因 + 「该怎么办」·
#       pane 数不变 · tmux session 列表不变 · 无 prompt 临时文件残留
#   AC5⑤ 广告面：`--help` 含 `--card` 与一句用途说明
#   AC8① 卡被删/改名后会话**不静默**：status 新增「角色未识别（疑似 fleet 遗留）」节，
#         带归属三态、**不给**可执行命令、给指路；非任务号形状的名字不误收（floor）
#   AC8② check 分级：内容类（缺 description/CRLF/超限/name: 双用）⇒ warn 不红 rc；
#         机制类（与常驻前缀冲突、卡集前缀嵌套）⇒ error rc=1
#   AC8③ overlay 兼容：扫描目录 realpath == $PROMPTS_DIR realpath ⇒ 该节整体跳过（不恒红）
#   AC8④ 卡集前缀嵌套：check 报 error 点名；status 用最长匹配不误杀
#
# 夹具纪律（B4 · 后端无关）：夹具经 `tests/t4/lib-backend.sh`（`be_*`）建，pane/身份/socket 与
#   会话根由后端抽象单点决定；herdr 侧用 `tests/t4/fixtures/herdr-double`（确定性替身，见其文件头），
#   因此本用例在两种后端都零真会话、零网络、可确定复现。名册仍空化（PI_CODING_AGENT_DIR 空目录）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
if [ "$BE_NAME" = "tmux" ]; then
  command -v tmux >/dev/null 2>&1 \
    || t4_skip "环境缺少 tmux（tmux 后端需真隔离 socket 断言 pane/session 零副作用）"
fi
BASH_BIN="$(command -v bash)"
LAB="$T4_CACHE_DIR/lab21-$$"

FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根判定会被污染"
  t4_exit
fi

# ---- 夹具 ----
mkdir -p "$LAB" "$LAB/bin" "$LAB/pi-empty"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
cp "$T4_ROOT/.agents/scripts/nao-fleet.sh" "$LAB/.agents/scripts/nao-fleet.sh"
# herdr 侧把替身放到 PATH 前缀（tmux 侧不调用 herdr ⇒ 对既有行为零影响）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }
t4_ok "护栏：后端=$BE_NAME · 夹具根=$LAB（不在任何 git 仓内）· 场已起"
# 被测项目（下游仓）与机制包（$LAB）**分居两目录**：卡夹具（含 fifo/目录）只落在项目侧，
# 否则 `check` 的交叉引用扫描会去 grep fifo 而阻塞（与被测特性无关的夹具污染）。
PROJ="$LAB/proj"
mkdir -p "$PROJ/.agents/prompts"
CARDS="$PROJ/.agents/prompts"
mk_card() { # <路径> <role> [description]
  printf -- '---\ndescription: %s\nrole: %s\nversion: 1\nupdated: 2026-11-01\n---\n\n# 夹具角色 %s\n' \
    "${3:-T537 夹具}" "$2" "$2" > "$1"
}
mk_card "$CARDS/ok-card.md" ok-card
printf -- '---\ndescription: 域外卡（不在 prompts/ 内）\nrole: outside-card\n---\n\n# outside\n' > "$PROJ/outside.md"
: > "$CARDS/empty.md"                                   # 空文件
printf -- '---\ndescription: 无 role 且文件名不可退化\n---\n\n# BadCard\n' > "$CARDS/BadCard.md"
ln -sf "$PROJ/outside.md" "$CARDS/escape.md"             # symlink 逃逸
mkfifo "$CARDS/fifo.md" 2>/dev/null || true              # fifo（cat 会挂死 ⇒ 必须在校验期拒）
mkdir -p "$CARDS/dircard.md"                             # 目录冒充卡
{ printf -- '---\ndescription: 超大卡\nrole: big-card\n---\n\n'
  head -c 300000 /dev/zero | tr '\0' 'a'; } > "$CARDS/big.md"
# 名册假探针（只读 env）：归属三态走 T530 既有路径（名册 cwd），不改 pane 键口径
cat > "$LAB/.agents/scripts/intercom-probe.mts" <<'JS'
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(process.env.NAO_QA_FAKE_ROSTER || "[]") }, null, 2));
JS
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
TSX_OK=0
if [ -f "$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then TSX_OK=1; fi
ROSTER_JSON='[]'
mk_roster() { # <repo> <session-name>... → 名册 JSON（cwd = <repo>，status=idle）
  local repo="$1" s="[" e; shift
  for e in "$@"; do s="$s{\"name\":\"$e\",\"cwd\":\"$repo\",\"status\":\"idle\"},"; done
  printf '%s' "${s%,}]"
}
cat > "$LAB/tasks.md" <<'MD'
# T4 case21 tasks-state 夹具（只读）

## 已归档

| 任务 | 状态 |
| :-- | :-- |
MD
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
exit 0
SH
chmod +x "$LAB/bin/pi"

CALLER="$(be_caller_pane)"
BASE="$(basename "$LAB")"
t4_assert_ne "" "$CALLER" "夹具：调用者 pane 建立（$CALLER；后端=$BE_NAME）"

t521_teardown() {
  [ -n "${LAB:-}" ] && [ -d "$LAB" ] || return 0
  be_teardown >/dev/null 2>&1 || true
  return 0
}
t521_exit_trap() {
  local rc=$?
  t521_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t521_exit_trap EXIT

# ---- 调用封装：cwd 可指定（check 分级用独立项目目录）----
# 业务 env 由本用例 export；后端句柄（TMUX/TMUX_PANE 或 HERDR_*/XDG_CONFIG_HOME）由 be_run_fleet 注入
export NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$PI_AGENT_DIR"
export NAO_TASKS_STATE="$LAB/tasks.md"
export PATH="$LAB/bin:$PATH"
run_fleet_in() { # <dir> <args...> → T4_RC/T4_OUT/T4_ERR（*_ANSI 去色）＋ BE_*
  local dir="$1"; shift
  export NAO_QA_FAKE_ROSTER="$ROSTER_JSON"
  be_run_fleet "$dir" "$@"
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT"; T4_ERR="$BE_ERR"
  T4_OUT_ANSI="$BE_OUT_ANSI"; T4_ERR_ANSI="$BE_ERR_ANSI"
}
run_fleet() { run_fleet_in "$PROJ" "$@"; }
pane_count() { be_pane_count; }
# 「零副作用」签名：pane 集 + 会话/workspace 集（tmux = session 名；herdr = workspace id）
scene_signature() { be_scene_signature; }
# 只统计**本用例卡夹具**生成的提示文件（`build_system_prompt` 按卡 basename 命名）：
#   本机/并行用例的常驻会话也会在 /tmp/nao-fleet-* 落文件，全局快照会被污染（假红）。
prompt_files() {
  local stem
  for stem in ok-card empty BadCard escape fifo dircard big outside; do
    ls -1 "/tmp/nao-fleet-$stem"*.md 2>/dev/null || true
  done | sort
}

# ============================================================ AC2 八种失败输入（零副作用）
ac2_case() { # <label> <预期 stderr 子串> <args...>
  local label="$1" want="$2"; shift 2
  local pc sl pf
  pc="$(pane_count)"; sl="$(scene_signature)"; pf="$(prompt_files)"
  run_fleet ensure "$@"
  t4_assert_ne "0" "$T4_RC" "AC2 $label ⇒ rc≠0"
  t4_assert_eq "1" "$(printf '%s\n' "$T4_ERR" | grep -c .)" "AC2 $label ⇒ stderr 恰单行"
  t4_assert_contains "$T4_ERR_ANSI" "$want" "AC2 $label ⇒ 原因点名：$want"
  t4_assert_contains "$T4_ERR_ANSI" "该怎么办" "AC2 $label ⇒ 文案含「该怎么办」"
  t4_assert_eq "$pc" "$(pane_count)" "AC2 $label ⇒ pane 数不变（零副作用）"
  t4_assert_eq "$sl" "$(scene_signature)" "AC2 $label ⇒ 现场签名不变（pane 集 + 会话/workspace 集）"
  t4_assert_eq "$pf" "$(prompt_files)" "AC2 $label ⇒ 无 prompt 临时文件残留"
}

ac2_case "①卡不存在" "角色卡不存在" --card .agents/prompts/missing.md
ac2_case "②空文件" "角色卡为空" --card .agents/prompts/empty.md
ac2_case "③无 role 且无可退化文件名" "角色卡 role 不可用" --card .agents/prompts/BadCard.md
ac2_case "④卡不在 .agents/prompts/ 内" "不在 <repo>/.agents/prompts/ 内" --card outside.md
ac2_case "⑤symlink 逃逸" "不在 <repo>/.agents/prompts/ 内" --card .agents/prompts/escape.md
ac2_case "⑥卡为 fifo" "不是常规文件" --card .agents/prompts/fifo.md
ac2_case "⑥卡为目录" "不是常规文件" --card .agents/prompts/dircard.md
ac2_case "⑦超 256 KiB" "角色卡过大" --card .agents/prompts/big.md
ac2_case "⑧缺少路径参数" "--card 后缺少卡路径参数" --card
ac2_case "⑨含 .. 段（显式拒绝）" "不得含 '..'" --card .agents/prompts/../prompts/ok-card.md

# ============================================================ AC5⑤ 广告面
run_fleet --help
t4_assert_eq "0" "$T4_RC" "AC5⑤ --help rc=0"
t4_assert_contains "$T4_OUT" "--card" "AC5⑤ 帮助含 --card"
t4_assert_contains "$T4_OUT" "下游仓自定义角色会话" "AC5⑤ 帮助含一句用途说明"

# ============================================================ AC8① status 未识别节（D5）
# AC8① 夹具：两个「卡已消失」的会话（身份/归属按后端各自的结构化面建；herdr 需在线证据 ⇒ 走 be_fixture_session）
P_GHOST="$(be_new_pane "$PROJ")"
t4_assert_ne "" "$P_GHOST" "夹具：角色未识别 pane 建立（ghost-reviewer-T9009）"
be_fixture_session "$P_GHOST" "ghost-reviewer-T9009" "$(basename "$PROJ")" || t4_bad "夹具：ghost-reviewer-T9009 身份写入失败"
P_PLAIN="$(be_new_pane "$PROJ")"
t4_assert_ne "" "$P_PLAIN" "夹具：floor pane 建立（helper）"
be_fixture_session "$P_PLAIN" "helper" "$(basename "$PROJ")" || t4_bad "夹具：helper 身份写入失败"
if [ "$TSX_OK" = "1" ]; then
  ROSTER_JSON="$(mk_roster "$PROJ" ghost-reviewer-T9009 helper)"
else
  t4_degrade "缺 tsx/node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ 名册 cwd 不可镜像，AC8① 归属断言降级"
fi
run_fleet status
t4_assert_eq "0" "$T4_RC" "AC8① status rc=0（夹具含孤儿会话）"
t4_assert_contains "$T4_OUT" "== 角色未识别（疑似 fleet 遗留）==" "AC8① 新增「角色未识别」节"
L_GHOST="$(printf '%s\n' "$T4_OUT" | grep -F "ghost-reviewer-T9009" || true)"
if [ "$TSX_OK" = "1" ]; then
  t4_assert_contains "$L_GHOST" "（本仓）" "AC8① 孤儿会话带归属三态（本仓）"
fi
t4_assert_contains "$L_GHOST" "卡被删除/改名" "AC8① 指路：卡被删除/改名"
t4_assert_not_contains "$L_GHOST" "close --task" "AC8① 该行不给可执行回收命令"
t4_assert_contains "$L_GHOST" "不给回收命令" "AC8① 明示本行不提供回收命令"
# floor 判据只看「角色未识别」节（投递判定节按设计会列所有在线 label —— 那不是「误收」）
UNREC_SEC="$(printf '%s\n' "$T4_OUT" | sed -n '/== 角色未识别/,/^== /p')"
t4_assert_contains "$UNREC_SEC" "ghost-reviewer-T9009" "AC8① floor 前置：未识别节确实存在且含目标行"
t4_assert_eq "" "$(printf '%s\n' "$UNREC_SEC" | grep -F "helper" || true)" \
  "AC8① floor：非任务号形状的名字不误收（不猜；只看「角色未识别」节）"
be_kill_pane "$P_GHOST"; be_kill_pane "$P_PLAIN"

# ============================================================ AC8② check 分级（内容 warn / 机制 error）
P1="$LAB/proj-content"     # 仅内容类问题 ⇒ warn 不红 rc
P2="$LAB/proj-conflict"    # 机制类：与常驻前缀冲突 ⇒ error
P3="$LAB/proj-nesting"     # 机制类：卡集前缀嵌套 ⇒ error
for d in "$P1" "$P2" "$P3"; do mkdir -p "$d/.agents/prompts"; done
mk_card "$P1/.agents/prompts/nodesc.md" nodesc ""
printf -- '---\nrole: nodesc2\nversion: 1\nupdated: 2026-11-01\n---\n\n# 无 description\n' > "$P1/.agents/prompts/nodesc2.md"
printf -- '---\r\ndescription: CRLF 卡\r\nrole: crlf-card\r\nversion: 1\r\nupdated: 2026-11-01\r\n---\r\n\r\n# CRLF\r\n' > "$P1/.agents/prompts/crlf.md"
{ printf -- '---\ndescription: 超大\nrole: big-card\n---\n\n'; head -c 300000 /dev/zero | tr '\0' 'a'; } > "$P1/.agents/prompts/big.md"
printf -- '---\nname: dual-use\ndescription: 双用卡\nrole: dual-card\n---\n\n# 双用\n' > "$P1/.agents/prompts/dual.md"
mk_card "$P2/.agents/prompts/pfx.md" qa-audit
mk_card "$P3/.agents/prompts/rev.md" rev
mk_card "$P3/.agents/prompts/revdeep.md" rev-deep

run_fleet_in "$P1" check -v
t4_assert_eq "0" "$T4_RC" "AC8② 内容类问题 ⇒ check rc=0（不红）"
t4_assert_contains "$T4_OUT_ANSI" "缺 frontmatter description" "AC8② 缺 description ⇒ warn 行"
t4_assert_contains "$T4_OUT_ANSI" "含 CRLF" "AC8② CRLF ⇒ warn 行"
t4_assert_contains "$T4_OUT_ANSI" "字节 > 262144" "AC8② 超限 ⇒ warn 行"
t4_assert_contains "$T4_OUT_ANSI" "含 name: " "AC8② name: 双用 ⇒ warn 行（B2）"
t4_assert_contains "$T4_OUT_ANSI" "同时被 pi-subagents 视作 agent" "AC8② 双用 warn 点名 subagent 路径不可解析"

run_fleet_in "$P2" check -v
t4_assert_ne "0" "$T4_RC" "AC8② 与常驻前缀冲突 ⇒ check rc=1（机制类）"
t4_assert_contains "$T4_OUT_ANSI" "✗ pfx.md role=qa-audit 不可用" "AC8② 冲突卡被点名报 error"

run_fleet_in "$P3" check -v
t4_assert_ne "0" "$T4_RC" "AC8④ 卡集前缀嵌套 ⇒ check rc=1"
t4_assert_contains "$T4_OUT_ANSI" "卡集前缀嵌套：rev 与 rev-deep" "AC8④ 嵌套报 error 并点名两卡"

# AC8④ status 最长匹配不误杀（rev 与 rev-deep 并存，会话名 rev-deep-T9001）
P_NEST="$(be_new_pane "$P3")"
t4_assert_ne "" "$P_NEST" "夹具：嵌套卡 pane 建立（rev-deep-T9001）"
be_fixture_session "$P_NEST" "rev-deep-T9001" "$(basename "$P3")" || t4_bad "夹具：rev-deep-T9001 身份写入失败"
if [ "$TSX_OK" = "1" ]; then ROSTER_JSON="$(mk_roster "$P3" rev-deep-T9001)"; fi
run_fleet_in "$P3" status
L_NEST="$(printf '%s\n' "$T4_OUT" | grep -F "rev-deep-T9001" || true)"
if [ "$TSX_OK" = "1" ]; then
  t4_assert_contains "$L_NEST" "下游卡 rev-deep" "AC8④ status 用最长匹配（rev-deep 而非 rev）"
  t4_assert_contains "$L_NEST" "! 残留" "AC8④ 无 tasks-state 记录 ⇒ 标「残留」"
  t4_assert_contains "$L_NEST" "close --task T9001 rev-deep" "AC8④ 最长匹配下给出正确可执行命令"
fi
be_kill_pane "$P_NEST"

# ============================================================ AC8③ overlay 兼容（realpath 相等 ⇒ 整节跳过）
run_fleet_in "$LAB" check -v
t4_assert_eq "0" "$T4_RC" "AC8③ overlay（扫描目录 == 机制包 prompts）⇒ check rc=0（不恒红）"
t4_assert_contains "$T4_OUT_ANSI" "overlay 生效" "AC8③ 该节整体跳过并说明原因"
t4_assert_not_contains "$T4_OUT_ANSI" "✗ fifo.md" "AC8③ 跳过时不得把机制常驻/夹具卡报成冲突"

t4_exit
