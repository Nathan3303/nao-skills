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

# --- #82 A / #88：真清单断言（期望收单处 + 负控自包含）---------------------------
# 沿革：#82 —— `check` 对「卡在、roles.yaml 未登记」只出 1 条 warn（rc=0）⇒ 假绿，本节直接核真清单；
#   #88 —— 期望曾散成字面量（角色数=7 / roles=7 / 硬编码别名）⇒ **计划内的角色新增**被自家闸判 4 红，
#          其中 2 条是误导红（负控/复位读了真清单状态）。
# 现在：① 期望**单处**在 `tests/t4/expected-roles.txt`（角色 id / 别名 / 卡名），不一致时文案直接指路；
#       ② 断言 = 真 `roles.yaml` + 真 `prompts/` **对**期望文件；
#       ③ 负控/复位**完全自包含**（清单与 prompts 都由期望文件生成），复位用**快照比对**；
#       ④ 防自洽空转：期望文件"结构相同但角色名写错" ⇒ 断言必红（不是拿真清单自证）。
EXPECT="$T4_ROOT/tests/t4/expected-roles.txt"
EXPECT_HINT="新增/删除角色或改别名/卡名请更新 tests/t4/expected-roles.txt"
t4_assert_file "$EXPECT" "A: 期望常量文件存在（tests/t4/expected-roles.txt）"

# 期望文件 → TSV（跳过注释/空行）
expect_tsv() { grep -vE '^[[:space:]]*(#|$)' "$1"; }

# roles.yaml → TSV: id \t aliases(csv,无空格) \t card
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

# 输出问题行（无输出 = 与期望一致）；$1=根目录（含 .agents） $2=期望文件
manifest_problems() {
  local root="$1" exp="$2" man="$1/.agents/roles.yaml" pdir="$1/.agents/prompts"
  local id al card eid eal ecard rf frole f b found extra="" missing=""
  local -a ids=() exp_ids=() exp_cards=()
  local -A m_al=() m_card=()
  while IFS=$'\t' read -r id al card; do
    [ -n "$id" ] || continue
    ids+=("$id"); m_al["$id"]="$al"; m_card["$id"]="$card"
  done < <(manifest_tsv "$man")
  while IFS=$'\t' read -r eid eal ecard; do
    [ -n "$eid" ] || continue
    exp_ids+=("$eid"); exp_cards+=("$ecard")
  done < <(expect_tsv "$exp")

  # ① 角色集 / 角色数 —— **合并成一条**（新增/删除角色只红这一条，不同源重复）
  for id in "${ids[@]}"; do
    found=0; for eid in "${exp_ids[@]}"; do [ "$id" = "$eid" ] && found=1; done
    (( found )) || extra="$extra $id"
  done
  for eid in "${exp_ids[@]}"; do
    found=0; for id in "${ids[@]}"; do [ "$id" = "$eid" ] && found=1; done
    (( found )) || missing="$missing $eid"
  done
  if [ -n "$extra$missing" ]; then
    printf '角色集不一致：清单 %s 个 / 期望 %s 个%s%s —— %s\n' "${#ids[@]}" "${#exp_ids[@]}" \
      "${extra:+ · 清单多出:${extra}}" "${missing:+ · 清单缺少:${missing}}" "$EXPECT_HINT"
  fi

  # ② 每个期望角色：别名 / card 字段 / 卡文件 / frontmatter role
  while IFS=$'\t' read -r eid eal ecard; do
    [ -n "$eid" ] || continue
    [ -n "${m_card[$eid]+x}" ] || continue        # 缺条目已在 ① 报过
    al="${m_al[$eid]}"; card="${m_card[$eid]}"
    [ "$al" = "$eal" ] || printf '%s：别名 [%s] 与期望 [%s] 不一致 —— %s\n' "$eid" "$al" "$eal" "$EXPECT_HINT"
    if [ -z "$card" ]; then printf '%s：清单缺 card 字段 —— %s\n' "$eid" "$EXPECT_HINT"; continue; fi
    rf="$pdir/$card"
    if [ ! -f "$rf" ]; then
      printf '%s：卡文件不存在（%s）—— 核对 roles.yaml 的 card 与卡文件名（改名请同时更新期望文件）\n' "$eid" "$card"
      continue
    fi
    frole="$(sed -n 's/^role:[[:space:]]*//p' "$rf" | head -1 | tr -d '\r')"
    [ "$frole" = "$eid" ] || printf '%s：卡 frontmatter role=%s 与清单 id 不一致 —— 改卡 role 或同步清单/期望文件\n' "$eid" "${frole:-<空>}"
  done < <(expect_tsv "$exp")

  # ③ 孤儿卡：prompts/*.md 不在**期望**卡集内
  for f in "$pdir"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; found=0
    for card in "${exp_cards[@]}"; do [ "$b" = "$card" ] && found=1; done
    (( found )) || printf '%s：卡存在但 roles.yaml 未登记（孤儿卡）—— %s\n' "$b" "$EXPECT_HINT"
  done
}

EXPECT_N="$(expect_tsv "$EXPECT" | grep -c . || true)"
real_problems="$(manifest_problems "$T4_ROOT" "$EXPECT")"
t4_info "真清单 vs 期望（角色数期望 $EXPECT_N）：problems=${real_problems:-无}"
t4_assert_eq "" "$real_problems" "A: 真 roles.yaml + 真卡集与期望文件一致（角色集 / 别名 / card↔roles）"
# check 与期望同源核对：仅在不漂移时断言（漂移时已由上面一条红覆盖，避免同源重复红）
if [ -z "$real_problems" ]; then
  # 作用域收窄：只在 check 的**汇总行**上断言（整段输出含 `roles=` 的其它位置不算数）
  CHECK_SUMMARY="$(printf '%s\n' "$out" | grep -m1 '^check: OK')"
  t4_assert_ne "" "${CHECK_SUMMARY:-}" "A: 存在 check 汇总行（check: OK · roles=…）"
  t4_assert_contains "${CHECK_SUMMARY:-}" "roles=$EXPECT_N" "A: check **汇总行**报 roles=$EXPECT_N（与期望文件一致）"
else
  t4_info "存在清单漂移 ⇒ 跳过 check roles= 断言（避免同源重复红）"
fi

# ---- 负控：**自包含夹具**（清单 + prompts 全由期望文件生成，不读真清单状态），复位用快照比对 ----
FX88="$T4_CACHE_DIR/fx88-$$"
build_selfcontained() { # $1=夹具根
  local root="$1" eid eal ecard
  rm -rf "$root"; mkdir -p "$root"
  cp -r "$T4_ROOT/.agents" "$root/.agents" || return 1
  rm -f "$root/.agents/prompts"/*.md          # 只保留期望声明的卡 ⇒ 真仓新增角色不影响本夹具
  while IFS=$'\t' read -r eid eal ecard; do
    [ -n "$eid" ] || continue
    if [ -f "$T4_ROOT/.agents/prompts/$ecard" ]; then
      cp "$T4_ROOT/.agents/prompts/$ecard" "$root/.agents/prompts/$ecard"
    else
      printf -- '---\nrole: %s\ndescription: fx88\n---\n\n# %s\n' "$eid" "$eid" > "$root/.agents/prompts/$ecard"
    fi
  done < <(expect_tsv "$EXPECT")
  {
    printf 'roles:\n'
    while IFS=$'\t' read -r eid eal ecard; do
      [ -n "$eid" ] || continue
      printf '  %s:\n    aliases: [%s]\n    card: %s\n    workspace: .\n' "$eid" "$eal" "$ecard"
    done < <(expect_tsv "$EXPECT")
  } > "$root/.agents/roles.yaml"
}
build_selfcontained "$FX88" || t4_bad "A 负控：自包含夹具构造失败"
SNAP="$(manifest_problems "$FX88" "$EXPECT")"
t4_assert_eq "" "$SNAP" "A 负控: 自包含夹具基线一致（与真清单状态无关）"

neg_state() { # $1=标签 $2=期望点名子串 $3=期望指路子串 $4=变异片段（在夹具根执行）
  local label="$1" want="$2" hint="$3" mut="$4" p r
  build_selfcontained "$FX88" || t4_bad "A 负控($label)：夹具构造失败"
  ( cd "$FX88" && eval "$mut" ) || t4_bad "A 负控($label)：变异未执行"
  p="$(manifest_problems "$FX88" "$EXPECT")"
  t4_assert_ne "" "$p" "A 负控($label): 漂移 ⇒ 断言翻红"
  t4_assert_contains "$p" "$want" "A 负控($label): 精确点名（$want）"
  t4_assert_contains "$p" "$hint" "A 负控($label): 文案含可执行指路"
  build_selfcontained "$FX88" || t4_bad "A 负控($label)：复位夹具构造失败"
  r="$(manifest_problems "$FX88" "$EXPECT")"
  t4_assert_eq "$SNAP" "$r" "A 负控($label): 复位后与**变异前快照**一致"
}
neg_state "摘条目" "清单缺少: qa" "请更新 tests/t4/expected-roles.txt" \
  "awk '/^  qa:[[:space:]]*\$/{s=1;next} s&&/^  [^ ][^:]*:[[:space:]]*\$/{s=0} !s' .agents/roles.yaml > /tmp/r88.\$\$ && mv /tmp/r88.\$\$ .agents/roles.yaml"
neg_state "加未登记卡" "probe-role.md：卡存在但 roles.yaml 未登记（孤儿卡）" "请更新 tests/t4/expected-roles.txt" \
  "printf -- '---\nrole: probe-role\ndescription: probe\n---\n' > .agents/prompts/probe-role.md"
neg_state "删别名" "uiux-designer：别名 [uiux] 与期望 [uiux,ui-designer,uiux-designer]" "请更新 tests/t4/expected-roles.txt" \
  "sed -i 's/^    aliases: \\[uiux,ui-designer,uiux-designer\\]\$/    aliases: [uiux]/' .agents/roles.yaml"
neg_state "卡文件缺失" "qa：卡文件不存在（test-engineer.md）" "核对 roles.yaml 的 card 与卡文件名" \
  "rm -f .agents/prompts/test-engineer.md"
neg_state "frontmatter role 不一致" "qa：卡 frontmatter role=qa-mutated 与清单 id 不一致" "改卡 role 或同步清单/期望文件" \
  "sed -i 's/^role: qa\$/role: qa-mutated/' .agents/prompts/test-engineer.md"
rm -rf "$FX88"

# ---- AC4 防自洽空转：期望文件"结构相同但角色名写错" ⇒ 断言必红（不是拿真清单自证）----
WRONG="$T4_CACHE_DIR/expect-wrong-$$.txt"
sed 's/^rd-infra	/rd-infraX	/' "$EXPECT" > "$WRONG"
wrong_problems="$(manifest_problems "$T4_ROOT" "$WRONG")"
t4_assert_ne "" "$wrong_problems" "A: 期望文件与真清单不一致 ⇒ 断言必红（防自洽空转）"
t4_assert_contains "$wrong_problems" "清单缺少: rd-infraX" "A: 点名期望里写错的角色名（清单缺少: rd-infraX）"
t4_assert_contains "$wrong_problems" "清单多出: rd-infra" "A: 同时点名真清单多出的（清单多出: rd-infra）"
rm -f "$WRONG"

# --- #84 A 行级 lint：用例不得在命令行位直接调 tmux（裸 socket ⇒ 生产 server）-------
# 真实缺陷类（`cases/20` v0.22.1 发布前置组 2 实测）：**同一隔离 server 内的累积残留（跨块/跨次）
#   + 全 server 计数（`list-panes -a`）+ `tail -1` 顺序启发式** ⇒ 残留/时序一变就假红。
#   该类写法普遍**带 `-S`** ⇒ 本 lint 对其零覆盖；`cases/20` 的解法是 reset_lab（每块重建隔离
#   server）+ 快照 diff（用例级已解耦），**不是**把根因关进了本用例。
# 本 lint 的范围（行级、静态）：命令行位的 `tmux` / `$REAL_TMUX` 调用必须显式 `-S`；
#   豁免 `command -v tmux` / `t4_require_cmd tmux`（非调用）。已知假阳/漏判见 #84 QA P3-2。
host_viol="$(t4_scan_host_pane_refs "$T4_ROOT/tests/t4/cases")"
t4_assert_eq "" "$host_viol" "AC2 护栏: 用例集无命令行位裸 tmux 调用（行级 lint；累积残留类由 cases/20 的 reset_lab 覆盖）"
# 负控：人造两条违规（直接命令行位 + 包装函数内）⇒ 护栏必须命中并点名
FXG="$T4_CACHE_DIR/fxguard-$$"
rm -rf "$FXG"; mkdir -p "$FXG"
# 夹具正文用 @TMUX@ 占位再替换成 `tmux`：避免本用例自身源码出现「命令行位 tmux」被自己的护栏扫到
cat > "$FXG/99-direct.sh" <<'SH'
#!/usr/bin/env bash
n="$(@TMUX@ list-panes -a -F '#{pane_id}' | wc -l)"
t4_assert_eq "2" "$n" "宿主窗口恰 2 个 pane"
SH
cat > "$FXG/98-wrapper.sh" <<'SH'
#!/usr/bin/env bash
TX() { @TMUX@ list-panes -a -F '#{pane_id}'; }
SH
sed -i 's/@TMUX@/tmux/g' "$FXG/99-direct.sh" "$FXG/98-wrapper.sh"
viol="$(t4_scan_host_pane_refs "$FXG")"
t4_assert_ne "" "$viol" "AC2 护栏负控: 人造违规被命中（非空转）"
t4_assert_contains "$viol" "99-direct.sh" "AC2 护栏负控: 点名直接命令行位违规文件"
t4_assert_contains "$viol" "98-wrapper.sh" "AC2 护栏负控: 点名包装函数内违规文件"
t4_assert_eq "2" "$(printf '%s\n' "$viol" | grep -c .)" "AC2 护栏负控: 恰 2 条命中（不漏判也不误判）"
# 豁免面自检：写一条合规调用 ⇒ 不计入
cat > "$FXG/97-ok.sh" <<'SH'
#!/usr/bin/env bash
SOCK="$LAB/sock/tmux-0/default"
TX() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}'; }
SH
t4_assert_eq "2" "$(t4_scan_host_pane_refs "$FXG" | grep -c .)" "AC2 护栏: 合规调用（tmux -S）不计入违规"
rm -rf "$FXG"

t4_exit
