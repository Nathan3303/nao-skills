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
#   ② 契约块**外**正文 0 命中 `<name|disp|core>="?(${…}|$ident)-${?(task|TASK)`（禁名字**与** core 拼接）
#      判据边界（P3-3② 选 ① · P3-a 收紧）：左右两段都**允许花括号与不花括号**（`${NAME}` / `$NAME`），
#      左段另允许数组下标（`${t_names[$i]}`）；左边界要求非标识符字符（防 `basename=` 误报）。
#      即只匹配「左段 + `-` + `${?task…`」这种**拼接形态**；
#      `core="${1-}"` / `core="$p_role"` / `core="$(fleet_core_build …)"` 这类纯赋值与
#      唯一构造点**不匹配** ⇒ 不会把合法用法误判成违规。已知盲区：拼接不落在 `name|disp|core`
#      这三个变量名上（如 `c="$r-$t"`）—— 已全部改走 `fleet_core_build`，故本轮 0 命中。
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
    | grep -cE '(^|[^A-Za-z0-9_])(name|disp|core)="?(\$\{[^}]+\}|\$[A-Za-z_][A-Za-z0-9_]*)?-\$(\{)?(task|TASK)' || true
}
lint3() { grep -c 'fleet_name_parse' "$1" || true; }                   # ③ 接线可见面（含说明行）
lint3c() { grep -cE 'fleet_name_parse "' "$1" || true; }               # ③ 代码调用点数

t4_assert_eq "1" "$(lint1 "$SUBJECT")" "C3① 全脚本恰 1 处 \`exec pi --name\`（唯一 exec 点）"
t4_assert_eq "0" "$(lint2 "$SUBJECT")" \
  "C3② 契约块外 0 处手写名字/core 拼接（(name|disp|core)=\${…}-\${task} 形态）"
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
# ---- C3 负控 A2（P3-3② / P3-a）：`core=` 手拼在 builder 外 ⇒ ②必须红 ----
#   **必须用无花括号形**：历史缺陷（7b08214 的 :2277/:2282/:2552）就是 `core="$NAME-$task"` 这种写法；
#   用花括号形做负控 = 「只证明能抓到自己写得出的那种」，正是 P3-a 判「声明比判据强」的根因。
NEG_A2="$T4_CACHE_DIR/c3-neg-a2.sh"
if mutate_file "$SUBJECT" "$NEG_A2" \
    '  local force="$1" task="$2" target="${3:-}"' \
    '  local force="$1" task="$2" target="${3:-}"
  core="$NAME-$task"'; then
  t4_assert_ne "0" "$(lint2 "$NEG_A2")" \
    "C3 负控A2 手写 \`core=\"\$NAME-\$task\"\`（无花括号形，与历史缺陷同形）⇒ ②红"
else
  t4_bad "C3 负控A2 变异锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3② 形态矩阵（P3-a）：拼接写法必须**全抓**（修复前：花括号形 1/1、无括号形全 0）----
NEG_MX="$T4_CACHE_DIR/c3-neg-matrix.sh"
if mutate_file "$SUBJECT" "$NEG_MX" \
    '  local force="$1" task="$2" target="${3:-}"' \
    '  local force="$1" task="$2" target="${3:-}"
  core="${NAME}-${task}"
  core="$NAME-$task"
  core="$NAME-${task}"
  core="${NAME}-$task"
  name="$NAME-$task"
  disp="$NAME-$task"
  core="${t_names[$i]}-${task}"
  core="$card_role-$task"'; then
  t4_assert_eq "8" "$(lint2 "$NEG_MX")" \
    "C3② 形态矩阵：8 种拼接写法全抓（花括号 2 · 无括号 3 · 混合 1 · 数组下标 1 · 卡 role 1）⇒ 判据与声明一致"
  t4_assert_eq "0" "$(lint2 "$SUBJECT")" "C3② 形态矩阵对照：真脚本仍 0（不误报合法构造）"
else
  t4_bad "C3② 形态矩阵锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3② 正控：唯一构造点自身 / 合法赋值不得被误判 ----
t4_assert_eq "0" \
  "$(awk '/^fleet_core_build\(\)/{f=1} f{print} f&&/^}/{exit}' "$SUBJECT" | lint2 /dev/stdin)" \
  "C3② 正控 fleet_core_build 自身 0 命中（判据只认拼接形态，不误判 printf 里的合法拼法）"
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

# ============================================================================
# #96 二期 B1：BR1 机械保证（动态面）+ herdr 判定面（幽灵 pane / 集成缺失 / BR7 映射）
#   ① 双拼写 md5：未设 NAO_TERMINAL 与显式 =tmux 两次 invocation 的 status 全文 md5 相等，
#      且都等于 C2 golden（基线 fixture 的 md5）—— 默认值唯一 ⇒ 两种拼写不可分叉
#   ② 双向 PATH 桩负控：tmux 模式下 herdr 桩 0 命中；herdr 模式下 tmux 桩 0 命中（+ node 探针 0 命中）
#   ③ tmux 侧调用次数零漂移：基线脚本与新脚本的 status 逐子命令计数相等（C2 只比 md5，抓不到次数）
#   ④ herdr 判定面：label 命中 ≠ 在线 —— ghost / integration-missing / dead / mismatch 各一档；
#      BR7 忙闲映射单测（term_deliverable）+ 快照缓存（多次 liveness 只 1 次 pane list / agent list）
# ============================================================================
REAL_TMUX28="$(command -v tmux)"
# ---- 桩：herdr（记录调用 + 供判定面夹具）· tmux 包装（记录后转发真 tmux）· node（记录后失败）----
cat > "$LAB/bin/herdr" <<SH
#!/usr/bin/env bash
printf 'herdr %s\n' "\$*" >> "$LAB/herdr-calls.log"
shift 2   # --session <s>
case "\$1" in
  --version) echo 'herdr 0.9.1'; exit 0 ;;
  api) printf 'Herdr API schema\nprotocol: %s\n' "\${HERDR_STUB_PROTOCOL:-22}"; exit 0 ;;
  pane)
    case "\$2" in
      list) cat <<'J'
{"result":{"panes":[
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-rd-fe"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-fe","pane_id":"w1:p1","terminal_id":"term_1"},
{"agent_status":"unknown","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-be-T9","pane_id":"w1:p2","terminal_id":"term_2"},
{"agent":"pi","agent_session":null,"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"qa-T9","pane_id":"w1:p3","terminal_id":"term_3"},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-pm"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"pm","pane_id":"w1:p4","terminal_id":"term_4"},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-ri"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-infra-T9","pane_id":"w1:p5","terminal_id":"term_5"}
],"type":"pane_list"}}
J
        ;;
      process-info)
        case "\${4:-}" in
          w1:p1) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","rd-fe"],"name":"pi","pid":11}],"pane_id":"w1:p1"}}}\n' ;;
          w1:p2) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["sleep","600"],"name":"sleep","pid":12}],"pane_id":"w1:p2"}}}\n' ;;
          w1:p3) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","qa-T9"],"name":"pi","pid":13}],"pane_id":"w1:p3"}}}\n' ;;
          w1:p4) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/bash"],"name":"bash","pid":14}],"pane_id":"w1:p4"}}}\n' ;;
          w1:p5) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","somebody-else"],"name":"pi","pid":15}],"pane_id":"w1:p5"}}}\n' ;;
          *) printf '{"result":{"process_info":{"foreground_processes":[],"pane_id":"%s"}}}\n' "\${4:-?}" ;;
        esac
        ;;
      *) exit 1 ;;
    esac ;;
  agent)
    case "\$2" in
      list) cat <<'J'
{"result":{"agents":[
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-rd-fe"},"agent_status":"idle","pane_id":"w1:p1","screen_detection_skipped":true,"state_change_seq":3},
{"agent":"pi","agent_session":null,"agent_status":"idle","pane_id":"w1:p3","screen_detection_skipped":false,"state_change_seq":2},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-pm"},"agent_status":"idle","pane_id":"w1:p4","screen_detection_skipped":true,"state_change_seq":1},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-ri"},"agent_status":"working","pane_id":"w1:p5","screen_detection_skipped":true,"state_change_seq":4}
],"type":"agent_list"}}
J
        ;;
      *) exit 1 ;;
    esac ;;
esac
exit 0
SH
sed -i "s#LABROOT#$LAB#g" "$LAB/bin/herdr"
cat > "$LAB/bin/tmux" <<SH
#!/usr/bin/env bash
printf 'tmux %s\n' "\$*" >> "$LAB/tmux-calls.log"
exec "$REAL_TMUX28" "\$@"
SH
cat > "$LAB/bin/node" <<SH
#!/usr/bin/env bash
printf 'node %s\n' "\$*" >> "$LAB/node-calls.log"
exit 1
SH
chmod +x "$LAB/bin/herdr" "$LAB/bin/tmux" "$LAB/bin/node"

# ---- ① 双拼写 md5（未设 vs 显式 =tmux；两次 invocation 必须逐字同源）----
: > "$LAB/herdr-calls.log"
unset NAO_TERMINAL
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" status
RC_DEF=$T4_RC; OUT_DEF="$T4_OUT_ANSI"
export NAO_TERMINAL=tmux
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" status
RC_TMUX=$T4_RC; OUT_TMUX="$T4_OUT_ANSI"
unset NAO_TERMINAL
MD5_DEF="$(printf '%s' "$OUT_DEF" | md5sum | awk '{print $1}')"
MD5_TMUX="$(printf '%s' "$OUT_TMUX" | md5sum | awk '{print $1}')"
t4_assert_eq "0" "$RC_DEF" "B1① 未设 NAO_TERMINAL ⇒ status rc=0"
t4_assert_eq "0" "$RC_TMUX" "B1① 显式 NAO_TERMINAL=tmux ⇒ status rc=0"
t4_assert_eq "$MD5_DEF" "$MD5_TMUX" "B1① 双拼写 status 全文 md5 相等（默认值唯一 ⇒ 不可分叉）"
t4_assert_eq "$MD5_A" "$MD5_DEF" "B1① 未设拼写 == C2 golden（基线 fixture 场）"
t4_assert_eq "$MD5_A" "$MD5_TMUX" "B1① =tmux 拼写 == C2 golden（基线 fixture 场）"
t4_info "B1① 双拼写 md5：未设=$MD5_DEF · =tmux=$MD5_TMUX · C2 golden=$MD5_A"
t4_assert_eq "0" "$(grep -c '^herdr ' "$LAB/herdr-calls.log" || true)" \
  "B1② tmux 模式 status：herdr 桩 0 命中（tmux 后端不碰 herdr）"

# ---- ③ tmux 调用次数零漂移（逐子命令计数：基线 vs 新版，同一套夹具 pane）----
count_tmux_calls() { # <log> <子命令> → 次数
  awk -v s="$2" '$1 == "tmux" { for (i = 2; i <= NF; i++) if ($i == s) { n++; break } } END { print n + 0 }' "$1"
}
: > "$LAB/tmux-calls.log"
run_in "$SOCK_A" "$SOCK_A_DIR" "$CALLER_A" "$BASE_SCRIPT" status
cp "$LAB/tmux-calls.log" "$LAB/tmux-base.log"
: > "$LAB/tmux-calls.log"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" status
cp "$LAB/tmux-calls.log" "$LAB/tmux-new.log"
for sub in list-panes list-sessions display-message capture-pane has-session; do
  t4_assert_eq "$(count_tmux_calls "$LAB/tmux-base.log" "$sub")" \
    "$(count_tmux_calls "$LAB/tmux-new.log" "$sub")" \
    "B1③ status 的 \`tmux $sub\` 调用次数与基线一致（C2 只比 md5，抓不到次数漂移）"
done
t4_assert_eq "$(grep -c '^tmux ' "$LAB/tmux-base.log" || true)" "$(grep -c '^tmux ' "$LAB/tmux-new.log" || true)" \
  "B1③ status 的 tmux 总调用次数与基线一致"

# ---- ② herdr 模式 status（端到端）：双向桩负控 + 四档非在线证据单列 ----
HENV=(env HERDR_ENV=1 HERDR_SESSION=nao-b1-status HERDR_SOCKET_PATH="$LAB/cfg/sessions/nao-b1-status/herdr.sock")
: > "$LAB/tmux-calls.log"; : > "$LAB/node-calls.log"; : > "$LAB/herdr-calls.log"
export NAO_TERMINAL=herdr
t4_run_in_dir "$LAB" "${HENV[@]}" NAO_TERMINAL=herdr NAO_SKILLS="$LAB" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" status
unset NAO_TERMINAL
RC_H=$T4_RC; OUT_H="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"; ERR_H="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$RC_H" "B1② herdr 模式 status rc=0（桩 protocol 22）"
t4_assert_eq "0" "$(grep -c '^tmux ' "$LAB/tmux-calls.log" || true)" \
  "B1② herdr 模式 status：tmux 桩 0 命中（后端隔离）"
t4_assert_eq "0" "$(grep -c '^node ' "$LAB/node-calls.log" || true)" \
  "B1② herdr 模式 status：名册探针（node）0 命中（身份/归属/忙闲全来自结构化事实）"
t4_assert_contains "$OUT_H" "✓ rd-fe " "B1④ 在线档：label + argv --name + agent_session + hook 权威 ⇒ ✓ 在线"
t4_assert_contains "$OUT_H" "== 终端证据异常（herdr 后端：label 命中 ≠ 在线）==" "B1④ 非在线证据单列成节"
t4_assert_contains "$OUT_H" "rd-be-T9 幽灵 pane" "B1④ 幽灵 pane：label 在、agent 条目缺 ⇒ 单列（不得当「已在运行」）"
t4_assert_contains "$OUT_H" "qa-T9 集成缺失" "B1④ 集成缺失：agent_session 空 ⇒ 单列"
t4_assert_contains "$OUT_H" "qa-T9 集成缺失" "B1④ 集成缺失点名会话"
t4_assert_contains "$OUT_H" "不可投递" "B1④ 集成缺失 ⇒ 明确「不可投递」（不退化成 unknown 静默）"
t4_assert_contains "$OUT_H" "pm 前台非 pi" "B1④ dead 档：agent 条目在但前台非 pi ⇒ 非在线（不得谎报在线）"
t4_assert_contains "$OUT_H" "rd-infra-T9 身份不一致" "B1④ mismatch 档：label 与 argv --name 不符 ⇒ 非在线（禁猜）"
t4_assert_not_contains "$OUT_H" "✓ rd-be-T9" "B1④ 幽灵 pane 不得渲染成在线"
t4_assert_not_contains "$OUT_H" "✓ qa-T9" "B1④ 集成缺失不得渲染成在线"
t4_assert_eq "1" "$(grep -c '^herdr .*pane list' "$LAB/herdr-calls.log" || true)" \
  "B1④ 每命令恰 1 次 pane list（快照单点，禁逐名调用）"
t4_assert_eq "1" "$(grep -c '^herdr .*agent list' "$LAB/herdr-calls.log" || true)" \
  "B1④ 每命令恰 1 次 agent list（权威源单点）"

# ---- ④ BR7 忙闲映射 + 阶梯单测（抽取门面区到子进程；只灌纯依赖，不启 tmux）----
FACADE_SRC="$T4_CACHE_DIR/b1-facade.sh"
awk '/^# >>> term-facade BEGIN/{f=1; next} /^# <<< term-facade END/{f=0} f' \
  "$LAB/.agents/scripts/nao-fleet.sh" > "$FACADE_SRC"
t4_assert_ne "0" "$(wc -l < "$FACADE_SRC" | tr -d ' ')" \
  "B1④ 门面区可抽取（# >>> term-facade BEGIN … END，非空 ⇒ 四函数可独立单测）"
{
  printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'warn() { printf "[warn] %%s\\n" "$*" >&2; }\n'
  printf 'die() { printf "[die] %%s\\n" "$*" >&2; exit 1; }\n'
  printf 'require_tmux() { return 0; }\n'
  printf 'TERM_HERDR_PROTOCOL=%s\n' "$(sed -n 's/^TERM_HERDR_PROTOCOL="\([^"]*\)"$/\1/p' "$LAB/.agents/scripts/nao-fleet.sh" | head -1)"
  printf 'VERBOSE=false\n'
  awk '/^nao_phys_path\(\)/{f=1} f{print} f&&/^}/{exit}' "$LAB/.agents/scripts/nao-fleet.sh"
  awk '/^repo_contains_path\(\)/{print; exit}' "$LAB/.agents/scripts/nao-fleet.sh"
  cat "$FACADE_SRC"
  cat <<'CHILD'
FAIL=0; OK=0
chk() { if [ "$2" = "$3" ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); printf '  ✗ %s want=[%s] got=[%s]\n' "$1" "$2" "$3"; fi; }
v() { term_liveness "$1" | cut -f1; }
chk "在线档（label+argv+session+hook）" "online" "$(v rd-fe)"
chk "在线档状态取 agent list（idle）" "online	idle	3	1" "$(term_liveness rd-fe)"
chk "幽灵 pane（label 在、agent 条目缺）" "ghost" "$(v rd-be-T9)"
chk "集成缺失（agent_session 空）" "integration-missing" "$(v qa-T9)"
chk "前台非 pi ⇒ dead（不谎报在线）" "dead" "$(v pm)"
chk "argv --name 不符 ⇒ mismatch" "mismatch" "$(v rd-infra-T9)"
chk "无 label 命中 ⇒ absent" "absent	-	-	-" "$(term_liveness no-such-session)"
chk "BR7 idle 可投递" "0" "$(term_deliverable idle; echo $?)"
chk "BR7 done 可投递（无 pi 路径的死分支，保留兼容）" "0" "$(term_deliverable done; echo $?)"
chk "BR7 working 不可投递" "1" "$(term_deliverable working; echo $?)"
chk "BR7 blocked 不可投递" "1" "$(term_deliverable blocked; echo $?)"
chk "BR7 unknown 保守不可投递" "1" "$(term_deliverable unknown; echo $?)"
chk "BR7 空值保守不可投递" "1" "$(term_deliverable ''; echo $?)"
# 快照缓存：上面已调用 term_liveness 7 次 ⇒ pane list / agent list 各仍只 1 次
chk "快照缓存：pane list 恰 1 次" "1" "$(grep -c '^herdr .*pane list' "$STUB_LOG" || true)"
chk "快照缓存：agent list 恰 1 次" "1" "$(grep -c '^herdr .*agent list' "$STUB_LOG" || true)"
# 前提闸门：protocol != 22 ⇒ exit 3（fail loud，不静默降级）
( HERDR_STUB_PROTOCOL=21; export HERDR_STUB_PROTOCOL; term_require >/dev/null 2>&1 )
chk "protocol 21 ⇒ exit 3" "3" "$?"
if [ "$FAIL" -gt 0 ]; then printf 'FACADE_FAIL ok=%d bad=%d\n' "$OK" "$FAIL"; exit 1; fi
printf 'FACADE_OK %d\n' "$OK"
CHILD
} > "$T4_CACHE_DIR/b1-facade-test.sh"
: > "$LAB/herdr-calls.log"
fac_out="$(STUB_LOG="$LAB/herdr-calls.log" HERDR_ENV=1 HERDR_SESSION=nao-b1-unit \
  HERDR_SOCKET_PATH="$LAB/cfg/sessions/nao-b1-unit/herdr.sock" NAO_TERMINAL=herdr \
  PATH="$LAB/bin:$PATH" "$BASH_BIN" "$T4_CACHE_DIR/b1-facade-test.sh" 2>&1)"; fac_rc=$?
t4_assert_eq "0" "$fac_rc" "B1④ 门面单测全绿（阶梯 + BR7 映射 + 快照缓存 + protocol 闸门）"
t4_assert_contains "$fac_out" "FACADE_OK" "B1④ 门面单测自报 OK（明细：$(printf '%s' "$fac_out" | tail -1)）"


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

# ============================================================================
# P2-1（第二轮 QA · 命名预算自洽）：builder 造得出 ⇒ parse 必须认得回
#   回归：card core 32 + '@' + scope 16 = 49 > 48 时，builder 照造、ensure 相位 1 不校验总长
#   ⇒ 会话拉得起来但 parse 恒 ERR ⇒ status **整条消失**（连「角色未识别」节也不进）。
#   修法：相位 1 用 parse 复核 builder 输出，非 OK 即 die（建 pane 之前 ⇒ BR6 零副作用）；
#   builder 不 die（close/status 也调它）。
# ============================================================================
T42="$(printf 'T%.0s' $(seq 1 42))"        # rd-be- + 42 = 48 字符（上限内，必须能起 + 必须可见）
T43="$(printf 'T%.0s' $(seq 1 43))"        # 49 字符（必须被拒）
BUD48="rd-be-$T42"
CARD32="$(printf 'c%.0s' $(seq 1 32))"     # 卡 core 恰好 32（卡校验上限）
SCOPE15="$(printf 's%.0s' $(seq 1 15))"    # 32 + 1 + 15 = 48（合法边界）
SCOPE16="$(printf 's%.0s' $(seq 1 16))"    # 32 + 1 + 16 = 49（超限）
printf -- '---\nrole: %s\n---\n# 32 字符卡（P2-1 预算边界夹具）\n' "$CARD32" > "$LAB/.agents/prompts/$CARD32.md"

pane_count_b() { "$REAL_TMUX" -S "$SOCK_B" list-panes -a -F '#{pane_id}' 2>/dev/null | wc -l | tr -d ' '; }

# ---- 负控：49 字符（task 43）⇒ die + 指路；零副作用 ----
BEFORE_N="$(pane_count_b)"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task "$T43" rd-be
t4_assert_ne "0" "$T4_RC" "P2-1 负控A：\`--task\` 43 位（总名 49 > 48）⇒ 拒绝（rc≠0）"
t4_assert_contains "$T4_ERR_ANSI" "目标名超预算" "P2-1 负控A：die 点名「目标名超预算」"
t4_assert_contains "$T4_ERR_ANSI" "49 字符 > 48" "P2-1 负控A：die 回显当前长度与上限（49 > 48）"
t4_assert_contains "$T4_ERR_ANSI" "该怎么办" "P2-1 负控A：die 给改法（该怎么办：缩短 --task 编号或 scope）"
t4_assert_contains "$T4_ERR_ANSI" "缩短 scope" "P3-b 负控A：**总长超限**分支必须提示可缩 scope（与负控C 的「不提示」成对）"
t4_assert_eq "$BEFORE_N" "$(pane_count_b)" "P2-1 负控A：零副作用（建 pane 之前就 die，pane 数不变）"

# ---- 负控：卡 core 32 + scope 16 = 49 ⇒ die（两者各自合法，合起来超限）----
BEFORE_N="$(pane_count_b)"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" \
  ensure --card ".agents/prompts/$CARD32.md" --scope "$SCOPE16"
t4_assert_ne "0" "$T4_RC" "P2-1 负控B：卡 core 32 + scope 16（总名 49）⇒ 拒绝（rc≠0）"
t4_assert_contains "$T4_ERR_ANSI" "49 字符 > 48" "P2-1 负控B：die 回显当前长度（32+1+16=49）"
t4_assert_eq "$BEFORE_N" "$(pane_count_b)" "P2-1 负控B：零副作用（pane 数不变）"

# ---- 负控C（P3-b）：卡 core 32 + `--task T1` ⇒ core 35 > **32**（卡 core 上限）----
#   拒绝是正确的，但文案若说成「35 字符 > 48」就是**事实错**（35 并不 > 48），且「缩 scope」是死路
#   （scope 只占 '@' 之后那段）⇒ 必须按原因分支给文案。
BEFORE_N="$(pane_count_b)"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" \
  ensure --card ".agents/prompts/$CARD32.md" --task T1
t4_assert_ne "0" "$T4_RC" "P2-1 负控C（P3-b）：卡 core 32 + --task T1（core 35）⇒ 拒绝（rc≠0）"
t4_assert_contains "$T4_ERR_ANSI" "卡会话 core 超上限" "P3-b 负控C：die 点名原因是**卡 core 上限**（不是总长）"
t4_assert_contains "$T4_ERR_ANSI" "35 字符 > 32" "P3-b 负控C：die 回显 core 长度与正确上限（35 > 32）"
t4_assert_not_contains "$T4_ERR_ANSI" "35 字符 > 48" "P3-b 负控C：不得把 35 说成「35 字符 > 48」（事实错）"
t4_assert_not_contains "$T4_ERR_ANSI" "缩短 scope" "P3-b 负控C：不提示缩 scope（死路：scope 只占 @ 之后那段）"
t4_assert_eq "$BEFORE_N" "$(pane_count_b)" "P3-b 负控C：零副作用（pane 数不变）"

# ---- 正控：48 字符边界仍能起（task 42）----
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task "$T42" rd-be
t4_assert_eq "0" "$T4_RC" "P2-1 正控A：总名恰 48 字符 ⇒ rc=0（边界不被误拒）"
t4_assert_contains "$T4_OUT_ANSI" "已拉起" "P2-1 正控A：确实拉起（已拉起行在位）"
t4_assert_eq "48" "$(printf '%s' "$BUD48" | wc -c | tr -d ' ')" "P2-1 正控A：夹具名字长度确认 = 48"

# ---- 正控：48 字符名字在 status 里**看得见**（这就是 P2-1 要防的静默漏行）----
start_titled "$SOCK_B" "fx-bud48" "π - $BUD48 - $(basename "$LAB")" >/dev/null \
  || t4_bad "P2-1 正控A：48 字符名字的标题 pane 未就绪（等不到标题 ⇒ 负控可能假绿）"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" status
t4_assert_contains "$T4_OUT_ANSI" "  · $BUD48" \
  "P2-1 正控A：48 字符名在 status 派生节可见（parse 认得回 ⇒ 不静默漏行）"

# ---- 正控：卡 core 32 + scope 15 = 48 ⇒ 起得来 ----
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" \
  ensure --card ".agents/prompts/$CARD32.md" --scope "$SCOPE15"
t4_assert_eq "0" "$T4_RC" "P2-1 正控B：卡 core 32 + scope 15 = 48 ⇒ rc=0"
t4_assert_contains "$T4_OUT_ANSI" "$CARD32@$SCOPE15" \
  "P2-1 正控B：拉起名逐字 = <32 卡 role>@<15 scope>（scope 由 builder 追加）"

# ============================================================================
# P3-2 / P3-3①：常驻「裸名 + 带 scope」同场 ⇒ **两条都显示**；显示名走 builder
#   回归：旧写法 `elif` 只留裸名 ⇒ `rd-be@todo` 在 status 任何位置都不出现。
# ============================================================================
start_titled "$SOCK_B" "fx-bare-rbe" "π - rd-be - $(basename "$LAB")" >/dev/null \
  || t4_bad "P3-2 夹具：裸名 rd-be 的标题 pane 未就绪"
start_titled "$SOCK_B" "fx-scoped-rbe" "π - rd-be@todo - $(basename "$LAB")" >/dev/null \
  || t4_bad "P3-2 夹具：rd-be@todo 的标题 pane 未就绪"
run_in "$SOCK_B" "$SOCK_B_DIR" "$CALLER_B" "$LAB/.agents/scripts/nao-fleet.sh" status
RBE_LINES="$(printf '%s\n' "$T4_OUT_ANSI" | grep -F -- '  ✓ rd-be ' || true)"
t4_assert_eq "2" "$(printf '%s\n' "$RBE_LINES" | grep -c . || true)" \
  "P3-2 同场：rd-be 与 rd-be@todo **两条都显示**（旧写法只留裸名 ⇒ 本断言红）"
t4_assert_contains "$RBE_LINES" "--name rd-be；" "P3-2 同场：裸名那条仍在（逐字格式不变）"
t4_assert_contains "$RBE_LINES" "--name rd-be@todo；" "P3-2 同场：带 scope 那条在位（名字经 builder 生成）"
t4_assert_contains "$RBE_LINES" "·scope=todo" "P3-2 / D5：带 scope 行尾有 ·scope=<x> 字段"
t4_assert_not_contains "$(printf '%s\n' "$RBE_LINES" | grep -F -- '·scope=todo')" "--name rd-be；" \
  "P3-3① ·scope 行只出现在带 scope 的那条上（不是裸名行被追加字段）"
t4_assert_contains "$T4_OUT_ANSI" "rd-be@todo" \
  "P2-1 正控C：带 scope 常驻可在 status 定位（不整条消失）"

t4_exit
