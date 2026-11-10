#!/usr/bin/env bash
# T4 后端抽象层 —— PRD #96 一期步 1（Issue #96 · AC1.1–AC1.7 · BR6/BR7/BR8 · 附一）
#
# 定位：**测试侧**后端抽象。生产脚本 `.agents/scripts/nao-fleet.sh` 零改动（步 1 硬约束）。
#   同一组函数两种后端：tmux 实现与既有用例（cases/19–25）的隔离写法逐字等价；
#   herdr 实现走**私有 `XDG_CONFIG_HOME` 根** ⇒ 用户 `default` 会话「碰不到」（不是「小心别碰」）。
#
# 开关：`NAO_TEST_TERMINAL=tmux|herdr|auto`（**默认 tmux**；`auto` 一期 = tmux —— herdr 转默认属三期）
#
# 契约（后端差异只在本文件内；调用方只用下列函数）：
#   be_backend                    打印解析后的后端（tmux|herdr）；非法取值 ⇒ 非 0
#   be_init <lab-root> [session]  解析后端 + 建实验根 + 三道护栏（**不建 server**）
#   be_start_server [cols rows]   起 server（已就绪 ⇒ effect=0 幂等）+ be_ready 轮询就绪
#   be_ready                      50×100ms 轮询 + 5s 上限，超时 **fail loud**（禁固定 sleep）
#   be_panes                      打印 `<pane_id>\t<terminal_id>`（每行一个 pane）
#   be_pane_pid <pane_id>         打印该 pane 的 shell pid
#   be_new_pane [cwd]             新建 pane，打印 pane_id（首个 pane 由 session/workspace 创建）
#   be_run <pane_id> <cmd>        在既有 pane 内执行命令（fire-and-forget）
#   be_teardown                   stop + delete（herdr）/ kill-server（tmux）；判据看 **effect**
#   辅助：be_session_exists / be_sessions_dir / be_herdr / be_guard_session / be_herdr_protocol
#
# 硬约束（arch spike 实测；PRD 附一「最易引 flake 的两处」+ §五 BR6）：
#   ① 就绪禁固定 sleep：50×100ms 轮询 + 5s 上限 + 超时 fail loud（实测 API 就绪仅 69ms）；
#   ② **只隔离 `XDG_CONFIG_HOME`**：不动 `XDG_STATE_HOME`（mise 等工具会写它，实测会工具状态错乱）；
#   ③ 清环境要枚举：`TMUX`/`TMUX_PANE`/`TMUX_TMPDIR` 显式 `-u` + `HERDR_*` 全量 `unset`（只 `-u` 已知变量会漏）；
#   ④ **任何 herdr 调用缺 `--session` ⇒ FAIL**（实测无 `--session` 会静默读到用户 `default`）
#      ⇒ 全仓唯一入口 `_be_herdr_exec`：`--session` 由它注入；绕过它 = 没有调用点（静态断言在 cases/27）；
#   ⑤ 拆场 `stop` + `delete`：只 `stop` 会回放上一轮 pane 布局（实测），且第二次 `stop` rc≠0（容忍）。
#   ⑥ tmux 侧单一入口 `_be_tmux`：恒带 `-S "$BE_SOCK"`（#84 采样纪律：禁裸 socket 打生产 server）。
#
# 失败语义：守卫/前置失败一律 `BE-GUARD-FAIL:` / `BE-*-FAIL:` 打 stderr + 非 0（fail loud，不静默降级）。
# 归一：本文件**不**做断言（不打 [PASS]/[FAIL]）；断言与计分在用例侧（cases/27）。
set -uo pipefail

# ---------------------------------------------------------------- 基础
be_msg()        { printf '%s\n' "$*" >&2; }
be_guard_fail() { printf 'BE-GUARD-FAIL: %s\n' "$*" >&2; }
be_init_fail()  { printf 'BE-INIT-FAIL: %s\n' "$*" >&2; }
be_ready_fail() { printf 'BE-READY-FAIL: %s\n' "$*" >&2; }
be_stage_fail() { printf 'BE-STAGE-FAIL: %s\n' "$*" >&2; }

# 后端解析：未设 = tmux（默认）；auto 一期 = tmux；未知取值 fail loud（不猜）
be_backend() {
  case "${NAO_TEST_TERMINAL:-tmux}" in
    tmux)  printf 'tmux' ;;
    herdr) printf 'herdr' ;;
    auto)  printf 'tmux' ;;
    *)     be_guard_fail "NAO_TEST_TERMINAL=${NAO_TEST_TERMINAL:-} 非法（期望 tmux|herdr|auto）"; return 1 ;;
  esac
}

# ---------------------------------------------------------------- 护栏（三道 + 会话名）
# herdr 实验根必须**在 cache 下**（AC1.5：实验根不在 cache 下 ⇒ FAIL，不 SKIP）
_be_guard_herdr_root() {
  local cache="${BE_CACHE_ROOT:-}"
  [ -n "$cache" ] || { be_guard_fail "未设 T4_CACHE_DIR（herdr 实验根无法证明在 cache 下）"; return 1; }
  case "$BE_CFGROOT" in
    "$cache"/*) ;;
    *) be_guard_fail "herdr 实验根不在 \$T4_CACHE_DIR 下: $BE_CFGROOT（cache=$cache）"; return 1 ;;
  esac
  return 0
}

# tmux socket 必须在实验根内，且不得命中生产默认候选（#84 血训：绝不裸打生产 server）
_be_guard_tmux_sock() {
  local p tm="${TMUX:-}"
  case "$BE_SOCK" in
    "$BE_LAB"/*) ;;
    *) be_guard_fail "tmux socket 不在实验根内: $BE_SOCK"; return 1 ;;
  esac
  for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${tm%%,*}"; do
    if [ -n "$p" ] && [ "$BE_SOCK" = "$p" ]; then
      be_guard_fail "tmux socket 撞生产默认候选: $BE_SOCK"; return 1
    fi
  done
  return 0
}

# 会话名守卫（BR5/④）：空 ⇒ 缺 --session · default ⇒ 用户会话 · 实验根不在 cache 下 ⇒ 拒绝
# 这是「缺 --session ⇒ FAIL」的唯一实现点；cases/27 对它有正断言（含变异自证）。
be_guard_session() {
  local s="${1:-}"
  case "$s" in
    "")      be_guard_fail "缺 --session（无 --session 会静默读到用户 default）"; return 1 ;;
    default) be_guard_fail "会话名不得为 default（用户会话，实测无 --session 时会静默命中）"; return 1 ;;
    *[[:space:]]*|*/*)
             be_guard_fail "会话名非法（空白或 /）: $s"; return 1 ;;
  esac
  [ -n "${BE_CFGROOT:-}" ] || { be_guard_fail "未初始化 herdr 实验根（先 be_init）"; return 1; }
  _be_guard_herdr_root
}

# ---------------------------------------------------------------- 初始化
be_init() { # <lab-root> [session]
  local lab="${1:-}" sess="${2:-}"
  BE_BACKEND="$(be_backend)" || return 1
  [ -n "$lab" ] || { be_init_fail "缺 lab 根"; return 1; }
  mkdir -p "$lab" || { be_init_fail "无法创建 lab 根: $lab"; return 1; }
  BE_LAB="$(cd "$lab" && pwd)"
  BE_CACHE_ROOT="${BE_CACHE_ROOT:-${T4_CACHE_DIR:-}}"
  BE_SESSION="${sess:-nao-t4-$BE_BACKEND-$$}"
  # 就绪轮询参数（单点；AC1.7：50×100ms + 5s 上限）
  BE_POLL_MAX="${BE_POLL_MAX:-50}"
  BE_POLL_INT="${BE_POLL_INT:-0.1}"
  BE_START_EFFECT=0
  BE_TEARDOWN_EFFECT=0
  case "$BE_BACKEND" in
    tmux)
      BE_SOCK="$BE_LAB/sock/tmux-$(id -u)/default"
      _be_guard_tmux_sock || return 1
      ;;
    herdr)
      # 每次 be_init 都按 lab 根重算私有根（禁 `${BE_CFGROOT:-}` 粘连上一场；显式覆盖用 NAO_T4_BE_CFGROOT）
      BE_CFGROOT="${NAO_T4_BE_CFGROOT:-$BE_LAB/config}"
      _be_guard_herdr_root || return 1
      be_guard_session "$BE_SESSION" || return 1
      ;;
  esac
  return 0
}

# ---------------------------------------------------------------- 唯一入口：tmux / herdr
_be_tmux() { tmux -S "${BE_SOCK:?未初始化 BE_SOCK}" "$@"; }

# herdr 唯一调用入口。`--session` 由本函数注入（调用方**无法**绕过 ⇒ 缺 --session 不可能发生）；
# 环境清洗在此单点完成：TMUX* 显式 -u + `HERDR_*` **枚举** unset（只 -u 已知变量会漏）。
# XDG_CONFIG_HOME 指向私有实验根；**XDG_STATE_HOME 原样透传**（BR6③）。
# $1 = session；其余 = herdr 子命令与参数。BE_HERDR_SETSID=1 时用 setsid 脱离进程组（起 server 用）。
_be_herdr_exec() {
  local s="${1:-}"; shift
  be_guard_session "$s" || return 1
  [ "$#" -gt 0 ] || { be_guard_fail "herdr 调用缺子命令（session=$s）"; return 1; }
  local detach=()
  [ "${BE_HERDR_SETSID:-0}" = "1" ] && detach=(--setsid)
  XDG_CONFIG_HOME="$BE_CFGROOT" \
  env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR \
    bash -c 'for v in $(env | grep -o "^HERDR_[A-Z_]*"); do unset "$v"; done
             if [ "${1:-}" = "--setsid" ]; then shift; exec setsid herdr --session "$0" "$@"; fi
             exec herdr --session "$0" "$@"' "$s" "${detach[@]}" "$@"
}

be_herdr() { _be_herdr_exec "$@"; }   # 别名：调用方显式命名（语义 = 「经唯一入口」）

# 依赖门槛（AC1.5 第一类 ⇒ 调用方 SKIP 并给原因）：版本 + 协议。
# 版本/schema 都是离线元数据，但仍走唯一入口（口径统一：任何 herdr 调用都带 --session）。
be_herdr_protocol() { # <session> ⇒ 打印 protocol 数字；失败非 0
  local s="${1:-}" out
  out="$(be_herdr "$s" api schema 2>/dev/null)" || return 1
  sed -nE 's/^protocol:[[:space:]]*([0-9]+).*/\1/p' <<< "$out" | head -1
}

# ---------------------------------------------------------------- server 生命周期
# 就绪判定：**轮询**（50×100ms 上限 5s），超时 fail loud。禁固定 sleep（附一硬条件①）。
be_ready() {
  local i=1 out
  while [ "$i" -le "$BE_POLL_MAX" ]; do
    case "$BE_BACKEND" in
      tmux)
        _be_tmux list-sessions >/dev/null 2>&1 && return 0
        ;;
      herdr)
        # 真就绪判据 = API 应答（socket 可用），非「session 目录里已写 session.json」
        out="$(be_herdr "$BE_SESSION" api snapshot 2>/dev/null)" \
          && grep -q '"protocol"' <<< "$out" && return 0
        ;;
    esac
    [ "$i" -lt "$BE_POLL_MAX" ] && sleep "$BE_POLL_INT"   # 轮询间隔（非固定等待）
    i=$((i + 1))
  done
  be_ready_fail "$BE_BACKEND server 未在 $((BE_POLL_MAX))×${BE_POLL_INT}s 内就绪（已用尽轮询）: $BE_SESSION"
  return 1
}

be_start_server() { # [cols rows]
  local cols="${1:-80}" rows="${2:-40}"
  BE_START_EFFECT=0
  case "$BE_BACKEND" in
    tmux)
      if _be_tmux has-session -t "$BE_SESSION" >/dev/null 2>&1; then return 0; fi   # 已就绪 ⇒ effect=0
      mkdir -p "$(dirname "$BE_SOCK")" && chmod 700 "$(dirname "$BE_SOCK")" \
        || { be_stage_fail "无法创建隔离 socket 目录: $(dirname "$BE_SOCK")"; return 1; }
      _be_tmux new-session -d -s "$BE_SESSION" -x "$cols" -y "$rows" -c "$BE_LAB" >/dev/null 2>&1 \
        || { be_stage_fail "tmux new-session 失败（session=$BE_SESSION）"; return 1; }
      BE_START_EFFECT=1
      ;;
    herdr)
      if be_ready >/dev/null 2>&1; then return 0; fi                                # 已就绪 ⇒ effect=0
      mkdir -p "$BE_CFGROOT" || { be_stage_fail "无法创建 herdr 私有根: $BE_CFGROOT"; return 1; }
      # 起 server：setsid 脱离本进程组（否则用例退出可能带走 server）；日志落实验根，不污染用例输出。
      # 注：子 shell + `&` 恒 rc=0 ⇒ 成败不在此判，由 be_ready 轮询决定（超时 fail loud 且附日志尾）。
      ( BE_HERDR_SETSID=1 _be_herdr_exec "$BE_SESSION" server \
          >"$BE_CFGROOT/herdr-server-launch.log" 2>&1 & )
      BE_START_EFFECT=1
      ;;
  esac
  if ! be_ready; then
    if [ "$BE_BACKEND" = "herdr" ] && [ -f "$BE_CFGROOT/herdr-server-launch.log" ]; then
      be_ready_fail "herdr server 启动日志尾（诊断用，末 5 行）：\n$(tail -5 "$BE_CFGROOT/herdr-server-launch.log" 2>/dev/null)"
    fi
    return 1
  fi
  return 0
}

be_session_exists() {
  case "$BE_BACKEND" in
    tmux) _be_tmux has-session -t "$BE_SESSION" >/dev/null 2>&1 ;;
    herdr)
      local js
      js="$(be_herdr "$BE_SESSION" session list --json 2>/dev/null)" || return 1
      grep -qF "\"name\":\"$BE_SESSION\"" <<< "$js"
      ;;
    *) return 1 ;;
  esac
}

# herdr 会话目录（零残留断言用：sessions/ 空 ⇒ 无残留场）
be_sessions_dir() { printf '%s/herdr/sessions' "$BE_CFGROOT"; }

# 拆场：herdr = stop（容忍非 0）+ delete（幂等）；tmux = kill-server（容忍非 0）。
# 判据 = **effect**（会话是否真的消失），不看单个命令 rc（实测 stop 第二次 rc=1）。
be_teardown() {
  BE_TEARDOWN_EFFECT=0
  case "$BE_BACKEND" in
    tmux)
      _be_tmux has-session -t "$BE_SESSION" >/dev/null 2>&1 && BE_TEARDOWN_EFFECT=1
      _be_tmux kill-server >/dev/null 2>&1 || true
      ;;
    herdr)
      be_session_exists && BE_TEARDOWN_EFFECT=1
      be_herdr "$BE_SESSION" session stop   "$BE_SESSION" >/dev/null 2>&1 || true   # 第二次 rc≠0 ⇒ 容忍
      be_herdr "$BE_SESSION" session delete "$BE_SESSION" >/dev/null 2>&1 || true   # 幂等：第二次 effect=0
      ;;
  esac
  if be_session_exists; then
    be_stage_fail "拆场后会话仍存在: $BE_SESSION"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------- pane 视图
_be_json_lines() { # $1=取值表达式（node 里对 result 求值，须是**表达式**，不是语句块）
  node -e '
let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
  let j;try{j=JSON.parse(s)}catch(e){process.exit(2)}
  const r=j.result||{};
  const rows=( '"$1"' );
  for(const x of rows)process.stdout.write(x+"\n");
});'
}

be_panes() { # 打印 `<pane_id>\t<terminal_id>`
  case "$BE_BACKEND" in
    tmux)
      _be_tmux list-panes -s -t "$BE_SESSION" -F $'#{pane_id}\t#{pane_tty}' 2>/dev/null
      ;;
    herdr)
      local js
      js="$(be_herdr "$BE_SESSION" pane list 2>/dev/null)" || return 1
      printf '%s' "$js" | _be_json_lines '(r.panes||[]).map(p=>[p.pane_id,p.terminal_id].join("\t"))'
      ;;
  esac
}

be_pane_pid() { # <pane_id>
  local pane="${1:-}"
  [ -n "$pane" ] || { be_guard_fail "be_pane_pid 缺 pane_id"; return 1; }
  case "$BE_BACKEND" in
    tmux)
      _be_tmux list-panes -s -t "$BE_SESSION" -F '#{pane_id} #{pane_pid}' 2>/dev/null \
        | awk -v p="$pane" '$1==p{print $2; found=1} END{exit(found?0:1)}'
      ;;
    herdr)
      local js
      js="$(be_herdr "$BE_SESSION" pane process-info --pane "$pane" 2>/dev/null)" || return 1
      printf '%s' "$js" | _be_json_lines '[(r.process_info||{}).shell_pid].filter(x=>x!==undefined).map(String)'
      ;;
  esac
}

be_new_pane() { # [cwd]
  local cwd="${1:-$BE_LAB}" js
  case "$BE_BACKEND" in
    tmux)
      _be_tmux split-window -d -t "$BE_SESSION" -c "$cwd" -P -F '#{pane_id}' 2>/dev/null || {
        be_stage_fail "tmux split-window 失败（session=$BE_SESSION）"; return 1; }
      ;;
    herdr)
      local ws first
      ws="$(be_herdr "$BE_SESSION" workspace list 2>/dev/null)" || return 1
      if printf '%s' "$ws" | grep -q '"workspace_id"'; then
        first="$(be_panes)"; first="${first%%$'\n'*}"; first="${first%%$'\t'*}"   # 不走管道（避 SIGPIPE/T534 类假红）
        [ -n "$first" ] || { be_stage_fail "herdr 已有 workspace 但 pane 视图为空: $BE_SESSION"; return 1; }
        js="$(be_herdr "$BE_SESSION" pane split "$first" \
                --direction down --cwd "$cwd" --no-focus 2>/dev/null)" || {
          be_stage_fail "herdr pane split 失败（session=$BE_SESSION）"; return 1; }
      else
        js="$(be_herdr "$BE_SESSION" workspace create --cwd "$cwd" \
                --label "$BE_SESSION" --no-focus 2>/dev/null)" || {
          be_stage_fail "herdr workspace create 失败（session=$BE_SESSION）"; return 1; }
      fi
      printf '%s' "$js" | _be_json_lines '[((r.pane||r.root_pane)||{}).pane_id].filter(Boolean)'
      ;;
  esac
}

be_run() { # <pane_id> <cmd...>
  local pane="${1:-}"; shift
  [ -n "$pane" ] || { be_guard_fail "be_run 缺 pane_id"; return 1; }
  [ "$#" -gt 0 ] || { be_guard_fail "be_run 缺命令"; return 1; }
  case "$BE_BACKEND" in
    tmux)  _be_tmux send-keys -t "$pane" -- "$*" Enter 2>/dev/null ;;
    herdr) be_herdr "$BE_SESSION" pane run "$pane" "$*" >/dev/null 2>&1 ;;
  esac
}

# ---------------------------------------------------------------- 有界等待（禁固定 sleep 的可复用入口）
# 条件轮询：`be_wait_until <max> <interval> <cmd...>`；返回 0 = 条件成立，1 = 用尽。
# 用途（cases/27）：等 pane 内 `env > file` 落盘、等标记进程起来 —— 一律轮询，不写死 sleep。
be_wait_until() {
  local max="${1:-50}" int="${2:-0.1}"; shift 2
  local i=1
  while [ "$i" -le "$max" ]; do
    "$@" >/dev/null 2>&1 && return 0
    [ "$i" -lt "$max" ] && sleep "$int"
    i=$((i + 1))
  done
  return 1
}
