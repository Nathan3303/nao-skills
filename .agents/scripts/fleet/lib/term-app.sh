# =============================================================================
# fleet/lib/term-app.sh — herdr desktop app 第二后端实现（NAO_TERMINAL=app）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term（常量与门面基座）；运行期另调 manifest 命名谓词（既有晚绑定调用，纯搬迁未改）
# 唯一对外入口 = `_term_app_exec`（app 臂 `hc` 命令位的唯一合法点，静态闸守）。
# =============================================================================

# =============================================================================
# app 后端实现（T562 / Issue #168 · ADR 2026-11-24-herdr-app-backend）
#
#   身份：HC_SCOPE + HC_TERMINAL_ID + HC_TERMINAL_SOCKET 三件套（缺任一 ⇒ exit 3，不猜）；
#         socket 必须落在 app core 目录 `$XDG_RUNTIME_DIR/herdr-core/` 下（stale/外贸 env 防串台）。
#   连接：**唯一入口 `_term_app_exec`** —— 注入 `HC_SOCKET=$HC_TERMINAL_SOCKET`
#         （`HC_TERMINAL_SOCKET` 不参与路由；`HC_SESSION` 拼错会静默新建空 core ⇒ 不用它路由）。
#   失败判据：**JSON `error` 字段**，不看 rc（实测 `hc get` 无目标 rc=3 而 `hc get` 缺参 rc=0）。
#   放置：写标签 `herdr.space`/`herdr.tab` → **轮询读 `doc.get herdr-app` 验证终端是否在该 tab 的 root 树**
#         （T565：收养是异步的，立刻读 = 假失败）→ 不成则 kill+rm 回滚 + fail loud 并**分类报因**
#         （目标 space/tab 不存在 vs 收养超时）。放置前先校验目标 space 仍在 doc 里（陈旧 id 不沿用）。
#   目标 space 选择序（T569 · New Terminal 语义）：① 调用者所在 space（`HC_TERMINAL_ID` 的
#         `labels.herdr.space`，且仍在 doc 里）→ ② 仓 folder 匹配（原行为）→ ③ 新建。
#         第 1 层命中时与仓无关：多仓会话可共存于同一 space（归属判定仍取终端标签，不靠 space 唯一性）。
#         `hc ls` 的 `where` 只是展示 label，**不进断言**。
#   忙闲：`status.app` + `status.state`（working/blocked = 忙；idle/done = 可投递；缺失 = unknown）；
#         **无 `state_change_seq` 等价物** ⇒ 快照 seq 位恒 `-`，判据不依赖它。
#   生命周期：`hc run --bg --no-parent --keep`（`--no-parent` 必须：否则父终端结束会带走子终端）；
#         close = `hc kill` → `hc rm`（顺序不可反：live 终端 rm ⇒ rc=1 `kind:live`；kill 幂等）。
#   测试隔离（R1 定论 = ③ 部分隔离）：私有 `XDG_RUNTIME_DIR` + `XDG_STATE_HOME` + `HC_SESSION`
#         起私有 core；**真实收养 / UI 效果属人工验收**（用例 `[SKIP]` 并给理由）。
# >>> term-impl-app BEGIN
# app 契约版本：`hc schema` generation + `doc.get herdr-app` 的 version（低于 10 ⇒ 不支持放置，fail loud）
TERM_APP_SCHEMA_MIN="1"
TERM_APP_DOC_MIN="10"
TERM_APP_LABEL_SPACE="herdr.space"
TERM_APP_LABEL_TAB="herdr.tab"
# 命名契约 v3 元数据（ADR 2026-11-25 决策一）：app 有键值 label ⇒ task + 原始名直接落标签。
TERM_APP_LABEL_TASK="nao.task"
TERM_APP_LABEL_NAME="nao.name"
# 收养轮询（T565/#175 · AC2）：app 的收养是**异步**的 —— 厂方内嵌文档原文：
#   「acknowledge with `pending: true`, then apply after the machine replies」
#   ⇒ 写完标签**立刻**读 doc 必然假失败（用户实机：t10 不在目标 tab 的 root 树里 ⇒ 回滚）。
#   默认 10 次 × 0.5s（上限 5s，不阻塞交互感）；可用 NAO_APP_ADOPT_TRIES / NAO_APP_ADOPT_INTERVAL 覆盖。
#   轮询期间**不重复起终端**（只读 doc；run 只发一次 —— 用例按 hc run 调用次数打钉）。
TERM_APP_ADOPT_TRIES="${NAO_APP_ADOPT_TRIES:-10}"
TERM_APP_ADOPT_INTERVAL="${NAO_APP_ADOPT_INTERVAL:-0.5}"

# 放置快照的 doc 权威集（AC1/T565）：doc 里的 space id + 被判为陈旧（不在 doc）的 space id —— prime 里重建。
declare -A _TERM_APP_DOC_SPACES=()
_TERM_APP_STALE_SPACES=()
_TERM_APP_CALLER_SPACE=""      # T569：调用者所在 space（仅在 doc 里仍存在时采用；prime 重建）
_TERM_VERIFY_STATE=""        # ok | no-space | no-tab | no-term | doc-fail（给分类报因）
_TERM_VERIFY_ATTEMPTS=0      # 实际读回次数（报错带参，不靠猜测）
_TERM_VERIFY_INTERVAL=""     # 规范化后的轮询间隔（非法值回落 0.5 后的**实际**值）

_term_app_backend() { [[ "${NAO_TERMINAL:-}" == "app" ]]; }

# 是否在 desktop app 终端内（三件套任一在场）：check 的 app 端前提体检按此触发 ——
#   用户实机就是「在 app 终端里跑 check，但 NAO_TERMINAL 未设」⇒ 端前提只校验了 pi 版本（#175 事实 3）。
_term_app_context() { [[ -n "${HC_SCOPE:-}${HC_TERMINAL_ID:-}${HC_TERMINAL_SOCKET:-}" ]]; }

# 唯一入口：所有 `hc` 调用经此处（静态闸 tests/t4/lib.sh::t4_scan_app_bare_hc 断言区间内裸调 = 0）
_term_app_exec() {  # <hc 子命令…> → stdout（错误 JSON 也在合流输出里）；rc 原样透传
  local sock="${HC_TERMINAL_SOCKET:-}" rc=0 out=""
  if [[ -z "$sock" ]]; then
    warn "app 后端调用缺 HC_TERMINAL_SOCKET（三件套未齐）—— 拒绝执行（猜 socket 会连错 core）"
    return 3
  fi
  if ! command -v hc >/dev/null 2>&1; then
    warn "app 后端需要 hc 在 PATH（herdr desktop app 的 CLI；装好后重试）"
    return 3
  fi
  out="$(HC_SOCKET="$sock" command hc "$@" 2>&1)" || rc=$?
  printf '%s\n' "$out"
  return "$rc"
}

# JSON 错误判据（BR：hc 有些错误路径 rc=0 ⇒ 只认 `"error":{…}`）
_term_app_payload_ok() {  # <输出> → 0 无 error 字段
  [[ -n "${1-}" ]] || return 1
  ! grep -qE '"error"[[:space:]]*:[[:space:]]*\{' <<< "${1-}"
}

# 字段抽取（紧凑 JSON，一行）
#   **取首个**同名键：`sed '.*"name":"…"'` 是贪婪匹配 ⇒ 会取到 `foreground.name`（= "pi"）而非终端名。
#   awk 按 `"` 切词后只在 `键` 紧跟 `:` 时取值，语义 = 首次出现。
_term_app_field() {  # <json> <键> → 首个字符串值（无则空）
  printf '%s\n' "${1-}" | awk -v k="$2" '{
    n = split($0, a, "\"")
    for (i = 1; i <= n - 2; i++) if (a[i] == k && a[i + 1] == ":") { print a[i + 2]; exit }
  }'
}
_term_app_term_state() {  # <json> → live | finished | 空
  sed -n 's/.*"state":"\(live\|finished\)".*/\1/p' <<< "${1-}" | head -1
}
_term_app_status_state() {  # <json> → status.state（无 status/null ⇒ 空）
  sed -n 's/.*"status":{[^}]*"state":"\([^"]*\)".*/\1/p' <<< "${1-}" | head -1
}
_term_app_status_app() {  # <json> → status.app（无 ⇒ 空；不假设 app 是 status 的键序第一位）
  sed -n 's/.*"status":{[^}]*"app":"\([^"]*\)".*/\1/p' <<< "${1-}" | head -1
}
# 前台进程名：真 hc 的 `get` **没有** `foreground` 块（实测），前台程序在顶层 `agent`
#   （例 `"agent":"pi"`）；替身给 `foreground.name`。两者都认，取首个非空。
_term_app_fg_name() {  # <json> → 前台程序名（无 ⇒ 空）
  local v=""
  v="$(sed -n 's/.*"foreground":{[^}]*"name":"\([^"]*\)".*/\1/p' <<< "${1-}" | head -1)"
  [[ -n "$v" ]] || v="$(sed -n 's/.*"agent":"\([^"]*\)".*/\1/p' <<< "${1-}" | head -1)"
  printf '%s' "$v"
}
_term_app_fg_cwd() {  # <json> → 前台 cwd（真 hc 无该字段 ⇒ 回落终端 cwd）
  local v=""
  v="$(sed -n 's/.*"foreground":{[^}]*"cwd":"\([^"]*\)".*/\1/p' <<< "${1-}" | head -1)"
  [[ -n "$v" ]] || v="$(_term_app_field "${1-}" cwd)"
  printf '%s' "$v"
}

# ---- 前提闸门（M2 / AC3）----
_term_app_require() {
  command -v hc >/dev/null 2>&1 || {
    printf '需要 hc：NAO_TERMINAL=app 要求 herdr desktop app 的 CLI（hc）在 PATH（装好后重试；不想用 app 后端请 unset NAO_TERMINAL）\n' >&2
    exit 3
  }
  local missing=""
  [[ -n "${HC_SCOPE:-}" ]] || missing="HC_SCOPE"
  [[ -n "${HC_TERMINAL_ID:-}" ]] || missing="${missing:+$missing、}HC_TERMINAL_ID"
  [[ -n "${HC_TERMINAL_SOCKET:-}" ]] || missing="${missing:+$missing、}HC_TERMINAL_SOCKET"
  if [[ -n "$missing" ]]; then
    printf '需要 desktop app 终端身份：%s 缺失（app 后端只在其终端内运行；缺参不猜）—— 在 herdr desktop app 的终端里重试（不想用 app 后端请 unset NAO_TERMINAL）\n' "$missing" >&2
    exit 3
  fi
  # socket 必须落在 app core 目录下（与 TUI 的 HERDR_SOCKET_PATH 同形守卫）
  local root="${XDG_RUNTIME_DIR:-}/herdr-core" spp rp
  spp="$(_term_path_norm "$HC_TERMINAL_SOCKET")"
  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    rp="$(_term_path_norm "$root")"
    if [[ "$spp" != "$rp"/* ]]; then
      printf '需要 app core socket：HC_TERMINAL_SOCKET=%s 不在 %s/ 下（stale/外贸 env ⇒ 拒绝，防串台）—— 在 app 终端内重试\n' \
        "$HC_TERMINAL_SOCKET" "$rp" >&2
      exit 3
    fi
  elif [[ "$spp" != */herdr-core/* ]]; then
    printf '需要 app core socket：HC_TERMINAL_SOCKET=%s 不含 /herdr-core/（无法证明属于 app core ⇒ 拒绝）—— 在 app 终端内重试\n' "$HC_TERMINAL_SOCKET" >&2
    exit 3
  fi
  if [[ ! -S "$spp" ]]; then
    printf '需要 app core socket：HC_TERMINAL_SOCKET=%s 不是 socket（desktop app 未运行 / core 已退出？）—— 打开 app 后重试\n' "$spp" >&2
    exit 3
  fi
}

# ensure 前的 app 专属前提（AC3b）：窗口不在跑 ⇒ 收养永不成 ⇒ exit 3，**不许先起终端再回滚**
_term_app_spawn_preflight() {
  if ! command -v herdr-app >/dev/null 2>&1; then
    printf '需要 herdr-app：desktop app 的 CLI 不在 PATH（无法判断窗口是否在跑；装好后重试；不想用 app 后端请 unset NAO_TERMINAL）\n' >&2
    exit 3
  fi
  if ! herdr-app status >/dev/null 2>&1; then
    printf 'desktop app 未在运行：ensure 需要先打开 herdr desktop app 窗口（窗口关闭时新终端永不被收养 ⇒ 本命令不执行）—— 打开后重试（不想用 app 后端请 unset NAO_TERMINAL）\n' >&2
    exit 3
  fi
}

# ---- app 布局文档（doc.get herdr-app）----
# 输出契约（每行，TAB 分隔）：
#   V<TAB><version>
#   S<TAB><space_id><TAB><folder><TAB><space_name>
#   T<TAB><space_id><TAB><tab_id><TAB><tab_name|-><TAB><terminals,csv>
#     ⚠️ tab_name 为空时必须输出占位符 `-`（不能留空）：bash `read` 对 IFS 里的空白字符
#     （TAB）会**压缩连续分隔符** ⇒ 空 name 会让 terminals 左移一格、第 5 字段读成空，
#     收养判据随即假失败（真机 app 的 space/tab 默认没有名字，2026-11-25 实机踩到：
#     doc 里 space/tab/终端全对，verify 仍判 no-term ⇒ 每次 ensure 都回滚）。
_term_app_doc_rows() {
  local raw="" rc=0 val="" js=""
  raw="$(_term_app_exec connect <<< '{"jsonrpc":"2.0","id":1,"method":"doc.get","params":{"name":"herdr-app"}}')" || rc=$?
  if (( rc != 0 )) || ! _term_app_payload_ok "$raw"; then
    warn "doc.get 失败：$(printf '%s' "${raw:-<空输出>}" | head -c 200)"
    return 1
  fi
  if ! command -v node >/dev/null 2>&1; then
    warn "app 后端需要 node 解析布局文档（nao-skill 自带 node 依赖；核验 PATH）"
    return 1
  fi
  js='let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{let j;try{j=JSON.parse(d)}catch(e){console.error("doc.get 输出不可解析");process.exit(1)}let r=j.result||{};let v=r.value;if(!v){console.log("V\t0");return}console.log("V\t"+(r.version||0));const walk=(n,acc)=>{if(!n||typeof n!=="object")return;if(Array.isArray(n)){for(const x of n)walk(x,acc);return}if(typeof n.terminal==="string")acc.push(n.terminal);for(const k of Object.keys(n)){if(k!=="terminal")walk(n[k],acc)}};for(const s of (v.spaces||[])){console.log(["S",s.id,s.folder||"",s.name||""].join("\t"));for(const t of (s.tabs||[])){const acc=[];walk(t.root,acc);console.log(["T",s.id,t.id,(t.name||"-"),acc.join(",")].join("\t"))}}})'
  if ! val="$(printf '%s' "$raw" | node -e "$js" 2>&1)"; then
    warn "doc.get 解析失败：$(printf '%s' "${val:-<空>}" | head -c 200)"
    return 1
  fi
  printf '%s\n' "$val"
}

# doc 契约探测（R2/AC8）：版本不足或无 spaces ⇒ fail loud（不当作「空布局」继续）
_term_app_doc_guard() {
  local rows="$1" ver=""
  ver="$(awk -F'\t' '$1=="V"{print $2; exit}' <<< "$rows")"
  if [[ -z "$ver" || "$ver" == "0" ]]; then
    warn "app 布局文档不可用（doc.get 返回 value=null）：desktop app 未打开窗口或版本不支持 —— 打开 app 后重试（不按「空布局」继续）"
    return 1
  fi
  if [[ ! "$ver" =~ ^[0-9]+$ ]] || (( ver < TERM_APP_DOC_MIN )); then
    warn "app 布局文档 version=${ver:-?} < ${TERM_APP_DOC_MIN}：当前 desktop app 版本不支持放置契约（升级 app 后重试；不降级为「写标签即成功」）"
    return 1
  fi
  return 0
}

# ---- 快照（12 列，与 herdr 同形，下游零改动）----
# name pane_id terminal_id cwd fg_cwd fg_process agent_status seq session argv_name hook ws_id
#   app 语义：pane_id/terminal_id = 终端地址（tN）；agent_status = status.state；
#   seq 恒 `-`（无 state_change_seq 等价物）；session 位放**终端生命周期**（live/finished）；
#   hook = 1 表示 `reported:true`（状态由程序 OSC 上报，非保守推断）；ws_id = labels.herdr.space。
# 身份还原（ADR 2026-11-25 决策一 / 缺陷 2）：labels.nao.name → 后端 name → argv --name
#   （argv 仅当进程是 pi 且名字可被 fleet_name_parse 识别）。app 的 `name=null` 不再整行省略。
#   注意：调用方须先 fleet_roles_init（status/ensure/close 均如此），否则 parse 表空 ⇒ argv 不通。
_term_app_identity() {  # <get-json> → 身份名（无 ⇒ 空）
  local g="${1-}" nm="" fg="" av=""
  nm="$(_term_app_field "$g" "$TERM_APP_LABEL_NAME")"
  [[ -n "$nm" ]] || nm="$(_term_app_name "$g")"
  # 真 hc 的 name 可为 null：字段抽取会得到 `null` / `null,` 一类裸值 ⇒ 一律视为缺席
  case "$nm" in null|null,*|null\}*) nm="" ;; esac
  if [[ -z "$nm" ]]; then
    fg="$(_term_app_fg_name "$g")"
    if [[ "$fg" == "pi" ]]; then
      av="$(sed -n 's/.*"argv":\[\([^]]*\)\].*/\1/p' <<< "$g" | head -1 | tr -d '"' | sed 's/,/ /g')"
      nm="$(_term_argv_name "$av")"
      case "$(fleet_name_parse "$nm")" in
        "OK "*|"LEGACY OK "*) ;;
        *) nm="" ;;
      esac
    fi
  fi
  printf '%s\n' "$nm"
}

# 终端名（T574/Issue #207）：真 hc 的 `get` 键序**按字母**排 ⇒ `foreground.name`（= "pi"）先于
#   顶层 `name` 出现；老实现「取首个同名键」因此永远拿到 "pi" ⇒ 按名定位恒空 ⇒ close 打印
#   「未发现 app 终端（幂等成功）」而终端仍在（假成功 + 占名撞 name_taken）。
#   修法：先把 `foreground` / `labels` 两个嵌套块整体剔掉，再取首个 `name`（= 顶层名）；null ⇒ 空。
_term_app_name() {  # <json> → 终端名（顶层 name；空/null ⇒ 空）
  local j="${1-}" v=""
  j="$(printf '%s\n' "$j" | sed -E -e 's/"foreground":\{[^}]*\},?//' -e 's/"labels":\{[^}]*\},?//')"
  v="$(_term_app_field "$j" name)"
  case "$v" in null|null,*|null\}*) v="" ;; esac
  printf '%s' "$v"
}

_term_app_facts() {
  local ls="" g addr name cwd tstate st fg fgcwd sp tb hook task
  local nl ncwd nfgcwd nsp ntb nfgp nst nts ntask
  ls="$(_term_app_exec ls --all --json)" || { warn "hc ls 失败（app core 未就绪？）"; return 1; }
  if ! _term_app_payload_ok "$ls"; then
    warn "hc ls 不可用：$(printf '%s' "$ls" | head -c 200)"
    return 1
  fi
  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    g="$(_term_app_exec get "$addr" --json)" || { warn "hc get $addr 失败（快照不完整）"; return 1; }
    if ! _term_app_payload_ok "$g"; then
      warn "hc get $addr 返回错误：$(printf '%s' "$g" | head -c 200)"
      return 1
    fi
    name="$(_term_app_identity "$g")"
    [[ -n "$name" ]] || continue
    cwd="$(_term_app_field "$g" cwd)"
    tstate="$(_term_app_term_state "$g")"
    st="$(_term_app_status_state "$g")"
    fg="$(_term_app_fg_name "$g")"
    fgcwd="$(_term_app_fg_cwd "$g")"
    sp="$(_term_app_field "$g" "$TERM_APP_LABEL_SPACE")"
    tb="$(_term_app_field "$g" "$TERM_APP_LABEL_TAB")"
    task="$(_term_app_field "$g" "$TERM_APP_LABEL_TASK")"
    case "$g" in *'"reported":true'*) hook=1 ;; *) hook=0 ;; esac
    _term_tsv_norm "$name";  nl="$_TSV_NORM"
    _term_tsv_norm "$cwd";   ncwd="$_TSV_NORM"
    _term_tsv_norm "$fgcwd"; nfgcwd="$_TSV_NORM"
    _term_tsv_norm "$sp";    nsp="$_TSV_NORM"
    _term_tsv_norm "$tb";    ntb="$_TSV_NORM"
    _term_tsv_norm "$fg";    nfgp="$_TSV_NORM"
    _term_tsv_norm "$st";    nst="$_TSV_NORM"
    _term_tsv_norm "$tstate"; nts="$_TSV_NORM"
    _term_tsv_norm "$task";  ntask="$_TSV_NORM"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$nl" "$addr" "$addr" "$ncwd" "$nfgcwd" "$nfgp" \
      "$nst" - "$nts" - "$hook" "$nsp" "$ntask"
  done < <(printf '%s' "$ls" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
  return 0
}

# 5 列中性投影（app 13 列 → 业务契约）：无身份省略；空值 `-`。
_term_app_project5() {
  local name pid tid cwd fgcwd fg astat seq sess avname hook wsid task status c
  while IFS=$'\t' read -r name pid tid cwd fgcwd fg astat seq sess avname hook wsid task; do
    [[ -n "$name" ]] || continue
    c="$cwd"; [[ "$c" == "-" || -z "$c" ]] && c="$fgcwd"
    if [[ "$sess" != "live" ]]; then status=alive
    elif [[ "$wsid" == "-" ]]; then status=alive
    elif [[ "$fg" != "pi" ]]; then status=alive
    elif [[ "$hook" != "1" ]]; then status=alive
    else
      case "$astat" in
        working|blocked) status=working ;;
        idle|done)       status=idle ;;
        *)               status=unknown ;;
      esac
    fi
    [[ -n "$c" ]] || c="-"
    [[ -n "$task" ]] || task="-"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$c" "$pid" "$task"
  done
}

# ---- 在线判定（M4：忙闲表，无 seq）----
_term_app_liveness() {  # <name> [repo] → verdict/state/seq/hook
  local name="${1-}" repo="${2-}" rows="" line rp="" filtered="" v="" state="-" cnt=0
  local _l _p _t c1 c2 fg st seq sess av hook ws live_rows=""
  [[ -n "$name" ]] || { printf 'absent\t-\t-\t-\n'; return 0; }
  rows="$(_term_facts 2>/dev/null | awk -F'\t' -v n="$name" '$1==n')" || rows=""
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
  # keep 换壳（BR4）：finished 终端 = pi 已退出、只剩 shell（`--keep` 语义）⇒ **不算在线**，
  #   也不参与同名歧义计数（否则一次 close/退出后的残留会把重建判成 ambiguous）；
  #   只有残留时给 `ghost`（label 在、agent 无）—— 比 absent 更诚实，status 会单列进证据异常节。
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _l _p _t _ _ fg st seq sess av hook ws _task <<< "$line"
    if [[ "$sess" == "live" ]]; then
      live_rows+="$line"$'\n'
    else
      [[ -z "$v" ]] && { v="ghost"; state="$st"; }
    fi
  done <<< "$rows"
  rows="${live_rows%$'\n'}"
  [[ -n "$rows" ]] || { printf '%s\t%s\t-\t-\n' "${v:-absent}" "$state"; return 0; }
  cnt="$(printf '%s\n' "$rows" | grep -c . || true)"
  if (( cnt > 1 )); then
    warn "同名命中 $cnt 个终端：$name ⇒ $(printf '%s\n' "$rows" | cut -f2 | paste -sd, -)（不猜：无唯一身份证据）"
    printf 'ambiguous\t-\t-\t-\n'; return 0
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _l _p _t _ _ fg st seq sess av hook ws _task <<< "$line"
    # 缺 `labels`（AC8 子形态，PM 裁定）：真 hc 恒给 `"labels":{}`，**单缺键**不构成「版本不支持」，
    #   但「有名字、无放置键」⇒ 无法确认归属 ⇒ 判 `unknown`（**不判在线/不可投递**）+ 一行 warn。
    #   若 labels 与 status **两项都缺** ⇒ 按 AC8 主形态判 `integration-missing`（更强的缺陷），
    #   不降级成 unknown（否则 status 会把「集成缺失」证据行吞掉）。
    if [[ "$ws" == "-" ]]; then
      # 只对**舰队形状的会话名**告警（非舰队终端 —— 如用户自己开的窗口、夹具的 self 终端 —— 不归我们管，
      #   否则每次 status 都会刷一条无意义告警）。
      if [[ "$(fleet_name_parse "$name")" == OK* ]]; then
        warn "集成缺 labels：无法确认放置归属（终端 $name；不判在线、不可投递）"
      fi
      if [[ "$st" == "-" || "$hook" != "1" ]]; then
        [[ -z "$v" ]] && { v="integration-missing"; state="-"; }
      else
        [[ -z "$v" ]] && { v="unknown"; state="-"; }
      fi
      continue
    fi
    if [[ "$st" == "-" || "$hook" != "1" ]]; then
      [[ -z "$v" ]] && { v="integration-missing"; state="-"; }
      continue
    fi
    printf 'online\t%s\t-\t%s\n' "$st" "$hook"; return 0
  done <<< "$rows"
  printf '%s\t%s\t-\t-\n' "${v:-absent}" "$state"
}

# app 侧前台 argv（每条 "process-name<TAB>argv"；供诊断/复用面）
_term_app_argv() {  # <addr>
  local addr="${1-}" g rc=0
  [[ -n "$addr" ]] || return 0
  g="$(_term_app_exec get "$addr" --json)" || return 0
  _term_app_payload_ok "$g" || return 0
  local nm av
  nm="$(_term_app_fg_name "$g")"
  av="$(sed -n 's/.*"argv":\[\([^]]*\)\].*/\1/p' <<< "$g" | head -1 | tr -d '"' | sed 's/,/ /g')"
  printf '%s\t%s\n' "${nm:-?}" "$av"
}

# ---- 放置（M3/BR2 + T565/AC1）：**doc 优先**发现 space；doc 里没有 ⇒ 交一个未知 id 让 app 自建 ----
_term_sha256() {  # <串> → 64 位 hex（sha256sum / shasum -a 256 两制）
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "${1-}" | sha256sum | cut -d' ' -f1
  else printf '%s' "${1-}" | shasum -a 256 | cut -d' ' -f1; fi
}
_term_app_mint_tab() {  # <space> <name> → tb<32hex>（确定性：同名同 space 不漂移）
  printf 'tb%s\n' "$(_term_sha256 "${1-}|${2-}" | cut -c1-32)"
}
# AC1 的新建 space id：**doc 里不可能有**（不沿用陈旧标签）。
#   为什么不再用“hash(repo)”（T562 旧实现）：它跨 app 重启稳定 ⇒ 重启后拿到的仍是旧 id，
#   而 AC1 要求“目标不在 doc ⇒ 用未知 id 交给 app 创建”（厂方文档：不认识的 id 由 app 新建）。
_term_app_mint_fresh_space() {  # <repo> → sp<32hex>
  local seed="${1-}|$$|${RANDOM:-0}|$(date +%s%N 2>/dev/null || date +%s)"
  printf 'sp%s\n' "$(_term_sha256 "$seed" | cut -c1-32)"
}
# doc 成员判据（AC1/T565）：目标 space 是否仍在 app 当前布局里（陈旧 id ⇒ 不在）。
#   注：tab 不单做前置校验 —— tab id 是 mint_tab(space, name) 现算的，只在 space 复用时才会撞旧 tab，
#   而那种情况由下方“目标 tab 已有终端”闸门和写后验证（no-tab / no-term）承担。
_term_app_doc_has_space() {  # <space_id> → 0 在 / 1 不在
  [[ -n "${1-}" ]] || return 1
  [[ -n "${_TERM_APP_DOC_SPACES[$1]:-}" ]]
}

_term_app_place_begin() {  # → 0 已建快照 / 1 后端不可用（fail loud 由调用方）
  local rows snap sid folder base cand nn kind a b c d csp="" cid="${HC_TERMINAL_ID:-}" cg="" task=""
  local -A sid_folder=() base_folder=() tab_of=() stale_seen=()
  _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=()
  _TERM_PLACE_TASK_BY_PANE=()
  _TERM_APP_DOC_SPACES=(); _TERM_APP_STALE_SPACES=(); _TERM_APP_CALLER_SPACE=""
  rows="$(_term_app_doc_rows)" || return 1
  _term_app_doc_guard "$rows" || return 1
  # ① space 发现：**doc 是唯一权威**（app 持久化）——AC1/T565：标签里的 id 只是线索，
  #    不在 doc 里（app 重启后 id 会变化）就不能当“该仓的 space”用。
  while IFS=$'\t' read -r kind a b c; do
    [[ "$kind" == "S" ]] || continue
    [[ -n "$a" ]] || continue
    _TERM_APP_DOC_SPACES["$a"]=1
    [[ -n "$b" ]] && sid_folder["$a"]="$b"
  done <<< "$rows"
  # ①-b T569：调用者所在 space（第 1 层）—— `HC_TERMINAL_ID` → `hc get` → `labels.herdr.space`。
  #   只在**仍在 doc 里**时采用；陈旧 ⇒ warn 一行 + 回退第 2 层。
  #   非交互形态（无 id / hc get 失败 / 该终端无该标签）⇒ csp 空、静默走第 2 层（不改变今日行为）。
  #   预置 stale_seen，避免下方「陈旧放置标签」对同一个 id 再喊一行（一行 = 本层唯一的可见信号）。
  if [[ -n "$cid" ]]; then
    cg="$(_term_app_exec get "$cid" --json 2>/dev/null)" || cg=""
    if _term_app_payload_ok "$cg"; then csp="$(_term_app_field "$cg" "$TERM_APP_LABEL_SPACE")"; fi
  fi
  if [[ -n "$csp" ]]; then
    if _term_app_doc_has_space "$csp"; then
      _TERM_APP_CALLER_SPACE="$csp"
    else
      warn "调用者所在 space 不在 app 布局文档里：space=$csp（app 重启后 space id 会变化）⇒ 回退按仓匹配/新建（不沿用该 id）"
      _TERM_APP_STALE_SPACES+=("$csp")
      stale_seen["$csp"]=1
    fi
  fi
  snap="$(_term_app_facts)" || return 1
  while IFS=$'\t' read -r label addr _tid cwd fgcwd _fg _st _seq _sess _av _hook sp _task; do
    [[ -n "$label" ]] || continue
    [[ -n "$sp" && "$sp" != "-" ]] || continue    # `-` = 快照里“该字段为空”的占位（非舰队终端/无标签）
    _term_app_doc_has_space "$sp" && continue
    # AC1：陈旧放置标签（space 不在 doc）——**不得**再拿它当 folder 兜底（旧实现会把它塞进
    #   sid_folder ⇒ spawn 沿用旧 id ⇒ 请求的 id 在 app 侧无处可去 ⇒ #175 的假失败）。
    #   一个陈旧 id 只喊一行（同一 id 可能被多个终端带着）。
    [[ -n "${stale_seen[$sp]:-}" ]] && continue
    stale_seen["$sp"]=1
    _TERM_APP_STALE_SPACES+=("$sp")
    warn "陈旧放置标签：终端 $addr 的 space=$sp 不在 app 布局文档里（app 重启后 space/tab id 会变化）⇒ 不沿用该 id"
  done <<< "$snap"
  # ② 让号 + label 映射（同基名不同 folder ⇒ base2..9，与 herdr 号段同口径）
  while IFS= read -r sid; do
    [[ -n "$sid" ]] || continue
    folder="${sid_folder[$sid]}"
    base="$(place_key_label "$folder")"; [[ -n "$base" ]] || continue
    cand="$base"
    if [[ -n "${base_folder[$base]:-}" && "${base_folder[$base]}" != "$folder" ]]; then
      nn=2
      while [[ -n "${base_folder[${base:0:15}$nn]:-}" ]]; do
        nn=$((nn + 1)); (( nn > 9 )) && { warn "space 号段已满（base=$base，2..9 全占）"; return 1; }
      done
      cand="${base:0:15}$nn"
    fi
    base_folder["$cand"]="$folder"
    _TERM_PLACE_WS_BY_LABEL["$cand"]="$sid"
    _TERM_PLACE_WS_ROWS+=("$sid"$'\t'"$cand")
  done < <(printf '%s\n' "${!sid_folder[@]}" | sort)
  # ③ tab 归属（doc 的 T 行：space / tab / terminals csv）
  while IFS=$'\t' read -r kind a b c d; do
    [[ "$kind" == "T" && -n "$d" ]] || continue
    local addr
    IFS=',' read -ra __ts <<< "$d"
    for addr in "${__ts[@]}"; do [[ -n "$addr" ]] && tab_of["$addr"]="$b"; done
  done <<< "$rows"
  # ④ pane 行（live）+ ⑤ keep 换壳残留（finished ⇒ 记 ghost，spawn 时清）
  local line tb
  local -a ghosts=()
  while IFS=$'\t' read -r label addr _tid cwd fgcwd _fg _st _seq _sess _av _hook sp task; do
    [[ -n "$label" ]] || continue
    [[ -n "$task" && "$task" != "-" ]] && _TERM_PLACE_TASK_BY_PANE["$addr"]="$task"
    tb="${tab_of[$addr]:-}"
    # finished 终端不在 doc（doc 只列 live）⇒ tab id 用与 spawn 同一确定性算法兜底
    [[ -n "$tb" ]] || tb="$(_term_app_mint_tab "$sp" "$label")"
    if [[ "$_sess" != "live" ]]; then
      ghosts+=("$tb"$'\t'"$addr"$'\t'"$label")
      continue
    fi
    _term_place_add_pane "$label" "$addr" "$sp" "$tb" "$cwd" "$fgcwd"
  done <<< "$snap"
  _TERM_APP_GHOST_TABS=("${ghosts[@]:-}")
  _TERM_PLACE_CACHE=1
  return 0
}

_term_app_place_end() {
  _TERM_PLACE_CACHE=0
  _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=(); _TERM_PLACE_TASK_BY_PANE=()
  _TERM_APP_GHOST_TABS=(); _TERM_APP_DOC_SPACES=(); _TERM_APP_STALE_SPACES=(); _TERM_APP_CALLER_SPACE=""
  return 0
}

_term_app_place_rows() {  # 5 列：<space_ref>\t<label>\t<name>\t<handle>\t<cwd>
  local line wsid label name handle c
  local -A wslabel=()
  for line in "${_TERM_PLACE_WS_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    _term_place_ws_fields "$line"
    [[ -n "$_TPW_WS" ]] && wslabel["$_TPW_WS"]="$_TPW_LABEL"
  done
  for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
    [[ -n "$line" ]] || continue
    _term_place_pane_fields "$line"
    [[ -n "$_TP_PANE" ]] || continue
    wsid="${_TP_WS:--}"; name="${_TP_LABEL:--}"; handle="$_TP_PANE"
    label="${wslabel[$_TP_WS]:-}"; [[ -n "$label" ]] || label="-"
    c="${_TP_CWD:--}"; [[ "$c" == "-" || -z "$c" ]] && c="${_TP_FGCWD:--}"
    [[ -n "$c" ]] || c="-"
    printf '%s\t%s\t%s\t%s\t%s\n' "$wsid" "$label" "$name" "$handle" "$c"
  done
}

_term_app_place_ws_for_label() {  # <label> → space_ref / 空；未 begin ⇒ rc1
  (( _TERM_PLACE_CACHE )) || { printf 'term_place_ws_for_label：未调用 term_place_begin\n' >&2; return 1; }
  printf '%s\n' "${_TERM_PLACE_WS_BY_LABEL[${1-}]:-}"
  return 0
}

# 写后读 doc 验证：终端地址必须在目标 tab 的 root 树里（BR2；where 不参与）。
#   AC3/T565：失败时把**成因**落进 _TERM_VERIFY_STATE（no-space / no-tab / no-term / doc-fail），
#   供调用方分两句报错：“目标 space/tab 不存在（app 重启后 id 会变化）” vs “收养超时”。
_term_app_verify_place() {  # <space> <tab> <addr> → 0 命中 / 1 未命中
  local rows kind a b c d sp_seen=0 tab_seen=0
  _TERM_VERIFY_STATE=""
  rows="$(_term_app_doc_rows)" || { _TERM_VERIFY_STATE="doc-fail"; return 1; }
  while IFS=$'\t' read -r kind a b c d; do
    [[ "$kind" == "T" ]] || continue
    [[ "$a" == "$1" ]] || continue
    sp_seen=1
    [[ "$b" == "$2" ]] || continue
    tab_seen=1
    case ",${d}," in *",$3,"*) _TERM_VERIFY_STATE="ok"; return 0 ;; esac
  done <<< "$rows"
  if (( ! sp_seen )); then _TERM_VERIFY_STATE="no-space"
  elif (( ! tab_seen )); then _TERM_VERIFY_STATE="no-tab"
  else _TERM_VERIFY_STATE="no-term"; fi
  return 1
}

# 收养轮询（AC2/T565）：app 侧是异步收养（pending 后由 app 落库）⇒ **有限轮询**读 doc，
#   超时才放弃；轮询期间**不重复起终端**（只读 doc + sleep）。参数校验失败 ⇒ 回落默认（不静默 0 轮）。
_term_app_poll_place() {  # <space> <tab> <addr> → 0 已收养 / 1 未成（_TERM_VERIFY_STATE 给成因）
  local sp="${1-}" tb="${2-}" addr="${3-}"
  local tries="${TERM_APP_ADOPT_TRIES:-10}" intv="${TERM_APP_ADOPT_INTERVAL:-0.5}" i
  if [[ ! "$tries" =~ ^[0-9]+$ ]]; then
    warn "NAO_APP_ADOPT_TRIES=$tries 非法（需非负整数）⇒ 回落 10"
    tries=10
  fi
  if [[ ! "$intv" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    warn "NAO_APP_ADOPT_INTERVAL=$intv 非法（需数字）⇒ 回落 0.5"
    intv=0.5
  fi
  (( tries > 0 )) || tries=1        # 0 轮 = 根本不验，不允许（宁可变 1 轮）
  _TERM_VERIFY_ATTEMPTS=0
  _TERM_VERIFY_INTERVAL="$intv"
  for (( i = 1; i <= tries; i++ )); do
    _TERM_VERIFY_ATTEMPTS=$i
    if _term_app_verify_place "$sp" "$tb" "$addr"; then
      (( i > 1 )) && log "放置收养完成（第 $i 次读回；app 收养是异步的）：终端 $addr ⇒ space=$sp tab=$tb"
      return 0
    fi
    (( i < tries )) && sleep "$intv"
  done
  return 1
}

_term_app_wait_ready() {  # <addr> <name> → 0 就绪 / 1 超时（终端保留）
  local addr="${1-}" name="${2-}" i g st app
  for i in $(seq 1 50); do
    g="$(_term_app_exec get "$addr" --json 2>/dev/null)" || { sleep 0.1; continue; }
    _term_app_payload_ok "$g" || { sleep 0.1; continue; }
    st="$(_term_app_status_state "$g")"; app="$(_term_app_status_app "$g")"
    if [[ "$app" == "pi" && "$st" == "idle" ]]; then return 0; fi
    sleep 0.1
  done
  warn "就绪门超时（$name ⇒ $addr：5s 内未见 status.app=pi ∧ state=idle；终端保留，不自动 kill）"
  warn "  该怎么办：核对 desktop app 内该 tab 的程序是否起在 pi 上；pi 首次启动停在提示框时会一直非 idle"
  return 1
}

_term_app_spawn() {  # <name> <inner> <repo> [force] <label> [group] [task] → SPAWN_RC_OK|FAIL
  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" task="${7-}"
  local sp tb out addr legal="" line llegal llabel
  [[ -n "$name" && -n "$inner" ]] || { warn "app spawn 参数缺失（name/inner）"; return "$SPAWN_RC_FAIL"; }
  [[ -n "$label" ]] || { warn "app spawn 缺放置键（期望 = 仓基键；repo=$repo）"; return "$SPAWN_RC_FAIL"; }
  if ! fleet_scope_problem "$label" >/dev/null; then
    warn "app spawn 的放置键不可用（label=$label；期望 ^[a-z0-9][a-z0-9_-]{0,15}$）"; return "$SPAWN_RC_FAIL"
  fi
  # space（AC1/T565）：**只认 doc**（app 持久化是权威）。拿到的 id 若不在 doc 里（陈旧标签 /
  #   app 重启后 id 变化）⇒ **禁沿用**（旧实现直接用它，app 不认识的 id 由 app 自己新建 ⇒ 请求的
  #   space/tab 无处可去 ⇒ #175 的假失败）；改交一个 doc 未知的新 id 让 app 自建，并回写标签。
  local sp_old=""
  if (( _TERM_PLACE_CACHE )); then sp="${_TERM_PLACE_WS_BY_LABEL[$label]:-}"; else sp=""; fi
  # T569 第 1 层：调用者所在 space 优先（New Terminal 语义）—— prime 已校验它仍在 doc 里。
  #   命中即只加 tab；仓 folder 匹配（第 2 层）与新建（第 3 层）保持原语义。
  if [[ -n "${_TERM_APP_CALLER_SPACE:-}" ]]; then sp="$_TERM_APP_CALLER_SPACE"; fi
  if ! _term_app_doc_has_space "$sp"; then
    sp_old="$sp"
    sp="$(_term_app_mint_fresh_space "$repo")"
    if [[ -n "$sp_old" ]]; then
      warn "目标 space 不在 app 布局文档里（陈旧 id / app 重启后 id 变化）⇒ 新建 space=$sp（不沿用 $sp_old）"
    fi
    # 本命令内同一放置键的后继角色共用这个新 space（不每次新起一个；仍不跨进程缓存）
    _TERM_PLACE_WS_BY_LABEL["$label"]="$sp"
    _TERM_APP_DOC_SPACES["$sp"]=1
  fi
  tb="$(_term_app_mint_tab "$sp" "$name")"
  # keep 换壳残留：同 tab 的 finished 终端（pi 已退出、只剩 shell）⇒ 先回收再重建，
  #   否则一次退出会永久占住该 tab（准确报因：finished = 无 agent 在跑，回收不杀会话）。
  if (( _TERM_PLACE_CACHE )); then
    local gline gtb gaddr gname
    for gline in "${_TERM_APP_GHOST_TABS[@]:-}"; do
      [[ -n "$gline" ]] || continue
      IFS=$'\t' read -r gtb gaddr gname <<< "$gline"
      [[ "$gtb" == "$tb" ]] || continue
      log "清理残留（finished）：$gname ⇒ $gaddr（该 tab 的旧终端已无 agent；kill → rm 后重建）"
      _term_app_exec kill "$gaddr" >/dev/null 2>&1 || true
      _term_app_exec rm "$gaddr" >/dev/null 2>&1 || true
    done
  fi
  # 同 tab 已有终端：本函数语义 = 不新建（ensure 的判重在上层；此处只防并发重复）
  if (( _TERM_PLACE_CACHE )); then
    local line
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      if [[ "$_TP_TAB" == "$tb" && -n "$_TP_PANE" ]]; then
        warn "目标 tab 已有终端（space=$sp tab=$tb ⇒ $_TP_PANE）：不新建第二个（先 close 该角色再 ensure）"
        return "$SPAWN_RC_FAIL"
      fi
    done
  fi
  # --no-parent 是硬护栏（父终端结束会带走子终端）；--keep 按 ADR 保留（core 丢失后原地换 shell）
  # 名称合法化（v3）：hc run --name 限 [a-z0-9-_.]{1,32}；原始 nao 名存 `nao.name`。
  legal="$(fleet_backend_name "$name")"
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      llabel="$_TP_LABEL"
      [[ -n "$llabel" && "$llabel" != "$name" ]] || continue
      llegal="$(fleet_backend_name "$llabel")"
      [[ "$llegal" == "$legal" ]] || continue
      legal="${legal:0:27}-$(_term_sha256 "$name" | cut -c1-4)"
      break
    done
  fi
  local -a lbl=(--label "$TERM_APP_LABEL_SPACE=$sp" --label "$TERM_APP_LABEL_TAB=$tb" --label "$TERM_APP_LABEL_NAME=$name")
  [[ -n "$task" ]] && lbl+=(--label "$TERM_APP_LABEL_TASK=$task")
  out="$(_term_app_exec run --bg --no-parent --keep --name "$legal" --cwd "$repo" \
        "${lbl[@]}" -- "${SHELL:-/bin/bash}" -lc "$inner")" || true
  if ! _term_app_payload_ok "$out"; then
    warn "hc run 失败（name=$name）：$(printf '%s' "$out" | head -c 200)"
    return "$SPAWN_RC_FAIL"
  fi
  addr="$(_term_app_field "$out" address)"
  if [[ -z "$addr" ]]; then
    warn "hc run 未返回终端地址（name=$name）：$(printf '%s' "$out" | head -c 200)"
    return "$SPAWN_RC_FAIL"
  fi
  # BR2/AC2/T565：写后**轮询**读 doc 验证（app 收养是异步的）；不成 ⇒ 按成因分两句报错
  #   + 回滚自己刚建的终端 + fail loud（不留孤儿）。
  if ! _term_app_poll_place "$sp" "$tb" "$addr"; then
    case "${_TERM_VERIFY_STATE:-}" in
      no-space)
        warn "放置验证失败：目标 space 不存在（app 重启后 space/tab id 会变化）—— space=$sp tab=$tb；终端 $addr 不在该 space ⇒ 回滚（kill → rm）"
        warn "  该怎么办：确认 desktop app 窗口在跑（本命令读不回该 space）；重跑 ensure 会按 app 当前布局新建 space" ;;
      no-tab)
        warn "放置验证失败：目标 tab 不存在（space=$sp 在 doc 里，tab=$tb 不在；app 可能把终端放进了别的 tab）—— 终端 $addr ⇒ 回滚（kill → rm）"
        warn "  该怎么办：确认 desktop app 版本支持标签收养（doc version ≥ $TERM_APP_DOC_MIN）；回滚后不会留下孤儿终端" ;;
      *)
        warn "放置验证失败：收养超时（${_TERM_VERIFY_ATTEMPTS}×${_TERM_VERIFY_INTERVAL:-$TERM_APP_ADOPT_INTERVAL}s 内 doc 未见终端 $addr 在目标 tab 的 root 树里；space=$sp tab=$tb）⇒ 回滚（kill → rm）"
        warn "  app 的放置是异步的（pending 后由 app 落库）：超时 = app 没认出这两个标签或窗口/版本不对；可用 NAO_APP_ADOPT_TRIES / NAO_APP_ADOPT_INTERVAL 放宽" ;;
    esac
    _term_app_exec kill "$addr" >/dev/null 2>&1 || true
    _term_app_exec rm "$addr" >/dev/null 2>&1 || true
    return "$SPAWN_RC_FAIL"
  fi
  if ! _term_app_wait_ready "$addr" "$name"; then
    return "$SPAWN_RC_FAIL"
  fi
  _TERM_SPAWN_PANE="$addr"; _TERM_SPAWN_WSID="$sp"; _TERM_SPAWN_TID="$tb"
  if [[ -n "${_TERM_SNAP_FILE:-}" ]]; then rm -f "$_TERM_SNAP_FILE" 2>/dev/null || true; _TERM_SNAP_FILE=""; fi
  if (( _TERM_PLACE_CACHE )); then
    _term_place_set_pane "$name" "$addr" "$sp" "$tb" "$repo" "$task"
  fi
  return "$SPAWN_RC_OK"
}

_term_app_deliver() {  # <addr> <message> → 0 已投递 / 1 失败（stdout: error code）
  local addr="${1-}" msg="${2-}" out
  [[ -n "$addr" ]] || { printf 'terminal_id 缺失\n'; return 1; }
  out="$(_term_app_exec send "$addr" "$msg" 2>&1)" || true
  if ! _term_app_payload_ok "$out"; then
    printf 'code=%s\n' "$(sed -nE 's/.*"code":[[:space:]]*"([^"]+)".*/\1/p' <<< "$out" | head -1)"
    return 1
  fi
  return 0
}

# ---- 回收（M5/BR4）：kill → rm（顺序固定；kill 幂等；live 直接 rm ⇒ rc=1 kind:live）----
_term_app_find_by_name() {  # <name> → 每行一个地址（ls --all；名字取**顶层** name，见 _term_app_name）
  local name="${1-}" ls a g
  ls="$(_term_app_exec ls --all --json 2>/dev/null)" || return 0
  _term_app_payload_ok "$ls" || return 0
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    g="$(_term_app_exec get "$a" --json 2>/dev/null)" || continue
    [[ "$(_term_app_name "$g")" == "$name" ]] && printf '%s\n' "$a"
  done < <(printf '%s' "$ls" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
}

_term_app_reclaim() {  # <name> <repo> <force> <core> <scope> <ensure-target> → 0 已回收 / 1 拒绝或失败
  local name="${1-}" repo="${2-}" force="${3:-false}" addrs=() addr g tstate st
  mapfile -t addrs < <(_term_app_find_by_name "$name")
  if (( ${#addrs[@]} == 0 )); then
    log "未发现 app 终端：$name（已不在运行；幂等成功）"
    return 0
  fi
  if (( ${#addrs[@]} > 1 )); then
    warn "同名命中多个 app 终端：$name ⇒ ${addrs[*]}（不猜：先人工核对；回收面不静默挑一个）"
    return 1
  fi
  addr="${addrs[0]}"
  if [[ "$addr" == "${HC_TERMINAL_ID:-}" ]]; then
    warn "拒绝回收自身终端（$name ⇒ $addr 就是当前终端）"
    return 1
  fi
  g="$(_term_app_exec get "$addr" --json 2>/dev/null)" || { warn "读取终端失败：$addr"; return 1; }
  _term_app_payload_ok "$g" || { warn "终端信息不可读：$addr（$(printf '%s' "$g" | head -c 160)）"; return 1; }
  tstate="$(_term_app_term_state "$g")"; st="$(_term_app_status_state "$g")"
  if [[ "$tstate" == "live" ]]; then
    case "$st" in
      working|blocked)
        if [[ "$force" != true ]]; then
          warn "拒绝回收 $name：状态=$st（忙）—— 等它空闲，或 --force（会打断当前回合）"
          return 1
        fi
        warn "强制回收 $name（状态=$st）：--force" ;;
      done)
        # T574/Issue #207：`--keep` 保活使「会话已结束」的终端以 live+done 存在
        #   （历史缺陷：门面状态映射漏 done ⇒ close 报「未运行/幂等成功」，终端残留占名）
        log "回收「会话已结束、终端保活」（$name ⇒ $addr：state=live · status=done）" ;;
      -|"")
        if [[ "$force" != true ]]; then
          warn "拒绝回收 $name：忙闲不可判定（$addr 无 status 上报）—— 确认无用时加 --force"
          return 1
        fi ;;
    esac
  fi
  # kill（幂等）→ rm（顺序不可反）；rm 允许**有界**重试（kill 生效是异步的：live 直接 rm ⇒ kind=live）
  if ! _term_app_exec kill "$addr" >/dev/null 2>&1; then
    warn "hc kill 失败（$name ⇒ $addr）"; return 1
  fi
  # T573 返修 D8：`ls` 失败/错误 payload ≠ 「已消失」。读不到 ⇒ 未知 ⇒ **fail loud 保留终端**
  #   （与分级同向：判不出就不动手；原实现把空输出当「已消失」⇒ 假成功）
  local _i=0 _rm_ok=1 _ls="" _present=0
  while (( _i < 15 )); do
    if _term_app_exec rm "$addr" >/dev/null 2>&1; then _rm_ok=0; break; fi
    _ls="$(_term_app_exec ls --all --json 2>/dev/null)" \
      || { warn "hc ls 失败（$name ⇒ $addr）：无法确认终端是否已消失 ⇒ 不判成功（请核对 hc ls --all）"; return 1; }
    _term_app_payload_ok "$_ls" \
      || { warn "hc ls 返回错误（$name ⇒ $addr）：$(printf '%s' "$_ls" | head -c 160) ⇒ 同上，不判成功"; return 1; }
    if ! printf '%s' "$_ls" | grep -qF "\"address\":\"$addr\""; then _rm_ok=0; break; fi
    sleep 0.1
    _i=$((_i + 1))
  done
  if (( _rm_ok != 0 )); then
    warn "hc rm 失败（$name ⇒ $addr：kill 后仍不可删？核对 hc ls --all）"; return 1
  fi
  # effect 判据（不看 rc）：地址必须从**可读的** ls --all 消失；读不到 ⇒ 不可判定 ⇒ 保留
  _ls="$(_term_app_exec ls --all --json 2>/dev/null)" \
    || { warn "回收结果不可判定：hc ls 失败（$name ⇒ $addr）⇒ 按失败处理、不宣称成功（核 hc ls --all）"; return 1; }
  _term_app_payload_ok "$_ls" \
    || { warn "回收结果不可判定：hc ls 返回错误（$name ⇒ $addr；$(printf '%s' "$_ls" | head -c 160)）⇒ 按失败处理、不宣称成功"; return 1; }
  if printf '%s' "$_ls" | grep -qF "\"address\":\"$addr\""; then
    warn "回收未达成：$addr 仍在 hc ls --all 中（effect 判据失败）"; return 1
  fi
  log "已回收 app 终端：$name（$addr）"
  return 0
}

# 拆场（app）：无「场」语义（core 属桌面版，停 core = 关用户窗口 ⇒ 禁止）；
#   本命令 = 逐个 kill+rm 带放置标签的舰队终端（跨仓同 core），--force 放行忙闲闸门。
_term_app_cleanup() {  # <session> [force]
  local force="${2:-false}" ls n=0 ok=0 busy=0 addr g tstate st
  ls="$(_term_app_exec ls --all --json 2>/dev/null)" || { warn "hc ls 不可用（desktop app / core 未就绪）"; return 1; }
  _term_app_payload_ok "$ls" || { warn "hc ls 返回错误：$(printf '%s' "$ls" | head -c 160)"; return 1; }
  while IFS= read -r addr; do
    [[ -n "$addr" ]] || continue
    g="$(_term_app_exec get "$addr" --json 2>/dev/null)" || continue
    _term_app_payload_ok "$g" || continue
    [[ -n "$(_term_app_field "$g" "$TERM_APP_LABEL_SPACE")" ]] || continue
    [[ "$addr" == "${HC_TERMINAL_ID:-}" ]] && { warn "跳过自身终端：$addr"; continue; }
    n=$((n + 1))
    tstate="$(_term_app_term_state "$g")"; st="$(_term_app_status_state "$g")"
    if [[ "$tstate" == "live" && ( "$st" == "working" || "$st" == "blocked" ) && "$force" != true ]]; then
      warn "跳过忙终端：$addr（状态=$st；--force 可强制）"; busy=$((busy + 1)); continue
    fi
    if _term_app_exec kill "$addr" >/dev/null 2>&1 && _term_app_exec rm "$addr" >/dev/null 2>&1; then
      ok=$((ok + 1))
    else
      warn "回收失败：$addr"
    fi
  done < <(printf '%s' "$ls" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
  log "app 拆场：命中 $n 个舰队终端，回收 $ok 个，跳过忙 $busy 个（core 本身不动：属桌面版）"
  (( busy == 0 )) && return 0
  return 1
}

# 前提探测（check · M1 + T565/#175 AC4）：只在 app 后端或 app 终端内输出；
#   **warn-only**：调用方一律 `|| true`（不计入 rc）—— 用户实机的真因常常就藏在这里，
#   但 check 是静态体检，不能用 rc 把它变成阻塞（真正的阻塞由 ensure 侧 fail loud 自己承担）。
#   覆盖项（AC4 点名的三项）：herdr-app 在 PATH + status rc=0 + doc 可读（另带 hc / doc 版本）。
_term_app_check_premise() {  # → 0 齐备 / 1 有问题（打印 `  ! ` 行 + 一行“不计入 rc”）
  local bad=0 rows ver hc_ok=0
  if ! command -v hc >/dev/null 2>&1; then
    printf '  ! app 后端：hc 不在 PATH（装 herdr desktop app CLI；不想用 app 后端请 unset NAO_TERMINAL）\n'
    bad=1
  else
    hc_ok=1
  fi
  if ! command -v herdr-app >/dev/null 2>&1; then
    printf '  ! app 后端：herdr-app 不在 PATH（无法判断窗口状态）\n'; bad=1
  elif ! herdr-app status >/dev/null 2>&1; then
    printf '  ! app 后端：desktop app 窗口未在运行（ensure 会 exit 3：窗口关闭时终端不会被收养）\n'; bad=1
  fi
  if (( hc_ok )); then
    if ! _term_app_exec schema >/dev/null 2>&1; then
      printf '  ! app 后端：hc schema 不可用（core/socket 异常；核对 desktop app 后重试）\n'; bad=1
    fi
  fi
  if [[ -n "${HC_TERMINAL_SOCKET:-}" ]]; then
    if (( ! hc_ok )); then
      printf '  ! app 后端：布局文档不可读（缺 hc；doc.get 无法执行）\n'; bad=1
    elif rows="$(_term_app_doc_rows 2>/dev/null)"; then
      ver="$(awk -F'\t' '$1=="V"{print $2; exit}' <<< "$rows")"
      if [[ -z "$ver" || "$ver" == "0" ]]; then
        printf '  ! app 后端：布局文档 value=null（窗口未开或版本过旧）\n'; bad=1
      elif [[ ! "$ver" =~ ^[0-9]+$ ]] || (( ver < TERM_APP_DOC_MIN )); then
        printf '  ! app 后端：布局文档 version=%s < %s（app 版本过旧，放置契约不支持）\n' "$ver" "$TERM_APP_DOC_MIN"; bad=1
      fi
    else
      printf '  ! app 后端：doc.get 失败（desktop app 未就绪）\n'; bad=1
    fi
  else
    printf '  · app 后端：当前不在 app 终端（三件套缺；ensure/status/close 需在 app 终端内运行）\n'
  fi
  (( bad == 0 )) && return 0
  printf '  · 以上 app 端前提仅提示，**不计入 rc**（放置类动作会自行 fail loud；先打开窗口再重试）\n'
  return 1
}

# 状态页的 space 标签表（替 herdr 的 workspace list）
_term_app_ws_label_rows() {  # → 每行 "<space_id>\t<label>"（label = 仓基键，同 herdr 口径）
  local rows kind a b c base cand nn
  local -A base_folder=()
  rows="$(_term_app_doc_rows 2>/dev/null)" || return 0
  while IFS=$'\t' read -r kind a b c; do
    [[ "$kind" == "S" ]] || continue
    [[ -n "$b" ]] || continue
    base="$(place_key_label "$b")"; [[ -n "$base" ]] || continue
    cand="$base"
    if [[ -n "${base_folder[$base]:-}" && "${base_folder[$base]}" != "$b" ]]; then
      nn=2
      while [[ -n "${base_folder[${base:0:15}$nn]:-}" ]]; do nn=$((nn + 1)); (( nn > 9 )) && break; done
      cand="${base:0:15}$nn"
    fi
    base_folder["$cand"]="$b"
    printf '%s\t%s\n' "$a" "$cand"
  done <<< "$rows"
}
# <<< term-impl-app END
