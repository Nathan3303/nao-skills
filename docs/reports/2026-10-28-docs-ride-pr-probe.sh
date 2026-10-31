#!/usr/bin/env bash
# 一次性只读探针 —— T533「文档与台账随任务 PR：一任务一 PR 全量改动」
# 验证接缝（AC1 / AC2 / AC3 / AC4），不进 tests/。
#
# 用法:  bash docs/reports/2026-10-28-docs-ride-pr-probe.sh
# 输出:  每行 `PASS <id> ...` / `FAIL <id> ...`，末两行汇总；rc=0 ⇔ FAIL=0
# 纪律:  真仓库**零写入**（仅 grep / git log / git status / git show）；全部构造在 mktemp -d 临时仓内完成并清理。
#        输出不含时间戳 / 临时路径 / 提交哈希 ⇒ 连跑两次逐字一致（确定性）。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS_N=0
FAIL_N=0

ok()   { PASS_N=$((PASS_N + 1)); printf 'PASS %s\n' "$*"; }
bad()  { FAIL_N=$((FAIL_N + 1)); printf 'FAIL %s\n' "$*"; }

# have <text> <fixed-string>
have() { printf '%s' "$1" | grep -qF -- "$2"; }

# need_all <id> <file> <kw...>  —— 关键词全在位才 PASS（漏一即 FAIL，逐个列出缺失项）
need_all() {
  local id="$1" file="$2" kw miss=""
  shift 2
  [[ -f "$file" ]] || { bad "$id（文件缺失）"; return; }
  for kw in "$@"; do
    grep -qF -- "$kw" "$file" || miss="$miss [$kw]"
  done
  if [[ -z "$miss" ]]; then ok "$id"; else bad "$id 缺失:$miss"; fi
}

# need_region <id> <file> <起行正则> <止行正则(空=到文末)> <kw...>  —— 只在指定小节正文里找
need_region() {
  local id="$1" file="$2" start="$3" stop="$4" kw body miss=""
  shift 4
  [[ -f "$file" ]] || { bad "$id（文件缺失）"; return; }
  body="$(awk -v s="$start" -v e="$stop" '
    on && e != "" && $0 ~ e { exit }
    on { print }
    $0 ~ s { on = 1 }
  ' "$file")"
  [[ -n "$body" ]] || { bad "$id（小节未命中）"; return; }
  for kw in "$@"; do
    have "$body" "$kw" || miss="$miss [$kw]"
  done
  if [[ -z "$miss" ]]; then ok "$id"; else bad "$id 缺失:$miss"; fi
}

# need_row <id> <file> <表格首列号> <kw>  —— 八阶段表按行核「产出」列承载的文档载体
need_row() {
  local id="$1" file="$2" n="$3" kw="$4" row
  row="$(grep -m1 -E "^\| ${n} \|" "$file" || true)"
  if [[ -n "$row" ]] && have "$row" "$kw"; then ok "$id"; else bad "$id 缺失:$kw"; fi
}

GF="$ROOT/.agents/skills/github-flow.md"
PM="$ROOT/.agents/prompts/product-manager.md"
PMC="$ROOT/.agents/checklists/pm.md"

# ── 真仓库快照（RO 判据：前后必须逐字一致）─────────────────────────────
RO_STATUS_BEFORE="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
RO_HEAD_BEFORE="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"

# ── AC1 规则单源在位（github-flow.md）──────────────────────────────────
need_all AC1-1-小节标题 "$GF" "## 文档与台账载体（一任务一 PR）"
need_all AC1-2-BR1全量 "$GF" \
  "BR1 全量" "任务 PR 必须包含该任务" "全部文件改动" \
  "PRD 定稿" "验收报告" "ADR" "docs/tasks-state.md" \
  "docs/reports/*-followups.md" "docs/prds/README.md" "docs/releases/<v>.md"
need_all AC1-3-BR2禁令 "$GF" "BR2 禁令" "禁止为文档 / 台账" "单开 PR" "独立提交直落 main"
need_all AC1-4-BR4谁提交 "$GF" "BR4 谁提交" "路径级" "docs(<编号>):" "禁 \`-A\`" "只暂存自己的路径"
need_all AC1-5-BR5收尾 "$GF" "BR5 批间收尾" "发布提交一次带走" "下一个任务 PR" "不得单独提交 main"
need_row AC1-6-阶段1产出 "$GF" 1 "docs/prds"
need_row AC1-7-阶段4产出 "$GF" 4 "随本 PR"
need_row AC1-8-阶段5产出 "$GF" 5 "docs/reports/"
need_row AC1-9-阶段6产出 "$GF" 6 "全部文档改动"
need_row AC1-10-阶段7产出 "$GF" 7 "docs/releases/"
need_region AC1-11-红线 "$GF" '^## 红线' '' \
  "为文档 / 台账**单开 PR**" "独立提交直落 main"
need_region AC1-12-离线降级 "$GF" '^## 离线 / 无远端降级' '' \
  "| 文档载体 |" "merge --squash" "不另开文档提交"

# ── AC2 禁令四处齐备（PM 卡 §六 / §十三 / 卡红线 / 清单红线 + 清单项）──
need_region AC2-1-PM卡六 "$PM" '^## 六、' '^## 七、' "文档随任务 PR" "单开 PR" "独立直落 main"
need_region AC2-2-PM卡十三 "$PM" '^## 十三、' '' "文档随任务 PR" "不为文档单开 PR" "不把任务期文档独立提交到 main"
need_region AC2-3-PM卡红线 "$PM" '^## 十、硬性红线' '^## 十一、' "为文档 / 台账单开 PR" "独立提交直落 main"
need_region AC2-4-清单红线 "$PMC" '^## 硬性红线' '^## 交付检查清单' "为文档 / 台账**单开 PR**" "独立提交直落 main"
need_region AC2-5-清单项 "$PMC" '^## 交付检查清单' '' "**文档随任务 PR**" "无文档-only PR"
need_all AC2-6-计数口径 "$PMC" "## 硬性红线（完整 34 项）" "## 交付检查清单（完整 43 项）"
need_all AC2-7-卡计数对齐 "$PM" "完整红线（34 项）" "交付检查清单（43 项）"

# ── AC3 立项例外可判（BR3 三条件逐字在位 + 降级无例外）────────────────
need_all AC3-1-BR3三条件 "$GF" \
  "BR3 立项例外" "仅用于" "最小摘要三要素" "TL;DR + AC 编号 + PRD 路径指针" \
  "单条" "不与其它改动混提" "降级批次（无 Issue）无此例外"

# ── AC4 负控：临时 git 仓构造两条反例 + 一条正向夹具 ────────────────────
TMP="$(mktemp -d "${TMPDIR:-/tmp}/nao-probe.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

gitq() { git -C "$1" "${@:2}"; }

mk_repo() { # $1=dir
  git init -q -b main "$1" >/dev/null 2>&1
  gitq "$1" config user.email probe@example.invalid
  gitq "$1" config user.name probe
  gitq "$1" config commit.gpgsign false
  gitq "$1" config core.autocrlf false
}

cm() { # $1=dir $2=subject $3=path $4=content  （临时仓内提交，-A 仅限夹具）
  local d="$1" s="$2" p="$3" c="$4"
  mkdir -p "$d/$(dirname "$p")"
  printf '%s\n' "$c" >"$d/$p"
  gitq "$d" add -A
  gitq "$d" commit -q -m "$s"
}

# judge <dir> <task> ⇒ 打印 PASS / FAIL:<reason>，rc 与判定一致
# 判据（main 上，针对任务 T；对应 BR1/BR2/BR3）：
#   R1 该任务提交数 ≥ 1 且 ≤ 2（1 条任务提交 + 最多 1 条立项摘要）
#   R2 存在 ≥2 条 docs 提交 ⇒ FAIL（违反 BR3「单条」）
#   R3 单条 docs 提交若非「立项摘要」（≠ 单一文件且落 docs/prds/）⇒ FAIL（BR2①）
#   R4 任何 merge 提交的侧分支里含 docs 提交 ⇒ FAIL（独立 PR 通道，BR2①）
#
# T534（C 项 · AC4）：docs 提交识别口径放宽 —— 全角 `（）`/`：`、无编号 `docs:`、大小写变体 `Docs(` 均算
#   文档提交（旧口径 `^docs\(T\):` 会把它们漏判成「非 docs 提交」⇒ 假阴性）。
#   is_docs_subject 是唯一判定点（T534 探针按此做「收窄正则」变异自证）。
# 判定口径两处单点（T534 探针按这两个变量做「收窄正则 / 去归一」变异自证）：
#   DOCS_SUBJECT_NORM = 全角 （） 与全角 ： 归一（旧口径的假阴来源之一）
#   DOCS_ERE          = docs 前缀（大小写不敏感、括号编号可选 ⇒ 覆盖无编号 `docs:`）
DOCS_SUBJECT_NORM='s/（/(/g; s/）/)/g; s/：/:/g'
DOCS_ERE='^[Dd][Oo][Cc][Ss][[:space:]]*(\([^)]*\))?[[:space:]]*:'

is_docs_subject() {  # <subject> <task-id>；subject 归一后匹配 docs 前缀，括号内编号（若有）须等于 task
  local n="" id=""
  n="$(printf '%s' "$1" | sed "$DOCS_SUBJECT_NORM")"
  printf '%s' "$n" | grep -qE "$DOCS_ERE" || return 1
  id="$(printf '%s' "$n" | sed -n 's/^[Dd][Oo][Cc][Ss][[:space:]]*(\([^)]*\))[[:space:]]*:.*/\1/p')"
  [[ -z "$id" || "$id" == "$2" ]]
}

# 该任务的 docs 提交：<sha>\t<subject>（每行一条；$3=revspec，默认 main）
docs_commits() {
  local d="$1" t="$2" rev="${3:-main}" sha subj
  while IFS=$'\t' read -r sha subj; do
    [[ -n "$sha" ]] || continue
    is_docs_subject "$subj" "$t" && printf '%s\t%s\n' "$sha" "$subj"
  done < <(gitq "$d" log --format='%H%x09%s' "$rev" 2>/dev/null || true)
}

judge() {
  local d="$1" t="$2" docs_list docs_cnt side_head side_log subj total
  # 任务提交识别：兼容半角 `(T900)` 与全角 `（T900）`（真实 squash 主题可能用全角）
  total="$(gitq "$d" log --format='%s' main | grep -cE "\(${t}\)|（${t}）" || true)"
  docs_list="$(docs_commits "$d" "$t")"
  docs_cnt="$(printf '%s\n' "$docs_list" | grep -c . || true)"

  # R4：main 上合并提交的侧分支（非 first-parent 链）里是否出现该任务的 docs 提交
  while IFS= read -r side_head; do
    [[ -n "$side_head" ]] || continue
    side_log="$(gitq "$d" log --format='%s' "$side_head" --not main~1 2>/dev/null || true)"
    while IFS= read -r subj; do
      [[ -n "$subj" ]] || continue
      if is_docs_subject "$subj" "$t"; then printf 'FAIL:docs-pr-separate\n'; return 1; fi
    done <<< "$side_log"
  done < <(gitq "$d" log --merges --format='%p' main | awk 'NF>1 { for (i=2;i<=NF;i++) print $i }')

  if (( total == 0 )); then printf 'FAIL:no-task-commit\n'; return 1; fi
  if (( docs_cnt >= 2 )); then printf 'FAIL:docs-only-multi\n'; return 1; fi
  if (( docs_cnt == 1 )); then
    local sha files
    sha="$(printf '%s\n' "$docs_list" | head -1 | cut -f1)"
    files="$(gitq "$d" show --pretty=format: --name-only "$sha" | grep -c . || true)"
    if (( files != 1 )) || ! gitq "$d" show --pretty=format: --name-only "$sha" | grep -qE '^docs/prds/'; then
      printf 'FAIL:docs-only-standalone\n'; return 1
    fi
  fi
  if (( total > 2 )); then printf 'FAIL:many-commits\n'; return 1; fi
  printf 'PASS:one-squash-with-docs\n'; return 0
}

# 负控 ①：任务期另开 docs-only 提交直落 main（线性，无合并）
R1D="$TMP/neg1"; mk_repo "$R1D"
cm "$R1D" "feat: 台账校验闸门（T900）" "src/gate.sh" "echo gate"
cm "$R1D" "docs(T900): tasks-state 台账更新" "docs/tasks-state.md" "- T900 完成"
OUT1="$(judge "$R1D" T900 || true)"
if [[ "$OUT1" == "FAIL:docs-only-standalone" ]]; then
  ok "NEG-1 任务期独立 docs() 提交直落 main ⇒ 判 FAIL（docs-only-standalone）"
else
  bad "NEG-1 期望 FAIL:docs-only-standalone，实得 $OUT1"
fi

# 负控 ②：为台账单开独立 PR（侧分支 + 合并提交）的提交流
R2D="$TMP/neg2"; mk_repo "$R2D"
cm "$R2D" "feat: 发布说明生成（T901）" "src/notes.sh" "echo notes"
gitq "$R2D" checkout -q -b docs/T901-ledger
cm "$R2D" "docs(T901): 台账收尾 + followups" "docs/tasks-state.md" "- T901 收尾"
gitq "$R2D" checkout -q main
gitq "$R2D" merge -q --no-ff docs/T901-ledger -m "Merge pull request #7 from docs/T901-ledger" >/dev/null 2>&1
OUT2="$(judge "$R2D" T901 || true)"
if [[ "$OUT2" == "FAIL:docs-pr-separate" ]]; then
  ok "NEG-2 为台账单开独立 PR ⇒ 判 FAIL（docs-pr-separate）"
else
  bad "NEG-2 期望 FAIL:docs-pr-separate，实得 $OUT2"
fi

# 正向夹具：单条 squash 内含实现 + 文档 ⇒ 判 PASS
POSD="$TMP/pos"; mk_repo "$POSD"
cm "$POSD" "feat: 文档随任务 PR 口径落地（T950）" "src/flow.sh" "echo flow"
mkdir -p "$POSD/docs/prds" && printf '%s\n' "# PRD T950" >"$POSD/docs/prds/T950.md"
gitq "$POSD" add -A && gitq "$POSD" commit -q --amend -m "文档与台账随任务 PR：一任务一 PR 全量改动（T950）"
OUT3="$(judge "$POSD" T950 || true)"
if [[ "$OUT3" == "PASS:one-squash-with-docs" ]]; then
  ok "POS-TMP 正向夹具（单条提交含 docs/ 改动）⇒ 判 PASS"
else
  bad "POS-TMP 期望 PASS:one-squash-with-docs，实得 $OUT3"
fi

# ── AC4（T534 · C 项）：识别口径放宽 —— 全角 （）/：、无编号 docs:、大小写变体 Docs( 均判「文档提交」
# 观测方式：同一批「任务提交 + 单条 docs-only 提交（非 docs/prds/）」夹具，四种写法都必须被识别为 docs 提交
#   ⇒ 判 FAIL:docs-only-standalone（未识别 ⇒ docs_cnt=0 ⇒ 假阴 PASS）。
# 覆盖限制（BR6 诚实）：**任务提交完全无 docs** 不在本探针判定范围（不属本批缺陷，也不得让未覆盖看起来像通过）。
printf '未覆盖：任务提交完全无 docs（本探针只判「有 docs 提交」的载体形态；无 docs 提交属未覆盖，不判 PASS 也不判 FAIL）\n'
for spec in 'AC4-1|docs(T902):|T902' 'AC4-2|docs（T903）：|T903' 'AC4-3|docs:|T904' 'AC4-4|Docs(T905):|T905'; do
  id="${spec%%|*}"; rest="${spec#*|}"; subj="${rest%|*}"; tno="${rest##*|}"
  D="$TMP/spell-$id"; mk_repo "$D"
  cm "$D" "feat: 识别口径夹具（$tno）" "src/x.sh" "echo x"
  cm "$D" "$subj tasks-state 台账更新" "docs/tasks-state.md" "- $tno 收尾"
  O="$(judge "$D" "$tno" || true)"
  if [[ "$O" == "FAIL:docs-only-standalone" ]]; then
    ok "$id 写法「$subj」被判为文档提交（docs-only-standalone）"
  else
    bad "$id 期望 FAIL:docs-only-standalone（写法「$subj」未被识别），实得 $O"
  fi
done

# ── RO：真仓库零写入 ──────────────────────────────────────────────────
RO_STATUS_AFTER="$(git -C "$ROOT" status --porcelain 2>/dev/null || true)"
RO_HEAD_AFTER="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
if [[ "$RO_STATUS_BEFORE" == "$RO_STATUS_AFTER" && "$RO_HEAD_BEFORE" == "$RO_HEAD_AFTER" ]]; then
  ok "RO-1 真仓库零写入（status/HEAD 前后一致）"
else
  bad "RO-1 真仓库被改动（status 或 HEAD 前后不一致）"
fi

printf -- '---\n探针汇总: PASS=%d FAIL=%d\n' "$PASS_N" "$FAIL_N"
(( FAIL_N == 0 )) || exit 1
