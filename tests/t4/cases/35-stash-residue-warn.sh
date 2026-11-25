#!/usr/bin/env bash
# 用例 35 —— check 的「stash 出口」机械闸（#126 B2-2 立项 · #130 D1 加**年龄阈值**）
#
# 判据来源：Issue #126（B2-2）· Issue #130（D1）· 上游 `docs/reports/118-mechanism-review.md` §四（BR5 批间收尾）
#   动机①（2026-11-14 实测）：3 个滞留 stash —— `v0.22.6` 压 7 天、`M20261113` 压 7.5 小时且其 sha
#     `0863ab2` 在台账 grep = 0 ⇒ **终态从未入库** ⇒ `check` 须有一条只读告警。
#   动机②（#130 D1）：BR5 的**合法**用法是「合并后事实 ⇒ 带标签 stash、随下批首提交回填」——
#     当天回填属正常节奏，「任何 stash 都 warn」让闸门自己变常驻噪声（本仓连撞两批）。故只对
#     **最老一条**年龄 > `NAO_STASH_WARN_HOURS`（默认 6）的才 warn；当天回填 **静默**。
#
# 断言分组：
#   A 无 stash ⇒ **零输出**：`^  ! git stash` 计数 0、摘要无 `warn=` 字段、rc=0（空时不制造常驻噪音）
#   B 刚生成的 stash（当天回填）⇒ **静默**：0 条 warn、摘要无 `warn=`、rc 仍 0（#130 D1 主判据）
#     反空转：同一条 fresh stash + `NAO_STASH_WARN_HOURS=0` ⇒ 恰 1 条 warn（闸门活着，不是被阈值废掉）
#   C 8 小时前 ⇒ 恰 1 条 warn + 摘要 `warn=1` + rc **仍 0** + 文案含「最老一条 8 小时前」「阈值 6 小时」
#     + BR5/pop/归口 + 点名最新一条消息
#   D 阈值可覆盖（env）：8h stash + 阈值 9 ⇒ 静默；+ 阈值 7 ⇒ warn（边界由 env 决定，不是写死）
#   E 多条 ⇒ 仍**一条** warn（不逐条刷屏）+ 文案给真实条数；且**以最老一条为准**
#     （fresh + aged 混合 ⇒ warn；两条都 fresh ⇒ 静默）
#   F 双向：pop 掉 ⇒ warn 消失（判据不是恒真）
#   G 不适用 ⇒ 零输出：根上无 `.git`（默认根 = 夹具包根）**不向上 walk**
#   H 时间/取值口径：**未来时间戳** ⇒ 不 warn（不误报、不炸）；阈值非法（`abc` / `-1`）⇒ 按「立即」处理
#     + 文案点名；**前导零**（`08`/`010`/`0008`）⇒ 按十进制 8/10/8 生效且 rc=0（#130 返修 P2-1：算术不得崩）；
#     `%ct` 不可解析 ⇒ 不 warn 但留 `  ·` 降级注记（#130 返修 P2-2：不得与「无 stash」不可区分）
#   I 零副作用自证：真实仓库 stash 存量前后一致 + 哨兵 stash 未出现在真实仓库（用例只碰临时仓）
#   J 静态面：单点实现 + 单点调用且 warn-only（`|| true`）· 机制脚本**只读** stash（无 push/pop/apply/drop）
#     · 年龄取自 `%ct` · 阈值走 env（默认 6）
#
# 测试纪律（PM 硬要求 · 别踩）：**不得在真实仓库造 stash** —— 同一 worktree 共享，会把 PM/QA 的工作台
#   一起卷进去。本用例的自建仓在 `$T4_CACHE_DIR/c35/*`（`mktemp -d` 下）里 `git init` + 造提交 +
#   造 stash；被测脚本经 `NAO_STASH_ROOT` **注入根**（默认根 = `$SKILLS_DIR`，绝不在真仓动作）。
#   「8 小时前」用 `GIT_COMMITTER_DATE/GIT_AUTHOR_DATE` 造（`git stash push` 的提交时间受其影响）
#   ⇒ 不需要 sleep、不依赖机器时钟精度。
#
# 能力门：`git`（缺 ⇒ BLOCKED）+ `date -d`（GNU date；缺则用例显式 FAIL，不静默跳过时间判据）。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
FLEET_BUNDLE="$(t4_fleet_bundle "$T4_ROOT/.agents/scripts")"   # T567-A：只读内容断言按文件集（入口 + fleet/lib）
t4_assert_file "$FLEET" "被测脚本存在（nao-fleet.sh）"
t4_require_cmd git

# ---------------------------------------------------------------- 夹具
rm -rf "$T4_CACHE_DIR/c35"
FX="$T4_CACHE_DIR/c35/repo"          # 被测包根（非 git 仓 ⇒ 默认根不适用）
GITROOT="$T4_CACHE_DIR/c35/gitroot"  # 注入根（自建 git 仓，stash 只造在这里）
GITFUT="$T4_CACHE_DIR/c35/gitfuture" # 未来时间戳专用仓（H 组）
BIN="$T4_CACHE_DIR/c35/bin"
AGENT_EMPTY="$T4_CACHE_DIR/c35/pi-empty"
mkdir -p "$FX" "$GITROOT" "$GITFUT" "$BIN" "$AGENT_EMPTY"
cp -r "$T4_ROOT/.agents" "$FX/.agents" || t4_blocked "夹具复制 .agents 失败"

# 桩：只满足 check 的端前提/版本机械面（不建任何 session / pane / server）
printf '#!/usr/bin/env bash\nprintf "herdr 0.9.1\\n"\n' > "$BIN/herdr"
printf '#!/usr/bin/env bash\nprintf "pi 1.5.2\\n"\n' > "$BIN/pi"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/tmux"
chmod +x "$BIN/herdr" "$BIN/pi" "$BIN/tmux"

# 自建 git 仓（**不在真实仓库动作**）：一次提交 + 一个改动，供 stash 演练
git -C "$GITROOT" init -q 2>/dev/null || t4_blocked "夹具 git init 失败"
git -C "$GITROOT" config user.email "t4@example.invalid"
git -C "$GITROOT" config user.name "t4"
printf 'base\n' > "$GITROOT/f.txt"
git -C "$GITROOT" add f.txt
git -C "$GITROOT" commit -qm "fixture: init"
git -C "$GITFUT" init -q 2>/dev/null || t4_blocked "夹具 git init 失败（future）"
git -C "$GITFUT" config user.email "t4@example.invalid"
git -C "$GITFUT" config user.name "t4"
printf 'base\n' > "$GITFUT/f.txt"
git -C "$GITFUT" add f.txt
git -C "$GITFUT" commit -qm "fixture: init"

# `date -d '<n> hours ago'`：GNU date 能力门（缺 ⇒ 显式 FAIL —— 时间判据不能静默跳过）
C35_DATE_OK=0
if C35_8H="$(date -d '8 hours ago' -R 2>/dev/null)" && [ -n "$C35_8H" ]; then C35_DATE_OK=1; fi
if C35_FUT="$(date -d '+2 hours' -R 2>/dev/null)" && [ -n "$C35_FUT" ]; then :; else C35_DATE_OK=0; fi
t4_assert_eq "1" "$C35_DATE_OK" "H0 夹具自证：本机 date 支持 -d（造 8h 前 / 未来时间戳）"

SENTINEL="c35-sentinel-stash"
stash_count() { git -C "$1" stash list 2>/dev/null | grep -c . || true; }
make_stash() { # $1=根 $2=消息 [$3=小时数前（空=现在）]：造一条 stash（工作区改动 ⇒ stash ⇒ 工作区回干净）
  printf 'dirty %s\n' "$2" >> "$1/f.txt"
  if [ -n "${3:-}" ]; then
    local ts
    ts="$(date -d "$3 hours ago" -R 2>/dev/null || true)"
    [ -n "$ts" ] || { t4_bad "夹具：date -d '$3 hours ago' 不可用（无法造老化 stash）"; return 1; }
    GIT_COMMITTER_DATE="$ts" GIT_AUTHOR_DATE="$ts" \
      git -C "$1" stash push -q -m "$2" -- f.txt 2>/dev/null || t4_bad "夹具 stash push 失败（$2）"
  else
    git -C "$1" stash push -q -m "$2" -- f.txt 2>/dev/null || t4_bad "夹具 stash push 失败（$2）"
  fi
}
make_future_stash() { # $1=根 $2=消息：提交时间 = now + 2h（时钟回拨 / 手工造未来日期）
  printf 'dirty %s\n' "$2" >> "$1/f.txt"
  GIT_COMMITTER_DATE="$C35_FUT" GIT_AUTHOR_DATE="$C35_FUT" \
    git -C "$1" stash push -q -m "$2" -- f.txt 2>/dev/null || t4_bad "夹具 stash push 失败（future/$2）"
}

# 环境：清掉宿主继承的 HERDR_*（**动态枚举**清 —— 超集，不登记清单；见 tests/t4/lib.sh 单源注释）。
#   `-u NAO_STASH_ROOT`：宿主若导出了注入根（外部演练/手工场景），一律摘掉 —— G 组验的是「**默认**根 =
#   夹具包根（非仓）⇒ 零输出」，被外部注入盖掉就变成另一条判据（假红）。
#   `-u NAO_STASH_WARN_HOURS`：阈值一律由本用例显式给，不继承宿主设置（判据不依赖外部 env）。
C35_CLEAN=(env -u NAO_STASH_ROOT -u NAO_STASH_WARN_HOURS)
for _v in $(env | grep -o '^HERDR_[A-Z_]*' || true); do C35_CLEAN+=(-u "$_v"); done
C35_BASE=("${C35_CLEAN[@]}" NAO_SKILLS="$FX" PI_CODING_AGENT_DIR="$AGENT_EMPTY" PATH="$BIN:$PATH")

C35_RC=0; C35_OUT=""; C35_HOURS=""   # C35_HOURS 非空 ⇒ 本轮显式给 NAO_STASH_WARN_HOURS（默认不设 = 走脚本默认 6）
run_check() { # $1=dk（default|inject|noroot|future）· 其余参数透传（如 -v）
  local kind="$1"; shift
  local of ef
  local -a envs
  case "$kind" in
    inject) envs=("${C35_BASE[@]}" NAO_STASH_ROOT="$GITROOT") ;;   # 注入根 = 自建仓
    future) envs=("${C35_BASE[@]}" NAO_STASH_ROOT="$GITFUT") ;;
    noroot) envs=("${C35_BASE[@]}") ;;   # 不注入 ⇒ 默认根 = $SKILLS_DIR（$FX，非 git 仓）
    *)      t4_bad "run_check：未知 dk=$kind"; return ;;
  esac
  # 阈值必须作为 **env 赋值**放在命令之前（写在 `check` 之后会变成位置参数 ⇒ 脚本进 verbose 模式，阈值不生效）
  [ -n "${C35_HOURS}" ] && envs+=(NAO_STASH_WARN_HOURS="$C35_HOURS")
  of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$FX" && "${envs[@]}" bash .agents/scripts/nao-fleet.sh check "$@" ) >"$of" 2>"$ef"
  C35_RC=$?
  C35_OUT="$(cat "$of"; cat "$ef")"
  rm -f "$of" "$ef"
}
stash_warns() { printf '%s\n' "$C35_OUT" | grep -c '^  ! git stash' || true; }
warn_field() { printf '%s\n' "$C35_OUT" | grep -oE 'warn=[0-9]+' | head -1 || true; }

# 真实仓库存量（**只读**）：前后一致 + 无哨兵 = 用例零副作用的自证
REAL_BEFORE="$(stash_count "$T4_ROOT")"

# ============================================================ A 无 stash ⇒ 零输出
t4_assert_eq "0" "$(stash_count "$GITROOT")" "A0 夹具自证：注入根初始无 stash"
run_check inject
t4_assert_eq "0" "$C35_RC" "A1 无 stash：rc=0"
t4_assert_eq "0" "$(stash_warns)" "A2 无 stash：零条 stash warn（空 ⇒ 零输出）"
t4_assert_eq "" "$(warn_field)" "A3 无 stash：摘要无 warn= 字段（不常驻）"
t4_assert_contains "$C35_OUT" "check: OK" "A4 无 stash：摘要行在场（正锚 ⇒ 空输出不会空转通过）"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "A5 无 stash + -v：rc=0"
t4_assert_eq "0" "$(stash_warns)" "A6 无 stash + -v：报告里也零条 stash warn（不是只在摘要里隐身）"
t4_assert_contains "$C35_OUT" "== 运行前提" "A7 无 stash + -v：报告正文在场（正锚 ⇒ 早退不会空转通过）"

# ============================================================ B 刚生成（当天回填）⇒ 静默（#130 D1 主判据）
make_stash "$GITROOT" "$SENTINEL"
t4_assert_eq "1" "$(stash_count "$GITROOT")" "B0 夹具自证：注入根已有 1 条**刚生成**的 stash（判据非空转）"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "B1 fresh stash + -v：rc=0"
t4_assert_eq "0" "$(stash_warns)" "B2 fresh stash（< 6h，当天回填）：**零条** warn（#130 D1：静默）"
run_check inject
t4_assert_eq "0" "$C35_RC" "B3 fresh stash 摘要模式：rc 仍 0"
t4_assert_eq "" "$(warn_field)" "B4 fresh stash：摘要**无** warn= 字段（不制造常驻噪声 —— 本项的病根）"
# 反空转：同一条 fresh stash + 阈值 0（= 立即）⇒ warn 必须出现（闸门活着，不是被阈值废掉）
C35_HOURS=0 run_check inject -v
t4_assert_eq "1" "$(stash_warns)" "B5 反空转：fresh stash + NAO_STASH_WARN_HOURS=0 ⇒ 恰 1 条 warn（闸门未被阈值废成空转）"
t4_assert_contains "$C35_OUT" "$SENTINEL" "B6 反空转：warn 点名滞留内容（可定位到具体 stash 消息）"

# ============================================================ C 8 小时前 ⇒ 恰 1 条 + warn=1 + rc 仍 0
git -C "$GITROOT" stash pop -q 2>/dev/null || t4_bad "夹具 stash pop 失败"
t4_assert_eq "0" "$(stash_count "$GITROOT")" "C0 夹具自证：pop 后注入根无 stash（为老化 stash 让位）"
make_stash "$GITROOT" "$SENTINEL-aged" 8
t4_assert_eq "1" "$(stash_count "$GITROOT")" "C1 夹具自证：注入根已有 1 条**8 小时前**的 stash"
t4_assert_eq "1" "$(git -C "$GITROOT" stash list --format='%ct' | awk -v now="$(date +%s)" '{print (now-$1>=7*3600)?1:0}' | head -1)" \
  "C2 夹具自证：该 stash 的 %ct 确在 7 小时前以上（GIT_COMMITTER_DATE 生效）"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "C3 aged stash + -v：rc 仍 0（warn-only，不改 rc）"
t4_assert_eq "1" "$(stash_warns)" "C4 aged stash：恰 1 条 stash warn（单点，不重复）"
t4_assert_match "$C35_OUT" '^  ! git stash 非空（1 条' "C5 文案给出条数（\`git stash 非空（N 条\`）"
t4_assert_contains "$C35_OUT" "最老一条 8 小时前 > 阈值 6 小时" "C6 文案给出年龄与阈值（8 小时前 > 6 小时）"
t4_assert_contains "$C35_OUT" "BR5" "C7 文案指明依据（合并后事实滞留 = BR5）"
t4_assert_contains "$C35_OUT" "pop" "C8 文案给出处置（下批首提交须 pop）"
t4_assert_contains "$C35_OUT" "归口" "C9 文案给出处置（或归口）"
t4_assert_contains "$C35_OUT" "$SENTINEL-aged" "C10 文案点名滞留内容（可定位到具体 stash 消息）"
run_check inject
t4_assert_eq "0" "$C35_RC" "C11 摘要模式：rc 仍 0（warn 不改 rc）"
t4_assert_contains "$C35_OUT" "warn=1" "C12 摘要模式：该 warn 计入 warn=N（被计数，不静默）"

# ============================================================ D 阈值 env 可覆盖（边界由 env 决定）
C35_HOURS=9 run_check inject
t4_assert_eq "0" "$(stash_warns)" "D1 阈值 9 小时：同一条 8h stash ⇒ **静默**（阈值真的读 env，不是写死 6）"
t4_assert_eq "" "$(warn_field)" "D2 阈值 9 小时：摘要无 warn= 字段"
C35_HOURS=7 run_check inject -v
t4_assert_eq "1" "$(stash_warns)" "D3 阈值 7 小时：同一条 8h stash ⇒ 仍 1 条 warn（边界 7 < 8）"
t4_assert_contains "$C35_OUT" "> 阈值 7 小时" "D4 文案回显生效阈值（7 小时）"

# ============================================================ E 多条 ⇒ 仍一条（不逐条刷屏）+ 以最老为准
make_stash "$GITROOT" "$SENTINEL-fresh"
t4_assert_eq "2" "$(stash_count "$GITROOT")" "E0 夹具自证：注入根已有 2 条 stash（1 aged + 1 fresh）"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "E1 两条 stash：rc 仍 0"
t4_assert_eq "1" "$(stash_warns)" "E2 两条 stash：仍恰 1 条 warn（聚合，不逐条刷屏）"
t4_assert_match "$C35_OUT" '^  ! git stash 非空（2 条' "E3 文案给出真实条数（2 条）"
t4_assert_contains "$C35_OUT" "最老一条 8 小时前" "E4 多条时以**最老一条**为准（8h ⇒ 仍超 6h 阈值）"
# 反向：两条都 fresh（最老之一也 < 6h）⇒ 静默
git -C "$GITROOT" stash pop -q 2>/dev/null || t4_bad "夹具 stash pop 失败（fresh 一条）"
git -C "$GITROOT" stash drop -q 2>/dev/null || true   # 丢掉剩下的 aged 那条（只碰临时仓）
t4_assert_eq "0" "$(stash_count "$GITROOT")" "E5 夹具自证：已清空临时仓 stash"
make_stash "$GITROOT" "$SENTINEL-f1"
make_stash "$GITROOT" "$SENTINEL-f2"
t4_assert_eq "2" "$(stash_count "$GITROOT")" "E6 夹具自证：两条**都刚生成**"
run_check inject -v
t4_assert_eq "0" "$(stash_warns)" "E7 两条都 fresh：最老一条仍 < 6h ⇒ 零条 warn（年龄判据作用于最老一条）"

# ============================================================ F 双向：pop/drop ⇒ 消失
git -C "$GITROOT" stash drop -q 2>/dev/null || t4_bad "夹具 stash drop 失败"
git -C "$GITROOT" stash drop -q 2>/dev/null || t4_bad "夹具 stash drop 失败"
t4_assert_eq "0" "$(stash_count "$GITROOT")" "F0 夹具自证：清空后注入根无 stash"
make_stash "$GITROOT" "$SENTINEL-pop" 8
run_check inject -v
t4_assert_eq "1" "$(stash_warns)" "F1 再次造 aged stash ⇒ warn 重现（双向正控）"
git -C "$GITROOT" stash pop -q 2>/dev/null || t4_bad "夹具 stash pop 失败"
t4_assert_eq "0" "$(stash_count "$GITROOT")" "F2 夹具自证：pop 后注入根无 stash"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "F3 pop 后：rc=0"
t4_assert_eq "0" "$(stash_warns)" "F4 pop 后：warn 消失（双向，判据非恒真）"
run_check inject
t4_assert_eq "" "$(warn_field)" "F5 pop 后：摘要无 warn= 字段"

# ============================================================ G 不适用 ⇒ 零输出（不向上 walk）
run_check noroot -v
t4_assert_eq "0" "$C35_RC" "G1 不注入根（默认根 = 夹具包根，非 git 仓）：rc=0"
t4_assert_eq "0" "$(stash_warns)" "G2 根上无 .git：零 warn（不向上 walk ⇒ temp 目录不被父仓误判）"
NAO_NONROOT="$T4_CACHE_DIR/c35/not-a-repo"
mkdir -p "$NAO_NONROOT"
C35_OUT="$( cd "$FX" && "${C35_BASE[@]}" NAO_STASH_ROOT="$NAO_NONROOT" bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_eq "0" "$(printf '%s\n' "$C35_OUT" | grep -c '^  ! git stash' || true)" \
  "G3 显式注入非仓目录：零 warn（不适用不刷屏）"

# ============================================================ H 时间口径（未来时间戳 / 非法阈值）
make_future_stash "$GITFUT" "$SENTINEL-future"
t4_assert_eq "1" "$(stash_count "$GITFUT")" "H1 夹具自证：未来仓已有 1 条 stash"
run_check future -v
t4_assert_eq "0" "$C35_RC" "H2 未来时间戳（now+2h）：rc=0（不炸）"
t4_assert_eq "0" "$(stash_warns)" "H3 未来时间戳：零条 warn（时间不可信时不误报）"
C35_HOURS=0 run_check future
t4_assert_eq "0" "$(stash_warns)" "H4 未来时间戳 + 阈值 0：仍零条 warn（未来时间戳恒不 warn）"
# 非法阈值：非数字 / 负数 ⇒ 按「立即」处理（不得把闸门静默调松），并在文案点名
make_stash "$GITROOT" "$SENTINEL-invalid"
C35_HOURS=abc run_check inject -v
t4_assert_eq "1" "$(stash_warns)" "H5 阈值 abc（非法）：fresh stash 仍 warn（按立即处理，不静默放行）"
t4_assert_contains "$C35_OUT" "NAO_STASH_WARN_HOURS 取值无效" "H6 非法阈值：文案点名取值无效（可诊断）"
C35_HOURS=-1 run_check inject -v
t4_assert_eq "1" "$(stash_warns)" "H7 阈值 -1（非法）：同样按立即处理 ⇒ warn"
git -C "$GITROOT" stash pop -q 2>/dev/null || true

# ============================================================ H2 前导零阈值（#130 返修 P2-1：不得让体检崩）
#   病根：`$(( hours * 3600 ))` 会把 `08` 当八进制 ⇒ bash 算术报「值对于底数而言过大」⇒ check rc=1、
#   无汇总行（门禁自己硬红）；`010` 反而静默按 8 生效、文案却写 010。修法 = 算术前 `10#`。
#   判据：08 / 010 / 0008 分别按**十进制** 8 / 10 / 8 生效，且 rc 恒 0（9h 时的 stash 可区分 8 与 10）。
t4_assert_eq "0" "$(stash_count "$GITROOT")" "H8 夹具自证：先清空（前导零组用 9h stash）"
make_stash "$GITROOT" "$SENTINEL-9h" 9
C35_HOURS=08 run_check inject -v
t4_assert_eq "0" "$C35_RC" "H8 阈值 08（前导零）：check rc=0（不得因八进制解析硬崩）"
t4_assert_eq "1" "$(stash_warns)" "H8 阈值 08 ⇒ 按十进制 8 生效（9h stash > 8h ⇒ warn）"
t4_assert_contains "$C35_OUT" "> 阈值 8 小时" "H8 文案回显解析后的十进制 8（非 08）"
C35_HOURS=010 run_check inject -v
t4_assert_eq "0" "$C35_RC" "H9 阈值 010（前导零）：check rc=0"
t4_assert_eq "0" "$(stash_warns)" "H9 阈值 010 ⇒ 按十进制 10 生效（9h stash < 10h ⇒ 静默，不是八进制 8）"
C35_HOURS=0008 run_check inject -v
t4_assert_eq "0" "$C35_RC" "H9 阈值 0008：check rc=0"
t4_assert_eq "1" "$(stash_warns)" "H9 阈值 0008 ⇒ 按十进制 8 生效（warn）"
t4_assert_contains "$C35_OUT" "> 阈值 8 小时" "H9 文案回显十进制 8（非 0008）"
git -C "$GITROOT" stash pop -q 2>/dev/null || true

# ============================================================ H3 `%ct` 不可解析 ⇒ 降级注记（#130 返修 P2-2）
#   病根：取不到 %ct 时旧实现 `return 0` 零输出 ⇒ 与「无 stash」**输出上不可区分**，闸门可被永久且无痕静默。
#   判据：仍**不 warn**（方向对：不误报）、rc=0，但 `-v` 必须有一条 `  ·` 降级注记（不进 warn 计数）。
C35_FAKEBIN="$T4_CACHE_DIR/c35/fakebin"
mkdir -p "$C35_FAKEBIN"
{ printf '#!/usr/bin/env bash\nfor a in "$@"; do case "$a" in *--format=%%ct*) printf "n/a\\n"; exit 0 ;; esac; done\nexec %q "$@"\n' "$(command -v git)"; } \
  > "$C35_FAKEBIN/git"
chmod +x "$C35_FAKEBIN/git"
run_check_fakegit() { # 同 run_check inject，但 PATH 前置「把 %ct 打成 n/a」的 git 包装器
  local of ef
  of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$FX" && "${C35_CLEAN[@]}" PATH="$C35_FAKEBIN:$BIN:$PATH" NAO_SKILLS="$FX" \
      PI_CODING_AGENT_DIR="$AGENT_EMPTY" NAO_STASH_ROOT="$GITROOT" \
      bash .agents/scripts/nao-fleet.sh check "$@" ) >"$of" 2>"$ef"
  C35_RC=$?
  C35_OUT="$(cat "$of"; cat "$ef")"
  rm -f "$of" "$ef"
}
make_stash "$GITROOT" "$SENTINEL-noct" 9
run_check inject -v
t4_assert_eq "1" "$(stash_warns)" "H10 夹具自证：真 git 下同一条 9h stash ⇒ 1 条 warn（对照）"
run_check_fakegit -v
t4_assert_eq "0" "$C35_RC" "H10 %ct 不可解析：rc=0（不炸）"
t4_assert_eq "0" "$(stash_warns)" "H10 %ct 不可解析：仍不 warn（避免误报 —— 方向不变）"
t4_assert_contains "$C35_OUT" "暂存滞留检查跳过" "H10 %ct 不可解析：「-v」 留下降级注记（与「无 stash」可区分）"
t4_assert_contains "$C35_OUT" "不可解析" "H10 注记点名能力缺失（可诊断）"
run_check_fakegit
t4_assert_eq "" "$(warn_field)" "H10 摘要模式：降级注记不计入 warn=（不进摘要、不污染噪声）"
git -C "$GITROOT" stash pop -q 2>/dev/null || true

# ============================================================ I 零副作用自证（真实仓库）
REAL_AFTER="$(stash_count "$T4_ROOT")"
t4_assert_eq "$REAL_BEFORE" "$REAL_AFTER" "I1 真实仓库 stash 存量前后一致（前=${REAL_BEFORE} 后=${REAL_AFTER}；用例零副作用）"
t4_assert_eq "0" "$(git -C "$T4_ROOT" stash list 2>/dev/null | grep -c 'c35-sentinel' || true)" \
  "I2 哨兵 stash 未出现在真实仓库（stash 只造在临时仓）"
t4_info "真实仓库 stash：前=${REAL_BEFORE} 后=${REAL_AFTER}；临时仓 ${GITROOT#"$T4_CACHE_DIR"/} 已造/弹/丢 stash"

# ============================================================ J 静态面（单点 + warn-only + 只读 + 年龄口径）
t4_assert_eq "2" "$(t4_fleet_count 'check_stash_residue' "$T4_ROOT/.agents/scripts")" \
  "J1 单点实现 + 单点调用（定义 1 + 调用 1）"
t4_assert_eq "1" "$(t4_fleet_count 'check_stash_residue [|][|] true' "$T4_ROOT/.agents/scripts")" \
  "J2 调用点 warn-only（\`|| true\` ⇒ 不改 check rc）"
t4_assert_eq "1" "$(t4_fleet_count 'NAO_STASH_ROOT:-\$SKILLS_DIR' "$T4_ROOT/.agents/scripts")" \
  "J3 默认根 = \$SKILLS_DIR，且可被 \`NAO_STASH_ROOT\` 注入（测试只碰临时仓）"
t4_assert_eq "1" "$(t4_fleet_count 'NAO_STASH_WARN_HOURS:-6' "$T4_ROOT/.agents/scripts")" \
  "J4 阈值默认 6 小时，且可被 \`NAO_STASH_WARN_HOURS\` 覆盖（单点读取）"
t4_assert_eq "1" "$(t4_fleet_count "--format='%ct' 2>/dev/null" "$T4_ROOT/.agents/scripts")" \
  "J5 年龄取自 \`stash list --format='%ct'\` 的最小值（单点，非 reflog）"
t4_assert_eq "0" "$(t4_fleet_count 'git .*stash (push|pop|apply|drop|save|clear)' "$T4_ROOT/.agents/scripts")" \
  "J6 机制脚本只读 stash（无 push/pop/apply/drop/save/clear ⇒ 闸门绝不自行改写滞留事实）"
t4_assert_eq "1" "$(t4_fleet_count '10#\$hours' "$T4_ROOT/.agents/scripts")" \
  "J7 前导零按十进制解析（算术前 10#；否则 08 会让 check 硬红）（#130 返修 P2-1）"
t4_assert_eq "1" "$(t4_fleet_count '暂存滞留检查跳过' "$T4_ROOT/.agents/scripts")" \
  "J8 取不到 %ct 时留降级注记（单点，与「无 stash」可区分）（#130 返修 P2-2）"

t4_exit
