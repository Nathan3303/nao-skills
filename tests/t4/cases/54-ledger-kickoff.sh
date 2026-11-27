#!/usr/bin/env bash
# 用例 54 —— 台账 / 开工卡结构探针（`check_ledger_structure`）的持久用例（T580 · #238）
#
# 被测：`.agents/scripts/fleet/lib/check.sh::check_ledger_structure`（**warn-only**：不计 warn、不改 rc）。
# 判据（九条，PRD AC1/AC2/AC3/AC5/AC6/AC7/AC8/AC9）：
#   ① 主路径：台账结构齐 + 卡 10 字段齐 ⇒ 零输出、rc=0（`-v` 回显活批次/锚点计数）
#   ② AC2 状态值域外（`搞定了` / `done`）⇒ 点名并给合法值清单
#   ③ AC3 卡缺字段 ⇒ 点名缺失字段名；补回后归零（先红后绿）
#   ④ AC5 完成项残留 ⇒ 点名「已完成批次 … 仍占卡摘要」
#   ⑤ AC6 有卡无台账行 ⇒ 点名
#   ⑥ 主台账 >300 行 ⇒ 点名
#   ⑦ 卡表头非逐字 ⇒ 点名
#   ⑧ AC7 表格边界两向：新布局 `prd.md` 含表格 ⇒ PRD 探针点名；`kickoff.md` 用表格 ⇒ 台账探针不报
#   ⑨ 本仓：台账探针零输出 + `check` 输出与「探针关闭」逐字一致（md5）
#
# 负控（三条，全部走「副本改一处 ⇒ 判据必红」）：
#   N1 删掉 `check_ledger_structure` 调用 ⇒ ② 的提示必消失（判据非空转）
#   N2 把 `'^  ! 台账'` 从摘要计数的排除名单去掉 ⇒ ⑨ 的「不计 warn」必红（`warn=` 出现）
#   N3 取反状态值域判据 ⇒ 合法状态也被报（② 的判据承重）
#
# 后端无关（只跑 bash + 夹具 `.agents`，不建 terminal server；不 exec 真 pi）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET_REAL="$T4_ROOT/.agents/scripts/nao-fleet.sh"
t4_assert_file "$FLEET_REAL" "前置：被测脚本存在"

LAB="$T4_CACHE_DIR/lab54-$$"
mkdir -p "$LAB/docs" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

t54_exit_trap() {
  local rc=$?
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t54_exit_trap EXIT

c54_out() { # <lab> [check 参数...]
  local lab="$1"; shift
  ( cd "$lab" && env -u NAO_STASH_ROOT -u NAO_TASKS_STATE bash .agents/scripts/nao-fleet.sh check "$@" 2>&1 )
}
c54_agg() { printf '%s\n' "$1" | grep -cE '^  ! 台账' || true; }
c54_det() { printf '%s\n' "$1" | grep -cE '^  · 台账：' || true; }

# ---------------------------------------------------------------- 夹具：归档 + 台账 + 卡
c54_mkfixture() { # <lab>
  local d="$1"
  mkdir -p "$d/docs/T999-x"
  cat > "$d/docs/tasks-archive.md" <<'EOF'
# 任务台账历史存档（夹具）

<a id="T900"></a>
## T900 · 已归档夹具

- ✅ 夹具历史批次（合并 `abc1234` · Issue #900 · PR #901）
EOF
  cat > "$d/docs/tasks-state.md" <<'EOF'
# 任务状态（PM 维护，运行时事实）

## 批次索引（已完成批次 → 归档锚点）

| 任务号 | 归档锚点 | 状态 | 完成日期 |
| :--- | :--- | :--- | :--- |
| T900 | `docs/tasks-archive.md#T900` | 已合并 | 2026-11-01 |

## T999 · fixture

| 任务号 | 目标 | 角色链 | 状态 | 完成日期 | 卡指针 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — | `docs/T999-x/kickoff.md` |
EOF
  cat > "$d/docs/T999-x/kickoff.md" <<'EOF'
# 开工确认卡 · T999

| 字段 | 内容 |
| :--- | :--- |
| 任务号 | T999 |
| 目标（一句话） | 夹具 |
| 角色链 | `pm` → `qa` |
| AC 指针 | `docs/T999-x/prd.md` §七 |
| 门禁 | `check` rc=0 |
| 红线 | 不动历史 |
| 待澄清 / 待拍 | 无 |
| 设计类 | 不适用（纯文本） |
| 发布节奏 | PATCH（夹具） |
| 用户确认结论 | 2026-11-27 夹具 |
EOF
}
c54_mkfixture "$LAB"

# ---------------------------------------------------------------- ① 主路径 ⇒ 零输出 + rc=0
OUT1="$(c54_out "$LAB")"; RC1=$?
t4_assert_eq "0" "$RC1" "① 主路径：台账 + 卡结构齐 ⇒ check rc=0"
t4_assert_eq "0" "$(c54_agg "$OUT1")" "① 主路径：台账探针零输出"
OUT1V="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT1V" "✓ 台账：活批次 1 个 · 归档锚点 1 个" "① -v 回显活批次与归档锚点计数（AC1）"

# ---------------------------------------------------------------- ② AC2 状态值域外
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/| T999 | 夹具目标 | `pm` → `qa` | 搞定了 | — |/' "$LAB/docs/tasks-state.md"
OUT2="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT2" "状态值域外：搞定了" "② 非法状态：点名原文（AC2）"
t4_assert_contains "$OUT2" "待开工 / 进行中 / 待验收 / 已合并 / 已发布 / 已关闭" "② 非法状态：给出 6 值清单"
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 搞定了 | — |/| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/' "$LAB/docs/tasks-state.md"
t4_assert_eq "0" "$(c54_agg "$(c54_out "$LAB")")" "② 改回合法值 ⇒ 归零（先红后绿）"

# ---------------------------------------------------------------- ③ AC3 卡缺字段
sed -i '/^| 发布节奏 | PATCH（夹具） |$/d' "$LAB/docs/T999-x/kickoff.md"
OUT3="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT3" "缺字段：发布节奏" "③ 卡缺字段：点名缺失字段（AC3）"
OUT3B="$(c54_out "$LAB")"; RC3=$?
t4_assert_eq "0" "$RC3" "③ 卡缺字段不改 rc（warn-only）"
printf '| 发布节奏 | PATCH（夹具） |\n' >> "$LAB/docs/T999-x/kickoff.md"
t4_assert_eq "0" "$(c54_det "$(c54_out "$LAB" -v)")" "③ 补回字段 ⇒ 明细归零（先红后绿）"

# ---------------------------------------------------------------- ④ AC5 完成项残留
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/| T999 | 夹具目标 | `pm` → `qa` | 已发布 | 2026-11-27 |/' "$LAB/docs/tasks-state.md"
OUT4="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT4" "仍占卡摘要" "④ 完成项残留：点名「已完成批次 … 仍占卡摘要」（AC5）"
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 已发布 | 2026-11-27 |/| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/' "$LAB/docs/tasks-state.md"

# ---------------------------------------------------------------- ⑤ AC6 有卡无台账行
mkdir -p "$LAB/docs/T998-y" && cp "$LAB/docs/T999-x/kickoff.md" "$LAB/docs/T998-y/kickoff.md" \
  && sed -i 's/T999/T998/g' "$LAB/docs/T998-y/kickoff.md"
OUT5="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT5" "docs/T998-y/kickoff.md 有卡但台账无对应段/行" "⑤ 有卡无台账行：点名（AC6）"
rm -rf "$LAB/docs/T998-y"
t4_assert_eq "0" "$(c54_agg "$(c54_out "$LAB")")" "⑤ 删掉孤儿卡 ⇒ 归零"

# ---------------------------------------------------------------- ⑥ 台账 >300 行
for ((i = 0; i < 320; i++)); do printf -- '- 垫行 %d\n' "$i" >> "$LAB/docs/tasks-state.md"; done
OUT6="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT6" "行 > 300" "⑥ 主台账超长：点名（PRD 目标 ≤300 行）"
c54_mkfixture "$LAB"   # 还原台账与卡

# ---------------------------------------------------------------- ⑦ 卡表头非逐字
sed -i 's/^| 字段 | 内容 |$/| 项 | 值 |/' "$LAB/docs/T999-x/kickoff.md"
OUT7="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT7" "表头非逐字（应为 \`| 字段 | 内容 |\`）" "⑦ 卡表头被改 ⇒ 点名（结构非法，不放行）"
c54_mkfixture "$LAB"

# ---------------------------------------------------------------- ⑧ AC7 表格边界两向
mkdir -p "$LAB/docs/T997-z"
cat > "$LAB/docs/T997-z/prd.md" <<'EOF'
# PRD：表格夹具

## TL;DR
- 夹具

## 一、问题证据
| 列A | 列B |
| :-- | :-- |
| 1 | 2 |

## 二、目标指标
x

## 三、范围 / 非范围
x

## 四、用户场景
x

## 五、业务规则
x

## 六、NFRs
x

## 七、AC

### 主路径
- AC1：x

### 异常
- AC2：x

### 边界
- AC3：x

### 负向闭环
- AC4：x

### 设计一致性
- AC5：x

## 八、上线闭环
x

## 九、变更治理
x
EOF
OUT8="$(c54_out "$LAB" -v)"
t4_assert_contains "$OUT8" "正文含表格" "⑧ PRD 正文含表格 ⇒ 结构探针仍点名（AC7 ① 不放松）"
t4_assert_eq "0" "$(c54_agg "$OUT8")" "⑧ kickoff.md 用表格 ⇒ 台账探针不报（AC7 ② 两向成立）"
rm -rf "$LAB/docs/T997-z"

# ---------------------------------------------------------------- ⑨ 本仓：零输出 + 与「探针关闭」逐字一致
REF="$T4_CACHE_DIR/lab54-ref-$$"
mkdir -p "$REF" && cp -r "$T4_ROOT/.agents" "$REF/.agents" || t4_bad "⑨ 夹具：复制 .agents 失败"
REF_CHECK="$(t4_fleet_file_for "$REF/.agents/scripts" cmd_check)"
t4_assert_ne "" "${REF_CHECK:-}" "⑨ 夹具：定位到 cmd_check 所在模块"
sed -i '/^  check_ledger_structure || true$/d' "$REF_CHECK"
t4_assert_eq "0" "$(grep -c 'check_ledger_structure || true' "$REF_CHECK" || true)" \
  "⑨ 负控锚点：副本已删掉探针调用（自证变异生效）"
OUT_REAL="$( cd "$T4_ROOT" && env -u NAO_STASH_ROOT bash "$FLEET_REAL" check 2>&1 )"
OUT_OFF="$( cd "$T4_ROOT" && env -u NAO_STASH_ROOT bash "$REF/.agents/scripts/nao-fleet.sh" check 2>&1 )"
t4_assert_eq "0" "$(c54_agg "$OUT_REAL")" "⑨ 本仓：台账探针零输出（台账已迁移 + 卡 10 字段齐）"
t4_assert_not_contains "$OUT_REAL" "warn=" "⑨ 本仓：摘要不出现 warn=（不计入 warn 计数）"
t4_assert_eq "$(printf '%s\n' "$OUT_OFF" | md5sum | awk '{print $1}')" \
  "$(printf '%s\n' "$OUT_REAL" | md5sum | awk '{print $1}')" \
  "⑨ 本仓：check 输出与「探针关闭」逐字一致（md5 相等）"

# ---------------------------------------------------------------- N1 删调用 ⇒ ② 必红消失
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/| T999 | 夹具目标 | `pm` → `qa` | 搞定了 | — |/' "$LAB/docs/tasks-state.md"
t4_assert_eq "0" "$( cd "$LAB" && env -u NAO_STASH_ROOT bash "$REF/.agents/scripts/nao-fleet.sh" check -v 2>&1 | grep -cE '^  ! 台账' || true )" \
  "N1 删掉探针调用 ⇒ 同一夹具 0 条提示（② 的判据非空转；还原即复绿）"
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 搞定了 | — |/| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/' "$LAB/docs/tasks-state.md"

# ---------------------------------------------------------------- N2 去排除名单 ⇒ warn= 必现
N2="$T4_CACHE_DIR/lab54-n2-$$"
mkdir -p "$N2" && cp -r "$T4_ROOT/.agents" "$N2/.agents" || t4_bad "N2 夹具：复制 .agents 失败"
t4_assert_eq "1" "$(grep -c "e '\^  ! 台账'" "$N2/.agents/scripts/nao-fleet.sh" || true)" \
  "N2 负控锚点：原脚本排除名单含台账提示前缀"
sed -i "s/ -e '\^  ! 台账'//" "$N2/.agents/scripts/nao-fleet.sh"
mkdir -p "$N2/docs" && cp -r "$LAB/docs/T999-x" "$N2/docs/T999-x" && cp "$LAB/docs/tasks-archive.md" "$N2/docs/tasks-archive.md" && cp "$LAB/docs/tasks-state.md" "$N2/docs/tasks-state.md"
sed -i 's/^| T999 | 夹具目标 | `pm` → `qa` | 进行中 | — |/| T999 | 夹具目标 | `pm` → `qa` | done | — |/' "$N2/docs/tasks-state.md"
OUT_N2="$( cd "$N2" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check 2>&1 )"
t4_assert_contains "$OUT_N2" "warn=" "N2 去掉排除名单 ⇒ 摘要出现 warn=（⑨ 必红 ⇒ 排除名单是承重的）"

# ---------------------------------------------------------------- N3 取反状态值域 ⇒ 合法值也被报
N3="$T4_CACHE_DIR/lab54-n3-$$"
mkdir -p "$N3" && cp -r "$T4_ROOT/.agents" "$N3/.agents" || t4_bad "N3 夹具：复制 .agents 失败"
N3_CHECK="$(t4_fleet_file_for "$N3/.agents/scripts" check_ledger_structure)"
t4_assert_ne "" "${N3_CHECK:-}" "N3 夹具：定位到台账探针所在模块"
t4_assert_eq "1" "$(grep -c 'C\[4\] !~ /^(待开工|进行中|待验收|已合并|已发布|已关闭)\$/' "$N3_CHECK" || true)" \
  "N3 负控锚点：原脚本含状态值域判据"
sed -i 's/(待开工|进行中|待验收|已合并|已发布|已关闭)/(待开工)/' "$N3_CHECK"
mkdir -p "$N3/docs" && cp -r "$LAB/docs/T999-x" "$N3/docs/T999-x" && cp "$LAB/docs/tasks-archive.md" "$N3/docs/tasks-archive.md" && cp "$LAB/docs/tasks-state.md" "$N3/docs/tasks-state.md"
OUT_N3="$( cd "$N3" && env -u NAO_STASH_ROOT bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$OUT_N3" "状态值域外：进行中" "N3 取反值域 ⇒ 合法状态也被报（② 的判据承重）"

rm -rf "$REF" "$N2" "$N3"
t4_exit 0
