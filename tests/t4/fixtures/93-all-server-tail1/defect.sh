#!/usr/bin/env bash
# #93 / #84 P3-2 历史缺陷片段 —— 固定 fixture，勿执行（只被 lint 扫描）
#
# 来源：Issue #93「复现」（PM 实测 2026-11-09）
#       + QA 报告 docs/reports/84-test-isolation-qa.md §二 AC2 / §三 P3-2
# 对应：v0.22.1 之前 `cases/20` 的 pane 采样写法（修后改为 reset_lab + 快照 diff）
# 缺陷形态：全 server 计数（`list-panes -a`）+ 顺序启发式挑最后一行（`| tail -1`）
#   两条都带 `-S`，所以旧行级 lint（只拦命令行位裸 tmux）对它们**零覆盖** —— 这正是 #93 要补的洞。
# 断言：tests/t4/cases/06-contract-guards.sh「#93 AC1/AC2/AC5」
SOCK=/tmp/lab
TX() { tmux -S "$SOCK" "$@"; }
# D1 包装函数调用（历史写法：pane_count）
pane_count() { TX list-panes -a -F '#{pane_id}' 2>/dev/null | tail -1; }
# D2 显式 -S 直调（历史写法：pane_total）
pane_total() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}' 2>/dev/null | tail -1; }
