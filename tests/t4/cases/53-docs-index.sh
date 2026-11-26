#!/usr/bin/env bash
# 用例 53 —— docs 一级索引一致性探针（`check_docs_index`）的持久用例（T579 · #237）
#
# 被测：`.agents/scripts/fleet/lib/check.sh::check_docs_index`（**warn-only**：不计 warn、不改 rc）。
# 判据（八条，PRD AC1/AC2/AC3/AC5/AC7 + ADR 决策 3/4）：
#   ① 主路径：目录 + 行齐 ⇒ 零输出、rc=0
#   ② AC2 未登记：目录存在但索引无行 ⇒ 点名该目录
#   ③ AC3 幽灵行：索引行指向不存在目录 ⇒ 点名该行
#   ④ AC5 版本重复：同一版本两行（指向不同目录）⇒ 点名重复
#   ⑤ 文法：单元格多出（列数 ≠ 表头）⇒ 点名列数（不静默跳过）
#   ⑥ AC7 老仓：只有 `docs/prds/*.md`、无索引无任务目录 ⇒ 零输出、rc=0
#   ⑦ 本仓：探针零输出 + `check` 输出与「探针关闭」逐字一致（md5）
#   ⑧ 半启用（ADR 决策 3）：任务目录已有契约产物但索引缺一段逐字标题 ⇒ 必须提示（删索引不得静默免责）
#
# 负控（三条，全部走「副本改一处 ⇒ 判据必红」）：
#   N1 删掉 `check_docs_index` 调用 ⇒ ② 的提示必消失（判据非空转）
#   N2 把 `'^  ! 索引'` 从摘要计数的排除名单去掉 ⇒ ⑦ 的「不计 warn」必红（`warn=` 出现）
#   N3 取反幽灵行判据 ⇒ 合法行也被报「不存在的目录」（③ 的判据承重）
#
# 后端无关（只跑 bash + 夹具 `.agents`，不建 tmux/herdr；不 exec 真 pi）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET_REAL="$T4_ROOT/.agents/scripts/nao-fleet.sh"
t4_assert_file "$FLEET_REAL" "前置：被测脚本存在"

LAB="$T4_CACHE_DIR/lab53-$$"
mkdir -p "$LAB/docs" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

t53_exit_trap() {
  local rc=$?
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t53_exit_trap EXIT

c53_out() { # <lab> [check 参数...]
  local lab="$1"; shift
  ( cd "$lab" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check "$@" 2>&1 )
}
c53_agg() { printf '%s\n' "$1" | grep -cE '^  ! 索引' || true; }          # 聚合提示行数（-v 下恰 1）
c53_det() { printf '%s\n' "$1" | grep -cE '^  · 索引：' || true; }        # -v 明细行数

# ---------------------------------------------------------------- 夹具：三段落齐 + 目录/版本/ADR 三处一致
c53_mkindex() { # <lab> · 基准索引（成功态：一处不一致都没有）
  cat > "$1/docs/README.md" <<'EOF'
# docs 索引（用例夹具）

## 一、任务批次

| 任务号 | 目录 | 一句话 | Issue/PR |
| :--- | :--- | :--- | :--- |
| T579 | `docs/T579-fixture/` | 夹具任务 | — |

## 二、版本

| 版本 | 权威路径 | 发布日期 |
| :--- | :--- | :--- |
| v0.1.0 | `docs/T579-fixture/release-notes-v0.1.0.md` | 2026-11-27 |

## 三、决策时间线

| 日期 | 决策 | 任务号 | 状态 |
| :--- | :--- | :--- | :--- |
| 2026-11-27 | [夹具决策](T579-fixture/adr-fixture.md) | T579 | 已接受（待落地） |
EOF
}
mkdir -p "$LAB/docs/T579-fixture" "$LAB/docs/prds"
printf '# 夹具 PRD\n' > "$LAB/docs/T579-fixture/prd.md"
printf '# 夹具 ADR\n' > "$LAB/docs/T579-fixture/adr-fixture.md"
printf '# 夹具发版说明\n' > "$LAB/docs/T579-fixture/release-notes-v0.1.0.md"
c53_mkindex "$LAB"

# ---------------------------------------------------------------- ① 主路径 ⇒ 零输出 + rc=0
OUT1="$(c53_out "$LAB")"; RC1=$?
t4_assert_eq "0" "$RC1" "① 主路径：目录/版本/ADR 三处一致 ⇒ check rc=0"
t4_assert_eq "0" "$(c53_agg "$OUT1")" "① 主路径：零输出（无聚合提示）"
OUT1V="$(c53_out "$LAB" -v)"
t4_assert_contains "$OUT1V" "✓ 索引：任务 1 行 / 版本 1 行 / 决策 1 行" "① -v 索引小节回显已登记行数（AC1）"
t4_assert_eq "0" "$(c53_det "$OUT1V")" "① 主路径：-v 无明细（无不一致项）"

# ---------------------------------------------------------------- ② AC2 未登记 ⇒ 点名
mkdir -p "$LAB/docs/T998-ghost"
printf '# 幽灵任务 PRD\n' > "$LAB/docs/T998-ghost/prd.md"
OUT2="$(c53_out "$LAB")"; RC2=$?
t4_assert_eq "0" "$RC2" "② 未登记：仍 rc=0（warn-only 不改 rc）"
t4_assert_eq "1" "$(c53_agg "$OUT2")" "② 未登记：恰 1 条聚合提示"
OUT2V="$(c53_out "$LAB" -v)"
t4_assert_contains "$OUT2V" "docs/T998-ghost/ 未在任务段登记" "② 点名未登记目录（AC2）"
rm -rf "$LAB/docs/T998-ghost"
t4_assert_eq "0" "$(c53_agg "$(c53_out "$LAB")")" "② 删掉目录 ⇒ 归零（双向可复绿）"

# ---------------------------------------------------------------- ③ AC3 幽灵行 ⇒ 点名
c53_mkindex "$LAB"
# 插在任务段数据行之后（追加到文件末尾会落进「决策时间线」段，变成另一个判据）
sed -i '/^| T579 | `docs\/T579-fixture\/` | 夹具任务 | — |$/a | T997 | `docs/T997-absent/` | 幽灵行 | — |' "$LAB/docs/README.md"
OUT3V="$(c53_out "$LAB" -v)"
t4_assert_contains "$OUT3V" "docs/T997-absent 指向不存在的目录" "③ 幽灵行：点名「指向不存在的目录」（AC3）"
c53_mkindex "$LAB"

# ---------------------------------------------------------------- ④ AC5 版本重复 ⇒ 点名
mkdir -p "$LAB/docs/T580-fixture"
printf '# 二号夹具 PRD\n' > "$LAB/docs/T580-fixture/prd.md"
printf '# 重复发版说明\n' > "$LAB/docs/T580-fixture/release-notes-v0.1.0.md"
sed -i 's#^| T579 | `docs/T579-fixture/` | 夹具任务 | — |$#| T579 | `docs/T579-fixture/` | 夹具任务 | — |\n| T580 | `docs/T580-fixture/` | 二号夹具 | — |#' "$LAB/docs/README.md"
sed -i 's#^| v0.1.0 | `docs/T579-fixture/release-notes-v0.1.0.md` | 2026-11-27 |$#| v0.1.0 | `docs/T579-fixture/release-notes-v0.1.0.md` | 2026-11-27 |\n| v0.1.0 | `docs/T580-fixture/release-notes-v0.1.0.md` | 2026-11-27 |#' "$LAB/docs/README.md"
OUT4V="$(c53_out "$LAB" -v)"
t4_assert_contains "$OUT4V" "版本重复登记 2 次：v0.1.0" "④ 版本重复：点名重复版本（AC5）"
# 还原：删两行与 T580 目录
sed -i '/^| T580 | `docs\/T580-fixture\/` | 二号夹具 | — |$/d' "$LAB/docs/README.md"
sed -i '/^| v0.1.0 | `docs\/T580-fixture\/release-notes-v0.1.0.md` | 2026-11-27 |$/d' "$LAB/docs/README.md"
rm -rf "$LAB/docs/T580-fixture"
t4_assert_eq "0" "$(c53_agg "$(c53_out "$LAB")")" "④ 还原后归零（重复是唯一成因）"

# ---------------------------------------------------------------- ⑤ 文法：列数不符 ⇒ 点名（不静默跳过）
c53_mkindex "$LAB"
sed -i '/^| T579 | `docs\/T579-fixture\/` | 夹具任务 | — |$/a | T581 | `docs/T581-x/` | 多一列 | — | 多余 |' "$LAB/docs/README.md"
OUT5V="$(c53_out "$LAB" -v)"
t4_assert_contains "$OUT5V" "任务批次 段列数 5 ≠ 4" "⑤ 文法非法：点名列数（单元格禁 \`|\`）"
c53_mkindex "$LAB"

# ---------------------------------------------------------------- ⑥ AC7 老仓 ⇒ 零输出 + rc=0
OLD="$T4_CACHE_DIR/lab53-old-$$"
mkdir -p "$OLD/docs/prds" && cp -r "$T4_ROOT/.agents" "$OLD/.agents" || t4_bad "⑥ 夹具：建老仓失败"
printf '# 老 PRD\n' > "$OLD/docs/prds/2026-11-01-legacy.md"
OUT6="$(c53_out "$OLD")"; RC6=$?
t4_assert_eq "0" "$RC6" "⑥ 老仓（只有 docs/prds/）：check rc=0"
t4_assert_eq "0" "$(c53_agg "$OUT6")" "⑥ 老仓：索引断言零输出（不因新规矩报错 · AC7）"
t4_assert_not_contains "$OUT6" "半启用" "⑥ 老仓无任务目录 ⇒ 不报半启用（不误伤）"

# ---------------------------------------------------------------- ⑧ 半启用：任务目录有契约产物但缺一段标题 ⇒ 必提示
HALF="$T4_CACHE_DIR/lab53-half-$$"
mkdir -p "$HALF/docs/T900-half" && cp -r "$T4_ROOT/.agents" "$HALF/.agents" || t4_bad "⑧ 夹具：建半启用仓失败"
printf '# 半启用 PRD\n' > "$HALF/docs/T900-half/prd.md"
c53_mkindex "$HALF"
sed -i '/^## 三、决策时间线$/d' "$HALF/docs/README.md"
OUT8="$(c53_out "$HALF")"
t4_assert_contains "$OUT8" "半启用" "⑧ 删索引一段标题 ⇒ 半启用提示必现（删索引不得静默免责）"
t4_assert_contains "$OUT8" '缺逐字标题 `## 三、决策时间线`' "⑧ 点名缺的那一段标题"

# ---------------------------------------------------------------- ⑦ 本仓：零输出 + 与「探针关闭」逐字一致
REF="$T4_CACHE_DIR/lab53-ref-$$"
mkdir -p "$REF" && cp -r "$T4_ROOT/.agents" "$REF/.agents" || t4_bad "⑦ 夹具：复制 .agents 失败"
REF_CHECK="$(t4_fleet_file_for "$REF/.agents/scripts" cmd_check)"
t4_assert_ne "" "${REF_CHECK:-}" "⑦ 夹具：定位到 cmd_check 所在模块"
sed -i '/^  check_docs_index || true$/d' "$REF_CHECK"
t4_assert_eq "0" "$(grep -c 'check_docs_index || true' "$REF_CHECK" || true)" \
  "⑦ 负控锚点：副本已删掉探针调用（自证变异生效）"
OUT_REAL="$( cd "$T4_ROOT" && env -u NAO_STASH_ROOT bash "$FLEET_REAL" check 2>&1 )"
OUT_OFF="$( cd "$T4_ROOT" && env -u NAO_STASH_ROOT bash "$REF/.agents/scripts/nao-fleet.sh" check 2>&1 )"
t4_assert_eq "0" "$(c53_agg "$OUT_REAL")" "⑦ 本仓：探针零输出（docs/README.md 与目录/版本/ADR 三处一致）"
t4_assert_eq "$(printf '%s\n' "$OUT_OFF" | md5sum | awk '{print $1}')" \
  "$(printf '%s\n' "$OUT_REAL" | md5sum | awk '{print $1}')" \
  "⑦ 本仓：check 输出与「探针关闭」逐字一致（md5 相等 ⇒ 既有 golden 不受本探针影响）"

# ---------------------------------------------------------------- 负控 N1：删调用 ⇒ ② 必红（判据非空转）
mkdir -p "$LAB/docs/T998-ghost"
printf '# 幽灵任务 PRD\n' > "$LAB/docs/T998-ghost/prd.md"
t4_assert_eq "0" "$( cd "$LAB" && env -u NAO_STASH_ROOT bash "$REF/.agents/scripts/nao-fleet.sh" check -v 2>&1 | grep -cE '^  ! 索引' || true )" \
  "N1 删掉探针调用 ⇒ 同一夹具 0 条提示（② 的判据非空转；还原即复绿）"
rm -rf "$LAB/docs/T998-ghost"

# ---------------------------------------------------------------- 负控 N2：去掉排除名单 ⇒ warn= 必现
N2="$T4_CACHE_DIR/lab53-n2-$$"
mkdir -p "$N2" && cp -r "$T4_ROOT/.agents" "$N2/.agents" || t4_bad "N2 夹具：复制 .agents 失败"
t4_assert_eq "1" "$(grep -c "e '\^  ! 索引'" "$N2/.agents/scripts/nao-fleet.sh" || true)" \
  "N2 负控锚点：原脚本排除名单含索引提示前缀"
sed -i "s/ -e '\^  ! 索引'//" "$N2/.agents/scripts/nao-fleet.sh"
t4_assert_eq "0" "$(grep -c "e '\^  ! 索引'" "$N2/.agents/scripts/nao-fleet.sh" || true)" \
  "N2 负控锚点：副本已去掉排除（变异生效）"
mkdir -p "$N2/docs" && cp "$LAB/docs/README.md" "$N2/docs/README.md" \
  && cp -r "$LAB/docs/T579-fixture" "$N2/docs/T579-fixture" \
  && mkdir -p "$N2/docs/T998-ghost" && printf '# x\n' > "$N2/docs/T998-ghost/prd.md"
OUT_N2="$( cd "$N2" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check 2>&1 )"
t4_assert_contains "$OUT_N2" "warn=" "N2 去掉排除名单 ⇒ 摘要出现 warn=（⑦ 必红 ⇒ 排除名单是承重的）"

# ---------------------------------------------------------------- 负控 N3：取反幽灵行判据 ⇒ 合法行也报「不存在」
N3="$T4_CACHE_DIR/lab53-n3-$$"
mkdir -p "$N3" && cp -r "$T4_ROOT/.agents" "$N3/.agents" || t4_bad "N3 夹具：复制 .agents 失败"
N3_CHECK="$(t4_fleet_file_for "$N3/.agents/scripts" check_docs_index)"
t4_assert_ne "" "${N3_CHECK:-}" "N3 夹具：定位到索引探针所在模块"
t4_assert_eq "1" "$(grep -c 'if (!inlist(TD\[i\], DL, nD))' "$N3_CHECK" || true)" \
  "N3 负控锚点：原脚本含「幽灵行」判据"
sed -i 's/if (!inlist(TD\[i\], DL, nD))/if (inlist(TD[i], DL, nD))/' "$N3_CHECK"
t4_assert_eq "1" "$(grep -c 'if (inlist(TD\[i\], DL, nD))' "$N3_CHECK" || true)" \
  "N3 负控锚点：副本判据已取反（变异生效）"
mkdir -p "$N3/docs" && cp -r "$LAB/docs/T579-fixture" "$N3/docs/T579-fixture"
c53_mkindex "$N3"
OUT_N3="$( cd "$N3" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$OUT_N3" "docs/T579-fixture 指向不存在的目录" \
  "N3 取反幽灵判据 ⇒ 合法目录被报「不存在」（③ 必红 ⇒ 判据承重）"

rm -rf "$REF" "$N2" "$N3" "$OLD" "$HALF"
t4_exit 0
