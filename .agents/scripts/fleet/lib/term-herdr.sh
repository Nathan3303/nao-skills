# =============================================================================
# fleet/lib/term-herdr.sh — herdr 后端实现（唯一后端程序的 TUI 形态）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term（常量与门面基座）；运行期另调 manifest 命名谓词与 session 名册（既有晚绑定调用，纯搬迁未改）
# 身份/归属/忙闲一律取 herdr 结构化事实（pane.label / cwd / agent_status），禁读终端标题。
# 唯一对外入口 = `_term_herdr_exec`（本文件内 `herdr` 命令位的唯一合法点，静态闸守）。
# =============================================================================

# >>> term-facade-herdr BEGIN
# herdr 后端实现（本区间**禁出现** tmux 句柄/标题字段名：静态 lint t4_scan_term_herdr_forbidden）
#   会话名来源 = 环境变量 HERDR_SESSION（herdr pane 内天然存在）；所有调用经唯一入口注入 --session。
_term_herdr_exec() {  # [--server-start] <herdr 子命令…> —— 唯一入口：--session 由此注入（调用方无法绕过）
  local s="${HERDR_SESSION:-}" v ss=0
  # T544（Issue #116）：起 server 的身份由**显式首参数**传，禁再用环境变量 ——
  #   旧写法 `_TERM_HERDR_SERVER_START=1 _term_herdr_exec server` 会被 bash 连环境一起交给子进程
  #   ⇒ herdr server 继承该旗标 ⇒ 它 spawn 的每个 pane 都带它 ⇒ pane 内**每次**调用都误走 server-start
  #   分支（多一层 env -u + setsid，并清掉子进程的 HERDR_*，含 HERDR_SOCKET_PATH）。
  #   参数不进 env：pane 环境里即使人为注入同名变量也不会触发本分支（负控见报告 T544 判据 3）。
  if [[ "${1-}" == "--server-start" ]]; then ss=1; shift; fi
  # T554/AC5：`default` 与专用 session 等价（不再拒）——只有「空会话名」无法注入 --session，属实现/前提缺陷。
  if [[ -z "$s" ]]; then
    warn "herdr 调用缺会话（HERDR_SESSION 为空）—— 拒绝执行（无 --session 会静默读到用户 default）"
    return 1
  fi
  # BR6（B2）：起 server 的**唯一**实现点 —— 清宿主终端句柄（三项，名表在通用区声明）+ **枚举**清 HERDR_*
  #   （只 -u 已知变量会漏）；setsid 脱离进程组（无 setsid 的平台降级为普通后台）。
  if (( ss )); then
    local -a hu=() pre=()
    for v in "${_TERM_HOST_HANDLE_VARS[@]}"; do hu+=(-u "$v"); done
    # T544 迁移带：调用方 pane 若由**旧** server 起（env 仍带历史旗标），不摘就会被新 server 继承、
    #   再复制给它 spawn 的所有新 pane（新 pane 里没人读它，但「pane env 干净」判据会永久不成立）。
    hu+=(-u _TERM_HERDR_SERVER_START)
    command -v setsid >/dev/null 2>&1 && pre=(setsid)
    env "${hu[@]}" "${pre[@]}" bash -c 'for v in $(env | grep -o "^HERDR_[A-Z_]*"); do unset "$v"; done; exec herdr --session "$0" "$@"' "$s" "$@"
    return $?
  fi
  herdr --session "$s" "$@"
}

# 路径归一（realpath -m：不要求存在；无 realpath 的平台退化为字面串）
_term_path_norm() { realpath -m -- "${1-}" 2>/dev/null || printf '%s\n' "${1-}"; }

# 前提闸门（herdr）：不满足 ⇒ exit 3（命令未执行）；**禁**从 `session list`/`pane current` 反推会话名
_term_herdr_require() {
  command -v herdr >/dev/null 2>&1 || {
    printf '需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试；旧版 tmux 后端已移除，需要它请 pin 回 ≤0.27.x）\n' >&2
    exit 3
  }
  if [[ "${HERDR_ENV:-}" != "1" ]]; then
    printf '需要 herdr pane：HERDR_ENV=1 缺失（herdr 后端只在其 pane 内运行；从外部推断会话名属猜测面，禁）—— 在该 herdr 会话的 pane 内重试（旧版 tmux 后端已移除）\n' >&2
    exit 3
  fi
  local s="${HERDR_SESSION:-}" sp="${HERDR_SOCKET_PATH:-}" root rootp spp
  # T554/AC5：default 全放行（ensure/status/close 直接可用）；仅空名/非法字符仍是前提不满足。
  if [[ -z "$s" || ! "$s" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf '需要 herdr 会话：HERDR_SESSION=%s 不可用（须非空、^[A-Za-z0-9._-]+$）—— 在有效 herdr 会话的 pane 内重试（旧版 tmux 后端已移除）\n' "${s:-<空>}" >&2
    exit 3
  fi
  # BR6：socket 必须落在**目标根**下（不是「任意 */sessions/<名>/*」——后者对 stale/外贸 env 等于死守卫）。
  #   根 = `${XDG_CONFIG_HOME:-$HOME/.config}/herdr`（与 herdr CLI 的会话目录推导同源）。
  root="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
  rootp="$(_term_path_norm "$root/sessions/$s")"
  spp="$(_term_path_norm "$sp")"
  if [[ -z "$sp" || "$spp" != "$rootp"/* ]]; then
    printf '需要 herdr 会话目录：HERDR_SOCKET_PATH=%s 不在目标根 %s/ 下（stale/外贸 env ⇒ 拒绝，防串台）—— 在目标会话 pane 内重试（旧版 tmux 后端已移除）\n' \
      "${sp:-<空>}" "$rootp" >&2
    exit 3
  fi
  local schema proto
  if ! schema="$(_term_herdr_exec api schema 2>/dev/null)"; then
    printf 'herdr api schema 不可用（server/CLI 异常）：无法校验 protocol ⇒ 拒绝执行（核对 herdr ≥0.9.1 / server 状态后重试；旧版 tmux 后端已移除）\n' >&2
    exit 3
  fi
  proto="$(printf '%s\n' "$schema" | sed -n 's/^protocol:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [[ "$proto" != "$TERM_HERDR_PROTOCOL" ]]; then
    printf 'herdr protocol=%s ≠ %s（破坏性变更 ⇒ fail loud，不静默降级；请升级 nao-skill，或 pin 回 ≤0.27.x）\n' \
      "${proto:-<未知>}" "$TERM_HERDR_PROTOCOL" >&2
    exit 3
  fi
  if $VERBOSE; then
    local hver
    hver="$(_term_herdr_exec --version 2>/dev/null | head -1)"
    printf '  · herdr %s（protocol %s）\n' "${hver:-?}" "$proto" >&2
  fi
  return 0
}

_term_json_str() {  # <json 行> <键> → 字符串值（无则空）
  sed -n 's/.*"'"$2"'":"\([^"]*\)".*/\1/p' <<< "${1-}" | head -1
}
_term_json_raw() {  # <json 行> <键> → 原始值（数字/布尔；无则空）
  sed -n 's/.*"'"$2"'":\([^,}]*\).*/\1/p' <<< "${1-}" | head -1
}
_term_json_objs() {  # stdin 紧凑 JSON → 每行一个对象（按 `},{` 切；已实测 pane/agent/process 对象内无该序列）
  sed 's/},{/}\n{/g'
}
_term_argv_name() {  # <argv 串> → `--name` 的值（无则空）
  awk '{ for (i = 1; i < NF; i++) if ($i == "--name") { print $(i + 1); exit } }' <<< "${1-}"
}

# 快照字段归一（同族护栏 · T558/#160）：`term_snapshot` 的 TSV 行要求每个可变字段**非空且不含 TAB**
#   —— 空字段 / 字段内 TAB 会让下游 `IFS=$'\t' read` 左移或串列（#160 P0 就是这一族）。
#   规则：字段内 TAB/CR/LF ⇒ 空格；空 ⇒ `-`（与既有 `${x:--}` 口径一致，单点收此）。
_TSV_NORM=""
_term_tsv_norm() {  # <value> → _TSV_NORM
  local v="${1-}"
  v="${v//$'\t'/ }"
  v="${v//$'\r'/ }"
  v="${v//$'\n'/ }"
  _TSV_NORM="${v:--}"
}

_term_herdr_argv() {  # <pane_id> → 每行 "process-name<TAB>argv"（全部前台进程，不只首个）
  local pid="${1-}" js obj nm av
  [[ -n "$pid" ]] || return 0
  js="$(_term_herdr_exec pane process-info --pane "$pid" 2>/dev/null)" || return 0
  [[ -n "$js" ]] || return 0
  while IFS= read -r obj; do
    [[ "$obj" == *'"argv":'* ]] || continue
    nm="$(_term_json_str "$obj" name)"
    av="$(sed -n 's/.*"argv":\[\([^]]*\)\].*/\1/p' <<< "$obj" | tr -d '"' | sed 's/,/ /g')"
    printf '%s\t%s\n' "${nm:-?}" "$av"
  done < <(_term_json_objs <<< "$js")
}

_term_herdr_snapshot() {
  local pl al
  pl="$(_term_herdr_exec pane list 2>/dev/null)" || { warn "herdr pane list 失败（server 未就绪？）"; return 1; }
  if [[ -z "$pl" || "$pl" == *'"error"'* ]]; then
    warn "herdr pane list 不可用：$(printf '%s' "$pl" | head -c 200)"
    return 1
  fi
  al="$(_term_herdr_exec agent list 2>/dev/null)" || al=""
  # agent list → 按 pane_id 索引（seq / hook 权威 / 跨系统会话身份 / 状态）
  local -A ag_seq=() ag_hook=() ag_sess=() ag_stat=()
  local obj pid seq hook sess stat
  while IFS= read -r obj; do
    pid="$(_term_json_str "$obj" pane_id)"
    [[ -n "$pid" ]] || continue
    seq="$(_term_json_raw "$obj" state_change_seq)"
    hook="$(_term_json_raw "$obj" screen_detection_skipped)"
    sess="$(_term_json_str "$obj" value)"
    stat="$(_term_json_str "$obj" agent_status)"
    ag_seq["$pid"]="${seq:--}"; ag_sess["$pid"]="${sess:--}"; ag_stat["$pid"]="${stat:--}"
    case "$hook" in true) ag_hook["$pid"]=1 ;; *) ag_hook["$pid"]=0 ;; esac
  done < <(_term_json_objs <<< "$al")
  # pane list → 每行一个带 label 的 pane（无 label 的 pane 不属舰队会话，B1 不判）
  local label cwd fgcwd astat tid fg pname avline avname st wsid nlabel ntid ncwd nfgcwd nwsid task ntask
  while IFS= read -r obj; do
    label="$(_term_json_str "$obj" label)"
    [[ -n "$label" ]] || continue
    _term_tsv_norm "$label"; nlabel="$_TSV_NORM"
    pid="$(_term_json_str "$obj" pane_id)"
    wsid="$(_term_json_str "$obj" workspace_id)"
    task="$(fleet_meta_read "$(fleet_meta_wsref "$wsid")" "$pid")"
    tid="$(_term_json_str "$obj" terminal_id)"
    cwd="$(_term_json_str "$obj" cwd)"
    fgcwd="$(_term_json_str "$obj" foreground_cwd)"
    astat="$(_term_json_str "$obj" agent_status)"
    _term_tsv_norm "$tid";   ntid="$_TSV_NORM"
    _term_tsv_norm "$cwd";   ncwd="$_TSV_NORM"
    _term_tsv_norm "$fgcwd"; nfgcwd="$_TSV_NORM"
    _term_tsv_norm "$wsid";  nwsid="$_TSV_NORM"
    _term_tsv_norm "$task";  ntask="$_TSV_NORM"
    fg=""; avname=""
    while IFS=$'\t' read -r pname avline; do
      [[ -n "$pname" ]] || continue
      [[ -n "$fg" ]] || fg="$pname"
      if [[ "$pname" == "pi" ]]; then
        fg="pi"; avname="$(_term_argv_name "$avline")"; break
      fi
    done < <(_term_herdr_argv "$pid")
    st="${ag_stat[$pid]:-}"; [[ -n "$st" ]] || st="${astat:--}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$nlabel" "$pid" "$ntid" "$ncwd" "$nfgcwd" "${fg:--}" \
      "$st" "${ag_seq[$pid]:--}" "${ag_sess[$pid]:--}" "${avname:--}" "${ag_hook[$pid]:-0}" "$nwsid" "$ntask"
  done < <(_term_json_objs <<< "$pl")
}

_term_herdr_liveness() {  # <name> [repo] → verdict/state/seq/hook（只读快照，零外部调用）
  local name="${1-}" repo="${2-}" rows="" line rp="" filtered=""
  local v="" state="-" rq="-" rh="-" c1 c2 fg astat seq sess avname hook rv
  [[ -n "$name" ]] || { printf 'absent\t-\t-\t-\n'; return 0; }
  rows="$(term_snapshot 2>/dev/null | awk -F'\t' -v n="$name" '$1==n')" || rows=""
  [[ -n "$rows" ]] || { printf 'absent\t-\t-\t-\n'; return 0; }
  if [[ -n "$repo" ]]; then
    rp="$(nao_phys_path "$repo")"
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      IFS=$'\t' read -r _ _ _ c1 c2 _ <<< "$line"
      if { [[ "$c1" != "-" ]] && repo_contains_path "$rp" "$(nao_phys_path "$c1")"; } \
         || { [[ "$c2" != "-" ]] && repo_contains_path "$rp" "$(nao_phys_path "$c2")"; }; then
        filtered+="$line"$'\n'
      fi
    done <<< "$rows"
    rows="${filtered%$'\n'}"
    [[ -n "$rows" ]] || { printf 'absent\t-\t-\t-\n'; return 0; }
  fi
  # B2：同名 label 多 pane ⇒ 歧义（命中多个 ⇒ warn 点名 + **不猜**：既不判 online，也不静默挑一个）
  local nrows
  nrows="$(printf '%s\n' "$rows" | grep -c . || true)"
  if (( nrows > 1 )); then
    warn "同名 label 命中 $nrows 个 pane：$name ⇒ $(printf '%s\n' "$rows" | cut -f2 | paste -sd, -)（不猜：无唯一身份证据）"
    printf 'ambiguous\t-\t-\t-\n'; return 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _ _ _ _ _ fg astat seq sess avname hook _ws _task <<< "$line"
    # 阶梯（定序）：ghost（label 在、agent 条目无）→ dead（前台非 pi）→ mismatch（argv --name 不符）
    #             → integration-missing（会话身份/钩子权威缺）→ online
    if [[ "$seq" == "-" ]]; then rv="ghost"
    elif [[ "$fg" != "pi" ]]; then rv="dead"
    elif [[ -n "$avname" && "$avname" != "-" && "$avname" != "$name" ]]; then rv="mismatch"
    elif [[ -z "$sess" || "$sess" == "-" || "$hook" != "1" ]]; then rv="integration-missing"
    else rv="online"; fi
    if [[ "$rv" == "online" ]]; then printf 'online\t%s\t%s\t%s\n' "$astat" "$seq" "$hook"; return 0; fi
    if [[ -z "$v" ]]; then v="$rv"; state="$astat"; rq="$seq"; rh="$hook"; fi
  done <<< "$rows"
  printf '%s\t%s\t%s\t%s\n' "${v:-absent}" "$state" "$rq" "$rh"
}

# ---------------------------------------------------------------------------
# B3（#96 二期）：回收面（close / cleanup）—— 句柄层双实现的 herdr 侧
#   · 定位：pane label 精确匹配（跨仓，不按 repo 过滤，label 即路由标签）；>1 ⇒ warn 点名 + **不猜**
#   · self 判据：(session, pane_id) 对 + process-info.shell_pid 祖先链（T530 三态 fail-closed）；
#     不可判定时**只对**「(session,pane) 全等」（HERDR_PANE_ID）保守拒 —— 宁可少回收一次
#   · 忙闲（BR7）：working/blocked ⇒ 拒；idle/done ⇒ 放行；unknown / 无 agent 条目 / 集成缺失 ⇒ 拒
#     （fail-closed）+ `--force` + 指路；**保留名册第二信号（OR）**：prompt 后 ~300–400ms
#     agent_status 仍 idle（实测 744ms 才见 working）⇒ 单信号会误杀
#   · 回收句柄唯一 = `pane close`（**不做** kill -9 兜底）；effect 复核（新 pane list），不静默成功
#   · 恢复窗口：process-info 明确 pane_not_found ⇒ **不回收**（不可寻址 ≠ 可回收）
#   所有 herdr 调用仍只经 `_term_herdr_exec`（本区间不出现 tmux 句柄/标题字段名）。
# ---------------------------------------------------------------------------
_term_herdr_pane_shell_pid() {  # <pane_id> → shell_pid（无/不可解析 ⇒ 空）
  local pid="${1-}" js v
  [[ -n "$pid" ]] || return 0
  js="$(_term_herdr_exec pane process-info --pane "$pid" 2>/dev/null)" || return 0
  v="$(_term_json_raw "$js" shell_pid)"
  [[ "$v" =~ ^[0-9]+$ ]] && printf '%s\n' "$v"
  return 0
}

# shell_pid 是否本进程（$$）的祖先：0 = 是（自己）· 1 = 不是 · 2 = 不可判定（链断/ps 不可读）
_term_herdr_shell_is_caller() {  # <shell_pid>
  local p_pid="${1-}" cur
  [[ "$p_pid" =~ ^[0-9]+$ ]] || return 2
  cur="$$"
  while [[ "$cur" =~ ^[0-9]+$ ]] && (( cur > 1 )); do
    [[ "$cur" == "$p_pid" ]] && return 0
    cur="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$cur" ]] || return 2
  done
  return 1
}

# F1 闸门（herdr 侧）：0 = 必须拒绝回收（判为调用者自身）· 1 = 放行
_term_herdr_self_refuse() {  # <pane_id>
  local pid="${1-}" sp rc=0
  [[ -n "$pid" ]] || return 0
  sp="$(_term_herdr_pane_shell_pid "$pid")"
  _term_herdr_shell_is_caller "$sp" || rc=$?
  case "$rc" in
    0) return 0 ;;   # 确定的自身 pane ⇒ 拒
    2) # 不可判定：保守侧只对「(session,pane) 全等」拒（当前已在 HERDR_SESSION 内 ⇒ 比 pane_id 即可）
       [[ -n "${HERDR_PANE_ID:-}" && "$pid" == "$HERDR_PANE_ID" ]] && return 0
       return 1 ;;
    *) return 1 ;;   # 确定不是自己 ⇒ 放行
  esac
}

# 忙闲证据（BR7 + 名册第二信号）：0 = 忙（理由落 _TERM_BUSY_WHY）· 1 = 可回收
_term_herdr_busy() {  # <name> [repo]
  local name="${1-}" repo="${2-}" vline verdict state seq hook why="" st
  _TERM_BUSY_WHY=""
  vline="$(term_liveness "$name" "$repo")"
  IFS=$'\t' read -r verdict state seq hook <<< "$vline"
  case "$verdict" in
    online)
      if ! term_deliverable "$state"; then
        why="agent_status=${state:-?}（BR7：working/blocked/unknown ⇒ 不可投递）"
      fi ;;
    ghost)               why="agent list 无该 pane 条目（幽灵 pane）⇒ 无忙闲证据，保守拒（BR7 无条目 ⇒ 不可投递）" ;;
    integration-missing) why="集成缺失（agent_session 空或生命周期钩子权威缺）⇒ 状态不可信，保守拒" ;;
    dead)                why="前台非 pi（可能刚退出/重启回放）⇒ 无 agent 生命周期证据，保守拒" ;;
    mismatch)            why="身份不一致（pane label 与 argv --name 不符）⇒ 定位不确定，拒" ;;
    ambiguous)           why="同名 label 命中多个 pane ⇒ 不猜" ;;
    *)                   why="在线证据缺失（verdict=${verdict:-absent}）⇒ 保守拒" ;;
  esac
  if [[ -z "$why" ]]; then
    # 第二信号（OR）：名册 thinking / tool:* 代表真在跑 turn；agent_status 有 ~0.3–0.75s 滞后窗口
    st="$(intercom_status_for "$name" "$repo")"   # 按目标仓取（同名会话可能多仓并存）
    case "$st" in
      ""|idle|\?) ;;
      *) why="pi-intercom 名册状态=$st（在跑 turn；agent_status 滞后窗口内的第二信号）" ;;
    esac
  fi
  _TERM_BUSY_WHY="$why"
  [[ -n "$why" ]]
}

# 单 pane 落地：唯一回收句柄 = pane close；effect 复核（新 pane list）⇒ 0 已消失 / 1 失败
_term_herdr_close_pane() {  # <name> <pane> <repo> <cwd> <fgcwd>
  local name="${1-}" pane="${2-}" repo="${3-}" cwdf="${4-}" fgcwd="${5-}" pcwd="" pl2="" close_rc=0
  [[ -n "$pane" ]] || return 1
  if ! _term_herdr_exec pane close "$pane" >/dev/null 2>&1; then close_rc=1; fi
  if [[ -n "${_TERM_SNAP_FILE:-}" ]]; then rm -f "$_TERM_SNAP_FILE" 2>/dev/null || true; _TERM_SNAP_FILE=""; fi
  if ! pl2="$(_term_herdr_exec pane list 2>/dev/null)"; then
    warn "已对 $name 的 pane $pane 执行 pane close（rc=$close_rc），但 effect 不可复核（pane list 失败）⇒ 非 0"
    warn "  该怎么办：\`herdr --session ${HERDR_SESSION:-<s>} pane list\` 核对后再定"
    return 1
  fi
  if printf '%s' "$pl2" | grep -qF "\"pane_id\":\"$pane\""; then
    warn "已定位到 $name 的 pane $pane 但回收失败（pane close rc=$close_rc，复核 pane 仍在）"
    warn "  该怎么办：\`herdr --session ${HERDR_SESSION:-<s>} pane list\` 核对；必要时人工关闭该 pane（不自动重试，防误关）"
    return 1
  fi
  pcwd="$fgcwd"; [[ "$pcwd" == "-" || -z "$pcwd" ]] && pcwd="$cwdf"
  [[ "$pcwd" == "-" || -z "$pcwd" ]] && pcwd="$repo"
  fleet_meta_remove_handle "$pane"   # v3：回收成功 ⇒ sidecar 即时删（幂等）
  log "已回收 $name（herdr pane $pane）@ $pcwd"
  return 0
}

# 单行快照行 → verdict（与 term_liveness 同一阶梯，供「同名多 pane」逐行判定）
_term_herdr_row_verdict() {  # <name> <row>
  local name="${1-}" line="${2-}" fg="" astat="" seq="" sess="" avname="" hook=""
  IFS=$'\t' read -r _ _ _ _ _ fg astat seq sess avname hook _ws _task <<< "$line"
  if [[ "$seq" == "-" ]]; then printf 'ghost\n'
  elif [[ "$fg" != "pi" ]]; then printf 'dead\n'
  elif [[ -n "$avname" && "$avname" != "-" && "$avname" != "$name" ]]; then printf 'mismatch\n'
  elif [[ -z "$sess" || "$sess" == "-" || "$hook" != "1" ]]; then printf 'integration-missing\n'
  else printf 'online\n'; fi
}

# 同名 label 多 pane + --force：**逐 pane 按安全判据清理**（B2 转办 ②「重复 label 清理」）
#   不猜「哪个是目标」；绝对护栏仍保留：调用者自身永不关、pane_not_found（恢复窗口）不关、
#   身份不一致（argv --name ≠ label）不关；跳过任一个 ⇒ rc=1（部分完成不谎报全成功）。
_term_herdr_reclaim_dup() {  # <name> <repo> <rows>
  local name="${1-}" repo="${2-}" rows="${3-}" line pane cwdf fgcwd vd probe pstate pmsg rc=0 skipped=0
  local astat="" rost="" rbusy=0
  # P3-1（可观测性）：kill 路径的「可能丢失在跑 turn」必须**逐 pane 可归属**（不能汇总一句）。
  #   判据与单 pane 路径同源：该 pane 的 agent_status ∈ working|blocked，或名册 busy（OR）。
  #   名册信号是**名字级**（同名多 pane 共用 label）⇒ 无法区分具体 pane，warn 里如实标注。
  rost="$(intercom_status_for "$name" "$repo")"
  case "$rost" in ""|idle|\?) ;; *) rbusy=1 ;; esac
  warn "同名 label 命中多个 pane：$name ⇒ $(printf '%s\n' "$rows" | cut -f2 | paste -sd, -)（--force：逐个按安全判据清理，不猜「哪个是目标」）"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _ pane _ cwdf fgcwd _ astat _ _ _ _ <<< "$line"
    vd="$(_term_herdr_row_verdict "$name" "$line")"
    if [[ "$vd" == "mismatch" ]]; then
      warn "跳过 pane $pane：身份不一致（pane label 与 argv --name 不符）⇒ 定位不确定，不关"
      skipped=1; continue
    fi
    if _term_herdr_self_refuse "$pane"; then
      warn "跳过 pane $pane：判为调用者自身（F1：绝不回收自己）"
      skipped=1; continue
    fi
    probe="$(_term_herdr_probe_pane "$pane")"
    pstate="${probe%%$'\t'*}"; pmsg="${probe#*$'\t'}"
    [[ "$pmsg" == "$probe" ]] && pmsg=""
    if [[ "$pstate" == "notfound" ]]; then
      warn "跳过 pane $pane：明确 pane_not_found（stop→restart 回放/恢复窗口内 ⇒ 不得当可回收）"
      skipped=1; continue
    fi
    [[ "$pstate" == "error" ]] && warn "--force 越过 process-info 不可判：pane $pane（${pmsg:-未知错误}）"
    if [[ "$astat" == "working" || "$astat" == "blocked" ]]; then
      warn "pane $pane：agent_status=$astat ⇒ **可能丢失在跑 turn**（--force 显式越过，仍按安全判据回收）"
    elif (( rbusy )); then
      warn "pane $pane：pi-intercom 名册状态=$rost ⇒ **可能丢失在跑 turn**（--force 显式越过；名册信号是名字级，无法区分 pane）"
    fi
    _term_herdr_close_pane "$name" "$pane" "$repo" "$cwdf" "$fgcwd" || rc=1
  done <<< "$rows"
  (( skipped )) && rc=1
  return $rc
}

_term_herdr_reclaim() {  # <name> <repo> <force> <core> <scope> <ensure-target>
  local name="${1-}" repo="${2-}" force="${3:-false}" core="${4-}" scope="${5-}" tgt="${6-}"
  local rows="" nrows=0 pane="" cwdf="" fgcwd="" why="" probe="" pstate="" pmsg=""
  # 快照不可用 ⇒ 不判「未运行」（否则 server 故障会被谎报成「无需回收」）
  if ! term_snapshot >/dev/null 2>&1; then
    warn "拒绝回收 $name：herdr pane/agent 快照不可用（server 未就绪？）⇒ 不回收"
    warn "  该怎么办：核对 \`herdr --session ${HERDR_SESSION:-<s>} api snapshot\` 后再试"
    return 1
  fi
  rows="$(term_snapshot 2>/dev/null | awk -F'\t' -v n="$name" '$1==n')" || rows=""
  # T554：v2 名字的同名跨 workspace **合法** ⇒ 回收只认目标仓锚内的行；
  #   旧形（LEGACY）名字沿用「全局唯一」旧契约 ⇒ 不按仓过滤（并列仍拒绝，AC6/K 口径）。
  local _pkind="${1-}"
  _pkind="$(fleet_name_parse "$name")"
  if [[ "$_pkind" == "LEGACY OK "* ]]; then _pkind="LEGACY"; else _pkind="V2"; fi
  if [[ "$_pkind" == "V2" && -n "$repo" && -n "$rows" ]]; then
    local _rp _line _c _f _keep=""
    _rp="$(nao_phys_path "$repo")"
    while IFS= read -r _line; do
      [[ -n "$_line" ]] || continue
      IFS=$'\t' read -r _ _ _ _c _f _ <<< "$_line"
      if { [[ "$_c" != "-" && -n "$_c" ]] && repo_contains_path "$_rp" "$(nao_phys_path "$_c")"; } \
         || { [[ "$_f" != "-" && -n "$_f" ]] && repo_contains_path "$_rp" "$(nao_phys_path "$_f")"; }; then
        _keep+="$_line"$'\n'
      fi
    done <<< "$rows"
    rows="${_keep%$'\n'}"
  fi
  nrows="$(printf '%s\n' "$rows" | grep -c . || true)"
  if (( nrows == 0 )); then
    # 名册在 herdr 非身份权威（BR3），但「报在线却无 label」必须非静默（不谎报「未运行」）
    if intercom_online "$name"; then
      warn "无法回收 $name：pi-intercom 名册报在线，但 herdr pane label 无命中"
      warn "  名册在 herdr 非身份权威（BR3）；请用 status / \`herdr --session ${HERDR_SESSION:-<s>} pane list\` 核对 label"
      return 1
    fi
    log "$name 未运行（无需回收）"; return 0
  fi
  if (( nrows > 1 )); then
    if [[ "$force" != true ]]; then
      warn "拒绝回收 $name：同名 label 命中 $nrows 个 pane（$(printf '%s\n' "$rows" | cut -f2 | paste -sd, -)）⇒ 不猜"
      warn "  该怎么办：先人工核对/清理重复 label（删掉多余 pane）后再回收"
      warn "  确要清理重复 label（B2 转办②）：close --force $name（仍不关调用者自身 / 恢复窗口中的 pane）"
      return 1
    fi
    _term_herdr_reclaim_dup "$name" "$repo" "$rows"
    return $?
  fi
  IFS=$'\t' read -r _ pane _ cwdf fgcwd _ _ _ _ _ _ <<< "$rows"
  # ---- 硬拒档（**--force 也不越过**）：身份不一致 = 定位到的不一定是目标会话 ----
  local vline verdict state seq hook
  vline="$(term_liveness "$name" "$repo")"
  IFS=$'\t' read -r verdict state seq hook <<< "$vline"
  if [[ "$verdict" == "mismatch" ]]; then
    warn "拒绝回收 $name：身份不一致（pane label 与 argv --name 不符）⇒ 定位不确定，--force 也不越过"
    warn "  该怎么办：用 status / intercom list 核对目标会话名；先人工处理该 pane"
    return 1
  fi
  # ---- self 判据（F1：绝不回收调用者自己）----
  if _term_herdr_self_refuse "$pane"; then
    warn "拒绝回收 $name：解析出的 pane $pane 判为调用者自身（shell_pid 祖先链命中，或不可判定且与 HERDR_PANE_ID 全等）"
    warn "  该怎么办：确认目标会话名（status / intercom list）后再处理"
    return 1
  fi
  # ---- 忙闲闸门（BR7 + 名册第二信号）----
  if _term_herdr_busy "$name" "$repo"; then
    why="$_TERM_BUSY_WHY"
    if [[ "$force" != true ]]; then
      warn "拒绝回收 $name：$why"
      warn "  等它停；回执与产物核对见 checklists/pm.md「会话回收 / 收窗核对」（或 --force 强制：会丢失在跑 turn/打回上下文）"
      return 1
    fi
    warn "--force 越过忙闲闸门：$name（$why）—— 明确按用户要求回收，可能丢失在跑 turn"
  fi
  # ---- 恢复窗口 / 回放幽灵：明确 pane_not_found ⇒ 不回收（不可寻址）----
  probe="$(_term_herdr_probe_pane "$pane")"
  pstate="${probe%%$'\t'*}"; pmsg="${probe#*$'\t'}"
  [[ "$pmsg" == "$probe" ]] && pmsg=""
  case "$pstate" in
    notfound)
      warn "拒绝回收 $name：pane=$pane 明确 pane_not_found（stop→restart 回放/恢复窗口内 ⇒ 不得当可回收）"
      warn "  等恢复完成（status 判在线）后再回收；诊断：herdr --session ${HERDR_SESSION:-<s>} agent explain $pane"
      return 1 ;;
    error)
      if [[ "$force" != true ]]; then
        warn "拒绝回收 $name：process-info 不可判（${pmsg:-未知错误}）⇒ 不回收（宁可少关一个）"
        warn "  该怎么办：稍后重试；确认该 pane 无用后再加 --force（显式越过，仍做 effect 复核）"
        return 1
      fi
      warn "--force 越过 process-info 不可判：$name（${pmsg:-未知错误}）"
      ;;
  esac
  # ---- 落地（唯一回收句柄 = pane close + effect 复核）----
  _term_herdr_close_pane "$name" "$pane" "$repo" "$cwdf" "$fgcwd"
}

# 会话表（effect 判据的唯一来源）：成功输出 JSON；CLI 失败/空输出 ⇒ 1（**不自动起 server**）
_term_herdr_session_json() {
  local js
  js="$(_term_herdr_exec session list --json 2>/dev/null)" || return 1
  [[ -n "$js" ]] || return 1
  printf '%s' "$js"
}

# 会话是否已消失（effect 判据）：0 = 已消失 · 1 = 仍可见 / 不可判（fail-closed）
_term_herdr_session_absent() {  # <session>
  local s="${1-}" js
  [[ -n "$s" ]] || return 1
  js="$(_term_herdr_session_json)" || return 1
  if printf '%s' "$js" | grep -qF "\"name\":\"$s\""; then return 1; fi
  return 0
}

# 拆场（herdr · 姊妹入口）：session stop + delete，**判 effect 不看 rc**（stop 非幂等：第二次 rc=1）。
#   守卫与 session-start 同源：显式目标必给 / ≠default（BR9）/ 字符集 / 目标根在 herdr 根内。
_term_herdr_cleanup() {  # <session> [force]
  local s="${1-}" root rootp sp spp dir prev rc=0
  # T554/D5：default 与专用 session 等价（放行），但破坏性动作必须先打印影响面；
  #   无 --force ⇒ rc=2 零动作（放行 ≠ 静默停用户 server）。非 default 路径保持既有语义。
  if [[ "$s" == "default" ]]; then
    local _wc=0 _pc=0 _js=""
    if _js="$(_term_herdr_exec workspace list 2>/dev/null)"; then
      _wc="$(printf '%s\n' "$_js" | grep -o '"workspace_id"' | grep -c . || true)"
    fi
    if _js="$(_term_herdr_exec pane list 2>/dev/null)"; then
      _pc="$(printf '%s\n' "$_js" | grep -o '"pane_id"' | grep -c . || true)"
    fi
    printf '[fleet] 将停止 session=default，影响 %s 个 workspace / %s 个 pane\n' "${_wc:-0}" "${_pc:-0}" >&2
    if [[ "${2:-false}" != "true" ]]; then
      printf '[fleet] 未给 --force ⇒ 零动作（rc=2）；确认执行请加 --force（当前 pane 可能属于该 session，将被终止）\n' >&2
      return 2
    fi
    printf '[fleet] --force：当前 pane 若属于 session=default 将被终止\n' >&2
  fi
  command -v herdr >/dev/null 2>&1 || {
    printf '需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试；旧版 tmux 后端已移除，需要它请 pin 回 ≤0.27.x）\n' >&2
    return 2
  }
  case "$s" in
    "")
      printf '需要 herdr 会话名：%s 不可用（cleanup 必填 --session；default 已放行，但需 --force）\n' "${s:-<空>}" >&2
      return 2 ;;
  esac
  if [[ ! "$s" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf '需要 herdr 会话名：%s 非法（^[A-Za-z0-9._-]+$）\n' "$s" >&2
    return 2
  fi
  root="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
  rootp="$(_term_path_norm "$root/sessions/$s")"
  sp="${HERDR_SOCKET_PATH:-}"
  if [[ -n "$sp" ]]; then
    spp="$(_term_path_norm "$sp")"
    if [[ "$spp" != "$rootp"/* ]]; then
      printf '需要 herdr 会话目录：HERDR_SOCKET_PATH=%s 不在目标根 %s/ 下（stale/外贸 env ⇒ 拒绝，防误拆）\n' "$sp" "$rootp" >&2
      return 3
    fi
  fi
  dir="$root/sessions/$s"
  prev="${HERDR_SESSION:-}"
  export HERDR_SESSION="$s"
  # P3-3（fail-closed）：effect 判据的来源不可用 ⇒ 拒绝（**不自动起 server**、零拆场动作）
  if ! _term_herdr_session_json >/dev/null; then
    printf '[fleet] cleanup 拒绝：herdr `session list` 不可用（无法判 effect；不自动起 server）\n' >&2
    printf '[fleet] 该怎么办：核对 `herdr --session %s session list --json`；必要时先 session-start 起 server 再重试\n' "$s" >&2
    if [[ -n "$prev" ]]; then export HERDR_SESSION="$prev"; else unset HERDR_SESSION; fi
    return 1
  fi
  # 幂等前置：会话条目与目录都不存在 ⇒ effect=0，零动作
  if _term_herdr_session_absent "$s" && [[ ! -e "$dir" ]]; then
    printf '[fleet] herdr session=%s 已清理（effect=0；stop+delete 均无动作）\n' "$s"
    if [[ -n "$prev" ]]; then export HERDR_SESSION="$prev"; else unset HERDR_SESSION; fi
    return 0
  fi
  # v3 元数据：拆场前收集本会话 pane 句柄，逐条删 sidecar（session 即将消失，避免留下孤儿）。
  local _pl="" _pobj="" _pid=""
  if _pl="$(_term_herdr_exec pane list 2>/dev/null)"; then
    while IFS= read -r _pobj; do
      _pid="$(_term_json_str "$_pobj" pane_id)"
      [[ -n "$_pid" ]] && fleet_meta_remove_handle "$_pid"
    done < <(_term_json_objs <<< "$_pl")
  fi
  _term_herdr_exec session stop "$s" >/dev/null 2>&1 || true    # 非幂等 ⇒ 吞 rc，判 effect
  _term_herdr_exec session delete "$s" >/dev/null 2>&1 || true
  if _term_herdr_session_absent "$s" && [[ ! -e "$dir" ]]; then
    printf '[fleet] 已终结 herdr session=%s（stop+delete；effect=已消失）\n' "$s"
  else
    rc=1
    printf '[fleet] cleanup 失败：herdr session=%s 清理后仍可见（effect 未达成；rc 不作判据）\n' "$s" >&2
    printf '[fleet] 该怎么办：`herdr session list` 核对；仍 running ⇒ `herdr --session %s session stop %s` 后重试\n' "$s" "$s" >&2
  fi
  if [[ -n "$prev" ]]; then export HERDR_SESSION="$prev"; else unset HERDR_SESSION; fi
  return $rc
}

# ---------------------------------------------------------------------------
# B2（#96 二期）：放置 + 就绪门 + 起 server
#   · 先 label 后启动（pane rename → pane run）：避免 status 抓到无主 pane；
#   · 就绪门 = **全条件与**（禁用 `agent wait --until idle`：已 idle 时 6ms 返回 = 假阳性）；
#   · 幽灵 pane（label 在、agent 无）**不判 same**：唯一命中 ⇒ 复用该 pane 重跑 agent；
#     多命中 ⇒ warn 点名 + 不猜（不静默跳过，也不擅自选一个）。
#   所有 herdr 调用仍只经 `_term_herdr_exec`（本区间不出现 tmux 句柄/标题字段名）。
# ---------------------------------------------------------------------------
_term_herdr_workspace_id_for() {  # <label> → workspace_id（无则空）
  #   判据恒为 **label 精确匹配**：WorkspaceInfo 无 cwd/worktree 字段（herdr 0.9.1 实测）⇒ 不能按 cwd/根 pane
  #   反查（那会引入第二个放置键，同一个 workspace 可能被两种键指向）。label 恒非空（ADR 2026-11-13），
  #   故下面防空守卫是**纯防御**（保持函数自洽，不依赖调用方）。
  local label="${1-}" js obj
  [[ -n "$label" ]] || return 0
  js="$(_term_herdr_exec workspace list 2>/dev/null)" || return 0
  while IFS= read -r obj; do
    [[ -n "$(_term_json_str "$obj" workspace_id)" ]] || continue
    [[ "$(_term_json_str "$obj" label)" == "$label" ]] || continue
    _term_json_str "$obj" workspace_id
    return 0
  done < <(_term_json_objs <<< "$js")
  return 0
}

# ---------------------------------------------------------------------------
# 放置/归属快照（T554 · 判据 §二「herdr 查询上限」）
#   `ensure` 的放置键冲突、槽位判重、workspace 复用判据全部读**本命令一份快照**：
#     ≤1 次 `workspace list` + ≤1 次 `pane list`（不再 per-target 重查）。
#   `_TERM_PLACE_CACHE=1` 时 spawn/layout/就绪门走缓存；其余命令（status/close）不启用。
#   快照只在 ensure 相位 2 启用（相位 1 的判重直接调用，不产生后端调用）。
# ---------------------------------------------------------------------------
_TERM_PLACE_CACHE=0
declare -A _TERM_PLACE_WS_BY_LABEL=()
declare -a _TERM_PLACE_WS_ROWS=()     # "wsid<TAB>label"
# pane 行字段分隔符（#160 P0）：US（`\x1f`，**非空白**）。TAB 属 IFS 空白类 ⇒ `IFS=$'\t' read`
#   会把空字段（无 label 的 pane = 用户自己手起的会话）整个折叠，字段整体左移（wsid 位读到 tab_id）。
_TERM_PLACE_FS=$'\x1f'
declare -a _TERM_PLACE_PANE_ROWS=()   # 6 字段行（`_term_place_pane_row` 构造；US 分隔，空字段保真）
declare -A _TERM_PLACE_TASK_BY_PANE=()  # v3 元数据 task（key=pane_id；prime 重建）
_TP_LABEL=""; _TP_PANE=""; _TP_WS=""; _TP_TAB=""; _TP_CWD=""; _TP_FGCWD=""

# pane 行**唯一构造点**：空字段原样保留（**不**补 `-` —— 空 label 是合法语义「非舰队 pane」，
#   而 tab_id/wsid 可能真的是空值；补哨兵会引入第二套「空值等价」规则）。
_term_place_pane_row() {  # <label> <pane_id> <wsid> <tab_id> <cwd> <fgcwd>
  local FS="$_TERM_PLACE_FS"
  printf '%s' "${1-}${FS}${2-}${FS}${3-}${FS}${4-}${FS}${5-}${FS}${6-}"
}

# 放置快照的**唯一 append 点**（两后端 prime 共用；构造仍走 `_term_place_pane_row`）。
#   T562：app 臂新增第二个 prime ⇒ 若各自 `+=`，行构造点会变 2 处（case 43 ① 断言唯一），
#   且下次改编码只需改构造器 —— append 也收成一处，防「双写改一处漏一处」。
_term_place_add_pane() {  # <label> <pane> <wsid> <tab> <cwd> <fgcwd>
  _TERM_PLACE_PANE_ROWS+=("$(_term_place_pane_row "${1-}" "${2-}" "${3-}" "${4-}" "${5-}" "${6-}")")
}

# pane 行**唯一解析点**（#160 P0）：所有消费点只准经本函数取值 —— 禁止再出现「直接 `read` 消费
#   `_TERM_PLACE_PANE_ROWS`」（静态闸 tests/t4/lib.sh::t4_scan_place_pane_rows 断言裸 read = 0）。
#   空字段保真（`\x1f` 非空白 ⇒ IFS 不折叠）；字段数不足时 `read` 把余下变量置空（不残留上一行）。
_term_place_pane_fields() {  # <row> → _TP_LABEL/_TP_PANE/_TP_WS/_TP_TAB/_TP_CWD/_TP_FGCWD
  _TP_LABEL=""; _TP_PANE=""; _TP_WS=""; _TP_TAB=""; _TP_CWD=""; _TP_FGCWD=""
  IFS="$_TERM_PLACE_FS" read -r _TP_LABEL _TP_PANE _TP_WS _TP_TAB _TP_CWD _TP_FGCWD <<< "${1-}"
  return 0
}

_term_herdr_place_prime() {  # → 0 已建快照 / 1 后端不可用
  local js="" obj label wsid pid tid cwd fgcwd task
  _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=(); _TERM_PLACE_TASK_BY_PANE=()
  js="$(_term_herdr_exec workspace list 2>/dev/null)" || return 1
  while IFS= read -r obj; do
    wsid="$(_term_json_str "$obj" workspace_id)"; [[ -n "$wsid" ]] || continue
    label="$(_term_json_str "$obj" label)"
    _TERM_PLACE_WS_ROWS+=("$wsid"$'\t'"$label")
    [[ -n "${_TERM_PLACE_WS_BY_LABEL[$label]:-}" ]] || _TERM_PLACE_WS_BY_LABEL["$label"]="$wsid"
  done < <(_term_json_objs <<< "$js")
  js="$(_term_herdr_exec pane list 2>/dev/null)" || return 1
  while IFS= read -r obj; do
    pid="$(_term_json_str "$obj" pane_id)"; [[ -n "$pid" ]] || continue
    label="$(_term_json_str "$obj" label)"
    tid="$(_term_json_str "$obj" tab_id)"
    wsid="$(_term_json_str "$obj" workspace_id)"
    cwd="$(_term_json_str "$obj" cwd)"
    fgcwd="$(_term_json_str "$obj" foreground_cwd)"
    task="$(fleet_meta_read "$(fleet_meta_wsref "$wsid")" "$pid")"
    [[ -n "$task" ]] && _TERM_PLACE_TASK_BY_PANE["$pid"]="$task"
    _term_place_add_pane "$label" "$pid" "$wsid" "$tid" "$cwd" "$fgcwd"
  done < <(_term_json_objs <<< "$js")
  # v3 元数据孤儿清理（ensure 读快照入口）：当前会话 handle 集合之外的 sidecar 即时删（幂等，仅 warn）。
  local row
  for row in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
    [[ -n "$row" ]] || continue
    _term_place_pane_fields "$row"
    [[ -n "$_TP_PANE" ]] && printf '%s\n' "$_TP_PANE"
  done | fleet_meta_gc
  _TERM_PLACE_CACHE=1
  return 0
}

_term_herdr_place_reset() { _TERM_PLACE_CACHE=0; _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=(); _TERM_PLACE_TASK_BY_PANE=(); }

# 关 workspace 前的**原始复核**（#160 P0 护栏）：返回 `pane list --workspace <wsid>` 的 pane 数。
#   快照可能失真（解析缺陷/并发变更），但关闭是**破坏性且不可回滚**的（会连带杀掉用户 pi 会话）
#   ⇒ 关前必须用后端原始结果再确认一次。读不到（命令失败）⇒ rc=1（调用方 fail loud，**不关**）。
_term_herdr_ws_pane_count_live() {  # <wsid> → stdout 计数
  local wsid="${1-}" js obj n=0
  [[ -n "$wsid" ]] || return 1
  js="$(_term_herdr_exec pane list --workspace "$wsid" 2>/dev/null)" || return 1
  [[ -n "$js" && "$js" != *'"error"'* ]] || return 1
  while IFS= read -r obj; do
    [[ -n "$(_term_json_str "$obj" pane_id)" ]] && n=$((n + 1))
  done < <(_term_json_objs <<< "$js")
  printf '%s\n' "$n"
}

# 快照内新增一条 pane 行（spawn 成功后回填；缓存只服务本命令的后续目标）
# 后端中立（herdr/app 两臂共用）：只改 `_TERM_PLACE_*` 数组，不调后端。
_term_place_set_pane() {  # <label> <pane> <wsid> <tab> <cwd> [task]
  local label="${1-}" pane="${2-}" wsid="${3-}" tab="${4-}" cwd="${5-}" task="${6-}"
  local line
  local -a keep=()
  (( _TERM_PLACE_CACHE )) || return 0
  for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    _term_place_pane_fields "$line"
    [[ "$_TP_PANE" == "$pane" ]] && continue
    keep+=("$line")
  done
  keep+=("$(_term_place_pane_row "$label" "$pane" "$wsid" "$tab" "$cwd" "$cwd")")
  _TERM_PLACE_PANE_ROWS=("${keep[@]:-}")
  if [[ -n "$task" ]]; then _TERM_PLACE_TASK_BY_PANE["$pane"]="$task"; else unset '_TERM_PLACE_TASK_BY_PANE[$pane]'; fi
}

# 快照内删一条 pane 行（幽灵 pane 被关 / 复用失败）
_term_herdr_place_drop_pane() {  # <pane_id>
  local pid="${1-}" line
  local -a keep=()
  (( _TERM_PLACE_CACHE )) || return 0
  for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    _term_place_pane_fields "$line"
    [[ "$_TP_PANE" == "$pid" ]] && continue
    keep+=("$line")
  done
  _TERM_PLACE_PANE_ROWS=("${keep[@]:-}")
}

# process-info 探针（P3-6）：**只有明确 pane_not_found 才算「回放幽灵」**；其它错误/空输出一律不 close。
#   返回 "ok" / "notfound<TAB><详情>" / "error<TAB><详情>"（详情截断 160 字节，供 fail loud 点名）。
_term_herdr_probe_pane() {  # <pane_id>
  local pid="${1-}" js rc=0
  [[ -n "$pid" ]] || { printf 'error\t缺 pane_id\n'; return 0; }
  # herdr 的错误 JSON 走 **stderr**（实测 rc=1）⇒ 必须合流才能判 pane_not_found
  js="$(_term_herdr_exec pane process-info --pane "$pid" 2>&1)" || rc=$?
  if (( rc != 0 )); then
    if [[ "$js" == *'"code":"pane_not_found"'* ]]; then
      printf 'notfound\t%s\n' "$(printf '%s' "$js" | head -c 160)"
      return 0
    fi
    printf 'error\t%s\n' "$(printf '%s' "${js:-<空输出>}" | head -c 160)"
    return 0
  fi
  if [[ -z "${js//[[:space:]]/}" ]]; then
    printf 'error\t空输出（pane 可达但无 process-info 响应）\n'
    return 0
  fi
  if [[ "$js" == *'"error"'* ]]; then
    printf 'error\t%s\n' "$(printf '%s' "$js" | head -c 160)"
    return 0
  fi
  printf 'ok\n'
  return 0
}

# 前台进程全部是交互式 shell 才允许复用（否则 `pane run` 会把命令注入用户正在跑的程序）
_term_fg_list_is_shell() {  # <name...> → 0 全部在 TERM_SHELL_NAMES 白名单
  local n sh_n hit
  (( $# > 0 )) || return 1
  for n in "$@"; do
    hit=0
    for sh_n in "${TERM_SHELL_NAMES[@]}"; do [[ "$n" == "$sh_n" ]] && { hit=1; break; }; done
    (( hit )) || return 1
  done
  return 0
}

# ---- 布局 A（三期 P1 · AC3.1）：tab 视图 + 结构收敛 + 空间判据（全部经唯一入口）----
# 结构判据（**非几何**）：每角色 tab `pane_count == 1` ∧ pane_id 唯一（`tab list` / `pane list` 的 tab_id 字段）
#   ⇒ 零几何算式（对比 tmux 侧 main-row2 的列宽算式）；attach 尺寸变化只影响渲染，不影响拓扑判据。
_term_herdr_tab_row() {  # <workspace_id> <tab_id> → "label<TAB>pane_count"（无该 tab ⇒ 空）
  local wsid="${1-}" tid="${2-}" js obj
  [[ -n "$wsid" && -n "$tid" ]] || return 0
  js="$(_term_herdr_exec tab list --workspace "$wsid" 2>/dev/null)" || return 0
  while IFS= read -r obj; do
    [[ "$(_term_json_str "$obj" tab_id)" == "$tid" ]] || continue
    printf '%s\t%s\n' "$(_term_json_str "$obj" label)" "$(_term_json_raw "$obj" pane_count)"
    return 0
  done < <(_term_json_objs <<< "$js")
  return 0
}

_term_herdr_tab_id_for() {  # <workspace_id> <label> → tab_id（无 ⇒ 空）
  local wsid="${1-}" want="${2-}" js obj
  [[ -n "$wsid" && -n "$want" ]] || return 0
  js="$(_term_herdr_exec tab list --workspace "$wsid" 2>/dev/null)" || return 0
  while IFS= read -r obj; do
    [[ "$(_term_json_str "$obj" label)" == "$want" ]] || continue
    _term_json_str "$obj" tab_id
    return 0
  done < <(_term_json_objs <<< "$js")
  return 0
}

_term_herdr_pane_tab() {  # <pane_id> → "tab_id<TAB>workspace_id"（无 ⇒ 空）
  local pid="${1-}" js obj line _p _tab _ws
  [[ -n "$pid" ]] || return 0
  # T554：ensure 快照启用 ⇒ 读本命令快照（不再 per-target `pane list`）
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      [[ "$_TP_PANE" == "$pid" ]] || continue
      printf '%s\t%s\n' "$_TP_TAB" "$_TP_WS"
      return 0
    done
    return 0
  fi
  js="$(_term_herdr_exec pane list 2>/dev/null)" || return 0
  while IFS= read -r obj; do
    [[ "$(_term_json_str "$obj" pane_id)" == "$pid" ]] || continue
    printf '%s\t%s\n' "$(_term_json_str "$obj" tab_id)" "$(_term_json_str "$obj" workspace_id)"
    return 0
  done < <(_term_json_objs <<< "$js")
  return 0
}

# 快照内改 pane 的 tab（layout A 迁移后回填；缓存只服务本命令）
_term_herdr_place_set_tab() {  # <pane_id> <tab_id> <wsid>
  local pid="${1-}" tab="${2-}" ws="${3-}" line
  local -a keep=()
  (( _TERM_PLACE_CACHE )) || return 0
  for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    _term_place_pane_fields "$line"
    if [[ "$_TP_PANE" == "$pid" ]]; then
      keep+=("$(_term_place_pane_row "$_TP_LABEL" "$pid" "$ws" "$tab" "$_TP_CWD" "$_TP_FGCWD")")
    else
      keep+=("$line")
    fi
  done
  _TERM_PLACE_PANE_ROWS=("${keep[@]:-}")
}

# J1 量测：`pane layout --pane <id>` → "width<TAB>height"（无该 pane / 无 rect ⇒ 空）
#   只取**本 pane** 对象的 rect：同一 JSON 里还有 tab 级 `area`（直接 grep width 会量到整个 tab）。
_term_herdr_pane_rect() {  # <pane_id>
  local pid="${1-}" js seg w h
  [[ -n "$pid" ]] || return 0
  js="$(_term_herdr_exec pane layout --pane "$pid" 2>/dev/null)" || return 0
  # `[^}]*` 不跨 `}` ⇒ 匹配必落在**同一个 pane 对象**内（herdr 0.9.1：pane_id 后紧跟 rect）
  seg="$(printf '%s' "$js" | grep -oE "\"pane_id\":\"$pid\"[^}]*\"rect\":\{[^}]*\}" | head -1)" || seg=""
  [[ -n "$seg" ]] || return 0
  w="$(sed -nE 's/.*"rect":\{[^}]*"width":([0-9]+).*/\1/p' <<< "$seg" | head -1)"
  h="$(sed -nE 's/.*"rect":\{[^}]*"height":([0-9]+).*/\1/p' <<< "$seg" | head -1)"
  [[ -n "$w" && -n "$h" ]] || return 0
  printf '%s\t%s\n' "$w" "$h"
  return 0
}

# J1/J5 空间判据（放置后**自测**；herdr 不报空间不足、rc 不可作判据）：
#   不足（< TERM_MIN_COLS/ROWS）⇒ 只 **warn**（rc 保持 0，跨后端 rc 语义一致）；
#   0 尺寸 pane（读不了内容）⇒ 不可用 ⇒ 计 SPAWN_FAIL（否则摘要说「成功 7」而实际读不了）。
#   文案三件套：① 哪个 pane 多少列/行 < 阈值 ② 三个可执行动作 ③ 文档指针。
_term_herdr_space_check() {  # <pane_id> <name> → 0 可继续 / 1 不可用（0 尺寸）
  local pid="${1-}" name="${2-}" rect w h
  rect="$(_term_herdr_pane_rect "$pid")"
  if [[ -z "$rect" ]]; then
    warn "空间量测不可用（$name ⇒ pane=$pid）：\`pane layout --pane\` 未给出 rect ⇒ 无法核对 ${TERM_MIN_COLS}×${TERM_MIN_ROWS}（不阻断）"
    warn "  该怎么办：\`herdr --session ${HERDR_SESSION:-<session>} pane layout --pane $pid\` 核对；必要时 attach 后重排"
    return 0
  fi
  w="${rect%%$'\t'*}"; h="${rect#*$'\t'}"
  if (( w < 1 || h < 1 )); then
    warn "空间不可用：$name（pane=$pid）列=$w 行=$h —— 0 尺寸 pane 读不了内容 ⇒ 计 SPAWN_FAIL（摘要不再算成功）"
    warn "  该怎么办：① 调 [server] headless_cols/headless_rows（config.toml）放大后重启会话（cleanup + session-start）"
    warn "            ② attach 后重排：herdr session attach ${HERDR_SESSION:-<session>}，再调整窗口/分屏"
    warn "            ③ 换更大窗口/显示器后 attach（后端 = herdr：旧版 tmux 后端已移除）"
    warn "  文档：docs/INSTALL.md「herdr 后端」· docs/prds/2026-11-10-herdr-base.md AC3.2（J1–J5）"
    return 1
  fi
  if (( w < TERM_MIN_COLS || h < TERM_MIN_ROWS )); then
    warn "空间不足：$name（pane=$pid）列=$w < ${TERM_MIN_COLS} 或 行=$h < ${TERM_MIN_ROWS} —— 仅 warn，不中断（rc 语义跨后端一致）"
    warn "  该怎么办：① 调 [server] headless_cols/headless_rows（config.toml）放大后重启会话（cleanup + session-start）"
    warn "            ② attach 后重排：herdr session attach ${HERDR_SESSION:-<session>}，再调整窗口/分屏"
    warn "            ③ 换更大窗口/显示器后 attach（后端 = herdr：旧版 tmux 后端已移除）"
    warn "  文档：docs/INSTALL.md「herdr 后端」· docs/prds/2026-11-10-herdr-base.md AC3.2（J1–J5）"
  fi
  return 0
}

# J2 结构收敛（布局 A）：本角色 pane 必须独占一个 tab，且该 tab label = 角色名。
#   旧布局（一个 tab 内 split 出多 pane）⇒ 迁移无损：`pane move <pane> --new-tab`（pane_id 不变，
#   被搬空的 tab 由 herdr 自动关闭）+ `tab rename` 把新 tab 标成角色名；
#   tab 已独占但 label 旧（如根 tab 的 "1"）⇒ 只改 tab 名（effect 零风险）。
_term_herdr_layout_converge() {  # <pane_id> <name> [group] → 0 布局 A 达成 / 1 未达成（fail loud）
  local pid="${1-}" name="${2-}" group="${3-}" pt tid wsid row label cnt js newtid prev_tid="" closed_note=""
  # #139（M3）：期望标签 = `<组前缀>/<name>`（group 空 ⇒ 逐字旧行为）。四处同源之一（收敛判据）。
  local tablabel="$name"
  [[ -n "$group" ]] && tablabel="$group/$name"
  pt="$(_term_herdr_pane_tab "$pid")"
  if [[ -z "$pt" ]]; then
    warn "布局判据不可用：pane=$pid 不在 pane list（无法确认独立 tab）⇒ 计 SPAWN_FAIL"
    return 1
  fi
  tid="${pt%%$'\t'*}"; wsid="${pt#*$'\t'}"
  row="$(_term_herdr_tab_row "$wsid" "$tid")"
  label="${row%%$'\t'*}"; cnt="${row#*$'\t'}"
  if [[ "$label" == "$tablabel" ]]; then
    if [[ "$cnt" != "1" ]]; then
      warn "布局 A 违例：tab=$tid（label=$tablabel）含 ${cnt:-?} 个 pane（契约 = 每角色 tab 恰 1 pane）；不擅自搬动他人 pane"
      warn "  该怎么办：attach 后人工收口（herdr session attach ${HERDR_SESSION:-<session>}），或 cleanup 后 session-start 重建会话"
    fi
    return 0
  fi
  if [[ "$cnt" == "1" ]]; then
    if _term_herdr_exec tab rename "$tid" "$tablabel" >/dev/null 2>&1; then return 0; fi
    warn "tab rename 失败（tab=$tid → label=$tablabel）⇒ 布局 A 未达成（计 SPAWN_FAIL）"
    return 1
  fi
  js="$(_term_herdr_exec pane move "$pid" --new-tab 2>/dev/null)" \
    || { warn "pane move --new-tab 失败（pane=$pid name=$name）⇒ 布局 A 未达成（计 SPAWN_FAIL）"; return 1; }
  prev_tid="$tid"
  newtid="$(printf '%s' "$js" | sed -nE 's/.*"created_tab":\{[^}]*"tab_id":"([^"]+)".*/\1/p' | head -1)"
  if [[ -z "$newtid" ]]; then pt="$(_term_herdr_pane_tab "$pid")"; newtid="${pt%%$'\t'*}"; fi
  [[ -n "$newtid" ]] || { warn "pane move 后未取到新 tab_id（pane=$pid name=$name）⇒ 布局 A 未达成"; return 1; }
  (( _TERM_PLACE_CACHE )) && _term_herdr_place_set_tab "$pid" "$newtid" "$wsid"
  if ! _term_herdr_exec tab rename "$newtid" "$tablabel" >/dev/null 2>&1; then
    warn "tab rename 失败（tab=$newtid → label=$tablabel）⇒ 布局 A 未达成（计 SPAWN_FAIL）"; return 1
  fi
  if [[ -n "$(_term_herdr_tab_row "$wsid" "$prev_tid")" ]]; then
    closed_note="源 tab $prev_tid 仍有其他 pane（未关闭）"
  else
    closed_note="被搬空的 tab $prev_tid 已由 herdr 自动关闭"
  fi
  log "[herdr] 布局 A 迁移：$name（pane=$pid）已搬到独立 tab $newtid（pane_id 不变；$closed_note）"
  return 0
}

_term_herdr_spawn() {  # <name> <inner> <repo> [force] <label> [group] [task] → SPAWN_RC_OK|FAIL
  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" task="${7-}" pl="" obj js line
  local pane="" wsid="" tid="" first="" nmatch=0 hit="" verdict="" seq="" launched=0 live_n=""
  # T554：tab 标签 = 名字（**组前缀退役** —— 1 workspace = 1 仓，同仓无需 `code/` 分组）。
  local tablabel="$name"
  [[ -n "$name" && -n "$inner" ]] || { warn "herdr spawn 参数缺失（name/inner）"; return "$SPAWN_RC_FAIL"; }
  # 放置键（T554）：入参 = **仓基键**（含冲突号，调用方相位 1 算定）；本函数不反解名字、不重算仓 slug。
  [[ -n "$label" ]] || { warn "herdr spawn 缺 workspace label（期望 = 仓基键；repo=$repo）"; return "$SPAWN_RC_FAIL"; }
  if ! fleet_scope_problem "$label" >/dev/null; then
    warn "herdr spawn 的 workspace label 不可用（label=$label；期望 ^[a-z0-9][a-z0-9_-]{0,15}$）"; return "$SPAWN_RC_FAIL"
  fi

  # ---- 目标 workspace 先定（同名判重**只在目标 ws 内**：跨 ws 同名合法）----
  if (( _TERM_PLACE_CACHE )); then
    wsid="${_TERM_PLACE_WS_BY_LABEL[$label]:-}"
  else
    wsid="$(_term_herdr_workspace_id_for "$label")"
  fi
  # ---- 同名 label 已在场（目标 ws 内）：0 ⇒ 正常放置；1 ⇒ 按证据分派；>1 ⇒ warn + 不猜 ----
  #   T554：快照已由 ensure 一次性建好（≤1 次 pane list）；未启用缓存时才直查（status/close 路径）。
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      [[ -n "$wsid" && "$_TP_WS" == "$wsid" ]] || continue
      [[ "$_TP_LABEL" == "$name" ]] || continue
      nmatch=$((nmatch + 1))
      hit="${hit}${hit:+ }$_TP_PANE"
    done
  else
    pl="$(_term_herdr_exec pane list 2>/dev/null)" || { warn "herdr pane list 失败（server 未就绪？）"; return "$SPAWN_RC_FAIL"; }
    while IFS= read -r obj; do
      [[ -n "$(_term_json_str "$obj" pane_id)" ]] || continue
      [[ "$(_term_json_str "$obj" label)" == "$name" ]] || continue
      [[ -n "$wsid" && "$(_term_json_str "$obj" workspace_id)" == "$wsid" ]] || continue
      nmatch=$((nmatch + 1))
      hit="${hit}${hit:+ }$(_term_json_str "$obj" pane_id)"
    done < <(_term_json_objs <<< "$pl")
  fi
  if (( nmatch > 1 )); then
    warn "同名 label 命中多个 pane：$name ⇒ $hit（不猜：既不判「已在运行」，也不擅自选一个）"
    warn "  该怎么办：先人工核对/清理重复 label（回收面归 B3），再重跑 ensure"
    return "$SPAWN_RC_FAIL"
  fi
  if (( nmatch == 1 )); then
    pane="$hit"
    local fgname probe pstate pmsg
    local -a fgnames=()
    vline="$(term_liveness "$name" "$repo")"
    IFS=$'\t' read -r verdict _ seq _ <<< "$vline"
    probe="$(_term_herdr_probe_pane "$pane")"
    pstate="${probe%%$'\t'*}"; pmsg="${probe#*$'\t'}"
    [[ "$pmsg" == "$probe" ]] && pmsg=""
    case "$pstate" in
      notfound)
        # **只有明确 pane_not_found** 才是 `stop→restart` 回放的不可寻址 pane ⇒ close 安全
        warn "restart 回放幽灵：$name 的 pane=$pane 明确 pane_not_found（verdict=$verdict seq=$seq）⇒ 不判「已在运行」，关闭该幽灵 pane 后重建"
        _term_herdr_exec pane close "$pane" >/dev/null 2>&1 || true
        _term_herdr_place_drop_pane "$pane"
        pane=""
        ;;
      ok)
        while IFS=$'\t' read -r fgname _; do
          [[ -n "$fgname" ]] && fgnames+=("$fgname")
        done < <(_term_herdr_argv "$pane")
        if (( ${#fgnames[@]} == 0 )); then
          # pane 可达但前台不可判（空进程表）⇒ **不 close**、不注入，fail loud
          warn "前台不可判（$name ⇒ $pane：process-info 无前台进程）⇒ 不关闭、不注入、不判「已在运行」"
          warn "  该怎么办：先回收该角色（nao-fleet.sh close ${name}）再 ensure；--force 不绕过本条（仍不会新建重复 label）"
          return "$SPAWN_RC_FAIL"
        elif _term_fg_list_is_shell "${fgnames[@]}"; then
          # 前台是交互式 shell ⇒ 可以安全把启动命令送进去；label 在、agent 无 = **不判「已在运行」**（不静默跳过）
          warn "label 已在场但不在线（幽灵 pane / stale：$name ⇒ $pane，verdict=$verdict 前台=${fgnames[*]}）⇒ 不判「已在运行」，复用该 pane 重跑 agent"
        elif $force; then
          # --force：显式要一个新会话；**不向在场程序注入按键**（会污染 vim/REPL/cat 的输入）。
          warn "前台非 shell（$name ⇒ $pane 前台=${fgnames[*]}）：--force 也不向在场程序注入按键"
          warn "  → 随后按布局 A 放置：角色 tab 已被占用 ⇒ fail loud（不新建重复 label；改法：先 close 该角色再 ensure）；旧 pane 在共享 tab 里才会新建独立 tab（旧 label 仍在 ⇒ status 标同名歧义）"
          pane=""
        else
          warn "前台非 shell（$name ⇒ $pane 前台=${fgnames[*]}）⇒ **不注入按键**、不判「已在运行」（向正在运行的程序写命令会污染其输入：vim/REPL/cat）"
          warn "  该怎么办：人工核对后关闭该 pane（回收面归 B3），或加 --force 后按布局 A 放置（角色 tab 被占用 ⇒ fail loud，不新建重复 tab/label）"
          return "$SPAWN_RC_FAIL"
        fi
        ;;
      *)
        # internal_error / 超时 / 解析失败 / 空输出：pane 可能仍可达 ⇒ **绝不 close**，fail loud 点名错误类别
        warn "process-info 错误（$name ⇒ $pane：${pmsg:-未知错误}）⇒ **不关闭**（pane 可能仍可达/正跑用户程序）、不判「已在运行」、不注入"
        warn "  该怎么办：稍后重试；确认该 pane 无用后先 close 该角色（回收面归 B3）再 ensure；--force 不绕过本条（仍不会新建重复 label）"
        return "$SPAWN_RC_FAIL"
        ;;
    esac
  fi

  # ---- 复用 pane（ghost）：先 label 后启动；失败（不可寻址）⇒ 关闭幽灵 pane 后重建 ----
  if [[ -n "$pane" ]]; then
    if _term_herdr_exec pane rename "$pane" "$name" >/dev/null 2>&1 \
       && _term_herdr_exec pane run "$pane" "$inner" >/dev/null 2>&1; then
      launched=1
    else
      warn "复用失败：pane=$pane 不可寻址（重启回放的幽灵 pane）⇒ 关闭它并重建（避免同名 label 歧义）"
      _term_herdr_exec pane close "$pane" >/dev/null 2>&1 || true
      _term_herdr_place_drop_pane "$pane"
      pane=""
    fi
  fi

  # ---- 放置（T554）：1 workspace/仓（label = 仓基键）+ 1 tab/角色 + 每 tab 恰 1 pane ----
  #   · 快照启用时 workspace 查找/空 ws 判据读本命令快照（≤1 次 workspace list + ≤1 次 pane list）；
  #   · 空 workspace（pane 全关）⇒ 关旧建新（同名 label 仍唯一）；
  #   · 角色 tab 已在场但无 pane 命中该角色 ⇒ **不猜**（fail loud）。
  if (( ! launched )); then
    if (( _TERM_PLACE_CACHE )); then
      first=""
      for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
        [[ -n "$line" ]] || continue
        _term_place_pane_fields "$line"
        [[ -n "$wsid" && "$_TP_WS" == "$wsid" ]] && { first="$_TP_PANE"; break; }
      done
    else
      if [[ -n "$wsid" ]]; then
        js="$(_term_herdr_exec pane list --workspace "$wsid" 2>/dev/null)" \
          || { warn "herdr pane list --workspace $wsid 失败"; return "$SPAWN_RC_FAIL"; }
        first="$(_term_json_str "$js" pane_id)"
      fi
    fi
    if [[ -n "$wsid" && -z "$first" ]]; then
      # 空 workspace（pane 已被关）：先关掉空的旧 workspace，再建新的（同名 label 仍唯一）。
      #   **#160 P0 护栏**：关闭是破坏性且不可回滚（会连带杀掉该 ws 里用户的 pi 会话）⇒ 关前用
      #   **原始 `pane list --workspace`** 再确认「确实 0 pane」；快照判空但实测非空 ⇒ **不关 + fail loud**
      #   （点名 wsid 与实测 pane 数）。宁可不建新 ws，也不杀用户会话。
      if ! live_n="$(_term_herdr_ws_pane_count_live "$wsid")"; then
        warn "workspace 关闭前复核失败（workspace=$wsid：pane list --workspace 不可用）⇒ **不关**（无法证明它是空的）"
        warn "  该怎么办：核对 herdr server 后重跑 ensure；确认该 ws 无人使用后手工 herdr workspace close $wsid（回收面归 B3）"
        return "$SPAWN_RC_FAIL"
      fi
      if [[ "$live_n" != "0" ]]; then
        warn "空 workspace 判据与实测冲突：workspace=$wsid 快照判 0 pane，实测 ${live_n} pane ⇒ **不关**（关掉会连带杀掉在场会话）"
        warn "  该怎么办：这是解析/并发缺陷的信号，勿手工重试同一命令；先看 herdr pane list --workspace $wsid 核对归属，再重跑 ensure"
        return "$SPAWN_RC_FAIL"
      fi
      _term_herdr_exec workspace close "$wsid" >/dev/null 2>&1 || true
      wsid=""
    fi
    if [[ -z "$wsid" ]]; then
      js="$(_term_herdr_exec workspace create --cwd "$repo" --label "$label" --no-focus 2>/dev/null)" \
        || { warn "herdr workspace create 失败（label=$label cwd=$repo）"; return "$SPAWN_RC_FAIL"; }
      pane="$(_term_json_str "$js" pane_id)"
      wsid="$(_term_json_str "$js" workspace_id)"
      tid="$(_term_json_str "$js" tab_id)"
      [[ -n "$pane" ]] || { warn "herdr workspace create 未返回 root_pane.pane_id（label=$label）"; return "$SPAWN_RC_FAIL"; }
      # 布局 A：workspace 的根 tab 归位为角色 tab（label = 名字）
      if [[ -z "$tid" ]] || ! _term_herdr_exec tab rename "$tid" "$tablabel" >/dev/null 2>&1; then
        warn "herdr tab rename 失败（tab=${tid:-<无>} label=$tablabel）⇒ 布局 A 未达成"; return "$SPAWN_RC_FAIL"
      fi
      (( _TERM_PLACE_CACHE )) && _TERM_PLACE_WS_BY_LABEL["$label"]="$wsid"
    else
      tid="$(_term_herdr_tab_id_for "$wsid" "$tablabel")"
      if [[ -n "$tid" ]]; then
        warn "角色 tab 已在场但无 pane 命中该角色（workspace=$wsid tab=$tid label=$tablabel）⇒ 不猜：既不新建第二个同名 tab，也不接管他人 pane"
        warn "  该怎么办：先回收该角色（nao-fleet.sh close ${name}）再重跑 ensure；--force 不绕过本条（避免同名 label 重复）"
        return "$SPAWN_RC_FAIL"
      fi
      js="$(_term_herdr_exec tab create --workspace "$wsid" --cwd "$repo" --label "$tablabel" --no-focus 2>/dev/null)" \
        || { warn "herdr tab create 失败（workspace=$wsid label=$tablabel cwd=$repo）"; return "$SPAWN_RC_FAIL"; }
      pane="$(_term_json_str "$js" pane_id)"
      tid="$(_term_json_str "$js" tab_id)"
      [[ -n "$pane" ]] || { warn "herdr tab create 未返回 root_pane.pane_id（label=$tablabel）"; return "$SPAWN_RC_FAIL"; }
    fi
    # ---- 先 label 后启动（顺序是契约：否则 status 可能抓到无 label 的 pi pane）----
    if ! _term_herdr_exec pane rename "$pane" "$name" >/dev/null 2>&1; then
      warn "herdr pane rename 失败（pane=$pane label=$name）"; return "$SPAWN_RC_FAIL"
    fi
    if ! _term_herdr_exec pane run "$pane" "$inner" >/dev/null 2>&1; then
      warn "herdr pane run 失败（pane=$pane name=$name）"; return "$SPAWN_RC_FAIL"
    fi
  fi
  _TERM_SPAWN_PANE="$pane"; _TERM_SPAWN_WSID="$wsid"; _TERM_SPAWN_TID="$tid"
  # v3 元数据：herdr 无键值 label ⇒ sidecar（失败仅 warn，不阻断启动）
  [[ -n "$task" ]] && fleet_meta_write "$(fleet_meta_wsref "$wsid")" "$pane" "$task" "$name"
  # 快照失效：本命令后续目标（判重/归属）必须看到新 pane，不得复用 spawn 前的旧快照
  if [[ -n "${_TERM_SNAP_FILE:-}" ]]; then rm -f "$_TERM_SNAP_FILE" 2>/dev/null || true; _TERM_SNAP_FILE=""; fi
  # 放置快照回填（T554）：新 pane 进本命令快照（不再为后续目标重查 pane list）
  if (( _TERM_PLACE_CACHE )); then
    _term_place_set_pane "$name" "$pane" "$wsid" "$tid" "$repo" "$task"
  fi

  # ---- J2 结构收敛（布局 A）：复用路径也跑（旧布局的 pane 在共享 tab 里 ⇒ 迁移到独立 tab）----
  if ! _term_herdr_layout_converge "$pane" "$name" "$group"; then
    return "$SPAWN_RC_FAIL"
  fi
  # ---- J1/J5 空间判据（放置后自测；0 尺寸 ⇒ SPAWN_FAIL，不足 ⇒ 只 warn）----
  if ! _term_herdr_space_check "$pane" "$name"; then
    return "$SPAWN_RC_FAIL"
  fi

  # ---- 就绪门（反假阳性）：全条件与，50×100ms / 5s，超时 fail loud（pane 保留，不自动 kill）----
  if ! _term_herdr_wait_ready "$pane" "$name"; then
    return "$SPAWN_RC_FAIL"
  fi
  return "$SPAWN_RC_OK"
}

# 投递（T548）：`agent prompt` 自带「提交 + 按 pane 的 bracketed-paste 模式包裹」⇒ **不再**补 Enter；
#   不带 `--wait`（那会把「已投递」耦合到「自检 turn 跑完」，两类失败混在一起）。
#   成功判据 = rc==0 **且 stdout 无 `"error":{"code"`**（真 herdr 把错误写在 stdout，别只吞 stderr）。
_term_herdr_deliver() {  # <pane_id> <message> → 0 已投递 / 1 失败（stdout: error code）
  local pane="${1-}" msg="${2-}" out="" rc=0 code=""
  [[ -n "$pane" ]] || { printf 'pane_id 缺失\n'; return 1; }
  out="$(_term_herdr_exec agent prompt "$pane" "$msg" 2>&1)" || rc=$?
  if (( rc != 0 )) || grep -qF '"error":{"code"' <<< "$out"; then
    code="$(sed -nE 's/.*"error":\{[[:space:]]*"code":[[:space:]]*"([^"]+)".*/\1/p' <<< "$out" | head -1)"
    printf 'rc=%s code=%s\n' "$rc" "${code:-unknown}"
    return 1
  fi
  return 0
}

# 就绪探针（单次）：七条件全与 ⇒ 0；结果落 _TR_* 供超时时**逐条**报缺。
_term_herdr_ready_state() {  # <pane_id> <expected name>
  local pid="${1-}" want="${2-}" al="" js="" obj av nm sess stat seq skip
  _TR_PANE=0; _TR_FG=""; _TR_ARGV=""; _TR_SESS=0; _TR_STAT=""; _TR_SEQ=0; _TR_SKIP=0
  [[ -n "$pid" ]] || return 1
  # T554：不再 per-poll `pane list`（ensure ≤1 次 pane list）—— pane 存在性由 process-info 承担
  #   （pane 已消失 ⇒ process-info 失败 ⇒ 下面七条件不满足 ⇒ 超时 fail loud，诊断行仍点名）。
  js="$(_term_herdr_exec pane process-info --pane "$pid" 2>/dev/null)" || js=""
  [[ -z "${js//[[:space:]]/}" ]] || _TR_PANE=1
  (( _TR_PANE )) || return 1
  while IFS= read -r obj; do
    [[ "$obj" == *'"argv":'* ]] || continue
    nm="$(_term_json_str "$obj" name)"
    [[ -n "$nm" ]] || continue
    [[ -n "$_TR_FG" ]] || _TR_FG="$nm"
    if [[ "$nm" == "pi" ]]; then
      _TR_FG="pi"
      av="$(sed -n 's/.*"argv":\[\([^]]*\)\].*/\1/p' <<< "$obj" | tr -d '"' | sed 's/,/ /g')"
      _TR_ARGV="$(_term_argv_name "$av")"
      break
    fi
  done < <(_term_json_objs <<< "$js")
  al="$(_term_herdr_exec agent list 2>/dev/null)" || al=""
  while IFS= read -r obj; do
    [[ "$(_term_json_str "$obj" pane_id)" == "$pid" ]] || continue
    [[ "$obj" == *'"agent_session":{'* ]] && sess="$(_term_json_str "$obj" value)" || sess=""
    stat="$(_term_json_str "$obj" agent_status)"
    seq="$(_term_json_raw "$obj" state_change_seq)"
    skip="$(_term_json_raw "$obj" screen_detection_skipped)"
    [[ -n "$sess" ]] && _TR_SESS=1
    _TR_STAT="${stat:--}"; _TR_SEQ="${seq:-0}"
    [[ "$skip" == "true" ]] && _TR_SKIP=1
    break
  done < <(_term_json_objs <<< "$al")
  [[ "$_TR_FG" == "pi" && "$_TR_ARGV" == "$want" && "$_TR_SESS" == "1" && "$_TR_STAT" == "idle" ]] || return 1
  [[ "$_TR_SEQ" =~ ^[0-9]+$ ]] || return 1
  (( _TR_SEQ >= 1 )) || return 1
  [[ "$_TR_SKIP" == "1" ]] || return 1
  return 0
}

_term_herdr_wait_ready() {  # <pane_id> <name> → 0 就绪 / 1 超时（逐条报缺 + 指路）
  local pid="${1-}" want="${2-}" i max="${TERM_READY_POLL_MAX:-50}" int="${TERM_READY_POLL_INT:-0.1}"
  local budget="${TERM_READY_TIMEOUT_MS:-5000}" start_ms now_ms elapsed
  # wall-clock 上限（不是「50×0.1s 睡眠」—— 每轮含 3 次 CLI 调用，只数睡眠会 name-only 5s）
  start_ms="$(date +%s%N)"
  elapsed=0
  for ((i = 1; i <= max; i++)); do
    _term_herdr_ready_state "$pid" "$want" && return 0
    now_ms="$(date +%s%N)"
    elapsed=$(( (now_ms - start_ms) / 1000000 ))
    (( elapsed >= budget )) && break
    sleep "$int"
  done
  now_ms="$(date +%s%N)"; elapsed=$(( (now_ms - start_ms) / 1000000 ))
  warn "就绪门超时（wall-clock 上限 ${budget}ms / ≤${max} 轮 × ${int}s，实际 ${elapsed}ms）：$want（pane=$pid）未满足以下条件："
  (( _TR_PANE )) || warn "  · pane 存在：pane list 无 $pid"
  [[ "$_TR_FG" == "pi" ]] || warn "  · 前台进程 name==pi：实际 ${_TR_FG:-<无前台进程>}"
  [[ "$_TR_ARGV" == "$want" ]] || warn "  · argv --name == $want：实际 ${_TR_ARGV:-<空>}（进程未起或 --name 不同）"
  (( _TR_SESS )) || warn "  · agent_session != null：agent list 无该 pane 的会话身份（pi-intercom/herdr 集成缺失？）"
  [[ "$_TR_STAT" == "idle" ]] || warn "  · agent_status == idle：实际 ${_TR_STAT:-<无条目>}"
  { [[ "$_TR_SEQ" =~ ^[0-9]+$ ]] && (( _TR_SEQ >= 1 )); } || warn "  · state_change_seq ≥ 1：实际 ${_TR_SEQ:-0}（未观测到状态迁移）"
  [[ "$_TR_SKIP" == "1" ]] || warn "  · screen_detection_skipped == true：实际 false（状态来自屏幕启发式，不可作就绪判据）"
  warn "  · 诊断指路：herdr --session ${HERDR_SESSION:-<session>} agent explain $pid"
  warn "  · 若 pi 首次启动停在 What's New / 信任提示（如 lastChangelogVersion 落后于 pi 版本），先手工关闭再重试"
  return 1
}

# 起专用 session 的 server（BR6 生产单点）：清宿主终端句柄 + 枚举清 HERDR_* → 轮询就绪 → attach 指路。
#   幂等：已就绪 ⇒ effect=0；失败 ⇒ rc=1 + 日志尾 + 改法；用法守卫（缺名/default/非法名）⇒ rc=2。
_term_herdr_session_start() {  # <session>
  local s="${1-}" root="" sock="" log="" prev="" i ok=0 max="${TERM_READY_POLL_MAX:-50}" int="${TERM_READY_POLL_INT:-0.1}"
  command -v herdr >/dev/null 2>&1 || { printf '需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试；旧版 tmux 后端已移除，需要它请 pin 回 ≤0.27.x）\n' >&2; return 1; }
  case "$s" in
    ""|"default") printf '需要 herdr 会话名：%s 不可用（--session 必填且 ≠default —— default 是用户会话，BR9）\n' "${s:-<空>}" >&2; return 2 ;;
  esac
  if [[ ! "$s" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf '需要 herdr 会话名：%s 非法（^[A-Za-z0-9._-]+$）\n' "$s" >&2; return 2
  fi
  root="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
  sock="$root/sessions/$s/herdr.sock"
  # 注：此处**不再**校验 `case "$sock"` —— sock 由 root+会话名拼出且会话名已禁 `/`/空白/glob，
  #   那个 case 恒真（死守卫，QA P2-1）。防串台由：① 会话名守卫 ② `_term_herdr_exec` 的 `--session`
  #   ③ `_term_herdr_require` 对 pane 内 `HERDR_SOCKET_PATH` 的**目标根**校验承担。
  prev="${HERDR_SESSION:-}"
  export HERDR_SESSION="$s"
  # 就绪判据 = **api snapshot**（真触 server）；`api schema` 是本地静态元数据（无 server 也 rc=0，禁作存活判据）
  if _term_herdr_exec api snapshot >/dev/null 2>&1; then
    printf '[fleet] herdr session=%s 已在运行（effect=0）；attach: herdr session attach %s\n' "$s" "$s"
    if [[ -n "$prev" ]]; then export HERDR_SESSION="$prev"; else unset HERDR_SESSION; fi
    return 0
  fi
  log="$(mktemp "${TMPDIR:-/tmp}/nao-fleet-herdr-server-${s}.XXXXXX.log" 2>/dev/null)" || log=""
  ( _term_herdr_exec --server-start server >"${log:-/dev/null}" 2>&1 & ) || true
  for ((i = 1; i <= max; i++)); do
    if _term_herdr_exec api snapshot >/dev/null 2>&1; then ok=1; break; fi
    sleep "$int"
  done
  if (( ! ok )); then
    printf '[fleet] herdr session=%s server 未在 %s×%ss 内就绪（已用尽轮询）\n' "$s" "$max" "$int" >&2
    if [[ -n "$log" && -f "$log" ]]; then
      printf '[fleet] 启动日志尾（末 5 行 %s）：\n' "$log" >&2
      tail -5 "$log" >&2 || true
    fi
    printf '[fleet] 该怎么办：核对 `herdr session list` / `herdr --session %s api schema`（要求 herdr ≥0.9.1 且 protocol 22）\n' "$s" >&2
    if [[ -n "$prev" ]]; then export HERDR_SESSION="$prev"; else unset HERDR_SESSION; fi
    return 1
  fi
  [[ -n "$log" ]] && rm -f "$log" 2>/dev/null || true
  printf '[fleet] herdr session=%s server 已就绪（socket: %s）\n' "$s" "$sock"
  printf '  · attach: herdr session attach %s（在该会话 pane 内用 NAO_TERMINAL=herdr nao-fleet.sh ensure …）\n' "$s"
  if [[ -n "$prev" ]]; then export HERDR_SESSION="$prev"; else unset HERDR_SESSION; fi
  return 0
}
# <<< term-facade-herdr END
