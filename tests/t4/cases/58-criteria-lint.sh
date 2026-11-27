#!/usr/bin/env bash
# 用例 58 —— 判据体检 lint（T589 · Issue #253）
#
# 被测：`tests/t4/lib-criteria.sh`（只读探针，**不并入 `check`**）—— 按规格
#   `docs/T589-criteria-check/review.md` §一/§二 的形态实现 R1–R6，抽取按「### 分组切块 + 块内 Then」。
#
# 判据（规格 §四，写成能过的样子）：
#   ① 反例 `fixtures/criteria-lint/bad/b1..b6` ⇒ **6/6 命中**，且每条命中的**规则 id 与期望一一对应**
#   ② 合格 `fixtures/criteria-lint/good/g1..g5` ⇒ **0 命中**（禁为「都拦得住」放宽到误报）
#   ③ 含 `###` 块但**无 Then** ⇒ 输出「跳过 N 块（无 Then）」且 **rc≠0**（抽取器失效不得静默）
#   ④ 围栏内的 Then 不参与判定（与 `check` 既有探针对齐）
#   ⑤ 变异负控 3 条：去掉 R2 的抑制词 / 去掉 R6 的抑制词 / 关掉 R5 规则 ⇒ 各自必红或必漏
#
# 后端无关：纯文件读取（零网络、不 exec 真 pi、不起 server）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-criteria.sh"

FIX="$T4_ROOT/tests/t4/fixtures/criteria-lint"
t4_assert_file "$FIX/bad/b1-aggregate-axis.md" "前置：反例夹具存在（docs/T589 规格同源复制）"

# ---------------------------------------------------------------- ① 反例 6/6，规则 id 一一对应
c58_bad_case() { # <文件> <期望规则 id>
  local f="$1" want="$2" out rc
  out="$(criteria_lint_file "$FIX/bad/$f")"; rc=$?
  t4_assert_eq "0" "$rc" "① $f：探针 rc=0（有命中但不是错误）"
  t4_assert_contains "$out" "✗ $f" "① $f：输出点名文件（逐条可读）"
  t4_assert_contains "$out" "$want" "① $f：命中 $want"
  t4_assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^✗' || true)" "① $f：恰 1 条命中（不重复报同一规则）"
}
c58_bad_case b1-aggregate-axis.md   "R1"
c58_bad_case b2-base-axis.md        "R2"
c58_bad_case b3-empty-scan.md       "R3"
c58_bad_case b4-truncated-semantics.md "R4"
c58_bad_case b5-innertext-semantics.md "R5"
c58_bad_case b6-unstable-sample.md  "R6"
t4_assert_eq "6" "$(criteria_lint_dir "$FIX/bad" | grep -c '^✗' || true)" "① 反例合计 6/6 命中"

# ---------------------------------------------------------------- ② 合格 5/5 ⇒ 0 误报
for g in g1-scope-declared g2-literal-count g3-visible-text g4-stable-sample g5-anti-vacuous; do
  out="$(criteria_lint_file "$FIX/good/$g.md")"
  t4_assert_eq "" "$out" "② $g：0 命中（合格对照不误报）"
done
t4_assert_eq "0" "$(criteria_lint_dir "$FIX/good" | grep -c '^✗' || true)" "② 合格合计 0 命中"

# ---------------------------------------------------------------- ③ 无 Then 的块 ⇒ 跳过并 rc≠0
TMP58="$T4_CACHE_DIR/c58-$$"; rm -rf "$TMP58"; mkdir -p "$TMP58"
cat > "$TMP58/no-then.md" <<'EOF'
### 主路径
Given 只有 Given 没有结论
When 跑探针
EOF
out="$(criteria_lint_file "$TMP58/no-then.md")"; rc=$?
t4_assert_ne "0" "$rc" "③ 无 Then 的块：rc≠0（抽取器失效不得静默）"
t4_assert_contains "$out" "跳过 1 块（无 Then）" "③ 显式打印跳过计数（禁静默漏扫）"

# ---------------------------------------------------------------- ④ 围栏内的 Then 不参与判定
cat > "$TMP58/fenced.md" <<'EOF'
### 主路径
Given 文档里贴了一段反例
When 跑探针
Then 正常结论

```text
Then 值仍为 1229，差值 0
```
EOF
t4_assert_eq "" "$(criteria_lint_file "$TMP58/fenced.md")" "④ 围栏内的 Then 不参与判定（先剥围栏再抽）"

# ---------------------------------------------------------------- ⑤ 变异负控（3 条，判据承重）
# ⑤-a R2 的抑制词承重：给 b2 加「同扫描面」⇒ 不再命中 R2（抑制词真的在压）
c58_mut="$TMP58/mut-b2.md"
t4_assert_eq "0" "$(grep -c '同扫描面' "$FIX/bad/b2-base-axis.md" || true)" "⑤-a 负控锚点：反例原文无抑制词"
sed 's/统计血统三类/统计血统三类（同扫描面）/' "$FIX/bad/b2-base-axis.md" > "$c58_mut"
t4_assert_eq "1" "$(grep -c '同扫描面' "$c58_mut" || true)" "⑤-a 负控锚点：副本已加抑制词（变异生效）"
t4_assert_eq "" "$(criteria_lint_file "$c58_mut")" "⑤-a 加抑制词 ⇒ R2 不再命中（抑制词承重）"

# ⑤-b R6 的抑制词承重：删掉 g4 的「中点/采样点/坐标」⇒ R6 命中
sed 's/顶边\*\*中点\*\*与距左 20px 三点（采样点 x=L+20..22, y=T+0.5）/顶边行首三点/' \
  "$FIX/good/g4-stable-sample.md" > "$TMP58/mut-g4.md"
t4_assert_eq "0" "$(grep -cE '中点|采样点|x=|y=' "$TMP58/mut-g4.md" || true)" "⑤-b 负控锚点：副本已去掉 R6 抑制词（变异生效）"
t4_assert_contains "$(criteria_lint_file "$TMP58/mut-g4.md")" "R6" "⑤-b 去掉抑制词 ⇒ R6 命中（抑制词承重）"

# ⑤-c 关掉 R5 规则 ⇒ b5 必漏（规则实现承重）
NEGLIB="$TMP58/lib-off.sh"
sed 's/^: "${c58_r5_enabled:=1}"$/: "${c58_r5_enabled:=0}"/' "$T4_ROOT/tests/t4/lib-criteria.sh" > "$NEGLIB"
t4_assert_eq "0" "$(grep -c '^: "${c58_r5_enabled:=1}"$' "$NEGLIB" || true)" \
  "⑤-c 负控锚点：副本已把 R5 关掉（变异生效）"
OUT_OFF="$( bash -c 'source "$1/tests/t4/lib.sh" >/dev/null 2>&1; source "$2"; criteria_lint_file "$3"' _ "$T4_ROOT" "$NEGLIB" "$FIX/bad/b5-innertext-semantics.md" 2>/dev/null || true )"
t4_assert_not_contains "$OUT_OFF" "R5" "⑤-c 关掉 R5 ⇒ b5 不再命中 R5（规则实现承重）"

rm -rf "$TMP58"
t4_exit 0
