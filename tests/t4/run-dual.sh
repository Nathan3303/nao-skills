#!/usr/bin/env bash
# 发布前置双环境 gate（T531 · BR4 / AC4）—— `npm run test:t4:full:dual`
#
# 为什么：同一棵树在「tmux 内默认 socket」前提下才有意义，而 `$TMUX_PANE` 有无会让
# 同一棵树得出不同结论（T529：QA `%5` 绿 / PM `%0` 红）。故发布前置必须在两种环境下都绿。
#
# 两组 = 同参数（`npm run test:t4:full`：T4_ALLOW_MISSING=0 + T4_REQUIRE_FULL=1）串跑，
#   组1：保留 `$TMUX_PANE`（默认环境，撞号态）
#   组2：`env -u TMUX_PANE`（未设态）
# 任一非 0 ⇒ 整体非 0，且结论行点名失败组。白名单 NOTE 明细由每组内 run.sh 汇总输出。
#
# 退出码：0 = 两组皆 rc=0；1 = 至少一组非 0（结论行标明哪组）
# 注：不落临时文件（无清理副作用）；两组各自独立缓存，互不共享状态（BR4 幂等）。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# 单点复用 npm script 定义（不复制 T4_ALLOW_MISSING/T4_REQUIRE_FULL 口径）
run_full() { ( cd "$ROOT" && "$@" npm run --silent test:t4:full ); }

printf '\n########## 组 1/2：保留 $TMUX_PANE（默认环境 · TMUX_PANE=%s）##########\n' "${TMUX_PANE:-<未设>}"
run_full
rc1=$?

printf '\n########## 组 2/2：env -u TMUX_PANE（$TMUX_PANE 未设 · TMUX=%s）##########\n' "${TMUX:-<未设>}"
run_full env -u TMUX_PANE
rc2=$?

printf '\n########## 双环境 gate 结论（test:t4:full:dual）##########\n'
printf '  组 1（保留 TMUX_PANE）  : rc=%d\n' "$rc1"
printf '  组 2（env -u TMUX_PANE）: rc=%d\n' "$rc2"
if [ "$rc1" = "0" ] && [ "$rc2" = "0" ]; then
  printf '  结论: PASS（两组 rc=0；判据另含每组 SKIP=0 · DEGRADE=0 · 非白名单 NOTE=0）\n'
  exit 0
fi
failed=""
[ "$rc1" != "0" ] && failed="组1"
[ "$rc2" != "0" ] && failed="${failed:+$failed + }组2"
printf '  结论: FAIL（失败组: %s —— 双环境 gate 要求两组均 rc=0）\n' "$failed"
exit 1
