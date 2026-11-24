#!/usr/bin/env bash
# 用例 45 —— app 后端「放置验证失败」（T565 / Issue #175）
#
# 缺陷（用户实机）：`NAO_TERMINAL=app ensure pm` ⇒
#   `放置验证失败：终端 t10 不在目标 tab 的 root 树里（space=sp89c3534f… tab=tb3c2b28…）⇒ 回滚`
#
# 根因（两条，互不替代）：
#   A. 放置前**不校验**目标 space/tab 是否仍在 app 布局文档里 ⇒ 沿用了「陈旧标签」里的旧 id
#      （app 重启后 id 会变化；厂方内嵌文档：「An id Herdr doesn't know becomes a new space or tab」——
#      不认识的 id 由 app 自己新建，请求的旧 id 就**无处可去**）。
#   B. app 的收养是**异步**的（厂方文档：「acknowledge with `pending: true`, then apply after the
#      machine replies」）⇒ 写标签后立刻读 doc 必然假失败。
#
# 断言组（编号 ↔ AC）：
#   ⓪ 单点静态：轮询参数 / 轮询函数 / AC1 文档校验 / `check` 侧 `|| true`（勿计入 rc）各有唯一事实。
#   ① AC1：目标 space 仍在 doc ⇒ 复用 doc 的 space id（不另起 space）。
#   ② AC1/AC5：标签指向**不存在**的 space ⇒ 不沿用陈旧 id，新建并转绿；陈旧 id 一条 warn。
#   ③ AC3-a：「目标 space 不存在」与「收养超时」是**两句不同**的报错；前者回滚干净。
#   ④ AC2：收养延迟（异步）⇒ 轮询转绿；`run` 恰 1 次（轮询期间不重复起终端）；
#     负控：只验一次（tries=1）⇒ 必红（证明轮询本身承重）。
#   ⑤ AC3-b：收养永不完成 ⇒ 「收养超时」+ 回滚 kill → rm + 无孤儿。
#   ⑥ AC4：`check` / `check -v` 的 app 端前提（herdr-app 在 PATH / status rc=0 / doc 可读）是 warn，
#      **不计入 rc**；在 app 终端内即使 NAO_TERMINAL 未设也体检；非 app 环境零新增输出（负控）。
#   ⑦ 断言射程自证（变异必红）：拆掉 ② 的文档校验 ⇒ 必复现**同一句**报错；拆掉 ④ 的轮询 ⇒ 收养延迟必栽。
#
# 夹具：`tests/t4/fixtures/hc-double`（hc + herdr-app 替身；T565 新增 stale_ids / adopt_delay /
#   adopt_never / space_refuse）。替身只模拟**观测面**（doc/labels/时序），真机 UI 效果仍归人工验收。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
FIXT="$T4_ROOT/tests/t4/fixtures/hc-double"
[ -x "$FIXT/hc" ] || { t4_bad "夹具缺失可执行: $FIXT/hc"; t4_exit; }
PATH="$FIXT:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab45-$$"
mkdir -p "$LAB" || { t4_bad "无法建 lab"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
FLEET_LAB="$LAB/.agents/scripts/nao-fleet.sh"

be_app_init "$LAB" "lab45-$$" || { t4_bad "be_app_init 失败"; t4_exit; }
be_app_arm_cleanup

APP_RC=0; APP_OUT=""; APP_ERR=""
APP_OVR=()   # 覆盖项（后写覆盖先写 ⇒ 必须排在基础 env 之后）
run_app() { # 走与生产一致的 env 面（显式 NAO_TERMINAL=app + 三件套 + 私有根）
  local -a envs=(NAO_TERMINAL=app "HC_SCOPE=$BE_SESSION" HC_TERMINAL_ID=t0
    "HC_TERMINAL_SOCKET=$BE_APP_SOCK" "XDG_RUNTIME_DIR=$BE_APP_RT"
    "HC_DOUBLE_STATE=$BE_APP_STATE" "PATH=$FIXT:$PATH"
    "HOME=$LAB/.t4-home" "PI_CODING_AGENT_DIR=$LAB/.t4-home/.pi/agent")
  local script="${BE_FLEET_SCRIPT:-$FLEET_LAB}"
  local -a argv=(env)
  argv+=("${envs[@]}")
  if (( ${#APP_OVR[@]} )); then argv+=("${APP_OVR[@]}"); fi
  argv+=(timeout "${BE_FLEET_TIMEOUT:-120}" bash "$script")
  t4_run_in_dir "$LAB" "${argv[@]}" "$@"
  APP_RC=$T4_RC; APP_OUT="$T4_OUT"; APP_ERR="$T4_ERR"
}
stub_hc() { HC_DOUBLE_STATE="$BE_APP_STATE" "$FIXT/hc" "$@"; }
app_addrs() { find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^t0$' | sort -V; }
app_field() { head -1 "$BE_APP_STATE/t/$1/$2" 2>/dev/null; }
app_log() { cat "$BE_APP_STATE/log" 2>/dev/null || true; }
app_reset() {
  find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d ! -name t0 -exec rm -rf {} + 2>/dev/null || true
  find "$BE_APP_STATE/spaces" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  [ -d "$BE_APP_STATE/tabs" ] && find "$BE_APP_STATE/tabs" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null
  : > "$BE_APP_STATE/log"
  rm -f "$BE_APP_STATE"/docver "$BE_APP_STATE"/doc_hide "$BE_APP_STATE"/ready \
        "$BE_APP_STATE"/status_app "$BE_APP_STATE"/status_state "$BE_APP_STATE"/run_fail \
        "$BE_APP_STATE"/send_fail "$BE_APP_STATE"/app_status_rc "$BE_APP_STATE"/bare_get \
        "$BE_APP_STATE"/bare_labels "$BE_APP_STATE"/stale_ids "$BE_APP_STATE"/adopt_delay \
        "$BE_APP_STATE"/adopt_never "$BE_APP_STATE"/space_refuse
  return 0
}
# 新起终端（排除预置的 stale 夹具终端）：按 cwd == repo 且 name 匹配
addr_of() { # <name>
  local a
  for a in $(app_addrs); do
    [ "$(app_field "$a" name)" = "$1" ] && { printf '%s' "$a"; return 0; }
  done
  return 0
}
doc_spaces() { stub_hc connect <<< '{"jsonrpc":"2.0","id":1,"method":"doc.get","params":{"name":"herdr-app"}}' \
  | grep -o '"id":"sp[^"]*"' | cut -d'"' -f4 | sort; }
doc_of() { stub_hc connect <<< '{"jsonrpc":"2.0","id":1,"method":"doc.get","params":{"name":"herdr-app"}}'; }
run_calls() { grep -c '^run ' <<< "$(app_log)" || true; }
mutate() { # <src> <dst> <old> <new>  —— 锚点必须**恰 1 次**（否则报锚点问题，不当绿）
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding='utf-8').read()
n = s.count(old)
if n != 1:
    print(f'MUTATION-ANCHOR: 命中 {n} 次（期望恰 1）: {old}')
    sys.exit(3)
open(dst, 'w', encoding='utf-8').write(s.replace(old, new))
PY
}

STALE_SP="spstale000000000000000000000000a"    # 32 hex 形态（旧 app run 的 space id）
STALE_TB="tbstale000000000000000000000000a"
KEEP_SP="spkeeper0000000000000000000000000"
KEEP_TB="tbkeeper0000000000000000000000000"

# ---------------------------------------------------------------- ⓪ 单点静态
t4_assert_eq "1" "$(grep -cE '^TERM_APP_ADOPT_TRIES="\$\{NAO_APP_ADOPT_TRIES:-10\}"' "$FLEET" || true)" \
  "⓪ AC2：轮询次数默认 10 单点（改默认必红）"
t4_assert_eq "1" "$(grep -cE '^TERM_APP_ADOPT_INTERVAL="\$\{NAO_APP_ADOPT_INTERVAL:-0\.5\}"' "$FLEET" || true)" \
  "⓪ AC2：轮询间隔默认 0.5s 单点"
t4_assert_eq "1" "$(grep -cE '^_term_app_poll_place\(\) \{' "$FLEET" || true)" \
  "⓪ AC2：轮询**唯一**实现点（不能有第二个各自 sleep 的循环）"
t4_assert_eq "1" "$(grep -cF '_term_app_poll_place "$sp" "$tb" "$addr"' "$FLEET" || true)" \
  "⓪ AC2：spawn 侧调用轮询（且只此一处）"
t4_assert_eq "1" "$(grep -cE '^_term_app_doc_has_space\(\) \{' "$FLEET" || true)" \
  "⓪ AC1：doc 校验有唯一实现点"
t4_assert_ge "2" "$(grep -cF '_term_app_check_premise || true' "$FLEET" || true)" \
  "⓪ AC4：check 侧 app 前提用 || true（app 后端臂 + app 终端臂各一处，warn 不计入 rc）"
t4_assert_eq "0" "$(grep -cF '_term_app_check_premise || rc=1' "$FLEET" || true)" \
  "⓪ AC4：旧的 || rc=1 接线已不存在（否则前提 warn 会改 rc）"

# ---------------------------------------------------------------- ① AC1：目标 space 存在 ⇒ 复用
app_reset
printf '%s' "$LAB" > "$BE_APP_STATE/spaces/$KEEP_SP"   # app 里本仓的 space（doc 权威）
stub_hc run --bg --no-parent --keep --name qa --cwd "$LAB" \
  --label "herdr.space=$KEEP_SP" --label "herdr.tab=$KEEP_TB" -- true >/dev/null
: > "$BE_APP_STATE/log"
run_app ensure rd-fe
A1="$(addr_of rd-fe)"
t4_assert_eq "0" "$APP_RC" "① 目标 space 在 doc ⇒ ensure rc=0"
t4_assert_eq "$KEEP_SP" "$(app_field "$A1" space)" "① AC1：复用 doc 里的 space id（不另起 space）"
t4_assert_eq "1" "$(doc_spaces | grep -c . || true)" "① AC1：space 数仍为 1（未新建重复 space）"
t4_assert_contains "$(doc_of)" "\"terminal\":\"$A1\"" "① 终端落在目标 tab 的 root 树里"

# ---------------------------------------------------------------- ② AC1：陈旧标签 ⇒ 不沿用
app_reset
# 预置：一个 live 终端带着**旧 app run** 的 space 标签，而该 space 不在 doc 里（没有 spaces 文件）；
#   同时 app 也不认这个 id（stale_ids）—— 正是不认识就自己新建、请求 id 无处可去。
stub_hc run --bg --no-parent --keep --name rd-be --cwd "$LAB" \
  --label "herdr.space=$STALE_SP" --label "herdr.tab=$STALE_TB" -- true >/dev/null
rm -f "$BE_APP_STATE/spaces/$STALE_SP"       # app 重启后该 space 已不存在（doc 里查无此 id）
printf '%s\n' "$STALE_SP" > "$BE_APP_STATE/stale_ids"
t4_assert_eq "" "$(doc_spaces)" "② 夹具：doc 里没有该 space（陈旧 id）"
: > "$BE_APP_STATE/log"
run_app ensure rd-fe
A2="$(addr_of rd-fe)"
t4_assert_eq "0" "$APP_RC" "② AC1：陈旧 id 不再沿用 ⇒ ensure rc=0（修复前必为 1）"
t4_assert_not_contains "$APP_ERR" "放置验证失败" "② AC1：未出现放置验证失败"
t4_assert_ne "$STALE_SP" "$(app_field "$A2" space)" "② AC1：终端不用陈旧 space id"
t4_assert_ne "" "$(app_field "$A2" space)" "② AC1：终端有新 space id（交给 app 创建后落库）"
t4_assert_contains "$APP_ERR" "陈旧放置标签" "② AC1：陈旧 id 有一条 warn（不静默）"
t4_assert_eq "1" "$(grep -cF '陈旧放置标签' <<< "$APP_ERR" || true)" "② AC1：该 warn 恰 1 行（不按终端刷屏）"
t4_assert_contains "$(doc_of)" "\"terminal\":\"$A2\"" "② AC1：终端确实落在 doc 的 tab 树里"

# ---------------------------------------------------------------- ③ AC3-a：目标 space 不存在 ⇒ 分类报错
app_reset
printf '1' > "$BE_APP_STATE/space_refuse"   # app 不认任何放置标签 ⇒ 目标 space 永不存在
: > "$BE_APP_STATE/log"
APP_OVR=("NAO_APP_ADOPT_TRIES=3" "NAO_APP_ADOPT_INTERVAL=0.1")
run_app ensure rd-fe
APP_OVR=()
t4_assert_ne "0" "$APP_RC" "③ AC3：app 不认标签 ⇒ ensure 非 0（fail loud）"
t4_assert_contains "$APP_ERR" "目标 space 不存在" "③ AC3-a：点名「目标 space 不存在」"
t4_assert_contains "$APP_ERR" "app 重启后" "③ AC3-a：指明成因（app 重启后 id 会变化）"
t4_assert_not_contains "$APP_ERR" "收养超时" "③ AC3-a：与「收养超时」是两句不同报错（不合并）"
t4_assert_contains "$APP_ERR" "回滚" "③ AC3-a：仍然回滚"
t4_assert_eq "" "$(addr_of rd-fe)" "③ AC3-a：回滚后不留孤儿终端"
rm -f "$BE_APP_STATE/space_refuse"

# ---------------------------------------------------------------- ④ AC2：异步收养 ⇒ 轮询转绿
app_reset
printf '2' > "$BE_APP_STATE/adopt_delay"
: > "$BE_APP_STATE/log"
run_app ensure rd-fe
A4="$(addr_of rd-fe)"
t4_assert_eq "0" "$APP_RC" "④ AC2：收养延迟（默认 10×0.5s 轮询）⇒ rc=0"
t4_assert_eq "1" "$(run_calls)" "④ AC2：轮询期间**不重复起终端**（hc run 恰 1 次）"
t4_assert_contains "$(doc_of)" "\"terminal\":\"$A4\"" "④ AC2：轮询到位后终端在目标 tab 树里"
# 负控：只验一次（不轮询）⇒ 同一夹具必红（证明轮询本身承重，不是别的分支救的场）
app_reset
printf '2' > "$BE_APP_STATE/adopt_delay"
: > "$BE_APP_STATE/log"
APP_OVR=("NAO_APP_ADOPT_TRIES=1")
run_app ensure rd-fe
APP_OVR=()
t4_assert_ne "0" "$APP_RC" "④ 负控：tries=1（不轮询）⇒ 同一延迟夹具必红"
t4_assert_contains "$APP_ERR" "收养超时" "④ 负控：点名超时（不是别的原因）"

# ---------------------------------------------------------------- ⑤ AC3-b：收养永不完成 ⇒ 超时 + 回滚
app_reset
printf '1' > "$BE_APP_STATE/adopt_never"
: > "$BE_APP_STATE/log"
APP_OVR=("NAO_APP_ADOPT_TRIES=3" "NAO_APP_ADOPT_INTERVAL=0.1")
run_app ensure rd-fe
APP_OVR=()
t4_assert_ne "0" "$APP_RC" "⑤ AC3-b：收养永不完成 ⇒ ensure 非 0"
t4_assert_contains "$APP_ERR" "收养超时" "⑤ AC3-b：点名「收养超时」"
t4_assert_match "$APP_ERR" "3×0\.1s" "⑤ AC3-b：报错带实际轮询参数（3×0.1s）"
t4_assert_not_contains "$APP_ERR" "目标 space 不存在" "⑤ AC3-b：与「目标 space 不存在」是两句不同报错"
t4_assert_eq "1" "$(run_calls)" "⑤ 轮询期间不重复起终端（hc run 恰 1 次）"
t4_assert_contains "$(app_log)" "kill t1" "⑤ 回滚先 kill"
t4_assert_contains "$(app_log)" "rm t1" "⑤ 回滚再 rm（顺序不可反）"
t4_assert_eq "" "$(app_addrs)" "⑤ 回滚后不留孤儿终端"
rm -f "$BE_APP_STATE/adopt_never"

# ---------------------------------------------------------------- ⑥ AC4：check 的 app 前提（warn-only）
app_reset
printf '1' > "$BE_APP_STATE/app_status_rc"   # herdr-app status rc≠0（窗口未在跑）
run_app check
t4_assert_contains "$APP_OUT" "warn=1" "⑥ AC4：前提告警进 warn 计数（摘要口径：详情走 -v）"
t4_assert_eq "0" "$APP_RC" "⑥ AC4：前提告警**不计入 rc**（rc 仍 0）"
run_app check -v
t4_assert_contains "$APP_OUT" "desktop app 窗口未在运行" "⑥ AC4：check -v 点名「窗口未在运行」（补上的 app 端前提）"
t4_assert_contains "$APP_OUT" "仅提示，**不计入 rc**" "⑥ AC4：明确写出不计入 rc（读者不用猜）"
t4_assert_eq "0" "$APP_RC" "⑥ AC4：check -v 也不计入 rc"
rm -f "$BE_APP_STATE/app_status_rc"
run_app check -v
t4_assert_not_contains "$APP_OUT" "desktop app 窗口未在运行" "⑥ 负控：窗口在跑 ⇒ 无该项（判据不空转）"
# hc 不在 PATH：一行指路（rc 不因它置红 —— 该形态下 pi 检查自身仍可能红，故不比 rc）
APP_OVR=("PATH=/usr/bin:/bin")
run_app check -v
APP_OVR=()
t4_assert_contains "$APP_OUT" "hc 不在 PATH" "⑥ AC4：hc 不在 PATH ⇒ 一行指路"
# 在 app 终端内但 NAO_TERMINAL 未设（用户实机形态）：也要体检；不置红
# >>> default-value-probe BEGIN（#175 AC4：验「app 终端内未设 NAO_TERMINAL」这条默认/未设路径 ——
#   用户实机就是在 herdr desktop app 的终端里跑 check，而 NAO_TERMINAL 没设（PM 事实 3）。
#   除本块外，用例全部显式给 NAO_TERMINAL=app；已登记在 cases/06 的探针块白名单里）
__run_check_no_term() { # [fleet 参数…]：在 app 终端内、但 NAO_TERMINAL 未设（用户实机形态）
  local -a argv=(env -u NAO_TERMINAL "HC_SCOPE=$BE_SESSION" HC_TERMINAL_ID=t0 \
    "HC_TERMINAL_SOCKET=$BE_APP_SOCK" "XDG_RUNTIME_DIR=$BE_APP_RT" \
    "HC_DOUBLE_STATE=$BE_APP_STATE" "PATH=$FIXT:$PATH" "HOME=$LAB/.t4-home")
  argv+=(bash "$FLEET_LAB" check)
  (( $# )) && argv+=("$@")
  t4_run_in_dir "$LAB" "${argv[@]}"
  APP_RC=$T4_RC; APP_OUT="$T4_OUT"; APP_ERR="$T4_ERR"
}
__run_check_bare() { # [fleet 参数…]：既不在 app 终端、也没 NAO_TERMINAL=app（负控）
  local -a argv=(env -u NAO_TERMINAL -u HC_SCOPE -u HC_TERMINAL_ID -u HC_TERMINAL_SOCKET \
    "PATH=$FIXT:$PATH" "HOME=$LAB/.t4-home" bash "$FLEET_LAB" check)
  (( $# )) && argv+=("$@")
  t4_run_in_dir "$LAB" "${argv[@]}"
  APP_RC=$T4_RC; APP_OUT="$T4_OUT"; APP_ERR="$T4_ERR"
}
# >>> default-value-probe END
printf '1' > "$BE_APP_STATE/app_status_rc"
__run_check_no_term -v
t4_assert_contains "$APP_OUT" "desktop app 窗口未在运行" "⑥ AC4：app 终端内（NAO_TERMINAL 未设）也体检 app 端前提（-v 展开）"
t4_assert_contains "$APP_OUT" "检测到 herdr desktop app 终端" "⑥ AC4：点名「在 app 终端里但 NAO_TERMINAL 未设」"
t4_assert_eq "0" "$APP_RC" "⑥ AC4：该形态下同样不计入 rc"
rm -f "$BE_APP_STATE/app_status_rc"
# 负控：既不在 app 终端、也没有 NAO_TERMINAL=app ⇒ 零新增输出（既有 golden 不受影响）
__run_check_bare -v
t4_assert_not_contains "$APP_OUT" "desktop app 窗口未在运行" "⑥ 负控：非 app 环境不打印 app 端前提（不污染既有输出）"
t4_assert_not_contains "$APP_OUT" "检测到 herdr desktop app 终端" "⑥ 负控：无三件套 ⇒ 不触发 app 端体检"

# ---------------------------------------------------------------- ⑦ 变异必红（断言射程自证）
MUT1="$LAB/mut1-nodocguard.sh"
if mutate "$FLEET_LAB" "$MUT1" '! _term_app_doc_has_space "$sp"' 'false'; then
  app_reset
  stub_hc run --bg --no-parent --keep --name rd-be --cwd "$LAB" \
    --label "herdr.space=$STALE_SP" --label "herdr.tab=$STALE_TB" -- true >/dev/null
  rm -f "$BE_APP_STATE/spaces/$STALE_SP"
  printf '%s\n' "$STALE_SP" > "$BE_APP_STATE/stale_ids"
  APP_OVR=("NAO_SKILLS=$LAB")
  BE_FLEET_SCRIPT="$MUT1" run_app ensure rd-fe
  BE_FLEET_SCRIPT=""
  APP_OVR=()
  t4_assert_ne "0" "$APP_RC" "⑦ 变异（拆掉 AC1 文档校验）⇒ ②场景必红（断言射程：只有它能抓住）"
  t4_assert_contains "$APP_ERR" "放置验证失败" "⑦ 变异必红：拆掉文档校验 ⇒ 放置失败重现"
  t4_assert_contains "$APP_ERR" "space=$STALE_SP" "⑦ 变异必红且报错里带着**陈旧 id**（证明它又被沿用了）"
else
  t4_bad "⑦ 变异锚点未命中（AC1 文档校验的实现行变了 ⇒ 用例需同步）"
fi
MUT2="$LAB/mut2-onepass.sh"
if mutate "$FLEET_LAB" "$MUT2" '_term_app_poll_place "$sp" "$tb" "$addr"' '_term_app_verify_place "$sp" "$tb" "$addr"'; then
  app_reset
  printf '2' > "$BE_APP_STATE/adopt_delay"
  APP_OVR=("NAO_SKILLS=$LAB")
  BE_FLEET_SCRIPT="$MUT2" run_app ensure rd-fe
  BE_FLEET_SCRIPT=""
  APP_OVR=()
  t4_assert_ne "0" "$APP_RC" "⑦ 变异（拆掉轮询）⇒ 收养延迟必栽（断言射程：只有它能抓住）"
  t4_assert_contains "$APP_ERR" "收养超时" "⑦ 变异必红原因 = 收养超时"
else
  t4_bad "⑦ 变异锚点未命中（轮询调用点变了 ⇒ 用例需同步）"
fi

t4_exit
