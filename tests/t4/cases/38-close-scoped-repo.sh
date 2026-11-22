#!/usr/bin/env bash
# 用例 38 —— close **全名**（`<core>@<fleet>`）的仓来源（Issue #151 · T552）
#
# 判据来源：docs/reports/151-lite-spec.md（§二 数据通道 / §三 八态判据 / §四 先红后绿 / §五 禁改区）
# 被测对象：.agents/scripts/nao-fleet.sh 的全名分支（`if [[ -n "$p_scope" ]]`）
#   · 仓来源由「名册首命中」（旧）+「按仓复核」（同义反复）改为**双键三态**：
#     全名字符串本身即 `core@fleet` ⇒ `intercom_cwds_for "$name"`（不传 anchor）0..N 行
#     h=1 采用 / h>1 die 列全部候选 / h=0 保留回落；名册不可用 ⇒ 不判并列（逐字等价）。
#
# 缺陷类（现场复刻 · Issue #151）：同一 `<core>@<fleet>` 在两个仓并存时，旧实现取**首命中**定仓
#   ⇒ 忙闲 / liveness 按错仓过滤（错仓 ⇒ 读不到忙闲 ⇒ 误杀在跑 turn；或按错仓报「未运行」）。
#
# 断言编号 ↔ 依据（每态必 PASS；后端**判别力**不可达时用 t4_note backend-gate 点名，不静默）：
#   a  唯一·本仓          ⇒ h=1 采用本仓 cwd（rc=0 · pane 消失 · @=本仓 · 探针调用=1）
#   b  唯一·他仓（AC3）    ⇒ h=1 **跨仓照旧回收**（rc=0 · 他仓 pane 消失 · @=他仓）
#   b3 唯一·他仓 + status=working ⇒ **不退化断言**：忙闲第二信号按**他仓**命中 ⇒ 拒绝（结果层）
#   a2 唯一·本仓 + 名册在线无 pane ⇒ 结果层 rc≠0 且不谎报「未运行」；文案 `cwd=<本仓>` 只作辅助
#   c  多命中·都在他仓    ⇒ h>1 die 列全部候选 + 零回收 + 不指路「用全名」
#   d  多命中·跨仓 1+1    ⇒ h>1 die（**禁**先按调用方仓过滤：过滤会把并列静默收敛成本仓 1 条）
#   g1 同 name 同 cwd ×2（1 个 pane）⇒ 按物理路径去重后唯一 ⇒ 采用并回收（rc=0；同仓陈旧重复条目不当歧义）
#   g2 同 name 同 cwd ×2（2 个 pane）⇒ 仓层已去重；**句柄层**两后端结论不同（tmux 收 1 条 / herdr「>1 label ⇒ 不猜」拒；
#      **herdr 判据必须绑拒绝理由文本**「同名 label 命中 2 个 pane」，禁「任何拒绝都吃绿」——由负控⑦ 反证）
#   m  混合态（PRB, PRB, PRC）⇒ 去重后 2 个路径 ⇒ 仍 die，候选只列去重后路径，文案点名「名册共 3 条记录」
#   e  0 命中·裸名在跑    ⇒ h=0 保留回落 ⇒ 「未运行」rc=0 · 裸名 pane 存活（兼容面，不猜）
#   f  名册不可用         ⇒ 不判并列：stdout 与既有基线逐字一致
#
# 先红基线（§四）：`T38_FLEET_SCRIPT=<旧脚本>` 跑本用例；旧脚本 = `git show <sha>:.agents/scripts/nao-fleet.sh`。
#   旧脚本（首命中）上 c/d 必红 —— 但**红点的成因按后端不同，别读成同一件事**：
#     · tmux：rc=0（首命中照旧回收）—— 这才是「h>1 未拒」的直接证据。
#     · herdr：仅文案红（无「close 目标歧义」），**因为 pane 层「同名 label 命中 2 个 pane ⇒ 不猜」先拒了**
#       ⇒ herdr 的 c/d 红点**不是 h>1 的独立证据**（herdr 侧 h>1 的独立证据由负控①承担）。
#       QA 补测：并列但只剩 1 个存活 pane 时，旧 herdr 会静默回收（同一缺陷的另一面）。
#
# 夹具 hermetic（沿用 cases/37 三件套）：
#   · 假名册探针（`NAO_QA_FAKE_ROSTER`）pretty-print（名册解析逐行 awk，紧凑 JSON 会折叠条目）
#     + 探针调用计数文件（机械旁证：每命令名册探针 ≤1 次）。
#   · 三仓 `fx38-a`（本仓 = git 仓 = 调用方 cwd）/ `fx38-b` / `fx38-c`（他仓，只作 pane cwd 与候选 cwd）。
#   · 会话名唯一派生（含 `$$`），**禁用 `pm` 等宿主真名**（防 #145：宿主名册恰有同名 working 会话）。
#   · pane 一律走 `be_*` 门面（tmux = 隔离 socket / herdr = 私有根 + 确定性替身）。
#   · 夹具缓存根**不得落在任何 git 仓内**（否则 toplevel 锚会把「他仓」拉回本仓 ⇒ 判据假绿）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node
BE_NAME="herdr"   # T555：唯一后端（be_backend 已删）
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH

if command -v git >/dev/null 2>&1; then
  t4_assert_eq "" "$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)" \
    "前提：夹具缓存根不在任何 git 仓内（否则 toplevel 锚把「他仓」拉回本仓）"
fi

LAB="$T4_CACHE_DIR/lab38-$$"
RA="$LAB/fx38-a"                      # 本仓：机制包夹具根 + git 仓 + close 的调用方 cwd
RB="$LAB/fx38-b"                      # 他仓 #2
RC="$LAB/fx38-c"                      # 他仓 #3（c 态的第二候选）
T38="T4C38$$"                         # 唯一任务编号
CORE="qa-$T38"                        # 裸名形态（legacy，无 scope）
F_A="f38a"; F_B="f38b"; F_C="f38c"
N_A="$CORE@$F_A"                      # 本仓 fleet 的全名
N_B="$CORE@$F_B"
N_C="$CORE@$F_C"
PROBE_CNT="$LAB/probe-count.txt"
NONE_MD="$RA/.none.md"                # 不存在 ⇒ tasks-state 闸门记 nofile（不污染本题证据）

mkdir -p "$LAB" "$RA" "$RB" "$RC" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$RA/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
cat > "$RA/.agents/scripts/intercom-probe.mts" <<JS
// T4 case38 hermetic roster fixture（只读 env；不接触真实 pi-intercom 名册）
// pretty-print 是**判据前提**：nao-fleet 的名册解析逐行读 "name"/"cwd"（紧凑 JSON 会折叠成一条）。
import { appendFileSync } from "node:fs";
try { appendFileSync("$PROBE_CNT", "probe\\n"); } catch (e) { /* 计数非判据 */ }
const raw = process.env.NAO_QA_FAKE_ROSTER || "[]";
process.stdout.write(JSON.stringify({ ok: true, sessions: JSON.parse(raw) }, null, 2));
JS
printf '%s\n' "$F_A" > "$RA/.agents/fleet-scope"

if command -v git >/dev/null 2>&1; then
  git init -q "$RA" >/dev/null 2>&1 || t4_bad "夹具：git init $RA 失败"
fi
PRA="$(cd "$RA" && pwd -P)"
PRB="$(cd "$RB" && pwd -P)"
PRC="$(cd "$RC" && pwd -P)"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab38" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }

w38_exit_trap() {
  local rc=$?
  be_teardown >/dev/null 2>&1 || true
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap w38_exit_trap EXIT

# ---------------------------------------------------------------- 夹具原语
rent() { # <会话名> <cwd> [status]
  printf '{"name":"%s","id":"%s","status":"%s","cwd":"%s"}' "$1" "$1" "${3:-idle}" "$2"
}
roster() { # <条目...> → JSON 数组（顺序即名册顺序，由调用方决定）
  local out="" e
  for e in "$@"; do out="${out:+$out,}$e"; done
  printf '[%s]' "$out"
}
stage38() { # <cwd> <会话名> → pane_id
  local cwd="$1" nm="$2" p
  p="$(be_new_pane "$cwd")" || return 1
  be_fixture_session "$p" "$nm" "$(basename "$cwd")" >/dev/null || return 1
  printf '%s' "$p"
}
kill38() { local p; for p in "$@"; do [ -n "$p" ] && be_kill_pane "$p"; done; return 0; }

# 跑生产脚本（唯一入口 = be_run_fleet：后端句柄 + 环境净化单点派生）
#   T38_FLEET_SCRIPT（可选）= 先红基线脚本；默认 = 夹具内（= 工作区）副本
run38() { # <cwd> <roster-json|-> <fleet 参数...>
  local cwd="$1" ros="$2"; shift 2
  : > "$PROBE_CNT"
  if [ "$ros" = "-" ]; then
    NAO_QA_FAKE_ROSTER='not-json{' \
      NAO_SKILLS="$RA" NAO_TASKS_STATE="$NONE_MD" BE_FLEET_SCRIPT="${T38_FLEET_SCRIPT:-$RA/.agents/scripts/nao-fleet.sh}" \
      be_run_fleet "$cwd" close "$@"
  else
    NAO_QA_FAKE_ROSTER="$ros" \
      NAO_SKILLS="$RA" NAO_TASKS_STATE="$NONE_MD" BE_FLEET_SCRIPT="${T38_FLEET_SCRIPT:-$RA/.agents/scripts/nao-fleet.sh}" \
      be_run_fleet "$cwd" close "$@"
  fi
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT_ANSI"; T4_ERR="$BE_ERR_ANSI"; T4_ALL="$T4_OUT"$'\n'"$T4_ERR"
}

at_field() { printf '%s\n' "$1" | grep -F '已回收' | sed -n 's/.*@ //p' | head -1; }
alive38() { local n=0 p; for p in "$@"; do be_pane_alive "$p" && n=$((n + 1)); done; printf '%s' "$n"; }
probe_calls() { grep -c . "$PROBE_CNT" 2>/dev/null || true; }

# ---- 各态的**单一尺子**（正控/负控共用；返回 GREEN 或 RED:<原因>）----
v_reclaim() { # <期望@> <目标 pane> [应存活 pane...]
  local want="$1" pane="$2"; shift 2
  local a
  [ "$T4_RC" = "0" ] || { printf 'RED:rc=%s' "$T4_RC"; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:误报未运行'; return; }
  grep -qF '目标歧义' <<< "$T4_ALL" && { printf 'RED:误报歧义'; return; }
  be_pane_alive "$pane" && { printf 'RED:目标 pane 仍在'; return; }
  a="$(at_field "$T4_OUT")"
  [ "$a" = "$want" ] || { printf 'RED:@=%s（期望 %s）' "${a:-<空>}" "$want"; return; }
  if [ "$#" -gt 0 ]; then
    local alive; alive="$(alive38 "$@")"
    [ "$alive" = "$#" ] || { printf 'RED:无关 pane 被误杀（%s/%s 存活）' "$alive" "$#"; return; }
  fi
  printf 'GREEN'
}
v_ambiguous() { # <期望 cwd 列表，用 | 分隔> <应存活 pane...>
  local wants="$1"; shift
  local w alive
  local -a ws=()
  [ "$T4_RC" != "0" ] || { printf 'RED:rc=0（并列未拒）'; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:报「未运行」'; return; }
  grep -qF 'close 目标歧义' <<< "$T4_ALL" || { printf 'RED:无「close 目标歧义」'; return; }
  grep -qF "$N_TGT" <<< "$T4_ALL" || { printf 'RED:文案未含全名'; return; }
  IFS='|' read -r -a ws <<< "$wants"
  for w in "${ws[@]}"; do
    grep -qF "$w" <<< "$T4_ALL" || { printf 'RED:文案未列候选 cwd（%s）' "$w"; return; }
  done
  grep -qF '人工核对' <<< "$T4_ALL" || { printf 'RED:文案无人工核对指路'; return; }
  grep -qF '用全名' <<< "$T4_ALL" && { printf 'RED:对全名目标指路「用全名」（无区分力）'; return; }
  alive="$(alive38 "$@")"
  [ "$alive" = "$#" ] || { printf 'RED:并列时发生了回收（%s/%s 存活）' "$alive" "$#"; return; }
  printf 'GREEN'
}
v_busy_refuse() { # <pane...> —— 不退化断言的结果层：忙闲按仓命中 ⇒ 拒绝且零回收
  local alive
  [ "$T4_RC" != "0" ] || { printf 'RED:rc=0（忙闲信号没读到 ⇒ 退化成回落值）'; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:误报未运行'; return; }
  grep -qF '拒绝回收' <<< "$T4_ALL" || { printf 'RED:无「拒绝回收」'; return; }
  alive="$(alive38 "$@")"
  [ "$alive" = "$#" ] || { printf 'RED:pane 被回收（%s/%s 存活）' "$alive" "$#"; return; }
  printf 'GREEN'
}
v_online_no_pane() { # —— 结果层：非 0 且不谎报「未运行」（与 e 态 rc=0 成对照）
  [ "$T4_RC" != "0" ] || { printf 'RED:rc=0（假设名册在线却报成功）'; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:谎报「未运行（无需回收）」'; return; }
  printf 'GREEN'
}
v_dup_label_refuse() { # <pane...> —— herdr 结构拒绝：**绑理由文本**（禁「任何拒绝都吃绿」）
  local alive
  [ "$T4_RC" != "0" ] || { printf 'RED:rc=0（同名 label 未拒）'; return; }
  grep -qF '未运行（无需回收）' <<< "$T4_ALL" && { printf 'RED:误报未运行'; return; }
  grep -qF '拒绝回收' <<< "$T4_ALL" || { printf 'RED:无「拒绝回收」'; return; }
  grep -qF '同名 label 命中 2 个 pane' <<< "$T4_ALL" \
    || { printf 'RED:拒绝理由未绑定（缺「同名 label 命中 2 个 pane」）'; return; }
  alive="$(alive38 "$@")"
  [ "$alive" = "$#" ] || { printf 'RED:pane 被回收（%s/%s 存活）' "$alive" "$#"; return; }
  printf 'GREEN'
}
v_offline_none() { # 与「旧脚本 + 名册不可用」逐字一致（rc=0 + 未启用 tasks-state + 未运行两行）
  local want
  want="$(printf '[fleet] 未启用 %s（跳过状态闸门）\n[fleet] %s 未运行（无需回收）' "$NONE_MD" "$N_TGT")"
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
  t4_degrade "缺 tsx / node（$PI_AGENT_DIR/npm/node_modules/tsx）⇒ a–f 未执行；仅验 f 的降级形态（BR7）"
  run38 "$RA" - "$N_A"
  t4_assert_eq "GREEN" "$(v_offline_none)" "f 名册不可用（降级）：rc/stdout 与基线逐字一致"
  t4_exit
fi

SRC_MD5="$(md5sum "$RA/.agents/scripts/nao-fleet.sh" | cut -d' ' -f1)"
N_TGT="$N_A"

# ================================================================ a 唯一·本仓
P_A="$(stage38 "$RA" "$N_A")" || t4_bad "a 夹具：本仓 pane 建立失败"
run38 "$RA" "$(roster "$(rent "$N_A" "$PRA")")" "$N_A"
t4_assert_eq "GREEN" "$(v_reclaim "$PRA" "$P_A")" \
  "a 唯一·本仓：h=1 采用本仓 cwd ⇒ rc=0 · pane 消失 · @=本仓（作用域：rc/pane/@ 三项）"
t4_assert_eq "1" "$(probe_calls)" "a 机械旁证：每次 close 的名册探针实际调用 = 1（_INTERCOM_JSON 缓存）"
kill38 "$P_A"

# ================================================================ b 唯一·他仓（cases/09 AC3 不回归）
P_B="$(stage38 "$RB" "$N_B")" || t4_bad "b 夹具：他仓 pane 建立失败"
run38 "$RA" "$(roster "$(rent "$N_B" "$PRB")")" "$N_B"
t4_assert_eq "GREEN" "$(v_reclaim "$PRB" "$P_B")" \
  "b 唯一·他仓：h=1 采用他仓 cwd ⇒ **跨仓照旧回收**（唯一命中不经锚）· rc=0 · @=他仓"
kill38 "$P_B"

# ================================================================ b3 唯一·他仓 + status=working（不退化断言）
# 判据：唯一命中时 h=1 采用值 ≡ 旧「首命中」值 ⇒ 采用本身无行为差；本态证「没退化成回落值」——
#   回落值 = 调用方仓 ⇒ herdr 忙闲第二信号（按仓过滤的名册状态）读不到 ⇒ 误杀在跑 turn。
P_B3="$(stage38 "$RB" "$N_B")" || t4_bad "b3 夹具：他仓 pane 建立失败"
run38 "$RA" "$(roster "$(rent "$N_B" "$PRB" working)")" "$N_B"
t4_assert_eq "GREEN" "$(v_busy_refuse "$P_B3")" \
  "b3 不退化（结果层）：忙闲按**他仓**命中 ⇒ rc≠0 +「拒绝回收」+ pane 存活（退化成回落 ⇒ rc=0 且误杀）"
  t4_assert_contains "$T4_ALL" '名册状态=working' \
    "b3 作用域（文案）：拒绝理由指名册状态=working（herdr 第二信号）"
kill38 "$P_B3"

# ================================================================ a2 唯一·本仓 + 名册在线但无 pane（不退化断言）
# 结果层（主）：rc≠0 且**不**谎报「未运行（无需回收）」；辅助（D7 明示辅助）：tmux warn 的 `cwd=<本仓>`。
run38 "$RA" "$(roster "$(rent "$N_A" "$PRA")")" "$N_A"
t4_assert_eq "GREEN" "$(v_online_no_pane)" \
  "a2 不退化（结果层·主）：名册在线无句柄 ⇒ rc≠0 且不谎报「未运行」（独立成立）"
  t4_note backend-gate "a2 辅助条在 herdr 结构上不可达：herdr 回收 warning 无 cwd 字段（后端无该信号）⇒ 不退化向由 b3-herdr（结果层）+ tmux 辅助条承担"

# ================================================================ c 多命中·都在他仓
# 两条同名同 fleet、cwd 不同（他仓 #2/#3），各配一个 pane ⇒ 必须 die 且**零回收**。
P_C1="$(stage38 "$RB" "$N_B")" || t4_bad "c 夹具：他仓#2 pane 建立失败"
P_C2="$(stage38 "$RC" "$N_B")" || t4_bad "c 夹具：他仓#3 pane 建立失败"
N_TGT="$N_B"
run38 "$RA" "$(roster "$(rent "$N_B" "$PRB")" "$(rent "$N_B" "$PRC")")" "$N_B"
t4_assert_eq "GREEN" "$(v_ambiguous "$PRB|$PRC" "$P_C1" "$P_C2")" \
  "c 多命中·都在他仓：die 列全部候选 cwd + 零回收 + 不指路「用全名」"
kill38 "$P_C1" "$P_C2"

# ================================================================ d 多命中·跨仓 1+1
# 名册顺序固定「他仓在前」⇒ 旧实现（首命中）必选他仓；**禁**先按调用方仓过滤（过滤成 1 ⇒ 静默回收本仓）。
P_D1="$(stage38 "$RA" "$N_A")" || t4_bad "d 夹具：本仓 pane 建立失败"
P_D2="$(stage38 "$RB" "$N_A")" || t4_bad "d 夹具：他仓 pane 建立失败"
N_TGT="$N_A"
run38 "$RA" "$(roster "$(rent "$N_A" "$PRB")" "$(rent "$N_A" "$PRA")")" "$N_A"
t4_assert_eq "GREEN" "$(v_ambiguous "$PRB|$PRA" "$P_D1" "$P_D2")" \
  "d 多命中·跨仓 1+1：die 列 PRA+PRB + 零回收（本仓 pane 存活）"
kill38 "$P_D1" "$P_D2"

# ================================================================ m 混合态（重复条目 + 另一路径）
# 名册 (PRB, PRB, PRC)：去重后仍是 2 个路径 ⇒ 仍 die（真并列）；候选只列去重后路径，不因重复条数虚增。
#   文案必须点名「名册共 3 条记录，含同名同仓重复条目」且**不说「N 个仓」**（同仓重复被说成多仓 = 误导）。
P_MIXA="$(stage38 "$RB" "$N_B")" || t4_bad "m 夹具：他仓#2 pane 建立失败"
P_MIXB="$(stage38 "$RC" "$N_C")" || t4_bad "m 夹具：他仓#3 pane 建立失败"
N_TGT="$N_B"
run38 "$RA" "$(roster "$(rent "$N_B" "$PRB")" "$(rent "$N_B" "$PRB")" "$(rent "$N_B" "$PRC")")" "$N_B"
t4_assert_eq "GREEN" "$(v_ambiguous "$PRB|$PRC" "$P_MIXA" "$P_MIXB")" \
  "m 混合态 (PRB,PRB,PRC)：去重后 2 个路径 ⇒ die 列去重后候选 + 零回收"
t4_assert_contains "$T4_ALL" "名册共 3 条记录" \
  "m 作用域（文案）：点名「名册共 3 条记录，含同名同仓重复条目」"
if grep -qF '个仓' <<< "$T4_ALL"; then
  t4_bad "m：文案不得说「N 个仓」（同一路径重复应说「路径」）"
else
  t4_ok "m 作用域（文案）：不说「N 个仓」（同仓重复 / 同仓不同子目录均只称路径）"
fi
kill38 "$P_MIXA" "$P_MIXB"

# ================================================================ g1 同 name 同 cwd ×2（1 个 pane）
# 陈旧的重复名册条目（同 name 同 cwd）不是「并列候选」：按物理路径去重后唯一 ⇒ 采用并回收（rc=0）。
# 回归点（P2 实指）：去重前该形态会 die（同一条路径列两次、且指路「多仓」= 误导）。
P_G1="$(stage38 "$RA" "$N_A")" || t4_bad "g1 夹具：本仓 pane 建立失败"
N_TGT="$N_A"
run38 "$RA" "$(roster "$(rent "$N_A" "$PRA")" "$(rent "$N_A" "$PRA")")" "$N_A"
t4_assert_eq "GREEN" "$(v_reclaim "$PRA" "$P_G1")" \
  "g1 同 name 同 cwd ×2：去重后唯一 ⇒ 回收本仓（rc=0 · pane 消失 · @=本仓 · 无「歧义」）"
kill38 "$P_G1"

# ================================================================ g2 同 name 同 cwd ×2（2 个 pane）
# 仓层已去重（→ 采用本仓）；**句柄层**两后端结论不同，断言按后端分开，差距点名（禁静默）：
#   tmux：按标题定位到 1 个 pane ⇒ 回收 1 条、另 1 条存活（rc=0）——「去重后不再因陈旧名单误拒」的结果层证据。
#   herdr：同名 label 命中 2 个 pane ⇒「不猜」拒（rc≠0、零回收）—— 后端结构不可判定，非本批退化。
P_G2A="$(stage38 "$RA" "$N_A")" || t4_bad "g2 夹具：pane#1 建立失败"
P_G2B="$(stage38 "$RA" "$N_A")" || t4_bad "g2 夹具：pane#2 建立失败"
N_TGT="$N_A"
run38 "$RA" "$(roster "$(rent "$N_A" "$PRA")" "$(rent "$N_A" "$PRA")")" "$N_A"
  t4_assert_eq "GREEN" "$(v_dup_label_refuse "$P_G2A" "$P_G2B")" \
    "g2 作用域（herdr）：同名 label 2 个 pane ⇒ 不猜（rc≠0 + 零回收 + **理由文本绑定**）"
  t4_note backend-gate "g2 在 herdr 不可判定：同 name 同 cwd 的两个 pane 在 label 层不可区分（后端无 pane-cwd 级歧义消解）⇒ 断言取「不猜」，与 tmux 的「收 1 条」非同形，故分后端写明"
kill38 "$P_G2A" "$P_G2B"


# 名册只有 legacy 裸名（cwd=本仓）+ 其 pane；全名查不到 ⇒ h=0 ⇒ 保留回落 ⇒ 「未运行」rc=0（不猜）。
P_E="$(stage38 "$RA" "$CORE")" || t4_bad "e 夹具：裸名 pane 建立失败"
run38 "$RA" "$(roster "$(rent "$CORE" "$PRA")")" "$N_A"
t4_assert_eq "0" "$T4_RC" "e 0 命中·裸名在跑：h=0 保留回落 ⇒ rc=0（幂等成功，不因 0 命中改 die）"
t4_assert_contains "$T4_OUT" "未运行（无需回收）" "e 作用域（stdout）：报「未运行（无需回收）」"
t4_assert_eq "1" "$(alive38 "$P_E")" "e 作用域（pane 存活）：裸名会话不被全名目标误杀（不同名 ⇒ 不猜）"
grep -qF '目标歧义' <<< "$T4_ALL" && t4_bad "e：0 命中不得报歧义" || t4_ok "e 作用域（无「目标歧义」）"
kill38 "$P_E"

# ================================================================ f 名册不可用
# 不判并列、与改动前逐字等价：rc=0 + 两行基线；禁「当 die」。
N_TGT="$N_A"
run38 "$RA" - "$N_A"
t4_assert_eq "GREEN" "$(v_offline_none)" "f 名册不可用：rc/stdout 与基线逐字一致（不判并列、不派死）"

# ================================================================ 变异负控（挑能咬住的那一层）
FLEET_SRC="$RA/.agents/scripts/nao-fleet.sh"
mut38() { # <文件> <定位串（须唯一）> <替换整行> → 0 = 已应用且定位串消失
  local f="$1" pat="$2" repl="$3" ln
  ln="$(grep -nF -- "$pat" "$f" | head -1 | cut -d: -f1)"
  [ -n "$ln" ] || return 1
  awk -v n="$ln" -v r="$repl" 'NR==n { print r; next } { print }' "$f" > "$f.new" || return 1
  mv "$f.new" "$f" || return 1
  ! grep -qF -- "$pat" "$f"
}
mut38_all() { # <文件> <定位串> <替换整行>（替换**所有**命中行；用于两分支同形的行）
  local f="$1" pat="$2" repl="$3"
  MUT_OLD="$pat" MUT_NEW="$repl" awk '
    { if (index($0, ENVIRON["MUT_OLD"]) > 0) print ENVIRON["MUT_NEW"]; else print }' "$f" > "$f.new" || return 1
  mv "$f.new" "$f" || return 1
  ! grep -qF -- "$pat" "$f"
}
mut_new() { # <编号> → 变异副本路径
  local d="$LAB/mut38-$1.sh"
  cp "$FLEET_SRC" "$d" && printf '%s' "$d"
}
mut_run() { # <变异脚本> <roster> <target> —— 以 cwd=$RA 跑变异副本
  T38_FLEET_SCRIPT="$1" run38 "$RA" "$2" "$3"
}

# ① h>1 取首条（去重后 `== 1` 改 `>= 1`）⇒ (d) 不再 die（红点：rc=0 / 发生回收）
MUT="$(mut_new 1)" && mut38 "$MUT" 'if (( ${#cw_uniq[@]} > 1 )); then' \
  'if false; then' \
  || t4_bad "负控① 变异未应用（实现写法已变：h=1 判定行）"
P_M1A="$(stage38 "$RA" "$N_A")"; P_M1B="$(stage38 "$RB" "$N_B")"
N_TGT="$N_A"
mut_run "$MUT" "$(roster "$(rent "$N_A" "$PRB")" "$(rent "$N_A" "$PRA")")" "$N_A"
t4_expect_red "$(v_ambiguous "$PRB|$PRA" "$P_M1A" "$P_M1B")" \
  "负控① h>1 取首条 ⇒ (d) 必红（红点：并列未拒 / 发生回收）"
kill38 "$P_M1A" "$P_M1B"

# ② 先按调用方仓过滤（多命中被静默收敛成 1 条）⇒ (d) 变成 rc=0 回收本仓 ⇒ 必红
MUT="$(mut_new 2)" && mut38 "$MUT" 'mapfile -t name_cwds < <(intercom_cwds_for "$name")' \
  'mapfile -t name_cwds < <(intercom_cwds_for "$name" "$(nao_phys_path "$PWD")")' \
  || t4_bad "负控② 变异未应用（实现写法已变：双键查询行）"
P_M2A="$(stage38 "$RA" "$N_A")"; P_M2B="$(stage38 "$RB" "$N_B")"
N_TGT="$N_A"
mut_run "$MUT" "$(roster "$(rent "$N_A" "$PRB")" "$(rent "$N_A" "$PRA")")" "$N_A"
t4_expect_red "$(v_ambiguous "$PRB|$PRA" "$P_M2A" "$P_M2B")" \
  "负控② 先按调用方仓过滤 ⇒ (d) 必红（红点：rc=0 / 本仓 pane 被回收）"
kill38 "$P_M2A" "$P_M2B"

# ③ 退化成回落值（h=1 不采用 cwd）⇒ a2 辅助条必红；b3 的结果层咬合只在 herdr（tmux 无按仓忙闲信号）
MUT="$(mut_new 3)" && mut38 "$MUT" '  _TERM_BUSY_WHY="$why"' '  _TERM_BUSY_WHY=""; return 1' \
  || t4_bad "负控③ 变异未应用（实现写法已变：忙闲闸门返回行）"
P_M3="$(stage38 "$RB" "$N_B")"
mut_run "$MUT" "$(roster "$(rent "$N_B" "$PRB" working)")" "$N_B"
  t4_expect_red "$(v_busy_refuse "$P_M3")" \
    "负控③ h=1 不采用 cwd ⇒ b3 不退化向必红（红点：rc=0 / 他仓 pane 被误杀）"
kill38 "$P_M3"

# ④ h=0 改 die（无同名记录时派死）⇒ (e) 破坏幂等基线
MUT="$(mut_new 4)" && mut38 "$MUT" 'mapfile -t name_cwds < <(intercom_cwds_for "$name")' \
  '      mapfile -t name_cwds < <(intercom_cwds_for "${name}"); [[ ${#name_cwds[@]} -gt 0 ]] || die "close 中止：名册无该全名（负控变异）"' \
  || t4_bad "负控④ 变异未应用（实现写法已变：旧形双键查询行）"
P_M4="$(stage38 "$RA" "$CORE")"
T38_FLEET_SCRIPT="$MUT" run38 "$RA" "$(roster "$(rent "$CORE" "$PRA")")" "$N_A"
t4_info "neg4 debug rc=$T4_RC all=[$T4_ALL]"
case "$T4_RC" in
  0) t4_bad "负控④ h=0 改 die 未命中（rc 仍 0，变异无效）" ;;
  *) t4_ok "负控④ h=0 改 die ⇒ (e) rc≠0（红点命中：$T4_RC）" ;;
esac
kill38 "$P_M4"

# ⑤ 名册不可用当 die ⇒ (f) 破坏逐字基线
MUT="$(mut_new 5)" && mut38_all "$MUT" 'if [[ "$roster_ok" == "1" ]]; then' \
  '[[ "$roster_ok" == "1" ]] || die "close 中止：名册不可用（负控变异）"; if true; then' \
  || t4_bad "负控⑤ 变异未应用（实现写法已变：名册可用性闸门行）"
T38_FLEET_SCRIPT="$MUT" run38 "$RA" - "$N_A"
t4_expect_red "$(v_offline_none)" "负控⑤ roster_ok=0 当 die ⇒ (f) 必红（红点：rc≠0 / stdout 偏离基线）"

# ⑥ 删去重守卫（helper 退化为恒等）⇒ (g1) 必红（红点：同仓重复条目被当成并列 ⇒ die 零回收）
#   QA 手工验证过这条红点（「删去重守卫行 ⇒ g 态 FAIL=4」）；本负控把它变成**用例内自动跑**，不靠人工。
MUT="$(mut_new 6)" && mut38 "$MUT" '    [[ -n "${seen[$q]:-}" ]] && continue' \
  '    : # 去重守卫被移除（负控⑥）' \
  || t4_bad "负控⑥ 变异未应用（实现写法已变：去重守卫行）"
P_M6="$(stage38 "$RA" "$N_A")"
N_TGT="$N_A"
mut_run "$MUT" "$(roster "$(rent "$N_A" "$PRA")" "$(rent "$N_A" "$PRA")")" "$N_A"
t4_expect_red "$(v_reclaim "$PRA" "$P_M6")" \
  "负控⑥ 删去重守卫 ⇒ (g1) 必红（红点：同仓重复条目当成并列 ⇒ 不回收）"
kill38 "$P_M6"

# ⑦ g2-herdr 的拒绝理由文本被改写（判定不变：仍拒、仍零回收）⇒ g2 必红
#   为什么必须：g2 旧判据只查「拒绝回收」⇒ 任何拒绝都吃绿（理由换了也绿 = 空转）。
#   变异只换理由字样，不碰「拒/不拒」的分支，红点只能来自「理由绑不住」。
  PAT38_7='拒绝回收 $name：同名 label 命中 $nrows 个 pane'
  HITS38_7="$(grep -cF -- "$PAT38_7" "$FLEET_SRC" || true)"
  if [ "${HITS38_7:-0}" = "0" ]; then
    t4_bad "负控⑦ 锚未命中（实现写法已变：herdr 同名 label 拒绝行）"
  elif [ "$HITS38_7" != "1" ]; then
    t4_bad "负控⑦ 锚不唯一（$HITS38_7 处命中）⇒ 换语叉唯一的锚，不得改断言口径"
  fi
  MUT="$(mut_new 7)" && mut38 "$MUT" "$PAT38_7" \
    '      warn "拒绝回收 $name：同名 label 多命中（负控⑦ 理由改写）⇒ 不猜"' \
    || t4_bad "负控⑦ 变异未应用（锚未命中/不唯一，见上）"
  P_M7A="$(stage38 "$RA" "$N_A")"; P_M7B="$(stage38 "$RA" "$N_A")"
  N_TGT="$N_A"
  mut_run "$MUT" "$(roster "$(rent "$N_A" "$PRA")" "$(rent "$N_A" "$PRA")")" "$N_A"
  t4_expect_red "$(v_dup_label_refuse "$P_M7A" "$P_M7B")" \
    "负控⑦ 拒绝理由文本被改写 ⇒ g2-herdr 必红（断言绑的是理由，不是「任何拒绝」）"
  kill38 "$P_M7A" "$P_M7B"

t4_assert_eq "$SRC_MD5" "$(md5sum "$FLEET_SRC" | cut -d' ' -f1)" \
  "变异只动副本：夹具脚本 md5 与用例开始时逐字节一致（无残留改写）"
t4_exit
