# =============================================================================
# fleet/lib/status.sh — status 子命令（判定面）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term/manifest/session
# 渲染层：线上/非在线证据全部来自门面快照与名册，不在此发明判定。
# =============================================================================

# ---------------------------------------------------------------------------
# status 的 scope 展示面（M5 · #139）：manifest 可读 ⇒ `fleet=<slug>` + `code=<code>` 两字段；
#   非法/不可读 ⇒ `fleet=?`（显式不可知，禁空值）。无 manifest ⇒ 逐字旧形态（AC2 结构性保持）。
STATUS_MN_OK=0; STATUS_MN_ROOT=""; STATUS_MN_CODES=""
STATUS_SNAP=""; declare -A STATUS_MN_PATHS=() STATUS_WS_LABEL=()
#   T554：manifest 只留「code → path」；legacy scope 的展示面 = `·code=<code> ·path=<path>`。
#   ⚠️ 返回值**不带前导空格**（常驻行紧贴、派发行前置一个空格 —— 两条成对调用各自补）。
_status_scope_tag() {  # <legacy scope> → "·code=…[ ·path=…]"
  local s="${1-}"
  (( STATUS_MN_OK == 2 )) && { printf '·code=?'; return 0; }
  if (( STATUS_MN_OK == 1 )); then
    if [[ "$s" == "main" ]]; then printf '·code=main ·path=%s' "$STATUS_MN_ROOT"; return 0; fi
    case " $STATUS_MN_CODES " in
      *" $s "*) printf '·code=%s ·path=%s' "$s" "${STATUS_MN_PATHS[$s]:-?}"; return 0 ;;
    esac
  fi
  printf '·code=%s' "$s"
}

# S13（T554）：本仓同名会话行末尾的「他仓同名 N 个」附加字段。
#   数据源 = 5 列中性快照（name/status/cwd/handle/task）；Step 2 起业务层不再拿 workspace_id。
#   own 判据 = 该行 cwd 落在目标仓内（与 term_liveness 的 repo 过滤同源）。
_status_other_same() {  # <name> <repo_phys>
  local name="${1-}" repo="${2-}" _n _st c _h _task n=0
  [[ -n "$name" && -n "${STATUS_SNAP:-}" ]] || return 0
  while IFS=$'\t' read -r _n _st c _h _task; do
    [[ "$_n" == "$name" ]] || continue
    if [[ -n "$repo" && -n "$c" && "$c" != "-" ]] && repo_contains_path "$repo" "$(_fleet_phys "$c")"; then
      continue
    fi
    n=$((n + 1))
  done <<< "$STATUS_SNAP"
  (( n > 0 )) || return 0
  printf ' · 他仓同名 %d 个' "$n"
}

cmd_status() {
  local a
  # BR8：parse 的角色事实表必须先灌入（身份还原的 argv 回退要用 fleet_name_parse 验名）
  fleet_roles_init --cards
  # B1（BR3/BR7）：身份/归属/忙闲全部来自结构化事实 ⇒ 快照**每命令一次**
  #   （≤1 次 pane list / agent list；逐名查询会 7×2 次 CLI，且同命令内两份快照不一致 = 新 flake 源）
  if ! term_snapshot >/dev/null; then
    if [[ "$(term_label)" == "app" ]]; then
      printf '需要 desktop app core：hc ls / hc get 不可用（核对 desktop app 是否在运行、HC_TERMINAL_SOCKET 是否有效）—— 修好后重试\n' >&2
    else
      printf '需要 herdr server：pane list / agent list 不可用（核对 `herdr --session %s server` 是否在跑、protocol 是否 22）—— 修好后重试\n' "${HERDR_SESSION:-?}" >&2
    fi
    exit 3
  fi
  # v3 元数据：task 映射 + 当前会话 sidecar 孤儿清理（快照已建好，零新增后端调用）
  fleet_task_map_init
  if [[ "$(term_label)" != "app" ]]; then
    term_snapshot 2>/dev/null | awk -F'\t' 'NF{print $4}' | fleet_meta_gc
  fi
  # M5（#139）：manifest 读面（只在 manifest 可读时追加字段；无 manifest / 不可读不动既有行格式）
  #   可读 ⇒ `fleet=<slug>` + `code=<code>`；非法/不可读 ⇒ `fleet=?`（显式不可知，禁空值）。
  STATUS_MN_OK=0; STATUS_MN_ROOT=""; STATUS_MN_CODES=""; STATUS_MN_PATHS=()
  local st_root="" st_mn="" _snk="" _sncode="" _snpath=""
  st_root="$(fleet_manifest_root "$PWD")"
  st_mn="$(fleet_manifest_load "$st_root" 2>/dev/null)" || true
  fleet_manifest_warn_deprecated "$st_mn"
  if [[ -n "$st_mn" ]]; then
    if [[ -n "$st_mn" && "$st_mn" != "NONE" ]]; then
      STATUS_MN_OK=1
      while IFS=$'\t' read -r _snk _sncode _snpath; do
        case "$_snk" in
          ROOT) STATUS_MN_ROOT="$_sncode" ;;
          REPO) STATUS_MN_PATHS["$_sncode"]="$_snpath"; STATUS_MN_CODES+="${STATUS_MN_CODES:+ }$_sncode" ;;
        esac
      done <<< "$st_mn"
    fi
  else
    STATUS_MN_OK=2
  fi
  # S13：5 列中性快照 + workspace label 表（≤1 次 workspace list；快照已由入口建好）
  STATUS_SNAP=""; STATUS_WS_LABEL=()
  STATUS_SNAP="$(term_snapshot 2>/dev/null || true)"
  local _wid _wlabel
  while IFS=$'\t' read -r _wid _wlabel; do
    [[ -n "${_wid:-}" ]] || continue
    STATUS_WS_LABEL["$_wid"]="$_wlabel"
  done < <(term_ws_label_rows 2>/dev/null || true)
  # 一次枚举会话名（label 去重）：下面两轮共用，避免多一轮后端/node 调用
  local -a field_names=()
  local dname pout p_kind p_role p_task p_scope p_num
  mapfile -t field_names < <(visible_session_names)
  # T554：常驻槽位（v2 `<role><N>`）与 legacy 带 scope 常驻（旧形只读）都要单列 —— 否则整条消失。
  local -A scoped_resident=() resident_v2=()
  local any_scoped=0
  for dname in "${field_names[@]}"; do
    pout="$(fleet_name_parse "$dname")"
    case "$pout" in
      "OK "*)
        IFS=',' read -r p_kind p_role p_task p_num <<< "${pout#OK }"
        p_scope=""
        ;;
      "LEGACY OK "*)
        IFS=',' read -r p_kind p_role p_task p_scope <<< "${pout#LEGACY OK }"
        p_num=""
        ;;
      *) continue ;;
    esac
    # v3：task 只在元数据里 ⇒ 名字解析为 resident 但有 task ⇒ 实为派生会话
    if [[ "$p_kind" == "resident" && -n "${FLEET_TASK_BY_NAME[$dname]:-}" ]]; then
      p_kind="derived"; p_task="${FLEET_TASK_BY_NAME[$dname]}"
    fi
    if [[ "$pout" == "LEGACY OK "* ]]; then
      [[ -n "$p_scope" ]] && any_scoped=1
      [[ "$p_kind" == "resident" && -n "$p_scope" ]] || continue
      # 存**旧形全名**（v2 无 scope 构造通道；旧形只读、直接显示在场名）
      case " ${scoped_resident[$p_role]:-} " in
        *" $dname "*) ;;
        *) scoped_resident["$p_role"]="${scoped_resident[$p_role]:-}$dname " ;;
      esac
    elif [[ "$p_kind" == "resident" ]]; then
      [[ -n "$p_num" ]] || continue                  # 裸名 `<role>` 由上方 running 覆盖
      resident_v2["$p_role"]="${resident_v2[$p_role]:-}$dname "
    fi
  done
  # ---- B1（herdr）：逐名在线证据一次算定（只读快照，零后端调用）----
  #   单列缺陷类（幽灵 pane / 集成缺失 / 前台非 pi / 身份不一致）不得静默退化成 unknown；
  #   `label` 命中 ≠ same/在线（BR1/AC2.1）。
  local -A hv=() hstate=() hseq=() hhook=() abn_seen=()
  local -a term_abn=()
  local vline nm vd vstate vseq vhook
  for nm in "${ROLE_ORDER[@]}" "${field_names[@]}"; do
    [[ -n "$nm" ]] || continue
    [[ -n "${hv[$nm]:-}" ]] && continue
    if [[ -n "${ROLE_CARDS[$nm]:-}" ]]; then
      vline="$(term_liveness "$nm" "${ROLE_WS[$nm]:-}")"
    else
      vline="$(term_liveness "$nm")"
    fi
    IFS=$'\t' read -r vd vstate vseq vhook <<< "$vline"
    hv["$nm"]="${vd:-absent}"; hstate["$nm"]="${vstate:--}"; hseq["$nm"]="${vseq:--}"; hhook["$nm"]="${vhook:--}"
  done
  for nm in "${ROLE_ORDER[@]}" "${field_names[@]}"; do
    [[ -n "$nm" ]] || continue
    [[ -n "${abn_seen[$nm]:-}" ]] && continue
    abn_seen["$nm"]=1
    case "${hv[$nm]:-absent}" in
      ghost)
        if [[ "$(term_label)" == "app" ]]; then
          term_abn+=("  ! $nm 终端残留：name 在、status 缺（finished 换壳）⇒ 非在线（勿当「已在运行」，回收归 B3）")
        else
          term_abn+=("  ! $nm 幽灵 pane：label 在、agent 条目缺（label 命中 ≠ 在线；勿当「已在运行」，回收归 B3）")
        fi ;;
      dead)
        term_abn+=("  ! $nm 前台非 pi（状态 ${hstate[$nm]}）→ 非在线（可能刚退出/重启回放）") ;;
      mismatch)
        term_abn+=("  ! $nm 身份不一致：label 与 argv --name 不符 → 非在线（禁猜）") ;;
      integration-missing)
        term_abn+=("  ! $nm 集成缺失：agent_session 空或生命周期钩子权威缺（状态 ${hstate[$nm]}）→ **不可投递**；请核对 pi-intercom/herdr 集成；若 pi 首次启动停在 What's New / 信任提示，先手工关闭再重试") ;;
      ambiguous)
        term_abn+=("  ! $nm 同名 label 多 pane：命中多个 ⇒ 不猜（既不判在线，也不静默挑一个）；先人工核对/清理重复 label（回收面归 B3）") ;;
    esac
  done
  
  if [[ "$(term_label)" == "app" ]]; then
    echo "== 角色会话在线状态（本表按 app 终端 name + status.state 判定；权威源 = hc ls / hc get）=="
  else
    echo "== 角色会话在线状态（本表按 herdr pane label + agent 状态判定；权威源 = pane list / agent list）=="
  fi
  local a_ok a_sc a_nm
  local a_extra=""
  for a in "${ROLE_ORDER[@]}"; do
    a_ok=0
    if running "$a" "${ROLE_WS[$a]:-}"; then
      a_extra="$(_status_other_same "$a" "$(nao_phys_path "${ROLE_WS[$a]:-}")")"
      printf '  ✓ %-14s 在线（--name %s；卡片 %s）%s\n' "$a" "$a" "${ROLE_CARDS[$a]}" "$a_extra"
      a_ok=1
    fi
    # T554：常驻槽位（`pm2`/`pm3`…）—— 与裸名同样单列（不静默消失）
    local a_slot
    for a_slot in ${resident_v2[$a]:-}; do
      [[ -n "$a_slot" ]] || continue
      if [[ "${hv[$a_slot]:-absent}" != "online" ]]; then continue; fi
      a_extra="$(_status_other_same "$a_slot" "$(nao_phys_path "${ROLE_WS[$a]:-}")")"
      printf '  ✓ %-14s 在线（--name %s；卡片 %s）%s\n' "$a" "$a_slot" "${ROLE_CARDS[$a]}" "$a_extra"
      a_ok=1
    done
    # P3-2（同族静默漏行）：裸名与带 scope **同场时两条都要显示** —— 旧写法用 elif 只留裸名，
    #   带 scope 那条就整条消失（P1 只覆盖「仅带 scope」）。scope 空 ⇒ 本段零输出（BR1 逐字不变）。
    # P3-3①：显示行里的名字走 builder（§0⑤「builder 之外禁名字拼接」）。
    if [[ -n "${scoped_resident[$a]:-}" ]]; then
      for a_nm in ${scoped_resident[$a]}; do
        a_sc=""
        pout="$(fleet_name_parse "$a_nm")"
        case "$pout" in "LEGACY OK "*) IFS=',' read -r _ _ _ a_sc <<< "${pout#LEGACY OK }" ;; esac
        # P1（QA 第二轮 · AC2.1 语义破口）：带 scope 的名字来自 pane.label —— **不是证据**，
        #   必须过门面在线判定；否则 ghost / dead / mismatch / integration-missing 会被打成「✓ 在线」，
        #   与紧随其后的「终端证据异常」节自相矛盾。非在线交给那一节单列。
        if [[ "${hv[$a_nm]:-absent}" != "online" ]]; then continue; fi
        printf '  ✓ %-14s 在线（--name %s；卡片 %s）%s\n' \
          "$a" "$a_nm" "${ROLE_CARDS[$a]}" "$(_status_scope_tag "$a_sc")"
        a_ok=1
      done
    fi
    # T597（Issue #281 · 红线族「读不到不得当成不存在」）：同名终端在场但**缺身份标签** ⇒ 归属不可判定，
    #   显示 `?` + 一行处置；**不得**报「未运行」（实际在跑）。label 齐的正常路径零变化（BR1）。
    if (( ! a_ok )) && [[ "${hv[$a]:-absent}" == "unknown" ]]; then
      printf '  ? %-14s 不可判定（同名终端在场但缺身份标签 space/tab/name ⇒ 归属无法确认）\n' "$a"
      printf '  %-16s 处置：`hc get <地址>` 看实况 / `hc label <地址>` 补标签 / `hc kill <地址>` 清掉（或 close --force）\n' "" 
    elif (( ! a_ok )); then
      printf '  · %-14s 未运行（ensure 拉起）\n' "$a"
    fi
  done
  # D5：分节标题示例带上全名写法 —— **仅当在场确有带 scope 的会话**（scope 为空时逐字保留旧标题 ⇒ BR1）
  if (( any_scoped )); then
    echo "== 任务派生会话（--task 拉起，如 rd-be / rd-be2；task 仅在尾注；含旧式 @ 名）=="
  else
    echo "== 任务派生会话（--task 拉起，如 rd-fe / rd-infra；task 仅在尾注）=="
  fi
  # T534：先建归属快照（本仓锚 / pane cwd / 名册 cwd），再逐会话**先定归属、后判本仓台账**
  #   （他仓不查本仓 tasks-state，杜绝误读；本仓行 cls tag 逐字不变）
  local roots_blob="" rl
  while IFS= read -r rl; do [[ -n "$rl" ]] && roots_blob+="$rl"$'\n'; done < <(repo_anchor_roots)
  local -A pane_cwds=() roster_cwds=()
  local pn pname pcwd rn rcwd prev
  # M20261101：pane_cwd_snapshot 字段序 = `会话名<TAB>pane_id<TAB>cwd` ⇒ 必须按**会话名**建键
  #   （与下面 pane_cwds["$dname"] 的查询口径一致）。此前误读成 `pane_id<TAB>…`，键成了 pane_id
  #   ⇒ 查询恒空、「pane cwd 优先」层从未生效。同名多 pane（分屏）仍拼接多行后再判定（BR5）。
  while IFS=$'\t' read -r pname pn pcwd; do
    [[ -n "$pname" ]] || continue
    prev="${pane_cwds[$pname]:-}"
    pane_cwds["$pname"]="$prev$pcwd"$'\n'
  done < <(pane_cwd_snapshot)
  # 归属**只用结构化事实**（pane cwd）；名册 cwd 不参与（否则名册陈旧/双源矛盾会把旧病带回来 —— arch 1b-3）

  local found=0 role id cls tag verdict obase scope_tag
  local -a unrecognized=()
  for dname in "${field_names[@]}"; do
    [[ -n "$dname" ]] || continue
    # ---- P1 常驻↔派生切分：一律经 fleet_name_parse；**禁**前缀切片 ----
    p_kind=""; p_role=""; p_task=""; p_scope=""; p_num=""
    pout="$(fleet_name_parse "$dname")"
    case "$pout" in
      "OK "*)        IFS=',' read -r p_kind p_role p_task p_num <<< "${pout#OK }" ;;
      "LEGACY OK "*) IFS=',' read -r p_kind p_role p_task p_scope <<< "${pout#LEGACY OK }" ;;
    esac
    p_task="$(fleet_effective_task "$dname")"
    [[ -n "$p_task" && "$p_kind" == "resident" ]] && p_kind="derived"
    scope_tag=""
    [[ -n "$p_scope" ]] && scope_tag=" $(_status_scope_tag "$p_scope")"   # 只追加字段，既有行格式不动（BR1）
    # 非在线证据类**单列**（下方「终端证据异常」节），此处不重复渲染成残留/进行态
    case "${hv[$dname]:-absent}" in
      ghost|dead|mismatch|integration-missing|ambiguous) continue ;;
    esac
    case "$p_kind" in
      resident)
        # 常驻会话本身已在上方 ROLE_ORDER 轮打印（含带 scope 的变体）⇒ 本区静默跳过（逐字不变）
        continue
        ;;
      derived)
        # ---- P2 后缀/角色一律取 parse 结果（禁再对 $dname 做前缀比较）----
        role="$p_role"; id="$p_task"
        IFS=$'\t' read -r verdict obase <<< "$(session_repo_verdict "$roots_blob" "${pane_cwds[$dname]:-}" "${roster_cwds[$dname]:-}")"
        case "$verdict" in
          # D5：他仓会话**列出并标注**（不静默隐藏），整行不含任何可执行 close 命令（BR2）
          other)   printf '  ~ %s（他仓 @ %s）他仓会话，勿在本仓回收%s\n' "$dname" "${obase:-?}" "$scope_tag"; found=1; continue ;;
          # fail-closed（T530 对偶）：不可判定时不得声称「是本仓残留」，只标注不给命令
          unknown) printf '  ? %s（归属不可判定）→ 人工核对（勿在本仓回收）%s\n' "$dname" "$scope_tag"; found=1; continue ;;
        esac
        # ---- P3 分类输入取 parse 的 task；回收命令的角色名取 parse 的 role ----
        #   （旧 `${dname%-"$id"}` 尾剥法在带 scope 时剥错 ⇒ 命令指向不存在的名字）
        cls="$(task_state_class "$id")"
        tag=""
        case "$cls" in
          closed)    tag="  ! 残留（$id 已归档）→ close --task $id $role" ;;
          active)    tag="  · $id 进行态" ;;
          mentioned) tag="  ? $id 仅散文提及（非表内记录）→ 核对后 close --task $id $role" ;;
          absent)    tag="  ! 残留（tasks-state 无 $id 记录）→ 核对后 close --task $id $role" ;;
        esac
        printf '  · %s%s%s task=%s\n' "$dname" "$tag" "$scope_tag" "${p_task:--}"
        found=1
        ;;
      card)
        # ---- P2 卡集：最长前缀已由 parse 判定（禁再遍历 card_path 比较前缀）----
        role="$p_role"
        IFS=$'\t' read -r verdict obase <<< "$(session_repo_verdict "$roots_blob" "${pane_cwds[$dname]:-}" "${roster_cwds[$dname]:-}")"
        case "$verdict" in
          # F2：他仓卡会话只标注（不读他仓 .agents/prompts）
          other)   printf '  ~ %s（他仓 @ %s）他仓会话，勿在本仓回收%s\n' "$dname" "${obase:-?}" "$scope_tag"; found=1; continue ;;
          unknown) printf '  ? %s（归属不可判定）→ 人工核对（勿在本仓回收）%s\n' "$dname" "$scope_tag"; found=1; continue ;;
        esac
        if [[ -z "$p_task" ]]; then
          printf '  · %s（一次性会话 · 下游卡 %s）→ close %s%s\n' "$dname" "$role" "$dname" "$scope_tag"
          found=1; continue
        fi
        # F4：后缀非任务编号形状 ⇒ 列名但不给 tag/命令（此收紧只对新（卡）前缀生效）
        if [[ ! "$p_task" =~ ^(T[0-9]+|M[0-9]{8}(-.*)?)$ ]]; then
          printf '  · %s（一次性会话 · 下游卡 %s）后缀非任务编号 → 不提供回收命令（核对后人工处理）%s\n' \
            "$dname" "$role" "$scope_tag"
          found=1; continue
        fi
        cls="$(task_state_class "$p_task")"
        tag=""
        case "$cls" in
          closed)    tag="  ! 残留（$p_task 已归档）→ close --task $p_task $role" ;;
          active)    tag="  · $p_task 进行态" ;;
          mentioned) tag="  ? $p_task 仅散文提及（非表内记录）→ 核对后 close --task $p_task $role" ;;
          absent)    tag="  ! 残留（tasks-state 无 $p_task 记录）→ 核对后 close --task $p_task $role" ;;
        esac
        if [[ -n "$p_task" ]]; then
          printf '  · %s（一次性会话 · 下游卡 %s）%s%s task=%s\n' "$dname" "$role" "$tag" "$scope_tag" "$p_task"
        else
          printf '  · %s（一次性会话 · 下游卡 %s）%s%s\n' "$dname" "$role" "$tag" "$scope_tag"
        fi
        found=1
        ;;
      *)
        # ---- parse 不识别（ERR）：T525 子代理单列计数；F3「角色未识别」不得静默 ----
        [[ "$dname" == subagent-* ]] && continue
        if [[ "$dname" =~ (^|-)T[0-9]+$ || "$dname" =~ (^|-)M[0-9]{8}(-|$) ]]; then
          IFS=$'\t' read -r verdict obase <<< "$(session_repo_verdict "$roots_blob" "${pane_cwds[$dname]:-}" "${roster_cwds[$dname]:-}")"
          case "$verdict" in
            other)   unrecognized+=("  ? $dname（他仓 @ ${obase:-?}）角色未识别（疑似 fleet 遗留）：卡被删除/改名、卡在他仓、或 overlay 改名？核对后人工处理（本行不给回收命令）") ;;
            unknown) unrecognized+=("  ? $dname（归属不可判定）角色未识别（疑似 fleet 遗留）：卡被删除/改名、卡在他仓、或 overlay 改名？核对后人工处理（本行不给回收命令）") ;;
            *)       unrecognized+=("  ? $dname（本仓）角色未识别（疑似 fleet 遗留）：卡被删除/改名、卡在他仓、或 overlay 改名？核对后人工处理（本行不给回收命令）") ;;
          esac
        fi
        continue
        ;;
    esac
  done
  (( found )) || echo '  （无）'
  [[ -f "$TASKS_STATE" ]] || echo "  （$TASKS_STATE 不存在，残留判定已跳过）"
  # B1（herdr）：终端证据异常节 —— 单列、点名、给结论（非在线 / 不可投递），不得静默退化成 unknown
  if (( ${#term_abn[@]} > 0 )); then
    if [[ "$(term_label)" == "app" ]]; then
      echo '== 终端证据异常（app 后端：name 命中 ≠ 在线）=='
    else
      echo '== 终端证据异常（herdr 后端：label 命中 ≠ 在线）=='
    fi
    printf '%s\n' "${term_abn[@]}"
  fi
  # AC2.2 闭环（B3）：可投递标注 —— **独立节/独立行**，不改任何既有行格式（BR1 md5 仍逐字）
  #   消费者 = close 忙闲闸门 + 本节；映射单源 = term_deliverable（idle/done 可投递，其余/unknown 不可）
  local -a dl=()
  local -A dl_seen=()
  local dn dv ds
  for dn in "${ROLE_ORDER[@]}" "${field_names[@]}"; do
    [[ -n "$dn" ]] || continue
    if [[ -n "${dl_seen[$dn]:-}" ]]; then continue; fi   # ROLE_ORDER 与现场名册有交集 ⇒ 去重后再渲染
    dl_seen["$dn"]=1
    [[ -n "${abn_seen[$dn]:-}" ]] || continue     # 只对已算定证据的名字（全集）
    dv="${hv[$dn]:-absent}"; ds="${hstate[$dn]:--}"
    [[ "$dv" == "absent" ]] && continue
    # T597（P3 信号收敛）：`unknown`（缺身份标签 ⇒ 归属不可判定）已由上线状态表的 `? 行 + 处置行` 说明，
    #   不再在「投递判定」节重复一遍（同一事实一处呈现）。
    [[ "$dv" == "unknown" ]] && continue
    if [[ "$dv" == "online" ]] && term_deliverable "$ds"; then
      dl+=("  · $dn：可投递（状态=$ds）")
    elif [[ "$dv" == "online" ]]; then
      dl+=("  · $dn：不可投递（状态=$ds；BR7 ⇒ 保守不可投递）")
    else
      dl+=("  · $dn：不可投递（$dv ⇒ 无在线证据）")
    fi
  done
  if (( ${#dl[@]} > 0 )); then
    echo '== 投递判定（BR7：idle/done 可投递；working/blocked/unknown 不可投递）=='
    printf '%s\n' "${dl[@]}"
  fi
  # D5：未识别节（F3）—— 单列，不给可执行命令（T530「非静默」对偶）
  if (( ${#unrecognized[@]} > 0 )); then
    echo '== 角色未识别（疑似 fleet 遗留）=='
    printf '%s\n' "${unrecognized[@]}"
  fi
  # T525：子代理会话（pi-subagents）不属舰队会话身份模型 —— 派生节后独立一行、只计数不列名、N=0 不打印（BR3/BR6）。
  local nsub
  nsub="$(subagent_in_field)"
  (( nsub > 0 )) && printf '  · 另有 %d 个子代理会话（subagent-*）· 生命周期由 pi-subagents 管理，nao 不回收\n' "$nsub"
  # 无标签 pi pane：**不列**（herdr 无标题契约、pane 可无 label 且可属用户自己的 agent；幽灵 pane 已单列）
  return 0
}

# =============================================================================
# status --json（T567-B · ADR 2026-11-24 §D2 · PRD §五）：编排器唯一跨进程契约（`schema:1`）。
#
# 硬约束（AC1）：文本路径 `cmd_status` **零改动** —— 本组函数不参与文本渲染，只读同一批门面事实
#   （term_snapshot / term_liveness / fleet_name_parse / session_repo_verdict），因此两侧不存在判定双源。
# 字段清单（**长期契约**，只增不删/不改语义；见 docs/reports/567-impl-rd-infra.md §三）：
#   {schema:1, backend, repo_root,
#    sessions:[{name,kind,role,task,pane_id,cwd,repo,own,online,agent,busy,deliverable,verdict}],
#    roles:[{role,online,sessions:[name...]}]}
#   agent 三态 = working | idle | unknown —— `unknown` 覆盖 absent/ghost/dead/mismatch/integration-missing
#     与任何非 idle/working 的 agent_status（fail-closed：不可投递 ≠ 空闲）。
#   own/online/busy/deliverable = 布尔；`verdict` 为归属原始判据（local|other|unknown），保留供诊断。
# JSON 由 node 生成（转义交给 JSON.stringify，禁 bash 手拼）：node 已是 fleet 的既有前提（check/session 用）。
_status_json_emit() {  # <backend> <repo_root>（TSV 行来自 stdin）
  node -e '
const [backend, repoRoot] = process.argv.slice(1);
let buf = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (d) => { buf += d; });
process.stdin.on("end", () => {
  const sessions = [];
  const roles = new Map();
  for (const line of buf.split("\n")) {
    if (!line) continue;
    const f = line.split("\t");
    if (f.length < 14) continue;
    const [name, kind, role, task, pane_id, cwd, repo, own, online, agent, busy, deliverable, verdict, live] = f;
    const s = {
      name, kind, role, task, pane_id, cwd, repo,
      own: own === "1", online: online === "1", agent,
      busy: busy === "1", deliverable: deliverable === "1", verdict,
      // T597：三态可区分（纯增量字段，schema 仍为 1）—— online=1 时恒 "online"；
      //   否则透传后端终态：unknown（同名在场但缺身份标签 ⇒ 归属不可判定）/ absent（确实没有）。
      liveness: online === "1" ? "online" : (live || "absent"),
    };
    sessions.push(s);
    if (!roles.has(role)) roles.set(role, { role, online: false, state: "absent", sessions: [] });
    const r = roles.get(role);
    if (s.online) r.online = true;
    // 角色级三态：任一在线 ⇒ online；否则有 unknown ⇒ unknown；否则 absent（顺序即优先级）
    if (r.state !== "unknown") r.state = s.online ? "online" : (r.state === "online" ? "online" : (s.liveness === "unknown" ? "unknown" : "absent"));
    r.sessions.push(name);
  }
  const out = {
    schema: 1, backend, repo_root: repoRoot,
    sessions,
    roles: [...roles.values()].sort((a, b) => (a.role < b.role ? -1 : a.role > b.role ? 1 : 0)),
  };
  process.stdout.write(JSON.stringify(out) + "\n");
});
' "$1" "$2"
}

cmd_status_json() {
  local be root snap nm k r t num sc po vline vd st seq hk ws verdict obase repo_c
  fleet_roles_init --cards

  local own online agent busy dl cwd pid
  local -a names=()
  local -A seen=() cwds=() pids=()
  # 前提：与文本路径同判据、同退出码（rc=3 = 环境级失败，调用方据 rc 决定下一步）
  if ! term_snapshot >/dev/null; then
    if [[ "$(term_label)" == "app" ]]; then
      printf 'status --json: 需要 desktop app core：hc ls / hc get 不可用（核对 desktop app 是否在运行、HC_TERMINAL_SOCKET 是否有效）—— 修好后重试\n' >&2
    else
      printf 'status --json: 需要 herdr server：pane list / agent list 不可用（核对 `herdr --session %s server` 是否在跑、protocol 是否 22）—— 修好后重试\n' "${HERDR_SESSION:-?}" >&2
    fi
    exit 3
  fi
  fleet_task_map_init
  if [[ "$(term_label)" != "app" ]]; then
    term_snapshot 2>/dev/null | awk -F'\t' 'NF{print $4}' | fleet_meta_gc
  fi
  be="$(term_label)"
  root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$root" ]] || root="$(nao_phys_path "$PWD")"
  # 会话全集：先常驻（ROLE_ORDER，未在线也要出现 —— 需要「角色缺席」这一事实），再现场名册
  for nm in "${ROLE_ORDER[@]}"; do
    [[ -n "$nm" && -z "${seen[$nm]:-}" ]] || continue
    names+=("$nm"); seen["$nm"]=1
  done
  # 变量名避开「关前复核」用例用来定位模块的那个子串（撞名会把它的变异打到本文件）
  local -a _sj_names=()
  mapfile -t _sj_names < <(visible_session_names)
  for nm in "${_sj_names[@]:-}"; do
    [[ -n "${nm:-}" && -z "${seen[$nm]:-}" ]] || continue
    names+=("$nm"); seen["$nm"]=1
  done
  # pane cwd / pane id（同名多 pane：取首个，保留分屏下的稳定输出）
  local pn pcwd ppid
  while IFS=$'\t' read -r pn ppid pcwd; do
    [[ -n "$pn" ]] || continue
    [[ -z "${cwds[$pn]:-}" ]] && cwds["$pn"]="$pcwd"
    [[ -z "${pids[$pn]:-}" ]] && pids["$pn"]="$ppid"
  done < <(pane_cwd_snapshot)
  local roots_blob="" rl
  while IFS= read -r rl; do [[ -n "$rl" ]] && roots_blob+="$rl"$'\n'; done < <(repo_anchor_roots)
  for nm in "${names[@]}"; do
    k=""; r=""; t=""; num=""; sc=""
    po="$(fleet_name_parse "$nm")"
    case "$po" in
      "OK "*)        IFS=',' read -r k r t num <<< "${po#OK }" ;;
      "LEGACY OK "*) IFS=',' read -r k r t sc <<< "${po#LEGACY OK }" ;;
      *)             k="other"; r="$nm" ;;
    esac
    t="$(fleet_effective_task "$nm")"
    [[ -n "$t" && "$k" == "resident" ]] && k="derived"
    # 与文本路径同一判据（常驻角色带所属 workspace 作 repo 过滤；其余不带）
    if [[ -n "${ROLE_CARDS[$nm]:-}" ]]; then
      vline="$(term_liveness "$nm" "${ROLE_WS[$nm]:-}")"
    else
      vline="$(term_liveness "$nm")"
    fi
    IFS=$'\t' read -r vd st seq hk <<< "$vline"
    online=0; [[ "${vd:-absent}" == "online" ]] && online=1
    agent=unknown
    if (( online )); then
      case "${st:--}" in
        working) agent=working ;;
        idle|done) agent=idle ;;
        *) agent=unknown ;;
      esac
    fi
    busy=0; [[ "$agent" == "working" ]] && busy=1
    dl=0; (( online )) && term_deliverable "${st:--}" && dl=1
    cwd="${cwds[$nm]:-}"; pid="${pids[$nm]:-}"
    IFS=$'\t' read -r verdict obase <<< "$(session_repo_verdict "$roots_blob" "$cwd" "")"
    own=0; repo_c=""
    case "$verdict" in
      local) own=1; repo_c="$root" ;;
      other) repo_c="${obase:--}" ;;
      *)     repo_c="" ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$nm" "$k" "$r" "$t" "$pid" "$cwd" "$repo_c" "$own" "$online" "$agent" "$busy" "$dl" "$verdict" "${vd:-absent}"
  done | _status_json_emit "$be" "$root"
}
