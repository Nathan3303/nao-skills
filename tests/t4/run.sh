#!/usr/bin/env bash
# T4 用例运行器 —— PRD #18
#
# 用法:
#   bash tests/t4/run.sh                     # 跑全部用例（默认严格：T2 产物缺失=FAIL）
#   bash tests/t4/run.sh --list              # 只列用例（不执行）
#   bash tests/t4/run.sh --preflight         # 打印前置探测（不执行用例）
#   bash tests/t4/run.sh --case 03           # 只跑指定编号
#   T4_ALLOW_MISSING=1 bash tests/t4/run.sh  # 宽松：依赖缺失=BLOCKED（仅显式 1）
#   T4_REQUIRE_FULL=1 bash tests/t4/run.sh   # 发布前置：SKIP 计数>0 即 FAIL（与上者正交）
#
# 退出码:
#   0 = 汇总全部 PASS/SKIP（严格默认下不会出现 BLOCKED）
#   1 = 有 FAIL / 参数错误 / 未识别状态（MISSING、NOT_RUN、未知值）/ (full) SKIP 计数>0
#   2 = 有 BLOCKED（仅宽松 T4_ALLOW_MISSING=1 下可能出现）
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

CASE_IDS=("01" "02" "03" "04" "05" "06" "07" "08" "09" "10" "11" "12")
CASE_TITLES=(
  "主路径足迹 + check exit=0（AC1）"
  "设计一致性：注册 skill 数==2 且无 collision（AC1/AC6）"
  "异常/边界：未物化 exit 2 + DEGRADED + 恢复命令；D7 防重入（AC3/NFR3/D5/D6/D7）"
  "零网络可执行断言：无网 check exit=0（NFR2/闸门B）"
  "迁移精准删除 + .nao-obsolete 备份 + 共享 skills 保留（AC4/§12-C/D）"
  "契约守护：AC6 机制侧 + AC8 manifest/注入 + AC2 静态替代"
  "真实 pi install -l --approve 与 tarball 布局对照"
  "评审修复回归：F1 lock 保缩进 + F2 init --force 走 migrate 防混装"
  "T509 别名解析 / check 守卫 / close 跨仓回收（#19）"
  "T510 migrate 收尾：shim 判定式 / 开关 / 单行 lock 去重 / B2（#21）"
  "宿主阶梯 / 失败语义 / 非 tmux 句柄（#26）"
  "派生会话 tmux 落点：宿主窗口显式寻址（T517 · AC1–AC7）"
)

mode="run"; only=""; arg_err=""
while [ $# -gt 0 ]; do
  a="$1"; shift
  case "$a" in
    --list) mode="list" ;;
    --preflight) mode="preflight" ;;
    --case)
      if [ $# -eq 0 ]; then arg_err="--case 缺少参数值"; break; fi
      mode="case"; only="$1"; shift ;;
    --case=*) mode="case"; only="${a#--case=}" ;;
    --*) arg_err="未知选项: $a" ;;
    *) arg_err="不支持的裸位置参数: $a（指定用例请用 --case <编号>）" ;;
  esac
done

if [ -z "$arg_err" ] && [ "$mode" = "case" ]; then
  [ -n "$only" ] || arg_err="--case 缺少参数值"
  if [ -n "$only" ]; then
    matched=0
    for id in "${CASE_IDS[@]}"; do [ "$only" = "$id" ] && matched=1; done
    [ "$matched" = "1" ] || arg_err="--case 无匹配用例: $only"
  fi
fi

if [ -n "$arg_err" ]; then
  printf '参数错误: %s\n' "$arg_err" >&2
  printf '用法: bash tests/t4/run.sh [--list | --preflight | --case <01-12>]\n' >&2
  exit 1
fi

export T4_CACHE_DIR="${T4_CACHE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/nao-t4.XXXXXX")}"
export T4_ROOT="$ROOT"
export T4_ALLOW_MISSING="${T4_ALLOW_MISSING:-0}"
export T4_REQUIRE_FULL="${T4_REQUIRE_FULL:-0}"

if [ "$mode" = "list" ]; then
  printf 'T4 用例清单（PRD #18 · 夹具缓存 %s）\n' "$T4_CACHE_DIR"
  for i in "${!CASE_IDS[@]}"; do
    printf '  %s  %s\n' "${CASE_IDS[$i]}" "${CASE_TITLES[$i]}"
  done
  exit 0
fi

if [ "$mode" = "preflight" ]; then
  printf 'T4 前置探测（T4_ALLOW_MISSING=%s（0=严格默认） · T4_REQUIRE_FULL=%s）\n' "$T4_ALLOW_MISSING" "$T4_REQUIRE_FULL"
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
  if [ "$mode" = "case" ] && [ "$only" != "$id" ]; then continue; fi
  printf '\n===== 用例 %s: %s =====\n' "$id" "${CASE_TITLES[$i]}"
  script="$(ls "$HERE/cases/${id}-"*.sh 2>/dev/null | head -1)"
  if [ -z "$script" ]; then results[$id]="MISSING"; continue; fi
  log="$T4_CACHE_DIR/case-${id}.log"
  bash "$script" 2>&1 | tee "$log"
  rc="${PIPESTATUS[0]}"
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
fail=0; blocked=0; skip_cases=0; skip_lines=0; note_lines=0
for i in "${!CASE_IDS[@]}"; do
  id="${CASE_IDS[$i]}"
  if [ "$mode" = "case" ] && [ "$only" != "$id" ]; then continue; fi
  st="${results[$id]:-NOT_RUN}"
  log="$T4_CACHE_DIR/case-${id}.log"
  sub_skip=0; sub_note=0
  if [ -f "$log" ]; then
    # SKIP 行解析：[SKIP]（T513 内部标记）/ SKIP:（t4_skip）/ SKIP+空格（T517 子项标记）
    sub_skip="$(grep -cE '^[[:space:]]*(\[SKIP\]|SKIP[[:space:]:])' "$log" 2>/dev/null || true)"
    sub_note="$(grep -cF '[NOTE]' "$log" 2>/dev/null || true)"
  fi
  sub_skip="${sub_skip:-0}"; sub_note="${sub_note:-0}"
  printf '  %s  %-12s %s\n' "$id" "$st" "${CASE_TITLES[$i]}"
  case "$st" in
    PASS|SKIP) ;;       # 白名单：仅 PASS/SKIP 视为通过
    BLOCKED) blocked=1 ;;
    *) fail=1 ;;        # FAIL* / MISSING / NOT_RUN / 未知值 一律 rc≠0
  esac
  if [ "$st" = "SKIP" ] || [ "$sub_skip" -gt 0 ]; then skip_cases=$((skip_cases + 1)); fi
  skip_lines=$((skip_lines + sub_skip))
  note_lines=$((note_lines + sub_note))
done
printf '  ---\n'
printf '  SKIP: %d 例（含用例内 SKIP 行）· %d 条 SKIP 行\n' "$skip_cases" "$skip_lines"
printf '  NOTE: %d 条（允许，不判 FAIL）\n' "$note_lines"
printf '缓存目录: %s\n' "$T4_CACHE_DIR"
if [ "$fail" = "1" ]; then
  printf 'RESULT: FAIL（存在 FAIL / MISSING / NOT_RUN / 未识别状态）\n'
  exit 1
fi
if [ "$blocked" = "1" ]; then
  printf 'RESULT: BLOCKED（T2 产物缺失；仅宽松 T4_ALLOW_MISSING=1 下出现）\n'
  exit 2
fi
if [ "$T4_REQUIRE_FULL" = "1" ] && [ "$skip_cases" -gt 0 ]; then
  printf 'RESULT: FAIL（T4_REQUIRE_FULL=1 且 SKIP 计数=%d>0 —— 发布前置要求 SKIP=0）\n' "$skip_cases"
  exit 1
fi
printf 'RESULT: PASS（SKIP=%d · NOTE=%d）\n' "$skip_cases" "$note_lines"
exit 0
