#!/usr/bin/env bash
# =============================================================================
# nao-fleet.sh — 按角色一键拉起 pi 会话窗口（nao 团队工具箱）
#
# 设计要点
#   - 角色身份 = pi 进程的 --name + 工作区(cwd)，与终端宿主无关。
#   - 角色卡一律取自 nao-skills/.agents/prompts，启动期经 --append-system-prompt 注入，
#     与 PM 提示词 §12「角色提示词加载」衔接（boot 注入，回执仅作双保险）。
#   - 模型规则：默认【不传 --model】，由 pi 全局配置(settings.json)决定；
#     绝不继承 PM 自身模型。仅在调用方显式 -m 时拼参数。
#
# 用法
#   nao-fleet.sh status                             列出本机可识别的角色会话
#   nao-fleet.sh ensure <别名>[@<repo目录>] [更多...]  拉起角色窗口（默认工作区=$PWD）
#   nao-fleet.sh ensure -m <model> <别名>...         显式指定模型（如 deepseek-v4-flash:high）
#   nao-fleet.sh ensure --force <别名>...            忽略“已在运行”判重，强制开窗
#
# 角色别名 → 角色卡（--name 一律用规范别名）
#   pm       → product-manager.md
#   arch     → architecture-designer.md   (arch-designer 同义)
#   rd-fe    → frontend-developer.md
#   rd-be    → backend-developer.md
#   qa       → test-engineer.md
#
# 环境变量
#   NAO_TERMINAL=ghostty|ptyxis|screen   强制宿主（默认自动探测 ghostty > ptyxis > screen；
#                                        无 GUI 终端时设 screen，会话后台运行，screen -r 附着）
#   NAO_SKILLS=<dir>                     角色卡根目录（默认：本脚本位于 <仓库根>/.agents/scripts，
#                                        向上两级即仓库根；可显式覆盖）
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${NAO_SKILLS:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PROMPTS_DIR="$SKILLS_DIR/.agents/prompts"

log()  { printf '\033[1;32m[fleet]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[fleet]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[fleet]\033[0m %s\n' "$*" >&2; exit 1; }

# 角色解析：填全局 $NAME(规范别名) 与 $PROMPT(角色卡文件名)
resolve_role() {
  case "$1" in
    pm)                  NAME="pm";            PROMPT="product-manager.md" ;;
    arch|arch-designer)  NAME="arch-designer"; PROMPT="architecture-designer.md" ;;
    rd-fe)               NAME="rd-fe";         PROMPT="frontend-developer.md" ;;
    rd-be)               NAME="rd-be";         PROMPT="backend-developer.md" ;;
    qa)                  NAME="qa";            PROMPT="test-engineer.md" ;;
    *) die "未知角色: $1（可用: pm arch arch-designer rd-fe rd-be qa）" ;;
  esac
}

detect_host() {
  [[ -n "${NAO_TERMINAL:-}" ]] && { echo "$NAO_TERMINAL"; return; }
  command -v ghostty >/dev/null 2>&1 && { echo ghostty; return; }
  command -v ptyxis  >/dev/null 2>&1 && { echo ptyxis;  return; }
  echo screen
}

running() { pgrep -f -- "--name $1" >/dev/null 2>&1; }

spawn_one() {
  local name="$1" repo="$2" model="$3" prompt_file host inner
  prompt_file="$PROMPTS_DIR/$PROMPT"
  [[ -f "$prompt_file" ]] || die "角色卡不存在: $prompt_file"
  [[ -d "$repo" ]]        || die "工作区不存在: $repo"

  # inner 交给 bash -lc 解析：cd 决定窗口工作区，--name 注册 intercom 身份
  inner="cd $(printf %q "$repo") && exec pi --name $(printf %q "$name")"
  if [[ -n "$model" ]]; then inner+=" --model $(printf %q "$model")"; fi
  inner+=" --append-system-prompt $(printf %q "$prompt_file")"

  host="$(detect_host)"
  case "$host" in
    ghostty) setsid -f ghostty -e bash -lc "$inner" >/dev/null 2>&1 ;;
    ptyxis)  setsid -f ptyxis  -- bash -lc "$inner" >/dev/null 2>&1 ;;
    screen)  screen -dmS "nao-$name" bash -lc "$inner" ;;
    *) die "不支持的宿主: $host" ;;
  esac
  log "[$host] 已拉起 $name @ $repo${model:+（model=$model）}"
}

cmd_status() {
  local a pid_list
  printf '%-16s %s\n' "会话" "状态"
  for a in pm arch-designer rd-fe rd-be qa; do
    if running "$a"; then
      pid_list="$(pgrep -af -- "--name $a" | awk '{print $1}' | paste -sd, -)"
      printf '%-16s \033[1;32m● running\033[0m (pid %s)\n' "$a" "$pid_list"
    else
      printf '%-16s \033[1;30m○ offline\033[0m\n' "$a"
    fi
  done
  warn "提示: status 只能识别 --name 启动的会话；权威在线名单用 intercom({action:'list'})（兼容 /alias 命名）。"
}

cmd_ensure() {
  local force="$1" model="$2"; shift 2
  local spec role repo
  [[ $# -eq 0 ]] && die "ensure 需要至少一个角色，如: nao-fleet.sh ensure arch rd-fe"
  for spec in "$@"; do
    if [[ "$spec" == *"@"* ]]; then
      role="${spec%%@*}"; repo="${spec#*@}"
    else
      role="$spec"; repo="$PWD"
    fi
    resolve_role "$role"
    if ! $force && running "$NAME"; then
      warn "$NAME 已在运行（--name 识别），跳过；确需重开请加 --force"
      continue
    fi
    spawn_one "$NAME" "$repo" "$model"
  done
}

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ---- 入口解析 ----
CMD=""; FORCE=false; MODEL=""; TARGETS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    status) CMD="status"; shift ;;
    ensure) CMD="ensure"; shift ;;
    -m|--model) MODEL="${2:-}"; [[ -n "$MODEL" ]] || die "-m 需要模型参数"; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help) usage ;;
    *) TARGETS+=("$1"); shift ;;
  esac
done

case "$CMD" in
  status) cmd_status ;;
  ensure) cmd_ensure "$FORCE" "$MODEL" "${TARGETS[@]}" ;;
  *) usage ;;
esac
