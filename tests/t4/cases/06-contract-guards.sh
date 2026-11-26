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

# #126（QA P2-1）：`check` 的 stash 闸读 `$SKILLS_DIR` 的 `git stash list` ⇒ 本用例在 `$T4_ROOT`（真仓）上
#   做的 golden 面会被「仓里有一条 stash」污染（首行多 `warn=1`、md5 变）。本用例全部**真实仓** `check`
#   调用一律显式注入 `NAO_STASH_ROOT=<非仓目录>`（= 该闸「不适用」分支），**不剥行、不改 golden、不改闸门语义**；
#   闸门本身是否真在跑，由下面「P2-1 双向」组用**临时 git 仓**旁证钉住（防注入把闸门一起废成空转）。
C6_STASH_NONE="$T4_CACHE_DIR/c6-stash-none"
mkdir -p "$C6_STASH_NONE"

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
# T567-A：实现已拆到 fleet/lib/*.sh ⇒ 内容断言按**文件集**计数（单文件口径会漏）
t4_assert_ge 1 "$(t4_fleet_count '--append-system-prompt' "$T4_ROOT/.agents/scripts")" "AC8: fleet 仍以 --append-system-prompt 常驻注入角色卡（BR2）"

# --- AC6（机制侧）：check 交叉引用 + 引用一致性 ------------------------------
of="$(mktemp)"; ef="$(mktemp)"
( cd "$T4_ROOT" && env -u NAO_SKILLS NAO_STASH_ROOT="$C6_STASH_NONE" timeout 120 bash .agents/scripts/nao-fleet.sh check ) >"$of" 2>"$ef"
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

# --- #93 语义化 lint：真实缺陷类（全 server 计数 + 顺序启发式挑尾）-----------------
# 病根（#84 P3-2）：上面的行级 lint 只判「命令行位裸 tmux 必须 -S」，而真实缺陷类写法**带 -S**
#   （同一隔离 server 内跨块/跨次累积残留 + 全 server 计数 + 挑最后一行）⇒ 对该类零覆盖。
# 本块 = 把缺陷形态固化成 fixture，并断言：**同一份输入**新 lint 必红、旧行级 lint（pre-#93 **快照**）仍绿。
# AC1/AC2：新 lint 必红 + 旧 lint 仍绿（两条都必须有，只证前者等于没证明补上了零覆盖那块）。
# P3-3：旧 lint 用 fixtures/pre93-host-pane-refs.sh 快照（固定历史事实）—— live 旧 lint 以后被增强也不会假红。
# AC4：不纳管类（会话定向 / 只计数 / 取首行 / 跨行 / 两行变量 / 跨语句）由 controls fixture 逐条做负控；
#   缩进注释必须被跳过（P3-2）；字符串字面量与引号内 `-a` 是**已知假阳**，只在 lib.sh 注释声明、不断言判对。
# AC5：变异自证 —— 在子进程里把新 lint 改恒假 / 去掉 -a 判据，复刻本块断言 ⇒ 必须点名翻红。
FX93="$T4_ROOT/tests/t4/fixtures/93-all-server-tail1"
F93_DEFECT="$FX93/defect.sh"
F93_CONTROLS="$FX93/controls.sh"
F93_OLD="$T4_ROOT/tests/t4/fixtures/pre93-host-pane-refs.sh"
t4_assert_file "$F93_DEFECT" "AC2 #93: 缺陷 fixture 存在（fixtures/93-all-server-tail1/defect.sh）"
t4_assert_file "$F93_CONTROLS" "AC2 #93: 负控 fixture 存在（fixtures/93-all-server-tail1/controls.sh）"
t4_assert_file "$F93_OLD" "AC1 #93: pre-#93 旧 lint 快照存在（fixtures/pre93-host-pane-refs.sh）"
fixture_head="$(sed -n '1,8p' "$F93_DEFECT")"
t4_assert_contains "$fixture_head" "Issue #93" "AC2 #93: fixture 标注来源（Issue #93）"
t4_assert_contains "$fixture_head" "2026-11-09" "AC2 #93: fixture 标注日期（2026-11-09）"
old_head="$(sed -n '1,4p' "$F93_OLD")"
t4_assert_contains "$old_head" "2497d87" "P3-3 #93: 旧 lint 快照标注来源 sha（main@2497d87）"
t4_assert_contains "$old_head" "2026-11-09" "P3-3 #93: 旧 lint 快照标注日期（2026-11-09）"

new_hits="$(t4_scan_all_server_tail1 "$FX93")"
t4_assert_ne "" "$new_hits" "AC1 #93: 同一份缺陷输入 ⇒ 新语义 lint 必红（补上旧 lint 的零覆盖）"
t4_assert_eq "2" "$(printf '%s\n' "$new_hits" | grep -c .)" "AC2 #93: 恰 2 条命中（包装函数调用 + 显式 -S 直调）"
t4_assert_contains "$new_hits" "pane_count" "AC2 #93: 点名包装函数调用形态"
t4_assert_contains "$new_hits" "pane_total" "AC2 #93: 点名显式 -S 直调形态"
t4_assert_not_contains "$new_hits" "pane_of_session" "AC4 #93 负控: 会话定向采样 + 挑尾不纳管（不是全 server 计数）"
t4_assert_not_contains "$new_hits" "pane_total_wc" "AC4 #93 负控: 全 server 计数但不挑尾不纳管"
t4_assert_not_contains "$new_hits" "pane_first" "AC4 #93 负控: 全 server 计数但取首行不纳管"
t4_assert_not_contains "$new_hits" "pane_multiline" "AC4 #93 负控: 跨行写法不纳管（行级 lint 不拼接续行，已知漏判）"
t4_assert_not_contains "$new_hits" "pane_two_lines" "AC4 #93 负控: 两行变量拼装不纳管（行级静态不追数据流，已知漏判）"
t4_assert_not_contains "$new_hits" "pane_then_echo" "P3-1 #93 负控: 分号后接无关 tail -1 不得命中（跳语句假阳）"
t4_assert_not_contains "$new_hits" "pane_and_echo" "P3-1 #93 负控: 逻辑与后接无关 tail -1 不得命中（跳语句假阳）"
t4_assert_not_contains "$new_hits" "pane_indented" "P3-2 #93 负控: 缩进注释先 trim 再判注释符（不得命中）"
FX93OLD="$T4_CACHE_DIR/fx93old-$$"
rm -rf "$FX93OLD"; mkdir -p "$FX93OLD"; cp "$F93_DEFECT" "$FX93OLD/defect.sh"
old_hits="$( source "$F93_OLD"; t4_scan_host_pane_refs "$FX93OLD" )"
t4_assert_eq "" "$old_hits" "AC1 #93: **pre-#93 快照版**对同一份缺陷输入仍绿（历史事实；live 旧 lint 被增强不再假红）"
rm -rf "$FX93OLD"
t4_assert_eq "" "$(t4_scan_all_server_tail1 "$T4_ROOT/tests/t4/cases")" "AC1 #93 常态护栏: 用例集 0 处「全 server 计数 + 顺序挑尾」组合"

# AC5 变异自证：子进程只替换 lint（本块的断言原样复刻），确认变松/变假会当场红
MUT93="$T4_CACHE_DIR/mut93-$$.sh"
cat > "$MUT93" <<'SH'
#!/usr/bin/env bash
source "$MUT_LIB" >/dev/null 2>&1
kind="$1"; fx="$2"
case "$kind" in
  const-false) t4_scan_all_server_tail1() { :; } ;;
  drop-all) t4_scan_all_server_tail1() {
      local dir="$1" f ln body
      local re='\|[[:space:]]*tail[[:space:]]+(-[0-9]*1|-n[[:space:]]*1|--lines=1)([^[:alnum:]]|$)'
      for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        while IFS= read -r ln; do
          body="${ln#*:}"
          case "$body" in \#*) continue;; esac
          printf '%s:%s\n' "$(basename "$f")" "$ln"
        done < <(grep -nE "$re" "$f")
      done
    } ;;
esac
hits="$(t4_scan_all_server_tail1 "$fx")"
n="$(printf '%s\n' "$hits" | grep -c . || true)"
t4_assert_ne "" "$hits" "AC2: 缺陷 fixture 必红（新 lint 命中）"
t4_assert_eq "2" "$n" "AC2: 恰 2 条命中（包装函数 + 显式 -S）"
t4_assert_not_contains "$hits" "pane_of_session" "AC4: 会话定向采样不纳管"
t4_exit
SH
mut_out="$(MUT_LIB="$T4_ROOT/tests/t4/lib.sh" bash "$MUT93" const-false "$FX93" 2>&1)"; mut_rc=$?
t4_assert_eq "1" "$mut_rc" "AC5 #93 变异(恒假): 复刻断言翻红（rc=1，不静默通过）"
t4_assert_contains "$mut_out" "[FAIL] AC2: 缺陷 fixture 必红" "AC5 #93 变异(恒假): 点名翻红的 AC2 断言"
mut_out="$(MUT_LIB="$T4_ROOT/tests/t4/lib.sh" bash "$MUT93" drop-all "$FX93" 2>&1)"; mut_rc=$?
t4_assert_eq "1" "$mut_rc" "AC5 #93 变异(丢 -a 判据): 复刻断言翻红（rc=1，不静默通过）"
t4_assert_contains "$mut_out" "[FAIL] AC2: 恰 2 条命中" "AC5 #93 变异(丢 -a 判据): 点名计数断言翻红（命中了不纳管类）"
rm -f "$MUT93"

# --- #96 步 2b：herdr 侧行级 lint（命令行位 herdr 必须经唯一入口**且**带 --session）-------
# 缺口（QA P3-3 首轮）：该守护原先只在「lib-backend.sh + cases/27 自身」内联，其余用例目录零覆盖。
#   本块把它提成 `lib.sh` 的公共 lint（`t4_scan_herdr_bare_calls`），扩到**整个 cases 目录**，
#   与上面的 tmux 侧 `t4_scan_host_pane_refs` 对称（同为行级/静态/只看命令位）。
# 与 `cases/27` 的关系（准确表述）：同为行级 lint，但 27 的判据**只扫单文件**（`lib-backend.sh`
#   + 自身）且**前缀集更窄**（行首 / `;` / `$(` / `{`，不含 `| & (`）—— 本 lint 是全目录口径的
#   补充，二者不互相替代（合取从严）。
# 判据：命中行必须**既在 `_be_herdr_exec` 函数体内、又带 `--session`** —— 二者是 AND：函数体外带
#   `--session` 仍是**旁路**（绕开清环境/私有根），函数体内缺 `--session` 仍会**静默打到用户
#   `default`**（实测）。白名单只有 `herdr --version`，且**整行等值**（剥行尾注释后整行恰为该命令）。
#   QA P3-3 实测的安全洞正是「行内出现即豁免」：`herdr workspace list # herdr --version` 与
#   `herdr --version ; herdr workspace list` 都能骗过子串匹配 ⇒ 下面两种形态各给一条负控。
HD_CASES="$T4_ROOT/tests/t4/cases"
HD_VIOL="$(t4_scan_herdr_bare_calls "$HD_CASES")"
t4_assert_eq "" "$HD_VIOL" \
  "#96 护栏: 全 cases 目录 0 处命令位 herdr 绕过唯一入口或缺 --session（白名单除外）"
t4_assert_eq "" "$(t4_scan_herdr_bare_calls "$T4_ROOT/tests/t4")" \
  "#96 护栏: 含 lib-backend.sh 的同判据也 0 命中（唯一入口体内两条均带 --session，非靠函数体豁免兜住）"
# P3-3 安全洞专项：白名单必须**整行等值** —— 两条「裸调用 + 附带白名单片段」必红并点名
FXHAB="$T4_CACHE_DIR/fxherdrabuse-$$"
rm -rf "$FXHAB"; mkdir -p "$FXHAB"
printf '#!/usr/bin/env bash\n@HERDR@ workspace list # @HERDR@ --version\n' > "$FXHAB/01-trick.sh"
sed -i 's/@HERDR@/herdr/g' "$FXHAB/01-trick.sh"
HD_AB1="$(t4_scan_herdr_bare_calls "$FXHAB")"
t4_assert_eq "1" "$(printf '%s\n' "$HD_AB1" | grep -c .)" \
  "P3-3 负控①: 裸调用 + 行尾注释伪造白名单（herdr workspace list # herdr --version）⇒ 必红"
t4_assert_contains "$HD_AB1" "01-trick.sh" "P3-3 负控①: 点名该违规文件（不是笼统失败）"
rm -f "$FXHAB/01-trick.sh"
printf '#!/usr/bin/env bash\n@HERDR@ --version ; @HERDR@ workspace list\n' > "$FXHAB/02-then-bare.sh"
sed -i 's/@HERDR@/herdr/g' "$FXHAB/02-then-bare.sh"
HD_AB2="$(t4_scan_herdr_bare_calls "$FXHAB")"
t4_assert_eq "1" "$(printf '%s\n' "$HD_AB2" | grep -c .)" \
  "P3-3 负控②: herdr --version 之后接 ; 裸调用 ⇒ 必红（不是「行内出现即豁免」）"
t4_assert_contains "$HD_AB2" "02-then-bare.sh" "P3-3 负控②: 点名该违规文件"
rm -f "$FXHAB/02-then-bare.sh"
printf '#!/usr/bin/env bash\n@HERDR@ --version\n' > "$FXHAB/03-ok.sh"
sed -i 's/@HERDR@/herdr/g' "$FXHAB/03-ok.sh"
t4_assert_eq "" "$(t4_scan_herdr_bare_calls "$FXHAB")" \
  "P3-3 正控: 整行只有 herdr --version ⇒ 放行（白名单命中即跳）"
rm -rf "$FXHAB"
# 人造违规夹具（/tmp：$T4_CACHE_DIR 下）：六种形态必须命中并点名，五种合规形态必须放行。
# 夹具正文用 @HERDR@ 占位再替换 —— 否则本用例自身源码会成为「命令行位裸 herdr」被自己扫到。
FXH="$T4_CACHE_DIR/fxherdr-$$"
rm -rf "$FXH"; mkdir -p "$FXH"
printf '#!/usr/bin/env bash\nn="$(@HERDR@ workspace list | wc -l)"\n' > "$FXH/99-bare.sh"
printf '#!/usr/bin/env bash\n@HERDR@ workspace list --session "$S"\n' > "$FXH/98-session-outside.sh"
printf '#!/usr/bin/env bash\n_be_herdr_exec() {\n  local s="$1"; shift\n  exec @HERDR@ workspace list\n}\n' > "$FXH/97-entry-nosession.sh"
printf '#!/usr/bin/env bash\n@HERDR@ --help\n' > "$FXH/96-help.sh"
printf '#!/usr/bin/env bash\n@HERDR@ workspace list # @HERDR@ --version\n' > "$FXH/95-wl-comment-trick.sh"
printf '#!/usr/bin/env bash\n@HERDR@ --version ; @HERDR@ workspace list\n' > "$FXH/94-wl-then-bare.sh"
printf '#!/usr/bin/env bash\n_be_herdr_exec() {\n  local s="$1"; shift\n  exec @HERDR@ --session "$s" "$@"\n}\n' > "$FXH/93-entry-session.sh"
printf '#!/usr/bin/env bash\n_be_herdr_exec () {\n  local s="$1"; shift\n  exec @HERDR@ --session "$s" "$@"\n}\n' > "$FXH/92-entry-spaced.sh"
printf '#!/usr/bin/env bash\n@HERDR@ --version\n' > "$FXH/91-version.sh"
printf '#!/usr/bin/env bash\n@HERDR@ --version  # 尾注可剥：剥后整行等值 ⇒ 放行\n' > "$FXH/90-version-comment.sh"
printf '#!/usr/bin/env bash\n# 注释里的 herdr workspace list 不纳管\n   # 缩进注释 @HERDR@ workspace list\n' > "$FXH/89-comment.sh"
sed -i 's/@HERDR@/herdr/g' "$FXH"/*.sh
HD_NEG="$(t4_scan_herdr_bare_calls "$FXH")"
t4_assert_ne "" "$HD_NEG" "#96 护栏负控: 人造违规被命中（非空转）"
t4_assert_eq "6" "$(printf '%s\n' "$HD_NEG" | grep -c .)" "#96 护栏负控: 恰 6 条命中（不漏判也不误判）"
t4_assert_contains "$HD_NEG" "99-bare.sh" "#96 护栏负控: 点名裸调用（命令行位缺 --session）"
t4_assert_contains "$HD_NEG" "98-session-outside.sh" "#96 护栏负控: 点名绕过唯一入口（函数体外即使带 --session 也算旁路）"
t4_assert_contains "$HD_NEG" "97-entry-nosession.sh" "#96 护栏负控: 点名唯一入口体内缺 --session（不做函体豁免）"
t4_assert_contains "$HD_NEG" "96-help.sh" "#96 护栏负控: 点名 herdr --help（白名单不是「所有 -- 旗标」）"
t4_assert_contains "$HD_NEG" "95-wl-comment-trick.sh" "#96 护栏负控: 点名「注释伪造白名单」（与 P3-3 负控① 同形态）"
t4_assert_contains "$HD_NEG" "94-wl-then-bare.sh" "#96 护栏负控: 点名「白名单片段后接裸调用」（与 P3-3 负控② 同形态）"
t4_assert_not_contains "$HD_NEG" "93-entry-session.sh" "#96 护栏: 唯一入口体内带 --session ⇒ 放行（合规形态不误判）"
t4_assert_not_contains "$HD_NEG" "92-entry-spaced.sh" \
  'P3-4 护栏: 函数体写法「_be_herdr_exec () {」（括号前带空格）同样识别 ⇒ 体内合规行仍放行'
t4_assert_not_contains "$HD_NEG" "91-version.sh" "#96 护栏正控: 仅 herdr --version ⇒ 白名单放行"
t4_assert_not_contains "$HD_NEG" "90-version-comment.sh" "#96 护栏: herdr --version + 行尾注释 ⇒ 剥注释后整行等值 ⇒ 放行"
t4_assert_not_contains "$HD_NEG" "89-comment.sh" "#96 护栏: 注释行（含缩进注释）不纳管"
# 白名单正控（单文件目录）：只放 `herdr --version` ⇒ 0 命中；白名单不得是空转
FXHWL="$T4_CACHE_DIR/fxherdrwl-$$"
rm -rf "$FXHWL"; mkdir -p "$FXHWL"
printf '#!/usr/bin/env bash\n@HERDR@ --version\n' > "$FXHWL/01-version.sh"
sed -i 's/@HERDR@/herdr/g' "$FXHWL"/*.sh
t4_assert_eq "" "$(t4_scan_herdr_bare_calls "$FXHWL")" "#96 护栏正控: 只 herdr --version ⇒ 判据放行（白名单命中即跳）"
# 变异自证（子进程只替换 lint，断言原样复刻）：改松 / 丢白名单 ⇒ 必当场红并点名
MUT96="$T4_CACHE_DIR/mut96-$$.sh"
cat > "$MUT96" <<'SH'
#!/usr/bin/env bash
source "$MUT_LIB" >/dev/null 2>&1
kind="$1"; cases="$2"; fx="$3"
case "$kind" in
  allow-all) t4_scan_herdr_bare_calls() { :; } ;;
  drop-whitelist) t4_scan_herdr_bare_calls() {
      local dir="$1" f ln lnno body body_trim fstart fend inbody
      local re='(^|[|;&(]|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?herdr([[:space:]]|$)'
      local sess='--session([[:space:]]|=|$)'
      for f in "$dir"/*.sh; do
        [ -f "$f" ] || continue
        fstart="$(grep -nE '^_be_herdr_exec[[:space:]]*\(\)' "$f" 2>/dev/null | head -1 | cut -d: -f1)"
        fend=""
        [ -n "$fstart" ] && fend="$(awk -v s="$fstart" 'NR>s && /^}/ {print NR; exit}' "$f")"
        while IFS= read -r ln; do
          lnno="${ln%%:*}"; body="${ln#*:}"
          body_trim="${body#"${body%%[![:space:]]*}"}"
          case "$body_trim" in \#*) continue;; esac
          inbody=0
          if [ -n "$fstart" ] && [ "$lnno" -ge "$fstart" ] && { [ -z "$fend" ] || [ "$lnno" -le "$fend" ]; }; then inbody=1; fi
          [ "$inbody" = "1" ] && grep -qE -- "$sess" <<< "$body" && continue
          printf '%s:%s:%s\n' "$(basename "$f")" "$lnno" "$body_trim"
        done < <(grep -nE "$re" "$f")
      done
    } ;;
esac
t4_assert_eq "" "$(t4_scan_herdr_bare_calls "$cases")" "#96 护栏: 常态目录 0 命中（全 cases 目录 / 白名单正控目录）"
out="$(t4_scan_herdr_bare_calls "$fx")"
t4_assert_ne "" "$out" "#96 护栏: 人造违规必红并点名"
t4_assert_eq "6" "$(printf '%s\n' "$out" | grep -c .)" "#96 护栏: 恰 6 条命中"
t4_exit
SH
mut_out="$(MUT_LIB="$T4_ROOT/tests/t4/lib.sh" bash "$MUT96" allow-all "$HD_CASES" "$FXH" 2>&1)"; mut_rc=$?
t4_assert_eq "1" "$mut_rc" "#96 变异自证(允许裸调用): 复刻断言翻红（rc=1，不静默通过）"
t4_assert_contains "$mut_out" "[FAIL] #96 护栏: 人造违规必红并点名" "#96 变异自证(允许裸调用): 点名翻红的是「人造违规必红」断言"
# 丢白名单的靶子 = **白名单正控目录**：真实仓内白名单已零使用（cases/27 的版本探针也走唯一入口），
#   拿全 cases 目录当靶子会「变异了也不翻红」= 无效变异；用正控目录才能证明白名单是承重的。
mut_out="$(MUT_LIB="$T4_ROOT/tests/t4/lib.sh" bash "$MUT96" drop-whitelist "$FXHWL" "$FXH" 2>&1)"; mut_rc=$?
t4_assert_eq "1" "$mut_rc" "#96 变异自证(丢白名单): 复刻断言翻红（rc=1）"
t4_assert_contains "$mut_out" "[FAIL] #96 护栏: 常态目录 0 命中" "#96 变异自证(丢白名单): 点名翻红的是「常态目录 0 命中」（白名单承重，不是摆设）"
rm -f "$MUT96"; rm -rf "$FXH" "$FXHWL"

# --- M20261109：pi 版本阈值的**单一事实**（MIN_PI_VERSION）-------------------------
# 判据：常量只有一份（脚本内该版本字面量恰 1 次）；比较阈值由它派生（无魔术数 4/1）；
#       三处文案插值；活体负控抬到 9.9.9 后**文案与判据自洽**（不再出现「1.4.0 < 1.4.0」）。
FLEET_VER="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"   # T567-A：入口 + fleet/lib 的只读合并视图
MINPI="$(sed -n 's/^MIN_PI_VERSION="\([^"]*\)"$/\1/p' "$FLEET_VER" 2>/dev/null | head -1)"
t4_assert_match "$MINPI" '^[0-9]+\.[0-9]+\.[0-9]+$' "MIN_PI_VERSION 可从脚本抽出且为 x.y.z（得到「$MINPI」）"
t4_assert_eq "1" "$(grep -cF -- "$MINPI" "$FLEET_VER" || true)" "MIN_PI_VERSION 在脚本内仅出现 1 次（文案/判据一律派生，无双源）"
t4_assert_eq "1" "$(grep -c 'c2 >= MIN_PI_MINOR' "$FLEET_VER" || true)" "比较判据用派生 MIN_PI_MINOR（无魔术数 4）"
t4_assert_eq "0" "$(grep -c 'c2 >= 4' "$FLEET_VER" || true)" "旧魔术数「c2 >= 4」已不存在"
t4_assert_eq "1" "$(grep -c 'c1 > MIN_PI_MAJOR' "$FLEET_VER" || true)" "major 阈值同源派生（c1 > MIN_PI_MAJOR）"
t4_assert_contains "$(cat "$FLEET_VER")" 'pi ≥$MIN_PI_VERSION；' "运行前提小节标题插值常量"
t4_assert_eq "2" "$(grep -cE 'pi 版本 %s [≥<] %s' "$FLEET_VER" || true)" "✓/✗ 两行文案均插值常量"

# 活体（副本 + 桩 pi；不读宿主真 pi，结果可复现）：正控（恰好达标边界）· 负控（抬阈值）· P3-2 变异自证
LABVER="$(mktemp -d "$T4_CACHE_DIR/pi-ver.XXXXXX")" || t4_blocked "pi 版本用例夹具创建失败"
cp -r "$T4_ROOT/.agents" "$LABVER/.agents" || t4_bad "pi 版本用例：复制 .agents 失败"
mkdir -p "$LABVER/bin"
# 桩 pi **故意等于常量值**（「实际 == 阈值」边界）：既是「恰好达标仍 PASS」的正面例子，也是旧缺陷
#   「1.4.0 < 1.4.0」唯一可能出现的前提（实际版本与文案阈值撞车）；否则矛盾类断言永不变红（QA P3-2）。
printf '#!/usr/bin/env bash\n[ "${1:-}" = "--version" ] && { echo "%s"; exit 0; }\nexit 0\n' "$MINPI" > "$LABVER/bin/pi"
chmod +x "$LABVER/bin/pi"
LABFLEET="$(t4_fleet_file_with "$LABVER/.agents/scripts" 'MIN_PI_VERSION="')"   # T567-A：常量在 core.sh
lab_check() { local root="$1"; ( cd "$root" && env -u NAO_STASH_ROOT -u NAO_SKILLS PATH="$root/bin:$PATH" timeout 120 bash .agents/scripts/nao-fleet.sh check -v 2>&1 ); }
lab_line()  { printf '%s\n' "$1" | grep -E '✗ pi 版本' | head -1 | sed 's/^ *//'; }
out_pos="$(lab_check "$LABVER")"
rc_pos=$?
t4_assert_eq "0" "$rc_pos" "正控: 桩 pi == 常量 $MINPI ⇒ check rc=0（恰好达标的边界）"
t4_assert_contains "$out_pos" "✓ pi 版本 $MINPI ≥ $MINPI" "正控: 达标边界仍 PASS，且 ✓ 行阈值 = 常量值"
sed -i.bak 's/^MIN_PI_VERSION=.*$/MIN_PI_VERSION="9.9.9"/' "$LABFLEET"
t4_assert_eq "9.9.9" "$(sed -n 's/^MIN_PI_VERSION="\([^"]*\)"$/\1/p' "$LABFLEET" | head -1)" "负控: 夹具副本阈值已抬到 9.9.9"
out_neg="$(lab_check "$LABVER")"
rc_neg=$?
neg_line="$(lab_line "$out_neg")"
t4_assert_ne "0" "$rc_neg" "负控: 阈值抬到 9.9.9 ⇒ check rc≠0（聚合）"
t4_assert_eq "✗ pi 版本 $MINPI < 9.9.9" "$neg_line" "负控: ✗ 行「实际」=桩版本、「阈值」=常量（两段都随源走）"
t4_assert_contains "$out_neg" "pi ≥9.9.9" "负控: 小节标题同源插值（9.9.9）"
t4_assert_eq "0" "$(printf '%s' "$out_neg" | grep -cF "$MINPI < $MINPI" || true)" "负控: 无「$MINPI < $MINPI」——实际==常量时文案与判据仍自洽"

# P3-2 非空转自证：把副本 ✗ 行改回**硬编码阈值**（复刻旧缺陷）⇒ 上面两条通用判据必须一起变红。
#   若不跑这一段，「不再出现 1.4.0 < 1.4.0」在实际≠常量时永不变红（QA 实测空转）。
LABMUT="$LABVER-mut"
cp -r "$LABVER" "$LABMUT" || t4_bad "P3-2: 变异副本创建失败"
LABMUT_COPY="$(t4_fleet_file_with "$LABMUT/.agents/scripts" '✗ pi 版本 %s < %s')"   # T567-A：文案在 check.sh
t4_assert_ne "" "$LABMUT_COPY" "P3-2: 定位到 ✗ 行所在模块（拆分后不再是入口文件）"
awk -v v="$MINPI" '{ if (index($0, "✗ pi 版本 %s < %s") > 0) gsub(/%s < %s/, "%s < " v); print }' \
  "$LABMUT_COPY" > "$LABMUT/fleet.mut" || t4_bad "P3-2: 变异副本生成失败"
mv "$LABMUT/fleet.mut" "$LABMUT_COPY"
t4_assert_ne "0" "$(cmp -s "$(t4_fleet_file_with "$LABVER/.agents/scripts" '✗ pi 版本 %s < %s')" "$LABMUT_COPY" && echo 0 || echo 1)" "P3-2: 变异副本确与负控副本不同（✗ 行阈值已硬编码 $MINPI）"
out_mut="$(lab_check "$LABMUT")"
rc_mut=$?
mut_line="$(lab_line "$out_mut")"
t4_assert_ne "0" "$rc_mut" "P3-2 变异: 硬编码 ✗ 行后仍 rc≠0（不是靠 rc 绊住，靠文案）"
t4_assert_eq "✗ pi 版本 $MINPI < $MINPI" "$mut_line" "P3-2 变异: 旧缺陷如实复现（文案回头 $MINPI < $MINPI）"
t4_assert_ne "✗ pi 版本 $MINPI < 9.9.9" "$mut_line" "P3-2 变异: 「✗ 行阈值==常量」判据在变异上必红（断言非空转）"
t4_assert_eq "1" "$(printf '%s' "$out_mut" | grep -cF "$MINPI < $MINPI" || true)" "P3-2 变异: 「无矛盾文案」判据在变异上计数 1（断言非空转）"
t4_assert_eq "1" "$(t4_fleet_count "$MINPI" "$T4_ROOT/.agents/scripts")" "全段结束后真脚本未被改动（阈值仍为 $MINPI，只在副本里变异）"

# ---------------------------------------------------------------------------
# E2-1（#132 · backlog sweep）：文档面 pi 下限「**漂移即红**」（替代「清空文档数字」）
#   背景：`MIN_PI_VERSION` 是脚本单源，但文档面另有独立字面量（README / AGENTS /
#     intercom-protocol / INSTALL / SKILL.md / pm-operations / ARCHITECTURE）。用户要看到门槛
#     ⇒ **不删文档里的版本号**，改为「文档声明的下限 == 脚本单源，漂移即红」。
#   判据两条（缺一即空转）：
#     ① **声明式下限**（`pi … ≥X.Y.Z` / `pi 版本低于 X.Y.Z`，含 `pi（≥ X.Y.Z）` 这类变体）
#        的取值必须 == 该根下脚本的 `MIN_PI_VERSION`；
#     ② **完备性**：现行文档里任何「pi … x.y.z」提及都必须被**归类** —— 或本身是 ① 的下限
#        声明，或该行带 **「截至」**（历史时点标注，如 codegraph.md 的「截至 pi 1.4.0 /
#        pi-codegraph 0.1.0」），否则红（防有人换一种写法写漂移，而 ① 抓不到）。
#   扫描面（fail-closed，不是白名单文件清单）：`git ls-files` 的 `*.md` 减去**历史时点类**
#     `docs/{adr,prds,releases,reports,notes,designs,research}/` · `docs/tasks-*.md`（台账/归档视图）
#     · `tests/`（夹具与负控样本，故意构造漂移）。历史类只按**目录类**豁免（不逐个列文件名）；
#     现行面里唯一的 as-of 行按**行内「截至」标注**豁免（机制，不是硬编码文件名）。
#   口径：包版本 pin（`pi install npm:@x.y.z`）不是 pi 自身的门槛 ⇒ 完备性正则排除前导 `@`。
E2_DOC_PRUNE_RE='^(docs/(adr|prds|releases|reports|notes|designs|research)/|docs/tasks-[^/]*$|tests/)'
E2_DOC_FILES="$(git -C "$T4_ROOT" ls-files -- '*.md' 2>/dev/null | grep -vE "$E2_DOC_PRUNE_RE" | sort || true)"
e2_min_of() { local f; f="$(t4_fleet_file_with "$1/.agents/scripts" 'MIN_PI_VERSION="')"; [ -n "$f" ] && sed -n 's/^MIN_PI_VERSION="\([^"]*\)"$/\1/p' "$f" 2>/dev/null | head -1; }
e2_scan() { # <根> decl|loose → "<相对路径>:<行>\t<版本或行文>…"（只读，不改任何文件）
  local root="$1" mode="$2" rel
  [ -n "$E2_DOC_FILES" ] || return 0
  printf '%s\n' "$E2_DOC_FILES" | while IFS= read -r rel; do
    [ -n "$rel" ] && [ -f "$root/$rel" ] || continue
    case "$mode" in
      decl) awk -v F="$rel" '{ line=$0; rest=$0
              while (match(rest, /pi[^0-9]*(≥|>=|低于)[[:space:]]*v?[0-9]+\.[0-9]+\.[0-9]+/)) {
                m=substr(rest, RSTART, RLENGTH)
                sub(/^.*(≥|>=|低于)[[:space:]]*v?/, "", m); gsub(/[[:space:]]/, "", m)
                printf "%s:%d\t%s\t%s\n", F, NR, m, substr(line, 1, 100)
                rest=substr(rest, RSTART + RLENGTH)
              } }' "$root/$rel" ;;
      loose) awk -v F="$rel" '/pi[^0-9@]*[0-9]+\.[0-9]+\.[0-9]+/ { printf "%s:%d\t%s\n", F, NR, substr($0, 1, 100) }' "$root/$rel" ;;
    esac
  done
}
e2_gate() { # <根> → 漂移/未归类报告（空 = 全绿；基准 = 该根下脚本的 MIN_PI_VERSION）
  local root="$1" min hits decl loc text
  min="$(e2_min_of "$root")"
  [ -n "$min" ] || { printf '夹具：%s 取不到 MIN_PI_VERSION\n' "$root"; return 0; }
  hits="$(e2_scan "$root" decl)"
  decl="$(printf '%s\n' "$hits" | cut -f1)"
  printf '%s\n' "$hits" | awk -F'\t' -v want="$min" '$1 != "" && $2 != want { printf "%s 声明 %s ≠ 单源 %s\n", $1, $2, want }'
  e2_scan "$root" loose | while IFS=$'\t' read -r loc text; do
    [ -n "$loc" ] || continue
    # T547-D2（QA 定性）：`printf | grep -q` + pipefail ⇒ grep 早退时上游 SIGPIPE(141) ⇒ 真命中被判「未归类」。
    #   同 lib.sh:281-283（T534-O2）的 here-string 修法；本处是 e2_gate 里漏改的那一处。
    grep -Fxq -- "$loc" <<< "$decl" && continue
    case "$text" in *截至*) continue ;; esac
    printf '%s 未归类：既非下限声明（≥/低于），也无「截至」历史时点标注 —— %s\n' "$loc" "$text"
  done
  return 0
}
e2_decl_files() { e2_scan "$1" decl | cut -f1 | sed 's/:[0-9]*$//' | sort -u; }

t4_assert_match "$MINPI" '^[0-9]+\.[0-9]+\.[0-9]+$' "E2-1 基准：脚本单源 MIN_PI_VERSION = $MINPI（x.y.z）"
t4_assert_ge 40 "$(printf '%s\n' "$E2_DOC_FILES" | grep -c . || true)" \
  "E2-1 扫描面非空：现行文档 *.md ≥ 40 个（git ls-files 可用；否则下面「全绿」会无对象空转）"
t4_assert_eq "" "$(e2_gate "$T4_ROOT")" "E2-1① 现仓全绿：文档面 pi 下限 == 脚本单源（漂移 0 · 未归类 0）"
E2_DECL_N="$(e2_scan "$T4_ROOT" decl | grep -c . || true)"
E2_DECL_FILES_N="$(e2_decl_files "$T4_ROOT" | grep -c . || true)"
# P3-3(b)：计数只当「扫描器没坏」的**宽松**绊线（贴脸阈值会在「合并 intercom:36 的重复声明 /
#   删一篇文档 / 改一处措辞」时以**错误原因**红）；文档面完整性由 E2-1② 完备性判据本身负责
#   （每一处 pi 版本提及都必须归类），不靠计数。
t4_assert_ge 9 "$E2_DECL_N" "E2-1① 扫描非空转：声明**处数** ≥ 9（实测 $E2_DECL_N；留裕度，防正常收敛假红）"
t4_assert_ge 6 "$E2_DECL_FILES_N" "E2-1① 扫描非空转：声明**文件数** ≥ 6（实测 $E2_DECL_FILES_N；留裕度）"
t4_assert_eq "0" "$(e2_decl_files "$T4_ROOT" | grep -c '^\.agents/skills/codegraph\.md$' || true)" \
  "E2-1④ 历史时点不参与下限比对：codegraph.md 无「≥/低于」声明（as-of 行按「截至」标注归类）"
t4_assert_eq "1" "$(e2_scan "$T4_ROOT" loose | grep -c '^\.agents/skills/codegraph\.md:21' || true)" \
  "E2-1④ codegraph.md:21 确在完备性扫描面内（靠「截至」被放过 —— 机制承重，不是文件名白名单）"

# 夹具：现行面副本（.agents + README + AGENTS + docs/{INSTALL,ARCHITECTURE}）—— 变异只在副本
E2_LAB="$T4_CACHE_DIR/e2-1-lab-$$"
mkdir -p "$E2_LAB/docs"
cp -r "$T4_ROOT/.agents" "$E2_LAB/.agents" || t4_bad "E2-1 夹具：复制 .agents 失败"
cp "$T4_ROOT/README.md" "$T4_ROOT/AGENTS.md" "$E2_LAB/" || t4_bad "E2-1 夹具：复制 README/AGENTS 失败"
cp "$T4_ROOT/docs/INSTALL.md" "$T4_ROOT/docs/ARCHITECTURE.md" "$E2_LAB/docs/" || t4_bad "E2-1 夹具：复制 docs 失败"
t4_assert_eq "" "$(e2_gate "$E2_LAB")" "E2-1 夹具自证：未变异副本同样全绿（基准不是只有真仓能过）"

# ② 只把**脚本常量**抬到 9.9.9（副本）⇒ 必红，并点名文件:行
cp -r "$E2_LAB" "$E2_LAB-b"
sed -i 's/^MIN_PI_VERSION=.*$/MIN_PI_VERSION="9.9.9"/' "$(t4_fleet_file_with "$E2_LAB-b/.agents/scripts" 'MIN_PI_VERSION="')"
t4_assert_eq "9.9.9" "$(e2_min_of "$E2_LAB-b")" "E2-1② 变异锚点：副本单源已抬到 9.9.9"
E2B_GATE="$(e2_gate "$E2_LAB-b")"
t4_assert_match "$E2B_GATE" "^README\.md:[0-9]+ 声明 $MINPI ≠ 单源 9\.9\.9$" \
  "E2-1② 脚本常量抬 9.9.9（副本）⇒ 断言必红并点名 README.md:行（文档未动）"
t4_assert_match "$E2B_GATE" "^docs/INSTALL\.md:[0-9]+ 声明 $MINPI ≠ 单源 9\.9\.9$" \
  "E2-1② 同轮点名另一处（不是只报首个就收工）"

# ③ 只把**某文档**改成 9.9.9（副本）⇒ 同样必红（双向）
cp -r "$E2_LAB" "$E2_LAB-c"
sed -i "0,/pi ≥ $MINPI/s//pi ≥ 9.9.9/" "$E2_LAB-c/README.md"
t4_assert_eq "1" "$(grep -c 'pi ≥ 9\.9\.9' "$E2_LAB-c/README.md" || true)" "E2-1③ 变异锚点：副本 README 已改为 9.9.9（脚本未动）"
t4_assert_match "$(e2_gate "$E2_LAB-c")" "^README\.md:[0-9]+ 声明 9\.9\.9 ≠ 单源 $MINPI$" \
  "E2-1③ 文档改 9.9.9（副本）⇒ 同样必红（脚本→文档、文档→脚本两个方向都能抓）"

# ④ 摘掉 as-of 行的「截至」标注（副本）⇒ 变「未归类」必红（豁免靠标注，不靠文件名）
cp -r "$E2_LAB" "$E2_LAB-d"
sed -i "s/截至 pi $MINPI/pi $MINPI/" "$E2_LAB-d/.agents/skills/codegraph.md"
t4_assert_eq "0" "$(grep -c '截至' "$E2_LAB-d/.agents/skills/codegraph.md" || true)" "E2-1④ 变异锚点：副本 codegraph.md 的「截至」已摘掉"
t4_assert_contains "$(e2_gate "$E2_LAB-d")" "codegraph.md:21 未归类" \
  "E2-1④ 摘掉「截至」⇒ 完备性判据必红（历史时点豁免是标注机制，不是按文件名硬编码）"
rm -rf "$E2_LAB" "$E2_LAB-b" "$E2_LAB-c" "$E2_LAB-d"


# ============================================================================
# #96 二期 B1：门面 + 双实现并存的**机械保证**（BR1 六条里的四条静态面）
#   ① 默认值唯一（`grep -cE '^NAO_TERMINAL='` 恰 1 处，且就是那行默认赋值）
#   ② 门面外禁裸后端调用（标记区 + 显式台账；负控四条：status 内注入 tmux / herdr 区外 herdr /
#      herdr 区注入 TMUX_PANE / 台账 stale+typo+超 baseline+已在标记区）
#   ③ herdr 实现区禁字（TMUX / terminal_title / pane_title —— BR2/BR6 机械兜）
#   ④ check 生效后端行：**仅 herdr 模式加行**（tmux 路径零新增输出）；herdr 模式下 close/cleanup
#      **已接门面（B3）**：用法守卫先于一切后端调用（PATH 桩 0 命中），空现场按「未运行/effect=0」幂等成功
# ============================================================================
FLEET_B1="$T4_ROOT/.agents/scripts"                     # T567-A：文件集（入口 + fleet/lib/*.sh）
FLEET_B1_BUNDLE="$(t4_fleet_bundle "$FLEET_B1")"         # 只读断言（grep/awk）合并视图
LEDGER_B1="$T4_ROOT/tests/t4/fixtures/term-legacy-allowlist.txt"
t4_assert_file "$FLEET_B1/nao-fleet.sh" "B1: 被测入口脚本存在"
# T555 QA 轮实测踩到的失败模式：lint helper 本身被误删 ⇒ 调用点 rc=127 + 空输出 ⇒ 「负控必红」
#   这类断言反被掏空（假绿）。此处把「helper 存在」钉成前置（少一个就红）。
t4_assert_eq "5" "$(for _f in t4_scan_term_bare_calls t4_verify_term_ledger t4_scan_term_herdr_forbidden \
    t4_scan_nao_terminal_default_probe t4_scan_tmux_residue; do
      declare -F "$_f" >/dev/null 2>&1 && echo x; done | grep -c .)" \
  "B1: 5 个 lint helper 均已定义（缺任一 ⇒ 其负控断言会因 127/空输出假绿）"
t4_assert_file "$LEDGER_B1" "B1: 门面台账存在（tests/t4/fixtures/term-legacy-allowlist.txt）"

# ---- T567-A：函数锚三向断言（ADR D3「174 函数锚怎么迁」；T567-B 起 176 = 174 + status --json 两函数；Step 2 门面中性化 200 = 185 + 15；T573 起 231 = 200 + sessions.sh 30 + _need_logs；T574 起 232）----
#   判据：① 各模块顶层函数并集 == 清单（无漏登记 / 无重名 / 无孤儿）② 归属模块一致
#         ③ 总数守恒（清单行数 == 头 total == 实际并集 = 232）
#   锚在**清单**（functions.txt 一处 diff）：新增函数必须同行加一行 + 改头 total，否则本组必红。
FN_MANIFEST="$T4_ROOT/.agents/scripts/fleet/functions.txt"
t4_assert_file "$FN_MANIFEST" "T567-A: functions.txt 存在（函数锚的唯一清单）"
t4_assert_eq "" "$(t4_verify_functions_manifest "$FLEET_B1" "$FN_MANIFEST")" \
  "T567-A: 232 三向守恒（无漏登记/无孤儿/归属一致/总数==total）"
t4_assert_eq "232" "$(grep -vcE '^[[:space:]]*(#|$)' "$FN_MANIFEST")" "T567-A: 清单行数 == 232（200 + sessions.sh 30 + _need_logs + _term_app_name）"
t4_assert_eq "232" "$(t4_fleet_count '^[A-Za-z_][A-Za-z0-9_]*\(\)[[:space:]]*\{' "$FLEET_B1")" \
  "T567-A: 各模块顶层函数并集 == 232（数量守恒）"
# 失败演练（判据必须承重，不能空转）：三种变异各自必红
FN_MUT="$T4_CACHE_DIR/fn-manifest-$$.mut"
grep -v $'\tcmd_check$' "$FN_MANIFEST" > "$FN_MUT"
t4_assert_contains "$(t4_verify_functions_manifest "$FLEET_B1" "$FN_MUT" | grep '漏登记' || true)" "cmd_check" \
  "T567-A 负控①：清单删一行 ⇒ 必红（漏登记 · 点名 cmd_check）"
sed 's#^fleet/lib/check.sh\tcmd_check$#fleet/lib/core.sh\tcmd_check#' "$FN_MANIFEST" > "$FN_MUT"
t4_assert_contains "$(t4_verify_functions_manifest "$FLEET_B1" "$FN_MUT" || true)" "归属不符" \
  "T567-A 负控②：模块归属写错 ⇒ 必红"
sed 's/^# total: 232$/# total: 231/' "$FN_MANIFEST" > "$FN_MUT"
out="$(t4_verify_functions_manifest "$FLEET_B1" "$FN_MUT" || true)"
t4_assert_contains "$out" "总数不符" "T567-A 负控③：头 total 与并集不符 ⇒ 必红"
t4_assert_contains "$out" "清单行数 232 ≠ 头 total 231" "T567-A 负控③b：只改 total 不改行数 ⇒ 同样必红"

# ---- T572：业务层后端词静态闸（双向负控 + 判据存在 + 演练）----
t4_assert_eq "1" "$(type t4_scan_business_backend_words >/dev/null 2>&1 && echo 1 || echo 0)" \
  "T572 静态闸：t4_scan_business_backend_words 存在（删判据 ⇒ 本组必红）"
t4_assert_eq "" "$(t4_scan_business_backend_words "$FLEET_B1")" \
  "T572 静态闸：业务模块 0 后端事实词（_TERM_PLACE_/_term_*_/pane_id/workspace_id/agent_status/argv_name/hook）"
GATE_BODY="$(sed -n '/^t4_scan_business_backend_words()/,/^}/p' "$T4_ROOT/tests/t4/lib.sh")"
for _tok in _TERM_PLACE_ _term_herdr_ _term_app_ pane_id workspace_id agent_status argv_name hook; do
  t4_assert_contains "$GATE_BODY" "$_tok" "T572 静态闸：判据含禁止词 $_tok（删词 ⇒ 本组必红）"
done
BIZ_NEG="$T4_CACHE_DIR/t572-biz-neg-$$"; rm -rf "$BIZ_NEG"; mkdir -p "$BIZ_NEG"
cp "$T4_ROOT/.agents/scripts/fleet/lib/ensure.sh" "$BIZ_NEG/ensure.sh"
printf '\n: $pane_id\n' >> "$BIZ_NEG/ensure.sh"
t4_assert_contains "$(t4_scan_business_backend_words "$BIZ_NEG/ensure.sh")" "pane_id" \
  "T572 静态闸 负控：业务模块注入 pane_id ⇒ 必红并点名"
# 删判据演练：从副本里删掉 pane_id 词 ⇒ 同一违规输入不再被该词抓到
T572_LIB_NEG="$T4_CACHE_DIR/t572-lib-neg-$$.sh"
sed 's/pane_id|//' "$T4_ROOT/tests/t4/lib.sh" > "$T572_LIB_NEG"
_out="$(bash -c 'source "$1"; t4_scan_business_backend_words "$2"' _ "$T572_LIB_NEG" "$BIZ_NEG/ensure.sh" 2>/dev/null || true)"
t4_assert_eq "0" "$(printf '%s\n' "$_out" | grep -cF 'pane_id' || true)" \
  "T572 演练③：删判据里的 pane_id 词 ⇒ 同一违规不再命中（判据承重，不是恒绿）"
sed -i '/: \$pane_id/d' "$BIZ_NEG/ensure.sh"
t4_assert_eq "" "$(t4_scan_business_backend_words "$BIZ_NEG/ensure.sh")" \
  "T572 静态闸 正控：移除注入后 0 命中（判据非恒真）"
rm -rf "$BIZ_NEG" "$T572_LIB_NEG"
# 演练①：把 term_snapshot 的 5 列投影退回后端事实列 ⇒ 判据必红
T572_TERM_NEG="$T4_CACHE_DIR/t572-term-neg-$$.sh"
sed 's/_term_backend_project5/_term_backend_facts/g' \
  "$(t4_fleet_file_for "$FLEET_B1" term_snapshot)" > "$T572_TERM_NEG"
t4_assert_eq "0" "$(sed -n '/^term_snapshot()/,/^}/p' "$T572_TERM_NEG" | grep -cF '_term_backend_project5' || true)" \
  "T572 演练①：5 列退回 13 列（term_snapshot 内投影调用被替换）⇒ 0 命中"
t4_assert_eq "1" "$(sed -n '/^term_snapshot()/,/^}/p' "$(t4_fleet_file_for "$FLEET_B1" term_snapshot)" | grep -cF '_term_backend_project5' || true)" \
  "T572 演练①：真件 term_snapshot 仍走 _term_backend_project5（5 列契约）"
# 演练②：恢复 check.sh 直连后端实现 ⇒ 业务静态闸必红
T572_CHK_NEG="$T4_CACHE_DIR/t572-chk-neg-$$.sh"
cp "$(t4_fleet_file_for "$FLEET_B1" cmd_check)" "$T572_CHK_NEG"
printf '\n_term_herdr_exec api schema >/dev/null 2>&1 || true\n' >> "$T572_CHK_NEG"
t4_assert_contains "$(t4_scan_business_backend_words "$T572_CHK_NEG")" "_term_herdr_" \
  "T572 演练②：恢复 check.sh:585 直连 _term_herdr_exec ⇒ 静态闸必红"
t4_assert_eq "0" "$(grep -cF '_term_herdr_exec' "$(t4_fleet_file_for "$FLEET_B1" cmd_check)" || true)" \
  "T572 演练②：真件 check.sh 0 处直连 _term_herdr_exec"
t4_assert_ge "1" "$(grep -cF 'term_api_schema' "$(t4_fleet_file_for "$FLEET_B1" cmd_check)" || true)" \
  "T572：check.sh 的 schema 走门面 term_api_schema"

# ---- ① 默认值唯一（#96 三期 P2：默认已翻 herdr；B1 立的 lint 就是为这一步准备的）----
t4_assert_eq "1" "$(t4_fleet_count '^NAO_TERMINAL=' "$FLEET_B1")" \
  "B1① NAO_TERMINAL 赋值点跨模块总和恰 1 处（默认值唯一；T567-A 起不再限制在单文件）"
t4_assert_eq 'NAO_TERMINAL="${NAO_TERMINAL:-herdr}"' "$(grep -E '^NAO_TERMINAL=' "$FLEET_B1_BUNDLE" || true)" \
  "P2① 唯一赋值点 = 默认 **herdr**（未设/空串两种拼写走同一处）"
t4_assert_eq "0" "$(t4_fleet_count '^NAO_TERMINAL="\$\{NAO_TERMINAL:-tmux\}"' "$FLEET_B1")" \
  "P2① 反向断言：默认不再是 tmux（flip 真生效，不是两处赋值共存）"

# T567-A：SELF_SH 必须与 NAO_TERMINAL 唯一赋值点**同文件**（term.sh）—— #124 的解析点
TERM_MOD_B1="$(t4_fleet_file_for "$FLEET_B1" term_backend)"
t4_assert_eq "1" "$(t4_fleet_count '^SELF_SH=' "$FLEET_B1")" "T567-A: SELF_SH 赋值点跨模块总和恰 1 处"
t4_assert_eq "1" "$(grep -cE '^SELF_SH=' "$TERM_MOD_B1" || true)" \
  "T567-A: SELF_SH 指向 term.sh（与 NAO_TERMINAL 同文件；端前提 warn 从这里解析默认值）"

# ---- ② 门面四函数 + 纯谓词：各恰 1 处定义（业务区只调它们）----
for fn in term_require term_snapshot term_liveness term_argv term_deliverable term_spawn term_deliver term_session_start term_reclaim term_cleanup; do
  t4_assert_eq "1" "$(t4_fleet_count "^${fn}\\(\\) \\{" "$FLEET_B1")" "B1② 门面函数 ${fn} 跨模块恰 1 处定义"
done

# ---- ② 门面外禁裸后端调用（正控：真脚本 0 命中）+ 台账可验 ----
t4_assert_eq "" "$(t4_scan_term_bare_calls "$FLEET_B1" "$LEDGER_B1")" \
  "B1② 真脚本：门面外 0 处裸后端调用（标记区 + 台账之外一律红）"
t4_assert_eq "" "$(t4_verify_term_ledger "$FLEET_B1" "$LEDGER_B1")" \
  "B1② 台账可验：函数存在 · 仍含裸调用 · 去重 · 不超 baseline · 不收录渲染层/标记区内函数"
t4_assert_contains "$(head -40 "$LEDGER_B1")" "baseline: 0" \
  "B1②/B4 台账头写明 baseline（B2 减 2 / B3 减 3 / B4 减 3 ⇒ 0；只减不增）"
t4_assert_eq "0" "$(grep -vcE '^[[:space:]]*(#|$)' "$LEDGER_B1")" \
  "B4 台账条目数 = 0（布局段进 tmux 标记区 + cmd_check 的裸调用进 term_session_name 门面）"

# ---- ② 负控 A（T555/AC8）：往 cmd_status 里塞裸 tmux 调用 ⇒ 旧面 lint 必红并点名 ----
#   旧 tmux 门面分支已删 ⇒ 该注入面改由 `t4_scan_tmux_residue`（禁旧面复活）接管。
NEG_B1A="$T4_CACHE_DIR/b1-neg-a.sh"
awk '{ print } /^cmd_status\(\) \{/ { print "  tmux list-panes -a -F '"'"'#{pane_id}'"'"' >/dev/null" }' \
  "$(t4_fleet_file_for "$FLEET_B1" cmd_status)" > "$NEG_B1A"
out="$(t4_scan_tmux_residue "$NEG_B1A")"
t4_assert_ne "" "$out" "B1② 负控A: cmd_status 内注入 tmux 调用 ⇒ 旧面 lint 必红（不是空转）"
t4_assert_contains "$out" "tmux list-panes" "B1② 负控A: 命中并回显被注入的那一行（可定位）"

# ---- ② 负控 B：herdr 实现区之外直接调 herdr ⇒ 必红（唯一入口不可旁路）----
NEG_B1B="$T4_CACHE_DIR/b1-neg-b.sh"
awk '{ print } /^cmd_status\(\) \{/ { print "  herdr pane list >/dev/null" }' "$(t4_fleet_file_for "$FLEET_B1" cmd_status)" > "$NEG_B1B"
out="$(t4_scan_term_bare_calls "$NEG_B1B" "$LEDGER_B1")"
t4_assert_ne "" "$out" "B1② 负控B: cmd_status 内直接调 herdr ⇒ 必红"
t4_assert_contains "$out" "[herdr-区外]" "B1② 负控B: 命中标签点名「herdr-区外」"

# ---- ③ herdr 实现区禁字（正控 0 命中；负控：注入 TMUX_PANE / terminal_title 各必红）----
t4_assert_eq "" "$(t4_scan_term_herdr_forbidden "$FLEET_B1")" \
  "B1③ herdr 实现区 0 处 tmux 句柄/标题字段名（BR2/BR6 机械兜）"
NEG_B1C="$T4_CACHE_DIR/b1-neg-c.sh"
awk '{ print } /^# >>> term-facade-herdr BEGIN/ { print "  local leak=\"$TMUX_PANE\"" }' \
  "$(t4_fleet_file_for "$FLEET_B1" _term_herdr_exec)" > "$NEG_B1C"
out="$(t4_scan_term_herdr_forbidden "$NEG_B1C")"
t4_assert_ne "" "$out" "B1③ 负控: herdr 区注入 \$TMUX_PANE ⇒ 禁字扫描必红"
t4_assert_contains "$out" "TMUX_PANE" "B1③ 负控: 回显被注入的句柄名"
NEG_B1D="$T4_CACHE_DIR/b1-neg-d.sh"
awk '{ print } /^# >>> term-facade-herdr BEGIN/ { print "  local t=\"terminal_title\"" }' \
  "$(t4_fleet_file_for "$FLEET_B1" _term_herdr_exec)" > "$NEG_B1D"
t4_assert_ne "" "$(t4_scan_term_herdr_forbidden "$NEG_B1D")" \
  "B1③ 负控: herdr 区注入 terminal_title（读标题）⇒ 禁字扫描必红"

# ---- ② 负控 C：台账四条自证（stale / typo / 超 baseline / 已在标记区）----
NEG_LED="$T4_CACHE_DIR/b1-ledger.txt"
cp "$LEDGER_B1" "$NEG_LED"
printf 'cmd_ensure\tB2\t假条目（cmd_ensure 已无裸 tmux 调用）\n' >> "$NEG_LED"
t4_assert_contains "$(t4_verify_term_ledger "$FLEET_B1" "$NEG_LED")" "台账 stale" \
  "B1② 负控C1: 已迁移函数留在台账 ⇒ stale 必红（只减不增是断言，不是口头约定）"
cp "$LEDGER_B1" "$NEG_LED"
printf 'no_such_function_b1\tB2\ttypo\n' >> "$NEG_LED"
t4_assert_contains "$(t4_verify_term_ledger "$FLEET_B1" "$NEG_LED")" "函数不存在（typo）" \
  "B1② 负控C2: 台账函数名 typo ⇒ 必红"
cp "$LEDGER_B1" "$NEG_LED"
printf '_term_herdr_facts\tB2\t已在 herdr 标记区内（T555：旧 tmux 区间已删，改用现存标记区）\n' >> "$NEG_LED"
out="$(t4_verify_term_ledger "$FLEET_B1" "$NEG_LED")"
t4_assert_contains "$out" "台账行数 1 超过 baseline 0" "B1②/B4 负控C3: 条目数超 baseline ⇒ 必红（B4: 0 条上限；自造第 1 条即红）"
t4_assert_contains "$out" "台账多余（该函数已在标记区内" "B1② 负控C4: 标记区内函数混进台账 ⇒ 必红"

# ---- ④ check 生效后端行 + herdr 模式 fail loud（零后端调用）----
B1BIN="$T4_CACHE_DIR/b1-bin-$$"
mkdir -p "$B1BIN"
B1_LOG="$T4_CACHE_DIR/b1-calls-$$.log"; : > "$B1_LOG"
cat > "$B1BIN/herdr" <<SH
#!/usr/bin/env bash
printf 'herdr %s\n' "\$*" >> "$B1_LOG"
case "\$*" in
  *"api schema"*) printf 'Herdr API schema\nprotocol: 22\n'; exit 0 ;;
  *"--version"*)  echo 'herdr 0.9.1'; exit 0 ;;
  *"pane list"*)  printf '{"result":{"panes":[],"type":"pane_list"}}\n'; exit 0 ;;
  *"agent list"*) printf '{"result":{"agents":[],"type":"agent_list"}}\n'; exit 0 ;;
  *"session list --json"*) printf '{"sessions":[]}\n'; exit 0 ;;
  *"session stop"*|*"session delete"*) exit 0 ;;
esac
exit 0
SH
cat > "$B1BIN/tmux" <<SH
#!/usr/bin/env bash
printf 'tmux %s\n' "\$*" >> "$B1_LOG"
exec "${REAL_TMUX_B1:?}" "\$@"
SH
chmod +x "$B1BIN/herdr" "$B1BIN/tmux"
REAL_TMUX_B1="$(command -v tmux || true)"
t4_assert_ne "" "${REAL_TMUX_B1:-}" "B1④ 真 tmux 可用（桩要转发）"
# P2-1（QA 第二轮）：HERDR_SOCKET_PATH 必须落在**目标根**（${XDG_CONFIG_HOME}/herdr/sessions/<名>/）下
B1_CFG="$T4_CACHE_DIR/b1-cfg-$$"
mkdir -p "$T4_CACHE_DIR/b1-pi-empty"
B1_ENV=(env -u NAO_SKILLS NAO_TERMINAL=herdr HERDR_ENV=1 HERDR_SESSION=nao-b1-check \
  XDG_CONFIG_HOME="$B1_CFG" HERDR_SOCKET_PATH="$B1_CFG/herdr/sessions/nao-b1-check/herdr.sock" \
  PI_CODING_AGENT_DIR="$T4_CACHE_DIR/b1-pi-empty" PATH="$B1BIN:$PATH" NAO_STASH_ROOT="$C6_STASH_NONE")
# cleanup 不要求 pane 内 env（拆场是外部动作）：只给后端 + 私有根 + PATH 桩
#   #111：必须**显式清掉**调用方（herdr pane）继承的 HERDR_SOCKET_PATH / HERDR_SESSION ——
#   否则生产 socket 会被带进夹具（不在 "$B1_CFG" 目标根下 ⇒ cleanup 按「stale/外贸 env」拒绝，rc=3），
#   夹具就从「空现场幂等」变成「拒绝执行」，假红/假绿都不再反映被测逻辑。
B3_CLEAN_ENV=(env "${T4_HERDR_UNSET_ARGS[@]}" NAO_TERMINAL=herdr XDG_CONFIG_HOME="$B1_CFG" \
  PI_CODING_AGENT_DIR="$T4_CACHE_DIR/b1-pi-empty" PATH="$B1BIN:$PATH")

: > "$B1_LOG"
out="$(cd "$T4_ROOT" && "${B1_ENV[@]}" bash .agents/scripts/nao-fleet.sh check 2>&1)"; rc=$?
t4_assert_eq "0" "$rc" "B1④ herdr 模式 check rc=0（herdr 桩 protocol 22）"
t4_assert_contains "$out" "生效后端 NAO_TERMINAL=herdr" "B1④ herdr 模式 check **加一行**生效后端（BR1 六条之一）"
t4_assert_eq "0" "$(grep -c '^tmux ' "$B1_LOG" || true)" "B1④ herdr 模式 check 零 tmux 调用（桩 0 命中）"

: > "$B1_LOG"
# T555（D2/D5）：旧后端变量从「可用回退通道」变为**用法守卫**（rc=2 + 单行 stderr，命令未执行）——
#   原「=tmux check 与旧 golden 逐字等价 / 零 NAO_TERMINAL 字样」两条断言随后端退役（无对照对象），
#   改钉 fail loud 契约本身 + 零副作用（桩 herdr/tmux 均 0 命中）。
OUT_B1_TMUX_CHECK="$(cd "$T4_ROOT" && env -u NAO_SKILLS NAO_TERMINAL=tmux PATH="$B1BIN:$PATH" REAL_TMUX_B1="$REAL_TMUX_B1" NAO_STASH_ROOT="$C6_STASH_NONE" bash .agents/scripts/nao-fleet.sh check 2>&1)"
rc=$?
t4_assert_eq "2" "$rc" "B1④ 旧后端变量 check ⇒ rc=2（用法守卫，命令未执行 —— D2）"
t4_assert_match "$OUT_B1_TMUX_CHECK" '已移除 tmux 后端.*herdr' "B1④ stderr 点名「已移除」+ herdr 指路（D2 文案）"
t4_assert_eq "1" "$(printf '%s\n' "$OUT_B1_TMUX_CHECK" | grep -c . || true)" "B1④ 提示恰为单行（不刷屏）"
t4_assert_eq "0" "$(grep -cE '^(herdr|tmux) ' "$B1_LOG" || true)" "B1④ 守卫先于一切后端调用（桩 0 命中，零副作用）"

# P2④（T555 取代旧 golden）：herdr 默认摘要首行 = roles/files 计数（`layout=` 字段随 tmux 布局整组删除 —— D3）；
#   行数 = 3（摘要 + codegraph 态 + 生效后端行）。
c6_check() { # <NAO_STASH_ROOT> [check 参数...] · 在真仓跑（**herdr 默认**：不再注入旧后端变量）
  local root="$1"; shift
  ( cd "$T4_ROOT" && env -u NAO_SKILLS PATH="$B1BIN:$PATH" REAL_TMUX_B1="$REAL_TMUX_B1" \
      NAO_STASH_ROOT="$root" bash .agents/scripts/nao-fleet.sh check "$@" 2>&1 )
}
OUT_B1_BASE_CHECK="$(c6_check "$C6_STASH_NONE")"
CHECK_GOLD_LINE='check: OK · roles=7 · files=69'   # T567-A：脚本拆 11 模块 + functions.txt（53 → 65，+12）；T567-B：+2 systemd 单元模板（65 → 67）；T573：+fleet/lib/sessions.sh（67 → 68）；skills/user-guide-writing（68 → 69，#211）；改机制文件数须同步本行
t4_assert_eq "$CHECK_GOLD_LINE" "$(printf '%s\n' "$OUT_B1_BASE_CHECK" | head -1)" \
  "P2④ herdr 摘要首行 = roles/files 计数（layout= 字段随 tmux 布局删除 —— D3）"
t4_assert_eq "3" "$(printf '%s\n' "$OUT_B1_BASE_CHECK" | grep -c . || true)" \
  "P2④ herdr 摘要恒 3 行（摘要 + codegraph 态 + 生效后端）"

# ---- P2-1（#126 · QA 复核）：stash 闸对真仓也生效 ⇒ golden 面与「仓 stash」解耦（注入非仓根）----
#   机理：`check_stash_residue` 读 `$SKILLS_DIR`（= 本仓）的 `git stash list`；仓里只要有 1 条 stash
#   （BR5 自己鼓励的 `git stash push -m …` 形态），摘要首行就多 `warn=1`、md5 也变 ⇒ 本用例假红。
#   修法取 **①（注入非仓根）**：上面全部真实仓 `check` 调用已带 `NAO_STASH_ROOT=$C6_STASH_NONE`。
#   为什么不取 ②（剥掉 `warn=` / `  ! ` 行）：那会把闸门一起废掉 —— 闸门坏了 / 被删了也无人抓（空转）。
#   反空转（双向 · 判据落在闸门本身，不与 golden 混）：
#     有 stash（临时仓旁证）⇒ warn 真出现（与 golden 首行**不同**，即 QA 实测的假红面）；
#     注入非仓根 / pop 掉 ⇒ 逐字回 golden。全程只碰 `$T4_CACHE_DIR` 下的临时仓（真仓 stash 零触碰）。
#   #130 D1：stash 闸加了**年龄阈值**（默认 6h）⇒ 本段的旁证 stash 必须造固有**8 小时前**，否则
#     「刚生成 = 当天回填」分支会静默（那不是闸门坏了，而是判据已按设计收紧）。
C6_GIT="$T4_CACHE_DIR/c6-git$$"
mkdir -p "$C6_GIT"
git -C "$C6_GIT" init -q 2>/dev/null \
  && git -C "$C6_GIT" config user.email "t4@example.invalid" \
  && git -C "$C6_GIT" config user.name "t4" \
  && printf 'a\n' > "$C6_GIT/f.txt" \
  && git -C "$C6_GIT" add f.txt \
  && git -C "$C6_GIT" commit -qm init
C6_STASH_ENV=(env)   # 造 8 小时前的 stash 提交（`git stash push` 的提交时间受这两项影响）
if C6_OLD="$(date -d '8 hours ago' -R 2>/dev/null)" && [ -n "$C6_OLD" ]; then
  C6_STASH_ENV+=(GIT_COMMITTER_DATE="$C6_OLD" GIT_AUTHOR_DATE="$C6_OLD")
else
  t4_bad "P2-1 夹具：本机 date 不支持 -d『8 hours ago』⇒ 无法造超阈值 stash（年龄判据无法演练）"
fi
printf 'b\n' >> "$C6_GIT/f.txt"
"${C6_STASH_ENV[@]}" git -C "$C6_GIT" stash push -q -m "c6: sentinel-stash" -- f.txt 2>/dev/null || true
t4_assert_eq "1" "$(git -C "$C6_GIT" stash list 2>/dev/null | grep -c . || true)" \
  "P2-1 夹具自证：临时仓已有 1 条 stash（判据非空转；真仓全程未造 stash）"
t4_assert_eq "1" "$(git -C "$C6_GIT" stash list --format='%ct' | awk -v now="$(date +%s)" '{print (now-$1>=7*3600)?1:0}' | head -1)" \
  "P2-1 夹具自证：该 stash 的 %ct 在 7 小时前以上（#130 D1 年龄阈值下仍会 warn）"
warn_n() { local n; n="$(printf '%s\n' "$1" | grep -oE 'warn=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)"; printf '%s' "${n:-0}"; }
OUT_STASHED="$(c6_check "$C6_GIT")"
t4_assert_contains "$OUT_STASHED" "check: OK" "P2-1① 注入「有 stash 的临时仓」：摘要行仍在（正锚）"
t4_assert_ne "$CHECK_GOLD_LINE" "$(printf '%s\n' "$OUT_STASHED" | head -1)" \
  "P2-1① 该形态首行 ≠ golden（QA 实测的假红面 —— 现由注入规避，而非剥行）"
t4_assert_eq "1" "$(( $(warn_n "$OUT_STASHED") - $(warn_n "$OUT_B1_BASE_CHECK") ))" \
  "P2-1② 相对基线（同形态无 stash 注入的那一轮）恰 +1 条 warn（闸门真在跑）"
OUT_STASHED_V="$(c6_check "$C6_GIT" -v)"
t4_assert_eq "1" "$(printf '%s\n' "$OUT_STASHED_V" | grep -c '^  ! git stash' || true)" \
  "P2-1② warn 真出现时**断言仍能抓**：\`-v\` 恰 1 条 stash warn（未被本用例剥掉 ⇒ 非空转）"
t4_assert_contains "$OUT_STASHED_V" "BR5" "P2-1② 该 warn 含 BR5 依据（与 cases/35 同文案契约）"
OUT_NOSTASH="$(c6_check "$C6_STASH_NONE")"
t4_assert_eq "$CHECK_GOLD_LINE" "$(printf '%s\n' "$OUT_NOSTASH" | head -1)" \
  "P2-1③ 注入非仓根：首行 == golden（不受仓 stash 影响）"
t4_assert_not_contains "$OUT_NOSTASH" "warn=" "P2-1③ 注入非仓根：无 warn= 字段（不新增噪音）"
git -C "$C6_GIT" stash pop -q 2>/dev/null || true
t4_assert_eq "0" "$(git -C "$C6_GIT" stash list 2>/dev/null | grep -c . || true)" \
  "P2-1 夹具自证：pop 后临时仓无 stash"
OUT_POPPED="$(c6_check "$C6_GIT")"
t4_assert_not_contains "$OUT_POPPED" "warn=" "P2-1④ pop 掉 ⇒ warn 消失（双向，判据非恒真）"

# >>> default-value-probe BEGIN（#96 P2：验「默认值」的探针段 —— 全仓唯一允许 unset 的位置）
: > "$B1_LOG"
out="$(cd "$T4_ROOT" && env -u NAO_TERMINAL -u NAO_SKILLS PATH="$B1BIN:$PATH" REAL_TMUX_B1="$REAL_TMUX_B1" NAO_STASH_ROOT="$C6_STASH_NONE" bash .agents/scripts/nao-fleet.sh check 2>&1)"; rc=$?
t4_assert_eq "0" "$rc" "P2① 未设 NAO_TERMINAL（默认）check rc=0"
t4_assert_contains "$out" "生效后端 NAO_TERMINAL=herdr" \
  "P2① 未设 ⇒ herdr（默认已翻；B1 的「仅 herdr 模式加行」靠本行反向验）"
t4_assert_eq "3" "$(printf '%s\n' "$out" | grep -c . || true)" \
  "P2① 未设(herdr) check = 3 行（摘要 + codegraph 态 + 生效后端行）"
t4_assert_ne "$OUT_B1_TMUX_CHECK" "$out" \
  "P2① 反向断言：未设(herdr) 与 显式 =tmux 的 check 输出必 **不同**（防 flip 未生效仍全绿）"
# >>> default-value-probe END

# B2（#96 二期）：ensure 已接 —— 不再是 exit 4；但桩夹具（pane/workspace 都为空）下必须 **fail loud**
#   （逐目标 warn + 失败计数），且 **零 tmux 调用**；T563/AC5 起**全败 ⇒ rc=1**（不再恒 0）。
: > "$B1_LOG"
out="$(cd "$T4_ROOT" && "${B1_ENV[@]}" bash .agents/scripts/nao-fleet.sh ensure rd-fe 2>&1)"; rc=$?
t4_assert_eq "1" "$rc" "B2④ herdr 模式 ensure 全败 ⇒ rc=1（T563/AC5；仍是 SPAWN_FAIL 而非 crash）"
t4_assert_not_contains "$out" "在 herdr 后端未实现" "B2④ herdr 模式 ensure 不再点名「未实现」"
t4_assert_contains "$out" "失败 1" "B2④ herdr 模式 ensure 失败计入摘要（逐目标 fail loud，不冒充成功）"
t4_assert_contains "$out" "herdr" "B2④ herdr 模式 ensure 走 herdr 分支（桩有调用）"
t4_assert_eq "0" "$(grep -c '^tmux ' "$B1_LOG" || true)" "B2④ herdr 模式 ensure 零 tmux 调用（后端隔离）"
t4_assert_ge "1" "$(grep -c '^herdr ' "$B1_LOG" || true)" "B2④ herdr 模式 ensure 确有 herdr 调用（非空转）"

# B3（#96 二期）：close / cleanup 已接门面 —— 不再是 exit 4；空现场按幂等成功（未运行 / effect=0）
: > "$B1_LOG"
out="$(cd "$T4_ROOT" && "${B1_ENV[@]}" bash .agents/scripts/nao-fleet.sh close rd-fe 2>&1)"; rc=$?
t4_assert_eq "0" "$rc" "B3④ herdr 模式 close 不再是 exit 4（回收面已接；空 label ⇒ 未运行 rc=0）"
t4_assert_not_contains "$out" "在 herdr 后端未实现" "B3④ herdr 模式 close 不再点名「未实现」"
t4_assert_contains "$out" "rd-fe 未运行（无需回收）" "B3④ close 空现场：幂等成功行（不谎报在线/失败）"
t4_assert_ge "1" "$(grep -c '^herdr ' "$B1_LOG" || true)" "B3④ herdr 模式 close 确有 herdr 调用（非空转）"
t4_assert_eq "0" "$(grep -c '^tmux ' "$B1_LOG" || true)" "B3④ herdr 模式 close 零 tmux 调用（后端隔离）"

: > "$B1_LOG"
out="$(cd "$T4_ROOT" && "${B3_CLEAN_ENV[@]}" bash .agents/scripts/nao-fleet.sh cleanup --session nao-b3-gate 2>&1)"; rc=$?
t4_assert_eq "0" "$rc" "B3④ herdr 模式 cleanup --session 不再是 exit 4（幂等：effect=0）"
t4_assert_contains "$out" "effect=0" "B3④ cleanup 空现场：明确报 effect=0（判 effect 不看 rc）"
t4_assert_not_contains "$out" "在 herdr 后端未实现" "B3④ herdr 模式 cleanup 不再点名「未实现」"
t4_assert_eq "0" "$(grep -c '^tmux ' "$B1_LOG" || true)" "B3④ herdr 模式 cleanup 零 tmux 调用（后端隔离）"
# 用法守卫先于一切后端调用：缺 --session / default / -S 误用
for b3guard in "" "default"; do
  : > "$B1_LOG"
  if [ -z "$b3guard" ]; then
    err="$(cd "$T4_ROOT" && "${B3_CLEAN_ENV[@]}" bash .agents/scripts/nao-fleet.sh cleanup 2>&1 >/dev/null)"; rc=$?
    t4_assert_eq "2" "$rc" "B3④ herdr cleanup 缺 --session ⇒ rc=2（显式目标必给）"
    t4_assert_contains "$err" "须显式 --session" "B3④ 缺参给可执行指路"
  else
    err="$(cd "$T4_ROOT" && "${B3_CLEAN_ENV[@]}" bash .agents/scripts/nao-fleet.sh cleanup --session "$b3guard" 2>&1 >/dev/null)"; rc=$?
    # T554 反转：default 由「拒绝」改为「放行 + 破坏性门槛」——无 --force ⇒ 打印影响面 + rc=2 零动作
    t4_assert_eq "2" "$rc" "B3④ herdr cleanup --session default 无 --force ⇒ rc=2（放行但零动作）"
    t4_assert_contains "$err" "将停止 session=default，影响" "B3④ default 打印影响面"
    t4_assert_not_contains "$err" "≠default" "B3④ 旧「≠default」拒绝文案已退场"
    t4_assert_eq "0" "$(grep -cE '^(herdr|tmux) .*session (stop|delete)( |$)' "$B1_LOG" || true)" "B3④ default 零拆场动作"
  fi
  if [ -z "$b3guard" ]; then
    t4_assert_eq "0" "$(grep -cE '^(herdr|tmux) ' "$B1_LOG" || true)" "B3④ 缺参守卫先于一切后端调用（桩 0 命中）"
  fi
done

# ---- B2（#96 二期 · T555 收窄）：session-start —— herdr 守卫（--session 必填 · ≠default）----
#   「tmux 幂等无操作」三条断言随后端删除（`term_session_start` 的 tmux 分支已整组删除，无对照对象）。
: > "$B1_LOG"
err="$(cd "$T4_ROOT" && "${B1_ENV[@]}" bash .agents/scripts/nao-fleet.sh session-start --session default 2>&1 >/dev/null)"; rc=$?
t4_assert_eq "2" "$rc" "B2④ herdr 模式 session-start --session default ⇒ rc=2（BR9：绝不碰用户会话）"
t4_assert_contains "$err" "≠default" "B2④ session-start 拒绝 default 并点名原因"
err="$(cd "$T4_ROOT" && "${B1_ENV[@]}" bash .agents/scripts/nao-fleet.sh session-start 2>&1 >/dev/null)"; rc=$?
t4_assert_ne "0" "$rc" "B2④ herdr 模式 session-start 缺 --session ⇒ 非 0（用法守卫）"
t4_assert_contains "$err" "需要 --session" "B2④ session-start 缺参给可执行指路"
: > "$B1_LOG"
out="$(cd "$T4_ROOT" && "${B1_ENV[@]}" bash .agents/scripts/nao-fleet.sh session-start --session nao-b2-start 2>&1)"; rc=$?
t4_assert_eq "0" "$rc" "B2④ herdr 模式 session-start 可用（桩 api snapshot 可应答 ⇒ 已就绪）"
t4_assert_contains "$out" "herdr session=nao-b2-start" "B2④ session-start 回显目标会话名"
t4_assert_eq "" "$(grep -v -- '--session nao-b2-start' "$B1_LOG" | grep '^herdr ' || true)" \
  "B2④ session-start 的每次 herdr 调用都带 --session nao-b2-start（唯一入口，禁串到 default）"
: > "$B1_LOG"
err="$(cd "$T4_ROOT" && "${B3_CLEAN_ENV[@]}" bash .agents/scripts/nao-fleet.sh cleanup -S /tmp/b1-sock 2>&1 >/dev/null)"; rc=$?
t4_assert_eq "2" "$rc" "B3④ herdr cleanup 给 -S ⇒ rc=2（-S 只属 tmux 实验场；按后端分派）"
t4_assert_contains "$err" "用 --session" "B3④ -S 误用：指路 --session"
t4_assert_eq "0" "$(grep -cE '^(herdr|tmux) ' "$B1_LOG" || true)" "B3④ -S 误用零后端调用（守卫在一切副作用之前）"

# 非法后端取值 ⇒ fail loud（rc=2 用法守卫；禁静默回落 tmux）
err="$(cd "$T4_ROOT" && env NAO_TERMINAL=bogus bash .agents/scripts/nao-fleet.sh status 2>&1 >/dev/null)"; rc=$?
t4_assert_eq "2" "$rc" "B1④ NAO_TERMINAL=bogus ⇒ rc=2（fail loud，不静默回落）"
t4_assert_contains "$err" "NAO_TERMINAL=bogus 非法" "B1④ 非法后端回显取值与期望值域"
# P3-2（PM 拍板）：`NAO_TERMINAL=`（空串）= 未设（`:-` 是 shell 标准语义）⇒ **herdr** 默认（三期 P2 改写：
#   空串仍不是错配，但默认已不是 tmux）；大小写敏感：`=TMUX` 仍 rc=2。两条一起钉住「空串放过、拼错不放」。
# >>> default-value-probe BEGIN（#96 P2：空串探针 —— 全仓唯一允许空串的位置）
out="$(cd "$T4_ROOT" && env -u NAO_SKILLS NAO_TERMINAL= PATH="$B1BIN:$PATH" REAL_TMUX_B1="$REAL_TMUX_B1" NAO_STASH_ROOT="$C6_STASH_NONE" bash .agents/scripts/nao-fleet.sh check 2>&1)"; rc=$?
t4_assert_eq "0" "$rc" "P2① NAO_TERMINAL=（空串）= 未设 ⇒ 按 **herdr** 默认跑（rc=0）"
t4_assert_contains "$out" "生效后端 NAO_TERMINAL=herdr" \
  "P2① 空串 ⇒ herdr（:- 语义；不是 tmux、也不是非法）"
# >>> default-value-probe END
err="$(cd "$T4_ROOT" && env NAO_TERMINAL=TMUX bash .agents/scripts/nao-fleet.sh status 2>&1 >/dev/null)"; rc=$?
t4_assert_eq "2" "$rc" "B1④ NAO_TERMINAL=TMUX（大小写不符）⇒ rc=2（空串放过、拼错不放）"

# ============================================================================
# #96 三期 P2：① herdr 侧每条 exit 3 文案都带回退指路（AC3.3）
#               ② **测试不依赖默认值**（静态面：块外 0 处 unset/空串）
#   口径：默认已 = herdr ⇒ 任何用例靠「未设」搭车 = 不可复现。基线由 run.sh 显式导出；
#   唯一例外 = 验默认值的探针段（`# >>> default-value-probe BEGIN/END`）。
# ============================================================================
# ---- ① exit 3 文案全扫（一条断言扫全部，不抽查）----
# 站点识别：**token 级**（#96 P2-P3-3）。只用「独占行」形态会漏 `cmd || exit 3` / `… ; exit 3`，
#   而计数断言照样绿 ⇒ 判据对未来写法脆。这里两轴并存：
#     axis-1 独占行数（历史形态，也用于「8 站点」的稳定叙述）
#     axis-2 token 级站点数（命令位：行首 / ; | & ( { / then|else|do 之后），排除整行注释
#   两者当前相等（= 8，说明没有非独占形态）；若将来有人写成 `|| exit 3`，axis-2 会变而 axis-1 不变 ⇒ 断言咬。
exit3_token_sites() { # <script> → 每行 "<行号>\t<该行原文>"（仅命令位站点）
  awk '
    /^[[:space:]]*#/ { next }
    {
      line = $0; ok = 0
      while (match(line, /exit[[:space:]]+3([^0-9]|$)/)) {
        pre = substr(line, 1, RSTART - 1)
        t = pre; sub(/[[:space:]]+$/, "", t)
        last = (length(t) ? substr(t, length(t), 1) : "")
        if (last == "" || last ~ /[;&|({]/ || t ~ /(then|else|do)$/) ok = 1
        line = substr(line, RSTART + RLENGTH)
      }
      if (ok) printf "%d\t%s\n", NR, $0
    }' "$1"
}
exit3_hint_scan() { # <script> → 逐站点检查前 3 行报文是否带指路（无指路则打印行号）
  local script="$1" ln body
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    body="$(awk -v n="$ln" 'NR >= n - 3 && NR <= n { buf = buf "\n" $0 } END { print buf }' "$script")"
    case "$body" in
      *"重试"*|*"pin 回"*) continue ;;   # T555：tmux 回退指路已删 ⇒ 判据 = 报文给出后续动作
    esac
    printf '%s: 报文缺回退指路\n' "$ln"
  done < <(exit3_token_sites "$script" | cut -f1)
}
EXIT3_STANDALONE="$(grep -cE '^[[:space:]]*exit 3[[:space:]]*$' "$FLEET_B1_BUNDLE" || true)"
EXIT3_TOKEN="$(exit3_token_sites "$FLEET_B1_BUNDLE" | grep -c . || true)"
# T562：第二后端（app）**结构上需要自己的 exit 3 闸门**（三件套/窗口/socket/放置文档）。
#   判据零放松：按「**app 区间内 / 外**」二分（不是按 herdr 区间 —— 旧面第 7 条本来就在区间外的 cmd_status）：
#     ① app 区间外（旧面）token 位站点仍**恰 7**（T555 原句不变量逐字保留）；
#     ② 两轴总数相加 == 站点总数（无游离站点）；③ 每条都带指路（下面全扫断言覆盖两侧）。
_app_r="$(_t4_term_ranges "$FLEET_B1_BUNDLE" term-impl-app)"
_exit3_in() { # <script> <ranges> → 该区间内的 exit 3 token 位行号
  local script="$1" ln
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    _t4_in_ranges "$ln" "$2" && printf '%s\n' "$ln"
  done < <(exit3_token_sites "$script" | cut -f1)
}
EXIT3_APP="$(_exit3_in "$FLEET_B1_BUNDLE" "$_app_r" | grep -c . || true)"
EXIT3_LEGACY=$((EXIT3_STANDALONE - EXIT3_APP))
# T567-B：8 = T555 原 7 处 + `status --json` 的 rc=3 前提闸门（环境级失败，orch 据此「不写 blocked」）
t4_assert_eq "8" "$EXIT3_LEGACY" "P2② app 区间**外**（旧面）token 位 exit 3 = 8（T555 原 7 + status --json 闸门）"
t4_assert_ge "1" "$EXIT3_APP" "P2② app 区间内 exit 3 闸门存在（三件套/窗口/socket/文档前置）"
t4_assert_eq "$EXIT3_TOKEN" "$((EXIT3_LEGACY + EXIT3_APP))" \
  "P2② token 位站点总数 = 旧面(7) + app($EXIT3_APP)（无区间外游离站点）"
t4_assert_eq "$EXIT3_STANDALONE" "$EXIT3_TOKEN" \
  "P2② 两轴相等（独占行与 token 位当前同值；若有人写成「cmd || exit 3」本断言会把差异摆出来）"
t4_assert_eq "" "$(exit3_hint_scan "$FLEET_B1_BUNDLE")" \
  "P2② 每条 exit 3 文案都给后续动作（重试 / pin 回旧版；T555：tmux 回退指路已随后端删除）"
EXIT3_HINTED="$(exit3_token_sites "$FLEET_B1_BUNDLE" | cut -f1 | while IFS= read -r ln; do
  body="$(awk -v n="$ln" 'NR >= n - 3 && NR <= n { buf = buf "\n" $0 } END { print buf }' "$FLEET_B1_BUNDLE")"
  case "$body" in *"重试"*|*"pin 回"*) printf 'x\n' ;; esac
done | grep -c . || true)"
t4_assert_eq "$EXIT3_TOKEN" "$EXIT3_HINTED" "P2② 含后续动作的 exit 3 = 全数（herdr 7 + app $EXIT3_APP）"

# 负控 A：摘掉一条 herdr 文案的回退指路 ⇒ hint 扫描恰 1 条必红（判据非空转）
NEG_EXIT3="$T4_CACHE_DIR/p2-neg-exit3-$$.sh"
sed 's/—— 在该 herdr 会话的 pane 内重试（旧版 tmux 后端已移除）//' "$FLEET_B1_BUNDLE" > "$NEG_EXIT3"
t4_assert_eq "1" "$(exit3_hint_scan "$NEG_EXIT3" | grep -c . || true)" \
  "P2② 负控A：摘掉一条 herdr 文案的回退指路 ⇒ 全扫恰 1 条必红（断言不是空转）"
rm -f "$NEG_EXIT3"

# 负控 B（P3-3）：把一条「独占行」站点改成 `cmd || exit 3` 形态 ⇒ **独占行数 -1、token 数不变**
#   ⇒ 证明 token 轴真的能捕获独占行判据漏掉的写法（也证明上面「两轴相等」不是恒等式）。
NEG_EXIT3B="$T4_CACHE_DIR/p2-neg-exit3b-$$.sh"
awk '{ if ($0 ~ /^[[:space:]]*exit 3[[:space:]]*$/ && !done) { sub(/^[[:space:]]*exit 3[[:space:]]*$/, "    : || exit 3"); done = 1 } print }' \
  "$FLEET_B1_BUNDLE" > "$NEG_EXIT3B"
t4_assert_eq "$((EXIT3_STANDALONE - 1))" "$(grep -cE '^[[:space:]]*exit 3[[:space:]]*$' "$NEG_EXIT3B" || true)" \
  "P2② 负控B：改成「cmd || exit 3」后独占行数 -1（旧判据会漏掉它）"
t4_assert_eq "$EXIT3_TOKEN" "$(exit3_token_sites "$NEG_EXIT3B" | grep -c . || true)" \
  "P2② 负控B：token 级计数不变 ⇒ 新写法被计入（≠ 旧判据）"
t4_assert_eq "" "$(exit3_hint_scan "$NEG_EXIT3B")" \
  "P2② 负控B：该形态同样受报文指路判据约束（hint 仍在 ⇒ 0 命中）"
sed -i 's/—— 在该 herdr 会话的 pane 内重试（旧版 tmux 后端已移除）//' "$NEG_EXIT3B"
t4_assert_eq "1" "$(exit3_hint_scan "$NEG_EXIT3B" | grep -c . || true)" \
  "P2② 负控B2：该形态缺指路时 hint 扫描必红（覆盖到位，不是只计数）"
rm -f "$NEG_EXIT3B"

# 负控 C（T562 · app 轴防空转）：把 **app 区间内**第一条独占行改成 `cmd || exit 3`
#   ⇒ 独占行总数 −1、app 区间 token 位**不变**（证明 app 轴真的按区间在算，不是空转）。
NEG_EXIT3C="$T4_CACHE_DIR/p2-neg-exit3c-$$.sh"
awk -v s="$(_t4_term_ranges "$FLEET_B1_BUNDLE" term-impl-app | cut -f1)" '
  NR >= s && !done && $0 ~ /^[[:space:]]*exit 3[[:space:]]*$/ { sub(/^[[:space:]]*exit 3[[:space:]]*$/, "    : || exit 3"); done = 1 }
  { print }' "$FLEET_B1_BUNDLE" > "$NEG_EXIT3C"
t4_assert_eq "$((EXIT3_STANDALONE - 1))" "$(grep -cE '^[[:space:]]*exit 3[[:space:]]*$' "$NEG_EXIT3C" || true)" \
  "P2② 负控C：app 区间内改「cmd || exit 3」⇒ 独占行总数 −1"
t4_assert_eq "$EXIT3_APP" "$(_exit3_in "$NEG_EXIT3C" "$_app_r" | grep -c . || true)" \
  "P2② 负控C：app 区间 token 位计数不变（app 轴不是空转）"
rm -f "$NEG_EXIT3C"

# ---- ② 测试不依赖默认值（静态面）----
CASES_DIR="$T4_ROOT/tests/t4/cases"
t4_assert_eq "1" "$(grep -cE '^export NAO_TERMINAL="\$BACKEND"$' "$T4_ROOT/tests/t4/run.sh" || true)" \
  "P2③ 测试基座：run.sh 按 BE_BACKEND 显式导出 NAO_TERMINAL（CI 固定后端）"
t4_assert_eq "1" "$(grep -cE "printf 'NAO_TERMINAL=(tmux|herdr)" "$T4_ROOT/tests/t4/lib-backend.sh" || true)" \
  "P2③ 测试基座：be_fleet_handles 显式给 NAO_TERMINAL=herdr（T555：单后端，不靠默认值）"
t4_assert_eq "" "$(t4_scan_nao_terminal_default_probe "$CASES_DIR")" \
  "P2③ 全部用例：默认值探针块外 0 处 unset / env -u / 空串 NAO_TERMINAL ⇒ 无任何用例在 unset 下跑生产路径"
t4_assert_eq "$(sed -n '/^CASE_IDS=(/,/)/p' "$T4_ROOT/tests/t4/run.sh" | grep -oE '"[0-9]+"' | wc -l | tr -d ' ')" \
  "$(ls -1 "$CASES_DIR"/*.sh | wc -l | tr -d ' ')" \
  "P2③ 扫描面 = 全部用例文件（= run.sh CASE_IDS 登记数；用例增删须两侧同步）"
t4_assert_eq "$(sed -n '/^CASE_IDS=(/,/)/p' "$T4_ROOT/tests/t4/run.sh" | grep -oE '"[0-9]+"' | tail -1 | tr -d '"')" \
  "$(ls -1 "$CASES_DIR"/*.sh | tail -1 | sed -E 's#.*/([0-9]+)-.*#\1#')" \
  "P2③ 最大用例编号 = run.sh CASE_IDS 末位（退役编号不复用）"
t4_assert_eq "06-contract-guards.sh 28-naming-contract.sh 44-app-backend.sh 45-app-placement.sh" \
  "$(grep -l 'default-value-probe BEGIN' "$CASES_DIR"/*.sh | while IFS= read -r f; do basename "$f"; done | sort | paste -sd' ' -)" \
  "P2③ 默认值探针块白名单 = 显式文件清单（06 默认值段 · 28 P2① herdr golden/默认值反向断言 · 44 AC1「默认=herdr」反向断言 · 45 #175 AC4「app 终端内未设 NAO_TERMINAL」；新增须显式改本断言，不靠计数漂移）"
# 负控：块外注入 unset ⇒ 必被扫到（并点名行号与形态）
#   注：本段用 printf **构造**违规样本（不是执行默认值探针）；构造串里必然出现被扫关键字，
#   故一并包在标记块内（否则用例 06 会「自我举报」—— 判据只白名单标记块内文本）。
# >>> default-value-probe BEGIN（构造负控样本）
PROBE_NEG_DIR="$T4_CACHE_DIR/p2-probe-neg-$$"
mkdir -p "$PROBE_NEG_DIR"
cp "$CASES_DIR/13-close-guards.sh" "$PROBE_NEG_DIR/x.sh"
printf '\nunset NAO_TERMINAL\n' >> "$PROBE_NEG_DIR/x.sh"
PROBE_NEG_OUT="$(t4_scan_nao_terminal_default_probe "$PROBE_NEG_DIR")"
t4_assert_contains "$PROBE_NEG_OUT" "[unset]" "P2③ 负控：探针块外 unset ⇒ 扫描必红并点名（判据非空转）"
printf '\nenv -u NAO_TERMINAL true\n' >> "$PROBE_NEG_DIR/x.sh"
t4_assert_contains "$(t4_scan_nao_terminal_default_probe "$PROBE_NEG_DIR")" "[env -u]" \
  "P2③ 负控：探针块外 env -u ⇒ 扫描必红"
# 正控：同一份内容放进标记块 ⇒ 0 命中（白名单不是空话）
cp "$CASES_DIR/13-close-guards.sh" "$PROBE_NEG_DIR/y.sh"
printf '\n# >>> default-value-probe BEGIN\nunset NAO_TERMINAL\nenv NAO_TERMINAL= true\n# >>> default-value-probe END\n' >> "$PROBE_NEG_DIR/y.sh"
t4_assert_eq "" "$(t4_scan_nao_terminal_default_probe "$PROBE_NEG_DIR/y.sh")" \
  "P2③ 正控：标记块内的 unset/空串被放过（白名单生效；否则真用例无法验默认值）"
rm -rf "$PROBE_NEG_DIR"
# >>> default-value-probe END

# ============================================================================
# E1（#128）：卡预算基线可观测 + 超阈值有信号（warn-only，不改 rc）
#   判据（PRD AC5）：
#     ① `check -v` 能报「各卡行数 + 最大占比」；数字与实测一致（不是抄死值）。
#     ② 超阈值仍有逐卡 `!` + 基线 >100%，但 rc 仍 0（不设硬限、不改闸门语义）。
#     ③ 移除基线实现 ⇒ 同一判据取值为 0（非空转，先红后绿的机检面）。
#   CARD_MAX_LINES 保持 200；本段从脚本抽常量，不在用例里复制第二份阈值。
E1_FLEET="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"   # T567-A：常量在 core.sh
E1_CARD_MAX="$(sed -n 's/^CARD_MAX_LINES=\([0-9][0-9]*\)$/\1/p' "$E1_FLEET" | head -1)"
t4_assert_eq "200" "$E1_CARD_MAX" "E1: CARD_MAX_LINES 保持 200（不设硬限；阈值仍由脚本单点给）"

E1_REAL_MAX=0; E1_REAL_NAME=""
for f in "$T4_ROOT"/.agents/prompts/*.md; do
  n="$(wc -l < "$f" | tr -d ' ')"
  if [ "$n" -gt "$E1_REAL_MAX" ]; then E1_REAL_MAX="$n"; E1_REAL_NAME="$(basename "$f")"; fi
done
E1_REAL_OUT="$( cd "$T4_ROOT" && env -u NAO_SKILLS NAO_STASH_ROOT="$C6_STASH_NONE" timeout 120 bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
E1_REAL_RC=$?
t4_assert_eq "0" "$E1_REAL_RC" "E1: 真仓 check -v rc=0（基线不改 rc）"
E1_LINE="$(printf '%s\n' "$E1_REAL_OUT" | grep -m1 '卡预算基线' || true)"
t4_assert_ne "" "$E1_LINE" "E1: check -v 输出卡预算基线行（可观测）"
E1_FIELDS="$(printf '%s\n' "$E1_LINE" | sed -nE 's/.*最大 ([^ ]+) ([0-9]+) 行 \/ 阈值 ([0-9]+) 行（([0-9]+\.[0-9]+)%）.*/\1 \2 \3 \4/p')"
read -r E1_GOT_NAME E1_GOT_LINES E1_GOT_THR E1_GOT_PCT <<< "$E1_FIELDS"
E1_PCT10=$(( E1_REAL_MAX * 1000 / E1_CARD_MAX ))
E1_EXP_PCT="$((E1_PCT10 / 10)).$((E1_PCT10 % 10))"
t4_assert_eq "$E1_REAL_NAME" "${E1_GOT_NAME:-}" "E1: 基线最大卡与实测最大卡同名（$E1_REAL_NAME）"
t4_assert_eq "$E1_REAL_MAX" "${E1_GOT_LINES:-}" "E1: 基线行数与实测一致（$E1_REAL_MAX 行）"
t4_assert_eq "$E1_CARD_MAX" "${E1_GOT_THR:-}" "E1: 基线阈值取自脚本常量（$E1_CARD_MAX 行）"
t4_assert_eq "$E1_EXP_PCT" "${E1_GOT_PCT:-}" "E1: 基线最大占比与实测一致（$E1_EXP_PCT%）"

# 超阈值负控：副本里把最大卡垫到 CARD_MAX+1 行（真仓零触碰）⇒ 逐卡 ! + 基线 >100%，rc 仍 0
E1_LAB="$T4_CACHE_DIR/e1-card-$$"
E1_BIN="$T4_CACHE_DIR/e1-bin-$$"
mkdir -p "$E1_LAB" "$E1_BIN"
cp -r "$T4_ROOT/.agents" "$E1_LAB/.agents" || t4_bad "E1: 复制 .agents 到夹具失败"
printf '#!/usr/bin/env bash\n[ "${1:-}" = "--version" ] && { echo "%s"; exit 0; }\nexit 0\n' "$MINPI" > "$E1_BIN/pi"
chmod +x "$E1_BIN/pi"
# P3-1（#132）：夹具 check 一律清 `NAO_SKILLS` —— 否则宿主 `export NAO_SKILLS=<真仓>` 会让夹具去读
#   真仓的 `.agents`（`nao-fleet.sh:125 SKILLS_DIR="${NAO_SKILLS:-<脚本>/../..}"`）⇒ 假红/假绿。
#   `E1_ENV_LEAK` = **故意不清**的镜像（负控专用：证明 `-u` 承重，不是为了绕过判据）。
E1_ENV=(env -u NAO_STASH_ROOT -u NAO_SKILLS PATH="$E1_BIN:$PATH")
E1_ENV_LEAK=(env -u NAO_STASH_ROOT PATH="$E1_BIN:$PATH")
E1_TARGET="$E1_LAB/.agents/prompts/$E1_REAL_NAME"
E1_HAVE="$(wc -l < "$E1_TARGET" | tr -d ' ')"
if [ "$E1_HAVE" -le "$E1_CARD_MAX" ]; then
  E1_NEED=$(( E1_CARD_MAX + 1 - E1_HAVE ))
  for ((E1_I = 0; E1_I < E1_NEED; E1_I++)); do printf -- '- E1 padding\n' >> "$E1_TARGET"; done
fi
E1_LAB_MAX=0; E1_LAB_NAME=""
for f in "$E1_LAB"/.agents/prompts/*.md; do
  n="$(wc -l < "$f" | tr -d ' ')"
  if [ "$n" -gt "$E1_LAB_MAX" ]; then E1_LAB_MAX="$n"; E1_LAB_NAME="$(basename "$f")"; fi
done
t4_assert_ge "$((E1_CARD_MAX + 1))" "$E1_LAB_MAX" "E1 夹具：最大卡已超阈值（$E1_LAB_NAME $E1_LAB_MAX 行）"
E1_LAB_OUT="$( cd "$E1_LAB" && "${E1_ENV[@]}" timeout 120 bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
E1_LAB_RC=$?
t4_assert_eq "0" "$E1_LAB_RC" "E1 超阈值：check rc 仍 0（warn-only，不设硬限）"
t4_assert_contains "$E1_LAB_OUT" "! $E1_LAB_NAME" "E1 超阈值：逐卡行报 !（点名 $E1_LAB_NAME）"
t4_assert_contains "$E1_LAB_OUT" "$E1_LAB_MAX 行" "E1 超阈值：报出实际行数 $E1_LAB_MAX"
E1_LAB_PCT10=$(( E1_LAB_MAX * 1000 / E1_CARD_MAX ))
E1_LAB_PCT="$((E1_LAB_PCT10 / 10)).$((E1_LAB_PCT10 % 10))"
t4_assert_contains "$E1_LAB_OUT" "最大 $E1_LAB_NAME $E1_LAB_MAX 行 / 阈值 $E1_CARD_MAX 行（$E1_LAB_PCT%）" \
  "E1 超阈值：基线给最大占比 $E1_LAB_PCT%（>100% 可见）"

# 变异自证：删掉副本脚本里的基线输出行 ⇒ 同一判据取值为 0（实现承重，不是空转）
E1_MUT="$E1_LAB-mut"
cp -r "$E1_LAB" "$E1_MUT" || t4_bad "E1 变异：副本创建失败"
sed -i '/卡预算基线/d' "$(t4_fleet_file_with "$E1_MUT/.agents/scripts" '卡预算基线')"
E1_MUT_OUT="$( cd "$E1_MUT" && "${E1_ENV[@]}" timeout 120 bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
E1_MUT_HIT=0
if printf '%s\n' "$E1_MUT_OUT" | grep -qF '卡预算基线'; then E1_MUT_HIT=1; fi
t4_assert_eq "0" "$E1_MUT_HIT" "E1 变异：移除基线实现 ⇒ 同一判据取值为 0（断言非空转）"

# ---- P3-1（#132）：宿主 `NAO_SKILLS` 不得渗进夹具（正控 / 负控镜像 / 静态审计）----
#   正控：宿主 env 给 `NAO_SKILLS=<真仓>`，`E1_ENV` 里的 `-u NAO_SKILLS` 必须盖掉它 ⇒ 仍报夹具垫过的行数。
#   负控镜像：同一夹具、同一制品，只把 `-u NAO_SKILLS` 拿掉 ⇒ 读到真仓 ⇒ 报不出夹具行数（证明正控不是白过）。
E1_POISON_OUT="$( cd "$E1_LAB" && NAO_SKILLS="$T4_ROOT" "${E1_ENV[@]}" \
  timeout 120 bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$E1_POISON_OUT" "最大 $E1_LAB_NAME $E1_LAB_MAX 行" \
  "P3-1 正控：宿主 NAO_SKILLS=<真仓> ⇒ 夹具仍读**夹具**的 .agents（\`-u NAO_SKILLS\` 承重）"
E1_LEAK_OUT="$( cd "$E1_LAB" && NAO_SKILLS="$T4_ROOT" "${E1_ENV_LEAK[@]}" \
  timeout 120 bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_not_contains "$E1_LEAK_OUT" "最大 $E1_LAB_NAME $E1_LAB_MAX 行" \
  "P3-1 负控镜像：不清 NAO_SKILLS ⇒ 读到真仓（同一夹具相反结果 ⇒ 正控有判别力）"
t4_assert_ne "$E1_POISON_OUT" "$E1_LEAK_OUT" \
  "P3-1 正负控输出必不同（否则「清了但没用」也会绿）"

# 静态审计：本用例**每处** `nao-fleet.sh check` 调用都必须在同一代码块内清/给 `NAO_SKILLS`
#   （窗口 = 向上 40 行，覆盖 `env` 数组与调用分离的写法；粗判据 + 上面的行为正负控共同兜底）
c6_check_sites_without_skills() { # <脚本> → 未清 NAO_SKILLS 的 check 调用行号
  awk '
    { line[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (line[i] !~ /nao-fleet\.sh check/) continue
        ok = 0
        for (j = i - 40; j <= i; j++) if (j >= 1 && line[j] ~ /NAO_SKILLS/) ok = 1
        if (!ok) printf "%d\n", i
      }
    }' "$1"
}
t4_assert_eq "" "$(c6_check_sites_without_skills "$T4_ROOT/tests/t4/cases/06-contract-guards.sh")" \
  "P3-1 静态审计：本用例全部 check 调用点都已清/给 NAO_SKILLS（新增未清点必红）"
C6_AUD="$T4_CACHE_DIR/c6-audit-$$.sh"
printf '#!/usr/bin/env bash\nbash .agents/scripts/nao-fleet.sh check\n' > "$C6_AUD"
t4_assert_eq "2" "$(c6_check_sites_without_skills "$C6_AUD")" \
  "P3-1 审计负控：无菌样本的那处调用必被点名（行号 2；判据非空转）"
printf '#!/usr/bin/env bash\n# NAO_SKILLS 由调用方清\nbash .agents/scripts/nao-fleet.sh check\n' > "$C6_AUD"
t4_assert_eq "" "$(c6_check_sites_without_skills "$C6_AUD")" \
  "P3-1 审计正控：同块内出现 NAO_SKILLS ⇒ 放过（白名单生效，否则真用例全红）"
rm -f "$C6_AUD"
rm -rf "$E1_LAB" "$E1_MUT" "$E1_BIN"

# ---- D2（#130 D2 = T543-O2）：HERDR_* 清除清单**单源化**（枚举集合只增不减 + 调用点零手写）----
#   判据形态：单源 = `tests/t4/lib.sh::T4_HERDR_ENV_VARS`（变量名数组）；调用点只用派生数组
#   `T4_HERDR_UNSET_ARGS`（= `env -u <名>` 参数）。
#   为何要 golden 钉死：收敛的硬约束是「枚举集合**不得减少**」—— 单源化时顺手漏一个变量，
#   后果是「宿主 HERDR_* 渗进夹具」的**假绿**（不报错、只让断言失真），没有报错面可接。
#   golden = 收敛前（#130 开工时）四处手写清单的**并集**：
#     lib-backend `envs` (ENV/SESSION/SOCKET_PATH/SOCKET_FILE) ∪ cases/06 `B3_CLEAN_ENV`
#     单源集合 = 8 个（lib.sh T4_HERDR_ENV_VARS）；cases/28 v3 重写后经 be_run_fleet 单源，无直连。
#     复核命令见 docs/reports/130-gate-tune.md。
D2_LIB="$T4_ROOT/tests/t4/lib.sh"
D2_GOLD="HERDR_BIN_PATH HERDR_ENV HERDR_PANE_ID HERDR_SESSION HERDR_SOCKET_FILE HERDR_SOCKET_PATH HERDR_TAB_ID HERDR_WORKSPACE_ID"
d2_vars()     { sed -n '/^T4_HERDR_ENV_VARS=(/,/)/p' "$1" | grep -oE '\bHERDR_[A-Z_]+' | sort -u; }
d2_vars_str() { d2_vars "$1" | tr '\n' ' ' | sed 's/ $//'; }
d2_refs()     { grep -cE 'T4_HERDR_UNSET_ARG[S]|T4_HERDR_ENV_VAR[S]' "$1" || true; }
d2_args_n()   { ( T4_CACHE_DIR="$T4_CACHE_DIR" bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "${#T4_HERDR_UNSET_ARGS[@]}"' _ "$1" 2>/dev/null || true ); }
# 夹具清理参数（be_herdr_unset_args）的实际 argv 数 / 是否含某个变量名（#130 D2 豁免面）
d2_fixture_args() { ( T4_CACHE_DIR="$T4_CACHE_DIR" bash -c 'source "$1/tests/t4/lib.sh"; source "$1/tests/t4/lib-backend.sh"; be_herdr_unset_args' _ "$T4_ROOT" 2>/dev/null || true ); }
d2_handwritten() { grep -rnE -- '-u HERD[R]_' "$T4_ROOT/tests" 2>/dev/null | wc -l | tr -d ' '; }

t4_assert_eq "1" "$(grep -c '^T4_HERDR_ENV_VARS=(' "$D2_LIB" || true)" "D2① 单源定义处恰 1 处（tests/t4/lib.sh）"
t4_assert_eq "$D2_GOLD" "$(d2_vars_str "$D2_LIB")" "D2② 单源集合 == 收敛前各点清理变量的**并集**（8 个，只增不减）"
t4_assert_eq "0" "$(d2_handwritten)" "D2③ 调用点零手写（tests/ 下 「env -u <HERDR 变量>」 直写 = 0 行）"
t4_assert_ge 2 "$(d2_refs "$T4_ROOT/tests/t4/lib-backend.sh")" "D2④ lib-backend 夹具经单源清（引用 + 缺失时 fail loud 的守卫）"
t4_assert_eq "1" "$(grep -cE '^B3_CLEAN_ENV=\(env .*T4_HERDR_UNSET_ARG[S]' "$T4_ROOT/tests/t4/cases/06-contract-guards.sh" || true)" \
  "D2④ cases/06 「B3_CLEAN_ENV」 改为引用单源"
t4_assert_eq "0" "$(grep -cF 'T4_HERDR_UNSET_ARGS' "$T4_ROOT/tests/t4/cases/28-naming-contract.sh" || true)" \
  "D2④ cases/28 v3 重写后零手写清理面（经 be_run_fleet / be_herdr 单源）"
t4_assert_ge "5" "$(grep -c 'be_run_fleet' "$T4_ROOT/tests/t4/cases/28-naming-contract.sh" || true)" \
  "D2④ cases/28 经 be_run_fleet 单源跑生产脚本（覆盖仍承重）"
t4_assert_eq "16" "$(d2_args_n "$D2_LIB")" "D2⑤ 派生参数数 = 2×8（「env -u <名>」 成对；形态可运行）"
# 变异 A（枚举减少 ⇒ 必红）：从副本的单源里删掉 `HERDR_SOCKET_FILE`
D2_MUT="$T4_CACHE_DIR/d2-lib-mut-$$.sh"
sed 's/ HERDR_SOCKET_FILE//' "$D2_LIB" > "$D2_MUT"
t4_assert_eq "7" "$(d2_vars "$D2_MUT" | grep -c .)" "D2⑥ 变异锚点：副本单源只剩 7 个（「HERDR_SOCKET_FILE」 已删）"
t4_assert_ne "$D2_GOLD" "$(d2_vars_str "$D2_MUT")" "D2⑥ 变异自证：删一个变量 ⇒ D2② 必红（枚举收紧蒙混不过）"
# 变异 B（新增只改一处）：往副本单源加一个 HERDR_*，派生参数自动 +2，**调用点零改动**
D2_ADD="$T4_CACHE_DIR/d2-lib-add-$$.sh"
sed 's/HERDR_BIN_PATH)/HERDR_BIN_PATH HERDR_DEMO_NEW)/' "$D2_LIB" > "$D2_ADD"
t4_assert_eq "9" "$(d2_vars "$D2_ADD" | grep -c .)" "D2⑦ 变异锚点：副本单源已含新增的 9 个变量"
t4_assert_eq "18" "$(d2_args_n "$D2_ADD")" "D2⑦ 新增一个 HERDR_* 只改单源一行 ⇒ 派生参数自动 18（调用点零改动）"
t4_assert_eq "0" "$(d2_handwritten)" "D2⑦ 新增后 tests/ 仍零手写（引用形态不变 ⇒ 不靠改调用点）"
# D2⑧ 夹具侧豁免（#130 D2 实测回归）：单源全集清若一刀切，会把用例**故意**注入的 HERDR_*
#   一起磨掉（cases/09 AC3h③ 的 HERDR_PANE_ID 自 pane 判据）⇒ 必须有显式豁免通道：
#   默认全清（14 行 = 7 对）· 声明 BE_HERDR_KEEP=HERDR_PANE_ID ⇒ 12 行且不再含该变量名。
t4_assert_eq "16" "$(d2_fixture_args | grep -c .)" "D2⑧ 夹具清理参数默认 = 单源全集（8 对 = 16 行）"
D2_KEEP_OUT="$( BE_HERDR_KEEP="HERDR_PANE_ID" d2_fixture_args )"
t4_assert_eq "14" "$(printf '%s\n' "$D2_KEEP_OUT" | grep -c .)" "D2⑧ 显式豁免一个变量 ⇒ 清理参数只剩 7 对（14 行）"
t4_assert_eq "0" "$(printf '%s\n' "$D2_KEEP_OUT" | grep -c '^HERDR_PANE_ID$' || true)" \
  "D2⑧ 被豁免的 HERDR_PANE_ID 不再出现在清理参数里（故意注入能活到子进程）"
t4_assert_eq "2" "$(grep -c 'be_herdr_unset_args' "$T4_ROOT/tests/t4/lib-backend.sh" || true)" \
  "D2⑧ 豁免逻辑单点派生（定义 1 + be_run_fleet 调用 1；不复制到各用例）"
# D2⑧b（#130 返修 P3③）：分隔符口径 —— 空格与逗号都必须生效（注释与实现一致）
D2_COMMA_OUT="$( BE_HERDR_KEEP="HERDR_PANE_ID,HERDR_ENV" d2_fixture_args )"
t4_assert_eq "12" "$(printf '%s\n' "$D2_COMMA_OUT" | grep -c .)" "D2⑧b 逗号分隔也生效（8−2=6 对 = 12 行）"
t4_assert_eq "0" "$(printf '%s\n' "$D2_COMMA_OUT" | grep -cE '^HERDR_(PANE_ID|ENV)$' || true)" \
  "D2⑧b 逗号分隔时两个变量都真被豁免（不是只认首个）"
# D2⑨ 行为反渗漏（#130 返修 P3②；**纯清理**面）：只验 argv 文本不够 —— 必须在**真实子进程 env** 里看不见它。
#   否则「删掉 HERDR_ENV」只会在静态 golden 上红，行为面依旧 0 红。夹具：把 be_run_fleet 的被测脚本
#   换成「打印自身 env 里的 HERDR_*」的桩，父进程注入全部 8 个宿主值。
#   `BE_FLEET_NO_HANDLES=1` 的定位（#130 末轮定论）：本子例**不初始化 BE 上下文**（无 BE_BACKEND/…）
#   ⇒ `be_fleet_handles` 根本注不了句柄（注入面为空）⇒ NO_HANDLES 在此**不承重**，只是为了把判据
#   收窄到「清理」本身。「清理之后才注入句柄」的顺序面由 **D2⑩** 独立覆盖（那里给足 BE 上下文且不设
#   NO_HANDLES）—— 后人不得把本行误读为「顺序面已被 NI_HANDLES 验过」。
D2B_DIR="$T4_CACHE_DIR/d2b-$$"; mkdir -p "$D2B_DIR"
D2B_STUB="$D2B_DIR/dump-herdr-env.sh"
# 桩打印自身 env 里的 HERDR_* + NAO_TERMINAL（D2⑩② 要钉后端句柄；D2⑨ 只数 `^HERDR_` 行，不受影响）
{ printf '#!/usr/bin/env bash\n'; printf 'env | grep -E "^(HERDR_[A-Z_]+|NAO_TERMINAL)=" || true\n'; } > "$D2B_STUB"
chmod +x "$D2B_STUB"
t4_assert_contains "$(env HERDR_ENV=1 bash "$D2B_STUB" 2>/dev/null)" "HERDR_ENV=1" \
  "D2⑨ 探针自证：直接跑桩时能看见 HERDR_ENV（判据非空转）"
D2B_OUT="$( T4_CACHE_DIR="$T4_CACHE_DIR" BE_FLEET_NO_HANDLES=1 BE_FLEET_SCRIPT="$D2B_STUB" \
  HERDR_ENV=1 HERDR_SESSION=host-prod HERDR_SOCKET_PATH=/host/prod.sock HERDR_SOCKET_FILE=/host/f \
  HERDR_PANE_ID=host-pane HERDR_WORKSPACE_ID=host-ws HERDR_TAB_ID=host-tab HERDR_BIN_PATH=/host/bin \
  bash -c 'source "$1/tests/t4/lib.sh"; source "$1/tests/t4/lib-backend.sh"; be_run_fleet "$2" run; printf "BE_RC=%s\n" "$BE_RC"; printf "%s\n" "$BE_OUT"' \
  _ "$T4_ROOT" "$D2B_DIR" 2>&1 )"
t4_assert_contains "$D2B_OUT" "BE_RC=0" "D2⑨ 夹具自证：被测桩确实执行（rc=0，非空转）"
t4_assert_eq "0" "$(printf '%s\n' "$D2B_OUT" | grep -cE '^HERDR_[A-Z_]+=' || true)" \
  "D2⑨ 行为反渗漏：父进程注入 8 个 HERDR_* ⇒ 被测子进程 env 里 0 条（验进程真实 env，不是 argv 文本）"

# D2⑩ 「清理 → 注入」**顺序**面（#130 末轮 B 方案）：给足 BE 上下文（让 be_fleet_handles 真能注入）、
#   不设 NO_HANDLES，父进程再注入全部 8 个**可识别**宿主值。三条判据：
#     ① 8 个宿主值**逐条**不在子进程 env（不数条数、不用可撞值 1/空；ENV/SESSION/SOCKET_PATH 三个
#        即使清理被删也会被实验句柄覆盖 ⇒ 真正可观测的是另 5 个，但 8 条仍逐条钉，防以后改句柄集合）。
#     ② 实验句柄**在场且值 = 本实验场**（HERDR_ENV / HERDR_SESSION / HERDR_SOCKET_PATH 落在实验根 /
#        NAO_TERMINAL=herdr）—— 不能只断言「有 HERDR_* 在场」（宿主泄漏也满足那种弱断言）。
#     ③ 无 `BE_BACKEND: 未绑定的变量`（上下文真的初始化了，否则 ① 会因为「根本无句柄」而空转通过）。
#   为什么这条不可少：真实用例只靠「跑通」间接兜顺序；谁删 `${hu[@]}` 或把注入挪到清理之前，
#   其间没有一条用例会点名（变异实测：删 `${hu[@]}` ⇒ ① 5 红 / ② 绿；注入前置 ⇒ ② 红）。
D2H_HOST="HOSTLEAK"; D2H_SESS="d2h-fixture-sess"; D2H_CFG="$T4_CACHE_DIR/d2h-cfg-$$"
mkdir -p "$D2H_CFG"
D2H_NAMES=(HERDR_ENV HERDR_SESSION HERDR_SOCKET_PATH HERDR_SOCKET_FILE HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_BIN_PATH)
D2H_VALS=( "$D2H_HOST-env" "$D2H_HOST-sess" "/$D2H_HOST/prod.sock" "/$D2H_HOST/f" \
           "$D2H_HOST-pane" "$D2H_HOST-ws" "$D2H_HOST-tab" "/$D2H_HOST/bin" )
D2H_OUT="$( T4_CACHE_DIR="$T4_CACHE_DIR" BE_BACKEND=herdr BE_SESSION="$D2H_SESS" BE_CFGROOT="$D2H_CFG" \
  BE_FLEET_SCRIPT="$D2B_STUB" NAO_TERMINAL=tmux \
  HERDR_ENV="${D2H_VALS[0]}" HERDR_SESSION="${D2H_VALS[1]}" HERDR_SOCKET_PATH="${D2H_VALS[2]}" \
  HERDR_SOCKET_FILE="${D2H_VALS[3]}" HERDR_PANE_ID="${D2H_VALS[4]}" HERDR_WORKSPACE_ID="${D2H_VALS[5]}" \
  HERDR_TAB_ID="${D2H_VALS[6]}" HERDR_BIN_PATH="${D2H_VALS[7]}" \
  bash -c 'source "$1/tests/t4/lib.sh"; source "$1/tests/t4/lib-backend.sh"; be_run_fleet "$2" run; printf "BE_RC=%s\n" "$BE_RC"; printf "%s\n" "$BE_OUT"' \
  _ "$T4_ROOT" "$D2B_DIR" 2>&1 )"
t4_assert_contains "$D2H_OUT" "BE_RC=0" "D2⑩ 夹具自证：被测桩确实执行（rc=0，非空转）"
t4_assert_not_contains "$D2H_OUT" "BE_BACKEND: 未绑定的变量" \
  "D2⑩③ 上下文真初始化：输出里无『BE_BACKEND: 未绑定的变量』（否则 ① 会因「根本无句柄」空转）"
for _i in "${!D2H_NAMES[@]}"; do
  t4_assert_not_contains "$D2H_OUT" "${D2H_NAMES[$_i]}=${D2H_VALS[$_i]}" \
    "D2⑩① 清理生效：宿主值 ${D2H_NAMES[$_i]}=${D2H_VALS[$_i]} 不在子进程 env（逐条钉值，不数条数）"
done
t4_assert_contains "$D2H_OUT" "HERDR_ENV=1" "D2⑩② 注入在清理之后：实验句柄 HERDR_ENV=1 在场"
t4_assert_contains "$D2H_OUT" "HERDR_SESSION=$D2H_SESS" "D2⑩② 注入在清理之后：HERDR_SESSION = 本实验场会话名"
t4_assert_contains "$D2H_OUT" "HERDR_SOCKET_PATH=$D2H_CFG/herdr/sessions/$D2H_SESS/herdr.sock" \
  "D2⑩② 注入在清理之后：HERDR_SOCKET_PATH = 实验根下该会话目录（$D2H_CFG）"
t4_assert_contains "$D2H_OUT" "NAO_TERMINAL=herdr" "D2⑩② 注入在清理之后：NAO_TERMINAL=herdr 在场（父给定为 tmux ⇒ 只能来自注入，两种后端下都承重）"
t4_assert_not_contains "$D2H_OUT" "NAO_TERMINAL=tmux" "D2⑩② 注入真覆盖了父值（NAO_TERMINAL 不再是父给定的 tmux）"
rm -f "$D2_MUT" "$D2_ADD"
rm -rf "$D2B_DIR" "$D2H_CFG"
rm -rf "$D2B_DIR"

# ============================================================================
# E2-2（#132 · backlog sweep）：两个 helper 单点的 `-u NAO_STASH_ROOT` 硬化**必须有断言守卫**
#   缺口（#126 遗留观察 `M20261114-helper-u-guard`）：硬化只存在于 helper 文本里 ⇒ 谁删掉它
#     都没有任何用例会红（宿主若导出注入根，夹具 check 会平白多一条 stash warn = 假红面复活）。
#   判据（P3-2 复核后改「**warn 数差**」，不再断言「无任何 `warn=`」）：helper 跑的是**摘要模式**
#     （`t4_run_shim` 固定 `check`，不带 `-v`），摘要里只有 `warn=N` 汇总数 ⇒ 判据 = 「注入根 vs
#     非仓根」两次调用的 `warn=N` **相等**（= 注入根被清掉，没多出那条 stash warn）。这样与
#     「卡预算 warn」「codegraph warn」等**无关原因**解耦（P3-2 要求；与 #126 P2-1 同族病根）。
#   四条腿（缺一即空转/假红）：
#     ① 直连旁证（`-v`）：注入根 + 阈值 0 ⇒ 恰 1 条 `^  ! git stash`（闸门活着、根注入本来生效）；
#     ② 经 helper：`warn=N(注入根)` == `warn=N(非仓根)` ⇒ 被 `-u` 清掉；
#     ③ 反空转：副本删掉 helper 的 `-u NAO_STASH_ROOT` ⇒ 注入根那次恰 **+1**（stash warn 回来）；
#     ④ 解耦自证：夹具垫一张超预算的卡（另有非 stash warn）⇒ ②的**差值为 0** 仍成立。
#   覆盖两个单点：`tests/t4/lib.sh::t4_run_shim` · `tests/t4/lib-backend.sh::be_run_fleet`。
#   纪律：stash 只造在 `$C6_GIT`（`$T4_CACHE_DIR` 下的临时仓，P2-1 段已 git init）；真实仓零触碰。
#   为什么落在 cases/06 而不是 34/35：本组验的是**测试基座**（helper）而非端前提/闸门语义，
#     与紧邻的 D2「helper 单点清理清单」同主题；且 06 已有 C6_GIT 临时仓夹具，无需新开仓/跨用例耦合。
E2_STASH_SENTINEL="e2-2-helper-stash"
printf 'c\n' >> "$C6_GIT/f.txt"
git -C "$C6_GIT" stash push -q -m "$E2_STASH_SENTINEL" -- f.txt 2>/dev/null \
  || t4_bad "E2-2 夹具：临时仓 stash push 失败"
t4_assert_eq "1" "$(git -C "$C6_GIT" stash list 2>/dev/null | grep -c . || true)" \
  "E2-2 夹具自证：临时仓有 1 条 stash（判据非空转；真仓未造 stash）"
# 阈值 0 = 立即 ⇒ 不依赖 stash 年龄（fresh stash 也必 warn），判据与时钟解耦
E2_ENV=(PI_CODING_AGENT_DIR="$T4_CACHE_DIR/b1-pi-empty" \
  PATH="$B1BIN:$PATH" REAL_TMUX_B1="$REAL_TMUX_B1" NAO_STASH_WARN_HOURS=0)
E2_NONE="$T4_CACHE_DIR/e2-2-none-$$"; mkdir -p "$E2_NONE"   # 闸门「不适用」根 = 基线（无 stash 注入）
e2_stash_n()  { printf '%s\n' "$1" | grep -c '^  ! git stash' || true; }   # 仅 `-v` 可见（直连旁证用）
e2_warn_n()   { local w; w="$(printf '%s\n' "$1" | grep -oE 'warn=[0-9]+' | head -1 | grep -oE '[0-9]+' || true)"; printf '%s' "${w:-0}"; }

# ---- ① 直连旁证（-v）：注入根有效 ⇒ 恰 1 条 stash warn ----
E2_DIRECT="$( cd "$T4_ROOT" && env -u NAO_SKILLS NAO_STASH_ROOT="$C6_GIT" "${E2_ENV[@]}" \
  bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_eq "1" "$(e2_stash_n "$E2_DIRECT")" \
  "E2-2② 旁证（直连脚本 -v）：注入根 + 阈值 0 ⇒ 恰 1 条 stash warn（闸门活着、根注入本来生效）"
t4_assert_contains "$E2_DIRECT" "$E2_STASH_SENTINEL" \
  "E2-2② 旁证点名滞留内容（判据锚在闸门文案上，不是泛化的 warn 汇总数）"

# ---- ②/③ 经 t4_run_shim：注入根 vs 非仓根的 warn 数相等；删 `-u` 后恰 +1 ----
e2_shim_via() { # <lib.sh 路径> <包根> <stash 根> → "RC=…" + 输出（NAO_SKILLS 显式钉该根）
  env NAO_STASH_ROOT="$3" NAO_SKILLS="$2" "${E2_ENV[@]}" T4_CACHE_DIR="$T4_CACHE_DIR" bash -c '
    source "$1" >/dev/null 2>&1; shift
    t4_run_shim "$@"
    printf "RC=%s\n" "$T4_RC"; printf "%s\n" "$T4_OUT"' _ "$1" "$2"
}
E2_SHIM_BASE="$(e2_shim_via "$T4_ROOT/tests/t4/lib.sh" "$T4_ROOT" "$E2_NONE")"
E2_SHIM_INJ="$(e2_shim_via "$T4_ROOT/tests/t4/lib.sh" "$T4_ROOT" "$C6_GIT")"
t4_assert_contains "$E2_SHIM_BASE" "check: OK" "E2-2① t4_run_shim 基线（非仓根）：正锚在场（空输出不会空转通过）"
t4_assert_eq "$(e2_warn_n "$E2_SHIM_BASE")" "$(e2_warn_n "$E2_SHIM_INJ")" \
  "E2-2① t4_run_shim：注入根与外层基线 **warn 数相同**（宿主注入根已被清掉；无关 warn 不参与）"

# ---- ②/③ 经 be_run_fleet：同上 ----
e2_be_via() { # <lib-backend.sh 路径> <包根> <stash 根> → "BE_RC=…" + 输出
  env NAO_STASH_ROOT="$3" NAO_SKILLS="$2" "${E2_ENV[@]}" T4_CACHE_DIR="$T4_CACHE_DIR" \
    BE_FLEET_NO_HANDLES=1 BE_FLEET_SCRIPT="$2/.agents/scripts/nao-fleet.sh" bash -c '
    source "$1/tests/t4/lib.sh" >/dev/null 2>&1
    source "$3" >/dev/null 2>&1
    be_run_fleet "$2" check
    printf "BE_RC=%s\n" "$BE_RC"; printf "%s\n" "$BE_OUT"' _ "$T4_ROOT" "$2" "$1"
}
E2_BE_BASE="$(e2_be_via "$T4_ROOT/tests/t4/lib-backend.sh" "$T4_ROOT" "$E2_NONE")"
E2_BE_INJ="$(e2_be_via "$T4_ROOT/tests/t4/lib-backend.sh" "$T4_ROOT" "$C6_GIT")"
t4_assert_contains "$E2_BE_BASE" "check: OK" "E2-2① be_run_fleet 基线（非仓根）：正锚在场（非空转）"
t4_assert_eq "$(e2_warn_n "$E2_BE_BASE")" "$(e2_warn_n "$E2_BE_INJ")" \
  "E2-2① be_run_fleet：注入根与外层基线 **warn 数相同**（宿主注入根已被清掉）"

# ---- ④ 解耦自证（P3-2）：夹具另有非 stash warn 时，②的差值仍为 0 ----
#   夹具：`.agents` 副本 + 把当前最大卡垫到 CARD_MAX+1 行（⇒ 卡预算逐卡 `!` + 基线 >100%）；
#   直连 `-v` 先证明「该夹具确实有一条与 stash 无关的 `!`」，再走两个 helper。
E2_LAB2="$T4_CACHE_DIR/e2-2-lab-$$"
mkdir -p "$E2_LAB2"
cp -r "$T4_ROOT/.agents" "$E2_LAB2/.agents" || t4_bad "E2-2 解耦夹具：复制 .agents 失败"
E2_L2_MAX=0; E2_L2_NAME=""
for _f in "$E2_LAB2"/.agents/prompts/*.md; do
  _n="$(wc -l < "$_f" | tr -d ' ')"
  if [ "$_n" -gt "$E2_L2_MAX" ]; then E2_L2_MAX="$_n"; E2_L2_NAME="$(basename "$_f")"; fi
done
E2_L2_NEED=$(( E1_CARD_MAX + 1 - E2_L2_MAX ))
if [ "$E2_L2_NEED" -gt 0 ]; then
  for ((_i = 0; _i < E2_L2_NEED; _i++)); do printf -- '- E2-2 padding\n' >> "$E2_LAB2/.agents/prompts/$E2_L2_NAME"; done
fi
E2_LAB2_DIRECT="$( cd "$E2_LAB2" && env -u NAO_SKILLS -u NAO_STASH_ROOT "${E2_ENV[@]}" \
  bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_contains "$E2_LAB2_DIRECT" "! $E2_L2_NAME" \
  "E2-2 解耦夹具自证：该夹具确有**非 stash** 的 warn（$E2_L2_NAME 超卡预算）"
E2_LAB2_BASE="$(e2_shim_via "$T4_ROOT/tests/t4/lib.sh" "$E2_LAB2" "$E2_NONE")"
E2_LAB2_INJ="$(e2_shim_via "$T4_ROOT/tests/t4/lib.sh" "$E2_LAB2" "$C6_GIT")"
t4_assert_ge 1 "$(e2_warn_n "$E2_LAB2_BASE")" \
  "E2-2 解耦夹具经 helper：基线确有非 stash warn（N=$(e2_warn_n "$E2_LAB2_BASE")）"
t4_assert_eq "$(e2_warn_n "$E2_LAB2_BASE")" "$(e2_warn_n "$E2_LAB2_INJ")" \
  "E2-2③ 解耦（P3-2）：无关 warn 在场时注入根仍不改变 warn 数（本组不会被卡预算 warn 带红）"

# ---- ⑤ 反空转：副本删掉 helper 的 `-u NAO_STASH_ROOT` ⇒ 注入根那次恰 +1 ----
E2_MUT="$T4_CACHE_DIR/e2-2-mut-$$"; mkdir -p "$E2_MUT"
sed 's/env -u NAO_STASH_ROOT "\$@"/env "\$@"/' "$T4_ROOT/tests/t4/lib.sh" > "$E2_MUT/lib.sh"
# Q7（M20261118-test-hygiene）：lib-backend 侧已收成**环境净化门面**（`be_clean_env` ⇒ `be_clean_unset_args`），
#   `NAO_STASH_ROOT` 不再以字面 `-u NAO_STASH_ROOT` 出现，由门面的**动态兜底**（宿主导出的 `NAO_*` 一律清）覆盖。
#   判据形态随之改为「门面里承重的那一处 = 动态兜底」，变异 = 中和它；**强度不减**（仍验行为 + 单点）。
sed 's/< <(be_env_ambient_names)/< <(:)/' "$T4_ROOT/tests/t4/lib-backend.sh" > "$E2_MUT/lib-backend.sh"
t4_assert_eq "0" "$(grep -c 'env -u NAO_STASH_ROOT' "$E2_MUT/lib.sh" || true)" \
  "E2-2④ 变异锚点：副本 lib.sh 的 \`-u NAO_STASH_ROOT\` 已删"
t4_assert_eq "1" "$(grep -c '< <(be_env_ambient_names)' "$T4_ROOT/tests/t4/lib-backend.sh" || true)" \
  "E2-2④ 单点锚点：门面的动态兜底调用恰 1 处"
t4_assert_eq "0" "$(grep -c '< <(be_env_ambient_names)' "$E2_MUT/lib-backend.sh" || true)" \
  "E2-2④ 变异锚点：副本已中和动态兜底（NAO_STASH_ROOT 不再被清）"
t4_assert_eq "0" "$(bash -n "$E2_MUT/lib.sh" 2>&1; echo $?)" "E2-2④ 变异副本 lib.sh 语法仍合法（红点只能来自判据）"
t4_assert_eq "0" "$(bash -n "$E2_MUT/lib-backend.sh" 2>&1; echo $?)" "E2-2④ 变异副本 lib-backend.sh 语法仍合法"
E2_SHIM_BAD="$(e2_shim_via "$E2_MUT/lib.sh" "$T4_ROOT" "$C6_GIT")"
t4_assert_eq "$(( $(e2_warn_n "$E2_SHIM_BASE") + 1 ))" "$(e2_warn_n "$E2_SHIM_BAD")" \
  "E2-2④ 反空转（t4_run_shim）：删掉 \`-u\` ⇒ 注入根复活 ⇒ warn 恰 +1（基线 $(e2_warn_n "$E2_SHIM_BASE") ⇒ $(e2_warn_n "$E2_SHIM_BAD")）"
E2_BE_BAD="$(e2_be_via "$E2_MUT/lib-backend.sh" "$T4_ROOT" "$C6_GIT")"
t4_assert_eq "$(( $(e2_warn_n "$E2_BE_BASE") + 1 ))" "$(e2_warn_n "$E2_BE_BAD")" \
  "E2-2④ 反空转（be_run_fleet）：删掉 \`-u\` ⇒ 注入根复活 ⇒ warn 恰 +1（基线 $(e2_warn_n "$E2_BE_BASE") ⇒ $(e2_warn_n "$E2_BE_BAD")）"

# ---- ⑥ 静态单点：两个 helper 各恰 1 处（行为判据之外的定位面）----
t4_assert_eq "1" "$(grep -c 'env -u NAO_STASH_ROOT' "$T4_ROOT/tests/t4/lib.sh" || true)" \
  "E2-2⑤ 单点①：t4_run_shim 带 \`env -u NAO_STASH_ROOT\` 恰 1 处"
t4_assert_eq "1" "$(grep -c '^be_clean_env() {' "$T4_ROOT/tests/t4/lib-backend.sh" || true)" \
  "E2-2⑤ 单点②：净化入口定义恰 1 处（「be_clean_env」，Q7）"
t4_assert_eq "1" "$(grep -cF 'clean=($(be_clean_env))' "$T4_ROOT/tests/t4/lib-backend.sh" || true)" \
  "E2-2⑤ 单点②：净化入口的调用点恰 1 处（be_run_fleet；调用点不再手写 「-u」）"
E2_BE_ARGS="$( T4_CACHE_DIR="$T4_CACHE_DIR" NAO_STASH_ROOT=/x NAO_SKILLS=/x \
  bash -c 'source "$1/tests/t4/lib.sh" >/dev/null 2>&1; source "$1/tests/t4/lib-backend.sh" >/dev/null 2>&1; be_clean_unset_args' \
  _ "$T4_ROOT" 2>/dev/null || true )"
t4_assert_eq "1" "$(printf '%s\n' "$E2_BE_ARGS" | grep -cx 'NAO_STASH_ROOT' || true)" \
  "E2-2⑤ 行为面：宿主导出 NAO_STASH_ROOT ⇒ 门面净化参数含它（清空面非空转）"
rm -rf "$E2_LAB2" "$E2_NONE"

# ============================================================================
# E2-3（#132 · QA P3-1）：夹具不得读**宿主**的 `NAO_SKILLS`
#   现象（QA 实测）：`NAO_SKILLS=$PWD bash tests/t4/run.sh --case 06` ⇒ **319 PASS / 3 FAIL**
#     （`28b5d44` 同现象）。根因 = `nao-fleet.sh:125 SKILLS_DIR="${NAO_SKILLS:-<脚本>/../..}"`：
#     宿主导出的包根会盖掉「夹具根」⇒ 夹具 check 去读**真仓**的 `.agents`（人数/卡预算/warn 全错）。
#     与本批 E2-2 刚修的 `NAO_STASH_ROOT` 同族（宿主 env 渗进夹具）。
#   本组三层：
#     ① 用例内**每处** `nao-fleet.sh check` 调用都在同一代码块内清/给 `NAO_SKILLS`（静态审计 + 负控）；
#     ② 行为正控：宿主 `NAO_SKILLS=<真仓>` 时，垫过卡的夹具 check 仍报**夹具**的最大卡行数；
#     ③ 行为负控（镜像）：同一制品去掉 `-u NAO_SKILLS` ⇒ 读到真仓 ⇒ 报不出夹具行数（证明②承重）。
#   `E1_ENV` / `E1_ENV_LEAK` 与审计断言都在 E1 段（那里有现成的垫卡夹具 `$E1_LAB`）。

rm -rf "$B1BIN" "$B1_LOG" "$NEG_B1A" "$NEG_B1B" "$NEG_B1C" "$NEG_B1D" "$NEG_LED"

t4_exit
