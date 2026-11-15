#!/usr/bin/env bash
# 用例 35 —— check 新增「stash 出口」机械闸（#126 · B2-2）
#
# 判据来源：Issue #126（B2-2）· 上游 `docs/reports/118-mechanism-review.md` §四（BR5 批间收尾）
#   实测动机（PM 2026-11-14 记）：3 个滞留 stash —— `v0.22.6` 压 7 天、`M20261113` 压 7.5 小时且其
#   sha `0863ab2` 在台账 grep = 0 ⇒ **终态从未入库**。故 `check` 须有一条只读告警，指明「合并后事实
#   可能滞留 stash（BR5）⇒ 下批首提交须 pop 或归口」。
#
# 断言分组：
#   A 无 stash ⇒ **零输出**：`^  ! ` 计数 0、摘要无 `warn=` 字段、rc=0（空时不制造常驻噪音）
#   B 有 stash ⇒ 恰 1 条 warn + 摘要 `warn=1` + rc **仍 0**（warn-only，不改 rc）+ 文案含 BR5/pop/归口
#   C 双向：pop 掉 ⇒ warn 消失（判据不是恒真）
#   D 多条 stash ⇒ 仍**一条** warn（不逐条刷屏）+ 文案给出条数
#   E 不适用 ⇒ 零输出：根上无 `.git`（默认根 = 夹具包根）**不向上 walk**（temp 目录被父仓误判即假红源）
#   F 零副作用自证：真实仓库 stash 存量前后一致 + 哨兵 stash 未出现在真实仓库（用例只碰临时仓）
#   G 静态面：单点实现 + 单点调用且 warn-only（`|| true`）· 机制脚本**只读** stash（无 push/pop/apply/drop）
#
# 测试纪律（PM 硬要求 · 别踩）：**不得在真实仓库造 stash** —— 同一 worktree 共享，会把 PM/QA 的工作台
#   一起卷进去。本用例的自建仓在 `$T4_CACHE_DIR/c35/gitroot`（`mktemp -d` 下）里 `git init` + 造提交 +
#   造 stash；被测脚本经 `NAO_STASH_ROOT` **注入根**（默认根 = `$SKILLS_DIR`，绝不在真仓动作）。
#
# 能力门：`git`（缺 ⇒ BLOCKED）；纯 bash，不建 server、零网络、零真 pi。
set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
t4_assert_file "$FLEET" "被测脚本存在（nao-fleet.sh）"
t4_require_cmd git

# ---------------------------------------------------------------- 夹具
rm -rf "$T4_CACHE_DIR/c35"
FX="$T4_CACHE_DIR/c35/repo"          # 被测包根（非 git 仓 ⇒ 默认根不适用）
GITROOT="$T4_CACHE_DIR/c35/gitroot"  # 注入根（自建 git 仓，stash 只造在这里）
BIN="$T4_CACHE_DIR/c35/bin"
AGENT_EMPTY="$T4_CACHE_DIR/c35/pi-empty"
mkdir -p "$FX" "$GITROOT" "$BIN" "$AGENT_EMPTY"
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

SENTINEL="c35-sentinel-stash"
stash_count() { git -C "$1" stash list 2>/dev/null | grep -c . || true; }
make_stash() { # $1=根 $2=消息：造一条 stash（工作区改动 ⇒ stash ⇒ 工作区回干净）
  printf 'dirty %s\n' "$2" >> "$1/f.txt"
  git -C "$1" stash push -q -m "$2" -- f.txt 2>/dev/null || t4_bad "夹具 stash push 失败（$2）"
}

# 环境：清掉宿主继承的 HERDR_*（枚举清 —— 与 lib-backend / cases/34 同纪律；否则在 herdr pane 内跑会问真 server）
#   `-u NAO_STASH_ROOT`：宿主若导出了注入根（外部演练/手工场景），一律摘掉 —— E 组验的是「**默认**根 =
#   夹具包根（非仓）⇒ 零输出」，被外部注入盖掉就变成另一条判据（假红）。
C35_CLEAN=(env -u NAO_STASH_ROOT)
for _v in $(env | grep -o '^HERDR_[A-Z_]*' || true); do C35_CLEAN+=(-u "$_v"); done
C35_BASE=("${C35_CLEAN[@]}" NAO_SKILLS="$FX" PI_CODING_AGENT_DIR="$AGENT_EMPTY" PATH="$BIN:$PATH")
C35_ENV=("${C35_BASE[@]}" NAO_STASH_ROOT="$GITROOT")   # 注入根 = 自建仓

C35_RC=0; C35_OUT=""
run_check() { # $1=dk（default|inject|noroot）· 其余参数透传（如 -v）
  local kind="$1"; shift
  local of ef
  local -a envs
  case "$kind" in
    inject) envs=("${C35_ENV[@]}") ;;
    noroot) envs=("${C35_BASE[@]}") ;;   # 不注入 ⇒ 默认根 = $SKILLS_DIR（$FX，非 git 仓）
    *)      t4_bad "run_check：未知 dk=$kind"; return ;;
  esac
  of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$FX" && "${envs[@]}" bash .agents/scripts/nao-fleet.sh check "$@" ) >"$of" 2>"$ef"
  C35_RC=$?
  C35_OUT="$(cat "$of"; cat "$ef")"
  rm -f "$of" "$ef"
}
stash_warns() { printf '%s\n' "$C35_OUT" | grep -c '^  ! git stash' || true; }

# 真实仓库存量（**只读**）：前后一致 + 无哨兵 = 用例零副作用的自证
REAL_BEFORE="$(stash_count "$T4_ROOT")"

# ============================================================ A 无 stash ⇒ 零输出
t4_assert_eq "0" "$(stash_count "$GITROOT")" "A0 夹具自证：注入根初始无 stash"
run_check inject
t4_assert_eq "0" "$C35_RC" "A1 无 stash：rc=0"
t4_assert_eq "0" "$(stash_warns)" "A2 无 stash：零条 stash warn（空 ⇒ 零输出）"
t4_assert_not_contains "$C35_OUT" "warn=" "A3 无 stash：摘要无 warn= 字段（不常驻）"
t4_assert_contains "$C35_OUT" "check: OK" "A4 无 stash：摘要行在场（正锚 ⇒ 空输出不会空转通过）"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "A5 无 stash + -v：rc=0"
t4_assert_eq "0" "$(stash_warns)" "A6 无 stash + -v：报告里也零条 stash warn（不是只在摘要里隐身）"
t4_assert_contains "$C35_OUT" "== 运行前提" "A7 无 stash + -v：报告正文在场（正锚 ⇒ 早退不会空转通过）"

# ============================================================ B 有 stash ⇒ 恰 1 条 + warn=1 + rc 仍 0
make_stash "$GITROOT" "$SENTINEL"
t4_assert_eq "1" "$(stash_count "$GITROOT")" "B0 夹具自证：注入根已有 1 条 stash（判据非空转）"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "B1 有 stash + -v：rc 仍 0（warn-only，不改 rc）"
t4_assert_eq "1" "$(stash_warns)" "B2 有 stash：恰 1 条 stash warn（单点，不重复）"
t4_assert_match "$C35_OUT" '^  ! git stash 非空（1 条' "B2b 文案给出条数（\`git stash 非空（N 条\`）"
t4_assert_contains "$C35_OUT" "BR5" "B3 文案指明依据（合并后事实滞留 = BR5）"
t4_assert_contains "$C35_OUT" "pop" "B4 文案给出处置（下批首提交须 pop）"
t4_assert_contains "$C35_OUT" "归口" "B5 文案给出处置（或归口）"
t4_assert_contains "$C35_OUT" "$SENTINEL" "B6 文案点名滞留内容（可定位到具体 stash 消息）"
run_check inject
t4_assert_eq "0" "$C35_RC" "B7 摘要模式：rc 仍 0（warn 不改 rc）"
t4_assert_contains "$C35_OUT" "warn=1" "B8 摘要模式：该 warn 计入 warn=N（被计数，不静默）"

# ============================================================ C 双向：pop ⇒ 消失
git -C "$GITROOT" stash pop -q 2>/dev/null || t4_bad "夹具 stash pop 失败"
t4_assert_eq "0" "$(stash_count "$GITROOT")" "C0 夹具自证：pop 后注入根无 stash"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "C1 pop 后：rc=0"
t4_assert_eq "0" "$(stash_warns)" "C2 pop 后：warn 消失（双向，判据非恒真）"
run_check inject
t4_assert_not_contains "$C35_OUT" "warn=" "C3 pop 后：摘要无 warn= 字段"

# ============================================================ D 多条 ⇒ 仍一条（不逐条刷屏）+ 给出条数
git -C "$GITROOT" checkout -q -- f.txt 2>/dev/null || true
make_stash "$GITROOT" "$SENTINEL-a"
make_stash "$GITROOT" "$SENTINEL-b"
t4_assert_eq "2" "$(stash_count "$GITROOT")" "D0 夹具自证：注入根已有 2 条 stash"
run_check inject -v
t4_assert_eq "0" "$C35_RC" "D1 两条 stash：rc 仍 0"
t4_assert_eq "1" "$(stash_warns)" "D2 两条 stash：仍恰 1 条 warn（聚合，不逐条刷屏）"
t4_assert_match "$C35_OUT" '^  ! git stash 非空（2 条' "D3 文案给出真实条数（2 条）"

# ============================================================ E 不适用 ⇒ 零输出（不向上 walk）
run_check noroot -v
t4_assert_eq "0" "$C35_RC" "E1 不注入根（默认根 = 夹具包根，非 git 仓）：rc=0"
t4_assert_eq "0" "$(stash_warns)" "E2 根上无 .git：零 warn（不向上 walk ⇒ temp 目录不被父仓误判）"
NAO_NONROOT="$T4_CACHE_DIR/c35/not-a-repo"
mkdir -p "$NAO_NONROOT"
C35_OUT="$( cd "$FX" && "${C35_ENV[@]}" NAO_STASH_ROOT="$NAO_NONROOT" bash .agents/scripts/nao-fleet.sh check -v 2>&1 )"
t4_assert_eq "0" "$(printf '%s\n' "$C35_OUT" | grep -c '^  ! git stash' || true)" \
  "E3 显式注入非仓目录：零 warn（不适用不刷屏）"

# ============================================================ F 零副作用自证（真实仓库）
REAL_AFTER="$(stash_count "$T4_ROOT")"
t4_assert_eq "$REAL_BEFORE" "$REAL_AFTER" "F1 真实仓库 stash 存量前后一致（前=${REAL_BEFORE} 后=${REAL_AFTER}；用例零副作用）"
t4_assert_eq "0" "$(git -C "$T4_ROOT" stash list 2>/dev/null | grep -c 'c35-sentinel' || true)" \
  "F2 哨兵 stash 未出现在真实仓库（stash 只造在临时仓）"
t4_info "真实仓库 stash：前=${REAL_BEFORE} 后=${REAL_AFTER}；临时仓 ${GITROOT#"$T4_CACHE_DIR"/} 已造/弹 stash"

# ============================================================ G 静态面（单点 + warn-only + 只读）
t4_assert_eq "2" "$(grep -c 'check_stash_residue' "$FLEET" || true)" \
  "G1 单点实现 + 单点调用（定义 1 + 调用 1）"
t4_assert_eq "1" "$(grep -c 'check_stash_residue || true' "$FLEET" || true)" \
  "G2 调用点 warn-only（\`|| true\` ⇒ 不改 check rc）"
t4_assert_eq "1" "$(grep -cE 'NAO_STASH_ROOT:-\$SKILLS_DIR' "$FLEET" || true)" \
  "G3 默认根 = \$SKILLS_DIR，且可被 \`NAO_STASH_ROOT\` 注入（测试只碰临时仓）"
t4_assert_eq "0" "$(grep -cE 'git .*stash (push|pop|apply|drop|save|clear)' "$FLEET" || true)" \
  "G4 机制脚本只读 stash（无 push/pop/apply/drop/save/clear ⇒ 闸门绝不自行改写滞留事实）"

t4_exit
