# 快照：pre-#93 版 `t4_scan_host_pane_refs`（逐字复制自 `main@2497d87` · v0.22.6 · 2026-11-09）
#
# 用途（#93 复核 P3-3）：固定「历史事实」—— 该版对 93-all-server-tail1/defect.sh 输出为空
#   （只拦命令行位裸 tmux，带 -S 的真实缺陷类零覆盖）。用例断言读本快照而不是 live 函数，
#   这样以后有人**增强 live 旧 lint**（把缺陷类也拦下）时，不会把「旧 lint 仍绿」断言弄成假红。
# 用法：`source <本文件>` 会定义同名函数；`cases/06` 在**子 shell** 里 source 以做同场对照。
# 维护：本文件是历史快照，**不随 live lint 演进**；要改地址/来源请新加快照文件，勿原地改判据。

# #84 A 行级 lint：用例不得在**命令行位直接调 `tmux`**（默认 socket ⇒ 生产 server）取 pane 数/做绝对断言。
#   判定：命令行位（行首 / | ; & ( $( { 之后）出现 tmux 或 $REAL_TMUX，且同串无 `-S`；
#   `command -v tmux` / `t4_require_cmd tmux` 豁免（非调用）。输出 "basename:line: content"。
#   覆盖边界：真实缺陷类（同 server 累积残留 + 全 server 计数 + `tail -1` 启发式）写法普遍带 `-S`，
#   **不在此 lint 覆盖面**；那类由用例级解耦承担（见 `cases/20` 的 reset_lab + 快照 diff）。
t4_scan_host_pane_refs() { # $1=用例目录
  local dir="$1" f ln body
  local re='(^|[|;&(]|\$\(|\{)[[:space:]]*(tmux|\$REAL_TMUX|"\$REAL_TMUX")[[:space:]]'
  local allow1='(command -v tmux|t4_require_cmd tmux)'
  local allow2='(tmux|\$REAL_TMUX)"?[[:space:]]+-S([[:space:]]|$)'
  for f in "$dir"/*.sh; do
    [ -f "$f" ] || continue
    while IFS= read -r ln; do
      body="${ln#*:}"
      case "$body" in \#*) continue;; esac
      grep -qE "$allow1" <<< "$ln" && continue
      grep -qE "$allow2" <<< "$ln" && continue
      printf '%s:%s\n' "$(basename "$f")" "$ln"
    done < <(grep -nE "$re" "$f")
  done
}
