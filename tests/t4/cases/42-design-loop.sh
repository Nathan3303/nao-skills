#!/usr/bin/env bash
# 用例 42 —— 设计循环静态契约（T557 · PRD docs/prds/2026-11-23-design-loop.md）
#
# 判据（AC1–AC7，全部静态、零网络、零 pi / 零 herdr）：
#   ① M1 存在：`.agents/skills/design-loop.md` 且 ≤120 行
#   ② 7 节标题在位（§一 路由表 … §七 偏好持久化）
#   ③ 关键词在位：灰模 / 概念 / 外视 / 视口 / 偏好；§四 黄金律在案（负控删除对象）
#   ④ 路由表可判：R1–R6 六类 + 「可略」列 + 边界判例（AC1）
#   ⑤ 循环 5 步 + 3 确认点（S1–S5 / CP1–CP3，AC2/AC3）
#   ⑥ 外视评审可派：材料信封 / 禁止项 / 回执形状 / `ensure --task` 样例（AC5）
#   ⑦ 视觉验收四判据（声明视口 / 截图或降级理由 / 空·加载·错误态 / 2 秒，AC6）
#   ⑧ 版权面机械闸：3 条第三方特征串（两个参考仓原句）在整个 `.agents/**` **0 命中**；
#      方法来源一行在位（BR5）
#   ⑨ 两张卡已 bump（version/updated）+ 含指向 M1 的指针；`uiux-designer.md` ≤80 行；
#      PM 卡含开工一问（不答 ⇒ 先灰模）（M2/M3）
#   ⑩ `checklists/qa.md` 四项判据关键词在位；两份清单/技能只留指针（防双源，M4/M5）
#
# 负控（在 `$T4_CACHE_DIR` 的机制副本上做，不碰仓库工作区）：
#   N1 删掉 §四（含黄金律）⇒ ⑬ 必红并点名 §四（判据非空转）
#   N2 把一条第三方特征串塞进 M1 ⇒ ⑭ 版权闸必红
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

DL_REL=".agents/skills/design-loop.md"
UIUX_REL=".agents/prompts/uiux-designer.md"
PM_REL=".agents/prompts/product-manager.md"
QA_REL=".agents/checklists/qa.md"
DOCS_REL=".agents/checklists/deliverable-docs.md"
DESIGN_REL=".agents/skills/uiux-design.md"

# 版权闸特征串（来源：两个参考仓的 README/SKILL 原句；**只在此处作「禁出现」判据**，不入任何机制文件）
C42_NEEDLES=(
  "the cheapest moment to change your mind"
  "every element to exist for a reason the user can feel"
  "Trust the real screen"
)

# c42_scan <机制根> —— 逐条打印违规；无违规 = 零输出（判据单点，真件与副本共用）
c42_scan() {
  local root="$1"
  local dl="$root/.agents/skills/design-loop.md" uiux="$root/$UIUX_REL" pm="$root/$PM_REL" qa="$root/$QA_REL"
  local t n v u

  if [ ! -f "$dl" ]; then printf '缺失: %s\n' "$DL_REL"; return 0; fi

  # ① 体量
  n="$(wc -l < "$dl")"
  [ "$n" -le 120 ] || printf '体量: design-loop.md %s 行 > 120\n' "$n"

  # ② 7 节
  for t in '## 一、路由表' '## 二、设计循环' '## 三、灰模规格' '## 四、参考→概念' \
           '## 五、独立外视评审' '## 六、视觉验收' '## 七、设计偏好持久化'; do
    grep -qF -- "$t" "$dl" || printf '缺节: %s\n' "$t"
  done

  # ③ 关键词 + 黄金律
  for t in 灰模 概念 外视 视口 偏好; do
    grep -qF -- "$t" "$dl" || printf '缺关键词: %s\n' "$t"
  done
  grep -qF -- '黄金律' "$dl" || printf '缺 §四 黄金律（AC4：参考→概念非复制）\n'

  # ④ 路由表（AC1）+ ⑤ 循环（AC2/AC3）+ ⑥ 外视评审（AC5）+ ⑦ 视觉验收（AC6）
  for t in R1 R2 R3 R4 R5 R6 可略 边界判例 S1 S2 S3 S4 S5 CP1 CP2 CP3 \
           材料信封 禁止项 回执形状 'ensure --task' 声明视口 '截图或降级理由' 加载 错误态 '2 秒'; do
    grep -qF -- "$t" "$dl" || printf '缺判据关键词: %s\n' "$t"
  done
  grep -qF -- '上色前必须' "$dl" || printf '缺闸门措辞: 上色前必须（AC2 灰模是闸门）\n'

  # ⑧ 版权面（BR5）：第三方原句 0 命中 + 方法来源一行
  for t in "${C42_NEEDLES[@]}"; do
    grep -rqF -- "$t" "$root/.agents" 2>/dev/null && printf '版权面: 命中第三方原句 <%.30s…>\n' "$t"
  done
  grep -qF -- '方法来源' "$dl" || printf '缺方法来源行（BR5）\n'
  grep -qF -- 'oil-oil/oil-ui' "$dl" || printf '方法来源缺 oil-oil/oil-ui（MIT）\n'
  grep -qF -- 'antislop-ui-ux-skill' "$dl" || printf '方法来源缺 antislop-ui-ux-skill（All Rights Reserved）\n'

  # ⑨ 卡 bump + 指针（M2/M3）
  v="$(sed -n 's/^version: *//p' "$uiux" | head -1)"
  u="$(sed -n 's/^updated: *//p' "$uiux" | head -1)"
  { [ -n "$v" ] && [ "$v" -ge 3 ] 2>/dev/null; } || printf 'uiux-designer.md version=%s 未 bump（期望 ≥3）\n' "${v:-<缺失>}"
  [[ "$u" > "2026-11-22" ]] || printf 'uiux-designer.md updated=%s 未刷新（期望 ≥2026-11-23）\n' "${u:-<缺失>}"
  n="$(wc -l < "$uiux")"
  [ "$n" -le 80 ] || printf '体量: uiux-designer.md %s 行 > 80\n' "$n"
  grep -qF -- 'design-loop.md' "$uiux" || printf 'uiux-designer.md 缺指向 design-loop.md 的指针\n'
  for t in 灰模 屏幕角色句 '参考→概念' 外视评审; do
    grep -qF -- "$t" "$uiux" || printf 'uiux-designer.md 缺要点: %s\n' "$t"
  done

  v="$(sed -n 's/^version: *//p' "$pm" | head -1)"
  u="$(sed -n 's/^updated: *//p' "$pm" | head -1)"
  { [ -n "$v" ] && [ "$v" -ge 40 ] 2>/dev/null; } || printf 'product-manager.md version=%s 未 bump（期望 ≥40）\n' "${v:-<缺失>}"
  [[ "$u" > "2026-11-22" ]] || printf 'product-manager.md updated=%s 未刷新（期望 ≥2026-11-23）\n' "${u:-<缺失>}"
  grep -qF -- 'design-loop.md' "$pm" || printf 'product-manager.md 缺指向 design-loop.md 的指针\n'
  grep -qF -- '先出灰模再上色' "$pm" || printf 'product-manager.md 缺开工一问原文（先出灰模再上色）\n'
  grep -qF -- '先灰模' "$pm" || printf 'product-manager.md 缺「不答 ⇒ 先灰模」默认口径\n'

  # ⑩ 清单四项判据 + 防双源指针（M4/M5）
  for t in 声明视口 '截图或降级理由' 加载 错误态 '2 秒'; do
    grep -qF -- "$t" "$qa" || printf 'qa.md 缺判据关键词: %s\n' "$t"
  done
  grep -qF -- 'design-loop.md' "$root/$DESIGN_REL" || printf 'uiux-design.md 缺指向 design-loop.md 的指针（防双源）\n'
  grep -qF -- 'design-loop.md' "$root/$DOCS_REL" || printf 'deliverable-docs.md §九 缺指向 design-loop.md 的指针（防双源）\n'
}

# ---------------------------------------------------------------- 真件判据（空 = 全过）
out="$(c42_scan "$T4_ROOT")"
t4_assert_eq "" "$out" "①–⑩ 静态契约全过（违规清单为空）"
if [ -n "$out" ]; then printf '%s\n' "$out" | sed 's/^/     ↳ /'; fi

# 定向断言（回执可读：把契约钉到 AC 编号）
DL="$T4_ROOT/$DL_REL"
t4_assert_file "$DL" "AC1: M1 技能文件存在（$DL_REL）"
t4_assert_eq "7" "$(grep -cE '^## [一二三四五六七]、' "$DL" || true)" "AC1: 恰 7 节标题"
t4_assert_eq "6" "$(grep -cE '^- \*\*R[1-6] ' "$DL" || true)" "AC1: 路由表 6 类各占一条（R1–R6）"
t4_assert_contains "$(cat "$DL")" "上色前必须有这一步的组织确认" "AC2: 灰模是闸门（上色前须有组织确认）"
t4_assert_contains "$(cat "$T4_ROOT/$UIUX_REL")" "灰模先行" "AC2: uiux 卡有灰模先行红线"
t4_assert_contains "$(cat "$T4_ROOT/$UIUX_REL")" "这屏存在是为了" "AC3: 屏幕角色句写进 M2 且带原句"
t4_assert_contains "$(cat "$DL")" "它不是 ___ 的屏" "AC3: 屏幕角色句格式在 M1"
t4_assert_contains "$(cat "$DL")" "丢了什么视觉" "AC4: 参考→概念三行留痕（含「丢了什么视觉」）"
t4_assert_contains "$(cat "$DL")" "被评审方**不先解释设计意图**" "AC5: 外视评审禁止自证"
t4_assert_match "$(cat "$DL")" 'ensure --task <编号> <角色>' "AC5: 派发命令样例为 ensure --task 形态"
t4_assert_contains "$(cat "$T4_ROOT/$QA_REL")" "视觉验收四判据" "AC6: qa.md 四项判据小节在位"
t4_assert_eq "4" "$(grep -cE '^- \[ \] \*\*[①②③④] ' "$T4_ROOT/$QA_REL" || true)" "AC6: 恰四项可勾选判据"
t4_assert_contains "$(cat "$DL")" "docs/designs/design-preferences.md" "AC7/§七: 偏好持久化载体在位"
t4_assert_contains "$(cat "$DL")" "一次需求最多追加 3 行" "§七: 偏好追加上限（3 行）在位"
t4_assert_eq "0" "$(grep -rhoF -- "${C42_NEEDLES[0]}" "$T4_ROOT/.agents" 2>/dev/null | wc -l)" "BR5: 第三方原句 1/3 在 .agents 内 0 命中"
t4_assert_eq "0" "$(grep -rhoF -- "${C42_NEEDLES[1]}" "$T4_ROOT/.agents" 2>/dev/null | wc -l)" "BR5: 第三方原句 2/3 在 .agents 内 0 命中"
t4_assert_eq "0" "$(grep -rhoF -- "${C42_NEEDLES[2]}" "$T4_ROOT/.agents" 2>/dev/null | wc -l)" "BR5: 第三方原句 3/3 在 .agents 内 0 命中"
t4_assert_match "$(cat "$DL")" '^方法来源：' "BR5: 方法来源恰为独立一行且带许可证名"

# ---------------------------------------------------------------- 负控（副本改一处 ⇒ 必红）
LAB="$T4_CACHE_DIR/lab42-$$"
mkdir -p "$LAB" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

# N1：删掉 §四（含黄金律）⇒ 必红且点名 §四
awk '/^## 四、/{skip=1;next} /^## 五、/{skip=0} !skip' "$LAB/$DL_REL" > "$LAB/dl.n1" && mv "$LAB/dl.n1" "$LAB/$DL_REL"
n1="$(c42_scan "$LAB")"
t4_assert_contains "$n1" "缺 §四 黄金律" "⑬ N1 负控（必红）：删 §四 ⇒ 点名黄金律缺失"
t4_assert_not_contains "$n1" "缺失: $DL_REL" "⑬ N1 负控：文件仍在（红点来自 §四，不是整文件消失）"
cp "$T4_ROOT/$DL_REL" "$LAB/$DL_REL"

# N2：把一条第三方原句塞进 M1 ⇒ 版权闸必红
printf '\n%s\n' "${C42_NEEDLES[0]}" >> "$LAB/$DL_REL"
t4_assert_contains "$(c42_scan "$LAB")" "版权面: 命中第三方原句" "⑭ N2 负控（必红）：注入第三方原句 ⇒ 版权闸咬住"

# 复原 ⇒ 复绿（先红后绿闭合）
cp "$T4_ROOT/$DL_REL" "$LAB/$DL_REL"
t4_assert_eq "" "$(c42_scan "$LAB")" "⑮ 复原后副本复绿（禁「红了就算过」）"

t4_exit
