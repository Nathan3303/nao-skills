#!/usr/bin/env bash
# 用例 11 —— 宿主阶梯 / 失败语义 / 非 tmux 句柄（#26 · T513）
#
# 断言实体由 QA 独立维护并冻结：docs/reports/2026-10-12-T513-verify.sh
#   --t4 口径：exit 0 = 全过 / 1 = 有 FAIL / 77 = 全 SKIP
# 本文件只做挂载（wrapper），不复制、不修改任何断言。
set -uo pipefail
ROOT="${T4_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
exec bash "$ROOT/docs/reports/2026-10-12-T513-verify.sh" --t4
