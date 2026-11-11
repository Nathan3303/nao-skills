#!/usr/bin/env bash
# 发布前置双后端 gate（T531 · BR4/AC4；#96 三期 P2 改写为「两后端各一组」）—— `npm run test:t4:full:dual`
#
# 为什么（P2 之前）：同一棵树在「tmux 内默认 socket」前提下才有意义，而 `$TMUX_PANE` 有无会让同一棵树
#   得出不同结论（T529：QA `%5` 绿 / PM `%0` 红）。故发布前置必须在两种环境下都绿。
#
# 为什么（P2 之后 · 必须改）：默认后端翻成 herdr 后，若两组都靠「不设 `NAO_TEST_TERMINAL`」搭车，
#   两组**都会落在 herdr** ⇒ tmux 后端（含 12/25 tmux-only）在文档化 gate 里**永不执行**，
#   直接顶 BR1「tmux 逐字零回归」。故改成**两后端各一组、全部显式**（发布判据不依赖默认值）：
#     组 1 = `NAO_TERMINAL=tmux`       （回退通道 · 保留 `$TMUX_PANE` 的撞号态）
#     组 2 = `NAO_TEST_TERMINAL=herdr` （默认通道 · `env -u TMUX_PANE` 未设态）
#   两组都用 `npm run test:t4:full`（T4_ALLOW_MISSING=0 + T4_REQUIRE_FULL=1）。
#
# 自证：每组开跑前**硬断言**解析后的后端（走 `lib-backend.sh::be_backend`，与 run.sh 同口径）：
#   组 1 必须 `tmux`、组 2 必须 `herdr`，不符即 **exit 1**（fail fast，本组不跑）。
#   为什么是断言而不是打印：这一路反复吃「设置 ≠ 生效」（`NAO_TERMINAL=` 空串 / `HERDR_ENV` 丢失 /
#   `TMUX_PANE` 渗透）—— 打印只是提示，断言才是判据（nit 3 · PM 2026-11-11）。
#
# 任一非 0 ⇒ 整体非 0，且结论行点名失败组。白名单 NOTE 明细由每组内 run.sh 汇总输出。
# 退出码：0 = 两组皆 rc=0；1 = 至少一组非 0（结论行标明哪组）
# 注：不落临时文件（无清理副作用）；两组各自独立缓存，互不共享状态（BR4 幂等）。
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# 单点复用 npm script 定义（不复制 T4_ALLOW_MISSING/T4_REQUIRE_FULL 口径）
run_full() { ( cd "$ROOT" && "$@" npm run --silent test:t4:full ); }

# 解析后的后端（与 run.sh / lib-backend.sh 同口径：NAO_TEST_TERMINAL > NAO_TERMINAL > 默认 herdr）
group_backend() { ( cd "$ROOT" && "$@" bash -c 'source tests/t4/lib-backend.sh; be_backend' 2>/dev/null ); }

# 硬断言：本组实际生效的后端必须等于期望值，否则点名「期望 / 实际」并 exit 1（该组不跑）。
assert_group_backend() { # <期望后端> <env...>
  local want="$1"; shift
  local got; got="$(group_backend "$@")"
  if [ "$got" = "$want" ]; then
    printf '  本组后端断言 = %s ✓（期望 %s）\n' "$got" "$want"
    return 0
  fi
  printf '\n########## 双后端 gate 结论（test:t4:full:dual）##########\n' >&2
  printf '  ✗ 后端断言失败：期望 %s，实际 %s\n' "$want" "${got:-<空>}" >&2
  printf '    含义：「设置 ≠ 生效」—— 更高优先级的 env 盖掉了本组设置（NAO_TEST_TERMINAL > NAO_TERMINAL > 默认 herdr）。\n' >&2
  printf '  结论: FAIL（组后端断言未过 · 该组未开跑，fail fast）\n' >&2
  exit 1
}

G1_ENV=(env -u NAO_TEST_TERMINAL NAO_TERMINAL=tmux)
G2_ENV=(env -u TMUX_PANE NAO_TEST_TERMINAL=herdr)

printf '\n########## 组 1/2：tmux 后端（回退通道 · NAO_TERMINAL=tmux · 保留 TMUX_PANE=%s）##########\n' "${TMUX_PANE:-<未设>}"
assert_group_backend tmux "${G1_ENV[@]}"
run_full "${G1_ENV[@]}"
rc1=$?

printf '\n########## 组 2/2：herdr 后端（默认通道 · NAO_TEST_TERMINAL=herdr · TMUX_PANE 未设）##########\n'
assert_group_backend herdr "${G2_ENV[@]}"
run_full "${G2_ENV[@]}"
rc2=$?

printf '\n########## 双后端 gate 结论（test:t4:full:dual）##########\n'
printf '  组 1（tmux 后端）  : rc=%d\n' "$rc1"
printf '  组 2（herdr 后端） : rc=%d\n' "$rc2"
if [ "$rc1" = "0" ] && [ "$rc2" = "0" ]; then
  printf '  结论: PASS（组1 断言 tmux ✓ / 组2 断言 herdr ✓ · 两组 rc=0；判据另含每组 SKIP=0 · DEGRADE=0 · 非白名单 NOTE=0）\n'
  exit 0
fi
failed=""
[ "$rc1" != "0" ] && failed="组1(tmux)"
[ "$rc2" != "0" ] && failed="${failed:+$failed + }组2(herdr)"
printf '  结论: FAIL（失败组: %s —— 发布门禁要求 tmux 与 herdr 两后端都绿）\n' "$failed"
exit 1
