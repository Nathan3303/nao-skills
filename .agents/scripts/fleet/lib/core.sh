# =============================================================================
# fleet/lib/core.sh — 基础层：路径锚 / 版本 / 日志退出 / 纯路径谓词
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：无（最底层）
# 本层只放「谁都要用、且不依赖任何后端/清单/名册」的东西：SCRIPT_DIR 等路径锚、
# MIN_PI_VERSION（单源）、log/warn/die、codegraph 与 ensure 文案常量、
# nao_phys_path / repo_contains_path / repo_anchor_roots / _fleet_phys 等无副作用谓词。
# =============================================================================
# ---- 路径锚（唯一解析点；本文件位于 <包根>/.agents/scripts/fleet/lib/）----
FLEET_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLEET_DIR="$(cd "$FLEET_LIB_DIR/.." && pwd)"
SCRIPT_DIR="$(cd "$FLEET_DIR/.." && pwd)"
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
