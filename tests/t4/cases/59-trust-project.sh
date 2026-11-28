#!/usr/bin/env bash
# 用例 59 —— `ensure --trust-project`（T586-B · Issue #248）
#
# 被测：`ensure` 的显式信任开关 —— 给**本次 spawn 的 pi** 加 `--approve`（pi 首启免「Trust project folder?」）。
#   背景：T584 已在就绪门超时时点名该提示；本开关让无人值守能自己过门，且**不写任何持久配置**。
#
# 判据（argv 级，不看 rc 了事）：
#   ① `--help` 同时写明 `--trust-project` 与 `NAO_TRUST_NEW_REPO`
#   ② 带 `--trust-project` ⇒ 交给后端的 `exec pi …` 命令串含 `--approve`（恰 1 处）
#   ③ **不带** ⇒ 不含（默认不开，负控）
#   ④ `NAO_TRUST_NEW_REPO=1` ⇒ 含 1 处（等价开关）
#   ⑤ flag + env 同给 ⇒ **仍恰 1 处**（同一个开关两种写法，不重复传参）
#   ⑥ **不写持久配置**：spawn 前后 `$HOME/.pi` 与项目 `.pi/` 快照一致（红线）
#   ⑦ 用法面：`--trust-project` 只给 `ensure`（其它子命令 ⇒ rc≠0；本仓用法错统一走 die=1）
#
# 夹具：`tests/t4/fixtures/herdr-double` + `T4_HERDR_CALL_LOG`（替身把每次调用的 argv 逐行追加）——
#   于是「pi 的 argv 里有没有 --approve」是**后端收到的原样命令串**，不是我们的自述。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

t4_require_cmd node
BE_NAME="herdr"
PATH="$T4_ROOT/tests/t4/fixtures/herdr-double:$PATH"; export PATH

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
LAB="$T4_CACHE_DIR/lab59-$$"
mkdir -p "$LAB" || { t4_bad "夹具：建 $LAB 失败"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

t59_exit_trap() {
  local rc=$?
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t59_exit_trap EXIT

BE_CACHE_ROOT="$T4_CACHE_DIR"
be_init "$LAB" "lab59" || { t4_bad "be_init 失败"; t4_exit; }
be_start_server || { t4_bad "夹具：herdr 替身 server 起不来"; t4_exit; }
[ -n "$(be_panes)" ] || be_new_pane "$LAB" >/dev/null

export T4_HERDR_CALL_LOG="$LAB/calls.log"
: > "$T4_HERDR_CALL_LOG"
printf '# 用例 59 tasks-state（空表）\n\n## 进行中\n\n（无）\n' > "$LAB/ts.md"

mk_repo() { mkdir -p "$LAB/$1"; }
run59() { # <repo 名> [env 前缀已由调用方给] <ensure 参数...>
  local r="$1"; shift
  be_run_fleet "$LAB/$r" ensure "$@" >/dev/null 2>&1 || true
  T4_RC="$BE_RC"; T4_OUT="$BE_OUT_ANSI"; T4_ERR="$BE_ERR_ANSI"
}
approve_count() { grep -c -- 'exec pi .*--approve' "$T4_HERDR_CALL_LOG" 2>/dev/null || true; }
reset_log() { : > "$T4_HERDR_CALL_LOG"; }

# ⑥ 快照：**真实 `$HOME/.pi`** + **被测进程实际继承的 HOME/.pi** + 每个 repo 的 `.pi`
#   ⚠️ 两个对象缺一不可（这是本用例最容易写成空转的地方）：
#     · 替身 LAB 下随手写的 `.pi` 恒为 0 文件 ⇒ 「空 vs 空」恒真（T589 R3 现场，抓不到任何东西）；
#     · 但夹具给被测进程注入了**隔离 HOME**（`be_isolated_env`）⇒ 只快照真实 `$HOME` 也抓不到
#       「代码里 `$HOME/.pi` 被写」这类实现（它落在隔离 HOME 里）。⇒ 两个都要，且真实面必须有文件。
#   排除 `agent/sessions`（运行产物：本机其它 pi 会话会持续追加，比它必然抖动）——红线在意的是**配置面**。
REAL_HOME59="${HOME:-}"; REAL_PI59="$REAL_HOME59/.pi"
CHILD_HOME59="$(be_isolated_env | sed -n 's/^HOME=//p' | head -1)"
[ -n "$CHILD_HOME59" ] || CHILD_HOME59="${BE_LAB:-$LAB}/.t4-home"
snap59() {
  { find "$REAL_PI59" -path "$REAL_PI59/agent/sessions" -prune -o -type f -print 2>/dev/null | sort
    find "$REAL_PI59" -path "$REAL_PI59/agent/sessions" -prune -o -type f -exec md5sum {} + 2>/dev/null | awk '{print $1}' | sort
    find "$CHILD_HOME59/.pi" -type f 2>/dev/null | sort
    find "$CHILD_HOME59/.pi" -type f -exec md5sum {} + 2>/dev/null | awk '{print $1}' | sort
    find "$LAB"/repo*/.pi -type f 2>/dev/null | sort
  } | paste -sd'|' -
}
# 防空转：真实配置面**必须有文件**，否则这条断言又变成「空 vs 空」
t4_require_cmd find
if [ ! -d "$REAL_PI59/agent" ] || [ "$(find "$REAL_PI59/agent" -maxdepth 1 -type f 2>/dev/null | grep -c . || true)" = "0" ]; then
  t4_skip "本机无真实 $REAL_PI59（无配置文件）⇒ 无法证明「不写用户配置」，跳过而非空转通过"
fi
t4_assert_ge 1 "$(find "$REAL_PI59/agent" -maxdepth 1 -type f 2>/dev/null | grep -c . || true)" \
  "⑥ 前置：真实 $REAL_PI59/agent 下配置面文件 ≥1（防空集恒真）"
t4_assert_eq "1" "$([ -d "$CHILD_HOME59" ] && echo 1 || echo 0)" \
  "⑥ 前置：被测进程的隔离 HOME 在场（$CHILD_HOME59；快照必须覆盖它，否则抓不到 `$HOME/.pi` 写入）"
SNAP_BEFORE="$(snap59)"

# ---------------------------------------------------------------- ① help
t4_assert_contains "$(bash "$FLEET" --help 2>&1 || true)" "--trust-project" "① --help 写明 --trust-project"
t4_assert_contains "$(bash "$FLEET" --help 2>&1 || true)" "NAO_TRUST_NEW_REPO" "① --help 写明等价环境变量 NAO_TRUST_NEW_REPO"

# ---------------------------------------------------------------- ② 带 flag ⇒ argv 含 --approve
mk_repo r1; reset_log
run59 r1 --trust-project "qa@$LAB/r1"
t4_assert_eq "0" "$T4_RC" "② --trust-project：ensure rc=0"
t4_assert_eq "1" "$(approve_count)" "② 交给后端的 exec pi 命令串含 --approve（恰 1 处；argv 级证据）"
t4_assert_eq "1" "$(grep -c -- 'exec pi .*--approve' "$T4_HERDR_CALL_LOG" || true)" \
  "② 同一行内 --approve 与 exec pi 同现（不是别处的孤立字符串）"

# ---------------------------------------------------------------- ③ 不带 ⇒ 不含（默认不开）
mk_repo r2; reset_log
run59 r2 "qa@$LAB/r2"
t4_assert_eq "0" "$T4_RC" "③ 不带开关：ensure rc=0（默认行为不变）"
t4_assert_eq "0" "$(approve_count)" "③ 不带开关 ⇒ argv **不含** --approve（默认不开，负控）"

# ---------------------------------------------------------------- ④ env 等价
mk_repo r3; reset_log
# 注：`be_run_fleet` 的环境净化会把**调用方 ambient 的 `NAO_*`** 一律 `-u`（防宿主渗进夹具）
#   ⇒ 要「让被测进程看到这个变量」，须显式进保留名单（`BE_ENV_KEEP`，净化门面的既有逃生阀）。
NAO_TRUST_NEW_REPO=1 BE_ENV_KEEP="NAO_TRUST_NEW_REPO ${BE_ENV_KEEP:-}" run59 r3 "qa@$LAB/r3"
t4_assert_eq "0" "$T4_RC" "④ NAO_TRUST_NEW_REPO=1：ensure rc=0"
t4_assert_eq "1" "$(approve_count)" "④ 环境变量等价 ⇒ argv 含 --approve（恰 1 处）"

# ---------------------------------------------------------------- ⑤ flag + env 同给 ⇒ 不重复传参
mk_repo r4; reset_log
NAO_TRUST_NEW_REPO=1 BE_ENV_KEEP="NAO_TRUST_NEW_REPO ${BE_ENV_KEEP:-}" run59 r4 --trust-project "qa@$LAB/r4"
t4_assert_eq "0" "$T4_RC" "⑤ flag + env 同给：ensure rc=0"
t4_assert_eq "1" "$(grep -o -- '--approve' "$T4_HERDR_CALL_LOG" | wc -l | tr -d ' ')" \
  "⑤ 两者同给仍只传 1 次 --approve（同一开关两种写法，不重复）"

# ---------------------------------------------------------------- ⑥ 不写持久配置（红线）
t4_assert_eq "$SNAP_BEFORE" "$(snap59)" \
  "⑥ spawn 前后：真实 $REAL_PI59（排除 agent/sessions）+ 隔离 HOME $CHILD_HOME59/.pi + 项目 .pi/ 逐字节一致（不写任何持久配置）"
t4_assert_eq "0" "$(find "$LAB"/repo*/.pi -type f 2>/dev/null | grep -c . || true)" \
  "⑥ 项目侧未被写入 .pi/（--trust-project 只作用于该次进程）"

# ---------------------------------------------------------------- ⑦ 用法面：只给 ensure
OUT59="$(bash "$FLEET" status --trust-project 2>&1)"; RC59=$?
t4_assert_ne "0" "$RC59" "⑦ --trust-project 用于 status ⇒ rc≠0（用法守卫；本仓用法错统一走 die=1）"
t4_assert_contains "$OUT59" "仅用于 ensure" "⑦ 点名「仅用于 ensure 子命令」"

t4_exit 0
