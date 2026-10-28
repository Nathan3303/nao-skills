#!/usr/bin/env bash
# 用例 09 —— T509（#19）：别名解析 / check 守卫 / close 跨仓回收
#
# 判据来源：docs/prds/2026-10-08-fleet-alias-close-fix.md §7 AC1–AC3 · §8 V3
#   AC1  别名与 canonical id 双轨均可解析（BR2 不回归）
#   AC2  check 守卫四点：① 别名无法解析（键值反写）② canonical id 未登记 aliases
#                        ③ 别名跨角色重名 ④ aliases 空/字段缺失（既有回归）
#   AC3  close 跨仓/派生名：不得静默「未运行」；真回收（tmux 可用时）
#
# T530（v0.19.0 发布阻断）回归：pane id（%N）是 **server 局部**命名空间 —— 不同 server 的首块 pane
#   都叫 %0。F1 自 pane 守卫曾拿「默认 server 的 $TMUX_PANE」与「隔离 server 里解析出的 pane id」做
#   裸 id 比较 ⇒ 撞号即误判「这是调用者的 pane」⇒ **误拒**正常回收（安全侧，但 close 不可用）。
#   AC3 真回收组因此扩为三态 + 跨 server 见证，且一律真跑（能力缺失 ⇒ SKIP 计分，不用 NOTE 掩盖）。
#
# 夹具全部落在 $T4_CACHE_DIR；不写仓库工作区（roles.yaml 只改夹具副本）。
# 名册走夹具内嵌假探针（NAO_QA_FAKE_ROSTER），不读真实 pi-intercom 名册。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node

FIX_SESS="t4c09-$$"
# T529：真回收组用**隔离 socket**（不碰生产默认 server；T516 纪律），并以其作 $TMUX 过入口闸门。
C09_SOCK="$T4_CACHE_DIR/c09-sock/tmux-$(id -u)/default"
C09_SOCK_B="$T4_CACHE_DIR/c09-sock-b/tmux-$(id -u)/default"
C09_TMUX_REAL="$C09_SOCK,$$,0"
t09() { tmux -S "$C09_SOCK" "$@"; }
c09b() { tmux -S "$C09_SOCK_B" "$@"; }
cleanup_c09() {
  command -v tmux >/dev/null 2>&1 && { t09 kill-server >/dev/null 2>&1 || true; c09b kill-server >/dev/null 2>&1 || true; }
  t4_cache_cleanup   # BR10：本 trap 会覆盖 lib.sh 的 EXIT trap，串一次清理（仅影响单跑 09；经 run.sh 时 OWNED=0，无害）
}
trap cleanup_c09 EXIT

# ---------------------------------------------------------------- 夹具
write_manifest() { # $1=路径 $2=normal|no_canon|dup|empty|missing
  local p="$1" v="$2"
  local a_arch="[arch, arch-designer]" a_qa="[qa]" a_rdfe="[rd-fe]"
  case "$v" in
    no_canon) a_arch="[arch]" ;;
    dup)      a_qa="[qa, rd-be]" ;;
    empty)    a_rdfe="[]" ;;
    missing)  a_rdfe="" ;;
  esac
  {
    printf 'roles:\n'
    printf '  pm:\n    aliases: [pm]\n    card: product-manager.md\n    workspace: .\n'
    printf '  arch-designer:\n    aliases: %s\n    card: architecture-designer.md\n    workspace: .\n' "$a_arch"
    printf '  rd-fe:\n'
    [ -n "$a_rdfe" ] && printf '    aliases: %s\n' "$a_rdfe"
    printf '    card: frontend-developer.md\n    workspace: .\n'
    printf '  rd-be:\n    aliases: [rd-be]\n    card: backend-developer.md\n    workspace: .\n'
    printf '  qa:\n    aliases: %s\n    card: test-engineer.md\n    workspace: .\n' "$a_qa"
    printf '  rd-infra:\n    aliases: [infra, rd-infra]\n    card: infra-engineer.md\n    workspace: .\n'
  } > "$p"
}

mk_fx() { # $1=名 $2=variant → 打印夹具根
  local d="$T4_CACHE_DIR/fx09-$1"
  rm -rf "$d"; mkdir -p "$d"
  cp -r "$T4_ROOT/.agents" "$d/.agents" || t4_blocked "夹具复制 .agents 失败"
  cat > "$d/.agents/scripts/intercom-probe.mts" <<'JS'
// T4 case09 hermetic roster fixture（只读 env；不接触真实 pi-intercom 名册）
const raw = process.env.NAO_QA_FAKE_ROSTER || "[]";
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(raw) }));
JS
  write_manifest "$d/.agents/roles.yaml" "$2"
  printf '%s' "$d"
}

# T529：ensure/status/close 只接受「tmux 内」——探针用**不存在的假 socket** 过闸门（不接触真 server）；
#   本机若真在 tmux 内则沿用真 $TMUX（真回收组需要真 server）。
C09_TMUX_FAKE="/tmp/nao-t4-c09-$$,1,0"
C09_TMUX="${TMUX:-$C09_TMUX_FAKE}"

fx_fleet() { # $1=夹具根；其余 = fleet 参数（可前置 KEY=VAL 环境变量）
  local d="$1"; shift
  # T530 夹具纪律：-u TMUX_PANE —— 不让共享 worktree 里调用者（PM/QA）的 pane 句柄混进断言；
  #   需要验「撞号」的子用例再显式把自己的 TMUX_PANE 设进去。
  t4_run_in_dir "$d" env -u TMUX_PANE TMUX="$C09_TMUX" NAO_SKILLS="$d" NAO_TASKS_STATE="$d/.none.md" \
    bash "$d/.agents/scripts/nao-fleet.sh" "$@"
}

# ---------------------------------------------------------------- AC2 守卫
FX_N="$(mk_fx normal normal)"

fx_fleet "$FX_N" check
t4_assert_eq "0" "$T4_RC" "AC2: 正常态 check exit=0（NFR3）"
t4_assert_contains "$T4_OUT" "roles=6" "AC2: 正常态 check 报 roles=6"

fx_fleet "$FX_N" check -v
t4_assert_eq "0" "$T4_RC" "AC2: 正常态 check -v exit=0"
t4_assert_contains "$T4_OUT" "别名解析守卫" "AC2: check -v 展示别名解析守卫通过"

# ② canonical id 未登记 aliases
FX_NOCAN="$(mk_fx nocan no_canon)"
fx_fleet "$FX_NOCAN" check
t4_assert_ne "0" "$T4_RC" "AC2: canonical id 未登记 aliases → check 非 0"
t4_assert_contains "$T4_OUT" "arch-designer" "AC2: 指名问题角色 arch-designer"

# ③ 别名跨角色重名
FX_DUP="$(mk_fx dup dup)"
fx_fleet "$FX_DUP" check
t4_assert_ne "0" "$T4_RC" "AC2: 别名跨角色重名 → check 非 0"
t4_assert_contains "$T4_OUT" "重名" "AC2: 指名跨角色重名"

# ① 别名无法解析（把夹具脚本 ALIAS 行置回键值反写态复现本缺陷）
FX_REV="$(mk_fx rev normal)"
perl -0pi -e 's/ALIAS_ROLE\["\$w"\]="\$v"/ALIAS_ROLE["\$v"]="\$w"/' "$FX_REV/.agents/scripts/nao-fleet.sh" 2>/dev/null || true
REVLINE="$(grep -m1 'ALIAS) ALIAS_ROLE' "$FX_REV/.agents/scripts/nao-fleet.sh" || true)"
if [ "$REVLINE" = "${REVLINE#*'ALIAS_ROLE["$v"]="$w"'}" ]; then
  t4_bad "AC2: 无法把夹具脚本置为键值反写态（实现写法已变）：$(printf '%s' "$REVLINE" | tr -d '\n')"
else
  fx_fleet "$FX_REV" check
  t4_assert_ne "0" "$T4_RC" "AC2: ALIAS_ROLE 键值反写 → check 非 0（守卫对表方向敏感）"
  t4_assert_contains "$T4_OUT" "解析异常" "AC2: 指名别名解析异常"
fi

# ④ 既有回归：aliases 空 / 字段缺失
FX_EMPTY="$(mk_fx empty empty)"
fx_fleet "$FX_EMPTY" check
t4_assert_ne "0" "$T4_RC" "AC2: aliases 为空 → check 非 0（既有守卫回归）"
FX_MISS="$(mk_fx missing missing)"
fx_fleet "$FX_MISS" check
t4_assert_ne "0" "$T4_RC" "AC2: aliases 字段缺失 → check 非 0（既有守卫回归）"

# ---------------------------------------------------------------- AC1 别名解析（行为探针，零副作用）
# close --task NAOQA9 <目标>：解析成功时输出含 <角色 id>-NAOQA9 且不报「未知角色」。
t4_info "别名/canonical 解析探针（close --task NAOQA9 <目标>，不实拉）"
c09_names=("pm:pm" "arch:arch-designer" "arch-designer:arch-designer" "rd-fe:rd-fe" \
           "rd-be:rd-be" "qa:qa" "infra:rd-infra" "rd-infra:rd-infra")
for pair in "${c09_names[@]}"; do
  n="${pair%%:*}"; want="${pair#*:}"
  fx_fleet "$FX_N" close --task NAOQA9 "$n"
  if [ "$T4_RC" = "0" ] && printf '%s' "$T4_OUT" | grep -qF "$want-NAOQA9" \
     && ! printf '%s' "$T4_OUT" | grep -qF "未知角色"; then
    t4_ok "AC1: \`$n\` → $want"
  else
    t4_bad "AC1: \`$n\` 未解析到 $want（rc=$T4_RC）"
  fi
done

# ---------------------------------------------------------------- AC3 close 跨仓 / 静默失败
OTHER="$T4_CACHE_DIR/fx09-otherrepo"; mkdir -p "$OTHER"
ROSS="[{\"name\":\"qa-T508\",\"id\":\"qa-T508\",\"status\":\"idle\",\"cwd\":\"$OTHER\",\"tmuxPane\":\"%999\"}]"

# 名册报在线（cwd=另一仓）但无存活 pane ⇒ 必须非静默（非 0 且不报「未运行（无需回收）」）
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env TMUX="$C09_TMUX" NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$ROSS" \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T508 qa
t4_assert_ne "0" "$T4_RC" "AC3: 跨仓 qa-T508 未定位到句柄 ⇒ 非 0"
t4_assert_not_contains "$T4_OUT" "未运行（无需回收）" "AC3: 不得报「未运行（无需回收）」而 pane 未回收"

# 派生会话名（无 --task）不得静默 no-op
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env TMUX="$C09_TMUX" NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$ROSS" \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close qa-T508
t4_assert_ne "0" "$T4_RC" "AC3: close qa-T508（无 --task）不得 rc=0 静默 no-op"
t4_assert_not_contains "$T4_OUT" "未运行（无需回收）" "AC3: close qa-T508 不得静默报「未运行」"

# 回归：确实不在线仍应 rc=0 + 「未运行（无需回收）」（不过度矫正为恒失败）
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env TMUX="$C09_TMUX" NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER='[]' \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T508 qa
t4_assert_eq "0" "$T4_RC" "AC3 回归: 名册无记录且无句柄 ⇒ 未运行 rc=0"
t4_assert_contains "$T4_OUT" "未运行（无需回收）" "AC3 回归: 输出「未运行（无需回收）」"

# ---------------------------------------------------------------- AC3 真回收 + 撞号负控（T530）
# pane id 是 server 局部命名空间（不同 server 首块 pane 都叫 %0）⇒ 任何裸 id 比较都会跨 server 撞号。
# 三态（缺一不可，能力缺失一律 SKIP 计分，不许 NOTE 掩盖）：
#   ① 正常回收：目标 pane 消失
#   ② 撞号回归（本次红态）：TMUX_PANE 刻意等于目标 pane id ⇒ 修复后仍必须回收成功
#   ③ 自 pane 不变量（既有护栏不许放松）：在目标 pane **内**真跑 close ⇒ rc≠0 + pane 存活
# 每条都同时断言「别的 server 的 pane 仍存活」= 误杀别人的回归护栏。
command -v tmux >/dev/null 2>&1 || t4_skip "AC3: 无 tmux —— 真回收断言必须真跑（不许 NOTE 掩盖）；full 计分"
mkdir -p "$(dirname "$C09_SOCK")" "$(dirname "$C09_SOCK_B")"
chmod 700 "$(dirname "$C09_SOCK")" "$(dirname "$C09_SOCK_B")"
t09 kill-server >/dev/null 2>&1 || true
c09b kill-server >/dev/null 2>&1 || true
if ! t09 new-session -d -s "$FIX_SESS" -c "$OTHER" 2>/dev/null \
   || ! c09b new-session -d -s "$FIX_SESS" -c "$OTHER" 2>/dev/null; then
  t4_skip "AC3: 无法创建隔离 tmux server（环境限制）—— 真回收断言必须真跑；full 计分"
fi
# 见证：另一个隔离 server（B）内的首块 pane（与 A 的目标 pane 同为 %0 量级的同 id 命名空间）
C09_WITNESS="$(c09b list-panes -t "$FIX_SESS" -F '#{pane_id}' 2>/dev/null | head -1)"
# 生产默认 server 既有 pane 快照（**只读**，仅作「不得误杀别人」的见证；不建不杀）
C09_DEF_SOCK="/tmp/tmux-$(id -u)/default"
C09_DEF_BEFORE="$(tmux -S "$C09_DEF_SOCK" list-panes -a -F '#{pane_id}' 2>/dev/null || true)"
C09_DEF_NOTE=""
[ -n "$C09_DEF_BEFORE" ] && C09_DEF_NOTE=" · 默认 server 完好:$(printf '%s' "$C09_DEF_BEFORE" | tr '\n' ' ' | sed 's/ *$//')"

c09_reclaimed() {  # $1=pane_id：server 可达 **且** 目标 pane 确实不在（server 崩/连不上不算成功）
  t09 list-sessions >/dev/null 2>&1 || return 1
  ! { t09 list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$1"; }
}
c09_witness_ok() {  # 见证 pane 全存活：隔离 server B + 生产默认 server 既有 pane
  c09b list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$C09_WITNESS" || return 1
  local p
  for p in $C09_DEF_BEFORE; do
    tmux -S "$C09_DEF_SOCK" list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$p" || return 1
  done
  return 0
}
c09_assert_witness() {  # $1=子用例标签
  if c09_witness_ok; then
    t4_ok "AC3$1: 跨 server 见证存活（隔离 B=$C09_WITNESS${C09_DEF_NOTE}）"
  else
    t4_bad "AC3$1: 跨 server 见证被误杀（隔离 B=$C09_WITNESS · 默认 server 快照:${C09_DEF_NOTE:-无}）"
  fi
}

# O1（QA 提出）：序列号必须在**父 shell** 自增 —— `$(stage_pane ...)` 是子 shell，函数内自增会丢，
#   三次都落到 -s1（同会话名重入 ⇒ tmux 侧串号；红态演练下 ③ 退化为 SKIP）。
C09_SEQ=0
c09_next_sess() {  # 父 shell 自增后输出唯一会话名（调用方必须**直接赋值**，不要放进 $() ）
  C09_SEQ=$((C09_SEQ + 1))
  C09_SESS="$FIX_SESS-s$C09_SEQ-$$"
}
stage_pane() {  # $1=会话名 $2=唯一 tmux 会话名 → 在隔离 server A 内新开 pane，标题契约 + 输出 pane_id
  local name="$1" sess="$2" p
  [ -n "$sess" ] || return 1
  t09 new-session -d -s "$sess" -c "$OTHER" 2>/dev/null || return 1
  p="$(t09 list-panes -t "$sess" -F '#{pane_id}' 2>/dev/null | head -1)"
  [ -n "$p" ] || return 1
  t09 select-pane -t "$p" -T "π - $name - $(basename "$OTHER")" >/dev/null 2>&1 || true
  # 不在此 pane 里注入前台进程：③ 需要把驱动脚本 send-keys 给**该 pane 的 shell**，
  # 前台被占（如 sleep）会让键盘输入落到那个进程的 stdin ⇒ pane 保持裸 shell 即可存活。
  printf '%s\n' "$p"
}

# ---- ① 正常回收（夹具纪律：-u TMUX_PANE）----
C09_NAME1="qa-T509R"
c09_next_sess
if ! C09_P1="$(stage_pane "$C09_NAME1" "$C09_SESS")"; then
  t4_skip "AC3: 隔离 server 内建 pane 失败（环境限制）—— 真回收断言必须真跑；full 计分"
fi
C09_R1="[{\"name\":\"$C09_NAME1\",\"id\":\"$C09_NAME1\",\"status\":\"idle\",\"cwd\":\"$OTHER\",\"tmuxPane\":\"$C09_P1\"}]"
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env -u TMUX_PANE TMUX="$C09_TMUX_REAL" NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$C09_R1" \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T509R qa
t4_assert_eq "0" "$T4_RC" "AC3①: 真回收 rc=0（跨仓 pane $C09_P1）"
if c09_reclaimed "$C09_P1"; then
  t4_ok "AC3①: 目标 pane $C09_P1 已回收（隔离 server 可达且 pane 不在）"
else
  t4_bad "AC3①: 真回收失败——pane $C09_P1 仍存活或隔离 server 不可达（rc=$T4_RC）"
fi
c09_assert_witness "①"

# ---- ② 撞号回归：TMUX_PANE 与目标 pane id 相同（修复前此处 rc=1 误拒）----
C09_NAME2="qa-T509S"
c09_next_sess
if ! C09_P2="$(stage_pane "$C09_NAME2" "$C09_SESS")"; then
  t4_skip "AC3: 隔离 server 内建 pane 失败（环境限制）—— 真回收断言必须真跑；full 计分"
fi
C09_R2="[{\"name\":\"$C09_NAME2\",\"id\":\"$C09_NAME2\",\"status\":\"idle\",\"cwd\":\"$OTHER\",\"tmuxPane\":\"$C09_P2\"}]"
t4_info "撞号负控：\$TMUX_PANE=$C09_P2（与实际调用者 pane 无关的陈旧句柄） vs 目标 pane $C09_P2"
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env TMUX="$C09_TMUX_REAL" TMUX_PANE="$C09_P2" NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$C09_R2" \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T509S qa
t4_assert_eq "0" "$T4_RC" "AC3②: pane id 与 \$TMUX_PANE 撞号不得误拒回收（rc=0）"
t4_assert_not_contains "$T4_OUT$T4_ERR" "拒绝回收" "AC3②: 不得报「拒绝回收」（撞号不是「调用者自己的 pane」）"
if c09_reclaimed "$C09_P2"; then
  t4_ok "AC3②: 撞号目标 pane $C09_P2 已回收"
else
  t4_bad "AC3②: 撞号目标 pane $C09_P2 仍存活或 server 不可达（rc=$T4_RC）"
fi
c09_assert_witness "②"

# ---- ③ 自 pane 不变量（fail-closed）：在目标 pane **内部**真跑 close ⇒ 必须拒 ----
# 两跑同一断言：③ 真 ps（祖先链可读 ⇒ 确定是自己）；③b 伪造 ps（祖先链**不可读** ⇒ 不可判定）。
# ③b 是 QA 的 SELF_KILLED 场景：判不了就放行 = fail-open ⇒ 自身 pane 被回收。此处必须红变绿。
C09_SELF_DRIVER="$T4_CACHE_DIR/c09-self.sh"
cat > "$C09_SELF_DRIVER" <<'EOS'
#!/usr/bin/env bash
# F1 自 pane 负控驱动：在目标 pane **内部**执行 close（调用者进程树挂在 pane_pid 下）
exec >"$C09_SELF_OUT" 2>&1
cd "$C09_FX" || exit 9
NAO_QA_FAKE_ROSTER="$(cat "$C09_ROSTER_FILE")" NAO_SKILLS="$C09_FX" NAO_TASKS_STATE="$C09_FX/.none.md" \
  bash "$C09_FX/.agents/scripts/nao-fleet.sh" close --task "$C09_TASK" qa
printf '\n__RC__=%s\n' "$?"
EOS
chmod +x "$C09_SELF_DRIVER"

# 伪造 ps：令祖先链不可读（ppid 查询恒失败）——真 ps 路径前置在 PATH 最前
C09_FAKEBIN="$T4_CACHE_DIR/c09-fakebin"; mkdir -p "$C09_FAKEBIN"
REAL_PS="$(command -v ps)"
cat > "$C09_FAKEBIN/ps" <<EOS
#!/usr/bin/env bash
# 伪造 ps：ppid 查询恒失败（模拟「祖先链不可读」）
case "\$*" in *ppid*) exit 1 ;; esac
exec "$REAL_PS" "\$@"
EOS
chmod +x "$C09_FAKEBIN/ps"

c09_self_drill() {  # $1=标签(③/③b) $2=任务号后缀 $3=PATH 前缀（空=真 ps）
  local label="$1" task="$2" pathpfx="$3"
  local name="qa-$task" p roster out rc sendenv
  c09_next_sess
  if ! p="$(stage_pane "$name" "$C09_SESS")"; then
    t4_bad "AC3$label: 隔离 server 内建 pane 失败（环境限制）"
    return 0
  fi
  roster="$T4_CACHE_DIR/c09-roster-$task.json"
  printf '[{"name":"%s","id":"%s","status":"idle","cwd":"%s","tmuxPane":"%s"}]' \
    "$name" "$name" "$OTHER" "$p" > "$roster"
  out="$T4_CACHE_DIR/c09-self-$task.out"; rm -f "$out"
  sendenv="C09_SELF_OUT='$out' C09_FX='$FX_N' C09_ROSTER_FILE='$roster' C09_TASK=$task"
  [ -n "$pathpfx" ] && sendenv="PATH='$pathpfx':\$PATH $sendenv"
  t09 send-keys -t "$p" "$sendenv bash '$C09_SELF_DRIVER'" Enter >/dev/null 2>&1 || true
  rc=""
  for _ in $(seq 1 200); do
    if grep -q '__RC__=' "$out" 2>/dev/null; then
      rc="$(sed -n 's/^__RC__=//p' "$out" | tail -1)"; break
    fi
    sleep 0.1
  done
  if [ -z "$rc" ]; then
    # 无结果有两种成因：驱动本身失败（pane 仍在），或**闸门缺失致 pane 被自杀**（驱动随 pane 一起死）。
    if t09 list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$p"; then
      t4_bad "AC3$label: 自 pane 负控未产出结果（pane $p 仍在 ⇒ 驱动超时/失败）—— 见 $out"
    else
      t4_bad "AC3$label: 调用者自身 pane $p 被回收（F1 不变量破坏/SELF_KILLED；驱动随 pane 死亡故无结果）"
    fi
    return 0
  fi
  t4_assert_ne "0" "$rc" "AC3$label: 目标 pane 就是调用者自身 ⇒ close 必须拒（rc≠0）"
  t4_assert_contains "$(cat "$out" 2>/dev/null)" "拒绝回收" "AC3$label: 输出「拒绝回收」"
  if t09 list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$p"; then
    t4_ok "AC3$label: 调用者自身 pane $p 存活（未被自杀）"
  else
    t4_bad "AC3$label: 调用者自身 pane $p 被回收了（F1 不变量破坏/SELF_KILLED）"
  fi
  c09_assert_witness "$label"
}

c09_self_drill "③"  "T509T" ""                    # 真 ps：祖先链可读 ⇒ 确定是自己 ⇒ 拒
c09_self_drill "③b" "T509U" "$C09_FAKEBIN"        # ps 不可读 ⇒ 不可判定 ⇒ fail-closed 仍拒

# ---- ④ 不可判定 + **不撞号** ⇒ 必须放行（防过度矫正把 v0.19.0 误拒引回来）----
# 判据：rc=2 只对「与 $TMUX_PANE 撞号」保守拒绝；不撞号时不得因此卡死正常回收。
C09_NAME4="qa-T509V"
c09_next_sess
if ! C09_P4="$(stage_pane "$C09_NAME4" "$C09_SESS")"; then
  t4_bad "AC3④: 隔离 server 内建 pane 失败（环境限制）"
else
  C09_R4="[{\"name\":\"$C09_NAME4\",\"id\":\"$C09_NAME4\",\"status\":\"idle\",\"cwd\":\"$OTHER\",\"tmuxPane\":\"$C09_P4\"}]"
  t4_info "不可判定负控：ps 不可读 + \$TMUX_PANE=%9（与目标 $C09_P4 不撞号）⇒ 必须放行"
  T4_OUT=""; T4_ERR=""; T4_RC=0
  t4_run_in_dir "$FX_N" env PATH="$C09_FAKEBIN:$PATH" TMUX="$C09_TMUX_REAL" TMUX_PANE="%9" \
    NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$C09_R4" \
    bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T509V qa
  t4_assert_eq "0" "$T4_RC" "AC3④: 不可判定且不撞号 ⇒ close 放行（rc=0）"
  t4_assert_not_contains "$T4_OUT$T4_ERR" "拒绝回收" "AC3④: 不得报「拒绝回收」（过度矫正会复现 v0.19.0 误拒）"
  if c09_reclaimed "$C09_P4"; then
    t4_ok "AC3④: 目标 pane $C09_P4 已回收"
  else
    t4_bad "AC3④: 目标 pane $C09_P4 仍存活或 server 不可达（rc=$T4_RC）"
  fi
  c09_assert_witness "④"
fi

t09 kill-server >/dev/null 2>&1 || true
c09b kill-server >/dev/null 2>&1 || true

t4_exit
