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
# C2 golden / 新期望表（status 仍与 fixture 逐字；ensure 按 T547 改为「恒带 @<fleet>」期望表）：
#   夹具 `tests/t4/fixtures/nao-fleet-baseline-2692b42.sh`（= git show 2692b42:… + 头注释）
#   比**两样**（同套隔离夹具：`env -u TMUX -u TMUX_PANE` + 私有 `TMUX_TMPDIR` + 桩 pi）：
#     ① `status` 全文 md5（名册离线 ⇒ 只走标题/卡集路径，确定性）
#     ② `ensure` 的 `[tmux] 已拉起 …` 行 + pi 桩 argv 里 `--name` 值 → T547 后为**新期望表**
#        （9 个目标名恒带 `@<仓 slug>`）；负控 = 默认 tier 改回空 ⇒ 丢 `@` ⇒ 必红。
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
#   ④ herdr 放置键不得取会话名（T545 · ADR 2026-11-13-herdr-workspace-scope-key）：抽
#      `_term_herdr_spawn` 函数体（`awk '/^_term_herdr_spawn\(\)/,/^}/'`）后 `grep -c HERDR_SESSION` == 0；
#      **白名单为空**（`--session` 注入只在 `_term_herdr_exec`，不在这个函数里）⇒ 连 warn 文案也算命中。
#      基线（T545 前）= 2 处（键回退 1 + 「无法确定 workspace label」文案 1）。本 lint **不进 `check`**（check 计数不漂）。
#   ⑤ 起 server 身份禁读 `_TERM_HERDR_SERVER_START`（T544 · Issue #116）：读取形（花括号 / 裸变量）
#      与命令位前置赋值形均 == 0，白名单为空；合法唯一形态 = 迁移带 `-u _TERM_HERDR_SERVER_START`。
#      它与「删测试侧兜底」互补：后者防**已发生的泄漏**（无泄漏环境下不红），本闸防**读取点被加回来**。
#   负控：close 里手写 `name="${NAME}-${task}"` ⇒ ②红；删一条 parse 调用 ⇒ ③红；spawn 内注入 `HERDR_SESSION` ⇒ ④红；
#      注入历史读取形 / 裸读取形 / 命令位赋值形 ⇒ ⑤红（三种形各一条）。
#
# 退出码沿用 lib.sh 约定；夹具根不得落在任何 git 仓内，收尾走机制 `cleanup -S`。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SUBJECT="${T4_28_SUBJECT:-$T4_ROOT/.agents/scripts/nao-fleet.sh}"
# T567-A：实现分布 fleet/lib ⇒ 只读断言（抽取/计数/变异源）一律走**文件集合并视图**
SUBJECT_BUNDLE="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"
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
  chk() { if [ "$2" = "$3" ]; then OKN=$((OKN + 1)); else BADN=$((BADN + 1)); printf '  ✗ %s\n    want=[%s]\n    got =[%s]\n' "$1" "$2" "$3"; fi; }
  declare -A FLEET_ROLE_KIND
  for r in pm arch-designer uiux-designer rd-fe rd-be qa rd-infra; do FLEET_ROLE_KIND[$r]=resident; done
  FLEET_ROLE_KIND[sec-review]=card
  source "$CONTRACT"
  b() { fleet_name_build "$@" 2>/dev/null; }
  p() { fleet_name_parse "$@"; }

  # ---- ① 字面量恒等 + ② 往返：kind|role|num|task|name|parse ----
  while IFS='|' read -r kind role num task name exp; do
    [ -n "$kind" ] || continue
    chk "① build($kind,$role,${num:-},${task:-}) == $name" "$name" "$(b "$kind" "$role" "$num" "$task")"
    chk "① parse($name) == $exp" "$exp" "$(p "$name")"
    chk "② 往返 parse(build(...)) == $exp" "$exp" "$(p "$(b "$kind" "$role" "$num" "$task")")"
  done <<'TBL'
resident|pm|||pm|OK resident,pm,,
resident|pm|2||pm2|OK resident,pm,,2
derived|rd-be||T1|rd-be(T1)|OK derived,rd-be,T1,
derived|rd-be|2|T553|rd-be2(T553)|OK derived,rd-be,T553,2
derived|arch-designer||96b|arch-designer(96b)|OK derived,arch-designer,96b,
derived|pm||M20261109-queue-slim|pm(M20261109-queue-slim)|OK derived,pm,M20261109-queue-slim,
derived|rd-infra||M20261014-pi-ext-update|rd-infra(M20261014-pi-ext-update)|OK derived,rd-infra,M20261014-pi-ext-update,
card|sec-review|||sec-review|OK card,sec-review,,
card|sec-review||notes|sec-review(notes)|OK card,sec-review,notes,
card|sec-review||T42|sec-review(T42)|OK card,sec-review,T42,
card|sec-review|2|T42|sec-review2(T42)|OK card,sec-review,T42,2
TBL
  # 旧形只读（parse 前缀区分；第 4 段 = scope）
  for pair in 'rd-be-T1|LEGACY OK derived,rd-be,T1,' 'qa-2|LEGACY OK derived,qa,2,' \
              'pm@todo|LEGACY OK resident,pm,,todo' 'rd-be-T1@todo|LEGACY OK derived,rd-be,T1,todo'; do
    chk "① 旧形只读 parse(${pair%%|*})" "${pair#*|}" "$(p "${pair%%|*}")"
  done
  for a in arch uiux ui-designer infra; do
    chk "① 别名 $a 不得被 parse 当成角色 id" "ERR" "$(p "$a")"
  done

  # ---- ③ 语法钉住（v2）----
  chk "③ build(card,sec-review) == sec-review" "sec-review" "$(b card sec-review)"
  chk "③ build 第三参非空非法（旧 scope 形态）⇒ rc≠0" "1" "$(b card sec-review todo >/dev/null 2>&1; echo $?)"
  chk "③ build(card,sec-review,2,T42) == sec-review2(T42)" "sec-review2(T42)" "$(b card sec-review 2 T42)"
  chk "③ parse(sec-review@todo) 仍 ERR（v2 不再产生 scope）" "ERR" "$(p sec-review@todo)"
  chk "③ parse(sec-review2(T42))" "OK card,sec-review,T42,2" "$(p "sec-review2(T42)")"
  chk "③ parse(rd-be-T1@todo) = LEGACY" "LEGACY OK derived,rd-be,T1,todo" "$(p rd-be-T1@todo)"

  # ---- ④ parse 全函数（非法一律 ERR，禁猜）----
  L17="$(printf 'a%.0s' $(seq 1 17))"
  L49="rd-be-$(printf 'T%.0s' $(seq 1 44))"
  for bad in "" "rd-fe@" "@todo" "rd-fe@@todo" "rd-fe@@@todo" "rd-fe@TODO" "rd-fe@a.b" "rd-fe@:x" \
             "rd-fe@$L17" "subagent-x@y" "nao-x@y" "$L49" "rd_fe" "rd-fe@todo!" "rd-fe@-x" "rd-fe@x-" \
             "rd-fe " " rd-fe" "RD-FE" "unknown-role" "sec-review-$(printf 'x%.0s' $(seq 1 30))" \
             "pm1" "pm0" "pm10" "pm2x" "arch-designer(T554" "arch-designerT554)" \
             "arch-designer((T554))" "arch-designer(T5)4" "rd-be(T553)2"; do
    chk "④ 非法/越界输入必须 ERR：[${bad}]" "ERR" "$(p "$bad")"
  done
  chk "④ 非法 num 下 build 必须拒绝" "1" "$(b resident rd-be 1 >/dev/null 2>&1; echo $?)"
  chk "④ 缺 task 的派生形态（build 第三参为 task 位）不得被当 num" "1" "$(b derived rd-be T553 >/dev/null 2>&1; echo $?)"
  chk "④ 未知 kind 下 build 必须拒绝" "1" "$(b bogus rd-be '' >/dev/null 2>&1; echo $?)"

  # ---- ⑤ 弃用 warn 单源（恰一行；不校验、不 fail）----
  ow="$(_fleet_deprecated_warn --fleet 2>&1)"
  chk "⑤ 弃用 warn 恰一行" "1" "$(printf '%s\n' "$ow" | grep -c .)"
  chk "⑤ 弃用 warn 点名 --fleet" "1" "$(printf '%s\n' "$ow" | grep -c '弃用：--fleet')"

  # ---- ⑤b 放置键（place_key_label）：归一 / 截断 / worktree 同键 ----
  mkdir -p "$W/My_Repo.V2"
  chk "⑤b 归一大写/_/. → -" "my-repo-v2" "$(place_key_label "$W/My_Repo.V2")"
  LONGDIR="$W/$(printf 'a%.0s' $(seq 1 30))"; mkdir -p "$LONGDIR"
  chk "⑤b 截断 16 且不以 - 结尾" "aaaaaaaaaaaaaaaa" "$(place_key_label "$LONGDIR")"
  if command -v git >/dev/null 2>&1; then
    G="$W/gitrepo"; mkdir -p "$G"
    ( cd "$G" && git init -q . && git config user.email t@t.invalid && git config user.name t \
        && : > f && git add -A && git commit -qm init ) >/dev/null 2>&1
    chk "⑤b 普通仓 = 仓目录名" "gitrepo" "$(place_key_label "$G")"
    ( cd "$G" && git worktree add -q "$W/wt" -b wtb ) >/dev/null 2>&1
    chk "⑤b worktree 与主仓同键（git --git-common-dir）" "gitrepo" "$(place_key_label "$W/wt")"
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
extract_contract "$SUBJECT_BUNDLE" > "$C1_BASE"
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
  'printf '"'"'%s%s\n'"'"' "$role" "$num"' 'printf '"'"'%s%s-x\n'"'"' "$role" "$num"'
mutation_neg "M2 parse 丢 task" \
  'if [[ "$pre" == "$role" ]]; then task=""; else task="${pre:${#role}+1}"; fi' \
  'if [[ -n "$role" ]]; then task=""; fi'
mutation_neg "M3 parse 改 \${x%-*} 尾切片" \
  'else task="${pre:${#role}+1}"; fi' \
  'else task="${pre%-*}"; fi'
mutation_neg "M4 parse 对非法 scope 返猜测值" \
  'fleet_scope_problem "$scope" >/dev/null || { printf '"'"'ERR\n'"'"'; return 0; }' ':'
mutation_neg "M5 未知角色放行（兜底成 pm）" \
  '[[ -n "$best" ]] || { printf '"'"'ERR\n'"'"'; return 0; }' \
  '[[ -n "$best" ]] || best="pm"' 

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

t4_assert_eq "1" "$(lint1 "$SUBJECT_BUNDLE")" "C3① 全脚本恰 1 处 \`exec pi --name\`（唯一 exec 点）"
t4_assert_eq "0" "$(lint2 "$SUBJECT_BUNDLE")" \
  "C3② 契约块外 0 处手写名字/core 拼接（(name|disp|core)=\${…}-\${task} 形态）"
N3="$(lint3 "$SUBJECT_BUNDLE")"; N3C="$(lint3c "$SUBJECT_BUNDLE")"
t4_assert_ge "11" "$N3" "C3③ \`grep -c fleet_name_parse\` ≥ 11（11 解析点全接线的可见面；实际 $N3）"
t4_info "C3③ 代码调用点数（fleet_name_parse \"…\"）= $N3C"
t4_assert_ge "6" "$N3C" "C3③ 代码调用点数 ≥ 6（status/close/derived/running_verdict 等实点；实际 $N3C）"

# ---- C3 负控 A：close 里手写 name 拼接 ⇒ ②必须红 ----
NEG_A="$T4_CACHE_DIR/c3-neg-a.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_A" \
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
if mutate_file "$SUBJECT_BUNDLE" "$NEG_A2" \
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
if mutate_file "$SUBJECT_BUNDLE" "$NEG_MX" \
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
  t4_assert_eq "0" "$(lint2 "$SUBJECT_BUNDLE")" "C3② 形态矩阵对照：真脚本仍 0（不误报合法构造）"
else
  t4_bad "C3② 形态矩阵锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3② 正控：唯一构造点自身 / 合法赋值不得被误判 ----
t4_assert_eq "0" \
  "$(awk '/^fleet_core_build\(\)/{f=1} f{print} f&&/^}/{exit}' "$SUBJECT_BUNDLE" | lint2 /dev/stdin)" \
  "C3② 正控 fleet_core_build 自身 0 命中（判据只认拼接形态，不误判 printf 里的合法拼法）"
# ---- C3 负控 B：删一条 parse 调用 ⇒ ③代码调用点数必须掉 ----
NEG_B="$T4_CACHE_DIR/c3-neg-b.sh"
if MUT_RE='^[[:space:]]*out="\$\(fleet_name_parse "\$n"\)"[[:space:]]*$' \
   awk '/^# >>> fleet-name-contract BEGIN/{f=1} /^# <<< fleet-name-contract END/{f=0}
        !f && $0 ~ ENVIRON["MUT_RE"] && !d { d=1; next } { print } END { exit (d?0:1) }' \
     "$SUBJECT_BUNDLE" > "$NEG_B"; then
  t4_assert_eq "$(($N3C - 1))" "$(lint3c "$NEG_B")" "C3 负控B 删一条 parse 调用 ⇒ ③代码调用点数 -1（负控有效）"
  t4_assert_ne "$N3C" "$(lint3c "$NEG_B")" "C3 负控B 删调用后 ③ 可见面变化（不是恒量）"
else
  t4_bad "C3 负控B 变异锚点未命中（用例锚点须跟随实现）"
fi

# ============================================================================
# C3④ herdr 放置键 lint（T545 · ADR 2026-11-13-herdr-workspace-scope-key）
#   判据（D1 收紧）：`_term_herdr_spawn` 函数体内 `HERDR_SESSION` 命中数 == 0 **且**
#   `fleet_scope_slug` 命中数 == 0 —— 放置键只认入参 label（= fleet），不得回退会话名、也不得在
#   spawn 内重算 slug（第二数据源消失）。否则空/默认 fleet 的仓会被塞进会话名或错 workspace。
#   为何白名单为空：本函数的合法 `--session` 用法不存在（`_term_herdr_exec` 才注入），故任何命中都是缺陷。
# ============================================================================
spawn_body() { awk '/^_term_herdr_spawn\(\)/,/^}/' "$1"; }
lint4() { spawn_body "$1" | grep -c 'HERDR_SESSION' || true; }
lint4b() { spawn_body "$1" | grep -c 'place_key_label' || true; }
T545_MSG='herdr 放置键只认入参 label=fleet：禁取会话名、禁在 spawn 内重算 slug（ADR 2026-11-17-fleet-identity-source D1）'
t4_assert_eq "0" "$(lint4 "$SUBJECT_BUNDLE")" "C3④ ${T545_MSG}（_term_herdr_spawn 内 HERDR_SESSION 命中 = 0）"
t4_assert_eq "0" "$(lint4b "$SUBJECT_BUNDLE")" "C3④ ${T545_MSG}（_term_herdr_spawn 内 place_key_label 命中 = 0）"
# ---- C3④ 负控：往 spawn 里注入一行 HERDR_SESSION ⇒ 必红 - 并且计数变 1（lint 不是恒 0）----
NEG_D="$T4_CACHE_DIR/c3-neg-d.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_D" \
    '  if ! fleet_scope_problem "$label" >/dev/null; then' \
    '  : "${HERDR_SESSION:-}"   # C3④ 负控注入
  if ! fleet_scope_problem "$label" >/dev/null; then'; then
  t4_assert_eq "1" "$(lint4 "$NEG_D")" "C3④ 负控：spawn 内注入 HERDR_SESSION ⇒ 命中 1 且点名【${T545_MSG}】"
else
  t4_bad "C3④ 负控变异锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3④ 负控 2：spawn 内重新调用 fleet_scope_slug ⇒ 必红（第二数据源不得回来）----
NEG_D2="$T4_CACHE_DIR/c3-neg-d2.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_D2" \
    'local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" pl="" obj js line' \
    'local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="$(place_key_label "$repo")" group="${6-}" pl="" obj js line'; then
  t4_assert_eq "1" "$(lint4b "$NEG_D2")" "C3④ 负控 2：spawn 内重算 slug ⇒ 命中 1（D1 零调用判据不空转）"
else
  t4_bad "C3④ 负控 2 变异锚点未命中（用例锚点须跟随实现）"
fi

# ============================================================================
# C3⑤ 起 server 身份禁读环境变量（T544 · Issue #116）
#   病根：旧实现用 `_TERM_HERDR_SERVER_START=1 _term_herdr_exec server` 传「我是起 server 者」——
#     bash 把「函数调用的前置变量赋值」连环境交给子进程 ⇒ herdr server 继承 ⇒ 它 spawn 的每个 pane
#     全继承 ⇒ pane 内每次 fleet 调用都误走 server-start 分支（多套 `env -u`+setsid，并清掉子进程
#     `HERDR_*` 含 `HERDR_SOCKET_PATH` ⇒ 跨 root/符号链接配置时可串台）。
#   现行形：身份由**显式首参数** `_term_herdr_exec --server-start` 传（不进 env）。本闸抓「把读取形/命令位
#     赋值形加回来」——它防的是**回归**（无泄漏环境下套件不会红，故与「删测试侧兜底」互补）。
#   判据（白名单为空，两类历史形态都纳管）：
#     ① 读取形（花括号 / 无花括号）：`\$\{?_TERM_HERDR_SERVER_START` —— 含历史分支判断
#        `[[ "${_TERM_HERDR_SERVER_START:-0}" == "1" ]]` 与裸 `$_TERM_HERDR_SERVER_START`；
#     ② 命令行位前置赋值形：`^<空白>[(]<空白>?_TERM_HERDR_SERVER_START=`（旧泄漏写法；单靠它不生效，
#        但会配一个读点 ⇒ 两者同报）。
#   合法唯一形态：`-u _TERM_HERDR_SERVER_START`（迁移带：不带 `$`、非行首赋值）⇒ 不命中。
#   已知边界：行级静态不剥引号/heredoc；命中即输出 `行号:内容`（便于点名）。
# ============================================================================
lint5() { # <script> → 违规行 "行号:内容"（空 = 合规）
  grep -nE '\$\{?_TERM_HERDR_SERVER_START|^[[:space:]]*(\([[:space:]]*)?_TERM_HERDR_SERVER_START=' "$1" || true
}
T544_MSG='起 server 的身份请用 `_term_herdr_exec --server-start`，禁读 _TERM_HERDR_SERVER_START 环境变量（ADR/T544 · Issue #116）'
# 历史读取形的**原文**（单引号书写 ⇒ 不展开、不当命令替换）：消息里要用它点名，不能直接写进双引号
T544_READ_FORM='[[ "${_TERM_HERDR_SERVER_START:-0}" == "1" ]]'
t4_assert_eq "" "$(lint5 "$SUBJECT_BUNDLE")" "C3⑤ ${T544_MSG}（真脚本 0 命中）"
# ---- C3⑤ 负控 1：历史读取形（花括号 + `:-0` 比较）⇒ 必红并点名行号 ----
NEG_E="$T4_CACHE_DIR/c3-neg-e.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_E" \
    '  local s="${HERDR_SESSION:-}" v ss=0' \
    '  local s="${HERDR_SESSION:-}" v ss=0
  if [[ "${_TERM_HERDR_SERVER_START:-0}" == "1" ]]; then :; fi'; then
  e_out="$(lint5 "$NEG_E")"
  t4_assert_match "$e_out" '^[0-9]+:.*_TERM_HERDR_SERVER_START' \
    "C3⑤ 负控 1 历史读取形「${T544_READ_FORM}」注入副本 ⇒ 红并点名【${T544_MSG}】"
else
  t4_bad "C3⑤ 负控 1 变异锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3⑤ 负控 2：裸变量读取形（无花括号）⇒ 同样必红（不只认一个写法）----
NEG_F="$T4_CACHE_DIR/c3-neg-f.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_F" \
    '  local s="${HERDR_SESSION:-}" v ss=0' \
    '  local s="${HERDR_SESSION:-}" v ss=0
  : "$_TERM_HERDR_SERVER_START"'; then
  t4_assert_match "$(lint5 "$NEG_F")" '^[0-9]+:.*_TERM_HERDR_SERVER_START' \
    "C3⑤ 负控 2 裸读取形「\$_TERM_HERDR_SERVER_START」（无花括号）⇒ 同样红（判据不只认一种拼法）"
else
  t4_bad "C3⑤ 负控 2 变异锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3⑤ 负控 3：命令行位前置赋值形（旧泄漏写法）⇒ 必红 ----
NEG_G="$T4_CACHE_DIR/c3-neg-g.sh"
if mutate_file "$SUBJECT_BUNDLE" "$NEG_G" \
    '  local s="${HERDR_SESSION:-}" v ss=0' \
    '  local s="${HERDR_SESSION:-}" v ss=0
  _TERM_HERDR_SERVER_START=1 :'; then
  t4_assert_match "$(lint5 "$NEG_G")" '^[0-9]+:.*_TERM_HERDR_SERVER_START=1' \
    "C3⑤ 负控 3 命令位前置赋值形（旧泄漏写法）⇒ 同样红"
else
  t4_bad "C3⑤ 负控 3 变异锚点未命中（用例锚点须跟随实现）"
fi
# ---- C3⑤ 正控（不误伤）：迁移带 `-u _TERM_HERDR_SERVER_START` 必须仍在场且被本闸放行 ----
#   为何要正控：否则「删干净」（连 `-u` 一起删）也能让 C3⑤ 绿 —— 而 `-u` 是迁移期承重件。
t4_assert_eq "1" "$(grep -c -- '-u _TERM_HERDR_SERVER_START' "$SUBJECT_BUNDLE" || true)" \
  "C3⑤ 正控：迁移带「-u _TERM_HERDR_SERVER_START」仍在场（与本闸零命中并存 ⇒ 不是靠删干净凑绿）"

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

# 历史常量（只作「herdr 渲染 ≠ 旧 tmux 渲染」的对照；不参与任何 tmux 执行）：
#   tmux 时代 status 全文 md5（自 2692b42 基线起未变；T555 后该后端已不存在，值冻结留档）
GOLD_TMUX_MD5="144f3447c9ff406d6aed828d9c9720e5"

# ============================================================================
# T555（纯 herdr 化）· C2 golden diff 组退役说明
#   机制：本组原用**两个隔离 tmux server**（各 6 个标题契约 pane）跑「基线 fixture（tmux 时代整脚本）
#   vs 新版」的 status 全文 md5 对照。tmux 后端已整组删除（ADR 2026-11-22-herdr-only）：
#     · 基线 fixture 只认 tmux 后端（`NAO_TERMINAL=tmux` 在本版是 rc=2 用法守卫）⇒ 无对照对象；
#     · 标题契约 pane 的构造面（`pane_title` / 会话名）也已不存在。
#   ⇒ 该组**整体退役**（断言退役逐条归因见 docs/reports/555-impl-rd-infra.md）。
#   零回归的等价覆盖：herdr golden 由本用例下方 herdr 夹具动态生成（`GOLD_HERDR_MD5`），
#     并断言「未设 == 显式 =herdr」+「未设 ≠ 旧 tmux golden」+ 变异自证（默认改回 tmux ⇒ 必红）。
# ============================================================================
LAB="$T4_CACHE_DIR/lab28-$$"
mkdir -p "$LAB/bin" "$LAB/pi-empty"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
t4_ok "C2 夹具（herdr 场）：LAB 建立 + .agents 复制完成（tmux 双场/标题 pane 构造面已随 T555 退役）"

# 下游卡夹具 ×2 —— **名字必须与下面的 status/ensure 目标集不相交**
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

# P3-5（B2 订正）：按本用例 PID + mtime 归属判「/tmp 净增」（全域计数在并发下会假红/假绿）。
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
# T555：tmux 后端已删 ⇒ 桩只记录（不转发）。维持「herdr 场零 tmux 调用」这条反向断言。
printf 'tmux %s\n' "\$*" >> "$LAB/tmux-calls.log"
exit 1
SH
cat > "$LAB/bin/node" <<SH
#!/usr/bin/env bash
printf 'node %s\n' "\$*" >> "$LAB/node-calls.log"
exit 1
SH
chmod +x "$LAB/bin/herdr" "$LAB/bin/tmux" "$LAB/bin/node"

# ---- ① 旧后端变量 ⇒ 用法守卫（T555 / D2）：golden 对照与 tmux 调用计数两组随后端退役 ----
#   退役（逐条归因见报告）：`=tmux status rc=0` / `=tmux == 旧 golden` / `=tmux == C2 golden` /
#   `tmux 模式 herdr 桩 0 命中` / `B1③ 五个子命令 + 总数零漂移` —— 对象（tmux 分支）已删。
#   取而代之：旧值 fail loud（rc=2 + 单行 + 零后端调用），且 herdr 侧反而**必须**有 herdr 调用。
: > "$LAB/herdr-calls.log"; : > "$LAB/tmux-calls.log"
t4_run_in_dir "$LAB" env "${T4_HERDR_UNSET_ARGS[@]}" -u TMUX -u TMUX_PANE NAO_TERMINAL=tmux NAO_SKILLS="$LAB" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" status
t4_assert_eq "2" "$T4_RC" "B1① 旧后端变量 status ⇒ rc=2（D2 用法守卫；原「=tmux golden」组退役）"
t4_assert_eq "0" "$(grep -c '^herdr ' "$LAB/herdr-calls.log" || true)" \
  "B1② 守卫先于一切后端调用（herdr 桩 0 命中）"

# ---- ② herdr 模式 status（端到端）：双向桩负控 + 四档非在线证据单列 ----
# P2-1：socket 必须落在目标根（XDG_CONFIG_HOME/herdr/sessions/<名>/）下 —— 夹具与之一致
HENV=(env HERDR_ENV=1 HERDR_SESSION=nao-b1-status XDG_CONFIG_HOME="$LAB/cfg" \
  HERDR_SOCKET_PATH="$LAB/cfg/herdr/sessions/nao-b1-status/herdr.sock")
mkdir -p "$LAB/tmp"   # 私有 TMPDIR：快照临时文件必须落这里且跑完为空（P3-5 残留断言）
: > "$LAB/tmux-calls.log"; : > "$LAB/node-calls.log"; : > "$LAB/herdr-calls.log"
t4_run_in_dir "$LAB" "${HENV[@]}" NAO_TERMINAL=herdr NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$LAB/.agents/scripts/nao-fleet.sh" status
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
# B1①（#96 三期 P2 · BR1 三期改写）：**默认值反向断言**
#   未设 NAO_TERMINAL ⇒ **herdr**（新 golden，由夹具生成）· 显式 =tmux ⇒ 旧 golden · 两者必不同。
#   golden 生成（未设 / 显式 =herdr 两次 invocation 必须逐字同源；herdr 侧 status 有后端专有头行）：
#     env -u NAO_TERMINAL ${HENV[@]} … status | md5sum   ⇒ herdr golden
#     env NAO_TERMINAL=herdr ${HENV[@]} … status | md5sum ⇒ 必须逐字相同（默认值唯一）
#   反向负控：tmux 夹具场里未设 ⇒ exit 3（**不回落** tmux）；变异「默认改回 tmux」⇒ herdr 场未设必红。
# ============================================================================
GOLD_HERDR_MD5="$(printf '%s' "$OUT_H" | md5sum | awk '{print $1}')"
# 已记录的 herdr golden（**由夹具生成，禁手抄**）：生成命令 = 上面这次 herdr 夹具 status 的 md5
#   （`env NAO_TERMINAL=herdr ${HENV[@]} … status`；与「未设」两跑同源）。两次独立跑次实测同值
#   （lab 路径含 $$ 但 herdr status 不回显路径 ⇒ 跨跑/跨机稳定）。
#   **有意改 herdr 渲染（文案/节标题/列）时须同步更新本行** —— 与 C2 tmux golden 同一纪律（BR1）。
# T561（#166）：status 分节标题示例改 v2（`rd-be(T1) / rd-be2(T1)`、`rd-fe(T1) / rd-infra(T1)`）
#   ⇒ 有意改渲染，按上文纪律同步本行。证据：同一夹具下「仅打这两行标题」的旧树命中本值（其余断言零变化）。
GOLD_HERDR_MD5_RECORDED="8b50475296f4bd5880fe37b9f454f73a"
t4_assert_eq "$GOLD_HERDR_MD5_RECORDED" "$GOLD_HERDR_MD5" \
  "P2① herdr golden == 记录的 golden（herdr 渲染零漂移；$GOLD_HERDR_MD5_RECORDED）"
t4_assert_contains "$OUT_H" "herdr 后端：label 命中 ≠ 在线" \
  "P2① herdr golden 确为 herdr 渲染（后端专有头行在位 ⇒ 不是 tmux 文本）"
t4_assert_ne "$GOLD_TMUX_MD5" "$GOLD_HERDR_MD5" \
  "P2① 反向断言：herdr golden ≠ 旧 tmux golden（$GOLD_HERDR_MD5 ≠ $GOLD_TMUX_MD5）"
: > "$LAB/herdr-calls.log"
t4_run_in_dir "$LAB" "${HENV[@]}" NAO_TERMINAL=herdr NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$LAB/.agents/scripts/nao-fleet.sh" status
RC_HX=$T4_RC; MD5_HX="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g' | md5sum | awk '{print $1}')"
t4_assert_eq "0" "$RC_HX" "P2① 显式 =herdr ⇒ status rc=0（golden 生成侧的对照）"
t4_assert_eq "$GOLD_HERDR_MD5" "$MD5_HX" "P2① 显式 =herdr == herdr golden（同一夹具两次同源）"

# >>> default-value-probe BEGIN（#96 P2：未设探针 —— 全仓唯一允许 unset 的位置）
: > "$LAB/herdr-calls.log"
t4_run_in_dir "$LAB" env -u NAO_TERMINAL "${HENV[@]:1}" NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$LAB/.agents/scripts/nao-fleet.sh" status
RC_UNSET=$T4_RC; OUT_UNSET="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
MD5_UNSET="$(printf '%s' "$OUT_UNSET" | md5sum | awk '{print $1}')"
t4_assert_eq "0" "$RC_UNSET" "P2① 未设 NAO_TERMINAL（herdr 场）⇒ status rc=0（默认已翻 herdr）"
t4_assert_eq "$GOLD_HERDR_MD5" "$MD5_UNSET" "P2① 未设 == herdr golden（默认值唯一：未设与显式 =herdr 不可分叉）"
t4_assert_ne "$GOLD_TMUX_MD5" "$MD5_UNSET" "P2① 未设 ≠ 旧 tmux golden（旧口径已按设计失效，不假绿）"
t4_info "P2① 双 golden：tmux=$GOLD_TMUX_MD5 · herdr=$GOLD_HERDR_MD5 · 未设=$MD5_UNSET"

# 反向负控 A：**清掉 herdr 前提**（NAO_TERMINAL 未设 + HERDR_* 全清）⇒ exit 3（fail loud，不静默回落）
#   T555：原写法是「造 tmux 夹具场、验未设不回落 tmux」—— tmux 后端已删，回落目标不存在 ⇒
#   同一意图改钉「未设 = herdr，但 herdr 前提缺失 ⇒ exit 3（点名 HERDR_ENV）」。
: > "$LAB/tmux-calls.log"
t4_run_in_dir "$LAB" env -u TMUX -u TMUX_PANE "${T4_HERDR_UNSET_ARGS[@]}" -u NAO_TERMINAL \
  NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty" \
  NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$LAB/.agents/scripts/nao-fleet.sh" status
RC_NOFALL=$T4_RC
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "3" "$RC_NOFALL" "P2① 反向负控A：未设 NAO_TERMINAL 且 herdr 前提全缺 ⇒ exit 3（不静默成功）"
t4_assert_contains "$T4_ERR_ANSI" "HERDR_ENV=1 缺失" "P2① 反向负控A：点名 herdr 前提（HERDR_ENV）"
t4_assert_match "$T4_ERR_ANSI" '重试|pin 回' "P2① 反向负控A：exit 3 文案给后续动作"

# 变异自证：把默认改回 tmux ⇒ 上面的「未设 == herdr golden」必红（判据非空转）
#   （本段仍在默认值探针块内：它跑的就是「未设」状态，只是换了一份变异脚本）
MUT_DEF_ROOT="$T4_CACHE_DIR/p2-mut-default-$$"
MUT_DEF="$(t4_fleet_clone "$LAB/.agents/scripts" "$MUT_DEF_ROOT")"
MUT_DEF_MOD="$(t4_fleet_file_for "$MUT_DEF_ROOT" term_backend)"   # NAO_TERMINAL 唯一赋值点在 term.sh
sed 's/^NAO_TERMINAL="${NAO_TERMINAL:-herdr}"$/NAO_TERMINAL="${NAO_TERMINAL:-tmux}"/' \
  "$MUT_DEF_MOD" > "$MUT_DEF_MOD.mut" && mv "$MUT_DEF_MOD.mut" "$MUT_DEF_MOD"
t4_assert_eq "1" "$(grep -cE '^NAO_TERMINAL="\$\{NAO_TERMINAL:-tmux\}"$' "$MUT_DEF_MOD" || true)" \
  "P2① 变异：副本确已把默认改回 tmux（变异锚点有效）"
t4_run_in_dir "$LAB" env -u NAO_TERMINAL "${HENV[@]:1}" NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" \
  PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" PATH="$LAB/bin:$PATH" \
  timeout 180 "$BASH_BIN" -c 'printf "%s\n" "$$" >> "$B2_PID_LOG"; exec "$@"' _ "$MUT_DEF" status
MUT_RC=$T4_RC; MUT_MD5="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g' | md5sum | awk '{print $1}')"
t4_assert_ne "$GOLD_HERDR_MD5" "$MUT_MD5" \
  "P2① 变异自证：默认改回 tmux ⇒ 未设不再等于 herdr golden（判据必红，不是空转）"
t4_assert_ne "0" "$MUT_RC" \
  "P2① 变异自证：默认改回 tmux 后 herdr 场未设 ⇒ rc≠0（herdr 场的默认前提全缺）"
rm -f "$MUT_DEF"
# >>> default-value-probe END

# ============================================================================
# B2（#96 二期 + 三期 P1 布局 A）：放置 / 就绪门 / 幽灵 pane / 同名歧义 / 迁移
#   桩状态：$ST/{panes,agents,ws,tabs,order.log,calls.log}；`pane run` 按 HERDR_STUB_ONRUN 追加 agent 条目，
#   并记 order.log（用于断言「先 label(rename) 后 run」）。
#   三期 P1：panes 第 5 列 = tab_id（缺 = `<ws>:t1`）；tabs = `tab_id|ws|label`（缺则按 pane 自动补登记）。
# ============================================================================
B2ST="$LAB/b2-stub"; B2ST_BIN="$B2ST/bin"; B2ST_ST="$B2ST/st"
mkdir -p "$B2ST_BIN" "$B2ST_ST"
cat > "$B2ST_BIN/herdr" <<'SH'
#!/usr/bin/env bash
ST="${HERDR_STUB_STATE:?}"
printf 'herdr %s\n' "$*" >> "$ST/calls.log"
if [ "${1:-}" = "--session" ]; then shift 2; fi
cmd="${1:-}"; shift || true
# panes: pane|label|fg|ws|tab（tab 空 ⇒ <ws>:t1）
pane_tab() { # <pane_id>
  awk -F'|' -v p="$1" '$1==p{ if ($5) print $5; else print $4":t1"; exit }' "$ST/panes" 2>/dev/null
}
pane_ws() { awk -F'|' -v p="$1" '$1==p{print $4; exit}' "$ST/panes" 2>/dev/null; }
# pane/tab id 分配 = max 现有索引 + 1（**同一套分配器**：tab create / pane split / move 不得撞号）
next_pane_id() { # <ws>
  awk -F'|' -v w="$1" '$4==w && $1 ~ /:p[0-9]+$/ { n=$1; sub(/^.*:p/,"",n); if (n+0>m) m=n+0 } END{ printf "%s:p%d\n", w, m+1 }' "$ST/panes" 2>/dev/null
}
next_tab_id() { # <ws>
  awk -F'|' -v w="$1" '$2==w && $1 ~ /:t[0-9]+$/ { n=$1; sub(/^.*:t/,"",n); if (n+0>m) m=n+0 } END{ printf "%s:t%d\n", w, m+1 }' "$ST/tabs" 2>/dev/null
}
tab_seeded() { # 未登记 tab 按现有 pane 自动补登记（label=1），保证旧夹具（4 列 panes）仍可读
  local pid tab ws
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    tab="$(pane_tab "$pid")"; ws="$(pane_ws "$pid")"
    [ -n "$tab" ] && [ -n "$ws" ] || continue
    grep -q "^$tab|" "$ST/tabs" 2>/dev/null || printf '%s|%s|1\n' "$tab" "$ws" >> "$ST/tabs"
  done < <(awk -F'|' 'NF{print $1}' "$ST/panes" 2>/dev/null)
}
tab_pane_count() { # <tab_id>
  local n=0 pid
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    [ "$(pane_tab "$pid")" = "$1" ] && n=$((n + 1))
  done < <(awk -F'|' 'NF{print $1}' "$ST/panes" 2>/dev/null)
  printf '%s' "$n"
}
json_tabs() { # [ws]
  local first=1 tab ws label out="" cnt
  tab_seeded
  while IFS='|' read -r tab ws label; do
    [ -n "$tab" ] || continue
    if [ -n "${WSFILTER:-}" ] && [ "$ws" != "$WSFILTER" ]; then continue; fi
    cnt="$(tab_pane_count "$tab")"
    [ "$first" = 1 ] || out+=","
    first=0
    out+="{\"tab_id\":\"$tab\",\"workspace_id\":\"$ws\",\"label\":\"$label\",\"pane_count\":$cnt}"
  done < "$ST/tabs" 2>/dev/null
  printf '{"result":{"tabs":[%s],"type":"tab_list"}}\n' "$out"
}
json_panes() {
  local first=1 pid label fg ws tab out=""
  while IFS='|' read -r pid label fg ws tab; do
    [ -n "$pid" ] || continue
    [ -n "$tab" ] || tab="$ws:t1"
    if [ -n "${WSFILTER:-}" ] && [ "$ws" != "$WSFILTER" ]; then continue; fi
    [ "$first" = 1 ] || out+=","
    first=0
    out+="{\"pane_id\":\"$pid\",\"label\":\"$label\",\"cwd\":\"${HERDR_STUB_CWD:-$ST/repo}\",\"foreground_cwd\":\"${HERDR_STUB_CWD:-$ST/repo}\",\"agent_status\":\"unknown\",\"terminal_id\":\"term_$pid\",\"workspace_id\":\"$ws\",\"tab_id\":\"$tab\"}"
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
        ws="$(awk -F'|' 'NR==1{print $4}' "$ST/panes")"
        base="${1:-}"; btab="$(pane_tab "$base")"
        new="$(next_pane_id "$ws")"
        printf '%s||bash|%s|%s\n' "$new" "$ws" "${btab:-$ws:t1}" >> "$ST/panes"
        printf '{"result":{"pane":{"pane_id":"%s"}}}\n' "$new" ;;
      layout)
        pid=""; while [ "$#" -gt 0 ]; do [ "$1" = "--pane" ] && pid="${2:-}"; shift; done
        tab="$(pane_tab "$pid")"; [ -n "$tab" ] || { printf '{"error":{"code":"pane_not_found"}}\n' >&2; exit 1; }
        cols="${HERDR_STUB_COLS:-120}"; rows="${HERDR_STUB_ROWS:-40}"
        printf '{"result":{"layout":{"area":{"height":%s,"width":%s,"x":0,"y":0},"panes":[{"focused":true,"pane_id":"%s","rect":{"height":%s,"width":%s,"x":0,"y":0}}],"tab_id":"%s"}}}\n' \
          "$rows" "$cols" "$pid" "$rows" "$cols" "$tab" ;;
      move)
        pid="${1:-}"; [ -n "$pid" ] || exit 1
        prev="$(pane_tab "$pid")"; ws="$(pane_ws "$pid")"
        created=""
        if printf '%s\n' "$*" | grep -q -- '--new-tab'; then
          tab="$(next_tab_id "$ws")"; printf '%s|%s|%s\n' "$tab" "$ws" "${tab##*:t}" >> "$ST/tabs"; created="$tab"
        else
          tab="$(printf '%s\n' "$*" | sed -nE 's/.*--tab ([^ ]+).*/\1/p' | head -1)"
          [ -n "$tab" ] || exit 1
        fi
        awk -F'|' -v p="$pid" -v t="$tab" 'BEGIN{OFS="|"} $1==p{$5=t} {print}' "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes"
        # 被搬空的 tab 自动关（布局 A 契约）
        if [ -n "$prev" ] && [ "$(tab_pane_count "$prev")" = "0" ]; then
          grep -v "^$prev|" "$ST/tabs" > "$ST/tabs.new" 2>/dev/null || true
          [ -f "$ST/tabs.new" ] && mv "$ST/tabs.new" "$ST/tabs"
        fi
        if [ -n "$created" ]; then
          printf '{"result":{"move_result":{"changed":true,"created_tab":{"tab_id":"%s","workspace_id":"%s"},"pane":{"pane_id":"%s"}}}}\n' "$created" "$ws" "$pid"
        else
          printf '{"result":{"move_result":{"changed":true,"pane":{"pane_id":"%s"}}}}\n' "$pid"
        fi ;;
      close)
        pid="${1:-}"; ctab="$(pane_tab "$pid")"
        grep -v "^$pid|" "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes"
        # 真 herdr：关掉 tab 的最后一个 pane ⇒ 该 tab 随之消失（布局 A 重开路径依赖这条）
        if [ -n "$ctab" ] && [ "$(tab_pane_count "$ctab")" = "0" ]; then
          grep -v "^$ctab|" "$ST/tabs" > "$ST/tabs.new" 2>/dev/null || true
          [ -f "$ST/tabs.new" ] && mv "$ST/tabs.new" "$ST/tabs"
        fi ;;
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
        printf '%s|%s|1\n' "$ws:t1" "$ws" >> "$ST/tabs"
        printf '%s||bash|%s|%s:t1\n' "$ws:p1" "$ws" "$ws" >> "$ST/panes"
        printf '{"result":{"root_pane":{"pane_id":"%s:p1","workspace_id":"%s","tab_id":"%s:t1"},"workspace":{"workspace_id":"%s","label":"%s"}}}\n' "$ws" "$ws" "$ws" "$ws" "$label" ;;
      close)
        ws="${1:-}"
        grep -v "^$ws|" "$ST/ws" > "$ST/ws.new" 2>/dev/null || true
        [ -f "$ST/ws.new" ] && mv "$ST/ws.new" "$ST/ws"
        grep -v "|$ws|" "$ST/panes" > "$ST/panes.new" 2>/dev/null || true
        [ -f "$ST/panes.new" ] && mv "$ST/panes.new" "$ST/panes"
        grep -v "^$ws:" "$ST/tabs" > "$ST/tabs.new" 2>/dev/null || true
        [ -f "$ST/tabs.new" ] && mv "$ST/tabs.new" "$ST/tabs" ;;
      *) exit 1 ;;
    esac ;;
  tab)
    sub="${1:-}"; shift || true
    case "$sub" in
      list)
        WSFILTER=""
        if [ "${1:-}" = "--workspace" ]; then WSFILTER="${2:-}"; fi
        json_tabs ;;
      create)
        ws=""; label=""
        while [ "$#" -gt 0 ]; do
          case "$1" in --workspace) ws="${2:-}"; shift 2 ;; --label) label="${2:-}"; shift 2 ;; *) shift ;; esac
        done
        [ -n "$ws" ] || exit 1
        tab="$(next_tab_id "$ws")"
        printf '%s|%s|%s\n' "$tab" "$ws" "$label" >> "$ST/tabs"
        newp="$(next_pane_id "$ws")"
        printf '%s||bash|%s|%s\n' "$newp" "$ws" "$tab" >> "$ST/panes"
        printf '{"result":{"root_pane":{"pane_id":"%s","workspace_id":"%s","tab_id":"%s"},"tab":{"tab_id":"%s","label":"%s"}}}\n' \
          "$newp" "$ws" "$tab" "$tab" "$label" ;;
      rename)
        tab="${1:-}"; label="${2:-}"
        awk -F'|' -v t="$tab" -v l="$label" 'BEGIN{OFS="|"} $1==t{$3=l} {print}' "$ST/tabs" > "$ST/tabs.new" 2>/dev/null || true
        [ -f "$ST/tabs.new" ] && mv "$ST/tabs.new" "$ST/tabs"
        printf '{"result":{"tab":{"tab_id":"%s","label":"%s"}}}\n' "$tab" "$label" ;;
      *) exit 1 ;;
    esac ;;
  *) exit 1 ;;
esac
exit 0
SH
chmod +x "$B2ST_BIN/herdr"
mkdir -p "$LAB/tmp"
# ---- D-1（T547 · QA P2-1②）继承面全摘：不能用单值钉 `HERDR_PANE_ID=w9:p9` 冒充隔离 ----
#   缺陷：钉值是**单一取值**，若宿主 pane 恰好撞上钉值（或守卫被删）就会重新 flaky；
#   且 HERDR_WORKSPACE_ID / HERDR_TAB_ID 同样会渗进 stub 场景。⇒ 直接引用单源清单
#   `tests/t4/lib.sh::T4_HERDR_UNSET_ARGS`（与 `_be_herdr_exec` / `be_run_fleet` 同口径），
#   使 B2 夹具与跑者所在 pane **脱钩**（host-independent；#130 D2 也要求调用点不手写清理变量名）。
B2_ENV=(env "${T4_HERDR_UNSET_ARGS[@]}" \
  HERDR_ENV=1 HERDR_SESSION=nao-b2-stub XDG_CONFIG_HOME="$LAB/cfg" \
  HERDR_SOCKET_PATH="$LAB/cfg/herdr/sessions/nao-b2-stub/herdr.sock" \
  HERDR_STUB_CWD="$LAB" \
  NAO_SKILLS="$LAB" TMPDIR="$LAB/tmp" PI_CODING_AGENT_DIR="$LAB/pi-empty" NAO_TASKS_STATE="$TASKS_FIX" \
  PATH="$B2ST_BIN:$PATH")
t4_assert_eq "1" "$(grep -F 'B2_ENV=(env "${T4_HERDR_UNSET_ARGS[@]}"' "${BASH_SOURCE[0]}" | grep -c '^B2_ENV=' || true)" \
  "D-1 静态：B2_ENV 从单源派生（#130 D2：调用点零手写）"
for v in HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID; do
  t4_assert_eq "1" "$([[ " ${B2_ENV[*]} " == *" -u $v "* ]] && echo 1 || echo 0)" \
    "D-1 静态：B2_ENV 继承面全摘含「-u $v」（单值钉不回流）"
done
# 放置键（T545 · ADR 2026-11-13）：label = 已声明 scope 否则**目标仓 slug**；本区用例的目标仓 = $LAB
#   （roles.yaml workspace="." ⇒ repo=$PWD=$LAB，非 git 仓 ⇒ slug = basename）。$LAB 名形如 `lab28-<pid>`
#   只含 [a-z0-9-]，slug 归一为恒等 ⇒ 可以直接用 basename 当期望值（不复制归一算式）。
B2_WS_LABEL="${LAB##*/}"
B2_RD_FE="rd-fe2(T1)"
B2_RD_BE="rd-be2(T1)"
b2_reset() { # 清桩状态（每场景一份）
  rm -rf "$B2ST_ST"; mkdir -p "$B2ST_ST"; : > "$B2ST_ST/panes"; : > "$B2ST_ST/agents"; printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"; : > "$B2ST_ST/tabs"
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

# ---- D-1 机械自证（QA P2-1②：撞号 pane id 不得让夹具 flaky）----
#   外部 env **显式注入** HERDR_PANE_ID=w1:p1 / WORKSPACE / TAB；B2_ENV 必须先摘掉它们，
#   于是 stub 里 w1:p1 的在线 pi 仍可被 close（rc=0）——这正是 QA 在宿主 pane=w1:p1 踩到的红。
#   负控：把 B2_ENV 的 `-u` 守卫去掉（副本）⇒ 注入值泄进 fleet ⇒ close 判「调用者自身」⇒ 本组必红。
b2_reset
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
printf 'w1:t1|w1|%s\n' "$B2_RD_FE" > "$B2ST_ST/tabs"
printf 'w1:p1|%s|pi|w1|w1:t1\n' "$B2_RD_FE" > "$B2ST_ST/panes"
printf 'w1:p1|idle|3|1|sess-a\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" env HERDR_PANE_ID=w1:p1 HERDR_WORKSPACE_ID=w1 HERDR_TAB_ID=w1:t1 \
  "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" close "rd-fe2(T1)"
B2_D1_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
B2_D1_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "D-1 注入撞号 HERDR_PANE_ID=w1:p1 ⇒ B2_ENV 摘除后 close rc=0（hermetic）"
t4_assert_contains "$B2_D1_OUT" "已回收 rd-fe" "D-1 撞号环境不影响真回收（注入值被摘掉）"
t4_assert_not_contains "$B2_D1_OUT$B2_D1_ERR" "调用者自身" "D-1 不得把 stub pane 误判为调用者自身"

# ---- B2① 反假阳性：已 idle 但 seq 不前进（ONRUN: idle|seq=0|skip=1|session 有）⇒ 就绪门超时 fail loud ----
#   同时验 wall-clock 口径（P3-3）：用 NAO_HERDR_READY_TIMEOUT_MS=400 覆盖，避免本用例白等 5s。
b2_reset
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|0|1|sess-x' \
  NAO_HERDR_READY_TIMEOUT_MS=400 NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "B2① 就绪超时 ⇒ ensure rc=1（T563/AC5 全败契约；跨后端一致）"
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
printf 'w1:p1|%s|bash|w1\n' "$B2_RD_FE" > "$B2ST_ST/panes"
: > "$B2ST_ST/agents"
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
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
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
printf 'w1:p1|%s|pi|w1\nw1:p2|%s|pi|w1\n' "$B2_RD_FE" "$B2_RD_FE" > "$B2ST_ST/panes"
printf 'w1:p1|idle|1|1|sess-a\nw1:p2|idle|1|1|sess-b\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "B2③ 同名歧义：ensure rc=1（T563/AC5 全败；仍是 SPAWN_FAIL 不是 crash）"
t4_assert_contains "$B2_ERR" "同名 label 命中多个 pane" "B2③ 命中多个 ⇒ warn 点名（不猜）"
t4_assert_contains "$B2_ERR" "w1:p1 w1:p2" "B2③ warn 回显全部命中的 pane（可定位）"
t4_assert_not_contains "$B2_OUT" "[herdr] 已拉起" "B2③ 歧义下不得擅自挑一个启动（无成功行）"
t4_assert_contains "$B2_OUT" "失败 1" "B2③ 歧义计入 SPAWN_FAIL（摘要可见）"
t4_assert_eq "0" "$(grep -cE '^herdr pane (rename|run|split)' "$B2ST_ST/calls.log" || true)" \
  "B2③ 歧义下零放置动作（rename/run/split 都不发）"

b2_reset
printf 'w1:p1|%s|pi|w1\nw1:p2|%s|pi|w1\n' "$B2_RD_FE" "$B2_RD_FE" > "$B2ST_ST/panes"
printf 'w1:p1|idle|1|1|sess-a\nw1:p2|idle|1|1|sess-b\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" status
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
sleep 0.6   # 等 status 的子进程/管道收尾（tmux-free，此处只避免与下段 tmux 用例抢输出文件）
t4_assert_eq "0" "$T4_RC" "B2③ 歧义场景 status rc=0（非 crash）"
t4_assert_contains "$B2_OUT" "同名 label 多 pane" "B2③ status 单列「同名 label 多 pane」（终端证据异常节）"
t4_assert_not_contains "$B2_OUT" "✓ $B2_RD_FE" "B2③ 歧义不得渲染成 ✓ 在线（不猜）"

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
  printf 'w1:p1|%s|%s|w1\n' "$B2_RD_FE" "$b2fg" > "$B2ST_ST/panes"
  : > "$B2ST_ST/agents"; printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
  t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
    NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
  B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "1" "$T4_RC" "P2-2 前台=$b2fg：ensure rc=1（T563/AC5 全败；仍是 SPAWN_FAIL 不是 crash）"
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
printf 'w1:p1|%s|phantom|w1\n' "$B2_RD_FE" > "$B2ST_ST/panes"
: > "$B2ST_ST/agents"; printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
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
  printf 'w1:p1|%s|%s|w1\n' "$B2_RD_FE" "$b2bad" > "$B2ST_ST/panes"
  : > "$B2ST_ST/agents"; printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
  t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
    NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
  B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "1" "$T4_RC" "P3-6 $b2bad：ensure rc=1（T563/AC5 全败；仍是 SPAWN_FAIL 不是 crash）"
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

# ---- 布局 A（三期 P1 · AC3.1）+ 迁移无损（同一 tab 内旧布局 ⇒ pane move --new-tab）----
#   梯度：① 新 workspace 内第二个角色 = **tab create**（不再 split 进同一 tab）→ 每 tab 恰 1 pane；
#        ② 旧布局（共享 tab 内多 pane，label = 目标名）⇒ ghost 复用 + 迁到独立 tab：pane_id 不变，
#           搬空的 tab 自动关；
#        ③ 对照：全程零 pane split（布局不靠分屏算式）。
b2_reset
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
: > "$B2ST_ST/panes"
: > "$B2ST_ST/tabs"
: > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 rd-fe2
B2A_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "J2① 新放置 ensure rc=0"
t4_assert_contains "$B2A_OUT" "已拉起 rd-fe" "J2① 成功行在位"
t4_assert_eq "0" "$(grep -cE '^herdr .*pane (move|split)' "$B2ST_ST/calls.log" || true)" \
  "J2① 新放置零 pane move/split（tab 拓扑由 workspace/tab create 建立）"
t4_assert_eq "0" "$(grep -c '^herdr .*pane split' "$B2ST_ST/calls.log" || true)" \
  "J2① 零 pane split（布局不靠分屏算式）"
t4_assert_contains "$(cat "$B2ST_ST/tabs")" "|$B2_RD_FE" "J2① tab label = 角色名（结构判据）"
t4_assert_eq "1" "$(awk -F'|' -v n="$B2_RD_FE" '$3==n{print $1}' "$B2ST_ST/tabs" | while read -r t; do awk -F'|' -v t="$t" '$5==t' "$B2ST_ST/panes" | wc -l; done)" \
  "J2① 该角色 tab 恰 1 个 pane（pane_count == 1）"
# ② 旧布局迁移（v2 新名）：两个 ghost 共处共享 tab ⇒ 各自 ensure 后 pane move --new-tab，pane_id 不变；
#    再给一个「独占但 label 旧」的 tab ⇒ 只 tab rename（零 pane 搬动，更小 effect）。
b2_reset
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
printf 'w1:p1|%s|bash|w1|w1:t1\nw1:p2|%s|bash|w1|w1:t1\n' "$B2_RD_FE" "$B2_RD_BE" > "$B2ST_ST/panes"
printf 'w1:t1|w1|1\n' > "$B2ST_ST/tabs"
: > "$B2ST_ST/agents"
for _r in rd-fe2 rd-be2; do
  t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-x' \
    NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 "$_r"
  t4_assert_eq "0" "$T4_RC" "J2② 迁移 $_r：ensure rc=0"
done
t4_assert_eq "2" "$(grep -c '^herdr .*pane move' "$B2ST_ST/calls.log" || true)" \
  "J2② 共享 tab 的两个 ghost 都用 pane move 迁移（各 1 次）"
t4_assert_eq "2" "$(grep -cE '^herdr .*pane move .* --new-tab' "$B2ST_ST/calls.log" || true)" \
  "J2② 迁移走 --new-tab（把 pane 搬进独立 tab）"
t4_assert_contains "$(cat "$B2ST_ST/panes")" "w1:p1|$B2_RD_FE" "J2② 迁移后 pane_id 不变（$B2_RD_FE 仍 w1:p1）"
t4_assert_contains "$(cat "$B2ST_ST/panes")" "w1:p2|$B2_RD_BE" "J2② 迁移后 pane_id 不变（$B2_RD_BE 仍 w1:p2）"
t4_assert_eq "0" "$(grep -c '|1$' "$B2ST_ST/tabs" || true)" "J2② 无 label=1 的旧 tab 残留（迁移已收敛）"
for _lbl in "$B2_RD_FE" "$B2_RD_BE"; do
  t4_assert_eq "1" "$(grep -cF -- "|$_lbl" "$B2ST_ST/tabs" || true)" \
    "J2② tab label = 角色名（$_lbl）"
  _tid="$(awk -F'|' -v n="$_lbl" '$3==n{print $1}' "$B2ST_ST/tabs" | head -1)"
  t4_assert_eq "1" "$([ -n "$_tid" ] && awk -F'|' -v t="$_tid" '$5==t' "$B2ST_ST/panes" | grep -c . || true)" \
    "J2② 该角色 tab 恰 1 个 pane（$_lbl）"
done
# 迁移分支同时覆盖 `tab rename`（每个 --new-tab 之后都把新 tab 标成角色名）
t4_assert_eq "2" "$(grep -c '^herdr .*tab rename' "$B2ST_ST/calls.log" || true)" \
  "J2② 迁移后新 tab 均被改名为角色名（rename 分支随迁移执行）"

# ---- P2-1（第二轮 QA）：文案与新语义一致（P1 把「角色 tab 被占 + --force」收紧成 fail loud）----
#   旧文案说「--force ⇒ 新建 pane（随后同名 label 会有 2 个）」，但实际紧接着就 fail loud、根本不新建
#   ⇒ 用户若照 close 提示「ensure --force 重开」会得到失败 1。本块把两条路径都钉住。
#   ① 角色 tab 被他人 pane 占用（tab label=n、pane label=intruder）+ `--force` ⇒ fail loud + 指路 close
b2_reset
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
printf 'w1:t1|w1|%s\n' "$B2_RD_FE" > "$B2ST_ST/tabs"
printf 'w1:p1|intruder|bash|w1|w1:t1\n' > "$B2ST_ST/panes"
: > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 --force rd-fe2
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "P2-1① 角色 tab 被占 + --force：ensure rc=1（T563/AC5：全败 ⇒ rc=1）"
t4_assert_contains "$B2_ERR" "角色 tab 已在场但无 pane 命中该角色" "P2-1① 新文案点名「角色 tab 已在场但无 pane 命中」"
t4_assert_contains "$B2_ERR" '先回收该角色（nao-fleet.sh close rd-fe2(T1)）再重跑 ensure' \
  "P2-1① 指路 = 先 close 该角色再 ensure（不再说「新建 pane」）"
t4_assert_not_contains "$B2_ERR" "同名 label 会有 2 个" "P2-1① 旧文案「同名 label 会有 2 个」已退场（实际不新建）"
t4_assert_contains "$B2_OUT" "（成功 0 / 跳过 0 / 失败 1）" "P2-1① 摘要计失败 1（不冒充成功）"
t4_assert_eq "1" "$(printf '%s\n' "$(cat "$B2ST_ST/panes")" | grep -c . || true)" \
  "P2-1① 同名 label 仍 1（未新建 pane，pane 数不变）"
t4_assert_eq "1" "$(grep -cF "|$B2_RD_FE" "$B2ST_ST/tabs" || true)" "P2-1① 仍只有 1 个 rd-fe tab（未新建第二个同名 tab）"
t4_assert_eq "0" "$(grep -c 'pane run ' "$B2ST_ST/calls.log" || true)" "P2-1① 零 pane run（不接管他人 pane）"
t4_assert_eq "0" "$(grep -c 'pane split ' "$B2ST_ST/calls.log" || true)" "P2-1① 零 pane split"

#   ② 在线 pi 占位 + `--force` ⇒ fail loud；提示=先 close 再 ensure；close 后 `ensure --force` ⇒ 成功新建
b2_reset
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
printf 'w1:t1|w1|%s\n' "$B2_RD_FE" > "$B2ST_ST/tabs"
printf 'w1:p1|%s|pi|w1|w1:t1\n' "$B2_RD_FE" > "$B2ST_ST/panes"
printf 'w1:p1|idle|3|1|sess-a\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 --force rd-fe2
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_contains "$B2_ERR" "--force 也不向在场程序注入按键" "P2-1② --force 撞上在线 pi：仍不注入按键"
t4_assert_contains "$B2_ERR" "角色 tab 已被占用 ⇒ fail loud" "P2-1② 明说随后会 fail loud（不再是「新建 pane」）"
t4_assert_eq "1" "$(printf '%s\n' "$(cat "$B2ST_ST/panes")" | grep -c . || true)" \
  "P2-1② 在线 pane 仍在场且未新增（同名 label 仍 1）"
# close 提示（P2-1 的第二处文案）
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" close "rd-fe2(T1)"
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "P2-1② close rd-fe2(T1) rc=0（派生）"
# 常驻 close 的提示语义：另起一个 resident 名（派生名带 task，走 tasks-state 分支，不弹常驻提示）
b2_reset
printf 'w1|%s\n' "$B2_WS_LABEL" > "$B2ST_ST/ws"
printf 'w1:t1|w1|rd-fe2\n' > "$B2ST_ST/tabs"
printf 'w1:p1|rd-fe2|pi|w1|w1:t1\n' > "$B2ST_ST/panes"
printf 'w1:p1|idle|3|1|sess-r\n' > "$B2ST_ST/agents"
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" NAO_TERMINAL=herdr timeout 60 \
  "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" close rd-fe2
B2_ERR="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "P2-1② close 常驻 rd-fe2 rc=0"
t4_assert_contains "$B2_ERR" "[fleet] 常驻会话 rd-fe2：" "P2-1② close 提示固定前缀在位（v2 名）"
t4_assert_contains "$B2_ERR" "本批不再需要该角色时才回收；回收后可用 ensure 重开" "P2-1② close 提示与新语义一致"
t4_assert_not_contains "$B2_ERR" "应 ensure --force 重开" "P2-1② 旧提示「应 ensure --force 重开」已退场"
# close 后（pane 与空 tab 均已消失）⇒ --force 成功新建（证明上一条提示可执行）
t4_run_in_dir "$LAB" "${B2_ENV[@]}" HERDR_STUB_STATE="$B2ST_ST" HERDR_STUB_ONRUN='idle|1|1|sess-b' \
  NAO_TERMINAL=herdr timeout 60 "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" ensure --task T1 --force rd-fe2
B2_OUT="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "0" "$T4_RC" "P2-1② close 后 ensure --force rc=0"
t4_assert_contains "$B2_OUT" "已拉起 rd-fe" "P2-1② close 后 ensure --force 成功新建（提示可执行，不再「照做即失败」）"
t4_assert_contains "$B2_OUT" "（成功 1 / 跳过 0 / 失败 0）" "P2-1② 摘要 1/0/0"

# ---- ④ BR7 忙闲映射 + 阶梯单测（抽取门面区到子进程；只灌纯依赖，不启 tmux）----
FACADE_SRC="$T4_CACHE_DIR/b1-facade.sh"
# T567-A：门面区 = term.sh（门面 + 常量）+ term-herdr.sh + term-app.sh（两个实现同层）
{
  cat "$(t4_fleet_file_for "$LAB/.agents/scripts" term_backend)" || exit 1
  cat "$(t4_fleet_file_for "$LAB/.agents/scripts" _term_herdr_exec)" || exit 1
  cat "$(t4_fleet_file_for "$LAB/.agents/scripts" _term_app_backend)" || exit 1
} > "$FACADE_SRC"
t4_assert_ne "0" "$(wc -l < "$FACADE_SRC" | tr -d ' ')" \
  "B1④ 门面区可抽取（# >>> term-facade BEGIN … END，非空 ⇒ 四函数可独立单测）"
{
  printf '#!/usr/bin/env bash\nset -uo pipefail\n'
  printf 'warn() { printf "[warn] %%s\\n" "$*" >&2; }\n'
  printf 'die() { printf "[die] %%s\\n" "$*" >&2; exit 1; }\n'
  printf 'require_tmux() { return 0; }\n'
  printf 'TERM_HERDR_PROTOCOL=%s\n' "$(sed -n 's/^TERM_HERDR_PROTOCOL="\([^"]*\)"$/\1/p' "$(t4_fleet_file_for "$LAB/.agents/scripts" term_backend)" | head -1)"
  printf 'VERBOSE=false\n'
  awk '/^nao_phys_path\(\)/{f=1} f{print} f&&/^}/{exit}' "$(t4_fleet_file_for "$LAB/.agents/scripts" nao_phys_path)"
  awk '/^repo_contains_path\(\)/{print; exit}' "$(t4_fleet_file_for "$LAB/.agents/scripts" repo_contains_path)"
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
# T555 退役（3 条）：`term_argv/liveness/snapshot` 的 tmux 分派断言 —— 分派分支已随后端删除；
#   门面的 herdr 路径由本子测上下文的其余 chk（快照缓存 / BR7 映射 / protocol 闸门）逐条覆盖。
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


# ---------------------------------------------------------------- C2② ensure（T555 退役）
# 退役整组（逐条归因见 docs/reports/555-impl-rd-infra.md）：
#   · 「基线场 vs 新版场」的 `已拉起` 行 / `--name` 值对照 —— 基线 fixture 只认 tmux 后端，
#     而本版 `NAO_TERMINAL=tmux` 是 rc=2 用法守卫 ⇒ 无对照对象；
#   · 其夹具（两场隔离 tmux server + `π - <名> - <仓>` 标题契约 pane）已不存在；
#   · P2-1 命名预算组（48/49/50 字符边界与「建 pane 之前 die」）与 P3-2/P3-3① 同场显示组
#     同样以 tmux title/pane 数为夹具，一并退役。
#   **等价覆盖**：v2 命名口径（恒带 `@<fleet>` / 槽位 / 派生 / 卡）由 cases/40（13 态）与
#   cases/38（close 全名解析）逐条钉；builder/parse 恒等由本用例 C1 codec + M1–M5 覆盖；
#     ensure 三态输出与逐目标卡由 cases/22 / 24 覆盖。
t4_ok "C2②（退役留痕）：命名契约的 ensure 级覆盖已移交 cases/40 与 22/24（本组不再以 tmux 夹具为载）"


# ============================================================================
# B3（#96 二期 · 用例 28 内嵌节）：herdr 回收面 close / cleanup
#   报告 = docs/reports/96b3-close-cleanup.md；本节独立可跑（`bash <本节所在文件>` 不单列，
#   但断言全部后端无关：用有状态 herdr 桩，不启真 server / 不碰用户 default）。
#   组：① BR1 tmux 逐字 golden md5 ② 忙闲闸门 BR7 ③ 名册第二信号 OR ④ 五档证据 fail-closed
#       ⑤ self 三态 ⑥ 恢复窗口 ⑦ effect 判据 ⑧ cleanup 守卫与幂等
# ============================================================================

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
FLEET_BUNDLE="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"   # T567-A：只读内容断言按文件集
BASH_BIN="$(command -v bash)"
B3_LAB="$T4_CACHE_DIR/c28b3-$$"
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
        if [ "${HERDR_STUB_PANE_LIST_FAIL:-0}" = "1" ]; then
          printf '{"error":{"code":"internal_error","message":"pane list unavailable"}}\n' >&2
          exit 1
        fi
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
        if [ "${HERDR_STUB_SESSION_LIST_FAIL:-0}" = "1" ]; then
          printf '{"error":{"code":"internal_error","message":"session list unavailable"}}\n' >&2
          exit 1
        fi
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
# golden 复算（旧版 = B3 之前 e98ed49；函数名在 B3 前后不同，故注释写明旧名，后来人可自行复算）：
#   句柄层（B3 前位于 **cmd_close** 体内；B3 后同段在 _term_tmux_reclaim 体内）：
#     git show e98ed49:.agents/scripts/nao-fleet.sh \
#       | awk '/^  # ---- 宿主句柄定位（跨仓）/{f=1} f{print} f&&/^}/{exit}' | md5sum   ⇒ 9549f513…
#   cleanup 体（B3 前函数名 **cmd_cleanup**；B3 后改名 _term_tmux_cleanup，判据跳过函数头行）：
#     git show e98ed49:.agents/scripts/nao-fleet.sh \
#       | awk '/^cmd_cleanup\(\) \{/{f=1;next} f{print} f&&/^}/{exit}' | md5sum              ⇒ d8937134…
#   socket 候选（函数名未变）：
#     git show e98ed49:.agents/scripts/nao-fleet.sh \
#       | awk '/^prod_sock_candidates\(\) \{/{f=1;print;next} f{print} f&&/^}/{exit}' | md5sum ⇒ e4950f38…
# ============================================================================
# BR1 tmux 逐字 golden（T555 退役，4 条）
#   原判据：`_term_tmux_reclaim` 句柄层段 / `_term_tmux_cleanup` 体 / `prod_sock_candidates`
#   三处 md5 与 B3 之前（e98ed49）逐字相等 + 一处变异自证。
#   tmux 后端整组删除（ADR 2026-11-22-herdr-only）⇒ 三处源码对象不存在、`cleanup -S` 面已改为
#   rc=2 用法守卫（cases/13/41 覆盖）⇒ 本组退役。herdr 侧的等价物：本用例 B3 节其余断言
#   （忙闲闸门 / 名册第二信号 / 五档 fail-closed / self 三态 / effect 判据 / 守卫幂等）逐条保留。
t4_ok "BR1 tmux 逐字 golden（退役留痕）：三处 tmux 源码对象已删，herdr 回收面由本节其余断言承重"

# ---- 结构：门面调用单点（T555 收窄：tmux 标记区与 6 个 tmux 函数已整组删除）----
#   原 7 条（「tmux 标记区存在」+ 6 个函数位于区内）随后端删除而退役；
#   保留并强化「业务区只经门面」这条（同一意图、单后端后仍然承重）。
t4_assert_eq "0" "$(grep -c '^# >>> term-impl-tmux BEGIN' "$FLEET_BUNDLE" || true)" \
  "B3 tmux 标记区 0 处（回收/自身判定/忙闲的 tmux 副本已删 —— ADR herdr-only）"
t4_assert_eq "1" "$(grep -cE '^  term_reclaim "\$name" "\$repo" "\$force" "\$role" "\$scope" "\$\{tgt:-\$role\}"$' "$FLEET_BUNDLE" || true)" \
  "B3 cmd_close 只调门面 term_reclaim（共用闸门层原地不动）"
t4_assert_eq "1" "$(grep -cE '^  term_cleanup "\$\{SESSION_ARG:-\}" "\$FORCE"$' "$FLEET_BUNDLE" || true)" \
  "B3 cmd_cleanup 只调门面 term_cleanup（T555：-S 面已删，入参仅 session+force）"

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
t4_info "B3dup debug rc=$T4_RC out=[$T4_OUT_ANSI] err=[$T4_ERR_ANSI]"
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
t4_assert_not_contains "$T4_ERR_ANSI" "可能丢失在跑 turn" \
  "P3-1 负控：两个 idle pane 的 --force 清理不误报「可能丢失在跑 turn」"
# P3-1（第二轮 QA · 必修）：working + blocked 各一个 ⇒ 逐 pane 点名 warn（不能汇总一句）
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1" "w1:p2|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|working|2|1|sess-a" "w1:p2|blocked|3|1|sess-b"
b3_run close --force rd-fe
t4_assert_eq "0" "$T4_RC" "P3-1 多 pane + --force（working+blocked）⇒ 按安全判据回收（rc=0）"
t4_assert_contains "$T4_ERR_ANSI" "pane w1:p1：agent_status=working ⇒ **可能丢失在跑 turn**" \
  "P3-1 working pane 逐条 warn（pane 可归属）"
t4_assert_contains "$T4_ERR_ANSI" "pane w1:p2：agent_status=blocked ⇒ **可能丢失在跑 turn**" \
  "P3-1 blocked pane 逐条 warn（pane 可归属）"
t4_assert_eq "2" "$(printf '%s\n' "$T4_ERR_ANSI" | grep -c '可能丢失在跑 turn' || true)" \
  "P3-1 恰 2 条「可能丢失在跑 turn」（每条可归属，不是汇总一句）"
t4_assert_eq "2" "$(b3_close_calls)" "P3-1 working/blocked 各一个：两 pane 都被回收（--force 显式）"
# P3-1 第二信号（OR）在 dup 路径同样逐 pane warn（名册是名字级 ⇒ 如实标注无法区分 pane）
if command -v node >/dev/null 2>&1; then
  B3_ROSTER_DUP="[{\"name\":\"rd-fe\",\"status\":\"tool:bash\",\"cwd\":\"$B3_LAB\",\"tmuxPane\":null}]"
  b3_reset
  b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1" "w1:p2|rd-fe|pi|$B3_LAB|w1"
  b3_agents "w1:p1|idle|2|1|sess-a" "w1:p2|idle|3|1|sess-b"
  t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr NAO_QA_FAKE_ROSTER="$B3_ROSTER_DUP" \
    timeout 60 "$BASH_BIN" "$FLEET" close --force rd-fe
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  t4_assert_eq "0" "$T4_RC" "P3-1 名册 busy + --force：两个都关（rc=0）—— 门禁不拦 --force"
  t4_assert_contains "$T4_ERR_ANSI" "pane w1:p1：pi-intercom 名册状态=tool:bash ⇒ **可能丢失在跑 turn**" \
    "P3-1 名册 busy：pane w1:p1 逐条 warn"
  t4_assert_contains "$T4_ERR_ANSI" "pane w1:p2：pi-intercom 名册状态=tool:bash ⇒ **可能丢失在跑 turn**" \
    "P3-1 名册 busy：pane w1:p2 逐条 warn"
  t4_assert_contains "$T4_ERR_ANSI" "名册信号是名字级" "P3-1 名册 warn 如实标注不可区分 pane（不假装精确）"
fi
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
# ⑥b P3-3（第二轮 QA · 必修）：fail-closed 分支有用例
#   快照不可用 ⇒ close 拒；session list 不可用 ⇒ cleanup 拒；两者都**不自动起 server**、零后端动作
# ============================================================================
b3_reset
b3_panes "w1:p1|rd-fe|pi|$B3_LAB|w1"
b3_agents "w1:p1|idle|2|1|sess-a"
t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr HERDR_STUB_PANE_LIST_FAIL=1 \
  timeout 60 "$BASH_BIN" "$FLEET" close rd-fe
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "P3-3 快照不可用 ⇒ close 拒（rc=1，fail-closed）"
t4_assert_contains "$T4_ERR_ANSI" "快照不可用" "P3-3 close：理由点名「快照不可用」（不谎报未运行）"
t4_assert_contains "$T4_ERR_ANSI" "不回收" "P3-3 close：明确不回收"
t4_assert_eq "0" "$(b3_close_calls)" "P3-3 close：零 pane close（零后端动作）"
t4_assert_eq "0" "$(b3_calls '^herdr .* server( |$)')" \
  "P3-3 close：**不自动起 server**（调用日志零 server）"
t4_assert_eq "1" "$(grep -c '^w1:p1|' "$B3_ST/panes" || true)" "P3-3 close：pane 未被触碰"

b3_reset
printf 'default|stopped\n%s|running\n' "$B3_SESS" > "$B3_ST/sessions"
mkdir -p "$B3_CFG/herdr/sessions/$B3_SESS"
t4_run_in_dir "$B3_LAB" "${B3_ENV[@]}" NAO_TERMINAL=herdr HERDR_STUB_SESSION_LIST_FAIL=1 \
  timeout 60 "$BASH_BIN" "$FLEET" cleanup --session "$B3_SESS"
T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
t4_assert_eq "1" "$T4_RC" "P3-3 session list 不可用 ⇒ cleanup 拒（rc=1）"
t4_assert_contains "$T4_ERR_ANSI" "cleanup 拒绝" "P3-3 cleanup：理由点名「拒绝」"
t4_assert_contains "$T4_ERR_ANSI" "不自动起 server" "P3-3 cleanup：文案明说不自动起 server"
t4_assert_eq "0" "$(b3_calls '^herdr .*session (stop|delete)( |$)')" \
  "P3-3 cleanup：零 stop/delete（零拆场动作）"
t4_assert_eq "0" "$(b3_calls '^herdr .* server( |$)')" "P3-3 cleanup：不自动起 server"
t4_assert_eq "1" "$([ -d "$B3_CFG/herdr/sessions/$B3_SESS" ] && echo 1 || echo 0)" \
  "P3-3 cleanup：会话目录仍在（未被动过）"

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
t4_assert_eq "2" "$T4_RC" "B3⑧ cleanup --session default 无 --force ⇒ rc=2（放行但零动作）"
t4_assert_contains "$T4_ERR_ANSI" "将停止 session=default，影响" "B3⑧ default：打印影响面"
t4_assert_contains "$T4_ERR_ANSI" "未给 --force ⇒ 零动作" "B3⑧ default：明确门槛"
t4_assert_eq "0" "$(b3_calls '^herdr .*session (stop|delete)( |$)')" "B3⑧ default：零拆场动作"
: > "$B3_ST/calls.log"
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
t4_run_in_dir "$B3_LAB" env "${T4_HERDR_UNSET_ARGS[@]}" NAO_TERMINAL=tmux PATH="$B3_BIN:$PATH" \
  timeout 60 "$BASH_BIN" "$FLEET" cleanup
t4_assert_eq "2" "$T4_RC" "B3⑧ tmux cleanup 缺 -S ⇒ rc=2（既有守卫零回归）"
t4_run_in_dir "$B3_LAB" env "${T4_HERDR_UNSET_ARGS[@]}" NAO_TERMINAL=tmux PATH="$B3_BIN:$PATH" \
  timeout 60 "$BASH_BIN" "$FLEET" cleanup --session nao-x
t4_assert_eq "2" "$T4_RC" "B3⑧ tmux cleanup 误用 --session ⇒ rc=2（按后端分派，不静默吞参）"


t4_exit
