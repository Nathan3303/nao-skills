#!/usr/bin/env bash
# T4 用例运行器 —— PRD #18
#
# 用法:
#   bash tests/t4/run.sh                 # 跑全部用例
#   bash tests/t4/run.sh --list          # 只列用例（不执行）
#   bash tests/t4/run.sh --preflight     # 打印前置探测（不执行用例）
#   bash tests/t4/run.sh --case 03       # 只跑指定编号
#   T4_ALLOW_MISSING=0 bash tests/t4/run.sh   # 严格模式：依赖缺失=FAIL（T2 回执后用）
#
# 退出码: 0=全 PASS/SKIP；1=有 FAIL；2=有 BLOCKED（宽松模式，T2 未交付）
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

CASE_IDS=("01" "02" "03" "04" "05" "06" "07")
CASE_TITLES=(
  "主路径足迹 + check exit=0（AC1）"
  "设计一致性：注册 skill 数==2 且无 collision（AC1/AC6）"
  "异常/边界：未物化 exit 2 + DEGRADED + 恢复命令；D7 防重入（AC3/NFR3/D5/D6/D7）"
  "零网络可执行断言：无网 check exit=0（NFR2/闸门B）"
  "迁移精准删除 + .nao-obsolete 备份 + 共享 skills 保留（AC4/§12-C/D）"
  "契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态替代"
  "真实 pi install -l --approve 与 tarball 布局对照"
)

mode="run"; only=""
for a in "$@"; do
  case "$a" in
    --list) mode="list" ;;
    --preflight) mode="preflight" ;;
    --case) mode="case" ;;
    --case=*) mode="case"; only="${a#--case=}" ;;
    *) only="$a" ;;
  esac
done

export T4_CACHE_DIR="${T4_CACHE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/nao-t4.XXXXXX")}"
export T4_ROOT="$ROOT"
export T4_ALLOW_MISSING="${T4_ALLOW_MISSING:-1}"

if [ "$mode" = "list" ]; then
  printf 'T4 用例清单（PRD #18 · 夹具缓存 %s）\n' "$T4_CACHE_DIR"
  for i in "${!CASE_IDS[@]}"; do
    printf '  %s  %s\n' "${CASE_IDS[$i]}" "${CASE_TITLES[$i]}"
  done
  exit 0
fi

if [ "$mode" = "preflight" ]; then
  printf 'T4 前置探测（宽松模式=%s）\n' "$T4_ALLOW_MISSING"
  printf '  仓库根            : %s\n' "$ROOT"
  printf '  包版本            : %s\n' "$(node -p "require('$ROOT/package.json').version" 2>/dev/null || echo '?')"
  printf '  bin/nao-skill.js  : %s\n' "$([ -f "$ROOT/bin/nao-skill.js" ] && echo 存在 || echo 缺失)"
  for sub in init migrate exec; do
    if bash -c "source '$HERE/lib.sh'; t4_cli_supports '$sub'" 2>/dev/null; then st=已交付; else st='未交付(T2 pending)'; fi
    printf '  CLI %-8s      : %s\n' "$sub" "$st"
  done
  printf '  package.json pi   : %s\n' "$(node -p "(require('$ROOT/package.json').pi)?'有 manifest':'无 manifest(T2 pending)'" 2>/dev/null || echo '?')"
  printf '  shim 源脚本       : %s\n' "$([ -f "$ROOT/.agents/scripts/nao-fleet.sh" ] && echo 存在 || echo 缺失)"
  printf '  bwrap 网络隔离    : %s\n' "$(bash -c "source '$HERE/lib.sh'; t4_bwrap_available && echo 可用 || echo 不可用")"
  printf '  strace connect    : %s\n' "$(bash -c "source '$HERE/lib.sh'; t4_strace_available && echo 可用 || echo 不可用")"
  printf '  pi CLI            : %s\n' "$(command -v pi >/dev/null 2>&1 && echo 可用 || echo 缺失)"
  exit 0
fi

declare -A results

for i in "${!CASE_IDS[@]}"; do
  id="${CASE_IDS[$i]}"
  if [ "$mode" = "case" ] && [ -n "$only" ] && [ "$only" != "$id" ]; then continue; fi
  printf '\n===== 用例 %s: %s =====\n' "$id" "${CASE_TITLES[$i]}"
  script="$(ls "$HERE/cases/${id}-"*.sh 2>/dev/null | head -1)"
  if [ -z "$script" ]; then results[$id]="MISSING"; continue; fi
  bash "$script"
  rc=$?
  case "$rc" in
    0) results[$id]="PASS" ;;
    1) results[$id]="FAIL" ;;
    77) results[$id]="SKIP" ;;
    78) results[$id]="BLOCKED" ;;
    124) results[$id]="FAIL(timeout)" ;;
    *) results[$id]="FAIL(rc=$rc)" ;;
  esac
done

printf '\n==================== T4 汇总 ====================\n'
fail=0; blocked=0
for i in "${!CASE_IDS[@]}"; do
  id="${CASE_IDS[$i]}"
  [ "$mode" = "case" ] && [ -n "$only" ] && [ "$only" != "$id" ] && continue
  st="${results[$id]:-NOT_RUN}"
  printf '  %s  %-12s %s\n' "$id" "$st" "${CASE_TITLES[$i]}"
  case "$st" in
    FAIL*) fail=1 ;;
    BLOCKED) blocked=1 ;;
  esac
done
printf '缓存目录: %s\n' "$T4_CACHE_DIR"
if [ "$fail" = "1" ]; then exit 1; fi
if [ "$blocked" = "1" ]; then exit 2; fi
exit 0
