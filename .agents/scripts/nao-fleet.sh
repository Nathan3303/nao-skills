#!/usr/bin/env bash
# =============================================================================
# nao-fleet.sh — 按角色一键拉起 pi 会话窗口（nao 团队工具箱）
#
# 运行前提（ADR 2026-10-27-strict-tmux-pi · 唯一路径）
#   必须在 tmux 会话内（$TMUX 非空且 tmux 命令可用）· pi ≥ 1.4.0（check 断言）
#   非 tmux ⇒ ensure/status/close 一律 exit 3 + 一行提示，且不建 session/pane/lock、不写状态（BR3）
#   cleanup 豁免本前提：其正常场景就是「非 tmux 的隔离实验场」（env -u TMUX ... -S <socket>）
#
# 用法
#   nao-fleet.sh check [--strict] [-v]            静态体检：roles.yaml/缩进/EOL/角色卡/交叉引用/PR 模板/白名单/布局/tmux+pi 前提
#                                                 默认摘要 2 行：摘要行 + codegraph 状态行（四态之一）；-v 展开完整报告（六态全展开）；失败始终展开
#   nao-fleet.sh status                           角色会话在线状态（按 tmux 终端标题/名册判定；权威名单见 intercom list）
#   nao-fleet.sh ensure <别名>[@<repo>] [更多...]  拉起角色窗口（默认工作区=roles.yaml workspace）
#   nao-fleet.sh ensure -m <model> <别名>...       显式指定模型（须命中白名单）
#   nao-fleet.sh ensure --task <编号> <别名>[@<repo>]   任务派生会话：--name <别名>-<编号>（并行隔离，避免同名冲突）
#   nao-fleet.sh ensure --force <别名>...          忽略"已在运行"判重
#   nao-fleet.sh close <别名|派生会话名> [--task <编号>] [--force]
#                                                 回收已完成会话（派生名如 rd-be-T1；跨仓定位；定位失败/名册报在线但无句柄 ⇒ 非 0 + 诊断）
#                                                 （闸门：在跑 turn / tasks-state 未推进 → 拒绝，--force 跳过；
#                                                  常驻缺席而其派生在场 ⇒ 目标歧义拒绝，T516 AC3）
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
#   当前：pm / arch-designer(arch) / rd-fe / rd-be / qa / rd-infra(infra)
#
# 环境变量
#   NAO_TMUX_LAYOUT=main-row2|main-col|grid   tmux 布局（默认 main-row2）
#   NAO_TMUX_MAIN_WIDTH=<10..90>             主 pane 宽度百分比（默认 35；main-row2/main-col 共用）
#   NAO_TMUX_MIN_PANE_WIDTH=<10..80>         最小非主 pane 列宽守卫（默认 30；低于则回退）
#   NAO_TMUX_HOST_WINDOW=<window>            显式指定派生宿主窗口（默认自动：$TMUX_PANE→名册；允许跨 session，建议 @id 形式）
#   NAO_SKILLS=<dir>                          nao 机制包根目录（默认 <脚本>/../..；项目内 shim 会显式指向包根）
#   NAO_MODEL_WHITELIST=<glob,...>            -m 白名单（默认空=不校验，支持 glob）
#   NAO_CLOSE_BUSY_PATTERN=<ERE>             close 的在跑 turn 判定正则（默认内置 pi 状态行标记）
#   NAO_TASKS_STATE=<path>                   任务状态文件（默认 docs/tasks-state.md，供残留检测/回收闸门）
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

MANIFEST="$SKILLS_DIR/.agents/roles.yaml"
CARD_MAX_LINES=200
ROLE_ORDER=()
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
# 状态文案单点（CG_MSG_*）：用例断言只认**固定前缀 + 命令子串**，不断言整行（防文案微调误伤）。
CG_MSG_UNDECLARED='codegraph 插件未声明（装法：pi install npm:@sean_pedersen/pi-codegraph；定位回退 grep）'
CG_MSG_NO_CLI='codegraph 插件已声明但 CLI 不在 PATH（装：npm i -g @colbymchenry/codegraph；回退 grep -rn + 行段）'
CG_MSG_NO_INDEX='codegraph 已就绪但当前仓无索引（codegraph init；索引后每会话约 +70–90MB PSS）'
CG_MSG_READY='codegraph 齐备'
CG_MSG_READY_SHORT='codegraph 齐备（索引新鲜度用 -v 查）'
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
#   full=0（默认 check）：零外部进程（两次文件读 + command -v + 一次目录判定，AC11）
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
# 输出当前版本（缺失/不可解析也给占位），rc 0 = 满足 ≥1.4.0；失败只置 rc，由 check 聚合后继续跑完其余体检。
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
  if (( c1 > 1 )); then return 0; fi
  if (( c1 < 1 )); then return 1; fi
  if (( c2 >= 4 )); then return 0; fi
  return 1
}

# ---------------------------------------------------------------------------
resolve_role() {
  local id="${ALIAS_ROLE[$1]:-}"
  [[ -n "$id" ]] || die "未知角色: $1（可用: ${ROLE_ORDER[*]}）"
  NAME="$id"
  PROMPT="${ROLE_CARDS[$id]}"
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
intercom_cwd_for() {
  local n c
  while IFS=$'\t' read -r n c; do
    [[ "$n" == "$1" ]] && { printf '%s\n' "$c"; return 0; }
  done < <(intercom_roster)
  return 0
}

# 会话所在的 tmux pane。三层后备（标题可被外部改写，如 "pi:c"）：
#   ① 终端标题契约 "π - <会话名> - <repo basename>"（pi 自设；最快）
#   ② pi-intercom 名册 tmuxPane（注册时读 $TMUX_PANE；与标题改名无关，权威）
#   ③ 本仓「未被认领 pi pane」唯一兜底（启发式：pane_current_command=pi 且
#      pane_current_path=repo；歧义时 warn，不猜）
# repo（可选）：给出时要求标题 basename / 名册 cwd / pane 当前路径一致，避免跨项目同名互串。
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

# ---- ④ 路径句柄（app-id/class）已随宿主阶梯删除（ADR 2026-10-27-strict-tmux-pi）---------

# 派生会话在场检测（T516 AC3）：visible_session_names 中形如 <name>-<非空后缀> 者。
# 用于 close <常驻名> 时判目标歧义：常驻精确句柄缺席而其派生在场 ⇒ 拒绝 + 指路（禁静默谎报「未运行」）。
derived_in_field() {  # <name> → 派生名列表（每行一个；空 = 无）
  local n
  while IFS= read -r n; do
    [[ "$n" == "$1"-?* ]] && printf '%s\n' "$n"
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
  local name="$1" repo="${2:-}"
  if intercom_online "$name" "$repo"; then return 0; fi
  if [[ -n "$(find_pane_for "$name" "$repo")" ]]; then return 0; fi
  # T516 #1（=锚）：tmux 会话名唯一前缀匹配曾误命中派生 nao-<名>-<任务>（T515 V4 实证）⇒ 一律 =nao-<名>。
  if command -v tmux >/dev/null 2>&1 && tmux has-session -t "=nao-$name" 2>/dev/null; then return 0; fi
  return 1
}

# 本机可见的会话名（tmux 标题 + tmux 会话 + 名册），供 status 枚举；已去重
# ⚠️ 每条枚举 `|| true`：set -e + pipefail 下 `tmux`（无 server 时 rc=1）会中断其余枚举，
#    使「名册回退」永远走不到 —— 必疾。
visible_session_names() {
  { if command -v tmux >/dev/null 2>&1; then
      { tmux list-panes -a -F '#{pane_title}' 2>/dev/null || true; } \
        | sed -n "s/^${PI_TITLE} - \([A-Za-z0-9_-]*\) - .*/\1/p"
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

# 该 pane 是否显示在跑 turn（启发式：扫末 12 行找状态行标记；回执/产物以 PM 核对清单为准）
# ⚠️ 窗口不能只用末 3 行：pi 状态行（如 "⠦ Working"）上方还有分隔线，实测会落到第 4 行以外。
# 真伪由 roster 状态(intercom_status_for)交叉；此处仅作 pane 级补充。
pane_busy() {
  local pane="$1" window
  window="$(tmux capture-pane -p -t "$pane" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -12)"
  [[ -n "$window" ]] || return 1
  grep -qE "$CLOSE_BUSY_PATTERN" <<< "$window"
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
#   1 | 2 | 4
#   1 | 3 | 5
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

# ---------------------------------------------------------------------------
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
  [[ -n "$HOST_WINDOW" ]] || return 0
  # 窄窗口/宿主上限会让 split-window 失败（no space for new pane，含宿主窗已关竞态）；
  # 捕获后 warn 并继续，不因单个 pane 失败中断整轮 ensure。
  local serr
  if ! serr=$(tmux split-window -h -t "$HOST_WINDOW" "$wrapped" 2>&1); then
    warn "pane 创建失败（宿主窗口 $HOST_WINDOW 过窄/已关或已达上限）：${serr:-<no message>}"
    warn "  已跳过该 pane，其余角色继续拉起；可放大窗口后重跑 ensure"
    return 0
  fi
  apply_tmux_layout
}

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
  local name="$1" repo="$2" model="$3" card prompt_file inner
  card="$PROMPTS_DIR/$PROMPT"
  [[ -f "$card" ]] || die "角色卡不存在: $card"
  [[ -d "$repo" ]] || die "工作区不存在: $repo"

  # 前提已由入口 require_tmux 硬校验（exit 3）；此处只走唯一路径（BR1/BR3）。
  prompt_file="$(build_system_prompt "$card")"
  inner="cd $(printf %q "$repo") && export CODEGRAPH_TELEMETRY=0 && exec pi --name $(printf %q "$name")"
  [[ -n "$model" ]] && inner+=" --model $(printf %q "$model")"
  inner+=" --append-system-prompt $(printf %q "$prompt_file")"
  ( sleep 60; rm -f -- "$prompt_file" ) & disown 2>/dev/null || true

  # 拉起（pane 级失败 = warn + 跳过该角色，D-A）；成功后打印「已拉起」
  spawn_tmux "$name" "$inner"
  log "[tmux] 已拉起 $name @ $repo${model:+（model=$model）}（layout=$TMUX_LAYOUT）"
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

  echo "== CodeGraph（四态检测：全部 warn，永不计入 rc；默认不 fork CLI）=="
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

  echo "== 运行前提（tmux 内 + pi ≥1.4.0；AC1/AC3）=="
  if command -v tmux >/dev/null 2>&1; then
    echo '  ✓ tmux 可用（唯一受支持宿主）'
  else
    printf '  ✗ tmux 缺失（ensure/status/close 将 exit 3）\n'; rc=1
  fi
  if [[ -n "${TMUX:-}" ]]; then
    echo "  ✓ 当前在 tmux 会话内（$(tmux display-message -p '#S' 2>/dev/null || echo '?')）"
  else
    printf '  · 当前不在 tmux 会话内：ensure/status/close 将 exit 3（先 `tmux new -s nao`）；纯静态体检可照跑\n'
  fi
  local pi_cur
  if pi_cur="$(pi_version_check)"; then
    printf '  ✓ pi 版本 %s ≥ 1.4.0\n' "$pi_cur"
  else
    printf '  ✗ pi 版本 %s < 1.4.0\n' "$pi_cur"; rc=1
  fi

  echo "== tmux 布局 =="
  if [[ -z "${TMUX:-}" ]]; then
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
cmd_status() {
  local a
  intercom_list_json >/dev/null 2>&1 || true   # 预热名册缓存（后续子 shell 复用）
  echo "== 角色会话在线状态（权威名单见 intercom({action:'list'})；本表按 tmux 终端标题/名册判定）=="
  for a in "${ROLE_ORDER[@]}"; do
    if running "$a" "${ROLE_WS[$a]:-}"; then
      printf '  ✓ %-14s 在线（--name %s；卡片 %s）\n' "$a" "$a" "${ROLE_CARDS[$a]}"
    else
      printf '  · %-14s 未运行（ensure 拉起）\n' "$a"
    fi
  done
  echo "== 任务派生会话（--task 拉起，如 rd-be-T1 / rd-infra-T1）=="
  local found=0 dname role id cls tag
  while IFS= read -r dname; do
    [[ -n "$dname" ]] || continue
    id=""
    for role in "${ROLE_ORDER[@]}"; do [[ "$dname" == "$role-"* ]] && { id="${dname#"$role"-}"; break; }; done
    [[ -n "$id" ]] || continue
    cls="$(task_state_class "$id")"
    tag=""
    case "$cls" in
      closed)    tag="  ! 残留（$id 已归档）→ close --task $id ${dname%-*}" ;;
      active)    tag="  · $id 进行态" ;;
      mentioned) tag="  ? $id 仅散文提及（非表内记录）→ 核对后 close --task $id ${dname%-*}" ;;
      absent)    tag="  ! 残留（tasks-state 无 $id 记录）→ 核对后 close --task $id ${dname%-*}" ;;
    esac
    printf '  · %s%s\n' "$dname" "$tag"
    found=1
  done < <(visible_session_names)
  (( found )) || echo '  （无）'
  [[ -f "$TASKS_STATE" ]] || echo "  （$TASKS_STATE 不存在，残留判定已跳过）"
  # T525：子代理会话（pi-subagents）不属舰队会话身份模型 —— 派生节后独立一行、只计数不列名、N=0 不打印（BR3/BR6）。
  local nsub
  nsub="$(subagent_in_field)"
  (( nsub > 0 )) && printf '  · 另有 %d 个子代理会话（subagent-*）· 生命周期由 pi-subagents 管理，nao 不回收\n' "$nsub"
  # 标题被改写/无名的 pi pane：非静默——显式列出，供人工核对
  local -a orph=()
  local pn pt
  while IFS=$'\t' read -r pn pt; do
    [[ -n "$pn" ]] && orph+=("$pn($pt)")
  done < <(unattributed_pi_panes)
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
  local name repo cls bus pane pids st tgt a best=""
  intercom_list_json >/dev/null 2>&1 || true   # 预热名册缓存

  # ---- 目标解析：别名/canonical id | 派生会话名 <角色>-<编号> ----
  # 派生名（如 qa-T508）可直接作目标；也兼容 close --task T508 qa 与 close --task T508 qa-T508。
  tgt=""
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
    die "未知角色或派生会话名: $target（可用角色: ${ROLE_ORDER[*]}；派生名形如 rd-be-T1 / qa-T1，亦可用 close --task <编号> <角色>）"
  fi
  resolve_role "$tgt"
  name="$NAME"
  [[ -n "$task" ]] && name="${NAME}-${task}"
  # 目标仓：名册 cwd 优先（跨仓会话真实仓），否则回退 roles.yaml workspace / 当前目录
  repo="$(intercom_cwd_for "$name")"
  [[ -n "$repo" ]] || repo="${ROLE_WS[$NAME]:-$PWD}"

  if [[ -z "$task" ]]; then
    warn "常驻会话 $name：任务闭环后应 ensure --force 重开，而非回收（仅在本批不再需要该角色时回收）"
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
    mapfile -t dfield < <(derived_in_field "$name")
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

# ---------------------------------------------------------------------------
# 实验场安全清理入口（T516 #2 · D2 形态 A）：终结指定实验场 tmux server。
# 守卫：① 无 -S ⇒ exit 2（默认 socket 是生产名册所在，禁止默认清理）；
#       ② -S 指向默认 socket ⇒ exit 2（防呆：显式传入也不放行）；
#       ③ socket 不存在 ⇒ 幂等成功（rc 0）；④ kill 失败 ⇒ 非 0 + 诊断，不谎报。
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
cmd_cleanup() {
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

# ---------------------------------------------------------------------------
cmd_ensure() {
  local force="$1" model="$2" task="$3"; shift 3
  local spec role repo key seen k
  local -a cg_done=()
  [[ $# -eq 0 ]] && die "ensure 需要至少一个角色，如: nao-fleet.sh ensure arch rd-fe rd-infra"
  # T517：入口一次性解析派生宿主窗口（仅 $TMUX 分支）；定位失败 ⇒ 解析处 warn 一次，各角色 pane 跳过
  HOST_WINDOW=""
  if [[ -n "${TMUX:-}" ]] && command -v tmux >/dev/null 2>&1; then resolve_host_window; fi
  for spec in "$@"; do
    if [[ "$spec" == *"@"* ]]; then
      role="${spec%%@*}"; repo="${spec#*@}"
    else
      role="$spec"; repo=""
    fi
    resolve_role "$role"
    [[ -n "$repo" ]] || repo="${ROLE_WS[$NAME]:-$PWD}"
    # 任务派生：会话名 = <角色>-<任务编号>，独立 intercom 身份（并行隔离，避免同名冲突）
    local disp="$NAME"
    [[ -n "$task" ]] && disp="${NAME}-${task}"
    # CodeGraph 索引健康（同 repo 只查一次，不阻塞拉起）
    key="$repo"; seen=0
    for k in "${cg_done[@]:-}"; do [[ "$k" == "$key" ]] && seen=1; done
    if (( ! seen )); then codegraph_state "$repo" 1 "$(basename "$repo")"; cg_done+=("$key"); fi
    if [[ "$force" != "true" ]] && running "$disp" "$repo"; then
      warn "$disp 已在运行（终端标题/名册命中），跳过；确需重开请加 --force"
      continue
    fi
    spawn_one "$disp" "$repo" "$model"
  done
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
CMD=""; FORCE=false; STRICT=false; MODEL=""; TASK=""; CLEANUP_SOCK=""; TARGETS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    check)  CMD="check";  shift ;;
    status) CMD="status"; shift ;;
    close)  CMD="close";  shift ;;
    cleanup) CMD="cleanup"; shift ;;
    -S) CLEANUP_SOCK="${2:-}"; [[ -n "$CLEANUP_SOCK" ]] || die "-S 需要socket路径参数"; shift 2 ;;
    ensure) CMD="ensure"; shift ;;
    -m|--model)
      MODEL="${2:-}"
      [[ -n "$MODEL" ]] || die "-m 需要模型参数"
      check_model "$MODEL" || die "模型 '$MODEL' 不在白名单内。允许: $MODEL_WHITELIST（可通过 NAO_MODEL_WHITELIST 覆盖）"
      shift 2 ;;
    --force)  FORCE=true;  shift ;;
    --task)   TASK="${2:-}"; [[ -n "$TASK" ]] || die "--task 需要任务编号（如 T1）"; [[ "$TASK" =~ ^[A-Za-z0-9_-]+$ ]] || die "--task 非法: $TASK（仅字母/数字/-/_）"; shift 2 ;;
    --strict) STRICT=true; shift ;;
    -v|--verbose) VERBOSE=true; shift ;;
    -h|--help) usage ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

# 唯一运行前提闸门（BR1/BR3）：先于 load_manifest 与任何副作用；不满足 ⇒ exit 3（命令未执行）。
# cleanup 豁免：其正常场景就是非 tmux 的隔离实验场（env -u TMUX ... -S <socket>）。
case "$CMD" in
  check)  : ;;   # cmd_check 自行先做文本契约体检，再 load_manifest（缩进违例时也能先出报告）
  ensure|status|close) require_tmux; load_manifest ;;
esac
case "$CMD" in
  cleanup) : ;;  # cleanup 不需角色清单
esac

# -S 仅 cleanup 消费：其他子命令带上 -S 视为用法错误（避免静默吞参）
if [[ -n "${CLEANUP_SOCK:-}" && "$CMD" != "cleanup" ]]; then
  die "-S 仅用于 cleanup 子命令（实验场安全清理）：nao-fleet.sh cleanup -S <socket>"
fi

case "$CMD" in
  check)
    # 默认摘要 2 行（派发前自检只需 exit code + 计数 + codegraph 态；完整报告 30+ 行不进 PM 上下文）；-v 或失败时展开
    # warn 计数口径：报告里所有 `  ! ` 行（含 codegraph 的四类 `!` 态：CLI 不在 PATH / 无索引 / pending / 不可解析）
    #   都计入摘要的 warn=N，但 codegraph 的任何状态**都不进 rc**（BR1：codegraph 永不计入退出码）。
    # 子 shell 隔离：cmd_check 内部 die/exit 不得吞掉报告（计数从报告解析，不靠子 shell 内变量）
    REPFILE="$(mktemp)"
    set +e
    ( cmd_check "$STRICT" ) >"$REPFILE" 2>&1
    CHECK_RC=$?
    set -e
    if (( CHECK_RC == 0 )) && ! $VERBOSE; then
      WARNS="$(grep -c '^  !' "$REPFILE" || true)"
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
    else
      cat "$REPFILE"
    fi
    rm -f "$REPFILE"
    exit $CHECK_RC
    ;;
  status) cmd_status ;;
  close)  cmd_close "$FORCE" "$TASK" "${TARGETS[0]:-}" ;;
  cleanup) cmd_cleanup ;;
  ensure) cmd_ensure "$FORCE" "$MODEL" "$TASK" "${TARGETS[@]}" ;;
  *) usage ;;
esac