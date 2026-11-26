# =============================================================================
# fleet/lib/close.sh — close 子命令（回收面）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term/manifest/session
# 闸门（在跑 turn / tasks-state 未推进）在 cmd_close 内；--force 跳过。
# =============================================================================

# close 裸名解析的**调用方锚**（Issue #146 §二）：只取本地事实，**禁**名册/`$repo`/ROLE_WS 反查（否则成环）。
#   居民目标 = $PWD 物理 toplevel（git toplevel 是严格祖先时归一，否则 pwd -P）；卡目标 = 卡文件所在仓。
#   git 调用 ≤1 次/close：只读复用 repo_anchor_roots 的单次实现（不改其语义/输出形状）；
#   该函数先印 pwd -P、再印严格祖先 toplevel ⇒ **末行 = 最宽锚**。
_close_anchor() {  # → 单值物理路径（stdout）
  local l last=""
  while IFS= read -r l; do [[ -n "$l" ]] && last="$l"; done < <(repo_anchor_roots)
  printf '%s\n' "${last:-$(nao_phys_path "$PWD")}"
}

# 候选 cwd 去重（#151/T552 P2 · **单源**）：stdin 每行一个 cwd → stdout 去重后的**物理路径**（保序）。
#   为什么单源：全名分支与裸名分支都要「同 name 同 cwd 的陈旧重复条目 ≠ 并列候选」，
#   复制两份必然漂移（T552 QA 实测：全名分支去重后采用、裸名分支仍 die 且同一路径列两遍）。
#   键 = 物理路径（`nao_phys_path`：symlink / 相对路径 / 尾斜杠归一），不是字符串比较。
_close_dedupe_cwds() {
  local -A seen=()
  local p q
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    q="$(nao_phys_path "$p")"
    [[ -n "$q" ]] || continue
    [[ -n "${seen[$q]:-}" ]] && continue
    seen[$q]=1
    printf '%s\n' "$q"
  done
}

# 采用候选名后的 repo 复核（Issue #146 §二 · 三态）：该名名册 cwd **唯一** ⇒ 采用；>1 ⇒ die；0 ⇒ 保留现值。
#   为什么不再「按目标仓过滤确认」：跨仓 close 采用唯一候选 `pm@x` 时，按调用方仓过滤必得 0
#   ⇒ repo 停在调用方仓 ⇒ herdr 侧 liveness/忙闲按仓过滤 ⇒ 「未运行」rc=0 假成功（R2 同类）。
#   名册不可用（roster_ok≠1）⇒ 不改写（与改动前逐字等价）。回填调用方的 `repo`（bash 动态作用域）。
_close_adopt_repo() {  # <name> <roster_ok>
  local nm="${1-}" ok="${2:-0}"
  local -a cw=()
  # 守卫（T551 P3-2）：回写靠 bash 动态作用域 ⇒ 调用点**必须**自己声明 `local repo`。
  #   否则赋值会静默创建/改写**全局** repo（无报错、无文案、下一次调用读到脏值）⇒ fail loud 比静默好。
  declare -p repo >/dev/null 2>&1 || die "内部错误：_close_adopt_repo 须在声明 local repo 的调用点内调用（否则会静默创建全局 repo；该怎么办：调用点先 local repo）"
  [[ "$ok" == "1" ]] || return 0
  mapfile -t cw < <(intercom_cwds_for "$nm")
  (( ${#cw[@]} == 1 )) && { repo="${cw[0]}"; return 0; }
  (( ${#cw[@]} > 1 )) || return 0
  die "close 目标歧义：$nm 在名册中对应 ${#cw[@]} 个 cwd：$(printf '%s ' "${cw[@]}")（该怎么办：用 intercom({action:'list'}) 人工核对该会话的仓位置；同名多仓没有「全名」写法可区分）"
}

# ---------------------------------------------------------------------------
# 回收已完成会话：闸门（tasks-state 已推进 + 无在跑 turn）+ 落地（pane/session）
cmd_close() {
  local force="$1" task="$2" target="${3:-}"
  [[ -n "$target" ]] || die "close 需要目标：角色别名或会话名（如 rd-be / rd-be2；旧形 qa(T1) / qa-T1 只读）"
  # T525 BR1/BR2/BR4：子代理会话显式拒绝（判定只针对 $target 位置名；--force 不旁路）
  if [[ "$target" == subagent-* ]]; then
    die "拒绝回收 $target：这是 pi-subagents 子代理会话（subagent-*），其生命周期不归 nao 回收（请用 pi-subagents 的 stop / retention 管理）"
  fi
  local name repo cls bus pane pids st tgt="" a best="" bestc="" is_resident=1 card_role="" card_path="" cr cp croot k
  local pout="" p_kind="" p_role="" p_task="" p_scope="" p_num="" parsed=0 legacy=0 exact="" role="" kindc=""
  local anchor="" roster_ok=0 fallback_repo="" scope="" base_name=""
  local -a name_cwds=() scoped_cwds=() cands=() cands_in=() cw_uniq=()
  local -A close_pw=()
  intercom_list_json >/dev/null 2>&1 || true   # 预热名册缓存
  fleet_roles_init --cards                     # BR8：parse 的角色事实表（常驻 + 卡 role）
  fleet_task_map_init                          # v3：task 元数据映射（5 列快照第 5 列）
  if [[ "$(term_label)" != "app" ]]; then
    term_snapshot 2>/dev/null | awk -F'\t' 'NF{print $4}' | fleet_meta_gc
  fi
  # D7：manifest `slug:` 弃用告警在 close 读入口也要出现（即使本命令不需要 manifest 做仓回退）
  local _mnr_w="" _mnj_w=""
  _mnr_w="$(fleet_manifest_root "$PWD")"
  _mnj_w="$(fleet_manifest_load "$_mnr_w" 2>/dev/null)" || true
  fleet_manifest_warn_deprecated "$_mnj_w"

  # ---- 目标解析（T554）：新形精确名 / 旧形只读（LEGACY）/ 未识别（别名·卡集）----
  pout="$(fleet_name_parse "$target")"
  case "$pout" in
    "OK "*)
      parsed=1
      IFS=',' read -r p_kind p_role p_task p_num <<< "${pout#OK }"
      # v3：名字里没有 task；--task 只按元数据匹配（effective = 元数据优先，v2 名字解析值回落）。
      local _nt="${p_task}"
      [[ -n "$_nt" ]] || _nt="$(fleet_effective_task "$target")"
      if [[ -n "$task" && -n "$_nt" && "$task" != "$_nt" ]]; then
        die "目标名与 --task 不一致：$target（元数据是 $_nt，--task 是 $task；该怎么办：二选一）"
      fi
      [[ -n "$_nt" ]] && task="$_nt"
      role="$p_role"; kindc="$p_kind"
      case "$p_kind" in card) kindc="card" ;; *) [[ -n "$task" ]] && kindc="derived" ;; esac
      # 名字里带 task（v2 只读）⇒ 精确名原样；v3 的 task 在元数据 ⇒ 由候选集合解析（不写进名字）
      if [[ -n "$task" && -z "$p_task" ]]; then
        exact=""
      else
        exact="$target"
      fi
      if [[ "$p_kind" == "card" ]]; then
        is_resident=0; card_role="$p_role"
        while IFS=$'\t' read -r cr cp croot; do
          [[ "$cr" == "$card_role" ]] || continue
          card_path="$cp"; break
        done < <(card_role_set)
        [[ -n "$card_path" ]] && fallback_repo="${card_path%/.agents/prompts/*}"
      else
        tgt="$p_role"
      fi
      ;;
    "LEGACY OK "*)
      parsed=1; legacy=1
      IFS=',' read -r p_kind p_role p_task p_scope <<< "${pout#LEGACY OK }"
      if [[ -n "$task" && -n "$p_task" && "$task" != "$p_task" ]]; then
        die "目标名与 --task 不一致：$target（名字里是 $p_task，--task 是 $task；该怎么办：二选一）"
      fi
      [[ -n "$p_task" ]] && task="$p_task"
      role="$p_role"; kindc="$p_kind"; scope="$p_scope"
      # 旧形裸名 + --task ⇒ 重建旧形（只读面）；否则精确名原样
      if [[ -n "$task" && -z "$p_task" ]]; then
        exact="$p_role-$task"; [[ -n "$p_scope" ]] && exact="$exact@$p_scope"
      else
        exact="$target"
      fi
      if [[ "$p_kind" == "card" ]]; then
        is_resident=0; card_role="$p_role"
        while IFS=$'\t' read -r cr cp croot; do
          [[ "$cr" == "$card_role" ]] || continue
          card_path="$cp"; break
        done < <(card_role_set)
        [[ -n "$card_path" ]] && fallback_repo="${card_path%/.agents/prompts/*}"
      else
        tgt="$p_role"
      fi
      ;;
  esac

  # ---- 未识别目标：别名 / <别名>-<任务> / 卡集最长前缀（只用来**解析身份**，名字仍由 builder 造）----
  if (( ! parsed )); then
    if [[ -n "${ALIAS_ROLE[$target]:-}" ]]; then
      tgt="$target"
    elif [[ -n "$task" && "$target" == *-"$task" && -n "${ALIAS_ROLE[${target%-"$task"}]:-}" ]]; then
      tgt="${target%-"$task"}"
    else
      for a in "${!ALIAS_ROLE[@]}"; do
        [[ "$target" == "$a"-* ]] || continue
        if [[ -z "$best" || ${#a} -gt ${#best} ]]; then best="$a"; fi
      done
      if [[ -n "$best" ]]; then tgt="$best"; task="${target#"$best"-}"; fi
    fi
    if [[ -z "$tgt" ]]; then
      local -A cset=()
      while IFS=$'\t' read -r cr cp croot; do
        [[ -n "$cr" ]] || continue
        cset["$cr"]="$cp"
      done < <(card_role_set)
      for k in "${!cset[@]}"; do
        [[ "$target" == "$k" || "$target" == "$k"-* ]] || continue
        if [[ -z "$bestc" || ${#k} -gt ${#bestc} ]]; then bestc="$k"; fi
      done
      if [[ -n "$bestc" ]]; then
        card_role="$bestc"; card_path="${cset[$bestc]}"; is_resident=0
        if [[ "$target" != "$bestc" ]]; then
          local tsuff="${target#"$bestc"-}"
          if [[ -n "$task" && "$task" != "$tsuff" ]]; then
            die "目标名后缀与 --task 不一致：$target（后缀 $tsuff，--task $task；该怎么办：二选一，如 close --task $tsuff $bestc）"
          fi
          task="$tsuff"
        fi
      fi
    fi
    if [[ -z "$tgt" && "$is_resident" == "1" ]]; then
      die "未知角色或会话名: $target（可用角色: ${ROLE_ORDER[*]}；常驻名 = <角色>[N]（N=2..9）；派生名 = <角色>[N]（task 用 --task 元数据匹配；v2 <角色>(<任务号>) / 旧形 <角色>-<任务号> / <角色>@<scope> 只读）；亦可用 close --task <编号> <角色>；下游卡角色需在本仓锚下存在 .agents/prompts/<role>.md）"
    fi
    if [[ "$is_resident" == "1" ]]; then
      resolve_role "$tgt"; role="$NAME"; kindc="resident"
      [[ -n "$task" ]] && kindc="derived"
      fallback_repo="${ROLE_WS[$NAME]:-$PWD}"
    else
      role="$card_role"; kindc="card"
      fallback_repo="${card_path%/.agents/prompts/*}"
      [[ -n "$fallback_repo" ]] || fallback_repo="$PWD"
    fi
    if [[ -n "$task" ]]; then
      exact=""   # v3：task 不进名字 ⇒ 交给候选（同 role + 元数据 task）解析
    else
      exact="$(fleet_name_build "$kindc" "$role" "")"
    fi
  fi
  [[ -n "$role" ]] || die "close 内部错误：未能解析角色（target=$target）"

  # ---- 锚（本地事实）：居民 = $PWD toplevel；卡 = 卡文件所在仓根 ----
  if [[ "$is_resident" == "1" ]]; then
    anchor="$(_close_anchor)"
  else
    anchor="$(nao_phys_path "$fallback_repo")"
  fi
  [[ -n "$anchor" ]] || anchor="$(nao_phys_path "$PWD")"
  roster_ok=0
  intercom_list_json >/dev/null 2>&1 && roster_ok=1

  # pane cwd 一次快照（锚过滤用；<1 次 pane list，与 status 同源）
  local pn pname pcwd
  while IFS=$'\t' read -r pname pn pcwd; do
    [[ -n "$pname" ]] || continue
    close_pw["$pname"]="${close_pw[$pname]:-}$pcwd"$'\n'
  done < <(pane_cwd_snapshot)

  # 名字是否落在锚内（名册 cwd 或 pane cwd 任一命中）
  _close_in_anchor() {  # <name>
    local nm="${1-}" c
    [[ -n "$nm" ]] || return 1
    # 名册不可用且 pane cwd 也不可知 ⇒ 无归属证据，不得据此隐藏会话（交给句柄层过滤/拒绝）
    [[ "$roster_ok" == "1" || -n "${close_pw[$nm]:-}" ]] || return 0
    if [[ "$roster_ok" == "1" ]]; then
      while IFS= read -r c; do [[ -n "$c" ]] && return 0; done < <(intercom_cwds_for "$nm" "$anchor")
    fi
    if [[ -n "${close_pw[$nm]:-}" ]]; then
      while IFS= read -r c; do
        [[ -n "$c" ]] || continue
        # cwd 不可知（stub/旧 pane 无 cwd）⇒ 不能据此隐藏会话（交给句柄层按仓过滤/拒绝）
        [[ "$c" == "-" ]] && return 0
        repo_contains_path "$anchor" "$(nao_phys_path "$c")" && return 0
      done <<< "${close_pw[$nm]}"
    fi
    return 1
  }

  # ---- 候选名：同 (role,task) 的 v2（任意槽位）+ 旧形（含 @scope）----
  mapfile -t cands < <(fleet_same_core_candidates "$role" "$task")
  if (( legacy )); then
    # 用户显式给了旧形全名 ⇒ 只认它（AC6；不因场里还有同名新形而改指）
    name="$exact"; scope="$p_scope"
  else
    # 新形/裸名：先精确名，再按 role+task 重建的新形/旧形（锚内唯一才采用）
    if _close_in_anchor "$exact"; then
      # 锚内同名多 pane / 多名册条目 ⇒ 不猜（与 d2 同口径；并列拒绝在句柄层之前给出可读文案）
      local _nro=0 _npa=0 _cc _cl _sr_p _sr_c _sr_f _pids=""
      local -a _ncw=()
      while IFS=$'\t' read -r _srcn _ _sr_c _sr_p _; do
        [[ "$_srcn" == "$exact" ]] || continue
        [[ "$_sr_c" == "-" || -z "$_sr_c" ]] || repo_contains_path "$anchor" "$(nao_phys_path "$_sr_c")" || continue
        _pids+="${_pids:+,}$_sr_p"
      done < <(term_snapshot 2>/dev/null || true)
      if [[ "$roster_ok" == "1" ]]; then
        while IFS= read -r _cc; do [[ -n "$_cc" ]] && { _nro=$((_nro+1)); _ncw+=("$_cc"); }; done < <(intercom_cwds_for "$exact" "$anchor")
      fi
      if [[ -n "${close_pw[$exact]:-}" ]]; then
        while IFS= read -r _cl; do
          [[ -n "$_cl" ]] || continue
          repo_contains_path "$anchor" "$(nao_phys_path "$_cl")" || continue
          _npa=$((_npa+1)); _ncw+=("$_cl")
        done <<< "${close_pw[$exact]}"
      fi
      # 名册 1 条 + pane 1 条 = 同一个会话（不重复计）；任一侧 >1 ⇒ 并列（d2 同口径）
      #   `--force` 时不在此拦（交给句柄层逐 pane 按安全判据清理，B2 转办②）
      if (( _nro > 1 || _npa > 1 )) && [[ "$force" != true ]]; then
        die "close 目标歧义：同名 label 命中 $(( _nro > _npa ? _nro : _npa )) 个 pane（$exact 在本仓锚 $anchor 内）：${_pids:-$(printf '%s ' "${_ncw[@]}")}（该怎么办：先 intercom({action:'list'}) 人工核对并关掉多余的会话（同仓同名多 pane 时本命令不猜哪一个是目标）)"
      fi
      name="$exact"; scope=""
    else
      cands_in=()
      local cn
      for cn in "${cands[@]:-}"; do
        [[ -n "$cn" && "$cn" != "$exact" ]] || continue
        _close_in_anchor "$cn" && cands_in+=("$cn")
      done
      if (( ${#cands_in[@]} == 1 )); then
        name="${cands_in[0]}"
        pout="$(fleet_name_parse "$name")"
        case "$pout" in
          "LEGACY OK "*) IFS=',' read -r _ _ _ scope <<< "${pout#LEGACY OK }" ;;
          *) scope="" ;;
        esac
        # v3：task 候选的名字可能同名（同一槽位）多 pane ⇒ 与精确名分支同口径，不猜
        if [[ "$force" != true ]]; then
          local _d2p=0 _d2r=0 _d2n _d2pane _d2c _d2f _d2cc
          while IFS=$'\t' read -r _d2n _ _d2c _d2pane _; do
            [[ "$_d2n" == "$name" ]] || continue
            [[ "$_d2c" == "-" || -z "$_d2c" ]] || repo_contains_path "$anchor" "$(nao_phys_path "$_d2c")" || continue
            _d2p=$((_d2p + 1))
          done < <(term_snapshot 2>/dev/null || true)
          if [[ "$roster_ok" == "1" ]]; then
            while IFS= read -r _d2cc; do [[ -n "$_d2cc" ]] && _d2r=$((_d2r + 1)); done < <(intercom_cwds_for "$name" "$anchor")
          fi
          if (( _d2p > 1 || _d2r > 1 )); then
            die "close 目标歧义：同名 label 命中 $(( _d2p > _d2r ? _d2p : _d2r )) 个 pane（$name 在本仓锚 $anchor 内）：不猜（该怎么办：先 intercom({action:'list'}) 人工核对并关掉多余的会话）"
          fi
        fi
      elif (( ${#cands_in[@]} > 1 )); then
        die "close 目标歧义：${exact:-$role} 在本仓锚（$anchor）内有 ${#cands_in[@]} 个同 (角色,任务) 的会话：$(printf '%s ' "${cands_in[@]}")（该怎么办：先 intercom({action:'list'}) 人工核对并关掉多余的会话；或显式写带槽位号的名字）"
      else
        # 本仓锚内无候选：若场里有同 (role,task) 的非本仓会话 ⇒ D4：不回收 + 指路（禁全局首命中）
        if (( ${#cands[@]} > 0 )); then
          log "${exact:-$role} 未运行（本仓锚内无该会话；场内有同名/同 core 会话：$(printf '%s ' "${cands[@]}")）→ 不在本仓回收；如确需回收请到对应仓执行 close"
          return 0
        fi
        # v3：task 不进名字 ⇒ 无元数据匹配时**不得**回落到裸 role（会误杀同名常驻会话）。
        #   用只读旧形 `<role>(<task>)` 作定位占位：它只会命中 v2 会话（已由候选覆盖）⇒ 此处必为空。
        if [[ -z "$exact" ]]; then
          name="$role($task)"; scope=""
        else
          name="$exact"; scope=""
        fi
      fi
    fi
  fi

  # ---- 仓来源（T554/AC6 + D4）：名册 cwd 唯一 ⇒ 采用；>1 ⇒ 不猜；0 ⇒ 回落 ----
  fallback_repo="${fallback_repo:-$anchor}"
  if (( legacy )); then
    # 旧形全名：manifest code → path 回落（J/39 态），否则锚
    local mnr="" mnstream="" mnkind="" mna="" mnb=""
    if [[ -n "$scope" ]]; then
      mnr="$(fleet_manifest_root "$anchor")"
      mnstream="$(fleet_manifest_load "$mnr" 2>/dev/null)" || true
      fleet_manifest_warn_deprecated "$mnstream"
      if [[ -n "$mnstream" && "$mnstream" != "NONE" ]]; then
        while IFS=$'\t' read -r mnkind mna mnb; do
          [[ "$mnkind" == "REPO" && "$mna" == "$scope" ]] && { fallback_repo="$mnb"; break; }
        done <<< "$mnstream"
      fi
    fi
    repo="$fallback_repo"
    if [[ "$roster_ok" == "1" ]]; then
      mapfile -t name_cwds < <(intercom_cwds_for "$name")
      if (( ${#name_cwds[@]} == 1 )); then
        repo="${name_cwds[0]}"
      elif (( ${#name_cwds[@]} > 1 )); then
        mapfile -t cw_uniq < <(printf '%s\n' "${name_cwds[@]}" | _close_dedupe_cwds)
        if (( ${#cw_uniq[@]} > 1 )); then
          local _dnote=""
          (( ${#name_cwds[@]} > ${#cw_uniq[@]} )) && _dnote="（名册共 ${#name_cwds[@]} 条记录，含同名同仓重复条目；同仓重复条目不必区分仓，不要当成多仓歧义）"
          die "close 目标歧义：$name 在名册中对应 ${#cw_uniq[@]} 个路径：$(printf '%s ' "${cw_uniq[@]}")$_dnote（该怎么办：先 intercom({action:'list'}) 人工核对该会话的仓位置并关掉多余的那个）"
        elif (( ${#cw_uniq[@]} == 1 )); then
          repo="${cw_uniq[0]}"
        fi
      fi
    fi
  else
    # 新形/裸名：v2 裸名只在锚内（D4）；名册唯一 cwd（**锚过滤**）可校正仓（同锚内子目录）
    repo="$anchor"
    if [[ "$roster_ok" == "1" ]]; then
      mapfile -t name_cwds < <(intercom_cwds_for "$name" "$anchor")
      if (( ${#name_cwds[@]} == 1 )); then
        repo="${name_cwds[0]}"
      elif (( ${#name_cwds[@]} > 1 )); then
        mapfile -t cw_uniq < <(printf '%s\n' "${name_cwds[@]}" | _close_dedupe_cwds)
        if (( ${#cw_uniq[@]} == 1 )); then
          repo="${cw_uniq[0]}"
        else
          die "close 目标歧义：$name 在名册中对应 ${#cw_uniq[@]} 个路径：$(printf '%s ' "${cw_uniq[@]}")（该怎么办：先 intercom({action:'list'}) 人工核对并关掉多余的会话）"
        fi
      fi
    fi
  fi

  # 卡会话的回收提示（判据不变）
  if [[ "$is_resident" != "1" ]]; then
    warn "一次性会话 $name（下游卡）$card_path：回收后不重开（如需重开：ensure --card <卡>）"
    if [[ -n "$task" ]]; then
      cls="$(task_state_class "$task")"
      case "$cls" in
        active)    log "跳过 tasks-state active 闸门（下游卡一次性会话）：$task（产物以回执/报告为准）" ;;
        absent)    log "tasks-state 全文无 $task 记录（下游卡一次性会话，不阻塞回收）" ;;
        mentioned) log "tasks-state 仅散文提及 $task（下游卡一次性会话，不阻塞回收）" ;;
        nofile)    log "未启用 $TASKS_STATE（跳过状态闸门）" ;;
      esac
    fi
  elif [[ -z "$task" ]]; then
    warn "常驻会话 $name：本批不再需要该角色时才回收；回收后可用 ensure 重开"
  else
    cls="$(task_state_class "$task")"
    if [[ "$cls" == "active" && "$force" != true ]]; then
      warn "拒绝回收 $name：tasks-state 中 $task 仍在进行态（未验收/未归档）"
      warn "  先把 $task 移入「已验收/已归档」再回收（或 --force：将丢失打回返工所需上下文）"
      return 1
    fi
    [[ "$cls" == "absent" ]] && warn "tasks-state 全文无 $task 记录（仅按会话名回收）"
    [[ "$cls" == "mentioned" ]] && log "tasks-state 仅散文提及 $task（非表内记录，不阻塞回收）"
    [[ "$cls" == "nofile" ]] && log "未启用 $TASKS_STATE（跳过状态闸门）"
  fi

  # ---- 句柄层（B3）：herdr 实现（定位 / self 判据 / liveness / 忙闲 / 回收句柄）----
  local _cl_rc=0
  term_reclaim "$name" "$repo" "$force" "$role" "$scope" "${tgt:-$role}" || _cl_rc=$?
  # T573：close 结果落台账（保留分级用；`--force` = 明示非正常收尾。失败只 warn、不改 rc）
  (( _cl_rc == 0 )) && { fleet_sessions_note_outcome "$name" "${task:-}" "$repo" "$force" || true; }
  return "$_cl_rc"
}
