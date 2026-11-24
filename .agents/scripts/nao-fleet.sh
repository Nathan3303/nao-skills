#!/usr/bin/env bash
# =============================================================================
# nao-fleet.sh — 按角色一键拉起 pi 会话窗口（nao 团队工具箱）
#
# 运行前提（端前提 = herdr pane 内 + pi ≥ MIN_PI_VERSION；ADR 2026-11-22-herdr-only
#   supersede 2026-10-27-strict-tmux-pi：**herdr 是唯一后端**，旧 tmux 后端与 -S 调用面已删除，见 §退出码）
#   **唯一后端 = herdr**：`NAO_TERMINAL` 只用于**拒绝**旧值（非空且非 herdr ⇒ stderr 1 行 + exit 2，命令未执行）；
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
#   nao-fleet.sh status                           角色会话在线状态（pane label + agent 状态
#                                                 （结构化事实，权威源 pane list/agent list）；非在线证据单列）
#   nao-fleet.sh ensure <别名>[@<repo>] [更多...]  拉起角色窗口（默认工作区=roles.yaml workspace）
#                                                 `@<repo>` = 目标仓选择符（`@main` 走 manifest、`@<路径>` 直指），不入会话名
#   nao-fleet.sh ensure -m <model> <别名>...       显式指定模型（须命中白名单）
#   nao-fleet.sh ensure --task <编号> <别名>[@<repo>]   任务派生会话：名字 = `<别名>(<编号>)`；同 workspace 内该
#                                                 role 已有会话 ⇒ 自动取槽位 `<别名><N>(<编号>)`（N=2..9，段满 fail loud）
#   nao-fleet.sh ensure --card <卡路径> [--as <会话名>] [--task <编号>]
#                                                 下游仓自定义角色会话（一次性）：卡须为 <repo>/.agents/prompts/<file>.md
#                                                 （卡 role 与常驻 id/别名必须前缀不相交；不入 roles.yaml、不算常驻；
#                                                  --as 只给常驻名/旧形后缀：= 卡 role、`<role><N>`（N=2..9）或
#                                                  `<role>-<后缀>`；含 `(` 即拒 —— 派生 task 只走 --task）
#   会话名契约（v2 · ADR 2026-11-20）：`<role>[<N>](<task>)` —— 常驻 `<role>[<N>]`、派生 `<role>[<N>](<task>)`；
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
#                                                 （目标解析为 pm 时，**就绪后**投递一条固定用户消息：机制包版本自检，
#                                                  仅提示不自动升级；关闭用 NAO_UPDATE_ON_ENSURE=0）
#   nao-fleet.sh close <别名|派生会话名|legacy 全名> [--task <编号>] [--force]
#                                                 回收已完成会话（派生名如 rd-be(T1)、带槽位 rd-be2(T1)）；
#                                                 裸别名 = 本仓锚内同 core（v2 各槽位 → legacy 旧形候选
#                                                 → 全 session 唯一同 core → 否则拒绝列候选）；带 `@` 的 legacy
#                                                 （跨仓定位；定位失败/名册报在线但无句柄 ⇒ 非 0 + 诊断）
#                                                 （闸门：在跑 turn / tasks-state 未推进 → 拒绝，--force 跳过；
#                                                  常驻缺席而其派生在场 ⇒ 目标歧义拒绝，T516 AC3）
#                                                 herdr 后端：忙闲闸门 = agent_status（BR7）+ 名册第二信号（OR）；
#                                                 unknown / 无 agent 条目 / 集成缺失 / 进程不可判 ⇒ 拒（fail-closed）
#   nao-fleet.sh cleanup --session <名>           （herdr 后端）拆专用 session：session stop + delete，
#                                                 判 **effect** 不看 rc（stop 非幂等）；--session 必填且 ≠default（BR9）
#   nao-fleet.sh cleanup -S <socket>              **已随 tmux 后端移除**（ADR 2026-11-22-herdr-only）：
#                                                 任一子命令带 -S ⇒ exit 2 + 单行指路 `--session <名>`（fail loud，不静默吞参）
#
# 角色别名 → 角色卡：见 .agents/roles.yaml（单一事实来源）
#   当前：pm / arch-designer(arch) / uiux-designer(uiux, ui-designer) / rd-fe / rd-be / qa / rd-infra(infra)
#
# 环境变量
#   NAO_SKILLS=<dir>                          nao 机制包根目录（默认 <脚本>/../..；项目内 shim 会显式指向包根）
#   NAO_MODEL_WHITELIST=<glob,...>            -m 白名单（默认空=不校验，支持 glob）
#   NAO_CLOSE_BUSY_PATTERN=<ERE>             close 的在跑 turn 判定正则（默认内置 pi 状态行标记）
#   NAO_TERMINAL=<值>                        唯一后端 = herdr（未设/空串 = herdr）；给**其他任何值**（含已移除的 tmux）
#                                            ⇒ stderr 1 行 + exit 2（命令未执行）。status/ensure/close/cleanup 走门面，
#                                            ensure 须先 `session-start` 起专用 session 并在其 pane 内运行
#   NAO_HERDR_READY_TIMEOUT_MS=<ms>          herdr 就绪门 wall-clock 上限（默认 5000；只对 herdr 后端生效）
#   NAO_TERM_MIN_COLS=<n>                     herdr 放置后空间判据最小列宽（默认 60；不足只 warn 不中断）
#   NAO_TERM_MIN_ROWS=<n>                     herdr 放置后空间判据最小行数（默认 10；0 尺寸 pane ⇒ 计 SPAWN_FAIL）
#   NAO_TASKS_STATE=<path>                   任务状态文件（默认 docs/tasks-state.md，供残留检测/回收闸门）
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
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${NAO_SKILLS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROMPTS_DIR="$SKILLS_DIR/.agents/prompts"
COMMON_DIR="$SKILLS_DIR/.agents/common"
SKILLS_SUB="$SKILLS_DIR/.agents/skills"
# 本脚本自身路径（#124）：端前提 warn 需从**唯一赋值点**解析默认后端，故要读回自己的源码。
#   不许在别处重述默认值字面量（tests/t4 的 `grep -cE '^NAO_TERMINAL='` 静态 lint 亦依赖唯一性）。
SELF_SH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"

# pi 运行前提（ADR 2026-10-27-strict-tmux-pi）的**单源**：check 文案与比较判据全部由它派生，
#   脚本内禁再出现该版本的字面量（tests/t4 用例 06 静态兜住）。改阈值只改这一行。
MIN_PI_VERSION="1.4.0"
# 派生比较阈值（major / minor）：判据里不得重敲数字；patch 不参与比较（准入只认版本线）
MIN_PI_MAJOR="${MIN_PI_VERSION%%.*}"
MIN_PI_MINOR="${MIN_PI_VERSION#*.}"
MIN_PI_MINOR="${MIN_PI_MINOR%%.*}"

# ---- 终端后端（#96 二期 B1 · PRD 附二「门面 + 双实现并存」）----
# 默认值**唯一赋值点**：全脚本 `grep -cE '^NAO_TERMINAL='` 必须恰 1 处（tests/t4 静态 lint 断言）。
# 三期 P2（2026-11-11）：**herdr 转默认**只改这一行（B1 立的 lint 就是为这一步准备的）。
#   `:-` 语义 ⇒ 未设与空串都落 herdr；本版起 herdr 是唯一后端（旧回退面已删，其他值 ⇒ 守卫 exit 2）。
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
# T536：本轮真正创建成功的 pane 数（>0 ⇒ ensure 收尾打印**恰一行**就绪提示；跳过/失败分支恒 0，BR3/AC4）
# T539：三态计数（成功 / 跳过 / 失败）—— 每个 ensure 目标恰落一类，合计 = 目标数（BR3 计数守恒）
SPAWN_OK=0
SPAWN_SKIP=0
SPAWN_FAIL=0
# T539/BR2：term_spawn 的**显式**结果契约（返回值；调用方禁用「没打印就是成功」这类隐式约定）：
#   0 = 成功（pane 已创建）· 2 = 跳过 · 3 = 失败（含就绪超时 / 0 尺寸 pane）
SPAWN_RC_OK=0
SPAWN_RC_SKIP=2
SPAWN_RC_FAIL=3
# check 输出契约：默认摘要 2–3 行（摘要行 + codegraph 状态行，herdr 后端另加「生效后端」行；四态之一），
#   -v 展开完整报告（六态全展开）；失败始终展开
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
# 开关（R6）：NAO_UPDATE_ON_ENSURE=0/false ⇒ 不投递（命令行与本缺陷前逐字等价；T548 起自检不再进 argv）。
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
# 唯一后端（ADR 2026-11-22-herdr-only · supersede 2026-10-27-strict-tmux-pi）
#   后端身份 = **常量而非分支**：herdr 是唯一后端。`NAO_TERMINAL` 只用于**拒绝**旧值（fail loud，不静默降级）：
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

# 快照构建分派（缓存/落盘逻辑在 term_snapshot，实现分派在此）
_term_backend_snapshot() { if _term_app_backend; then _term_app_snapshot; else _term_herdr_snapshot; fi; }

# ---- 1/4 前提闸门 ----
term_require() { if _term_app_backend; then _term_app_require; else _term_herdr_require; fi; }

# ensure 前的后端前提（app = AC3b「窗口不在跑 ⇒ exit 3」；herdr 无此概念 ⇒ 无操作）
term_spawn_preflight() { if _term_app_backend; then _term_app_spawn_preflight; else return 0; fi; }

# ---- 2/4 快照（每命令 ≤1 次 pane list / agent list；落临时文件，子 shell 复用同一份）----
# 12 列（TAB）：name pane_id terminal_id cwd foreground_cwd fg_process
#               agent_status state_change_seq agent_session argv_name hook_authority workspace_id
#   pane list + agent list 按 pane_id join；只对带 label 的 pane 各取一次 process-info
term_snapshot() {
  local f="${_TERM_SNAP_FILE:-${_TERM_SNAP_PATH:-${TMPDIR:-/tmp}/nao-fleet-term-snap.$$}}"
  # 判据用「文件存在」而非「非空」：**无 label 会话时快照合法为空** —— 用 -s 会每调用重建
  #   （QA P3-1 实测 status 退化成 pane list ×7 / agent list ×7）。
  if [[ -e "$f" ]]; then _TERM_SNAP_FILE="$f"; cat "$f"; return 0; fi
  # 上一轮被 SIGKILL/timeout 杀掉时会留下同名快照（EXIT trap 不执行）⇒ 只在**重建**时清 >2h 的陈迹
  find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nao-fleet-term-snap.*' -mmin +120 -delete 2>/dev/null || true
  if ! _term_backend_snapshot > "$f"; then
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
term_spawn() {  # <name> <inner> <repo> [force] [label] [group]
  if _term_app_backend; then _term_app_spawn "${1-}" "${2-}" "${3-}" "${4:-false}" "${5-}" "${6-}"
  else _term_herdr_spawn "${1-}" "${2-}" "${3-}" "${4:-false}" "${5-}" "${6-}"; fi
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

# ---- 放置快照门面（ensure 相位 1a）：herdr = workspace/pane list；app = doc.get + hc ls ----
term_place_prime() {  # → 0 已建快照 / 1 不可用
  if _term_app_backend; then _term_app_place_prime; else _term_herdr_place_prime; fi
}
term_place_reset() { _TERM_PLACE_CACHE=0; _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=(); _TERM_APP_GHOST_TABS=(); }

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
  local label cwd fgcwd astat tid fg pname avline avname st wsid nlabel ntid ncwd nfgcwd nwsid
  while IFS= read -r obj; do
    label="$(_term_json_str "$obj" label)"
    [[ -n "$label" ]] || continue
    _term_tsv_norm "$label"; nlabel="$_TSV_NORM"
    pid="$(_term_json_str "$obj" pane_id)"
    wsid="$(_term_json_str "$obj" workspace_id)"
    tid="$(_term_json_str "$obj" terminal_id)"
    cwd="$(_term_json_str "$obj" cwd)"
    fgcwd="$(_term_json_str "$obj" foreground_cwd)"
    astat="$(_term_json_str "$obj" agent_status)"
    _term_tsv_norm "$tid";   ntid="$_TSV_NORM"
    _term_tsv_norm "$cwd";   ncwd="$_TSV_NORM"
    _term_tsv_norm "$fgcwd"; nfgcwd="$_TSV_NORM"
    _term_tsv_norm "$wsid";  nwsid="$_TSV_NORM"
    fg=""; avname=""
    while IFS=$'\t' read -r pname avline; do
      [[ -n "$pname" ]] || continue
      [[ -n "$fg" ]] || fg="$pname"
      if [[ "$pname" == "pi" ]]; then
        fg="pi"; avname="$(_term_argv_name "$avline")"; break
      fi
    done < <(_term_herdr_argv "$pid")
    st="${ag_stat[$pid]:-}"; [[ -n "$st" ]] || st="${astat:--}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$nlabel" "$pid" "$ntid" "$ncwd" "$nfgcwd" "${fg:--}" \
      "$st" "${ag_seq[$pid]:--}" "${ag_sess[$pid]:--}" "${avname:--}" "${ag_hook[$pid]:-0}" "$nwsid"
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
    IFS=$'\t' read -r _ _ _ _ _ fg astat seq sess avname hook _ws <<< "$line"
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
  log "已回收 $name（herdr pane $pane）@ $pcwd"
  return 0
}

# 单行快照行 → verdict（与 term_liveness 同一阶梯，供「同名多 pane」逐行判定）
_term_herdr_row_verdict() {  # <name> <row>
  local name="${1-}" line="${2-}" fg="" astat="" seq="" sess="" avname="" hook=""
  IFS=$'\t' read -r _ _ _ _ _ fg astat seq sess avname hook _ws <<< "$line"
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
  local js="" obj label wsid pid tid cwd fgcwd
  _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=()
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
    _term_place_add_pane "$label" "$pid" "$wsid" "$tid" "$cwd" "$fgcwd"
  done < <(_term_json_objs <<< "$js")
  _TERM_PLACE_CACHE=1
  return 0
}

_term_herdr_place_reset() { _TERM_PLACE_CACHE=0; _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=(); }

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
_term_place_set_pane() {  # <label> <pane> <wsid> <tab> <cwd>
  local label="${1-}" pane="${2-}" wsid="${3-}" tab="${4-}" cwd="${5-}"
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
    warn "            ③ 换更大窗口/显示器后 attach（唯一后端 = herdr：旧版 tmux 后端已移除）"
    warn "  文档：docs/INSTALL.md「herdr 后端」· docs/prds/2026-11-10-herdr-base.md AC3.2（J1–J5）"
    return 1
  fi
  if (( w < TERM_MIN_COLS || h < TERM_MIN_ROWS )); then
    warn "空间不足：$name（pane=$pid）列=$w < ${TERM_MIN_COLS} 或 行=$h < ${TERM_MIN_ROWS} —— 仅 warn，不中断（rc 语义跨后端一致）"
    warn "  该怎么办：① 调 [server] headless_cols/headless_rows（config.toml）放大后重启会话（cleanup + session-start）"
    warn "            ② attach 后重排：herdr session attach ${HERDR_SESSION:-<session>}，再调整窗口/分屏"
    warn "            ③ 换更大窗口/显示器后 attach（唯一后端 = herdr：旧版 tmux 后端已移除）"
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

_term_herdr_spawn() {  # <name> <inner> <repo> [force] <label> [group] → SPAWN_RC_OK|FAIL
  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}" pl="" obj js line
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
  # 快照失效：本命令后续目标（判重/归属）必须看到新 pane，不得复用 spawn 前的旧快照
  if [[ -n "${_TERM_SNAP_FILE:-}" ]]; then rm -f "$_TERM_SNAP_FILE" 2>/dev/null || true; _TERM_SNAP_FILE=""; fi
  # 放置快照回填（T554）：新 pane 进本命令快照（不再为后续目标重查 pane list）
  if (( _TERM_PLACE_CACHE )); then
    _term_place_set_pane "$name" "$pane" "$wsid" "$tid" "$repo"
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

# =============================================================================
# app 后端实现（T562 / Issue #168 · ADR 2026-11-24-herdr-app-backend）
#
#   身份：HC_SCOPE + HC_TERMINAL_ID + HC_TERMINAL_SOCKET 三件套（缺任一 ⇒ exit 3，不猜）；
#         socket 必须落在 app core 目录 `$XDG_RUNTIME_DIR/herdr-core/` 下（stale/外贸 env 防串台）。
#   连接：**唯一入口 `_term_app_exec`** —— 注入 `HC_SOCKET=$HC_TERMINAL_SOCKET`
#         （`HC_TERMINAL_SOCKET` 不参与路由；`HC_SESSION` 拼错会静默新建空 core ⇒ 不用它路由）。
#   失败判据：**JSON `error` 字段**，不看 rc（实测 `hc get` 无目标 rc=3 而 `hc get` 缺参 rc=0）。
#   放置：写标签 `herdr.space`/`herdr.tab` → **读 `doc.get herdr-app` 验证终端是否在该 tab 的 root 树**
#         → 不成则 kill+rm 回滚 + fail loud。`hc ls` 的 `where` 只是展示 label，**不进断言**。
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

_term_app_backend() { [[ "${NAO_TERMINAL:-}" == "app" ]]; }

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
#   T<TAB><space_id><TAB><tab_id><TAB><tab_name><TAB><terminals,csv>
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
  js='let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{let j;try{j=JSON.parse(d)}catch(e){console.error("doc.get 输出不可解析");process.exit(1)}let r=j.result||{};let v=r.value;if(!v){console.log("V\t0");return}console.log("V\t"+(r.version||0));const walk=(n,acc)=>{if(!n||typeof n!=="object")return;if(Array.isArray(n)){for(const x of n)walk(x,acc);return}if(typeof n.terminal==="string")acc.push(n.terminal);for(const k of Object.keys(n)){if(k!=="terminal")walk(n[k],acc)}};for(const s of (v.spaces||[])){console.log(["S",s.id,s.folder||"",s.name||""].join("\t"));for(const t of (s.tabs||[])){const acc=[];walk(t.root,acc);console.log(["T",s.id,t.id,t.name||"",acc.join(",")].join("\t"))}}})'
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
_term_app_snapshot() {
  local ls="" g addr name cwd tstate st fg fgcwd sp tb hook
  local nl ncwd nfgcwd nsp ntb nfgp nst nts
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
    name="$(_term_app_field "$g" name)"
    [[ -n "$name" ]] || continue
    cwd="$(_term_app_field "$g" cwd)"
    tstate="$(_term_app_term_state "$g")"
    st="$(_term_app_status_state "$g")"
    fg="$(_term_app_fg_name "$g")"
    fgcwd="$(_term_app_fg_cwd "$g")"
    sp="$(_term_app_field "$g" "$TERM_APP_LABEL_SPACE")"
    tb="$(_term_app_field "$g" "$TERM_APP_LABEL_TAB")"
    case "$g" in *'"reported":true'*) hook=1 ;; *) hook=0 ;; esac
    _term_tsv_norm "$name";  nl="$_TSV_NORM"
    _term_tsv_norm "$cwd";   ncwd="$_TSV_NORM"
    _term_tsv_norm "$fgcwd"; nfgcwd="$_TSV_NORM"
    _term_tsv_norm "$sp";    nsp="$_TSV_NORM"
    _term_tsv_norm "$tb";    ntb="$_TSV_NORM"
    _term_tsv_norm "$fg";    nfgp="$_TSV_NORM"
    _term_tsv_norm "$st";    nst="$_TSV_NORM"
    _term_tsv_norm "$tstate"; nts="$_TSV_NORM"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$nl" "$addr" "$addr" "$ncwd" "$nfgcwd" "$nfgp" \
      "$nst" - "$nts" - "$hook" "$nsp"
  done < <(printf '%s' "$ls" | grep -o '"address":"[^"]*"' | cut -d'"' -f4)
  return 0
}

# ---- 在线判定（M4：忙闲表，无 seq）----
_term_app_liveness() {  # <name> [repo] → verdict/state/seq/hook
  local name="${1-}" repo="${2-}" rows="" line rp="" filtered="" v="" state="-" cnt=0
  local _l _p _t c1 c2 fg st seq sess av hook ws live_rows=""
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
  # keep 换壳（BR4）：finished 终端 = pi 已退出、只剩 shell（`--keep` 语义）⇒ **不算在线**，
  #   也不参与同名歧义计数（否则一次 close/退出后的残留会把重建判成 ambiguous）；
  #   只有残留时给 `ghost`（label 在、agent 无）—— 比 absent 更诚实，status 会单列进证据异常节。
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\t' read -r _l _p _t _ _ fg st seq sess av hook ws <<< "$line"
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
    IFS=$'\t' read -r _l _p _t _ _ fg st seq sess av hook ws <<< "$line"
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

# ---- 放置（M3/BR2）：文档优先发现 space，缺则确定性铸造 ----
_term_sha256() {  # <串> → 64 位 hex（sha256sum / shasum -a 256 两制）
  if command -v sha256sum >/dev/null 2>&1; then printf '%s' "${1-}" | sha256sum | cut -d' ' -f1
  else printf '%s' "${1-}" | shasum -a 256 | cut -d' ' -f1; fi
}
_term_app_mint_space() {  # <repo> → sp<32hex>
  printf 'sp%s\n' "$(_term_sha256 "$(_term_path_norm "${1-}")" | cut -c1-32)"
}
_term_app_mint_tab() {  # <space> <name> → tb<32hex>
  printf 'tb%s\n' "$(_term_sha256 "${1-}|${2-}" | cut -c1-32)"
}

_term_app_place_prime() {  # → 0 已建快照 / 1 后端不可用（fail loud 由调用方）
  local rows snap sid folder base cand nn kind a b c d
  local -A sid_folder=() base_folder=() tab_of=()
  _TERM_PLACE_WS_BY_LABEL=(); _TERM_PLACE_WS_ROWS=(); _TERM_PLACE_PANE_ROWS=()
  rows="$(_term_app_doc_rows)" || return 1
  _term_app_doc_guard "$rows" || return 1
  # ① space 发现：doc 的 folder 是权威（app 持久化）；doc 缺该 space 时才用终端 cwd 兜底
  #    （M3「读该仓现有终端 label 取 space id」—— label 只存 id，folder 只有 doc 有）
  while IFS=$'\t' read -r kind a b c; do
    [[ "$kind" == "S" ]] || continue
    [[ -n "$a" && -n "$b" ]] && sid_folder["$a"]="$b"
  done <<< "$rows"
  snap="$(_term_app_snapshot)" || return 1
  while IFS=$'\t' read -r label addr _tid cwd fgcwd _fg _st _seq _sess _av _hook sp; do
    [[ -n "$label" ]] || continue
    if [[ -n "$sp" && -z "${sid_folder[$sp]:-}" && "$cwd" != "-" ]]; then sid_folder["$sp"]="$cwd"; fi
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
  while IFS=$'\t' read -r label addr _tid cwd fgcwd _fg _st _seq _sess _av _hook sp; do
    [[ -n "$label" ]] || continue
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

# 写后读 doc 验证：终端地址必须在目标 tab 的 root 树里（BR2；where 不参与）
_term_app_verify_place() {  # <space> <tab> <addr>
  local rows kind a b c d
  rows="$(_term_app_doc_rows)" || return 1
  while IFS=$'\t' read -r kind a b c d; do
    [[ "$kind" == "T" ]] || continue
    [[ "$a" == "$1" && "$b" == "$2" ]] || continue
    case ",${d}," in *",$3,"*) return 0 ;; esac
  done <<< "$rows"
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

_term_app_spawn() {  # <name> <inner> <repo> [force] <label> [group] → SPAWN_RC_OK|FAIL
  local name="${1-}" inner="${2-}" repo="${3-}" force="${4:-false}" label="${5-}" group="${6-}"
  local sp tb out addr
  [[ -n "$name" && -n "$inner" ]] || { warn "app spawn 参数缺失（name/inner）"; return "$SPAWN_RC_FAIL"; }
  [[ -n "$label" ]] || { warn "app spawn 缺放置键（期望 = 仓基键；repo=$repo）"; return "$SPAWN_RC_FAIL"; }
  if ! fleet_scope_problem "$label" >/dev/null; then
    warn "app spawn 的放置键不可用（label=$label；期望 ^[a-z0-9][a-z0-9_-]{0,15}$）"; return "$SPAWN_RC_FAIL"
  fi
  # space：快照已含该仓现有 space ⇒ 复用其 id；否则确定性铸造（app 按标签自建）
  if (( _TERM_PLACE_CACHE )); then sp="${_TERM_PLACE_WS_BY_LABEL[$label]:-}"; else sp=""; fi
  [[ -n "$sp" ]] || sp="$(_term_app_mint_space "$repo")"
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
  out="$(_term_app_exec run --bg --no-parent --keep --name "$name" --cwd "$repo" \
        --label "$TERM_APP_LABEL_SPACE=$sp" --label "$TERM_APP_LABEL_TAB=$tb" \
        -- "${SHELL:-/bin/bash}" -lc "$inner")" || true
  if ! _term_app_payload_ok "$out"; then
    warn "hc run 失败（name=$name）：$(printf '%s' "$out" | head -c 200)"
    return "$SPAWN_RC_FAIL"
  fi
  addr="$(_term_app_field "$out" address)"
  if [[ -z "$addr" ]]; then
    warn "hc run 未返回终端地址（name=$name）：$(printf '%s' "$out" | head -c 200)"
    return "$SPAWN_RC_FAIL"
  fi
  # BR2/AC4：写后读 doc 验证；不成 ⇒ 回滚自己刚建的终端 + fail loud（不留孤儿）
  if ! _term_app_verify_place "$sp" "$tb" "$addr"; then
    warn "放置验证失败：终端 $addr 不在目标 tab 的 root 树里（space=$sp tab=$tb）⇒ 回滚（kill → rm）"
    warn "  该怎么办：确认 desktop app 窗口在跑且版本支持标签收养；回滚后不会留下孤儿终端"
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
    _term_place_set_pane "$name" "$addr" "$sp" "$tb" "$repo"
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
_term_app_find_by_name() {  # <name> → 每行一个地址（ls --all）
  local name="${1-}" ls
  ls="$(_term_app_exec ls --all --json 2>/dev/null)" || return 0
  _term_app_payload_ok "$ls" || return 0
  printf '%s' "$ls" | grep -o '"address":"[^"]*"' | cut -d'"' -f4 | while IFS= read -r a; do
    local g; g="$(_term_app_exec get "$a" --json 2>/dev/null)" || continue
    [[ "$(_term_app_field "$g" name)" == "$name" ]] && printf '%s\n' "$a"
  done
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
      -|"")
        if [[ "$force" != true ]]; then
          warn "拒绝回收 $name：忙闲不可判定（$addr 无 status 上报）—— 确认无用时加 --force"
          return 1
        fi ;;
    esac
  fi
  # kill（幂等）→ rm（顺序不可反）
  if ! _term_app_exec kill "$addr" >/dev/null 2>&1; then
    warn "hc kill 失败（$name ⇒ $addr）"; return 1
  fi
  if ! _term_app_exec rm "$addr" >/dev/null 2>&1; then
    warn "hc rm 失败（$name ⇒ $addr：kill 后仍不可删？核对 hc ls --all）"; return 1
  fi
  # effect 判据（不看 rc）：地址必须从 ls --all 消失
  if _term_app_exec ls --all --json 2>/dev/null | grep -qF "\"address\":\"$addr\""; then
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

# 前提探测（check · M1）：只在 NAO_TERMINAL=app 时输出；不改变 TUI 用户的输出
_term_app_check_premise() {  # → 0 齐备 / 1 缺项（打印 `  ! ` 行）
  local bad=0 rows ver
  if ! command -v hc >/dev/null 2>&1; then
    printf '  ! app 后端：hc 不在 PATH（装 herdr desktop app CLI；不想用 app 后端请 unset NAO_TERMINAL）\n'
    return 1
  fi
  if ! command -v herdr-app >/dev/null 2>&1; then
    printf '  ! app 后端：herdr-app 不在 PATH（无法判断窗口状态）\n'; bad=1
  elif ! herdr-app status >/dev/null 2>&1; then
    printf '  ! app 后端：desktop app 窗口未在运行（ensure 会 exit 3：窗口关闭时终端不会被收养）\n'; bad=1
  fi
  if command -v hc >/dev/null 2>&1; then
    if ! _term_app_exec schema >/dev/null 2>&1; then
      printf '  ! app 后端：hc schema 不可用（core/socket 异常；核对 desktop app 后重试）\n'; bad=1
    fi
  fi
  if [[ -n "${HC_TERMINAL_SOCKET:-}" ]]; then
    if rows="$(_term_app_doc_rows 2>/dev/null)"; then
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

# 端前提声明一致性（#124 · AC5/AC6；上游 #118 §八 D4 裁定 = **不加新闸门**，改单点 warn）
#   比对面：机制文本声明的「默认后端」（`.agents/common/intercom-protocol.md` + `AGENTS.md`）
#   vs 实现默认（`NAO_TERMINAL` 唯一赋值点，从本脚本源码解析 —— 不在此重述默认值字面量）。
#   纪律：**只 warn、不改 rc**（BR4）；**一致时零输出**（tests/t4/cases/06 的 golden md5 依赖这一点）。
#   声明写法契约（改文案别破坏）：声明行须含 **`默认 herdr`** 原文（`默认` 与后端名之间只许空格 /
#   `=`/`＝`；不要插 `**` 等标记）。解析不出 ⇒ `nodecl` ⇒ warn（fail loud，不静默放过）。
#   **全部声明行参与判定**（P2-1 · QA 复核）：同文件内多行声明各判各的 —— 只回退其中一个症状行
#   （如 `AGENTS.md:18` 而 `:33` 仍写 herdr）也必须被抓到；旧实现「取第一条可解析行」正是该盲区。
#   输出（每行一条，TAB 分隔）：`<行号>\t<herdr|tmux|nodecl>`；
#   **无输出 = 不适用**（文件不存在 / 存在但无端前提声明行）—— 只 `return 0`，**不打印 `absent`**
#   （P1-1：单 token 会被调用方读成 `行号=absent, 声明=""` ⇒ npm 安装态每次 `check` 常驻假 warn；
#    真实信道 = npm 包根 `files` 不含 `AGENTS.md`，下游 shim 仓也可能没有协议文件）
premise_declared_backend() {
  local f="$1" n line decl
  [[ -f "$f" ]] || return 0
  grep -qE '运行前提|机制只支持|端前提' "$f" 2>/dev/null || return 0
  # 只信「端前提声明行」：其它行的「默认」与后端无关（如「默认 main-row2」布局）
  #   `tmux` 仍被解析（T555/AC10）：声明里残留它 ⇒ 由调用方 warn 点名「已移除」，**不**静默放过。
  while IFS=: read -r n line; do
    [[ -n "${n:-}" ]] || continue
    decl="$(printf '%s\n' "$line" | grep -oE '默认(后端)?[ ]*(=[ ]*)?(herdr|tmux)' | head -1 | grep -oE '(herdr|tmux)$')"
    if [[ -z "$decl" ]]; then
      # 旧口径（v0.23.0 前）：「唯一路径 … tmux」= 声明 tmux 唯一 ⇒ 与现行默认 herdr 不一致
      if printf '%s\n' "$line" | grep -qE '唯一路径.*tmux'; then decl=tmux; else decl=nodecl; fi
    fi
    printf '%s\t%s\n' "$n" "$decl"
  done < <(grep -nE '运行前提|机制只支持|端前提' "$f" 2>/dev/null || true)
}

# warn-only 单点一致性检查（调用点必须 `|| true`）：逐**声明行**一条 `  ! `（进摘要 warn=N，不合并吞行号）
check_backend_premise() {
  local actual f decl n rel
  actual="$(sed -n 's/^NAO_TERMINAL="\${NAO_TERMINAL:-\([A-Za-z][A-Za-z]*\)}"$/\1/p' "$SELF_SH" 2>/dev/null | head -1)"
  if [[ -z "$actual" ]]; then
    printf '  ! 端前提声明比对跳过：无法从 %s 的 NAO_TERMINAL 唯一赋值点解析默认后端\n' "${SELF_SH#"$SKILLS_DIR"/}"
    return 0
  fi
  for f in "$COMMON_DIR/intercom-protocol.md" "$SKILLS_DIR/AGENTS.md"; do
    rel="${f#"$SKILLS_DIR"/}"
    while IFS=$'\t' read -r n decl; do
      [[ -n "${n:-}" ]] || continue                  # 空行/不产生行 ⇒ 不适用（"absent" 不再作为 token 出现）
      [[ "$decl" == "$actual" ]] && continue         # 该行与实现一致 ⇒ 零输出
      if [[ "$decl" == "nodecl" ]]; then
        printf '  ! 端前提行未给出可比对的后端声明：%s:%s（若该行与终端后端无关，可忽略；或在 AGENTS.md 中删去该行的「运行前提」字样以免被纳入比对）—— 实现默认 = %s（%s 的唯一赋值点）\n' \
          "$rel" "$n" "$actual" "nao-fleet.sh"
      elif [[ "$decl" == "tmux" ]]; then
        printf '  ! 端前提声明不一致：%s:%s 声明默认后端 = tmux，而本版**已移除 tmux 后端**（唯一后端 = %s，见 %s 的唯一赋值点）—— 改声明为「运行前提（仅 pi · 默认 herdr）」\n' \
          "$rel" "$n" "$actual" "nao-fleet.sh"
      else
        printf '  ! 端前提声明不一致：%s:%s 声明默认后端 = %s，而实现默认 = %s（%s 的唯一赋值点）—— 改声明或改实现，同一事实勿双源\n' \
          "$rel" "$n" "$decl" "$actual" "nao-fleet.sh"
      fi
    done < <(premise_declared_backend "$f")
  done
  return 0
}

# stash 出口机械闸（#126 B2-2 · github-flow BR5「批间收尾」）—— `check` 内**只读**告警，不改 rc。
#   动机（2026-11-14 实测）：3 条滞留 stash（`v0.22.6` 压 7 天 · `M20261113` 压 7.5 小时且其 sha
#   `0863ab2` 在台账 grep = 0）⇒ 合并后事实留在 stash 里 = 终态从未入库。
#   #130 D1（**年龄阈值**）：BR5 的合法用法是「合并后事实 ⇒ 带标签 stash、随下批首提交回填」——
#   当天回填属正常节奏，而「任何 stash 都 warn」会让闸门自己变成常驻噪声（连撞两批）。故只对
#   **最老一条**年龄 > `NAO_STASH_WARN_HOURS`（默认 6 小时）的才 warn；当天回填**静默**。
#   年龄取法：`stash list --format='%ct'` 的**最小值**（= stash 提交的 committer date）。
#     为什么不取 reflog 时间：`%ct` 是「事实被切出来」的时刻 —— `git stash store` 把**旧** stash 导入
#     本仓时它保持原龄，而 reflog 时间会被刷成 now（旧事实被当成新的、永久静默）；且 `%ct` 一次
#     `stash list --format` 即可取值，不必逐条 reflog 子进程。
#   阈值取值口径：正整数 = 小时数；`0` = 立即（关闭年龄豁免，任何 stash 都 warn）；非数字 / 负数 = **非法**
#     ⇒ 按 `0` 处理（配置坏了不得把闸门静默调松，宁可多报），并在文案里点名「取值无效」。
#   时间不可判定（`%ct` 取不到 / 非数字）或**未来时间戳**（age < 0，时钟回拨 / 手工造未来日期）：**不 warn**
#     （时间不可信时不误报；也不得因算术把闸门弄崩）。
#   根（可注入 · 测试纪律）：`NAO_STASH_ROOT` ⇒ 默认 `$SKILLS_DIR`；**根上无 `.git` ⇒ 零输出**，
#   **不向上 walk**（临时目录落在父仓里也不会被误判；npm 安装态 / 非仓目录同样不适用）。
#   只读契约：本闸**绝不** push/pop/apply/drop —— 滞留事实的处置权在提交人。
#   输出：超阈值 ⇒ **一条** `  ! `（进摘要 warn=N、`-v` 可见，不逐条刷屏）；空 / 不适用 / 未超阈值 ⇒ 零输出。
check_stash_residue() {
  local root="${NAO_STASH_ROOT:-$SKILLS_DIR}" n newest oldest now hours threshold age age_h label hint
  [[ -e "$root/.git" ]] || return 0
  command -v git >/dev/null 2>&1 || return 0
  n="$(git -C "$root" stash list 2>/dev/null | grep -c . || true)"
  [[ "$n" =~ ^[0-9]+$ ]] || return 0
  (( n > 0 )) || return 0
  hours="${NAO_STASH_WARN_HOURS:-6}"
  hint=""
  if [[ "$hours" =~ ^[0-9]+$ ]]; then
    # 前导零必须按**十进制**解释（#130 返修 P2-1）：`08`/`0008` 在算术里会被当八进制 ⇒
    #   `$(( hours * 3600 ))` 直接报「值对于底数而言过大」⇒ check rc=1 且无汇总行（门禁自己崩）；
    #   `010` 则会静默按 8 生效、文案却写 010。凡放行前导零，必须先 `10#`。
    hours=$((10#$hours))
  else
    hint="（NAO_STASH_WARN_HOURS 取值无效 ⇒ 按立即处理）"; hours=0
  fi
  threshold=$(( hours * 3600 ))
  # 最老一条 = 最小 `%ct`；取不到（非数字）⇒ 时间不可判定 ⇒ 不 warn，但必须留**降级注记**
  #   （#130 返修 P2-2）：否则「能力缺失」与「无 stash」在输出上不可区分 ⇒ 闸门可被永久且无痕静默。
  #   注记只走 `  ·`（只在 -v 报告里出现），不计 warn、不改 rc。
  oldest="$(git -C "$root" stash list --format='%ct' 2>/dev/null | grep -E '^[0-9]+$' | sort -n | head -1 || true)"
  if [[ ! "$oldest" =~ ^[0-9]+$ ]]; then
    printf '  · 暂存滞留检查跳过：`stash list --format=%%ct` 不可解析（%s 条 stash 仍在）⇒ 无法做年龄判定（未 warn，也未据此判「无滞留」）\n' "$n"
    return 0
  fi
  now="$(date +%s 2>/dev/null || true)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 0
  age=$(( now - oldest ))
  (( age < 0 )) && return 0                       # 未来时间戳 ⇒ 不误报（别炸）
  # hours=0（显式 0 或非法值）⇒ 立即：任何年龄都 warn（fresh stash 的 age 可能 0，故不能靠 `> 0` 判）
  (( hours > 0 )) && { (( age > threshold )) || return 0; }
  age_h=$(( age / 3600 ))
  newest="$(git -C "$root" stash list -1 --format='%s' 2>/dev/null || true)"
  label="$root"
  case "$root" in
    "$SKILLS_DIR") label="." ;;
    "$SKILLS_DIR"/*) label="${root#"$SKILLS_DIR"/}" ;;
  esac
  printf '  ! git stash 非空（%s 条 @ %s，最老一条 %s 小时前 > 阈值 %s 小时%s）：合并后事实可能滞留 stash（BR5）⇒ 下批首提交须 pop 或归口（本闸只读，不自动 pop；最新一条=%s）\n' \
    "$n" "$label" "$age_h" "$hours" "$hint" "${newest:-<无消息>}"
  return 0
}

# PRD 结构探针（M20261118-prd-structure · **warn-only**：只提示，**不进 warn 计数、不改 rc**）。
#   动机：ADR 有结构契约（checklists §四），PRD 长期无任何门禁 ⇒ 结构漂移只能靠人眼看。
#   口径（PM 定，防刷屏）：
#     · 只在本仓存在 `docs/prds/*.md` 时生效（无目录 / 无 PRD ⇒ 零输出）。
#     · **只查文件名日期 ≥ `NAO_PRD_STRUCT_SINCE`（默认 2026-11-18）** 的 PRD：老 PRD 不追溯
#       （前缀 `YYYY-MM-DD-`；无前缀 / 不可解析 ⇒ 不查，`-v` 给一条跳过注记，**不猜**）。
#     · 三条判据：① 必含 9 个 `## ` 模块标题（TL;DR + 一…九；`## 附录` 可缺）
#                  ② §七 AC 节内 `### ` 组 ≥5（五覆盖：主路径/异常/边界/负向闭环/设计一致性）
#                  ③ 全文 ≤150 行（PRD 上限，见 checklists §一）
#     · 违反 ⇒ **恰一条** `  ! PRD 结构…`（排除计入 warn 的名单见 cmd_check 摘要处）；`-v` 逐文件展开。
#     · **防假绿**：文件不可读 / 0 字节 **不算通过** —— 单列「不可读/空」，不得当「结构合格」放行。
#     · 局限（可接受）：统计按行首标记，不区分数围栏内的示例；warn-only 不阻断，误报代价低。
check_prd_structure() {
  local dir="$PWD/docs/prds" since="${NAO_PRD_STRUCT_SINCE:-2026-11-18}"
  [[ "$since" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
    || { $VERBOSE && printf '  · PRD 结构：NAO_PRD_STRUCT_SINCE=%s 非法（应为 YYYY-MM-DD）⇒ 回落默认 2026-11-18\n' "$since"; since="2026-11-18"; }
  [[ -d "$dir" ]] || return 0
  local -a files=()
  shopt -s nullglob
  files=("$dir"/*.md)
  shopt -u nullglob
  (( ${#files[@]} > 0 )) || return 0
  local f base d nlines ac_groups miss h total=0 bad=0 first="" detail=""
  local -a req=("TL;DR" "一、" "二、" "三、" "四、" "五、" "六、" "七、" "八、" "九、")
  for f in "${files[@]}"; do
    base="$(basename "$f")"
    if [[ ! "$base" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})- ]]; then
      $VERBOSE && printf '  · PRD 结构：跳过 %s（文件名无 `YYYY-MM-DD-` 前缀 ⇒ 无法判定是否追溯面）\n' "$base"
      continue
    fi
    d="${BASH_REMATCH[1]}"
    [[ "$d" < "$since" ]] && continue        # ISO 日期可直接按字串比较
    total=$((total + 1))
    miss=""
    if [[ ! -r "$f" || ! -s "$f" ]]; then
      # 防假绿：读不到 / 空文件 ≠ 合格（否则「删内容凑绿」永不可发现）
      miss="不可读或空文件（拒绝判为合格）"
    else
      nlines="$(wc -l <"$f" 2>/dev/null | tr -d ' ' || echo 0)"
      [[ "$nlines" =~ ^[0-9]+$ ]] || nlines=0
      local -a lack=()
      for h in "${req[@]}"; do
        grep -qE "^##[[:space:]]+${h}" "$f" 2>/dev/null || lack+=("$h")
      done
      (( ${#lack[@]} > 0 )) && miss+="缺模块 ${lack[*]}；"
      # §七 AC 节内的 `###` 组数（到下一个小节标题为止）
      ac_groups="$(awk '
        /^##[[:space:]]/ { if (ins) exit; if ($0 ~ /^##[[:space:]]+七、/) { ins=1; next } }
        ins && /^###[[:space:]]/ { n++ }
        END { print n + 0 }
      ' "$f" 2>/dev/null || echo 0)"
      [[ "$ac_groups" =~ ^[0-9]+$ ]] || ac_groups=0
      (( ac_groups < 5 )) && miss+="AC 分组 ${ac_groups} < 5；"
      (( nlines > 150 )) && miss+="${nlines} 行 > 150；"
      # 防御：读成功但三条全空（含 0 行且标记齐的神文件）⇒ 合格
      miss="${miss%；}"
    fi
    [[ -n "$miss" ]] || continue
    bad=$((bad + 1))
    if [[ -z "$first" ]]; then first="$base：$miss"; fi
    detail+="  · PRD 结构：docs/prds/$base —— $miss"$'\n'
  done
  (( bad > 0 )) || return 0
  printf '  ! PRD 结构（warn-only，不计 warn / 不改 rc）：%s 份新 PRD（≥%s）中 %s 份缺结构（%s）⇒ -v 看明细（规范：checklists/deliverable-docs.md §三）\n' \
    "$total" "$since" "$bad" "$first"
  $VERBOSE && printf '%s' "$detail"
  return 0
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
# 舰队命名契约 v2（T554 · ADR 2026-11-20-workspace-as-binding-unit · 唯一构造/解析点）
#
#   放置键 = 仓（`place_key_label`，见下）；**名字不含位置**（`@` 段已删除）。
#   常驻 = `<role>[<N>]` · 派生 = `<role>[<N>](<task>)`（N 在 `(` **之前**，单字符 2..9，
#     空 = 槽位 1；task = `^[A-Za-z0-9_-]+$`，`T` 是任务号自带前缀，格式不另加）。
#   预算：name ≤48 · role 段（含 N）≤32（卡）· task 不设独立上限（随 name 总长收紧）。
#   文法唯一判据（R1）：`(` 位置 + 槽位紧贴单字符 + 角色**最长匹配** + 按**首个分隔符**分派：
#     `(` ⇒ 新形 · `-` ⇒ 旧形只读 · `@` ⇒ legacy scope（旧形只读）。三集合不相交。
#   反例（§一.3，用例 28 注释同抄）：
#     ① `rd-be2(T553)` 唯一分解 = rd-be + 槽位 2 + task T553；若 N 放到 `)` 后
#        （`rd-be(T553)2`）就与「task 尾部数字」不可区分 ⇒ 该串不以 `)` 结尾 ⇒ ERR。
#     ② `rd-be(T553)` 与旧形 `rd-be-T553` 是不同字符串：`qa-2` 是旧形任务号 2，`qa2` 是槽位 2。
#   历史形态：旧形 `<core>[-<task>][@<scope>]` 只读（status/close 接受；ensure 自动命名永不生成）。
#   parse 输出：新形 `OK <kind>,<role>,<task>,<num>` · 旧形 `LEGACY OK <kind>,<role>,<task>,<scope>` · 非法 `ERR`
#   （第 4 段语义按前缀区分：新形 = 槽位号、旧形 = scope —— 调用点禁把 legacy 值当 num）。
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

# 弃用告警**单源**（D7）：`--fleet` / `--scope` / `fleet.yaml` 的 `slug:` / `.agents/fleet-scope`
#   命中 ⇒ 本函数打**恰一行** warn（本版忽略，下一 MINOR 移除），不校验、不 fail、不影响放置。
#   调用点每来源只调一次（flag 在 argv 解析处；文件在 ensure 相位 0 每目标仓一次）。
_fleet_deprecated_warn() {  # <--fleet|--scope|fleet-scope|slug>
  local src="${1-}"
  case "$src" in
    --fleet)      printf '[fleet] 弃用：--fleet 本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    --scope)      printf '[fleet] 弃用：--scope 本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    fleet-scope)  printf '[fleet] 弃用：.agents/fleet-scope 本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    slug)         printf '[fleet] 弃用：fleet.yaml 的 slug 字段本版忽略（下一 MINOR 移除）；放置键恒为仓基键\n' >&2 ;;
    *)            printf '[fleet] 弃用：%s 本版忽略（下一 MINOR 移除）\n' "$src" >&2 ;;
  esac
  return 0
}

# legacy scope 合法性（只读面 + manifest code 共用）：合法 0；否则 echo 单行原因 + 1。
#   D-1（2026-11-17 用户拍板 A）：保留前缀 subagent- / nao- **只管 role**，不拒 scope。
#   新形不再产生 scope；本函数只服务旧形解析与 manifest `code` 校验。
fleet_scope_problem() {
  local s="${1-}"
  [[ -n "$s" ]] || { printf 'fleet/scope 为空（空值的语义是「未给」，不得写成裸 @）\n'; return 1; }
  (( ${#s} <= 16 )) || { printf 'fleet/scope 过长（%d > 16 字符）\n' "${#s}"; return 1; }
  [[ "$s" =~ ^[a-z0-9][a-z0-9_-]*$ ]] \
    || { printf 'fleet/scope 含非法字符（须 ^[a-z0-9][a-z0-9_-]*$：小写字母/数字/-/_，首字符非 -/_；禁 @ . : 空白）\n'; return 1; }
  [[ "$s" != *- ]] || { printf 'fleet/scope 不得以 - 结尾\n'; return 1; }
  return 0
}

# 放置键 = **仓基键**（单一实现；原 fleet_scope_slug 改名）：
#   git 仓 = `basename(dirname(realpath(git --git-common-dir)))`（防 worktree 分裂）；
#   非 git 仓 = realpath(repo) 的 basename；归一 = lowercase / 非 [a-z0-9] → - / 压缩 - / 去首尾 /
#   截 16 / 空则 `repo`。stdout 恰 1 行；空输出 = 实现缺陷（调用方 die，禁用 rc/空行承载不可知）。
place_key_label() {
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

# ⓪ 名字主体构造（**唯一构造点**）：<role> [<task>] [<num>] → `<role><num>` 或 `<role><num>(<task>)`
#   num 空 = 槽位 1（不出现数字）；num 非空必须是单字符 2..9（N>9 结构上不可解析 ⇒ fail loud）。
#   core 与 scope/fleet 彻底解耦（名字不含位置）。
fleet_core_build() {
  local role="${1-}" task="${2-}" num="${3-}"
  [[ -n "$role" ]] || { printf 'fleet_core_build：role 为空\n' >&2; return 1; }
  [[ "$role" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] \
    || { printf 'fleet_core_build：role 含非法字符（仅字母/数字/-/_）：%s\n' "$role" >&2; return 1; }
  if [[ -n "$num" ]]; then
    [[ "$num" =~ ^[2-9]$ ]] \
      || { printf 'fleet_core_build：槽位号非法（只接受单字符 2..9；空 = 槽位 1）：%s\n' "$num" >&2; return 1; }
  fi
  if [[ -n "$task" ]]; then
    [[ "$task" =~ ^[A-Za-z0-9_-]+$ ]] \
      || { printf 'fleet_core_build：task 含非法字符（仅字母/数字/-/_）：%s\n' "$task" >&2; return 1; }
    printf '%s%s(%s)\n' "$role" "$num" "$task"
  else
    printf '%s%s\n' "$role" "$num"
  fi
}

# ① 名字构造（kind 只做契约自证）：<kind> <role> [<num>] [<task>] → stdout 名字
#   签名与判据 §四 一致（build(kind,role[,num][,task])）；旧签名第 3 参 scope 已删除
#   ⇒ 传非空非法值（如旧 scope）即 rc≠0（防调用点静默残留旧语义）。
fleet_name_build() {
  local kind="${1-}" role="${2-}" num="${3-}" task="${4-}"
  case "$kind" in
    resident|derived|card) ;;
    *) printf 'fleet_name_build：未知 kind=%s（只能是 resident|derived|card）\n' "${kind:-<空>}" >&2; return 1 ;;
  esac
  fleet_core_build "$role" "$task" "$num"
}

# ② 名字解析（**全函数**：任何输入都有定义结果；非法一律 ERR，禁猜）
#   分派顺序：含 `(` ⇒ 新形；否则含 `@` ⇒ legacy scope；否则旧形（`-` 任务分隔）。
#   角色 = 事实表**最长匹配**；旧形 task 必须由 `-` 引导（故 `pm1` / `pm10` / `pm2x` 均 ERR）。
fleet_name_parse() {
  local name="${1-}" pre="" task="" scope="" role="" kind="" best="" bestnum="" num="" rest="" c=""
  [[ -n "$name" ]] || { printf 'ERR\n'; return 0; }
  (( ${#name} <= 48 )) || { printf 'ERR\n'; return 0; }        # 总名长预算

  # ---- 新形：<role>[<N>](<task>) ----
  if [[ "$name" == *'('* ]]; then
    [[ "$name" == *')' ]] || { printf 'ERR\n'; return 0; }    # 反例①：不以 `)` 结尾 ⇒ ERR
    pre="${name%%(*}"
    rest="${name#*(}"
    [[ "$pre" != *'('* ]] || { printf 'ERR\n'; return 0; }     # 只允许一个 `(`
    [[ "$rest" == *')' ]] || { printf 'ERR\n'; return 0; }
    task="${rest%)}"
    [[ "$task" != *')'* ]] || { printf 'ERR\n'; return 0; }    # 只允许一个 `)`（且必须在末尾）
    [[ -n "$task" && "$task" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'ERR\n'; return 0; }
    (( ${#FLEET_ROLE_KIND[@]} )) || { printf 'ERR\n'; return 0; }
    for c in "${!FLEET_ROLE_KIND[@]}"; do
      if [[ "$pre" == "$c" ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum=""
      elif [[ "$pre" == "$c"[2-9] ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum="${pre:${#c}}"
      fi
    done
    [[ -n "$best" ]] || { printf 'ERR\n'; return 0; }
    role="$best"; num="$bestnum"
    case "$role" in subagent-*|nao-*) printf 'ERR\n'; return 0 ;; esac
    kind="${FLEET_ROLE_KIND[$role]:-}"
    [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
    if [[ "$kind" == "card" ]] && (( ${#role} + ${#num} > 32 )); then printf 'ERR\n'; return 0; fi
    if [[ "$kind" == "resident" ]]; then kind="derived"; fi
    printf 'OK %s,%s,%s,%s\n' "$kind" "$role" "$task" "$num"
    return 0
  fi

  # ---- 新形常驻（无括号）：<role>[<N>]（裸 <role> 与旧形裸名同串 ⇒ 归新形；旧形裸名行为不变）----
  if [[ "$name" != *@* ]]; then
    best=""; bestnum=""
    for c in "${!FLEET_ROLE_KIND[@]}"; do
      if [[ "$name" == "$c" ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum=""
      elif [[ "$name" == "$c"[2-9] ]]; then
        [[ -z "$best" ]] || (( ${#c} > ${#best} )) || continue
        best="$c"; bestnum="${name:${#c}}"
      fi
    done
    if [[ -n "$best" ]]; then
      case "$best" in subagent-*|nao-*) printf 'ERR\n'; return 0 ;; esac
      kind="${FLEET_ROLE_KIND[$best]:-}"
      [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
      if [[ "$kind" == "card" ]] && (( ${#best} + ${#bestnum} > 32 )); then printf 'ERR\n'; return 0; fi
      printf 'OK %s,%s,,%s\n' "$kind" "$best" "$bestnum"
      return 0
    fi
  fi

  # ---- 旧形（只读）：<core>[@<scope>] ----
  case "$name" in
    *@*@*) printf 'ERR\n'; return 0 ;;                          # 多 @（歧义，无定义）
    *@*)
      pre="${name%@*}"; scope="${name##*@}"
      [[ -n "$pre" ]] || { printf 'ERR\n'; return 0; }
      fleet_scope_problem "$scope" >/dev/null || { printf 'ERR\n'; return 0; }
      ;;
    *) pre="$name" ;;
  esac
  case "$pre" in
    subagent-*|nao-*) printf 'ERR\n'; return 0 ;;              # 保留前缀不属舰队命名空间
  esac
  (( ${#FLEET_ROLE_KIND[@]} )) || { printf 'ERR\n'; return 0; }
  best=""
  for c in "${!FLEET_ROLE_KIND[@]}"; do
    if [[ "$pre" == "$c" ]]; then best="$c"; break; fi
    [[ "$pre" == "$c"-?* ]] || continue
    if [[ -z "$best" ]] || (( ${#c} > ${#best} )); then best="$c"; fi
  done
  [[ -n "$best" ]] || { printf 'ERR\n'; return 0; }
  role="$best"
  if [[ "$pre" == "$role" ]]; then task=""; else task="${pre:${#role}+1}"; fi
  if [[ -n "$task" ]]; then
    [[ "$task" =~ ^[A-Za-z0-9_-]+$ ]] || { printf 'ERR\n'; return 0; }
  fi
  kind="${FLEET_ROLE_KIND[$role]:-}"
  [[ -n "$kind" ]] || { printf 'ERR\n'; return 0; }
  if [[ "$kind" == "resident" && -n "$task" ]]; then kind="derived"; fi
  if [[ "$kind" == "card" ]] && (( ${#pre} > 32 )); then printf 'ERR\n'; return 0; fi
  # v2：卡会话不再有 scope 形态（一次性语义）⇒ `sec-review@todo` 属非法旧形
  if [[ "$kind" == "card" && -n "$scope" ]]; then printf 'ERR\n'; return 0; fi
  printf 'LEGACY OK %s,%s,%s,%s\n' "$kind" "$role" "$task" "$scope"
}
# <<< fleet-name-contract END

# ===========================================================================
# 联动仓 manifest（`.agents/fleet.yaml` · T554 降级为「仓代号 → 路径」映射）
#
# 数据通道（单一读点在本节）：
#   fleet_manifest_load <repo_phys> → stdout 记录流，rc 承载「合法 / 非法」：
#     NONE                             无 manifest（**合法事实**，不是错误）
#     ROOT<TAB><repo_phys>              manifest 所在仓根（`@main` 的目标）
#     REPO<TAB><code><TAB><path_phys>  ×N
#   rc=1 ⇒ stderr 单行 `<文件>:<行号> <字段> <原因>`（fail loud）。
#   禁：用 rc / 空行承载「不可知」· 空输出当 NONE（那是实现缺陷，调用方 die）· 落盘缓存
#   （AC8 由「每命令一次、无落地」构造性满足）。
#   manifest 源 = 调用方仓根（不做向上查找、不自动发现联动仓 —— 已知边界见 ADR §限制）。
# 受限 YAML 子集（零新依赖、零网络）：顶层键 repos（`slug:` 为弃用键：恰一行 warn 后忽略）；
#   项键只 code / path；缩进用空格（整行 `#` 注释）、值单双引号可省可留；
#   锚点/别名/流式/多文档/制表符/未知键 ⇒ 非法。
# ===========================================================================
FLEET_MANIFEST_SLUG_SEEN=0; FLEET_MANIFEST_WARNED=0
fleet_manifest_root() {  # <dir> → 仓根物理路径（git toplevel；非 git 仓 = 该目录物理路径）
  local d="${1-}" top=""
  [[ -n "$d" ]] || d="$PWD"
  if command -v git >/dev/null 2>&1; then
    top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  fi
  [[ -n "$top" ]] || top="$d"
  _fleet_phys "$top"
}

fleet_manifest_load() {  # <repo_phys> → 记录流（见上）· rc=1 非法（stderr 点名文件:行号 字段 原因）
  local repo="${1-}" f="" line="" indent="" rest="" key="" val="" sec=""
  local slug_seen=0 in_item=0 istart=0 icode="" ipath="" icno=0 ipno=0
  local no=0 why="" i=0 j=0 pp="" need_in=0
  local -a codes=() cpaths=() cnos=() plits=() istarts=()

  [[ -n "$repo" ]] || { printf 'fleet_manifest_load：缺仓路径\n' >&2; return 1; }
  repo="$(_fleet_phys "$repo")"
  f="$repo/.agents/fleet.yaml"
  if [[ ! -e "$f" && ! -L "$f" ]]; then printf 'NONE\n'; return 0; fi
  if [[ ! -f "$f" ]]; then
    printf '%s:1 fleet.yaml 不是常规文件（目录 / fifo / socket 一律拒绝）\n' "$f" >&2; return 1
  fi
  [[ -r "$f" ]] || { printf '%s:1 fleet.yaml 不可读\n' "$f" >&2; return 1; }

  while IFS= read -r line || [[ -n "$line" ]]; do
    no=$((no + 1))
    line="${line%$'\r'}"
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" == *$'\t'* ]]; then
      printf '%s:%d 缩进/值 含制表符（本子集只接受空格缩进）\n' "$f" "$no" >&2; return 1
    fi
    indent="${line%%[![:space:]]*}"; rest="${line#"$indent"}"
    [[ "$rest" == \#* ]] && continue
    if [[ -z "$indent" ]]; then
      case "$rest" in
        ---|...) printf '%s:%d 多文档分隔 %s 不受支持（只接受单文档）\n' "$f" "$no" "$rest" >&2; return 1 ;;
      esac
      [[ "$rest" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:(.*)$ ]] \
        || { printf '%s:%d %s 无法解析（期望 `键: 值`；本子集只接受 repos）\n' "$f" "$no" "${rest%% *}" >&2; return 1; }
      key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
      if (( ${#val} >= 2 )); then
        case "$val" in \"*\") val="${val:1:${#val}-2}" ;; \'*\') val="${val:1:${#val}-2}" ;; esac
      fi
      case "$key" in
        slug)
          # D7：弃用键 —— 本版**不校验、不 fail、不影响放置**；warn 由调用方统一触发（见下函数），
          #   避免 status/close 的 `2>/dev/null` 把单源告警吞掉。
          FLEET_MANIFEST_SLUG_SEEN=1
          (( ! slug_seen )) && slug_seen=1
          sec=""
          ;;
        repos)
          [[ -n "$val" ]] && { printf '%s:%d repos 只接受缩进列表（值必须为空）\n' "$f" "$no" >&2; return 1; }
          sec="repos"
          ;;
        *)
          printf '%s:%d 未知键 %s（本子集只接受 repos；slug 为弃用键）\n' "$f" "$no" "$key" >&2; return 1
          ;;
      esac
      continue
    fi
    # ---- 缩进项：只允许位于 repos: 之下 ----
    [[ "$sec" == "repos" ]] || { printf '%s:%d 缩进项必须位于 `repos:` 之下\n' "$f" "$no" >&2; return 1; }
    if [[ "$rest" == -* ]]; then
      if (( in_item )); then
        codes+=("$icode"); cpaths+=("$ipath"); cnos+=("$icno"); plits+=("$ipno"); istarts+=("$istart")
      fi
      in_item=1; istart=$no; icode=""; ipath=""; icno=0; ipno=0
      rest="${rest#-}"; rest="${rest#"${rest%%[![:space:]]*}"}"
      [[ -n "$rest" ]] || { printf '%s:%d 列表项为空（期望 `- code: <短代号>`）\n' "$f" "$no" >&2; return 1; }
    elif (( ! in_item )); then
      printf '%s:%d 缩进项必须跟在 `- ` 列表项之后\n' "$f" "$no" >&2; return 1
    fi
    [[ "$rest" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:(.*)$ ]] \
      || { printf '%s:%d %s 无法解析（期望 `code: <短代号>` / `path: <路径>`）\n' "$f" "$no" "${rest%% *}" >&2; return 1; }
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    val="${val#"${val%%[![:space:]]*}"}"; val="${val%"${val##*[![:space:]]}"}"
    if (( ${#val} >= 2 )); then
      case "$val" in \"*\") val="${val:1:${#val}-2}" ;; \'*\') val="${val:1:${#val}-2}" ;; esac
    fi
    case "$val" in
      ''|'&'*|'*'*|'{'*|'['*|'|'*|'>'*|'!'*|'%'*)
        printf '%s:%d %s 值不受支持（空值 / 锚点 / 别名 / 流式 / 块标量 ⇒ 非法）\n' "$f" "$no" "$key" >&2; return 1 ;;
    esac
    case "$key" in
      code)
        [[ -n "$icode" ]] && { printf '%s:%d code 重复声明\n' "$f" "$no" >&2; return 1; }
        icode="$val"; icno=$no ;;
      path)
        [[ -n "$ipath" ]] && { printf '%s:%d path 重复声明\n' "$f" "$no" >&2; return 1; }
        ipath="$val"; ipno=$no ;;
      *)
        printf '%s:%d 未知键 %s（repos 项只接受 code / path）\n' "$f" "$no" "$key" >&2; return 1 ;;
    esac
  done < "$f"
  if (( in_item )); then
    codes+=("$icode"); cpaths+=("$ipath"); cnos+=("$icno"); plits+=("$ipno"); istarts+=("$istart")
  fi

  # ---- 全量校验（错误一律点名 文件:行号 字段 原因；slug 不参与）----
  for i in "${!codes[@]}"; do
    if [[ -z "${codes[$i]}" ]]; then
      printf '%s:%d repos 项缺 code\n' "$f" "${istarts[$i]}" >&2; return 1
    fi
    if [[ -z "${cpaths[$i]}" ]]; then
      printf '%s:%d repos 项缺 path\n' "$f" "${istarts[$i]}" >&2; return 1
    fi
    if ! why="$(fleet_scope_problem "${codes[$i]}")"; then
      printf '%s:%d code 不可用（%s）\n' "$f" "${cnos[$i]}" "$why" >&2; return 1
    fi
    [[ "${codes[$i]}" == "main" ]] && { printf '%s:%d code 不能用保留代号 main（`@main` 指 manifest 所在仓）\n' "$f" "${cnos[$i]}" >&2; return 1; }
    for j in "${!codes[@]}"; do
      (( j < i )) || break
      [[ "${codes[$j]}" == "${codes[$i]}" ]] && { printf '%s:%d code 重复（%s，首次声明在第 %d 行）\n' "$f" "${cnos[$i]}" "${codes[$i]}" "${cnos[$j]}" >&2; return 1; }
    done
    case "${cpaths[$i]}" in
      /*|..|../*) need_in=0 ;;
      *) need_in=1 ;;
    esac
    pp="$(_fleet_phys "$repo/${cpaths[$i]}")"
    if (( need_in )) && ! repo_contains_path "$repo" "$pp"; then
      printf '%s:%d path 经 symlink 逃出仓根（%s → %s；显式 ../ 或绝对路径才允许出仓）\n' "$f" "${plits[$i]}" "${cpaths[$i]}" "$pp" >&2; return 1
    fi
    [[ -e "$pp" ]] || { printf '%s:%d path 不存在（%s → %s）\n' "$f" "${plits[$i]}" "${cpaths[$i]}" "$pp" >&2; return 1; }
    [[ -d "$pp" ]] || { printf '%s:%d path 不是目录（%s → %s）\n' "$f" "${plits[$i]}" "${cpaths[$i]}" "$pp" >&2; return 1; }
  done

  (( slug_seen )) && printf 'DEPRECATED\tslug\n'
  printf 'ROOT\t%s\n' "$repo"
  for i in "${!codes[@]}"; do
    printf 'REPO\t%s\t%s\n' "${codes[$i]}" "$(_fleet_phys "$repo/${cpaths[$i]}")"
  done
  return 0
}

# manifest 弃用键的单源告警（**所有读入口**调用；同一命令只打一次）。
#   为什么不在 load 内直接 warn：status/close 用 `2>/dev/null` 捕获记录流，会连告警一起吞掉。
fleet_manifest_warn_deprecated() {  # <记录流>：含 DEPRECATED 行 ⇒ 恰一行 warn（同一命令只打一次）
  local stream="${1-}"
  [[ "$stream" == *$'DEPRECATED\tslug'* ]] || return 0
  [[ "${FLEET_MANIFEST_WARNED:-0}" == "1" ]] && return 0
  FLEET_MANIFEST_WARNED=1
  _fleet_deprecated_warn slug
  return 0
}

# `@` 段解析（T554 · 唯一顺序）：`@main` ⇒ manifest 所在仓；code 命中 ⇒ 联动仓；
#   否则既有仓路径语义；两者同时命中且物理路径不同 ⇒ fail loud；都未命中 ⇒ fail loud 列 code + 「@<仓路径>」。
#   纯函数：输入 = 段 + stdin 记录流；输出单行 `OK<TAB>main|linked|path<TAB>repo_phys`
#   （path 分支 = legacy 仓路径语义）。`@` **只选目标仓，不进名字**（AC/判据 §一.5）。
fleet_repo_resolve() {  # <段>（stdin = manifest 记录流）
  local seg="${1-}" kind="" a="" b="" root="" cpath="" pp="" i=0
  local -a codes=() cpaths=()
  while IFS=$'\t' read -r kind a b; do
    case "$kind" in
      ROOT) root="$a" ;;
      REPO) codes+=("$a"); cpaths+=("$b") ;;
    esac
  done
  [[ -n "$root" ]] \
    || { printf 'fleet_repo_resolve：manifest 记录流缺 ROOT 行（实现缺陷，不得猜）\n' >&2; return 1; }
  pp="$(_fleet_phys "$seg")"; [[ -d "$pp" ]] || pp=""
  for i in "${!codes[@]}"; do
    [[ "${codes[$i]}" == "$seg" ]] || continue
    cpath="${cpaths[$i]}"
    if [[ -n "$pp" && "$pp" != "$cpath" ]]; then
      printf 'fleet_repo_resolve：@%s 同时命中联动仓 code（%s）与仓路径（%s）且物理路径不同 ⇒ 不猜（该怎么办：二者只能取一个，改 code 或在 manifest 里指到同一物理路径）\n' \
        "$seg" "$cpath" "$pp" >&2
      return 1
    fi
    printf 'OK\tlinked\t%s\n' "$cpath"
    return 0
  done
  if [[ "$seg" == "main" ]]; then
    if [[ -n "$pp" && "$pp" != "$root" ]]; then
      printf 'fleet_repo_resolve：@main 同时命中主仓（%s）与仓路径（%s）且物理路径不同 ⇒ 不猜\n' "$root" "$pp" >&2
      return 1
    fi
    printf 'OK\tmain\t%s\n' "$root"
    return 0
  fi
  if [[ -n "$pp" ]]; then printf 'OK\tpath\t%s\n' "$pp"; return 0; fi
  printf 'fleet_repo_resolve：@%s 未命中（可用 code：%s；也可写 @main 指主仓，或 @<仓路径>）\n' \
    "$seg" "${codes[*]:-无}" >&2
  return 1
}

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
derived_in_field() {  # <role> [want_scope] → 同角色的派生命名（v2 + 旧形；空 = 无）
  local role="${1-}" want_scope="${2-}" n out k r t s sc
  [[ -n "$role" ]] || return 0
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    case "$out" in
      "OK "*)
        IFS=',' read -r k r t s <<< "${out#OK }"
        sc=""                                       # v2 无 scope
        ;;
      "LEGACY OK "*)
        IFS=',' read -r k r t sc <<< "${out#LEGACY OK }"
        ;;
      *) continue ;;
    esac
    [[ -n "$t" ]] || continue                      # 无任务号 ⇒ 不是派生
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
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    out="$(fleet_name_parse "$n")"
    case "$out" in
      "OK "*|"LEGACY OK "*) ;;
      *) continue ;;
    esac
    IFS=',' read -r k r t s <<< "${out#*OK }"
    [[ "$r" == "$role" && "$t" == "$want_task" ]] || continue
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
running_verdict() {  # <name> [repo] → same | absent
  local name="$1" repo="${2:-}"
  # T554：跨 workspace 同名合法 ⇒ **不再有 conflict 态**（判重域 = 目标 workspace；槽位由 ensure 相位 1 算定）。
  if running "$name" "$repo"; then printf 'same\n'; return 0; fi
  printf 'absent\n'
}

# ---- 共享投影（无后端调用）：会话名从门面快照取（label 即会话名；名册不参与身份判定 —— BR3/BR7）----
visible_session_names() {
  term_snapshot | awk -F'\t' 'NF && $1 != "" {print $1}' | awk '!seen[$0]++'
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

# ---------------------------------------------------------------------------

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
  local name="$1" repo="$2" model="$3" card_override="${4:-}" role_id="${5:-}" card_name="${6:-}" force="${7:-false}" label="${8:-}" group="${9:-}" card prompt_file inner
  # T537：卡路径可由调用方显式给出（下游仓卡）；未给出时仍走清单（PROMPTS_DIR/<card>）逐字不变
  # #75：**两条取卡通道分两个参数，禁混用** ——
  #   ④ card_override = `--card` 的**完整路径**（下游卡，已由 resolve_card 限定在 <repo>/.agents/prompts/ 内）
  #   ⑥ card_name     = 清单**相对名**（roles.yaml 的 card 文件名，由 cmd_ensure **按目标**下发）
  #   旧写法在无 override 时回落全局 `$PROMPT`（resolve 阶段每个目标覆写一次 ⇒ 最后一个胜出），
  #   于是多目标 `ensure arch rd-fe` 的**每个** pane 都拿到最后一个目标的卡（身份级错误）。
  if [[ -n "$card_override" ]]; then card="$card_override"; else card="$PROMPTS_DIR/${card_name:-}"; fi
  [[ -f "$card" ]] || die "角色卡不存在: $card"
  [[ -d "$repo" ]] || die "工作区不存在: $repo"

  # 前提已由入口 term_require 硬校验（HERDR_ENV / HERDR_SESSION / protocol 22）；
  #   此处只走唯一路径（BR1/BR3）。
  prompt_file="$(build_system_prompt "$card")"
  inner="cd $(printf %q "$repo") && export CODEGRAPH_TELEMETRY=0 && exec pi --name $(printf %q "$name")"
  [[ -n "$model" ]] && inner+=" --model $(printf %q "$model")"
  inner+=" --append-system-prompt $(printf %q "$prompt_file")"
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
  term_spawn "$name" "$inner" "$repo" "$force" "$label" "$group" || rc=$?
  case "$rc" in
    "$SPAWN_RC_OK")   SPAWN_OK=$((SPAWN_OK + 1))
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

  # D4（T554 迁移）：`.agents/fleet-scope` 只给**弃用信息行**（本版忽略、下一 MINOR 移除）。
  #   文件存在仍是合法状态 ⇒ **不计 warn、不改 rc**（T4 计数口径不变）。
  if [[ -e "$PWD/.agents/fleet-scope" || -L "$PWD/.agents/fleet-scope" ]]; then
    printf '  · 弃用：.agents/fleet-scope 已忽略（本版忽略，下一 MINOR 移除；放置键恒为仓基键）\n'
  fi

  echo "== 常驻角色卡（阈值 ${CARD_MAX_LINES} 行，frontmatter 校验）=="
  local a role version updated max_card="" max_lines=0 pct10=0
  for a in "${ROLE_ORDER[@]}"; do
    f="$PROMPTS_DIR/${ROLE_CARDS[$a]}"
    if [[ ! -f "$f" ]]; then
      printf '  ✗ %-26s 缺失\n' "${ROLE_CARDS[$a]}"; rc=1; continue
    fi
    lines=$(wc -l < "$f")
    if (( lines > max_lines )); then max_lines=$lines; max_card="${ROLE_CARDS[$a]}"; fi
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
  # #128 E1：卡预算基线（`-v` 可见；只观测，不进 rc —— 不设硬限，超阈值仍有逐卡 `!`）
  if (( max_lines > 0 )); then
    pct10=$(( max_lines * 1000 / CARD_MAX_LINES ))
    printf '  · 卡预算基线：最大 %s %d 行 / 阈值 %d 行（%d.%d%%）\n' "$max_card" "$max_lines" "$CARD_MAX_LINES" "$((pct10 / 10))" "$((pct10 % 10))"
  fi

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

  # #126 B2-2：stash 滞留机械闸（单点 · warn-only ⇒ 不改 rc；无 stash / 不适用 ⇒ 零输出）
  check_stash_residue || true

  # M20261118：PRD 结构探针（warn-only ⇒ 不计 warn、不改 rc；无新 PRD / 结构合格 ⇒ 零输出）
  check_prd_structure || true

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

  if _term_app_backend; then
    echo "== 运行前提（端前提 = herdr desktop app 终端 + pi ≥$MIN_PI_VERSION；app 后端）=="
    echo '  · 生效后端 NAO_TERMINAL=app（第二后端；status/ensure/close/cleanup 走门面；core 由 desktop app 管理；session-start 不适用）'
    _term_app_check_premise || rc=1
  else
  echo "== 运行前提（端前提 = herdr pane + pi ≥$MIN_PI_VERSION；AC1/AC3）=="
  # rc 口径（P3-4 订正）：**缺 herdr 可执行文件** ⇒ rc=1（明确错配，不能装没看见）；
  #   缺 `HERDR_SESSION`（未在 herdr pane 内，CI 常见）⇒ 只提示不置红（静态体检照跑）；
  #   `protocol≠22` ⇒ rc=1（唯一可置红的机械项）。
  echo '  · 生效后端 NAO_TERMINAL=herdr（唯一后端；#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）'
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
        printf '  · herdr api schema 不可用（status 将 exit 3）—— 核对 herdr ≥0.9.1 / server 状态后重试\n'
      fi
    else
      echo '  · 未在 herdr pane 内（HERDR_SESSION 空）：status 将 exit 3；default 已放行（仅破坏性动作需 --force）；纯静态体检可照跑'
    fi
  else
    printf '  ✗ herdr 缺失（status 将 exit 3）—— 装 herdr ≥0.9.1 后重试\n'; rc=1
  fi
  fi
  local pi_cur
  if pi_cur="$(pi_version_check)"; then
    printf '  ✓ pi 版本 %s ≥ %s\n' "$pi_cur" "$MIN_PI_VERSION"
  else
    printf '  ✗ pi 版本 %s < %s\n' "$pi_cur" "$MIN_PI_VERSION"; rc=1
  fi
  # #124：端前提声明（协议 / AGENTS.md）vs 实现默认后端 —— **单点 warn，不进 rc**；
  #   一致时零输出（不同后端、不同仓都不改既有输出形态；见函数注释与 tests/t4/cases/34）。
  check_backend_premise || true

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
  local n="$1" core="$1" num="" r rp
  [[ -n "$n" ]] || { echo "名字为空"; return 1; }
  (( ${#n} <= 48 )) || { echo "名字过长（总名 ${#n} > 48 字符）"; return 1; }
  case "$n" in
    *@*) echo "名字不得含 @（v2 名字不含位置；目标仓用 ensure <role>@<code>）"; return 1 ;;
    *'('*|*')'*) echo "名字不得含括号（派生 task 只走 --task，如 ensure --task T554 <角色>）"; return 1 ;;
  esac
  # 常驻槽位号：<role><N>（N 单字符 2..9；`pm1`/`pm0`/`pm10` 结构上不可解析）
  if [[ "$n" =~ ^(.*[^-])([2-9])$ ]]; then core="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[2]}"; fi
  (( ${#core} + ${#num} <= 32 )) || { echo "名字过长（role 段 ${#core}+${#num} > 32 字符）"; return 1; }
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
#   运行时读、不落状态文件（守「不新增配置」）；每 run 一次 glob + frontmatter 读，不新增后端/node 调用。
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

# S13（T554）：本仓同名会话行末尾的「他仓同名 N 个（ws=<label>）」附加字段。
#   数据源 = status 已建的快照（STATUS_SNAP，12 列含 workspace_id）+ workspace list（≤1 次）。
#   own 判据 = 该行 cwd/foreground_cwd 落在目标仓内（与 term_liveness 的 repo 过滤同源）。
_status_other_same() {  # <name> <repo_phys>
  local name="${1-}" repo="${2-}" line _n _p _t _c _f _fg _st _sq _sess _av _hk wsid c n=0 labels=""
  [[ -n "$name" && -n "${STATUS_SNAP:-}" ]] || return 0
  while IFS=$'\t' read -r _n _p _t _c _f _fg _st _sq _sess _av _hk wsid; do
    [[ "$_n" == "$name" ]] || continue
    c="$_c"; [[ "$c" == "-" || -z "$c" ]] && c="$_f"
    if [[ -n "$repo" && -n "$c" && "$c" != "-" ]] && repo_contains_path "$repo" "$(_fleet_phys "$c")"; then
      continue
    fi
    n=$((n + 1))
    labels+="${labels:+ }${STATUS_WS_LABEL[$wsid]:-${wsid:--}}"
  done <<< "$STATUS_SNAP"
  (( n > 0 )) || return 0
  printf ' · 他仓同名 %d 个（ws=%s）' "$n" "$labels"
}

cmd_status() {
  local a
  # B1（BR3/BR7）：身份/归属/忙闲全部来自结构化事实 ⇒ 快照**每命令一次**
  #   （≤1 次 pane list / agent list；逐名查询会 7×2 次 CLI，且同命令内两份快照不一致 = 新 flake 源）
  if ! term_snapshot >/dev/null; then
    if _term_app_backend; then
      printf '需要 desktop app core：hc ls / hc get 不可用（核对 desktop app 是否在运行、HC_TERMINAL_SOCKET 是否有效）—— 修好后重试\n' >&2
    else
      printf '需要 herdr server：pane list / agent list 不可用（核对 `herdr --session %s server` 是否在跑、protocol 是否 22）—— 修好后重试\n' "${HERDR_SESSION:-?}" >&2
    fi
    exit 3
  fi
  # BR8：parse 的角色事实表（常驻 id + 锚根下合法卡 role）；**一次** glob，不再二次 card_role_set
  fleet_roles_init --cards
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
  # S13：herdr 快照（12 列）+ workspace label 表（≤1 次 workspace list；快照已由入口建好）
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
        if _term_app_backend; then
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
  
  if _term_app_backend; then
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
    (( a_ok )) || printf '  · %-14s 未运行（ensure 拉起）\n' "$a"
  done
  # D5：分节标题示例带上全名写法 —— **仅当在场确有带 scope 的会话**（scope 为空时逐字保留旧标题 ⇒ BR1）
  if (( any_scoped )); then
    echo "== 任务派生会话（--task 拉起，如 rd-be(T1) / rd-be2(T1)；含旧式 @ 名）=="
  else
    echo "== 任务派生会话（--task 拉起，如 rd-fe(T1) / rd-infra(T1)）=="
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
    if _term_app_backend; then
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

# ---------------------------------------------------------------------------
# 回收已完成会话：闸门（tasks-state 已推进 + 无在跑 turn）+ 落地（pane/session）
cmd_close() {
  local force="$1" task="$2" target="${3:-}"
  [[ -n "$target" ]] || die "close 需要目标：角色别名或会话名（如 rd-be / qa(T1) / 旧形 qa-T1）"
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
      if [[ -n "$task" && -n "$p_task" && "$task" != "$p_task" ]]; then
        die "目标名与 --task 不一致：$target（名字里是 $p_task，--task 是 $task；该怎么办：二选一）"
      fi
      [[ -n "$p_task" ]] && task="$p_task"
      role="$p_role"; kindc="$p_kind"
      # 裸名/带槽位名 + --task ⇒ 别名重建（新形）；否则精确名原样
      if [[ -n "$task" && -z "$p_task" ]]; then
        exact="$(fleet_name_build "$( [[ "$p_kind" == "card" ]] && printf card || printf derived )" "$p_role" "$p_num" "$task")"
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
      die "未知角色或会话名: $target（可用角色: ${ROLE_ORDER[*]}；常驻名 = <角色>[N]（N=2..9）；派生名 = <角色>(<任务号>)；旧形（<角色>-<任务号> / <角色>@<scope>）仍可回收；亦可用 close --task <编号> <角色>；下游卡角色需在本仓锚下存在 .agents/prompts/<role>.md）"
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
    exact="$(fleet_name_build "$kindc" "$role" "" "$task")"
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
      while IFS=$'\t' read -r _srcn _sr_p _ _sr_c _sr_f _; do
        [[ "$_srcn" == "$exact" ]] || continue
        _sr_c="$_sr_c"; [[ "$_sr_c" == "-" || -z "$_sr_c" ]] && _sr_c="$_sr_f"
        [[ "$_sr_c" == "-" ]] || repo_contains_path "$anchor" "$(nao_phys_path "$_sr_c")" || continue
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
      elif (( ${#cands_in[@]} > 1 )); then
        die "close 目标歧义：$exact 在本仓锚（$anchor）内有 ${#cands_in[@]} 个同 (角色,任务) 的会话：$(printf '%s ' "${cands_in[@]}")（该怎么办：先 intercom({action:'list'}) 人工核对并关掉多余的会话；或显式写带槽位号的名字）"
      else
        # 本仓锚内无候选：若场里有同 (role,task) 的非本仓会话 ⇒ D4：不回收 + 指路（禁全局首命中）
        if (( ${#cands[@]} > 0 )); then
          log "$exact 未运行（本仓锚内无该会话；场内有同名/同 core 会话：$(printf '%s ' "${cands[@]}")）→ 不在本仓回收；如确需回收请到对应仓执行 close"
          return 0
        fi
        name="$exact"; scope=""
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
  term_reclaim "$name" "$repo" "$force" "$role" "$scope" "${tgt:-$role}"
  return $?
}

# ---------------------------------------------------------------------------
# 拆场入口（B3）：herdr = session stop+delete（实现 `_term_herdr_cleanup`）；显式目标守卫在入口（rc=2）。
cmd_cleanup() {
  term_cleanup "${SESSION_ARG:-}" "$FORCE"
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# ensure 相位 1 的「槽位/放置」判据（T554 · 判据 §一.4 / §二）
#   · 槽位占用的单一判据：目标 workspace 内、名字经 parse 后 (role,num) 相同者占位
#     （v2：slot = 第 4 段，空 = 槽位 1；旧形不占 v2 槽位 —— 旧会话只读、可并存）。
#   · 本批预留：同批两个 pm ⇒ pm / pm2（`_T_RSV_*` 只服务本命令，禁全局状态跨命令泄漏）。
#   · 数据源：本命令快照（≤1 workspace list + ≤1 pane list）。
# ---------------------------------------------------------------------------
declare -a _T_RSV_WS=() _T_RSV_NAME=() _T_RSV_ROLE=() _T_RSV_NUM=()
declare -A _DEP_SCOPE_WARNED=()

# 目标 repo 存在弃用文件 `.agents/fleet-scope` ⇒ 恰一行 warn（每 repo 一次；本版忽略）
_dep_warn_scope_file() {  # <repo_phys>
  local repo="${1-}" phys
  [[ -n "$repo" ]] || return 0
  phys="$(_fleet_phys "$repo")"
  [[ -e "$phys/.agents/fleet-scope" || -L "$phys/.agents/fleet-scope" ]] || return 0
  [[ -n "${_DEP_SCOPE_WARNED[$phys]:-}" ]] && return 0
  _DEP_SCOPE_WARNED["$phys"]=1
  _fleet_deprecated_warn fleet-scope
  return 0
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

# 快照内某 workspace 的 pane cwd 是否**全在**目标仓内（含空 ws ⇒ true）
_ensure_ws_panes_in_repo() {  # <wsid> <repo_phys> → 0 全部在仓内 / 1 有 pane 在仓外
  local wsid="${1-}" repo="${2-}" line
  local -a cwds=()
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      [[ "$_TP_WS" == "$wsid" ]] || continue
      cwds+=("${_TP_FGCWD:-$_TP_CWD}")
    done
  fi
  (( ${#cwds[@]} )) || return 0
  local c ident
  ident="$(_repo_identity "$repo")"
  for c in "${cwds[@]}"; do
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
      if (( _TERM_PLACE_CACHE )); then
        wsid="${_TERM_PLACE_WS_BY_LABEL[$cand]:-}"
        if [[ -n "$wsid" ]]; then
          if _ensure_ws_panes_in_repo "$wsid" "$repo"; then printf '%s\n' "$cand"; return 0; fi
        else
          printf '%s\n' "$cand"; return 0
        fi
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
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      [[ -n "$_TP_LABEL" ]] || continue
      [[ "$_TP_WS" == "$wsid" ]] || continue
      name="$_TP_LABEL"
      out="$(fleet_name_parse "$name")"
      [[ "$out" == "OK "* ]] || continue
      IFS=',' read -r k r t s <<< "${out#OK }"
      [[ "$r" == "$role" && "$s" == "$num" ]] && return 0
    done
  else
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      out="$(fleet_name_parse "$name")"
      [[ "$out" == "OK "* ]] || continue
      IFS=',' read -r k r t s <<< "${out#OK }"
      [[ "$r" == "$role" && "$s" == "$num" ]] && return 0
    done < <(visible_session_names)
  fi
  return 1
}

# 派生任务复用：目标 ws 内已有同 (role,task) 的 v2 名字 ⇒ 打印该名字（同槽位同 task = same）
_ensure_task_name_in_ws() {  # <wsid> <role> <task>
  local wsid="${1-}" role="${2-}" task="${3-}" name out k r t s line
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      name="$_TP_LABEL"
      [[ -n "$name" && "$_TP_WS" == "$wsid" ]] || continue
      out="$(fleet_name_parse "$name")"
      [[ "$out" == "OK "* ]] || continue
      IFS=',' read -r k r t s <<< "${out#OK }"
      [[ "$r" == "$role" && "$t" == "$task" ]] && { printf '%s\n' "$name"; return 0; }
    done
  else
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      out="$(fleet_name_parse "$name")"
      [[ "$out" == "OK "* ]] || continue
      IFS=',' read -r k r t s <<< "${out#OK }"
      [[ "$r" == "$role" && "$t" == "$task" ]] && { printf '%s\n' "$name"; return 0; }
    done < <(visible_session_names)
  fi
  return 0
}

# 选槽位：派生优先复用已有次槽位（≥2），否则取最小空闲槽位；常驻取最小空闲。全占 ⇒ fail（rc=1）。
_ensure_pick_num() {  # <wsid> <role> <task> <kind> → stdout num（空 = 槽位 1）
  local wsid="${1-}" role="${2-}" task="${3-}" kind="${4-}" n found="" name line out k r t s
  # 收集已占槽位
  local -a occ=()
  if (( _TERM_PLACE_CACHE )); then
    for line in "${_TERM_PLACE_PANE_ROWS[@]:-}"; do
      [[ -n "$line" ]] || continue
      _term_place_pane_fields "$line"
      name="$_TP_LABEL"
      [[ -n "$name" && "$_TP_WS" == "$wsid" ]] || continue
      out="$(fleet_name_parse "$name")"
      [[ "$out" == "OK "* ]] || continue
      IFS=',' read -r k r t s <<< "${out#OK }"
      [[ "$r" == "$role" ]] && occ+=("${s:-1}")
    done
  else
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      out="$(fleet_name_parse "$name")"
      [[ "$out" == "OK "* ]] || continue
      IFS=',' read -r k r t s <<< "${out#OK }"
      [[ "$r" == "$role" ]] && occ+=("${s:-1}")
    done < <(visible_session_names)
  fi
  local i
  for i in "${!_T_RSV_NAME[@]}"; do
    [[ -z "${_T_RSV_WS[$i]:-}" || "${_T_RSV_WS[$i]}" == "$wsid" ]] || continue
    [[ "${_T_RSV_ROLE[$i]}" == "$role" ]] && occ+=("${_T_RSV_NUM[$i]:-1}")
  done
  if [[ -n "$task" ]]; then
    # 派生复用已有次槽位（最小 ≥2）
    local best=""
    for n in "${occ[@]:-}"; do
      [[ "$n" =~ ^[2-9]$ ]] || continue
      [[ -z "$best" || "$n" -lt "$best" ]] && best="$n"
    done
    if [[ -n "$best" ]]; then printf '%s\n' "$best"; return 0; fi
  fi
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
  term_place_reset
  if ! term_place_prime; then
    if _term_app_backend; then
      die "ensure 中止：app 放置快照不可用（hc ls / doc.get 失败；核对 desktop app 窗口后重试）"
    fi
    die "ensure 中止：herdr 放置快照不可用（workspace list / pane list 失败；核对 server 后重试）"
  fi

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
        wsid="${_TERM_PLACE_WS_BY_LABEL[$place]:-}"
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
          disp="$(fleet_name_build card "$CARD_ROLE" "$slot" "$task")"
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
      wsid="${_TERM_PLACE_WS_BY_LABEL[$place]:-}"
      if [[ -n "$forced_num" ]]; then
        slot="$forced_num"
        if [[ -n "$task" ]]; then disp="$(fleet_name_build derived "$NAME" "$slot" "$task")"
        else disp="$(fleet_name_build resident "$NAME" "$slot" "")"; fi
      elif [[ -n "$task" ]]; then
        # 同槽位同 task 已在 ⇒ same（复用该名字；相位 2 判重会跳过）
        disp="$(_ensure_task_name_in_ws "$wsid" "$NAME" "$task")"
        if [[ -n "$disp" ]]; then
          slot=""; pout_tmp="$(fleet_name_parse "$disp")"
          IFS=',' read -r _p_kind _p_role _p_task slot <<< "${pout_tmp#OK }"
        else
          slot="$(_ensure_pick_num "$wsid" "$NAME" "$task" "derived")" \
            || die "ensure 中止：角色槽位已满（$NAME 的 2..9 全占；该怎么办：先 close 无用会话再重试）"
          disp="$(fleet_name_build derived "$NAME" "$slot" "$task")"
        fi
      else
        slot="$(_ensure_pick_num "$wsid" "$NAME" "" "resident")" \
          || die "ensure 中止：角色槽位已满（$NAME 的 2..9 全占；该怎么办：先 close 无用会话，如 close ${NAME}2）"
        disp="$(fleet_name_build resident "$NAME" "$slot" "")"
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
        if _term_app_backend; then
          warn "$disp 已在运行（终端 name + status 事实命中），跳过；确需重开请加 --force"
        elif [[ "$NAO_TERMINAL" == "herdr" ]]; then
          warn "$disp 已在运行（pane label + 结构化事实命中），跳过；确需重开请加 --force"
        else
          warn "$disp 已在运行（终端标题/名册命中），跳过；确需重开请加 --force"
        fi
        SPAWN_SKIP=$((SPAWN_SKIP + 1))
        continue
      fi
    fi
    if [[ -n "${t_cards[$i]}" ]]; then
      spawn_one "$disp" "$repo" "$model" "${t_cards[$i]}" "${t_roles[$i]:-}" "" "$force" "${t_labels[$i]}" ""
    else
      spawn_one "$disp" "$repo" "$model" "" "${t_roles[$i]:-}" "${t_prompts[$i]:-}" "$force" "${t_labels[$i]}" ""
    fi
  done
  term_place_reset
  # 恰一行摘要，三类计数（成功/跳过/失败）
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
# T554/D7：`--fleet` / `--scope` 已弃用 —— 只保留「给参但空 ⇒ 用法错」守卫；非空仅打一行 warn 后丢弃（放置键恒为仓基键）
CLI_FLEET=""; SCOPE_SEEN=false; FLEET_SEEN=false
# T537：目标级修饰符（--card / --as）的绑定状态 —— 只作用于**其后第一个 positional**（BR11）
TARGET_CARD=(); TARGET_AS=(); PEND_CARD=false; PEND_AS=""; LAST_CARD_IDX=-1
_need_ensure() { [[ "$CMD" == "ensure" ]] || die "$1 仅用于 ensure 子命令：nao-fleet.sh ensure [<角色>[@<code>]] [--card <卡路径>[@<repo>]] [--task <编号>] [--as <会话名>]"; }
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
      WARNS="$(grep '^  !' "$REPFILE" | grep -v -e '^  ! codegraph ' -e '^  ! PRD 结构' | grep -c . || true)"
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
      # B1（BR1 六条机械保证之「check 打印生效后端」）：唯一后端 ⇒ 恒打印（与 -v 报告同文案）
      if [[ "$NAO_TERMINAL" == "app" ]]; then
        echo '  · 生效后端 NAO_TERMINAL=app（第二后端；status/ensure/close/cleanup 走门面；core 由 desktop app 管理；session-start 不适用）'
      else
        echo '  · 生效后端 NAO_TERMINAL=herdr（唯一后端；#96 二期 B4：status/ensure/close/cleanup 走门面；session-start 起 server；台账 0 条）'
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