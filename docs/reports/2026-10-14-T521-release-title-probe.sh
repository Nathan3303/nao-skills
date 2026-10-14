#!/usr/bin/env bash
# T521 Release 标题口径一次性探针（只读 · 幂等 · 不进 tests/）
#
# 用途：机械核验 PRD docs/prds/2026-10-14-release-title-bare-version.md §七 AC2–AC7。
#
# 用法：
#   bash docs/reports/2026-10-14-T521-release-title-probe.sh           # 全量（结构 + 门禁 check/npm test + 收尾工作区）
#   bash docs/reports/2026-10-14-T521-release-title-probe.sh --fast    # 仅结构断言（跳过门禁与工作区）
#   bash docs/reports/2026-10-14-T521-release-title-probe.sh --negctl  # 负控自证：mktemp -d 副本注反例 ⇒ 子探针必须 FAIL
#
# 只读保证：不写仓库任何文件；负控只在 `mktemp -d` 临时副本上注反例，运行后清理（不回显随机路径以保幂等）。
# 幂等保证：同一工作区连跑两次输出逐字一致（门禁只回放解析后的精确数字）。
# 覆盖变量：PROBE_ROOT（被核验的仓库根；默认本仓根，负控传入临时副本）、PROBE_NEGROOT（负控父目录，默认 mktemp -d）。
set -uo pipefail

SELF_ABS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO_ROOT="$(cd "$(dirname "$SELF_ABS")/../.." && pwd)"
SELF_REL="docs/reports/2026-10-14-T521-release-title-probe.sh"

FAST=false
NEGCTL=false
for a in "$@"; do
  case "$a" in
    --fast)    FAST=true ;;
    --negctl)  NEGCTL=true ;;
    -h|--help) sed -n '2,13p' "$SELF_ABS"; exit 0 ;;
    *) printf '未知参数：%s\n' "$a" >&2; exit 2 ;;
  esac
done

ROOT="${PROBE_ROOT:-$REPO_ROOT}"
AGENTS="$ROOT/.agents"
REM="$AGENTS/common/release-notes.md"
GHFLOW="$AGENTS/skills/github-flow.md"
PMCARD="$AGENTS/prompts/product-manager.md"
TMPL="$AGENTS/templates/release-notes.md.example"

PASS=0; FAIL=0; SKIP=0
pass(){ PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail(){ FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }
skip(){ SKIP=$((SKIP+1)); printf 'SKIP  %s\n' "$1"; }
count_lines(){ grep -c . 2>/dev/null || true; }

section_of(){
  awk -v pat="$2" '
    $0 ~ pat { f=1 }
    f && /^## / && $0 !~ pat { f=0 }
    f { print }
  ' "$1"
}

# ---------------------------------------------------------------------------
# 负控：mktemp -d 临时副本注反例，子探针必须 FAIL（证伪能力自检）
# 控制 1 = 注入旧占位语（应触发 AC3）· 控制 2 = 角色卡 version 回退（应触发 AC4）
# ---------------------------------------------------------------------------
copy_fixture(){
  local dir="$1"
  mkdir -p "$dir/.agents/common" "$dir/.agents/skills" "$dir/.agents/prompts" "$dir/.agents/templates"
  cp "$REPO_ROOT/.agents/common/release-notes.md"        "$dir/.agents/common/"
  cp "$REPO_ROOT/.agents/skills/github-flow.md"          "$dir/.agents/skills/"
  cp "$REPO_ROOT/.agents/prompts/product-manager.md"     "$dir/.agents/prompts/"
  cp "$REPO_ROOT/.agents/templates/release-notes.md.example" "$dir/.agents/templates/"
}

negctl_run(){
  local base="${PROBE_NEGROOT:-$(mktemp -d)}"
  mkdir -p "$base"
  local np=0 nf=0 ctl dir out rc cnt
  for ctl in placeholder version-rollback; do
    dir="$(mktemp -d "$base/ctl.XXXXXX")"
    copy_fixture "$dir"
    if [[ "$ctl" == placeholder ]]; then
      sed -i 's/--title "vX.Y.Z"/--title "<用户可读标题>"/' \
        "$dir/.agents/skills/github-flow.md" "$dir/.agents/prompts/product-manager.md"
    else
      sed -i 's/^version: 25$/version: 24/' "$dir/.agents/prompts/product-manager.md"
    fi
    out="$(PROBE_ROOT="$dir" bash "$SELF_ABS" --fast 2>&1)"; rc=$?
    cnt="$(printf '%s\n' "$out" | grep -oE 'RESULT: PASS=[0-9]+ FAIL=[0-9]+' | tail -1)"
    printf '  反例[%s] 子探针 rc=%s %s\n' "$ctl" "$rc" "${cnt:-RESULT: ?}"
    printf '%s\n' "$out" | grep -E '^FAIL ' | sed 's/^/    /'
    if [[ "$rc" -ne 0 && "$cnt" == *"FAIL="* && "${cnt##*FAIL=}" -ge 1 ]]; then
      np=$((np+1)); printf '  ⇒ 负控[%s] PASS（探针正确 FAIL）\n' "$ctl"
    else
      nf=$((nf+1)); printf '  ⇒ 负控[%s] FAIL（探针未报错，证伪能力不足）\n' "$ctl"
    fi
  done
  [[ -n "${PROBE_NEGROOT:-}" ]] || rm -rf "$base"
  printf '\nNEGCTL: PASS=%d FAIL=%d\n' "$np" "$nf"
  exit $(( nf > 0 ? 1 : 0 ))
}

if $NEGCTL; then negctl_run; fi

# ---------------------------------------------------------------------------
# AC2 权威单处
# ---------------------------------------------------------------------------
printf '== AC2 权威单处（common/release-notes.md §一）==\n'
sec1="$(section_of "$REM" '^## 一、硬约束')"
[[ -n "$sec1" ]] && pass "AC2 §一 硬约束段非空" || fail "AC2 §一 硬约束段为空（节名漂移？）"
{ [[ "$sec1" == *"裸"* ]] && [[ "$sec1" == *"vX.Y.Z"* ]]; } \
  && pass "AC2 §一 含标题硬约束「裸 vX.Y.Z」" || fail "AC2 §一 缺「裸 vX.Y.Z」标题硬约束"
{ [[ "$sec1" == *"正文首段"* ]] && [[ "$sec1" == *"本次更新"* ]]; } \
  && pass "AC2 §一 明示描述归属正文首段「本次更新」" || fail "AC2 §一 未明示描述归属正文首段"

# ---------------------------------------------------------------------------
# AC3 引用收敛 + 反删除
# ---------------------------------------------------------------------------
printf '== AC3 引用收敛 + 反删除 ==\n'
n_old="$(grep -rn '用户可读标题' "$AGENTS" 2>/dev/null | count_lines)"
[[ "$n_old" -eq 0 ]] && pass "AC3 全 .agents/ 「用户可读标题」命中数 = 0" \
  || fail "AC3 「用户可读标题」仍命中 $n_old 处"
for f in "$GHFLOW" "$PMCARD"; do
  rel="${f#"$ROOT"/}"
  if [[ ! -f "$f" ]]; then fail "AC3 $rel 不存在（反删除失败）"; continue; fi
  pass "AC3 $rel 仍在（反删除）"
  c="$(grep -c -- '--title "vX.Y.Z"' "$f" || true)"
  [[ "$c" -eq 1 ]] && pass "AC3 $rel 含 --title \"vX.Y.Z\"（1 处）" \
    || fail "AC3 $rel --title \"vX.Y.Z\" 命中=$c（应 1）"
  c2="$(grep -c -- '--title "vX.Y.Z".*common/release-notes.md' "$f" || true)"
  [[ "$c2" -ge 1 ]] && pass "AC3 $rel 同一行指回权威单处" \
    || fail "AC3 $rel 未指回权威单处（common/release-notes.md）"
done

# ---------------------------------------------------------------------------
# AC4 角色卡纪律
# ---------------------------------------------------------------------------
printf '== AC4 角色卡纪律（product-manager.md frontmatter）==\n'
head6="$(sed -n '1,6p' "$PMCARD")"
[[ "$head6" == *"version: 25"* ]] && pass "AC4 product-manager version: 25" \
  || fail "AC4 product-manager version ≠ 25"
[[ "$head6" == *"updated: 2026-10-14"* ]] && pass "AC4 product-manager updated: 2026-10-14" \
  || fail "AC4 product-manager updated ≠ 2026-10-14"

# ---------------------------------------------------------------------------
# AC5 模板边界（注释加标题口径 · 分段标题不动）
# ---------------------------------------------------------------------------
printf '== AC5 模板边界（release-notes.md.example）==\n'
if [[ -f "$TMPL" ]]; then
  pass "AC5 release-notes.md.example 存在"
  grep -qF 'Release 标题 = 裸 `vX.Y.Z`' "$TMPL" \
    && pass "AC5 头部注释含标题口径行" || fail "AC5 头部注释缺标题口径行"
  grep -qF '# 本次更新' "$TMPL" && pass "AC5 分段标题在：# 本次更新" || fail "AC5 分段标题缺失：# 本次更新"
  for h in '## ✨ 更好用了' '## 🐛 修好了'; do
    grep -qF "$h" "$TMPL" && pass "AC5 分段标题在：$h" || fail "AC5 分段标题缺失：$h"
  done
  grep -qE '^## ⚠️ 请留意' "$TMPL" && pass "AC5 分段标题在：## ⚠️ 请留意" \
    || fail "AC5 分段标题缺失：## ⚠️ 请留意"
  grep -qE '^## 技术细节' "$TMPL" && pass "AC5 分段标题在：## 技术细节" \
    || fail "AC5 分段标题缺失：## 技术细节"
else
  fail "AC5 release-notes.md.example 不存在：$TMPL"
fi

# ---------------------------------------------------------------------------
# AC6 正文规范未误伤 + 收尾工作区
# ---------------------------------------------------------------------------
printf '== AC6 正文规范未误伤 + 收尾工作区 ==\n'
if { grep -qF '本次更新' "$TMPL" && grep -qF '技术细节' "$TMPL"; }; then
  pass "AC6 正文关键词「本次更新 / 技术细节」仍在"
else
  fail "AC6 正文关键词「本次更新 / 技术细节」缺失"
fi
if $FAST; then
  skip "AC6 收尾 git status --short 为空（--fast 跳过）"
else
  raw="$(git -C "$REPO_ROOT" status --short)"
  other="$(printf '%s\n' "$raw" | grep -vF "$SELF_REL" | count_lines)"
  printf '  raw git status --short：%s\n' "$(printf '%s' "$raw" | tr '\n' ' ')"
  if [[ "$other" -eq 0 ]]; then
    pass "AC6 收尾 git status --short 为空（探针自身未提交项除外）"
  else
    fail "AC6 工作区有改动 $other 项：$(printf '%s' "$raw" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------------------------
# AC7 降级路径回归
# ---------------------------------------------------------------------------
printf '== AC7 降级路径回归 ==\n'
line71="$(sed -n '71p' "$GHFLOW")"
if [[ "$line71" == *'gh release create'* && "$line71" == *'git tag -a'* && "$line71" == *'docs/releases/'* ]]; then
  pass "AC7 github-flow.md:71 降级表行仍在"
else
  fail "AC7 github-flow.md:71 降级表行丢失：${line71:-<空>}"
fi
hard="$(grep -rnE '必须安装 ?`?gh|必须使用 ?`?gh|强制 ?`?gh|硬依赖 ?`?gh|gh ?必装|requires? ?`?gh|必须有 ?`?gh' "$AGENTS" 2>/dev/null | count_lines)"
[[ "$hard" -eq 0 ]] && pass "AC7 全 .agents/ 无新增 gh 硬依赖表述（命中 0）" \
  || fail "AC7 出现 gh 硬依赖表述 $hard 处（应 0）"
soft=0
for f in "$GHFLOW" "$PMCARD"; do grep -qF '优先 `gh`' "$f" && soft=$((soft+1)); done
[[ "$soft" -eq 2 ]] && pass "AC7 两文件仍保留「优先 \`gh\`」（非硬依赖）" \
  || fail "AC7 「优先 \`gh\`」保留数=$soft（应 2）"

# ---------------------------------------------------------------------------
# 门禁（check / npm test）
# ---------------------------------------------------------------------------
printf '== 门禁（check / npm test）==\n'
if $FAST; then
  skip "门禁 nao-fleet.sh check（--fast 跳过）"
  skip "门禁 npm test（--fast 跳过）"
else
  cout="$(bash "$REPO_ROOT/.agents/scripts/nao-fleet.sh" check 2>&1)"; crc=$?
  croles="$(printf '%s\n' "$cout" | grep -oE 'roles=[0-9]+' | head -1 | cut -d= -f2)"
  cfiles="$(printf '%s\n' "$cout" | grep -oE 'files=[0-9]+' | head -1 | cut -d= -f2)"
  if [[ "$crc" -eq 0 ]]; then
    pass "门禁 check rc=0（roles=${croles:-?} files=${cfiles:-?}）"
  else
    fail "门禁 check rc=$crc"
  fi
  [[ "$croles" == "6" ]] && pass "门禁 check roles=6" || fail "门禁 check roles=${croles:-?}（应 6）"
  [[ "$cfiles" == "46" ]] && pass "门禁 check files=46" || fail "门禁 check files=${cfiles:-?}（应 46）"

  ( cd "$REPO_ROOT" && npm test ) >/dev/null 2>&1; nrc=$?
  [[ "$nrc" -eq 0 ]] && pass "门禁 npm test rc=0" || fail "门禁 npm test rc=$nrc"
fi

printf '\nRESULT: PASS=%d FAIL=%d SKIP=%d\n' "$PASS" "$FAIL" "$SKIP"
exit $(( FAIL > 0 ? 1 : 0 ))
