#!/usr/bin/env bash
# 用例 34 —— 端前提声明一致性单点 warn（#124 · AC5/AC6）
#
# 判据来源：Issue #124（§范围 5 · §AC5 · §AC6）· 上游 `docs/reports/118-mechanism-review.md`
#   §四 T1（`.agents/**/*.md` 0 次 herdr，实现默认 herdr ⇒ 口径整层脱节）与 §八 D4
#   （裁定：**不加新闸门**，改为现有 `check` 内**单点 warn** —— 比对「协议 / `AGENTS.md` 声明的默认后端」
#   与「`nao-fleet.sh` 唯一赋值点的默认后端」；不一致 ⇒ warn，**不改 rc**）。
#
# 断言分组：
#   A 一致（基座原样）⇒ 摘要无 `warn=` 字段、`-v` 零端前提 warn；显式 `=tmux` 下默认摘要仍 2 行（golden 不破）
#   B 负控①（AC6）：协议改回旧口径「唯一路径 … tmux」⇒ 恰 1 条 warn，点名协议 + 实现来源，rc 仍 0，
#     且摘要 `warn=1`（计入 warn=N）；还原 ⇒ warn 消失（双向）
#   C 负控②（AC2）：`AGENTS.md` 声明改成「默认 tmux」⇒ 恰 1 条 warn，点名 `AGENTS.md`（且不误点名协议），
#     rc 仍 0；还原 ⇒ warn 消失（双向）
#   D 静态面：单点实现 + 单点调用且 warn-only（`|| true`）· 默认后端仍只有唯一赋值点（warn 不重述字面量）
#     · 仓库口径已对齐（`.agents` 有 herdr、无「唯一路径 … tmux」旧口径）
#
# 夹具：`$FX` = `.agents` 副本 + `AGENTS.md` 副本 —— 被测比对目标就是 `$SKILLS_DIR` 下的这两个文件，
#   故负控只动夹具、**不碰仓库工作区**。后端可用性用桩（herdr / tmux / pi）⇒ 两后端跑同一组断言。
#
# 读数口径：warn 行只在 `-v`（或失败展开）时可见，摘要模式只露 `warn=N` ⇒ 两种读数各断言一次
#   （「看得见」与「被计数」是两条判据，缺一即是静默或不计分）。
#
# 能力门：无（纯 bash + 夹具副本；不建 server / 不 spawn pane / 零网络）。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
t4_assert_file "$FLEET" "被测脚本存在（nao-fleet.sh）"

# ---------------------------------------------------------------- 夹具
# 每次重建（避免二次跑沿用到上一轮变异过的副本）
rm -rf "$T4_CACHE_DIR/c34"
FX="$T4_CACHE_DIR/c34/repo"
BIN="$T4_CACHE_DIR/c34/bin"
AGENT_EMPTY="$T4_CACHE_DIR/c34/pi-empty"
BAK="$T4_CACHE_DIR/c34/bak"
mkdir -p "$FX" "$BIN" "$AGENT_EMPTY" "$BAK"
cp -r "$T4_ROOT/.agents" "$FX/.agents" || t4_blocked "夹具复制 .agents 失败"
cp "$T4_ROOT/AGENTS.md" "$FX/AGENTS.md" || t4_blocked "夹具复制 AGENTS.md 失败"
PROTO="$FX/.agents/common/intercom-protocol.md"
AGENTS="$FX/AGENTS.md"
cp "$PROTO" "$BAK/intercom-protocol.md"
cp "$AGENTS" "$BAK/AGENTS.md"

# 桩：只满足「运行前提」段与 pi 版本断言的机械面（不建任何 session / pane / server）
printf '#!/usr/bin/env bash\nprintf "herdr 0.9.1\\n"\n' > "$BIN/herdr"
printf '#!/usr/bin/env bash\nprintf "pi 1.5.2\\n"\n' > "$BIN/pi"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/tmux"
chmod +x "$BIN/herdr" "$BIN/pi" "$BIN/tmux"

# 环境：清掉宿主继承的 HERDR_*（枚举清，不只 -u 已知变量 —— 与 lib-backend 同纪律），
#   否则在 herdr pane 内跑本用例会把真实 HERDR_SESSION 带进夹具 ⇒ check 去问真 server（假红/串台）。
C34_CLEAN=(env)
for _v in $(env | grep -o '^HERDR_[A-Z_]*' || true); do C34_CLEAN+=(-u "$_v"); done
C34_ENV=("${C34_CLEAN[@]}" NAO_SKILLS="$FX" PI_CODING_AGENT_DIR="$AGENT_EMPTY" PATH="$BIN:$PATH")

C34_RC=0; C34_OUT=""; C34_SUM=""
run_check() { # 参数透传（如 -v）；$FX = 夹具包根
  local of ef; of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$FX" && "${C34_ENV[@]}" bash .agents/scripts/nao-fleet.sh check "$@" ) >"$of" 2>"$ef"
  C34_RC=$?
  C34_OUT="$(cat "$of"; cat "$ef")"
  rm -f "$of" "$ef"
}
premise_warns() { printf '%s\n' "$C34_OUT" | grep -c '^  ! 端前提' || true; }
restore() { cp "$BAK/intercom-protocol.md" "$PROTO"; cp "$BAK/AGENTS.md" "$AGENTS"; }

# ============================================================ A 一致（基座原样）
run_check
C34_SUM="$C34_OUT"
t4_assert_eq "0" "$C34_RC" "A1 一致：check rc=0"
t4_assert_not_contains "$C34_SUM" "warn=" "A2 一致：摘要无 warn= 字段（端前提 warn 不是常驻噪音）"
t4_assert_contains "$C34_SUM" "check: OK" "A3 一致：摘要行照常输出"
if [ "${NAO_TERMINAL:-}" = "tmux" ]; then
  t4_assert_eq "2" "$(printf '%s\n' "$C34_SUM" | grep -c . || true)" \
    "A4 一致 + 显式 =tmux：默认摘要仍 2 行（一致时零输出 ⇒ 旧 golden 不破）"
else
  t4_note backend-gate "A4 行数断言仅 tmux 后端（herdr 摘要另含「生效后端」行，口径见 cases/06）"
fi
run_check -v
t4_assert_eq "0" "$(premise_warns)" "A5 一致 + -v：报告里也零端前提 warn（不是只在摘要里隐身）"
t4_assert_eq "0" "$C34_RC" "A6 一致 + -v：rc=0"

# ============================================================ B 负控①（AC6）：协议改回 tmux 唯一
# 复刻 v0.23.0 前的旧口径：把声明里的「默认（后端）herdr」改写成「唯一路径」、回退指路改成 tmux-only 措辞。
#   （两条 sed 都覆盖：`默认后端 herdr` = 协议措辞，`默认 herdr` = AGENTS.md/技能措辞）
sed -i -e 's/默认后端 herdr/唯一路径/g' -e 's/默认 herdr/唯一路径/g' -e 's/回退 tmux/仅 tmux 会话内/g' "$PROTO"
t4_assert_eq "1" "$(grep -c '唯一路径.*tmux' "$PROTO" || true)" \
  "B0 变异自证：夹具协议已含旧口径「唯一路径 … tmux」（判据非空转）"
t4_assert_eq "0" "$(grep -c '默认\(后端 \)\?herdr' "$PROTO" || true)" \
  "B0b 变异自证：夹具协议已无「默认 … herdr」声明"
run_check -v
t4_assert_eq "0" "$C34_RC" "B1 协议回退 tmux：warn 不改 rc（仍 0）"
t4_assert_eq "1" "$(premise_warns)" "B2 协议回退 tmux：恰 1 条端前提 warn（单点，不重复）"
t4_assert_contains "$C34_OUT" "端前提声明不一致：.agents/common/intercom-protocol.md:" \
  "B3 warn 点名声明来源（路径 + 行号形态）"
t4_assert_match "$C34_OUT" 'intercom-protocol\.md:[0-9]+ 声明默认后端 = tmux' \
  "B3b warn 给出「文件:行号 + 解析值」（不是只给文件名）"
t4_assert_contains "$C34_OUT" "nao-fleet.sh" "B4 warn 点名实现来源（nao-fleet.sh 默认后端）"
t4_assert_eq "0" "$(printf '%s\n' "$C34_OUT" | grep -c 'AGENTS\.md:' || true)" \
  "B5 只点名真正不一致的那一处（不误伤 AGENTS.md）"
run_check
t4_assert_eq "0" "$C34_RC" "B6 摘要模式：rc 仍 0（warn 不改 rc）"
t4_assert_match "$C34_OUT" 'warn=1' "B7 摘要模式：该 warn 计入 warn=N（被计数，不静默）"

restore
run_check -v
t4_assert_eq "0" "$(premise_warns)" "B8 还原一致：warn 消失（双向）"
t4_assert_eq "0" "$C34_RC" "B9 还原一致：rc=0"

# ============================================================ C 负控②（AC2 + P2-1）：AGENTS.md 单行 / 双行回退
# P2-1 背景（QA 复核）：旧实现只取「第一条能解析出后端的前提行」⇒ 只回退 `:18`（#124 的原始症状行）
#   而 `:33` 仍是 herdr 时判「一致」⇒ 守护静默失效。本组三种形态都断言：
#   ① 仅 `:18` 回退旧文（不可比对 ⇒ nodecl）② 仅 `:33` 声明改成 tmux ③ 两行都改（条数 = 声明行数，不刷屏）
L18="$(grep -n '仅 pi 宿主' "$AGENTS" | head -1 | cut -d: -f1)"
L33="$(grep -n '布局/宿主/句柄语义' "$AGENTS" | head -1 | cut -d: -f1)"
t4_assert_ne "" "$L18" "C0a 夹具定位：AGENTS.md「仅 pi 宿主」行 = :$L18"
t4_assert_ne "" "$L33" "C0b 夹具定位：AGENTS.md「布局/宿主/句柄语义」行 = :$L33"

# C1 仅 :18 回退成 v0.23.0 前的原文（#124 的原始症状行；解析不出后端 ⇒ nodecl）
sed -i "${L18}s/.*/- **仅 pi 宿主（唯一，无第二宿主）**：机制只支持 **pi ≥1.4.0 + tmux**。/" "$AGENTS"
t4_assert_eq "0" "$(sed -n "${L18}p" "$AGENTS" | grep -c '默认' || true)" \
  "C1a 变异自证：:${L18} 已无「默认 …」声明（回退到旧文形态）"
run_check -v
t4_assert_eq "0" "$C34_RC" "C1b 仅 :${L18} 回退：warn 不改 rc（仍 0）"
t4_assert_eq "1" "$(premise_warns)" "C1c 仅 :${L18} 回退：恰 1 条端前提 warn（**P2-1 盲区：旧实现此处为 0**）"
t4_assert_contains "$C34_OUT" "AGENTS.md:${L18}" "C1d warn 点名 :${L18}（行号级定位）"
t4_assert_contains "$C34_OUT" "端前提行未给出可比对的后端声明" \
  "C1d2 nodecl 分支文案 = 「端前提行未给出可比对的后端声明」（P3-8：不再把下游项目的『运行前提』称作端前提声明）"
t4_assert_eq "0" "$(printf '%s\n' "$C34_OUT" | grep -c "AGENTS\.md:${L33}" || true)" \
  "C1e 不误点名未改动的 :${L33}"
restore

# C2 仅 :33 声明改成 tmux（:18 仍 herdr）
sed -i "${L33}s/默认 herdr/默认 tmux/" "$AGENTS"
t4_assert_eq "1" "$(sed -n "${L33}p" "$AGENTS" | grep -c '默认 tmux' || true)" \
  "C2a 变异自证：仅 :${L33} 改成 tmux"
run_check -v
t4_assert_eq "0" "$C34_RC" "C2b 仅 :${L33} 改 tmux：warn 不改 rc（仍 0）"
t4_assert_eq "1" "$(premise_warns)" "C2c 仅 :${L33} 改 tmux：恰 1 条端前提 warn"
t4_assert_contains "$C34_OUT" "AGENTS.md:${L33}" "C2d warn 点名 :${L33}（check 认这处，不只认协议文件）"
t4_assert_contains "$C34_OUT" "nao-fleet.sh" "C2e warn 点名实现来源"
t4_assert_eq "0" "$(printf '%s\n' "$C34_OUT" | grep -c 'intercom-protocol\.md:' || true)" \
  "C2f 不误伤协议文件（协议本就一致）"
restore

# C3 两行都改 ⇒ 条数 = 声明行数（各 1 条，不重复刷屏、不合并吞行号）
sed -i "${L18}s/.*/- **仅 pi 宿主（唯一，无第二宿主）**：机制只支持 **pi ≥1.4.0 + tmux**。/" "$AGENTS"
sed -i "${L33}s/默认 herdr/默认 tmux/" "$AGENTS"
run_check -v
t4_assert_eq "0" "$C34_RC" "C3a 两行都改：warn 不改 rc（仍 0）"
t4_assert_eq "2" "$(premise_warns)" "C3b 两行都改：恰 2 条（= 声明行数；不重复刷屏）"
t4_assert_eq "1" "$(printf '%s\n' "$C34_OUT" | grep -c "AGENTS\.md:${L18}" || true)" \
  "C3c :${L18} 恰 1 条（无重复）"
t4_assert_eq "1" "$(printf '%s\n' "$C34_OUT" | grep -c "AGENTS\.md:${L33}" || true)" \
  "C3d :${L33} 恰 1 条（无重复）"
t4_assert_eq "0" "$(printf '%s\n' "$C34_OUT" | grep -c 'AGENTS\.md（AGENTS\.md）' || true)" \
  "C3e warn 文案无 label 重复（P3-3：不再出现「AGENTS.md（AGENTS.md）」）"

restore
run_check -v
t4_assert_eq "0" "$(premise_warns)" "C4 还原一致：warn 消失（双向）"
t4_assert_eq "0" "$C34_RC" "C5 还原一致：rc=0"

# ============================================================ E 不适用面（P1-1）：absent ⇒ 零输出、零 warn
# P1-1（QA 二轮）：`absent` 曾是**单 token**输出，调用方读成 `n=absent, decl=""` ⇒ 落进「不一致」分支 ⇒
#   npm 安装态（包内不带 `AGENTS.md`）每次 `check` 常驻一条乱码式假 warn。本组把「不适用」钉成判据：
#   **判定** = 文件不存在 / 存在但无任何端前提声明行 ⇒ **零输出**（不产生 warn、不进 warn=N）。
# E1 夹具无 `AGENTS.md`（= npm 包根形态）：零 warn + rc=0
mv "$AGENTS" "$BAK/AGENTS.e1"
run_check -v
t4_assert_eq "0" "$(premise_warns)" "E1 无 AGENTS.md（npm 包根形态）：零端前提 warn"
t4_assert_eq "0" "$C34_RC" "E1b 无 AGENTS.md：rc=0（不因缺文件置红）"
mv "$BAK/AGENTS.e1" "$AGENTS"

# E2 `AGENTS.md` 存在但无任何声明行（下游项目常见）：零 warn + rc=0
#   注意：夹具正文**不得**出现标记词（`运行前提|机制只支持|端前提`）—— 出现标记却无声明 = `nodecl` ⇒ 必 warn（by design）
printf '# 夹具 AGENTS.md\n\n- 项目属性：仅测试夹具，不谈终端后端。\n' > "$AGENTS"
run_check -v
t4_assert_eq "0" "$(premise_warns)" "E2 AGENTS.md 无端前提声明行：零端前提 warn（不适用）"
t4_assert_eq "0" "$C34_RC" "E2b AGENTS.md 无端前提行：rc=0"
cp "$BAK/AGENTS.md" "$AGENTS"

# E3 仅协议文件在场（AGENTS.md 缺失）+ 协议缺失对照：前者零 warn；后者 warn 也为 0（rc 由既有「公共规范缺失」判红）
mv "$AGENTS" "$BAK/AGENTS.e3"
mv "$PROTO" "$BAK/proto.e3"
run_check -v
t4_assert_eq "0" "$(premise_warns)" "E3 协议文件也缺失：端前提 warn 仍 0（不适用不刷屏）"
mv "$BAK/proto.e3" "$PROTO"
run_check -v
t4_assert_eq "0" "$(premise_warns)" "E3b 仅协议在场：端前提 warn 0"
t4_assert_eq "0" "$C34_RC" "E3c 仅协议在场：rc=0"
mv "$BAK/AGENTS.e3" "$AGENTS"

# E4 回归位（真实安装信道的最小化形态）：无 AGENTS.md 时摘要**不得**出现 warn= 字段
# P3-7（QA 三轮 · 防空转）：`not_contains` 单用会被「check 早退且输出为空」空转通过 ⇒ 每条各配**正锚**
#   （E4 = 摘要行正锚 + rc；E4b = `-v` 的「运行前提」段正锚 + rc）。变异自证见报告 §P3-7。
mv "$AGENTS" "$BAK/AGENTS.e4"
run_check
t4_assert_eq "0" "$C34_RC" "E4a 无 AGENTS.md：rc=0（正锚 ⇒ 早退且非 0 不会混过）"
t4_assert_contains "$C34_OUT" "check: OK" "E4b 无 AGENTS.md：摘要行在场（正锚 ⇒ 空输出不会空转通过）"
t4_assert_not_contains "$C34_OUT" "warn=" "E4c 无 AGENTS.md：默认摘要无 warn= 字段（不常驻）"
run_check -v
t4_assert_eq "0" "$C34_RC" "E4d 无 AGENTS.md + -v：rc=0（正锚）"
t4_assert_contains "$C34_OUT" "== 运行前提" "E4e 无 AGENTS.md + -v：报告正文在场（正锚 ⇒ 空输出不会空转通过）"
t4_assert_not_contains "$C34_OUT" "AGENTS.md:absent" "E4f 无 AGENTS.md：不再出现 \`AGENTS.md:absent\` 乱码式文案"
mv "$BAK/AGENTS.e4" "$AGENTS"

# ============================================================ D 静态面（单点 + warn-only + 默认值单源）
t4_assert_ge "2" "$(grep -c 'check_backend_premise' "$FLEET" || true)" \
  "D1 单点实现 + 单点调用（定义 1 + 调用 1）"
t4_assert_eq "1" "$(grep -c 'check_backend_premise || true' "$FLEET" || true)" \
  "D2 调用点 warn-only（\`|| true\` ⇒ 不改 check rc）"
t4_assert_eq "1" "$(grep -cE '^NAO_TERMINAL=' "$FLEET" || true)" \
  "D3 默认后端仍只有唯一赋值点（warn 比对从该点解析，不重述字面量）"
t4_assert_eq "0" "$(grep -c '唯一路径.*tmux' "$T4_ROOT/.agents/common/intercom-protocol.md" || true)" \
  "D4 仓库协议文件已无「唯一路径 … tmux」旧口径（AC1 负向）"
t4_assert_ge "3" "$(grep -rhn 'herdr' "$T4_ROOT/.agents" --include=*.md | wc -l | tr -d ' ')" \
  "D5 .agents/**/*.md 提到 herdr ≥3 行（AC1 正向）"

t4_exit
