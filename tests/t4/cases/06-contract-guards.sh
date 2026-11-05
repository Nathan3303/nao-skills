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
t4_note static-contract "AC6 文档侧（README / ARCHITECTURE / 模板对齐）→ T3 关闭，本轮不判"

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
t4_note static-contract "AC2 动态发现（真 pi 加载）见 T4-02；无凭据时以本条静态断言为替代证据"

# --- 门禁接线契约（T522 · PRD §三.1/2 · BR1/BR4/BR5）------------------------
# 防「接线被后人摘掉无人报警」+ 封第三类假绿（用例脚本不以 t4_exit|t4_skip|exec 收尾时，
# T4_FAIL 计数已累加但进程 rc 仍 0 ⇒ 假绿）。断言实体由 QA 维护。
scripts_tsv="$(node -e '
const s=require(process.argv[1]+"/package.json").scripts||{};
console.log("test="+(s.test||""));
console.log("full="+(s["test:t4:full"]||""));
console.log("prepack="+(s.prepack||""));
' "$T4_ROOT" 2>&1)"
script_test="$(printf '%s\n' "$scripts_tsv" | sed -n 's/^test=//p')"
script_full="$(printf '%s\n' "$scripts_tsv" | sed -n 's/^full=//p')"
script_prepack="$(printf '%s\n' "$scripts_tsv" | sed -n 's/^prepack=//p')"
t4_info "scripts: test=[$script_test] full=[$script_full] prepack=[$script_prepack]"

# ① 默认门禁真串联 t4（防「装饰性接线」：写了 test:t4 但 test 不调用它）
t4_assert_contains "$script_test" "npm run test:t4" "T522 BR1: scripts.test 串联 npm run test:t4"

# ② full 闸门两轴齐备（缺产物轴 + 能力轴；任一缺失则发布判据退化）
axes=""
printf '%s' "$script_full" | grep -qF 'T4_ALLOW_MISSING=0' && axes="${axes}A"
printf '%s' "$script_full" | grep -qF 'T4_REQUIRE_FULL=1' && axes="${axes}R"
t4_assert_eq "AR" "$axes" "T522 BR4: test:t4:full 同时含两严格轴 A(T4_ALLOW_MISSING=0)+R(T4_REQUIRE_FULL=1)"

# ③ prepack 与 t4 解耦（发布/打包不被 ≈2min + 网络/凭据/tmux 阻塞，BR5）
#   变异控制实证：仅断言「不含 test:t4」会漏掉 prepack="npm test"（间接引入 t4，X3 曾假通过）
#   ⇒ 正向钉住 test:agents，且同时排除直连 test:t4 与经由 npm test 的间接引入。
pre_ok=""
if printf '%s' "$script_prepack" | grep -qF 'test:agents' \
   && ! printf '%s' "$script_prepack" | grep -qE '(^|[^:[:alnum:]_-])npm test([^[:alnum:]_-]|$)' \
   && ! printf '%s' "$script_prepack" | grep -qF 'test:t4'; then pre_ok=1; fi
t4_assert_eq "1" "$pre_ok" "T522 BR5: scripts.prepack 仅 test:agents（无直连 test:t4 亦无 npm test 间接引入）"

# ④ 全部用例以收尾函数结束（封第三类假绿：只累 T4_FAIL 不退出 ⇒ rc=0）
bad_tail=""; n_case=0
for c in "$T4_ROOT"/tests/t4/cases/*.sh; do
  [ -f "$c" ] || continue
  n_case=$((n_case + 1))
  last="$(grep -v '^[[:space:]]*$' "$c" | tail -1)"
  case "$last" in
    *t4_exit*|*t4_skip*|*exec*) ;;
    *) bad_tail="$bad_tail $(basename "$c")" ;;
  esac
done
t4_assert_eq "" "${bad_tail# }" "T522: 全部用例（$n_case 例）以 t4_exit|t4_skip|exec 收尾"

# --- 测试基建 helper 级断言（T536 · BR4/AC3）--------------------------------
# t4_cli_supports 是整批用例的能力门（决定 SKIP/BLOCKED）——它自身必须有正反两条断言，
# 否则改写（管道→here-string）若有偏差会以「全批静默 SKIP」的形式假绿。
if t4_cli_supports init; then
  t4_ok "T536: helper 正向 —— t4_cli_supports init 命中 nao-skill 已有子命令"
else
  t4_bad "T536: helper 正向 —— t4_cli_supports init 未命中已有子命令（help 解析或判定回归）"
fi
if t4_cli_supports __t536_no_such_subcommand; then
  t4_bad "T536: helper 负向 —— t4_cli_supports 命中不存在的子命令（判定过宽）"
else
  t4_ok "T536: helper 负向 —— 不存在的子命令不命中"
fi
# BR4 常量护栏：lib.sh 内不留 `printf … | grep` 同型管道（SIGPIPE 隐患源头）
lib_pipes="$(grep -cE 'printf[^|]*\|[[:space:]]*grep' "$T4_ROOT/tests/t4/lib.sh" 2>/dev/null || true)"
t4_assert_eq "0" "${lib_pipes:-0}" "T536 BR4: lib.sh 内 printf…| grep 同型管道 0 处"

# --- #82 A：真清单断言（孤儿卡假绿）------------------------------------------
# 缺陷：`check` 对「卡在、roles.yaml 未登记」只出 1 条 warn（rc=0）⇒ 既有用例（09/17 自带夹具清单）
#   看不见真实清单漂移。本节直接核**真** `.agents/roles.yaml`，并用夹具副本做负控证明断言能翻红。
# 期望角色集**显式钉住**（不从清单自推，否则摘条目后仍自洽 = 断言空转）。
MANIFEST_EXPECT="pm arch-designer uiux-designer rd-fe rd-be qa rd-infra"

# 解析 roles.yaml → TSV: id \t aliases(csv,无空格) \t card
manifest_tsv() {
  awk '
    /^roles:[[:space:]]*$/ { inr=1; next }
    !inr { next }
    /^  [^ ][^:]*:[[:space:]]*$/ {
      if (id != "") printf "%s\t%s\t%s\n", id, al, card
      c=$0; sub(/^  /,"",c); sub(/:[[:space:]]*$/,"",c); id=c; al=""; card=""; next
    }
    id != "" && /^    aliases:[[:space:]]*\[/ {
      v=$0; sub(/^    aliases:[[:space:]]*\[/,"",v); sub(/\].*/,"",v); gsub(/[[:space:]]/,"",v); al=v; next
    }
    id != "" && /^    card:[[:space:]]/ {
      v=$0; sub(/^    card:[[:space:]]*/,"",v); gsub(/[[:space:]]/,"",v); card=v; next
    }
    END { if (id != "") printf "%s\t%s\t%s\n", id, al, card }
  ' "$1"
}

# 输出问题行（无输出 = 一致）；$1=根目录（含 .agents）
manifest_problems() {
  local root="$1" man="$1/.agents/roles.yaml" pdir="$1/.agents/prompts" id al card rf
  local -a ids=() cards=()
  while IFS=$'\t' read -r id al card; do
    [ -n "$id" ] || continue
    ids+=("$id")
    if [ -z "$card" ]; then printf '%s：缺 card 字段\n' "$id"; continue; fi
    cards+=("$card")
    rf="$pdir/$card"
    if [ ! -f "$rf" ]; then printf '%s：卡文件不存在（%s）\n' "$id" "$card"; continue; fi
    local frole; frole="$(sed -n 's/^role:[[:space:]]*//p' "$rf" | head -1 | tr -d '\r')"
    [ "$frole" = "$id" ] || printf '%s：卡 frontmatter role=%s 与清单 id 不一致\n' "$id" "${frole:-<空>}"
  done < <(manifest_tsv "$man")
  # ① 角色数 + 角色集（钉住期望集）
  [ "${#ids[@]}" = "7" ] || printf '角色数=%s（期望 7）\n' "${#ids[@]}"
  [ "$(printf '%s\n' "${ids[@]}" | sort | tr '\n' ' ')" = "$(printf '%s\n' $MANIFEST_EXPECT | sort | tr '\n' ' ')" ] \
    || printf '角色集不一致：%s（期望 %s）\n' "${ids[*]:-<空>}" "$MANIFEST_EXPECT"
  # ② 关键别名（#80 D1：canonical 必须登记）
  local ual; ual="$(manifest_tsv "$man" | awk -F'\t' '$1=="uiux-designer"{print $2}')"
  [ "$ual" = "uiux,ui-designer,uiux-designer" ] || printf 'uiux-designer 别名=%s（期望 uiux,ui-designer,uiux-designer）\n' "${ual:-<空>}"
  # ③ card↔roles 双向：prompts/*.md 必须全部被清单引用（孤儿卡 = 漂移）
  local f b found
  for f in "$pdir"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; found=0
    for card in "${cards[@]}"; do [ "$b" = "$card" ] && found=1; done
    (( found )) || printf '%s：卡存在但 roles.yaml 未登记（孤儿卡）\n' "$b"
  done
}

real_problems="$(manifest_problems "$T4_ROOT")"
t4_info "真清单：$(manifest_tsv "$T4_ROOT/.agents/roles.yaml" | wc -l | tr -d ' ') 个角色 · problems=${real_problems:-无}"
t4_assert_eq "" "$real_problems" "A: 真 roles.yaml 与卡集一致（角色集 / 别名 / card↔roles 双向）"
t4_assert_contains "$out" "roles=7" "A: 真清单下 check 报 roles=7（清单与卡集未漂移）"

# 负控（先红）：夹具副本摘掉 uiux-designer 条目 ⇒ 断言必须翻红并点名
FX82="$T4_CACHE_DIR/fx82-$$"
rm -rf "$FX82"; mkdir -p "$FX82"
cp -r "$T4_ROOT/.agents" "$FX82/.agents" || t4_bad "A 负控：夹具复制 .agents 失败"
awk '
  /^  uiux-designer:[[:space:]]*$/ { skip=1; next }
  skip && /^  [^ ][^:]*:[[:space:]]*$/ { skip=0 }
  !skip { print }
' "$FX82/.agents/roles.yaml" > "$FX82/.agents/roles.yaml.new" \
  && mv "$FX82/.agents/roles.yaml.new" "$FX82/.agents/roles.yaml"
mut_problems="$(manifest_problems "$FX82")"
t4_assert_ne "" "$mut_problems" "A 负控：摘掉 roles.yaml 条目 ⇒ 真清单断言翻红（不再假绿）"
t4_assert_contains "$mut_problems" "uiux-designer" "A 负控：翻红点名 uiux-designer"
t4_assert_contains "$mut_problems" "角色数=6" "A 负控：翻红给出角色数=6（期望 7）"
t4_assert_contains "$mut_problems" "uiux-designer.md：卡存在但 roles.yaml 未登记" "A 负控：点名孤儿卡（card↔roles 反向）"
# 现状留痕：check 在漂移清单上仍 rc=0（仅 warn）——本批不把它改成 error（Issue 修法为补断言），
#   断言的存在即把「假绿」关进用例：清单漂移 ⇒ 本条红，不再随 check rc 一起绿。
of82="$(mktemp)"; rc82=0
( cd "$FX82" && env -u NAO_SKILLS timeout 120 bash "$FX82/.agents/scripts/nao-fleet.sh" check ) >"$of82" 2>&1 || rc82=$?
t4_assert_eq "0" "$rc82" "A 负控：check 在漂移清单上 rc=0（假绿本体）"
t4_assert_contains "$(cat "$of82")" "roles=6" "A 负控：check 报 roles=6（佐证漂移）"
t4_assert_contains "$(cat "$of82")" "warn=1" "A 负控：check 只降到 warn=1（不翻红 ⇒ 假绿根因）"
of82v="$(mktemp)"
( cd "$FX82" && env -u NAO_SKILLS timeout 120 bash "$FX82/.agents/scripts/nao-fleet.sh" check -v ) >"$of82v" 2>&1 || true
t4_assert_contains "$(cat "$of82v")" "! uiux-designer.md 未登记于 roles.yaml" "A 负控：-v 点名孤儿卡（漂移可见）"
rm -f "$of82" "$of82v"
# 复位（绿）：重新复制真清单 ⇒ 断言回到空
cp "$T4_ROOT/.agents/roles.yaml" "$FX82/.agents/roles.yaml"
t4_assert_eq "" "$(manifest_problems "$FX82")" "A: 复位后断言复绿"
rm -rf "$FX82"

t4_exit
