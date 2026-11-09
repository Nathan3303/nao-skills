#!/usr/bin/env bash
# #93 AC4 配套负控 —— 固定 fixture，勿执行（只被 lint 扫描）
#
# 这些形态**明示不纳管**（见 tests/t4/lib.sh 的 t4_scan_all_server_tail1 注释）：
#   本 lint 只承诺「全 server 计数（`list-panes -a`）+ 顺序启发式挑尾（`| tail -1`）」这一组合，
#   不承诺判 socket 形态、不拼接续行、不把「只计数/取首行/会话定向」当成缺陷。
# 断言：tests/t4/cases/06-contract-guards.sh「#93 AC4 负控」——本例命中数必须为 0。
SOCK=/tmp/lab
# C1 会话定向采样 + 挑尾：不是全 server 计数（不在承诺内）
pane_of_session() { tmux -S "$SOCK" list-panes -t "$s" -F '#{pane_id}' | tail -1; }
# C2 全 server 计数但不挑尾：只数总数，没有顺序启发式
pane_total_wc() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}' | wc -l; }
# C3 全 server 计数但取首行：不是「挑最后一行」
pane_first() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}' | head -1; }
# C4 跨行写法：行级 lint 不拼接续行 ⇒ 已知漏判，显式声明不纳管
pane_multiline() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}' \
  | tail -1; }
# C5 两行变量拼装：命令面与挑选面分隔，行级 lint 不追数据流 ⇒ 不纳管
cmds="list-panes -a -F '#{pane_id}'"
pane_two_lines() { tmux -S "$SOCK" $cmds | tail -1; }
# C6 跳语句（`;`）：分号后的 `tail -1` 不属于 list-panes 那条管道 ⇒ 不得命中
pane_then_echo() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}'; echo done | tail -1; }
# C7 跳语句（`&&`）：同理，跨语句不得当成同一条管道
pane_and_echo() { tmux -S "$SOCK" list-panes -a -F '#{pane_id}' && echo done | tail -1; }
  # C8 pane_indented: 缩进注释必须先 trim 再判 `#`（P3-2）—— 这行含缺陷形态但不得命中
  #   list-panes -a -F '#{pane_id}' | tail -1
