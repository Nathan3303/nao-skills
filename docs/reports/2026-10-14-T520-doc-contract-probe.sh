#!/usr/bin/env bash
# T520 文档契约一次性探针（只读 · 幂等 · 不进 tests/）
#
# 用途：机械核验 PRD docs/prds/2026-10-14-doc-templates-convention.md §七 AC1–AC4
#      与 arch 定稿 docs/reports/2026-10-14-T520-arch-review.md §一/§三。
#
# 用法：
#   bash docs/reports/2026-10-14-T520-doc-contract-probe.sh           # 全量（结构 + 门禁 check/npm test/t4）
#   bash docs/reports/2026-10-14-T520-doc-contract-probe.sh --fast    # 仅结构断言（跳过门禁）
#   bash docs/reports/2026-10-14-T520-doc-contract-probe.sh --negctl  # 负控自证：/tmp 造反例 ⇒ 探针必须 FAIL
#
# 只读保证：不写仓库任何文件；负控仅写 ${TMPDIR:-/tmp}/t520-negctl（PROBE_NEGDIR 可覆盖）。
# 幂等保证：连跑两次输出逐字一致（门禁只回放解析后的精确数字，不回放过程日志）。
# 覆盖变量：PROBE_ADR_EXAMPLE / PROBE_ADR_INDEX_EXAMPLE / PROBE_ADR_INDEX_REAL /
#   PROBE_DELIVERABLE_DOCS / PROBE_ARCH_PATTERNS / PROBE_ARCH_CARD / PROBE_FIRST_ADR /
#   PROBE_DIFF_BASE / PROBE_DIFF_REF / PROBE_NEGDIR。
set -uo pipefail

SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF_ABS")/../.." && pwd)"

FAST=false
NEGCTL=false
for a in "$@"; do
  case "$a" in
    --fast)    FAST=true ;;
    --negctl)  NEGCTL=true ;;
    -h|--help) sed -n '2,20p' "$SELF_ABS"; exit 0 ;;
    *) printf '未知参数：%s\n' "$a" >&2; exit 2 ;;
  esac
done

ADR_EXAMPLE="${PROBE_ADR_EXAMPLE:-$ROOT/.agents/templates/adr.md.example}"
ADR_INDEX_EXAMPLE="${PROBE_ADR_INDEX_EXAMPLE:-$ROOT/.agents/templates/adr-index.md.example}"
ADR_INDEX_REAL="${PROBE_ADR_INDEX_REAL:-$ROOT/docs/adr/README.md}"
DELIVERABLE_DOCS="${PROBE_DELIVERABLE_DOCS:-$ROOT/.agents/checklists/deliverable-docs.md}"
ARCH_PATTERNS="${PROBE_ARCH_PATTERNS:-$ROOT/.agents/skills/arch-patterns.md}"
ARCH_CARD="${PROBE_ARCH_CARD:-$ROOT/.agents/prompts/architecture-designer.md}"
FIRST_ADR="${PROBE_FIRST_ADR:-$ROOT/docs/adr/2026-10-14-adr-structure-contract.md}"
DIFF_BASE="${PROBE_DIFF_BASE:-main}"
DIFF_REF="${PROBE_DIFF_REF:-nao/doc-templates}"
SELF_REL="docs/reports/2026-10-14-T520-doc-contract-probe.sh"

PASS=0; FAIL=0; SKIP=0
pass(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
skip(){ SKIP=$((SKIP+1)); printf 'SKIP  %s\n' "$1"; }

CANON=(背景 决策 理由 对照过的备选模式 后果与风险 限制与已知边界 相关指针 参考来源)
MUST=(背景 决策 理由 对照过的备选模式 参考来源)
FORBIDDEN=(实施闸门 接线清单 交接 备选方案)

noncomment_text(){ printf '%s\n' "$1" | awk '!/<!--/ && !/-->/ && !/⛔/'; }
section_of(){
  awk -v pat="$2" '
    $0 ~ pat { f=1 }
    f && /^## / && $0 !~ pat { f=0 }
    f { print }
  ' "$1"
}
canon_idx(){
  local h="$1" i
  for i in "${!CANON[@]}"; do [[ "${CANON[$i]}" == "$h" ]] && { printf '%s' "$i"; return; }; done
  printf '%s' -1
}
forbidden_in_text(){
  local t="$1" w out=""
  for w in "${FORBIDDEN[@]}"; do case "$t" in *"$w"*) out="$out $w" ;; esac; done
  printf '%s' "${out# }"
}
row_cells(){ awk -F'|' '{for(i=2;i<NF;i++){gsub(/^[ \t]+|[ \t]+$/,"",$i); print $i}}' <<<"$1"; }

# ---------------------------------------------------------------------------
# 结构契约：ADR 骨架 / 首实例通用断言
# 12 项：必写 5 · 白名单 · 单调 · 末节 · 头部字段数 · 头四字段 · 禁词 · ≤60 行
# ---------------------------------------------------------------------------
check_skeleton(){
  local label="$1" f="$2"
  if [[ ! -f "$f" ]]; then fail "$label 文件不存在：$f"; return; fi

  local h idx prev=-1 last=-1 ok=1 subset_ok=1
  local -a hdrs=()
  mapfile -t hdrs < <(grep -E '^## ' "$f" | sed 's/^## //')

  for h in "${MUST[@]}"; do
    if grep -Fxq "## $h" "$f"; then pass "$label 必写节在：## $h"; else fail "$label 缺必写节：## $h"; fi
  done

  for h in "${hdrs[@]}"; do
    idx="$(canon_idx "$h")"
    if [[ "$idx" -lt 0 ]]; then subset_ok=0; fail "$label 标题不在白名单：## $h"; fi
  done
  [[ "$subset_ok" -eq 1 ]] && pass "$label 标题集合 ⊆ 8 个白名单"

  for h in "${hdrs[@]}"; do
    idx="$(canon_idx "$h")"
    if [[ "$idx" -ge 0 ]]; then
      [[ "$idx" -le "$prev" ]] && ok=0
      prev="$idx"; last="$idx"
    fi
  done
  [[ "$ok" -eq 1 ]] && pass "$label 节序单调递增" || fail "$label 节序非单调（重复或逆序）"
  [[ "$last" -eq 7 ]] && pass "$label 参考来源恒为末节" || fail "$label 末节不是 参考来源（末位索引=$last）"

  local hdr nf fld c fld_ok=1
  hdr="$(awk '{if ($0 ~ /^## /) exit; print}' "$f")"
  nf="$(printf '%s\n' "$hdr" | grep -cE '^- [^： ]+：')"
  [[ "$nf" -eq 4 ]] && pass "$label 头部恰 4 字段" || fail "$label 头部字段数=$nf（应 4）"
  for fld in 状态 更新 Owner 指针; do
    c="$(printf '%s\n' "$hdr" | grep -cE "^- ${fld}：")"
    [[ "$c" -eq 1 ]] || fld_ok=0
  done
  [[ "$fld_ok" -eq 1 ]] && pass "$label 头部四字段齐（状态/更新/Owner/指针）" || fail "$label 头部四字段缺失或重复"

  local hits
  hits="$(forbidden_in_text "$(noncomment_text "$(cat "$f")")")"
  [[ -z "$hits" ]] && pass "$label 正文无禁词（实施闸门/接线清单/交接/备选方案）" || fail "$label 正文命中禁词：$hits"

  local lines
  lines="$(wc -l < "$f" | tr -d ' ')"
  [[ "$lines" -le 60 ]] && pass "$label ≤60 行（实际 $lines）" || fail "$label 超 60 行（实际 $lines）"
}

# ---------------------------------------------------------------------------
# 负控：/tmp 造反例，子探针必须 FAIL（证伪能力自检）
# ---------------------------------------------------------------------------
negctl_run(){
  local dir="${PROBE_NEGDIR:-${TMPDIR:-/tmp}/t520-negctl}"
  rm -rf "$dir"; mkdir -p "$dir"
  local bad_word="$dir/adr.bad-word.md" bad_order="$dir/adr.bad-order.md"
  cp "$ADR_EXAMPLE" "$bad_word"
  printf '\n- 备选方案：<注入反例（禁词）>\n' >> "$bad_word"
  cp "$ADR_EXAMPLE" "$bad_order"
  sed -i '/^## 决策$/i ## 限制与已知边界' "$bad_order"

  local np=0 nf=0 pair name file out rc cnt
  for pair in "禁词注入:$bad_word" "节序打乱:$bad_order"; do
    name="${pair%%:*}"; file="${pair#*:}"
    out="$(PROBE_ADR_EXAMPLE="$file" PROBE_NEGCTL_CHILD=1 bash "$SELF_ABS" --fast 2>&1)"; rc=$?
    cnt="$(printf '%s\n' "$out" | grep -oE 'FAIL=[0-9]+' | tail -1 | cut -d= -f2)"
    printf '  反例[%s] 临时文件=%s 子探针 rc=%s FAIL=%s\n' "$name" "$file" "$rc" "${cnt:-?}"
    printf '%s\n' "$out" | grep -E '^FAIL ' | sed 's/^/    /'
    if [[ "$rc" -ne 0 && "${cnt:-0}" -ge 1 ]]; then
      np=$((np+1)); printf '  ⇒ 负控[%s] PASS（探针正确 FAIL）\n' "$name"
    else
      nf=$((nf+1)); printf '  ⇒ 负控[%s] FAIL（探针未报错，证伪能力不足）\n' "$name"
    fi
  done
  printf '\nNEGCTL: PASS=%d FAIL=%d\n' "$np" "$nf"
  exit $(( nf > 0 ? 1 : 0 ))
}

if $NEGCTL; then negctl_run; fi

# ---------------------------------------------------------------------------
# AC1 骨架单源
# ---------------------------------------------------------------------------
printf '== AC1 骨架单源（adr.md.example）==\n'
[[ -f "$ADR_EXAMPLE" ]] && pass "AC1 adr.md.example 存在" || fail "AC1 adr.md.example 不存在：$ADR_EXAMPLE"
check_skeleton "AC1 adr.md.example" "$ADR_EXAMPLE"

sec4="$(section_of "$DELIVERABLE_DOCS" '^## 四、ADR')"
[[ "$sec4" == *"templates/adr.md.example"* ]] \
  && pass "AC1 deliverable-docs §四 含骨架指针 templates/adr.md.example" \
  || fail "AC1 deliverable-docs §四 缺骨架指针"
grep -Fq 'templates/adr.md.example' "$ARCH_PATTERNS" \
  && pass "AC1 arch-patterns.md 含骨架指针 templates/adr.md.example" \
  || fail "AC1 arch-patterns.md 缺骨架指针"

# ---------------------------------------------------------------------------
# AC2 职责边界（下沉）
# ---------------------------------------------------------------------------
printf '== AC2 职责边界（deliverable-docs §四 + arch-patterns ## ADR 模板）==\n'
[[ -n "$sec4" ]] && pass "AC2 deliverable-docs §四 段非空" || fail "AC2 deliverable-docs §四 段为空（节名漂移？）"
[[ "$sec4" == *"docs/reports/<编号>-arch-review.md"* ]] \
  && pass "AC2 §四 下沉落点 = docs/reports/<编号>-arch-review.md" \
  || fail "AC2 §四 缺下沉落点"
{ [[ "$sec4" == *"禁写"* ]] && [[ "$sec4" == *"下沉"* ]]; } \
  && pass "AC2 §四 含禁写/下沉条款" \
  || fail "AC2 §四 缺禁写/下沉条款"
[[ "$sec4" == *"对照模式清单"* ]] && pass "AC2 §四 已称「对照模式清单」" || fail "AC2 §四 未称「对照模式清单」"
[[ "$sec4" != *"对照模式表"* ]] && pass "AC2 §四 无「对照模式表」残留" || fail "AC2 §四 仍含「对照模式表」"

rem="$(printf '%s' "$sec4" | tr '\n' ' ')"; oks=1; stuck=""
for tok in 背景 决策 理由 对照模式清单 后果与风险 限制与已知边界 相关指针 参考来源; do
  if [[ "$rem" == *"$tok"* ]]; then rem="${rem#*"$tok"}"; else oks=0; stuck="$tok"; break; fi
done
[[ "$oks" -eq 1 ]] && pass "AC2 §四 节序与 arch 定稿一致" || fail "AC2 §四 节序不符（卡在 $stuck）"

sec_adr="$(section_of "$ARCH_PATTERNS" '^## ADR 模板')"
[[ -n "$sec_adr" ]] && pass "AC2 arch-patterns ## ADR 模板 段非空" || fail "AC2 arch-patterns 缺 ## ADR 模板 段"
hits="$(forbidden_in_text "$(noncomment_text "$sec_adr")")"
[[ -z "$hits" ]] && pass "AC2 arch-patterns ## ADR 模板 段无禁词" || fail "AC2 arch-patterns ## ADR 模板 段命中禁词：$hits"

# ---------------------------------------------------------------------------
# AC3 索引模板与列宽
# ---------------------------------------------------------------------------
printf '== AC3 索引模板与列宽 ==\n'
[[ -f "$ADR_INDEX_EXAMPLE" ]] && pass "AC3 adr-index.md.example 存在" || fail "AC3 adr-index.md.example 不存在：$ADR_INDEX_EXAMPLE"
hdr_line="$(grep -m1 '^|' "$ADR_INDEX_EXAMPLE" 2>/dev/null || true)"
hcells=(); if [[ -n "$hdr_line" ]]; then mapfile -t hcells < <(row_cells "$hdr_line"); fi
if [[ "${#hcells[@]}" -eq 4 && "${hcells[0]}" == 日期 && "${hcells[1]}" == 主题 && "${hcells[2]}" == 决策 && "${hcells[3]}" == 状态 ]]; then
  pass "AC3 索引模板表头恰 4 列（日期/主题/决策/状态）"
else
  fail "AC3 索引模板表头非 4 列或名称不符（列数=${#hcells[@]}）"
fi

rmax=0; rmaxcell=""; rows=0; rviol=0; colbad=0
while IFS= read -r line; do
  [[ "$line" == \|* ]] || continue
  cells=(); mapfile -t cells < <(row_cells "$line")
  [[ "${cells[0]:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
  rows=$((rows+1))
  if [[ "${#cells[@]}" -ne 4 ]]; then colbad=$((colbad+1)); continue; fi
  L=${#cells[2]}
  (( L > rmax )) && { rmax=$L; rmaxcell="${cells[2]}"; }
  (( L > 20 )) && rviol=$((rviol+1))
done < "$ADR_INDEX_REAL"
[[ "$colbad" -eq 0 ]] && pass "AC3 README 数据行均 4 列（$rows 行）" || fail "AC3 README 有 $colbad 行列数≠4"
if [[ "$rviol" -eq 0 ]]; then
  pass "AC3 README 决策列 ≤20 字（最大值=$rmax：「$rmaxcell」）"
else
  fail "AC3 README 决策列超 20 字：$rviol 行（最大值=$rmax：「$rmaxcell」）"
fi

sec11="$(section_of "$ARCH_CARD" '^## 十一、归档')"
[[ "$sec11" == *"adr-index.md.example"* ]] && pass "AC3 arch 卡 §十一 含索引模板指针" || fail "AC3 arch 卡 §十一 缺索引模板指针"
[[ "$sec11" == *"adr.md.example"* ]] && pass "AC3 arch 卡 §十一 含骨架指针" || fail "AC3 arch 卡 §十一 缺骨架指针"
grep -qE '^version: 12$' "$ARCH_CARD" && pass "AC3 arch 卡 version: 12" || fail "AC3 arch 卡 version ≠ 12"

# ---------------------------------------------------------------------------
# AC4 不追溯 + 门禁
# ---------------------------------------------------------------------------
printf '== AC4 不追溯（既有 7 篇 diff 零命中）+ 首实例 ==\n'
if git -C "$ROOT" rev-parse --verify -q "$DIFF_REF" >/dev/null; then
  base_adrs="$(git -C "$ROOT" ls-tree --name-only "$DIFF_BASE:docs/adr/" 2>/dev/null | grep -E '^2026-.*\.md$' || true)"
  nbase="$(printf '%s\n' "$base_adrs" | grep -c . || true)"
  [[ "$nbase" -eq 7 ]] && pass "AC4 基线既有 ADR = 7 篇" || fail "AC4 基线既有 ADR 数=$nbase（应 7）"
  arr=(); while IFS= read -r x; do [[ -n "$x" ]] && arr+=("docs/adr/$x"); done <<< "$base_adrs"
  if [[ "${#arr[@]}" -gt 0 ]]; then
    do_lines="$(git -C "$ROOT" diff "$DIFF_BASE...$DIFF_REF" -- "${arr[@]}")"
  else
    do_lines=""
  fi
  [[ -z "$do_lines" ]] && pass "AC4 既有 7 篇 ADR diff 零命中" \
    || fail "AC4 既有 ADR 被改动（$(printf '%s\n' "$do_lines" | grep -c '^diff --git') 处）"
else
  fail "AC4 分支/引用不存在：$DIFF_REF（无法核对 diff）"
fi

[[ -f "$FIRST_ADR" ]] && pass "AC4 首实例 ADR 存在" || fail "AC4 首实例 ADR 不存在：$FIRST_ADR"
check_skeleton "AC4 首实例 ADR" "$FIRST_ADR"
ns="$(git -C "$ROOT" diff --name-status "$DIFF_BASE...$DIFF_REF" -- "$FIRST_ADR" 2>/dev/null || true)"
[[ "$ns" == A* ]] && pass "AC4 首实例在 diff 中为新增（A）" || fail "AC4 首实例 diff 状态非新增：${ns:-空}"

printf '== AC4 门禁（check / npm test / t4）==\n'
if $FAST; then
  skip "门禁 nao-fleet.sh check（--fast 跳过）"
  skip "门禁 npm test（--fast 跳过）"
  skip "门禁 tests/t4/run.sh 12/12（--fast 跳过）"
  skip "工作区干净（--fast 跳过）"
else
  cout="$(bash "$ROOT/.agents/scripts/nao-fleet.sh" check 2>&1)"; crc=$?
  cfiles="$(printf '%s\n' "$cout" | grep -oE 'files=[0-9]+' | head -1 | cut -d= -f2)"
  croles="$(printf '%s\n' "$cout" | grep -oE 'roles=[0-9]+' | head -1 | cut -d= -f2)"
  if [[ "$crc" -eq 0 ]]; then pass "门禁 check rc=0（roles=${croles:-?} files=${cfiles:-?}）"; else fail "门禁 check rc=$crc"; fi
  [[ "$cfiles" == "46" ]] && pass "门禁 check files=46" || fail "门禁 check files=${cfiles:-?}（应 46）"
  [[ "$croles" == "6" ]] && pass "门禁 check roles=6" || fail "门禁 check roles=${croles:-?}（应 6）"

  ( cd "$ROOT" && npm test ) >/dev/null 2>&1; nrc=$?
  [[ "$nrc" -eq 0 ]] && pass "门禁 npm test rc=0" || fail "门禁 npm test rc=$nrc"

  tout="$(bash "$ROOT/tests/t4/run.sh" 2>&1)"; trc=$?
  tpass="$(printf '%s\n' "$tout" | grep -cE '^  [0-9]{2}  PASS' || true)"
  tfail="$(printf '%s\n' "$tout" | grep -cE '^  [0-9]{2}  FAIL' || true)"
  [[ "$trc" -eq 0 ]] && pass "门禁 tests/t4/run.sh rc=0" || fail "门禁 tests/t4/run.sh rc=$trc"
  [[ "$tpass" -eq 12 && "$tfail" -eq 0 ]] && pass "门禁 tests/t4/run.sh 12/12" || fail "门禁 tests/t4/run.sh PASS=$tpass FAIL=$tfail"

  dirty="$(git -C "$ROOT" status --porcelain | grep -vF "$SELF_REL" || true)"
  [[ -z "$dirty" ]] && pass "AC4 工作区干净（忽略探针自身）" || fail "AC4 工作区有改动：$(printf '%s' "$dirty" | tr '\n' ' ')"
fi

printf '\nRESULT: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
exit $(( FAIL > 0 ? 1 : 0 ))
