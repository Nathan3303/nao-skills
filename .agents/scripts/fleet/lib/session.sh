# =============================================================================
# fleet/lib/session.sh — 名册 / cwd / 身份 / 派生名 / 任务态
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core（路径谓词）；manifest（命名契约）。运行期才能调 term 门面（term_snapshot 等）
# 身份判定**不**依赖名册（BR3/BR7）：名册仅供 status -v 诊断；可见会话名取门面快照。
# =============================================================================

# ---------------------------------------------------------------------------
# 会话在线判定
#
# 身份/归属/忙闲**全部取 herdr 结构化事实**（ADR 2026-11-22-herdr-only）：
#   身份 = pane label（+ argv --name 交叉校验）· 归属 = pane.cwd / foreground_cwd ·
#   忙闲 = agent_status + state_change_seq（权威源 pane list / agent list）。
# 历史上的「终端标题契约 / tmux pane_id / 会话名」三层句柄随 tmux 后端一并删除（见 ADR）；
#   名册（intercom-probe.mts，含 tmuxPane 字段）只作 status -v 的诊断差异信号，**不参与**身份判定。
# repo（可选）：给出时要求标题 basename / 名册 cwd 一致，避免跨项目同名会话互串。

PI_AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
PI_TITLE="π"
# 含 tmuxPane 的名册探针（标题被改写时定位 pane 的权威依据）
INTERCOM_PROBE="$SKILLS_DIR/.agents/scripts/intercom-probe.mts"
_INTERCOM_JSON=""; _INTERCOM_PROBED=0

# 以 15s 超时跑 tsx（有 timeout 才用；无则裸跑）；stdout/stderr 原样透传
_node_tsx() {
  local tsx="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout 15 node "$tsx" "$@"
  else
    node "$tsx" "$@"
  fi
}

# intercom 名册 JSON（一次调用、进程内缓存）；不可用返回 1（不 die）
#   ① intercom-probe.mts（含 tmuxPane，标题被改写仍可定位 pane）
#   ② pi-intercom 官方 cli.ts list --json（无 tmuxPane，仅 name/cwd/status）
intercom_list_json() {
  if (( _INTERCOM_PROBED )); then
    [[ -n "$_INTERCOM_JSON" ]] && printf '%s' "$_INTERCOM_JSON"
    return
  fi
  _INTERCOM_PROBED=1
  local dir="$PI_AGENT_DIR/npm/node_modules/pi-intercom"
  local tsx="$PI_AGENT_DIR/npm/node_modules/tsx/dist/cli.mjs"
  [[ -f "$tsx" ]] || return 1
  command -v node >/dev/null 2>&1 || return 1
  local out=""
  if [[ -f "$INTERCOM_PROBE" ]]; then
    out="$(_node_tsx "$tsx" "$INTERCOM_PROBE" "$PI_AGENT_DIR" 2>/dev/null)" || out=""
  fi
  if [[ -z "$out" && -f "$dir/cli.ts" ]]; then
    out="$(_node_tsx "$tsx" "$dir/cli.ts" list --json 2>/dev/null)" || out=""
  fi
  [[ -n "$out" ]] || return 1
  _INTERCOM_JSON="$out"
  printf '%s' "$out"
}

# 名册 → "会话名<TAB>cwd"（每行一条）
intercom_roster() {
  local json; json="$(intercom_list_json)" || return 1
  awk '
    /"name":[[:space:]]*"/ { s=$0; sub(/.*"name":[[:space:]]*"/,"",s); sub(/".*/,"",s); n=s }
    /"cwd":[[:space:]]*"/  { s=$0; sub(/.*"cwd":[[:space:]]*"/,"",s);  sub(/".*/,"",s);  print n "\t" s }
  ' <<< "$json"
}

# 名册中是否在线；repo 给出时须 cwd 精确匹配
intercom_online() {
  local name="$1" repo="${2:-}" abs="" n c
  intercom_list_json >/dev/null 2>&1 || return 1
  if [[ -n "$repo" ]]; then abs="$(repo_abspath "$repo")"; fi
  while IFS=$'\t' read -r n c; do
    [[ "$n" == "$name" ]] || continue
    if [[ -z "$abs" || "$c" == "$abs" ]]; then return 0; fi
  done < <(intercom_roster)
  return 1
}

# 名册中该会话的 cwd（跨仓 close 需按目标仓定位；无记录则空）
# P8（BR8）：可选第 2 参 repo ⇒ 只返 `cwd == realpath(repo)` 的条目。带 scope 时同名会话可能
#   在多个仓并存（名字是路由标签而非身份证明），close 必须能按**目标仓**取句柄，禁取首命中。
intercom_cwd_for() {  # <name> [repo]
  local n c abs=""
  [[ -n "${2:-}" ]] && abs="$(_nao_phys_for_match "$2")"
  while IFS=$'\t' read -r n c; do
    [[ "$n" == "$1" ]] || continue
    [[ -z "$abs" || "$c" == "$abs" ]] || continue
    printf '%s\n' "$c"; return 0
  done < <(intercom_roster)
  return 0
}

# 名册中该会话的**全部** cwd（0..N 行；Issue #146）。
#   为什么必须复数通道：intercom_cwd_for 命中即 return，且**无命中也 rc=0 / 0 行** ⇒ 结构上分不出
#   「本仓并列」与「名册不可知」；给旧函数加 anchor 参数只能再旁路计数（双判据）。本函数只查询、不决策。
#   anchor（可选）：只留 cwd 等于或落在 anchor 子树内的条目（组件级前缀，见 repo_contains_path）；
#   路径两侧都物理归一（nao_phys_path），避免 symlink / 相对路径造成「本仓条目看不见」。
#   探针零新增：名册读 intercom_roster，复用 _INTERCOM_JSON 进程内缓存（名册探针每命令 ≤1 次）。
intercom_cwds_for() {  # <name> [anchor]
  local n c abs=""
  [[ -n "${2:-}" ]] && abs="$(nao_phys_path "$2")"
  while IFS=$'\t' read -r n c; do
    [[ "$n" == "$1" ]] || continue
    [[ -n "$c" ]] || continue
    [[ -z "$abs" ]] || repo_contains_path "$abs" "$(nao_phys_path "$c")" || continue
    printf '%s\n' "$c"
  done < <(intercom_roster)
  return 0
}

# 名册里记录的 pane 句柄（herdr 起 server 前会清宿主句柄；此处仅作 -v 诊断差异信号）：
#   ① 终端标题契约 "π - <会话名> - <repo basename>"（pi 自设；最快）
#   ② pi-intercom 名册 tmuxPane（注册时读 $TMUX_PANE；与标题改名无关，权威）
#   ③ 本仓「未被认领 pi pane」唯一兜底（启发式：pane_current_command=pi 且
#      pane_current_path=repo；歧义时 warn，不猜）
# repo（可选）：给出时要求标题 basename / 名册 cwd / pane 当前路径一致，避免跨项目同名互串。


# 名册中该会话的 tmux pane（注册时读 $TMUX_PANE；标题被改写仍有效）
intercom_pane_for() {
  local name="$1" repo="${2:-}" abs="" json
  json="$(intercom_list_json 2>/dev/null)" || return 0
  [[ -n "$json" ]] || return 0
  if [[ -n "$repo" ]]; then abs="$(repo_abspath "$repo")"; fi
  awk -v n="$name" -v a="$abs" '
    /"name":[[:space:]]*"/ { s=$0; sub(/.*"name":[[:space:]]*"/,"",s); sub(/".*/,"",s); cn=s }
    /"cwd":[[:space:]]*"/  { s=$0; sub(/.*"cwd":[[:space:]]*"/,"",s);  sub(/".*/,"",s);  cc=s }
    /"tmuxPane":[[:space:]]*"/ {
      s=$0; sub(/.*"tmuxPane":[[:space:]]*"/,"",s); sub(/".*/,"",s); cp=s
      if (cn == n && (a == "" || cc == a) && cp != "") { print cp; exit }
    }
  ' <<< "$json"
}

# 名册中该会话的活动状态（无记录则空）；pi-intercom 状态值如 idle / thinking / tool:bash
# 标题被改写或 pane 不可判时，这是「在跑 turn」的权威信号。
intercom_status_for() {
  local name="$1" repo="${2:-}" abs="" json
  json="$(intercom_list_json 2>/dev/null)" || return 0
  [[ -n "$json" ]] || return 0
  if [[ -n "$repo" ]]; then abs="$(repo_abspath "$repo")"; fi
  awk -v n="$name" -v a="$abs" '
    /"name":[[:space:]]*"/   { s=$0; sub(/.*"name":[[:space:]]*"/,"",s);   sub(/".*/,"",s); cn=s; cs="" }
    /"status":[[:space:]]*"/ { s=$0; sub(/.*"status":[[:space:]]*"/,"",s); sub(/".*/,"",s); cs=s }
    /"cwd":[[:space:]]*"/ {
      s=$0; sub(/.*"cwd":[[:space:]]*"/,"",s); sub(/".*/,"",s); cc=s
      if (cn == n && (a == "" || cc == a)) { print cs; exit }
    }
  ' <<< "$json"
}

# 本仓所有「当前前台命令为 pi」的 pane：pane_id<TAB>pane_current_path
# pane_current_command 与标题/argv 无关，是标题被改写时的可靠进程特征。

# ---- ④ 路径句柄（app-id/class）已随宿主阶梯删除（ADR 2026-10-27-strict-tmux-pi）---------

# 派生会话在场检测（T516 AC3）：visible_session_names 中 core（= role[-task]，**不含 scope**）以
#   `<core>-` 开头且带非空后缀者。用于 close <常驻名> 时判目标歧义：常驻精确句柄缺席而其派生在场
#   ⇒ 拒绝 + 指路（禁静默谎报「未运行」）。
# P5（BR8）：候选**必须**先经 fleet_name_parse 比 **core**，并要求 scope 与目标一致 ——
#   旧写法 `[[ "$n" == "$1"-?* ]]` 会把**他仓/他 scope 的派生**算成本仓派生（T516 AC3 误拒复发）。
derived_in_field() {  # <role> [want_scope] → 同角色的派生命名（v3 元数据 + v2/旧形；空 = 无）
  local role="${1-}" want_scope="${2-}" n out k r t s sc te
  [[ -n "$role" ]] || return 0
  fleet_task_map_init
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    case "$out" in
      "OK "*)
        IFS=',' read -r k r t s <<< "${out#OK }"
        sc=""                                       # v3/v2 无 scope
        ;;
      "LEGACY OK "*)
        IFS=',' read -r k r t sc <<< "${out#LEGACY OK }"
        ;;
      *) continue ;;
    esac
    te="$(fleet_effective_task "$n")"
    [[ -n "$te" ]] || continue                     # 无任务 ⇒ 不是派生
    [[ "$r" == "$role" ]] || continue
    [[ "$sc" == "$want_scope" ]] || continue       # 旧形按 scope 过滤（裸名 ≠ 带 scope 全名）
    printf '%s\n' "$n"
  done < <(visible_session_names)
}

# 同 core 且带 scope 的**旧形**会话（close 裸名时用于 legacy 回落；每行一个）。
#   T554：旧形只读；v2 不再产生带 scope 的名字（`@` 段已删除）。
fleet_scoped_candidates() {  # <role> [<task>] → 名字（每行一个；空 = 无）
  local role="${1-}" want_task="${2-}" n out k r t s
  [[ -n "$role" ]] || return 0
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    [[ "$out" == "LEGACY OK "* ]] || continue
    IFS=',' read -r k r t s <<< "${out#LEGACY OK }"
    [[ -n "$s" ]] || continue                      # 无 scope ⇒ 不是本函数的候选
    [[ "$r" == "$role" && "$t" == "$want_task" ]] || continue
    printf '%s\n' "$n"
  done < <(visible_session_names)
}

# 同 (role,task) 的在场会话（**不限定槽位/scope**；close 裸名第 4 档用）。
fleet_same_core_candidates() {  # <role> [<task>] → 名字（每行一个；空 = 无）
  local role="${1-}" want_task="${2-}" n out k r t s
  [[ -n "$role" ]] || return 0
  fleet_task_map_init
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    case "$out" in
      "OK "*|"LEGACY OK "*) ;;
      *) continue ;;
    esac
    IFS=',' read -r k r t s <<< "${out#*OK }"
    [[ "$r" == "$role" ]] || continue
    [[ "$(fleet_effective_task "$n")" == "$want_task" ]] || continue
    printf '%s\n' "$n"
  done < <(visible_session_names)
}

# 子代理（pi-subagents）不属舰队会话身份模型 —— status 只计数不列名；生命周期归 pi-subagents，nao 不回收。
# BR6 前缀精确：`subagent-*` 不匹配 `subagentfoo` / 裸 `subagent` / `mysubagent-x`。
subagent_in_field() {  # → echo 子代理会话数（0..N）
  local n c=0
  while IFS= read -r n; do
    [[ "$n" == subagent-* ]] && c=$((c + 1))
  done < <(visible_session_names)
  printf '%s\n' "$c"
}

running() {
  # 门面包装：证据链 = herdr 结构化事实（label + argv + agent_status）
  #   **布尔探针静默**：告警由「专用证据面」（cmd_status 的 hv 预计算）负责，这里只取 verdict，
  #   否则同一个名字会被问两次、告警刷两条（app 臂的「集成缺 labels」实测如此）。
  [[ "$(term_liveness "${1-}" "${2-}" 2>/dev/null | cut -f1)" == "online" ]]
}

# P11（BR8）：`ensure` 判重**三态**（旧二态无法区分「同名不同 scope/仓」⇒ 静默起出第二个会话）
#   same     = 同名同仓同 scope 已在运行 ⇒ 跳过（文案与旧行为逐字一致）
#   conflict = 同 core 但 scope 或仓不同 ⇒ **die + 指路**（列候选），禁静默拉起
#   absent   = 拉起
#   repo 未知（pane/名册均无 cwd）时不得凭空判冲突 ⇒ 落 absent（与旧行为一致，不新增误拒）。
running_verdict() {  # <name> [repo] → same | unknown | absent
  local name="$1" repo="${2:-}" v
  # T554：跨 workspace 同名合法 ⇒ **不再有 conflict 态**（判重域 = 目标 workspace；槽位由 ensure 相位 1 算定）。
  # T563/AC2：`unknown`（集成缺 labels ⇒ 无法确认放置归属）**不得**落 absent —— 落 absent 会静默起第二个终端
  #   并与既有终端同名多命中（close 随即因同名拒）。判重必须 fail-closed，由 ensure 拒绝并给一行指路。
  v="$(term_liveness "$name" "$repo" 2>/dev/null | cut -f1)"
  case "$v" in
    online) printf 'same\n' ;;
    unknown) printf 'unknown\n' ;;
    *) printf 'absent\n' ;;
  esac
}

# ---- 共享投影（无后端调用）：会话名从门面快照取（label 即会话名；名册不参与身份判定 —— BR3/BR7）----
visible_session_names() {
  term_snapshot | awk -F'\t' 'NF && $1 != "" {print $1}' | awk '!seen[$0]++'
}

# 元数据 task 索引（v3 · ADR 2026-11-25）：快照第 13 列 = 后端元数据（app `nao.task` / herdr sidecar）。
#   只存**元数据**；v2/legacy 名字里的 task 由 fleet_effective_task 回落解析（不在快照里反解角色，
#   因为快照可能在 roles 表灌入前建成）。每命令一次；调用点：status / close / ensure（roles 初始化之后）。
declare -A FLEET_TASK_BY_NAME=()
fleet_task_map_init() {  # → 0（后端不可用 ⇒ 空表，不报错）
  local n t line
  FLEET_TASK_BY_NAME=()
  while IFS=$'\t' read -r n _ _ _ _ _ _ _ _ _ _ _ t; do
    [[ -n "$n" ]] || continue
    [[ -n "$t" && "$t" != "-" ]] && FLEET_TASK_BY_NAME["$n"]="$t"
  done < <(term_snapshot 2>/dev/null || true)
  return 0
}

# 有效 task：元数据优先，其次只读旧形/ v2 名字里的 task（槽位号永不承载语义）。
fleet_effective_task() {  # <name> → task（无 ⇒ 空）
  local nm="${1-}" out k r t s
  [[ -n "$nm" ]] || return 0
  if [[ -n "${FLEET_TASK_BY_NAME[$nm]:-}" ]]; then printf '%s\n' "${FLEET_TASK_BY_NAME[$nm]}"; return 0; fi
  out="$(fleet_name_parse "$nm")"
  case "$out" in
    "OK "*)        IFS=',' read -r k r t s <<< "${out#OK }" ;;
    "LEGACY OK "*) IFS=',' read -r k r t s <<< "${out#LEGACY OK }" ;;
    *) return 0 ;;
  esac
  [[ -n "$t" ]] && printf '%s\n' "$t"
  return 0
}

# 任务在 tasks-state 的归处：
#   active（在表内进行态）/ closed（在归档区表内）/ mentioned（仅散文提及）
#   / absent（全文无记录）/ nofile
# 归一处：表内单元格可选带反引号/**（常见写法 `T157` / **T157**）→ 去首尾空白与标记后比较。
# 标题级别不限（`##` 与 `###` 子表都算）；归档区 = 标题含「已验收|已归档|归档」。
# 边界：先按非 [A-Za-z0-9_-] 切词再比较，避免 T15 命中 T155。
task_state_class() {
  local id="$1"
  [[ -f "$TASKS_STATE" ]] || { echo nofile; return; }
  awk -v id="$id" '
    function norm(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); gsub(/`/, "", s); gsub(/\*\*/, "", s); return s }
    /^#+[[:space:]]/ { sec=$0; sub(/^#+[[:space:]]*/, "", sec); next }
    {
      n=split($0, cells, "|")
      for (i=1;i<=n;i++) {
        if (norm(cells[i]) != id) continue
        if (sec ~ /已验收|已归档|归档/) arch=1; else cell=1
        break
      }
      line=$0; gsub(/[^A-Za-z0-9_-]/, " ", line)
      m=split(line, toks, " ")
      for (j=1;j<=m;j++) if (toks[j]==id) { seen=1; break }
    }
    END {
      if (arch) { print "closed"; exit }
      if (cell) { print "active"; exit }
      if (seen) { print "mentioned"; exit }
      print "absent"
    }
  ' "$TASKS_STATE"
}

# 共享投影（无后端调用）：从门面快照取 name/pane/cwd（列 1/2/4）；**禁**逐名查询（O(N) 次后端调用）
pane_cwd_snapshot() {
  term_snapshot | awk -F'\t' '$1 != "" && $2 != "" {print $1 "\t" $2 "\t" $4}'
}

# 归属三态：local（本仓）/ other（他仓）/ unknown（不可判定 ⇒ fail-closed，只标注不给命令）
#   $1=本仓锚集（换行分隔）· $2=pane cwd 集（换行分隔；空 = 无 pane）· $3=名册 cwd（可空）
#   优先级 pane > 名册；同名多 pane：本仓 ≥1 ⇒ local · 本仓 0 且他仓 ≥1 ⇒ other · 两侧皆无 ⇒ unknown
#   输出：`<verdict><TAB><他仓仓名 basename>`
session_repo_verdict() {
  local roots="$1" cwds="$2" rcwd="$3"
  local c r hit local_n=0 other_n=0 obase="" verdict=""
  if [[ -n "$cwds" ]]; then
    while IFS= read -r c; do
      [[ -n "$c" ]] || continue
      c="$(nao_phys_path "$c")"
      hit=0
      while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        if repo_contains_path "$r" "$c"; then hit=1; break; fi
      done <<< "$roots"
      if (( hit )); then
        local_n=$((local_n + 1))
      else
        other_n=$((other_n + 1))
        if [[ -z "$obase" ]]; then obase="${c%/}"; obase="${obase##*/}"; fi
      fi
    done <<< "$cwds"
    if (( local_n > 0 )); then verdict=local
    elif (( other_n > 0 )); then verdict=other
    fi
  fi
  if [[ -z "$verdict" && -n "$rcwd" ]]; then
    c="$(nao_phys_path "$rcwd")"
    hit=0
    while IFS= read -r r; do
      [[ -n "$r" ]] || continue
      if repo_contains_path "$r" "$c"; then hit=1; break; fi
    done <<< "$roots"
    if (( hit )); then
      verdict=local
    else
      verdict=other
      obase="${c%/}"; obase="${obase##*/}"
    fi
  fi
  [[ -n "$verdict" ]] || verdict=unknown
  printf '%s\t%s\n' "$verdict" "$obase"
}
