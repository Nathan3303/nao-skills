#!/usr/bin/env bash
# =============================================================================
# nao-fleet.sh — 按角色一键拉起 pi 会话窗口（nao 团队工具箱）
#
# 运行前提（ADR 2026-10-27-strict-tmux-pi · 唯一路径）
#   必须在 tmux 会话内（$TMUX 非空且 tmux 命令可用）· pi ≥ MIN_PI_VERSION（check 断言；阈值单源，见下方常量区）
#   非 tmux ⇒ ensure/status/close 一律 exit 3 + 一行提示，且不建 session/pane/lock、不写状态（BR3）
#   cleanup 豁免本前提：其正常场景就是「非 tmux 的隔离实验场」（env -u TMUX ... -S <socket>）
#   herdr 后端（NAO_TERMINAL=herdr · #96 二期 B1/B2/B3 · 三期 P1 布局 A）：前提改为「herdr pane 内 + HERDR_SESSION
#     有效 + protocol 22」；B1 判定面（status）· B2 放置/就绪面（ensure）· B3 回收面（close/cleanup）—— 全部走门面，
#     不静默回退 tmux。**布局 A（AC3.1）**：1 workspace/仓（label=scope）+ 1 tab/角色（label=角色名）+ 每 tab 恰 1 pane；
#     放置后自测空间（HERDR 不报空间不足 ⇒ rc 不可作判据，见 TERM_MIN_COLS/ROWS 与 J1/J5）。
#     起 server 由独立入口 `session-start --session <名>` 负责（BR6：清宿主终端句柄 + 枚举清 HERDR_*）；
#     拆场由姊妹入口 `cleanup --session <名>` 负责（stop+delete，判 effect 不看 rc）。
#
# 退出码
#   0 = 成功 · 1 = 已执行但失败 · 2 = 用法守卫（cleanup 的 -S / session-start 的 --session 守卫等）
#   3 = 前提不满足（命令未执行；tmux 不在会话内 / herdr 缺会话或 protocol 不兼容）
#   4 = 本后端未实现该子命令（命令未执行；B3 后**无**此类子命令，取值保留以维持 rc 语义稳定）
#
# 用法
#   nao-fleet.sh check [--strict] [-v]            静态体检：roles.yaml/缩进/EOL/角色卡/交叉引用/PR 模板/白名单/布局/tmux+pi 前提
#                                                 默认摘要 2 行：摘要行 + codegraph 状态行（四态之一）；-v 展开完整报告（六态全展开）；失败始终展开
#   nao-fleet.sh status                           角色会话在线状态（tmux：终端标题/名册；herdr：pane label + agent 状态
#                                                 （结构化事实，权威源 pane list/agent list）；非在线证据单列）
#   nao-fleet.sh ensure <别名>[@<repo>] [更多...]  拉起角色窗口（默认工作区=roles.yaml workspace）
#   nao-fleet.sh ensure -m <model> <别名>...       显式指定模型（须命中白名单）
#   nao-fleet.sh ensure --task <编号> <别名>[@<repo>]   任务派生会话：--name <别名>-<编号>[@<scope>]（并行隔离，避免同名冲突）
#   nao-fleet.sh ensure --card <卡路径> [--as <会话名>] [--task <编号>]
#                                                 下游仓自定义角色会话（一次性）：卡须为 <repo>/.agents/prompts/<file>.md
#                                                 （卡 role 与常驻 id/别名必须前缀不相交；不入 roles.yaml、不算常驻；
#                                                  --as 须等于卡 role 或以 <role>- 为前缀，否则拒绝 —— fleet 按前缀识别身份）
#   会话名契约（BR8）：`<role>[-<task>][@<scope>]` —— scope 末位、`@` 分隔、**非空才出现**（为空时与旧名逐字相同）。
#                                                 `--as` 只给 core（含 `@` 即拒）；scope 只能由 fleet 追加。
#   --scope <slug>                                显式 scope（^[a-z0-9][a-z0-9_-]{0,15}$，≤16）；
#                                                 覆盖 `<目标仓>/.agents/fleet-scope`（该文件缺失 ⇒ 空、静默；
#                                                 存在但空/多行/非法/非常规文件/symlink 逃仓 ⇒ 一律 fail loud）。
#                                                 两仓并发**必须**设 scope，否则第二仓 ensure 同 core 会话会 fail loud。
#   nao-fleet.sh session-start --session <名>     起专用 herdr session 的 server（herdr 后端）。
#                                                 --session 必填、≠default；起 server 前**清宿主终端句柄**
#                                                 （TMUX/TMUX_PANE/TMUX_TMPDIR）+ **枚举清 HERDR_***（BR6），
#                                                 50×100ms / 5s 轮询就绪，超时 fail loud。tmux 后端无需此步（rc=0）
#   nao-fleet.sh ensure --force <别名>...          忽略"已在运行"判重
#                                                 （目标解析为 pm 时追加一条固定首条用户消息：机制包版本自检，
#                                                  仅提示不自动升级；关闭用 NAO_UPDATE_ON_ENSURE=0）
#   nao-fleet.sh close <别名|派生会话名|全名> [--task <编号>] [--force]
#                                                 回收已完成会话（派生名如 rd-be-T1；全名如 rd-be-T1@todo）；
#                                                 裸别名 = 调用者所在仓的 scope；带 `@` 的全名忽略 scope 文件
#                                                 （跨仓定位；定位失败/名册报在线但无句柄 ⇒ 非 0 + 诊断）
#                                                 （闸门：在跑 turn / tasks-state 未推进 → 拒绝，--force 跳过；
#                                                  常驻缺席而其派生在场 ⇒ 目标歧义拒绝，T516 AC3）
#                                                 herdr 后端：忙闲闸门 = agent_status（BR7）+ 名册第二信号（OR）；
#                                                 unknown / 无 agent 条目 / 集成缺失 / 进程不可判 ⇒ 拒（fail-closed）
#   nao-fleet.sh cleanup --session <名>           （herdr 后端）拆专用 session：session stop + delete，
#                                                 判 **effect** 不看 rc（stop 非幂等）；--session 必填且 ≠default（BR9）
#   nao-fleet.sh cleanup -S <socket>              终结实验场 tmux server（**强制**显式 -S socket；不看 $TMUX）
#                                                 不带 -S / 命中生产默认 socket ⇒ exit 2 + 单行拒绝（真 server 不受影响）
#                                                 ⚠ 生产默认 socket 判定 = $TMUX 句柄 + /tmp/tmux-<uid>/default（+$TMPDIR 变体），
#                                                 **与 TMUX_TMPDIR 无关**（T516 事故：夹具设 TMUX_TMPDIR 曾令真默认 socket 被放行而连坐自灭）
#                                                 ⚠ 实验纪律：一律 `env -u TMUX` + `-S <隔离 socket>`（T515 血训：
#                                                 tmux 客户端在 $TMUX 已设时无视 TMUX_TMPDIR，裸 tmux/kill-server 会连坐真 server）；
#                                                 验证脚本勿在承载自己会话的 tmux 内执行（F1 自 pane 闸门已改为
#                                                 进程归属判定 pane_hosts_caller，不再依赖 $TMUX_PANE——T530）
#
# 角色别名 → 角色卡：见 .agents/roles.yaml（单一事实来源）
#   当前：pm / arch-designer(arch) / uiux-designer(uiux, ui-designer) / rd-fe / rd-be / qa / rd-infra(infra)
#
# 环境变量
#   NAO_TMUX_LAYOUT=main-row2|main-col|grid   tmux 布局（默认 main-row2）
#   NAO_TMUX_MAIN_WIDTH=<10..90>             主 pane 宽度百分比（默认 35；main-row2/main-col 共用）
#   NAO_TMUX_MIN_PANE_WIDTH=<10..80>         最小非主 pane 列宽守卫（默认 30；低于则回退）
#   NAO_TMUX_HOST_WINDOW=<window>            显式指定派生宿主窗口（默认自动：$TMUX_PANE→名册；允许跨 session，建议 @id 形式）
#   NAO_SKILLS=<dir>                          nao 机制包根目录（默认 <脚本>/../..；项目内 shim 会显式指向包根）
#   NAO_MODEL_WHITELIST=<glob,...>            -m 白名单（默认空=不校验，支持 glob）
#   NAO_CLOSE_BUSY_PATTERN=<ERE>             close 的在跑 turn 判定正则（默认内置 pi 状态行标记）
#   NAO_TERMINAL=tmux|herdr                  终端后端（默认 tmux；herdr 侧 B1–B3：status / ensure / close / cleanup；
#                                            ensure 须先 `session-start` 起专用 session 并在其 pane 内运行）
#   NAO_HERDR_READY_TIMEOUT_MS=<ms>          herdr 就绪门 wall-clock 上限（默认 5000；只对 herdr 后端生效）
#   NAO_TERM_MIN_COLS=<n>                     herdr 放置后空间判据最小列宽（默认 60；不足只 warn 不中断）
#   NAO_TERM_MIN_ROWS=<n>                     herdr 放置后空间判据最小行数（默认 10；0 尺寸 pane ⇒ 计 SPAWN_FAIL）
#   NAO_TASKS_STATE=<path>                   任务状态文件（默认 docs/tasks-state.md，供残留检测/回收闸门）
#   NAO_UPDATE_ON_ENSURE=0|false             ensure pm 的下游版本自检注入开关（默认开；0/false ⇒ 与本批之前逐字等价）
#
# 在线判定与 pane 定位（status / close / ensure 判重共用）
#   ⚠️ pane id（%N）是 **server 局部**命名空间（每个 server 首块 pane 都是 %0）⇒ 任何「跨 server 比较
#     pane id」的判据都是错的（T530 误拒根因）；「解析句柄」与「执行 kill」必须同 server（同 $TMUX）。
#   pi 启动后用 OSC 0 把终端标题设为 "π - <会话名> - <cwd basename>" 并改写 argv
#   （/proc/<pid>/cmdline 只剩 "pi"）⇒ 不使用 `pgrep --name`（历史假阴性根因）。
#   ⚠️ 标题可能被外部改写（PM 实测变为 "pi:c"）⇒ pane 定位按三层后备（find_pane_for）：
#     ① 终端标题契约（最快）
#     ② pi-intercom 名册 tmuxPane（注册时读 $TMUX_PANE；与标题改名无关，权威）
#     ③ 本仓「未被认领 pi pane」唯一兜底（启发式；歧义即 warn，不猜）
#   名册由 intercom-probe.mts（一次调用、进程内缓存，含 tmuxPane）取；探针不可用回退
#   pi-intercom 官方 cli.ts（无 tmuxPane），再不可用回退 tmux 会话名。
#
# tmux 宿主行为（唯一路径）
#   - 以派生宿主窗口（调用者 pane 所在 window）分屏拉起，不新建窗口；
#     显式 `-t @<window_id>` 目标（定位链：NAO_TMUX_HOST_WINDOW > $TMUX_PANE > 名册唯一命中；
#     否则 warn + 跳过该 pane，不落入当前窗口）
#   - main-row2：第 1 个 pane 全高占左，后续每角色往右开列、每列上下 2 个（默认）：
#                 1 | 2 | 4
#                 1 | 3 | 5
#   - main-col：第 1 个 pane 全高占左，其余 pane 在右列纵向堆叠（委托内建 main-vertical）：
#                 1 | 2
#                 1 | 3
#                 1 | 4
#   - grid：所有 pane 等大网格（tmux 内建 tiled），宽度最优。
#   - 窄列守卫：main-row2 的最窄非主 pane < NAO_TMUX_MIN_PANE_WIDTH ⇒ 回退 main-col；
#              回退后右列仍不足 ⇒ 再回退 grid（带 warn，不中断 ensure）。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${NAO_SKILLS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROMPTS_DIR="$SKILLS_DIR/.agents/prompts"
COMMON_DIR="$SKILLS_DIR/.agents/common"
SKILLS_SUB="$SKILLS_DIR/.agents/skills"

# pi 运行前提（ADR 2026-10-27-strict-tmux-pi）的**单源**：check 文案与比较判据全部由它派生，
#   脚本内禁再出现该版本的字面量（tests/t4 用例 06 静态兜住）。改阈值只改这一行。
MIN_PI_VERSION="1.4.0"
# 派生比较阈值（major / minor）：判据里不得重敲数字；patch 不参与比较（准入只认版本线）
MIN_PI_MAJOR="${MIN_PI_VERSION%%.*}"
MIN_PI_MINOR="${MIN_PI_VERSION#*.}"
MIN_PI_MINOR="${MIN_PI_MINOR%%.*}"

# ---- 终端后端（#96 二期 B1 · PRD 附二「门面 + 双实现并存」）----
# 默认值**唯一赋值点**：全脚本 `grep -cE '^NAO_TERMINAL='` 必须恰 1 处（tests/t4 静态 lint 断言）。
# 三期 herdr 转默认只改这一行；本批 tmux 仍是默认（BR1 零回归）。
NAO_TERMINAL="${NAO_TERMINAL:-tmux}"
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
trap 'rm -f "${_TERM_SNAP_PATH:-}" 2>/dev/null || true' EXIT

MANIFEST="$SKILLS_DIR/.agents/roles.yaml"
CARD_MAX_LINES=200
# T537 · 下游仓自定义角色会话（ensure --card）：卡正文 = 系统提示，故有硬边界（BR3）与命名契约（BR9）
CARD_MAX_BYTES=262144                    # 256 KiB：超限即拒（卡正文会整段塞进 system prompt）
CARD_SET_MAX=30                          # 卡集上限（锚根 ≤2）：超出只 warn 一行，不拒
CARD_RESERVED_PREFIXES="subagent- nao-"  # T525/T527 保留前缀（命中 ⇒ 会话拉起即失联）
ROLE_ORDER=()
NAME=""; PROMPT=""
declare -A ROLE_CARDS ROLE_WS ALIAS_ROLE
MODEL_WHITELIST="${NAO_MODEL_WHITELIST:-}"
TMUX_LAYOUT="${NAO_TMUX_LAYOUT:-main-row2}"
# main-row2 主 pane 宽度百分比：默认值与非法值回退共用同一常量（防三处漂移）
TMUX_MAIN_WIDTH_DEFAULT=33
TMUX_MAIN_WIDTH="${NAO_TMUX_MAIN_WIDTH:-$TMUX_MAIN_WIDTH_DEFAULT}"
# 最小非主 pane 列宽守卫：默认值与非法值回退共用同一常量（防漂移）
TMUX_MIN_PANE_WIDTH_DEFAULT=30
TMUX_MIN_PANE_WIDTH="${NAO_TMUX_MIN_PANE_WIDTH:-$TMUX_MIN_PANE_WIDTH_DEFAULT}"
# T517：派生宿主窗口 ID（归一化 @<window_id>；空 = 定位失败 ⇒ 该角色 pane warn+skip，禁无 -t 续建）
HOST_WINDOW=""
# T536：本轮真正创建成功的 pane 数（>0 ⇒ ensure 收尾打印**恰一行**就绪提示；跳过/失败分支恒 0，BR3/AC4）
# T539：三态计数（成功 / 跳过 / 失败）—— 每个 ensure 目标恰落一类，合计 = 目标数（BR3 计数守恒）
SPAWN_OK=0
SPAWN_SKIP=0
SPAWN_FAIL=0
# T539/BR2：spawn_tmux 的**显式**结果契约（返回值；调用方禁用「没打印就是成功」这类隐式约定）：
#   0 = 成功（pane 已创建）· 2 = 跳过（宿主窗口未解析，未创建）· 3 = 失败（split-window 非 0，未创建）
SPAWN_RC_OK=0
SPAWN_RC_SKIP=2
SPAWN_RC_FAIL=3
# check 输出契约：默认摘要 2 行（摘要行 + codegraph 状态行，四态之一），-v 展开完整报告（六态全展开）；失败始终展开
VERBOSE=false
# close 的在跑 turn 判定（pi 默认状态行：Working (esc to interrupt) / Thinking... / Retrying / Compacting）
CLOSE_BUSY_PATTERN="${NAO_CLOSE_BUSY_PATTERN:-Working \(|Thinking\.\.\.|to interrupt|to cancel|Retrying \(|Compacting|Summarizing branch}"
# 任务状态文件（相对当前目录；供残留检测与回收闸门）
TASKS_STATE="${NAO_TASKS_STATE:-docs/tasks-state.md}"

# ---- CodeGraph（T532 · BR1/BR2）：四态检测全 warn，**永不计入 rc** ----
# 包名单源（BR5）：与 bin/nao-skill.js 的 PI_PLUGINS.codegraph 各一处，由 tests/t4/cases/18 等值断言兜住。
# 运行时**不**跨语言抽取（sed 抽空 ⇒ 静默假「未声明」，且 shim-only 安装可能无 bin/）。
CODEGRAPH_PKG="@sean_pedersen/pi-codegraph"

# ---- ensure pm：下游机制包版本自检（M20261103 · PRD 2026-11-03-ensure-pm-update-check R1–R6）----
# 注入文本是**常量**（R3 六要素齐备，grep 可自证）：fleet 进程内零外部命令、零网络（NFR），
#   实际检查由 PM 会话自己按文本执行；未获用户同意前不得改文件/升级（R5）。
# 开关（R6）：NAO_UPDATE_ON_ENSURE=0/false ⇒ 不注入（命令行与本批之前逐字等价）。
NAO_UPDATE_MSG='【nao 机制包版本自检 · ensure pm 注入 · 仅提示，不自动升级】
这条自检是本回合唯一额外动作；一行汇报后立即回到用户原来的消息，不要展开其它话题。
1) 本地 pin：读 .pi/settings.json 里 @nathan33/nao-skill 的版本（X）；本仓若无该文件或无此 pin ⇒ 直接走 4 的情形 ④（不要说成必然有 pin）。
2) 远端最新版：npm view @nathan33/nao-skill version --fetch-timeout=5000（内置 5s 超时；不要用外部 timeout 命令，macOS 原生没有；超时/报错 ⇒ 情形 ③）。
3) 仅当有新版（Y 大于 X）才取要点：gh release view v<Y>（要点压成不超过两句，不要贴全文）；无 gh 或取不到 ⇒ 情形 ⑤。
4) 只输出以下**恰好一行**（按 ①–⑤ 顺序命中即止，不解释、不追加）：
   ① 有新版：当前 X → 可升 Y（要点）。要升吗？
   ② 已最新：版本检查：已是最新 X。
   ③ 离线或超时：版本检查：离线或超时，跳过（可稍后手动 npx @nathan33/nao-skill --version 核对）。
   ④ 未检测到下游 pin：版本检查：未检测到下游 pin（本仓为机制源），跳过。
   ⑤ 无 gh 只报版本号：版本检查：当前 X → 可升 Y（要点取不到，见 https://github.com/Nathan3303/nao-skills/releases）。要升吗？
5) 硬约束：检查阶段只读；**未获我同意前不要改任何文件、不要升级**（不改 .pi/settings.json、不跑 pi install / pi update）。
6) 只有我明确同意后才按序执行：pi install -l npm:@nathan33/nao-skill@<Y>（若提示安装脚本授权，停下来交给我确认，不要自行放行）→ pi update --extensions → 提醒我「本轮会话仍是旧角色卡，建议重开」。
7) 我未表态或说稍后：原样待命，不要重试、不要轮询、不要后台检查。'

# R1/R6：开关判定（默认开；仅显式 0/false 关闭）
update_check_enabled() {
  case "${NAO_UPDATE_ON_ENSURE:-1}" in
    0|[Ff][Aa][Ll][Ss][Ee]) return 1 ;;
  esac
  return 0
}
# 状态文案单点（CG_MSG_*）：用例断言只认**固定前缀 + 命令子串**，不断言整行（防文案微调误伤）。
CG_MSG_UNDECLARED='codegraph 插件未声明（装法：pi install npm:@sean_pedersen/pi-codegraph；定位回退 grep）'
CG_MSG_NO_CLI='codegraph 插件已声明但 CLI 不在 PATH（装：npm i -g @colbymchenry/codegraph；回退 grep -rn + 行段）'
CG_MSG_NO_INDEX='codegraph 已就绪但当前仓无索引（codegraph init；索引后每会话约 +70–90MB PSS）'
CG_MSG_READY='codegraph 齐备（生效还依赖插件未被过滤/禁用）'
CG_MSG_READY_SHORT='codegraph 齐备（索引新鲜度用 -v 查；生效依赖插件未被过滤/禁用）'
CG_MSG_PENDING='codegraph 索引 pending（codegraph sync 同步）'
CG_MSG_UNPARSABLE='codegraph status 输出不可解析（手工 codegraph status 核对）'

log()  { printf '\033[1;32m[fleet]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fleet]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fleet]\033[0m %s\n' "$*" >&2; exit 1; }
# 唯一运行前提（BR1/BR3 · ADR 2026-10-27-strict-tmux-pi）：$TMUX 非空且 tmux 可用。
# 不满足 ⇒ exit 3 + 单行提示；调用点在建 session / load_manifest / 写状态**之前**（失败零副作用）。
# rc 语义：3 = 前提不满足 ⇒ 命令未执行；不复用 1（已执行但失败）/ 2（用法守卫，现仅 cleanup）。
require_tmux() {
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then return 0; fi
  printf '需要 tmux：nao-fleet 只支持在 tmux 会话内运行（先 `tmux new -s nao`，再在该会话内重试）\n' >&2
  exit 3
}

# =============================================================================
# 终端后端门面（#96 二期 B1 · PRD 附二「门面 + 双实现并存」）
#
#   契约：**业务区只调** term_require / term_snapshot / term_liveness / term_argv /
#         term_spawn / term_session_start / term_reclaim / term_cleanup（+ 纯谓词 term_deliverable）。
#         后端差异只允许出现在本区间与 `# >>> term-impl-tmux` 区间
#         （静态 lint：tests/t4/lib.sh::t4_scan_term_bare_calls）。
#   默认值唯一：常量区的 `NAO_TERMINAL="${NAO_TERMINAL:-tmux}"` 是全脚本**唯一**赋值点。
#   herdr 侧纪律（BR2/BR3/BR6）：身份取 pane.label（+ argv --name 交叉校验）、归属取
#         pane.cwd/foreground_cwd（谓词复用 repo_contains_path）、忙闲取 agent_status +
#         state_change_seq（权威源 = pane list / agent list；`agent explain` 只作诊断、禁作判据）；
#         **一律不读终端标题**，也**不把宿主 tmux 的句柄变量当证据** —— 从 tmux shell 起的
#         herdr server 会把外层句柄渗进 pane（spike 实测），拿来判身份必串台。
#   rc 语义：4 = 保留（B3 后无未实现子命令）；1 = 已执行但失败；3 = 前提不满足；2 = 用法守卫。
# >>> term-facade BEGIN
term_backend() {
  case "${NAO_TERMINAL:-}" in
    tmux|herdr) printf '%s\n' "$NAO_TERMINAL" ;;
    *)
      printf '[fleet] NAO_TERMINAL=%s 非法（期望 tmux|herdr）\n' "${NAO_TERMINAL:-<空>}" >&2
      return 1 ;;
  esac
}

# ---- 1/4 前提闸门 ----
term_require() {
  case "$(term_backend)" in
    tmux) require_tmux ;;
    herdr) _term_herdr_require ;;
  esac
}

# ---- 2/4 快照（每命令 ≤1 次 pane list / agent list；herdr 侧落临时文件，子 shell 复用同一份）----
# 11 列（TAB）：name pane_id terminal_id cwd foreground_cwd fg_process
#               agent_status state_change_seq agent_session argv_name hook_authority
#   tmux：由既有 visible_session_names / pane_cwd_snapshot 合成，新列一律 `-`（语义零改动）
#   herdr：pane list + agent list 按 pane_id join；只对带 label 的 pane 各取一次 process-info
term_snapshot() {
  case "$(term_backend)" in
    tmux) _term_tmux_snapshot ;;
    herdr)
      local f="${_TERM_SNAP_FILE:-${_TERM_SNAP_PATH:-${TMPDIR:-/tmp}/nao-fleet-term-snap.$$}}"
      # 判据用「文件存在」而非「非空」：**无 label 会话时快照合法为空** —— 用 -s 会每调用重建
      #   （QA P3-1 实测 status 退化成 pane list ×7 / agent list ×7）。
      if [[ -e "$f" ]]; then _TERM_SNAP_FILE="$f"; cat "$f"; return 0; fi
      # 上一轮被 SIGKILL/timeout 杀掉时会留下同名快照（EXIT trap 不执行）⇒ 只在**重建**时清 >2h 的陈迹
      find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nao-fleet-term-snap.*' -mmin +120 -delete 2>/dev/null || true
      if ! _term_herdr_snapshot > "$f"; then
        rm -f "$f" 2>/dev/null || true; _TERM_SNAP_FILE=""
        return 1
      fi
      _TERM_SNAP_FILE="$f"
      cat "$f" ;;
  esac
}

# ---- 3/4 在线判定 → "<verdict>\t<state>\t<seq>\t<hook_authority>" ----
#   verdict：online | absent | ghost | dead | mismatch | integration-missing
#   阶梯（定序，避免一条残留同时进多桶）：absent → ghost → dead → mismatch →
#   integration-missing → online；`hook_authority` = agent list 的 screen_detection_skipped
#   （1 = 状态来自生命周期 hook（可信）/ 0 = 屏幕启发式或缺失（保守不可投递））。
term_liveness() {  # <name> [repo]
  case "$(term_backend)" in
    tmux) _term_tmux_liveness "${1-}" "${2-}" ;;
    herdr) _term_herdr_liveness "${1-}" "${2-}" ;;
  esac
}

# ---- 4/4 前台 argv（herdr 取全部前台进程；tmux 只给命令名 ⇒ argv 列留空，不得用 ps 兜底）----
term_argv() {  # <pane_id> → 每行 "process-name<TAB>argv"
  case "$(term_backend)" in
    tmux) _term_tmux_argv "${1-}" ;;
    herdr) _term_herdr_argv "${1-}" ;;
  esac
}

# ---- 5/8 放置（B2 + 三期 P1 布局 A）：tmux = split-window / herdr = 1 workspace/仓 + 1 tab/角色 ----
# herdr 侧：tab label = 角色名，每 tab 恰 1 pane（结构判据，零几何算式）；既有 pane 若在共享 tab 里
#   ⇒ `pane move --new-tab` + `tab rename` 迁移（pane_id 不变、被搬空的 tab 由 herdr 自动关闭）。
# 返回三态码（SPAWN_RC_*）：0 成功 · 2 跳过 · 3 失败（含就绪超时 / 0 尺寸 pane；调用方计入 SPAWN_FAIL）。
term_spawn() {  # <name> <inner> <repo> [force]
  case "$(term_backend)" in
    tmux) spawn_tmux "${1-}" "${2-}" ;;
    herdr) _term_herdr_spawn "${1-}" "${2-}" "${3-}" "${4:-false}" ;;
  esac
}

# ---- 6/8 起 server（B2 · BR6）：herdr 唯一生产入口；tmux 幂等无害（server 随会话自动起）----
term_session_start() {  # <session>
  case "$(term_backend)" in
    tmux) printf '[fleet] tmux 后端无需 session-start（server 随会话自动起）\n'; return 0 ;;
    herdr) _term_herdr_session_start "${1-}" ;;
  esac
}

# ---- 7/8 回收（B3）：句柄层（定位 / self 判据 / liveness / 忙闲证据 / 回收句柄）双实现 ----
#   共用闸门层（tasks-state、subagent 拒收、目标解析、--force）仍在 cmd_close，**不动**。
#   返回 0 = 已回收 / 未运行（幂等成功）；1 = 拒绝或已执行但失败（含 effect 未达成）。
term_reclaim() {  # <name> <repo> <force> <core> <scope> <ensure-target>
  case "$(term_backend)" in
    tmux) _term_tmux_reclaim "${1-}" "${2-}" "${3-}" "${4-}" "${5-}" "${6-}" ;;
    herdr) _term_herdr_reclaim "${1-}" "${2-}" "${3-}" "${4-}" "${5-}" "${6-}" ;;
  esac
}

# ---- 8/8 拆场（B3 姊妹入口）：tmux = 终结隔离 server（socket 为显式目标）；herdr = session stop+delete ----
#   herdr 的 stop **非幂等**（第二次 rc=1）⇒ 判 **effect** 不看 rc；default 一律拒（BR9）。
term_cleanup() {  # <tmux-socket> <herdr-session>
  case "$(term_backend)" in
    tmux) _term_tmux_cleanup "${1-}" ;;
    herdr) _term_herdr_cleanup "${2-}" ;;
  esac
}

# ---- 9/9 当前终端会话名（诊断行用；B4 起取代 cmd_check 的裸 `tmux display-message`）----
#   tmux = 当前 client 的 session 名（无 client/失败 ⇒ 空，调用方给 `?`）；herdr = HERDR_SESSION。
term_session_name() {
  case "$(term_backend)" in
    tmux) _term_tmux_current_session ;;
    herdr) printf '%s\n' "${HERDR_SESSION:-}" ;;
  esac
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

# tmux 侧快照：由既有两函数合成（**不改**它们的签名/行为 —— close/ensure 仍直接用）
_term_tmux_snapshot() {
  local n p c
  local -A emitted=()
  while IFS=$'\t' read -r n p c; do
    [[ -n "$n" ]] || continue
    printf '%s\t%s\t-\t%s\t-\t-\t-\t-\t-\t-\t-\n' "$n" "$p" "$c"
    emitted["$n"]=1
  done < <(_term_tmux_pane_cwds)
  # 无 pane 的会话名（tmux 会话 nao-*）：pane/cwd 列留空
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    [[ -n "${emitted[$n]:-}" ]] && continue
    printf '%s\t\t-\t\t-\t-\t-\t-\t-\t-\t-\n' "$n"
  done < <(_term_tmux_names)
}
# >>> term-facade-herdr BEGIN
# herdr 后端实现（本区间**禁出现** tmux 句柄/标题字段名：静态 lint t4_scan_term_herdr_forbidden）
#   会话名来源 = 环境变量 HERDR_SESSION（herdr pane 内天然存在）；所有调用经唯一入口注入 --session。
_term_herdr_exec() {  # 唯一入口：--session 由此注入（调用方无法绕过）
  local s="${HERDR_SESSION:-}" v
  if [[ -z "$s" || "$s" == "default" ]]; then
    warn "herdr 调用缺会话（HERDR_SESSION 空或 default）—— 拒绝执行（BR6④：无 --session 会静默读到用户 default）"
    return 1
  fi
  # BR6（B2）：起 server 的**唯一**实现点 —— 清宿主终端句柄（三项，名表在通用区声明）+ **枚举**清 HERDR_*
  #   （只 -u 已知变量会漏）；setsid 脱离进程组（无 setsid 的平台降级为普通后台）。
  if [[ "${_TERM_HERDR_SERVER_START:-0}" == "1" ]]; then
    local -a hu=() pre=()
    for v in "${_TERM_HOST_HANDLE_VARS[@]}"; do hu+=(-u "$v"); done
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
    printf '需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试，或 NAO_TERMINAL=tmux 回退）\n' >&2
    exit 3
  }
  if [[ "${HERDR_ENV:-}" != "1" ]]; then
    printf '需要 herdr pane：HERDR_ENV=1 缺失（herdr 后端只在其 pane 内运行；从外部推断会话名属猜测面，禁）\n' >&2
    exit 3
  fi
  local s="${HERDR_SESSION:-}" sp="${HERDR_SOCKET_PATH:-}" root rootp spp
  if [[ -z "$s" || "$s" == "default" || ! "$s" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf '需要 herdr 会话：HERDR_SESSION=%s 不可用（须非空、≠default、^[A-Za-z0-9._-]+$）\n' "${s:-<空>}" >&2
    exit 3
  fi
  # BR6：socket 必须落在**目标根**下（不是「任意 */sessions/<名>/*」——后者对 stale/外贸 env 等于死守卫）。
  #   根 = `${XDG_CONFIG_HOME:-$HOME/.config}/herdr`（与 herdr CLI 的会话目录推导同源）。
  root="${XDG_CONFIG_HOME:-$HOME/.config}/herdr"
  rootp="$(_term_path_norm "$root/sessions/$s")"
  spp="$(_term_path_norm "$sp")"
  if [[ -z "$sp" || "$spp" != "$rootp"/* ]]; then
    printf '需要 herdr 会话目录：HERDR_SOCKET_PATH=%s 不在目标根 %s/ 下（stale/外贸 env ⇒ 拒绝，防串台）\n' \
      "${sp:-<空>}" "$rootp" >&2
    exit 3
  fi
  local schema proto
  if ! schema="$(_term_herdr_exec api schema 2>/dev/null)"; then
    printf 'herdr api schema 不可用（server/CLI 异常）：无法校验 protocol ⇒ 拒绝执行\n' >&2
    exit 3
  fi
  proto="$(printf '%s\n' "$schema" | sed -n 's/^protocol:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
  if [[ "$proto" != "$TERM_HERDR_PROTOCOL" ]]; then
    printf 'herdr protocol=%s ≠ %s（破坏性变更 ⇒ fail loud，不静默降级；请升级 nao-skill 或回退 NAO_TERMINAL=tmux）\n' \
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
  local label cwd fgcwd astat tid fg pname avline avname st
  while IFS= read -r obj; do
    label="$(_term_json_str "$obj" label)"
    [[ -n "$label" ]] || continue
    pid="$(_term_json_str "$obj" pane_id)"
    tid="$(_term_json_str "$obj" terminal_id)"
    cwd="$(_term_json_str "$obj" cwd)"
    fgcwd="$(_term_json_str "$obj" foreground_cwd)"
    astat="$(_term_json_str "$obj" agent_status)"
    fg=""; avname=""
    while IFS=$'\t' read -r pname avline; do
      [[ -n "$pname" ]] || continue
      [[ -n "$fg" ]] || fg="$pname"
      if [[ "$pname" == "pi" ]]; then
        fg="pi"; avname="$(_term_argv_name "$avline")"; break
      fi
    done < <(_term_herdr_argv "$pid")
    st="${ag_stat[$pid]:-}"; [[ -n "$st" ]] || st="${astat:--}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$label" "$pid" "${tid:--}" "${cwd:--}" "${fgcwd:--}" "${fg:--}" \
      "$st" "${ag_seq[$pid]:--}" "${ag_sess[$pid]:--}" "${avname:--}" "${ag_hook[$pid]:-0}"
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
    IFS=$'\t' read -r _ _ _ _ _ fg astat seq sess avname hook <<< "$line"
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
  vline="$(term_liveness "$name")"
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
  log "已回收 $name（herdr pane $pane）@ $pcwd"
  return 0
}

# 单行快照行 → verdict（与 term_liveness 同一阶梯，供「同名多 pane」逐行判定）
_term_herdr_row_verdict() {  # <name> <row>
  local name="${1-}" line="${2-}" fg="" astat="" seq="" sess="" avname="" hook=""
  IFS=$'\t' read -r _ _ _ _ _ fg astat seq sess avname hook <<< "$line"
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
  vline="$(term_liveness "$name")"
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
_term_herdr_cleanup() {  # <session>
  local s="${1-}" root rootp sp spp dir prev rc=0
  command -v herdr >/dev/null 2>&1 || {
    printf '需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试，或 NAO_TERMINAL=tmux 回退）\n' >&2
    return 2
  }
  case "$s" in
    ""|"default")
      printf '需要 herdr 会话名：%s 不可用（cleanup 必填 --session 且 ≠default —— default 是用户会话，BR9）\n' "${s:-<空>}" >&2
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
  local pid="${1-}" js obj
  [[ -n "$pid" ]] || return 0
  js="$(_term_herdr_exec pane list 2>/dev/null)" || return 0
  while IFS= read -r obj; do
    [[ "$(_term_json_str "$obj" pane_id)" == "$pid" ]] || continue
    printf '%s\t%s\n' "$(_term_json_str "$obj" tab_id)" "$(_term_json_str "$obj" workspace_id)"
    return 0
  done < <(_term_json_objs <<< "$js")
  return 0
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
    warn "            ③ 切布局：export NAO_TERMINAL=tmux（回退 tmux 后端）"
    warn "  文档：docs/INSTALL.md「herdr 后端」· docs/prds/2026-11-10-herdr-base.md AC3.2（J1–J5）"
    return 1
  fi
  if (( w < TERM_MIN_COLS || h < TERM_MIN_ROWS )); then
    warn "空间不足：$name（pane=$pid）列=$w < ${TERM_MIN_COLS} 或 行=$h < ${TERM_MIN_ROWS} —— 仅 warn，不中断（rc 语义跨后端一致）"
    warn "  该怎么办：① 调 [server] headless_cols/headless_rows（config.toml）放大后重启会话（cleanup + session-start）"
    warn "            ② attach 后重排：herdr session attach ${HERDR_SESSION:-<session>}，再调整窗口/分屏"
    warn "            ③ 切布局：export NAO_TERMINAL=tmux（回退 tmux 后端）"
    warn "  文档：docs/INSTALL.md「herdr 后端」· docs/prds/2026-11-10-herdr-base.md AC3.2（J1–J5）"
  fi
  return 0
}

# J2 结构收敛（布局 A）：本角色 pane 必须独占一个 tab，且该 tab label = 角色名。
#   旧布局（一个 tab 内 split 出多 pane）⇒ 迁移无损：`pane move <pane> --new-tab`（pane_id 不变，
#   被搬空的 tab 由 herdr 自动关闭）+ `tab rename` 把新 tab 标成角色名；
#   tab 已独占但 label 旧（如根 tab 的 "1"）⇒ 只改 tab 名（effect 零风险）。
_term_herdr_layout_converge() {  # <pane_id> <name> → 0 布局 A 达成 / 1 未达成（fail loud）
  local pid="${1-}" name="${2-}" pt tid wsid row label cnt js newtid prev_tid="" closed_note=""
  pt="$(_term_herdr_pane_tab "$pid")"
  if [[ -z "$pt" ]]; then
    warn "布局判据不可用：pane=$pid 不在 pane list（无法确认独立 tab）⇒ 计 SPAWN_FAIL"
    return 1
  fi
  tid="${pt%%$'\t'*}"; wsid="${pt#*$'\t'}"
  row="$(_term_herdr_tab_row "$wsid" "$tid")"
  label="${row%%$'\t'*}"; cnt="${row#*$'\t'}"
  if [[ "$label" == "$name" ]]; then
    if [[ "$cnt" != "1" ]]; then
      warn "布局 A 违例：tab=$tid（label=$name）含 ${cnt:-?} 个 pane（契约 = 每角色 tab 恰 1 pane）；不擅自搬动他人 pane"
      warn "  该怎么办：attach 后人工收口（herdr session attach ${HERDR_SESSION:-<session>}），或 cleanup 后 session-start 重建会话"
    fi
    return 0
  fi
  if [[ "$cnt" == "1" ]]; then
    if _term_herdr_exec tab rename "$tid" "$name" >/dev/null 2>&1; then return 0; fi
    warn "tab rename 失败（tab=$tid → label=$name）⇒ 布局 A 未达成（计 SPAWN_FAIL）"
    return 1
  fi
  js="$(_term_herdr_exec pane move "$pid" --new-tab 2>/dev/null)" \
    || { warn "pane move --new-tab 失败（pane=$pid name=$name）⇒ 布局 A 未达成（计 SPAWN_FAIL）"; return 1; }
  prev_tid="$tid"
  newtid="$(printf '%s' "$js" | sed -nE 's/.*"created_tab":\{[^}]*"tab_id":"([^"]+)".*/\1/p' | head -1)"
  if [[ -z "$newtid" ]]; then pt="$(_term_herdr_pane_tab "$pid")"; newtid="${pt%%$'\t'*}"; fi
  [[ -n "$newtid" ]] || { warn "pane move 后未取到新 tab_id（pane=$pid name=$name）⇒ 布局 A 未达成"; return 1; }
  if ! _term_herdr_exec tab rename "$newtid" "$name" >/dev/null 2>&1; then
    warn "tab rename 失败（tab=$newtid → label=$name）⇒ 布局 A 未达成（计 SPAWN_FAIL）"; return 1
  fi
  if [[ -n "$(_term_herdr_tab_row "$wsid" "$prev_tid")" ]]; then
    closed_note="源 tab $prev_tid 仍有其他 pane（未关闭）"
  else
    closed_note="被搬空的 tab $prev_tid 已由 herdr 自动关闭"
  fi
  log "[herdr] 布局 A 迁移：$name（pane=$pid）已搬到独立 tab $newtid（pane_id 不变；$closed_note）"
  return 0
}

_term_herdr_spawn() {  # <name> <inner> <repo> [force] → SPAWN_RC_OK|FAIL
  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="" pout="" pl="" obj js
  local pane="" wsid="" tid="" first="" nmatch=0 hit="" verdict="" seq="" launched=0
  [[ -n "$name" && -n "$inner" ]] || { warn "herdr spawn 参数缺失（name/inner）"; return "$SPAWN_RC_FAIL"; }
  # workspace 匹配键 = scope（无 scope ⇒ 会话名）：WorkspaceInfo 无 cwd/worktree 字段 ⇒ 只能按 label；
  #   label 匹配同时满足一期契约「名字是路由标签」与重跑幂等（不会重复建 workspace）。
  pout="$(fleet_name_parse "$name")"
  if [[ "$pout" == "OK "* ]]; then IFS=',' read -r _ _ _ label <<< "${pout#OK }"; fi
  [[ -n "$label" ]] || label="${HERDR_SESSION:-}"
  [[ -n "$label" ]] || { warn "herdr spawn 无法确定 workspace label（名字无 scope 且 HERDR_SESSION 空）"; return "$SPAWN_RC_FAIL"; }

  # ---- 同名 label 已在场：0 ⇒ 正常放置；1 ⇒ 按证据分派；>1 ⇒ warn + 不猜 ----
  pl="$(_term_herdr_exec pane list 2>/dev/null)" || { warn "herdr pane list 失败（server 未就绪？）"; return "$SPAWN_RC_FAIL"; }
  while IFS= read -r obj; do
    [[ -n "$(_term_json_str "$obj" pane_id)" ]] || continue
    [[ "$(_term_json_str "$obj" label)" == "$name" ]] || continue
    nmatch=$((nmatch + 1))
    hit="${hit}${hit:+ }$(_term_json_str "$obj" pane_id)"
  done < <(_term_json_objs <<< "$pl")
  if (( nmatch > 1 )); then
    warn "同名 label 命中多个 pane：$name ⇒ $hit（不猜：既不判「已在运行」，也不擅自选一个）"
    warn "  该怎么办：先人工核对/清理重复 label（回收面归 B3），再重跑 ensure"
    return "$SPAWN_RC_FAIL"
  fi
  if (( nmatch == 1 )); then
    pane="$hit"
    local vline fgname probe pstate pmsg
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
        pane=""
        ;;
      ok)
        while IFS=$'\t' read -r fgname _; do
          [[ -n "$fgname" ]] && fgnames+=("$fgname")
        done < <(_term_herdr_argv "$pane")
        if (( ${#fgnames[@]} == 0 )); then
          # pane 可达但前台不可判（空进程表）⇒ **不 close**、不注入，fail loud
          warn "前台不可判（$name ⇒ $pane：process-info 无前台进程）⇒ 不关闭、不注入、不判「已在运行」"
          warn "  该怎么办：先回收该角色（nao-fleet.sh close ${name%%@*}）再 ensure；--force 不绕过本条（仍不会新建重复 label）"
          return "$SPAWN_RC_FAIL"
        elif _term_fg_list_is_shell "${fgnames[@]}"; then
          # 前台是交互式 shell ⇒ 可以安全把启动命令送进去；label 在、agent 无 = **不判「已在运行」**（不静默跳过）
          warn "label 已在场但不在线（幽灵 pane / stale：$name ⇒ $pane，verdict=$verdict 前台=${fgnames[*]}）⇒ 不判「已在运行」，复用该 pane 重跑 agent"
        elif $force; then
          # --force：显式要一个新会话；**不向在场程序注入按键**（会污染 vim/REPL/cat 的输入）。
          #   随后按布局 A 放置：角色 tab 已被占用 ⇒ fail loud（不新建重复 tab/label）；
          #   旧 pane 在共享 tab 里才可能新建独立 tab（旧 label 仍在 ⇒ status 会标同名歧义）。
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
      pane=""
    fi
  fi

  # ---- 放置（三期 P1 · AC3.1 布局 A）：1 workspace/仓（label=scope）+ 1 tab/角色（label=角色名）+ 每 tab 恰 1 pane
  #   · 新 pane 永远开在**角色 tab** 里（不再把多个角色 split 进同一个 tab ⇒ 零几何算式）；
  #   · 空 workspace（pane 全关）⇒ 关旧建新（同名 label 仍唯一）；
  #   · 角色 tab 已在场但无 pane 命中该角色 ⇒ **不猜**（fail loud：可能是 --force 撞上仍在场的 pi）。
  if (( ! launched )); then
    wsid="$(_term_herdr_workspace_id_for "$label")"
    if [[ -n "$wsid" ]]; then
      js="$(_term_herdr_exec pane list --workspace "$wsid" 2>/dev/null)" \
        || { warn "herdr pane list --workspace $wsid 失败"; return "$SPAWN_RC_FAIL"; }
      first="$(_term_json_str "$js" pane_id)"
      if [[ -z "$first" ]]; then
        # 空 workspace（pane 已被关）：先关掉空的旧 workspace，再建新的（同名 label 仍唯一）
        _term_herdr_exec workspace close "$wsid" >/dev/null 2>&1 || true
        wsid=""
      fi
    fi
    if [[ -z "$wsid" ]]; then
      js="$(_term_herdr_exec workspace create --cwd "$repo" --label "$label" --no-focus 2>/dev/null)" \
        || { warn "herdr workspace create 失败（label=$label cwd=$repo）"; return "$SPAWN_RC_FAIL"; }
      pane="$(_term_json_str "$js" pane_id)"
      wsid="$(_term_json_str "$js" workspace_id)"
      tid="$(_term_json_str "$js" tab_id)"
      [[ -n "$pane" ]] || { warn "herdr workspace create 未返回 root_pane.pane_id（label=$label）"; return "$SPAWN_RC_FAIL"; }
      # 布局 A：workspace 的根 tab 归位为角色 tab（label = 角色名）
      if [[ -z "$tid" ]] || ! _term_herdr_exec tab rename "$tid" "$name" >/dev/null 2>&1; then
        warn "herdr tab rename 失败（tab=${tid:-<无>} label=$name）⇒ 布局 A 未达成"; return "$SPAWN_RC_FAIL"
      fi
    else
      tid="$(_term_herdr_tab_id_for "$wsid" "$name")"
      if [[ -n "$tid" ]]; then
        warn "角色 tab 已在场但无 pane 命中该角色（workspace=$wsid tab=$tid label=$name）⇒ 不猜：既不新建第二个同名 tab，也不接管他人 pane"
        warn "  该怎么办：先回收该角色（nao-fleet.sh close ${name%%@*}）再重跑 ensure；--force 不绕过本条（避免同名 label 重复）"
        return "$SPAWN_RC_FAIL"
      fi
      js="$(_term_herdr_exec tab create --workspace "$wsid" --cwd "$repo" --label "$name" --no-focus 2>/dev/null)" \
        || { warn "herdr tab create 失败（workspace=$wsid label=$name cwd=$repo）"; return "$SPAWN_RC_FAIL"; }
      pane="$(_term_json_str "$js" pane_id)"
      [[ -n "$pane" ]] || { warn "herdr tab create 未返回 root_pane.pane_id（label=$name）"; return "$SPAWN_RC_FAIL"; }
    fi
    # ---- 先 label 后启动（顺序是契约：否则 status 可能抓到无 label 的 pi pane）----
    if ! _term_herdr_exec pane rename "$pane" "$name" >/dev/null 2>&1; then
      warn "herdr pane rename 失败（pane=$pane label=$name）"; return "$SPAWN_RC_FAIL"
    fi
    if ! _term_herdr_exec pane run "$pane" "$inner" >/dev/null 2>&1; then
      warn "herdr pane run 失败（pane=$pane name=$name）"; return "$SPAWN_RC_FAIL"
    fi
  fi
  _TERM_SPAWN_PANE="$pane"
  # 快照失效：本命令后续目标（判重/归属）必须看到新 pane，不得复用 spawn 前的旧快照
  if [[ -n "${_TERM_SNAP_FILE:-}" ]]; then rm -f "$_TERM_SNAP_FILE" 2>/dev/null || true; _TERM_SNAP_FILE=""; fi

  # ---- J2 结构收敛（布局 A）：复用路径也跑（旧布局的 pane 在共享 tab 里 ⇒ 迁移到独立 tab）----
  if ! _term_herdr_layout_converge "$pane" "$name"; then
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

# 就绪探针（单次）：七条件全与 ⇒ 0；结果落 _TR_* 供超时时**逐条**报缺。
_term_herdr_ready_state() {  # <pane_id> <expected name>
  local pid="${1-}" want="${2-}" pl="" al="" js="" obj av nm sess stat seq skip
  _TR_PANE=0; _TR_FG=""; _TR_ARGV=""; _TR_SESS=0; _TR_STAT=""; _TR_SEQ=0; _TR_SKIP=0
  [[ -n "$pid" ]] || return 1
  pl="$(_term_herdr_exec pane list 2>/dev/null)" || pl=""
  while IFS= read -r obj; do
    [[ "$(_term_json_str "$obj" pane_id)" == "$pid" ]] || continue
    _TR_PANE=1; break
  done < <(_term_json_objs <<< "$pl")
  (( _TR_PANE )) || return 1
  js="$(_term_herdr_exec pane process-info --pane "$pid" 2>/dev/null)" || js=""
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
  command -v herdr >/dev/null 2>&1 || { printf '需要 herdr：herdr 后端要求 herdr ≥0.9.1 在 PATH（装好后重试，或 NAO_TERMINAL=tmux 回退）\n' >&2; return 1; }
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
  ( _TERM_HERDR_SERVER_START=1 _term_herdr_exec server >"${log:-/dev/null}" 2>&1 & ) || true
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
# <<< term-facade END

# ---------------------------------------------------------------------------
# roles.yaml 解析（严格子集：顶层 roles:，2 空格角色条目 / 4 空格字段，禁 Tab）
# 填充 ROLE_ORDER / ROLE_CARDS / ROLE_WS / ALIAS_ROLE；解析失败即 die
load_manifest() {
  local f="$MANIFEST" out
  [[ -f "$f" ]] || die "角色清单缺失: $f（请创建 .agents/roles.yaml）"
  out="$(awk -F'\t' '
    function die(msg) { print "ERR: " FNR ": " msg; bad=1 }
    BEGIN { bad=0; in_roles=0; cur=""; n=0 }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      if ($0 ~ /\t/) { die("禁止 Tab 缩进"); next }
      if (!in_roles) {
        if ($0 ~ /^roles:[[:space:]]*$/) { in_roles=1; next }
        die("顶层仅允许 roles:，得到: " $0); next
      }
      if ($0 ~ /^  [^ ][^:]*:[[:space:]]*$/) {
        cur=$0; sub(/^  /, "", cur); sub(/:[[:space:]]*$/, "", cur)
        if (cur !~ /^[a-z0-9][a-z0-9-]*$/) { die("非法角色 id: " cur); next }
        card[cur]=""; ws[cur]="."; na[cur]=0; order[++n]=cur; next
      }
      if (cur != "" && $0 ~ /^    [a-z_]+:[[:space:]]/) {
        key=$0; sub(/^    /, "", key); sub(/:.*/, "", key)
        val=$0; sub(/^    [a-z_]+:[[:space:]]*/, "", val)
        if      (key=="card")      { card[cur]=val }
        else if (key=="workspace") { ws[cur]=val }
        else if (key=="aliases") {
          if (val !~ /^\[[^]]*\]$/) { die(cur ".aliases 须为 [a, b] 列表: " $0); next }
          gsub(/^\[|\]$/, "", val); m=split(val, arr, /,/)
          for (i=1; i<=m; i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", arr[i]); if (arr[i]!="") alias[cur,++na[cur]]=arr[i] }
          if (na[cur]==0) die(cur ".aliases 为空")
        }
        else die(cur " 未知字段: " key)
        next
      }
      die("无法解析: " $0)
    }
    END {
      if (bad) exit 1
      if (!in_roles) { print "ERR: 缺少 roles: 顶层键"; exit 1 }
      for (i=1; i<=n; i++) { c=order[i]; if (card[c]=="") { print "ERR: " c " 缺少 card"; bad=1 } if (na[c]==0) { print "ERR: " c " 缺少 aliases"; bad=1 } }
      if (bad) exit 1
      for (i=1; i<=n; i++) { c=order[i]; print "ROLE\t" c "\t" card[c] "\t" ws[c]; for (j=1; j<=na[c]; j++) print "ALIAS\t" c "\t" alias[c,j] }
    }
  ' "$f")" || { printf '%s\n' "$out" >&2; die "roles.yaml 解析失败: $f"; }
  local k v w rest
  while IFS=$'\t' read -r k v w rest; do
    case "$k" in
      ROLE)  ROLE_ORDER+=("$v"); ROLE_CARDS["$v"]="$w"; ROLE_WS["$v"]="$rest" ;;
      ALIAS) ALIAS_ROLE["$w"]="$v" ;;   # 别名 → 角色 id（消费方 resolve_role/close 按此方向取值）
    esac
  done <<< "$out"
}

# 读取卡片 frontmatter 字段（--- 与 --- 之间）
card_field() {
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && $0 ~ "^" k ":" { sub("^" k ": *", ""); print; exit }
  ' "$1"
}

# 校验卡片/公共规范/清单中的 @.agents/... 引用均存在（含 checklists/ 子目录；跨仓库会话能解析的关键保障）
check_cross_refs() {
  local rc=0 src ref
  local -a srcs=()
  shopt -s nullglob
  srcs+=("$PROMPTS_DIR"/*.md "$COMMON_DIR"/*.md "$SKILLS_SUB"/*.md "$SKILLS_DIR"/.agents/checklists/*.md)
  shopt -u nullglob
  for src in "${srcs[@]}"; do
    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      case "$ref" in
        common/*|skills/*|prompts/*|scripts/*|templates/*|checklists/*) ;;
        *) continue ;;
      esac
      if [[ ! -e "$SKILLS_DIR/.agents/$ref" ]]; then
        printf '  ✗ %s → @.agents/%s 缺失\n' "$(basename "$src")" "$ref"
        rc=1
      fi
    done < <(grep -hoE '@\.agents/(common|skills|prompts|scripts|templates|checklists)/[A-Za-z0-9._/-]+' "$src" | sed 's/^@\.agents\///' | sort -u)
  done
  [[ $rc -eq 0 ]] && echo '  ✓ 全部引用文件存在'
  return $rc
}

# .agents/** 文本文件 EOL 契约：必须全为 LF（出现 CR 即 fail，列出文件）
# 排除 .nao-obsolete/（update 的旧版备份，EOL 不作为契约）
check_eol() {
  local rc=0 n=0 f
  local -a bad=()
  while IFS= read -r -d '' f; do
    n=$((n + 1))
    grep -Iq $'\r' "$f" && bad+=("${f#"$SKILLS_DIR"/}")
  done < <(find "$SKILLS_DIR/.agents" -type f ! -path '*/.nao-obsolete/*' -print0)
  if (( ${#bad[@]} == 0 )); then
    printf '  ✓ %d 个文本文件全 LF\n' "$n"
  else
    rc=1
    printf '  ✗ %d/%d 个文件含 CR（须转 LF；CRLF 会破坏 fleet/awk 解析）:\n' "${#bad[@]}" "$n"
    printf '      %s\n' "${bad[@]}"
  fi
  return $rc
}

# roles.yaml 缩进契约：角色 id 2 空格 / 字段 4 空格 / 禁 Tab（与 load_manifest 解析器同契约，独立报行号）
check_roles_indent() {
  awk '
    BEGIN { in_roles=0; cur=0; bad=0 }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    /\t/ { printf "  ✗ 行 %d: 含 Tab（禁止 Tab 缩进）\n", FNR; bad=1; next }
    !in_roles {
      if ($0 ~ /^roles:[[:space:]]*$/) { in_roles=1; next }
      printf "  ✗ 行 %d: 顶层仅允许 roles:（得到: %s）\n", FNR, $0; bad=1; next
    }
    $0 ~ /^  [^ ][^:]*:[[:space:]]*$/ { cur=1; next }
    cur && $0 ~ /^    [a-z_]+:[[:space:]]/ { next }
    { printf "  ✗ 行 %d: 缩进/位置非法（角色 id 须 2 空格、字段须 4 空格且挂在角色下）: %s\n", FNR, $0; bad=1 }
    END { exit (bad ? 1 : 0) }
  ' "$MANIFEST"
}

# 别名解析守卫（#19）：独立重解析 roles.yaml（不依赖可能被写反的 ALIAS_ROLE），校验
#   ① 每个声明的别名可解析为「声明它的角色」（对 ALIAS_ROLE 键值方向敏感）
#   ② 每个角色 canonical id 已登记于 aliases（BR2：canonical 须可解析为自身）
#   ③ 别名不跨角色重名
check_alias_resolution() {
  local rc=0 ga gr
  local -A owner=()
  # T525 BR6/AC7：`subagent-` 前缀保留给 pi-subagents 子代理会话 —— canonical id 与 alias **都不得占用**
  # （否则 status/close 的排除面会吃掉该角色）。折入本函数（唯一枚举点，避第二处遍历漂移），
  # 与缩进/别名唯一性各自累积 rc。
  while IFS=$'\t' read -r ga gr; do
    [[ -n "$ga" && -n "$gr" ]] || continue
    if [[ "$ga" == subagent-* ]]; then
      printf '  ✗ 角色 id/别名 %s 以 subagent- 开头（该前缀保留给 pi-subagents 子代理会话，nao 不接管）\n' "$ga"; rc=1
    fi
    if [[ -n "${owner[$ga]:-}" && "${owner[$ga]}" != "$gr" ]]; then
      printf '  ✗ 别名 %s 跨角色重名：%s 与 %s\n' "$ga" "${owner[$ga]}" "$gr"; rc=1
    fi
    owner["$ga"]="$gr"
    if [[ "${ALIAS_ROLE[$ga]:-}" != "$gr" ]]; then
      printf '  ✗ 别名 %s 解析异常：roles.yaml 声明属 %s，实际解析为 %s（ALIAS_ROLE 键值方向可能反写）\n' \
        "$ga" "$gr" "${ALIAS_ROLE[$ga]:-<未登记>}"; rc=1
    fi
  done < <(awk -F'\t' '
      /^  [^ ][^:]*:[[:space:]]*$/ { c=$0; sub(/^  /,"",c); sub(/:[[:space:]]*$/,"",c); next }
      c!="" && /^    aliases:[[:space:]]*\[/ {
        v=$0; sub(/^    aliases:[[:space:]]*\[/,"",v); sub(/\].*/,"",v)
        n=split(v, a, /,/)
        for (i=1;i<=n;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i]); if(a[i]!="") print a[i] "\t" c }
      }' "$MANIFEST")
  for gr in "${ROLE_ORDER[@]}"; do
    if [[ "$gr" == subagent-* ]]; then
      printf '  ✗ 角色 id/别名 %s 以 subagent- 开头（该前缀保留给 pi-subagents 子代理会话，nao 不接管）\n' "$gr"; rc=1
    fi
    if [[ "${owner[$gr]:-}" != "$gr" ]]; then
      printf '  ✗ 角色 %s 的 canonical id 未登记于 aliases（BR2：canonical 须可解析为自身）\n' "$gr"; rc=1
    fi
  done
  (( rc == 0 )) && printf '  ✓ 别名解析守卫：全部别名可解析且无跨角色重名 + 无 subagent- 保留前缀\n'
  return $rc
}

# CodeGraph 四态检测（T532 · BR1/BR2）—— check / ensure 唯一发射点。
#   codegraph_state <repo> [full] [name]
#   ！（永不计入 rc）所有状态都只是**可观测信号**：不设 rc=1、--strict 亦不升级；
#     理由 = 六会话并发下「索引 pending」是稳态，长期拉红会侵蚀真失败信号（arch A1）。
#   严格短路：① 声明（两份 settings.json 的 packages 含包名）② command -v codegraph
#              ③ <repo>/.codegraph ④ status 文本（**仅 full=1**）
#   full=0（默认 check）：**零 codegraph 调用**（AC11 判据 = codegraph 调用 0 次）——实际新增 2 次 grep fork
#     （settings 声明匹配 + 摘要行抽取）；不 spawn 任何第三方进程
#   full=1（check -v / ensure）：每仓一次 `codegraph status`（实测 0.37–0.42s，不进派发热路径）
#   契约前缀：· 未声明 / ! 已声明但 CLI 不在 PATH / ! 无索引 / ✓ 齐备 / ! pending / ! 不可解析
codegraph_state() {
  local repo="$1" full="${2:-0}" name="${3:-}" f declared=0 pre="" st
  local -a sets=("$PI_AGENT_DIR/settings.json" "$repo/.pi/settings.json")
  [[ -n "$name" ]] && pre="[$name] "
  for f in "${sets[@]}"; do
    [[ -f "$f" ]] || continue
    if grep -qF -- "$CODEGRAPH_PKG" "$f" 2>/dev/null; then declared=1; break; fi
  done
  if (( ! declared )); then
    printf '  · %s%s\n' "$pre" "$CG_MSG_UNDECLARED"; return 0
  fi
  if ! command -v codegraph >/dev/null 2>&1; then
    printf '  ! %s%s\n' "$pre" "$CG_MSG_NO_CLI"; return 0
  fi
  if [[ ! -d "$repo/.codegraph" ]]; then
    printf '  ! %s%s\n' "$pre" "$CG_MSG_NO_INDEX"; return 0
  fi
  if (( ! full )); then
    printf '  ✓ %s%s\n' "$pre" "$CG_MSG_READY_SHORT"; return 0
  fi
  st="$(cd "$repo" 2>/dev/null && codegraph status 2>&1)" || st=""
  # 文本契约（已冻结于 codegraph 1.6.2 实测，见 docs/reports/M20261028-codegraph-followups.md §二 T1）
  case "$st" in
    *"Index is up to date"*) printf '  ✓ %s%s\n' "$pre" "$CG_MSG_READY" ;;
    *"Pending Changes"*)     printf '  ! %s%s\n' "$pre" "$CG_MSG_PENDING" ;;
    *"Not initialized"*)     printf '  ! %s%s\n' "$pre" "$CG_MSG_NO_INDEX" ;;  # 目录在但无 DB（下游常见态）
    *)                       printf '  ! %s%s\n' "$pre" "$CG_MSG_UNPARSABLE" ;;
  esac
  return 0
}

# pi 运行前提（BR4/AC3）：版本源 = `pi --version` 首个 semver token；预发布（含 `-`）视为不满足。
# 输出当前版本（缺失/不可解析也给占位），rc 0 = 满足 ≥ MIN_PI_VERSION；失败只置 rc，由 check 聚合后继续跑完其余体检。
pi_version_check() {
  if ! command -v pi >/dev/null 2>&1; then printf '%s' '<缺失>'; return 1; fi
  local raw cur base c1 c2
  raw="$(pi --version 2>/dev/null || true)"
  cur="$(printf '%s\n' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?' | head -1 || true)"
  if [[ -z "$cur" ]]; then printf '%s' '<无法解析>'; return 1; fi
  printf '%s' "$cur"
  [[ "$cur" == *-* ]] && return 1          # 预发布不满足（BR4）
  base="${cur%%+*}"                        # 忽略 build metadata
  c1="${base%%.*}"; base="${base#*.}"
  c2="${base%%.*}"
  if (( c1 > MIN_PI_MAJOR )); then return 0; fi
  if (( c1 < MIN_PI_MAJOR )); then return 1; fi
  if (( c2 >= MIN_PI_MINOR )); then return 0; fi
  return 1
}

# ---------------------------------------------------------------------------
resolve_role() {
  local id="${ALIAS_ROLE[$1]:-}"
  [[ -n "$id" ]] || die "未知角色: $1（可用: ${ROLE_ORDER[*]}）"
  NAME="$id"
  PROMPT="${ROLE_CARDS[$id]}"
}

# ---------------------------------------------------------------------------
# BR8 · 舰队命名契约（#96 步 2a · 唯一构造/解析点 · 语法冻结）
#
#   名字 = `<core>[@<scope>]`；core = `<role>[-<task>]`（role = 常驻 id 或下游卡 role）
#   scope 末位、`@` 分隔、**非空才出现**（为空时名字与改动前逐字相同 ⇒ BR1 零回归）
#   预算（三个数各管一段，勿相加）：卡 core ≤32 · scope ≤16 · **full ≤48**（= core [+ '@' + scope]）；
#     派生 core = <role>-<task> 不设 core 上限，但 full 仍 ≤48 ⇒ 长 task 配长 scope 会被拒（P2-1）。
#     full 的上限**只在 parse** 判；builder 不 die（close/status 也调它，抛错会把坏名字变成命令崩）——
#     故 ensure 相位 1 必须拿 parse 复核 builder 输出，非 OK 即 die（BR6 零副作用）。
#   名字是**路由标签，不作身份证明**；二期只允许替换 scope 的来源与归一化实现（后两个符号）
#
# 接线清单（11 处解析点全经 fleet_name_parse；契约函数体外禁前缀切片 / 名字拼接）：
#   P1 status 常驻↔派生切分 · P2 status 卡集最长前缀 + suff · P3 status 任务号 + 回收命令角色名
#   P4 close 目标解析（全名命中即用；裸名 = 调用者所在仓 scope）· P5 derived_in_field 比 core
#   P6 visible_session_names 标题字符集加 @ · P7 pane_cwd_snapshot 名字字符集加 @
#   P8 intercom_cwd_for 增可选 repo 过滤 · P9 card_name_problem 校验 core + scope
#   P10 --as 只给 core（含 @ 即拒）· P11 running_verdict 三态 same|conflict|absent
#
# C1 单测（tests/t4/cases/28）按下方标记**整体抽取**本块 ⇒ 块内自包含
#   （不依赖块外的 nao_phys_path / repo_* / warn：只用 _fleet_phys 与 printf 回落）。
# >>> fleet-name-contract BEGIN
# 角色事实表 role → resident|card（parse 的**唯一**角色来源；由 fleet_roles_init 每 run 灌入）
#   注意：`declare -A X`（无赋值）对已存在的关联数组是 no-op ⇒ C1 沙箱可先灌表再 source 本块。
declare -A FLEET_ROLE_KIND

# 物理归一（块内自包含版；语义同 nao_phys_path：pwd -P → readlink -f → 原串）
_fleet_phys() {
  local p="${1-}" out=""
  [[ -n "$p" ]] || return 0
  out="$(cd "$p" 2>/dev/null && pwd -P)" || out=""
  [[ -n "$out" ]] || out="$(readlink -f -- "$p" 2>/dev/null || true)"
  [[ -n "$out" ]] || out="$p"
  printf '%s\n' "$out"
}

# scope 合法性：合法 0；否则 echo 单行原因 + 1。空串 = 「无 scope」由调用方决定，不在此判。
fleet_scope_problem() {
  local s="${1-}"
  [[ -n "$s" ]] || { printf 'scope 为空（空 scope 的语义是「无 scope」，不得写成裸 @）\n'; return 1; }
  (( ${#s} <= 16 )) || { printf 'scope 过长（%d > 16 字符）\n' "${#s}"; return 1; }
  [[ "$s" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
    || { printf 'scope 含非法字符（须 ^[a-z0-9][a-z0-9_-]*$：小写字母/数字/-/_，首字符非 -/_；禁 @ . : 空白）\n'; return 1; }
  [[ "$s" != *- ]] || { printf 'scope 不得以 - 结尾\n'; return 1; }
  case "$s" in
    subagent-*|nao-*) printf 'scope 不得以保留前缀 subagent- / nao- 开头（归 pi-subagents / nao 机制）\n'; return 1 ;;
  esac
  return 0
}

# ⓪ core 构造：<role> [task] → stdout `<role>` 或 `<role>-<task>`
#   core 是名字的前半段（§0），与 scope 无关。同样是**唯一**构造点：C3② 的 lint 把 `core=` 也纳入
#   扫描面（合法拼法只有这里）。lint 判据 = `<name|disp|core>="?${x}?-${?task`（花括号可省），
#   故 `core="$NAME-$task"` / `core="${NAME}-${task}"` / `core="$NAME-${task}"` / `core="${NAME}-$task"`
#   四种形态**都会红**（用例 28 的形态矩阵断言守住这 6 种写法）。
fleet_core_build() {
  local role="${1-}" task="${2-}"
  [[ -n "$role" ]] || { printf 'fleet_core_build：role 为空\n' >&2; return 1; }
  if [[ -z "$task" ]]; then printf '%s\n' "$role"; return 0; fi
  [[ "$task" =~ ^[A-Za-z0-9_-]+$ ]] \
    || { printf 'fleet_core_build：task 含非法字符（仅字母/数字/-/_）：%s\n' "$task" >&2; return 1; }
  printf '%s-%s\n' "$role" "$task"
}

# ① 名字构造：<kind> <core> [scope] → stdout `<core>[@<scope>]`
#   kind ∈ resident|derived|card 只做契约自证（名字本身不编码 kind —— 语法冻结）
#   **预算关系（§0，P2-1 自洽口径）**：core 由 fleet_core_build 产（`<role>[-<task>]`），
#   full = core [+ '@' + scope]；三个数各管一段：卡 core ≤32、scope ≤16、**full ≤48**（含 '@'），
#   而 full 的上限由 parse 独占判定 —— 故 builder 照造、ensure 相位 1 用 parse 复核后才落 pane。
fleet_name_build() {
  local kind="${1-}" core="${2-}" scope="${3-}" why=""
  case "$kind" in
    resident|derived|card) ;;
    *) printf 'fleet_name_build：未知 kind=%s（只能是 resident|derived|card）\n' "${kind:-<空>}" >&2; return 1 ;;
  esac
  [[ -n "$core" ]] || { printf 'fleet_name_build：core 为空\n' >&2; return 1; }
  if [[ -z "$scope" ]]; then
    printf '%s\n' "$core"            # scope 空 ⇒ `@` 整段不出现（BR1 逐字等价的前提）
    return 0
  fi
  if ! why="$(fleet_scope_problem "$scope")"; then
    printf 'fleet_name_build：scope 不可用（%s）\n' "$why" >&2; return 1
  fi
  printf '%s@%s\n' "$core" "$scope"
}

# ② 名字解析（**全函数**：任何输入都有定义结果；非法一律 ERR，禁猜）
#   → `OK <kind>,<role>,<task>,<scope>`（task 空 = 无任务号；scope 空 = 无 scope）
#   禁 `${role}-` 前缀切片：旧缺陷类（跨角色名前缀 + 剥尾）会把 task 算错，故 task 用位置切。
fleet_name_parse() {
  local name="${1-}" core="" scope="" role="" task="" kind="" best="" c=""
  [[ -n "$name" ]] || { printf 'ERR\n'; return 0; }
  (( ${#name} <= 48 )) || { printf 'ERR\n'; return 0; }        # 总名长预算（§0）
  case "$name" in
    *@*@*) printf 'ERR\n'; return 0 ;;                          # 多 @（歧义，无定义）
    *@*)
      core="${name%@*}"; scope="${name##*@}"
      [[ -n "$core" ]] || { printf 'ERR\n'; return 0; }
      fleet_scope_problem "$scope" >/dev/null || { printf 'ERR\n'; return 0; }
      ;;
    *) core="$name" ;;
  esac
  case "$core" in
    subagent-*|nao-*) printf 'ERR\n'; return 0 ;;              # 保留前缀不属舰队命名空间
  esac
  (( ${#FLEET_ROLE_KIND[@]} )) || { printf 'ERR\n'; return 0; }
  # 角色 = 事实表里的**最长**匹配（短前缀会让 `arch-designer-96b` 之类的 task 算错）
  best=""
  for c in "${!FLEET_ROLE_KIND[@]}"; do
    if [[ "$core" == "$c" ]]; then best="$c"; break; fi
    [[ "$core" == "$c"-?* ]] || continue
    if [[ -z "$best" ]] || (( ${#c} > ${#best} )); then best="$c"; fi
  done
  [[ -n "$best" ]] || { printf 'ERR\n'; return 0; }
  role="$best"
  if [[ "$core" == "$role" ]]; then task=""; else task="${core:${#role}+1}"; fi
  if [[ -n "$task" ]]; then
    [[ "$task" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'ERR\n'; return 0; }
  fi
  kind="${FLEET_ROLE_KIND[$role]:-}"
  [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
  if [[ "$kind" == "resident" && -n "$task" ]]; then kind="derived"; fi
  if [[ "$kind" == "card" ]] && (( ${#core} > 32 )); then printf 'ERR\n'; return 0; fi
  printf 'OK %s,%s,%s,%s\n' "$kind" "$role" "$task" "$scope"
}

# ③ 仓级 scope slug（防 worktree 分裂：**必须**取 git --git-common-dir 的父目录名；
#   `--show-toplevel` 在 worktree 里会分裂成两个 slug —— 已实测）
#   slug = basename(dirname(realpath(git --git-common-dir)))；非 git 仓 = realpath(repo) 的 basename
#   归一：lowercase / 非 [a-z0-9] → - / 压缩 - / 去首尾 / 截 16 / 空则 `repo`
fleet_scope_slug() {
  local repo="${1-}" phys="" common="" base="" slug="" d=""
  [[ -n "$repo" ]] || return 0
  phys="$(_fleet_phys "$repo")"
  if command -v git >/dev/null 2>&1; then
    common="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null || true)"
  fi
  if [[ -n "$common" ]]; then
    case "$common" in
      /*) ;;
      *) common="$phys/${common#./}" ;;      # --git-common-dir 可返回相对仓根的路径
    esac
    common="$(_fleet_phys "$common")"
    d="$(dirname -- "$common")"
    base="${d##*/}"
  fi
  [[ -n "$base" ]] || base="${phys%/}"
  base="${base##*/}"
  slug="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"
  slug="${slug:0:16}"
  while [[ "$slug" == *- ]]; do slug="${slug%-}"; done
  [[ -n "$slug" ]] || slug="repo"
  printf '%s\n' "$slug"
}

# ④ 本次调用的 scope（优先级 --scope > <目标仓>/.agents/fleet-scope > 空；**全部 fail loud**）
#   读取对象 = 目标仓 realpath（不是调用者 cwd）；status 不调用本函数（从名字 parse）
#   → stdout scope（可空）；失败 ⇒ stderr 一行原因 + rc=1（调用方 die，禁静默回落）
fleet_scope_of_invocation() {
  local repo="${1-}" cli="${2-}" phys="" f="" raw="" why="" target=""
  if [[ -n "$cli" ]]; then
    if ! why="$(fleet_scope_problem "$cli")"; then
      printf 'fleet_scope_of_invocation：--scope 不可用（%s）\n' "$why" >&2; return 1
    fi
    printf '%s\n' "$cli"; return 0          # 给参即静默胜出（覆盖文件；来源只由 -v 打印）
  fi
  [[ -n "$repo" ]] || return 0
  phys="$(_fleet_phys "$repo")"
  f="$phys/.agents/fleet-scope"
  [[ -e "$f" || -L "$f" ]] || return 0      # 文件不存在 ⇒ 空、**静默**（BR1 全靠这条）
  if [[ ! -f "$f" ]]; then
    printf 'fleet_scope_of_invocation：%s 不是常规文件（目录/fifo/socket 一律拒绝）\n' "$f" >&2; return 1
  fi
  if [[ ! -r "$f" ]]; then
    printf 'fleet_scope_of_invocation：%s 不可读\n' "$f" >&2; return 1
  fi
  target="$(_fleet_phys "$f")"
  case "$target" in
    "$phys"|"$phys"/*) ;;
    *) printf 'fleet_scope_of_invocation：%s 经 symlink 逃出仓 %s（同卡边界口径：配置不得指向仓外）\n' "$f" "$phys" >&2; return 1 ;;
  esac
  raw="$(cat -- "$f" 2>/dev/null)" || { printf 'fleet_scope_of_invocation：%s 读取失败\n' "$f" >&2; return 1; }
  case "$raw" in
    *$'\n'*) printf 'fleet_scope_of_invocation：%s 含多行（歧义；须单行）\n' "$f" >&2; return 1 ;;
  esac
  raw="${raw%$'\r'}"                       # CRLF：剥 \r 再校验（EOL 归 check，不因 EOL 拒绝）
  if [[ -z "${raw//[[:space:]]/}" ]]; then
    printf 'fleet_scope_of_invocation：%s 是空文件/仅空白（声明了却没值 —— 静默回落会把 typo 变成静默撞名）\n' "$f" >&2; return 1
  fi
  if ! why="$(fleet_scope_problem "$raw")"; then
    printf 'fleet_scope_of_invocation：%s 内容不可用（%s）\n' "$f" "$why" >&2; return 1
  fi
  printf '%s\n' "$raw"
}
# <<< fleet-name-contract END

# 角色事实表灌入（每 run 一次）。--cards ⇒ 并入锚根下的下游卡 role（status/close 用；
#   ensure 不读卡集，避免为 parse 引入额外 glob/IO 与 CARD_SET_MAX 告警）。
fleet_roles_init() {
  local r cr a b
  FLEET_ROLE_KIND=()
  for r in "${ROLE_ORDER[@]}"; do [[ -n "$r" ]] && FLEET_ROLE_KIND["$r"]=resident; done
  [[ "${1:-}" == "--cards" ]] || return 0
  while IFS=$'\t' read -r cr a b; do
    [[ -n "$cr" ]] || continue
    [[ -n "${FLEET_ROLE_KIND[$cr]:-}" ]] || FLEET_ROLE_KIND["$cr"]=card
  done < <(card_role_set)
  return 0
}

# 宿主阶梯（已删 · ADR 2026-10-27-strict-tmux-pi）：单一前提 = tmux 会话内；
#   ② $TMUX 存在 ⇒ 派生宿主窗口（调用者 pane 所在 window）split-window 显式 -t @<window_id>。

# ---------------------------------------------------------------------------
# 会话在线判定
#
# 历史假阴性根因：pi 启动后用 OSC 0 把终端标题设为
#   "π - <会话名> - <cwd basename>"（pi 源码 updateTerminalTitle），
# 并同步改写 argv —— /proc/<pid>/cmdline 只剩 "pi"，`pgrep -f --name` 恒失配，
# 于是 status/close 长期判「不在线」（close 退化为静默空转、exit 0）。
# 现改为按「终端标题契约」取句柄，argv 扫描一律不用：
#   ① pi-intercom 名册（权威在线名单）
#   ② tmux pane_title（pi 自设；与 pane_start_command 是否为空无关）
#   ③ tmux detached 会话名 nao-<会话名>
# ⚠️ 标题可被外部改写（实测 "pi:c"）⇒ find_pane_for 再叠三层后备：标题契约 →
#   名册 tmuxPane（$TMUX_PANE，权威）→ 本仓未认领 pi pane 唯一兜底。
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

repo_abspath() { ( cd "$1" >/dev/null 2>&1 && pwd ) 2>/dev/null || true; }
# 路径物理归一（cwd 比较专用）：pwd -P → readlink -f → 原串（与 nao_phys_path 同语义；
#   此处提前定义以便 P8 的 cwd 比较不依赖后续定义顺序）
_nao_phys_for_match() {
  local p="${1-}" out=""
  [[ -n "$p" ]] || return 0
  out="$(cd "$p" 2>/dev/null && pwd -P)" || out=""
  [[ -n "$out" ]] || out="$(readlink -f -- "$p" 2>/dev/null || true)"
  [[ -n "$out" ]] || out="$p"
  printf '%s\n' "$out"
}
repo_basename() {
  local abs; abs="$(repo_abspath "$1")"
  [[ -n "$abs" ]] && printf '%s\n' "${abs##*/}"
  return 0
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

# 会话所在的 tmux pane。三层后备（标题可被外部改写，如 "pi:c"）：
#   ① 终端标题契约 "π - <会话名> - <repo basename>"（pi 自设；最快）
#   ② pi-intercom 名册 tmuxPane（注册时读 $TMUX_PANE；与标题改名无关，权威）
#   ③ 本仓「未被认领 pi pane」唯一兜底（启发式：pane_current_command=pi 且
#      pane_current_path=repo；歧义时 warn，不猜）
# repo（可选）：给出时要求标题 basename / 名册 cwd / pane 当前路径一致，避免跨项目同名互串。
# >>> term-impl-tmux BEGIN (pane 定位)
find_pane_by_title() {
  local name="$1" repo="${2:-}" base=""
  command -v tmux >/dev/null 2>&1 || return 0
  if [[ -n "$repo" ]]; then base="$(repo_basename "$repo")"; fi
  tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_title}" 2>/dev/null \
    | awk -F'\t' -v p="$PI_TITLE" -v n="$name" -v b="$base" '
        { t=$2
          if (b != "") { if (t == p " - " n " - " b) { print $1; exit } }
          else if (index(t, p " - " n " - ") == 1) { print $1; exit }
        }' || true
}

# tmux pane 是否存活（名册 tmuxPane 可能滞后于 pane 关闭）
tmux_pane_live() {
  [[ -n "$1" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qxF "$1"
}
# <<< term-impl-tmux END (pane 定位)

# >>> term-impl-tmux BEGIN (回收 / 自身判定 / 忙闲)
# 目标 pane 是否就是**调用者自己所在的 pane**（F1 不变量：close 任何路径不得回收调用者的 pane）。
# T530 修正根因：旧判据是裸 pane id 比较（`"$pane" == "$TMUX_PANE"`）。pane id 是 **server 局部**
#   命名空间（每个 server 的首块 pane 都是 %0）⇒ 跨 server 撞号时必然误判：隔离/custom socket 的
#   测试 server 里解析出的 %0 与调用者默认 server 的 $TMUX_PANE=%0 字符串相同 → 误判「是自己」→ **误拒**
#   正常回收（安全侧失败，不误杀，但功能不可用）。
#   为什么不用「(socket, pane_id) 二元组相等」：撞号的成因就是 $TMUX_PANE 是**陈旧/外来**的
#   （$TMUX 指向隔离 server，而 $TMUX_PANE 还是默认 server 的 %0）—— 两边读出来的 socket 恰好都等于
#   $TMUX 首字段、id 又都是 %0，二元组照样相等 ⇒ 仍误拒。所以判据必须是「我是否真在这个 pane 里」。
#   实现：目标 pane 的 pane_pid 是否是本进程（$$）的祖先 —— OS 级事实，与 pane id 命名空间无关，
#   天然免疫跨 server 撞号，且顺带覆盖旧闸门的已知缺口（$TMUX_PANE 被清/未设时旧判据完全失效）。
#   语义不放松：真自身 pane（如派生时继承 $TMUX_PANE 致名册错注册，T513-S2/T523/T525）⇒ 祖先命中 ⇒ 仍拒。
#
# T530-D1（QA 复核）：判据必须 **fail-closed**（三态），不得「不可判定 ⇒ 不声称是自己」。
#   QA 实证：伪造 `ps` 令祖先链不可读 ＋ 在自身 pane 内跑 close ⇒ 自身 pane 被回收（SELF_KILLED）。
#   F1「绝不杀自己」是硬不变量 ⇒ 判不了就**拒**（成本是少回收一次，代价是误杀一个会话）。
#   返回：0 = 确定是自己 · 1 = 确定不是 · 2 = 不可判定（pane_pid 取不到 / ps 读不出 / 链断）
pane_hosts_caller() {
  local pane="$1" p_pid cur
  [[ -n "$pane" ]] || return 2
  p_pid="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null || true)"
  [[ "$p_pid" =~ ^[0-9]+$ ]] || return 2          # pane_pid 取不到 ⇒ 不可判定
  cur="$$"
  while [[ "$cur" =~ ^[0-9]+$ ]] && (( cur > 1 )); do
    [[ "$cur" == "$p_pid" ]] && return 0
    cur="$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d '[:space:]')"
    [[ -n "$cur" ]] || return 2                  # 链断（ps 不可读/被伪造）⇒ 不可判定
  done
  return 1                                        # 走到 init 仍未命中 ⇒ 确定不是
}

# F1 闸门统一判据（两个调用点共用）：0 = 必须拒绝回收，1 = 放行。
#   不可判定（rc=2）时**仅当**目标 pane id 与调用者句柄 `$TMUX_PANE` 撞号才拒（保守侧）。
#   ⛔ 不得把「rc=2 且 id 不等」也拒：跨 server 撞号是陈旧句柄造成的，若一律拒会把 v0.19.0
#   那种「隔离 server 的 %0 被当成自己」的误拒（发布阻断红态）重新引回来。
self_pane_refuse() {
  local pane="$1" rc=0
  pane_hosts_caller "$pane" || rc=$?
  case "$rc" in
    0) return 0 ;;                                                      # 确定是自己 ⇒ 拒
    2) [[ -n "${TMUX_PANE:-}" && "$pane" == "$TMUX_PANE" ]] && return 0  # 不可判定但撞号 ⇒ 保守拒
       return 1 ;;
    *) return 1 ;;                                                      # 确定不是 ⇒ 放行
  esac
}

# 该 pane 是否显示在跑 turn（启发式：扫末 12 行找状态行标记；回执/产物以 PM 核对清单为准）
# ⚠️ 窗口不能只用末 3 行：pi 状态行（如 "⠦ Working"）上方还有分隔线，实测会落到第 4 行以外。
# 真伪由 roster 状态(intercom_status_for)交叉；此处仅作 pane 级补充。
pane_busy() {
  local pane="$1" window
  window="$(tmux capture-pane -p -t "$pane" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -12)"
  [[ -n "$window" ]] || return 1
  grep -qE "$CLOSE_BUSY_PATTERN" <<< "$window"
}

# 句柄层回收（B3）：tmux 实现。函数体**逐字**来自 B3 之前的 cmd_close（行为零回归；
#   用例 28 的 B3 节以「提取段 md5 == golden md5」钉住），参数化只为让共用闸门层留在 cmd_close。
_term_tmux_reclaim() {  # <name> <repo> <force> <core> <scope> <ensure-target>
  local name="${1-}" repo="${2-}" force="${3:-false}" core="${4-}" scope="${5-}" tgt="${6-}"
  local pane="" pids="" st="" bus="" pcwd=""
  # ---- 宿主句柄定位（跨仓）：pane 按标题任意仓 basename / 名册 tmuxPane 不限定 cwd ----
  pane="$(find_pane_for_any_repo "$name")"
  # F1 不变量（T513-S2）：close 任何路径不得回收调用者自己的 pane/窗口。
  #   根因：派生窗口若继承 $TMUX_PANE，子进程按该 pane 注册名册 ⇒ 层② 命中调用者自身；
  #   本闸门是纵深防御——无论上游解析为何，命中即拒绝（不 kill-pane、不进入 pi_pids_for 兜底）。
  #   T530：判据=进程归属三态（fail-closed，见 self_pane_refuse），不是裸 pane id 比较 —— pane id 是
  #   server 局部命名空间，隔离 socket 的 %0 与默认 server 的 $TMUX_PANE=%0 撞号会被误判为「自己」而**误拒**。
  #   不可判定时只对「撞号」保守拒绝：判不了自己 ⇒ 宁可少回收一次，不得误杀一个会话。
  if [[ -n "$pane" ]] && self_pane_refuse "$pane"; then
    warn "拒绝回收 $name：解析出的 pane $pane 判为调用者自身（pane_pid 祖先链命中，或祖先链不可判定且与 \$TMUX_PANE 撞号）"
    warn "  名册 tmuxPane 可能因派生时继承 TMUX_PANE 而错注册；请用 intercom({action:'list'}) 核对目标会话后再处理"
    return 1
  fi
  if [[ -z "$pane" ]]; then
    # nao-<会话名> detached tmux 会话（不依赖 repo）
    if command -v tmux >/dev/null 2>&1 && tmux has-session -t "=nao-$name" 2>/dev/null; then
      if tmux kill-session -t "=nao-$name" 2>/dev/null; then log "已回收 $name（tmux 会话 nao-$name）@ $repo"; return 0; fi
    fi
    # 无任何可杀句柄：名册若报在线 ⇒ 定位失败，必须非静默（禁止「未运行」而 pane 仍在）
    if intercom_online "$name"; then
      warn "无法回收 $name：pi-intercom 名册报在线（cwd=${repo}）但未定位到存活 pane/会话"
      warn "  标题契约 / 名册 tmuxPane 均未命中；tmuxPane 可能滞后或未注册"
      warn "  请用 intercom({action:'list'}) 人工核对；确认已退出后忽略，或按 pane_id 手工处理"
      return 1
    fi
    # T516 AC3（#1 错定缺陷的负向闸）：常驻精确句柄全缺席而其派生在场 ⇒ 目标歧义，
    # 拒绝并指路（不得落入「未运行（无需回收）」静默 no-op）。
    local -a dfield=()
    mapfile -t dfield < <(derived_in_field "$core" "$scope")
    if (( ${#dfield[@]} > 0 )); then
      warn "拒绝回收 $name：常驻会话 nao-$name 不存在，但其派生在场：${dfield[*]}"
      warn "  目标歧义（tmux 会话名前缀匹配曾误回收派生，T515 #1）：如需回收派生用 close <派生名>（如 close ${dfield[0]}）；如需拉起常驻用 ensure $tgt"
      return 1
    fi
    # BR5（T529）：tmux 下必有句柄，不可判定不再发生 ⇒ 直接报「未运行」（无 offline 分支）
    log "$name 未运行（无需回收）"; return 0
  fi

  # 闸门②：在跑 turn（pane 标记 + roster 状态双重信号）
  bus=""
  # 显式双分支赋值：pane 空闲时 bus 必须落为 ""。
  # 曾用 `pane_busy "$pane" && bus=…`：pane_busy 为假时 && 短路，bus 在 set -u 下未绑定 → 行 1007 崩溃。
  if pane_busy "$pane"; then
    bus="tmux pane $pane 显示在跑 turn"
  fi
  st="$(intercom_status_for "$name")"
  if [[ -z "$bus" ]]; then
    case "$st" in
      ""|idle|\?) ;;   # 无状态或空闲 → 不阻塞
      *) bus="pi-intercom 名册状态=$st（在跑 turn）" ;;
    esac
  fi
  if [[ -n "$bus" && "$force" != true ]]; then
    warn "拒绝回收 $name：$bus"
    warn "  等它停；回执与产物核对见 checklists/pm.md「会话回收 / 收窗核对」（或 --force 强制）"
    return 1
  fi

  # 回收前以 pane 真实 cwd 校正日志中的仓（名册可能缺记录）
  local pcwd
  pcwd="$(tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null || true)"
  [[ -n "$pcwd" ]] && repo="$pcwd"
  if tmux kill-pane -t "$pane" 2>/dev/null; then
    log "已回收 $name（tmux pane $pane）@ $repo"; return 0
  fi
  pids="$(pi_pids_for "$name" "$repo" | tr '\n' ' ')"
  if [[ -n "$pids" ]] && kill $pids 2>/dev/null; then
    log "已回收 $name（结束进程: $pids）@ $repo"; return 0
  fi
  warn "已定位到 $name 的 pane $pane 但回收失败（pane 可能刚好退出；核对 pane 已消失后可忽略）"; return 1
}

# 实验场安全清理（T516 #2 · D2 形态 A）：终结指定实验场 server。
# 守卫：① 无 -S ⇒ exit 2（默认 socket 是生产名册所在，禁止默认清理）；
#       ② -S 指向默认 socket ⇒ exit 2（防呆：显式传入也不放行）；
#       ③ socket 不存在 ⇒ 幂等成功（rc 0）；④ kill 失败 ⇒ 非 0 + 诊断，不谎报。
# 拆场（B3）：tmux 实现 —— 函数体逐字来自 B3 之前的 cmd_cleanup（行为零回归；用例 28 的 B3 节钉 md5）。
# 生产默认 socket 候选。T516 事故修正：判定**不得**依赖 `${TMUX_TMPDIR:-/tmp}` ——
#   实验夹具为让 fleet 内部裸 `tmux` 落到夹具 server 会把 TMUX_TMPDIR 指向隔离目录，
#   若据此判定，真实默认 socket 会被误判为「非默认」而遭清理 ⇒ 真 server 连坐自灭
#   （2026-10-13 AC5e 负向用例实测杀掉调用者自己的 server）。恒含常量 /tmp/tmux-<uid>/default
#   （id -u 失败也是安全路径）；回归脚本护栏用同一常量**独立复算**（双保险，互不依赖）。
prod_sock_candidates() {  # 每行一个候选
  local uid; uid="$(id -u)"
  [[ -n "${TMUX:-}" ]] && printf '%s\n' "${TMUX%%,*}"
  printf '%s\n' "/tmp/tmux-$uid/default" "${TMPDIR:-/tmp}/tmux-$uid/default"
}
_term_tmux_cleanup() {
  local sock="${CLEANUP_SOCK:-}"
  if [[ -z "$sock" ]]; then
    printf '[fleet] cleanup 拒绝：未指定 -S <socket>。生产默认 socket 是生产名册所在，禁止默认清理；实验场清理用：env -u TMUX nao-fleet.sh cleanup -S <隔离socket>\n' >&2
    return 2
  fi
  # F3-B3（arch 评审 · 低）：`-S` 若为符号链接/未归一化路径（`/tmp//…`、symlink）可绕过字符串比对
  # ⇒ 比对前 readlink -f 归一化；readlink -f 不可用/不可解析时退回原串（保持原语义、无新依赖）。
  local sock_cmp
  sock_cmp="$(readlink -f -- "$sock" 2>/dev/null || true)"
  [[ -n "$sock_cmp" ]] || sock_cmp="$sock"
  local -a prod=() p
  mapfile -t prod < <(prod_sock_candidates | awk '!seen[$0]++')
  for p in "${prod[@]:-}"; do
    if [[ "$sock_cmp" == "$p" ]]; then
      printf '[fleet] cleanup 拒绝：-S 指向生产默认 socket（%s）；请用隔离 socket（须不同于生产候选：%s）\n' "$sock" "${prod[*]}" >&2
      return 2
    fi
  done
  [[ -n "${TMUX:-}" ]] && warn "当前在 tmux 客户端内：本次 -S 已显式（安全），但实验纪律建议先 env -u TMUX 再执行"
  if [[ ! -S "$sock" ]]; then
    log "socket 不存在（无 server，幂等清理）：$sock"; return 0
  fi
  # 陈旧 socket（kill-server 后残留的 socket 文件，无 server 监听）：清除文件即幂等成功
  # （实测 tmux 3.7c 在 -S 自定义路径下 kill-server 不卸载 socket 文件 ⇒ 二次 cleanup 需兜底）
  if ! tmux -S "$sock" ls >/dev/null 2>&1; then
    rm -f "$sock" 2>/dev/null || true
    log "socket 无 server 监听（残留），已清除：$sock"; return 0
  fi
  if tmux -S "$sock" kill-server 2>/dev/null; then
    log "已终结实验场 tmux server：$sock"; return 0
  fi
  warn "cleanup 失败：tmux -S $sock kill-server 非 0（server 可能刚好退出；核对 socket 后重试）"
  return 1
}

# <<< term-impl-tmux END (回收 / 自身判定 / 忙闲)

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
# >>> term-impl-tmux BEGIN (pane 枚举 / argv / 在线)
pi_panes() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_current_command}"$'\t'"#{pane_current_path}" 2>/dev/null \
    | awk -F'\t' '{ c=$2; sub(/^.*\//,"",c); if (c=="pi") print $1 "\t" $3 }' || true
}

# 兜底：本仓 pi pane 中「未被其它会话认领」且**跨全部角色唯一**者。
# ⚠ 层③ 误配根因（T513f）：新 pane 尚未被标题/名册认领时会被误判给别的角色
#   （实测 ensure qa rd-infra ⇒ rd-infra 被 qa 的新 pane 命中而误判「已在运行」跳过）。
# 收紧（不猜）：① 本仓未认领 pi pane 必须**跨全部角色唯一**（>1 ⇒ warn + 不返回）；
#   ② 还须叠加「名册 cwd 匹配」（目标会话确实登记在本仓）才可返回。
# 层①标题契约 / 层②名册 tmuxPane 语义不变（T512-① 属独立课题）。
fallback_pane_for() {
  local name="$1" repo="$2" abs="" cp j v
  command -v tmux >/dev/null 2>&1 || return 0
  abs="$(repo_abspath "$repo")"; [[ -n "$abs" ]] || return 0
  local -A claimed=()
  while IFS= read -r cp; do
    [[ -n "$cp" ]] && claimed["$cp"]=1
  done < <(tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_title}" 2>/dev/null \
             | awk -F'\t' -v t="$PI_TITLE" '$2 ~ "^" t " - " { print $1 }')
  j="$(intercom_list_json 2>/dev/null)" || j=""
  if [[ -n "$j" ]]; then
    cp="$(printf '%s\n' "$j" | sed -n 's/.*"tmuxPane":[[:space:]]*"\([^"]*\)".*/\1/p')"
    while IFS= read -r v; do [[ -n "$v" ]] && claimed["$v"]=1; done <<< "$cp"
  fi
  local -a cand=()
  local pid ppath
  while IFS=$'\t' read -r pid ppath; do
    [[ "$ppath" == "$abs" ]] || continue
    [[ -n "${claimed[$pid]:-}" ]] && continue
    cand+=("$pid")
  done < <(pi_panes)
  # ① 跨全部角色唯一（歧义不猜）
  if (( ${#cand[@]} > 1 )); then
    warn "标题被改写且名册无 pane 记录：$abs 内有多个未认领 pi pane（${cand[*]}）→ 无法唯一确定 $name（不认领）"
    return 0
  fi
  (( ${#cand[@]} == 0 )) && return 0
  # ② 名册 cwd 匹配（目标会话须确实登记在本仓），否则绝不认领本仓 pane
  intercom_online "$name" "$abs" || return 0
  printf '%s\n' "${cand[0]}"; return 0
}

find_pane_for() {
  local name="$1" repo="${2:-}" pane=""
  # ① 终端标题契约
  pane="$(find_pane_by_title "$name" "$repo")"
  [[ -n "$pane" ]] && { printf '%s\n' "$pane"; return 0; }
  # ② pi-intercom 名册 tmuxPane（权威；标题被改写仍有效）
  pane="$(intercom_pane_for "$name" "$repo")"
  if [[ -n "$pane" ]] && tmux_pane_live "$pane"; then printf '%s\n' "$pane"; return 0; fi
  # ③ 本仓未认领 pi pane 唯一兜底
  pane="$(fallback_pane_for "$name" "$repo")"
  [[ -n "$pane" ]] && { printf '%s\n' "$pane"; return 0; }
  return 0
}

# 跨仓 pane 定位：不限定 repo（标题任意仓 basename / 名册 tmuxPane 不限 cwd）
# close 的目标可能在别的仓（roles.yaml workspace 恒为本仓）⇒ 不能用 find_pane_for 的 repo 约束。
find_pane_for_any_repo() {
  local name="$1" pane=""
  pane="$(find_pane_by_title "$name" "")"
  [[ -n "$pane" ]] && { printf '%s\n' "$pane"; return 0; }
  pane="$(intercom_pane_for "$name" "")"
  if [[ -n "$pane" ]] && tmux_pane_live "$pane"; then printf '%s\n' "$pane"; return 0; fi
  return 0
}

# 该会话名对应的 pi 进程 PID（经 pane 句柄取 pane_pid 及其子进程中 comm=pi 者）
pi_pids_for() {
  local pane root pid
  pane="$(find_pane_for "$1" "${2:-}")"
  [[ -n "$pane" ]] || return 0
  # F1 纵深（T513-S2）：绝不据「调用者自己的 pane」反查 pid，否则会 kill 到自身进程。
  # T530：判据=进程归属（pane_hosts_caller 三态，fail-closed），不比较裸 pane id（server 局部命名空间）。
  self_pane_refuse "$pane" && return 0
  root="$(tmux display-message -p -t "$pane" '#{pane_pid}' 2>/dev/null)"
  [[ -n "$root" ]] || return 0
  { printf '%s\n' "$root"; pgrep -P "$root" 2>/dev/null || true; } | while IFS= read -r pid; do
    [[ "$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ')" == "pi" ]] || continue
    printf '%s\n' "$pid"
  done
}

# tmux 侧 argv：只有命令名（无完整 argv）⇒ argv 列留空；**不得**用 ps 兜底（pid 竞态 + 判据不同源）
_term_tmux_argv() {  # <pane_id> → 每行 "process-name<TAB>"
  local p="${1-}" c
  [[ -n "$p" ]] || return 0
  command -v tmux >/dev/null 2>&1 || return 0
  c="$(tmux display-message -p -t "$p" '#{pane_current_command}' 2>/dev/null || true)"
  [[ -n "$c" ]] || return 0
  c="${c##*/}"
  printf '%s\t\n' "$c"
}

# tmux 侧在线判定：保留现有证据链（名册 → pane 定位 → 会话名），**不用**门面新列改语义（BR1）
_term_tmux_liveness() {  # <name> [repo] → "<verdict>\t-\t-\t-"
  local name="${1-}" repo="${2:-}"
  if intercom_online "$name" "$repo"; then printf 'online\t-\t-\t-\n'; return 0; fi
  if [[ -n "$(find_pane_for "$name" "$repo")" ]]; then printf 'online\t-\t-\t-\n'; return 0; fi
  # T516 #1（=锚）：tmux 会话名唯一前缀匹配曾误命中派生 nao-<名>-<任务>（T515 V4 实证）⇒ 一律 =nao-<名>。
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "=nao-$name" 2>/dev/null; then
    printf 'online\t-\t-\t-\n'; return 0
  fi
  printf 'absent\t-\t-\t-\n'; return 0
}
# <<< term-impl-tmux END (pane 枚举 / argv / 在线)

# ---- ④ 路径句柄（app-id/class）已随宿主阶梯删除（ADR 2026-10-27-strict-tmux-pi）---------

# 派生会话在场检测（T516 AC3）：visible_session_names 中 core（= role[-task]，**不含 scope**）以
#   `<core>-` 开头且带非空后缀者。用于 close <常驻名> 时判目标歧义：常驻精确句柄缺席而其派生在场
#   ⇒ 拒绝 + 指路（禁静默谎报「未运行」）。
# P5（BR8）：候选**必须**先经 fleet_name_parse 比 **core**，并要求 scope 与目标一致 ——
#   旧写法 `[[ "$n" == "$1"-?* ]]` 会把**他仓/他 scope 的派生**算成本仓派生（T516 AC3 误拒复发）。
derived_in_field() {  # <core> [scope] → 派生名列表（每行一个；空 = 无）
  local core="${1-}" want="${2-}" n out k r t s c
  [[ -n "$core" ]] || return 0
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    [[ "$out" == "OK "* ]] || continue
    IFS=',' read -r k r t s <<< "${out#OK }"
    [[ -n "$t" ]] || continue                      # 无任务号 ⇒ 不是派生
    c="$(fleet_core_build "$r" "$t")"
    [[ "$c" == "$core"-?* ]] || continue           # 比 core（不是裸名字前缀）
    [[ "$s" == "$want" ]] || continue              # scope 必须一致（否则他仓派生被算本仓）
    printf '%s\n' "$n"
  done < <(visible_session_names)
}

# 同 core 且带 scope 的在场会话（close 裸名时用于定位他仓/他 scope 的会话；每行一个）。
#   与 derived_in_field 互补：那个找「更长的 core」，这个找「同 core + 不同 scope」。
fleet_scoped_candidates() {  # <core> → 名字（每行一个；空 = 无）
  local core="${1-}" n out k r t s c
  [[ -n "$core" ]] || return 0
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    [[ "$out" == "OK "* ]] || continue
    IFS=',' read -r k r t s <<< "${out#OK }"
    [[ -n "$s" ]] || continue                      # 无 scope ⇒ 不是本函数的候选
    c="$(fleet_core_build "$r" "$t")"
    [[ "$c" == "$core" ]] || continue
    printf '%s\n' "$n"
  done < <(visible_session_names)
}

# 子代理会话计数（T525）：与 derived_in_field 同源（visible_session_names，已去重）中锚首 `subagent-` 者。
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
  # 门面包装：证据链按后端双实现（tmux = 名册/pane/会话名；herdr = label+argv+agent 结构化事实）
  [[ "$(term_liveness "${1-}" "${2-}" | cut -f1)" == "online" ]]
}

# P11（BR8）：`ensure` 判重**三态**（旧二态无法区分「同名不同 scope/仓」⇒ 静默起出第二个会话）
#   same     = 同名同仓同 scope 已在运行 ⇒ 跳过（文案与旧行为逐字一致）
#   conflict = 同 core 但 scope 或仓不同 ⇒ **die + 指路**（列候选），禁静默拉起
#   absent   = 拉起
#   repo 未知（pane/名册均无 cwd）时不得凭空判冲突 ⇒ 落 absent（与旧行为一致，不新增误拒）。
running_verdict() {  # <name> [repo] → same | conflict:<候选…> | absent
  local name="$1" repo="${2:-}" out k r t s ckey ckey2 n p2 k2 r2 t2 s2 rcwd cand=""
  local have_snap=0 sname spane scwd
  local -A pmap=()
  if running "$name" "$repo"; then printf 'same\n'; return 0; fi
  out="$(fleet_name_parse "$name")"
  [[ "$out" == "OK "* ]] || { printf 'absent\n'; return 0; }
  IFS=',' read -r k r t s <<< "${out#OK }"
  # 比较键（**不是** §0 的 core）：用 '/' 分隔 role 与 task，避免与 `-` 拼接的 core 混淆
  ckey="$r"; if [[ -n "$t" ]]; then ckey="$r/$t"; fi
  # 注意：候选**可以就是目标同名**（同名不同仓 = scope 未设的典型撞名）—— running 已按目标仓判过缺席，
  #   走到这里就说明「场里有这个名、但不是本仓的那一个」⇒ 靠下面的仓比较定冲突，不能先按名字跳过。
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    p2="$(fleet_name_parse "$n")"
    [[ "$p2" == "OK "* ]] || continue
    IFS=',' read -r k2 r2 t2 s2 <<< "${p2#OK }"
    ckey2="$r2"; if [[ -n "$t2" ]]; then ckey2="$r2/$t2"; fi
    [[ "$ckey2" == "$ckey" ]] || continue
    # 冲突判据（AC1.6）：**scope 不同 ⇒ 各自可见，不是冲突**（这正是 scope 的用途）；
    #   只有「同 scope（含都未设）+ 仓不同」才是静默撞名 ⇒ fail loud 列候选。
    #   仓未知（pane-only 无名册 cwd）时不凭空判冲突（与旧行为一致，不新增误拒）。
    [[ "$s2" == "$s" ]] || continue
    # B2：herdr 侧**禁用名册探针**（node）—— cwd 权威只取 pane.cwd/foreground_cwd（term_snapshot）；
    #   否则名册陈旧/双源矛盾会把 B1 要根除的旧病带回来（与 status 同一口径）。tmux 路径逐字不变。
    if [[ "$NAO_TERMINAL" == "herdr" ]]; then
      rcwd=""
    else
      rcwd="$(intercom_cwd_for "$n")"
    fi
    if [[ -z "$rcwd" ]]; then
      # 名册无 cwd ⇒ 回退 pane cwd（权威层，与 status 归属同口径）；快照每 run 至多一次
      if (( ! have_snap )); then
        while IFS=$'\t' read -r sname spane scwd; do
          [[ -n "$sname" ]] || continue
          [[ -n "${pmap[$sname]:-}" ]] || pmap["$sname"]="$scwd"
        done < <(pane_cwd_snapshot)
        have_snap=1
      fi
      rcwd="${pmap[$n]:-}"
    fi
    if [[ -n "$rcwd" && -n "$repo" ]]; then
      if [[ "$(_nao_phys_for_match "$rcwd")" != "$(_nao_phys_for_match "$repo")" ]]; then
        cand+="$n（cwd=$rcwd） "
      fi
    fi
  done < <(visible_session_names)
  if [[ -n "$cand" ]]; then printf 'conflict:%s\n' "${cand% }"; return 0; fi
  printf 'absent\n'
}

# 本机可见的会话名（tmux 标题 + tmux 会话 + 名册），供 status 枚举；已去重
# ⚠️ 每条枚举 `|| true`：set -e + pipefail 下 `tmux`（无 server 时 rc=1）会中断其余枚举，
#    使「名册回退」永远走不到 —— 必疾。
# P6（BR8）：标题字符集必须含 `@` —— 否则带 scope 的会话在 status 里**整条消失**（已实测）。
# >>> term-impl-tmux BEGIN (会话名 / 未归属)
_term_tmux_current_session() { tmux display-message -p '#S' 2>/dev/null || true; }

_term_tmux_names() {
  { if command -v tmux >/dev/null 2>&1; then
      { tmux list-panes -a -F '#{pane_title}' 2>/dev/null || true; } \
        | sed -n "s/^${PI_TITLE} - \([A-Za-z0-9_@-]*\) - .*/\1/p"
      { tmux list-sessions -F '#{session_name}' 2>/dev/null || true; } \
        | sed -n 's/^nao-//p'
    fi
    intercom_roster 2>/dev/null || true
  } | awk -F'\t' 'NF {print $1}' | awk '!seen[$0]++'
}

# 名册「条目感知」pane 认领集（T525 E2）：name↔tmuxPane 配对后**过滤** `^subagent-` 条目 ⇒ 每行一个 pane。
# 兼容紧凑/pretty 两种 JSON：`sed 's/},/}\n/g'` 先按对象边界切行（纯状态机 awk 在紧凑单行名册里会因
# 贪婪匹配塌缩成末条 ⇒ 假告警）；取值法与 intercom_pane_for 的逐条目取法同源。
# ⚠ 仅用于 unattributed_pi_panes：fallback_pane_for 的 claimed 语义是「该 pane 已被占用」（含子代理），
#   排除会致兜底**误认领父 pane**（D-A 已裁定，见 PRD §三.4）。
roster_pane_claims() {  # → 被非子代理会话认领的 pane_id（每行一个；rc 恒 0）
  intercom_list_json 2>/dev/null | sed 's/},/}\n/g' | awk '
    /"name":[[:space:]]*"/     { s=$0; sub(/.*"name":[[:space:]]*"/,"",s);     sub(/".*/,"",s); n=s }
    /"tmuxPane":[[:space:]]*"/ { s=$0; sub(/.*"tmuxPane":[[:space:]]*"/,"",s); sub(/".*/,"",s); p=s
                                 if (p != "" && n !~ /^subagent-/) print p }
  ' || true
}

# 未能归属到任何会话名的 pi pane（标题不符契约且名册无 tmuxPane 记录）：
# 输出 pane_id<TAB>pane_title；供 status 做「非静默」提示（不假装看不到）。
# T525 E2：claimed 用 roster_pane_claims（条目感知、排除 `^subagent-`）⇒ 仅被子代理继承 tmuxPane 的孤儿
# pane 回到「无法归属会话名」告警（BR8 非静默优先）。
unattributed_pi_panes() {
  command -v tmux >/dev/null 2>&1 || return 0
  local claimed p tt
  claimed="$(roster_pane_claims)" || claimed=""
  while IFS=$'\t' read -r p tt; do
    [[ -n "$p" ]] || continue
    grep -qxF "$p" <<< "$claimed" && continue
    printf '%s\t%s\n' "$p" "$tt"
  done < <(tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_current_command}"$'\t'"#{pane_title}" 2>/dev/null \
             | awk -F'\t' -v t="$PI_TITLE" '{ c=$2; sub(/^.*\//,"",c); if (c!="pi") next; if ($3 ~ "^" t " - ") next; print $1 "\t" $3 }' || true)
}
# <<< term-impl-tmux END (会话名 / 未归属)

# ---- 共享投影（无后端调用）：会话名 / pane cwd 从门面快照取（herdr）或走 tmux 证据层 ----
visible_session_names() {
  case "$(term_backend)" in
    tmux) _term_tmux_names ;;
    # herdr：label 即会话名（结构化事实；名册不参与身份判定 —— 见 BR3/BR7）
    herdr) term_snapshot | awk -F'\t' 'NF && $1 != "" {print $1}' | awk '!seen[$0]++' ;;
  esac
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

# 16 位 checksum，与 tmux 源码 layout_checksum() 一致
_layout_checksum() {
  local s="$1" c=0 b
  local -a bytes=()
  # shellcheck disable=SC2207
  bytes=($(printf '%s' "$s" | od -An -v -tu1 | tr -s ' \n' ' '))
  for b in "${bytes[@]}"; do
    c=$(( ((c >> 1) + ((c & 1) << 15) + b) & 0xFFFF ))
  done
  printf '%04x' "$c"
}

# main-row2 / main-col 共用几何（单一源头，防守卫与构建两处漂移）
# 输入：窗口宽 win_w · pane 数 n · 主宽百分比 pct
# 输出（空格分隔）：main_w right_w right_x cols cw_base cw_last
main_row2_geom() {
  local win_w="$1" n="$2" pct="$3"
  local usable_w=$(( win_w - 1 ))
  (( usable_w < 2 )) && usable_w=2
  local main_w=$(( usable_w * pct / 100 ))
  (( main_w < 1 )) && main_w=1
  (( main_w > usable_w - 1 )) && main_w=$(( usable_w - 1 ))
  local right_w=$(( usable_w - main_w ))
  (( right_w < 1 )) && right_w=1
  local right_x=$(( main_w + 1 ))
  local m=$(( n - 1 ))
  (( m < 1 )) && m=1
  local cols=$(( (m + 1) / 2 ))
  (( cols < 1 )) && cols=1
  local r_usable=$(( right_w - (cols - 1) ))
  (( r_usable < 1 )) && r_usable=1
  local cw_base=$(( r_usable / cols ))
  (( cw_base < 1 )) && cw_base=1
  local cw_last=$(( r_usable - cw_base * (cols - 1) ))
  (( cw_last < 1 )) && cw_last=1
  printf '%s %s %s %s %s %s' "$main_w" "$right_w" "$right_x" "$cols" "$cw_base" "$cw_last"
}

# main-row2 最窄非主 pane 列宽（窄列守卫用；与 build 共用 main_row2_geom）
main_row2_min_col() {
  local win_w="$1" n="$2" pct="$3"
  (( n >= 2 )) || { printf '%s' "$win_w"; return 0; }
  local main_w right_w right_x cols cw_base cw_last
  read -r main_w right_w right_x cols cw_base cw_last < <(main_row2_geom "$win_w" "$n" "$pct")
  if (( cw_base < cw_last )); then printf '%s' "$cw_base"; else printf '%s' "$cw_last"; fi
}

# main-col 右列宽（tmux main-vertical 百分比语义；与 main_row2_geom 的 right_w 同源）
main_col_right_w() {
  local main_w right_w right_x cols cw_base cw_last
  read -r main_w right_w right_x cols cw_base cw_last < <(main_row2_geom "$1" 2 "$2")
  printf '%s' "$right_w"
}

# main-row2：主 pane 全高占左；往右每列 2 个上下堆叠
#   5 pane：1 | 2 | 4
#           1 | 3 | 5
#   7 pane：1 | 2 | 4 | 6
#           1 | 3 | 5 | 7
# tmux 规范：相邻子 pane 之间 1 格 gap；{} 左右排列，[] 上下排列
build_main_row2_layout() {
  local win_w="$1" win_h="$2" pct="$3"
  shift 3
  local -a panes=("$@")
  local n=${#panes[@]}
  (( n >= 1 )) || return 1
  if (( n == 1 )); then
    printf '%sx%s,0,0,%s' "$win_w" "$win_h" "${panes[0]}"
    return 0
  fi

  # 几何统一来自 main_row2_geom（守卫与构建同源，防漂移）
  local main_w right_w right_x cols cw_base cw_last
  read -r main_w right_w right_x cols cw_base cw_last < <(main_row2_geom "$win_w" "$n" "$pct")

  # 每列内部：上下 2 个，中间 1 gap
  local v_usable=$(( win_h - 1 ))
  (( v_usable < 2 )) && v_usable=2
  local top_h=$(( v_usable / 2 ))
  (( top_h < 1 )) && top_h=1
  local bot_h=$(( v_usable - top_h ))
  (( bot_h < 1 )) && bot_h=1
  local bot_y=$(( top_h + 1 ))

  local -a col_parts=()
  local col col_x cw i_top i_bot
  for (( col=0; col<cols; col++ )); do
    col_x=$(( right_x + col * (cw_base + 1) ))
    if (( col == cols - 1 )); then cw=$cw_last; else cw=$cw_base; fi
    i_top=$(( col * 2 + 1 ))
    i_bot=$(( col * 2 + 2 ))
    if (( i_bot < n )); then
      col_parts+=("${cw}x${win_h},${col_x},0[${cw}x${top_h},${col_x},0,${panes[$i_top]},${cw}x${bot_h},${col_x},${bot_y},${panes[$i_bot]}]")
    elif (( i_top < n )); then
      col_parts+=("${cw}x${win_h},${col_x},0,${panes[$i_top]}")
    fi
  done

  local right_body
  if (( cols == 1 )); then
    right_body="${col_parts[0]}"
  else
    local IFS=','
    right_body="${right_w}x${win_h},${right_x},0{${col_parts[*]}}"
    unset IFS
  fi

  printf '%sx%s,0,0{%sx%s,0,0,%s,%s}' \
    "$win_w" "$win_h" \
    "$main_w" "$win_h" "${panes[0]}" \
    "$right_body"
}

# >>> term-impl-tmux BEGIN (布局 / 窄列回退)
# B4（#96 二期）：布局面整段进 tmux 标记区 —— 它是**后端专有**证据层（三期 workspace/tab 拓扑替换），
#   不是业务区。进门面标记区后台账条目（apply_main_col / apply_tmux_layout）清零，只减不增。
# main-col：委托 tmux 内建 main-vertical（主 pane 左全高 + 右列纵向堆叠）
#   坑：tmux 默认 main-pane-width=80（格）⇒ 必须显式设百分比
apply_main_col() {
  local pct="$1" n="$2" min_w="$3" win_w="$4" from="$5"
  if (( n >= 2 )); then
    local right_w; right_w="$(main_col_right_w "$win_w" "$pct")"
    if (( right_w < min_w )); then
      if [[ "$from" == "main-col" ]]; then
        warn "main-col 右列 ${right_w} < 最小 ${min_w}（${n} pane @ ${win_w} 列）→ 回退 grid"
      else
        warn "${from} → main-col 右列 ${right_w} < 最小 ${min_w}（${n} pane @ ${win_w} 列）→ 再回退 grid"
      fi
      tmux select-layout -t "$HOST_WINDOW" tiled >/dev/null 2>&1 || true
      return 0
    fi
  fi
  tmux set-window-option -t "$HOST_WINDOW" main-pane-width "${pct}%" >/dev/null 2>&1 || true
  local err
  if ! err=$(tmux select-layout -t "$HOST_WINDOW" main-vertical 2>&1); then
    warn "main-col（main-vertical）应用失败，回退 grid（宿主窗口 $HOST_WINDOW）"
    warn "  tmux:   ${err:-<no message>}"
    tmux select-layout -t "$HOST_WINDOW" tiled >/dev/null 2>&1 || true
  fi
}

apply_tmux_layout() {
  [[ -n "${TMUX:-}" ]] || return 0
  [[ -n "$HOST_WINDOW" ]] || return 0
  if [[ "$TMUX_LAYOUT" == "grid" ]]; then
    tmux select-layout -t "$HOST_WINDOW" tiled >/dev/null 2>&1 || true
    return
  fi
  # main-row2
  local win_w win_h
  # D7（T513-S3）：display-message 无输出时 `read` 返回 1，set -e 会硬中断整轮 ensure
  #   ⇒ 守卫为 true（读不到尺寸即跳过布局，不硬崩）。
  read -r win_w win_h < <(tmux display-message -p -t "$HOST_WINDOW" '#{window_width} #{window_height}' 2>/dev/null) || true
  [[ -n "$win_w" && -n "$win_h" ]] || return 0

  local -a pane_ids=()
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] && pane_ids+=("$line")
  done < <(tmux list-panes -t "$HOST_WINDOW" -F '#{pane_id}' 2>/dev/null | sed 's/^%//')
  local n=${#pane_ids[@]}
  (( n >= 1 )) || return 0

  local pct="$TMUX_MAIN_WIDTH"
  [[ "$pct" =~ ^[0-9]+$ ]] || pct="$TMUX_MAIN_WIDTH_DEFAULT"
  (( pct < 10 )) && pct=10
  (( pct > 90 )) && pct=90

  local min_w="$TMUX_MIN_PANE_WIDTH"
  [[ "$min_w" =~ ^[0-9]+$ ]] || min_w="$TMUX_MIN_PANE_WIDTH_DEFAULT"
  (( min_w < 10 )) && min_w=10
  (( min_w > 80 )) && min_w=80

  if [[ "$TMUX_LAYOUT" == "main-col" ]]; then
    apply_main_col "$pct" "$n" "$min_w" "$win_w" "main-col"
    return
  fi

  # 窄列守卫：main-row2 最窄非主 pane < 阈值 ⇒ 回退 main-col（再不足⇒grid）
  local narrow; narrow="$(main_row2_min_col "$win_w" "$n" "$pct")"
  if (( narrow < min_w )); then
    warn "${n} pane @ ${win_w} 列：main-row2 最窄列 ${narrow} < 最小 ${min_w} → 回退 main-col"
    apply_main_col "$pct" "$n" "$min_w" "$win_w" "main-row2"
    return
  fi

  local full; full="$(build_main_row2_layout "$win_w" "$win_h" "$pct" "${pane_ids[@]}")"
  [[ -n "$full" ]] || return 0

  local ck; ck="$(_layout_checksum "$full")"
  local err
  if ! err=$(tmux select-layout -t "$HOST_WINDOW" "${ck},${full}" 2>&1); then
    warn "main-row2 布局应用失败，回退 tiled（宿主窗口 $HOST_WINDOW）"
    warn "  tmux:   ${err:-<no message>}"
    warn "  layout: $full"
    tmux select-layout -t "$HOST_WINDOW" tiled >/dev/null 2>&1 || true
  fi
}

# <<< term-impl-tmux END (布局 / 窄列回退)

# ---------------------------------------------------------------------------
# >>> term-impl-tmux BEGIN (spawn)
# T517 派生宿主窗口解析（ADR 2026-10-13-derived-pane-window-addressing · PRD T517 §五）
#   入口一次性解析 → 全局 HOST_WINDOW=@<window_id>；空 = 定位失败 ⇒ 解析处 warn 一次（每 run 一次），
#   spawn_tmux 对空值跳过该 pane（D-A：warn + skip，禁无 -t 续建——那是拆用户视图）。定位链：
#     L1 NAO_TMUX_HOST_WINDOW   显式覆盖：display-message 探测归一化；允许跨 session（@id 全局唯一），
#                                非 @id 形式 warn 建议用 @id；解析失败（关窗/垃圾值）⇒ warn + 沿链降级（不 die）
#     L2 $TMUX_PANE → window_id 调用者 pane 所在 window（= 派生宿主；不依赖 client 视图；核心路径）
#     L3 名册唯一命中            仅在本 $TMUX 所属 session 内取候选窗（pane→window 全表一次调用
#                                + 名册 cwd=本仓 + 活 pane + 窗口去重唯一）；歧义/无命中 ⇒ warn 标来源，不猜
#     L4 skip                    warn + 不创建（其余角色继续；rc 不劣化）
#   调用预算：L1/L2 各 ≤1 次 tmux 调用；L3 ≤2 次（session 探测 + list-panes 全表）。
resolve_host_window() {
  local tgt="" sess_id="" pid wid sid abs rp rw
  # L1 显式覆盖
  if [[ -n "${NAO_TMUX_HOST_WINDOW:-}" ]]; then
    tgt="$(tmux display-message -p -t "$NAO_TMUX_HOST_WINDOW" '#{window_id}' 2>/dev/null || true)"
    if [[ -n "$tgt" ]]; then
      [[ "$NAO_TMUX_HOST_WINDOW" == "@"* ]] || \
        warn "NAO_TMUX_HOST_WINDOW=$NAO_TMUX_HOST_WINDOW 非 @id 形式（裸窗口名跨 session 可能歧义）→ 已归一化 $tgt，建议改用 @id"
      log "宿主窗口 = NAO_TMUX_HOST_WINDOW（显式覆盖）→ $tgt"
      HOST_WINDOW="$tgt"; return 0
    fi
    warn "NAO_TMUX_HOST_WINDOW=$NAO_TMUX_HOST_WINDOW 解析失败（窗口已关或非法）→ 降级 TMUX_PANE/名册"
  fi
  # L2 调用者 pane → window_id（同一次调用顺带取 session_id，供 L3 限定本 session）
  if [[ -n "${TMUX_PANE:-}" ]]; then
    read -r tgt sess_id < <(tmux display-message -p -t "$TMUX_PANE" '#{window_id} #{session_id}' 2>/dev/null || true) || true
    if [[ -n "$tgt" ]]; then
      HOST_WINDOW="$tgt"; return 0
    fi
    warn "TMUX_PANE=$TMUX_PANE 解析不到 window_id（pane 已关？）→ 降级名册推断"
  else
    warn "TMUX 已设但 TMUX_PANE 空（AC5b 场景）→ 跳 L2，降级名册推断"
  fi
  # L3 名册唯一命中（D-B：仅本 $TMUX 所属 session 内取候选窗，不跨 session 推断）
  [[ -n "$sess_id" ]] || sess_id="$(tmux display-message -p '#{session_id}' 2>/dev/null || true)"
  if [[ -z "$sess_id" ]]; then
    warn "无法确定本 \$TMUX 所属 session（无 client/无 pane 句柄）→ 名册推断无从限定，L4 skip"
    return 0
  fi
  local -A win_of=()
  # pane→window 全表（1 次调用；pane 在表中即活，无需单独探测）
  while IFS=$'\t' read -r pid wid sid; do
    [[ "$sid" == "$sess_id" ]] && win_of["$pid"]="$wid"
  done < <(tmux list-panes -a -F "#{pane_id}"$'\t'"#{window_id}"$'\t'"#{session_id}" 2>/dev/null || true)
  abs="$(repo_abspath "$PWD")"; [[ -n "$abs" ]] || return 0
  local -A seen=()
  local -a wins=()
  # 名册 tmuxPane（cwd=本仓）→ 本 session 窗口去重（与 fallback_pane_for 同构的 cwd 过滤）
  while IFS= read -r rp; do
    [[ -n "$rp" ]] || continue
    rw="${win_of[$rp]:-}"
    [[ -n "$rw" ]] && { [[ -z "${seen[$rw]:-}" ]] && { seen["$rw"]=1; wins+=("$rw"); }; }
  done < <(intercom_list_json 2>/dev/null | sed 's/},/}\n/g' | awk -v a="$abs" '
    /"cwd":[[:space:]]*"/  { s=$0; sub(/.*"cwd":[[:space:]]*"/,"",s);  sub(/".*/,"",s);  cc=s }
    /"tmuxPane":[[:space:]]*"/ { s=$0; sub(/.*"tmuxPane":[[:space:]]*"/,"",s); sub(/".*/,"",s); cp=s
                                  if (cp != "" && cc == a) print cp }
  ' || true)  # sed 按对象边界拆行：紧凑/pretty 两种 JSON 布局同语义（逐条目取 cwd+tmuxPane）
  if (( ${#wins[@]} == 1 )); then
    HOST_WINDOW="${wins[0]}"
    warn "名册唯一命中宿主窗口 $HOST_WINDOW（来源：名册 tmuxPane + cwd=本仓 + 仅本 session $sess_id）"
    return 0
  fi
  if (( ${#wins[@]} > 1 )); then
    warn "名册推断歧义：本 session 内候选窗 ${wins[*]}（>1）→ 不猜，L4 skip（可设 NAO_TMUX_HOST_WINDOW 显式指定）"
  else
    warn "名册推断无命中：本 session 内无名册 pane 或 cwd≠本仓 → L4 skip（可设 NAO_TMUX_HOST_WINDOW 显式指定）"
  fi
  return 0   # HOST_WINDOW 保持空 ⇒ spawn_tmux 跳过（D-A：warn + skip，禁无 -t 续建）
}

spawn_tmux() {
  local name="$1" inner="$2"
  case "$TMUX_LAYOUT" in
    main-row2|main-col|grid) ;;
    *) die "NAO_TMUX_LAYOUT 无效: $TMUX_LAYOUT（可选 main-row2|main-col|grid）" ;;
  esac
  local wrapped="bash -lc $(printf %q "$inner")"
  # T517：目标显式化——HOST_WINDOW 解析失败时此处已由解析处 warn（每 run 一次），
  #   跳过该 pane；禁止无 -t 续建（tmux 会落「当前窗口」= 用户视图，即缺陷根因）。
  # T539：显式回报「跳过」（不再用 return 0 冒充成功）。
  [[ -n "$HOST_WINDOW" ]] || return "$SPAWN_RC_SKIP"
  # 窄窗口/宿主上限会让 split-window 失败（no space for new pane，含宿主窗已关竞态）；
  # 捕获后 warn 并继续，不因单个 pane 失败中断整轮 ensure。
  # T539：显式回报「失败」；两条 warn 是诊断信息，保留不合并。
  local serr
  if ! serr=$(tmux split-window -h -t "$HOST_WINDOW" "$wrapped" 2>&1); then
    warn "pane 创建失败（宿主窗口 $HOST_WINDOW 过窄/已关或已达上限）：${serr:-<no message>}"
    warn "  已跳过该 pane，其余角色继续拉起；可放大窗口后重跑 ensure"
    return "$SPAWN_RC_FAIL"
  fi
  # 布局是尽力而为（内部各 tmux 调用已 || true）；布局成败不影响「pane 已创建」这一结果。
  apply_tmux_layout || true
  return "$SPAWN_RC_OK"
}
# <<< term-impl-tmux END (spawn)

# 组装系统提示文件：角色卡 + 环境锚点（本机绝对路径，供跨仓库会话解析 @ 引用失败时兜底）
build_system_prompt() {
  local card="$1" f
  f="$(mktemp "/tmp/nao-fleet-$(basename "$card" .md)-XXXXXX.md")"
  {
    cat "$card"
    printf '\n## 环境锚点\n- NAO_SKILLS=%s（nao 机制**包根**；@.agents/... 引用一律以 `$NAO_SKILLS/.agents/` 为根解析。注意：项目内 `.agents/` 只有 shim，不存机制副本）\n' "$SKILLS_DIR"
  } > "$f"
  echo "$f"
}

spawn_one() {
  local name="$1" repo="$2" model="$3" card_override="${4:-}" role_id="${5:-}" card_name="${6:-}" force="${7:-false}" card prompt_file inner
  # T537：卡路径可由调用方显式给出（下游仓卡）；未给出时仍走清单（PROMPTS_DIR/<card>）逐字不变
  # #75：**两条取卡通道分两个参数，禁混用** ——
  #   ④ card_override = `--card` 的**完整路径**（下游卡，已由 resolve_card 限定在 <repo>/.agents/prompts/ 内）
  #   ⑥ card_name     = 清单**相对名**（roles.yaml 的 card 文件名，由 cmd_ensure **按目标**下发）
  #   旧写法在无 override 时回落全局 `$PROMPT`（resolve 阶段每个目标覆写一次 ⇒ 最后一个胜出），
  #   于是多目标 `ensure arch rd-fe` 的**每个** pane 都拿到最后一个目标的卡（身份级错误）。
  if [[ -n "$card_override" ]]; then card="$card_override"; else card="$PROMPTS_DIR/${card_name:-}"; fi
  [[ -f "$card" ]] || die "角色卡不存在: $card"
  [[ -d "$repo" ]] || die "工作区不存在: $repo"

  # 前提已由入口 term_require 硬校验（tmux: exit 3；herdr: HERDR_ENV/HERDR_SESSION/protocol 22）；
  #   此处只走唯一路径（BR1/BR3）。
  prompt_file="$(build_system_prompt "$card")"
  inner="cd $(printf %q "$repo") && export CODEGRAPH_TELEMETRY=0 && exec pi --name $(printf %q "$name")"
  [[ -n "$model" ]] && inner+=" --model $(printf %q "$model")"
  inner+=" --append-system-prompt $(printf %q "$prompt_file")"
  # M20261103/R2/R4：pm 目标在 `--append-system-prompt` **之后**以 `--` 分隔追加一条固定首条用户消息
  #   （版本自检提示）；文本整体 printf %q 转义（禁拼接未转义文本）⇒ 不会被当成 @file 或选项。
  #   纯字符串拼接，不跑任何外部命令（零网络）；非 pm / 开关关闭 ⇒ 本段不执行（命令行逐字不变）。
  if [[ "$role_id" == "pm" ]] && update_check_enabled; then
    inner+=" -- $(printf %q "$NAO_UPDATE_MSG")"
  fi
  # T536/BR2：后台清理必须**完全脱离调用方 fd**。原写法 `( sleep 60; … ) &` 让子 shell 继承调用方
  #   stdout/stderr ⇒ 输出被 `| cat` / CI 捕获时调用方要等 EOF 到 60s 才返回（实测 60.3s vs 0.3s）。
  #   `disown` 只脱离作业表，不关继承而来的 fd。⇒ ① 三路重定向到 /dev/null；② 改用独立 argv 的
  #   `bash -c`（清理进程不再顶着本脚本 argv，`pgrep -f nao-fleet.sh` 无残留命中）。
  #   不用 setsid：macOS 无该 bin，`… || true` 会静默跳过清理（BR1 缩水）。清理窗口 60s 不缩短。
  bash -c 'sleep 60; rm -f -- "$1"' _ "$prompt_file" >/dev/null 2>&1 </dev/null & disown 2>/dev/null || true

  # 拉起：门面 term_spawn 以**显式三态**回报（T539/BR2；tmux = spawn_tmux 逐字不变，herdr = B2 新实现）；
  #   每目标恰一行结果行：成功 → 唯一一条 `[tmux] 已拉起 …`（tmux 仍逐字不变，BR1）· 跳过/失败 → 不打印成功行。
  #   `|| rc=$?` 是 set -e 下的必需写法（|| 列表豁免 errexit）；函数返回值即结果契约。
  local rc=0
  _TERM_SPAWN_PANE=""
  term_spawn "$name" "$inner" "$repo" "$force" || rc=$?
  case "$rc" in
    "$SPAWN_RC_OK")   SPAWN_OK=$((SPAWN_OK + 1))
                      if [[ "$NAO_TERMINAL" == "herdr" ]]; then
                        log "[herdr] 已拉起 $name @ $repo${model:+（model=$model）}${_TERM_SPAWN_PANE:+（pane=$_TERM_SPAWN_PANE）}"
                      else
                        log "[tmux] 已拉起 $name @ $repo${model:+（model=$model）}（layout=$TMUX_LAYOUT）"
                      fi ;;
    "$SPAWN_RC_SKIP") SPAWN_SKIP=$((SPAWN_SKIP + 1)) ;;
    *)                SPAWN_FAIL=$((SPAWN_FAIL + 1)) ;;   # 3 = fail；未知值按失败处理（宁可少报成功）
  esac
}

# ---------------------------------------------------------------------------
cmd_check() {
  local strict="${1:-false}"
  local rc=0 f lines d
  local wl_problems=0

  echo "== 目录 =="
  for d in "$PROMPTS_DIR" "$COMMON_DIR" "$SKILLS_SUB" "$SKILLS_DIR"/.agents/checklists; do
    if [[ -d "$d" ]]; then printf '  ✓ %s\n' "$d"
    else printf '  ✗ 缺失: %s\n' "$d"; rc=1; fi
  done

  echo "== 文本契约（roles.yaml 缩进 2/4 · .agents/** EOL 全 LF）=="
  if [[ -f "$MANIFEST" ]]; then
    if check_roles_indent; then
      printf '  ✓ roles.yaml 缩进契约（角色 id 2 空格 / 字段 4 空格 / 无 Tab）\n'
    else
      rc=1
    fi
  else
    printf '  ✗ roles.yaml 缺失: %s\n' "$MANIFEST"; rc=1
  fi
  check_eol || rc=1

  echo "== 角色清单 roles.yaml =="
  load_manifest
  printf '  ✓ 解析成功，%d 个角色: %s\n' "${#ROLE_ORDER[@]}" "${ROLE_ORDER[*]}"
  check_alias_resolution || rc=1

  echo "== 常驻角色卡（阈值 ${CARD_MAX_LINES} 行，frontmatter 校验）=="
  local a role version updated
  for a in "${ROLE_ORDER[@]}"; do
    f="$PROMPTS_DIR/${ROLE_CARDS[$a]}"
    if [[ ! -f "$f" ]]; then
      printf '  ✗ %-26s 缺失\n' "${ROLE_CARDS[$a]}"; rc=1; continue
    fi
    lines=$(wc -l < "$f")
    if (( lines > CARD_MAX_LINES )); then
      printf '  ! %-26s %3d 行（超阈值，建议拆到 skills/）\n' "${ROLE_CARDS[$a]}" "$lines"
    else
      printf '  ✓ %-26s %3d 行\n' "${ROLE_CARDS[$a]}" "$lines"
    fi
    role="$(card_field "$f" role)"
    version="$(card_field "$f" version)"
    updated="$(card_field "$f" updated)"
    if [[ "$role" != "$a" ]]; then
      printf '  ✗ %s frontmatter role=%s 与 manifest 角色 %s 不一致\n' "${ROLE_CARDS[$a]}" "${role:-<缺失>}" "$a"; rc=1
    fi
    if [[ ! "$version" =~ ^[0-9]+$ ]]; then
      printf '  ✗ %s frontmatter version=%s 缺失或非整数\n' "${ROLE_CARDS[$a]}" "${version:-<缺失>}"; rc=1
    fi
    if [[ -z "$updated" ]]; then
      printf '  ✗ %s frontmatter updated 缺失（应如 2026-09-21）\n' "${ROLE_CARDS[$a]}"; rc=1
    fi
  done

  echo "== prompts/ 孤儿检查 =="
  local cf found c2 orphan=0
  shopt -s nullglob
  for cf in "$PROMPTS_DIR"/*.md; do
    found=0
    for c2 in "${ROLE_ORDER[@]}"; do
      [[ "$(basename "$cf")" == "${ROLE_CARDS[$c2]}" ]] && found=1
    done
    if (( ! found )); then printf '  ! %s 未登记于 roles.yaml\n' "$(basename "$cf")"; orphan=1; fi
  done
  shopt -u nullglob
  (( orphan )) || echo '  ✓ 无孤儿卡'

  echo "== 下游角色卡（若存在）=="
  check_downstream_cards || rc=1

  echo "== pi 扩展声明（T527：声明 + 文件存在，防「声明漏写 ⇒ 静默无 agent」）=="
  if [[ ! -f "$SKILLS_DIR/package.json" ]]; then
    # 非包根（legacy 仓内真脚本 / 夹具只有 .agents）：无 manifest 可核，跳过不判 FAIL
    echo '  · package.json 缺失（非包根/legacy：跳过 pi.extensions 校验）'
  elif ! command -v node >/dev/null 2>&1; then
    printf '  ✗ node 缺失，无法校验 pi.extensions 声明\n'; rc=1
  else
    local ext_list="" ext_bad=0 e
    if ext_list="$(node -e '
      const p=require(process.argv[1]); const pi=p.pi||{};
      const ex=pi.extensions;
      if(!Array.isArray(ex)||ex.length===0) process.exit(3);
      process.stdout.write(ex.join("\n"));
    ' "$SKILLS_DIR/package.json" 2>/dev/null)"; then
      while IFS= read -r e; do
        [[ -n "$e" ]] || continue
        if [[ ! -e "$SKILLS_DIR/$e" ]]; then
          printf '  ✗ pi.extensions 声明条目不存在: %s\n' "$e"; ext_bad=1; rc=1
        fi
      done <<< "$ext_list"
      if (( ext_bad == 0 )); then
        printf '  ✓ pi.extensions 声明 %d 条且文件存在\n' "$(printf '%s\n' "$ext_list" | grep -c .)"
      fi
    else
      printf '  ✗ pi.extensions 未声明或非法（package.json）\n'; rc=1
    fi
  fi

  echo "== 公共规范 =="
  for f in output-format.md intercom-protocol.md; do
    if [[ -f "$COMMON_DIR/$f" ]]; then printf '  ✓ %s\n' "$f"
    else printf '  ✗ %s 缺失\n' "$f"; rc=1; fi
  done

  echo "== PR 模板（GitHub Flow）=="
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo '  · 非 git 仓库（跳过）'
  else
    local remote_url prtpl="" cand
    remote_url="$(git config --get remote.origin.url 2>/dev/null || true)"
    if [[ -z "$remote_url" ]]; then
      echo '  · 无 remote.origin（跳过）'
    elif [[ "$remote_url" != *github.com* ]]; then
      echo '  · 远端非 GitHub（跳过；PR 模板不适用）'
    else
      shopt -s nullglob
      for cand in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md \
                  .github/PULL_REQUEST_TEMPLATE \
                  pull_request_template.md PULL_REQUEST_TEMPLATE.md \
                  docs/pull_request_template.md docs/PULL_REQUEST_TEMPLATE.md; do
        [[ -e "$cand" ]] && { prtpl="$cand"; break; }
      done
      shopt -u nullglob
      if [[ -n "$prtpl" ]]; then
        printf '  ✓ PR 模板已就位：%s\n' "$prtpl"
      else
        echo '  ! 未找到 PR 模板（GitHub 远端）：PM 立项时从 .agents/templates/github/pull_request_template.md.example 复制为 .github/pull_request_template.md（见 skills/github-flow.md）'
      fi
    fi
  fi

  echo "== 按需技能 =="
  if [[ -d "$SKILLS_SUB" ]]; then
    shopt -s nullglob
    for f in "$SKILLS_SUB"/*.md; do printf '  · %s\n' "$(basename "$f")"; done
    shopt -u nullglob
  fi

  echo "== 交叉引用（@.agents/common|skills|prompts|scripts/... 均须存在）=="
  check_cross_refs || rc=1

  echo "== CodeGraph（四态检测：全部 warn，永不计入 rc；默认不调用 CLI）=="
  local cgfull=0
  if $VERBOSE; then cgfull=1; fi
  codegraph_state "$PWD" "$cgfull"

  echo "== pi 插件（业界调研能力）=="
  local piset="$PI_AGENT_DIR/settings.json"
  if [[ -f "$piset" ]]; then
    if grep -q 'pi-web-access' "$piset" 2>/dev/null; then
      echo '  · pi-web-access ✓ 已装（PM/arch 业界调研可用）'
    else
      echo '  ! pi-web-access 未装（业界调研不可用；nao-skill plugins install web-access）'
    fi
  else
    echo "  · 未找到 $piset（跳过插件检测）"
  fi

  echo "== 模型白名单 =="
  if [[ -z "$MODEL_WHITELIST" ]]; then
    echo "  （未设置 NAO_MODEL_WHITELIST，-m 不校验）"
  else
    local entry s dup kind tag
    local entries=() seen=()
    IFS=',' read -ra entries <<< "$MODEL_WHITELIST"
    for entry in "${entries[@]}"; do
      entry="${entry#"${entry%%[![:space:]]*}"}"
      entry="${entry%"${entry##*[![:space:]]}"}"
      if [[ -z "$entry" ]]; then
        printf '  ! 空条目被忽略\n'
        wl_problems=$((wl_problems + 1))
        continue
      fi
      dup=0
      for s in "${seen[@]}"; do [[ "$s" == "$entry" ]] && { dup=1; break; }; done
      seen+=("$entry")
      case "$entry" in
        *'*'*|*'?'*|*'['*) kind="glob" ;;
        *)                 kind="字面量" ;;
      esac
      tag=""
      if (( dup )); then tag=" [重复]"; wl_problems=$((wl_problems + 1)); fi
      if [[ "$entry" == "*" ]]; then tag+=" [过宽!]"; wl_problems=$((wl_problems + 1)); fi
      printf '  · %-32s (%s)%s\n' "$entry" "$kind" "$tag"
    done
  fi

  echo "== 运行前提（tmux 内 + pi ≥$MIN_PI_VERSION；AC1/AC3）=="
  if [[ "$(term_backend 2>/dev/null)" == "herdr" ]]; then
    # B1：仅 herdr 模式加行（tmux 路径零新增输出 —— BR1/AC2.6）。
    #   rc 口径（P3-4 订正）：显式指定 herdr 却**缺 herdr 可执行文件** ⇒ rc=1（明确错配，不能装没看见）；
    #   缺 `HERDR_SESSION`（未在 herdr pane 内，CI 常见）⇒ 只提示不置红（静态体检照跑）；
    #   `protocol≠22` ⇒ rc=1（唯一可置红的机械项）。
    echo '  · 生效后端 NAO_TERMINAL=herdr（#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）'
    if command -v herdr >/dev/null 2>&1; then
      printf '  ✓ herdr 可用\n'
      if [[ -n "${HERDR_SESSION:-}" && "${HERDR_SESSION}" != "default" ]]; then
        printf '  ✓ HERDR_SESSION=%s\n' "$HERDR_SESSION"
        local hschema hproto
        if hschema="$(_term_herdr_exec api schema 2>/dev/null)"; then
          hproto="$(printf '%s\n' "$hschema" | sed -n 's/^protocol:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
          if [[ "$hproto" == "$TERM_HERDR_PROTOCOL" ]]; then
            printf '  ✓ herdr protocol=%s\n' "$hproto"
          else
            printf '  ✗ herdr protocol=%s ≠ %s（破坏性变更 ⇒ fail loud）\n' "${hproto:-<未知>}" "$TERM_HERDR_PROTOCOL"
            rc=1
          fi
        else
          printf '  · herdr api schema 不可用（status 将 exit 3）\n'
        fi
      else
        echo '  · 未在 herdr pane 内（HERDR_SESSION 空/default）：status 将 exit 3；纯静态体检可照跑'
      fi
    else
      printf '  ✗ herdr 缺失（status 将 exit 3）\n'; rc=1
    fi
    if command -v tmux >/dev/null 2>&1; then
      echo '  · tmux 可用（回退能力：NAO_TERMINAL=tmux）'
    else
      echo '  · tmux 缺失（herdr 后端下仅影响回退能力）'
    fi
  else
  if command -v tmux >/dev/null 2>&1; then
    echo '  ✓ tmux 可用（唯一受支持宿主）'
  else
    printf '  ✗ tmux 缺失（ensure/status/close 将 exit 3）\n'; rc=1
  fi
  if [[ -n "${TMUX:-}" ]]; then
    # B4：会话名经门面取（tmux 证据层 `_term_tmux_current_session`；业务区不再裸调后端）
    local tmux_session_now
    tmux_session_now="$(term_session_name 2>/dev/null)"
    echo "  ✓ 当前在 tmux 会话内（${tmux_session_now:-?}）"
  else
    printf '  · 当前不在 tmux 会话内：ensure/status/close 将 exit 3（先 `tmux new -s nao`）；纯静态体检可照跑\n'
  fi
  fi
  local pi_cur
  if pi_cur="$(pi_version_check)"; then
    printf '  ✓ pi 版本 %s ≥ %s\n' "$pi_cur" "$MIN_PI_VERSION"
  else
    printf '  ✗ pi 版本 %s < %s\n' "$pi_cur" "$MIN_PI_VERSION"; rc=1
  fi

  echo "== tmux 布局 =="
  if [[ -z "${TMUX:-}" && "$(term_backend 2>/dev/null)" == "tmux" ]]; then
    echo '  · 当前不在 tmux 内（布局只在 tmux 分屏时生效）'
  fi
  case "$TMUX_LAYOUT" in
    main-row2|main-col|grid)
      printf '  ✓ NAO_TMUX_LAYOUT=%-10s 合法\n' "$TMUX_LAYOUT" ;;
    *)
      printf '  ✗ NAO_TMUX_LAYOUT=%-10s 非法（可选 main-row2|main-col|grid）\n' "$TMUX_LAYOUT"; rc=1 ;;
  esac
  if [[ "$TMUX_LAYOUT" == "main-row2" || "$TMUX_LAYOUT" == "main-col" ]]; then
    if [[ "$TMUX_MAIN_WIDTH" =~ ^[0-9]+$ ]] && (( TMUX_MAIN_WIDTH >= 10 && TMUX_MAIN_WIDTH <= 90 )); then
      printf '  ✓ NAO_TMUX_MAIN_WIDTH=%-3s%% 合法\n' "$TMUX_MAIN_WIDTH"
    else
      printf '  ! NAO_TMUX_MAIN_WIDTH=%-3s  非法（10..90）：越界夹取到 10/90，非数字回退 %s\n' "$TMUX_MAIN_WIDTH" "$TMUX_MAIN_WIDTH_DEFAULT"
    fi
  fi
  if [[ "$TMUX_MIN_PANE_WIDTH" =~ ^[0-9]+$ ]] && (( TMUX_MIN_PANE_WIDTH >= 10 && TMUX_MIN_PANE_WIDTH <= 80 )); then
    printf '  ✓ NAO_TMUX_MIN_PANE_WIDTH=%-3s 合法\n' "$TMUX_MIN_PANE_WIDTH"
  else
    printf '  ! NAO_TMUX_MIN_PANE_WIDTH=%-3s 非法（10..80）：越界夹取到 10/80，非数字回退 %s\n' "$TMUX_MIN_PANE_WIDTH" "$TMUX_MIN_PANE_WIDTH_DEFAULT"
  fi

  if [[ "$strict" == "true" && $wl_problems -gt 0 ]]; then
    warn "strict 模式：白名单发现 $wl_problems 项问题（空条目/重复/过宽）"
    rc=1
  fi

  return $rc
}

# ---------------------------------------------------------------------------
# T534（A · ADR 2026-10-31-fleet-status-repo-attribution）：派生会话归属加「仓」维度
#   北极星 = 本仓 status 的残留提示**永不**指向他仓会话（BR2「提示即可执行」）；
#   close / ensure **零改动**（BR3），本批只收紧 status 的判定与提示。
# 物理归一：pwd -P → readlink -f → 原串（目录已删/不可读时不猜，交给组件级前缀判否）
nao_phys_path() {
  local p="$1" out=""
  [[ -n "$p" ]] || return 0
  out="$(cd "$p" 2>/dev/null && pwd -P)" || out=""
  [[ -n "$out" ]] || out="$(readlink -f -- "$p" 2>/dev/null || true)"
  [[ -n "$out" ]] || out="$p"
  printf '%s\n' "$out"
}

# 单行谓词（AC7⑤，同时是 AC2 的单行变异点）：cwd 是否落在 root 子树内。
#   组件级前缀：`/a/b` **不**命中 `/a/bc`（裸字符串前缀的经典陷阱 ⇒ AC7②）。
repo_contains_path() { [[ -n "$1" && -n "$2" && ( "$2" == "$1" || "$2" == "${1%/}"/* ) ]]; }

# 本仓锚集（每 run 一次）：主锚 pwd -P；git toplevel 是 cwd **严格祖先**时并入
#   （覆盖在 `.agents/` 等子目录跑 status ⇒ AC7③）。不用 roles.yaml workspace（常为 `.`/子目录，且 ensure 支持 @repo）。
repo_anchor_roots() {
  local cwd top
  cwd="$(nao_phys_path "$PWD")"
  [[ -n "$cwd" ]] && printf '%s\n' "$cwd"
  command -v git >/dev/null 2>&1 || return 0
  top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$top" ]] || return 0
  top="$(nao_phys_path "$top")"
  [[ -n "$top" && "$top" != "$cwd" ]] || return 0
  repo_contains_path "$top" "$cwd" || return 0
  printf '%s\n' "$top"
}

# pane cwd 一次快照（**禁**逐名 find_pane_for：O(N) 次 tmux 调用违 NFR「不引入额外 I/O 循环」）
#   输出：name<TAB>pane_id<TAB>pane_current_path；标题契约 `π - <会话名> - <任意>`（会话名字符集含 `@`）
# P7（BR8）：名字字符集不加 `@` ⇒ 带 scope 的 pane 在归属层直接丢失 ⇒ 被归他仓/unknown。
# >>> term-impl-tmux BEGIN (pane cwd)
_term_tmux_pane_cwds() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux list-panes -a -F "#{pane_id}"$'\t'"#{pane_title}"$'\t'"#{pane_current_path}" 2>/dev/null \
    | awk -F'\t' -v p="$PI_TITLE" '
        { pre = p " - "
          if (index($2, pre) != 1) next
          rest = substr($2, length(pre) + 1)
          i = index(rest, " - ")
          if (i <= 1) next
          name = substr(rest, 1, i - 1)
          if (name !~ /^[A-Za-z0-9_@-]+$/) next
          print name "\t" $1 "\t" $3
        }' || true
}
# <<< term-impl-tmux END (pane cwd)

# 共享投影（无后端调用）：herdr 从门面快照取 name/pane/cwd（列 1/2/4）；tmux 走标题契约证据层
pane_cwd_snapshot() {
  case "$(term_backend)" in
    tmux) _term_tmux_pane_cwds ;;
    herdr) term_snapshot | awk -F'\t' '$1 != "" && $2 != "" {print $1 "\t" $2 "\t" $4}' ;;
  esac
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

# ---------------------------------------------------------------------------
# T537 · 下游仓自定义角色会话（ensure --card）—— ADR 2026-11-01-downstream-card-sessions
#   定位：卡（= 系统提示）来自**下游项目仓** <repo>/.agents/prompts/<file>.md；会话属派生/一次性
#   语义（与常驻同等的 pane 托管 / status 可见 / close 可回收），但不登记 roles.yaml、不算常驻。
#   三条机制不变量（BR9）：① 卡 role 与常驻 id/别名**相等或前缀相交**即拒（防抢 status 枚举）；
#   ② 卡集内部前缀反链（check 报 error，status/close 用最长匹配兜底）；③ 字符集/长度契约。
#   这三条是「status 能在既有 ROLE_ORDER 循环之后追加枚举而不改既有行」的前提（arch Q2）。
#   定性：卡限定目录是**可审计边界，不是权限边界** —— 卡正文 = 完全可信输入（能写该仓者
#   即定义角色）；这里只做一致性校验（目录/常规文件/大小/命名），不做也不该做内容安全校验。

# 命名契约（BR9 · AC3②③ · AC6）：echo 单行原因并返回 1；合法返回 0（无输出）
# P9（BR8）：校验对象改为 **core**（≤32 / 字符集 / 尾 - / 保留前缀 / 撞常驻）+ scope（字符集 /
#   ≤16 / 尾 - / 禁 @ . : 空白）+ 总长 ≤48 单判。带 scope 的全名并不由 `--as` 产生（P10 只给 core），
#   但 status/close 的校验面必须能说清「带 scope 的名字合不合法」——两条口径共用本函数。
card_name_problem() {
  local n="$1" core="$1" scope="" r rp why
  [[ -n "$n" ]] || { echo "名字为空"; return 1; }
  (( ${#n} <= 48 )) || { echo "名字过长（总名 ${#n} > 48 字符）"; return 1; }
  case "$n" in
    *@*)
      core="${n%@*}"; scope="${n##*@}"
      case "$core" in *@*) echo "名字含多个 @（只允许一个 scope 分隔符）"; return 1 ;; esac
      if ! why="$(fleet_scope_problem "$scope")"; then echo "scope 不可用：$why"; return 1; fi
      ;;
  esac
  (( ${#core} <= 32 )) || { echo "名字过长（core ${#core} > 32 字符）"; return 1; }
  [[ "$core" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
    || { echo "名字含非法字符（只允许小写字母/数字/-/_，且首字符须为字母或数字）"; return 1; }
  [[ "$core" != *- ]] || { echo "名字不得以 - 结尾"; return 1; }
  for rp in $CARD_RESERVED_PREFIXES; do
    [[ "$core" != "$rp"* ]] || { echo "名字不得以保留前缀 $rp 开头（$rp 归 pi-subagents / nao 机制）"; return 1; }
  done
  if [[ -n "${ALIAS_ROLE[$core]:-}" ]]; then
    echo "名字与常驻角色/别名 $core 同名（该怎么办：改卡内 frontmatter role —— fleet 按前缀识别身份，--as 也须保留卡 role 前缀，绕不过同名冲突）"; return 1
  fi
  for r in "${ROLE_ORDER[@]}" "${!ALIAS_ROLE[@]}"; do
    [[ "$core" != "$r"-* ]] \
      || { echo "名字以常驻前缀 $r- 开头（会抢走 status/close 对 $r 的枚举；该怎么办：改卡内 role，使其不以任何常驻 id/别名为 <x>- 前缀）"; return 1; }
  done
  return 0
}

# 卡集（status/close 的识别集 · Q2）：锚根全集下 <root>/.agents/prompts/*.md 的 frontmatter role（退化文件名）。
#   输出：role<TAB>卡路径<TAB>锚根。**只收合法且非常驻的 role** —— 安装副本/常驻卡不进卡集
#   （BR9 保证二者不相交；非法卡 ensure 必拒，其历史会话落 status 的「角色未识别」节，不静默）。
#   运行时读、不落状态文件（守「不新增配置」）；每 run 一次 glob + frontmatter 读，不新增 tmux/node 调用。
card_role_set() {
  local root f role phys n=0
  local -a roots=() files=()
  mapfile -t roots < <(repo_anchor_roots)
  (( ${#roots[@]} )) || return 0
  shopt -s nullglob
  for root in "${roots[@]}"; do
    # 非常规文件（fifo/目录/设备）不入卡集：否则每次 status/close 都要打开它（fifo 会挂死）
    for f in "$root/.agents/prompts"/*.md; do [[ -f "$f" ]] && files+=("$f"); done
  done
  shopt -u nullglob
  local -A seen=()
  for f in "${files[@]}"; do
    phys="$(nao_phys_path "$f")"
    [[ -z "${seen[$phys]:-}" ]] || continue
    seen["$phys"]=1
    role="$(card_field "$f" role)"
    [[ -n "$role" ]] || role="$(basename -- "$f" .md)"
    [[ -z "$(card_name_problem "$role")" ]] || continue
    n=$((n + 1))
    printf '%s\t%s\t%s\n' "$role" "$f" "${f%/.agents/prompts/*}"
  done
  if (( n > CARD_SET_MAX )); then
    warn "下游角色卡 $n 张 > 上限 $CARD_SET_MAX：status/close 只做名字匹配，建议精简本仓 .agents/prompts/"
  fi
  return 0
}

# 卡校验（BR3 六条 · AC2 八种失败输入）：通过则设 CARD_PATH / CARD_ROLE / CARD_REPO（均 realpath）。
#   失败一律 die（单行「原因 + 该怎么办」），且**必在建 pane 之前**（cmd_ensure 两相执行 ⇒ BR6 零副作用）。
#   ① 基准 = <repo> realpath；② 显式拒 `..` 与非 .md；③ 常规文件（fifo/目录会让 cat 挂死）；
#   ④ 256 KiB 上限；⑤ 文案含「该怎么办」；⑥ 定性见上（可审计边界）。
resolve_card() {  # $1=卡路径 · $2=仓（可空 ⇒ $PWD）
  local arg="$1" repo_arg="${2:-}" repo cand card_phys parent_phys prompts_phys role bytes why
  repo="${repo_arg:-$PWD}"
  case "/$arg/" in
    */../*) die "角色卡路径不得含 '..'：$arg（该怎么办：用 <repo>/.agents/prompts/<name>.md 的相对/绝对路径，不要用 .. 回退）" ;;
  esac
  case "$arg" in
    *.md) ;;
    *) die "角色卡须为 .md 文件：${arg:-<空>}（该怎么办：把卡放在 <repo>/.agents/prompts/<name>.md）" ;;
  esac
  [[ -d "$repo" ]] || die "工作区不存在：$repo（该怎么办：--card <卡>@<仓> 指定仓，或先 cd 到目标仓）"
  local repo_phys
  repo_phys="$(nao_phys_path "$repo")"
  # BR3②：相对路径按 realpath(repo) 解析（不是 $PWD；否则 --card <卡>@<他仓> 时两者分歧）
  case "$arg" in
    /*) cand="$arg" ;;
    *)  cand="$repo_phys/$arg" ;;
  esac
  [[ -e "$cand" ]] || die "角色卡不存在：$arg（期望 $repo_phys/.agents/prompts/；该怎么办：在目标仓 .agents/prompts/ 下创建该卡，或用 @<仓> 指向正确仓）"
  # BR3③：常规文件 —— fifo/设备/目录会让 cat 永久挂死，必须**在打开之前**拒
  [[ -f "$cand" ]] || die "角色卡不是常规文件（目录/fifo/设备）：$arg（该怎么办：换成 <repo>/.agents/prompts/<name>.md 常规文件）"
  card_phys="$(nao_phys_path "$cand")"
  prompts_phys="$(nao_phys_path "$repo_phys/.agents/prompts")"
  parent_phys="$(nao_phys_path "$(dirname -- "$card_phys")")"
  [[ "$parent_phys" == "$prompts_phys" ]] \
    || die "角色卡不在 <repo>/.agents/prompts/ 内：$arg → $card_phys（符号链接逃逸也算越界；该怎么办：把卡放进 $repo_phys/.agents/prompts/）"
  bytes="$(wc -c < "$card_phys" | tr -d '[:space:]')"
  (( bytes <= CARD_MAX_BYTES )) \
    || die "角色卡过大：$bytes 字节 > $CARD_MAX_BYTES（提示会整段塞进 system prompt；该怎么办：拆到 skills/ 或精简卡）"
  [[ -s "$card_phys" ]] || die "角色卡为空：$arg（该怎么办：至少写 frontmatter role 与一段角色说明）"
  role="$(card_field "$card_phys" role)"
  role="$(printf '%s' "$role" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')"
  [[ -n "$role" ]] || role="$(basename -- "$card_phys" .md)"    # 退化：文件名（AC2「无 role 且无可退化文件名」由命名契约拦下）
  if ! why="$(card_name_problem "$role")"; then
    die "角色卡 role 不可用：$role —— $why（该怎么办：改卡内 frontmatter role，或在 ensure 时加 --as <合规名字>）"
  fi
  CARD_PATH="$card_phys"; CARD_ROLE="$role"; CARD_REPO="$repo_phys"
}

# check 新增节：下游角色卡（若存在）—— D7 分级
#   内容类（缺 role/description、CRLF、超限、含 name: 双用）⇒ `  ! ` warn（不红 rc）
#   机制类（与常驻 id/别名或前缀冲突、卡集前缀嵌套、命名契约越界）⇒ `  ✗ ` error（rc=1，运行期必拒）
#   overlay 兼容（AC8③）：扫描目录 realpath == $PROMPTS_DIR realpath ⇒ 该根整体跳过（否则常驻卡被误报冲突）
#   机制常驻卡的项目内副本（legacy 全量安装）按「同名卡文件」识别 ⇒ 跳过冲突检查（不红）；
#   真正的下游卡（不同文件名）才纳入校验。
check_downstream_cards() {
  local rc=0 root f role desc bytes n=0 why base r
  local -a roots=() scan=() files=() roles=()
  local skipped=0
  mapfile -t roots < <(repo_anchor_roots)
  for root in "${roots[@]}"; do
    [[ -d "$root/.agents/prompts" ]] || continue
    if [[ "$(nao_phys_path "$root/.agents/prompts")" == "$(nao_phys_path "$PROMPTS_DIR")" ]]; then
      skipped=$((skipped + 1)); continue
    fi
    scan+=("$root")
  done
  if (( ${#scan[@]} == 0 )); then
    if (( skipped > 0 )); then
      echo '  · 下游卡扫描目录即机制包 prompts（overlay 生效）：本节跳过'
    else
      echo '  · 未发现下游角色卡目录（<repo>/.agents/prompts/ 不存在）：跳过'
    fi
    return 0
  fi
  shopt -s nullglob
  local -a nonreg=()
  for root in "${scan[@]}"; do
    for f in "$root/.agents/prompts"/*.md; do
      if [[ -f "$f" ]]; then files+=("$f"); else nonreg+=("$f"); fi
    done
  done
  shopt -u nullglob
  # 非常规文件（fifo/目录/设备）：ensure --card 运行期必拒（且 cat 会挂死）⇒ 机制类 error
  for f in "${nonreg[@]:-}"; do
    [[ -n "$f" ]] || continue
    printf '  ✗ %s 不是常规文件（fifo/目录/设备）：ensure --card 必拒，且读取会挂死\n' "$(basename -- "$f")"
    rc=1
  done
  if (( ${#files[@]} == 0 )); then echo '  · 下游角色卡目录为空：跳过'; return 0; fi
  for f in "${files[@]}"; do
    base="$(basename -- "$f")"
    role="$(card_field "$f" role)"
    desc="$(card_field "$f" description)"
    if [[ -z "$role" ]]; then
      printf '  ! %s 缺 frontmatter role（退化用文件名 %s）\n' "$base" "$(basename -- "$f" .md)"
      role="$(basename -- "$f" .md)"
    fi
    local resident=0
    for r in "${ROLE_ORDER[@]}"; do
      if [[ "$base" == "${ROLE_CARDS[$r]}" ]] && [[ "$role" == "$r" || "${ALIAS_ROLE[$role]:-}" == "$r" ]]; then
        resident=1; break
      fi
    done
    if (( resident )); then
      printf '  · %s 机制常驻卡副本（role=%s）：跳过冲突检查\n' "$base" "$role"
      continue
    fi
    n=$((n + 1))
    roles+=("$role")
    printf '  · %s role=%s\n' "$base" "$role"
    [[ -n "$desc" ]] || printf '  ! %s 缺 frontmatter description（建议补一行用途说明）\n' "$base"
    if grep -q $'\r' "$f" 2>/dev/null; then
      printf '  ! %s 含 CRLF（须转 LF；CRLF 会破坏 frontmatter 解析）\n' "$base"
    fi
    bytes="$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')"; bytes="${bytes:-0}"
    (( bytes <= CARD_MAX_BYTES )) \
      || printf '  ! %s %s 字节 > %s（256 KiB；建议拆到 skills/）\n' "$base" "$bytes" "$CARD_MAX_BYTES"
    [[ -z "$(card_field "$f" name)" ]] \
      || printf '  ! %s 含 name: —— 同时被 pi-subagents 视作 agent（其路径无 ## 环境锚点，@.agents 引用不可解析）\n' "$base"
    if ! why="$(card_name_problem "$role")"; then
      printf '  ✗ %s role=%s 不可用：%s（运行期 ensure --card 必拒 ⇒ 闸门提前红）\n' "$base" "$role" "$why"
      rc=1
    fi
  done
  local i j
  for i in "${!roles[@]}"; do
    for j in "${!roles[@]}"; do
      (( i == j )) && continue
      [[ "${roles[$i]}" == "${roles[$j]}-"* ]] || continue
      printf '  ✗ 卡集前缀嵌套：%s 与 %s（后者会抢走前者的 status/close 枚举；须改名）\n' "${roles[$j]}" "${roles[$i]}"
      rc=1
    done
  done
  (( rc != 0 )) || printf '  ✓ 下游角色卡 %d 张，无机制冲突\n' "$n"
  return $rc
}

# ---------------------------------------------------------------------------
cmd_status() {
  local a backend
  backend="$(term_backend)"
  if [[ "$backend" == "herdr" ]]; then
    # B1（BR3/BR7）：herdr 的身份/归属/忙闲全部来自结构化事实 ⇒ 快照**每命令一次**
    #   （≤1 次 pane list / agent list；逐名查询会 7×2 次 CLI，且同命令内两份快照不一致 = 新 flake 源）
    if ! term_snapshot >/dev/null; then
      printf '需要 herdr server：pane list / agent list 不可用（核对 `herdr --session %s server` 是否在跑、protocol 是否 22）\n' "${HERDR_SESSION:-?}" >&2
      exit 3
    fi
  else
    intercom_list_json >/dev/null 2>&1 || true   # 预热名册缓存（后续子 shell 复用）
  fi
  # BR8：parse 的角色事实表（常驻 id + 锚根下合法卡 role）；**一次** glob，不再二次 card_role_set
  fleet_roles_init --cards
  # 一次枚举会话名（标题/会话/名册去重）：下面两轮共用，避免多一轮 tmux/node 调用
  local -a field_names=()
  local dname pout p_kind p_role p_task p_scope
  mapfile -t field_names < <(visible_session_names)
  # P1（前置）：带 scope 的常驻会话（名字 = <role>@<scope>）—— 上方按 `running <role>` 判不到，
  #   不单列就是**整条消失**（BR8 非静默）。scope 为空时本表恒空 ⇒ 常驻区输出逐字不变（BR1）。
  local -A scoped_resident=()
  local any_scoped=0
  for dname in "${field_names[@]}"; do
    pout="$(fleet_name_parse "$dname")"
    [[ "$pout" == "OK "* ]] || continue
    IFS=',' read -r p_kind p_role p_task p_scope <<< "${pout#OK }"
    [[ -n "$p_scope" ]] && any_scoped=1
    [[ "$p_kind" == "resident" && -n "$p_scope" ]] || continue
    # 同一角色可能有多个带 scope 的常驻（不同仓）⇒ 累积成列表（空格分隔，值域是 slug）
    case " ${scoped_resident[$p_role]:-} " in
      *" $p_scope "*) ;;
      *) scoped_resident["$p_role"]="${scoped_resident[$p_role]:-}$p_scope " ;;
    esac
  done
  # ---- B1（herdr）：逐名在线证据一次算定（只读快照，零后端调用）----
  #   单列缺陷类（幽灵 pane / 集成缺失 / 前台非 pi / 身份不一致）不得静默退化成 unknown；
  #   `label` 命中 ≠ same/在线（BR1/AC2.1）。tmux 侧本表恒空 ⇒ 输出逐字不变。
  local -A hv=() hstate=() hseq=() hhook=() abn_seen=()
  local -a term_abn=()
  local vline nm vd vstate vseq vhook
  if [[ "$backend" == "herdr" ]]; then
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
          term_abn+=("  ! $nm 幽灵 pane：label 在、agent 条目缺（label 命中 ≠ 在线；勿当「已在运行」，回收归 B3）") ;;
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
  fi
  if [[ "$backend" == "herdr" ]]; then
    echo "== 角色会话在线状态（本表按 herdr pane label + agent 状态判定；权威源 = pane list / agent list）=="
  else
    echo "== 角色会话在线状态（权威名单见 intercom({action:'list'})；本表按 tmux 终端标题/名册判定）=="
  fi
  local a_ok a_sc a_nm
  for a in "${ROLE_ORDER[@]}"; do
    a_ok=0
    if running "$a" "${ROLE_WS[$a]:-}"; then
      printf '  ✓ %-14s 在线（--name %s；卡片 %s）\n' "$a" "$a" "${ROLE_CARDS[$a]}"
      a_ok=1
    fi
    # P3-2（同族静默漏行）：裸名与带 scope **同场时两条都要显示** —— 旧写法用 elif 只留裸名，
    #   带 scope 那条就整条消失（P1 只覆盖「仅带 scope」）。scope 空 ⇒ 本段零输出（BR1 逐字不变）。
    # P3-3①：显示行里的名字走 builder（§0⑤「builder 之外禁名字拼接」）。
    if [[ -n "${scoped_resident[$a]:-}" ]]; then
      for a_sc in ${scoped_resident[$a]}; do
        a_nm="$(fleet_name_build resident "$a" "$a_sc")"
        # P1（QA 第二轮 · AC2.1 语义破口）：herdr 模式下带 scope 的名字来自 pane.label —— **不是证据**。
        #   tmux 侧该名单来自标题/会话/名册（是证据），可直接打 ✓；herdr 侧必须过门面在线判定，
        #   否则 ghost / dead / mismatch / integration-missing 会被打成「✓ 在线」，
        #   与紧随其后的「终端证据异常」节自相矛盾。非在线交给那一节单列。
        if [[ "$backend" == "herdr" && "${hv[$a_nm]:-absent}" != "online" ]]; then
          continue
        fi
        printf '  ✓ %-14s 在线（--name %s；卡片 %s）·scope=%s\n' \
          "$a" "$a_nm" "${ROLE_CARDS[$a]}" "$a_sc"
        a_ok=1
      done
    fi
    (( a_ok )) || printf '  · %-14s 未运行（ensure 拉起）\n' "$a"
  done
  # D5：分节标题示例带上全名写法 —— **仅当在场确有带 scope 的会话**（scope 为空时逐字保留旧标题 ⇒ BR1）
  if (( any_scoped )); then
    echo "== 任务派生会话（--task 拉起，如 rd-be-T1 / rd-be-T1@todo）=="
  else
    echo "== 任务派生会话（--task 拉起，如 rd-be-T1 / rd-infra-T1）=="
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
  # 名册 cwd 只在 tmux 后端参与归属回退；herdr 侧**只用结构化事实**（roster 仅 -v 差异日志用），
  #   否则名册陈旧/双源矛盾会把 B1 要根除的旧病带回来（arch 1b-3 / 验收补项）。
  if [[ "$backend" == "tmux" ]]; then
    while IFS=$'\t' read -r rn rcwd; do
      [[ -n "$rn" ]] || continue
      [[ -n "${roster_cwds[$rn]:-}" ]] || roster_cwds["$rn"]="$rcwd"
    done < <(intercom_roster 2>/dev/null || true)
  fi

  local found=0 role id cls tag verdict obase scope_tag
  local -a unrecognized=()
  for dname in "${field_names[@]}"; do
    [[ -n "$dname" ]] || continue
    # ---- P1 常驻↔派生切分：一律经 fleet_name_parse；**禁** `[[ x == "$role-"* ]]` + `${x#"$role"-}` 切片 ----
    p_kind=""; p_role=""; p_task=""; p_scope=""
    pout="$(fleet_name_parse "$dname")"
    if [[ "$pout" == "OK "* ]]; then IFS=',' read -r p_kind p_role p_task p_scope <<< "${pout#OK }"; fi
    scope_tag=""
    [[ -n "$p_scope" ]] && scope_tag=" ·scope=$p_scope"    # D5：只追加字段，既有行格式不动（BR1）
    # herdr：非在线证据类**单列**（下方「终端证据异常」节），此处不重复渲染成残留/进行态
    if [[ "$backend" == "herdr" ]]; then
      case "${hv[$dname]:-absent}" in
        ghost|dead|mismatch|integration-missing|ambiguous) continue ;;
      esac
    fi
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
        printf '  · %s%s%s\n' "$dname" "$tag" "$scope_tag"
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
        printf '  · %s（一次性会话 · 下游卡 %s）%s%s\n' "$dname" "$role" "$tag" "$scope_tag"
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
    echo '== 终端证据异常（herdr 后端：label 命中 ≠ 在线）=='
    printf '%s\n' "${term_abn[@]}"
  fi
  # AC2.2 闭环（B3）：可投递标注 —— **独立节/独立行**，不改任何既有行格式（BR1 md5 仍逐字）
  #   消费者 = close 忙闲闸门 + 本节；映射单源 = term_deliverable（idle/done 可投递，其余/unknown 不可）
  if [[ "$backend" == "herdr" ]]; then
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
      if [[ "$dv" == "online" ]] && term_deliverable "$ds"; then
        dl+=("  · $dn：可投递（agent_status=$ds）")
      elif [[ "$dv" == "online" ]]; then
        dl+=("  · $dn：不可投递（agent_status=$ds；BR7 ⇒ 保守不可投递）")
      else
        dl+=("  · $dn：不可投递（$dv ⇒ 无在线证据）")
      fi
    done
    if (( ${#dl[@]} > 0 )); then
      echo '== 投递判定（BR7：idle/done 可投递；working/blocked/unknown 不可投递）=='
      printf '%s\n' "${dl[@]}"
    fi
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
  # 标题被改写/无名的 pi pane：非静默——显式列出，供人工核对
  #   herdr 后端：本批不列（无标题契约、pane 可无 label 且可属用户自己的 agent；幽灵 pane 已单列）
  local -a orph=()
  local pn2 pt
  if [[ "$backend" == "tmux" ]]; then
    while IFS=$'\t' read -r pn2 pt; do
      [[ -n "$pn2" ]] && orph+=("$pn2($pt)")
    done < <(unattributed_pi_panes)
  fi
  if (( ${#orph[@]} > 0 )); then
    warn "以下 pi pane 标题不符契约且名册无 pane 记录，无法归属会话名：${orph[*]}"
    warn "  （标题可能被外部改写；用 intercom({action:'list'}) 人工核对，或按 pane_id 处理）"
  fi
}

# ---------------------------------------------------------------------------
# 回收已完成会话：闸门（tasks-state 已推进 + 无在跑 turn）+ 落地（pane/tmux 会话/进程）
cmd_close() {
  local force="$1" task="$2" target="${3:-}"
  [[ -n "$target" ]] || die "close 需要目标：角色别名或派生会话名（如 rd-be / rd-be-T1 / qa-T1）"
  # T525 BR1/BR2/BR4：子代理会话显式拒绝 —— 判定**只针对 $target 位置名**（`close --task subagent-x qa`
  # 是合法派生 qa-subagent-x，不得误杀）；锚首 glob（`subagentfoo`/裸 `subagent` 不匹配）；`--force` 不旁路；
  # die 于任何 pane 定位/捕获/kill 之前 ⇒ 父 pane 必存活（父+子共用 tmuxPane 亦然）。
  if [[ "$target" == subagent-* ]]; then
    die "拒绝回收 $target：这是 pi-subagents 子代理会话（subagent-*），其生命周期不归 nao 回收（请用 pi-subagents 的 stop / retention 管理）"
  fi
  local name repo cls bus pane pids st tgt a best="" bestc="" is_resident=1 card_role="" card_path="" cr cp croot k
  local pout="" p_kind="" p_role="" p_task="" p_scope="" parsed=0 core="" kindc="" scope="" base_name=""
  local fallback_repo="" scoped_cands=() r2=""
  intercom_list_json >/dev/null 2>&1 || true   # 预热名册缓存
  fleet_roles_init --cards                     # BR8：parse 的角色事实表（常驻 + 卡 role）

  # ---- P4（BR8）：头部先整体 parse 目标名 ----
  #   命中 ⇒ 直接用 parse 的 (kind,role,task,scope)，**忽略** scope 文件（§5：全名给 scope 即权威）；
  #   不命中（ERR / 未知角色）⇒ 走原五级兼容路径（别名 close arch / close --task T508 qa / 卡集最长前缀…）。
  #   同 core 多个带 scope 会话且无法定 ⇒ die 列候选（禁猜）。
  pout="$(fleet_name_parse "$target")"
  if [[ "$pout" == "OK "* ]]; then
    parsed=1
    IFS=',' read -r p_kind p_role p_task p_scope <<< "${pout#OK }"
    if [[ -n "$task" && -n "$p_task" && "$task" != "$p_task" ]]; then
      die "目标名与 --task 不一致：$target（名字里是 $p_task，--task 是 $task；该怎么办：二选一）"
    fi
    if [[ -n "$p_task" ]]; then task="$p_task"; fi
    if [[ "$p_kind" == "card" ]]; then
      is_resident=0; card_role="$p_role"
      while IFS=$'\t' read -r cr cp croot; do
        [[ "$cr" == "$card_role" ]] || continue
        card_path="$cp"; break
      done < <(card_role_set)
    else
      tgt="$p_role"
    fi
  fi

  # ---- 目标解析：别名/canonical id | 派生会话名 <角色>-<编号>（parse 未命中时才走）----
  # 派生名（如 qa-T508）可直接作目标；也兼容 close --task T508 qa 与 close --task T508 qa-T508。
  # T537：解析顺序 ① ALIAS_ROLE 精确 → ② <别名>-<编号> → ③ 卡集最长前缀 + 任务号 → ④ 卡集裸名精确 → ⑤ die。
  #   ①② 逐字不动；③④ 为新增分支（下游卡一次性会话）；类别由显式布尔 is_resident 决定（BR10，禁用 `-z task` 推断）。
  tgt=""; [[ "$parsed" == "1" ]] && tgt="$p_role"
  if [[ "$parsed" != "1" ]]; then
  if [[ -n "${ALIAS_ROLE[$target]:-}" ]]; then
    tgt="$target"
  elif [[ -n "$task" && "$target" == *-"$task" && -n "${ALIAS_ROLE[${target%-"$task"}]:-}" ]]; then
    tgt="${target%-"$task"}"
  else
    # 未带 --task 的派生名：取最长可解析前缀为角色，余下为任务编号
    for a in "${!ALIAS_ROLE[@]}"; do
      [[ "$target" == "$a"-* ]] || continue
      if [[ -z "$best" || ${#a} -gt ${#best} ]]; then best="$a"; fi
    done
    if [[ -n "$best" ]]; then tgt="$best"; task="${target#"$best"-}"; fi
  fi
  if [[ -z "$tgt" ]]; then
    # ③④ 下游卡（一次性）：最长前缀匹配（纵深防御：卡集前缀嵌套由 check 报 error）
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
      card_role="$bestc"
      card_path="${cset[$bestc]}"
      is_resident=0
      if [[ "$target" != "$bestc" ]]; then
        local tsuff="${target#"$bestc"-}"
        if [[ -n "$task" && "$task" != "$tsuff" ]]; then
          die "目标名后缀与 --task 不一致：$target（后缀 $tsuff，--task $task；该怎么办：二选一，如 close --task $tsuff $bestc）"
        fi
        task="$tsuff"
      fi
    fi
  fi
  fi   # ← 原五级（parse 未命中时）
  if [[ -z "$tgt" && "$is_resident" == "1" ]]; then
    # D4（BR8）：点名「全名」写法 + 本仓 scope 现值（或未设）+ 在场的带 scope 会话（多 scope 候选）
    local cur_scope="(不可用)" scoped_in_field=""
    if cur_scope="$(fleet_scope_of_invocation "$PWD" "")"; then
      [[ -n "$cur_scope" ]] || cur_scope="未设"
    else
      cur_scope="(不可用：.agents/fleet-scope 非法)"
    fi
    scoped_in_field="$(visible_session_names 2>/dev/null | grep -F '@' | tr '\n' ' ' || true)"
    scoped_in_field="${scoped_in_field% }"
    die "未知角色或派生会话名: $target（可用角色: ${ROLE_ORDER[*]}；派生名形如 rd-be-T1 / qa-T1；**全名**形如 rd-be-T1@todo 或 rd-be@todo（末位 @<scope>，scope 空则不出现）；本仓 scope 现值：$cur_scope；在场带 scope 会话：${scoped_in_field:-无}；亦可用 close --task <编号> <角色>；下游卡角色需在本仓锚下存在 .agents/prompts/<role>.md）"
  fi
  # ---- B2（BR8）：名字重建走 builder；scope 来源分歧（§5）----
  #   core = <role>[-<task>]；kind 只供 builder 自证（语法冻结，名字不编码 kind）
  if [[ "$is_resident" == "1" ]]; then
    resolve_role "$tgt"
    core="$(fleet_core_build "$NAME" "$task")"
    kindc="resident"; [[ -n "$task" ]] && kindc="derived"
    fallback_repo="${ROLE_WS[$NAME]:-$PWD}"
  else
    core="$(fleet_core_build "$card_role" "$task")"
    kindc="card"
    fallback_repo="${card_path%/.agents/prompts/*}"
    [[ -n "$fallback_repo" ]] || fallback_repo="$PWD"
  fi
  if [[ -n "$p_scope" ]]; then
    # ① 全名给了 scope ⇒ 只认这一个名字（**忽略** scope 文件；同 core 多 scope 时由用户显式定）
    name="$(fleet_name_build "$kindc" "$core" "$p_scope")"
    repo="$(intercom_cwd_for "$name")"             # 名册 cwd 优先（跨仓会话真实仓）
    [[ -n "$repo" ]] || repo="$fallback_repo"
    r2="$(intercom_cwd_for "$name" "$repo")"       # P8：按目标仓复核（同名多仓时不取首命中）
    [[ -n "$r2" ]] && repo="$r2"
  else
    # ② 裸名/派生名：先按**无 scope 精确名**定位目标仓（既有跨仓行为逐字保留）
    base_name="$(fleet_name_build "$kindc" "$core" "")"
    repo="$(intercom_cwd_for "$base_name")"
    [[ -n "$repo" ]] || repo="$fallback_repo"
    mapfile -t scoped_cands < <(fleet_scoped_candidates "$core")
    if (( ${#scoped_cands[@]} > 1 )); then
      die "close 目标歧义：$core 的带 scope 会话有多个：${scoped_cands[*]}（该怎么办：用全名 <core>@<scope> 指定，如 close ${scoped_cands[0]}）"
    elif (( ${#scoped_cands[@]} == 1 )); then
      # 唯一小数 ⇒ 采用它的 scope（等价于显式全名；跨仓 close 可用）
      pout="$(fleet_name_parse "${scoped_cands[0]}")"
      IFS=',' read -r p_kind p_role p_task scope <<< "${pout#OK }"
      name="$(fleet_name_build "$kindc" "$core" "$scope")"
      r2="$(intercom_cwd_for "$name" "$repo")"
      [[ -n "$r2" ]] && repo="$r2"
    else
      # ③ 否则 = 目标仓的 invocation scope（裸别名 ⇒ 调用者所在仓；文件不存在 ⇒ 空 ⇒ 逐字同旧名）
      if ! scope="$(fleet_scope_of_invocation "$repo" "$CLI_SCOPE")"; then
        die "close 中止：无法确定 <$repo> 的 scope（该怎么办：修或删 <目标仓>/.agents/fleet-scope，或用全名 <core>@<scope> 指定）"
      fi
      name="$(fleet_name_build "$kindc" "$core" "$scope")"
      if [[ -n "$scope" ]]; then
        r2="$(intercom_cwd_for "$name" "$repo")"   # P8：带 scope 时按目标仓复核名册 cwd
        [[ -n "$r2" ]] && repo="$r2"
      fi
    fi
  fi

  if [[ "$is_resident" != "1" ]]; then
    # BR5/BR10：一次性（下游卡）会话 —— 不弹常驻警告、不提示 ensure --force 重开；AC4③B 固定前缀在 stderr
    warn "一次性会话 $name（下游卡）$card_path：回收后不重开（如需重开：ensure --card <卡>）"
    if [[ -n "$task" ]]; then
      # D8：tasks-state active 闸门对卡会话**跳过**（只 log）；在跑 turn 闸门**不放宽**（下面依然生效）
      cls="$(task_state_class "$task")"
      case "$cls" in
        active)    log "跳过 tasks-state active 闸门（下游卡一次性会话）：$task（产物以回执/报告为准）" ;;
        absent)    log "tasks-state 全文无 $task 记录（下游卡一次性会话，不阻塞回收）" ;;
        mentioned) log "tasks-state 仅散文提及 $task（下游卡一次性会话，不阻塞回收）" ;;
        nofile)    log "未启用 $TASKS_STATE（跳过状态闸门）" ;;
      esac
    fi
  elif [[ -z "$task" ]]; then
    warn "常驻会话 $name：任务闭环后应先 close 该角色再 ensure 重开（pane 仍在场时 ensure --force 会 fail loud）；仅在本批不再需要该角色时才回收"
  else
    # 闸门①：tasks-state 未推进 → 拒绝（验收未过需原会话返工，回收会丢上下文）
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

  # ---- 句柄层（B3）：tmux / herdr 双实现（定位 / self 判据 / liveness / 忙闲 / 回收句柄）----
  #   共用闸门层（tasks-state / subagent 拒收 / 目标解析 / --force）已在上方，**不动**。
  term_reclaim "$name" "$repo" "$force" "$core" "$scope" "$tgt"
  return $?
}

# ---------------------------------------------------------------------------
# 拆场入口（B3 · 双实现）：tmux = 终结实验场 server（-S 显式 socket）；herdr = session stop+delete。
#   后端差异在门面后（_term_tmux_cleanup / _term_herdr_cleanup）；显式目标守卫在入口（rc=2）。
cmd_cleanup() {
  term_cleanup "${CLEANUP_SOCK:-}" "${SESSION_ARG:-}"
}

# ---------------------------------------------------------------------------
cmd_ensure() {
  local force="$1" model="$2" task="$3"
  local i spec role repo key seen k card_arg card_as disp role_id scope core kind vrd
  local chk_core chk_full chk_p maxs chk_role chk_added
  local -a cg_done=() t_names=() t_repos=() t_cards=() t_roles=() t_prompts=() t_scopes=() t_kinds=()
  # BR8：parse 的角色事实表（常驻 id）。ensure 不读卡集（不为判重引入额外 glob 与 CARD_SET_MAX 告警）
  fleet_roles_init
  [[ ${#TARGETS[@]} -gt 0 ]] || die "ensure 需要至少一个角色，如: nao-fleet.sh ensure arch rd-fe rd-infra"
  # ==== 相位 1：全量解析 + 校验（BR11 两相执行）====
  #   卡、role、BR9、--as 全过才进相位 2；任一项失败都在**建 pane 之前** die ⇒ BR6「零副作用」可达
  for i in "${!TARGETS[@]}"; do
    spec="${TARGETS[$i]}"; card_arg="${TARGET_CARD[$i]:-}"; card_as="${TARGET_AS[$i]:-}"
    role=""; repo=""
    if [[ "$spec" == *"@"* ]]; then
      role="${spec%%@*}"; repo="${spec#*@}"
    else
      role="$spec"
    fi
    if [[ -n "$card_arg" ]]; then
      # 下游卡目标：目标 positional 即卡路径（BR11 目标级绑定）
      resolve_card "$role" "$repo"
      if [[ -n "$card_as" ]]; then
        local why
        # P10（BR8）：`--as` **只给 core**（名字 = core[@scope]）—— scope 只能由 builder 追加，
        #   来源是 `--scope` 或 <目标仓>/.agents/fleet-scope。含 `@` 即拒（否则两处来源不一，名字无定义）。
        if [[ "$card_as" == *"@"* ]]; then
          die "--as 不可用：$card_as 含 @（--as 只给 core；scope 只能由 fleet 追加 —— 用 --scope <slug> 或写 <目标仓>/.agents/fleet-scope，名字形如 <role>[-<task>][@<scope>]）"
        fi
        # 命名契约先判（字符集/保留前缀/撞常驻），再判 D9 前缀约束 —— 让「撞常驻 id」这类
        #   更根本的问题先点名，避免被前缀提示掩盖。
        if ! why="$(card_name_problem "$card_as")"; then
          die "--as 不可用：$card_as —— $why（该怎么办：换一个不以常驻 id/别名开头、符合 ^[a-z0-9][a-z0-9_-]*$ 且 core ≤ 32 字符的名字）"
        fi
        # D9（PM 拍板）：--as 必须等于卡 role 或以 `<卡 role>-` 为前缀 —— 否则会起出 status/close
        #   解析不到的会话（等于把「起得来但管不到」合法化）；warn 不够，必须 die。
        if [[ "$card_as" != "$CARD_ROLE" && "$card_as" != "$CARD_ROLE"-* ]]; then
          die "--as 不可用：$card_as 不以卡 role（$CARD_ROLE）为前缀 —— 改名不得脱离卡 role 前缀（fleet 按前缀识别身份），用 <role>-<suffix>（如 $CARD_ROLE-notes）"
        fi
        disp="$card_as"
      else
        disp="$CARD_ROLE"
      fi
      # B1（BR8）：scope 在**相位 1** 一次算定（读取对象 = 卡的仓 CARD_REPO，不是调用者 cwd）；
      #   相位 2 禁重算（重算会让「--scope 与文件并存」的语义随执行时序漂移）
      if ! scope="$(fleet_scope_of_invocation "$CARD_REPO" "$CLI_SCOPE")"; then
        die "ensure 中止：无法确定 <$CARD_REPO> 的 scope（该怎么办：修或删 <目标仓>/.agents/fleet-scope，或用 --scope <slug> 显式指定）"
      fi
      t_names+=("$disp"); t_repos+=("$CARD_REPO"); t_cards+=("$CARD_PATH"); t_roles+=("${CARD_ROLE:-}")
      t_scopes+=("$scope"); t_kinds+=("card")
      if [[ -n "$scope" ]] && $VERBOSE; then
        log "scope=$scope @ $CARD_REPO（来源：$([ -n "$CLI_SCOPE" ] && printf -- '--scope' || printf '.agents/fleet-scope')）"
      fi
      # #75：card 目标只走 ④ 完整路径；⑥ 留空（两条通道互斥，override 不得被当相对名）
      t_prompts+=("")
    else
      [[ -z "$card_as" ]] || die "--as 只能用于同一目标的 --card 之后（如 ensure --card <卡> --as <会话名>）"
      resolve_role "$role"
      [[ -n "$repo" ]] || repo="${ROLE_WS[$NAME]:-$PWD}"
      if ! scope="$(fleet_scope_of_invocation "$repo" "$CLI_SCOPE")"; then
        die "ensure 中止：无法确定 <$repo> 的 scope（该怎么办：修或删 <目标仓>/.agents/fleet-scope，或用 --scope <slug> 显式指定）"
      fi
      t_names+=("$NAME"); t_repos+=("$repo"); t_cards+=(""); t_roles+=("$NAME")
      t_scopes+=("$scope"); t_kinds+=("resident")
      if [[ -n "$scope" ]] && $VERBOSE; then
        log "scope=$scope @ $repo（来源：$([ -n "$CLI_SCOPE" ] && printf -- '--scope' || printf '.agents/fleet-scope')）"
      fi
      # #75：常驻卡名**当场**取证（resolve_role 每目标覆写全局 PROMPT ⇒ 只有此刻的值属于本目标）
      t_prompts+=("$PROMPT")
    fi
    # ---- P2-1（命名预算自洽）：builder 造得出 ≠ parse 认得回 ----
    #   管理面（status/close）**全靠 parse**：造出 parse 不认的名字 ⇒ 会话拉得起来但整条从 status
    #   消失（连「角色未识别」节都不进）⇒ 旧脚本可见、新脚本消失 = 回归。故相位 1 就用 parse 复核
    #   builder 输出，非 OK 即 die（**建 pane 之前** ⇒ BR6 零副作用）。builder 本身不 die：close/status
    #   也调它，抛错会把「读到坏名字」变成「命令崩」。
    kind="${t_kinds[$i]}"
    if [[ "$kind" == "resident" && -n "$task" ]]; then kind="derived"; fi
    chk_core="$(fleet_core_build "${t_names[$i]}" "$task")"
    chk_full="$(fleet_name_build "$kind" "$chk_core" "${t_scopes[$i]}")"
    # 本目标的 role 可能不在全局事实表里（ensure 不读卡集：为判重引入 glob/IO 属 P3-1 观察项，本批不动）
    #   ⇒ 只为**这次复核**临时登记再撤销，绝不改变 ensure 的判重语义（running_verdict 看到的表不变）。
    chk_role="${t_roles[$i]:-}"
    chk_added=0
    if [[ -n "$chk_role" && -z "${FLEET_ROLE_KIND[$chk_role]:-}" ]]; then
      FLEET_ROLE_KIND["$chk_role"]="card"; chk_added=1
    fi
    chk_p="$(fleet_name_parse "$chk_full")"
    (( chk_added )) && unset 'FLEET_ROLE_KIND[$chk_role]'
    if [[ "$chk_p" != "OK "* ]]; then
      # P3-b：按**原因**分支（别把「卡 core 超 32」说成「总长 > 48」——35 并不 > 48，
      #   且那种情形缩 scope 是死路：scope 只占 '@' 之后那段，救不回 core）。
      if [[ "$kind" == "card" ]] && (( ${#chk_core} > 32 )); then
        die "ensure 中止：卡会话 core 超上限 —— core「$chk_core」共 ${#chk_core} 字符 > 32（卡 core 上限 32；scope ≤16；总长上限 48）。该怎么办：缩短 --task 编号（当前 ${#task} 字符）或改用更短的卡 role（卡 role 本身 ≤32 由卡校验兜）"
      fi
      maxs=$(( 48 - ${#chk_core} - 1 )); (( maxs < 0 )) && maxs=0
      die "ensure 中止：目标名超预算 —— 「$chk_full」共 ${#chk_full} 字符 > 48。名字 = <core>[@<scope>]：core ≤48（卡 core 另限 ≤32）、scope ≤16、**总长 ≤48**（含 '@'）。该怎么办：缩短 --task 编号（当前 core ${#chk_core} 字符）或缩短 scope（当前 ${#scope} 字符，core 不变时最多 $maxs 字符）"
    fi
  done
  # ==== 相位 2：拉起（宿主窗口解析、判重、codegraph 状态、spawn 逐目标不变）====
  # T517：入口一次性解析派生宿主窗口（**仅 tmux 后端**；herdr 放置由 term_spawn 自行完成，禁裸 tmux 调用）
  HOST_WINDOW=""
  if [[ "$NAO_TERMINAL" == "tmux" && -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then resolve_host_window; fi
  for i in "${!t_names[@]}"; do
    repo="${t_repos[$i]}"
    # ---- BR8：名字的**唯一**构造点（builder）。core = <role>[-<task>]，scope 已在相位 1 算定 ----
    #   任务派生 = 独立 intercom 身份（并行隔离，避免同名冲突）；scope 空 ⇒ 与改动前逐字相同
    kind="${t_kinds[$i]}"
    if [[ "$kind" == "resident" && -n "$task" ]]; then kind="derived"; fi
    core="$(fleet_core_build "${t_names[$i]}" "$task")"
    disp="$(fleet_name_build "$kind" "$core" "${t_scopes[$i]}")"
    # CodeGraph 索引健康（同 repo 只查一次，不阻塞拉起）
    key="$repo"; seen=0
    for k in "${cg_done[@]:-}"; do [[ "$k" == "$key" ]] && seen=1; done
    if (( ! seen )); then codegraph_state "$repo" 1 "$(basename "$repo")"; cg_done+=("$key"); fi
    # ---- P11（BR8）：判重三态 same|conflict|absent（旧二态对「同 core 不同 scope/仓」静默起第二个）----
    if [[ "$force" != "true" ]]; then
      vrd="$(running_verdict "$disp" "$repo")"
      case "$vrd" in
        same)
          if [[ "$NAO_TERMINAL" == "herdr" ]]; then
            warn "$disp 已在运行（pane label + 结构化事实命中），跳过；确需重开请加 --force"
          else
            warn "$disp 已在运行（终端标题/名册命中），跳过；确需重开请加 --force"
          fi
          SPAWN_SKIP=$((SPAWN_SKIP + 1))   # T539/BR3：跳过也计入摘要（且不加成功行）
          continue
          ;;
        conflict:*)
          die "$disp 与在场会话同 core 但 scope/仓不同：${vrd#conflict:}（该怎么办：给每个仓设各自的 <目标仓>/.agents/fleet-scope，或用 --scope <slug> 指定；两仓并发**必须**设 scope，否则同名会话互相顶掉）"
          ;;
      esac
    fi
    # #75：卡按目标下发（④ 完整路径 / ⑥ 相对名；两条通道互不混用），不再依赖全局 PROMPT
    if [[ -n "${t_cards[$i]}" ]]; then
      spawn_one "$disp" "$repo" "$model" "${t_cards[$i]}" "${t_roles[$i]:-}" "" "$force"
    else
      spawn_one "$disp" "$repo" "$model" "" "${t_roles[$i]:-}" "${t_prompts[$i]:-}" "$force"
    fi
  done
  # T536/BR3/AC4 + T539/BR3：**恰一行**摘要，三类计数（成功/跳过/失败）；三类全 0 不打印（与现状一致）。
  #   前缀「已拉起 N 个会话」保留（既有断言与用户习惯依赖），计数细化追加在括号内（BR6 旧→新对照见 T539 报告）。
  if (( SPAWN_OK + SPAWN_SKIP + SPAWN_FAIL > 0 )); then
    log "已拉起 ${SPAWN_OK} 个会话（成功 ${SPAWN_OK} / 跳过 ${SPAWN_SKIP} / 失败 ${SPAWN_FAIL}）；就绪后在线状态用 nao-fleet.sh status 查看"
  fi
}

# ---------------------------------------------------------------------------
usage() {
  awk '
    /^# =+$/ { c++; if (c==2) exit; next }
    c==1 && /^#/ { sub(/^# ?/,""); print }
  ' "$0"
  exit 0
}

# ---- 入口 ----
CMD=""; FORCE=false; STRICT=false; MODEL=""; TASK=""; CLEANUP_SOCK=""; SESSION_ARG=""; TARGETS=()
# BR8：本次 ensure 的显式 scope（覆盖 <目标仓>/.agents/fleet-scope；给参即静默胜出，来源仅 -v 打印）
CLI_SCOPE=""; SCOPE_WHY=""
# T537：目标级修饰符（--card / --as）的绑定状态 —— 只作用于**其后第一个 positional**（BR11）
TARGET_CARD=(); TARGET_AS=(); PEND_CARD=false; PEND_AS=""; LAST_CARD_IDX=-1
_need_ensure() { [[ "$CMD" == "ensure" ]] || die "$1 仅用于 ensure 子命令：nao-fleet.sh ensure --card <卡路径>[@<repo>] [--task <编号>] [--as <会话名>]"; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    check)  CMD="check";  shift ;;
    status) CMD="status"; shift ;;
    close)  CMD="close";  shift ;;
    cleanup) CMD="cleanup"; shift ;;
    session-start) CMD="session-start"; shift ;;
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
    --force)  FORCE=true;  shift ;;
    --task)   TASK="${2:-}"; [[ -n "$TASK" ]] || die "--task 需要任务编号（如 T1）"; [[ "$TASK" =~ ^[A-Za-z0-9_-]+$ ]] || die "--task 非法: $TASK（仅字母/数字/-/_）"; shift 2 ;;
    # BR8 · --scope：只用于 ensure（照 --card/--as 先例）。给参但空 ⇒ die（照 --task 先例），
    #   非法 ⇒ die + 回显规则（§5 全部 fail loud，禁静默回落文件）。
    --scope)
      _need_ensure "--scope"
      CLI_SCOPE="${2:-}"
      [[ -n "$CLI_SCOPE" ]] || die "--scope 需要 scope 值（给参但空 ⇒ 拒绝）；不用 scope 时不要写 --scope"
      SCOPE_WHY="$(fleet_scope_problem "$CLI_SCOPE")" \
        || die "--scope 不可用：$CLI_SCOPE —— $SCOPE_WHY"
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
if $PEND_CARD; then die "--card 后缺少卡路径参数（该怎么办：ensure --card .agents/prompts/<name>.md）"; fi
if [[ -n "$PEND_AS" ]]; then die "--as 缺少同目标的 --card 与卡路径（该怎么办：ensure --card <卡路径> --as <会话名>）"; fi

# 后端取值校验（fail loud，禁静默回落 tmux）
term_backend >/dev/null || exit 2

# session-start：--session 必填（在一切副作用之前；herdr 实现内部再校 default/字符集/socket 前缀）
if [[ "$CMD" == "session-start" && -z "$SESSION_ARG" ]]; then
  die "session-start 需要 --session <名>（如 nao-fleet.sh session-start --session nao-fleet）"
fi

# 唯一运行前提闸门（BR1/BR3）：先于 load_manifest 与任何副作用；不满足 ⇒ exit 3（命令未执行）。
# cleanup 豁免：其正常场景就是实验场拆场（tmux: env -u TMUX ... -S <socket> / herdr: --session <名>）。
# herdr 后端（#96 二期 B1–B3）：ensure/status/close 走 term_require（pane + protocol 闸门）；
#   闸门在此之前 ⇒ 零后端调用（用例以 PATH 桩 0 命中断言）。
# session-start 自校验（herdr = 起 server，无需已在 pane 内；tmux = 幂等无操作）
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

# -S 仅 cleanup 消费：其他子命令带上 -S 视为用法错误（避免静默吞参）
if [[ -n "${CLEANUP_SOCK:-}" && "$CMD" != "cleanup" ]]; then
  die "-S 仅用于 cleanup 子命令（实验场安全清理）：nao-fleet.sh cleanup -S <socket>"
fi
# B3 · 拆场的显式目标按后端分派（用法守卫 rc=2；在一切后端调用之前）
if [[ "$CMD" == "cleanup" ]]; then
  if [[ "$(term_backend)" == "herdr" ]]; then
    if [[ -n "${CLEANUP_SOCK:-}" ]]; then
      printf '[fleet] herdr 后端的 cleanup 用 --session <名>（-S 仅用于 tmux 实验场 socket）\n' >&2
      exit 2
    fi
    if [[ -z "${SESSION_ARG:-}" ]]; then
      printf '[fleet] cleanup 拒绝：herdr 后端须显式 --session <名>（default 是用户会话，禁止；如 --session nao-fleet）\n' >&2
      exit 2
    fi
  elif [[ -n "${SESSION_ARG:-}" ]]; then
    printf '[fleet] --session 仅用于 herdr 后端（tmux cleanup 用 -S <隔离socket>）\n' >&2
    exit 2
  fi
fi

case "$CMD" in
  check)
    # 默认摘要 2 行（派发前自检只需 exit code + 计数 + codegraph 态；完整报告 30+ 行不进 PM 上下文）；-v 或失败时展开
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
      WARNS="$(grep '^  !' "$REPFILE" | grep -vc '^  ! codegraph ' || true)"
      ROLES_N="$(grep -oE '解析成功，[0-9]+ 个角色' "$REPFILE" | grep -oE '[0-9]+' | head -1 || true)"
      FILES_N="$(grep -oE '[0-9]+ 个文本文件全 LF' "$REPFILE" | grep -oE '^[0-9]+' | head -1 || true)"
      if (( WARNS > 0 )); then
        printf 'check: OK · roles=%s · files=%s · layout=%s · warn=%d（-v 看详情）\n' \
          "${ROLES_N:-?}" "${FILES_N:-?}" "$TMUX_LAYOUT" "$WARNS"
      else
        printf 'check: OK · roles=%s · files=%s · layout=%s\n' \
          "${ROLES_N:-?}" "${FILES_N:-?}" "$TMUX_LAYOUT"
      fi
      # CodeGraph 四态行常驻可见（BR9 不静默）：摘要模式下也从报告里抽这一行原样回显，
      # 保持「默认只出四态中的一行」（PRD AC1）且不额外 fork（full=0 已在报告期算完）。
      grep -m1 -E '^  . codegraph ' "$REPFILE" || true
      # B1（BR1 六条机械保证之「check 打印生效后端」）：**仅 herdr 模式加行**；tmux 路径零新增输出
      if [[ "$NAO_TERMINAL" == "herdr" ]]; then
        echo '  · 生效后端 NAO_TERMINAL=herdr（#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）'
      fi
    else
      cat "$REPFILE"
    fi
    rm -f "$REPFILE"
    exit $CHECK_RC
    ;;
  status) cmd_status ;;
  close)  cmd_close "$FORCE" "$TASK" "${TARGETS[0]:-}" ;;
  cleanup) cmd_cleanup ;;
  session-start) term_session_start "$SESSION_ARG" ;;
  ensure) cmd_ensure "$FORCE" "$MODEL" "$TASK" ;;
  *) usage ;;
esac