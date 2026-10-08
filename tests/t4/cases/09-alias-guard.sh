#!/usr/bin/env bash
# 用例 09 —— T509（#19）：别名解析 / check 守卫 / close 跨仓回收
#
# 判据来源：docs/prds/2026-10-08-fleet-alias-close-fix.md §7 AC1–AC3 · §8 V3
#   AC1  别名与 canonical id 双轨均可解析（BR2 不回归）
#   AC2  check 守卫四点：① 别名无法解析（键值反写）② canonical id 未登记 aliases
#                        ③ 别名跨角色重名 ④ aliases 空/字段缺失（既有回归）
#   AC3  close 跨仓/派生名：不得静默「未运行」；真回收（tmux 可用时）
#
# 夹具全部落在 $T4_CACHE_DIR；不写仓库工作区（roles.yaml 只改夹具副本）。
# 名册走夹具内嵌假探针（NAO_QA_FAKE_ROSTER），不读真实 pi-intercom 名册。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node

FIX_SESS="t4c09-$$"
cleanup_c09() {
  command -v tmux >/dev/null 2>&1 && tmux kill-session -t "$FIX_SESS" 2>/dev/null || true
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

fx_fleet() { # $1=夹具根；其余 = fleet 参数（可前置 KEY=VAL 环境变量）
  local d="$1"; shift
  t4_run_in_dir "$d" env NAO_SKILLS="$d" NAO_TASKS_STATE="$d/.none.md" \
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
t4_run_in_dir "$FX_N" env NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$ROSS" \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T508 qa
t4_assert_ne "0" "$T4_RC" "AC3: 跨仓 qa-T508 未定位到句柄 ⇒ 非 0"
t4_assert_not_contains "$T4_OUT" "未运行（无需回收）" "AC3: 不得报「未运行（无需回收）」而 pane 未回收"

# 派生会话名（无 --task）不得静默 no-op
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$ROSS" \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close qa-T508
t4_assert_ne "0" "$T4_RC" "AC3: close qa-T508（无 --task）不得 rc=0 静默 no-op"
t4_assert_not_contains "$T4_OUT" "未运行（无需回收）" "AC3: close qa-T508 不得静默报「未运行」"

# 回归：确实不在线仍应 rc=0 + 「未运行（无需回收）」（不过度矫正为恒失败）
T4_OUT=""; T4_ERR=""; T4_RC=0
t4_run_in_dir "$FX_N" env NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER='[]' \
  bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T508 qa
t4_assert_eq "0" "$T4_RC" "AC3 回归: 名册无记录且无句柄 ⇒ 未运行 rc=0"
t4_assert_contains "$T4_OUT" "未运行（无需回收）" "AC3 回归: 输出「未运行（无需回收）」"

# 真回收（tmux 可用时）：自建跨仓 pane（标题契约 + 名册 tmuxPane），验「真的关掉」
if command -v tmux >/dev/null 2>&1; then
  tmux kill-session -t "$FIX_SESS" 2>/dev/null || true
  if tmux new-session -d -s "$FIX_SESS" -c "$OTHER" 2>/dev/null; then
    pane="$(tmux list-panes -t "$FIX_SESS" -F '#{pane_id}' 2>/dev/null | head -1)"
    tmux select-pane -t "$pane" -T "π - qa-T509R - $(basename "$OTHER")" 2>/dev/null || true
    tmux send-keys -t "$pane" 'sleep 300' Enter 2>/dev/null || true
    ROSS2="[{\"name\":\"qa-T509R\",\"id\":\"qa-T509R\",\"status\":\"idle\",\"cwd\":\"$OTHER\",\"tmuxPane\":\"$pane\"}]"
    T4_OUT=""; T4_ERR=""; T4_RC=0
    t4_run_in_dir "$FX_N" env NAO_SKILLS="$FX_N" NAO_TASKS_STATE="$FX_N/.none.md" NAO_QA_FAKE_ROSTER="$ROSS2" \
      bash "$FX_N/.agents/scripts/nao-fleet.sh" close --task T509R qa
    if tmux list-panes -t "$FIX_SESS" -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane"; then
      t4_bad "AC3: 真回收失败——跨仓 pane $pane 仍存活（rc=$T4_RC）"
    else
      t4_ok "AC3: 真回收跨仓 pane $pane（已关闭）"
    fi
    tmux kill-session -t "$FIX_SESS" 2>/dev/null || true
  else
    t4_note "AC3: tmux 夹具会话创建失败（环境限制），真回收断言跳过"
  fi
else
  t4_note "AC3: 无 tmux，真回收断言跳过（跨仓非静默断言已覆盖）"
fi

t4_exit
