#!/usr/bin/env bash
# 用例 39 —— 联动仓 manifest（#139 / T553 · ADR 2026-11-19-fleet-repo-manifest）
#
# 判据来源：docs/reports/139-lite-spec.md（13 态判据表）· PRD docs/prds/2026-11-19-fleet-manifest.md
# 被测对象：.agents/scripts/nao-fleet.sh
#   · M1 `fleet_manifest_load`（单次加载；NONE = 合法缺席；非法 = 文件:行号 字段 原因）
#   · M2 `fleet_repo_resolve`（`@` 四步：code → 既有仓路径 → 冲突 fail loud → 都未命中 fail loud）
#   · M3 放置键 = slug + tab 标签 = `<组前缀>/<name>`（main = 主仓组前缀；四处同源）
#   · M4 三预算不放宽（core ≤32 / scope ≤16 / full ≤48）
#   · M5 status / close 读面（期望仓回落 = manifest code → path）
#
# **加速档（用户 2026-11-19 拍板）**：只断言「能被改动咬住」的位 —— 核心三态（B 合法派生 / E 未命中 /
#   F 非法字段）最严；其余态直接绿断言。**不**为求全面再加等价态 / 逐条变异矩阵（变异面由 cases/06 的
#   静态契约 + 审查兜底）。用例不入快档（建 pane 超 15s 预算，同 T551 D2 口径）。
#
# 断言编号 ↔ 依据（每态必 PASS 或 SKIP，禁 FAIL、禁静默通过）：
#   A 无 manifest        ⇒ 与既有行为逐字一致：名字 `rd-be@<仓 slug>` · tab label = 名字（无 `/`）· cwd = 仓根
#   B 合法 · 主仓         ⇒ 名字 `rd-be@alpha` · tab label `main/rd-be@alpha` · cwd = 主仓 · ws label = alpha
#   C 合法 · `@api`       ⇒ 名字 `rd-be@api` · cwd = api · **同一** workspace（wsid 等于 B）· tab label `api/rd-be@api`
#   D `@alpha`（= slug）  ⇒ 主仓语义（非 unknown / 非 linked）：rc=0 · cwd = 主仓 · 前缀 `main/`
#   E `@nope` 未命中      ⇒ rc≠0 · stderr 含全部 code + slug · 无「已拉起」· pane 数不变
#   F 各字段非法（逐项）  ⇒ 每项 rc≠0 + `fleet.yaml:<行号>` + 零 pane（解析期就拒，不进相位 2）
#   G `fleet.yaml` + `fleet-scope` ⇒ 同值放行（放置 = 该值）/ 分歧 fail loud 点名两文件两值 + 零 pane
#   H `--fleet beta` vs manifest(slug alpha) ⇒ fail loud 点名两值 + 零 pane；`--fleet alpha` ⇒ rc=0
#   I full > 48          ⇒ fail loud 点明够不着的段（core 32 + '@' + code 16 = 49），**不**自动截短 code
#   J `close rd-fe@api`  ⇒ 回收行 `@` 后 = api 物理路径 · 该 pane 消失（期望仓回落 = manifest code → path）
#   K 跨仓同 code 并列   ⇒ herdr：拒绝列候选、零回收（tmux 无 label 契约 ⇒ NOTE backend-no-signal）
#   L 运行期改坏 manifest ⇒ 下一次调用即 fail loud（无落盘缓存）、零 pane
#   静态：`.agents/fleet.yaml` 字面读点 ≤1（AC10 单源）
#
# 夹具 hermetic：临时主仓 `fx39-main`（manifest 源）+ `fx39-api` / `fx39-web` + `fx39-plain`（无 manifest）；
#   会话名唯一派生（`T4C39$$` 类，**禁** `pm` 等宿主真名，防 #145 回潮）；pane 一律走 `be_*` 门面。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node
BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH

HAS_TABS=0
[ "$BE_NAME" = "herdr" ] && HAS_TABS=1
if [ "$HAS_TABS" = "0" ]; then
  t4_note backend-no-signal "tab 分组（<组前缀>/<name>）只在 herdr tab 模型上有信号：tmux 无 tab（rc / 名字 / cwd 断言照跑；workspace 放置面亦不可达）"
fi

FLEET_MAIN="$T4_ROOT/.agents/scripts/nao-fleet.sh"
LAB="$T4_CACHE_DIR/lab39-$$"
MAIN="$LAB/fx39-main"
API="$LAB/fx39-api"
WEB="$LAB/fx39-web"
PLAIN="$LAB/fx39-plain"
BAD="$LAB/fx39-bad"
T39="T4C39$$"
LONG_CODE="averylongcode16c"          # 16 字符（scope 上限）；用于 full > 48 的撞线

# ---- 硬护栏：夹具根不得落 git 仓内（否则 manifest 源 / toplevel 锚被污染）----
if command -v git >/dev/null 2>&1; then
  t4_assert_eq "" "$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)" \
    "前提：夹具缓存根不在任何 git 仓内"
fi

# ---- 夹具 ----
mkdir -p "$LAB" "$LAB/bin" "$MAIN/.agents" "$API" "$WEB" "$PLAIN" "$BAD/.agents" \
  || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
# pi 桩（tmux 后端）：记录 argv 后长驻，绝不拉起真 pi 会话（herdr 替身不执行该桩）
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
exec sleep 900
SH
chmod +x "$LAB/bin/pi"
export PATH="$LAB/bin:$PATH"
: > "$LAB/not-a-dir"                   # path 非目录夹具
ln -sfn /etc "$BAD/esc"                # symlink 间接逃逸夹具
write_manifest() { printf '%s\n' "$1" > "$MAIN/.agents/fleet.yaml"; }
write_manifest "#
slug: alpha
repos:
  - code: api
    path: ../fx39-api
  - code: 'web'
    path: ../fx39-web
  - code: $LONG_CODE
    path: ../fx39-api"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab39" || { t4_bad "be_init 失败"; t4_exit; }
# 宽口起场（只影响 tmux 几何）：本用例跨 A–L 多态会多次 spawn，默认 80 列下 split-window 会耗尽空间
be_start_server 400 80 || { t4_bad "夹具：be_start_server 失败"; t4_exit; }
be_ensure_scene || { t4_bad "夹具：调用方 scene 建立失败"; t4_exit; }

# ---------------------------------------------------------------- 判据工具（单字段 + 计数，禁「整段包含」）
pl() { be_herdr "$BE_SESSION" pane list 2>/dev/null; }
wl() { be_herdr "$BE_SESSION" workspace list 2>/dev/null; }
tl() { be_herdr "$BE_SESSION" tab list 2>/dev/null; }
split_objs() { sed 's/},{/}\n{/g'; }
fld() { sed -nE "s/.*\"$2\":\"([^\"]+)\".*/\1/p" <<< "${1:-}" | head -1; }
obj_for() { split_objs <<< "$1" | grep -F "\"$2\":\"$3\"" | head -1; }
ws_id_by_label() { fld "$(obj_for "$(wl)" label "${1:-}")" workspace_id; }
ws_label_count() { split_objs <<< "$(wl)" | grep -cF "\"label\":\"${1:-}\"" || true; }
pane_ws_by_name() { fld "$(obj_for "$(pl)" label "${1:-}")" workspace_id; }
tab_label_of_name() { # <会话名> → 该 pane 所在 tab 的 label
  local o t
  o="$(obj_for "$(pl)" label "$1")"; t="$(fld "$o" tab_id)"
  fld "$(obj_for "$(tl)" tab_id "$t")" label
}
phys() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
pane_of() { # <会话名> → pane_id（tmux 的 pane_start_command 带 printf %q 反斜杠 ⇒ 先剥再比）
  local want="$1" p c
  while IFS=$'\t' read -r p _; do
    [ -n "$p" ] || continue
    c="$(be_pane_cmdline "$p" 2>/dev/null | tr -d '\\')"
    case "$c" in *"--name $want"*) printf '%s' "$p"; return 0 ;; esac
  done < <(be_panes 2>/dev/null)
  return 0
}
pane_count() { be_pane_count 2>/dev/null || printf '0'; }
# 身份面：herdr = pane.label 精确等于会话名；tmux 无标题契约（桩 pi 不写 OSC）⇒ 以 argv `--name` 为身份证据
name_present() { # <会话名> → 0 在位 / 1 不在
  local n="$1" p
  p="$(pane_of "$n")"; [ -n "$p" ] || return 1
  if [ "$HAS_TABS" = "1" ]; then [ "$(be_pane_label "$p" 2>/dev/null)" = "$n" ] || return 1; fi
  return 0
}

# 唯一运行入口 = `be_run_fleet`（单源清单清 HERDR_* 再注入本实验场句柄）
fleet() { be_run_fleet "$LAB" "$@"; }
fleet_in() { local d="$1"; shift; be_run_fleet "$d" "$@"; }

l39_exit_trap() {
  local rc=$?
  be_teardown >/dev/null 2>&1 || true
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap l39_exit_trap EXIT

# ================================================================ 静态：manifest 读点单源（AC10）
t4_assert_eq "1" "$(grep -cF '"$repo/.agents/fleet.yaml"' "$FLEET_MAIN" || true)" \
  "静态 AC10：「.agents/fleet.yaml」路径只在 fleet_manifest_load 内拼一次（其余调用点复用该函数）"

# ================================================================ A 无 manifest（逐字旧行为）
fleet_in "$PLAIN" ensure rd-be
t4_assert_eq "0" "$BE_RC" "A ensure rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
A_NAME="rd-be@fx39-plain"
A_PANE="$(pane_of "$A_NAME")"
t4_assert_eq "0" "$(name_present "$A_NAME"; echo $?)" "A 会话名 = rd-be@<仓 slug>（herdr=pane.label / tmux=argv --name）"
t4_assert_eq "$(phys "$PLAIN")" "$(phys "$(be_pane_cwd "${A_PANE:-none}" 2>/dev/null || true)")" "A pane cwd = 仓根"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "$A_NAME" "$(tab_label_of_name "$A_NAME")" "A tab label = 名字（无 code/ 前缀 ⇒ 无 manifest 不加组前缀）"
  t4_assert_not_contains "$(tab_label_of_name "$A_NAME")" "/" "A tab label 不含 '/'（组前缀只在 manifest 仓出现）"
fi

# ================================================================ B 合法 · 主仓
fleet_in "$MAIN" ensure rd-be
t4_assert_eq "0" "$BE_RC" "B ensure rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
B_PANE="$(pane_of "rd-be@alpha")"
t4_assert_eq "0" "$(name_present "rd-be@alpha"; echo $?)" "B 名字 = rd-be@<slug>（主仓 scope = slug）"
t4_assert_eq "$(phys "$MAIN")" "$(phys "$(be_pane_cwd "${B_PANE:-none}" 2>/dev/null || true)")" "B pane cwd = 主仓"
if [ "$HAS_TABS" = "1" ]; then
  B_WS="$(ws_id_by_label alpha)"
  t4_assert_eq "1" "$(ws_label_count alpha)" "B 放置键 = manifest slug（label=alpha 的 workspace 恰 1 个）"
  t4_assert_eq "$B_WS" "$(pane_ws_by_name "rd-be@alpha")" "B pane 落在 label=alpha 的 workspace"
  t4_assert_eq "main/rd-be@alpha" "$(tab_label_of_name "rd-be@alpha")" "B tab label = main/<name>（主仓组前缀固定 main）"
else
  B_WS=""
fi

# ================================================================ C 合法 · @api（同一 workspace 跨仓派生）
fleet_in "$MAIN" ensure rd-be@api
t4_assert_eq "0" "$BE_RC" "C ensure rd-be@api rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
C_PANE="$(pane_of "rd-be@api")"
t4_assert_eq "0" "$(name_present "rd-be@api"; echo $?)" "C 名字 = rd-be@<code>"
t4_assert_eq "$(phys "$API")" "$(phys "$(be_pane_cwd "${C_PANE:-none}" 2>/dev/null || true)")" "C pane cwd = api 仓物理路径"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "$B_WS" "$(pane_ws_by_name "rd-be@api")" "C 与 B 同一 workspace（放置键恒为 slug，不因目标仓新开 workspace）"
  t4_assert_eq "1" "$(ws_label_count alpha)" "C 不新增 workspace（label=alpha 仍恰 1 个）"
  t4_assert_eq "api/rd-be@api" "$(tab_label_of_name "rd-be@api")" "C tab label = api/<name>（组前缀 = code）"
  # M5（#139）：status 读面 = fleet=<slug> + code=<code> 两字段（herdr 侧 scoped 行才是证据面）
  fleet_in "$MAIN" status
  t4_assert_eq "0" "$BE_RC" "M5 status rc=0"
  t4_assert_contains "$BE_OUT_ANSI" "·fleet=alpha ·code=api" "M5 status 对 code scope 同时给出 fleet= 与 code=（不可读才印 ?）"
fi

# ================================================================ D @alpha（= slug）⇒ 主仓语义
fleet_in "$MAIN" ensure qa@alpha
t4_assert_eq "0" "$BE_RC" "D ensure qa@alpha rc=0（slug 当主仓、不当 unknown/linked）"
t4_assert_eq "$(phys "$MAIN")" "$(phys "$(be_pane_cwd "$(pane_of "qa@alpha")" 2>/dev/null || true)")" "D pane cwd = 主仓"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "main/qa@alpha" "$(tab_label_of_name "qa@alpha")" "D tab 前缀 = main"
fi

# ================================================================ E @nope 未命中 ⇒ fail loud 列候选
N_BEFORE="$(pane_count)"
fleet_in "$MAIN" ensure rd-be@nope
t4_assert_ne "0" "$BE_RC" "E ensure rd-be@nope rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "api" "E stderr 列出可用 code（api）"
t4_assert_contains "$BE_ERR_ANSI" "web" "E stderr 列出可用 code（web）"
t4_assert_contains "$BE_ERR_ANSI" "alpha" "E stderr 点名舰队 slug（alpha）"
t4_assert_not_contains "$BE_OUT_ANSI" "已拉起" "E 无「已拉起」行（零 pane）"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "E pane 数不变（BR6 零副作用）"

# ================================================================ F 各字段非法（逐项：rc≠0 + 文件:行号 + 零 pane）
f_case() { # <标签> <manifest 内容>
  printf '%s\n' "$2" > "$BAD/.agents/fleet.yaml"
  local before; before="$(pane_count)"
  fleet_in "$BAD" ensure rd-be
  t4_assert_ne "0" "$BE_RC" "F $1：rc≠0"
  t4_assert_match "$BE_ERR_ANSI" 'fleet\.yaml:[0-9]+' "F $1：报错点名 文件:行号"
  t4_assert_eq "$before" "$(pane_count)" "F $1：零 pane"
}
f_case "缺 slug"            "repos:
  - code: api
    path: ../fx39-api"
f_case "未知键"             "slug: alpha
bogus: 1"
f_case "code 重复"          "slug: alpha
repos:
  - code: api
    path: ../fx39-api
  - code: api
    path: ../fx39-web"
f_case "code=main（保留）"   "slug: alpha
repos:
  - code: main
    path: ../fx39-api"
f_case "code==slug"         "slug: alpha
repos:
  - code: alpha
    path: ../fx39-api"
f_case "code 非法字符"       "slug: alpha
repos:
  - code: API
    path: ../fx39-api"
f_case "code >16"           "slug: alpha
repos:
  - code: abcdefghijklmnopq
    path: ../fx39-api"
f_case "path 不存在"         "slug: alpha
repos:
  - code: api
    path: ../fx39-missing"
f_case "path 非目录"         "slug: alpha
repos:
  - code: api
    path: ../not-a-dir"
f_case "symlink 间接逃逸"    "slug: alpha
repos:
  - code: esc
    path: esc"
f_case "slug 非法（超 16）"  "slug: thisslugiswaytoolong
repos:"

# ================================================================ G fleet.yaml + fleet-scope 共存
printf 'alpha\n' > "$MAIN/.agents/fleet-scope"
fleet_in "$MAIN" ensure uiux-designer
t4_assert_eq "0" "$BE_RC" "G 同值共存：rc=0（不因两来源并存拒绝）"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "$(ws_id_by_label alpha)" "$(pane_ws_by_name "uiux-designer@alpha")" "G 同值：放置 = 该值（label=alpha）"
fi
printf 'beta\n' > "$MAIN/.agents/fleet-scope"
N_BEFORE="$(pane_count)"
fleet_in "$MAIN" ensure rd-infra
t4_assert_ne "0" "$BE_RC" "G 分歧：rc≠0（同权来源禁静默取一）"
t4_assert_contains "$BE_ERR_ANSI" "beta" "G 分歧：点名 fleet-scope 值（beta）"
t4_assert_contains "$BE_ERR_ANSI" "alpha" "G 分歧：点名 manifest slug（alpha）"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "G 分歧：零 pane"
rm -f "$MAIN/.agents/fleet-scope"

# ================================================================ H --fleet ≠ manifest.slug ⇒ fail loud
N_BEFORE="$(pane_count)"
fleet_in "$MAIN" ensure --fleet beta rd-fe
t4_assert_ne "0" "$BE_RC" "H --fleet beta + manifest(alpha)：rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "beta" "H 点名 --fleet 值"
t4_assert_contains "$BE_ERR_ANSI" "alpha" "H 点名 manifest slug"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "H 零 pane"
fleet_in "$MAIN" ensure --fleet alpha rd-infra
t4_assert_eq "0" "$BE_RC" "H --fleet alpha（= slug）：rc=0"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "main/rd-infra@alpha" "$(tab_label_of_name "rd-infra@alpha")" "H 放行时仍用主仓组前缀"
fi

# ================================================================ I 三预算：full > 48 必 fail loud（禁截短 code）
I_TASK="T4539ABCDEFGHIJKLM"           # 18 字符 ⇒ core = arch-designer-<18> = 32；32+1+16 = 49 > 48
N_BEFORE="$(pane_count)"
fleet_in "$MAIN" ensure "arch-designer@$LONG_CODE" --task "$I_TASK"
t4_assert_ne "0" "$BE_RC" "I full > 48：rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "48" "I 报错点名总长预算（48）"
t4_assert_not_contains "$BE_OUT_ANSI" "已拉起" "I 无「已拉起」（零 pane）"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "I 零 pane"

# ================================================================ J close rd-fe@api（期望仓回落 = manifest code → path）
JP="$(be_new_pane "$API")" || { t4_bad "J 夹具：be_new_pane 失败"; }
be_fixture_session "$JP" "rd-fe@api" "fx39-api" || t4_bad "J 夹具：fixture session 未就绪"
fleet_in "$MAIN" close "rd-fe@api"
t4_assert_eq "0" "$BE_RC" "J close rd-fe@api rc=0"
t4_assert_contains "$BE_OUT_ANSI" "已回收 rd-fe@api" "J 回收行在位"
t4_assert_contains "$BE_OUT_ANSI" "@ $(phys "$API")" "J 回收行 @ 后字段 = api 物理路径（期望仓回落自 manifest）"
t4_assert_eq "1" "$(be_pane_alive "$JP" >/dev/null 2>&1; echo $?)" "J 该 pane 已消失"
t4_assert_not_contains "$BE_OUT_ANSI" "未运行" "J 不谎报「未运行」"

# ================================================================ K 跨仓同 code 并列（不猜）
K1="$(be_new_pane "$API")"; K2="$(be_new_pane "$WEB")"
be_fixture_session "$K1" "qa@api" "fx39-api" || t4_bad "K 夹具：api 侧会话未就绪"
be_fixture_session "$K2" "qa@api" "fx39-web" || t4_bad "K 夹具：web 侧会话未就绪"
if [ "$HAS_TABS" = "1" ]; then
  N_BEFORE="$(pane_count)"
  fleet_in "$MAIN" close "qa@api"
  t4_assert_ne "0" "$BE_RC" "K 同名跨仓并列：rc≠0（不取首条）"
  t4_assert_contains "$BE_ERR_ANSI" "同名 label" "K 因由绑定「同名 label 命中多个 pane」（禁任何拒绝都吃绿）"
  t4_assert_not_contains "$BE_OUT_ANSI" "未运行" "K 不谎报「未运行」"
  t4_assert_eq "$N_BEFORE" "$(pane_count)" "K 零回收（两 pane 均存活）"
else
  t4_note backend-no-signal "K 并列拒绝面只在 herdr「同名 label >1」句柄层有信号：tmux 无 label 契约（取首条 = 既有语义，cases/38 g2 同口径）"
fi
be_kill_pane "$K1"; be_kill_pane "$K2"

# ================================================================ L 运行期改坏 manifest ⇒ 下一次调用即 fail loud
N_BEFORE="$(pane_count)"
write_manifest "slug: alpha
bogus: 1"
fleet_in "$MAIN" ensure rd-fe
t4_assert_ne "0" "$BE_RC" "L 改坏后下一次调用 rc≠0（不沿用上次解析结果 ⇒ 无落盘缓存）"
t4_assert_match "$BE_ERR_ANSI" 'fleet\.yaml:[0-9]+' "L 报错点名 文件:行号"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "L 零 pane"

t4_exit
