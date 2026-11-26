# =============================================================================
# fleet/lib/sessions.sh — 舰队 session 记录治理（T573 · Issue #206）
#
#   ⓐ **独立目录 + 一仓一子目录**：`ensure` 给**全部**舰队会话（常驻 + `--task` 派生）加
#      `pi --session-dir <root>/<编码 cwd>`（root = `$FLEET_STATE_ROOT/sessions`，与 sidecar
#      `session-meta/` 同处；`NAO_FLEET_META_DIR` 一起覆盖）
#      ⇒ 记录**不落** `~/.pi/agent/sessions/`，`/resume` 主列表只剩用户自己的会话。
#      注（实测 pi 1.6.0）：显式 `--session-dir` **不会**再按 cwd 分子目录
#        （`SessionManager.create` = `normalizePath(sessionDir)`，文件名直接 join 该目录）——
#        所以「一仓一子目录」由**本模块**按 Pi 默认目录的同款编码（`--<cwd 去掉首 / 再把 / : 换成 ->--`）
#        建好并传入，`/resume`/`--continue` 的目录语义与默认布局一致。
#      目录不可建 ⇒ 调用方 **fail loud**（绝不静默落回主目录）。
#   ⓑ **按结果分级**短保留（`--days N` 可一次性覆盖；按**文件 mtime** 判寿命，不造日期层）：
#        · 正常交付（有 `done` 回执，或 close 判定正常）⇒ 24h
#        · 异常（无回执 / `close --force` / 崩溃 / 判不出）⇒ 7 天，并在**记录所在 state 子目录**的
#          `.retention.log` 留一行点名（角色 + 任务 + 路径；同一记录只点一次 ⇒ 幂等）
#          —— 机制内部状态**不写**业务仓的 `docs/tasks-state.md`（那是交付台账，T573 返修 D2）
#      结果来源（fail-closed：判不出 = 异常，绝不猜「正常」）：
#        · 台账（每仓目录 `.ledger`，append-only TSV：
#          `<epoch>\t<kind>\t<name>\t<role>\t<task>\t<repo>`；kind = spawn / done / force）
#          —— ensure 落 spawn、close 落 done|force；记录↔台账按 (name, 起始时刻就近 ≤6h) 归属，
#          **只在记录自己的仓台账里**找（跨仓 done 不得升级本仓记录），且 done/force 必须落在
#          **该代窗口** = 「本代 spawn 之后、下一同名 spawn 之前」；带 task 的行按 task 逐字比对。
#          无 spawn 行 ⇒ 代次判不出 ⇒ 不认 done/force（T573 返修 D1：原按名字全仓匹配 ⇒ fail-open）
#        · 回执 `<cwd>/docs/queue/<task>.receipt.json` 存在 ⇒ 正常交付
#      清理时机：`ensure`（顺手、静默、全量）与 `logs --purge`；**幂等**、失败只 warn、不改 rc。
#   ⓒ `logs <role> [--repo <仓名>]`：turn 摘要（user 首行 + assistant 首行 + 工具名）/ `--raw` /
#      `--list`（仓 + 日期 + 角色 + 大小 + 路径）/ `--purge [--days N]`。
#      **默认只看当前仓**（`git rev-parse --show-toplevel` → `place_key_label` 仓基键）；`--repo all` 看全部。
#      无记录 ⇒ rc=0 + 一行提示。
#   纪律：近 `FLEET_SESSION_BUSY_SEC` 有写入 ⇒ 可能在跑，本轮**不删**（宁留勿删）。
#   依赖：core（FLEET_STATE_ROOT / log / warn / die）· manifest（place_key_label；缺则回落 basename 归一）
# =============================================================================
FLEET_SESSIONS_ROOT="$FLEET_STATE_ROOT/sessions"
FLEET_SESSION_KEEP_OK_SEC=86400        # 正常交付：24h
FLEET_SESSION_KEEP_BAD_SEC=604800      # 异常：7 天
FLEET_SESSION_LEDGER_WINDOW=21600      # 台账↔记录 归属窗口（6h；超窗不猜 ⇒ 按异常）
FLEET_SESSION_BUSY_SEC=3600            # 近 1h 有写入 ⇒ 视为可能在跑，本轮跳过删除

# ---------------------------------------------------------------------------
# 目录（一仓一子目录）与台账（写入面：ensure / close）
# ---------------------------------------------------------------------------
_fleet_sessions_dir_name() {  # <repo 物理路径> → Pi 默认布局同款目录名（--a-b-c--）
  local p="${1-}"
  [[ -n "$p" ]] || { printf '%s\n' "--unknown--"; return 0; }
  printf -- '--%s--\n' "$(printf '%s' "${p#/}" | sed -e 's#[/\\:]#-#g')"
}

fleet_sessions_dir() {  # [repo] → <root>/<编码 cwd>（默认当前仓）
  local p="${1:-$PWD}"
  p="$(nao_phys_path "$p")"
  [[ -n "$p" ]] || p="$PWD"
  printf '%s/%s\n' "$FLEET_SESSIONS_ROOT" "$(_fleet_sessions_dir_name "$p")"
}

fleet_sessions_prepare() {  # <dir> → 0 = 已存在/已建；1 = 不可建（调用方 fail loud）
  local d="${1-}"
  [[ -n "$d" ]] || return 1
  [[ -d "$d" ]] && return 0
  mkdir -p "$d" 2>/dev/null || return 1
  [[ -d "$d" ]]
}

fleet_sessions_note_spawn() {  # <name> <role> <task> <repo> → 0 / 1（失败仅 warn，不阻断启动）
  local n="${1-}" r="${2-}" t="${3-}" repo="${4-}" dir
  [[ -n "$n" ]] || return 1
  dir="$(fleet_sessions_dir "$repo")"
  fleet_sessions_prepare "$dir" \
    || { warn "会话台账目录不可建：$dir（本轮不记绑定 ⇒ 该记录按异常保留 7 天）"; return 1; }
  printf '%s\tspawn\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$n" "${r:--}" "${t:--}" "${repo:--}" \
    >> "$dir/.ledger" 2>/dev/null \
    || { warn "会话台账写入失败：$dir/.ledger（不阻断启动；该记录按异常保留 7 天）"; return 1; }
  return 0
}

fleet_sessions_note_outcome() {  # <name> <task> <repo> <force:true|false> → 0 / 1（失败仅 warn）
  local n="${1-}" t="${2-}" repo="${3-}" force="${4:-false}" dir kind
  [[ -n "$n" ]] || return 1
  if [[ "$force" == "true" ]]; then kind="force"; else kind="done"; fi
  dir="$(fleet_sessions_dir "${repo:-$PWD}")"
  fleet_sessions_prepare "$dir" || { warn "会话台账目录不可建：$dir（close 结果未记账）"; return 1; }
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%s)" "$kind" "$n" "-" "${t:--}" "${repo:--}" \
    >> "$dir/.ledger" 2>/dev/null \
    || { warn "会话台账写入失败：$dir/.ledger（close 结果未记账）"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# 仓维度（logs 的默认作用域）
# ---------------------------------------------------------------------------
_fleet_repo_key() {  # <path> → 仓基键（place_key_label 同口径；缺则 basename 归一）
  local p="${1-}" k=""
  [[ -n "$p" && "$p" != "-" ]] || { printf '%s\n' "-"; return 0; }
  if declare -F place_key_label >/dev/null 2>&1; then
    k="$(place_key_label "$p" 2>/dev/null || true)"
  fi
  if [[ -z "$k" ]]; then
    k="$(basename "$p" | tr '[:upper:]' '[:lower:]' \
         | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//' \
         | cut -c1-16 | sed -e 's/-$//')"
  fi
  printf '%s\n' "${k:--}"
}

_fleet_current_repo() {  # → 当前仓根（git toplevel 优先；非 git 仓 = PWD）
  local top=""
  if command -v git >/dev/null 2>&1; then
    top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  printf '%s\n' "${top:-$PWD}"
}

_fleet_repo_matches() {  # <记录 cwd> <--repo 值> → 0 命中
  local cwd="${1-}" want="${2-}"
  [[ -z "$want" || "$want" == "all" ]] && return 0
  [[ "$cwd" == "$want" ]] && return 0
  [[ "$(_fleet_repo_key "$cwd")" == "$want" ]] && return 0
  [[ "$(basename "${cwd:-/}")" == "$want" ]] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# 记录读取（单一事实 = Pi 的 jsonl：header `type":"session"` + `session_info.name`）
# ---------------------------------------------------------------------------
_fleet_mtime() {  # <file> → epoch（GNU stat → BSD stat → 0）
  local e=""
  e="$(stat -c %Y "$1" 2>/dev/null || true)"
  [[ -n "$e" ]] || e="$(stat -f %m "$1" 2>/dev/null || true)"
  printf '%s\n' "${e:-0}"
}

_fleet_epoch_of() {  # <ISO8601> → epoch（GNU date → BSD date → 0）
  local ts="${1-}" e=""
  [[ -n "$ts" ]] || { printf '0\n'; return 0; }
  e="$(date -u -d "$ts" +%s 2>/dev/null || true)"
  if [[ -z "$e" ]]; then
    e="$(date -u -j -f "%Y-%m-%dT%H:%M:%S" "${ts%%.*}" +%s 2>/dev/null || true)"
  fi
  printf '%s\n' "${e:-0}"
}

_fleet_json_field() {  # <file> <json key> [行内前缀过滤] → 首个匹配行的值（无则空）
  local f="${1-}" key="${2-}" want="${3-}" needle
  [[ -f "$f" && -n "$key" ]] || return 0
  needle="\"$key\":\""
  LC_ALL=C awk -v needle="$needle" -v want="$want" '
    (want == "" || index($0, want) > 0) {
      p = index($0, needle)
      if (p) { s = substr($0, p + length(needle)); q = index(s, "\""); if (q) { print substr(s, 1, q - 1); exit } }
    }
  ' "$f" 2>/dev/null | head -1
}

fleet_session_name() {  # <file> → 会话名（session_info.name；无则空）
  _fleet_json_field "$1" name '"type":"session_info"'
}

_fleet_session_meta() {  # <file> → "<name>\t<iso>\t<cwd>"
  local f="${1-}" name="" iso="" cwd=""
  [[ -f "$f" ]] || return 1
  name="$(fleet_session_name "$f")"
  iso="$(_fleet_json_field "$f" timestamp '"type":"session"')"
  cwd="$(_fleet_json_field "$f" cwd '"type":"session"')"
  printf '%s\t%s\t%s\n' "$name" "$iso" "$cwd"
}

_fleet_session_role_of() {  # <name> → 角色段（剥槽位号；卡会话 `<role>-<后缀>` 原样返回）
  local n="${1-}"
  [[ -n "$n" ]] || return 0
  if [[ "$n" =~ ^(.*[^2-9])([2-9])$ ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; else printf '%s\n' "$n"; fi
}

_fleet_role_id() {  # <别名|角色 id> → 角色 id（解析不出 ⇒ 原样返回；logs 不需完整 manifest）
  local a="${1-}" id=""
  [[ -n "$a" ]] || return 0
  if [[ -f "$MANIFEST" ]]; then
    id="$(LC_ALL=C awk -v want="$a" '
      /^  [a-z0-9][a-z0-9-]*:[[:space:]]*$/ {
        cur = $0; sub(/^  /, "", cur); sub(/:[[:space:]]*$/, "", cur)
        if (cur == want) { print cur; exit }
        next
      }
      /^    aliases:[[:space:]]*\[/ {
        v = $0; sub(/^    aliases:[[:space:]]*\[/, "", v); sub(/\].*$/, "", v)
        m = split(v, arr, ",")
        for (i = 1; i <= m; i++) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i])
          if (arr[i] == want) { print cur; exit }
        }
      }
    ' "$MANIFEST" 2>/dev/null | head -1)"
  fi
  printf '%s\n' "${id:-$a}"
}

_fleet_session_files() {  # [role] [task] [repo] → 每行一个 jsonl（按路径升序）
  local role="${1-}" task="${2-}" repo="${3-}" f name meta iso cwd
  [[ -d "$FLEET_SESSIONS_ROOT" ]] || return 0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    name="$(fleet_session_name "$f")"
    if [[ -n "$role" ]]; then
      [[ -n "$name" ]] || continue
      case "$name" in
        "$role"|"$role"-*) ;;
        *) [[ "$(_fleet_session_role_of "$name")" == "$role" ]] || continue ;;
      esac
    fi
    if [[ -n "$task" || -n "$repo" ]]; then
      meta="$(_fleet_session_meta "$f")" || continue
      IFS=$'\t' read -r name iso cwd <<< "$meta"
      _fleet_repo_matches "$cwd" "$repo" || continue
      if [[ -n "$task" ]]; then
        [[ "$(_fleet_session_task_of "$name" "$(_fleet_epoch_of "$iso")" "$(dirname "$f")")" == "$task" ]] || continue
      fi
    fi
    printf '%s\n' "$f"
  done < <(find "$FLEET_SESSIONS_ROOT" -mindepth 2 -maxdepth 2 -type f -name '*.jsonl' 2>/dev/null | sort)
}

# ---------------------------------------------------------------------------
# 台账查询（记录 ↔ spawn/done/force 的归属；超窗/缺失一律「判不出」）
# ---------------------------------------------------------------------------
_fleet_ledger_lines() {  # [dir] —— 给 dir ⇒ 只读该仓台账；否则全部仓的台账
  local d="${1-}"
  if [[ -n "$d" && -f "$d/.ledger" ]]; then
    cat "$d/.ledger" 2>/dev/null || true
  else
    cat "$FLEET_SESSIONS_ROOT"/*/.ledger 2>/dev/null || true
  fi
}

# 台账扫描："<epoch>\t<kind>\t<name>\t<role>\t<task>\t<repo>"；`nearest` = 距 ts 最近的 spawn 行（≤窗口）
_fleet_ledger_scan() {  # <dir|空> <name> <ts> <nearest|outcome|next> [until] [task]
  #   nearest = 距 ts 最近的 spawn 行（≤窗口）· next = 该代之后**下一个**同名 spawn 的 epoch
  #   outcome = 代次窗口内的 done/force 行（until = 下一代 spawn 起点，空 = 无上界；task 非空 ⇒ 带 task 的行须逐字相同）
  local dir="${1-}" name="${2-}" ts="${3-}" mode="${4-}" until="${5-}" task="${6-}"
  [[ -n "$name" ]] || return 0
  _fleet_ledger_lines "$dir" | LC_ALL=C awk -F'\t' -v n="$name" -v t="$ts" -v w="$FLEET_SESSION_LEDGER_WINDOW" \
      -v mode="$mode" -v u="$until" -v tk="$task" '
    mode == "nearest" {
      if ($3 == n && $2 == "spawn") {
        d = $1 - t; if (d < 0) d = -d
        if (best == "" || d < bestd) { best = $0; bestd = d }
      }
      next
    }
    mode == "next" {
      if ($3 == n && $2 == "spawn" && $1 > t) { if (nd == "" || $1 < nd) nd = $1 }
      next
    }
    mode == "outcome" {
      if ($3 != n || ($2 != "done" && $2 != "force")) next
      if (($1 + 60) < t) next
      if (u != "" && u != "0" && $1 >= u) next
      if ($5 != "-" && $5 != tk) next
      print
    }
    END {
      if (mode == "nearest" && best != "" && bestd <= w) print best
      if (mode == "next" && nd != "") print nd
    }
  ' 2>/dev/null || true
}

_fleet_session_spawn_row() {  # <name> <ts> [dir] → 该仓台账里最接近的 spawn 行（≤窗口）；否则空
  #   T573 返修 D1：**不再**退回「全部仓台账」—— 跨仓 spawn/done 不得参与本仓记录的分级
  #   （`dir` 为空 = 调用方本就按全仓视图查询，如 logs 的无仓过滤）
  local name="${1-}" ts="${2-}" dir="${3-}" row=""
  [[ -n "$name" ]] || return 0
  row="$(_fleet_ledger_scan "${dir:-}" "$name" "$ts" nearest)"
  printf '%s\n' "$row"
}

_fleet_session_outcome_rows() {  # <name> <ts> [dir] [until] [task] → 该代窗口内的 done/force 行（每行一个）
  _fleet_ledger_scan "${3-}" "${1-}" "${2-}" outcome "${4-}" "${5-}"
}

_fleet_session_task_of() {  # <name> <ts> [dir] → task（无绑定 ⇒ 空）
  local row t
  row="$(_fleet_session_spawn_row "${1-}" "${2-}" "${3-}")"
  [[ -n "$row" ]] || return 0
  t="$(printf '%s\n' "$row" | cut -f5)"
  [[ "$t" == "-" ]] && t=""
  printf '%s\n' "$t"
}

# 分级：正常 / 异常（+ 绑定的 task）。判不出 ⇒ 异常（fail-closed）。
_fleet_session_grade() {  # <name> <ts> <cwd> → "<normal|anomaly>\t<task>"
  local name="${1-}" ts="${2-}" cwd="${3-}" dir spawn="" task="" repo="" gen="" until="" after="" k dir2
  dir="$(_fleet_sessions_dir_name "$(nao_phys_path "${cwd:-$PWD}")")"
  dir2="$FLEET_SESSIONS_ROOT/$dir"
  spawn="$(_fleet_session_spawn_row "$name" "$ts" "$dir2")"
  if [[ -n "$spawn" ]]; then
    task="$(printf '%s\n' "$spawn" | cut -f5)"
    repo="$(printf '%s\n' "$spawn" | cut -f6)"
    [[ "$task" == "-" ]] && task=""
    # 代次窗口上界 = 本代 spawn 之后的下一个同名 spawn（无 ⇒ 无上界 = 最新一代）
    gen="$(printf '%s\n' "$spawn" | cut -f1)"
    until="$(_fleet_ledger_scan "$dir2" "$name" "$gen" next)"
  fi
  # 无 spawn 行 ⇒ 代次判不出 ⇒ 不认 done/force（fail-closed：宁可留 7 天 + 点名）
  after=""
  [[ -n "$spawn" ]] && after="$(_fleet_session_outcome_rows "$name" "$ts" "$dir2" "$until" "$task")"
  # close 判据优先于回执：--force = 明示「非正常收尾」；done = close 判定正常
  k="$(printf '%s\n' "$after" | awk -F'\t' '{ print $2 }' | head -20)"
  if printf '%s\n' "$k" | grep -qx 'force'; then printf 'anomaly\t%s\n' "$task"; return 0; fi
  if printf '%s\n' "$k" | grep -qx 'done';  then printf 'normal\t%s\n'  "$task"; return 0; fi
  if [[ -n "$task" ]]; then
    dir2="$cwd"
    [[ -n "$dir2" && "$dir2" != "-" ]] || dir2="$repo"
    if [[ -n "$dir2" && "$dir2" != "-" && -f "$dir2/docs/queue/$task.receipt.json" ]]; then
      printf 'normal\t%s\n' "$task"; return 0
    fi
  fi
  printf 'anomaly\t%s\n' "$task"
}

# 异常点名（T573 返修 D2：写记录所在 **state 子目录** `.retention.log`，不碰仓内交付台账；
#   幂等 = 同一记录只点一次名（按记录路径去重，跨天重跑也不重复））
_fleet_session_anomaly_note() {  # <name> <task> <file>
  local name="${1-}" task="${2-}" f="${3-}" dir line
  [[ -n "$f" ]] || return 0
  dir="$(dirname "$f")"
  [[ -d "$dir" ]] || return 0
  grep -qF -- "· $f" "$dir/.retention.log" 2>/dev/null && return 0
  line="$(date -u +%Y-%m-%dT%H:%M:%SZ) · [session-retention] ${name:-?} · task=${task:--} · $f"
  printf '%s\n' "$line" >> "$dir/.retention.log" 2>/dev/null \
    || { warn "会话异常点名写入失败：$dir/.retention.log（不影响清理结果）"; return 1; }
  return 0
}

# ---------------------------------------------------------------------------
# 清理（幂等；失败只 warn、不改 rc）
# ---------------------------------------------------------------------------
_fleet_session_purge_one() {  # <file> <days|""> <now> → "<deleted|kept>\t<grade>"
  local f="${1-}" days="${2-}" now="${3-}" meta name iso cwd ts grade task retain g
  meta="$(_fleet_session_meta "$f")" || return 1
  IFS=$'\t' read -r name iso cwd <<< "$meta"
  ts="$(_fleet_epoch_of "$iso")"
  (( ts > 0 )) || ts="$(_fleet_mtime "$f")"
  g="$(_fleet_session_grade "$name" "$ts" "$cwd")"
  IFS=$'\t' read -r grade task <<< "$g"
  if [[ "$grade" != "normal" ]]; then
    _fleet_session_anomaly_note "$name" "$task" "$f" || true
  fi
  if [[ -n "$days" ]]; then
    retain=$(( days * 86400 ))
  elif [[ "$grade" == "normal" ]]; then
    retain=$FLEET_SESSION_KEEP_OK_SEC
  else
    retain=$FLEET_SESSION_KEEP_BAD_SEC
  fi
  # 寿命按**文件 mtime**（Pi 文件名已含起始时间戳，不另造日期层）
  if (( now - $(_fleet_mtime "$f") >= retain )) \
     && (( now - $(_fleet_mtime "$f") >= FLEET_SESSION_BUSY_SEC )); then
    if rm -f -- "$f" 2>/dev/null; then
      printf 'deleted\t%s\n' "$grade"
      return 0
    fi
    warn "会话记录删除失败：$f（不影响本次清理结果）"
  fi
  printf 'kept\t%s\n' "$grade"
  return 0
}

fleet_sessions_purge() {  # [--days N] [--role R] [--repo <仓名|all>] [--quiet] → 恒 0（失败只 warn）
  local days="" role="" repo="" quiet=false f verdict deleted=0 kept=0 anomaly=0 now
  while (( $# )); do
    case "$1" in
      --days)  days="${2:-}"; shift 2 ;;
      --role)  role="${2:-}"; shift 2 ;;
      --repo)  repo="${2:-}"; shift 2 ;;
      --quiet) quiet=true; shift ;;
      *)       shift ;;
    esac
  done
  if [[ -n "$days" && ! "$days" =~ ^[0-9]+$ ]]; then
    warn "会话清理：--days 须为非负整数（得到 '$days'）⇒ 忽略，按分级保留"
    days=""
  fi
  [[ -d "$FLEET_SESSIONS_ROOT" ]] || return 0
  now="$(date +%s)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    verdict="$(_fleet_session_purge_one "$f" "$days" "$now")" \
      || { warn "会话记录清理跳过：$f（判定失败）"; continue; }
    case "${verdict%%$'\t'*}" in
      deleted) deleted=$((deleted + 1)) ;;
      *)       kept=$((kept + 1)) ;;
    esac
    [[ "${verdict##*$'\t'}" == "anomaly" ]] && anomaly=$((anomaly + 1))
  done < <(_fleet_session_files "$role" "" "$repo")
  # ensure 顺手清理时静默（真删了才说一句）；显式 logs --purge 恒给一行
  if $quiet && (( deleted == 0 )); then return 0; fi
  log "会话记录清理：删除 ${deleted} 条 · 保留 ${kept} 条（异常 ${anomaly} 条；范围 = $([[ -z "$repo" || "$repo" == "all" ]] && printf '全部仓' || printf '%s' "$repo")；策略 = 正常 24h / 异常 7 天${days:+ · 本次 --days $days}）"
  (( anomaly > 0 )) && log "  · 异常点名落 state 目录：${FLEET_SESSIONS_ROOT}/<编码 仓路径>/.retention.log（不写仓内 docs/tasks-state.md）"
  return 0
}

# ---------------------------------------------------------------------------
# 展示（turn 摘要：user 首行 + assistant 首行 + 工具名；纯 awk，无第三方依赖）
# ---------------------------------------------------------------------------
_fleet_session_turns() {  # <file> [max] → 每行 "<HH:MM>\t<user|assistant|more>\t<文本>"
  local f="${1-}" max="${2:-14}"
  [[ -f "$f" ]] || return 0
  LC_ALL=C awk -v max="$max" '
    function grab(s, from,   i, c, out) {
      out = ""
      for (i = from; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
        if (c == "\"") return out
        out = out c
      }
      return out
    }
    function unesc(s,   i, c, n, out) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c != "\\") { out = out c; continue }
        n = substr(s, i + 1, 1)
        if (n == "n") { out = out "\\n"; i++; continue }
        if (n == "t") { out = out " "; i++; continue }
        if (n == "r") { i++; continue }
        if (n == "u") { out = out "?"; i = i + 5; continue }
        out = out n; i++
      }
      return out
    }
    function firstline(t) { sub(/\\n.*/, "", t); gsub(/[\t\r]+/, " ", t); return t }
    function hhmm(s,   p) {
      p = index(s, "\"timestamp\":\"")
      if (!p) return "??:??"
      # T573 返修 D7：时间恒为 UTC（Pi 记录 ISO8601 以 Z 结尾）⇒ 后缀显式标注，避免 +8 误读
      return substr(substr(s, p + 13), 12, 5) "Z"
    }
    function toolnames(s,   out, p, q, rest) {
      out = ""
      while ((p = index(s, "\"type\":\"toolCall\"")) > 0) {
        s = substr(s, p + 17)
        q = index(s, "\"name\":\"")
        if (!q) break
        rest = substr(s, q + 8)
        out = out (out == "" ? "" : ",") substr(rest, 1, index(rest, "\"") - 1)
      }
      return out
    }
    function emit(kind, txt) {
      total++
      if (shown < max) { print tm "\t" kind "\t" txt; shown++ }
    }
    {
      line = $0
      tm = hhmm(line)
      if (index(line, "\"type\":\"message\"") > 0) {
        p = index(line, "\"role\":\"")
        role = p ? substr(line, p + 8) : ""
        q = index(role, "\""); role = q ? substr(role, 1, q - 1) : ""
        if (role == "assistant") {
          t = index(line, "\"type\":\"text\",\"text\":\"")
          txt = t ? firstline(unesc(grab(line, t + 22))) : ""
          tl = toolnames(line)
          if (txt == "" && tl == "") next
          emit("assistant", txt (tl != "" ? "  [" tl "]" : ""))
        } else if (role == "user") {
          t = index(line, "\"type\":\"text\",\"text\":\"")
          if (t) txt = firstline(unesc(grab(line, t + 22)))
          else { c2 = index(line, "\"content\":\""); txt = c2 ? firstline(unesc(grab(line, c2 + 11))) : "" }
          if (txt != "") emit("user", txt)
        }
      } else if (index(line, "\"type\":\"custom_message\"") > 0) {
        c2 = index(line, "\"content\":\"")
        txt = c2 ? firstline(unesc(grab(line, c2 + 11))) : ""
        if (txt != "") emit("user", txt)
      }
    }
    END { if (total > shown) print "--\tmore\t(另有 " (total - shown) " 条，用 --raw 看原文)" }
  ' "$f" 2>/dev/null
}

_fleet_session_size() {  # <file> → "123K"
  local k; k="$(du -k "$1" 2>/dev/null | cut -f1)"
  printf '%s\n' "${k:-0}K"
}

_fleet_logs_show() {  # <file> → 摘要（逐 turn 一行）
  local f="${1-}" t k x
  printf '  · %s  %s  %s\n' "$(basename "$(dirname "$f")")" "$(_fleet_session_size "$f")" "$(basename "$f")"
  while IFS=$'\t' read -r t k x; do
    [[ -n "${t:-}" ]] || continue
    case "$k" in
      more) printf '      %s\n' "${x:-}" ;;
      *)    printf '      %s %-9s %s\n' "$t" "$k" "${x:0:120}" ;;
    esac
  done < <(_fleet_session_turns "$f")
}

_fleet_logs_list() {  # <file> → 一行：仓 + 日期 + 角色 + 大小 + 路径
  local f="${1-}" meta name iso cwd
  meta="$(_fleet_session_meta "$f")" || return 0
  IFS=$'\t' read -r name iso cwd <<< "$meta"
  printf '  %-16s %s  %6s  %-16s %s\n' \
    "$(_fleet_repo_key "$cwd")" "${iso:0:10}" "$(_fleet_session_size "$f")" "${name:--}" "$f"
}

cmd_logs() {  # logs 子命令（纯文件系统：不建会话、不调后端、零网络）
  local role_arg="${TARGETS[0]:-}" role="" repo="" files=() f
  (( ${#TARGETS[@]} > 1 )) \
    && die "logs 只接受一个角色参数（得到 ${#TARGETS[@]} 个：${TARGETS[*]}；如 nao-fleet.sh logs rd-infra）"
  $LOGS_LIST && $LOGS_PURGE && die "logs：--list 与 --purge 不可同时使用"
  $LOGS_RAW && { $LOGS_LIST || $LOGS_PURGE; } && die "logs：--raw 只用于 turn 摘要（不可与 --list / --purge 同用）"
  if [[ -z "$role_arg" ]]; then
    $LOGS_PURGE || die "logs 需要角色参数（如 nao-fleet.sh logs rd-infra）；清理用 nao-fleet.sh logs --purge [--days N]"
  fi
  [[ -n "$role_arg" ]] && role="$(_fleet_role_id "$role_arg")"
  # 仓作用域：默认当前仓（仓基键）；`--repo all` = 全部
  repo="$LOGS_REPO"
  if [[ -z "$repo" ]]; then
    repo="$(_fleet_repo_key "$(_fleet_current_repo)")"
  fi

  if $LOGS_PURGE; then
    fleet_sessions_purge ${role:+--role "$role"} --repo "$repo" ${LOGS_DAYS:+--days "$LOGS_DAYS"}
    return 0
  fi

  mapfile -t files < <(_fleet_session_files "$role" "$TASK" "$repo")
  if (( ${#files[@]} == 0 )); then
    log "会话记录：${role} · 仓 ${repo} 无记录（目录 ${FLEET_SESSIONS_ROOT}；派生/常驻会话落此，正常 24h / 异常 7 天后清理；跨仓用 --repo all）"
    return 0
  fi
  if $LOGS_LIST; then
    log "会话记录：${role} · ${#files[@]} 条（仓 ${repo}；${FLEET_SESSIONS_ROOT}）"
    for f in "${files[@]}"; do _fleet_logs_list "$f"; done
    return 0
  fi
  if $LOGS_RAW; then
    for f in "${files[@]}"; do
      printf '=== %s\n' "$f"
      cat -- "$f"
    done
    return 0
  fi
  log "会话记录：${role} · ${#files[@]} 条（仓 ${repo}；摘要 · --raw 看原文 · --list 只列记录 · --repo all 跨仓）"
  for f in "${files[@]}"; do _fleet_logs_show "$f"; done
  return 0
}
