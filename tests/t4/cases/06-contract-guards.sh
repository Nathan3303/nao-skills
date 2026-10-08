#!/usr/bin/env bash
# 用例 06 —— 契约守护（补齐 T4 三处 partial：AC6 机制侧 / AC8 / AC2 静态替代）
#
# AC6（机制侧）: `check` 交叉引用绿 + 全仓 `.agents/**` 引用一致（无废弃路径、NAO_SKILLS 引用可达）
#              文档侧（README/ARCHITECTURE/模板）→ T3 关闭（本轮显式标注，不判 FAIL）
# AC8        : manifest 无 `pi.prompts` + 未被 manifest 引用 `.agents/prompts/*.md`
#              + fleet 仍以 `--append-system-prompt` 常驻注入（BR2）
# AC2（静态）: SKILL.md description 含「何时加载」触发语 + 「拉起舰队」指引；name == 父目录名
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm

# --- AC8：manifest 不承载 prompt / 常驻注入不变 -----------------------------
pi_refs="$(node -e '
const p=require(process.argv[1]+"/package.json");
const pi=p.pi||{};
console.log("has_prompts="+(pi.prompts===undefined?0:1));
const all=JSON.stringify(pi);
console.log("refs_prompts="+(all.includes(".agents/prompts")?1:0));
console.log("skills="+JSON.stringify(pi.skills||[]));
' "$T4_ROOT" 2>&1)"
t4_info "manifest: $(printf '%s' "$pi_refs" | tr '\n' ' ')"
t4_assert_eq "0" "$(printf '%s\n' "$pi_refs" | sed -n 's/^has_prompts=//p')" "AC8: manifest 无 pi.prompts"
t4_assert_eq "0" "$(printf '%s\n' "$pi_refs" | sed -n 's/^refs_prompts=//p')" "AC8: manifest 未引用 .agents/prompts/*.md"
t4_assert_ge 1 "$(grep -c -- '--append-system-prompt' "$T4_ROOT/.agents/scripts/nao-fleet.sh")" "AC8: fleet 仍以 --append-system-prompt 常驻注入角色卡（BR2）"

# --- AC6（机制侧）：check 交叉引用 + 引用一致性 ------------------------------
of="$(mktemp)"; ef="$(mktemp)"
( cd "$T4_ROOT" && timeout 120 bash .agents/scripts/nao-fleet.sh check ) >"$of" 2>"$ef"
rc=$?; out="$(cat "$of")"; err="$(cat "$ef")"; rm -f "$of" "$ef"
t4_info "check rc=$rc · $(printf '%s' "$out" | head -1)"
t4_assert_eq "0" "$rc" "AC6: 机制 check（含交叉引用校验）exit=0"
t4_assert_contains "$out" "check: OK" "AC6: check 输出 OK"

obsolete="$(grep -rln 'skills/checklists' "$T4_ROOT/.agents" --exclude-dir=.nao-obsolete 2>/dev/null || true)"
t4_assert_eq "" "$obsolete" "AC6: 无指向废弃路径 .agents/skills/checklists 的 live 引用"

# NAO_SKILLS 引用可达：抽取 `$NAO_SKILLS/.agents/<path>`，逐个在包内解析
refs="$(grep -rhoE '\$NAO_SKILLS/\.agents/[A-Za-z0-9_./*-]+' "$T4_ROOT/.agents" --include='*.md' 2>/dev/null | sed 's#^\$NAO_SKILLS/##' | sort -u)"
bad=""
n=0
while IFS= read -r r; do
  [ -n "$r" ] || continue
  n=$((n + 1))
  # shellcheck disable=SC2086
  if ! compgen -G "$T4_ROOT/$r" >/dev/null 2>&1; then bad="$bad $r"; fi
done <<< "$refs"
t4_info "NAO_SKILLS 引用 $n 条 · 不可达:${bad:- 无}"
t4_assert_eq "" "${bad# }" 'AC6: 全部 $NAO_SKILLS/.agents 引用在包内可达'
t4_note "AC6 文档侧（README / ARCHITECTURE / 模板对齐）→ T3 关闭，本轮不判"

# --- AC2（静态替代）：SKILL 入口可发现性与指引 ------------------------------
sk="$T4_ROOT/.agents/skills/nao-fleet/SKILL.md"
t4_assert_file "$sk" "AC2: nao-fleet SKILL.md 存在"
body="$(cat "$sk" 2>/dev/null)"
t4_assert_match "$body" '当用户' "AC2: description/正文含触发条件（何时加载）"
t4_assert_contains "$body" "拉起舰队" "AC2: 含「拉起舰队」指引"
for s in nao-fleet frontend-design; do
  nm="$(sed -n 's/^name:[[:space:]]*//p' "$T4_ROOT/.agents/skills/$s/SKILL.md" | head -1 | tr -d '\r')"
  t4_assert_eq "$s" "$nm" "AC2: $s 的 name == 父目录名"
done
t4_note "AC2 动态发现（真 pi 加载）见 T4-02；无凭据时以本条静态断言为替代证据"

t4_exit
