#!/usr/bin/env bash
# 用例 28 —— 舰队命名契约（BR8 · #96 步 2a）：C1 codec 恒等 / C2 golden diff 空 / C3 单写点 lint
#
# 交接口径：docs/reports/96a-naming-contract.md（§0 契约 · §5 scope 优先级与 fail loud · §6 判据）
# 被测对象：.agents/scripts/nao-fleet.sh 的契约块（`# >>> fleet-name-contract` 标记区间）
#           + `cmd_status` / `cmd_ensure` / `cmd_close` 的全部构造/解析点
#
# C1 codec 恒等（**纯函数、不启 tmux**）：契约块整体抽取到沙箱（只灌「角色事实表」）
#   ① 字面量恒等（scope=""）：常驻 7 + 派生 5 + 卡 3，且别名不得当角色 id 输出
#   ② 往返：parse(build(x)) 回原 (kind,role,task,"")
#   ③ 语法钉住：scope=todo ⇒ `sec-review@todo` / `sec-review-T42@todo` 精确相等
#   ④ parse 全函数：非法输入一律 ERR（空/裸 @/多 @/大写/`.`/`:`/超 16/保留前缀/超总长/非法字符）
#   ⑤ scope 来源：优先级 + 六条 fail loud（空文件/仅空白/多行/非法/非常规文件/symlink 逃仓）+ slug 归一
#   M1–M4 变异负控（不红 = 本组断言无效）：M1 build 尾追加 -x · M2 parse 丢 task
#     · M3 parse 改 ${x%-*} 切片 · M4 parse 对非法 scope 返猜测值
#
# C2 golden diff 空（fixture = 改动前那一版，**必须在动脚本之前生成**，否则自等价）：
#   夹具 `tests/t4/fixtures/nao-fleet-baseline-2692b42.sh`（= git show 2692b42:… + 头注释）
#   比**两样**（同套隔离夹具：`env -u TMUX -u TMUX_PANE` + 私有 `TMUX_TMPDIR` + 桩 pi）：
#     ① `status` 全文 md5（名册离线 ⇒ 只走标题/卡集路径，确定性）
#     ② `ensure` 的 `[tmux] 已拉起 …` 行 + pi 桩 argv 里 `--name` 值，拼接后 md5
#   目标集 9 个（7 常驻 + `--task T1` + `--card`），**全不设 scope** ⇒ BR1 逐字等价。
#   另守卫（Issue #78 P3-1 同口径）：fixture 正文 md5 必须 ≠ 被测脚本正文 md5（防自等价恒绿）。
#
# C3 单写点 lint（静态、变异负控在 $T4_CACHE_DIR 的副本上做，绝不写工作区）：
#   ① `grep -c 'exec pi --name'` == 1（唯一 exec 点）
#   ② 契约块**外**正文 0 命中 `(name|disp)="?${…}-${?(task|TASK)`（禁名字拼接）
#   ③ `grep -c fleet_name_parse` ≥ 11（11 解析点全接线的**可见面**）+ 代码调用点数固定
#   负控：close 里手写 `name="${NAME}-${task}"` ⇒ ②红；删一条 parse 调用 ⇒ ③红
#
# 退出码沿用 lib.sh 约定；夹具根不得落在任何 git 仓内，收尾走机制 `cleanup -S`。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SUBJECT="${T4_28_SUBJECT:-$T4_ROOT/.agents/scripts/nao-fleet.sh}"
BASH_BIN="$(command -v bash)"
CONTRACT_BEGIN='^# >>> fleet-name-contract BEGIN'
CONTRACT_END='^# <<< fleet-name-contract END'

# ============================================================================
# C1 子进程模式：只测纯函数（零 tmux / 零仓库依赖）；父进程据此做 M1–M4 变异负控
# ============================================================================
if [ "${T4_28_C1_CHILD:-0}" = "1" ]; then
  CONTRACT="${T4_28_CONTRACT:?子进程需要 T4_28_CONTRACT}"
  W="$(mktemp -d "${T4_CACHE_DIR:-/tmp}/c1.XXXXXX")"
  trap 'rm -rf "$W"' EXIT
  OKN=0; BADN=0
  chk() { # <label> <want> <got>
    if [ "$2" = "$3" ]; then OKN=$((OKN + 1))
    else BADN=$((BADN + 1)); printf '  ✗ %s\n    want=[%s]\n    got =[%s]\n' "$1" "$2" "$3"; fi
  }
  # 角色事实表（= roles.yaml 现状 + 一张下游卡）：parse 的**唯一**角色来源，不启 tmux、不读仓
  declare -A FLEET_ROLE_KIND
  for r in pm arch-designer uiux-designer rd-fe rd-be qa rd-infra; do FLEET_ROLE_KIND[$r]=resident; done
  FLEET_ROLE_KIND[sec-review]=card
  # shellcheck disable=SC1090
  source "$CONTRACT"
  b() { fleet_name_build "$@" 2>/dev/null; }
  p() { fleet_name_parse "$@"; }

  # ---- ① 字面量恒等（scope=""）+ ② 往返：一条表（core|kind|role|task）----
  while IFS='|' read -r core kind role task; do
    [ -n "$core" ] || continue
    chk "① build($kind,$core,scope=空) == $core（@ 整段不出现）" "$core" "$(b "$kind" "$core" "")"
    chk "① parse($core) == OK $kind,$role,$task,（role 输出 canonical id，非别名）" \
      "OK $kind,$role,$task," "$(p "$core")"
    chk "② 往返 parse(build($kind,$core,\"\"))" "OK $kind,$role,$task," "$(p "$(b "$kind" "$core" "")")"
  done <<'TBL'
pm|resident|pm|
arch-designer|resident|arch-designer|
uiux-designer|resident|uiux-designer|
rd-fe|resident|rd-fe|
rd-be|resident|rd-be|
qa|resident|qa|
rd-infra|resident|rd-infra|
rd-be-T1|derived|rd-be|T1
qa-T508|derived|qa|T508
arch-designer-96b|derived|arch-designer|96b
pm-M20261109-queue-slim|derived|pm|M20261109-queue-slim
rd-infra-M20261014-pi-ext-update|derived|rd-infra|M20261014-pi-ext-update
sec-review|card|sec-review|
sec-review-T42|card|sec-review|T42
sec-review-notes|card|sec-review|notes
TBL
  # 别名不得被当成角色 id（须先 resolve_role 成 id 再进 builder）
  for a in arch uiux ui-designer infra; do
    chk "① 别名 $a 不得被 parse 当成角色 id（先 resolve_role 成 id）" "ERR" "$(p "$a")"
  done
  chk "① 解析后的 canonical id 反向可解析" "OK resident,arch-designer,," "$(p "arch-designer")"

  # ---- ③ 语法钉住 ----
  chk "③ build(card,sec-review,todo) 精确 == sec-review@todo" "sec-review@todo" "$(b card sec-review todo)"
  chk "③ build(card,sec-review-T42,todo) 精确 == sec-review-T42@todo" "sec-review-T42@todo" "$(b card sec-review-T42 todo)"
  chk "③ parse(sec-review@todo)" "OK card,sec-review,,todo" "$(p sec-review@todo)"
  chk "③ parse(sec-review-T42@todo)" "OK card,sec-review,T42,todo" "$(p sec-review-T42@todo)"
  chk "③ parse(rd-be-T1@todo)（派生 + scope ⇒ kind=derived）" "OK derived,rd-be,T1,todo" "$(p rd-be-T1@todo)"
  chk "③ 往返带 scope" "OK card,sec-review,T42,todo" "$(p "$(b card sec-review-T42 todo)")"

  # ---- ④ parse 全函数（非法一律 ERR，禁猜）----
  L17="$(printf 'a%.0s' $(seq 1 17))"
  L49="rd-be-$(printf 'T%.0s' $(seq 1 44))"     # 50 字符 > 48
  for bad in "" "rd-fe@" "@todo" "rd-fe@@todo" "rd-fe@@@todo" "rd-fe@TODO" "rd-fe@a.b" "rd-fe@:x" \
             "rd-fe@$L17" "subagent-x@y" "nao-x@y" "$L49" "rd_fe" "rd-fe@todo!" "rd-fe@-x" "rd-fe@x-" \
             "rd-fe " " rd-fe" "RD-FE" "unknown-role" "sec-review-$(printf 'x%.0s' $(seq 1 30))"; do
    chk "④ 非法/越界输入必须 ERR：[${bad}]" "ERR" "$(p "$bad")"
  done
  chk "④ 非法输入下 build 必须拒绝（rc≠0）" "1" "$(b card rd-be 'bad scope!' >/dev/null 2>&1; echo $?)"
  chk "④ 未知 kind 下 build 必须拒绝（rc≠0）" "1" "$(b bogus rd-be '' >/dev/null 2>&1; echo $?)"

  # ---- ⑤ scope 来源与 fail loud（§5）----
  R="$W/repo"; mkdir -p "$R/.agents"
  chk "⑤ 文件不存在 ⇒ 空且静默" "" "$(fleet_scope_of_invocation "$R" "" 2>/dev/null)"
  printf 'todo\n' > "$R/.agents/fleet-scope"
  chk "⑤ 单行合法 ⇒ todo" "todo" "$(fleet_scope_of_invocation "$R" "" 2>/dev/null)"
  chk "⑤ --scope 覆盖文件（静默胜出）" "other" "$(fleet_scope_of_invocation "$R" other 2>/dev/null)"
  printf 'todo\r\n' > "$R/.agents/fleet-scope"
  chk "⑤ CRLF ⇒ 剥 \\r 后合法（不因 EOL 拒绝）" "todo" "$(fleet_scope_of_invocation "$R" "" 2>/dev/null)"
  printf 'todo\n' > "$R/.agents/fleet-scope"
  chk "⑤ --scope 非法 ⇒ 失败（不回落文件）" "1" \
    "$(fleet_scope_of_invocation "$R" 'BAD' >/dev/null 2>&1; echo $?)"
  for badf in "" "   " "todo
other" "TODO" "a.b" ":x" "$L17" "-lead" "tail-" "subagent-x" "nao-x" "todo x"; do
    printf '%s' "$badf" > "$R/.agents/fleet-scope"
    chk "⑤ 文件内容非法必须 fail loud：[${badf//$'\n'/\\n}]" "1" \
      "$(fleet_scope_of_invocation "$R" "" >/dev/null 2>&1; echo $?)"
  done
  rm -f "$R/.agents/fleet-scope"; mkdir "$R/.agents/fleet-scope"
  chk "⑤ 目录（非常规文件）必须 fail loud" "1" \
    "$(fleet_scope_of_invocation "$R" "" >/dev/null 2>&1; echo $?)"
  rmdir "$R/.agents/fleet-scope"
  mkdir -p "$W/outside"; printf 'evil\n' > "$W/outside/scope.txt"
  ln -s "$W/outside/scope.txt" "$R/.agents/fleet-scope"
  chk "⑤ symlink 逃出仓必须 fail loud" "1" \
    "$(fleet_scope_of_invocation "$R" "" >/dev/null 2>&1; echo $?)"
  printf 'inside\n' > "$R/.agents/scope-real.txt"
  rm -f "$R/.agents/fleet-scope"; ln -s "$R/.agents/scope-real.txt" "$R/.agents/fleet-scope"
  chk "⑤ symlink 不逃仓 ⇒ 正常读取" "inside" "$(fleet_scope_of_invocation "$R" "" 2>/dev/null)"
  rm -f "$R/.agents/fleet-scope"

  # ---- ⑤b slug：归一 + worktree 不分裂（--show-toplevel 会分裂 ⇒ 必须用 --git-common-dir）----
  mkdir -p "$W/My_Repo.V2"
  chk "⑤ slug 归一：大写/_/. → -，非 git 仓用 basename" "my-repo-v2" "$(fleet_scope_slug "$W/My_Repo.V2")"
  LONGDIR="$W/$(printf 'a%.0s' $(seq 1 30))"; mkdir -p "$LONGDIR"
  chk "⑤ slug 截断 16 且不以 - 结尾" "aaaaaaaaaaaaaaaa" "$(fleet_scope_slug "$LONGDIR")"
  if command -v git >/dev/null 2>&1; then
    G="$W/gitrepo"; mkdir -p "$G"
    ( cd "$G" && git init -q . && git config user.email t@t.invalid && git config user.name t \
        && : > f && git add -A && git commit -qm init ) >/dev/null 2>&1
    chk "⑤ slug 普通仓 = 仓目录名" "gitrepo" "$(fleet_scope_slug "$G")"
    ( cd "$G" && git worktree add -q "$W/wt" -b wtb ) >/dev/null 2>&1
    chk "⑤ slug worktree 与主仓一致（--show-toplevel 会分裂 ⇒ 本断言守 P-hazard）" \
      "gitrepo" "$(fleet_scope_slug "$W/wt")"
  else
    printf '  -- 环境缺少 git：slug 的 worktree 防止分裂断言跳过（归一断言已跑）\n'
  fi

  if [ "$BADN" -gt 0 ]; then printf 'C1_FAIL ok=%d bad=%d\n' "$OKN" "$BADN"; exit 1; fi
  printf 'C1_OK %d\n' "$OKN"; exit 0
fi

# ============================================================================
# 父进程：C1（抽取 + M1–M4）→ C3 lint → C2 golden diff
# ============================================================================
extract_contract() {
  awk -v b="$CONTRACT_BEGIN" -v e="$CONTRACT_END" '$0 ~ b { f=1; next } $0 ~ e { f=0 } f' "$1"
}
# 字面替换（awk ENVIRON：不经 -v 转义，正文里的 \n 原样比较）；无命中 ⇒ rc=1
mutate_file() { # <src> <dst> <old-literal> <new-literal>
  MUT_OLD="$3" MUT_NEW="$4" awk '
    BEGIN { n = 0 }
    { i = index($0, ENVIRON["MUT_OLD"])
      if (i > 0) { print substr($0, 1, i - 1) ENVIRON["MUT_NEW"] substr($0, i + length(ENVIRON["MUT_OLD"])); n++ }
      else print }
    END { exit (n ? 0 : 1) }' "$1" > "$2"
}
run_c1() { # <contract-file> → 0 = C1 全绿；$C1_DETAIL 明细
  C1_DETAIL="$(T4_28_C1_CHILD=1 T4_28_CONTRACT="$1" T4_CACHE_DIR="$T4_CACHE_DIR" \
    "$BASH_BIN" "$SELF" 2>&1)"
  local rc=$?
  if [ "$rc" != 0 ]; then printf '%s\n' "$C1_DETAIL" | sed -e 's/^/    /' | head -12 >&2; fi
  return "$rc"
}

[ -f "$SUBJECT" ] || { t4_bad "被测脚本不存在：$SUBJECT"; t4_exit; }
C1_BASE="$T4_CACHE_DIR/c1-contract.sh"
extract_contract "$SUBJECT" > "$C1_BASE"
t4_assert_ne "0" "$(wc -l < "$C1_BASE" | tr -d ' ')" \
  "C1 契约块可在脚本内抽取（标记 $CONTRACT_BEGIN … $CONTRACT_END，非空 ⇒ 否则四符号无从单测）"

# ---- C1 正控：抽取块全绿 ----
if run_c1 "$C1_BASE"; then
  t4_ok "C1 四组断言全绿（① 字面量恒等 / ② 往返 / ③ 语法钉住 / ④ parse 全函数 / ⑤ scope fail loud）"
  t4_info "C1 断言数：$(printf '%s' "$C1_DETAIL" | sed -n 's/^C1_OK \([0-9]*\)$/\1/p')"
else
  t4_bad "C1 四组断言未全绿（抽取块跑红；明细见上）"
fi

# ---- C1 变异负控 M1–M4（不红 ⇒ 该组断言无效）----
mutation_neg() { # <label> <old> <new>
  local label="$1" old="$2" new="$3" f="$T4_CACHE_DIR/c1-mut.sh" rc
  if ! mutate_file "$C1_BASE" "$f" "$old" "$new"; then
    t4_bad "M $label：变异锚点未命中（sed 等价物失配 ⇒ 负控无效，须修用例锚点）"; return
  fi
  t4_assert_ne "$(md5sum < "$C1_BASE")" "$(md5sum < "$f")" "M $label：变异确实改到了契约正文"
  run_c1 "$f" >/dev/null 2>&1 && rc=0 || rc=$?
  t4_assert_ne "0" "$rc" "M $label：变异后 C1 必须变红（未红 ⇒ 该断言组是同义反复）"
}
mutation_neg "M1 build 尾追加 -x" \
  'printf '"'"'%s\n'"'"' "$core"' 'printf '"'"'%s-x\n'"'"' "$core"'
mutation_neg "M2 parse 丢 task" \
  'if [[ "$core" == "$role" ]]; then task=""; else task="${core:${#role}+1}"; fi' \
  'if [[ -n "$role" ]]; then task=""; fi'
mutation_neg "M3 parse 改 \${x%-*} 尾切片" \
  'else task="${core:${#role}+1}"; fi' \
  'else task="${core%-*}"; fi'
mutation_neg "M4 parse 对非法 scope 返猜测值" \
  'fleet_scope_problem "$scope" >/dev/null || { printf '"'"'ERR\n'"'"'; return 0; }' ':'

# ============================================================================
# C3 单写点 lint（静态；负控只在副本上做）
# ============================================================================
lint1() { grep -c 'exec pi --name' "$1" || true; }                     # ① 唯一 exec 点
lint2() {                                                              # ② 契约块外的名字拼接
  awk -v b="$CONTRACT_BEGIN" -v e="$CONTRACT_END" '
    $0 ~ b { f=1; next } $0 ~ e { f=0; next } f { next } { print }' "$1" \
    | grep -cE '(name|disp)="?\$\{[^}]+\}-\$\{?(task|TASK)' || true
}
lint3() { grep -c 'fleet_name_parse' "$1" || true; }                   # ③ 接线可见面（含说明行）
lint3c() { grep -cE 'fleet_name_parse "' "$1" || true; }               # ③ 代码调用点数

t4_assert_eq "1" "$(lint1 "$SUBJECT")" "C3① 全脚本恰 1 处 \`exec pi --name\`（唯一 exec 点）"
t4_assert_eq "0" "$(lint2 "$SUBJECT")" \
  "C3② 契约块外 0 处手写名字拼接（(name|disp)=\${…}-\${task} 形态）"
N3="$(lint3 "$SUBJECT")"; N3C="$(lint3c "$SUBJECT")"
t4_assert_ge "11" "$N3" "C3③ \`grep -c fleet_name_parse\` ≥ 11（11 解析点全接线的可见面；实际 $N3）"
t4_info "C3③ 代码调用点数（fleet_name_parse \"…\"）= $N3C"
t4_assert_ge "6" "$N3C" "C3③ 代码调用点数 ≥ 6（status/close/derived/running_verdict 等实点；实际 $N3C）"

# ---- C3 负控 A：close 里手写 name 拼接 ⇒ ②必须红 ----
NEG_A="$T4_CACHE_DIR/c3-neg-a.sh"
if mutate_file "$SUBJECT" "$NEG_A" \
    '  local force="$1" task="$2" target="${3:-}"' \
    '  local force="$1" task="$2" target="${3:-}"
  name="${NAME}-${task}"'; then
  t4_assert_ne "0" "$(lint2 "$NEG_A")" "C3 负控A 手写 \`name=\"\${NAME}-\${task}\"\` ⇒ ②红（点名拼接点）"
else
  t4_bad "C3 负控A 变异锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3 负控 B：删一条 parse 调用 ⇒ ③代码调用点数必须掉 ----
NEG_B="$T4_CACHE_DIR/c3-neg-b.sh"
if MUT_RE='^[[:space:]]*out="\$\(fleet_name_parse "\$n"\)"[[:space:]]*$' \
   awk '/^# >>> fleet-name-contract BEGIN/{f=1} /^# <<< fleet-name-contract END/{f=0}
        !f && $0 ~ ENVIRON["MUT_RE"] && !d { d=1; next } { print } END { exit (d?0:1) }' \
     "$SUBJECT" > "$NEG_B"; then
  t4_assert_eq "$(($N3C - 1))" "$(lint3c "$NEG_B")" "C3 负控B 删一条 parse 调用 ⇒ ③代码调用点数 -1（负控有效）"
  t4_assert_ne "$N3C" "$(lint3c "$NEG_B")" "C3 负控B 删调用后 ③ 可见面变化（不是恒量）"
else
  t4_bad "C3 负控B 变异锚点未命中（用例锚点须跟随实现）"
fi

# ============================================================================
# C2 golden diff 空（status 全文 + ensure 已拉起行/--name 值）
# ============================================================================
BASELINE_SHA="2692b42"
BASELINE_FIXTURE="$T4_ROOT/tests/t4/fixtures/nao-fleet-baseline-$BASELINE_SHA.sh"
FIXTURE_HDR_LINES=10

t4_assert_file "$BASELINE_FIXTURE" "C2 基线 fixture 存在（tests/t4/fixtures/nao-fleet-baseline-$BASELINE_SHA.sh）"
t4_assert_contains "$(head -12 "$BASELINE_FIXTURE" 2>/dev/null)" "source sha: $BASELINE_SHA" \
  "C2 fixture 顶部注明来源 sha（$BASELINE_SHA）与理由行"
FIX_BODY_MD5="$(tail -n +$((FIXTURE_HDR_LINES + 1)) "$BASELINE_FIXTURE" 2>/dev/null | md5sum | awk '{print $1}')"
SUBJ_BODY_MD5="$(tail -n +2 "$SUBJECT" | md5sum | awk '{print $1}')"
t4_assert_ne "$FIX_BODY_MD5" "$SUBJ_BODY_MD5" \
  "C2 基线非自等价（fixture 正文 md5 ≠ 被测脚本正文 md5 ⇒ 不是「把当前脚本当基线」的恒绿）"

if ! command -v tmux >/dev/null 2>&1; then
  t4_degrade "环境缺少 tmux ⇒ C2 golden diff（status/ensure 两样）未执行；C1/C3 已跑"
  t4_exit
fi

REAL_TMUX="$(command -v tmux)"
LAB="$T4_CACHE_DIR/lab28-$$"
SOCK_A_DIR="$LAB/sockA"
SOCK_B_DIR="$LAB/sockB"
SOCK_A="$SOCK_A_DIR/tmux-$(id -u)/default"
SOCK_B="$SOCK_B_DIR/tmux-$(id -u)/default"

# ---- 硬护栏（先于一切 tmux 操作）----
GUARD=0
_TM="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${_TM%%,*}"; do
  [ -n "$p" ] || continue
  [ "$SOCK_A" = "$p" ] && GUARD=1
  [ "$SOCK_B" = "$p" ] && GUARD=1
done
[[ "$SOCK_A" == "$LAB"/* && "$SOCK_B" == "$LAB"/* && "$SOCK_A" != "$SOCK_B" ]] || GUARD=1
if [ "$GUARD" != 0 ]; then
  t4_bad "护栏触发：夹具 SOCK 不在 \$LAB 下、两场不独立或与生产默认候选冲突"
  t4_exit
fi
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：两个隔离 socket（基线/新版各一场）+ 夹具根不在任何 git 仓内"

mkdir -p "$LAB" "$SOCK_A_DIR/tmux-$(id -u)" "$SOCK_B_DIR/tmux-$(id -u)" "$LAB/bin" "$LAB/pi-empty"
chmod 700 "$SOCK_A_DIR/tmux-$(id -u)" "$SOCK_B_DIR/tmux-$(id -u)"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
BASE_SCRIPT="$LAB/base-fleet.sh"
cp "$BASELINE_FIXTURE" "$BASE_SCRIPT" 2>/dev/null || : > "$BASE_SCRIPT"
t4_assert_ne "0" "$(wc -c < "$BASE_SCRIPT" | tr -d ' ')" "C2 基线脚本可执行副本非空（空 ⇒ 断言必红，不静默跳过）"

# 下游卡夹具 ×2 —— **名字必须与下面 ensure 目标集不相交**（同一 tmux server 上，status 夹具 pane
#   的存在会让 ensure 的 running 判重命中 ⇒ 会静默跳过，令 C2② 目标数不足而假绿）
cat > "$LAB/.agents/prompts/sec-review.md" <<'MD'
---
role: sec-review
---
# sec-review（用例 28 夹具卡 · ensure --card 目标，只用于 C2②）
MD
cat > "$LAB/.agents/prompts/sec-audit.md" <<'MD'
---
role: sec-audit
---
# sec-audit（用例 28 夹具卡 · 只用于 C2① status 的卡路径断言）
MD
# tasks-state 夹具：T9001 已归档（⇒ 派生行 tag = `! 残留`）
TASKS_FIX="$LAB/tasks-state-fixture.md"
cat > "$TASKS_FIX" <<'MD'
# case28 tasks-state 夹具（只读）

## 已归档

| 任务 | 状态 |
| :-- | :-- |
| T9001 | v0.1 |
MD

# pi 桩：只记录 `--name` 值（追加），绝不拉起真 pi；pane 里长驻 sleep
PI_NAMES="$LAB/pi-names.log"; : > "$PI_NAMES"
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
n=""; prev=""
for a in "\$@"; do [ "\$prev" = "--name" ] && n="\$a"; prev="\$a"; done
printf '%s\n' "\$n" >> "$PI_NAMES"
exec sleep 900
SH
chmod +x "$LAB/bin/pi"

# 标题启动器（pane 内进程自己输出 OSC 0 ⇒ 标题恒定，不依赖 shell prompt）
cat > "$LAB/pane-title.sh" <<'SH'
#!/usr/bin/env bash
printf '\033]0;%s\007' "$1"
exec sleep 1800
SH
chmod +x "$LAB/pane-title.sh"

TX() { local s="$1"; shift; "$REAL_TMUX" -S "$s" "$@"; }
setup_server() { # <sock> <sockdir> → echo 调用者 pane
  local s="$1" d="$2"
  mkdir -p "$d/tmux-$(id -u)"; chmod 700 "$d/tmux-$(id -u)"
  "$REAL_TMUX" -S "$s" new-session -d -s lab -x 320 -y 70 -c "$LAB" >/dev/null 2>&1 || return 1
  sleep 0.3
  "$REAL_TMUX" -S "$s" setenv -g PATH "$LAB/bin:$PATH" >/dev/null 2>&1 || true
  "$REAL_TMUX" -S "$s" list-panes -t lab -F '#{pane_id}' 2>/dev/null | head -1
}
wait_title() { # <sock> <pane> <expected>
  local s="$1" p="$2" want="$3" i got
  for i in $(seq 1 50); do
    got="$("$REAL_TMUX" -S "$s" display-message -p -t "$p" '#{pane_title}' 2>/dev/null)"
    [ "$got" = "$want" ] && return 0
    sleep 0.1
  done
  return 1
}
start_titled() { # <sock> <session> <title>
  local s="$1" sess="$2" title="$3" p
  "$REAL_TMUX" -S "$s" new-session -d -s "$sess" -x 200 -y 50 -c "$LAB" \
    "$LAB/pane-title.sh" "$title" >/dev/null 2>&1 || return 1
  p="$("$REAL_TMUX" -S "$s" list-panes -t "$sess" -F '#{pane_id}' 2>/dev/null | head -1)"
  [ -n "$p" ] || return 1
  wait_title "$s" "$p" "$title" || return 1
  printf '%s' "$p"
}

trap 'for s in "$SOCK_A" "$SOCK_B"; do
        [ -n "${s:-}" ] && [ -d "${LAB:-/nonexistent}" ] || continue
        ( cd "$LAB" 2>/dev/null || cd /tmp
          env -u TMUX TMUX_TMPDIR="$SOCK_A_DIR" "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$s" >/dev/null 2>&1 ) || true
      done
      t4_cache_cleanup 2>/dev/null || true' EXIT

run_in() { # <socket> <tmuxdir> <caller> <script> <args...>
  local sock="$1" tdir="$2" pane="$3" script="$4"; shift 4
  t4_run_in_dir "$LAB" env -u TMUX -u TMUX_PANE TMUX="$sock,0,0" TMUX_PANE="$pane" \
    TMUX_TMPDIR="$tdir" NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty" \
    NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
    timeout 180 "$BASH_BIN" "$script" "$@"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
}

# ---------------------------------------------------------------- C2① status
CALLER_A="$(setup_server "$SOCK_A" "$SOCK_A_DIR")"
CALLER_B="$(setup_server "$SOCK_B" "$SOCK_B_DIR")"
t4_assert_ne "" "${CALLER_A:-}" "C2 夹具：基线场隔离 tmux server + 调用者 pane 建立"
t4_assert_ne "" "${CALLER_B:-}" "C2 夹具：新版场隔离 tmux server + 调用者 pane 建立"

# 同一套 pane 标题夹具铺到两场（名字全不带 scope ⇒ BR1 口径）
STATUS_TITLES=("rd-infra-T9001" "qa-T9002" "pm-M20261014-evil" "sec-audit" "sec-audit-T9003" "subagent-abc")
ST_OK=1
for t in "${STATUS_TITLES[@]}"; do
  start_titled "$SOCK_A" "fx-${t}" "π - $t - $(basename "$LAB")" >/dev/null || ST_OK=0
  start_titled "$SOCK_B" "fx-${t}" "π - $t - $(basename "$LAB")" >/dev/null || ST_OK=0
done
t4_assert_eq "1" "$ST_OK" "C2 夹具：${#STATUS_TITLES[@]} 个标题契约 pane 在两场就绪（标题等不到 ⇒ 本断言红，不假绿）"

run_in "$SOCK_A" "$SOCK_A_DIR" "$CALLER_A" "$BASE_SCRIPT" status
RC_A=$T4_RC; OUT_A="$T4_OUT_ANSI"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" status
RC_B=$T4_RC; OUT_B="$T4_OUT_ANSI"
t4_assert_eq "0" "$RC_A" "C2① 基线（fixture $BASELINE_SHA）status rc=0"
t4_assert_eq "0" "$RC_B" "C2① 新版 status rc=0"
MD5_A="$(printf '%s' "$OUT_A" | md5sum | awk '{print $1}')"
MD5_B="$(printf '%s' "$OUT_B" | md5sum | awk '{print $1}')"
# 可诊断失败：把首个差异行打出来（md5 不同时给出定位）
if [ "$MD5_A" != "$MD5_B" ]; then
  diff -u <(printf '%s\n' "$OUT_A") <(printf '%s\n' "$OUT_B") 2>/dev/null | head -20 >&2 || true
fi
t4_assert_eq "$MD5_A" "$MD5_B" \
  "C2① 名册离线正常路径：新版 status 全文与基线逐字等价（md5 $MD5_A；scope 为空 ⇒ 零回归）"
t4_info "C2① status md5 = $MD5_A（两场相等；行数 $(printf '%s\n' "$OUT_B" | wc -l | tr -d ' ')）"

# ---------------------------------------------------------------- C2② ensure
# 同一 $LAB 上两场顺序跑：基线场填 A，收场后新版场填 B（名字全不带 scope）
ensure_targets() { # <socket> <tmuxdir> <caller> <script> → 拼 "已拉起 行 + --name 值"
  local sock="$1" tdir="$2" pane="$3" script="$4" lines="" names=""
  local -a batches=("pm arch-designer uiux-designer rd-fe rd-be qa rd-infra" "--task T1 rd-be" "--card .agents/prompts/sec-review.md")
  : > "$PI_NAMES"
  for batch in "${batches[@]}"; do
    # shellcheck disable=SC2086
    run_in "$sock" "$tdir" "$pane" "$script" ensure $batch
    [ "$T4_RC" = "0" ] || printf '  -- ensure %s 失败（rc=%s）：%s\n' "$batch" "$T4_RC" "$(printf '%s' "$T4_ERR_ANSI" | head -2)" >&2
    lines+="$(printf '%s\n' "$T4_OUT_ANSI" | grep -F -- '[tmux] 已拉起' || true)"$'\n'
  done
  names="$(cat "$PI_NAMES" 2>/dev/null || true)"
  # 归一化夹具路径（$LAB 含每轮 mktemp 随机串）⇒ md5 跨轮稳定，可直接作为回执里的对照数字
  #   （只替换夹具根，不动其余字节；两场用同一 $LAB，归一化前后都是同一口径）
  printf '%s\n%s\n' "$lines" "$names" | sed -e "s|$LAB|<LAB>|g"
}
BLOB_A="$(ensure_targets "$SOCK_A" "$SOCK_A_DIR" "$CALLER_A" "$BASE_SCRIPT")"
BLOB_B="$(ensure_targets "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh")"
LAUNCH_N_A="$(printf '%s\n' "$BLOB_A" | grep -cF -- '[tmux] 已拉起' || true)"
LAUNCH_N_B="$(printf '%s\n' "$BLOB_B" | grep -cF -- '[tmux] 已拉起' || true)"
t4_assert_eq "9" "$LAUNCH_N_A" "C2② 基线场 9 个目标全部拉起（7 常驻 + --task + --card）"
t4_assert_eq "9" "$LAUNCH_N_B" "C2② 新版场 9 个目标全部拉起（否则下面 md5 相等无意义）"
t4_assert_contains "$BLOB_B" 'rd-be-T1' "C2② 新版 --name 含派生名 rd-be-T1（--task 路径已走 builder）"
t4_assert_contains "$BLOB_B" 'sec-review' "C2② 新版 --name 含卡会话 sec-review（--card 路径已走 builder）"
MDB_A="$(printf '%s' "$BLOB_A" | md5sum | awk '{print $1}')"
MDB_B="$(printf '%s' "$BLOB_B" | md5sum | awk '{print $1}')"
if [ "$MDB_A" != "$MDB_B" ]; then
  diff -u <(printf '%s\n' "$BLOB_A") <(printf '%s\n' "$BLOB_B") 2>/dev/null | head -20 >&2 || true
fi
t4_assert_eq "$MDB_A" "$MDB_B" \
  "C2② 新版 ensure「已拉起」行 + pi --name 值与基线逐字等价（md5 $MDB_A；scope 为空 ⇒ 零回归）"
t4_info "C2② ensure blob md5 = $MDB_A（已拉起 $LAUNCH_N_B 条 + --name $(printf '%s\n' "$BLOB_B" | grep -c '^$' >/dev/null; printf '%s' "$BLOB_B" | sed -n '/已拉起/,$p' | grep -cE '^[a-z]' || true) 值）"

t4_exit
