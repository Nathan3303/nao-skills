# =============================================================================
# fleet/lib/ensure.sh — ensure 子命令（放置/就绪面）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term/manifest/session
# 三态计数（成功/跳过/失败）与 SPAWN_RC_* 结果契约的消费方；卡/槽位/放置键解析在 manifest。
# =============================================================================

# 白名单命中返回 0，否则返回 1；未设白名单=放行
check_model() {
  local m="$1" entry
  local entries=()
  [[ -z "$MODEL_WHITELIST" ]] && return 0
  IFS=',' read -ra entries <<< "$MODEL_WHITELIST"
  for entry in "${entries[@]}"; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -z "$entry" ]] && continue
    # shellcheck disable=SC2053
    [[ "$m" == $entry ]] && return 0
  done
  return 1
}

# ---------------------------------------------------------------------------

# 组装系统提示文件：角色卡 + 环境锚点（本机绝对路径，供跨仓库会话解析 @ 引用失败时兜底）
build_system_prompt() {
  local card="$1" f
  f="$(mktemp "/tmp/nao-fleet-$(basename "$card" .md)-XXXXXX.md")"
  {
    cat "$card"
    printf '\n## 环境锚点\n- NAO_FLEET=%s（nao 机制**包根**；`NAO_SKILLS` 为兼容别名，二者都给时 NAO_FLEET 优先。@.agents/... 引用一律以 `$NAO_FLEET/.agents/` 为根解析。注意：项目内 `.agents/` 只有 shim，不存机制副本）\n' "$SKILLS_DIR"
  } > "$f"
  echo "$f"
}

spawn_one() {
  local name="$1" repo="$2" model="$3" card_override="${4:-}" role_id="${5:-}" card_name="${6:-}" force="${7:-false}" label="${8:-}" group="${9:-}" task="${10:-}" card prompt_file inner session_dir
  # T537：卡路径可由调用方显式给出（下游仓卡）；未给出时仍走清单（PROMPTS_DIR/<card>）逐字不变
  # #75：**两条取卡通道分两个参数，禁混用** ——
  #   ④ card_override = `--card` 的**完整路径**（下游卡，已由 resolve_card 限定在 <repo>/.agents/prompts/ 内）
  #   ⑥ card_name     = 清单**相对名**（roles.yaml 的 card 文件名，由 cmd_ensure **按目标**下发）
  #   旧写法在无 override 时回落全局 `$PROMPT`（resolve 阶段每个目标覆写一次 ⇒ 最后一个胜出），
  #   于是多目标 `ensure arch rd-fe` 的**每个** pane 都拿到最后一个目标的卡（身份级错误）。
  if [[ -n "$card_override" ]]; then card="$card_override"; else card="$PROMPTS_DIR/${card_name:-}"; fi
  [[ -f "$card" ]] || die "角色卡不存在: $card"
  [[ -d "$repo" ]] || die "工作区不存在: $repo"

  # T573/Issue #206：派生会话的 Pi session 记录落**舰队自有目录**（一仓一子目录），不进 ~/.pi/agent/sessions，
  #   否则每条 ensure 都往用户的 /resume 主列表里添一条。Pi 显式 `--session-dir` 直接用它（不再按 cwd 分子目录），
  #   故子目录由本侧按 Pi 默认布局同款编码建好并传入。不可建 ⇒ **fail loud**（绝不静默去掉这个参数落回主目录）。
  session_dir="$(fleet_sessions_dir "$repo")"
  fleet_sessions_prepare "$session_dir" \
    || die "会话记录目录不可建: $session_dir（拒绝静默落回 ~/.pi/agent/sessions）—— 该怎么办：核对 ${FLEET_STATE_ROOT} 的权限/磁盘，或设 NAO_FLEET_META_DIR 指向可写目录后重试"

  # 前提已由入口 term_require 硬校验（HERDR_ENV / HERDR_SESSION / protocol 22）；
  #   此处只走唯一路径（BR1/BR3）。
  prompt_file="$(build_system_prompt "$card")"
  inner="cd $(printf %q "$repo") && export CODEGRAPH_TELEMETRY=0 && exec pi --name $(printf %q "$name")"
  [[ -n "$model" ]] && inner+=" --model $(printf %q "$model")"
  inner+=" --append-system-prompt $(printf %q "$prompt_file")"
  inner+=" --session-dir $(printf %q "$session_dir")"
  # T548/Issue #140：自检**不再**拼进 argv（那会把「要 pi 干活」放在「等 pi 空闲」的就绪门之前 ⇒
  #   就绪门恒超时，rc=1 假失败）。改为 spawn 成功后由 term_deliver 投递（见下方 SPAWN_RC_OK 分支）；
  #   开关关/非 pm ⇒ 整段不执行 ⇒ 命令行与本缺陷前逐字等价（AC3）。
  # T536/BR2：后台清理必须**完全脱离调用方 fd**。原写法 `( sleep 60; … ) &` 让子 shell 继承调用方
  #   stdout/stderr ⇒ 输出被 `| cat` / CI 捕获时调用方要等 EOF 到 60s 才返回（实测 60.3s vs 0.3s）。
  #   `disown` 只脱离作业表，不关继承而来的 fd。⇒ ① 三路重定向到 /dev/null；② 改用独立 argv 的
  #   `bash -c`（清理进程不再顶着本脚本 argv，`pgrep -f nao-fleet.sh` 无残留命中）。
  #   不用 setsid：macOS 无该 bin，`… || true` 会静默跳过清理（BR1 缩水）。清理窗口 60s 不缩短。
  bash -c 'sleep 60; rm -f -- "$1"' _ "$prompt_file" >/dev/null 2>&1 </dev/null & disown 2>/dev/null || true

  # 拉起：门面 term_spawn 以**显式三态**回报（T539/BR2 · B2 herdr 实现）；
  #   每目标恰一行结果行：成功 → 唯一一条 `[herdr] 已拉起 …` · 跳过/失败 → 不打印成功行。
  #   `|| rc=$?` 是 set -e 下的必需写法（|| 列表豁免 errexit）；函数返回值即结果契约。
  local rc=0
  _TERM_SPAWN_PANE=""
  term_spawn "$name" "$inner" "$repo" "$force" "$label" "$group" "$task" || rc=$?
  case "$rc" in
    "$SPAWN_RC_OK")   SPAWN_OK=$((SPAWN_OK + 1))
                      # T573：记录↔角色/任务绑定（供保留分级用；失败只 warn，不阻断启动）
                      fleet_sessions_note_spawn "$name" "${role_id:-}" "${task:-}" "$repo" || true
                      log "[$(term_label)] 已拉起 $name @ $repo${model:+（model=$model）}${_TERM_SPAWN_PANE:+（pane=$_TERM_SPAWN_PANE）}"
                      # T548/AC2/AC4：投递点**唯一**（新 pane / 幽灵复用 / --force 重开均经此处恰 1 次）；
                      #   投递失败 ⇒ **rc 仍 0、不计 SPAWN_FAIL**（会话确实可用；计 FAIL 正是本缺陷的假红灯源）
                      #   ！失败必须**默认可见**（一条 warn + error code），`-v` 再补诊断指路。
                      if [[ "$role_id" == "pm" ]] && update_check_enabled; then
                        local derr=""
                        if ! derr="$(term_deliver "$_TERM_SPAWN_PANE" "$NAO_UPDATE_MSG")"; then
                          warn "版本自检投递失败（$name ⇒ pane=${_TERM_SPAWN_PANE:-?}；${derr:-未知错误}）—— 会话仍可用，本次**不计失败**（自检只读非阻塞）"
                          if [[ "$VERBOSE" == "true" ]]; then
                            warn "  · 诊断：herdr --session ${HERDR_SESSION:-<session>} agent explain ${_TERM_SPAWN_PANE:-<pane>}"
                            warn "  · 常见原因：启动浮层（What's New / 信任提示）吃按键 / agent 处于 blocked（agent_blocked）"
                          fi
                        fi
                      fi ;;
    "$SPAWN_RC_SKIP") SPAWN_SKIP=$((SPAWN_SKIP + 1)) ;;
    *)                SPAWN_FAIL=$((SPAWN_FAIL + 1)) ;;   # 3 = fail；未知值按失败处理（宁可少报成功）
  esac
}

# 仓身份（T554 worktree 同键）：git 仓 = git-common-dir 的物理路径（worktree/主仓同值）；
#   非 git 仓 = 物理路径。用于「同仓 worktree 复用同一 workspace」，同时不把**同名不同仓**误并。
_repo_identity() {  # <path> → 物理身份串
  local p="${1-}" common="" phys
  [[ -n "$p" ]] || return 0
  phys="$(_fleet_phys "$p")"
  if command -v git >/dev/null 2>&1; then
    common="$(git -C "$p" rev-parse --git-common-dir 2>/dev/null || true)"
  fi
  if [[ -n "$common" ]]; then
    case "$common" in /*) ;; *) common="$phys/${common#./}" ;; esac
    _fleet_phys "$common"
  else
    printf '%s\n' "$phys"
  fi
}

# 本命令的放置行（业务侧缓存；5 列 = space_ref/label/name/handle/cwd）
declare -a ENSURE_PLACE_ROWS=()
_ensure_place_load() { mapfile -t ENSURE_PLACE_ROWS < <(term_place_rows 2>/dev/null || true); }

# 快照内某 space 的 pane cwd 是否**全在**目标仓内（含空 space ⇒ true）
_ensure_ws_panes_in_repo() {  # <space_ref> <repo_phys> → 0 全部在仓内 / 1 有 pane 在仓外
  local wsid="${1-}" repo="${2-}" line _sr _lbl _nm _h c ident
  ident="$(_repo_identity "$repo")"
  for line in "${ENSURE_PLACE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _sr _lbl _nm _h c <<< "$line"
    [[ "$_sr" == "$wsid" ]] || continue
    [[ "$c" == "-" || -z "$c" ]] && continue
    # 同仓 worktree（git common-dir 相同）⇒ 复用；否则必须物理落在目标仓内
    if [[ -n "$ident" && "$(_repo_identity "$c")" == "$ident" ]]; then continue; fi
    repo_contains_path "$repo" "$(_fleet_phys "$c")" || return 1
  done
  return 0
}

# 解析放置 label（仓基键 + 冲突号）：同名 ws 的 pane cwd 全在目标仓内 ⇒ 复用；
#   否则 `<key>2`…`<key>9`；全占 ⇒ 返回 1（调用方 die）。第二个同基键仓在**本批**也走号段。
_ensure_place_label() {  # <base> <repo_phys> → stdout label
  local base="${1-}" repo="${2-}" cand="" n=2 wsid i
  cand="$base"
  [[ -n "$base" ]] || return 1
  while :; do
    # 本批已预留：同 label 不同仓 ⇒ 必须让号（同仓重复目标复用同 label）
    local taken=0 same=0
    for i in "${!_T_RSV_WS[@]}"; do
      [[ "${_T_RSV_WS[$i]}" == *"|$cand" ]] || continue
      # 同 repo 复用同 label（同批多角色落同一仓）；不同 repo 同基键 ⇒ 让号
      if [[ "${_T_RSV_WS[$i]}" == "${repo}|${cand}" ]]; then same=1; break; fi
      taken=1
    done
    (( same )) && { printf '%s\n' "$cand"; return 0; }
    if (( ! taken )); then
      wsid="$(term_place_ws_for_label "$cand")" || return 1
      if [[ -n "$wsid" ]]; then
        if _ensure_ws_panes_in_repo "$wsid" "$repo"; then printf '%s\n' "$cand"; return 0; fi
      else
        printf '%s\n' "$cand"; return 0
      fi
    fi
    (( n > 9 )) && return 1
    cand="${base:0:15}$n"; n=$((n + 1))
  done
}

# 名字是否已占目标槽位（v2 parse 同 role/num；含本批预留）
_ensure_slot_taken() {  # <wsid> <role> <num>
  local wsid="${1-}" role="${2-}" num="${3-}" name out k r t s line
  local want="$role/$num"; want="${want%/}"
  # 本批预留
  local i
  for i in "${!_T_RSV_NAME[@]}"; do
    [[ -z "${_T_RSV_WS[$i]:-}" || "${_T_RSV_WS[$i]}" == "$wsid" ]] || continue
    [[ "${_T_RSV_ROLE[$i]}" == "$role" && "${_T_RSV_NUM[$i]}" == "$num" ]] && return 0
  done
  for line in "${ENSURE_PLACE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _sr _lbl name _h _c <<< "$line"
    [[ -n "$name" ]] || continue
    [[ "$_sr" == "$wsid" ]] || continue
    out="$(fleet_name_parse "$name")"
    [[ "$out" == "OK "* ]] || continue
    IFS=',' read -r k r t s <<< "${out#OK }"
    [[ "$r" == "$role" && "$s" == "$num" ]] && return 0
  done
  return 1
}

# 任务复用（v3）：目标 ws 内已有同 (role, task) 的会话 ⇒ 打印该名字（task 只认元数据；
#   槽位号不承载语义）。v2/legacy 名字仍按解析出的 task 兼容复用（只读面）。
_ensure_task_name_in_ws() {  # <wsid> <role> <task>
  local wsid="${1-}" role="${2-}" task="${3-}" name out k r t s line
  for line in "${ENSURE_PLACE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _sr _lbl name _h _c <<< "$line"
    [[ -n "$name" ]] || continue
    [[ "$_sr" == "$wsid" ]] || continue
    out="$(fleet_name_parse "$name")"
    [[ "$out" == "OK "* ]] || continue
    IFS=',' read -r k r t s <<< "${out#OK }"
    [[ "$r" == "$role" ]] || continue
    [[ "$(fleet_effective_task "$name")" == "$task" ]] || continue
    printf '%s\n' "$name"; return 0
  done
  return 0
}

# 选槽位：派生优先复用已有次槽位（≥2），否则取最小空闲槽位；常驻取最小空闲。全占 ⇒ fail（rc=1）。
_ensure_pick_num() {  # <wsid> <role> <task> <kind> → stdout num（空 = 槽位 1）
  local wsid="${1-}" role="${2-}" task="${3-}" kind="${4-}" n found="" name line out k r t s
  # 收集已占槽位
  local -a occ=()
  for line in "${ENSURE_PLACE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _sr _lbl name _h _c <<< "$line"
    [[ -n "$name" ]] || continue
    [[ "$_sr" == "$wsid" ]] || continue
    out="$(fleet_name_parse "$name")"
    [[ "$out" == "OK "* ]] || continue
    IFS=',' read -r k r t s <<< "${out#OK }"
    [[ "$r" == "$role" ]] && occ+=("${s:-1}")
  done
  local i
  for i in "${!_T_RSV_NAME[@]}"; do
    [[ -z "${_T_RSV_WS[$i]:-}" || "${_T_RSV_WS[$i]}" == "$wsid" ]] || continue
    [[ "${_T_RSV_ROLE[$i]}" == "$role" ]] && occ+=("${_T_RSV_NUM[$i]:-1}")
  done
  # v3：task 不进名字 ⇒ 槽位号只用于区分同 role 多会话，**不得**复用已占槽位
  #   （v2 的「派生复用已有次槽位」会让两个不同 task 撞同一个 `role2` 名）。
  for n in "" 2 3 4 5 6 7 8 9; do
    local hit=0
    for i in "${occ[@]:-}"; do [[ "$i" == "${n:-1}" ]] && { hit=1; break; }; done
    (( hit )) && continue
    printf '%s\n' "$n"; return 0
  done
  return 1
}

cmd_ensure() {
  local force="$1" model="$2" task="$3"
  local i spec role repo key seen k card_arg card_as disp role_id scope_name=""
  local chk_name chk_p vrd
  local _res_ok="" pout_tmp="" _p_kind="" _p_role="" _p_task=""
  local MN="" MANIFEST_ROOT="" MANIFEST_OK=0 rres="" rkind="" base_label="" place="" slot="" wsid=""
  local -a cg_done=() t_names=() t_repos=() t_cards=() t_roles=() t_prompts=() t_nums=() t_kinds=() t_labels=() t_disps=()
  # BR8：parse 的角色事实表（常驻 id）。ensure 不读卡集（不为判重引入额外 glob 与 CARD_SET_MAX 告警）
  fleet_roles_init
  [[ ${#TARGETS[@]} -gt 0 ]] || die "ensure 需要至少一个角色，如: nao-fleet.sh ensure arch rd-fe rd-infra"
  _T_RSV_WS=(); _T_RSV_NAME=(); _T_RSV_ROLE=(); _T_RSV_NUM=(); _DEP_SCOPE_WARNED=()

  # ==== 相位 0：manifest 单次加载（NONE = 合法事实；无 slug 校验 —— D7 已弃用）====
  MANIFEST_ROOT="$(fleet_manifest_root "$PWD")"
  MN="$(fleet_manifest_load "$MANIFEST_ROOT")" \
    || die "ensure 中止：$MANIFEST_ROOT/.agents/fleet.yaml 非法（见上；该怎么改：按报错的文件:行号修字段，或删掉该文件回到无 manifest 语义）"
  fleet_manifest_warn_deprecated "$MN"
  if [[ "$MN" == "NONE" ]]; then
    MN=""
  else
    [[ -n "$MN" ]] || die "ensure 中止：manifest 解析返回空输出（实现缺陷，不得当 NONE）"
    MANIFEST_OK=1
  fi

  # ==== 相位 1a：后端前提 + 放置快照（T554 查询上限：≤1 布局/终端列表）====
  #   app：AC3b 窗口不在跑 ⇒ exit 3（**先于**任何终端创建，不玩「起了再回滚」）
  term_spawn_preflight
  if ! term_place_begin; then
    if [[ "$(term_label)" == "app" ]]; then
      die "ensure 中止：app 放置快照不可用（hc ls / doc.get 失败；核对 desktop app 窗口后重试）"
    fi
    die "ensure 中止：herdr 放置快照不可用（workspace list / pane list 失败；核对 server 后重试）"
  fi

  _ensure_place_load
  fleet_task_map_init
  # ==== 相位 1b：全量解析 + 校验（BR11 两相执行；失败必在建 pane 之前）====
  for i in "${!TARGETS[@]}"; do
    spec="${TARGETS[$i]}"; card_arg="${TARGET_CARD[$i]:-}"; card_as="${TARGET_AS[$i]:-}"
    role=""; repo=""; rkind=""
    if [[ "$spec" == *"@"* ]]; then
      role="${spec%%@*}"; repo="${spec#*@}"
    else
      role="$spec"
    fi
    if [[ -n "$card_arg" ]]; then
      # 下游卡目标：目标 positional 即卡路径（BR11 目标级绑定）
      resolve_card "$role" "$repo"
      # T554：ensure 不读卡集（避免额外 glob）⇒ 本目标的卡 role 当场登记（只影响本命令的 parse 自证）
      [[ -n "${FLEET_ROLE_KIND[$CARD_ROLE]:-}" ]] || FLEET_ROLE_KIND["$CARD_ROLE"]="card"
      if [[ -n "$card_as" ]]; then
        # P10 v2：`--as` 只给常驻形（<role>[<N>]）或旧形自定义后缀；带 `()` 即拒（指路 --task）。
        case "$card_as" in
          *'('*|*')'*) die "--as 不可用：$card_as 含括号（派生 task 用 --task <编号>；--as 只给常驻名或旧形自定义后缀）" ;;
        esac
        local why
        if ! why="$(card_name_problem "$card_as")"; then
          die "--as 不可用：$card_as —— $why（该怎么办：用卡 role、<卡 role><N>（N=2..9）或 <卡 role>-<后缀>）"
        fi
        # D9（v2）：--as 必须 = 卡 role、以 `<卡 role>-` 为前缀（旧形），或 = `<卡 role><N>`
        if [[ "$card_as" != "$CARD_ROLE" && "$card_as" != "$CARD_ROLE"-* && ! "$card_as" =~ ^"$CARD_ROLE"[2-9]$ ]]; then
          die "--as 不可用：$card_as 不以卡 role（$CARD_ROLE）为前缀 —— 改名不得脱离卡 role 前缀（fleet 按前缀识别身份），用 <role>-<suffix> 或 <role><N>"
        fi
        disp="$card_as"
      else
        disp="$CARD_ROLE"
      fi
      repo="$CARD_REPO"
      _dep_warn_scope_file "$repo"
      base_label="$(place_key_label "$repo")"
      [[ -n "$base_label" ]] || die "ensure 中止：放置键计算失败（repo=$repo；实现缺陷，不得回落空值）"
      place="$(_ensure_place_label "$base_label" "$repo")" \
        || die "ensure 中止：workspace label 号段已满（base=$base_label，2..9 全占；该怎么办：先清理空 workspace 或 close 无用会话）"
      # 槽位：--as 已显式给名字 ⇒ 不参与自动槽位；否则按卡 role 取空闲槽位
      slot=""
      if [[ -z "$card_as" ]]; then
        wsid="$(term_place_ws_for_label "$place")"
        # 卡会话同 role+task 已在 ⇒ same（复用名字；相位 2 判重跳过）；否则取空闲槽位
        if [[ -n "$task" ]]; then
          disp="$(_ensure_task_name_in_ws "$wsid" "$CARD_ROLE" "$task")"
        else
          disp=""
        fi
        if [[ -n "$disp" ]]; then
          slot=""; pout_tmp="$(fleet_name_parse "$disp")"
          case "$pout_tmp" in "OK "*) IFS=',' read -r _p_kind _p_role _p_task slot <<< "${pout_tmp#OK }" ;; esac
        else
          slot="$(_ensure_pick_num "$wsid" "$CARD_ROLE" "$task" "card")" \
            || die "ensure 中止：角色槽位已满（$CARD_ROLE 的 2..9 全占；该怎么办：先 close 无用会话再重试）"
          disp="$(fleet_name_build card "$CARD_ROLE" "$slot")"
        fi
      fi
      t_names+=("$CARD_ROLE"); t_repos+=("$CARD_REPO"); t_cards+=("$CARD_PATH"); t_roles+=("${CARD_ROLE:-}")
      t_nums+=("$slot"); t_kinds+=("card"); t_labels+=("$place"); t_disps+=("$disp")
      t_prompts+=("")
      if $VERBOSE; then log "name=$disp · placement=$place @ $CARD_REPO（来源：仓基键）"; fi
    else
      [[ -z "$card_as" ]] || die "--as 只能用于同一目标的 --card 之后（如 ensure --card <卡> --as <会话名>）"
      # T554：目标名可显式带槽位（`ensure rd-be2`）—— 相位 1 尊重该槽位（否则测试/用户无法定点）
      local forced_num="" _sp="" _spk="" _spr="" _spt=""
      _sp="$(fleet_name_parse "$role")"
      case "$_sp" in
        "OK resident,"*) IFS=',' read -r _spk _spr _spt forced_num <<< "${_sp#OK }"; role="$_spr" ;;
      esac
      resolve_role "$role"
      scope_name=""
      if (( MANIFEST_OK )); then
        if [[ -n "$repo" ]]; then
          if ! rres="$(fleet_repo_resolve "$repo" <<< "$MN")"; then
            die "ensure 中止：目标段 @$repo 不可判定（见上一条列出的可用 code；也可用 @main 指主仓 / @<仓路径>）"
          fi
          IFS=$'\t' read -r _res_ok rkind repo <<< "$rres"
        else
          repo="$MANIFEST_ROOT"; rkind="main"
        fi
      else
        if [[ -n "$repo" ]]; then
          if [[ "$repo" == "main" ]]; then
            die "ensure 中止：@main 需要 manifest（本仓无 .agents/fleet.yaml）；改用 @<仓路径> 或直接 cd 到目标仓"
          fi
          [[ -d "$repo" ]] || die "ensure 中止：@$repo 未命中（无 manifest 时 @ 只接受既有仓路径）"
          repo="$(_fleet_phys "$repo")"
          rkind="path"
        else
          repo="${ROLE_WS[$NAME]:-$PWD}"
          repo="$(_fleet_phys "$repo")"
        fi
      fi
      [[ -d "$repo" ]] || die "ensure 中止：目标仓不存在（$repo）"
      _dep_warn_scope_file "$repo"
      base_label="$(place_key_label "$repo")"
      [[ -n "$base_label" ]] || die "ensure 中止：放置键计算失败（repo=$repo；实现缺陷，不得回落空值）"
      place="$(_ensure_place_label "$base_label" "$repo")" \
        || die "ensure 中止：workspace label 号段已满（base=$base_label，2..9 全占；该怎么办：先清理空 workspace 或 close 无用会话）"
      wsid="$(term_place_ws_for_label "$place")"
      if [[ -n "$forced_num" ]]; then
        slot="$forced_num"
        if [[ -n "$task" ]]; then disp="$(fleet_name_build derived "$NAME" "$slot")"
        else disp="$(fleet_name_build resident "$NAME" "$slot")"; fi
      elif [[ -n "$task" ]]; then
        # 同 (role, task) 元数据已在 ⇒ same（复用该名字；相位 2 判重会跳过）
        disp="$(_ensure_task_name_in_ws "$wsid" "$NAME" "$task")"
        if [[ -n "$disp" ]]; then
          slot=""; pout_tmp="$(fleet_name_parse "$disp")"
          IFS=',' read -r _p_kind _p_role _p_task slot <<< "${pout_tmp#OK }"
        else
          slot="$(_ensure_pick_num "$wsid" "$NAME" "$task" "derived")" \
            || die "ensure 中止：角色槽位已满（$NAME 的 2..9 全占；该怎么办：先 close 无用会话再重试）"
          disp="$(fleet_name_build derived "$NAME" "$slot")"
        fi
      else
        slot="$(_ensure_pick_num "$wsid" "$NAME" "" "resident")" \
          || die "ensure 中止：角色槽位已满（$NAME 的 2..9 全占；该怎么办：先 close 无用会话，如 close ${NAME}2）"
        disp="$(fleet_name_build resident "$NAME" "$slot")"
      fi
      t_names+=("$NAME"); t_repos+=("$repo"); t_cards+=(""); t_roles+=("$NAME")
      t_nums+=("$slot"); t_kinds+=("resident"); t_labels+=("$place"); t_disps+=("$disp")
      t_prompts+=("$PROMPT")
      if $VERBOSE; then
        log "name=$disp · placement=$place @ $repo（来源：仓基键；kind=$([ -n "$task" ] && printf derived || printf resident)）"
      fi
    fi
    # 本批预留（同批两个 pm ⇒ pm / pm2；同批多角色落同一仓复用一个 label）
    _T_RSV_WS+=("${repo}|${place}"); _T_RSV_NAME+=("$disp")
    _T_RSV_ROLE+=("$role"); _T_RSV_NUM+=("${slot:-1}")
    # 名字复核：builder 造得出 ≠ parse 认得回（建 pane 之前 fail loud ⇒ BR6 零副作用）
    chk_p="$(fleet_name_parse "$disp")"
    # `--as` 的旧形自定义后缀是**只读合法名**（起得来、按 legacy 解析）⇒ 允许 LEGACY OK
    if [[ "$chk_p" != "OK "* && "$chk_p" != "LEGACY OK "* ]]; then
      die "ensure 中止：目标名不可解析 —— 「$disp」（name ≤48 · role 段含槽位 ≤32（卡）· 于 $( [ -n "$task" ] && printf 'task %s' "$task" || printf '常驻形' )）。该怎么办：缩短 task 编号或改用更短的卡 role"
    fi
  done

  # ==== 相位 2：拉起（判重 + codegraph + spawn 逐目标）====
  for i in "${!t_names[@]}"; do
    repo="${t_repos[$i]}"
    disp="${t_disps[$i]}"
    # CodeGraph 索引健康（同 repo 只查一次，不阻塞拉起）
    key="$repo"; seen=0
    for k in "${cg_done[@]:-}"; do [[ "$k" == "$key" ]] && seen=1; done
    if (( ! seen )); then codegraph_state "$repo" 1 "$(basename "$repo")"; cg_done+=("$key"); fi
    if [[ "$force" != "true" ]]; then
      vrd="$(running_verdict "$disp" "$repo")"
      if [[ "$vrd" == "same" ]]; then
        if [[ "$(term_label)" == "app" ]]; then
          warn "$disp 已在运行（终端 name + status 事实命中），跳过；确需重开请加 --force"
        elif [[ "$NAO_TERMINAL" == "herdr" ]]; then
          warn "$disp 已在运行（pane label + 结构化事实命中），跳过；确需重开请加 --force"
        else
          warn "$disp 已在运行（终端标题/名册命中），跳过；确需重开请加 --force"
        fi
        SPAWN_SKIP=$((SPAWN_SKIP + 1))
        continue
      fi
      # T563/AC2（fail-closed）：`unknown` = 名字命中但**放置归属无法确认**（集成缺 labels）。
      #   此时既不能判「已在运行」也不能判「可拉起」：自动拉起会造出同名第二个终端，后续 close 因同名拒。
      #   ⇒ 拒绝 + **恰一行指路**（不静默：本分支不重定向 stderr；`--force` 是明确的人工确认）。
      if [[ "$vrd" == "unknown" ]]; then
        warn "$disp 无法确认放置归属（集成缺 labels）⇒ 不自动拉起；人工核对该终端后在 herdr desktop app 确认，确需重开请加 --force 重试"
        SPAWN_FAIL=$((SPAWN_FAIL + 1))
        continue
      fi
    fi
    if [[ -n "${t_cards[$i]}" ]]; then
      spawn_one "$disp" "$repo" "$model" "${t_cards[$i]}" "${t_roles[$i]:-}" "" "$force" "${t_labels[$i]}" "" "$task"
    else
      spawn_one "$disp" "$repo" "$model" "" "${t_roles[$i]:-}" "${t_prompts[$i]:-}" "$force" "${t_labels[$i]}" "" "$task"
    fi
  done
  term_place_end
  # T573：顺手清理过期会话记录（幂等；失败只 warn、不改 rc；真删了才打一行）
  fleet_sessions_purge --quiet || warn "会话记录清理失败（不影响本次 ensure 结果）"
  # 恰一行摘要，三类计数（成功/跳过/失败）
  if (( SPAWN_OK + SPAWN_SKIP + SPAWN_FAIL > 0 )); then
    log "已拉起 ${SPAWN_OK} 个会话（成功 ${SPAWN_OK} / 跳过 ${SPAWN_SKIP} / 失败 ${SPAWN_FAIL}）；就绪后在线状态用 nao-fleet.sh status 查看"
  fi
  # T563/AC5（行为契约变更，PM 裁定 rc=1）：判据 = **实际拉起成功数 == 0 且确有失败**。
  #   ① 纯跳过（全都在运行）⇒ rc=0：幂等重跑 effect=0 不得报失败；
  #   ② 全败 / 失败且零成功 ⇒ rc=1（调用方/CI 能据此判红），并给一行汇总；
  #   ③ 不复用 rc=2（用法/后端拒绝）与 rc=3（前置不可用）—— 三者语义互斥。
  if (( SPAWN_OK == 0 && SPAWN_FAIL > 0 )); then
    warn "全部 ${#t_names[@]} 个角色均未拉起（成功 0 / 跳过 ${SPAWN_SKIP} / 失败 ${SPAWN_FAIL}）；逐条原因见上"
    return 1
  fi
}
