# =============================================================================
# fleet/lib/term.sh — 终端后端门面（18 函数）+ 终端常量
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core（log/warn/die、路径谓词）
# **NAO_TERMINAL 唯一赋值点在本文件**（跨模块总和 = 1；SELF_SH 指向本文件）。
# 业务层只调门面函数；herdr/app 实现在同层文件里，由门面分派。
# =============================================================================
# 本文件自身路径（#124）：端前提 warn 需从**唯一赋值点**（本文件的 NAO_TERMINAL）解析默认后端，
#   故要读回自己的源码。禁在别处重述默认值字面量（tests/t4 的跨模块 `grep -cE '^NAO_TERMINAL='`
#   总和 = 1 静态 lint 亦依赖唯一性；SELF_SH 由 tests/t4/lib.sh 断言指向本文件）。
SELF_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# ---- 终端后端（#96 二期 B1 · PRD 附二「门面 + 双实现并存」）----
# 默认值**唯一赋值点**：全脚本 `grep -cE '^NAO_TERMINAL='` 必须恰 1 处（tests/t4 静态 lint 断言）。
# 三期 P2（2026-11-11）：**herdr 转默认**只改这一行（B1 立的 lint 就是为这一步准备的）。
#   `:-` 语义 ⇒ 未设与空串都落 herdr；本版起**唯一后端程序 = herdr**（形态 TUI / app；旧回退面已删，其他值 ⇒ 守卫 exit 2）。
NAO_TERMINAL="${NAO_TERMINAL:-herdr}"
# herdr 破坏性变更的唯一硬判据（version 只打印不比较：版本串比较脆）
TERM_HERDR_PROTOCOL="22"
# BR6：起 herdr server 前必须清掉的**宿主终端句柄**。名字表放通用区（herdr 实现区禁出现该字面量：
#   tests/t4/lib.sh::t4_scan_term_herdr_forbidden），由 `_term_herdr_exec` 的 server-start 模式消费。
_TERM_HOST_HANDLE_VARS=(TMUX TMUX_PANE TMUX_TMPDIR)
# B2：herdr 就绪门轮询 —— **wall-clock 上限**（默认 5s，可用 NAO_HERDR_READY_TIMEOUT_MS 覆盖）
#   轮询间隔 100ms + 每轮上限保护；**禁**固定 sleep 与 `agent wait --until idle`（已 idle 时 6ms 假阳性）。
TERM_READY_POLL_MAX=50
TERM_READY_POLL_INT=0.1
TERM_READY_TIMEOUT_MS="${NAO_HERDR_READY_TIMEOUT_MS:-5000}"
[[ "$TERM_READY_TIMEOUT_MS" =~ ^[0-9]+$ ]] || TERM_READY_TIMEOUT_MS=5000
# 三期 P1（AC3.2 J1/J5）：herdr **不报**空间不足（split 从不失败、pane 可被压到 0 行、resize 静默无效）
#   ⇒ rc 不可作判据，必须**自测** `pane layout` 的 rect。阈值 = 常量（可覆盖）：不足只 warn（rc 保持 0），
#   0 尺寸 pane（读不了内容）计 SPAWN_FAIL（否则摘要说「成功 7」而实际不可用）。
TERM_MIN_COLS="${NAO_TERM_MIN_COLS:-60}"
TERM_MIN_ROWS="${NAO_TERM_MIN_ROWS:-10}"
[[ "$TERM_MIN_COLS" =~ ^[0-9]+$ ]] && (( TERM_MIN_COLS > 0 )) || TERM_MIN_COLS=60
[[ "$TERM_MIN_ROWS" =~ ^[0-9]+$ ]] && (( TERM_MIN_ROWS > 0 )) || TERM_MIN_ROWS=10
# B2：ghost pane 复用前只允许把命令送进**交互式 shell**（前台非 shell ⇒ 拒绝注入，fail loud）
TERM_SHELL_NAMES=(bash zsh sh dash fish ksh mksh tcsh csh nu elvish xonsh)
# herdr 快照缓存路径（#96 B1）：**每命令一份**。`$$` 在子 shell 里不变 ⇒ 快照由任一子 shell 建好后，
#   其余子 shell 与父 shell 读同一份（status 另在入口显式 prime 一次，保证「每命令 ≤1 次 pane list」）。
_TERM_SNAP_TOKEN="$$.$RANDOM$RANDOM"
_TERM_SNAP_PATH="${TMPDIR:-/tmp}/nao-fleet-term-snap.${_TERM_SNAP_TOKEN}"
# 后端私有事实行（13 列）缓存：只供实现层（liveness/reclaim/project5）读，业务层不可见。
_TERM_FACT_PATH="${TMPDIR:-/tmp}/nao-fleet-term-facts.${_TERM_SNAP_TOKEN}"
trap 'rm -f "${_TERM_SNAP_PATH:-}" "${_TERM_FACT_PATH:-}" 2>/dev/null || true' EXIT

# =============================================================================
# 终端后端门面（#96 二期 B1 · PRD 附二「门面 + 双实现并存」）
#
#   契约：**业务区只调** term_require / term_snapshot / term_liveness / term_argv /
#         term_spawn / term_deliver / term_session_start / term_reclaim / term_cleanup（+ 纯谓词 term_deliverable）。
#         实现只有 herdr 一份（静态 lint：tests/t4/lib.sh::t4_scan_tmux_residue 禁旧面复活）。
#   默认值唯一：**常量区的 `NAO_TERMINAL` 赋值就是全脚本唯一的赋值点**（此处不重述默认值字面量 ——
#   重述会与常量区脱钩把注释写成谎话；值只认常量区，grep 判据见 tests/t4 的 `grep -cE '^NAO_TERMINAL='`）。
#   herdr 侧纪律（BR2/BR3/BR6）：身份取 pane.label（+ argv --name 交叉校验）、归属取
#         pane.cwd/foreground_cwd（谓词复用 repo_contains_path）、忙闲取 agent_status +
#         state_change_seq（权威源 = pane list / agent list；`agent explain` 只作诊断、禁作判据）；
#         **一律不读终端标题**，也**不把宿主 tmux 的句柄变量当证据** —— 从 tmux shell 起的
#         herdr server 会把外层句柄渗进 pane（spike 实测），拿来判身份必串台。
#   rc 语义：4 = 保留（B3 后无未实现子命令）；1 = 已执行但失败；3 = 前提不满足；2 = 用法守卫。
# >>> term-facade BEGIN
# 唯一后端程序 = herdr（形态 TUI / desktop app）（ADR 2026-11-22-herdr-only · supersede 2026-10-27-strict-tmux-pi）
#   后端身份 = **常量而非分支**：herdr 是唯一后端程序。`NAO_TERMINAL` 只接受 herdr/app（其他值 fail loud，不静默降级）：
#   未设/空串/herdr ⇒ 放行；其余（含旧回退值）⇒ stderr 恰 1 行 + exit 2（命令未执行，零副作用）。
#   契约：**业务区只调** term_require / term_snapshot / term_liveness / term_argv /
#         term_spawn / term_deliver / term_session_start / term_reclaim / term_cleanup（+ 纯谓词 term_deliverable）。
#   默认值唯一：**常量区的 `NAO_TERMINAL` 赋值就是全脚本唯一的赋值点**（此处不重述默认值字面量 ——
#   重述会与常量区脱钩把注释写成谎话；值只认常量区，grep 判据见 tests/t4 的 `grep -cE '^NAO_TERMINAL='`）。
#   herdr 侧纪律（BR2/BR3/BR6）：身份取 pane.label（+ argv --name 交叉校验）、归属取
#         pane.cwd/foreground_cwd（谓词复用 repo_contains_path）、忙闲取 agent_status +
#         state_change_seq（权威源 = pane list / agent list；`agent explain` 只作诊断、禁作判据）；
#         **一律不读终端标题**，也**不把宿主 tmux 的句柄变量当证据** —— 从 tmux shell 起的
#         herdr server 会把外层句柄渗进 pane（spike 实测），拿来判身份必串台。
#   rc 语义：1 = 已执行但失败；3 = 前提不满足；2 = 用法守卫（旧调用面：非 herdr 的 NAO_TERMINAL / cleanup -S）。
term_backend() {  # 守卫（无输出 = 放行）；非法/已移除值 ⇒ 单行 stderr + exit 2
  case "${NAO_TERMINAL:-}" in
    ''|herdr) return 0 ;;
    app) return 0 ;;
    tmux)
      printf '[fleet] 已移除 tmux 后端：本版后端 = herdr（默认，TUI）/ app（herdr desktop app）—— 删掉 NAO_TERMINAL 或置空后重试（迁移见 v0.28.0 发布说明）\n' >&2
      exit 2 ;;
    *)
      printf '[fleet] NAO_TERMINAL=%s 非法：允许值 = herdr（默认，TUI）/ app（herdr desktop app）；未设/空串 = herdr\n' "$NAO_TERMINAL" >&2
      exit 2 ;;
  esac
}

# 后端名（输出面用；herdr 路径的文案逐字不变 ⇒ AC1）
term_label() { if _term_app_backend; then printf 'app\n'; else printf 'herdr\n'; fi; }

# 事实构建分派（13 列，后端私有；只给实现层与 project5 用）
_term_backend_facts() { if _term_app_backend; then _term_app_facts; else _term_herdr_facts; fi; }
# 5 列投影分派（<name>\t<status>\t<cwd>\t<handle>\t<task>）
_term_backend_project5() { if _term_app_backend; then _term_app_project5; else _term_herdr_project5; fi; }

# 后端私有事实行（每命令一份；业务层禁调）
_term_facts() {
  local f="${_TERM_FACT_FILE:-${_TERM_FACT_PATH:-${TMPDIR:-/tmp}/nao-fleet-term-facts.$$}}"
  if [[ -e "$f" ]]; then _TERM_FACT_FILE="$f"; cat "$f"; return 0; fi
  if ! _term_backend_facts > "$f"; then
    rm -f "$f" 2>/dev/null || true; _TERM_FACT_FILE=""
    return 1
  fi
  _TERM_FACT_FILE="$f"
  cat "$f"
}

# ---- 1/4 前提闸门 ----
term_require() { if _term_app_backend; then _term_app_require; else _term_herdr_require; fi; }

# ensure 前的后端前提（app = AC3b「窗口不在跑 ⇒ exit 3」；herdr 无此概念 ⇒ 无操作）
term_spawn_preflight() { if _term_app_backend; then _term_app_spawn_preflight; else return 0; fi; }

# ---- 2/4 快照（5 列中性投影；每命令 ≤1 次 pane list / agent list；落临时文件）----
# 每行：<name>\t<status>\t<cwd>\t<handle>\t<task>
#   status ∈ alive|working|idle|unknown；cwd = 归属 cwd；handle 不透明；空值 `-`；无身份整行省略。
#   后端私有 13 列事实只在实现层（_term_facts / project5）可见，业务层读完即弃。
term_snapshot() {
  local f="${_TERM_SNAP_FILE:-${_TERM_SNAP_PATH:-${TMPDIR:-/tmp}/nao-fleet-term-snap.$$}}" facts=""
  # 判据用「文件存在」而非「非空」：无舰队会话时快照合法为空（用 -s 会每调用重建）。
  if [[ -e "$f" ]]; then _TERM_SNAP_FILE="$f"; cat "$f"; return 0; fi
  find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nao-fleet-term-snap.*' -mmin +120 -delete 2>/dev/null || true
  facts="$(_term_facts)" || { rm -f "$f" 2>/dev/null || true; _TERM_SNAP_FILE=""; return 1; }
  if ! printf '%s\n' "$facts" | _term_backend_project5 > "$f"; then
    rm -f "$f" 2>/dev/null || true; _TERM_SNAP_FILE=""
    return 1
  fi
  _TERM_SNAP_FILE="$f"
  cat "$f"
}

# ---- 3/4 在线判定 → "<verdict>\t<state>\t<seq>\t<hook_authority>" ----
#   verdict：online | absent | ghost | dead | mismatch | integration-missing
#   阶梯（定序，避免一条残留同时进多桶）：absent → ghost → dead → mismatch →
#   integration-missing → online；`hook_authority` = agent list 的 screen_detection_skipped
#   （1 = 状态来自生命周期 hook（可信）/ 0 = 屏幕启发式或缺失（保守不可投递））。
# 归属 label 投影（T595-B）：每行 `<name>\t<nao.repo>`（缺失 ⇒ `-`）。只读快照，零额外后端调用。
term_repo_label_rows() {
  _term_facts 2>/dev/null | awk -F'\t' 'NF>=14 && $1 != "" { printf "%s\t%s\n", $1, ($14 == "" ? "-" : $14) }' | awk '!seen[$0]++'
}

term_liveness() {  # <name> [repo]
  if _term_app_backend; then _term_app_liveness "${1-}" "${2-}"; else _term_herdr_liveness "${1-}" "${2-}"; fi
}

# ---- 4/4 前台 argv（取全部前台进程 → 每行 "process-name<TAB>argv"；不得用 ps 兜底）----
term_argv() {  # <pane_id>
  if _term_app_backend; then _term_app_argv "${1-}"; else _term_herdr_argv "${1-}"; fi
}

# ---- 5/8 放置（三期 P1 布局 A）：1 workspace/仓 + 1 tab/角色 ----
# tab label = 角色名，每 tab 恰 1 pane（结构判据，零几何算式）；既有 pane 若在共享 tab 里
#   ⇒ `pane move --new-tab` + `tab rename` 迁移（pane_id 不变、被搬空的 tab 由 herdr 自动关闭）。
# 返回三态码（SPAWN_RC_*）：0 成功 · 2 跳过 · 3 失败（含就绪超时 / 0 尺寸 pane；调用方计入 SPAWN_FAIL）。
# 成功时**必须**回填 `_TERM_SPAWN_PANE`（T548 投递点依赖它）。
term_spawn() {  # <name> <inner> <repo> [force] [label] [group] [task] [repo_key]
  # T595-B：第 8 参 `repo_key` = 仓基键（ensure 相位 1 算定，**spawn 内禁止重算** —— D1 判据）
  if _term_app_backend; then _term_app_spawn "${1-}" "${2-}" "${3-}" "${4:-false}" "${5-}" "${6-}" "${7-}" "${8-}"
  else _term_herdr_spawn "${1-}" "${2-}" "${3-}" "${4:-false}" "${5-}" "${6-}" "${7-}" "${8-}"; fi
}

# ---- 6/8 起 server（B2 · BR6）：唯一生产入口 ----
term_session_start() {  # <session>
  if _term_app_backend; then
    # app 无「起 server」：core 归桌面版所有（起/停 core = 操作用户窗口 ⇒ 拒绝）
    printf '[fleet] session-start 不适用于 app 后端：core 由 herdr desktop app 管理（打开 app 即就绪）—— 本命令只用于 herdr TUI 后端\n' >&2
    exit 2
  fi
  _term_herdr_session_start "${1-}"
}

# ---- 5.5/8 投递（T548/Issue #140）：就绪后把**下游版本自检**作为一条用户消息送进已就绪会话 ----
#   为什么单独一门面：**只在 spawn 成功后**才允许调用（就绪门语义不放宽 —— 自检不再进 argv，见 spawn_one）。
#   契约：0 = 已投递 · 1 = 投递失败（**调用方不计 SPAWN_FAIL**：会话确实可用，自检只读非阻塞）。
#     失败时 stdout 给一行可粘贴的诊断（error code），供调用方 warn。
term_deliver() {  # <pane_id> <message>
  if _term_app_backend; then _term_app_deliver "${1-}" "${2-}"; else _term_herdr_deliver "${1-}" "${2-}"; fi
}

# ---- 7/8 回收（B3）：句柄层（定位 / self 判据 / liveness / 忙闲证据 / 回收句柄）----
#   共用闸门层（tasks-state、subagent 拒收、目标解析、--force）仍在 cmd_close，**不动**。
#   返回 0 = 已回收 / 未运行（幂等成功）；1 = 拒绝或已执行但失败（含 effect 未达成）。
term_reclaim() {  # <name> <repo> <force> <core> <scope> <ensure-target>
  if _term_app_backend; then _term_app_reclaim "${1-}" "${2-}" "${3:-false}" "${4-}" "${5-}" "${6-}"
  else _term_herdr_reclaim "${1-}" "${2-}" "${3-}" "${4-}" "${5-}" "${6-}"; fi
}

# ---- 8/8 拆场（B3 姊妹入口）：herdr = session stop+delete ----
#   herdr 的 stop **非幂等**（第二次 rc=1）⇒ 判 **effect** 不看 rc；default 一律拒（BR9）。
term_cleanup() {  # <herdr-session> [force]
  if _term_app_backend; then _term_app_cleanup "${1-}" "${2:-false}"; else _term_herdr_cleanup "${1-}" "${2:-false}"; fi
}

# ---- 9/9 当前终端会话名（诊断行用）----
term_session_name() { if _term_app_backend; then printf '%s\n' "${HC_SCOPE:-}"; else printf '%s\n' "${HERDR_SESSION:-}"; fi; }

# ---- 放置面（中性）：begin/end/rows/ws_for_label；业务层禁见任何 _TERM_PLACE_* ----
term_place_begin() {  # → 0 已建 / 1 不可用
  if _term_app_backend; then _term_app_place_begin; else _term_herdr_place_begin; fi
}
term_place_end() {  # 幂等
  if _term_app_backend; then _term_app_place_end; else _term_herdr_place_end; fi
}
term_place_rows() {  # 每行 <space_ref>\t<label>\t<name>\t<handle>\t<cwd>；空值 `-`
  if _term_app_backend; then _term_app_place_rows; else _term_herdr_place_rows; fi
}
term_place_ws_for_label() {  # <label> → space_ref（未命中空 + rc0；未 begin ⇒ rc1 + stderr）
  if _term_app_backend; then _term_app_place_ws_for_label "${1-}"; else _term_herdr_place_ws_for_label "${1-}"; fi
}

# ---- 诊断面（check 用）：后端 schema 谓词 + app 端前提（中性门面，业务不直连实现）----
term_api_schema() {  # → 后端 schema 输出（不可用 ⇒ rc1）
  if _term_app_backend; then _term_app_exec schema; else _term_herdr_exec api schema; fi
}
term_check_premise() {  # app 端前提 warn-only（app 后端或 app 终端内）；herdr TUI 无输出
  if _term_app_backend || _term_app_context; then
    if _term_app_context && ! _term_app_backend; then
      printf '  · 检测到 herdr desktop app 终端（HC_* 三件套在场），但 NAO_TERMINAL 未设为 app ⇒ 以下 app 端前提仅供参考\n'
    fi
    _term_app_check_premise
  fi
  return 0
}

# ---- 状态页的 workspace/space 标签表（每行 "<id>\t<label>"）----
term_ws_label_rows() {
  if _term_app_backend; then _term_app_ws_label_rows; return 0; fi
  local js obj wid label
  js="$(_term_herdr_exec workspace list 2>/dev/null || true)"
  while IFS= read -r obj; do
    wid="$(_term_json_str "$obj" workspace_id)"; [[ -n "$wid" ]] || continue
    label="$(_term_json_str "$obj" label)"
    printf '%s\t%s\n' "$wid" "$label"
  done < <(_term_json_objs <<< "$js")
}

# ---- BR7 忙闲 → 可投递（纯谓词；事实判定与策略映射分离，B3 close 复用）----
#   idle/done 可投递；working/blocked 不可；unknown 保守不可。
#   `done` 对 pi **不可达**（实测扩展只上报 idle/working/blocked，PaneAgentState 枚举无 done）
#   ⇒ 保留该分支仅为兼容非 pi agent；用例禁伪造 done 当验收。
term_deliverable() {
  case "${1:-}" in
    idle|done) return 0 ;;
    *) return 1 ;;
  esac
}
# <<< term-facade END
