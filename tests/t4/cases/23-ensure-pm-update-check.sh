#!/usr/bin/env bash
# 用例 23 —— `ensure pm` 的下游机制包版本自检（M20261103 · Issue #74 · T548/Issue #140 改「就绪后投递」）
#
# PRD：docs/prds/2026-11-03-ensure-pm-update-check.md（R1–R6）· Issue #140（就绪门假失败）
# 被测对象：.agents/scripts/nao-fleet.sh 的 `spawn_one` / `cmd_ensure` / `NAO_UPDATE_MSG` /
#           `term_deliver`（herdr `agent prompt` · tmux load-buffer + paste-buffer + Enter）
#
# 断言映射（T548 口径）：
#   AC1 默认配置 `ensure pm` rc=0 且摘要「成功 1」（正面判据：自检不再进 argv ⇒ 就绪门不被自检 turn 顶掉）
#   AC2 自检**确实送达并被执行**（三层判据 · 复核 P2-1）：① 投递面 = `agent prompt` rc=0 且 stdout 无
#       `"error":{"code"`；② 执行面 = 投递后 ≤10×100ms 观察到 `agent_status==working` 或 `seq > 基线`；
#       ③ 内容面（辅助）= `agent read --source visible` 命中常量首行（working 期可读）。**禁**用 `--lines`
#       （真机 working 时直接报 `agent_not_idle`；idle 后深度随本轮输出漂移）。负控 = 开关关 2s 内无锚。
#   AC3 `NAO_UPDATE_ON_ENSURE=0` 时 pi 命令行与本缺陷前**逐字等价**（diff 空 + md5 相等）
#   AC4 就绪门七条件语义不放宽（静态：门仍逐条可点名 + 禁 `agent wait`）；投递失败 ⇒ rc 仍 0、不计 SPAWN_FAIL、
#       但必须有默认可见 warn（含 pane + error code）；幂等：已在运行 ⇒ 不二次投递
#   R3 常量六要素齐备（可 grep 自证）· AC7 零网络（fleet 内除常量块外无 npm view/gh/curl/wget）
#
# 夹具纪律（沿用 T4 血训）：
#   - 真 tmux **隔离 socket**（be_init 单点护栏）+ `env -u TMUX -u TMUX_PANE`；herdr 走确定性替身 + 私有 XDG 根
#   - 桩 `pi`（记录 argv 后 `exec -a pi sleep` ⇒ `pane_current_command==pi`，投递等待可满足；绝不拉起真 pi）
#   - 桩 `tmux`（split-window 命令串原样落盘 + 可注入 load-buffer 失败）⇒ 断言取 fleet 交给后端的原始字节
#   - 夹具根不得落在任何 git 仓内；收尾走 lib/be_teardown
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

BE_NAME="herdr"   # T555：唯一后端（be_backend 已删）
FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
BASH_BIN="$(command -v bash)"
REAL_TMUX="${NAO_T23_REAL_TMUX:-$(command -v tmux || true)}"
LAB="$T4_CACHE_DIR/lab23-$$"
BASE="$(basename "$LAB")"   # T547 起会话名恒带 @<fleet>（默认 tier = 目标仓 slug = $LAB basename）
PI_LOG="$LAB/fake-pi.log"
# 「交给后端的原始命令」取证口：tmux = 桩 split-window 落盘 · herdr = 替身的 pane run 落盘
SPLIT_LOG="$LAB/split.log"
ANCHOR='【nao 机制包版本自检'

# ---- 硬护栏（先于一切后端操作）：夹具根不得落 git 仓内 ----
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：夹具根不在任何 git 仓内（后端场护栏由 be_init 负责）"

# ---- 夹具 ----
mkdir -p "$LAB" "$LAB/bin" "$LAB/pi-empty"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
[ -f "$LAB/.pi/settings.json" ] && rm -f "$LAB/.pi/settings.json"

# pi 桩：记录 argv 后以 argv[0]=pi 长驻（投递等待 pane_current_command==pi 需要）
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
{ printf 'cwd=%s\n' "\$PWD"; printf '%q\n' "\$@"; printf 'END\n'; } >> "$PI_LOG"
exec -a pi sleep 900
SH
chmod +x "$LAB/bin/pi"

# tmux 桩：split-window 命令串原样落盘后转发真 tmux；可注入 load-buffer 失败（AC4 失败语义）
cat > "$LAB/bin/tmux" <<'SH'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "split-window" ]; then
  args=("$@")
  printf '%s\n' "${args[${#args[@]}-1]}" >> "$D/../split.log"
fi
if [ "${1:-}" = "load-buffer" ] && [ "${T4_TMUX_FAIL_BUFFER:-0}" = "1" ]; then
  echo "injected load-buffer failure" >&2
  exit 1
fi
exec "${NAO_T23_REAL_TMUX:?}" "$@"
SH
chmod +x "$LAB/bin/tmux"

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab" || { t4_bad "be_init 失败（后端=$BE_NAME）"; t4_exit; }
be_ensure_scene || { t4_bad "be_ensure_scene 失败（后端=$BE_NAME）"; t4_exit; }
CALLER="$(be_caller_pane)"
t4_assert_ne "" "$CALLER" "夹具：调用者 pane 建立（$CALLER；后端=$BE_NAME）"

t523_exit_trap() {
  local rc=$?
  be_teardown >/dev/null 2>&1 || true
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t523_exit_trap EXIT

# ---- 调用封装 ----
export NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty"
export NAO_T23_REAL_TMUX="${REAL_TMUX:-}"
export PATH="$LAB/bin:$PATH"
export T4_HERDR_SPAWN_LOG="$SPLIT_LOG"
# T548 复核：替身的「投递起 turn」默认立即完成（避免污染其他用例的 close 忙闲闸门）；
#   本用例需要稳定观察 working / `--lines` 报 agent_not_idle ⇒ 显式把 turn 拉长到 60s。
export T4_HERDR_PROMPT_TURN_MS=60000
run_fleet() { # <args...> → BE_RC / BE_OUT / BE_ERR（*_ANSI = 去色后版本）
  export NAO_UPDATE_ON_ENSURE="${T23_SWITCH:-1}"   # 开关每次调用现读（块内会切换）
  be_run_fleet "$LAB" "$@"
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT"; T4_ERR="$BE_ERR"
  T4_OUT_ANSI="$BE_OUT_ANSI"; T4_ERR_ANSI="$BE_ERR_ANSI"
}
split_count() { [ -f "$SPLIT_LOG" ] && wc -l < "$SPLIT_LOG" || echo 0; }
new_split() { [ -f "$SPLIT_LOG" ] && sed -n "$(( $1 + 1 )),\$p" "$SPLIT_LOG" || true; }
launch_lines() { grep -cF -- "[$BE_NAME] 已拉起" <<< "$T4_OUT_ANSI" || true; }

# ---- 期望命令行（逐字重建；AC3 基线 = 缺陷前形态：无任何注入段）----
expected_inner() { # <name> <prompt_file>
  printf 'cd %s && export CODEGRAPH_TELEMETRY=0 && exec pi --name %s --append-system-prompt %s' \
    "$(printf %q "$LAB")" "$(printf %q "$1")" "$(printf %q "$2")"
}
expected_wrapped() {
  printf '%s' "$(expected_inner "$1" "$2")"
}
prompt_file_of() {
  local flat; flat="$(printf '%s' "$1" | tr -d '\\')"
  printf '%s' "$flat" | sed -nE 's#.*--append-system-prompt (/tmp/nao-fleet-[^ ]*\.md).*#\1#p'
}
diff_assert() {
  local exp="$1" act="$2" tag="$3" d
  d="$(diff <(printf '%s\n' "$exp") <(printf '%s\n' "$act") 2>&1 || true)"
  if [ -z "$d" ]; then t4_ok "$tag（diff 为空）"; else t4_bad "$tag：diff 非空"; printf '%s\n' "$d" | sed 's/^/    /'; fi
}

# ---- 投递取证面（两后端同锚 / 同判据）----
pane_of() { # <name> → pane_id（tmux：pane_start_command 去掉 %q 转义后按 `--name <名>` 定位）
  be_pane_by_name "$1"; return 0
  local want="$1" p _ c flat
  while IFS=$'\t' read -r p _; do
    [ -n "$p" ] || continue
    c="$(_be_tmux display-message -p -t "$p" '#{pane_start_command}' 2>/dev/null || true)"
    flat="${c//\\/}"
    case "$flat" in
      *"--name $want "*|*"--name $want") printf '%s' "$p"; return 0 ;;
    esac
  done < <(be_panes 2>/dev/null)
  return 0
}
capture_of() { # <pane> → 屏幕文本（tmux capture-pane -p -J / herdr agent read recent-unwrapped）
    # T548 复核 P2-1：AC2 内容面只用 `--source visible`（working 期可读；**禁** `--lines`：真机 working 时直接报 agent_not_idle）
    LC_ALL=C be_herdr "$BE_SESSION" agent read "$1" --source visible 2>/dev/null
}
anchor_count() { grep -oF -- "$ANCHOR" <<< "$1" | wc -l | tr -d ' '; }
STATE=""
[ "$BE_NAME" = "herdr" ] && STATE="$BE_CFGROOT/herdr/sessions/$BE_SESSION/double-state.json"
seq_of() {
  node -e 'const fs=require("fs");const st=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));process.stdout.write(String((st.knobs&&st.knobs.pi_seq)||0))' "$STATE" 2>/dev/null || true
}
delivered_of() { # <pane>
  node -e 'const fs=require("fs");const st=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const p=st.panes&&st.panes[process.argv[2]];process.stdout.write(String(p&&p.delivered?p.delivered.length:0))' "$STATE" "${1:-}" 2>/dev/null || true
}
set_knob() { # <键> <JSON 值>（与 case 29 同口径；只用于 P2-3 七条件负控）
  node -e '
const fs=require("fs");const p=process.argv[1];const k=process.argv[2];const v=JSON.parse(process.argv[3]);
const st=JSON.parse(fs.readFileSync(p,"utf8"));st.knobs=st.knobs||{};st.knobs[k]=v;
fs.writeFileSync(p,JSON.stringify(st));' "$STATE" "$1" "$2" || t4_bad "夹具：旋钮写入失败（$1=$2）"
}
# 执行面证据（herdr）：`agent list` → `status<TAB>seq`（真机权威源；替身同构）
agent_row() { # <pane>
  [ "$BE_NAME" = "herdr" ] || return 0
  LC_ALL=C be_herdr "$BE_SESSION" agent list 2>/dev/null | node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{let j;try{j=JSON.parse(s)}catch(e){process.exit(0)}
const pid=process.argv[1];for(const a of (j.result&&j.result.agents)||[]){if(a.pane_id===pid){process.stdout.write(String(a.agent_status)+"\t"+String(a.state_change_seq));return}}})' "${1:-}" 2>/dev/null || true
}
# T548 复核 P2-1 层②：投递后 ≤10×100ms 同步观察「working 或 seq > 基线」（同一预算，不新增轮询面）
wait_exec_started() { # <pane> <基线 seq> → 0 = 观察到 turn 真起来
  local pane="$1" base="$2" i row st sq
  for ((i = 1; i <= 10; i++)); do
    row="$(agent_row "$pane")"
    st="${row%%$'\t'*}"; sq="${row#*$'\t'}"
    if [ "$st" = "working" ]; then return 0; fi
    if [[ "$sq" =~ ^[0-9]+$ ]] && (( sq > base )); then return 0; fi
    sleep 0.1
  done
  return 1
}
# 负控：<pane> 在 <secs> 秒内不得出现锚（有界轮询，不用裸 sleep 判存在性）
no_anchor_within() { # <pane> <secs> → 0 = 窗口内确实没有
  local pane="$1" lim=$(( ${2:-2} * 10 )) i c
  for ((i = 1; i <= lim; i++)); do
    c="$(anchor_count "$(capture_of "$pane")")"
    (( c == 0 )) || return 1
    sleep 0.1
  done
  return 0
}

# ---- 注入常量：从脚本原样抽出（R3「常量便于 grep 自证」）----
MSG_START="$(grep -n "^NAO_UPDATE_MSG='" "$FLEET" | cut -d: -f1)"
MSG_END="$(awk -v s="${MSG_START:-0}" 'NR>s && /'"'"'[[:space:]]*$/ {print NR; exit}' "$FLEET")"
t4_assert_ne "" "$MSG_START" "R3 注入文本是脚本内常量（\$NAO_UPDATE_MSG 可 grep 定位）"
t4_assert_ne "" "$MSG_END" "R3 常量边界可解析（起始行 ${MSG_START:-?} → 结束行 ${MSG_END:-?}）"
sed -n "${MSG_START:-1},${MSG_END:-1}p" "$FLEET" > "$LAB/msg.sh"
# shellcheck disable=SC1090
MSG="$(. "$LAB/msg.sh" && printf '%s' "$NAO_UPDATE_MSG")"
t4_assert_ne "" "$MSG" "R3 常量可解析为实际文本（$(printf '%s' "$MSG" | wc -c) 字节 / $(printf '%s' "$MSG" | wc -l) 行）"

# ============================================================ R3 六要素（常量本体）
check_msg() { # <子串> <要素标签>
  if printf '%s' "$MSG" | grep -qF -- "$1"; then t4_ok "R3 $2"; else t4_bad "R3 $2（缺：$1）"; fi
}
check_msg ".pi/settings.json" "①读本地 pin"
check_msg "@nathan33/nao-skill" "①pin 包名"
check_msg "npm view @nathan33/nao-skill version" "①远端版本查询"
check_msg "5s" "①5s 超时口径"
check_msg "gh release view" "②有新版取 release 要点"
check_msg "不超过两句" "②要点压成不超过两句"
check_msg "要升吗？" "③一行询问"
check_msg "已是最新" "④降级②已最新"
check_msg "离线或超时" "④降级③离线或超时"
check_msg "未检测到下游 pin" "④降级④无下游 pin"
check_msg "无 gh" "④降级⑤无 gh 只报版本号"
check_msg "未获我同意前不要改任何文件、不要升级" "⑤硬约束句"
check_msg "pi install -l npm:@nathan33/nao-skill@<Y>" "⑥同意后动作 ①"
check_msg "pi update --extensions" "⑥同意后动作 ②"
check_msg "建议重开" "⑥本轮会话仍是旧角色卡提醒"
check_msg "--fetch-timeout=5000" "① 5s 超时可移植（npm 内置参数，不用外部 timeout）"
t4_assert_eq "0" "$(grep -cF -- 'timeout 5 npm view' <<< "$MSG" || true)" \
  "D1 常量不再依赖外部 timeout 命令（macOS 原生无该命令）"
check_msg "若提示安装脚本授权" "⑥授权提示须停下交用户确认（不自行放行）"

# ============================================================ AC7 零网络：常量块外不得出现网络命令
OUTSIDE="$LAB/fleet-outside-msg.sh"
awk -v s="${MSG_START:-0}" -v e="${MSG_END:-0}" 'NR<s || NR>e' "$FLEET" > "$OUTSIDE"
NET_HITS="$(grep -nE 'npm[[:space:]]+view|gh[[:space:]]+release|curl|wget' "$OUTSIDE" || true)"
t4_assert_eq "" "$NET_HITS" "AC7 fleet 内除常量块外无网络/外部命令（npm view / gh release / curl / wget）"
t4_assert_eq "0" "$(grep -cE '^\s*(npm|gh|curl|wget)\b' <<< "$MSG" || true)" \
  "AC7 常量块内也无「行首即命令」形态（只是给 PM 的文本）"

# ============================================================ AC3/AC4 静态面：自检不进 argv + 两通道形态
t4_assert_eq "0" "$(grep -cF -- 'inner+=" -- $(printf %q "$NAO_UPDATE_MSG")"' "$FLEET" || true)" \
  "AC3 静态：spawn_one 不再把自检拼进 pi argv（缺陷根因已移除）"
t4_assert_ge "1" "$(grep -cF -- 'term_deliver "$_TERM_SPAWN_PANE" "$NAO_UPDATE_MSG"' "$FLEET" || true)" \
  "AC2/AC4 静态：投递点唯一 = spawn 成功后（term_deliver）"
t4_assert_ge "1" "$(grep -cF -- 'agent prompt "$pane" "$msg"' "$FLEET" || true)" \
  "AC2 静态：herdr 通道 = agent prompt（自带提交 + bracketed-paste 包裹）"
t4_assert_eq "0" "$(grep -cE 'agent[[:space:]]+prompt.*--wait' "$FLEET" || true)" \
  "AC2 静态：herdr 投递不带 --wait（不把「已投递」耦合到「自检 turn 跑完」）"
t4_assert_ge "1" "$(grep -cF -- 'paste-buffer -p -d -b "$buf" -t "$pane"' "$FLEET" || true)" \
  "AC2 静态：tmux 通道 = paste-buffer -p + 独立 buffer + -d（不动用户粘贴板）"
t4_assert_ge "1" "$(grep -cF -- 'send-keys -t "$pane" Enter' "$FLEET" || true)" \
  "AC2 静态：tmux 通道末尾恰一次键名 Enter"
t4_assert_ge "1" "$(grep -cF -- 'bracket_paste_flag' "$FLEET" || true)" \
  "AC2 静态：tmux bracketed-paste 退化判定面存在（#{bracket_paste_flag}）"
t4_assert_ge "1" "$(grep -cF "\${msg//\$'\\n'/ }" "$FLEET" || true)" \
  "AC2 静态：退化时投递前做形态归一（换行 → 空格；文案单一源不变）"
t4_assert_contains "$(grep -F '版本自检投递失败' "$FLEET" || true)" "不计失败" \
  "AC4 静态：投递失败不计 SPAWN_FAIL（失败语义 = rc 0 + warn）"
t4_assert_eq "0" "$(grep -cE 'agent[[:space:]]+wait' <(grep -vE '^[[:space:]]*#' "$FLEET") || true)" \
  "AC4 静态：就绪门仍禁用 agent wait（七条件语义不放宽）"
for cond in "state_change_seq ≥ 1" "agent_status == idle" "screen_detection_skipped" "agent_session != null"; do
  t4_assert_contains "$(grep -F -- "$cond" "$FLEET" || true)" "$cond" "AC4 静态：就绪门条件仍逐条可点名：$cond"
done
# P2-3：七条件在**就绪探针函数体内**逐条成关（不只存在 warn 文案），且最终是与关系
READY_BODY="$(awk '/^_term_herdr_ready_state\(\)/{f=1} f{print} f&&/^}/{exit}' "$FLEET")"
for cond in '_TR_PANE' '_TR_FG" == "pi' '_TR_ARGV" == "$want' '_TR_SESS" == "1' '_TR_STAT" == "idle' '_TR_SEQ" =~ ^[0-9]+$' '_TR_SKIP" == "1'; do
  t4_assert_contains "$READY_BODY" "$cond" "AC4 静态：就绪探针体内成关：$cond"
done
t4_assert_contains "$READY_BODY" '_TR_SKIP" == "1" ]' \
  "AC4 静态：七条件是 AND（最后一关之后 return 0，无任何支路可短路成功）"

# ============================================================ AC1/AC2 ensure pm（默认开）
BASE_SEQ="$(seq_of)"   # 投递前基线（就绪门只要求 seq≥1；AC2 判 `>` 不判 `==+1`）
BEFORE="$(split_count)"
T23_SWITCH=1
run_fleet ensure --task T1 "pm@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1① ensure pm rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_eq "1" "$(launch_lines)" "AC1① 恰 1 行 [$BE_NAME] 已拉起（三态契约不变）"
t4_assert_contains "$T4_OUT_ANSI" "（成功 1 / 跳过 0 / 失败 0）" "AC1① 摘要「成功 1」（本缺陷的正面判据）"
CMD_PM="$(new_split "$BEFORE" | head -1)"
t4_assert_ne "" "$CMD_PM" "AC1① 捕获到 fleet 交给后端的启动命令串"
PF_PM="$(prompt_file_of "$CMD_PM")"
t4_assert_ne "" "$PF_PM" "AC1① 命令串含 --append-system-prompt 文件（$PF_PM）"
diff_assert "$(expected_wrapped "pm(T1)" "$PF_PM")" "$CMD_PM" \
  "AC3① pm 命令行 = 缺陷前基线（无「 -- 」注入段，逐字）"
t4_assert_eq "0" "$(grep -cF -- ' -- ' <<< "$CMD_PM" || true)" "AC3① pm 命令行无「 -- 」注入段"

PANE_PM="$(pane_of "pm(T1)")"
t4_assert_ne "" "$PANE_PM" "AC2① 定位 pm 会话 pane（$PANE_PM）"
# tmux 桩 pi 不写标题；补写身份，令后续相位 1 的槽位判重与 herdr 同口径（否则 off/140 会落槽位 1）
[ "$BE_NAME" = "tmux" ] && be_set_name "$PANE_PM" "pm(T1)" "$BASE" >/dev/null 2>&1 || true
CAP_PM="$(capture_of "$PANE_PM")"
t4_assert_eq "1" "$(anchor_count "$CAP_PM")" "AC2① 投递文案确实到达会话（回读命中固定锚，恰 1 次）"
  # 层① 投递面：替身记录 delivered=1 且 seq 已 +1（= agent prompt rc=0 且无 error）；
  # 层② 执行面：投递后 ≤10×100ms 观察 working 或 seq > 基线；
  # 层③ 内容面（辅助）：`agent read --source visible` 命中常量首行（上面 CAP_PM）。
  t4_assert_eq "1" "$(delivered_of "$PANE_PM")" "AC2① 层① 投递面：agent prompt 成功恰 1 次（无重复）"
  wait_exec_started "$PANE_PM" "$BASE_SEQ" \
    && t4_ok "AC2① 层② 执行面：≤10×100ms 内观察到 working 或 seq > 基线($BASE_SEQ)" \
    || t4_bad "AC2① 层② 执行面：10×100ms 内未观察到 working / seq 前进（agent_row=$(agent_row "$PANE_PM")）"
  SEQ_AFTER="$(seq_of)"
  t4_assert_ge "$(( ${BASE_SEQ:-0} + 1 ))" "${SEQ_AFTER:-0}" \
    "AC2① 层② seq 差分：投递后 seq(${SEQ_AFTER:-?}) > 基线($BASE_SEQ)（不判 == 基线+1：turn 结束会再 +1）"

# ============================================================ AC4 幂等：已在运行 ⇒ 不二次投递（herdr 可观测面）
  T23_SWITCH=1
  run_fleet ensure --task T1 "pm@$LAB"
  t4_assert_eq "0" "$T4_RC" "AC4 幂等：二次 ensure pm rc=0"
  t4_assert_contains "$T4_ERR_ANSI" "已在运行" "AC4 幂等：二次 ensure 判「已在运行」跳过（不进 spawn_one）"
  t4_assert_eq "1" "$(delivered_of "$PANE_PM")" "AC4 幂等：投递次数仍为 1（无状态文件、无二次投递）"
  t4_assert_eq "${SEQ_AFTER:-2}" "$(seq_of)" "AC4 幂等：seq 未再前进（未再起自检 turn）"

# ============================================================ AC1② ensure rd-be ⇒ 不投递
BEFORE="$(split_count)"
T23_SWITCH=1
run_fleet ensure "rd-be@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1② ensure rd-be rc=0"
t4_assert_eq "1" "$(launch_lines)" "AC1② 恰 1 行 [$BE_NAME] 已拉起"
CMD_RD="$(new_split "$BEFORE" | head -1)"
PF_RD="$(prompt_file_of "$CMD_RD")"
t4_assert_ne "" "$PF_RD" "AC1② rd-be 命令串正常（$PF_RD）"
diff_assert "$(expected_wrapped "rd-be" "$PF_RD")" "$CMD_RD" "AC3② rd-be 命令行与缺陷前基线逐字一致"
PANE_RD="$(pane_of "rd-be")"
t4_assert_ne "" "$PANE_RD" "AC1② 定位 rd-be pane（$PANE_RD）"
t4_assert_eq "0" "$(anchor_count "$(capture_of "$PANE_RD")")" "AC2② rd-be 会话不出现自检锚（非 pm 不投递）"
[ "$BE_NAME" = "herdr" ] && t4_assert_eq "0" "$(delivered_of "$PANE_RD")" "AC2② herdr：rd-be 无 agent prompt 投递"

# ============================================================ P2-2 替身保真（真机语义不得被替身放宽）
  # ① working 时带 `--lines` ⇒ 真机 rc=1 agent_not_idle（禁再用 --lines 做 AC2）
  OUT_LINES="$(LC_ALL=C be_herdr "$BE_SESSION" agent read "$PANE_PM" --lines 80 2>&1)"; RC_LINES=$?
  t4_assert_ne "0" "$RC_LINES" "P2-2① 替身保真：working 时「--lines 80」⇒ rc≠0（真机 agent_not_idle）"
  t4_assert_contains "$OUT_LINES" "agent_not_idle" "P2-2① 错误码 = agent_not_idle（把错误当正文读会被这条打红）"
  t4_assert_eq "0" "$(anchor_count "$OUT_LINES")" "P2-2① 错误路径不返回正文锚（真机实测 0 命中的真因）"
  # ② `--source full` ⇒ 非法枚举（真机只有 visible|recent|recent-unwrapped|detection）
  OUT_FULL="$(LC_ALL=C be_herdr "$BE_SESSION" agent read "$PANE_RD" --source full 2>&1)"; RC_FULL=$?
  t4_assert_ne "0" "$RC_FULL" "P2-2② 替身保真：「--source full」⇒ rc≠0（非法枚举）"
  t4_assert_contains "$OUT_FULL" "invalid read source" "P2-2② 错误点名 invalid read source（PM 先前的 0 命中 = 把错误当正文）"
  # ③ `--lines` 超 viewport（≤term_rows=40）⇒ rc≠0（idle pane 上也一样）
  OUT_BIG="$(LC_ALL=C be_herdr "$BE_SESSION" agent read "$PANE_RD" --lines 9999 2>&1)"; RC_BIG=$?
  t4_assert_ne "0" "$RC_BIG" "P2-2③ 替身保真：「--lines 9999」超 viewport ⇒ rc≠0"
  # ④ 正面对照：`--source visible` 在 working 期也 rc=0 且能读（AC2 内容面的合法面）
  OUT_VIS="$(LC_ALL=C be_herdr "$BE_SESSION" agent read "$PANE_PM" --source visible 2>&1)"; RC_VIS=$?
  t4_assert_eq "0" "$RC_VIS" "P2-2④ 正面对照：working 期「--source visible」rc=0（内容面可用）"
  t4_assert_eq "1" "$(anchor_count "$OUT_VIS")" "P2-2④「--source visible」命中常量首行（working 期可读）"

# ============================================================ AC1③/AC3③ 开关关闭 ⇒ 命令行逐字不变 + 不投递
BEFORE="$(split_count)"
T23_SWITCH=0
run_fleet ensure --task off "pm@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1③ 开关关闭 ensure pm rc=0"
t4_assert_eq "1" "$(launch_lines)" "AC1③ 恰 1 行 [$BE_NAME] 已拉起"
CMD_PMOFF="$(new_split "$BEFORE" | head -1)"
PF_PMOFF="$(prompt_file_of "$CMD_PMOFF")"
t4_assert_ne "" "$PF_PMOFF" "AC1③ pm-off 命令串正常（$PF_PMOFF）"
t4_assert_eq "0" "$(grep -cF -- ' -- ' <<< "$CMD_PMOFF" || true)" "AC1③ 开关关闭时无「 -- 」注入段"
diff_assert "$(expected_wrapped "pm2(off)" "$PF_PMOFF")" "$CMD_PMOFF" \
  "AC3③ NAO_UPDATE_ON_ENSURE=0 下 pm 命令行与缺陷前逐字一致"
# AC3 硬证据：默认开 vs 关闭 ⇒ 命令行 md5 相等（唯一变量是投递，不是 argv）
NORM_ON="$(printf '%s' "${CMD_PM//\\/}" | sed -E 's#--name [^ ]+ #--name <name> #; s#/tmp/nao-fleet-[^ ]+\.md#<prompt>#')"
NORM_OFF="$(printf '%s' "${CMD_PMOFF//\\/}" | sed -E 's#--name [^ ]+ #--name <name> #; s#/tmp/nao-fleet-[^ ]+\.md#<prompt>#')"
t4_assert_eq "$(printf '%s' "$NORM_OFF" | md5sum | awk '{print $1}')" \
  "$(printf '%s' "$NORM_ON" | md5sum | awk '{print $1}')" \
  "AC3④ 默认开与开关关的 pi 命令行 md5 相等（自检只改投递，不改 argv）"
# AC2 负控：开关关闭的新会话就绪后 2s 内不得出现该锚
PANE_PMOFF="$(pane_of "pm2(off)")"
t4_assert_ne "" "$PANE_PMOFF" "AC2③ 定位 pm-off pane（$PANE_PMOFF）"
t4_assert_eq "0" "$(anchor_count "$(capture_of "$PANE_PMOFF")")" "AC2③ 开关关闭：就绪后 2s 内无自检锚（负控）"
no_anchor_within "$PANE_PMOFF" 2 && t4_ok "AC2③ 负控窗口内（2s）持续无锚" || t4_bad "AC2③ 负控窗口内出现了自检锚"
[ "$BE_NAME" = "herdr" ] && t4_assert_eq "0" "$(delivered_of "$PANE_PMOFF")" "AC2③ herdr：开关关闭时 agent prompt 投递 0 次"

# ============================================================ AC4 失败语义：rc 仍 0 + 默认可见 warn（含 pane + code）
# herdr：替身对指定 target 返回 stdout 错误 JSON（agent_blocked）；tmux：桩 load-buffer 注入失败
  FAIL_ENV=(T4_HERDR_FAIL_PROMPT="pm2(140)")
T23_SWITCH=1
export "${FAIL_ENV[@]}"
run_fleet ensure --task 140 "pm@$LAB"
unset T4_HERDR_FAIL_PROMPT T4_TMUX_FAIL_BUFFER
t4_assert_eq "0" "$T4_RC" "AC4① 投递失败不改 rc（会话可用 ⇒ rc=0）"
t4_assert_contains "$T4_OUT_ANSI" "（成功 1 / 跳过 0 / 失败 0）" "AC4① 投递失败不计 SPAWN_FAIL（摘要仍 成功 1）"
t4_assert_contains "$T4_ERR_ANSI" "版本自检投递失败" "AC4① 投递失败有默认可见 warn（不静默）"
  t4_assert_contains "$T4_ERR_ANSI" "agent_blocked" "AC4① warn 含 herdr error code（agent_blocked，取自 stdout）"
t4_assert_contains "$T4_ERR_ANSI" "pane=" "AC4① warn 含 pane（可定位）"
PANE_FAIL="$(pane_of "pm2(140)")"
t4_assert_ne "" "$PANE_FAIL" "AC4① 失败夹具 pane 仍建立（会话确实可用）"
t4_assert_eq "0" "$(anchor_count "$(capture_of "$PANE_FAIL")")" "AC4① 失败路径无投递锚（确实没送达）"

# ============================================================ P2-3 七条件「与关系」机械负控（逐条违反 ⇒ 必超时）
# 为什么必须在用例里跑：QA 实测「删掉 AND 里的 agent_status == idle」时 case 23/29 全绿 —— 只有
#   warn 文案 grep，没有机械负控。这里对三条关键条件分别造「只差这一条」的现场：每条都必须
#   超时 + 0 成功行 + 摘要失败 1。若产品代码删掉对应条件，这三组立刻翻红（不是文案能兜的）。
  export TERM_READY_TIMEOUT_MS=600 TERM_READY_POLL_MAX=5 TERM_READY_POLL_INT=0.1
  # ① 只差 idle：已 idle 才是就绪（本组 = working）
  set_knob pi_status '"working"'; set_knob pi_seq 1; set_knob pi_skip true; set_knob pi_session true
  T23_SWITCH=1
  run_fleet ensure "rd-fe@$LAB"
  t4_assert_eq "0" "$T4_RC" "P2-3① 违反 idle：rc=0（D3，失败只进计数）"
  t4_assert_eq "0" "$(launch_lines)" "P2-3① 违反 idle ⇒ 零成功行（禁把 working 当就绪）"
  t4_assert_contains "$T4_OUT_ANSI" "（成功 0 / 跳过 0 / 失败 1）" "P2-3① 违反 idle ⇒ 摘要计失败 1"
  t4_assert_contains "$T4_ERR_ANSI" "agent_status == idle" "P2-3① 逐条点名缺 idle（删掉该条件 ⇒ 本组翻红）"
  # ② 只差 seq ≥ 1：未观测到状态迁移就不算就绪（本组 seq=0）
  set_knob pi_status '"idle"'; set_knob pi_seq 0; set_knob pi_skip true; set_knob pi_session true
  T23_SWITCH=1
  run_fleet ensure "arch-designer@$LAB"
  t4_assert_eq "0" "$T4_RC" "P2-3② 违反 seq：rc=0"
  t4_assert_eq "0" "$(launch_lines)" "P2-3② 违反 seq ⇒ 零成功行（禁把从未迁移当就绪）"
  t4_assert_contains "$T4_OUT_ANSI" "（成功 0 / 跳过 0 / 失败 1）" "P2-3② 违反 seq ⇒ 摘要计失败 1"
  t4_assert_contains "$T4_ERR_ANSI" "state_change_seq ≥ 1" "P2-3② 逐条点名缺 seq（删掉该条件 ⇒ 本组翻红）"
  # ③ 只差钩子权威：屏幕启发式状态不可作就绪判据（本组 skip=false）
  set_knob pi_status '"idle"'; set_knob pi_seq 1; set_knob pi_skip false; set_knob pi_session true
  T23_SWITCH=1
  run_fleet ensure "uiux-designer@$LAB"
  t4_assert_eq "0" "$T4_RC" "P2-3③ 违反 skip：rc=0"
  t4_assert_eq "0" "$(launch_lines)" "P2-3③ 违反 skip ⇒ 零成功行（禁把屏幕启发式当权威）"
  t4_assert_contains "$T4_OUT_ANSI" "（成功 0 / 跳过 0 / 失败 1）" "P2-3③ 违反 skip ⇒ 摘要计失败 1"
  t4_assert_contains "$T4_ERR_ANSI" "screen_detection_skipped" "P2-3③ 逐条点名缺 skip（删掉该条件 ⇒ 本组翻红）"
  unset TERM_READY_TIMEOUT_MS TERM_READY_POLL_MAX TERM_READY_POLL_INT

t4_exit
