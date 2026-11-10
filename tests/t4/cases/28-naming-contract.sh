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
# B3（#96 二期）节：herdr close / cleanup 回收面（忙闲闸门 BR7 / self 判据 / effect 判据 /
#   同义反复防护：tmux 落地段 golden md5），详见文件末尾「B3」节头。
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
# P3-5（B2 订正）：改为**按本用例 PID + mtime 归属**判「系统 /tmp 净增」——全域计数在并发下会假红/假绿。
#   归属通道：每次 fleet 调用都用 `bash -c 'echo $$; exec …'` 记下**最终进程 PID**（exec 不改 PID），
#   快照文件名 = `nao-fleet-term-snap.<pid>.<rand>` ⇒ 只统计「窗口内新建 ∧ pid 属于本用例」的文件。
B2_SNAP_TS="$(date +%s)"
B2_PID_LOG="$LAB/fleet-pids.log"; : > "$B2_PID_LOG"; export B2_PID_LOG
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
      list)
        if [ "\${HERDR_STUB_EMPTY:-0}" = "1" ]; then
          printf '%s\n' '{"result":{"panes":[{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-x"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","pane_id":"w9:p1","terminal_id":"term_9"}],"type":"pane_list"}}'
          exit 0
        fi
        cat <<'J'
{"result":{"panes":[
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-rd-fe"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-fe","pane_id":"w1:p1","terminal_id":"term_1"},
{"agent_status":"unknown","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-be-T9","pane_id":"w1:p2","terminal_id":"term_2"},
{"agent":"pi","agent_session":null,"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"qa-T9","pane_id":"w1:p3","terminal_id":"term_3"},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-pm"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"pm","pane_id":"w1:p4","terminal_id":"term_4"},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-ri"},"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-infra-T9","pane_id":"w1:p5","terminal_id":"term_5"},
{"agent_status":"unknown","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"rd-be@todo","pane_id":"w1:p6","terminal_id":"term_6"},
{"agent":"pi","agent_session":null,"agent_status":"idle","cwd":"LABROOT","foreground_cwd":"LABROOT","label":"qa@todo","pane_id":"w1:p7","terminal_id":"term_7"}
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
          w1:p6) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["sleep","600"],"name":"sleep","pid":16}],"pane_id":"w1:p6"}}}\n' ;;
          w1:p7) printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","qa@todo"],"name":"pi","pid":17}],"pane_id":"w1:p7"}}}\n' ;;
          *) printf '{"result":{"process_info":{"foreground_processes":[],"pane_id":"%s"}}}\n' "\${4:-?}" ;;
        esac
        ;;
      *) exit 1 ;;
    esac ;;
  agent)
    case "\$2" in
      list)
        if [ "\${HERDR_STUB_EMPTY:-0}" = "1" ]; then
          printf '%s\n' '{"result":{"agents":[{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-x"},"agent_status":"idle","pane_id":"w9:p1","screen_detection_skipped":true,"state_change_seq":1}],"type":"agent_list"}}'
          exit 0
        fi
        cat <<'J'
{"result":{"agents":[
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-rd-fe"},"agent_status":"idle","pane_id":"w1:p1","screen_detection_skipped":true,"state_change_seq":3},
{"agent":"pi","agent_session":null,"agent_status":"idle","pane_id":"w1:p3","screen_detection_skipped":false,"state_change_seq":2},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-pm"},"agent_status":"idle","pane_id":"w1:p4","screen_detection_skipped":true,"state_change_seq":1},
{"agent":"pi","agent_session":{"agent":"pi","kind":"id","value":"sess-ri"},"agent_status":"working","pane_id":"w1:p5","screen_detection_skipped":true,"state_change_seq":4},
{"agent":"pi","agent_session":null,"agent_status":"idle","pane_id":"w1:p7","screen_detection_skipped":false,"state_change_seq":5}
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
# P2-1：socket 必须落在目标根（XDG_CONFIG_HOME/herdr/sessions/<名>/）下 —— 夹具与之一致
HENV=(env HERDR_ENV=1 HERDR_SESSION=nao-b1-status XDG_CONFIG_HOME="$LAB/cfg" \
  HERDR_SOCKET_PATH="$LAB/cfg/herdr/sessions/nao-b1-status/herdr.sock")
mkdir -p "$LAB/tmp"   # 私有 TMPDIR：快照临时文件必须落这里且跑完为空（P3-5 残留断言）
: > "$LAB/tmux-calls.log"; : > "$LAB/node-calls.log"; : > "$LAB/herdr-calls.log"
export NAO_TERMINAL=herdr
t4_run_in_dir "$LAB" "${HENV[@]}" NAO_TERMINAL=herdr NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$LAB/.agents/scripts/nao-fleet.sh" status
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
# P1（QA 第二轮 · AC2.1 语义破口）：带 scope 的名字来自 pane.label —— **不是证据**。
#   非在线四档必须**不得**被常驻区打成「✓ 在线」，只能出现在「终端证据异常」节。
t4_assert_not_contains "$OUT_H" "✓ rd-be " "B1① 带 scope 幽灵（rd-be@todo）不得渲染成 ✓ 在线"
t4_assert_not_contains "$OUT_H" "--name rd-be@todo；" "B1① 带 scope 幽灵不得出现「在线（--name rd-be@todo）」行"
t4_assert_not_contains "$OUT_H" "✓ qa " "B1① 带 scope 集成缺失（qa@todo）不得渲染成 ✓ 在线"
t4_assert_not_contains "$OUT_H" "--name qa@todo；" "B1① 带 scope 集成缺失不得出现「在线（--name qa@todo）」行"
t4_assert_contains "$OUT_H" "rd-be@todo 幽灵 pane" "B1① 带 scope 幽灵单列在「终端证据异常」节（非静默）"
t4_assert_contains "$OUT_H" "qa@todo 集成缺失" "B1① 带 scope 集成缺失单列（含「不可投递」）"
t4_assert_contains "$OUT_H" "· rd-be " "B1① 该角色退化为「· 未运行」（不再谎报在线）"
t4_assert_eq "0" "$(ls -A "$LAB/tmp" 2>/dev/null | wc -l | tr -d ' ')" \
  "B1⑤ 快照临时文件零残留（私有 TMPDIR 跑完为空）"

# ---- P3-1（QA 第二轮）：**无 label 会话**时快照合法为空 ⇒ 缓存判据不得靠「非空」
: > "$LAB/herdr-calls.log"
t4_run_in_dir "$LAB" "${HENV[@]}" HERDR_STUB_EMPTY=1 NAO_TERMINAL=herdr NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$LAB/.agents/scripts/nao-fleet.sh" status
RC_E=$T4_RC
t4_assert_eq "0" "$RC_E" "B1⑤ 空 label 夹具：status rc=0（快照为空是合法状态）"
t4_assert_eq "1" "$(grep -c '^herdr .*pane list' "$LAB/herdr-calls.log" || true)" \
  "B1⑤ 空 label 夹具：pane list 仍恰 1 次（缓存判据用「文件存在」而非「非空」）"
t4_assert_eq "1" "$(grep -c '^herdr .*agent list' "$LAB/herdr-calls.log" || true)" \
  "B1⑤ 空 label 夹具：agent list 仍恰 1 次"
t4_assert_eq "0" "$(ls -A "$LAB/tmp" 2>/dev/null | wc -l | tr -d ' ')" "B1⑤ 空 label 夹具：快照临时文件零残留"

# ============================================================================
# B2（#96 二期）：放置 / 就绪门 / 幽灵 pane / 同名歧义 —— 全部用**有状态** herdr 桩（不启真 server）
#   桩状态：$ST/{panes,agents,ws,order.log,calls.log}；`pane run` 按 HERDR_STUB_ONRUN 追加 agent 条目，
#   并记 order.log（用于断言「先 label(rename) 后 run」）。
# ============================================================================
B2ST="$LAB/b2-stub"; B2ST_BIN="$B2ST/bin"; B2ST_ST="$B2ST/st"
mkdir -p "$B2ST_BIN" "$B2ST_ST"
cat > "$B2ST_BIN/herdr" <<'SH'
#!/usr/bin/env bash
ST="${HERDR_STUB_STATE:?}"
printf 'herdr %s\n' "$*" >> "$ST/calls.log"
if [ "${1:-}" = "--session" ]; then shift 2; fi
cmd="${1:-}"; shift || true
json_panes() {
  local first=1 pid label fg ws out=""
  while IFS='|' read -r pid label fg ws; do
    [ -n "$pid" ] || continue
    if [ -n "${WSFILTER:-}" ] && [ "$ws" != "$WSFILTER" ]; then continue; fi
    [ "$first" = 1 ] || out+=","
    first=0
    out+="{\"pane_id\":\"$pid\",\"label\":\"$label\",\"cwd\":\"${HERDR_STUB_CWD:-$ST/repo}\",\"foreground_cwd\":\"${HERDR_STUB_CWD:-$ST/repo}\",\"agent_status\":\"unknown\",\"terminal_id\":\"term_$pid\",\"workspace_id\":\"$ws\"}"
  done < "$ST/panes" 2>/dev/null
  printf '{"result":{"panes":[%s],"type":"pane_list"}}\n' "$out"
}
json_agents() {
  local first=1 pid stat seq skip sess sessj out=""
  while IFS='|' read -r pid stat seq skip sess; do
    [ -n "$pid" ] || continue
    [ "$first" = 1 ] || out+=","
    first=0
    if [ "$sess" = "-" ] || [ -z "$sess" ]; then sessj="null"; else sessj="{\"agent\":\"pi\",\"kind\":\"id\",\"value\":\"$sess\"}"; fi
    if [ "$skip" = "1" ]; then skipj="true"; else skipj="false"; fi
    out+="{\"agent\":\"pi\",\"agent_session\":$sessj,\"agent_status\":\"${stat:-unknown}\",\"pane_id\":\"$pid\",\"screen_detection_skipped\":$skipj,\"state_change_seq\":${seq:-0}}"
  done < "$ST/agents" 2>/dev/null
  printf '{"result":{"agents":[%s],"type":"agent_list"}}\n' "$out"
}
case "$cmd" in
  --version) echo 'herdr 0.9.1' ;;
  api) printf 'Herdr API schema\nprotocol: 22\n' ;;
  pane)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        WSFILTER=""
        if [ "${1:-}" = "--workspace" ]; then WSFILTER="${2:-}"; fi
        json_panes ;;
      process-info)
        pid="${2:-}"; label="$(awk -F'|' -v p="$pid" '$1==p{print $2}' "$ST/panes")"
        fg="$(awk -F'|' -v p="$pid" '$1==p{print $3}' "$ST/panes")"
        # phantom = stop→restart 回放出的不可寻址 pane（实测 pane run/process-info ⇒ pane_not_found，**错误 JSON 走 stderr**）
        if [ "$fg" = "phantom" ]; then
          printf '{"error":{"code":"pane_not_found","message":"pane %s not found"}}\n' "$pid" >&2
          exit 1
        fi
        # internal = 服务端内部错误（pane 仍可达）—— **不得**被当成回放证据
        if [ "$fg" = "internal" ]; then
          printf '{"error":{"code":"internal_error","message":"boom"}}\n' >&2
          exit 1
        fi
        # empty = 可达但空输出（协议异常）—— 也不得 close
        if [ "$fg" = "empty" ]; then
          exit 0
        fi
        if [ "$fg" = "pi" ]; then
          printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","%s"],"name":"pi","pid":1}],"pane_id":"%s"}}}\n' "$label" "$pid"
        else
          printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/%s"],"name":"%s","pid":1}],"pane_id":"%s"}}}\n' "${fg:-bash}" "${fg:-bash}" "$pid"
        fi ;;
      rename)
        pid="${1:-}"; label="${2:-}"
        printf 'rename %s %s\n' "$pid" "$label" >> "$ST/order.log"
        awk -F'|' -v p="$pid" -v l="$label" 'BEGIN{OFS="|"} $1==p{$2=l} {print}' "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes" ;;
      run)
        pid="${1:-}"
        printf 'run %s\n' "$pid" >> "$ST/order.log"
        awk -F'|' -v p="$pid" 'BEGIN{OFS="|"} $1==p{$3="pi"} {print}' "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes"
        if ! grep -q "^$pid|" "$ST/agents" 2>/dev/null; then
          printf '%s|%s\n' "$pid" "${HERDR_STUB_ONRUN:-idle|1|1|sess-x}" >> "$ST/agents"
        fi ;;
      split)
        n=$(( $(wc -l < "$ST/panes") + 1 )); ws="$(awk -F'|' 'NR==1{print $4}' "$ST/panes")"
        new="$ws:p$n"
        printf '%s||bash|%s\n' "$new" "$ws" >> "$ST/panes"
        printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "$new" ;;
      close)
        pid="${1:-}"
        grep -v "^$pid|" "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes" ;;
      *) exit 1 ;;
    esac ;;
  agent)
    sub="${1:-}"; shift || true
    case "$sub" in
      list) json_agents ;;
      *) exit 1 ;;
    esac ;;
  workspace)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        first=1; out=""
        while IFS='|' read -r ws label; do
          [ -n "$ws" ] || continue
          [ "$first" = 1 ] || out+=","
          first=0
          out+="{\"workspace_id\":\"$ws\",\"label\":\"$label\",\"pane_count\":1}"
        done < "$ST/ws" 2>/dev/null
        printf '{"result":{"workspaces":[%s],"type":"workspace_list"}}\n' "$out" ;;
      create)
        label=""
        while [ "$#" -gt 0 ]; do [ "$1" = "--label" ] && label="${2:-}"; shift; done
        ws="w$(( $(wc -l < "$ST/ws" 2>/dev/null || echo 0) + 1 ))"
        printf '%s|%s\n' "$ws" "$label" >> "$ST/ws"
        printf '%s||bash|%s\n' "$ws:p1" "$ws" >> "$ST/panes"
        printf '{"result":{"root_pane":{"pane_id":"%s:p1","workspace_id":"%s"},"workspace":{"workspace_id":"%s","label":"%s"}}}\n' "$ws" "$ws" "$ws" "$label" ;;
      close)
        ws="${1:-}"
        grep -v "^$ws|" "$ST/ws" > "$ST/ws.new" 2>/dev/null || true
        [ -f "$ST/ws.new" ] && mv "$ST/ws.new" "$ST/ws"
        grep -v "|$ws$" "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
exit 0
SH
chmod +x "$B2ST_BIN/herdr"
mkdir -p "$LAB/tmp"
B2_ENV=(env HERDR_ENV=1 HERDR_SESSION=nao-b2-stub XDG_CONFIG_HOME="$LAB/cfg" \
  HERDR_SOCKET_PATH="$LAB/cfg/herdr/sessions/nao-b2-stub/herdr.sock" \
  HERDR_STUB_CWD="$LAB" \
  NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" \
  PATH="$B2ST_BIN:$PATH")
b2_reset() { # 清桩状态（每场景一份）
  rm -rf "$B2ST_ST"; mkdir -p "$B2ST_ST"; : > "$B2ST_ST/panes"; : > "$B2ST_ST/agents"; : > "$B2ST_ST/ws"
  : > "$B2ST_ST/order.log"; : > "$B2ST_ST/calls.log"
}
b2_run() { # <onrun> <args...> → 清桩后跑 fleet（输出落 T4_OUT/T4_ERR）
  local onrun="$1"; shift
  b2_reset
  t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN="$onrun" \
    NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" "$@"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
}

# ---- B2① 反假阳性：已 idle 但 seq 不前进（ONRUN: idle|seq=0|skip=1|session 有）⇒ 就绪门超时 fail loud ----
#   同时验 wall-clock 口径（P3-3）：用 NAO_HERDR_READY_TIMEOUT_MS=400 覆盖，避免本用例白等 5s。
b2_reset
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|0|1|sess-x' \
  NAO_HERDR_READY_TIMEOUT_MS=400 NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "B2① 就绪超时 ⇒ ensure rc 仍 0（D3：跨后端 rc 语义一致）"
t4_assert_contains "$T4_OUT_ANSI$T4_ERR_ANSI" "就绪门超时" "B2① 就绪超时 fail loud（打「就绪门超时」，不是静默）"
t4_assert_contains "$T4_OUT_ANSI$T4_ERR_ANSI" "wall-clock 上限 400ms" \
  "B2①/P3-3 超时按 **wall-clock 上限**报口径（且 NAO_HERDR_READY_TIMEOUT_MS 可覆盖）"
t4_assert_contains "$T4_OUT_ANSI$T4_ERR_ANSI" "state_change_seq ≥ 1" "B2① 逐条报缺：state_change_seq（已 idle 但 seq 不前进）"
t4_assert_not_contains "$T4_OUT_ANSI$T4_ERR_ANSI" "前台进程 name==pi：" "B2① 只报缺的那条（前台已是 pi，不得误报）"
t4_assert_not_contains "$T4_OUT_ANSI$T4_ERR_ANSI" "agent_status == idle：" "B2① 只报缺的那条（状态已 idle，不得误报）"
t4_assert_contains "$T4_OUT_ANSI$T4_ERR_ANSI" "agent explain" "B2① 超时给诊断指路 agent explain <pane>"
t4_assert_not_contains "$T4_OUT_ANSI" "[herdr] 已拉起" "B2① 超时不得打印「[herdr] 已拉起」（不冒充成功）"
t4_assert_contains "$T4_OUT_ANSI" "失败 1" "B2① 超时计入 SPAWN_FAIL（摘要行可见）"

# ---- B2② 幽灵 pane（label 在、agent 无）⇒ 不判 same；复用 pane（不新建 label）且**先 rename 后 run** ----
b2_reset
printf 'w1:p1|rd-fe|bash|w1\n' > "$B2ST_ST/panes"
: > "$B2ST_ST/agents"
: > "$B2ST_ST/ws"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "B2② 幽灵 pane：ensure rc=0"
t4_assert_contains "$B2_ERR" "幽灵 pane" "B2② label 在、agent 条目缺 ⇒ 显式点名幽灵 pane（不静默跳过的可控证据）"
t4_assert_not_contains "$B2_OUT$B2_ERR" "已在运行（" "B2② 幽灵 pane **不得**判「已在运行」跳过（label 命中 ≠ same）"
t4_assert_contains "$B2_OUT" "已拉起 rd-fe" "B2② 幽灵 pane 复用后确实重跑 agent（成功行在位）"
t4_assert_eq "1" "$(grep -c '^rename ' "$B2ST_ST/order.log" || true)" "B2② 复用路径 rename 恰 1 次（label 幂等重写）"
t4_assert_eq "1" "$(grep -c '^run ' "$B2ST_ST/order.log" || true)" "B2② 复用路径 run 恰 1 次（不重复建 pane）"
t4_assert_eq "0" "$(grep -c '^herdr pane split' "$B2ST_ST/calls.log" || true)" \
  "B2② 幽灵复用不新建 pane（同名 label 仍唯一）"
B2_RENAME_LINE="$(grep -n '^rename ' "$B2ST_ST/order.log" | head -1 | cut -d: -f1)"
B2_RUN_LINE="$(grep -n '^run ' "$B2ST_ST/order.log" | head -1 | cut -d: -f1)"
t4_assert_eq "1" "$([ -n "$B2_RENAME_LINE" ] && [ -n "$B2_RUN_LINE" ] && [ "$B2_RENAME_LINE" -lt "$B2_RUN_LINE" ] && echo 1 || echo 0)" \
  "B2② **先 label(rename) 后启动(run)**（order 行号: rename=$B2_RENAME_LINE < run=$B2_RUN_LINE）"

# ---- B2③ 同名 label 多 pane ⇒ warn 点名 + 不猜；status 单列歧义 ----
b2_reset
printf 'w1:p1|rd-fe|pi|w1\nw1:p2|rd-fe|pi|w1\n' > "$B2ST_ST/panes"
printf 'w1:p1|idle|1|1|sess-a\nw1:p2|idle|1|1|sess-b\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "B2③ 同名歧义：ensure rc=0（失败计 SPAWN_FAIL，不是 crash）"
t4_assert_contains "$B2_ERR" "同名 label 命中多个 pane" "B2③ 命中多个 ⇒ warn 点名（不猜）"
t4_assert_contains "$B2_ERR" "w1:p1 w1:p2" "B2③ warn 回显全部命中的 pane（可定位）"
t4_assert_not_contains "$B2_OUT" "[herdr] 已拉起" "B2③ 歧义下不得擅自挑一个启动（无成功行）"
t4_assert_contains "$B2_OUT" "失败 1" "B2③ 歧义计入 SPAWN_FAIL（摘要可见）"
t4_assert_eq "0" "$(grep -cE '^herdr pane (rename|run|split)' "$B2ST_ST/calls.log" || true)" \
  "B2③ 歧义下零放置动作（rename/run/split 都不发）"

b2_reset
printf 'w1:p1|rd-fe|pi|w1\nw1:p2|rd-fe|pi|w1\n' > "$B2ST_ST/panes"
printf 'w1:p1|idle|1|1|sess-a\nw1:p2|idle|1|1|sess-b\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" status
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
sleep 0.6   # 等 status 的子进程/管道收尾（tmux-free，此处只避免与下段 tmux 用例抢输出文件）
t4_assert_eq "0" "$T4_RC" "B2③ 歧义场景 status rc=0（非 crash）"
t4_assert_contains "$B2_OUT" "同名 label 多 pane" "B2③ status 单列「同名 label 多 pane」（终端证据异常节）"
t4_assert_not_contains "$B2_OUT" "✓ rd-fe" "B2③ 歧义不得渲染成 ✓ 在线（不猜）"

# ---- P2-1（QA 第二轮）：HERDR_SOCKET_PATH **目标根**校验（stale/外贸 env 必须 exit 3）----
: > "$LAB/herdr-calls.log"
BAD_ENV=(env HERDR_ENV=1 HERDR_SESSION=nao-b1-status XDG_CONFIG_HOME="$LAB/cfg" \
  HERDR_SOCKET_PATH="/tmp/wrong-root/sessions/nao-b1-status/x.sock")
t4_run_in_dir "$LAB" "${BAD_ENV[@]}" NAO_TERMINAL=herdr NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" status
t4_assert_eq "3" "$T4_RC" "P2-1 错误根的 HERDR_SOCKET_PATH ⇒ exit 3（stale/外贸 env 必拒，不假绿）"
t4_assert_contains "$T4_ERR" "不在目标根" "P2-1 拒绝理由点名「目标根」（不是任意 */sessions/<名>/*）"
t4_assert_contains "$T4_ERR" "$LAB/cfg/herdr/sessions/nao-b1-status" "P2-1 回显期望根（可定位）"
t4_assert_eq "0" "$(grep -c '^herdr ' "$LAB/herdr-calls.log" || true)" \
  "P2-1 根校验先于一切 herdr 调用（stale env 下零后端调用）"

# ---- P2-2（QA 第二轮）：ghost 复用前前台必须是 shell；非 shell ⇒ 不注入 + fail loud ----
for b2fg in cat vim sleep; do
  b2_reset
  printf 'w1:p1|rd-fe|%s|w1\n' "$b2fg" > "$B2ST_ST/panes"
  : > "$B2ST_ST/agents"; : > "$B2ST_ST/ws"
  t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
    NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
  B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "0" "$T4_RC" "P2-2 前台=$b2fg：ensure rc=0（失败计 SPAWN_FAIL，不是 crash）"
  t4_assert_contains "$B2_ERR" "前台非 shell" "P2-2 前台=$b2fg：必须点名「前台非 shell」（不得注入用户程序）"
  t4_assert_contains "$B2_ERR" "$b2fg" "P2-2 前台=$b2fg：诊断回显实际前台进程名"
  t4_assert_contains "$B2_ERR" "--force" "P2-2 前台=$b2fg：给出 --force 指路"
  t4_assert_not_contains "$B2_OUT" "[herdr] 已拉起" "P2-2 前台=$b2fg：不得冒充成功"
  t4_assert_eq "0" "$(grep -c 'pane run ' "$B2ST_ST/calls.log" || true)" \
    "P2-2 前台=$b2fg：**零 pane run**（不把启动命令写进 cat/vim/sleep 的输入）"
  t4_assert_eq "0" "$(grep -c 'pane close ' "$B2ST_ST/calls.log" || true)" \
    "P2-2 前台=$b2fg：也不关闭在场 pane（不误伤用户程序；回收归 B3）"
done

# ---- P2-2b：restart 回放幽灵（process-info 不可用）⇒ 关闭并重建，且不注入 ----
b2_reset
printf 'w1:p1|rd-fe|phantom|w1\n' > "$B2ST_ST/panes"
: > "$B2ST_ST/agents"; : > "$B2ST_ST/ws"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "P3-6② 回放幽灵：ensure rc=0（原路径不退化）"
t4_assert_contains "$B2_ERR" "restart 回放幽灵" "P3-6② 明确 pane_not_found ⇒ 判回放幽灵（不注入、不判 same）"
t4_assert_contains "$B2_ERR" "明确 pane_not_found" "P3-6② 回放判据点名「明确 pane_not_found」（不是任意错误）"
t4_assert_eq "1" "$(grep -c 'pane close ' "$B2ST_ST/calls.log" || true)" \
  "P3-6② 回放幽灵：关闭该幽灵 pane 恰 1 次（不可寻址故 close 安全）"
t4_assert_contains "$B2_OUT" "已拉起 rd-fe" "P2-2b 回放幽灵：关闭后重建成功"
t4_assert_eq "1" "$(grep -c 'pane run ' "$B2ST_ST/calls.log" || true)" \
  "P2-2b 回放幽灵：只在**新** pane 上 run 一次"

# ---- P3-6（提级必修）：**只有明确 pane_not_found 才 close**；其它 process-info 错误不得关闭活 pane ----
for b2bad in internal empty; do
  b2_reset
  printf 'w1:p1|rd-fe|%s|w1\n' "$b2bad" > "$B2ST_ST/panes"
  : > "$B2ST_ST/agents"; : > "$B2ST_ST/ws"
  t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
    NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure rd-fe
  B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "0" "$T4_RC" "P3-6 $b2bad：ensure rc=0（失败计 SPAWN_FAIL，不是 crash）"
  if [ "$b2bad" = "internal" ]; then
    t4_assert_contains "$B2_ERR" "process-info 错误" "P3-6 internal_error：fail loud 点名 process-info 错误"
    t4_assert_contains "$B2_ERR" "internal_error" "P3-6 internal_error：回显错误类别（可定位）"
    t4_assert_contains "$B2_ERR" "不关闭" "P3-6 internal_error：明确「不关闭」（pane 可能仍可达）"
  else
    t4_assert_contains "$B2_ERR" "空输出" "P3-6 空输出：fail loud 点名「空输出」（错误类别可定位）"
    t4_assert_contains "$B2_ERR" "不关闭" "P3-6 空输出：明确「不关闭」"
  fi
  t4_assert_contains "$B2_ERR" "--force" "P3-6 $b2bad：给 --force 指路"
  t4_assert_not_contains "$B2_OUT" "[herdr] 已拉起" "P3-6 $b2bad：不得冒充成功"
  t4_assert_eq "0" "$(grep -c 'pane close ' "$B2ST_ST/calls.log" || true)" \
    "P3-6 $b2bad：**零 pane close**（不误关仍可达的活 pane）"
  t4_assert_eq "0" "$(grep -c 'pane run ' "$B2ST_ST/calls.log" || true)" \
    "P3-6 $b2bad：零 pane run（不注入）"
done

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
# P3-5（QA 第二轮 · 测试卫生）：子进程显式给快照路径 + EXIT trap ⇒ 不在 /tmp 留
#   `nao-fleet-term-snap.<pid>`（生产 status 正常退出会删；子进程不设就是泄漏源）。
_TERM_SNAP_PATH="${SNAP_DIR:?}/snap.$$"
trap 'rm -f "$_TERM_SNAP_PATH"' EXIT
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
# P2（QA 第二轮）：tmux 分支分派名必须真实存在（此前 `__term_tmux_argv` 双下划线 ⇒ rc=127，
#   无生产调用者所以 BR1 不红，但 B2 一接就在 set -e 下中断）。三个分派各一条，抓错名。
_term_tmux_argv() { printf 'STUB\t%s\n' "$1"; }
_term_tmux_liveness() { printf 'online\t-\t-\t-\n'; }
_term_tmux_snapshot() { printf 'x\tp\t-\t/tmp\t-\t-\t-\t-\t-\t-\t-\n'; }
chk "tmux 分派 term_argv" "STUB	p1" "$(NAO_TERMINAL=tmux term_argv p1)"
chk "tmux 分派 term_liveness" "online" "$(NAO_TERMINAL=tmux term_liveness x | cut -f1)"
chk "tmux 分派 term_snapshot" "x" "$(NAO_TERMINAL=tmux term_snapshot | cut -f1)"
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
fac_out="$(STUB_LOG="$LAB/herdr-calls.log" SNAP_DIR="$LAB/tmp" HERDR_ENV=1 HERDR_SESSION=nao-b1-unit \
  XDG_CONFIG_HOME="$LAB/cfg" HERDR_SOCKET_PATH="$LAB/cfg/herdr/sessions/nao-b1-unit/herdr.sock" NAO_TERMINAL=herdr \
  PATH="$LAB/bin:$PATH" "$BASH_BIN" "$T4_CACHE_DIR/b1-facade-test.sh" 2>&1)"; fac_rc=$?
t4_assert_eq "0" "$fac_rc" "B1④ 门面单测全绿（阶梯 + BR7 映射 + 快照缓存 + protocol 闸门）"
t4_assert_contains "$fac_out" "FACADE_OK" "B1④ 门面单测自报 OK（明细：$(printf '%s' "$fac_out" | tail -1)）"
t4_assert_eq "0" "$(ls -A "$LAB/tmp" 2>/dev/null | wc -l | tr -d ' ')" \
  "B1⑤ 门面子进程零残留（显式快照路径 + EXIT trap）"
# B2 订正（P3-5）：**按本用例 PID + mtime 过滤**判净增（不再全域计数）
b2_snap_ours() { # → 本用例窗口内新建、且 PID 属于本用例的 /tmp 快照文件
  local f p
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    p="$(basename "$f" | sed -nE 's/^nao-fleet-term-snap\.([0-9]+)\..*/\1/p')"
    [ -n "$p" ] || continue
    grep -qxF "$p" "$B2_PID_LOG" && printf '%s\n' "$f"
  done < <(find /tmp -maxdepth 1 -name 'nao-fleet-term-snap.*' -newermt "@$B2_SNAP_TS" 2>/dev/null)
  return 0
}
t4_assert_eq "" "$(b2_snap_ours)" \
  "B1⑤ 本用例自身的 /tmp 快照净增 = 0（PID+mtime 归属；并发/历史遗留不误伤）"
# 变异自证：用**本用例已记录的 PID** 造一个窗口内新文件 ⇒ 同一判据必须命中（不是空转）
B2_PROBE_PID="$(head -1 "$B2_PID_LOG" 2>/dev/null || true)"
t4_assert_ne "" "$B2_PROBE_PID" "B1⑤ 归属判据有 PID 通道（否则变异自证无法构造）"
B2_PROBE="/tmp/nao-fleet-term-snap.${B2_PROBE_PID}.b2probe"
: > "$B2_PROBE"
t4_assert_contains "$(b2_snap_ours)" "$B2_PROBE" "B1⑤ 变异自证：本用例 PID 的新快照文件必被归属判据命中（防恒绿）"
rm -f "$B2_PROBE"
t4_assert_eq "" "$(b2_snap_ours)" "B1⑤ 变异自证后还原：本用例自身净增仍为 0（无残留）"


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


# ============================================================================
# B3（#96 二期 · 用例 28 内嵌节）：herdr 回收面 close / cleanup
#   报告 = docs/reports/96b3-close-cleanup.md；本节独立可跑（`bash <本节所在文件>` 不单列，
#   但断言全部后端无关：用有状态 herdr 桩，不启真 server / 不碰用户 default）。
#   组：① BR1 tmux 逐字 golden md5 ② 忙闲闸门 BR7 ③ 名册第二信号 OR ④ 五档证据 fail-closed
#       ⑤ self 三态 ⑥ 恢复窗口 ⑦ effect 判据 ⑧ cleanup 守卫与幂等
# ============================================================================

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
BASH_BIN="$(command -v bash)"
B3_LAB="$T4_CACHE_DIR/c29-$$"
B3_ST="$B3_LAB/st"
B3_BIN="$B3_LAB/bin"
B3_CFG="$B3_LAB/cfg"
B3_SESS="nao-b3-unit"
B3_TASKS="$B3_LAB/tasks-state.md"

rm -rf "$B3_LAB"; mkdir -p "$B3_LAB" "$B3_BIN" "$B3_CFG/herdr/sessions/$B3_SESS"
cp -r "$T4_ROOT/.agents" "$B3_LAB/.agents" || t4_bad "夹具复制 .agents 失败"
printf '# c29 tasks-state 夹具（T9001 = 进行态 ⇒ tasks-state 闸门仍咬）\n\n## 进行中\n\n| 任务 | 状态 |\n| :-- | :-- |\n| T9001 | active |\n' > "$B3_TASKS"
# 名册探针桩：假 tsx 按 env 输出 roster（只读；不需要真 pi-intercom/tsx）
mkdir -p "$B3_LAB/pi-roster/npm/node_modules/tsx/dist" "$B3_LAB/pi-roster/npm/node_modules/pi-intercom"
cat > "$B3_LAB/pi-roster/npm/node_modules/tsx/dist/cli.mjs" <<'JS'
process.stdout.write(process.env.NAO_QA_FAKE_ROSTER || "[]");
JS
printf '# c29 名册探针占位（假 tsx 忽略参数，只按 env 输出）\n' > "$B3_LAB/.agents/scripts/intercom-probe.mts"

# ============================================================================
# 有状态 herdr 桩：panes = pane_id|label|fg|cwd|ws；agents = pane_id|status|seq|skip|sess
#   sessions = name|status；special fg：phantom（pane_not_found）/ internal / empty
#   开关：HERDR_STUB_SELF=1（shell_pid=$PPID ⇒ 判「调用者自身」）· HERDR_STUB_SHELL_PID=<n>
#         $ST/close_noop（close 无效）· $ST/delete_noop（delete 无效）
# ============================================================================
cat > "$B3_BIN/herdr" <<'SH'
#!/usr/bin/env bash
ST="${HERDR_STUB_STATE:?}"
printf 'herdr %s\n' "$*" >> "$ST/calls.log"
if [ "${1:-}" = "--session" ]; then shift 2; fi
cmd="${1:-}"; shift || true
pane_field() { # <pane_id> <field 1..5>
  awk -F'|' -v p="$1" -v f="$2" '$1==p{print $f; exit}' "$ST/panes" 2>/dev/null
}
panes_json() {
  local first=1 pid label fg cwd ws out=""
  while IFS='|' read -r pid label fg cwd ws; do
    [ -n "$pid" ] || continue
    if [ -n "${WSFILTER:-}" ] && [ "$ws" != "$WSFILTER" ]; then continue; fi
    [ "$first" = 1 ] || out+=","
    first=0
    out+="{\"pane_id\":\"$pid\",\"label\":\"$label\",\"cwd\":\"$cwd\",\"foreground_cwd\":\"$cwd\",\"agent_status\":\"unknown\",\"terminal_id\":\"term_$pid\",\"workspace_id\":\"${ws:-w1}\"}"
  done < "$ST/panes" 2>/dev/null
  printf '{"result":{"panes":[%s],"type":"pane_list"}}\n' "$out"
}
agents_json() {
  local first=1 pid stat seq skip sess sessj skipj out=""
  while IFS='|' read -r pid stat seq skip sess; do
    [ -n "$pid" ] || continue
    if [ "$sess" = "-" ] || [ -z "$sess" ]; then sessj="null"; else sessj="{\"agent\":\"pi\",\"kind\":\"id\",\"value\":\"$sess\"}"; fi
    if [ "$skip" = "1" ]; then skipj="true"; else skipj="false"; fi
    [ "$first" = 1 ] || out+=","
    first=0
    out+="{\"agent\":\"pi\",\"agent_session\":$sessj,\"agent_status\":\"${stat:-unknown}\",\"pane_id\":\"$pid\",\"screen_detection_skipped\":$skipj,\"state_change_seq\":${seq:-0}}"
  done < "$ST/agents" 2>/dev/null
  printf '{"result":{"agents":[%s],"type":"agent_list"}}\n' "$out"
}
sessions_json() {
  local first=1 n s out=""
  [ -f "$ST/sessions" ] || : > "$ST/sessions"
  while IFS='|' read -r n s; do
    [ -n "$n" ] || continue
    [ "$first" = 1 ] || out+=","
    first=0
    if [ "$s" = "running" ]; then runj=true; else runj=false; fi
    out+="{\"default\":$([ "$n" = default ] && echo true || echo false),\"name\":\"$n\",\"running\":$runj,\"session_dir\":\"$HERDR_STUB_CFG/herdr/sessions/$n\",\"socket_path\":\"$HERDR_STUB_CFG/herdr/sessions/$n/herdr.sock\"}"
  done < "$ST/sessions"
  printf '{"sessions":[%s]}\n' "$out"
}
case "$cmd" in
  --version) echo 'herdr 0.9.1' ;;
  api)
    case "${1:-}" in
      schema) printf 'Herdr API schema\nprotocol: 22\n' ;;
      snapshot) printf '{"sessions":[],"type":"snapshot"}\n' ;;
      *) exit 1 ;;
    esac ;;
  pane)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        WSFILTER=""
        if [ "${1:-}" = "--workspace" ]; then WSFILTER="${2:-}"; fi
        panes_json ;;
      process-info)
        pid=""
        while [ "$#" -gt 0 ]; do case "$1" in --pane) pid="${2:-}"; shift 2 ;; *) shift ;; esac; done
        fg="$(pane_field "$pid" 3)"; label="$(pane_field "$pid" 2)"
        [ -n "$pid" ] || { printf '{"error":{"code":"pane_not_found","message":"no pane"}}\n' >&2; exit 1; }
        # 第 N 次起失败（模拟：快照取到 pi，落到回收前的 process-info 探针才失败）
        cnt_file="$ST/pi-count.${pid//:/_}"
        cnt=$(( $(cat "$cnt_file" 2>/dev/null || echo 0) + 1 )); echo "$cnt" > "$cnt_file"
        if [ "${HERDR_STUB_PI_FAIL_FROM:-0}" != "0" ] && [ "$cnt" -ge "${HERDR_STUB_PI_FAIL_FROM:-0}" ]; then
          if [ "${HERDR_STUB_PI_FAIL_KIND:-internal}" = "empty" ]; then exit 0; fi
          printf '{"error":{"code":"internal_error","message":"boom"}}\n' >&2
          exit 1
        fi
        case "$fg" in
          phantom)
            printf '{"error":{"code":"pane_not_found","message":"pane %s not found (replay)"}}\n' "$pid" >&2
            exit 1 ;;
          internal)
            printf '{"error":{"code":"internal_error","message":"boom"}}\n' >&2
            exit 1 ;;
          empty) exit 0 ;;
        esac
        shell=""
        if [ -f "$ST/selfpanes" ] && grep -qxF "$pid" "$ST/selfpanes"; then
          shell="${HERDR_STUB_SELF_PID:-}"
        elif [ "${HERDR_STUB_SELF:-0}" = "1" ]; then shell="$PPID"
        elif [ -n "${HERDR_STUB_SHELL_PID:-}" ]; then shell="$HERDR_STUB_SHELL_PID"; fi
        shellj=""; [ -n "$shell" ] && shellj=",\"shell_pid\":$shell"
        if [ "$fg" = "pi" ]; then
          printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","%s"],"name":"pi","pid":1}],"pane_id":"%s"%s}}}\n' "$label" "$pid" "$shellj"
        elif [ "$fg" = "pi-badname" ]; then
          printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/pi","--name","somebody-else"],"name":"pi","pid":1}],"pane_id":"%s"%s}}}\n' "$pid" "$shellj"
        else
          printf '{"result":{"process_info":{"foreground_processes":[{"argv":["/usr/bin/%s"],"name":"%s","pid":1}],"pane_id":"%s"%s}}}\n' "${fg:-bash}" "${fg:-bash}" "$pid" "$shellj"
        fi ;;
      close)
        pid="${1:-}"
        if [ -f "$ST/close_noop" ]; then exit 0; fi   # 无 effect：rc=0 但 pane 仍在
        grep -v "^$pid|" "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes" ;;
      *) exit 1 ;;
    esac ;;
  agent)
    case "${1:-}" in
      list) agents_json ;;
      *) exit 1 ;;
    esac ;;
  session)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        sessions_json ;;
      stop)
        n="${1:-}"
        st="$(awk -F'|' -v n="$n" '$1==n{print $2}' "$ST/sessions" 2>/dev/null)"
        if [ "$st" != "running" ]; then
          printf '{"error":{"code":"session_stop_failed","message":"session %s is not running"}}\n' "$n" >&2
          exit 1
        fi
        awk -F'|' -v n="$n" 'BEGIN{OFS="|"} $1==n{$2="stopped"} {print}' "$ST/sessions" > "$ST/sessions.new"
        mv "$ST/sessions.new" "$ST/sessions"
        echo "stopped session $n" ;;
      delete)
        n="${1:-}"
        if [ -f "$ST/delete_noop" ]; then echo "deleted session $n"; exit 0; fi
        grep -v "^$n|" "$ST/sessions" > "$ST/sessions.new" 2>/dev/null || true
        [ -f "$ST/sessions.new" ] && mv "$ST/sessions.new" "$ST/sessions"
        rm -rf "$HERDR_STUB_CFG/herdr/sessions/$n" 2>/dev/null || true
        echo "deleted session $n" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
exit 0
SH
chmod +x "$B3_BIN/herdr"

t4_assert_file "$FLEET" "被测脚本存在"
t4_assert_file "$B3_BIN/herdr" "有状态 herdr 桩就绪（B3 全部断言不启真 server）"

B3_ENV=(env HERDR_ENV=1 HERDR_SESSION="$B3_SESS" HERDR_PANE_ID="w9:p9"
  XDG_CONFIG_HOME="$B3_CFG" HERDR_SOCKET_PATH="$B3_CFG/herdr/sessions/$B3_SESS/herdr.sock"
  HERDR_STUB_STATE="$B3_ST" HERDR_STUB_CFG="$B3_CFG"
  NAO_SKILLS="$B3_LAB" PI_CODING_AGENT_DIR="$B3_LAB/pi-roster"
  NAO_TASKS_STATE="$B3_TASKS" PATH="$B3_BIN:$PATH")

b3_reset() { # 清桩状态（每场景一份）
  rm -rf "$B3_ST"; mkdir -p "$B3_ST"
  : > "$B3_ST/panes"; : > "$B3_ST/agents"; : > "$B3_ST/sessions"; : > "$B3_ST/calls.log"
}
b3_panes() { printf '%s\n' "$@" > "$B3_ST/panes"; }
b3_agents() { printf '%s\n' "$@" > "$B3_ST/agents"; }
b3_run() { # <args...> → 输出落 T4_OUT/T4_ERR（ANSI 已剥）
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$FLEET" "$@"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
b3_oe() { printf '%s\n%s' "$T4_OUT_ANSI" "$T4_ERR_ANSI"; }        # 合并视图（stdout+stderr）
b3_calls() { grep -cE "$1" "$B3_ST/calls.log" 2>/dev/null || true; }
b3_close_calls() { b3_calls '^herdr .*pane close( |$)'; }

# ============================================================================
# ① BR1 静态：tmux 落地段与 B3 之前**逐字**相等（golden md5；不是「把当前脚本当基线」）
#   golden 取自 B3 之前的 main（e98ed49）：句柄层 9549f5… · cleanup 体 d89371… · socket 候选 e4950f…
# ============================================================================
GOLD_RECLAIM="9549f513b7a66fbced68bc1a1fa1dc10"
GOLD_CLEANUP="d8937134bb3ed4ceca29fb581d4acf2c"
GOLD_SOCK="e4950f3897670a97d7baaea8f54727c3"
md5_of() { md5sum | awk '{print $1}'; }
RECLAIM_MD5="$(awk '/^  # ---- 宿主句柄定位（跨仓）/{f=1} f{print} f&&/^}/{exit}' "$FLEET" | md5_of)"
CLEANUP_MD5="$(awk '/^_term_tmux_cleanup\(\) \{/{f=1;next} f{print} f&&/^}/{exit}' "$FLEET" | md5_of)"
SOCK_MD5="$(awk '/^prod_sock_candidates\(\) \{/{f=1;print;next} f{print} f&&/^}/{exit}' "$FLEET" | md5_of)"
t4_assert_ne "" "$RECLAIM_MD5" "BR1 句柄层段可提取（非空 ⇒ 下面的 md5 断言不是空转）"
t4_assert_eq "$GOLD_RECLAIM" "$RECLAIM_MD5" \
  "BR1 tmux close 句柄层（定位→self→忙闲→kill）与 B3 之前逐字相等（md5 $RECLAIM_MD5）"
t4_assert_eq "$GOLD_CLEANUP" "$CLEANUP_MD5" \
  "BR1 tmux cleanup 体（-S 守卫/默认 socket 拒绝/kill-server）与 B3 之前逐字相等（md5 $CLEANUP_MD5）"
t4_assert_eq "$GOLD_SOCK" "$SOCK_MD5" "BR1 生产默认 socket 候选表逐字相等（md5 $SOCK_MD5）"
# 变异自证：在**被钉住的段内**改一个字符 ⇒ md5 必变（判据不是恒真）
sed 's|if tmux kill-pane -t "$pane" 2>/dev/null; then|if tmux kill-pane -t "$pane"  2>/dev/null; then|' \
  "$FLEET" > "$B3_LAB/mut-fleet.sh"
t4_assert_ne "$RECLAIM_MD5" "$(awk '/^  # ---- 宿主句柄定位（跨仓）/{f=1} f{print} f&&/^}/{exit}' "$B3_LAB/mut-fleet.sh" | md5_of)" \
  "BR1 变异自证：句柄层内多一个空格 ⇒ 同一 md5 判据必红（golden 不是空转）"

# ---- 结构：移入的 tmux 函数在标记区内；cmd_close 只剩门面调用 ----
B3_TMUX_BEGIN="$(grep -n '^# >>> term-impl-tmux BEGIN (回收 / 自身判定 / 忙闲)$' "$FLEET" | cut -d: -f1)"
B3_TMUX_END="$(grep -n '^# <<< term-impl-tmux END (回收 / 自身判定 / 忙闲)$' "$FLEET" | cut -d: -f1)"
t4_assert_ne "" "$B3_TMUX_BEGIN" "B3 新增 tmux 标记区存在（回收 / 自身判定 / 忙闲）"
for fn in pane_hosts_caller self_pane_refuse pane_busy _term_tmux_reclaim _term_tmux_cleanup prod_sock_candidates; do
  ln="$(grep -n "^${fn}() {" "$FLEET" | cut -d: -f1 | head -1)"
  t4_assert_eq "1" "$([ -n "$ln" ] && [ "$ln" -gt "$B3_TMUX_BEGIN" ] && [ "$ln" -lt "$B3_TMUX_END" ] && echo 1 || echo 0)" \
    "B3 ${fn} 定义在 tmux 标记区内（$ln ∈ ($B3_TMUX_BEGIN,$B3_TMUX_END)）"
done
t4_assert_eq "1" "$(grep -cE '^  term_reclaim "\$name" "\$repo" "\$force" "\$core" "\$scope" "\$tgt"$' "$FLEET" || true)" \
  "B3 cmd_close 只调门面 term_reclaim（共用闸门层原地不动）"
t4_assert_eq "1" "$(grep -cE '^  term_cleanup "\$\{CLEANUP_SOCK:-\}" "\$\{SESSION_ARG:-\}"$' "$FLEET" || true)" \
  "B3 cmd_cleanup 只调门面 term_cleanup（后端差异在门面后）"

# ============================================================================
# ② 忙闲闸门（BR7）：working / blocked ⇒ 拒；idle ⇒ 放行；unknown ⇒ fail-closed；--force 越过且 warn
# ============================================================================
for b3st in working blocked; do
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
  b3_agents "w1:p1|$b3st|2|1|sess-a"
  b3_run close rd-fe
  t4_assert_eq "1" "$T4_RC" "B3② agent_status=$b3st ⇒ close 拒绝（rc=1）"
  t4_assert_contains "$(b3_oe)" "拒绝回收 rd-fe" "B3② $b3st：warn 点名拒绝"
  t4_assert_contains "$(b3_oe)" "agent_status=$b3st" "B3② $b3st：理由回显 agent_status（可定位）"
  t4_assert_contains "$(b3_oe)" "不可投递" "B3② $b3st：按 BR7 明说「不可投递」"
  t4_assert_contains "$(b3_oe)" "--force" "B3② $b3st：给可执行指路（--force）"
  t4_assert_eq "0" "$(b3_close_calls)" "B3② $b3st：**零 pane close**（不误杀在跑 turn）"
  t4_assert_eq "1" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "B3② $b3st：pane 仍在（未被动过）"
done

b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|3|1|sess-a"
b3_run close rd-fe
t4_assert_eq "0" "$T4_RC" "B3② agent_status=idle ⇒ close 放行（rc=0）"
t4_assert_contains "$T4_OUT_ANSI" "已回收 rd-fe（herdr pane w1:p1）@ $B3_LAB" \
  "B3② idle：成功行含 pane 与**pane 真实 cwd**（不是名册 cwd）"
t4_assert_eq "1" "$(b3_close_calls)" "B3② idle：pane close 恰 1 次（唯一回收句柄）"
t4_assert_eq "0" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "B3② idle：pane 已从现场消失（effect 达成）"
t4_assert_eq "0" "$(grep -c 'kill' "$B3_ST/calls.log" || true)" "B3② idle：无任何 kill 兜底（不做 kill -9）"

b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|unknown|2|1|sess-a"
b3_run close rd-fe
t4_assert_eq "1" "$T4_RC" "B3② agent_status=unknown ⇒ 拒（fail-closed，rc=1）"
t4_assert_contains "$(b3_oe)" "unknown" "B3② unknown：理由回显状态"
t4_assert_contains "$(b3_oe)" "--force" "B3② unknown：给 --force 指路"
t4_assert_eq "0" "$(b3_close_calls)" "B3② unknown：零 pane close（不把 unknown 当空闲）"
b3_run close --force rd-fe
t4_assert_eq "0" "$T4_RC" "B3② unknown + --force ⇒ 放行（显式越过）"
t4_assert_contains "$T4_ERR_ANSI" "越过忙闲闸门" "B3② --force 越过时**明确 warn**（不静默强杀）"
t4_assert_eq "1" "$(b3_close_calls)" "B3② --force 越过：pane close 恰 1 次"

# ---- tasks-state 闸门（共用层未动）：T9001 进行态 ⇒ 无 --force 拒 ----
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|3|1|sess-a"
b3_run close --task T9001 rd-fe
t4_assert_eq "1" "$T4_RC" "B3② tasks-state 进行态（T9001）⇒ close 拒（共用闸门层仍咬）"
t4_assert_contains "$(b3_oe)" "tasks-state 中 T9001 仍在进行态" "B3② tasks-state 闸门理由在位"
t4_assert_eq "0" "$(b3_close_calls)" "B3② tasks-state 闸门先于任何回收动作"

# ============================================================================
# ③ 第二信号（OR）：agent_status=idle 但名册 thinking ⇒ 拒（prompt 后 300–400ms 的滞后窗口）
# ============================================================================
if command -v node >/dev/null 2>&1; then
  B3_ROSTER_BUSY="[{\"name\":\"rd-fe\",\"status\":\"thinking\",\"cwd\":\"$B3_LAB\",\"tmuxPane\":\"%9\"}]"
  t4_assert_contains "$(NAO_QA_FAKE_ROSTER="$B3_ROSTER_BUSY" PI_CODING_AGENT_DIR="$B3_LAB/pi-roster" \
    node "$B3_LAB/pi-roster/npm/node_modules/tsx/dist/cli.mjs" x 2>/dev/null)" '"status":"thinking"' \
    "B3③ 名册桩可用（假 tsx 按 env 输出 roster；非空转）"
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
  b3_agents "w1:p1|idle|3|1|sess-a"
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr NAO_QA_FAKE_ROSTER="$B3_ROSTER_BUSY" \
    timeout 60 "$BASH_BIN" "$FLEET" close rd-fe
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "1" "$T4_RC" "B3③ agent_status=idle + 名册 thinking ⇒ 拒（第二信号 OR 生效）"
  t4_assert_contains "$T4_ERR_ANSI" "名册状态=thinking" "B3③ 理由点名名册状态（不是靠运气）"
  t4_assert_contains "$T4_ERR_ANSI" "第二信号" "B3③ 文案说明这是 agent_status 滞后窗口的第二信号"
  t4_assert_eq "0" "$(b3_close_calls)" "B3③ 第二信号命中 ⇒ 零 pane close"
  # 正控：名册 idle 不阻塞（OR 的另一侧）
  B3_ROSTER_IDLE="[{\"name\":\"rd-fe\",\"status\":\"idle\",\"cwd\":\"$B3_LAB\",\"tmuxPane\":\"%9\"}]"
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
  b3_agents "w1:p1|idle|3|1|sess-a"
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr NAO_QA_FAKE_ROSTER="$B3_ROSTER_IDLE" \
    timeout 60 "$BASH_BIN" "$FLEET" close rd-fe
  t4_assert_eq "0" "$T4_RC" "B3③ 正控：名册 idle ⇒ 不阻塞（idle 两侧都放行）"
  t4_assert_eq "1" "$(b3_close_calls)" "B3③ 正控：名册 idle ⇒ 放行并回收"
else
  t4_degrade "缺 node ⇒ 名册第二信号（OR）未执行（默认豁免、full 计分；BR7）"
fi

# ============================================================================
# ④ 定位/证据 fail-closed：幽灵 / 集成缺失 / 前台非 pi / 身份不一致 / 同名歧义 / 缺席
# ============================================================================
# 幽灵 pane（label 在、agent 无）⇒ 拒 + --force；--force 才回收
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
: > "$B3_ST/agents"
b3_run close rd-fe
t4_assert_eq "1" "$T4_RC" "B3④ 幽灵 pane（无 agent 条目）⇒ 拒（fail-closed）"
t4_assert_contains "$(b3_oe)" "无该 pane 条目" "B3④ 幽灵：理由点名「无 agent 条目」"
t4_assert_contains "$(b3_oe)" "--force" "B3④ 幽灵：给 --force 指路"
t4_assert_eq "0" "$(b3_close_calls)" "B3④ 幽灵：零 pane close（账面不确定 ⇒ 不杀）"
b3_run close --force rd-fe
t4_assert_eq "0" "$T4_RC" "B3④ 幽灵 + --force ⇒ 放行（显式越过）"
t4_assert_contains "$T4_ERR_ANSI" "越过忙闲闸门" "B3④ 幽灵 --force：明确 warn"

# 集成缺失（agent_session 空 / 钩子权威缺）⇒ 拒 + --force
for b3im in "w1:p1|idle|2|1|-" "w1:p1|idle|2|0|sess-a"; do
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
  b3_agents "$b3im"
  b3_run close rd-fe
  t4_assert_eq "1" "$T4_RC" "B3④ 集成缺失（$b3im）⇒ 拒（状态不可信，fail-closed）"
  t4_assert_contains "$(b3_oe)" "集成缺失" "B3④ 集成缺失：理由点名缺陷类"
  t4_assert_contains "$(b3_oe)" "--force" "B3④ 集成缺失：给 --force 指路"
  t4_assert_eq "0" "$(b3_close_calls)" "B3④ 集成缺失：零 pane close"
done

# 前台非 pi（agent 条目在）⇒ 拒 + --force
b3_reset
b3_panes "w1:p1|rd-fe|bash|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
b3_run close rd-fe
t4_assert_eq "1" "$T4_RC" "B3④ 前台非 pi ⇒ 拒（无生命周期证据，fail-closed）"
t4_assert_contains "$(b3_oe)" "前台非 pi" "B3④ 前台非 pi：理由点名"
t4_assert_contains "$(b3_oe)" "--force" "B3④ 前台非 pi：给 --force 指路"
t4_assert_eq "0" "$(b3_close_calls)" "B3④ 前台非 pi：零 pane close（不误关用户程序）"

# 身份不一致（argv --name ≠ label）⇒ **--force 也不越过**（定位不确定 ≠ 可强杀）
b3_reset
b3_panes "w1:p1|rd-fe|pi-badname|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
b3_run close rd-fe
t4_assert_eq "1" "$T4_RC" "B3④ 身份不一致 ⇒ 拒（rc=1）"
t4_assert_contains "$(b3_oe)" "身份不一致" "B3④ 身份不一致：理由点名（禁猜）"
t4_assert_eq "0" "$(b3_close_calls)" "B3④ 身份不一致：零 pane close"
b3_run close --force rd-fe
t4_assert_eq "1" "$T4_RC" "B3④ 身份不一致 + --force ⇒ 仍拒（跨会话撞号的代价不可接受）"
t4_assert_contains "$(b3_oe)" "身份不一致" "B3④ 身份不一致 + --force：仍点名同一硬拒理由"
t4_assert_eq "0" "$(b3_close_calls)" "B3④ 身份不一致 + --force：零 pane close（宁可少关一个）"

# 同名 label 多 pane ⇒ 点名 + 不猜
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1" "w1:p2|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a" "w1:p2|idle|2|1|sess-b"
b3_run close rd-fe
t4_assert_eq "1" "$T4_RC" "B3④ 同名 label 多 pane ⇒ 拒（不猜）"
t4_assert_contains "$(b3_oe)" "同名 label 命中 2 个 pane" "B3④ 歧义：warn 点名命中数"
t4_assert_contains "$(b3_oe)" "w1:p1,w1:p2" "B3④ 歧义：回显全部 pane（可定位）"
t4_assert_eq "0" "$(b3_close_calls)" "B3④ 歧义：零 pane close"
# B2 转办②（B3）：--force 逐 pane 按安全判据清理重复 label（不猜「哪个是目标」）
b3_run close --force rd-fe
t4_assert_eq "0" "$T4_RC" "B3④ 歧义 + --force ⇒ 逐 pane 清理成功（rc=0）"
t4_assert_contains "$T4_ERR_ANSI" "逐个按安全判据清理" "B3④ 歧义 + --force：明确口径（逐个按安全判据）"
t4_assert_eq "2" "$(b3_close_calls)" "B3④ 歧义 + --force：两个 pane 各关一次"
t4_assert_eq "0" "$(grep -c '^w1:p' "$B3_ST/panes" || true)" "B3④ 歧义 + --force：重复 label 已清空"
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1" "w1:p2|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a" "w1:p2|idle|2|1|sess-b"
printf 'w1:p1\n' > "$B3_ST/selfpanes"
t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr HERDR_STUB_SELF_PID="$$" \
  timeout 60 "$BASH_BIN" "$FLEET" close --force rd-fe
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "B3④ 歧义 + --force + 含调用者自身 ⇒ rc=1（部分完成不谎报全成功）"
t4_assert_contains "$T4_ERR_ANSI" "跳过 pane w1:p1：判为调用者自身" "B3④ 歧义 + --force：自身 pane 被跳过并点名"
t4_assert_eq "1" "$(b3_close_calls)" "B3④ 自身跳过：只关另一个（恰好 1 次）"
t4_assert_eq "1" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "B3④ 自身跳过：调用者 pane 仍在"
b3_reset
b3_panes "w1:p1|rd-fe|phantom|$B3_LAB|w1" "w1:p2|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a" "w1:p2|idle|2|1|sess-b"
b3_run close --force rd-fe
t4_assert_eq "1" "$T4_RC" "B3④ 歧义 + --force + 含恢复窗口 pane ⇒ rc=1（部分完成）"
t4_assert_contains "$(b3_oe)" "跳过 pane w1:p1：明确 pane_not_found" "B3④ 恢复窗口 pane 被跳过并点名"
t4_assert_eq "1" "$(b3_close_calls)" "B3④ 恢复窗口跳过：只关另一个"
t4_assert_eq "1" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "B3④ 恢复窗口 pane 仍在（未被当垃圾）"

# 缺席 ⇒ 「未运行（无需回收）」rc=0（幂等成功；不谎报失败）
b3_reset
b3_run close rd-fe
t4_assert_eq "0" "$T4_RC" "B3④ label 无命中 ⇒ 未运行（无需回收）rc=0"
t4_assert_contains "$T4_OUT_ANSI" "rd-fe 未运行（无需回收）" "B3④ 缺席：幂等成功行在位"
t4_assert_eq "0" "$(b3_close_calls)" "B3④ 缺席：零 pane close"

# 名册报在线但 label 无命中 ⇒ 非静默（rc=1，不谎报「未运行」）
if command -v node >/dev/null 2>&1; then
  B3_ROSTER_ANY="[{\"name\":\"rd-fe\",\"status\":\"idle\",\"cwd\":\"$B3_LAB\",\"tmuxPane\":\"%9\"}]"
  b3_reset
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr NAO_QA_FAKE_ROSTER="$B3_ROSTER_ANY" \
    timeout 60 "$BASH_BIN" "$FLEET" close rd-fe
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "1" "$T4_RC" "B3④ 名册报在线 + label 无命中 ⇒ 非 0（不得谎报「未运行」）"
  t4_assert_contains "$T4_ERR_ANSI" "名册报在线" "B3④ 理由点名名册与 label 的分歧"
  t4_assert_not_contains "$T4_OUT_ANSI" "未运行（无需回收）" "B3④ 分歧时不得打「未运行」成功行"
  t4_assert_eq "0" "$(b3_close_calls)" "B3④ 分歧：零 pane close"
fi

# ============================================================================
# ⑤ self 判据（F1）：自身 pane ⇒ 拒；不可判定 + (session,pane) 全等 ⇒ 保守拒
# ============================================================================
# 确定的自身：桩把 shell_pid 报成 fleet 的父进程（即 close 进程的祖先）⇒ 祖先链命中
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
# shell_pid = 本用例进程（fleet 的祖先）⇒ 祖先链必命中；这是真 PID 断言，不是桩假装
t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr HERDR_STUB_SHELL_PID="$$" \
  timeout 60 "$BASH_BIN" "$FLEET" close --force rd-fe
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "B3⑤ 自身 pane（shell_pid 祖先链命中）⇒ 拒（--force 也不越过）"
t4_assert_contains "$T4_ERR_ANSI" "调用者自身" "B3⑤ 自身：理由点名"
t4_assert_eq "0" "$(b3_close_calls)" "B3⑤ 自身：零 pane close（不得自灭）"
t4_assert_eq "1" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "B3⑤ 自身：pane 仍在"

# 不可判定（process-info 无 shell_pid）+ 目标 pane == HERDR_PANE_ID ⇒ 保守拒
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
b3_run close --force rd-fe   # 基础 env 的 HERDR_PANE_ID=w9:p9 ⇒ 不撞号
t4_assert_eq "0" "$T4_RC" "B3⑤ 不可判定 + 不撞号（w9:p9 ≠ w1:p1）⇒ 放行（不误拒）"
t4_assert_eq "1" "$(b3_close_calls)" "B3⑤ 不撞号：正常回收"
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" HERDR_PANE_ID="w1:p1" NAO_TERMINAL=herdr \
  timeout 60 "$BASH_BIN" "$FLEET" close --force rd-fe
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "B3⑤ 不可判定 + (session,pane) 全等 ⇒ 保守拒（T530 三态）"
t4_assert_contains "$T4_ERR_ANSI" "调用者自身" "B3⑤ 全等：理由点名"
t4_assert_eq "0" "$(b3_close_calls)" "B3⑤ 全等：零 pane close"

# ============================================================================
# ⑥ 恢复窗口：process-info 明确 pane_not_found ⇒ **不回收**（不可寻址 ≠ 可回收）
# ============================================================================
b3_reset
b3_panes "w1:p1|rd-fe|phantom|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
b3_run close --force rd-fe
t4_assert_eq "1" "$T4_RC" "B3⑥ stop→restart 回放/恢复窗口（pane_not_found）⇒ 拒（--force 也不越过）"
t4_assert_contains "$(b3_oe)" "pane_not_found" "B3⑥ 明确点名 pane_not_found（判据不是「任意错误」）"
t4_assert_contains "$(b3_oe)" "不得当可回收" "B3⑥ 文案钉住语义（恢复中 ≠ 可回收）"
t4_assert_eq "0" "$(b3_close_calls)" "B3⑥ 零 pane close（不把恢复中的 pane 当垃圾）"

# 其它 process-info 错误（internal / 空输出）：快照取到 pi，落到回收前的探针才失败
#   ⇒ 拒（不可判 ⇒ 宁可少关一个）；--force 显式越过且明确 warn
for b3bad in internal empty; do
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
  b3_agents "w1:p1|idle|2|1|sess-a"
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr HERDR_STUB_PI_FAIL_FROM=2 \
    HERDR_STUB_PI_FAIL_KIND="$b3bad" timeout 60 "$BASH_BIN" "$FLEET" close rd-fe
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "1" "$T4_RC" "B3⑥ process-info $b3bad ⇒ 拒（不可判 ⇒ 宁可少关一个）"
  t4_assert_contains "$T4_ERR_ANSI" "process-info 不可判" "B3⑥ $b3bad：理由点名不可判"
  t4_assert_contains "$T4_ERR_ANSI" "--force" "B3⑥ $b3bad：给 --force 指路"
  t4_assert_eq "0" "$(b3_close_calls)" "B3⑥ $b3bad：零 pane close"
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
  b3_agents "w1:p1|idle|2|1|sess-a"
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr HERDR_STUB_PI_FAIL_FROM=2 \
    HERDR_STUB_PI_FAIL_KIND="$b3bad" timeout 60 "$BASH_BIN" "$FLEET" close --force rd-fe
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "0" "$T4_RC" "B3⑥ $b3bad + --force ⇒ 越过（显式）并回收"
  t4_assert_contains "$T4_ERR_ANSI" "越过 process-info 不可判" "B3⑥ $b3bad + --force：明确 warn"
  t4_assert_eq "1" "$(b3_close_calls)" "B3⑥ $b3bad + --force：pane close 恰 1 次"
  t4_assert_eq "3" "$(cat "$B3_ST/pi-count.w1_p1" 2>/dev/null)" \
    "B3⑥ $b3bad：第 1 次（快照）取到 pi，第 2/3 次（self / 回收探针）失败 ⇒ 探针分支被真实覆盖"
done

# ============================================================================
# ⑦ effect 判据：pane close 无效 ⇒ 非 0 + 诊断 + 不重试；cleanup 连跑 2 次 effect=0
# ============================================================================
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
: > "$B3_ST/close_noop"
b3_run close rd-fe
t4_assert_eq "1" "$T4_RC" "B3⑦ pane close 无 effect（rc=0 但 pane 仍在）⇒ **非 0**（不静默成功）"
t4_assert_contains "$(b3_oe)" "复核 pane 仍在" "B3⑦ 诊断点名「effect 复核」结果"
t4_assert_contains "$(b3_oe)" "pane close rc=0" "B3⑦ 回显 pane close 的 rc（0 也不当成功）"
t4_assert_eq "1" "$(b3_close_calls)" "B3⑦ 不自动重试（防误关；恰 1 次 close 尝试）"
t4_assert_eq "1" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "B3⑦ 无 effect：pane 仍在（如实报告）"

# cleanup：运行中会话 ⇒ stop+delete ⇒ effect 达成
b3_reset
printf 'default|stopped\n%s|running\n' "$B3_SESS" > "$B3_ST/sessions"
mkdir -p "$B3_CFG/herdr/sessions/$B3_SESS"
b3_run cleanup --session "$B3_SESS"
t4_assert_eq "0" "$T4_RC" "B3⑦ cleanup（running）⇒ rc=0（effect 达成）"
t4_assert_contains "$T4_OUT_ANSI" "已终结 herdr session=$B3_SESS" "B3⑦ cleanup：成功行点名会话"
t4_assert_eq "1" "$(b3_calls "^herdr .*session stop( |$)")" "B3⑦ cleanup：session stop 恰 1 次"
t4_assert_eq "1" "$(b3_calls "^herdr .*session delete( |$)")" "B3⑦ cleanup：session delete 恰 1 次"
t4_assert_eq "0" "$(grep -c "^$B3_SESS|" "$B3_ST/sessions" || true)" "B3⑦ cleanup：会话条目已消失（effect）"
t4_assert_eq "1" "$([ ! -e "$B3_CFG/herdr/sessions/$B3_SESS" ] && echo 1 || echo 0)" "B3⑦ cleanup：会话目录已删除（effect）"
: > "$B3_ST/calls.log"
b3_run cleanup --session "$B3_SESS"
t4_assert_eq "0" "$T4_RC" "B3⑦ cleanup 第二次 ⇒ rc=0（幂等）"
t4_assert_contains "$T4_OUT_ANSI" "effect=0" "B3⑦ 第二次明确报 effect=0"
t4_assert_eq "0" "$(b3_calls '^herdr .*session (stop|delete)( |$)')" \
  "B3⑦ 第二次零 stop/delete 调用（先判 effect 再动手）"

# stop 非幂等（rc=1）不算失败：仅 delete 生效 ⇒ rc=0
b3_reset
printf 'default|stopped\n%s|stopped\n' "$B3_SESS" > "$B3_ST/sessions"
mkdir -p "$B3_CFG/herdr/sessions/$B3_SESS"
b3_run cleanup --session "$B3_SESS"
t4_assert_eq "0" "$T4_RC" "B3⑦ stop rc=1（已 stopped）不算失败：判 effect ⇒ rc=0"
t4_assert_contains "$T4_OUT_ANSI" "已终结 herdr session=$B3_SESS" "B3⑦ stop 非幂等：仍报成功（effect 达成）"
t4_assert_eq "1" "$(b3_calls "^herdr .*session stop( |$)")" "B3⑦ 确实尝试过 stop（rc 被吞但动作在）"

# delete 无 effect（会话仍可见）⇒ rc=1 + 诊断（不谎报成功）
b3_reset
printf 'default|stopped\n%s|running\n' "$B3_SESS" > "$B3_ST/sessions"
mkdir -p "$B3_CFG/herdr/sessions/$B3_SESS"
: > "$B3_ST/delete_noop"
b3_run cleanup --session "$B3_SESS"
t4_assert_eq "1" "$T4_RC" "B3⑦ delete 无 effect ⇒ rc=1（非 0 + 诊断，不谎报）"
t4_assert_contains "$T4_ERR_ANSI" "effect 未达成" "B3⑦ 失败诊断点名 effect 未达成"
t4_assert_contains "$T4_ERR_ANSI" "rc 不作判据" "B3⑦ 口径可见：判 effect 不看 rc"

# ============================================================================
# ⑧ 守卫：cleanup 拒 default / 显式目标必给 / -S 与 --session 按后端分派 / tmux 侧逐字不变
# ============================================================================
b3_reset
b3_run cleanup
t4_assert_eq "2" "$T4_RC" "B3⑧ herdr cleanup 缺 --session ⇒ rc=2（显式目标必给）"
t4_assert_contains "$T4_ERR_ANSI" "须显式 --session" "B3⑧ 缺参：可执行指路"
t4_assert_eq "0" "$(b3_calls '^herdr ')" "B3⑧ 缺参：零后端调用（守卫先于一切副作用）"
b3_run cleanup --session default
t4_assert_eq "2" "$T4_RC" "B3⑧ cleanup --session default ⇒ rc=2（BR9：绝不碰用户会话）"
t4_assert_contains "$T4_ERR_ANSI" "≠default" "B3⑧ default：理由点名"
t4_assert_eq "0" "$(b3_calls '^herdr ')" "B3⑧ default：零后端调用"
b3_run cleanup -S /tmp/b3-x.sock
t4_assert_eq "2" "$T4_RC" "B3⑧ herdr cleanup 给 -S ⇒ rc=2（-S 只属 tmux 实验场）"
t4_assert_contains "$T4_ERR_ANSI" "用 --session" "B3⑧ -S 误用：指路 --session"
t4_assert_eq "0" "$(b3_calls '^herdr ')" "B3⑧ -S 误用：零后端调用"
# HERDR_SOCKET_PATH 不在目标根 ⇒ rc=3（stale/外贸 env 必拒，防误拆）
b3_reset
printf 'default|stopped\n%s|running\n' "$B3_SESS" > "$B3_ST/sessions"
t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" HERDR_SOCKET_PATH="/tmp/wrong-root/sessions/x/y.sock" \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$FLEET" cleanup --session "$B3_SESS"
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "3" "$T4_RC" "B3⑧ 错误根的 HERDR_SOCKET_PATH ⇒ rc=3（stale/外贸 env 必拒）"
t4_assert_contains "$T4_ERR_ANSI" "不在目标根" "B3⑧ rc=3：拒绝理由点名目标根"
t4_assert_eq "0" "$(b3_calls "^herdr .*session (stop|delete)( |$)")" "B3⑧ rc=3：零拆场动作"
# tmux 侧守卫逐字不变：cleanup 无 -S ⇒ rc=2；--session 误用 ⇒ rc=2
t4_run_in_dir "$B3_LAB" env -u NAO_TERMINAL -u HERDR_ENV -u HERDR_SESSION PATH="$B3_BIN:$PATH" \
  timeout 60 "$BASH_BIN" "$FLEET" cleanup
t4_assert_eq "2" "$T4_RC" "B3⑧ tmux cleanup 缺 -S ⇒ rc=2（既有守卫零回归）"
t4_run_in_dir "$B3_LAB" env -u NAO_TERMINAL -u HERDR_ENV -u HERDR_SESSION PATH="$B3_BIN:$PATH" \
  timeout 60 "$BASH_BIN" "$FLEET" cleanup --session nao-x
t4_assert_eq "2" "$T4_RC" "B3⑧ tmux cleanup 误用 --session ⇒ rc=2（按后端分派，不静默吞参）"


t4_exit
