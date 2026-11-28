#!/usr/bin/env bash
# =============================================================================
# nao-fleet.sh — 按角色一键拉起 pi 会话窗口（nao 团队工具箱）
#
# 运行前提（端前提 = herdr pane 内 + pi ≥ MIN_PI_VERSION；ADR 2026-11-22-herdr-only
#   supersede 2026-10-27-strict-tmux-pi：**herdr 是唯一后端程序**（形态：TUI 默认 / desktop app），旧 tmux 后端与 -S 调用面已删除，见 §退出码）
#   **唯一后端程序 = herdr**（形态 herdr=TUI 默认 / app=desktop app）：`NAO_TERMINAL` 只接受这两个值（其他值 ⇒ stderr 1 行 + exit 2，命令未执行）；
#     未设/空串/herdr 均放行。**不自动回落、不静默降级**（ADR 决策 3）。
#   前提 = 「herdr pane 内 + HERDR_SESSION 有效 + protocol 22」；ensure/status/close 任一项不满足 ⇒
#     fail loud exit 3 + 一行提示，不建 session/pane/lock、不写状态。
#   cleanup 豁免本前提：拆场是外部动作（`cleanup --session <名>`）。
#   herdr 后端（#96 二期 B1/B2/B3 · 三期 P1 布局 A）：判定面（status）· 放置/就绪面（ensure）· 回收面（close/cleanup）
#     —— 全部走门面。**布局 A（AC3.1）**：1 workspace/仓（label = **仓基键**：git 仓名/目录名归一化；
#     同机两仓同基名 ⇒ 后者自动让号 `base2`..`base9`（base 截 15 字符 + 单字符 N），段满 fail loud；
#     ADR 2026-11-20-workspace-as-binding-unit：绑定单位 = herdr workspace，**名字不含位置**）
#     + 1 tab/角色（label=角色名）+ 每 tab 恰 1 pane；
#     放置后自测空间（HERDR 不报空间不足 ⇒ rc 不可作判据，见 TERM_MIN_COLS/ROWS 与 J1/J5）。
#     起 server 由独立入口 `session-start --session <名>` 负责（BR6：清宿主终端句柄 + 枚举清 HERDR_*）；
#     拆场由姊妹入口 `cleanup --session <名>` 负责（stop+delete，判 effect 不看 rc）。
#
# 退出码
#   0 = 成功 · 1 = 已执行但失败 · 2 = 用法守卫（非 herdr 的 NAO_TERMINAL / cleanup -S / --session 守卫等）
#   3 = 前提不满足（命令未执行；缺 HERDR_ENV/HERDR_SESSION 或 protocol 不兼容）
#   4 = 本后端未实现该子命令（命令未执行；B3 后**无**此类子命令，取值保留以维持 rc 语义稳定）
#
# 用法
#   nao-fleet.sh check [--strict] [-v]            静态体检：roles.yaml/缩进/EOL/角色卡/交叉引用/PR 模板/白名单/herdr+pi 前提
#                                                 默认摘要 2–3 行：摘要行 + codegraph 状态行（四态之一）+ herdr 的生效后端行；-v 展开完整报告；失败始终展开
#   nao-fleet.sh status [--json]                  角色会话在线状态（pane label + agent 状态
#                                                 （结构化事实，权威源 pane list/agent list）；非在线证据单列）
#                                                 `--json`（T567-B · schema:1）= 编排器契约：文本输出**逐字不变**，
#                                                 另出机读 JSON（角色/会话/pane/cwd/归属/在线/三态忙闲/可投递）
#   nao-fleet.sh ensure <别名>[@<repo>] [更多...]  拉起角色窗口（默认工作区=roles.yaml workspace）
#                                                 `@<repo>` = 目标仓选择符（`@main` 走 manifest、`@<路径>` 直指），不入会话名
#   nao-fleet.sh ensure -m <model> <别名>...       显式指定模型（须命中白名单）
#   nao-fleet.sh ensure --task <编号> <别名>[@<repo>]   任务派生会话（task 只进元数据）：名字 = `<别名>[<N>]`；
#                                                 同 (role,task) 元数据已在 ⇒ 复用该名；否则取空闲槽位（N=2..9，段满 fail loud）
#   nao-fleet.sh ensure --card <卡路径> [--as <会话名>] [--task <编号>]
#                                                 下游仓自定义角色会话（一次性）：卡须为 <repo>/.agents/prompts/<file>.md
#                                                 （卡 role 与常驻 id/别名必须前缀不相交；不入 roles.yaml、不算常驻；
#                                                  --as 只给常驻名/旧形后缀：= 卡 role、`<role><N>`（N=2..9）或
#                                                  `<role>-<后缀>`；含 `(` 即拒 —— 派生 task 只走 --task）
#   会话名契约（v3 · ADR 2026-11-25）：`<role>[<N>]`（task 不进名字，只落元数据）；
#                                                 N = 单字符 2..9（空 = 槽位 1；>9 结构上不可解析 ⇒ fail loud）；
#                                                 名字不含位置，绑定单位 = herdr workspace（同名跨仓合法）。
#                                                 旧形 `<core>[-<task>][@<scope>]` 只读：status/close 能认，ensure 永不生成。
#   --fleet <slug>                                **已弃用**（下一 MINOR 移除）：给参但空 ⇒ 用法错；非空 ⇒ 恰一行
#                                                 warn 后**忽略**（不校验、不影响放置）。放置键恒为仓基键。
#   --scope <slug>                                **已弃用别名**（同口径）：等同 --fleet 被忽略，不再「覆盖放置键」。
#   `.agents/fleet-scope` / fleet.yaml 的 `slug:`  **已弃用**：读到即恰一行 warn 后忽略（放置键恒为仓基键）。
#   nao-fleet.sh session-start --session <名>     起专用 herdr session 的 server（herdr 后端）。
#                                                 --session 必填、≠default；起 server 前**清宿主终端句柄**
#                                                 （TMUX/TMUX_PANE/TMUX_TMPDIR）+ **枚举清 HERDR_***（BR6），
#                                                 50×100ms / 5s 轮询就绪，超时 fail loud
#   nao-fleet.sh ensure --force <别名>...          忽略"已在运行"判重
#   nao-fleet.sh ensure --trust-project <别名>...   给**本次**拉起的 pi 加 `--approve`（首次在未信任目录免确认；
#                                                 只影响该次 spawn，不写任何持久配置；等价环境变量 NAO_TRUST_NEW_REPO=1）
#                                                 （目标解析为 pm 时，**就绪后**投递一条固定用户消息：机制包版本自检，
#                                                  仅提示不自动升级；关闭用 NAO_UPDATE_ON_ENSURE=0）
#   nao-fleet.sh close <别名|派生会话名|legacy 全名> [--task <编号>] [--force]
#                                                 回收已完成会话（派生名如 rd-be、带槽位 rd-be2；task 按元数据匹配）；
#                                                 裸别名 = 本仓锚内同 core（v2 各槽位 → legacy 旧形候选
#                                                 → 全 session 唯一同 core → 否则拒绝列候选）；带 `@` 的 legacy
#                                                 （跨仓定位；定位失败/名册报在线但无句柄 ⇒ 非 0 + 诊断）
#                                                 （闸门：在跑 turn / tasks-state 未推进 / app 侧 status=idle → 拒绝，--force 跳过；
#                                                  常驻缺席而其派生在场 ⇒ 目标歧义拒绝，T516 AC3）
#                                                 herdr 后端：忙闲闸门 = agent_status（BR7）+ 名册第二信号（OR）；
#                                                 unknown / 无 agent 条目 / 集成缺失 / 进程不可判 ⇒ 拒（fail-closed）
#   nao-fleet.sh cleanup --session <名>           （herdr 后端）拆专用 session：session stop + delete，
#                                                 判 **effect** 不看 rc（stop 非幂等）；--session 必填且 ≠default（BR9）
#   nao-fleet.sh logs <role> [--task <编号>] [--raw|--list|--purge [--days N]]
#                                                 会话记录入口（T573）：默认按 turn 摘要（user 首行 +
#                                                 assistant 首行 + 工具名）；--raw 原样；--list 列记录；
#                                                 --purge 按结果分级清理（正常 24h / 异常 7 天，--days N 一次性
#                                                 统一保质期）；无记录 ⇒ rc=0 + 一行提示。**不建会话、不调后端**。
#   nao-fleet.sh cleanup -S <socket>              **已随 tmux 后端移除**（ADR 2026-11-22-herdr-only）：
#                                                 任一子命令带 -S ⇒ exit 2 + 单行指路 `--session <名>`（fail loud，不静默吞参）
#
# 角色别名 → 角色卡：见 .agents/roles.yaml（单一事实来源）
#   当前：pm / arch-designer(arch) / uiux-designer(uiux, ui-designer) / rd-fe / rd-be / qa / rd-infra(infra)
#
# 环境变量
#   NAO_FLEET=<dir>                           nao 机制包根目录（默认 <脚本>/../..；项目内 shim 会显式指向包根）
#   NAO_SKILLS=<dir>                          兼容别名（旧名，一个版本后弃用；与 NAO_FLEET 同给时以前者为准）
#   NAO_MODEL_WHITELIST=<glob,...>            -m 白名单（默认空=不校验，支持 glob）
#   NAO_CLOSE_BUSY_PATTERN=<ERE>             close 的在跑 turn 判定正则（默认内置 pi 状态行标记）
#   NAO_TERMINAL=<值>                        后端形态：herdr（TUI，默认）/ app（desktop app）；给**其他任何值**（含已移除的 tmux）
#                                            ⇒ stderr 1 行 + exit 2（命令未执行）。status/ensure/close/cleanup 走门面，
#                                            ensure 须先 `session-start` 起专用 session 并在其 pane 内运行
#   NAO_HERDR_READY_TIMEOUT_MS=<ms>          herdr 就绪门 wall-clock 上限（默认 5000；只对 herdr 后端生效）
#   NAO_TERM_MIN_COLS=<n>                     herdr 放置后空间判据最小列宽（默认 60；不足只 warn 不中断）
#   NAO_TERM_MIN_ROWS=<n>                     herdr 放置后空间判据最小行数（默认 10；0 尺寸 pane ⇒ 计 SPAWN_FAIL）
#   NAO_TASKS_STATE=<path>                   任务状态文件（默认 docs/tasks-state.md，供残留检测/回收闸门）
#   NAO_FLEET_META_DIR=<dir>                 舰队自有状态根（默认 ~/.local/state）：其下 `sessions/<编码 cwd>/` = Pi session 记录
#                                            （ensure 对**全部**舰队会话以 --session-dir 落此、一仓一子目录，T573）·
#                                            `session-meta/` = herdr sidecar
#   NAO_UPDATE_ON_ENSURE=0|false             ensure pm 就绪后的下游版本自检**投递**开关（默认开；0/false ⇒ 不投递）
#
# 在线判定与 pane 定位（status / close / ensure 判重共用）
#   身份/归属/忙闲全部取 herdr 结构化事实：pane label（+ argv --name 交叉校验）· pane cwd /
#     foreground_cwd（谓词复用 repo_contains_path）· agent_status + state_change_seq。
#   ⚠️ 一律不读终端标题，也不把宿主终端句柄当证据：从 tmux shell 起的 herdr server 会把外层
#     句柄（TMUX/TMUX_PANE/TMUX_TMPDIR）渗进 pane（spike 实测）⇒ 起 server 前必须清（BR6）。
#   pane id（%N）是 **server 局部**命名空间 ⇒ 任何「跨 server 比较 pane id」的判据都是错的（T530 误拒根因）。
#   名册由 intercom-probe.mts（一次调用、进程内缓存，含 tmuxPane 字段）取，仅供 status 的 -v 诊断；
#     身份判定**不**依赖名册（BR3/BR7）。
# =============================================================================

# ---- 模块装配（T567-A · ADR D3 拓扑序；纯搬迁，行为零变更）----
# 入口永久保留：本注释头（usage() 用 awk 读 $0 的头块 ⇒ 不可搬走）+ CLI 解析 + 分发。
FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/fleet" && pwd)"
source "$FLEET_DIR/lib/core.sh"
source "$FLEET_DIR/lib/term.sh"
source "$FLEET_DIR/lib/term-herdr.sh"
source "$FLEET_DIR/lib/term-app.sh"
source "$FLEET_DIR/lib/manifest.sh"
source "$FLEET_DIR/lib/sessions.sh"
source "$FLEET_DIR/lib/session.sh"
source "$FLEET_DIR/lib/check.sh"
source "$FLEET_DIR/lib/status.sh"
source "$FLEET_DIR/lib/close.sh"
source "$FLEET_DIR/lib/cleanup.sh"
source "$FLEET_DIR/lib/ensure.sh"


# ---------------------------------------------------------------------------
usage() {
  awk '
    /^# =+$/ { c++; if (c==2) exit; next }
    c==1 && /^#/ { sub(/^# ?/,""); print }
  ' "$0"
  exit 0
}

# ---- 入口 ----
CMD=""; FORCE=false; STRICT=false; MODEL=""; TASK=""; TRUST_PROJECT=false; CLEANUP_SOCK=""; SESSION_ARG=""; TARGETS=()
# T567-B：`status --json`（编排器唯一跨进程契约）。默认关 ⇒ 文本路径逐字不变（AC1）。
JSON_OUT=false
# T554/D7：`--fleet` / `--scope` 已弃用 —— 只保留「给参但空 ⇒ 用法错」守卫；非空仅打一行 warn 后丢弃（放置键恒为仓基键）
CLI_FLEET=""; SCOPE_SEEN=false; FLEET_SEEN=false
# T573：`logs` 入口开关（只用于 logs；其他子命令带 ⇒ 用法错）
LOGS_RAW=false; LOGS_LIST=false; LOGS_PURGE=false; LOGS_DAYS=""; LOGS_REPO=""
_need_logs() { [[ "$CMD" == "logs" ]] || die "$1 仅用于 logs 子命令：nao-fleet.sh logs <role> [--task <编号>] [--raw|--list|--purge [--days N]]"; }
# T537：目标级修饰符（--card / --as）的绑定状态 —— 只作用于**其后第一个 positional**（BR11）
TARGET_CARD=(); TARGET_AS=(); PEND_CARD=false; PEND_AS=""; LAST_CARD_IDX=-1
_need_ensure() { [[ "$CMD" == "ensure" ]] || die "$1 仅用于 ensure 子命令：nao-fleet.sh ensure [<角色>[@<code>]] [--card <卡路径>[@<repo>]] [--task <编号>] [--as <会话名>]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    check)  CMD="check";  shift ;;
    status) CMD="status"; shift ;;
    # T567-B · --json：只给 status（其它子命令/空命令 ⇒ 用法错，不静默吞参）
    --json)
      JSON_OUT=true; shift ;;
    close)  CMD="close";  shift ;;
    cleanup) CMD="cleanup"; shift ;;
    session-start) CMD="session-start"; shift ;;
    logs)   CMD="logs";   shift ;;
    # T573 · logs 专属开关（互斥关系在 cmd_logs 内统一校）
    --raw)   _need_logs "--raw";   LOGS_RAW=true;   shift ;;
    --list)  _need_logs "--list";  LOGS_LIST=true;  shift ;;
    --purge) _need_logs "--purge"; LOGS_PURGE=true; shift ;;
    --days)
      _need_logs "--days"
      LOGS_DAYS="${2:-}"
      [[ -n "$LOGS_DAYS" ]] || die "--days 需要天数参数（如 --days 3）"
      [[ "$LOGS_DAYS" =~ ^[0-9]+$ ]] || die "--days 非法: $LOGS_DAYS（须为非负整数）"
      shift 2 ;;
    --repo)
      _need_logs "--repo"
      LOGS_REPO="${2:-}"
      [[ -n "$LOGS_REPO" ]] || die "--repo 需要仓名参数（仓基键；或 all = 全部仓）"
      shift 2 ;;
    # B2/B3 · --session：用于 session-start（起 server）/ cleanup（herdr 拆场）
    #   与 -S 同风格：给参但空 ⇒ 拒；缺参 ⇒ 拒
    --session)
      case "$CMD" in
        session-start|cleanup) ;;
        *) die "--session 仅用于 session-start / cleanup 子命令：nao-fleet.sh session-start --session <名>"
      esac
      SESSION_ARG="${2:-}"
      [[ -n "$SESSION_ARG" ]] || die "--session 需要会话名参数（如 --session nao-fleet）"
      shift 2 ;;
    -S) CLEANUP_SOCK="${2:-}"; [[ -n "$CLEANUP_SOCK" ]] || die "-S 需要socket路径参数"; shift 2 ;;
    ensure) CMD="ensure"; shift ;;
    # T537 · --card：目标级修饰符，**绑定其后第一个 positional**（该 positional 即卡路径）
    --card)
      _need_ensure "--card"
      $PEND_CARD && die "--card 不能连写：每个 --card 只绑定其后的第一个目标（卡路径）"
      PEND_CARD=true; PEND_AS=""; shift ;;
    # T537 · --as：仅在同目标的 --card 之后合法（卡路径前或后皆可；重复即用法错）
    --as)
      _need_ensure "--as"
      [[ -z "$PEND_AS" ]] || die "--as 重复：每个目标只能指定一个会话名"
      PEND_AS="${2:-}"
      [[ -n "$PEND_AS" ]] || die "--as 需要会话名参数"
      if $PEND_CARD; then
        :   # 卡路径尚未到来：挂在同目标上
      elif (( LAST_CARD_IDX >= 0 )) && [[ -z "${TARGET_AS[$LAST_CARD_IDX]:-}" ]]; then
        TARGET_AS[$LAST_CARD_IDX]="$PEND_AS"; PEND_AS=""
      else
        die "--as 只能紧跟同一目标的 --card（如 ensure --card <卡路径> --as <会话名>）"
      fi
      shift 2 ;;
    -m|--model)
      MODEL="${2:-}"
      [[ -n "$MODEL" ]] || die "-m 需要模型参数"
      check_model "$MODEL" || die "模型 '$MODEL' 不在白名单内。允许: $MODEL_WHITELIST（可通过 NAO_MODEL_WHITELIST 覆盖）"
      shift 2 ;;
    # T586-B/Issue #248：显式信任开关 —— **只影响本次 spawn 的 pi**（传 `--approve`），不写任何持久配置
    --trust-project) _need_ensure "--trust-project"; TRUST_PROJECT=true; shift ;;
    --force)  FORCE=true;  shift ;;
    --task)   TASK="${2:-}"; [[ -n "$TASK" ]] || die "--task 需要任务编号（如 T1）"; [[ "$TASK" =~ ^[A-Za-z0-9_-]+$ ]] || die "--task 非法: $TASK（仅字母/数字/-/_）"; shift 2 ;;
    # T554/D7 · --fleet：**弃用** —— 给参但空仍是用法错；非空 ⇒ 恰一行 warn 后忽略（不校验、不影响放置）。
    --fleet)
      _need_ensure "--fleet"
      CLI_FLEET="${2:-}"
      [[ -n "$CLI_FLEET" ]] || die "--fleet 需要值（给参但空 ⇒ 拒绝）"
      FLEET_SEEN=true
      _fleet_deprecated_warn --fleet
      shift 2 ;;
    # T554/D7 · --scope：**弃用别名**（与 --fleet 同口径：给参但空拒绝；非空 ⇒ 恰一行 warn 后忽略）。
    --scope)
      _need_ensure "--scope"
      CLI_FLEET="${2:-}"
      [[ -n "$CLI_FLEET" ]] || die "--scope 需要值（给参但空 ⇒ 拒绝）"
      SCOPE_SEEN=true
      _fleet_deprecated_warn --scope
      shift 2 ;;
    --strict) STRICT=true; shift ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -h|--help) usage ;;
    *)
      if $PEND_CARD; then
        TARGETS+=("$1"); TARGET_CARD+=("$1"); TARGET_AS+=("$PEND_AS")
        LAST_CARD_IDX=$(( ${#TARGETS[@]} - 1 )); PEND_CARD=false; PEND_AS=""
      else
        TARGETS+=("$1"); TARGET_CARD+=(""); TARGET_AS+=(""); LAST_CARD_IDX=-1
      fi
      shift ;;
  esac
done
# 悬挂修饰符：命令末尾缺目标 ⇒ 用法错（非 0 + 单行，照 -S 守卫先例；AC7②）
if $JSON_OUT && [[ "$CMD" != "status" ]]; then
  die "--json 仅用于 status 子命令：nao-fleet.sh status --json（当前子命令：${CMD:-<无>}）"
fi
if $PEND_CARD; then die "--card 后缺少卡路径参数（该怎么办：ensure --card .agents/prompts/<name>.md）"; fi
if [[ -n "$PEND_AS" ]]; then die "--as 缺少同目标的 --card 与卡路径（该怎么办：ensure --card <卡路径> --as <会话名>）"; fi

# 后端守卫（fail loud，不静默降级）：非 herdr 的 NAO_TERMINAL ⇒ stderr 1 行 + exit 2（命令未执行）
term_backend || exit 2

# session-start：--session 必填（在一切副作用之前；herdr 实现内部再校 default/字符集/socket 前缀）
if [[ "$CMD" == "session-start" && -z "$SESSION_ARG" ]]; then
  die "session-start 需要 --session <名>（如 nao-fleet.sh session-start --session nao-fleet）"
fi

# 唯一运行前提闸门（BR1/BR3）：先于 load_manifest 与任何副作用；不满足 ⇒ exit 3（命令未执行）。
# cleanup 豁免：拆场是外部动作（`cleanup --session <名>`）。
# herdr 后端（#96 二期 B1–B3）：ensure/status/close 走 term_require（pane + protocol 闸门）；
#   闸门在此之前 ⇒ 零后端调用（用例以 PATH 桩 0 命中断言）。
# session-start 自校验（herdr = 起 server，无需已在 pane 内）
case "$CMD" in
  check)  : ;;   # cmd_check 自行先做文本契约体检，再 load_manifest（缩进违例时也能先出报告）
  session-start) : ;;
  ensure|status)
    term_require; load_manifest ;;
  close)
    term_require; load_manifest ;;
  cleanup)
    : ;;  # cleanup 不需角色清单（也不要求已在 pane 内：拆场是外部动作）
esac

# `-S` 已随 tmux 后端移除：任何子命令带上它 ⇒ stderr 恰 1 行 + exit 2 + 指路 --session（fail loud，不静默吞参）
if [[ -n "${CLEANUP_SOCK:-}" ]]; then
  printf '[fleet] -S 已随 tmux 后端移除：cleanup 改用 --session <名>（如 nao-fleet.sh cleanup --session nao-fleet）\n' >&2
  exit 2
fi
# B3 · 拆场的显式目标守卫（用法守卫 rc=2；在一切后端调用之前）
if [[ "$CMD" == "cleanup" && -z "${SESSION_ARG:-}" ]]; then
  printf '[fleet] cleanup 拒绝：须显式 --session <名>（default 已放行，但需 --force；如 --session nao-fleet）\n' >&2
  exit 2
fi

case "$CMD" in
  check)
    # 默认摘要 2–3 行（派发前自检只需 exit code + 计数 + codegraph 态；完整报告 30+ 行不进 PM 上下文）；
    #   herdr 后端另加「生效后端」行（= 3 行）；-v 或失败时展开
    # warn 计数口径：只有**非 codegraph** 的 `  ! ` 行计入摘要 warn=N；codegraph 的四类 `!` 态
    #   （CLI 不在 PATH / 无索引 / pending / 不可解析）**既不计入 warn、也不进 rc**（BR1 + arch D4）——
    #   它的可见性由常驻的第 2 行（四态之一）承担，故不会因「不计数」而静默。
    # 子 shell 隔离：cmd_check 内部 die/exit 不得吞掉报告（计数从报告解析，不靠子 shell 内变量）
    REPFILE="$(mktemp)"
    set +e
    ( cmd_check "$STRICT" ) >"$REPFILE" 2>&1
    CHECK_RC=$?
    set -e
    if (( CHECK_RC == 0 )) && ! $VERBOSE; then
      # D4（arch 裁 A）：codegraph 任态**不计入** warn 计数 —— 它是常驻第 2 行，不必重复计数；
      # 六条 CG_MSG_* 全以 `codegraph ` 开头 ⇒ 前缀匹配不误伤其它体检项（grep -c 0 命中 rc=1，|| true 别丢）。
      # M20261118：PRD 结构探针同理**不计入**（`  ! PRD 结构` 单列；「不计数的可见性」由它自己那行承担）。
      # T579：docs 索引一致性探针同理**不计入**（`  ! 索引` 单列，同上）。
      # T580：台账/开工卡结构探针同理**不计入**（`  ! 台账` 单列，同上）。
      WARNS="$(grep '^  !' "$REPFILE" | grep -v -e '^  ! codegraph ' -e '^  ! PRD 结构' -e '^  ! 索引' -e '^  ! 台账' | grep -c . || true)"
      ROLES_N="$(grep -oE '解析成功，[0-9]+ 个角色' "$REPFILE" | grep -oE '[0-9]+' | head -1 || true)"
      FILES_N="$(grep -oE '[0-9]+ 个文本文件全 LF' "$REPFILE" | grep -oE '^[0-9]+' | head -1 || true)"
      if (( WARNS > 0 )); then
        printf 'check: OK · roles=%s · files=%s · warn=%d（-v 看详情）\n' \
          "${ROLES_N:-?}" "${FILES_N:-?}" "$WARNS"
      else
        printf 'check: OK · roles=%s · files=%s\n' \
          "${ROLES_N:-?}" "${FILES_N:-?}"
      fi
      # CodeGraph 四态行常驻可见（BR9 不静默）：摘要模式下也从报告里抽这一行原样回显，
      # 保持「默认只出四态中的一行」（PRD AC1）且不额外 fork（full=0 已在报告期算完）。
      grep -m1 -E '^  . codegraph ' "$REPFILE" || true
      # M20261118：PRD 结构提示也常驻可见（与 codegraph 同口径：**不计入 warn**，可见性由它自己这行承担）
      grep -m1 -E '^  ! PRD 结构' "$REPFILE" || true
      # T579：docs 索引不一致同样常驻回显（同上：不计入 warn，但**不得**藏进 -v —— 索引是唯一发现入口）
      grep -m1 -E '^  ! 索引' "$REPFILE" || true
      # T580：台账/开工卡结构提示同样常驻回显（不计入 warn，但**不得**藏进 -v —— 台账是唯一运行态入口）
      grep -m1 -E '^  ! 台账' "$REPFILE" || true
      # B1（BR1 六条机械保证之「check 打印生效后端」）：herdr 形态（默认）⇒ 恒打印（与 -v 报告同文案）
      if [[ "$NAO_TERMINAL" == "app" ]]; then
        echo '  · 生效后端 NAO_TERMINAL=app（第二后端；status/ensure/close/cleanup 走门面；core 由 desktop app 管理；session-start 不适用）'
      else
        echo '  · 生效后端 NAO_TERMINAL=herdr（形态 TUI；desktop app 走 NAO_TERMINAL=app；#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）'
      fi
    else
      cat "$REPFILE"
    fi
    rm -f "$REPFILE"
    exit $CHECK_RC
    ;;
  status) if $JSON_OUT; then cmd_status_json; else cmd_status; fi ;;
  close)  cmd_close "$FORCE" "$TASK" "${TARGETS[0]:-}" ;;
  cleanup) cmd_cleanup ;;
  session-start) term_session_start "$SESSION_ARG" ;;
  ensure) cmd_ensure "$FORCE" "$MODEL" "$TASK" "$TRUST_PROJECT" ;;
  logs)   cmd_logs ;;
  *) usage ;;
esac
