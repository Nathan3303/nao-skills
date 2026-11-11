#!/usr/bin/env bash
# T4 后端抽象层 —— PRD #96 一期步 1（Issue #96 · AC1.1–AC1.7 · BR6/BR7/BR8 · 附一）
#
# 定位：**测试侧**后端抽象。生产脚本 `.agents/scripts/nao-fleet.sh` 零改动（步 1 硬约束）。
#   同一组函数两种后端：tmux 实现与既有用例（cases/19–25）的隔离写法逐字等价；
#   herdr 实现走**私有 `XDG_CONFIG_HOME` 根** ⇒ 用户 `default` 会话「碰不到」（不是「小心别碰」）。
#
# 开关：`NAO_TEST_TERMINAL=tmux|herdr|auto`（#96 三期 P2：未设 = **herdr**，与生产默认一致；`auto` = herdr）
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
#   be_arm_cleanup                失败/中断兜底：把「停本场 server」链进 EXIT trap（保留原 $?）
#   be_sweep_orphans              起跑前扫「死 run 遗留」的 herdr server 并 stop（不碰用户根/活 run）
#   辅助：be_session_exists / be_sessions_dir / be_herdr / be_guard_session / be_herdr_protocol
#         be_orphan_server_count / _be_scan_herdr_servers（供用例按 effect 断言）
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

# 后端解析（#96 三期 P2）：来源优先级 NAO_TEST_TERMINAL > NAO_TERMINAL > **生产默认 herdr**；
#   auto = 生产默认 = herdr。未知取值 fail loud（不猜）。与 run.sh 的后端解析同口径（单点语义两处实现，
#   cases/27 有交叉断言）。
be_backend() {
  case "${NAO_TEST_TERMINAL:-${NAO_TERMINAL:-herdr}}" in
    tmux)  printf 'tmux' ;;
    herdr) printf 'herdr' ;;
    auto)  printf 'herdr' ;;
    *)     be_guard_fail "后端取值 ${NAO_TEST_TERMINAL:-${NAO_TERMINAL:-}} 非法（期望 tmux|herdr|auto）"; return 1 ;;
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

# sun_path 108 前置护栏（P3-2 · QA 实测）：`T4_CACHE_DIR` 过长时 herdr 在 bind 阶段抛
#   `Error: local socket name length exceeds capacity of sun_path`，栈深且会被上层误读成
#   「rc=9 / 兜底未点火」。⇒ 在 be_init 就 fail loud，给**当前长度 + 上限 + 可执行改法**。
#   判据用**最长**那个 socket：`herdr-client.sock`（实测会话目录里还有 `herdr.sock`，更短）。
#   sun_path = 108 含结尾 NUL ⇒ 可用上限 107；建议留余量到 ≤100（换机/换 herdr 版本不会擦边）。
_be_guard_sun_path() {
  local sock len hard=107 advice=100
  sock="$BE_CFGROOT/herdr/sessions/$BE_SESSION/herdr-client.sock"
  len=${#sock}
  [ "$len" -le "$hard" ] && return 0
  be_guard_fail "herdr socket 路径过长（sun_path 上限 108 含结尾 NUL ⇒ 可用 ${hard}；建议 ≤${advice} 留余量）
  当前长度: ${len} 字符（超限 $((len - hard))）
  超限路径: ${sock}
  改法    : 把 T4_CACHE_DIR 换短（如 T4_CACHE_DIR=/tmp/t4），或缩短会话名（当前 ${#BE_SESSION} 字符）"
  return 1
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

# ---------------------------------------------------------------- 实验根判定（结构性；守卫与孤儿 sweep 复用）
# 用户根一律拒（BR9）：`$HOME/.config/herdr` 及其下 —— 那是用户 `default` 会话。
#   实测用户 server 的 `XDG_CONFIG_HOME` 通常是 `$HOME/.config`（会话目录 = 其下 `herdr/`），
#   这条也覆盖「根正好是 `$HOME/.config`」以外的任何用户侧形态：凡不含 `nao-t4.*` 段且不在
#   当前 cache 下者一律不算实验根。
_be_is_user_herdr_root() {
  local r="${1:-}" h="${HOME:-}"
  [ -n "$r" ] && [ -n "$h" ] || return 1
  case "$r" in "$h/.config/herdr"|"$h/.config/herdr"/*|"$h/.config") return 0 ;; esac
  return 1
}

# t4 实验根 = 路径含 `nao-t4.*` 段（T524 缓存形态）或位于当前 BE_CACHE_ROOT 之下
_be_is_lab_root() {
  local r="${1:-}"
  [ -n "$r" ] || return 1
  _be_is_user_herdr_root "$r" && return 1
  case "$r" in */nao-t4.*/*) return 0 ;; esac
  if [ -n "${BE_CACHE_ROOT:-}" ]; then case "$r" in "$BE_CACHE_ROOT"/*) return 0 ;; esac; fi
  return 1
}

# 实验根所属的 cache 目录（`/tmp/nao-t4.ABC/lab/config` ⇒ `/tmp/nao-t4.ABC`；无形态则空）
_be_cache_of_root() { printf '%s' "${1:-}" | sed -nE 's#^(.*/nao-t4\.[^/]+)/.*$#\1#p'; }

# 会话名守卫（BR5/④）：空 ⇒ 缺 --session · default ⇒ 用户会话 · 根不是实验根 ⇒ 拒
# 这是「缺 --session ⇒ FAIL」的唯一实现点；cases/27 对它有正断言（含变异自证）。
be_guard_session() {
  local s="${1:-}" root="${BE_CFGROOT:-}"
  case "$s" in
    "")      be_guard_fail "缺 --session（无 --session 会静默读到用户 default）"; return 1 ;;
    default) be_guard_fail "会话名不得为 default（用户会话，实测无 --session 时会静默命中）"; return 1 ;;
    *[[:space:]]*|*/*)
             be_guard_fail "会话名非法（空白或 /）: $s"; return 1 ;;
  esac
  [ -n "$root" ] || { be_guard_fail "未初始化 herdr 实验根（先 be_init）"; return 1; }
  if _be_is_user_herdr_root "$root"; then
    be_guard_fail "会话根指向用户 herdr 根（$root）—— 绝不碰用户 default"; return 1
  fi
  _be_is_lab_root "$root" || { be_guard_fail "会话根不是 t4 实验根（$root）"; return 1; }
  return 0
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
  BE_CLEANUP_ARMED="${BE_CLEANUP_ARMED:-0}"     # 不覆盖已挂的兜底（ctx 切换不得丢保护）
  case "$BE_BACKEND" in
    tmux)
      BE_SOCK="$BE_LAB/sock/tmux-$(id -u)/default"
      _be_guard_tmux_sock || return 1
      ;;
    herdr)
      # 每次 be_init 都按 lab 根重算私有根（禁 `${BE_CFGROOT:-}` 粘连上一场；显式覆盖用 NAO_T4_BE_CFGROOT）
      BE_CFGROOT="${NAO_T4_BE_CFGROOT:-$BE_LAB/config}"
      _be_guard_herdr_root || return 1
      _be_guard_sun_path || return 1
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

# 临时切换上下文执行（孤儿 sweep 用：拿**孤儿自己的根**去 stop 它，不动调用方的场）
_be_with_ctx() { # <root> <session> <fn> [args...]
  local root="$1" sess="$2" fn="$3"; shift 3
  local s_root="${BE_CFGROOT:-}" s_sess="${BE_SESSION:-}" rc=0
  BE_CFGROOT="$root"; BE_SESSION="$sess"
  "$fn" "$@"; rc=$?
  BE_CFGROOT="$s_root"; BE_SESSION="$s_sess"
  return "$rc"
}

# ---------------------------------------------------------------- 孤儿 sweep（P2 缺陷修复）
# 缺陷：herdr server 用 `setsid` 脱离进程组 ⇒ 用例被中断 / 失败时 EXIT 钩子杀不掉它；
#   T524 口径失败**保留 cache**（好证据）但**进程**没人管 ⇒ 每次失败泄漏一个常驻 server。
# 三层防护（本文件单点实现）：① 起跑前扫孤儿（be_sweep_orphans）② 失败/中断兜底（be_arm_cleanup）
#   ③ 正常拆场（be_teardown）。判据一律看 **effect**（进程真的没了）不看 rc。
# 安全边界（绝不误伤）：
#   · 只认**实验根形态**（含 `nao-t4.*` 段 / 在 BE_CACHE_ROOT 下）；
#   · **用户根（$HOME/.config/herdr、$HOME/.config）结构上不可能被选中**；
#   · **活 run 的 cache 跳过**（有进程持有该 cache 的 `T4_CACHE_DIR=`）⇒ 并发跑不会互杀；
#     活 run 自己的残留由它自己的 teardown + EXIT 兜底负责；只有「死 run 遗留」才被清。
#   · **不删**任何目录（只停进程 + 删该会话场）；cache 目录按 T524 口径留给证据。

# 枚举 herdr server 进程：argv[0] basename == herdr，argv 含 `--session <n>` 且含 `server`
# 输出：`<pid>\t<session>\t<XDG_CONFIG_HOME>`（根缺失 = 空字段 ⇒ 调用方按「非实验根」处理）
_be_scan_herdr_servers() {
  local d pid args argv0 line prev name has_server root
  for d in /proc/[0-9]*; do
    pid="${d##*/}"
    [ -r "$d/cmdline" ] || continue
    args="$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null)" || continue
    [ -n "$args" ] || continue
    argv0="${args%%$'\n'*}"; argv0="${argv0##*/}"
    [ "$argv0" = "herdr" ] || continue
    name=""; has_server=0; prev=""
    while IFS= read -r line; do
      [ "$line" = "server" ] && has_server=1
      [ "$prev" = "--session" ] && name="$line"
      prev="$line"
    done <<< "$args"
    # 也纳管「无 --session 的 server」（用户 default 形态 = `herdr server`）—— 只为让负控有基线；
    # 它 roots 不在实验根判据内 ⇒ sweep 永远不会动它。
    [ "$has_server" = "1" ] || continue
    root="$(tr '\0' '\n' < "$d/environ" 2>/dev/null | sed -nE 's/^XDG_CONFIG_HOME=(.*)$/\1/p' | head -1)"
    printf '%s\t%s\t%s\n' "$pid" "$name" "$root"
  done
}

# 某进程的祖先里是否有 herdr（孤儿 server 的**子孙**会继承起跑方的 T4_CACHE_DIR；
#   实测 server 会起 curl 子进程 ⇒ 只看「排除 argv0=herdr」不够，会把死 run 的 cache 错判成活）
_be_pid_has_herdr_ancestor() {
  local cur="${1:-}" ppid a0 i=0 rest
  [ -n "$cur" ] || return 1
  while [ "$cur" != "1" ] && [ -n "$cur" ] && [ "$i" -lt 64 ]; do
    rest="$(sed 's/^[^)]*)//' "/proc/$cur/stat" 2>/dev/null)" || return 1
    ppid="$(printf '%s' "$rest" | awk '{print $2}')"
    case "$ppid" in ''|*[!0-9]*) return 1 ;; esac
    cur="$ppid"
    [ "$cur" = "1" ] && return 1
    a0="$(tr '\0' '\n' < "/proc/$cur/cmdline" 2>/dev/null | head -1)"; a0="${a0##*/}"
    [ "$a0" = "herdr" ] && return 0
    i=$((i + 1))
  done
  return 1
}

# 活 run 的 cache 根（有**非 herdr 世系**的进程持有 `T4_CACHE_DIR=<dir>`）：sweep 跳过，防并发误杀。
# 判据要排除「herdr 自身及其子孙」—— 否则孤儿 server 会把自己赖着的 cache 标成「活」（自锁，实测踩过）。
_be_live_cache_dirs() {
  local d v a0
  for d in /proc/[0-9]*; do
    [ -r "$d/environ" ] || continue
    a0="$(tr '\0' '\n' < "$d/cmdline" 2>/dev/null | head -1)"; a0="${a0##*/}"
    [ "$a0" = "herdr" ] && continue
    v="$(tr '\0' '\n' < "$d/environ" 2>/dev/null | sed -nE 's/^T4_CACHE_DIR=(.*)$/\1/p' | head -1)"
    [ -n "$v" ] || continue
    _be_pid_has_herdr_ancestor "${d##*/}" && continue
    printf '%s\n' "$v"
  done 2>/dev/null | sort -u
}

# 某根下的 server 进程数（effect 断言用；非 0 ⇒ 仍有残留）
be_orphan_server_count() { # <root>
  local root="${1:-}" pid name r n=0
  [ -n "$root" ] || return 1
  while IFS=$'\t' read -r pid name r; do
    [ "${r:-}" = "$root" ] && n=$((n + 1))
  done < <(_be_scan_herdr_servers)
  printf '%s' "$n"
}

# 某 pid 已不是 herdr server（僵尸进程 cmdline 为空 ⇒ 也不在扫描结果里）
_be_server_gone() {
  ! _be_scan_herdr_servers | awk -F'\t' -v p="${1:-}" '$1==p{found=1} END{exit(found?0:1)}'
}

# be_sweep_orphans —— 停掉「死 run 遗留」的 herdr server（含删其会话场）。幂等：第 2 次 effect=0。
# effect 三数：BE_SWEEP_EFFECT（真停掉数）/ BE_SWEEP_SKIPPED_LIVE（活 run 跳过）/ BE_SWEEP_SKIPPED_FOREIGN（非实验根跳过）
# 失败：BE_SWEEP_FAILED 逐条 `BE-SWEEP-WARN:` 点名（不静默），函数 rc=1。
be_sweep_orphans() {
  BE_SWEEP_EFFECT=0; BE_SWEEP_FAILED=0
  BE_SWEEP_SKIPPED_LIVE=0; BE_SWEEP_SKIPPED_FOREIGN=0
  BE_BACKEND="${BE_BACKEND:-$(be_backend)}" || return 1   # sweep 可能先于 be_init 调用（run.sh 起跑前）
  [ "$BE_BACKEND" = "herdr" ] || return 0                  # tmux 侧无 setsid 脱离问题（kill-server 已覆盖）
  BE_CACHE_ROOT="${BE_CACHE_ROOT:-${T4_CACHE_DIR:-}}"
  BE_POLL_MAX="${BE_POLL_MAX:-50}"; BE_POLL_INT="${BE_POLL_INT:-0.1}"
  BE_CLEANUP_ARMED="${BE_CLEANUP_ARMED:-0}"
  local pid name root cache live
  live="$(_be_live_cache_dirs)"
  while IFS=$'\t' read -r pid name root; do
    [ -n "${pid:-}" ] || continue
    if ! _be_is_lab_root "${root:-}" || [ -z "${name:-}" ]; then
      BE_SWEEP_SKIPPED_FOREIGN=$((BE_SWEEP_SKIPPED_FOREIGN + 1)); continue
    fi
    cache="$(_be_cache_of_root "$root")"
    if [ -n "$cache" ] && grep -qxF -- "$cache" <<< "$live"; then
      BE_SWEEP_SKIPPED_LIVE=$((BE_SWEEP_SKIPPED_LIVE + 1)); continue
    fi
    _be_with_ctx "$root" "$name" be_teardown >/dev/null 2>&1 || true
    # 兜底：会话场不可达（如 cache 目录已被删 ⇒ socket 消失，`session stop` 够不着）⇒ 按 pid 终止。
    #   安全性由上层判据保证（该 pid 的 XDG_CONFIG_HOME 已是**实验根**，绝不可能是用户 server）。
    if ! be_wait_until 20 0.1 _be_server_gone "$pid"; then
      be_msg "BE-SWEEP-NOTE: 会话场不可达，按 pid 终止（pid=$pid session=$name）"
      kill -TERM "$pid" 2>/dev/null || true
      if ! be_wait_until 20 0.1 _be_server_gone "$pid"; then
        kill -KILL "$pid" 2>/dev/null || true
      fi
    fi
    # effect 判据：该 pid 不再是 herdr server 进程（僵尸 cmdline 为空 ⇒ 也不在扫描结果里）
    if be_wait_until 20 0.1 _be_server_gone "$pid"; then
      BE_SWEEP_EFFECT=$((BE_SWEEP_EFFECT + 1))
    else
      BE_SWEEP_FAILED=$((BE_SWEEP_FAILED + 1))
      be_msg "BE-SWEEP-WARN: 孤儿 server 未停掉（pid=$pid session=$name root=$root）—— 下次起跑重试"
    fi
  done < <(_be_scan_herdr_servers)
  [ "$BE_SWEEP_FAILED" = "0" ] || return 1
  return 0
}

# 失败/中断兜底：把「停本场 server」前置进既有 EXIT trap（lib.sh 的 t4_cache_cleanup 必须最后跑且拿到原 $?）。
# 不能 `trap X EXIT` 直接覆盖 —— 那会吞掉 T524 的缓存生命周期语义（cases/14）。
_be_chain_exit_hook() { # <fn>
  local fn="${1:-}" prev cmd
  prev="$(trap -p EXIT)"
  case "$prev" in
    '') trap "$fn" EXIT; return 0 ;;
    "trap -- '"*"' EXIT")
      cmd="${prev#trap -- \'}"; cmd="${cmd%\' EXIT}"
      case "$cmd" in *"'"*) be_msg "BE-WARN: 既有 EXIT trap 含单引号，无法安全接管（$prev）"; return 1 ;; esac
      trap "$fn; $cmd" EXIT
      return 0 ;;
    *) be_msg "BE-WARN: 无法解析既有 EXIT trap（$prev），跳过失败路径兜底"; return 1 ;;
  esac
}

_be_exit_stop() { # EXIT 钩子：必须原样返回 $?（后继 t4_cache_cleanup 按它判「失败保留缓存」）
  local rc=$?
  [ "${BE_CLEANUP_ARMED:-0}" = "1" ] && [ "${BE_BACKEND:-}" = "herdr" ] || return "$rc"
  be_session_exists 2>/dev/null || return "$rc"
  if be_teardown >/dev/null 2>&1; then
    printf 'BE-CLEANUP: 失败/中断路径兜底已停本场 server（%s）\n' "${BE_SESSION:-}" >&2
  else
    printf 'BE-CLEANUP-WARN: 兜底 stop 失败（session=%s root=%s）—— 下次起跑由 be_sweep_orphans 清扫\n' \
      "${BE_SESSION:-}" "${BE_CFGROOT:-}" >&2
  fi
  return "$rc"
}

# 挂上兜底（herdr 起 server 成功后调；tmux 无异步 server）
be_arm_cleanup() {
  [ "$BE_BACKEND" = "herdr" ] || return 0
  BE_ARMED_SESSION="$BE_SESSION"
  BE_CLEANUP_ARMED=1
  [ "${BE_HOOK_CHAINED:-0}" = "1" ] && return 0     # 只链一次（钩子按当时 BE_SESSION 收场，避免 trap 串增殖）
  _be_chain_exit_hook _be_exit_stop || return 1
  BE_HOOK_CHAINED=1
  return 0
}

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
  # 失败/中断兜底（P2 缺陷修复）：setsid 的 server 不在本进程组 ⇒ 必须显式挂 EXIT 钩子
  be_arm_cleanup
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
  # 正常拆场完成 ⇒ 卸下兜底（只认被 arm 的那场；sweep 拆别人的场不得卸自己的保护）
  if [ "${BE_SESSION:-}" = "${BE_ARMED_SESSION:-}" ]; then BE_CLEANUP_ARMED=0; fi
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
      local first
      # 以 **pane 视图**为准（不是 workspace 表）：workspace 可能还在但 pane 已关空 ⇒ 应新建 workspace，
      #   否则 split 无锚点（实测：关掉最后一个 pane 后再建 pane 时 pane list 为空）。
      first="$(be_panes)"; first="${first%%$'\n'*}"; first="${first%%$'\t'*}"   # 不走管道（避 SIGPIPE/T534 类假红）
      if [ -n "$first" ]; then
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

# ---------------------------------------------------------------- 用例侧夹具 API（B4 · D 类迁移）
# 目的：D 类用例（19/20/21/23/24）的**夹具**只经本组函数 ⇒ tmux/herdr 差异单点收在此处；
#   用例正文只断言「我们自己的输出 / argv / 文件内容」（PRD AC2.7 的 shared 定义）。
# 前置：已 `be_init`；herdr 侧必须在 `be_start_server` **之前** export 好要被 pane 继承的环境
#   （server 把自己起跑时的环境交给 pane —— 如 PI_CODING_AGENT_DIR，避免写用户 ~/.pi）。
# 纪律：本组内 tmux 调用一律经 `_be_tmux`（恒带 -S），herdr 一律经 `be_herdr`（恒带 --session）。

# 起 server 并保证「至少一个 pane」（后端无关的调用者场景）：
#   tmux = server 自带一个 shell pane；herdr = 无 workspace 就没有 pane ⇒ 首个 pane 由 workspace 建。
be_ensure_scene() {
  be_start_server || return 1
  if [ -z "$(be_panes 2>/dev/null)" ]; then
    be_new_pane "$BE_LAB" >/dev/null || return 1
  fi
  return 0
}

be_caller_pane() { # 本场首个 pane（夹具里的「调用者」）
  local first
  first="$(be_panes 2>/dev/null)"; first="${first%%$'\n'*}"; first="${first%%$'\t'*}"
  printf '%s' "$first"
}

be_pane_count() { # 本场 pane 数（只数本会话/场，不数整 server）
  local n; n="$(be_panes 2>/dev/null | grep -c . || true)"; printf '%s' "${n:-0}"
}

be_pane_alive() { # <pane_id> → 0 存活 / 1 不在
  local p="${1:-}"
  [ -n "$p" ] || return 1
  be_panes 2>/dev/null | awk -F'\t' -v p="$p" '$1 == p { f = 1 } END { exit(f ? 0 : 1) }'
}

be_set_name() { # <pane_id> <会话名> [仓标签] —— 置身份：tmux = 标题契约 · herdr = pane.label
  local p="${1:-}" n="${2:-}" repo="${3:-}"
  [ -n "$p" ] && [ -n "$n" ] || { be_guard_fail "be_set_name 缺 pane/name"; return 1; }
  [ -n "$repo" ] || repo="$(basename "${BE_LAB:-.}")"
  case "$BE_BACKEND" in
    tmux)  _be_tmux select-pane -t "$p" -T "π - $n - $repo" >/dev/null 2>&1 ;;
    herdr) be_herdr "$BE_SESSION" pane rename "$p" "$n" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

be_pane_cwd() { # <pane_id> → 该 pane 的工作目录
  local p="${1:-}" js
  [ -n "$p" ] || return 1
  case "$BE_BACKEND" in
    tmux)  _be_tmux display-message -p -t "$p" '#{pane_current_path}' 2>/dev/null ;;
    herdr)
      js="$(be_herdr "$BE_SESSION" pane list 2>/dev/null)" || return 1
      printf '%s' "$js" | _be_json_lines \
        "(r.panes||[]).filter(p=>p.pane_id===\"$p\").map(p=>p.cwd||p.foreground_cwd||\"\")"
      ;;
    *) return 1 ;;
  esac
}

be_pane_cmdline() { # <pane_id> → 启动命令行（tmux: pane_start_command · herdr: 前台进程 cmdline）
  local p="${1:-}" js
  [ -n "$p" ] || return 1
  case "$BE_BACKEND" in
    tmux)  _be_tmux display-message -p -t "$p" '#{pane_start_command}' 2>/dev/null ;;
    herdr)
      js="$(be_herdr "$BE_SESSION" pane process-info --pane "$p" 2>/dev/null)" || return 1
      printf '%s' "$js" | _be_json_lines \
        '((r.process_info||{}).foreground_processes||[]).map(x=>x.cmdline||"").filter(Boolean)'
      ;;
    *) return 1 ;;
  esac
}

be_pane_label() { # <pane_id> → 身份面（tmux = pane_title 契约串 · herdr = pane.label）
  local p="${1:-}" js
  [ -n "$p" ] || return 1
  case "$BE_BACKEND" in
    tmux)  _be_tmux display-message -p -t "$p" '#{pane_title}' 2>/dev/null ;;
    herdr)
      js="$(be_herdr "$BE_SESSION" pane list 2>/dev/null)" || return 1
      printf '%s' "$js" | _be_json_lines "(r.panes||[]).filter(p=>p.pane_id===\"$p\").map(p=>p.label||\"\")"
      ;;
    *) return 1 ;;
  esac
}

be_kill_pane() { # <pane_id> —— 关 pane（收尾/隔离用；判据看 effect 不看 rc）
  local p="${1:-}"
  [ -n "$p" ] || return 1
  case "$BE_BACKEND" in
    tmux)  _be_tmux kill-pane -t "$p" >/dev/null 2>&1 || true ;;
    herdr) be_herdr "$BE_SESSION" pane close "$p" >/dev/null 2>&1 || true ;;
  esac
  return 0
}

be_scene_signature() { # 现场签名（排序后逐行）：pane + 会话/workspace —— 「零副作用」断言用
  case "$BE_BACKEND" in
    tmux)
      { _be_tmux list-panes -a -F 'pane #{pane_id}' 2>/dev/null || true
        _be_tmux list-sessions -F 'sess #{session_name}' 2>/dev/null || true
      } | sort ;;
    herdr)
      { be_panes 2>/dev/null | awk -F'\t' 'NF { print "pane " $1 }'
        be_herdr "$BE_SESSION" workspace list 2>/dev/null \
          | _be_json_lines '(r.workspaces||[]).map(w=>"ws "+w.workspace_id)' || true
      } | sort ;;
    *) return 1 ;;
  esac
}

be_fleet_handles() { # 打印运行生产脚本所需的后端句柄（每行 VAR=VAL），供 `env` 直接展开
  # #96 三期 P2（默认翻 herdr）：**两后端都显式给 NAO_TERMINAL** —— 测试不得依赖生产默认值
  #   （否则同一用例在不同默认下走不同后端）。tmux 侧多给一行 = 唯一差异，其余逐字不变。
  case "$BE_BACKEND" in
    tmux)
      local td; td="$(dirname "$(dirname "$BE_SOCK")")"
      printf 'NAO_TERMINAL=tmux\nTMUX=%s,0,0\nTMUX_PANE=%s\nTMUX_TMPDIR=%s\n' "$BE_SOCK" "$(be_caller_pane)" "$td" ;;
    herdr)
      printf 'NAO_TERMINAL=herdr\nHERDR_ENV=1\nHERDR_SESSION=%s\nHERDR_SOCKET_PATH=%s/herdr/sessions/%s/herdr.sock\nXDG_CONFIG_HOME=%s\n' \
        "$BE_SESSION" "$BE_CFGROOT" "$BE_SESSION" "$BE_CFGROOT" ;;
    *) return 1 ;;
  esac
}

# 跑生产脚本（本用例的后端句柄由 be_fleet_handles 注入；调用方只补业务 env）。
# 结果：BE_RC / BE_OUT / BE_ERR / BE_OUT_ANSI / BE_ERR_ANSI（ANSI 已去色）。
be_run_fleet() { # <cwd 目录> <args...>
  local dir="${1:-}"; shift
  [ -n "$dir" ] || { be_guard_fail "be_run_fleet 缺工作目录"; return 1; }
  command -v t4_run_in_dir >/dev/null 2>&1 || { be_guard_fail "be_run_fleet 需要 lib.sh（t4_run_in_dir）"; return 1; }
  local script="${BE_FLEET_SCRIPT:-${BE_FLEET_ROOT:-$BE_LAB}/.agents/scripts/nao-fleet.sh}"
  local -a envs=(env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR
                 -u HERDR_ENV -u HERDR_SESSION -u HERDR_SOCKET_PATH -u HERDR_SOCKET_FILE)
  local kv
  # BE_FLEET_NO_HANDLES=1：不注入后端句柄（负控用：验「不在终端内」时入口闸门必须 exit 3）
  if [ "${BE_FLEET_NO_HANDLES:-0}" != "1" ]; then
    while IFS= read -r kv; do [ -n "$kv" ] && envs+=("$kv"); done < <(be_fleet_handles)
  fi
  t4_run_in_dir "$dir" "${envs[@]}" timeout "${BE_FLEET_TIMEOUT:-120}" \
    bash "$script" "$@"
  BE_RC=$T4_RC; BE_OUT=$T4_OUT; BE_ERR=$T4_ERR
  BE_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
  BE_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  return 0
}

# 造一个「可被舰队识别」的夹具会话（D 类用例的唯一身份入口）：
#   tmux  = 由 pane 内进程自己输出 **OSC 0** 后再 `exec sleep`（#90 定性的 flake 根因是
#           `select-pane -T` 会被 PS1 随后重写；进程自己设且不再有 shell 则标题恒定）。
#           需要「只是改标题」的原语时用 `be_set_name`（= select-pane -T）。
#   herdr = 先 `pane rename` 写 label，再在 pane 内起 `pi --name <名>`（在线证据链要求
#           pane.label ∧ 前台 pi ∧ argv --name 三者自洽；替身按命令推导前台进程与 agent 条目）。
be_fixture_session() { # <pane_id> <会话名> [仓标签]
  local p="${1:-}" n="${2:-}" repo="${3:-}"
  [ -n "$p" ] && [ -n "$n" ] || { be_guard_fail "be_fixture_session 缺 pane/name"; return 1; }
  [ -n "$repo" ] || repo="$(basename "${BE_LAB:-.}")"
  local want i
  case "$BE_BACKEND" in
    tmux)  want="π - $n - $repo"
           be_run "$p" "printf '\\033]0;$want\\007'; exec sleep \"\${BE_FIXTURE_IDLE_SECS:-900}\"" || return 1 ;;
    herdr) want="$n"
           be_set_name "$p" "$n" "$repo" || return 1
           be_run "$p" "exec pi --name $n" || return 1 ;;
    *) return 1 ;;
  esac
  # 有界确认（禁固定 sleep）：send-keys / pane run 都是 fire-and-forget ⇒ 必须等身份面**真的**就位，
  #   否则紧随其后的 status 会读到「还没命名」的 pane（实测：AC3 冲突夹具若不等标题就位会假红）。
  for i in $(seq 1 "${BE_POLL_MAX:-50}"); do
    [ "$(be_pane_label "$p" 2>/dev/null)" = "$want" ] && return 0
    sleep "${BE_POLL_INT:-0.1}"
  done
  be_stage_fail "be_fixture_session 身份未就绪（pane=$p 期望=[$want] 实际=[$(be_pane_label "$p" 2>/dev/null)]）"
  return 1
}

be_pane_argv() { # <pane_id> → 每行一个 argv 元素（不含 argv[0]；与桩 pi 落盘同口径）
  local p="${1:-}" js
  [ -n "$p" ] || return 1
  case "$BE_BACKEND" in
    herdr)
      js="$(be_herdr "$BE_SESSION" pane process-info --pane "$p" 2>/dev/null)" || return 1
      printf '%s' "$js" | _be_json_lines \
        '((((r.process_info||{}).foreground_processes||[])[0]||{}).argv||[]).slice(1)'
      ;;
    tmux) return 0 ;;   # tmux 侧无法取 argv（既有用例改用桩进程日志）
    *) return 1 ;;
  esac
}

# 按 `--name <名>` 找到 pane（D 类用例：spawn 之后按名字定位新 pane）
be_pane_by_name() { # <name> → pane_id（无则空）
  local want="${1:-}" p c
  [ -n "$want" ] || return 1
  while IFS=$'\t' read -r p _; do
    [ -n "$p" ] || continue
    c="$(be_pane_cmdline "$p" 2>/dev/null)"
    case "$c" in
      *"--name $want "*|*"--name $want") printf '%s' "$p"; return 0 ;;
    esac
  done < <(be_panes 2>/dev/null)
  return 0
}
