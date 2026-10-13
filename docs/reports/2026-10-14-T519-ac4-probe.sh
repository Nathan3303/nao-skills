#!/usr/bin/env bash
# =============================================================================
# T519 · AC4 只读探针（零仓内写入）
#
# 目的：证明 task_state_class()（.agents/scripts/nao-fleet.sh L694–718）的四条
#       分类语义在台账瘦身后不回归。所有用例经 NAO_TASKS_STATE/TASKS_STATE 指向
#       **临时夹具**（/tmp，mktemp -d）；真 docs/tasks-state.md **只读**（sha256 前后比对）。
#
# 用法：
#   bash probe.sh [<repo-root>] [--pre]
#     <repo-root>  默认 = pwd
#     --pre        历史 id 断言改用迁移前基线（默认 ref=main；可用 T519_BASE_REF 覆盖）
#                  （迁移前基线演示：预期 FAIL；迁移后省略 --pre：预期 PASS）
#
# 退出码 = FAIL 条数（0 = 全过）
#
# 产出方：qa-T519（T519 第一交付）· 落盘登记：PM（docs/reports/，不进 tests/）
# =============================================================================
set -uo pipefail

REPO="${1:-$PWD}"
MODE="${2:-}"
[[ -d "$REPO/.agents/scripts" ]] || { echo "不是 nao-skills 仓根: $REPO" >&2; exit 2; }
FLEET="$REPO/.agents/scripts/nao-fleet.sh"
REAL="$REPO/docs/tasks-state.md"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/t519probe.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
t() { # t <标签> <期望> <实际>
  if [[ "$2" == "$3" ]]; then printf 'PASS  %-34s expect=%-9s actual=%s\n' "$1" "$2" "$3"; PASS=$((PASS+1))
  else printf 'FAIL  %-34s expect=%-9s actual=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
note() { printf 'NOTE  %s\n' "$*"; }

# ---- 0) 只读基线 -----------------------------------------------------------
SHA_BEFORE="$(sha256sum "$REAL" | cut -d' ' -f1)"
ST_BEFORE="$(git -C "$REPO" status --porcelain)"

# ---- 1) 抽取真函数正文（不改脚本，只读） ------------------------------------
FN_SRC="$(awk '/^task_state_class\(\) \{$/{f=1} f{print} f&&/^\}$/{exit}' "$FLEET")"
eval "$FN_SRC"
if declare -F task_state_class >/dev/null; then
  note "已从 $FLEET 抽取 task_state_class()（$(wc -l <<<"$FN_SRC") 行，逐字节取自脚本）"
else
  echo "FATAL 抽取失败：task_state_class 未定义" >&2; exit 2
fi
cls() { TASKS_STATE="$1" task_state_class "$2"; }

# ---- 2) 探针自检：真函数 → 不存在路径必须 nofile ----------------------------
t "S0 自检: 缺文件 → nofile" "nofile" "$(cls "$TMP/nonexistent.md" T900)"

# ---- 3) 合成夹具（覆盖 AC4 ②③④ + 格式写法观察） ----------------------------
cat > "$TMP/fx.md" <<'EOF'
## 待派发队列

> 泛化提及：T902 已于早前批次闭环（散文行，非单元格）。

## 进行中

| 任务编号 | 目标会话 | 概要 |
| :--- | :--- | :--- |
| T900 | qa-T900 | 非归档区裸 id 单元格 |

## 已验收 / 已归档

| 任务编号 | 结论 |
| :--- | :--- |
| T901 | 已合并归档 |
EOF
t "AC4-② 非归档表内裸 id → active" "active" "$(cls "$TMP/fx.md" T900)"
t "AC4-③ 归档表内裸 id → closed"    "closed" "$(cls "$TMP/fx.md" T901)"
t "AC4-④ 散文泛化提及 → mentioned"  "mentioned" "$(cls "$TMP/fx.md" T902)"

# 允许写法（norm 剥 ` 与 **）：`T900` / **T900**
cat > "$TMP/fx-ok.md" <<'EOF'
## 进行中

| 任务编号 | 目标会话 |
| :--- | :--- |
| `T900` | qa-T900 |
EOF
t '允许写法 `T900`（反引号）→ active' "active" "$(cls "$TMP/fx-ok.md" T900)"

# ---- 4) 格式写法 → 分类变化（观察项，供 RD 禁令清单） -----------------------
obs() { # obs <标签> <夹具文件> <id>
  printf 'OBS   %-42s %s\n' "$1" "$(cls "$2" "$3")"
}
# D1 归档小节下加 ### 子标题 → 子标题覆盖 sec ⇒ 归档行退化为 active
cat > "$TMP/d1.md" <<'EOF'
## 已验收 / 已归档
### 最近 2 批

| 任务编号 | 结论 |
| :--- | :--- |
| T901 | 已合并 |
EOF
obs "D1 归档节内 ### 子标题（无『归档』字样）" "$TMP/d1.md" T901
# D2 标题缺空格 ⇒ 不被认作标题 ⇒ 行归上一节
cat > "$TMP/d2.md" <<'EOF'
## 进行中

| 任务编号 | 结论 |
| :--- | :--- |
| T900 | x |
##已归档

| 任务编号 | 结论 |
| :--- | :--- |
| T901 | y |
EOF
obs "D2 '##已归档'（# 后无空格）" "$TMP/d2.md" T901
# D3 运行态标题含『归档』⇒ 全节升格归档区
cat > "$TMP/d3.md" <<'EOF'
## 待派发队列（历史已归档指针）

| 任务编号 | 概要 |
| :--- | :--- |
| T900 | 在飞 |
EOF
obs "D3 运行态标题含『归档』字样" "$TMP/d3.md" T900
# D4 围栏代码块内的 '# 归档…' 行被当作标题
cat > "$TMP/d4.md" <<'EOF'
## 进行中

| 任务编号 | 概要 |
| :--- | :--- |
| T899 | 前一行仍 active |

```
# 归档示例
```

| 任务编号 | 概要 |
| :--- | :--- |
| T900 | 围栏后一行 |
EOF
obs "D4 围栏内 '# 归档示例' 劫持 sec" "$TMP/d4.md" T900
# D5 ~ 删除线 / 斜体 / 链接 / 括注 / 多 id 单元格
cat > "$TMP/d5.md" <<'EOF'
## 进行中

| 任务编号 | 概要 |
| :--- | :--- |
| ~~T900~~ | 删除线 |
| *T901* | 斜体 |
| [T902](https://x) | 链接 |
| T903（已闭环） | 括注 |
| T904 / T905 | 多 id 单元格 |
| _T906_ | 下划线斜体（_ 属词内字符） |
EOF
obs "D5a '~~T900~~'（删strike）" "$TMP/d5.md" T900
obs "D5b '*T901*'（斜体）"      "$TMP/d5.md" T901
obs "D5c '[T902](url)'（链接）"  "$TMP/d5.md" T902
obs "D5d 'T903（已闭环）'（括注）" "$TMP/d5.md" T903
obs "D5e 'T904 / T905'（多 id）"  "$TMP/d5.md" T904
obs "D5f '_T906_'（下划线，词内字符）" "$TMP/d5.md" T906
# D6 同 id 同时出现在归档表与非归档表 ⇒ arch 优先（END 顺序）
cat > "$TMP/d6.md" <<'EOF'
## 进行中

| 任务编号 | 概要 |
| :--- | :--- |
| T900 | 在飞（非归档区裸 id） |

## 已验收 / 已归档

| 任务编号 | 结论 |
| :--- | :--- |
| T900 | 旧行误留 |
EOF
obs "D6 同时命中非归档 + 归档表（arch 优先）" "$TMP/d6.md" T900
# D7 带后缀 / id 在标题行
cat > "$TMP/d7.md" <<'EOF'
## 进行中 T900

| 任务编号 | 概要 |
| :--- | :--- |
| T900-RD | 带后缀 |
EOF
obs "D7 'T900-RD'（带后缀单元格）" "$TMP/d7.md" T900

# ---- 5) 真台账（只读）历史 id 断言 -----------------------------------------
# 迁移前基线引用：默认 main（RD 已提交后 HEAD 不再可靠）；可用 T519_BASE_REF 覆盖
BASE_REF="${T519_BASE_REF:-main}"
if git -C "$REPO" cat-file -e "$BASE_REF:docs/tasks-state.md" 2>/dev/null; then
  git -C "$REPO" show "$BASE_REF:docs/tasks-state.md" > "$TMP/base.md"
else
  BASE_REF=HEAD
  git -C "$REPO" show HEAD:docs/tasks-state.md > "$TMP/base.md" || { echo 'FATAL 无法取得迁移前台账（设 T519_BASE_REF=<ref>）' >&2; exit 2; }
fi
note "迁移前基线 ref=$BASE_REF（行数 $(wc -l < "$TMP/base.md")）"
if [[ "$MODE" == "--pre" ]]; then
  LEDGER="$TMP/base.md"; LBL="迁移前($BASE_REF)"
else
  LEDGER="$REAL"; LBL="迁移后(工作区)"
fi
mapfile -t IDS < <(grep -oE 'T[0-9]+[a-z]?' "$TMP/base.md" | sort -u)
note "历史 id 集合（自 $BASE_REF 抽取，${#IDS[@]} 个）: ${IDS[*]}"
LIVE_RE='^T519$'   # 唯一在飞 id（PRD 范围内保持 active）；RD 落地时按当时舰队实际在飞集核对
n_active=0; n_ids=0; active_list=()
for id in "${IDS[@]}"; do
  [[ "$id" =~ $LIVE_RE ]] && continue
  n_ids=$((n_ids+1))
  c="$(cls "$LEDGER" "$id")"
  if [[ "$c" == "active" ]]; then n_active=$((n_active+1)); active_list+=("$id"); fi
done
echo "---- AC4-① [${LBL}] 历史 id 共 ${n_ids} 个，判 active 者 ${n_active} 个" \
     "（${active_list[*]:-无}）"
t "AC4-① 历史 id 无一判 active" "0" "$n_active"

# 在飞 id 必须 active（保护未验收任务：close 闸门依赖）—— 补 AC4 四条盲区
t "AC4-②' [${LBL}] 在飞 T519 → active" "active" "$(cls "$LEDGER" T519)"
# 迁移后归档墙最近 2 批（T518/T517）必须 closed（§3.4 结构 + 防 ### 子标题破坏）
if [[ "$MODE" != "--pre" ]]; then
  for id in T518 T517; do
    t "AC4-③' [${LBL}] 归档墙 $id → closed" "closed" "$(cls "$LEDGER" "$id")"
  done
fi

# ---- 6) 只读复核 -----------------------------------------------------------
SHA_AFTER="$(sha256sum "$REAL" | cut -d' ' -f1)"
ST_AFTER="$(git -C "$REPO" status --porcelain)"
t "只读 sha256 未变" "same" "$([[ "$SHA_BEFORE" == "$SHA_AFTER" ]] && echo same || echo changed)"
t "git status 未变"  "same" "$([[ "$ST_BEFORE" == "$ST_AFTER" ]] && echo same || echo changed)"
note "真台账 sha256=$SHA_AFTER · 夹具目录 $TMP（$MODE）"

if [[ "$MODE" != "--pre" && $FAIL -gt 0 ]]; then
  note "非 --pre 模式的 FAIL 可能是『迁移尚未落地』的正常现象：RD 落地后须全 PASS"
fi
echo "==== SUMMARY: PASS=$PASS FAIL=$FAIL ===="
exit "$FAIL"
