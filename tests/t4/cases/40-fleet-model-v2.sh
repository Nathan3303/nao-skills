#!/usr/bin/env bash
# 用例 40 —— 舰队模型 v2 的 13 态 wired（T554 · 判据 §三）
#   S1 单仓首拉 / S2 同 ws 追加 / S3 槽位递增 / S4 N>9 与文法 / S5 基键冲突 / S6 @code /
#   S7 未命中 / S8 default 读 / S9 default 破坏性动作 / S10 护栏（NOTE：由 30/31/37/38 覆盖）/
#   S11 legacy 回收 / S12 弃用 warn / S13 status ego
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
if [ "$BE_NAME" != "herdr" ]; then
  t4_note backend-gate "13 态的主判据依赖 workspace/tab/default session 结构面（herdr）；tmux 侧由 28/33/37/38 的共享断言覆盖"
  t4_exit
fi

LAB="$T4_CACHE_DIR/lab40-$$"
RA="$LAB/fx40-api"; RB="$LAB/fx40-web"; RC="$LAB/fx40-plain"
mkdir -p "$RA" "$RB" "$RC" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
printf 'repos:\n  - code: web\n    path: ../fx40-web\n' > "$RA/.agents/fleet.yaml" 2>/dev/null || {
  mkdir -p "$RA/.agents"; printf 'repos:\n  - code: web\n    path: ../fx40-web\n' > "$RA/.agents/fleet.yaml"; }

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab40" || { t4_bad "be_init 失败"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败"; t4_exit; }

pj() { be_herdr "$BE_SESSION" pane list 2>/dev/null; }
wj() { be_herdr "$BE_SESSION" workspace list 2>/dev/null; }
tj() { be_herdr "$BE_SESSION" tab list 2>/dev/null; }
so() { sed 's/},{/}\n{/g'; }
fld() { sed -nE "s/.*\"$2\":\"([^\"]+)\".*/\\1/p" <<< "${1:-}" | head -1; }
obj_for() { so <<< "$1" | grep -F "\"$2\":\"$3\"" | head -1; }
ws_by_label() { fld "$(obj_for "$(wj)" label "${1:-}")" workspace_id; }
ws_n() { so <<< "$(wj)" | grep -cF "\"label\":\"${1:-}\"" || true; }
pane_ws() { fld "$(obj_for "$(pj)" label "${1:-}")" workspace_id; }
pane_cwd() { fld "$(obj_for "$(pj)" label "${1:-}")" cwd; }
pane_cwd_by_ws() { fld "$(obj_for "$(pj)" workspace_id "$1")" cwd; }
tab_label() { local o t; o="$(obj_for "$(pj)" label "$1")"; t="$(fld "$o" tab_id)"; fld "$(obj_for "$(tj)" tab_id "$t")" label; }
phys() { ( cd "$1" 2>/dev/null && pwd -P ) || printf '%s' "$1"; }
fleet() { be_run_fleet "$LAB" "$@"; }
fin() { local d="$1"; shift; be_run_fleet "$d" "$@"; }

t40_exit_trap() { local rc=$?; be_teardown >/dev/null 2>&1 || true; trap - EXIT; if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi; exit "$rc"; }
trap t40_exit_trap EXIT

# S1 单仓首拉
fin "$RA" ensure pm
t4_assert_eq "0" "$BE_RC" "S1 ensure pm rc=0（T4_ERR=$(printf '%s' "$BE_ERR_ANSI" | head -1)）"
t4_assert_eq "1" "$(ws_n "fx40-api")" "S1 ws label = 仓基键（fx40-api）"
t4_assert_eq "$(ws_by_label "fx40-api")" "$(pane_ws pm)" "S1 pane 落该 ws"
t4_assert_eq "$(phys "$RA")" "$(pane_cwd pm)" "S1 pane cwd = 仓根"
t4_assert_eq "pm" "$(tab_label pm)" "S1 tab label = pm"

# S2 同 ws 追加
fin "$RA" ensure rd-be
t4_assert_eq "0" "$BE_RC" "S2 ensure rd-be rc=0"
t4_assert_eq "1" "$(ws_n "fx40-api")" "S2 同 ws 追加（label 仍 1 个）"
t4_assert_eq "$(ws_by_label "fx40-api")" "$(pane_ws rd-be)" "S2 rd-be 落同一 ws"
t4_assert_eq "rd-be" "$(tab_label rd-be)" "S2 tab label = rd-be"

# S3 槽位递增 / 派生复用
fin "$RA" ensure pm
t4_assert_eq "0" "$BE_RC" "S3 二次 ensure pm rc=0"
t4_assert_eq "pm2" "$(be_pane_by_name pm2 >/dev/null 2>&1 && echo pm2 || true)" "S3 第二个 pm 名字 = pm2"
fin "$RA" ensure --task T554 pm
t4_assert_eq "0" "$BE_RC" "S3 带任务 ensure rc=0"
t4_assert_eq "pm2(T554)" "$(be_pane_by_name "pm2(T554)" >/dev/null 2>&1 && echo "pm2(T554)" || true)" "S3 派生复用槽位 2（pm2(T554)）"

# S4 文法 / N>9：非法串一律拒绝
for bad in pm1 pm0 pm10 pm2x "arch-designer(T554" "arch-designerT554)" "arch-designer((T554))" "arch-designer(T5)4"; do
  fin "$RA" ensure "$bad"
  t4_assert_ne "0" "$BE_RC" "S4 非法名 $bad ⇒ rc≠0"
done

# S4b 槽位耗尽：2..9 全占 ⇒ fail loud 指路 close、零 pane（S4 的字面非法之外的结构面）
SLOT_REPO="$LAB/fx40-slots"; mkdir -p "$SLOT_REPO"
for _i in $(seq 1 9); do fin "$SLOT_REPO" ensure pm >/dev/null 2>&1; done
t4_assert_eq "0" "$(be_pane_by_name pm9 >/dev/null 2>&1; echo $?)" "S4b 槽位夹具：pm9 已拉起（2..9 全占）"
_s4_before="$(be_pane_count)"
fin "$SLOT_REPO" ensure pm
t4_assert_ne "0" "$BE_RC" "S4b 2..9 全占后再 ensure ⇒ rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "先 close" "S4b fail loud 指路 close"
t4_assert_contains "$BE_ERR_ANSI" "槽位已满" "S4b 点名槽位耗尽"
t4_assert_eq "$_s4_before" "$(be_pane_count)" "S4b 零 pane 副作用"

# S5 基键冲突（两个同名目录）
mkdir -p "$LAB/a/fx40-dup" "$LAB/b/fx40-dup"
fin "$LAB/a/fx40-dup" ensure qa
fin "$LAB/b/fx40-dup" ensure rd-infra
t4_assert_eq "1" "$(ws_n "fx40-dup")" "S5 第一个同名仓 label = fx40-dup"
t4_assert_eq "1" "$(ws_n "fx40-dup2")" "S5 第二个同名仓 label = fx40-dup2（号段）"
t4_assert_eq "$(ws_by_label "fx40-dup2")" "$(pane_ws rd-infra)" "S5 第二仓 pane 落自己的 ws（不串）"

# S6 @code（名字不含 @）
fin "$RA" ensure rd-be@web
t4_assert_eq "0" "$BE_RC" "S6 ensure rd-be@web rc=0"
t4_assert_eq "$(phys "$RB")" "$(pane_cwd_by_ws "$(ws_by_label fx40-web)")" "S6 pane cwd = web 仓"
t4_assert_eq "1" "$(ws_n "fx40-web")" "S6 ws label = web 仓基键"
t4_assert_not_contains "$(pj)" '"label":"rd-be@' "S6 名字不含 @（不拼进 label）"

# S7 @nope 未命中
before="$(be_pane_count)"; fin "$RA" ensure rd-be@nope
t4_assert_ne "0" "$BE_RC" "S7 @nope rc≠0"
t4_assert_contains "$BE_ERR_ANSI" "web" "S7 列出可用 code"
t4_assert_eq "$before" "$(be_pane_count)" "S7 零 pane"

# S8 default 读（ensure/status 放行；不再 exit 3）
env XDG_CONFIG_HOME="$BE_CFGROOT" herdr --session default server >/dev/null 2>&1 || true
T40_ENV=(env HERDR_ENV=1 HERDR_SESSION=default HERDR_SOCKET_PATH="$BE_CFGROOT/herdr/sessions/default/herdr.sock" \
  XDG_CONFIG_HOME="$BE_CFGROOT" NAO_TERMINAL=herdr NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty")
t4_run_in_dir "$RC" "${T40_ENV[@]}" timeout 60 bash "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
t4_assert_eq "0" "$T4_RC" "S8 default 内 ensure rc=0（无 exit 3）"
t4_run_in_dir "$RC" "${T40_ENV[@]}" timeout 60 bash "$LAB/.agents/scripts/nao-fleet.sh" status
t4_assert_eq "0" "$T4_RC" "S8 default 内 status rc=0"

# S9 default 破坏性动作：打印影响面；无 --force ⇒ rc=2 零动作
t4_run_in_dir "$RC" "${T40_ENV[@]}" timeout 60 bash "$LAB/.agents/scripts/nao-fleet.sh" cleanup --session default
t4_assert_eq "2" "$T4_RC" "S9 cleanup default 无 --force ⇒ rc=2"
t4_assert_contains "$T4_ERR" "将停止 session=default，影响" "S9 打印影响面（workspace/pane 数）"
t4_assert_contains "$T4_ERR" "未给 --force ⇒ 零动作" "S9 明确零动作"

# S9b default + --force：真执行（stop+delete），并点名当前 pane 将被终止
t4_run_in_dir "$RC" "${T40_ENV[@]}" timeout 60 bash "$LAB/.agents/scripts/nao-fleet.sh" cleanup --session default --force
t4_assert_eq "0" "$T4_RC" "S9b cleanup default --force ⇒ rc=0（真执行）"
t4_assert_contains "$T4_OUT$T4_ERR" "已终结 herdr session=default" "S9b 执行结果点名已终结 default"
t4_assert_contains "$T4_ERR" "--force：当前 pane 若属于 session=default 将被终止" "S9b 点名当前 pane 风险"
t4_assert_eq "1" "$([ ! -e "$BE_CFGROOT/herdr/sessions/default" ] && echo 1 || echo 0)" \
  "S9b effect：default session 目录已删除"

# S10 护栏：由 30/31/37/38 覆盖（此处只做静态指针，不重复造桩）
t4_note backend-gate "S10 三条护栏（自面板 / 归属不可判定 / 忙闲）由 cases/30/31/37/38 逐条覆盖；本用例不重复造桩"

# S11 legacy 回收（独立仓锚内只有 pm@todo）
LR="$LAB/fx40-legacy"; mkdir -p "$LR"
P_LEG="$(be_new_pane "$LR")"
be_fixture_session "$P_LEG" "pm@todo" "fx40-legacy" >/dev/null || t4_bad "S11 夹具：legacy pane 未就绪"
fin "$LR" close pm
t4_assert_eq "0" "$BE_RC" "S11 close pm（本仓锚内命中 legacy pm@todo）rc=0"
t4_assert_contains "$BE_OUT_ANSI" "已回收 pm@todo" "S11 回收行点名 legacy 名（不谎报未运行）"

# S12 弃用 warn（--fleet 恰一行；放置仍 = 仓基键）
fin "$RB" ensure --fleet x qa
t4_assert_eq "0" "$BE_RC" "S12 --fleet x rc=0（忽略）"
t4_assert_eq "1" "$(grep -c '弃用：--fleet' <<< "$BE_ERR_ANSI" || true)" "S12 弃用 warn 恰一行"
t4_assert_eq "1" "$(ws_n "fx40-web")" "S12 放置仍 = 仓基键"

# S13 status ego（本仓行 + 他仓同名追加）
fin "$RA" status
t4_assert_eq "0" "$BE_RC" "S13 status rc=0"
t4_assert_contains "$BE_OUT_ANSI" "✓ pm" "S13 本仓 pm 行在位"
t4_assert_contains "$BE_OUT_ANSI" "他仓同名" "S13 它仓同名追加字段（ws=<label>）"

t4_exit
