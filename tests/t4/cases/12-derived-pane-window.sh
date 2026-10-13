#!/usr/bin/env bash
# 用例 12 —— 派生会话 tmux 落点：宿主窗口显式寻址（T517 · AC1–AC5）
#
# 断言实体由 QA 独立维护并冻结：docs/reports/2026-10-13-T517-derived-pane-window-regression.sh
#   --t4 口径：exit 0 = 全过 / 1 = 有 FAIL / 77 = 全 SKIP（无 tmux / 全跳过）
# 本文件只做挂载（wrapper），不复制、不修改任何断言。
set -uo pipefail
ROOT="${T4_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
exec env -u TMUX bash "$ROOT/docs/reports/2026-10-13-T517-derived-pane-window-regression.sh" --t4