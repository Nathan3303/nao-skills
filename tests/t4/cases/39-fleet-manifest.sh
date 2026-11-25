#!/usr/bin/env bash
# 用例 39 —— 联动仓 manifest（T554 降级为「仓代号 → 路径」映射）
#
# 判据：docs/reports/554-lite-spec.md §四「39」迁移清单
# 旧→新（本文件断言口径）：
#   A/B/C/D 会话名去 `@<fleet/@code>`；B ws label = 仓基键（fx39-main）；C 改**独立 ws**（fx39-api）
#   tab 组前缀 `main/`|`api/` 退役（tab label = 名字）
#   E 未命中仍 fail loud（列 code；不再有 slug）
#   F「缺 slug」「code==slug」「slug 超 16」退役（改弃用 warn 忽略），其余 8 条字段非法保留
#   G/H 两来源分歧由 fail loud **反转为** warn + 忽略（放置恒 = 仓基键）
#   I 名长：改为 32 字 role + 长 `(task)` 使 name>48 ⇒ fail loud
#   J/K 旧形全名只读（AC6；回收/并列拒绝口径不变）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node
BE_NAME="herdr"   # T555：唯一后端（be_backend 已删）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
HAS_TABS=0
[ "$BE_NAME" = "herdr" ] && HAS_TABS=1
if [ "$HAS_TABS" = "0" ]; then
  t4_note backend-no-signal "workspace/tab 是 herdr 结构面：tmux 侧只跑 rc/名字/cwd 断言（ws/tab 断言门控）"
fi

FLEET_MAIN="$T4_ROOT/.agents/scripts/nao-fleet.sh"
FLEET_BUNDLE="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"   # T567-A：只读内容断言按文件集
LAB="$T4_CACHE_DIR/lab39-$$"
MAIN="$LAB/fx39-main"; API="$LAB/fx39-api"; WEB="$LAB/fx39-web"; PLAIN="$LAB/fx39-plain"; BAD="$LAB/fx39-bad"
T39="T4C39$$"
if command -v git >/dev/null 2>&1; then
  t4_assert_eq "" "$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)" "前提：夹具缓存根不在任何 git 仓内"
fi
mkdir -p "$LAB/bin" "$MAIN/.agents" "$API" "$WEB" "$PLAIN" "$BAD/.agents" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
cat > "$LAB/bin/pi" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
exec sleep 900
SH
chmod +x "$LAB/bin/pi"; export PATH="$LAB/bin:$PATH"
: > "$LAB/not-a-dir"; ln -sfn /etc "$BAD/esc"
write_manifest() { printf '%s\n' "$1" > "$MAIN/.agents/fleet.yaml"; }
write_manifest "repos:
  - code: api
    path: ../fx39-api
  - code: 'web'
    path: ../fx39-web"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab39" || { t4_bad "be_init 失败"; t4_exit; }
be_start_server 400 80 || { t4_bad "be_start_server 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }

pl() { be_herdr "$BE_SESSION" pane list 2>/dev/null; }
wl() { be_herdr "$BE_SESSION" workspace list 2>/dev/null; }
tl() { be_herdr "$BE_SESSION" tab list 2>/dev/null; }
split_objs() { sed 's/},{/}\n{/g'; }
fld() { sed -nE "s/.*\"$2\":\"([^\"]+)\".*/\\1/p" <<< "${1:-}" | head -1; }
obj_for() { split_objs <<< "$1" | grep -F "\"$2\":\"$3\"" | head -1; }
ws_id_by_label() { fld "$(obj_for "$(wl)" label "${1:-}")" workspace_id; }
ws_label_count() { split_objs <<< "$(wl)" | grep -cF "\"label\":\"${1:-}\"" || true; }
pane_ws_by_name() { fld "$(obj_for "$(pl)" label "${1:-}")" workspace_id; }
tab_label_of_name() { local o t; o="$(obj_for "$(pl)" label "$1")"; t="$(fld "$o" tab_id)"; fld "$(obj_for "$(tl)" tab_id "$t")" label; }
phys() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
pane_of() { local want="$1" p c; while IFS=$'\t' read -r p _; do [ -n "$p" ] || continue; c="$(be_pane_cmdline "$p" 2>/dev/null | tr -d '\\')"; case "$c" in *"--name $want"*) printf '%s' "$p"; return 0 ;; esac; done < <(be_panes 2>/dev/null); }
pane_count() { be_pane_count 2>/dev/null || printf '0'; }
name_present() { local n="$1" p; p="$(pane_of "$n")"; [ -n "$p" ] || return 1; if [ "$HAS_TABS" = "1" ]; then [ "$(be_pane_label "$p" 2>/dev/null)" = "$n" ] || return 1; fi; return 0; }
fleet() { be_run_fleet "$LAB" "$@"; }
fleet_in() { local d="$1"; shift; be_run_fleet "$d" "$@"; }
l39_exit_trap() { local rc=$?; be_teardown >/dev/null 2>&1 || true; trap - EXIT; if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi; exit "$rc"; }
trap l39_exit_trap EXIT

t4_assert_eq "1" "$(grep -cF '"$repo/.agents/fleet.yaml"' "$FLEET_BUNDLE" || true)" "静态 AC10：manifest 路径只在 fleet_manifest_load 内拼一次"

# ================================================================ A 无 manifest
fleet_in "$PLAIN" ensure rd-be
t4_assert_eq "0" "$BE_RC" "A ensure rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
t4_assert_eq "0" "$(name_present "rd-be"; echo $?)" "A 名字 = rd-be（无 @ / 无位置段）"
t4_assert_eq "$(phys "$PLAIN")" "$(phys "$(be_pane_cwd "$(pane_of rd-be)" 2>/dev/null || true)")" "A pane cwd = 仓根"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "1" "$(ws_label_count "fx39-plain")" "A ws label = 仓基键（fx39-plain）"
  t4_assert_eq "rd-be" "$(tab_label_of_name rd-be)" "A tab label = 名字（无组前缀）"
fi

# ================================================================ B 主仓（manifest + @main）
fleet_in "$MAIN" ensure rd-fe
t4_assert_eq "0" "$BE_RC" "B ensure rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
t4_assert_eq "0" "$(name_present "rd-fe"; echo $?)" "B 名字 = rd-fe"
t4_assert_eq "$(phys "$MAIN")" "$(phys "$(be_pane_cwd "$(pane_of rd-fe)" 2>/dev/null || true)")" "B pane cwd = 主仓"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "1" "$(ws_label_count "fx39-main")" "B 放置键 = 仓基键（fx39-main）"
  t4_assert_eq "$(ws_id_by_label fx39-main)" "$(pane_ws_by_name rd-fe)" "B pane 落 fx39-main"
  t4_assert_eq "rd-fe" "$(tab_label_of_name rd-fe)" "B tab label = rd-fe（组前缀退役）"
fi

# ================================================================ C @api（独立 workspace）
fleet_in "$MAIN" ensure qa@api
t4_assert_eq "0" "$BE_RC" "C ensure qa@api rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
t4_assert_eq "$(phys "$API")" "$(phys "$(be_pane_cwd "$(pane_of qa)" 2>/dev/null || true)")" "C pane cwd = api 仓"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "1" "$(ws_label_count "fx39-api")" "C @api 建独立 ws（fx39-api）"
  t4_assert_eq "$(ws_id_by_label fx39-api)" "$(pane_ws_by_name qa)" "C pane 落 fx39-api"
  t4_assert_eq "qa" "$(tab_label_of_name qa)" "C tab label = qa"
  fleet_in "$MAIN" status
  t4_assert_eq "0" "$BE_RC" "M5 status rc=0"
fi

# ================================================================ D @main（主仓别名）
fleet_in "$MAIN" ensure pm@main
t4_assert_eq "0" "$BE_RC" "D ensure pm@main rc=0"
t4_assert_eq "$(phys "$MAIN")" "$(phys "$(be_pane_cwd "$(pane_of pm)" 2>/dev/null || true)")" "D pane cwd = 主仓"
if [ "$HAS_TABS" = "1" ]; then t4_assert_eq "pm" "$(tab_label_of_name pm)" "D tab label = pm"; fi

# ================================================================ E @nope
N_BEFORE="$(pane_count)"
fleet_in "$MAIN" ensure rd-be@nope
t4_assert_ne "0" "$BE_RC" "E ensure rd-be@nope rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "api" "E 列出可用 code（api）"
t4_assert_contains "$BE_ERR_ANSI" "web" "E 列出可用 code（web）"
t4_assert_not_contains "$BE_OUT_ANSI" "已拉起" "E 无「已拉起」行"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "E pane 数不变（零副作用）"

# ================================================================ F 非法字段（8 条保留；3 条退役）
f_case() {
  printf '%s\n' "$2" > "$BAD/.agents/fleet.yaml"
  local before; before="$(pane_count)"
  fleet_in "$BAD" ensure rd-be
  t4_assert_ne "0" "$BE_RC" "F $1：rc≠0"
  t4_assert_match "$BE_ERR_ANSI" 'fleet\.yaml:[0-9]+' "F $1：点名 文件:行号"
  t4_assert_eq "$before" "$(pane_count)" "F $1：零 pane"
}
f_case "未知键" "bogus: 1"
f_case "code 重复" "repos:
  - code: api
    path: ../fx39-api
  - code: api
    path: ../fx39-web"
f_case "code=main（保留）" "repos:
  - code: main
    path: ../fx39-api"
f_case "code 非法字符" "repos:
  - code: API
    path: ../fx39-api"
f_case "code >16" "repos:
  - code: abcdefghijklmnopq
    path: ../fx39-api"
f_case "path 不存在" "repos:
  - code: api
    path: ../fx39-missing"
f_case "path 非目录" "repos:
  - code: api
    path: ../not-a-dir"
f_case "symlink 间接逃逸" "repos:
  - code: esc
    path: esc"

# F 退役：slug 由 fail → warn + 忽略（rc=0、放置 = 仓基键）
printf 'slug: alpha\nrepos:\n' > "$BAD/.agents/fleet.yaml"
fleet_in "$BAD" ensure rd-be
t4_assert_eq "0" "$BE_RC" "F 退役：slug 字段 → rc=0（弃用忽略）"
t4_assert_eq "1" "$(grep -c '弃用：fleet.yaml 的 slug' <<< "$BE_ERR_ANSI" || true)" "F 退役：slug 恰一行弃用 warn"

# ================================================================ G 两来源共存（忽略）
printf 'alpha\n' > "$MAIN/.agents/fleet-scope"
fleet_in "$MAIN" ensure uiux-designer
t4_assert_eq "0" "$BE_RC" "G manifest+fleet-scope 共存：rc=0"
t4_assert_eq "1" "$(grep -c '弃用：.agents/fleet-scope' <<< "$BE_ERR_ANSI" || true)" "G 文件来源恰一行弃用 warn"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "$(ws_id_by_label fx39-main)" "$(pane_ws_by_name uiux-designer)" "G 放置仍 = 仓基键（fx39-main）"
fi
printf 'beta\n' > "$MAIN/.agents/fleet-scope"
fleet_in "$MAIN" ensure rd-infra
t4_assert_eq "0" "$BE_RC" "G 旧「分歧 fail loud」退役：rc=0"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "$(ws_id_by_label fx39-main)" "$(pane_ws_by_name rd-infra)" "G 分歧也被忽略（放置 = 仓基键）"
fi
rm -f "$MAIN/.agents/fleet-scope"

# ================================================================ H --fleet（忽略）
fleet_in "$MAIN" ensure --fleet beta arch-designer
t4_assert_eq "0" "$BE_RC" "H --fleet beta：rc=0（弃用忽略）"
t4_assert_eq "1" "$(grep -c '弃用：--fleet' <<< "$BE_ERR_ANSI" || true)" "H --fleet 恰一行弃用 warn"
if [ "$HAS_TABS" = "1" ]; then
  t4_assert_eq "$(ws_id_by_label fx39-main)" "$(pane_ws_by_name arch-designer)" "H 放行后放置 = 仓基键"
  t4_assert_eq "arch-designer" "$(tab_label_of_name arch-designer)" "H tab label = arch-designer"
fi

# ================================================================ I 名长（32 字 role + 长 task ⇒ >48）
I_TASK="$(printf 'T%.0s' $(seq 1 40))"
N_BEFORE="$(pane_count)"
fleet_in "$MAIN" ensure --task "$I_TASK" arch-designer
t4_assert_ne "0" "$BE_RC" "I name>48：rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "48" "I 点名总长预算（48）"
t4_assert_not_contains "$BE_OUT_ANSI" "已拉起" "I 无「已拉起」"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "I 零 pane"

# ================================================================ J 旧形全名 close（只读面）
JP="$(be_new_pane "$API")" || t4_bad "J 夹具：be_new_pane 失败"
be_fixture_session "$JP" "rd-fe@api" "fx39-api" || t4_bad "J 夹具：fixture 未就绪"
fleet_in "$MAIN" close "rd-fe@api"
t4_assert_eq "0" "$BE_RC" "J close rd-fe@api rc=0（legacy 只读）"
t4_assert_contains "$BE_OUT_ANSI" "已回收 rd-fe@api" "J 回收行在位"
t4_assert_contains "$BE_OUT_ANSI" "@ $(phys "$API")" "J 回收行 @ = api 物理路径（manifest code→path 回落）"
t4_assert_eq "1" "$(be_pane_alive "$JP" >/dev/null 2>&1; echo $?)" "J pane 已消失"
t4_assert_not_contains "$BE_OUT_ANSI" "未运行" "J 不谎报「未运行」"

# ================================================================ K 旧形并列（不猜）
K1="$(be_new_pane "$API")"; K2="$(be_new_pane "$WEB")"
be_fixture_session "$K1" "qa@api" "fx39-api" || t4_bad "K 夹具：api 侧未就绪"
be_fixture_session "$K2" "qa@api" "fx39-web" || t4_bad "K 夹具：web 侧未就绪"
if [ "$HAS_TABS" = "1" ]; then
  N_BEFORE="$(pane_count)"
  fleet_in "$MAIN" close "qa@api"
  t4_assert_ne "0" "$BE_RC" "K 同名跨仓并列：rc≠0（不取首条）"
  t4_assert_contains "$BE_ERR_ANSI" "同名 label" "K 因由绑定「同名 label 命中多个 pane」"
  t4_assert_not_contains "$BE_OUT_ANSI" "未运行" "K 不谎报「未运行」"
  t4_assert_eq "$N_BEFORE" "$(pane_count)" "K 零回收（两 pane 均存活）"
else
  t4_note backend-no-signal "K 并列拒绝面只在 herdr「同名 label >1」句柄层有信号（tmux 无 label 契约）"
fi
be_kill_pane "$K1"; be_kill_pane "$K2"

# ================================================================ L 运行期改坏 manifest
N_BEFORE="$(pane_count)"
write_manifest "bogus: 1"
fleet_in "$MAIN" ensure rd-fe
t4_assert_ne "0" "$BE_RC" "L 改坏后下一次调用 rc≠0（无落盘缓存）"
t4_assert_match "$BE_ERR_ANSI" 'fleet\.yaml:[0-9]+' "L 点名 文件:行号"
t4_assert_eq "$N_BEFORE" "$(pane_count)" "L 零 pane"

t4_exit
