#!/usr/bin/env bash
# tests/t4/lib-criteria.sh —— 判据体检 lint（T589 · Issue #253）
#
# 规格（唯一正文）：`docs/T589-criteria-check/review.md` §一（R1–R6 形态）/ §二（抽取规则）/ §四（自检判据）。
# 本文件只做**实现**，不复写规则理由；改规则形态请先改规格再改这里（一处一条）。
#
# 用法：
#   criteria_lint_file <file>   → 逐条命中行 `✗ <basename> → R<k> <短语>`；无命中 ⇒ 无输出
#                                 rc=0 正常（含 0 命中）· rc=1 抽取器失效（存在缺 Then 的块）
#   criteria_lint_dir  <dir>    → 同格式逐文件汇总（* .md）
#
# 抽取（规格 §二）：先剥 ``` 围栏；按 `### ` 切块；块内取 `^\s*Then`（兼容 `然后`）拼接判一次。
#   块内**无 Then** ⇒ 记一次跳过（显式计数，禁静默漏扫）。

# 规则开关（变异负控用：`sed 's/^: "${c58_r5_enabled:=1}"$/…0/'` 关掉 R5）
: "${c58_r5_enabled:=1}"

criteria_lint_file() { # <file>
  local f="${1-}"
  [ -f "$f" ] || { printf '探针：文件不存在：%s\n' "$f" >&2; return 1; }
  local base out hits skips
  base="$(basename "$f")"
  out="$(awk -v r5="${c58_r5_enabled}" '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function test_rules(blk, thn,   n, cp, hit) {
      hit = ""
      # R1 聚合轴错：Then 断「不变/差值 0」而块内又在单源化/搬迁/改名（数字必变）
      if (thn ~ /(仍为|仍等于|保持不变|不变|差值[ \t]*0)/ && blk ~ /(单源|收敛|去重|搬迁|搬去|迁移|替换|改写|删除|删掉|改名)/)
        hit = hit "R1\t聚合轴错：同块既要求「不变/差值 0」又在单源化/搬迁/改名\n"
      # R2 基数混轴：≥2 处 a→b 且块内未声明同一扫描面/基数
      cp = blk
      n = gsub(/[0-9]+[ \t]*(→|->)[ \t]*[0-9]+/, "&", cp)
      if (n >= 2 && blk !~ /(扫描面|基数|同口径|同基数|同一批文件)/)
        hit = hit "R2\t基数混轴：块内 " n " 处 a→b 且未声明同一扫描面/基数\n"
      # R3 空集假绿：扫描面 0 却「跳过/视为通过」
      if (blk ~ /(扫描面[ \t]*0|0[ \t]*个对象|对象为空|列表为空)/ && blk ~ /(跳过|视为通过|不算失败)/)
        hit = hit "R3\t空集假绿：零对象也「跳过/视为通过」（须先断扫描面 ≥1）\n"
      # R4 截断假红：先截前 N 字再判「须含标注」
      if (blk ~ /((前|截|取)[ \t]*[0-9]+[ \t]*字|截断|head[ \t]*-c|substring|\.slice\([ \t]*0)/ && thn ~ /(含|标注|声明|须)/)
        hit = hit "R4\t截断假红：先截断再判「须含/标注」（标注写在截断点之后就假红）\n"
      # R5 语义隔层：innerText 判「空」而不限定「可见」（sr-only 回退句必然进 innerText）
      if (r5 == 1 && thn ~ /innerText/ && thn ~ /(空串|为空|空)/ && thn !~ /可见/)
        hit = hit "R5\t语义隔层：innerText 判空且未限定「可见」（sr-only 回退句会进 innerText）\n"
      # R6 采样点不稳：断言行首三点/像素值却未声明采样点/坐标
      if (thn ~ /((行首|首)[^。]{0,10}(三点|3[ \t]*点)|像素值|=[ \t]*[0-9]{2,3}（亮）)/ && thn !~ /(中点|居中|采样点|坐标|x[ \t]*=|y[ \t]*=)/)
        hit = hit "R6\t采样点不稳：未声明采样点/坐标（行首/像素值受圆角与抗锯齿影响）\n"
      return hit
    }
    function flush(   h) {
      if (blkno == 0) return
      if (thn == "") { skip++; return }
      h = test_rules(blk, thn)
      if (h != "") printf "%s", h
    }
    { if ($0 ~ /^[ \t]*```/) { fence = !fence; next } }
    fence { next }
    /^###[ \t]/ { flush(); blkno++; blk = ""; thn = ""; blk = $0 "\n"; next }
    {
      if (blkno == 0) { blkno = 1 }        # 无 `###` ⇒ 整文件一块
      blk = blk $0 "\n"
      if ($0 ~ /^[ \t]*(Then|然后)([ \t]|$)/) thn = thn $0 "\n"
    }
    END { flush(); printf "SKIP\t%d\n", skip + 0 }
  ' "$f")" || return 1
  # 输出行 = `<R<k>>\t<理由>` 若干 + 末行 `SKIP\t<n>`；按 TAB 逐行解析（勿用 grep 的 \t —— ERE 里不是制表符）
  local line rid why skipn=0
  while IFS=$'\t' read -r rid why; do
    case "$rid" in
      R[1-6]) printf '✗ %s → %s %s\n' "$base" "$rid" "$why" ;;
      SKIP)   skipn="${why:-0}" ;;
    esac
  done <<< "$out"
  if [[ "${skipn:-0}" -gt 0 ]]; then
    printf '跳过 %s 块（无 Then）—— %s\n' "$skipn" "$base"
    return 1
  fi
  return 0
}

criteria_lint_dir() { # <dir>
  local d="${1-}" f rc=0
  for f in "$d"/*.md; do
    [ -f "$f" ] || continue
    criteria_lint_file "$f" || rc=1
  done
  return "$rc"
}
