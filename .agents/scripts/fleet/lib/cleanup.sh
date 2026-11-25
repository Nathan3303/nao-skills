# =============================================================================
# fleet/lib/cleanup.sh — cleanup 子命令（拆场）
#
# T567-A（ADR 2026-11-24 §D3）：从 nao-fleet.sh 纯搬迁而来 —— 不重命名函数、不改行为。
# 顶层函数清单见 fleet/functions.txt（174 守恒 · tests/t4/cases/06 三向断言）。
# 依赖：core/term
# 拆场判 effect 不看 rc（stop 非幂等）；--session 必填且 ≠default 的用法守卫在入口。
# =============================================================================

# ---------------------------------------------------------------------------
# 拆场入口（B3）：herdr = session stop+delete（实现 `_term_herdr_cleanup`）；显式目标守卫在入口（rc=2）。
cmd_cleanup() {
  term_cleanup "${SESSION_ARG:-}" "$FORCE"
}
