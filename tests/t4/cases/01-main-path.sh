#!/usr/bin/env bash
# 用例 01 —— 主路径：足迹 + check exit=0（PRD AC1 / S1）
#
# Given 本地物化的包 + 空项目
# When  node <pkg>/bin/nao-skill.js init
# Then  足迹 = AGENTS.md + .pi/settings.json + .pi/npm(未跟踪) + .agents(shim)
#       且 shim `check` exit=0
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
t4_require_cmd git
t4_require_cli init

fx="$(t4_fixture)"
t4_log "夹具: $fx"
t4_materialize "$fx"

t4_run_init "$fx"
t4_info "init rc=$T4_RC"
[ "$T4_RC" -eq 0 ] && t4_ok "init exit=0" || t4_bad "init exit=$T4_RC（$(printf '%s' "$T4_ERR" | head -2 | tr '\n' ' ')）"

# --- 足迹形状 ---------------------------------------------------------------
t4_assert_file "$fx/.pi/settings.json" "足迹: .pi/settings.json 存在"
t4_assert_contains "$(cat "$fx/.pi/settings.json" 2>/dev/null)" "npm:${PKG_NAME}@${PKG_VERSION}" ".pi/settings.json 记录 pin 版本 ${PKG_VERSION}"
t4_assert_dir "$fx/.pi/npm/node_modules/$PKG_NAME" "足迹: 包物化于 .pi/npm（项目内）"
t4_assert_file "$fx/AGENTS.md" "足迹: AGENTS.md 存在"
t4_assert_file "$(t4_shim "$fx")" "足迹: .agents/scripts/nao-fleet.sh（shim）存在"

# .agents 仅 shim：live 文件集 ⊆ {scripts/nao-fleet.sh, .nao-version}
live_files="$(find "$fx/.agents" -type f -not -path '*/.nao-obsolete/*' -printf '%P\n' 2>/dev/null | sort)"
t4_info ".agents live 文件: $(printf '%s' "$live_files" | tr '\n' ' ')"
extra="$(printf '%s\n' "$live_files" | grep -vE '^(scripts/nao-fleet\.sh|\.nao-version)$' || true)"
t4_assert_eq "" "$extra" ".agents/ 仅含 shim（无机制副本）"

for d in prompts common checklists skills templates; do
  t4_assert_absent "$fx/.agents/$d" ".agents/$d 未落盘（机制在包内）"
done

# 项目根未平铺 nao 机制
top="$(ls -A "$fx" | grep -v '^\.git$' | sort | tr '\n' ' ')"
t4_info "项目根条目: $top"
bad_top="$(printf '%s\n' "$(ls -A "$fx")" | grep -vE '^(\.git|AGENTS\.md|\.agents|\.pi)$' || true)"
t4_assert_eq "" "$bad_top" "项目根无额外 nao 机制条目"

# .pi/npm 未跟踪（pi 自建 .gitignore）——node_modules 内容必须被忽略
untracked_all="$(cd "$fx" && git status --porcelain --untracked-files=all -- .pi/npm 2>/dev/null)"
node_mod_hits="$(printf '%s\n' "$untracked_all" | grep -c 'node_modules' || true)"
t4_info ".pi/npm 未跟踪条目: $(printf '%s' "$untracked_all" | tr '\n' ' ')"
t4_assert_eq "0" "$node_mod_hits" ".pi/npm/node_modules 未被 git 跟踪（.gitignore 生效）"
if ( cd "$fx" && git check-ignore -q ".pi/npm/node_modules/$PKG_NAME/package.json" ); then
  t4_ok "git check-ignore 命中 .pi/npm/node_modules/**"
else
  t4_bad "git check-ignore 未忽略 .pi/npm/node_modules/**（pi 自建 .gitignore 缺失？）"
fi

# --- check 走 shim，exit=0 --------------------------------------------------
t4_run_shim "$fx" -u NAO_SKILLS -u NAO_SHIM_ENTERED
t4_info "check rc=$T4_RC · out=$(printf '%s' "$T4_OUT" | head -1)"
t4_assert_eq "0" "$T4_RC" "shim check exit=0"
t4_assert_contains "$T4_OUT" "check: OK" "check 输出含 'check: OK'"
t4_assert_not_contains "$T4_OUT$T4_ERR" "DEGRADED" "正常路径无 DEGRADED 降级"

t4_exit
