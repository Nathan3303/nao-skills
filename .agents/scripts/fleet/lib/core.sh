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
# T594：包根环境变量 —— `NAO_FLEET` **优先**，`NAO_SKILLS` 为兼容别名（一个版本后弃用；弃用期两者都给时以 NAO_FLEET 为准）。
SKILLS_DIR="${NAO_FLEET:-${NAO_SKILLS:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"
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
1) 本地 pin：读 .pi/settings.json 里 nao-fleet 的版本（X）；本仓若无该文件或无此 pin ⇒ 直接走 4 的情形 ④（不要说成必然有 pin）。
2) 远端最新版：npm view nao-fleet version --fetch-timeout=5000（内置 5s 超时；不要用外部 timeout 命令，macOS 原生没有；超时/报错 ⇒ 情形 ③）。
3) 仅当有新版（Y 大于 X）才取要点：gh release view v<Y>（要点压成不超过两句，不要贴全文）；无 gh 或取不到 ⇒ 情形 ⑤。
4) 只输出以下**恰好一行**（按 ①–⑤ 顺序命中即止，不解释、不追加）：
   ① 有新版：当前 X → 可升 Y（要点）。要升吗？
   ② 已最新：版本检查：已是最新 X。
   ③ 离线或超时：版本检查：离线或超时，跳过（可稍后手动 npx nao-fleet --version 核对）。
   ④ 未检测到下游 pin：版本检查：未检测到下游 pin（本仓为机制源），跳过。
   ⑤ 无 gh 只报版本号：版本检查：当前 X → 可升 Y（要点取不到，见 https://github.com/Nathan3303/nao-fleet/releases）。要升吗？
5) 硬约束：检查阶段只读；**未获我同意前不要改任何文件、不要升级**（不改 .pi/settings.json、不跑 pi install / pi update）。
6) 只有我明确同意后才按序执行：pi install -l npm:nao-fleet@<Y>（若提示安装脚本授权，停下来交给我确认，不要自行放行）→ pi update --extensions → 提醒我「本轮会话仍是旧角色卡，建议重开」。
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
# 舰队命名契约 v3（T571 · ADR 2026-11-25-term-facade-neutral-contract · 唯一构造/解析点）
#
#   放置键 = 仓（`place_key_label`，见下）；**名字不含位置**（`@` 段已删除）。
#   会话名 = `<role>[<N>]`（N 单字符 2..9，空 = 槽位 1）；**task 不进身份**，只落元数据
#     （app `nao.task` / `nao.name` label；herdr sidecar）。构造器多传 task ⇒ fail loud。
#   预算：name ≤48 · role 段（含 N）≤32（卡）。
#   只读兼容：v2 `<role>[<N>](<task>)` / legacy `<role>-<task>` / `<role>-<task>@<scope>`
#     （status/close 可认，task 仍从名字解析；ensure 永不生成这些写形态）。
#   文法唯一判据（R1）：槽位紧贴单字符 + 角色**最长匹配** + 按**首个分隔符**分派：
#     `(` ⇒ v2 只读 · `-` ⇒ 旧形只读 · `@` ⇒ legacy scope（只读）。三集合不相交。
#   parse 输出：新形 `OK <kind>,<role>,<task>,<num>` · 旧形 `LEGACY OK <kind>,<role>,<task>,<scope>` · 非法 `ERR`
#   （第 4 段语义按前缀区分：新形 = 槽位号、旧形 = scope —— 调用点禁把 legacy 值当 num；
#     v3 写入面只产生 task 为空的新形）。
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

# ---------------------------------------------------------------------------
# 会话元数据（命名契约 v3 · ADR 2026-11-25 决策一）：task 不进身份，只落元数据。
#   herdr 无键值 label ⇒ 本地 sidecar：<root>/<workspace_ref>/<handle>，内容 `task=<id>` / `name=<原始名>`。
#   app 用 labels `nao.task` / `nao.name`（写读在 term-app.sh；本组只管 herdr 的持久面）。
#   纪律：读写失败只 warn、**不改 rc**（元数据缺失不得阻断启动）；原子写 = 临时文件 + mv。
#   孤儿清理：任何读快照的入口（status / ensure）拿到 handle 集合后调用 fleet_meta_gc。
# ---------------------------------------------------------------------------
# 舰队自有状态根（T573）：`session-meta/`（herdr sidecar）与 `sessions/`（Pi session 记录）同处。
#   `NAO_FLEET_META_DIR` 覆盖根目录 ⇒ 两者一起搬家（测试用隔离 HOME 即可）。
FLEET_STATE_ROOT="${NAO_FLEET_META_DIR:-${HOME:-/tmp}/.local/state}/nao-fleet"
FLEET_META_ROOT="$FLEET_STATE_ROOT/session-meta"

# workspace_ref = <后端上下文句柄>__<workspace_id>：同一个 meta 根下可能有多个 herdr session，
#   只用 workspace_id 会让 A 会话的 status 把 B 会话的 sidecar 当孤儿删掉（handle 只在 session 内唯一）。
fleet_meta_wsref() {  # <workspace_id> → <session>__<workspace_id>
  printf '%s__%s\n' "${HERDR_SESSION:-${HC_SCOPE:-_}}" "${1-}"
}

fleet_meta_write() {  # <workspace_ref> <handle> <task> <name> → 0 / 1（仅 warn）
  local ws="${1-}" h="${2-}" task="${3-}" name="${4-}" dir tmp
  [[ -n "$ws" && -n "$h" ]] || { warn "元数据未落盘：缺 workspace_ref/handle（ws=$ws handle=$h）"; return 1; }
  dir="$FLEET_META_ROOT/$ws"
  mkdir -p "$dir" 2>/dev/null || { warn "元数据目录不可建：$dir（task=$task；不阻断启动）"; return 1; }
  tmp="$dir/.$h.tmp.$$"
  if ! { printf 'task=%s\n' "$task"; printf 'name=%s\n' "$name"; } > "$tmp" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    warn "元数据写入失败：$tmp（task=$task；不阻断启动）"; return 1
  fi
  if ! mv -f "$tmp" "$dir/$h" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null || true
    warn "元数据落位失败：$dir/$h（task=$task；不阻断启动）"; return 1
  fi
  return 0
}

fleet_meta_read() {  # <workspace_ref> <handle> [key=task] → 值（缺失 ⇒ 空，rc=0）
  local f="$FLEET_META_ROOT/${1-}/${2-}" key="${3:-task}"
  [[ -f "$f" ]] || return 0
  sed -n "s/^${key}=//p" "$f" 2>/dev/null | head -1
  return 0
}

fleet_meta_remove_handle() {  # <handle> —— close/cleanup 即时删（幂等；失败仅 warn）
  local h="${1-}"
  [[ -n "$h" && -d "$FLEET_META_ROOT" ]] || return 0
  find "$FLEET_META_ROOT" -mindepth 2 -maxdepth 2 -type f -name "$h" -delete 2>/dev/null \
    || warn "元数据删除失败：handle=$h（不影响回收结果）"
  return 0
}

fleet_meta_gc() {  # stdin = 当前 live handle（每行一个）→ 删不在集合内的 sidecar（幂等；失败仅 warn）
  local -A live=()
  local h f
  while IFS= read -r h; do [[ -n "$h" ]] && live["$h"]=1; done
  [[ -d "$FLEET_META_ROOT" ]] || return 0
  local sess="${HERDR_SESSION:-}" rel ref
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    rel="${f#"$FLEET_META_ROOT"/}"; ref="${rel%%/*}"
    # 只清**当前会话**的 sidecar（其他 session 的 handle 集合不在本次快照里，删了就是误伤）
    [[ -z "$sess" || "$ref" == "$sess"__* ]] || continue
    h="${f##*/}"
    [[ -n "${live[$h]:-}" ]] && continue
    rm -f "$f" 2>/dev/null || warn "元数据孤儿清理失败：$f（不影响本次判定）"
  done < <(find "$FLEET_META_ROOT" -mindepth 2 -maxdepth 2 -type f 2>/dev/null)
  return 0
}

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
