#!/usr/bin/env bash
# 用例 05 —— 迁移精准删除 + 备份 + 共享目录保留（PRD AC4 / §12-C·D / BR4·BR5）
#
# Given 旧版全套 .agents/（含共享 skills 目录，模拟 nue-ui / nao-todo 下游）
# When  执行迁移
# Then  共享 .agents/skills/ 不被整目录删除；nao 资产备份到 .agents/.nao-obsolete/；
#       frontend-design 从 live 移除（D3 去重）；shim 就位；旧入口 check exit=0；
#       迁移提示仅一次（第二次不再提示）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
if ! t4_cli_supports migrate && ! t4_cli_supports init; then
  t4_blocked "CLI 既无 migrate 也无 init（T2 bin/）"
fi

fx="$(t4_fixture)"
mkdir -p "$fx/.agents"
cp -a "$T4_ROOT/.agents/." "$fx/.agents/"
printf '0.0.1-legacy\n' > "$fx/.agents/.nao-version"   # 模拟旧版标记（非当前版本断言）

# 模拟下游共享 skill 目录（PRD §12-D 实测清单）
for s in nue-ui-dev agent-browser find-skills skill-creator nue-ui; do
  mkdir -p "$fx/.agents/skills/$s"
  printf -- '---\nname: %s\ndescription: downstream shared skill (must survive migration)\n---\n' "$s" \
    > "$fx/.agents/skills/$s/SKILL.md"
done
t4_assert_file "$fx/.agents/skills/frontend-design/SKILL.md" "前置: 旧版含 nao 资产 frontend-design"
t4_assert_dir "$fx/.agents/prompts" "前置: 旧版含 .agents/prompts"

t4_materialize "$fx"

# --- 第一次迁移 -------------------------------------------------------------
t4_run_migrate "$fx"
run1="$T4_OUT$T4_ERR"
t4_info "migrate#1 rc=$T4_RC"
[ "$T4_RC" -eq 0 ] && t4_ok "迁移 exit=0（或幂等非致命）" || t4_info "迁移 rc=$T4_RC（若非 0 将以下方状态断言判定）"

# --- 精准删除 / 共享保留 ----------------------------------------------------
for s in nue-ui-dev agent-browser find-skills skill-creator nue-ui; do
  t4_assert_dir "$fx/.agents/skills/$s" "共享 skill 目录保留: $s（禁止整目录删除）"
done
t4_assert_absent "$fx/.agents/skills/frontend-design" "nao 资产 frontend-design 从 live 移除（D3 去重）"

# --- 备份到 .nao-obsolete ---------------------------------------------------
t4_assert_dir "$fx/.agents/.nao-obsolete" ".agents/.nao-obsolete 备份目录存在"
ob_files="$(find "$fx/.agents/.nao-obsolete" -type f 2>/dev/null | wc -l)"
t4_assert_ge 5 "$ob_files" "备份文件数 >= 5（nao 资产已备份）"
ob_fd="$(find "$fx/.agents/.nao-obsolete" -path '*frontend-design*' 2>/dev/null | head -1)"
t4_assert_ne "" "$ob_fd" "备份中含 frontend-design"
ob_mech="$(find "$fx/.agents/.nao-obsolete" \( -name 'pm.md' -o -name 'roles.yaml' -o -path '*checklists*' -o -path '*prompts*' -o -path '*common*' \) 2>/dev/null | head -1)"
t4_assert_ne "" "$ob_mech" "备份中含旧机制资产（prompts/checklists/common）"

# --- live 机制副本清空 + shim 就位 -----------------------------------------
for d in prompts checklists common; do
  t4_assert_absent "$fx/.agents/$d" "live .agents/$d 已移除（机制以包为单一来源，BR5）"
done
t4_require_shim "$fx"

# --- 旧入口仍可用 -----------------------------------------------------------
t4_run_shim "$fx" -u NAO_SKILLS -u NAO_SHIM_ENTERED
t4_info "迁移后 check rc=$T4_RC · out=$(printf '%s' "$T4_OUT" | head -1)"
t4_assert_eq "0" "$T4_RC" "迁移后 .agents/scripts/nao-fleet.sh check exit=0（旧路径可用）"

# --- 迁移提示仅一次 ---------------------------------------------------------
t4_assert_match "$run1" '(迁移|migrat|nao-obsolete)' "第一次迁移输出含迁移提示"
t4_run_migrate "$fx"
run2="$T4_OUT$T4_ERR"
n2="$(printf '%s\n' "$run2" | grep -cE '(迁移|migrat|nao-obsolete)' || true)"
t4_assert_eq "0" "$n2" "第二次迁移不再提示（每版本一次，BR4）"

t4_exit
