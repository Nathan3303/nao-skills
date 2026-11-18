#!/usr/bin/env bash
# 用例 37 —— close 裸名解析的「仓来源」（Issue #146 · T551）
#
# 判据来源：docs/reports/146-arch-lite.md（§二 数据通道 / §四 五态判据 / §五 先红后绿 / §六 禁改区）
# 被测对象：.agents/scripts/nao-fleet.sh
#   · 新增 `intercom_cwds_for <name> [anchor]`（0..N 行；复用 _INTERCOM_JSON 缓存，零新增探针）
#   · cmd_close 裸名分支：仓来源由「名册首命中」改为「调用方锚 + 三态决策」
#   · 采用候选名后的 repo 复核：该名唯一 cwd ⇒ 采用 / >1 die / 0 保留现值
#
# 缺陷类（现场复刻 · Issue #146）：裸名 close 用「名册首命中」定仓 ⇒ 跨仓同名时本仓目标被改指他仓
#   ⇒ liveness / 忙闲 / 回收全链落到他仓（本仓在跑的会话被误拒，或他仓 pane 被误回收）。
#
# 断言编号 ↔ 依据（五态每态必有断言，每态必 PASS 或 SKIP，禁 FAIL、禁静默通过）：
#   a  无同名          ⇒ h=0 → 锚 → ⑤「未运行（无需回收）」rc=0（不过度矫正为失败）
#   b  仅本仓 1 条      ⇒ h=1 → 回收本仓（`@` 后字段 = 本仓物理路径 + 本仓 pane 消失 + 探针调用 = 1）
#   b2 仅本仓 1 条·子目录 ⇒ 锚 = git toplevel（物理归一 + 「toplevel 是 cwd 祖先」判据）
#   c  仅他仓 1 条      ⇒ h=0 → ④ 全 session 唯一同 core → 采用唯一 cwd ⇒ 他仓 pane 消失、本仓零动作
#   d  两仓各 1 条      ⇒ 锚过滤后只认本仓（他仓条目排首也不得把目标带跑）
#   d2 本仓 2 条        ⇒ die 列全部候选 cwd + 零回收 + 无「未运行」+ **不**指路「全名」（同仓同名无区分力）
#   d3 本仓 0 + 他仓 2 条 ⇒ 采用候选时按名计数 >1 ⇒ die 列全部候选 + 零回收 + 无「未运行」
#   e  名册不可用        ⇒ 不过滤 / 不判并列：rc 与 stdout 与既有基线（cases/13 ⑥）逐字一致
# 负控五向（真跑变异副本，每向点名对应红点）：过滤写空 · 过滤用 `$repo`（循环） · `>1` 取首条 ·
#   删回落档 · `roster_ok=0` 当 die。
#
# 夹具 hermetic（BR6）：
#   · 假名册探针（`NAO_QA_FAKE_ROSTER`）**pretty-print** —— 名册解析是逐行 awk（紧凑 JSON 会把多条目
#     折叠成一条，让「两条同名」这类判据悄悄退化）；另带探针调用计数文件（机械旁证：每 close ≤1 次）。
#   · 两仓 `fx37-a`（= 机制包夹具根 = git 仓 = close 的调用方 cwd）/ `fx37-b`（他仓，仅作 pane cwd）。
#   · 会话名一律唯一派生（含 `$$`），**禁用 `pm` 等宿主真名**（防 #145 回潮：宿主名册里恰有同名会话）。
#   · pane 一律走 `be_*` 门面（tmux = 隔离 socket / herdr = 私有根 + 确定性替身），不建真 server 之外的场。
#   · 夹具缓存根**不得落在任何 git 仓内**（否则 toplevel 锚会把「他仓」拉回本仓 ⇒ 判据假绿）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node
BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法"; t4_exit; }
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH

# 前置：夹具缓存根不在任何 git 仓内（与 cases/19 同一条纪律；不满足则 toplevel 锚会污染判据）
if command -v git >/dev/null 2>&1; then
  t4_assert_eq "" "$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)" \
    "前提：夹具缓存根不在任何 git 仓内（否则 toplevel 锚把「他仓」拉回本仓）"
fi

LAB="$T4_CACHE_DIR/lab37-$$"
RA="$LAB/fx37-a"                      # 本仓：机制包夹具根 + git 仓 + close 的调用方 cwd
RB="$LAB/fx37-b"                      # 他仓：只作 pane 的 cwd（不需要 .agents）
T37="T4C37$$"                         # 唯一任务编号（`--task` 合法字符集）
CORE="qa-$T37"                        # 裸名（legacy 无 scope 形态）
LFLEET="f37a"                         # 本仓 fleet（.agents/fleet-scope 给出，避免默认 slug 漂移）
LSCOPED="$CORE@$LFLEET"               # 本仓带 scope 的会话名
OSCOPED="$CORE@f37b"                  # 他仓带 scope 的会话名
PROBE_CNT="$LAB/probe-count.txt"
NONE_MD="$RA/.none.md"                # 不存在 ⇒ tasks-state 闸门记 nofile（不污染本题证据）

mkdir -p "$LAB" "$RA" "$RB" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$RA/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
#   · 计数文件路径**烘进探针源码**（`NAO_*` 由 be_clean_unset_args 的「单源全集净化」清掉，未经
#     keep 名单的 NAO_* 传不进子进程 ⇒ 不能靠 env 传）。它只证明 `intercom_list_json` 每命令 ≤1 次。
cat > "$RA/.agents/scripts/intercom-probe.mts" <<JS
// T4 case37 hermetic roster fixture（只读 env；不接触真实 pi-intercom 名册）
// pretty-print 是**判据前提**：nao-fleet 的名册解析逐行读 "name"/"cwd"（紧凑 JSON 会折叠成一条）。
import { appendFileSync } from "node:fs";
try { appendFileSync("$PROBE_CNT", "probe\\n"); } catch (e) { /* 计数非判据 */ }
const raw = process.env.NAO_QA_FAKE_ROSTER || "[]";
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(raw) }, null, 2));
JS
printf '%s\n' "$LFLEET" > "$RA/.agents/fleet-scope"

if command -v git >/dev/null 2>&1; then
  git init -q "$RA" >/dev/null 2>&1 || t4_bad "夹具：git init $RA 失败"
fi
PRA="$(cd "$RA" && pwd -P)"
PRB="$(cd "$RB" && pwd -P)"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab37" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }

w37_exit_trap() {
  local rc=$?
  be_teardown >/dev/null 2>&1 || true
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap w37_exit_trap EXIT

# ---------------------------------------------------------------- 夹具原语
# 名册条目（字段顺序 = name,id,status,cwd —— 名册解析逐行，name 必须在 cwd 之前）
rent() { # <会话名> <cwd> [status]
  printf '{"name":"%s","id":"%s","status":"%s","cwd":"%s"}' "$1" "$1" "${3:-idle}" "$2"
}
roster() { # <条目...> → JSON 数组（他仓在前由调用方决定）
  local out="" e
  for e in "$@"; do out="${out:+$out,}$e"; done
  printf '[%s]' "$out"
}

stage37() { # <cwd> <会话名> → pane_id（身份面就位后输出；失败 rc≠0）
  local cwd="$1" nm="$2" p
  p="$(be_new_pane "$cwd")" || return 1
  be_fixture_session "$p" "$nm" "$(basename "$cwd")" >/dev/null || return 1
  printf '%s' "$p"
}
kill37() { local p; for p in "$@"; do [ -n "$p" ] && be_kill_pane "$p"; done; return 0; }

# 跑生产脚本（**唯一**入口 = be_run_fleet：后端句柄 + 环境净化单点派生）
#   FLEET_SCRIPT（可选）= 变异副本路径；其余形参 = fleet 参数
FLEET_SCRIPT=""
run37() { # <cwd> <roster-json|-> [fleet 参数...]
  local cwd="$1" ros="$2"; shift 2
  : > "$PROBE_CNT"
  if [ "$ros" = "-" ]; then
    # 名册**不可用**：假探针收到非法 JSON ⇒ JSON.parse 抛错 ⇒ 探针非 0 退出 ⇒ intercom_list_json 失败
    NAO_QA_FAKE_ROSTER='not-json{' \
      NAO_SKILLS="$RA" NAO_TASKS_STATE="$NONE_MD" BE_FLEET_SCRIPT="${FLEET_SCRIPT:-$RA/.agents/scripts/nao-fleet.sh}" \
      be_run_fleet "$cwd" close "$@"
  else
    NAO_QA_FAKE_ROSTER="$ros" \
      NAO_SKILLS="$RA" NAO_TASKS_STATE="$NONE_MD" BE_FLEET_SCRIPT="${FLEET_SCRIPT:-$RA/.agents/scripts/nao-fleet.sh}" \
      be_run_fleet "$cwd" close "$@"
  fi
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT_ANSI"; T4_ERR="$BE_ERR_ANSI"; T4_ALL="$T4_OUT"$'\n'"$T4_ERR"
}

# `已回收 <名>（…）@ <仓>` 行的 `@` 后字段（作用域 = 该单字段）
at_field() { printf '%s\n' "$1" | grep -F '已回收' | sed -n 's/.*@ //p' | head -1; }
alive37() { local n=0 p; for p in "$@"; do be_pane_alive "$p" && n=$((n + 1)); done; printf '%s' "$n"; }
probe_calls() { grep -c . "$PROBE_CNT" 2>/dev/null || true; }

# ---- 各态的**单一尺子**（正控与负控共用；返回 GREEN 或 RED:<原因>）----
v_reclaim() { # <本仓期望@> <目标 pane> [他仓 pane（应存活）]
  local want="$1" pane="$2" other="${3:-}" a
  [ "$T4_RC" = "0" ] || { printf 'RED:rc=%s' "$T4_RC"; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:误报未运行'; return; }
  grep -qF '目标歧义' <<< "$T4_ALL" && { printf 'RED:误报歧义'; return; }
  be_pane_alive "$pane" && { printf 'RED:目标 pane 仍在'; return; }
  [ -z "$other" ] || be_pane_alive "$other" || { printf 'RED:他仓 pane 被误杀'; return; }
  a="$(at_field "$T4_OUT")"
  [ "$a" = "$want" ] || { printf 'RED:@=%s（期望 %s）' "${a:-<空>}" "$want"; return; }
  printf 'GREEN'
}
v_ambiguous() { # <期望出现的 cwd> <pane...>（全部应存活）
  local want="$1"; shift
  local alive
  [ "$T4_RC" != "0" ] || { printf 'RED:rc=0（并列未拒）'; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:报「未运行」'; return; }
  grep -qF 'close 目标歧义' <<< "$T4_ALL" || { printf 'RED:无「close 目标歧义」'; return; }
  grep -qF "$CORE" <<< "$T4_ALL" || { printf 'RED:文案未含 core 名'; return; }
  grep -qF "$want" <<< "$T4_ALL" || { printf 'RED:文案未列候选 cwd（%s）' "$want"; return; }
  grep -qF '人工核对' <<< "$T4_ALL" || { printf 'RED:文案无人工核对指路'; return; }
  grep -qF '用全名' <<< "$T4_ALL" && { printf 'RED:对同名候选指路「用全名」（无区分力）'; return; }
  alive="$(alive37 "$@")"
  [ "$alive" = "$#" ] || { printf 'RED:并列时发生了回收（%s/%s 存活）' "$alive" "$#"; return; }
  printf 'GREEN'
}
v_offline_none() { # 与 cases/13 ⑥ 基线逐字一致（rc=0 + 「未启用 tasks-state」+「未运行」两行）
  local want
  want="$(printf '[fleet] 未启用 %s（跳过状态闸门）\n[fleet] %s 未运行（无需回收）' "$NONE_MD" "$CORE")"
  [ "$T4_RC" = "0" ] || { printf 'RED:rc=%s' "$T4_RC"; return; }
  [ "$T4_OUT" = "$want" ] || { printf 'RED:stdout 与基线不一致（实际=%s）' "${T4_OUT//$'\n'/ | }"; return; }
  grep -qF '目标歧义' <<< "$T4_ALL" && { printf 'RED:误报歧义'; return; }
  printf 'GREEN'
}
t4_expect_red() { # <verdict> <label>
  case "${1-}" in
    RED*) t4_ok "$2（负控命中：$1）" ;;
    *)    t4_bad "$2（负控未命中：期望 RED，实际 ${1:-<空>}）" ;;
  esac
}

# ---------------------------------------------------------------- 能力门：名册探针（tsx）
PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
tsx_ok=""
if [ -f "$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs" ] && command -v node >/dev/null 2>&1; then tsx_ok=1; fi

if [ "$tsx_ok" != "1" ]; then
  # 名册整体不可用 ⇒ (a)–(d3) 与五向负控全部退化为 e 态。**只跑 e**，其余显式降级（不静默通过）。
  t4_degrade "缺 tsx / node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ a–d3 与五向负控未执行；e 态照跑（BR7）"
  run37 "$RA" - --task "$T37" qa
  t4_assert_eq "GREEN" "$(v_offline_none)" "e 名册不可用：rc/stdout 与基线（cases/13 ⑥）逐字一致"
  t4_exit
fi

# ================================================================ a 无同名
# 名册里有别的会话（证明「过滤不是靠空名册」），但没有该 core 的任何候选。
run37 "$RA" "$(roster "$(rent "rd-be-$T37" "$PRB")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_offline_none)" "a 无同名（名册非空但无该 core）：h=0 → 锚 → 「未运行」rc=0"
t4_assert_eq "1" "$(probe_calls)" "a 机械旁证：每次 close 的名册探针实际调用 = 1（_INTERCOM_JSON 缓存）"

# ================================================================ b 仅本仓 1 条（legacy 裸名）
P_B="$(stage37 "$RA" "$CORE")" || t4_bad "b 夹具：本仓 pane 建立失败"
run37 "$RA" "$(roster "$(rent "$CORE" "$PRA")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_reclaim "$PRA" "$P_B")" "b 仅本仓 1：h=1 → 回收本仓（@ = 本仓物理路径 · pane 消失 · 无误报）"
t4_assert_eq "1" "$(probe_calls)" "b 机械旁证：每次 close 的名册探针实际调用 = 1（锚过滤不新增 probe）"
kill37 "$P_B"

# ================================================================ b2 仅本仓 1 条 · 从子目录运行
# 锚必须物理归一到 git toplevel（cwd = <本仓>/.agents ⇒ 锚 = <本仓>），否则「本仓条目看不见」⇒ 假「未运行」。
P_B2="$(stage37 "$RA" "$CORE")" || t4_bad "b2 夹具：本仓 pane 建立失败"
run37 "$RA/.agents" "$(roster "$(rent "$CORE" "$PRA")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_reclaim "$PRA" "$P_B2")" "b2 从子目录运行：锚 = 物理 toplevel（祖先判据）⇒ 仍回收本仓"
kill37 "$P_B2"

# ================================================================ c 仅他仓 1 条（legacy 裸名）
# D1 拍板：跨仓「唯一回落」必须保留（收紧会破 cases/09 AC3 的跨仓 close）。
P_C="$(stage37 "$RB" "$CORE")" || t4_bad "c 夹具：他仓 pane 建立失败"
run37 "$RA" "$(roster "$(rent "$CORE" "$PRB")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_reclaim "$PRB" "$P_C")"   "c 仅他仓 1（legacy 裸名）：h=0 → ④ 全 session 唯一同 core → 采用他仓唯一 cwd ⇒ 他仓 pane 消失"
kill37 "$P_C"

# ================================================================ c2 仅他仓 1 条（带 scope 候选）
P_C2="$(stage37 "$RB" "$OSCOPED")" || t4_bad "c2 夹具：他仓 pane 建立失败"
run37 "$RA" "$(roster "$(rent "$OSCOPED" "$PRB")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_reclaim "$PRB" "$P_C2")" \
  "c2 仅他仓 1（带 scope）：采用唯一 scoped 候选并按其唯一 cwd 校正 repo ⇒ 他仓 pane 消失"
t4_assert_contains "$T4_OUT" "已回收 $OSCOPED" "c2 作用域：回收行的会话名 = 名册里那条带 scope 的名字"
kill37 "$P_C2"

# ================================================================ d 两仓各 1 条（他仓条目排首）
# 名册顺序固定「他仓在前」⇒ 旧实现（首命中）必选他仓；锚过滤后只认本仓。
P_DL="$(stage37 "$RA" "$LSCOPED")" || t4_bad "d 夹具：本仓 pane 建立失败"
P_DO="$(stage37 "$RB" "$CORE")"    || t4_bad "d 夹具：他仓 pane 建立失败"
run37 "$RA" "$(roster "$(rent "$CORE" "$PRB")" "$(rent "$LSCOPED" "$PRA")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_reclaim "$PRA" "$P_DL" "$P_DO")" \
  "d 两仓各 1（他仓条目排首）：只回收本仓，他仓 pane 存活（作用域：pane 存活 + @ 字段）"
kill37 "$P_DL" "$P_DO"

# ================================================================ d2 本仓 2 条（并列）
P_D2A="$(stage37 "$RA" "$CORE")" || t4_bad "d2 夹具：本仓 pane#1 建立失败"
P_D2B="$(stage37 "$RA" "$CORE")" || t4_bad "d2 夹具：本仓 pane#2 建立失败"
run37 "$RA" "$(roster "$(rent "$CORE" "$PRA")" "$(rent "$CORE" "$PRA")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_ambiguous "$PRA" "$P_D2A" "$P_D2B")" \
  "d2 本仓 2 条：die 列全部候选 cwd + 零回收 + 无「未运行」+ 不指路「全名」"
kill37 "$P_D2A" "$P_D2B"

# ================================================================ d3 本仓 0 + 他仓 2 条
# 采用候选时「该名唯一 cwd」判据必须挡住：否则按名回收他仓其中一个 ⇒ 静默误杀。
P_D3A="$(stage37 "$RB" "$CORE")" || t4_bad "d3 夹具：他仓 pane#1 建立失败"
P_D3B="$(stage37 "$RB" "$CORE")" || t4_bad "d3 夹具：他仓 pane#2 建立失败"
run37 "$RA" "$(roster "$(rent "$CORE" "$PRB")" "$(rent "$CORE" "$PRB")")" --task "$T37" qa
t4_assert_eq "GREEN" "$(v_ambiguous "$PRB" "$P_D3A" "$P_D3B")" \
  "d3 本仓 0 + 他仓 2 条：die 列全部候选 + 零回收（禁按名取一条误杀）"
kill37 "$P_D3A" "$P_D3B"

# ================================================================ e 名册不可用
# 不过滤、不判并列：rc 与 stdout 与基线（cases/13 ⑥）逐字一致（禁「当 die」/禁走唯一回落）。
run37 "$RA" - --task "$T37" qa
t4_assert_eq "GREEN" "$(v_offline_none)" "e 名册不可用：rc/stdout 与基线（cases/13 ⑥）逐字一致"

# ================================================================ 负控五向（真跑变异副本）
FLEET_SRC="$RA/.agents/scripts/nao-fleet.sh"
mut37() { # <文件> <定位串（须唯一）> <替换整行> → 0 = 已应用且定位串消失
  local f="$1" pat="$2" repl="$3" ln
  ln="$(grep -nF -- "$pat" "$f" | head -1 | cut -d: -f1)"
  [ -n "$ln" ] || return 1
  awk -v n="$ln" -v r="$repl" 'NR==n { print r; next } { print }' "$f" > "$f.new" || return 1
  mv "$f.new" "$f" || return 1
  ! grep -qF -- "$pat" "$f"
}
mut_new() { # <编号> → 变异副本路径
  local d="$LAB/mut37-$1.sh"
  cp "$FLEET_SRC" "$d" && printf '%s' "$d"
}

# ① 过滤写空：锚过滤恒拒（h 恒 0）⇒ (d2) 的「本仓并列」判据必消失，退化成「按名回收」（负控红点）
#    负控用的 d2 变体 = 名册 2 条同 cwd + **实存 1 条 pane**（陈旧条目形态）：并列仍必须零回收，
#    于是「判据消失 ⇒ 那条 pane 被回收」在两后端同形可判（不再依赖后端各自的次生防御）。
MUT="$(mut_new 1)" && mut37 "$MUT" 'repo_contains_path "$abs" "$(nao_phys_path "$c")" || continue' '    continue' \
  || t4_bad "负控① 变异未应用（实现写法已变：锚过滤谓词）"
P_M1="$(stage37 "$RA" "$CORE")"
FLEET_SCRIPT="$MUT" run37 "$RA" "$(roster "$(rent "$CORE" "$PRA")" "$(rent "$CORE" "$PRA")")" --task "$T37" qa
t4_expect_red "$(v_ambiguous "$PRA" "$P_M1")" "负控① 过滤写空 ⇒ (d2 变体) 必红（红点：并列仍回收了那条 pane）"
kill37 "$P_M1"

# ② 过滤用 `$repo`（循环依赖）：锚取自名册首命中 ⇒ (d) 被带到他仓（红点：本仓目标被改指他仓 / 误报歧义）
MUT="$(mut_new 2)" && mut37 "$MUT" 'anchor="$(_close_anchor)"' \
  '      anchor="$(nao_phys_path "$(intercom_cwd_for "$base_name")")"' \
  || t4_bad "负控② 变异未应用（实现写法已变：锚来源行）"
P_M2L="$(stage37 "$RA" "$LSCOPED")"; P_M2O="$(stage37 "$RB" "$CORE")"
FLEET_SCRIPT="$MUT" run37 "$RA" "$(roster "$(rent "$CORE" "$PRB")" "$(rent "$LSCOPED" "$PRA")")" --task "$T37" qa
t4_expect_red "$(v_reclaim "$PRA" "$P_M2L" "$P_M2O")" "负控② 过滤用 \$repo（循环）⇒ (d) 必红（红点：本仓目标被带跑）"
kill37 "$P_M2L" "$P_M2O"

# ③ `>1` 取首条：并列改取第一条 ⇒ (d2) 不再 die（红点：零回收被破坏 / 歧义判据消失）
MUT="$(mut_new 3)" && mut37 "$MUT" 'die "close 目标歧义：$base_name 在本仓锚（$anchor）内有' \
  '        repo="${name_cwds[0]}"' \
  || t4_bad "负控③ 变异未应用（实现写法已变：h>1 的 die 行）"
P_M3="$(stage37 "$RA" "$CORE")"
FLEET_SCRIPT="$MUT" run37 "$RA" "$(roster "$(rent "$CORE" "$PRA")" "$(rent "$CORE" "$PRA")")" --task "$T37" qa
t4_expect_red "$(v_ambiguous "$PRA" "$P_M3")" "负控③ >1 取首条 ⇒ (d2 变体) 必红（红点：并列未拒/那条 pane 被回收）"
kill37 "$P_M3"

# ④ 删回落档：去掉「全 session 唯一同 core」⇒ (d3) 的「按名唯一 cwd」复核整条消失
#    ⑤ 用裸名直接按名回收 ⇒ 他仓两条同名里的任意一条被静默误杀（红点：零回收被破坏 / 无歧义判据）。
#    注：负控绑定 d3 而非 (c) —— (c) 的候选名 == 裸名，⑤ 按名仍能定位同一个 pane（实测咬不动，如实记录）。
MUT="$(mut_new 4)" && mut37 "$MUT" 'mapfile -t same_core < <(fleet_same_core_candidates "$core")' \
  '        same_core=()' \
  || t4_bad "负控④ 变异未应用（实现写法已变：④ 回落档）"
P_M4A="$(stage37 "$RB" "$CORE")"; P_M4B="$(stage37 "$RB" "$CORE")"
FLEET_SCRIPT="$MUT" run37 "$RA" "$(roster "$(rent "$CORE" "$PRB")" "$(rent "$CORE" "$PRB")")" --task "$T37" qa
t4_expect_red "$(v_ambiguous "$PRB" "$P_M4A" "$P_M4B")" "负控④ 删回落档 ⇒ (d3) 必红（红点：并列未拒/按名误杀一条）"
kill37 "$P_M4A" "$P_M4B"

# ⑤ `roster_ok=0` 当 die：名册不可用不再走「不过滤」⇒ (e) 必红（红点：rc≠0，破坏幂等基线）
MUT="$(mut_new 5)" && mut37 "$MUT" '    repo="$fallback_repo"' \
  '    [[ "$roster_ok" == "1" ]] || die "close 中止：名册不可用（负控变异）"' \
  || t4_bad "负控⑤ 变异未应用（实现写法已变：名册不可用时的 repo 赋值行）"
FLEET_SCRIPT="$MUT" run37 "$RA" - --task "$T37" qa
t4_expect_red "$(v_offline_none)" "负控⑤ roster_ok=0 当 die ⇒ (e) 必红（红点：rc≠0 / stdout 偏离基线）"

t4_exit
