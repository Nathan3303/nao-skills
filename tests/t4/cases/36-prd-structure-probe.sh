#!/usr/bin/env bash
# 用例 36 —— PRD 结构探针（`check_prd_structure`）的持久用例（Q8 · M20261118-test-hygiene）
#
# 被测：`.agents/scripts/nao-fleet.sh::check_prd_structure`（warn-only 探针，口径见 checklists §三）。
# 判据（七条，PM Q8）：
#   ① 新日期 PRD 缺 `###` 组 ⇒ **提示**且 rc=0  ② >150 行 ⇒ 提示
#   ③ 老日期（2026-10-01）同缺 ⇒ **不提示**（不追溯）
#   ④ 0 字节 / 不可读 ⇒ **拒绝判合格**（防「删内容凑绿」）
#   ⑤ `NAO_PRD_STRUCT_SINCE` 非法 ⇒ 回落默认且 `-v` 可见
#   ⑥ `warn=` 计数**不被污染**（提示不计入 warn）
#   ⑦ 本仓 `check` 输出与「探针关闭」逐字一致（md5）—— 等价说法：探针在本仓零输出
#
# 负控（三条，全部走「副本改一处 ⇒ 判据必红」）：
#   N1 删掉 `check_prd_structure` 调用 ⇒ ① 的提示必消失（判据非空转）
#   N2 把 `'^  ! PRD 结构'` 从摘要计数的排除名单去掉 ⇒ ⑥ 必红（`warn=` 出现）
#   N3 中和「老日期跳过」⇒ ③ 必红（不追溯的唯一成因）
#   （④「0 字节不得当合格」不单设变异：0 字节文件即便无守卫也会因缺模块被点名 ⇒ 拿它做负控是假演练）
#
# 后端无关（只跑 bash + 夹具 `.agents`，不建 tmux/herdr；不 exec 真 pi）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET_REAL="$T4_ROOT/.agents/scripts/nao-fleet.sh"
t4_assert_file "$FLEET_REAL" "前置：被测脚本存在"

LAB="$T4_CACHE_DIR/lab36-$$"
mkdir -p "$LAB/docs/prds" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

t36_exit_trap() {
  local rc=$?
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t36_exit_trap EXIT

# 夹具 PRD：9 模块齐（缺/齐由调用方定）、AC 组数可调、可垫行到指定行数
t36_mkprd() { # <路径> <AC组数> <总行数>
  local p="$1" groups="$2" want="$3" h i
  local -a names=(— 主路径 异常 边界 负向闭环 设计一致性)   # 1-based（下标 0 占位）
  {
    printf '# PRD：夹具（%s）\n\n' "$(basename "$p")"
    printf '## TL;DR（≤5 行）\n- **做什么**：探针夹具\n\n'
    for h in 一、问题证据 二、目标指标 三、范围/非范围 四、用户场景 五、业务规则 六、NFRs; do
      printf '## %s\n<夹具内容>\n\n' "$h"
    done
    printf '## 七、AC\n\n- 验证接缝：夹具（QA 已确认 2026-11-18）\n'
    for ((i = 1; i <= groups; i++)); do
      printf '\n### %s\n\n- AC%d：Given 前置，When 操作，Then 预期\n' "${names[i]}" "$i"
    done
    printf '\n## 八、上线闭环\n<夹具>\n\n## 九、变更治理\n<夹具>\n'
  } > "$p"
  local now; now="$(wc -l < "$p")"
  for ((i = now; i < want; i++)); do printf -- '- 垫行 %d\n' "$i" >> "$p"; done
}

t36_check() { # <根> [额外 env...] → 输出（rc 见返回值）；在 $1 内跑 check
  local root="$1"; shift
  ( cd "$root" && env -u NAO_STASH_ROOT "$@" bash .agents/scripts/nao-fleet.sh check 2>&1 )
}
t36_hints() { printf '%s\n' "$1" | grep -cE '^  ! PRD 结构' || true; }

# ---------------------------------------------------------------- ① 新日期缺组 ⇒ 提示 + rc=0
P1="$LAB/docs/prds/2026-11-18-missing-group.md"
t36_mkprd "$P1" 4 0
OUT1="$(t36_check "$LAB")"; RC1=$?
t4_assert_eq "0" "$RC1" "① 缺组：check rc=0（warn-only 不改 rc）"
t4_assert_eq "1" "$(t36_hints "$OUT1")" "① 缺组：恰 1 条提示行"
t4_assert_contains "$OUT1" "AC 分组 4 < 5" "① 点名缺项（AC 分组 4 < 5）"
t4_assert_contains "$OUT1" "2026-11-18-missing-group.md" "① 点名具体文件"

# ---------------------------------------------------------------- ② >150 行 ⇒ 提示（明细在 -v）
P2="$LAB/docs/prds/2026-11-18-too-long.md"
t36_mkprd "$P2" 5 166
t4_assert_ge 151 "$(wc -l < "$P2")" "② 夹具自证：文件 >150 行（$(wc -l < "$P2") 行）"
OUT2="$(t36_check "$LAB")"; RC2=$?
t4_assert_eq "0" "$RC2" "② 超行数：check rc=0"
t4_assert_eq "1" "$(t36_hints "$OUT2")" "② 默认模式仍**恰 1 条**聚合提示（不按文件刷屏）"
t4_assert_contains "$OUT2" "中 2 份缺结构" "② 聚合提示给出违规份数（2 份）"
OUT2V="$( cd "$LAB" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$OUT2V" "2026-11-18-too-long.md" "② -v 展开到超行数那份文件"
t4_assert_contains "$OUT2V" "行 > 150" "② -v 点名超行数"
rm -f "$P2"

# ---------------------------------------------------------------- ③ 老日期 ⇒ 不追溯
P3="$LAB/docs/prds/2026-10-01-old-missing.md"
t36_mkprd "$P3" 3 0
OUT3="$(t36_check "$LAB")"
t4_assert_eq "1" "$(t36_hints "$OUT3")" "③ 老日期（2026-10-01）即使缺组也不提示（只剩 ① 那 1 条）"
t4_assert_not_contains "$OUT3" "2026-10-01-old-missing.md" "③ 老文件不出现在提示里（不追溯）"
rm -f "$P3"

# ---------------------------------------------------------------- ④ 0 字节 ⇒ 拒绝判合格
: > "$LAB/docs/prds/2026-11-19-empty.md"
OUT4="$(t36_check "$LAB")"
t4_assert_contains "$OUT4" "中 2 份缺结构" "④ 0 字节：计入违规份数（不得静默当合格）"
OUT4V="$( cd "$LAB" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$OUT4V" "2026-11-19-empty.md" "④ -v 点名空文件"
t4_assert_contains "$OUT4V" "不可读或空文件" "④ -v 点名「不可读或空文件（拒绝判为合格）」"
rm -f "$LAB/docs/prds/2026-11-19-empty.md"

# ---------------------------------------------------------------- ⑤ SINCE 非法 ⇒ 回落默认（-v 可见）
OUT5="$( cd "$LAB" && env -u NAO_STASH_ROOT NAO_PRD_STRUCT_SINCE=bad bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$OUT5" "NAO_PRD_STRUCT_SINCE=bad 非法" "⑤ 非法取值：-v 点名「非法（应为 YYYY-MM-DD）」"
t4_assert_contains "$OUT5" "回落默认 2026-11-18" "⑤ 非法取值：说明回落默认阈值"
t4_assert_eq "1" "$(t36_hints "$OUT5")" "⑤ 非法取值：仍按默认阈值报同一 1 条（行为不漂）"

# ---------------------------------------------------------------- ⑥ warn= 不被污染
t4_assert_not_contains "$OUT1" "warn=" "⑥ 摘要里不出现 warn=（PRD 提示不计入 warn 计数）"
t4_assert_contains "$OUT1" "check: OK · roles=" "⑥ 摘要行仍在（rc=0 正常路径）"

# ---------------------------------------------------------------- ⑦ 本仓输出 ==「探针关闭」逐字一致
REF="$T4_CACHE_DIR/lab36-ref-$$"
mkdir -p "$REF" && cp -r "$T4_ROOT/.agents" "$REF/.agents" || t4_bad "⑦ 夹具：复制 .agents 失败"
# 探针关闭 = 删掉 cmd_check 里的调用行（其余一字不改）
grep -c '^  check_prd_structure || true$' "$REF/.agents/scripts/nao-fleet.sh" >/dev/null 2>&1
sed -i '/^  check_prd_structure || true$/d' "$REF/.agents/scripts/nao-fleet.sh"
t4_assert_eq "0" "$(grep -c 'check_prd_structure || true' "$REF/.agents/scripts/nao-fleet.sh" || true)" \
  "⑦ 负控锚点：副本已删掉探针调用（自证变异生效）"
OUT_REAL="$( cd "$T4_ROOT" && env -u NAO_STASH_ROOT bash "$FLEET_REAL" check 2>&1 )"
OUT_OFF="$( cd "$T4_ROOT" && env -u NAO_STASH_ROOT bash "$REF/.agents/scripts/nao-fleet.sh" check 2>&1 )"
t4_assert_eq "0" "$(t36_hints "$OUT_REAL")" "⑦ 本仓：探针零输出（无 ≥2026-11-18 的 PRD）"
t4_assert_eq "$(printf '%s\n' "$OUT_OFF" | md5sum | awk '{print $1}')" \
  "$(printf '%s\n' "$OUT_REAL" | md5sum | awk '{print $1}')" \
  "⑦ 本仓：check 输出与「探针关闭」逐字一致（md5 相等 ⇒ 既有 golden 不受本探针影响）"

# ---------------------------------------------------------------- 负控 N1：删调用 ⇒ ① 必红
t4_assert_eq "0" "$( cd "$LAB" && env -u NAO_STASH_ROOT bash "$REF/.agents/scripts/nao-fleet.sh" check 2>&1 | grep -cE '^  ! PRD 结构' || true )" \
  "N1 删掉探针调用 ⇒ 同一夹具 0 条提示（① 的判据非空转；还原即复绿）"

# ---------------------------------------------------------------- 负控 N2：去掉排除名单 ⇒ ⑥ 必红
N2="$T4_CACHE_DIR/lab36-n2-$$"
mkdir -p "$N2" && cp -r "$T4_ROOT/.agents" "$N2/.agents" || t4_bad "N2 夹具：复制 .agents 失败"
t4_assert_eq "1" "$(grep -c "e '\^  ! PRD 结构'" "$N2/.agents/scripts/nao-fleet.sh" || true)" "N2 负控锚点：原脚本排除名单含 PRD 提示前缀"
sed -i "s/ -e '\^  ! PRD 结构'//" "$N2/.agents/scripts/nao-fleet.sh"
t4_assert_eq "0" "$(grep -c "e '\^  ! PRD 结构'" "$N2/.agents/scripts/nao-fleet.sh" || true)" "N2 负控锚点：副本已去掉排除（变异生效）"
mkdir -p "$N2/docs/prds" && t36_mkprd "$N2/docs/prds/2026-11-18-missing-group.md" 4 0
OUT_N2="$( cd "$N2" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check 2>&1 )"
t4_assert_contains "$OUT_N2" "warn=" "N2 去掉排除名单 ⇒ 摘要出现 warn=（⑥ 必红 ⇒ 排除名单是承重的）"

# ---------------------------------------------------------------- 负控 N3：中和「不追溯」过滤 ⇒ ③ 必红
#   为什么不是「去掉空文件守卫」：0 字节文件即便没有守卫也会因「缺 10 个模块」被点名 ⇒ 该守卫
#   不是 ④ 的唯一成因，拿它做负控等于假演练。真正承重且唯一的是**日期过滤**（③ 的全部内容）。
N3="$T4_CACHE_DIR/lab36-n3-$$"
mkdir -p "$N3" && cp -r "$T4_ROOT/.agents" "$N3/.agents" || t4_bad "N3 夹具：复制 .agents 失败"
t4_assert_eq "1" "$(grep -c '\[\[ "\$d" < "\$since" \]\] && continue' "$N3/.agents/scripts/nao-fleet.sh" || true)" "N3 负控锚点：原脚本含「老日期跳过」一行"
sed -i 's/\[\[ "\$d" < "\$since" \]\] && continue/: 变异：过滤已中和/' "$N3/.agents/scripts/nao-fleet.sh"
t4_assert_eq "1" "$(grep -c '变异：过滤已中和' "$N3/.agents/scripts/nao-fleet.sh" || true)" "N3 负控锚点：副本过滤已中和（变异生效）"
mkdir -p "$N3/docs/prds" && t36_mkprd "$N3/docs/prds/2026-10-01-old-missing.md" 3 0
OUT_N3="$( cd "$N3" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$OUT_N3" "2026-10-01-old-missing.md" "N3 中和追溯过滤 ⇒ 老文件被报（③ 必红 ⇒ 过滤是承重的）"

rm -rf "$REF" "$N2" "$N3"
t4_exit 0
