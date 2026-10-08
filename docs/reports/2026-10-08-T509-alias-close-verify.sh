#!/usr/bin/env bash
# =============================================================================
# T509 独立断言脚本 —— #19 别名解析 + check 守卫 + close 跨仓回收
#
# 判据来源（唯一）：docs/prds/2026-10-08-fleet-alias-close-fix.md §7 AC1–AC8 / §8 V1–V4
# 被测：.agents/scripts/nao-fleet.sh（**本脚本不修改机制源码**；构造场景只在 temp fixture）
#
# 用法:
#   bash docs/reports/2026-10-08-T509-alias-close-verify.sh --baseline   # 现树体检（0.12.0 修复前）
#   bash docs/reports/2026-10-08-T509-alias-close-verify.sh              # 修复后验收
#   附加：--with-tmux   允许 AC3 真回收用「独立 tmux pane 夹具」（默认跳过，避免污染 PM 共享 tmux）
#         KEEP=1        保留 temp fixture（默认清理）
#
# 退出码: 0 = 无非预期 FAIL（--baseline 恒 0，FAIL 属预期）；1 = 修复后模式存在 FAIL；2 = 脚本自身环境错误
#
# 断言分组（与 AC 逐条映射）:
#   AC1 别名/canonical 解析（行为探针，零副作用）           AC2 check 守卫（4 构造场景 + 正常态）
#   AC3 close 跨仓回收（hermetic roster 夹具；真回收 opt-in） AC4 README/help 与 roles.yaml 一致
#   AC5 门禁（npm test / tests/t4 / check / status）        AC6 负向闭环（三仓 NFR4 + 版本）
#   AC7 提交治理（合并后核）                                AC8 非范围守护（diff）
#   V1–V4 待验证项（信息性，不计 PASS/FAIL）
#
# 安全边界:
#   - 绝不写本仓 .agents/roles.yaml / nao-fleet.sh / tests/**（全部改动落在 $TMP 夹具副本）
#   - 零网络；不拉真实 pi 会话；默认不动 tmux（--with-tmux 才创建并回收自建 pane）
#   - 名册走 fixture 内嵌假探针（NAO_QA_FAKE_ROSTER），不读取/不污染真实 pi-intercom 名册
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FLEET="$ROOT/.agents/scripts/nao-fleet.sh"
README="$ROOT/README.md"
MODE="verify"; ALLOW_TMUX=0
for a in "$@"; do
  case "$a" in
    --baseline)  MODE="baseline" ;;
    --verify)    MODE="verify" ;;
    --with-tmux) ALLOW_TMUX=1 ;;
    -h|--help)   sed -n '2,33p' "$0"; exit 0 ;;
    *) printf '未知参数: %s\n' "$a" >&2; exit 2 ;;
  esac
done

DOWNSTREAM=("$HOME/Project/nao-todo" "$HOME/Project/nao-todo-server" "$HOME/Project/nue-ui")
export NAO_QA_FAKE_ROSTER="${NAO_QA_FAKE_ROSTER:-[]}"

PASS_N=0 FAIL_N=0 SKIP_N=0 WARN_N=0
declare -A AC_P AC_F AC_S AC_W
declare -a FAILED=()
pass(){ local ac="$1"; shift; PASS_N=$((PASS_N+1)); AC_P[$ac]=$(( ${AC_P[$ac]:-0}+1 )); printf '  [PASS] %-4s %s\n' "$ac" "$*"; }
bad(){ local ac="$1"; shift; FAIL_N=$((FAIL_N+1)); AC_F[$ac]=$(( ${AC_F[$ac]:-0}+1 )); FAILED+=("$ac $*"); printf '  [FAIL] %-4s %s\n' "$ac" "$*"; }
skip(){ local ac="$1"; shift; SKIP_N=$((SKIP_N+1)); AC_S[$ac]=$(( ${AC_S[$ac]:-0}+1 )); printf '  [SKIP] %-4s %s\n' "$ac" "$*"; }
warn2(){ local ac="$1"; shift; WARN_N=$((WARN_N+1)); AC_W[$ac]=$(( ${AC_W[$ac]:-0}+1 )); printf '  [WARN] %-4s %s\n' "$ac" "$*"; }
note(){ printf '  [NOTE] %s\n' "$*"; }
sec(){ printf '\n== %s ==\n' "$*"; }
oneline(){ printf '%s' "${1:-}" | perl -pe 's/\e\[[0-9;]*m//g' | tr '\n' '|' | cut -c1-200; }

FXROOT="$(mktemp -d "${TMPDIR:-/tmp}/t509-verify.XXXXXX")" || { echo "mktemp 失败" >&2; exit 2; }
TMUX_FIX_SESSION=""
cleanup(){
  if [[ -n "$TMUX_FIX_SESSION" ]] && command -v tmux >/dev/null 2>&1; then
    tmux kill-session -t "$TMUX_FIX_SESSION" 2>/dev/null || true
  fi
  [[ "${KEEP:-0}" == 1 ]] && { printf '\n（KEEP=1：夹具保留于 %s）\n' "$FXROOT"; return 0; }
  rm -rf "$FXROOT"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# fixture 工具（全部落在 $FXROOT，绝不碰本仓）
write_probe(){ # $1 = fixture 根
  cat > "$1/.agents/scripts/intercom-probe.mts" <<'JS'
// T509 QA hermetic roster fixture（只读 env；绝不接触真实 pi-intercom 名册）
const raw = process.env.NAO_QA_FAKE_ROSTER || "[]";
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(raw) }));
JS
}

write_manifest(){ # $1 = 目标路径  $2 = 变体 normal|no_canon_id|dup_alias|empty_alias
  local p="$1" v="$2"
  cat > "$p" <<'YAML'
# T509 QA fixture manifest（生成物）
roles:
  pm:
    aliases: [pm]
    card: product-manager.md
    workspace: .
  arch-designer:
    aliases: [arch, arch-designer]
    card: architecture-designer.md
    workspace: .
  rd-fe:
    aliases: [rd-fe]
    card: frontend-developer.md
    workspace: .
  rd-be:
    aliases: [rd-be]
    card: backend-developer.md
    workspace: .
  qa:
    aliases: [qa]
    card: test-engineer.md
    workspace: .
  rd-infra:
    aliases: [infra, rd-infra]
    card: infra-engineer.md
    workspace: .
YAML
  case "$v" in
    normal)      : ;;
    no_canon_id) perl -0pi -e 's/aliases: \[arch, arch-designer\]/aliases: [arch]/' "$p" ;;
    dup_alias)   perl -0pi -e 's/^    aliases: \[qa\]$/    aliases: [qa, rd-be]/m' "$p" ;;
    empty_alias) perl -0pi -e 's/^    aliases: \[rd-fe\]$/    aliases: []/m' "$p" ;;
    missing_alias) perl -0pi -e 's/^    aliases: \[rd-fe\]\n//m' "$p" ;;
    *) echo "未知 manifest 变体: $v" >&2; return 2 ;;
  esac
}

mk_fixture(){ # $1 = 名 → 打印夹具根（.agents 全量副本 + 假探针 + 指定 manifest）
  local n="$1"
  local v="${2:-normal}"
  local d="$FXROOT/$n"
  rm -rf "$d"; mkdir -p "$d"
  cp -r "$ROOT/.agents" "$d/.agents" || { echo "夹具复制失败: $d" >&2; return 2; }
  write_probe "$d"
  write_manifest "$d/.agents/roles.yaml" "$v"
  printf '%s' "$d"
}

run_fleet(){ # $1 = 夹具根；其余为 fleet 参数（cwd=夹具，NAO_SKILLS=夹具 ⇒ 全 hermetic）
  local d="$1"; shift
  ( cd "$d" && NAO_SKILLS="$d" NAO_TASKS_STATE="$d/.no-tasks-state.md" \
      bash "$d/.agents/scripts/nao-fleet.sh" "$@" ) 2>&1
}
run_check(){ run_fleet "$1" check; }

# ---------------------------------------------------------------------------
printf '################ T509 别名/守卫/跨仓回收 —— 独立断言 ################\n'
printf '模式      : %s%s\n' "$MODE" "$( [[ $MODE == baseline ]] && echo ' （现树体检：FAIL 属预期，修复前）' )"
printf '仓库根    : %s\n' "$ROOT"
printf '机制版本  : %s\n' "$(node -p "require('$ROOT/package.json').version" 2>/dev/null || echo '?')"
printf 'git 分支  : %s\n' "$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
printf '夹具目录  : %s\n' "$FXROOT"

# ---------------------------------------------------------------------------
sec "E 现状实测（原始输出，供修复前后对照）"

printf -- '-- ensure arch --\n'
if [[ "$MODE" == baseline ]]; then
  eo="$(cd "$ROOT" && timeout 60 bash "$FLEET" ensure arch </dev/null 2>&1)"; erc=$?
  printf '   rc=%s | %s\n' "$erc" "$(oneline "$eo")"
  printf -- '-- ensure infra --\n'
  eo="$(cd "$ROOT" && timeout 60 bash "$FLEET" ensure infra </dev/null 2>&1)"; erc=$?
  printf '   rc=%s | %s\n' "$erc" "$(oneline "$eo")"
else
  note "verify 模式跳过 ensure 实拉（会真起面板；AC1 实拉由 PM/RD 在授权后跑）"
fi

co="$(cd "$ROOT" && bash "$FLEET" check 2>&1)"; crc=$?
printf -- '-- 本仓 check --\n   rc=%s | %s\n' "$crc" "$(oneline "$co")"

if command -v tmux >/dev/null 2>&1; then
  printf -- '-- tmux list-panes（pane_id | title | cmd | path）--\n'
  tmux list-panes -a -F '#{pane_id} | #{pane_title} | #{pane_current_command} | #{pane_current_path}' 2>/dev/null \
    | sed 's/^/   /' || true
else
  note "无 tmux（跨仓 close 的 tmux 相关断言将 SKIP）"
fi

printf -- '-- pi-intercom 名册（真实）--\n'
rp="$(timeout 20 node "$HOME/.pi/agent/npm/node_modules/tsx/dist/cli.mjs" "$ROOT/.agents/scripts/intercom-probe.mts" "$HOME/.pi/agent" 2>/dev/null || true)"
printf '%s' "$rp" | awk '/"name":/ { n=$0; sub(/.*"name":[[:space:]]*"/,"",n); sub(/".*/,"",n) }
                          /"cwd":/  { c=$0; sub(/.*"cwd":[[:space:]]*"/,"",c);  sub(/".*/,"",c); print "   " n "\t" c }' || true

# ---------------------------------------------------------------------------
sec "AC1 别名/canonical 解析（行为探针：close --task <夹具编号> <目标> 的解析结果）"

FX_MAIN="$(mk_fixture main normal)" || { echo "夹具初始化失败" >&2; exit 2; }

A1_NAMES=(pm arch arch-designer rd-fe rd-be qa infra rd-infra)
A1_WANT=(pm arch-designer arch-designer rd-fe rd-be qa rd-infra rd-infra)
for i in "${!A1_NAMES[@]}"; do
  n="${A1_NAMES[$i]}"; want="${A1_WANT[$i]}"
  out="$(NAO_QA_FAKE_ROSTER='[]' run_fleet "$FX_MAIN" close --task NAOQA9 "$n")"; rc=$?
  if [[ $rc -eq 0 && "$out" == *"$want"* && "$out" != *"未知角色"* ]]; then
    pass AC1 "\`$n\` → $want（rc=0；输出含 ${want}-NAOQA9）"
  else
    bad AC1 "\`$n\` 未解析到 $want（rc=$rc；$(oneline "$out")）"
  fi
done
skip AC1 "ensure 真实拉起（arch/infra 起面板 + 角色卡注入）—— 共享宿主禁止脚本实拉；由 PM/RD 授权后人工跑并回填"

# ---------------------------------------------------------------------------
sec "AC2 check 守卫（构造场景：① 别名缺失② ALIAS_ROLE 键值反写③ 跨角色重名 + 正常态）"

# 2.0 正常态（NFR3）
out="$(run_check "$FX_MAIN")"; rc=$?
if [[ $rc -eq 0 && "$out" == *"roles=6"* ]]; then
  pass AC2 "正常态 check exit=0 且 roles=6（NFR3）"
else
  bad AC2 "正常态 check 应 exit=0 且 roles=6（rc=$rc；$(oneline "$out")）"
fi

# 2.a 别名缺失 A：canonical id 未登记于 aliases（BR2 守卫）
FX_NOCAN="$(mk_fixture nocan no_canon_id)"
out="$(run_check "$FX_NOCAN")"; rc=$?
if [[ $rc -ne 0 && "$out" == *arch* ]]; then
  pass AC2 "① 别名缺失（canonical \`arch-designer\` 未登记）→ check rc=$rc 且指名问题"
else
  bad AC2 "① 别名缺失：canonical 未登记未使 check 非 0（rc=$rc；$(oneline "$out")）"
fi
A1_NOCAN_RC=$rc

# 2.b ALIAS_ROLE 键值反写（本缺陷复现：把夹具脚本置为反写态，即 ALIAS_ROLE[角色id]=别名）
FX_REV="$(mk_fixture rev normal)"
perl -0pi -e 's/ALIAS\) ALIAS_ROLE\["\$w"\]="\$v"/ALIAS) ALIAS_ROLE["\$v"]="\$w"/' "$FX_REV/.agents/scripts/nao-fleet.sh"
REVLINE="$(grep -m1 'ALIAS) ALIAS_ROLE' "$FX_REV/.agents/scripts/nao-fleet.sh" || true)"
if [[ "$REVLINE" == *'ALIAS_ROLE["$v"]="$w"'* ]]; then
  out="$(run_check "$FX_REV")"; rc=$?
  if [[ $rc -ne 0 ]]; then
    pass AC2 "② ALIAS_ROLE 键值反写 → check rc=$rc（守卫对表方向敏感）"
  else
    bad AC2 "② ALIAS_ROLE 键值反写未被检出（check rc=0；$(oneline "$out")）"
  fi
  GUARD_REV_EVIDENCE="反写夹具（$REVLINE）check rc=$rc"
else
  bad AC2 "② 无法将夹具脚本置为反写态（ALIAS 映射写法已变：$(oneline "$REVLINE")）—— 夹具与实现不符"
  GUARD_REV_EVIDENCE="反写夹具置态失败（判定为 FAIL）"
fi

# 2.c 跨角色重名
FX_DUP="$(mk_fixture dup dup_alias)"
out="$(run_check "$FX_DUP")"; rc=$?
if [[ $rc -ne 0 && "$out" == *rd-be* ]]; then
  pass AC2 "③ 别名跨角色重名（qa 与 rd-be 均声明 \`rd-be\`）→ check rc=$rc 且指名问题"
else
  bad AC2 "③ 跨角色重名未使 check 非 0（rc=$rc；$(oneline "$out")）"
fi

# 2.d 别名空（现存行为，回归守护）
FX_EMPTY="$(mk_fixture empty empty_alias)"
out="$(run_check "$FX_EMPTY")"; rc=$?
if [[ $rc -ne 0 ]]; then
  pass AC2 "①' aliases: [] → check rc=$rc（既有守卫回归保持）"
else
  bad AC2 "①' aliases: [] 应非 0（rc=$rc）"
fi

# 2.e 别名字段缺失（现存行为，回归守护）
FX_MISS="$(mk_fixture miss missing_alias)"
out="$(run_check "$FX_MISS")"; rc=$?
if [[ $rc -ne 0 ]]; then
  pass AC2 "①'' aliases 字段缺失 → check rc=$rc（既有守卫回归保持）"
else
  bad AC2 "①'' aliases 字段缺失应非 0（rc=$rc）"
fi

# ---------------------------------------------------------------------------
sec "AC3 close 跨仓派生会话回收（hermetic；真回收需 --with-tmux）"

OTHERREPO="$FXROOT/otherrepo"; mkdir -p "$OTHERREPO"
ROSS_A='[{"name":"qa-T508","id":"qa-T508","status":"idle","cwd":"'"$OTHERREPO"'","tmuxPane":"%999"}]'

# 3.a 名册报在线（cwd=另一仓，tmuxPane 不存活）⇒ 不得静默「未运行（无需回收）」
out="$(NAO_QA_FAKE_ROSTER="$ROSS_A" run_fleet "$FX_MAIN" close --task T508 qa)"; rc=$?
if [[ $rc -eq 0 && "$out" == *"未运行（无需回收）"* ]]; then
  bad AC3 "跨仓 qa-T508：名册报在线（cwd=$OTHERREPO）却 rc=0 + 「未运行（无需回收）」= 静默失败"
  CROSSREPO_EVIDENCE="close --task T508 qa → rc=0 + 「未运行（无需回收）」而名册 cwd=另一仓"
else
  pass AC3 "跨仓 qa-T508 非静默（rc=$rc；$(oneline "$out")）"
  CROSSREPO_EVIDENCE="close --task T508 qa → rc=$rc 且未报「未运行（无需回收）」"
fi

# 3.b 派生会话名作目标（--task 分支）⇒ 不得报「未知角色」
out="$(NAO_QA_FAKE_ROSTER="$ROSS_A" run_fleet "$FX_MAIN" close --task T508 qa-T508)"; rc=$?
if [[ "$out" == *"未知角色"* ]]; then
  bad AC3 "close --task T508 qa-T508 → 仍报「未知角色」（派生名不被识别；rc=$rc）"
else
  pass AC3 "close --task T508 qa-T508 不再报「未知角色」（rc=$rc；$(oneline "$out")）"
fi
# 3.b' 无 --task 的派生名：名册在线时同样不得静默 no-op
out="$(NAO_QA_FAKE_ROSTER="$ROSS_A" run_fleet "$FX_MAIN" close qa-T508)"; rc=$?
if [[ $rc -eq 0 && "$out" == *"未运行（无需回收）"* ]]; then
  bad AC3 "close qa-T508（无 --task）：名册报在线却 rc=0 + 「未运行（无需回收）」= 静默 no-op"
else
  pass AC3 "close qa-T508（无 --task）非静默（rc=$rc；$(oneline "$out")）"
fi

# 3.c 真回收（opt-in）：自建独立 tmux pane（标题契约 + 名册 tmuxPane 双路），验「真的关掉」
if [[ $ALLOW_TMUX -eq 1 ]] && command -v tmux >/dev/null 2>&1; then
  TMUX_FIX_SESSION="t509qa-fx-$$"
  tmux kill-session -t "$TMUX_FIX_SESSION" 2>/dev/null || true
  if tmux new-session -d -s "$TMUX_FIX_SESSION" -c "$OTHERREPO" 2>/dev/null; then
    pane="$(tmux list-panes -t "$TMUX_FIX_SESSION" -F '#{pane_id}' 2>/dev/null | head -1)"
    tmux select-pane -t "$pane" -T "π - qa-QA2 - otherrepo" 2>/dev/null || true
    tmux send-keys -t "$pane" 'sleep 600' Enter 2>/dev/null || true
    ROSS_C='[{"name":"qa-QA2","id":"qa-QA2","status":"idle","cwd":"'"$OTHERREPO"'","tmuxPane":"'"$pane"'"}]'
    out="$(NAO_QA_FAKE_ROSTER="$ROSS_C" run_fleet "$FX_MAIN" close --task QA2 qa)"; rc=$?
    if ! tmux list-panes -t "$TMUX_FIX_SESSION" -F '#{pane_id}' 2>/dev/null | grep -qxF "$pane"; then
      pass AC3 "真回收：跨仓 pane $pane 已关闭（rc=$rc；$(oneline "$out")）"
    else
      bad AC3 "真回收失败：pane $pane 仍存活（rc=$rc；$(oneline "$out")）"
    fi
    tmux kill-session -t "$TMUX_FIX_SESSION" 2>/dev/null || true; TMUX_FIX_SESSION=""
  else
    skip AC3 "真回收：tmux 夹具会话创建失败（环境限制）"
  fi
else
  skip AC3 "真回收（跨仓 pane 实际关闭）：默认跳过（需 --with-tmux；避免污染 PM 共享 tmux）"
fi

# ---------------------------------------------------------------------------
sec "AC4 README / help 与 roles.yaml 别名一致"

EX="$(grep -m1 -E 'nao-fleet\.sh ensure ' "$README" 2>/dev/null | sed 's/#.*//')"
if [[ -z "$EX" ]]; then
  warn2 AC4 "README 未找到 \`nao-fleet.sh ensure ...\` 示例（无法核对）"
else
  n_bad=0; bad_list=""
  for t in ${EX#*ensure }; do
    case "$t" in -*|*@*|*/*) continue ;; esac
    out="$(NAO_QA_FAKE_ROSTER='[]' run_fleet "$FX_MAIN" close --task NAOQA9 "$t")"; rc=$?
    [[ $rc -eq 0 && "$out" != *"未知角色"* ]] || { n_bad=$((n_bad+1)); bad_list+="$t "; }
  done
  if [[ $n_bad -eq 0 ]]; then
    pass AC4 "README 示例命令全部别名可解析：$(printf '%s' "${EX#*ensure }" | tr -s ' ')"
  else
    bad AC4 "README 示例含不可解析别名（$n_bad 个）：$bad_list｜原句: $(oneline "$EX")"
  fi
fi

HDR="$(grep -m1 '当前：' "$FLEET" 2>/dev/null || true)"
if [[ -n "$HDR" ]]; then
  miss=""
  for a in arch arch-designer rd-fe rd-be qa rd-infra infra pm; do
    [[ "$HDR" == *"$a"* ]] || miss+="$a "
  done
  if [[ -z "$miss" ]]; then pass AC4 "nao-fleet.sh help 头部别名表覆盖全部别名"; else bad AC4 "help 头部缺别名：$miss"; fi
else
  warn2 AC4 "未找到 nao-fleet.sh help 别名表行"
fi

if grep -qE 'close' "$README" 2>/dev/null && grep -qE '派生|--task' "$README" 2>/dev/null; then
  pass AC4 "README 已含 close 用法与派生会话说明"
else
  warn2 AC4 "README 未写明 close 对「派生会话名（如 qa-T508）」支持与否 / 报错文案（AC3 尾款，人工核）"
fi

# ---------------------------------------------------------------------------
sec "AC5 门禁：npm test / tests/t4/run.sh / check / status"

t0=$(date +%s); no="$(cd "$ROOT" && npm test 2>&1)"; nrc=$?; t1=$(date +%s)
if [[ $nrc -eq 0 ]]; then pass AC5 "npm test exit=0（$((t1-t0))s）"; else bad AC5 "npm test exit=$nrc（$(oneline "$no")）"; fi

t0=$(date +%s); to="$(cd "$ROOT" && bash tests/t4/run.sh 2>&1)"; trc=$?; t1=$(date +%s)
t4_cases="$(printf '%s' "$to" | grep -cE '^  [0-9]{2}  (PASS|FAIL|SKIP|BLOCKED|MISSING)')"
t4_pass="$(printf '%s' "$to" | grep -c '\[PASS\]')"
t4_fail="$(printf '%s' "$to" | grep -c '\[FAIL\]')"
t4_blk="$(printf '%s' "$to" | grep -c '\[BLOCKED\]')"
printf '   tests/t4: rc=%s · 用例=%s · PASS=%s · FAIL=%s · BLOCKED=%s · %ss\n' \
  "$trc" "$t4_cases" "$t4_pass" "$t4_fail" "$t4_blk" "$((t1-t0))"
if [[ $trc -eq 0 && $t4_fail -eq 0 && $t4_blk -eq 0 && $t4_pass -ge 109 ]]; then
  pass AC5 "tests/t4/run.sh 全绿（断言 PASS=$t4_pass ≥ 基线 109）"
else
  bad AC5 "tests/t4/run.sh 未全绿（rc=$trc FAIL=$t4_fail BLOCKED=$t4_blk PASS=$t4_pass）"
fi
if [[ "$MODE" == baseline ]]; then
  if [[ $t4_cases -ge 8 ]]; then pass AC5 "用例数=$t4_cases（基线 8；修复后应 ≥9）"; else bad AC5 "用例数 $t4_cases < 基线 8"; fi
else
  if [[ $t4_cases -ge 9 ]]; then pass AC5 "用例数=$t4_cases ≥ 9（含新增守卫/回收用例）"; else bad AC5 "用例数=$t4_cases < 9（未新增守卫/回收用例）"; fi
fi

out="$(cd "$ROOT" && bash "$FLEET" check 2>&1)"; rc=$?
if [[ $rc -eq 0 && "$out" == *"roles=6"* ]]; then pass AC5 "nao-fleet.sh check exit=0 且 roles=6"; else bad AC5 "check rc=$rc / roles≠6（$(oneline "$out")）"; fi

sout="$(cd "$ROOT" && timeout 60 bash "$FLEET" status 2>&1)"; src=$?
if [[ $src -eq 0 ]]; then pass AC5 "status exit=0"; else bad AC5 "status exit=$src（$(oneline "$sout")）"; fi
# 跨仓派生会话若在跑：status 不得把它报成未运行/残留
cross_live=0
if command -v tmux >/dev/null 2>&1; then
  while IFS= read -r t; do
    case "$t" in "π - "*) : ;; *) continue ;; esac
    ses="${t#π - }"; ses="${ses%% - *}"; base="${t##* - }"
    case "$ses" in *-*) case "$base" in nao-skills) : ;; *) cross_live=$((cross_live+1)); \
      if [[ "$sout" == *"$ses"* ]]; then pass AC5 "status 列出跨仓派生会话 $ses（未误报未运行）"; else bad AC5 "status 漏报在跑的跨仓派生会话 $ses"; fi ;; esac ;; esac
  done < <(tmux list-panes -a -F '#{pane_title}' 2>/dev/null || true)
fi
(( cross_live )) || skip AC5 "status 跨仓派生会话假残留核对：当前无「π - <角色>-<批次> - <非本仓>」存活 pane"

# ---------------------------------------------------------------------------
sec "AC6 负向闭环：三批已迁移仓 check（NFR4）+ 版本一致性"

for d in "${DOWNSTREAM[@]}"; do
  if [[ ! -f "$d/.agents/scripts/nao-fleet.sh" ]]; then skip AC6 "$d 无 shim（跳过）"; continue; fi
  o="$(cd "$d" && NAO_SKILLS="$ROOT" timeout 60 bash .agents/scripts/nao-fleet.sh check 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$o" == *"roles=6"* ]]; then
    pass AC6 "NFR4 $d：以修复后机制 check rc=0 roles=6"
  else
    bad AC6 "NFR4 $d：check rc=$rc（$(oneline "$o")）"
  fi
  o2="$(cd "$d" && timeout 60 bash .agents/scripts/nao-fleet.sh check 2>&1)"; rc2=$?
  inst="$(node -p "require('$d/.pi/npm/node_modules/@nathan33/nao-skill/package.json').version" 2>/dev/null || echo '?')"
  note "$d：pin 包 $inst check(现状) rc=$rc2 | $(oneline "$o2")"
done

pv="$(node -p "require('$ROOT/package.json').version" 2>/dev/null || echo '?')"
if [[ "$pv" == "0.12.1" ]]; then pass AC6 "package.json version=0.12.1"; else bad AC6 "package.json version=$pv（期望 0.12.1）"; fi
rel="$ROOT/docs/releases/v0.12.1.md"
if [[ -f "$rel" ]] && grep -q '0.12.1' "$rel"; then
  pass AC6 "docs/releases/v0.12.1.md 存在且含 0.12.1"
  if grep -qE '升级' "$rel" && grep -qE '留意|影响|行为有变化' "$rel"; then
    pass AC6 "release notes 用户可读（改了什么 / 行为变化与影响 / 如何升级）"
  else
    warn2 AC6 "release notes 缺「影响/留意」或「升级方式」语段（用户可读性需 PM 人眼核）"
  fi
else
  bad AC6 "docs/releases/v0.12.1.md 缺失或不含 0.12.1（$rel）"
fi

# ---------------------------------------------------------------------------
sec "AC7 提交治理 / AC8 非范围守护"

BR="$(cd "$ROOT" && git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
CNT="$(cd "$ROOT" && git rev-list --count main..HEAD 2>/dev/null || echo 0)"
if [[ "$BR" == "main" || "$CNT" == "0" ]]; then
  skip AC7 "提交治理（恰好 1 条 / 无 wip() / PR 标题可读 / 工作区干净）：当前分支 $BR、领先 main $CNT 提交 ⇒ 未开分支/未提交"
  skip AC8 "非范围守护（diff 未碰 bin/ · .agents/skills|common|checklists|templates · 历史归档既有条目）：无分支 diff"
else
  # AC7：预合并态按 PM 裁定记 WARN（判据：squash 后 main 恰 1 条且无 wip()）
  wips="$(cd "$ROOT" && git log --format=%s main..HEAD 2>/dev/null | grep -cE '^wip\(' || true)"
  if [[ "$CNT" == "1" && "$wips" == "0" ]]; then
    pass AC7 "恰 1 条提交且无 wip()"
  else
    warn2 AC7 "预合并态：提交数=$CNT（squash 后须恰 1）· wip()=$wips（squash 后须 0）—— 按 PM 裁定记 WARN"
  fi
  dirty="$(cd "$ROOT" && git status --porcelain 2>/dev/null | grep -vE '^\?\?' | wc -l | tr -d ' ')"
  if [[ "$dirty" == "0" ]]; then pass AC7 "工作区无已跟踪改动（untracked QA/PRD 产物不计）"; else bad AC7 "工作区有 $dirty 个已跟踪改动"; fi

  # AC8（PM 裁定口径）：
  #   a) 禁碰路径零命中（任意状态，含新增）
  #   b) 既有历史条目零改动：与 main 基线文件清单比对，main 中已存在的 docs/{adr,prds,releases} 条目不得 M/D/R/T
  #      （本批**新建** docs/releases/v0.12.1.md 属 PRD §3 IN，不计违规）
  ST="$(cd "$ROOT" && git diff --name-status main...HEAD 2>/dev/null || true)"
  ALLPATHS="$(printf '%s\n' "$ST" | awk 'NF{print $NF}' | grep -c . || true)"
  hitF="$(printf '%s\n' "$ST" | awk '{print $NF}' | grep -E '^(bin/|\.agents/skills/|\.agents/common/|\.agents/checklists/|\.agents/templates/)' || true)"
  if [[ -z "$hitF" ]]; then
    pass AC8 "a) 禁碰路径零命中（bin/ · .agents/skills|common|checklists|templates；diff 共 $ALLPATHS 个文件）"
  else
    bad AC8 "a) 命中禁碰路径：$(printf '%s' "$hitF" | tr '\n' ' ')"
  fi
  BASE="$(cd "$ROOT" && git ls-tree -r --name-only main 2>/dev/null || true)"
  hitH="$(printf '%s\n' "$ST" | awk '$1!="A"{print $NF}' | while IFS= read -r p; do
      [[ -n "$p" ]] || continue
      printf '%s\n' "$BASE" | grep -qxF "$p" || continue
      case "$p" in docs/adr/*|docs/prds/*|docs/releases/*) printf '%s\n' "$p" ;; esac
    done)"
  if [[ -z "$hitH" ]]; then
    pass AC8 "b) 既有历史归档条目零改动（main 基线 docs/{adr,prds,releases} 逐项比对；新建条目不计）"
  else
    bad AC8 "b) 既有历史归档被改动：$(printf '%s' "$hitH" | tr '\n' ' ')"
  fi
  note "AC8 改动清单（name-status main...HEAD）：$(printf '%s' "$ST" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
sec "V1–V4 待验证项（信息性）"

v1="$(grep -n 'ALIAS_ROLE' "$FLEET" | grep -c 'ALIAS_ROLE\[' || true)"
note "V1 ALIAS_ROLE 消费点：$(grep -n 'ALIAS_ROLE\[' "$FLEET" | tr '\n' ' | ')"
note "V1 写入点仅 load_manifest（L135）；读取点 resolve_role(L276) + close(L1127/1128) ⇒ 修复单点即可，方向一致"
note "V2 find_pane_for 三级后备（代码）：① find_pane_by_title 要求「π - <会话名> - <repo basename>」且 repo=ROLE_WS 解析值；② intercom_pane_for 要求名册 cwd==abs(repo)；③ fallback_pane_for 要求 pane_current_path==abs(repo)。跨仓会话 cwd 为**目标仓**、repo 却由 roles.yaml workspace(.) 取成本仓 ⇒ 三级全不命中"
if command -v tmux >/dev/null 2>&1; then
  note "V2 现存活 pane 标题/路径对照：$(tmux list-panes -a -F '#{pane_title}@#{pane_current_path}' 2>/dev/null | tr '\n' ' | ')"
fi
v3="$(grep -rlE 'ALIAS_ROLE|aliases\b' "$ROOT/tests" 2>/dev/null | tr '\n' ' ')"
note "V3 tests/t4 现有 8 用例对 roles.yaml 解析覆盖：仅 05-migration 把 roles.yaml 当备份产物；无别名解析/守卫用例（命中：${v3:-无}）⇒ 守卫用例宜新增 case 09（或扩 06-contract-guards）"
note "V4 三仓 NFR4 证据见 AC6；修复前基线三仓 check 均 rc=0 roles=6（pin=0.12.0）"

# ---------------------------------------------------------------------------
printf '\n==================== T509 汇总（模式=%s）====================\n' "$MODE"
for ac in AC1 AC2 AC3 AC4 AC5 AC6 AC7 AC8; do
  p=${AC_P[$ac]:-0}; f=${AC_F[$ac]:-0}; s=${AC_S[$ac]:-0}; w=${AC_W[$ac]:-0}
  if (( f > 0 )); then st="RED"
  elif (( p > 0 )); then st="PASS"
  elif (( s > 0 )); then st="SKIP"
  else st="—"; fi
  printf '  %-4s %-5s PASS=%s FAIL=%s SKIP=%s WARN=%s\n' "$ac" "$st" "$p" "$f" "$s" "$w"
done
printf '\n  合计: PASS=%s FAIL=%s SKIP=%s WARN=%s\n' "$PASS_N" "$FAIL_N" "$SKIP_N" "$WARN_N"
if (( ${#FAILED[@]} > 0 )); then
  printf '  FAIL 明细:\n'
  for f in "${FAILED[@]}"; do printf '    - %s\n' "$f"; done
fi
printf '\n  一句话证据:\n'
printf '    · 守卫缺失: %s\n' "${GUARD_REV_EVIDENCE:-未采集}"
printf '    · 跨仓回收: %s\n' "${CROSSREPO_EVIDENCE:-未采集}"

if (( FAIL_N > 0 )); then
  if [[ "$MODE" == baseline ]]; then
    printf '\nRESULT: %d FAIL（基线模式：修复前现树，FAIL 属预期）· exit 0\n' "$FAIL_N"
    exit 0
  fi
  printf '\nRESULT: FAIL · exit 1\n'
  exit 1
fi
printf '\nRESULT: PASS · exit 0\n'
exit 0
