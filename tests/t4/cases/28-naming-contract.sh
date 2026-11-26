#!/usr/bin/env bash
# 用例 28 — 命名契约 v3 + 元数据面 + 身份还原（T571 / ADR 2026-11-25-term-facade-neutral-contract）
#
# 判据（决策一）：
#   ① 名字 = <role>[<N>]，**task 不进身份**；构造器多传 task ⇒ fail loud（不静默忽略）。
#   ② 解析面 v3 新形 + 只读兼容 v2 `role(task)` / legacy `role-task` / `role-task@scope`。
#   ③ 槽位号不承载语义：`role2` 解析只给 num，task 只认元数据。
#   ④ 元数据：app `nao.task` / `nao.name` label；herdr sidecar（原子写、按 handle 清、孤儿扫描）。
#   ⑤ 身份还原：labels.nao.name → 后端 name → argv --name（仅 pi 且可被 fleet_name_parse 识别）。
#   ⑥ 名称合法化：小写化 / 非法字符→`-` / 首字符补齐 / 截 32 且保留槽位后缀。
#   ⑦ 用法面：ensure --task 同 (role,task) 复用；close --task 按元数据匹配（0=未运行，>1=不猜）；
#      status --json 增 task，文本派生节尾注 task=<id>。
#
# 本文件 = **整组重写**（不是改旧断言）：旧 C2 golden / tmux 面已随 T555 退役；v3 改动面覆盖
#   C1 纯函数、C3 静态闸、app/herdr 两臂元数据、身份还原、sidecar 孤儿清理与四条失败演练。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SUBJECT="$T4_ROOT/.agents/scripts/nao-fleet.sh"
SUBJECT_BUNDLE="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"
BASH_BIN="$(command -v bash)"
CONTRACT_BEGIN='^# >>> fleet-name-contract BEGIN'
CONTRACT_END='^# <<< fleet-name-contract END'
FIXT_APP="$T4_ROOT/tests/t4/fixtures/hc-double"
FIXT_HERDR="$T4_ROOT/tests/t4/fixtures/herdr-double"
FLEET_MOD="$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_app_spawn)"

extract_contract() {
  awk -v b="$CONTRACT_BEGIN" -v e="$CONTRACT_END" '$0 ~ b { f=1; next } $0 ~ e { f=0 } f' "$1"
}
mutate_file() { # <src> <dst> <old> <new>（锚点必须恰 1 次；否则 rc=4）
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src,dst,old,new=sys.argv[1:5]
s=open(src,encoding='utf-8').read()
n=s.count(old)
if n!=1:
    print(f'MUTATION-ANCHOR: 命中 {n} 次（期望恰 1）: {old}',file=sys.stderr)
    sys.exit(4)
open(dst,'w',encoding='utf-8').write(s.replace(old,new))
PY
}
mutate_many() { # <src> <dst> <old1> <new1> [<old2> <new2> ...]
  python3 - "$@" <<'PY'
import sys
src,dst,*pairs=sys.argv[1:]
s=open(src,encoding='utf-8').read()
for old,new in zip(pairs[::2],pairs[1::2]):
    n=s.count(old)
    if n!=1:
        print(f'MUTATION-ANCHOR: 命中 {n} 次（期望恰 1）: {old}',file=sys.stderr)
        sys.exit(4)
    s=s.replace(old,new)
open(dst,'w',encoding='utf-8').write(s)
PY
}
clone_for_mut() { # <name> <anchor> → MUT_ENTRY / MUT_MOD（禁在 $() 里调）
  local name="$1" anchor="$2" root=""
  root="$LAB/mut-$name"
  MUT_ENTRY=""; MUT_MOD=""
  MUT_ENTRY="$(t4_fleet_clone "$T4_ROOT/.agents/scripts" "$root")" || return 1
  MUT_MOD="$(t4_fleet_file_with "$root" "$anchor")" || return 1
  [ -n "$MUT_MOD" ] || return 1
  return 0
}

# ============================================================================
# C1 纯函数（子进程；只 source 契约块，零后端/零仓库）
# ============================================================================
if [ "${T4_28_C1_CHILD:-0}" = "1" ]; then
  CONTRACT="${T4_28_CONTRACT:?子进程需要 T4_28_CONTRACT}"
  W="$(mktemp -d "${T4_CACHE_DIR:-/tmp}/c1.XXXXXX")"
  trap 'rm -rf "$W"' EXIT
  OKN=0; BADN=0
  chk() { if [ "$2" = "$3" ]; then OKN=$((OKN+1)); else BADN=$((BADN+1)); printf '  ✗ %s\n    want=[%s]\n    got =[%s]\n' "$1" "$2" "$3"; fi; }
  declare -A FLEET_ROLE_KIND
  for r in pm arch-designer uiux-designer rd-fe rd-be qa rd-infra; do FLEET_ROLE_KIND[$r]=resident; done
  FLEET_ROLE_KIND[sec-review]=card
  source "$CONTRACT"
  b() { fleet_name_build "$@" 2>/dev/null; }
  p() { fleet_name_parse "$@"; }
  bn() { fleet_backend_name "$@"; }

  # ---- ① v3 构造：task 不出现 ----
  chk "① build(resident,pm) == pm" "pm" "$(b resident pm)"
  chk "① build(resident,pm,2) == pm2" "pm2" "$(b resident pm 2)"
  chk "① build(derived,rd-be) == rd-be（kind 只是语义标签）" "rd-be" "$(b derived rd-be)"
  chk "① build(card,sec-review,2) == sec-review2" "sec-review2" "$(b card sec-review 2)"
  out="$(fleet_name_build resident pm "" T1 2>&1)"; rc=$?
  chk "① build 多传 task ⇒ fail loud（rc=1）" "1" "$rc"
  chk "① build 多传 task ⇒ 文案点明 task/元数据" "1" "$(printf '%s' "$out" | grep -ci 'task' || true)"
  out="$(fleet_core_build pm 2 T1 2>&1)"; rc=$?
  chk "① core_build 多传 task ⇒ fail loud（rc=1）" "1" "$rc"
  chk "① core_build 多传 task ⇒ 文案点明 task" "1" "$(printf '%s' "$out" | grep -ci 'task' || true)"

  # ---- ② 解析：v3 新形 + 只读旧形 ----
  chk "② parse(pm)" "OK resident,pm,," "$(p pm)"
  chk "② parse(pm2)" "OK resident,pm,,2" "$(p pm2)"
  chk "② parse(rd-be2)（槽位号不带语义）" "OK resident,rd-be,,2" "$(p rd-be2)"
  chk "② parse(v2 rd-be(T1)) 只读" "OK derived,rd-be,T1," "$(p 'rd-be(T1)')"
  chk "② parse(v2 rd-be2(T553)) 只读" "OK derived,rd-be,T553,2" "$(p 'rd-be2(T553)')"
  chk "② parse(legacy rd-be-T1)" "LEGACY OK derived,rd-be,T1," "$(p rd-be-T1)"
  chk "② parse(legacy pm@todo)" "LEGACY OK resident,pm,,todo" "$(p pm@todo)"
  chk "② parse(legacy rd-be-T1@todo)" "LEGACY OK derived,rd-be,T1,todo" "$(p rd-be-T1@todo)"
  chk "② parse(card sec-review2)" "OK card,sec-review,,2" "$(p sec-review2)"
  chk "② 别名不得被 parse 当角色" "ERR" "$(p arch)"
  chk "② parse(sec-review@todo) ERR（v2 卡不再有 scope）" "ERR" "$(p sec-review@todo)"

  # ---- ③ 非法/越界一律 ERR ----
  L49="rd-be-$(printf 'T%.0s' $(seq 1 44))"
  for bad in "" "rd-fe@" "@todo" "rd-fe@@todo" "rd-fe@TODO" "rd-fe@a.b" "rd-fe@$L49" \
             "subagent-x@y" "nao-x@y" "$L49" "rd_fe" "rd-fe@todo!" "rd-fe@-x" "rd-fe@x-" \
             "rd-fe " " rd-fe" "RD-FE" "unknown-role" "pm1" "pm0" "pm10" "pm2x" \
             "arch-designer(T554" "arch-designerT554)" "arch-designer((T554))" "arch-designer(T5)4" \
             "rd-be(T553)2" "rd-be2(T553)@x"; do
    chk "③ 非法输入必须 ERR：[${bad}]" "ERR" "$(p "$bad")"
  done
  chk "③ build 槽位 1 非法" "1" "$(b resident rd-be 1 >/dev/null 2>&1; echo $?)"
  chk "③ build 未知 kind 拒绝" "1" "$(b bogus rd-be >/dev/null 2>&1; echo $?)"

  # ---- ④ 后端合法名映射 ----
  chk "④ 大写/括号 → 小写 + 连字符" "my_role-t1-" "$(bn 'My_Role(T1)')"
  chk "④ 点号保留" "code.reviewer" "$(bn 'Code.Reviewer')"
  chk "④ 纯大写归一" "rd-fe" "$(bn RD-FE)"
  chk "④ 空名 → session" "session" "$(bn '')"
  long="$(printf 'a%.0s' $(seq 1 40))2"
  chk "④ 截 32 且保留槽位后缀" "$(printf 'a%.0s' $(seq 1 31))2" "$(bn "$long")"
  chk "④ 首字符补齐（非字母数字）" "s-_x" "$(bn '_x')"

  if [ "$BADN" -gt 0 ]; then printf 'C1_FAIL ok=%d bad=%d\n' "$OKN" "$BADN"; exit 1; fi
  printf 'C1_OK %d\n' "$OKN"; exit 0
fi

# ============================================================================
# 父进程：C1 正控 + 变异负控 + C3 静态闸 + app/herdr 两臂
# ============================================================================
C1_BASE="$T4_CACHE_DIR/c28-contract.sh"
extract_contract "$SUBJECT_BUNDLE" > "$C1_BASE"
t4_assert_ne "0" "$(wc -l < "$C1_BASE" | tr -d ' ')" "C1 契约块可抽取（非空）"
run_c1() { T4_28_C1_CHILD=1 T4_28_CONTRACT="${1:-$C1_BASE}" T4_CACHE_DIR="$T4_CACHE_DIR" "$BASH_BIN" "$SELF" 2>&1; }
if det="$(run_c1)"; then
  t4_ok "C1 v3 纯函数全绿（构造/解析/合法名）"
  t4_info "C1 断言数：$(printf '%s' "$det" | sed -n 's/^C1_OK \([0-9]*\)$/\1/p')"
else
  t4_bad "C1 v3 纯函数未全绿"; printf '%s\n' "$det" | sed -e 's/^/    /' | head -16
fi
mutation_neg() { # <label> <mutated-contract>
  local label="$1" f="$2" rc=0
  run_c1 "$f" >/dev/null 2>&1 || rc=$?
  t4_assert_ne "0" "$rc" "C1 变异负控：$label ⇒ 必红（断言不空转）"
}
M="$T4_CACHE_DIR/c28-m1.sh"
if mutate_file "$C1_BASE" "$M" 'printf '"'"'%s%s\n'"'"' "$role" "$num"' 'printf '"'"'%s%s-x\n'"'"' "$role" "$num"'; then
  mutation_neg "M1 构造器追加 -x" "$M"
else t4_bad "M1 锚点未命中"; fi
M="$T4_CACHE_DIR/c28-m2.sh"
if mutate_file "$C1_BASE" "$M" 'else task="${pre:${#role}+1}"; fi' 'else task=""; fi'; then
  mutation_neg "M2 legacy 解析丢 task" "$M"
else t4_bad "M2 锚点未命中"; fi
M="$T4_CACHE_DIR/c28-m3.sh"
if mutate_file "$C1_BASE" "$M" 'core="${core:0:$(( 32 - ${#num} ))}"' 'core="$core"'; then
  mutation_neg "M3 合法名不截 32" "$M"
else t4_bad "M3 锚点未命中"; fi
M="$T4_CACHE_DIR/c28-m4.sh"
if mutate_file "$C1_BASE" "$M" 'fleet_scope_problem "$scope" >/dev/null || { printf '"'"'ERR\n'"'"'; return 0; }' ':'; then
  mutation_neg "M4 非法 legacy scope 放行" "$M"
else t4_bad "M4 锚点未命中"; fi

# ---------------------------------------------------------------- C3 静态闸
t4_assert_eq "1" "$(grep -c 'exec pi --name' "$SUBJECT_BUNDLE" || true)" "C3① 唯一 exec pi --name 点"
t4_assert_eq "0" "$(grep -cE 'fleet_name_build[^\\n]*\\$\\{?task' "$SUBJECT_BUNDLE" || true)" \
  "C3② 调用点不再把 task 传给构造器"
t4_assert_contains "$(cat "$FLEET_MOD" 2>/dev/null)" 'fleet_backend_name "$name"' "C3③ app spawn 使用合法化名"
t4_assert_contains "$(cat "$FLEET_MOD" 2>/dev/null)" '--name "$legal"' "C3③ hc run --name = 合法化名"
t4_assert_contains "$(cat "$FLEET_MOD" 2>/dev/null)" 'nao.name' "C3③ app 写 nao.name 原始名标签"
t4_assert_contains "$(cat "$FLEET_MOD" 2>/dev/null)" 'nao.task' "C3③ app 写 nao.task 元数据标签"
t4_assert_ge "1" "$(grep -c 'fleet_meta_write' "$SUBJECT_BUNDLE" || true)" "C3④ herdr sidecar 写入点存在"
t4_assert_ge "2" "$(grep -c 'fleet_meta_gc' "$SUBJECT_BUNDLE" || true)" "C3④ 孤儿扫描接入点 ≥2（ensure/status）"
t4_assert_contains "$(awk '/^_term_app_identity\(\)/,/^}/' "$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_app_identity)")" \
  'TERM_APP_LABEL_NAME' "C3⑤ 身份还原第一层 = labels.nao.name"
# 身份还原顺序：nao.name 行 < backend name 行 < argv --name 行
id_body="$(awk '/^_term_app_identity\(\)/,/^}/' "$(t4_fleet_file_for "$T4_ROOT/.agents/scripts" _term_app_identity)")"
ln_label="$(printf '%s\n' "$id_body" | grep -n 'TERM_APP_LABEL_NAME' | head -1 | cut -d: -f1)"
ln_name="$(printf '%s\n' "$id_body" | grep -n '_term_app_field "$g" name' | head -1 | cut -d: -f1)"
ln_argv="$(printf '%s\n' "$id_body" | grep -n '_term_argv_name' | head -1 | cut -d: -f1)"
t4_assert_eq "1" "$([ -n "$ln_label" ] && [ -n "$ln_name" ] && [ -n "$ln_argv" ] && (( ln_label < ln_name && ln_name < ln_argv )) && echo 1 || echo 0)" \
  "C3⑤ 身份还原顺序 = nao.name → name → argv --name"

# C3② 名字拼接 lint（构造器外出现 `name/core = role-task` ⇒ 必红）
lint2() {
  awk -v b="$CONTRACT_BEGIN" -v e="$CONTRACT_END" '
    $0 ~ b { f=1; next } $0 ~ e { f=0; next } f { next } { print }' "$1" \
    | grep -cE '(^|[^A-Za-z0-9_])(name|disp|core)="?(\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)?-\$(\{)?(task|TASK)' || true
}
t4_assert_eq "0" "$(lint2 "$SUBJECT_BUNDLE")" "C3② 真脚本：契约块外 0 处手写名字/core 拼接"
NEG_A="$T4_CACHE_DIR/c28-c3-neg-a.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_A" '  local force="$1" task="$2" target="${3:-}"' \
     '  local force="$1" task="$2" target="${3:-}"
  name="${NAME}-${task}"'; then
  t4_assert_ne "0" "$(lint2 "$NEG_A")" "C3② 负控A：注入 name=\"\${NAME}-\${task}\" ⇒ 必红"
else t4_bad "C3② 负控A 锚点未命中"; fi
NEG_A2="$T4_CACHE_DIR/c28-c3-neg-a2.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_A2" '  local force="$1" task="$2" target="${3:-}"' \
     '  local force="$1" task="$2" target="${3:-}"
  core="$NAME-$task"'; then
  t4_assert_ne "0" "$(lint2 "$NEG_A2")" "C3② 负控A2：注入 core=\"\$NAME-\$task\"（无花括号形，历史缺陷同形）⇒ 必红"
else t4_bad "C3② 负控A2 锚点未命中"; fi
NEG_MX="$T4_CACHE_DIR/c28-c3-neg-matrix.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_MX" '  local force="$1" task="$2" target="${3:-}"' \
     '  local force="$1" task="$2" target="${3:-}"
  core="${NAME}-${task}"
  core="$NAME-$task"
  core="$NAME-${task}"
  core="${NAME}-$task"
  name="$NAME-$task"
  disp="$NAME-$task"
  core="${t_names[$i]}-${task}"
  core="$card_role-$task"'; then
  t4_assert_eq "8" "$(lint2 "$NEG_MX")" "C3② 形态矩阵：8 种拼接写法全抓（判据与声明一致）"
else t4_bad "C3② 形态矩阵锚点未命中"; fi
CORE_BODY="$T4_CACHE_DIR/c28-core-body.sh"
awk '/^fleet_core_build\(\)/{f=1} f{print} f&&/^}/{exit}' "$SUBJECT_BUNDLE" > "$CORE_BODY"
t4_assert_eq "0" "$(lint2 "$CORE_BODY")" "C3② 正控：唯一构造点自身 0 命中（不误判合法拼法）"

# C3④ herdr 放置键 lint（spawn 内不得取会话名 / 重算仓基键）
spawn_body() { awk '/^_term_herdr_spawn\(\)/,/^}/' "$1"; }
lint4()  { spawn_body "$1" | grep -c 'HERDR_SESSION' || true; }
lint4b() { spawn_body "$1" | grep -c 'place_key_label' || true; }
t4_assert_eq "0" "$(lint4 "$SUBJECT_BUNDLE" || true)" "C3④ 真脚本：spawn 内不取 HERDR_SESSION（放置键只认入参 label）"
t4_assert_eq "0" "$(lint4b "$SUBJECT_BUNDLE" || true)" "C3④ 真脚本：spawn 内不重算 place_key_label"
NEG_D="$T4_CACHE_DIR/c28-c3-neg-d.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_D" \
     '  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" task="${7-}" pl="" obj js line' \
     '  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" task="${7-}" pl="" obj js line; : "${HERDR_SESSION:-}"'; then
  t4_assert_eq "1" "$(lint4 "$NEG_D" || true)" "C3④ 负控：spawn 内注入 HERDR_SESSION ⇒ 命中 1（判据非空转）"
else t4_bad "C3④ 负控锚点未命中"; fi
NEG_D2="$T4_CACHE_DIR/c28-c3-neg-d2.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_D2" \
     '  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" task="${7-}" pl="" obj js line' \
     '  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="$(place_key_label "$repo")" group="${6-}" task="${7-}" pl="" obj js line'; then
  t4_assert_eq "1" "$(lint4b "$NEG_D2" || true)" "C3④ 负控2：spawn 内重算 slug ⇒ 命中 1（D1 零调用判据不空转）"
else t4_bad "C3④ 负控2 锚点未命中"; fi

# C3⑤ 起 server 身份禁读环境变量（T544）
lint5() { grep -nE '\$\{?_TERM_HERDR_SERVER_START|^[[:space:]]*(\([[:space:]]*)?_TERM_HERDR_SERVER_START=' "$1" || true; }
t4_assert_eq "" "$(lint5 "$SUBJECT_BUNDLE")" "C3⑤ 真脚本：不读 _TERM_HERDR_SERVER_START（唯一形态 = -u 迁移带）"
NEG_E="$T4_CACHE_DIR/c28-c3-neg-e.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_E" '  local s="${HERDR_SESSION:-}" v ss=0' \
     '  local s="${HERDR_SESSION:-}" v ss=0
  if [[ "${_TERM_HERDR_SERVER_START:-0}" == "1" ]]; then :; fi'; then
  t4_assert_match "$(lint5 "$NEG_E")" '^[0-9]+:.*_TERM_HERDR_SERVER_START' "C3⑤ 负控1：历史读取形 ⇒ 必红并点名行号"
else t4_bad "C3⑤ 负控1 锚点未命中"; fi
NEG_F="$T4_CACHE_DIR/c28-c3-neg-f.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_F" '  local s="${HERDR_SESSION:-}" v ss=0' \
     '  local s="${HERDR_SESSION:-}" v ss=0
  : "$_TERM_HERDR_SERVER_START"'; then
  t4_assert_match "$(lint5 "$NEG_F")" '^[0-9]+:.*_TERM_HERDR_SERVER_START' "C3⑤ 负控2：裸变量读取形 ⇒ 必红"
else t4_bad "C3⑤ 负控2 锚点未命中"; fi
NEG_G="$T4_CACHE_DIR/c28-c3-neg-g.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_G" '  local s="${HERDR_SESSION:-}" v ss=0' \
     '  local s="${HERDR_SESSION:-}" v ss=0
  _TERM_HERDR_SERVER_START=1 :'; then
  t4_assert_match "$(lint5 "$NEG_G")" '^[0-9]+:.*_TERM_HERDR_SERVER_START=1' "C3⑤ 负控3：命令行位前置赋值形 ⇒ 必红"
else t4_bad "C3⑤ 负控3 锚点未命中"; fi
t4_assert_eq "1" "$(grep -c -- '-u _TERM_HERDR_SERVER_START' "$SUBJECT_BUNDLE" || true)" \
  "C3⑤ 正控：迁移带「-u _TERM_HERDR_SERVER_START」仍在场（不是靠删干净凑绿）"

# ============================================================================
# 夹具：app 臂（hc-double）
# ============================================================================
LAB="$T4_CACHE_DIR/lab28-$$"
mkdir -p "$LAB" || { t4_bad "无法建 lab"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
PATH="$FIXT_APP:$PATH"; export PATH
be_app_init "$LAB" "lab28-$$" || { t4_bad "be_app_init 失败"; t4_exit; }
be_app_arm_cleanup
APP_RC=0; APP_OUT=""; APP_ERR=""
run_app() {
  local -a envs=(NAO_TERMINAL=app "HC_SCOPE=$BE_SESSION" HC_TERMINAL_ID=t0
    "HC_TERMINAL_SOCKET=$BE_APP_SOCK" "XDG_RUNTIME_DIR=$BE_APP_RT"
    "HC_DOUBLE_STATE=$BE_APP_STATE" "PATH=$FIXT_APP:$PATH" "NAO_SKILLS=$LAB"
    "HOME=$LAB/.t4-home" "PI_CODING_AGENT_DIR=$LAB/.t4-home/.pi/agent")
  local script="${BE_FLEET_SCRIPT:-$LAB/.agents/scripts/nao-fleet.sh}"
  t4_run_in_dir "$LAB" env "${envs[@]}" timeout "${BE_FLEET_TIMEOUT:-120}" bash "$script" "$@"
  APP_RC=$T4_RC; APP_OUT="$T4_OUT"; APP_ERR="$T4_ERR"
}
stub_hc() { HC_DOUBLE_STATE="$BE_APP_STATE" "$FIXT_APP/hc" "$@"; }
app_addrs() { find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^t0$' | sort -V; }
app_field() { head -1 "$BE_APP_STATE/t/$1/$2" 2>/dev/null; }
addr_of() { local a; for a in $(app_addrs); do [ "$(app_field "$a" name)" = "$1" ] && { printf '%s' "$a"; return; }; done; }
addr_by_nao() { local a; for a in $(app_addrs); do [ "$(app_field "$a" nao_name)" = "$1" ] && { printf '%s' "$a"; return; }; done; }
app_reset() {
  find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d ! -name t0 -exec rm -rf {} + 2>/dev/null || true
  find "$BE_APP_STATE/spaces" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  rm -f "$BE_APP_STATE/t/t0/space" "$BE_APP_STATE/t/t0/tab"
  : > "$BE_APP_STATE/log"
  rm -f "$BE_APP_STATE"/{name_null,argv_name,fg,bare_get,bare_labels,adopt_delay,adopt_never,stale_ids,space_refuse} 2>/dev/null || true
  return 0
}
app_state_file() { printf '%s\n' "$BE_APP_STATE/t/${1}/${2}"; }

# ---------------------------------------------------------------- app 臂：元数据 + 用法面
app_reset
run_app ensure --task T1 rd-fe
A1="$(addr_of rd-fe)"
t4_assert_eq "0" "$APP_RC" "app① ensure --task T1 rd-fe rc=0"
t4_assert_ne "" "$A1" "app① 终端已建立"
t4_assert_eq "rd-fe" "$(app_field "$A1" name)" "app① hc run --name = v3 名（不含 task/括号）"
t4_assert_eq "T1" "$(app_field "$A1" nao_task)" "app① nao.task=T1 落标签"
t4_assert_eq "rd-fe" "$(app_field "$A1" nao_name)" "app① nao.name=rd-fe 原始名落标签"
run_app status
t4_assert_contains "$APP_OUT" "task=T1" "app① 文本 status 派生节尾注 task=T1"
run_app status --json
t4_assert_contains "$APP_OUT" '"name":"rd-fe"' "app① status --json 含会话名"
t4_assert_contains "$APP_OUT" '"kind":"derived"' "app① status --json kind=derived（task 来自元数据）"
t4_assert_contains "$APP_OUT" '"task":"T1"' "app① status --json task=T1"
n1="$(app_addrs | grep -c . || true)"
run_app ensure --task T1 rd-fe
t4_assert_eq "0" "$APP_RC" "app② 同 (role,task) 二次 ensure rc=0"
t4_assert_eq "$n1" "$(app_addrs | grep -c . || true)" "app② 同 task 复用 ⇒ 不新建终端"
t4_assert_contains "$APP_OUT" "（成功 0 / 跳过 1 / 失败 0）" "app② 摘要走跳过"
run_app ensure --task T2 rd-fe
A2="$(addr_of rd-fe2)"
t4_assert_eq "0" "$APP_RC" "app③ 不同 task 取空闲槽位 rc=0"
t4_assert_ne "" "$A2" "app③ 新会话名 = rd-fe2（槽位 2）"
t4_assert_eq "T2" "$(app_field "$A2" nao_task)" "app③ 新会话 nao.task=T2"
run_app close --task T1 rd-fe
t4_assert_eq "0" "$APP_RC" "app④ close --task T1 rd-fe rc=0"
t4_assert_eq "" "$(addr_of rd-fe)" "app④ T1 终端已回收"
t4_assert_ne "" "$(addr_of rd-fe2)" "app④ T2 终端仍在（按元数据精确匹配）"
run_app close --task T404 rd-fe
t4_assert_eq "0" "$APP_RC" "app⑤ close --task 无匹配 ⇒ rc=0（未运行）"
t4_assert_contains "$APP_OUT" "已不在运行" "app⑤ 明确「已不在运行」（app 后端幂等文案）"
t4_assert_ne "" "$(addr_of rd-fe2)" "app⑤ 无匹配不误杀同名会话"
run_app close --task T2 rd-fe
app_reset

# ---------------------------------------------------------------- app 臂：身份还原（缺陷 2）
# ① name=null + argv --name（无 nao.name 标签）⇒ 识别为在线
stub_hc run --bg --no-parent --keep --name rd-infra --cwd "$LAB" \
  --label herdr.space=spid --label herdr.tab=tbid -- true >/dev/null
AID="$(app_addrs | head -1)"
[ -n "$AID" ] || t4_bad "身份夹具：终端未建立"
: > "$(app_state_file "$AID" name)"
: > "$(app_state_file "$AID" name_null)"
printf 'rd-infra\n' > "$(app_state_file "$AID" argv_name)"
run_app status
t4_assert_contains "$APP_OUT" "✓ rd-infra" "identity① name=null + argv --name ⇒ 仍判在线（旧终端零迁移）"
# ② name=null + nao.name label（优先级高于 argv/name）
printf 'rd-be\n' > "$(app_state_file "$AID" nao_name)"
printf 'other-name\n' > "$(app_state_file "$AID" argv_name)"
run_app status
t4_assert_contains "$APP_OUT" "✓ rd-be" "identity② labels.nao.name 优先（不被 argv 覆盖）"
t4_assert_not_contains "$APP_OUT" "✓ other-name" "identity② 身份不是 argv 值"
# ③ 负控：非 pi 进程 + 空 name（且无 nao.name）⇒ 不得用 argv 猜身份
rm -f "$(app_state_file "$AID" nao_name)"
printf 'bash\n' > "$(app_state_file "$AID" fg)"
run_app status
t4_assert_not_contains "$APP_OUT" "✓ rd-be" "identity③ 非 pi ⇒ argv --name 不作身份（禁猜）"
# ④ ensure 建立的终端 name 被清空（app 真机 name=null）⇒ nao.name 仍可识别
app_reset
run_app ensure --task T3 rd-be
A3="$(addr_of rd-be)"
t4_assert_ne "" "$A3" "identity④ ensure 终端已建立"
: > "$(app_state_file "$A3" name)"; : > "$(app_state_file "$A3" name_null)"
run_app status
t4_assert_contains "$APP_OUT" "✓ rd-be" "identity④ app name=null 仍在线（labels.nao.name 还原）"
t4_assert_contains "$APP_OUT" "task=T3" "identity④ 元数据 task 一并可见"
app_reset

# ============================================================================
# 夹具：herdr 臂（herdr-double）
# ============================================================================
PATH="$FIXT_HERDR:$PATH"; export PATH
HLAB="$T4_CACHE_DIR/lab28h-$$"; mkdir -p "$HLAB"; cp -r "$T4_ROOT/.agents" "$HLAB/.agents"
BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$HLAB" "lab28h-$$" || { t4_bad "herdr be_init 失败"; t4_exit; }
be_start_server || { t4_bad "herdr server 起不来"; t4_exit; }
[ -n "$(be_panes)" ] || be_new_pane "$HLAB" >/dev/null

# ---------------------------------------------------------------- herdr golden + 默认值反向断言（T555 / P2①）
# 旧 cases/28 C2 的 tmux golden 组已随 T555 退役；等价覆盖 = 本组 herdr golden：
#   未设 NAO_TERMINAL == 显式 =herdr（默认值唯一）· ≠ 冻结的旧 tmux golden ·
#   缺 herdr 前提 ⇒ exit 3（不静默回落）· 变异「默认改回 tmux」⇒ 未设 golden 必红（先红后绿）。
GOLD_TMUX_MD5="144f3447c9ff406d6aed828d9c9720e5"
GOLD_HERDR_MD5_RECORDED="4b7f47b28a141521ec262b2d727348f8"
# >>> default-value-probe BEGIN（T555 P2①：未设探针 —— 全仓唯一允许 unset NAO_TERMINAL 的位置）
gold_md5() { printf '%s' "$1" | md5sum | awk '{print $1}'; }
gold_run() { # <explicit|unset> <script> [extra env...] → GOLD_RC / GOLD_OUT / GOLD_ERR
  local mode="$1" script="$2"; shift 2
  local kv
  local -a clean=() handles=() envs=()
  mapfile -t clean < <(be_clean_env)
  mapfile -t handles < <(be_fleet_handles)
  for kv in "${handles[@]}"; do [[ "$kv" == NAO_TERMINAL=* ]] || envs+=("$kv"); done
  if [[ "$mode" == "explicit" ]]; then
    t4_run_in_dir "$HLAB" env "${clean[@]}" "${envs[@]}" "NAO_SKILLS=$HLAB" NAO_TERMINAL=herdr \
      timeout 180 bash "$script" status "$@"
  else
    t4_run_in_dir "$HLAB" env -u NAO_TERMINAL "${clean[@]}" "${envs[@]}" "NAO_SKILLS=$HLAB" \
      timeout 180 bash "$script" status "$@"
  fi
  GOLD_RC=$T4_RC
  GOLD_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  GOLD_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
gold_run explicit "$HLAB/.agents/scripts/nao-fleet.sh"
GOLD_HERDR_MD5="$(gold_md5 "$GOLD_OUT")"
t4_assert_eq "0" "$GOLD_RC" "P2① 显式 =herdr ⇒ status rc=0"
t4_assert_contains "$GOLD_OUT" "本表按 herdr pane label" "P2① herdr golden 确为 herdr 渲染（后端专有头行）"
t4_assert_eq "$GOLD_HERDR_MD5_RECORDED" "$GOLD_HERDR_MD5" \
  "P2① herdr golden == 记录值（渲染零漂移；实际=$GOLD_HERDR_MD5）"
t4_assert_ne "$GOLD_TMUX_MD5" "$GOLD_HERDR_MD5" "P2① 反向断言：herdr golden ≠ 旧 tmux golden"
t4_info "P2① golden：tmux=$GOLD_TMUX_MD5 · herdr=$GOLD_HERDR_MD5"
# 未设探针（同一 default-value-probe 块内）
gold_run unset "$HLAB/.agents/scripts/nao-fleet.sh"
t4_assert_eq "0" "$GOLD_RC" "P2① 未设 NAO_TERMINAL（herdr 场）⇒ status rc=0（默认已翻 herdr）"
t4_assert_eq "$GOLD_HERDR_MD5" "$(gold_md5 "$GOLD_OUT")" \
  "P2① 未设 == herdr golden（默认值唯一：未设与显式 =herdr 不可分叉）"
t4_assert_ne "$GOLD_TMUX_MD5" "$(gold_md5 "$GOLD_OUT")" "P2① 未设 ≠ 旧 tmux golden（旧口径已失效）"
# 反向负控 A：未设 + HERDR_* 全缺 ⇒ exit 3（点名 HERDR_ENV；不静默回落）
mapfile -t GOLD_CLEAN < <(be_clean_env)
t4_run_in_dir "$HLAB" env -u NAO_TERMINAL "${GOLD_CLEAN[@]}" "NAO_SKILLS=$HLAB" \
  timeout 180 bash "$HLAB/.agents/scripts/nao-fleet.sh" status
t4_assert_eq "3" "$T4_RC" "P2① 反向负控A：未设 NAO_TERMINAL 且 herdr 前提全缺 ⇒ exit 3"
t4_assert_contains "$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')" "HERDR_ENV=1 缺失" \
  "P2① 反向负控A：点名 herdr 前提（HERDR_ENV）"
# 变异自证：默认改回 tmux ⇒ 未设 golden 必红（判据非空转）；复原后复绿（先红后绿）
GOLD_MUT_ROOT="$HLAB/mut-default-$$"
GOLD_MUT="$(t4_fleet_clone "$HLAB/.agents/scripts" "$GOLD_MUT_ROOT")"
GOLD_MUT_MOD="$(t4_fleet_file_for "$GOLD_MUT_ROOT" term_backend)"
sed 's/^NAO_TERMINAL="${NAO_TERMINAL:-herdr}"$/NAO_TERMINAL="${NAO_TERMINAL:-tmux}"/' \
  "$GOLD_MUT_MOD" > "$GOLD_MUT_MOD.mut" && mv "$GOLD_MUT_MOD.mut" "$GOLD_MUT_MOD"
t4_assert_eq "1" "$(grep -cE '^NAO_TERMINAL="\$\{NAO_TERMINAL:-tmux\}"$' "$GOLD_MUT_MOD" || true)" \
  "P2① 变异锚点有效：副本默认已改回 tmux"
gold_run unset "$GOLD_MUT"
t4_assert_ne "0" "$GOLD_RC" "P2① 变异自证：默认改回 tmux ⇒ 未设 rc≠0"
t4_assert_ne "$GOLD_HERDR_MD5" "$(gold_md5 "$GOLD_OUT")" \
  "P2① 变异自证：默认改回 tmux ⇒ 未设不再等于 herdr golden（必红，不是空转）"
gold_run unset "$HLAB/.agents/scripts/nao-fleet.sh"
t4_assert_eq "$GOLD_HERDR_MD5" "$(gold_md5 "$GOLD_OUT")" "P2① 复原后复绿：未设 == herdr golden"
rm -rf "$GOLD_MUT_ROOT"
# >>> default-value-probe END

meta_root() { printf '%s/.local/state/nao-fleet/session-meta\n' "$HLAB/.t4-home"; }
ws_of_label() { be_herdr "$BE_SESSION" pane list 2>/dev/null | _be_json_lines "(r.panes||[]).filter(p=>p.label==='$1').map(p=>p.workspace_id)" | sed -n '1p'; }
sidecar_for() { # <label> → path（当前会话 + 该 label 的 workspace）
  local w; w="$(ws_of_label "$1")"
  [ -n "$w" ] || return 1
  local p; p="$(be_herdr "$BE_SESSION" pane list 2>/dev/null | _be_json_lines "(r.panes||[]).filter(p=>p.label==='$1' && p.workspace_id==='$w').map(p=>p.pane_id)" | sed -n '1p')"
  [ -n "$p" ] || return 1
  printf '%s/%s__%s/%s\n' "$(meta_root)" "$BE_SESSION" "$w" "$p"
}

be_run_fleet "$HLAB" ensure --task T1 rd-fe
t4_assert_eq "0" "$BE_RC" "herdr① ensure --task T1 rd-fe rc=0"
SC1="$(sidecar_for rd-fe)" || true
t4_assert_file "${SC1:-/nonexistent}" "herdr① sidecar 已落盘（$SC1）"
t4_assert_contains "$(cat "$SC1" 2>/dev/null)" "task=T1" "herdr① sidecar task=T1"
be_run_fleet "$HLAB" status
t4_assert_contains "$BE_OUT" "task=T1" "herdr① 文本 status 尾注 task=T1"
be_run_fleet "$HLAB" status --json
t4_assert_contains "$BE_OUT" '"task":"T1"' "herdr① status --json task=T1"
be_run_fleet "$HLAB" ensure --task T1 rd-fe
t4_assert_contains "$BE_OUT" "（成功 0 / 跳过 1 / 失败 0）" "herdr② 同 task 二次 ensure 走跳过"
be_run_fleet "$HLAB" ensure --task T2 rd-fe
t4_assert_eq "0" "$BE_RC" "herdr③ 不同 task ensure rc=0"
t4_assert_ne "" "$(be_pane_by_name rd-fe2)" "herdr③ 取空闲槽位 2 = rd-fe2"
be_run_fleet "$HLAB" close --task T1 rd-fe
t4_assert_eq "0" "$BE_RC" "herdr④ close --task T1 rd-fe rc=0"
t4_assert_eq "" "$(be_pane_by_name rd-fe)" "herdr④ T1 pane 已回收"
t4_assert_ne "" "$(be_pane_by_name rd-fe2)" "herdr④ T2 pane 仍在"
t4_assert_eq "0" "$(grep -rlF 'task=T1' "$(meta_root)" 2>/dev/null | grep -c . || true)" "herdr④ close 按 handle 即时删 sidecar"

# ---------------------------------------------------------------- herdr 臂：只读旧形 + 歧义
P_LEG="$(be_new_pane "$HLAB")"; be_fixture_session "$P_LEG" "qa(T99)" "$HLAB" >/dev/null
be_run_fleet "$HLAB" status
t4_assert_contains "$BE_OUT" "qa(T99)" "herdr⑤ legacy/v2 名仍列在派生节"
t4_assert_contains "$BE_OUT" "task=T99" "herdr⑤ 旧形 task 从名字解析"
be_run_fleet "$HLAB" close --task T99 qa
t4_assert_eq "0" "$BE_RC" "herdr⑤ close --task T99 qa rc=0（只读旧形可回收）"
t4_assert_eq "" "$(be_pane_by_name 'qa(T99)')" "herdr⑤ 旧形 pane 已回收"
# 同名同 task 多 pane ⇒ 不猜
P_D1="$(be_new_pane "$HLAB")"; P_D2="$(be_new_pane "$HLAB")"
be_set_name "$P_D1" "rd-be" "$HLAB"; be_set_name "$P_D2" "rd-be" "$HLAB"
WD="$(ws_of_label rd-be)"
mkdir -p "$(meta_root)/${BE_SESSION}__${WD}"
printf 'task=T5\nname=rd-be\n' > "$(meta_root)/${BE_SESSION}__${WD}/$P_D1"
printf 'task=T5\nname=rd-be\n' > "$(meta_root)/${BE_SESSION}__${WD}/$P_D2"
be_run_fleet "$HLAB" close --task T5 rd-be
t4_assert_ne "0" "$BE_RC" "herdr⑥ 同 (role,task) 两 pane ⇒ close 拒绝（不猜）"
t4_assert_contains "$BE_ERR_ANSI" "目标歧义" "herdr⑥ 文案点名歧义"
be_pane_alive "$P_D1" && t4_ok "herdr⑥ pane#1 仍存活" || t4_bad "herdr⑥ pane#1 被误杀"
be_pane_alive "$P_D2" && t4_ok "herdr⑥ pane#2 仍存活" || t4_bad "herdr⑥ pane#2 被误杀"
be_kill_pane "$P_D1"; be_kill_pane "$P_D2"

# ---------------------------------------------------------------- herdr 臂：sidecar 孤儿清理
be_run_fleet "$HLAB" ensure --task T7 rd-infra
LIVE_SC="$(sidecar_for rd-infra)" || true
t4_assert_file "${LIVE_SC:-/nonexistent}" "orphan 夹具：live sidecar 在位"
ODIR="$(dirname "$LIVE_SC")"
printf 'task=TX\nname=fake1\n' > "$ODIR/fakeh1"
printf 'task=TY\nname=fake2\n' > "$ODIR/fakeh2"
be_run_fleet "$HLAB" status
t4_assert_eq "0" "$BE_RC" "orphan status rc=0（清理失败不改 rc）"
t4_assert_eq "0" "$([ -e "$ODIR/fakeh1" ] && echo 1 || echo 0)" "orphan 清理 fakeh1"
t4_assert_eq "0" "$([ -e "$ODIR/fakeh2" ] && echo 1 || echo 0)" "orphan 清理 fakeh2"
t4_assert_eq "1" "$([ -e "$LIVE_SC" ] && echo 1 || echo 0)" "orphan 保留 live handle 的 sidecar"
be_run_fleet "$HLAB" ensure --task T7 rd-infra
t4_assert_eq "0" "$BE_RC" "orphan 后 ensure 幂等 rc=0"

# ============================================================================
# 失败演练（变异必红）
# ============================================================================
# ① 身份还原顺序退回「只读 name」⇒ identity① 必红
MUT=""; MUT_MOD=""
if clone_for_mut ident 'TERM_APP_LABEL_NAME'; then MUT="$MUT_ENTRY"; MUT_MOD="$MUT_MOD"; fi
if [ -n "$MUT" ] && mutate_many "$MUT_MOD" "$MUT_MOD.mut" \
     'nm="$(_term_app_field "$g" "$TERM_APP_LABEL_NAME")"' 'nm=""' \
     'if [[ -z "$nm" ]]; then' 'if false; then'; then
  mv "$MUT_MOD.mut" "$MUT_MOD"
  app_reset
  stub_hc run --bg --no-parent --keep --name rd-infra --cwd "$LAB" \
    --label herdr.space=spid2 --label herdr.tab=tbid2 -- true >/dev/null
  AID="$(app_addrs | head -1)"
  : > "$(app_state_file "$AID" name)"; : > "$(app_state_file "$AID" name_null)"
  printf 'rd-infra\n' > "$(app_state_file "$AID" argv_name)"
  printf 'rd-be\n' > "$(app_state_file "$AID" nao_name)"
  BE_FLEET_SCRIPT="$MUT" run_app status
  BE_FLEET_SCRIPT=""
  t4_assert_not_contains "$APP_OUT" "✓ rd-be" "变异① 只读 name（丢 label/argv）⇒ identity 必红"
  t4_assert_not_contains "$APP_OUT" "✓ rd-infra" "变异① 只读 name（丢 argv）⇒ 空名终端不再在线"
else
  t4_bad "变异① 锚点未命中（身份还原实现行变了）"
fi
# ② app --name 改回原始名（合法化被绕过）⇒ 带括号的旧名必被 hc 拒
MUT=""; MUT_MOD=""
if clone_for_mut legal 'fleet_backend_name "$name"'; then MUT="$MUT_ENTRY"; MUT_MOD="$MUT_MOD"; fi
if [ -n "$MUT" ] && mutate_file "$MUT_MOD" "$MUT_MOD.mut" 'legal="$(fleet_backend_name "$name")"' 'legal="$name"'; then
  mv "$MUT_MOD.mut" "$MUT_MOD"
  app_reset
  # 造一条 v2 旧名会话（nao.name=rd-fe(T1) + nao.task=T1），ensure --force 会复用它并尝试 spawn
  stub_hc run --bg --no-parent --keep --name rd-fe-t1- --cwd "$LAB" \
    --label herdr.space=spv2 --label herdr.tab=tbv2 \
    --label 'nao.task=T1' --label 'nao.name=rd-fe(T1)' -- true >/dev/null
  printf '%s' "$LAB" > "$BE_APP_STATE/spaces/spv2"
  BE_FLEET_SCRIPT="$MUT" run_app ensure --force --task T1 rd-fe
  BE_FLEET_SCRIPT=""
  t4_assert_ne "0" "$APP_RC" "变异② --name 原始名（含括号）⇒ app 必红（hc 合法名拒绝）"
  t4_assert_contains "$APP_ERR" "hc run 失败" "变异② 失败点 = hc run（不是别的分支）"
else
  t4_bad "变异② 锚点未命中（合法化实现行变了）"
fi

be_teardown >/dev/null 2>&1 || true
t4_exit
