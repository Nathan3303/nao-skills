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
#   f  card 目标 · 子目录调用 ⇒ 锚 = **卡文件所在仓根**（不是 $PWD）⇒ 回收落到仓根（arch §二）
# 负控六向（真跑变异副本，每向点名对应红点）：过滤写空 · 过滤用 `$repo`（循环） · `>1` 取首条 ·
#   删回落档 · `roster_ok=0` 当 die · 卡分支锚回退 `$PWD`（P3-1）。
# 守卫自证（P3-2）：`_close_adopt_repo` 经动态作用域回写调用方 `local repo` ⇒ 函数内一行 fail-loud
#   守卫；本用例**在不声明 repo 的裸 shell 里调该函数必 die**（正/负/去守卫三向自证，不靠「应会红」）。
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

# 变异工具（P3-1/2 与五向负控共用）：只动 $T4_CACHE_DIR/lab 内的副本，仓库脚本 md5 不变
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
v_card_reclaim() { # <卡会话 pane> [他仓见证 pane]（卡目标 + 子目录调用：锚必须是卡所在仓根）
  local pane="$1" other="${2:-}" a
  # 结果层（**主判据**，不读任何实现层文案）：rc / 未运行 / 卡 pane 消失 / 他仓 pane 存活 / @ 字段
  [ "$T4_RC" = "0" ] || { printf 'RED:rc=%s' "$T4_RC"; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:误报未运行'; return; }
  be_pane_alive "$pane" && { printf 'RED:卡会话 pane 仍在'; return; }
  [ -z "$other" ] || be_pane_alive "$other" || { printf 'RED:他仓见证 pane 被误杀'; return; }
  a="$(at_field "$T4_OUT")"
  [ "$a" = "$PRA" ] || { printf 'RED:@=%s（期望仓根 %s）' "${a:-<空>}" "$PRA"; return; }
  # 判定层（**双保险**，非主判据）：锚 = 仓根 ⇒ ③ 同仓 legacy 裸名当场命中。
  grep -qF "close 命中同仓 legacy 裸名 $CARD_CORE" <<< "$T4_OUT" \
    || { printf 'RED:③ 判定层未命中（锚未落到卡所在仓根）'; return; }
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

# ================================================================ f card 目标 · 子目录调用（arch §二）
# 卡目标的锚 = **卡文件所在仓根**（本地事实），**不是** $PWD：从仓的子目录调用也必须落到仓根，
# 否则锚 = 子目录 ⇒ 名册条目（cwd = 仓根）看不见 ⇒ liveness/忙闲按错目录过滤。
mkdir -p "$RA/.agents/prompts" "$RA/sub"
printf -- '---\nrole: fxcard\n---\n# T4 case37 一次性卡（close 只做卡名/路径匹配，正文不进判据）\n' \
  > "$RA/.agents/prompts/fxcard.md"
CARD_CORE="fxcard-$T37"
# 他仓侧两件（判别力加强 · P3-B）：
#   ① 名册里**同名另仓**条目（cwd = 他仓根）：锚退化时 h=0 ⇒ ④ 唯一同 core ⇒ 按名取 cwd 得 2 条
#      ⇒「close 目标歧义」die ⇒ **结果层**（rc）就红，不依赖 ③ 的实现层文案；
#   ② 他仓**见证 pane**（异名 = 不会与卡会话争同名 label）：断言「跨仓不误杀」。
#   ⚠ 为什么不给他仓那条同名会话配 pane：同 label 两 pane 在 herdr 侧本身即歧义（句柄层禁改区
#     会保守拒）⇒ 正确路径也会红；故同名以名册条目表达、pane 存活以异名见证表达。
P_FW="$(stage37 "$RB" "rd-be-$T37")" || t4_bad "f 夹具：他仓见证 pane 建立失败"
P_F="$(stage37 "$RA" "$CARD_CORE")" || t4_bad "f 夹具：卡会话 pane 建立失败"
SRC_MD5="$(md5sum "$RA/.agents/scripts/nao-fleet.sh" | cut -d' ' -f1)"
FROSTER="$(roster "$(rent "$CARD_CORE" "$PRA")" "$(rent "$CARD_CORE" "$PRB")" "$(rent "rd-be-$T37" "$PRB")")"
run37 "$RA/sub" "$FROSTER" --task "$T37" fxcard
t4_assert_eq "GREEN" "$(v_card_reclaim "$P_F" "$P_FW")" \
  "f card 目标 + 子目录调用：rc=0 · @ = 卡所在仓根 · 卡 pane 消失 · 他仓见证 pane 存活 · 无「未运行」"
if be_pane_alive "$P_FW"; then
  t4_ok "f 作用域（他仓 pane 存活）：$P_FW 未被误杀（跨仓不越界）"
else
  t4_bad "f 作用域（他仓 pane 存活）：$P_FW 被他仓回收（跨仓越界）"
fi
kill37 "$P_F"

# 负控⑥（P3-1）：把卡分支锚改回 `$PWD`（未剥/未取卡所在仓）⇒ **先红在结果层**：h=0 ⇒ ④ 按名取 cwd
#   得 2 条 ⇒「close 目标歧义」die（rc≠0 + 零回收）；③「同仓 legacy 裸名」同时消失，但仅作双保险。
MUT="$(mut_new 6)" && mut37 "$MUT" 'anchor="$(nao_phys_path "$fallback_repo")"' \
  '      anchor="$(nao_phys_path "$PWD")"' \
  || t4_bad "负控⑥ 变异未应用（实现写法已变：卡分支锚行）"
P_M6W="$(stage37 "$RB" "rd-be-$T37")"
P_M6="$(stage37 "$RA" "$CARD_CORE")"
FLEET_SCRIPT="$MUT" run37 "$RA/sub" "$FROSTER" --task "$T37" fxcard
t4_expect_red "$(v_card_reclaim "$P_M6" "$P_M6W")" \
  "负控⑥ 卡分支锚回退 \$PWD ⇒ f 必红（**结果层**：h=0 → ④ 按名 2 条 cwd ⇒ 目标歧义 die；先红的是 rc）"
t4_assert_eq "2" "$(alive37 "$P_M6" "$P_M6W")" \
  "负控⑥ 同场景零回收（卡 pane + 他仓见证 pane 均存活 ⇒ 不误杀）"
t4_assert_not_contains "$T4_OUT" "close 命中同仓 legacy 裸名 $CARD_CORE" \
  "负控⑥ 同场景 ③ 也同时红（双保险明细：③ 未命中）"
kill37 "$P_M6" "$P_M6W"
t4_assert_eq "$SRC_MD5" "$(md5sum "$FLEET_SRC" | cut -d' ' -f1)" \
  "负控⑥ 变异只动副本：仓库脚本 md5 与变异前逐字节一致（无残留改写）"

# ================================================================ 负控六向（真跑变异副本）

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

# ================================================================ 守卫自证（P3-2 · 动态作用域回写）
# 为什么要守卫：`_close_adopt_repo` 用 bash 动态作用域回写调用方的 `local repo`；将来在**未声明**
#   `local repo` 的调用点复用 ⇒ 赋值会静默创建全局（无报错、无文案）。守卫 = 函数内首语句
#   `declare -p repo`，不成立即 die。证法**不靠「应会红」**：把 `die` + 该函数抽到裸 shell 里，
#   ① 无 repo 声明 ⇒ 必 die 且点名内部错误；② 有 repo 声明 ⇒ 不 die（守卫不误伤）；③ 副本删掉
#   守卫行 ⇒ ① 翻绿（证明 ① 抓到的是守卫本身，不是别的东西）。
#   子壳里必须 **stub `intercom_cwds_for`**（否则它对未定义命令 ⇒ 0 条 cwd ⇒ repo 恒空，
#   「repo=」这类断言对空值同样吃绿 = 空转断言）；stub 后判据精确到 **repo=/tmp/x**。
adopt_unit() { # <脚本> <模式：bare|local> → 子 shell 的输出 + `rc=<退出码>`（die 是 exit 1，故 rc 必须从进程取）
  local src="$1" mode="$2" prog out rc
  prog="$(
    grep -m1 '^die()' "$src"
    sed -n '/^_close_adopt_repo()/,/^}/p' "$src"
    printf 'intercom_cwds_for() { printf "%%s\\n" /tmp/x; }\n'
    case "$mode" in
      local) printf 'h37() { local repo=""; _close_adopt_repo "qa-x" "1"; printf "repo=%%s\\n" "$repo"; }\nh37\n' ;;
      *)     printf '_close_adopt_repo "qa-x" "1"\n' ;;
    esac
  )"
  out="$(printf '%s\n' "$prog" | bash -s 2>&1)"; rc=$?
  printf '%s\nrc=%s\n' "$out" "$rc"
}
OUT_BARE="$(adopt_unit "$FLEET_SRC" bare)"
t4_assert_contains "$OUT_BARE" "内部错误：_close_adopt_repo 须在声明 local repo 的调用点内调用" \
  "P3-2① 无 repo 声明的调用点 ⇒ 守卫 fail loud 点名内部错误（不是静默造全局）"
t4_assert_contains "$OUT_BARE" "rc=1" "P3-2① 同场景 rc=1（die 生效，不继续回写）"
OUT_LOCAL="$(adopt_unit "$FLEET_SRC" local)"
t4_assert_contains "$OUT_LOCAL" "rc=0" "P3-2② 已声明 local repo 的调用点 ⇒ 守卫不误伤（rc=0）"
# 判据必须**精确到值**：stub 的 cwd 是 /tmp/x ⇒ 回写成功才会出现 repo=/tmp/x
#   （「repo=」对空值同样匹配 = 空转，QA 实测指出并订正）
t4_assert_contains "$OUT_LOCAL" "repo=/tmp/x" "P3-2② 同场景回写值 = stub cwd（repo=/tmp/x；非空值也算绿的空转断言）"
t4_assert_not_contains "$OUT_LOCAL" "内部错误" "P3-2② 同场景无「内部错误」文案"
MUT="$(mut_new 7)" && mut37 "$MUT" 'declare -p repo >/dev/null 2>&1' \
  '    : # 守卫被移除（P3-2 负控）' \
  || t4_bad "P3-2③ 变异未应用（实现写法已变：守卫行）"
OUT_BARE2="$(adopt_unit "$MUT" bare)"
t4_assert_not_contains "$OUT_BARE2" "内部错误" \
  "P3-2③ 删掉守卫行 ⇒ ① 翻绿（证明 ① 抓到的就是这一行守卫，判据非空转）"
t4_assert_contains "$OUT_BARE2" "rc=0" "P3-2③ 同场景退回静默（rc=0 无报错）= 守卫要堵的形态"

# ④ 判据非空转的**反向**证明：副本删掉 `repo="${cw[0]}"` 这一行 ⇒ 回写消失 ⇒ ② 的 `repo=/tmp/x` 必不成立
MUT="$(mut_new 8)" && mut37 "$MUT" 'repo="${cw[0]}"' \
  '  (( ${#cw[@]} == 1 )) && { return 0; }' \
  || t4_bad "P3-2④ 变异未应用（实现写法已变：回写行）"
OUT_LOCAL2="$(adopt_unit "$MUT" local)"
t4_assert_not_contains "$OUT_LOCAL2" "repo=/tmp/x" \
  "P3-2④ 删掉回写行 ⇒ ② 必红（判据非空转；实测 repo= 为空，见回执）"
t4_assert_contains "$OUT_LOCAL2" "repo=" \
  "P3-2④ 同场景仍能打印 repo=（空值）⇒ 证明旧断言「repo=」会被空值吃绿（QA 结论复现）"

t4_exit
