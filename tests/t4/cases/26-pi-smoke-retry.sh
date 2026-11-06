#!/usr/bin/env bash
# 用例 26 —— 真 pi 冒烟的受限重试护栏（#86 A）：只吸收延迟抖动，不吸收其它红
#
# 判据来源：Issue #86 §A（QA 设计输入，四条护栏一条不简化）· `tests/t4/lib.sh` 的 `t4_pi_smoke`
#   ① 每次调用都打 info 行，含**两次 attempt 的 rc + 字节数**（可 grep `pi-smoke:`）
#   ② **只有**「首次 rc=124（超时）」**或**「首次 rc=0 且 stdout 0 字节」才允许重试；**非零退出即便 0 字节也不重试**
#      （收严自 Issue 原文「rc=124 或 0 字节」—— 原式会把「非超时真故障」洗成绿，QA P2-1 实测）
#   ③ 重试仍失败 ⇒ 语义不变（调用方仍 SKIP，full 轴照旧计分）
#   ④ 轻度放宽：首次 120s / 重试 180s（`T4_PI_TIMEOUT` / `T4_PI_RETRY_TIMEOUT` 可覆盖）
#   ⑤ 额外不重试前置：「No API key」（凭据缺失与抖动无关）
#
# 断言分组（全部用桩命令，不跑真 pi / 不联网 / 不依赖 tmux）：
#   R1 超时 ⇒ 重试；两次都超时 ⇒ 仍返回 4（= 调用方 SKIP，AC1/AC3）
#   R2 非超时失败（有输出）⇒ **不重新调用**（AC2 负控，按调用次数证，而非只信 info 行）
#   R3 非零退出 + 0 字节 ⇒ 不重试（P2-1 收严）；R3b rc=0 且 0 字节 ⇒ 仍重试；R2b 非零失败 + 第二次会成功 ⇒ 仍不重试
#   R4 No API key ⇒ 不重试、返回 3（凭据缺失额外前置）
#   R5 接线：`cases/02` 真跑路径确实调用该护栏（防「护栏只在用例里被调」的空转）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

LAB="$(mktemp -d "$T4_CACHE_DIR/lab26.XXXXXX")" || t4_blocked "夹具目录创建失败"
trap 'rm -rf "$LAB"' EXIT
OUT="$LAB/out"; ERR="$LAB/err"; CNT="$LAB/calls"

# 桩：每次调用计数；行为由 $1 指定
mk_stub() { # $1=sleep|fail|empty|retryok|nokey  $2=输出字节
  local kind="$1" n="${2:-0}"
  cat > "$LAB/stub.sh" <<SH
#!/usr/bin/env bash
echo x >> "$CNT"
case "$kind" in
  sleep)   exec sleep 30 ;;
  fail)    head -c $n /dev/zero | tr '\\0' 'a'; exit 7 ;;
  empty)   exit 3 ;;
  retryok) c=\$(wc -l < "$CNT"); if [ "\$c" = "1" ]; then exec sleep 30; fi; printf '{"ok":1}'; exit 0 ;;
  zeroexit) exit 0 ;;
  failthenok) c=\$(wc -l < "$CNT"); if [ "\$c" = "1" ]; then exit 7; fi; printf '{"ok":1}'; exit 0 ;;
  nokey)   echo "No API key for provider" >&2; exit 2 ;;
esac
SH
  chmod +x "$LAB/stub.sh"
  : > "$CNT"
}

# ---------------------------------------------------------------- R1 两次都超时 ⇒ 仍 SKIP 语义
mk_stub sleep 0
T4_PI_TIMEOUT=1 T4_PI_RETRY_TIMEOUT=1 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "4" "$rc" "R1: 两次均超时 ⇒ 返回 4（调用方仍判 SKIP，AC3 语义不变）"
t4_assert_eq "2" "$n_calls" "R1: 恰好两次 attempt（超时允许重试一次，不多不少）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "attempt1 rc=124" "R1: info 行含首次 rc=124"
t4_assert_contains "$T4_PI_SMOKE_INFO" "attempt2 rc=124" "R1: info 行含重试 rc=124"
t4_assert_contains "$T4_PI_SMOKE_INFO" "retry=yes" "R1: info 行标 retry=yes"
t4_assert_match "$T4_PI_SMOKE_INFO" 'bytes=[0-9]+ · attempt2 rc=-?[0-9]+ bytes=[0-9]+' \
  "R1: info 行同时给出**两次** attempt 的 rc + 字节数（可 grep）"

# ---------------------------------------------------------------- R1b 首次超时、重试成功
mk_stub retryok 0
T4_PI_TIMEOUT=1 T4_PI_RETRY_TIMEOUT=10 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "0" "$rc" "R1b: 首次超时 + 重试成功 ⇒ 返回 0（吸收延迟抖动，AC1）"
t4_assert_eq "2" "$n_calls" "R1b: 重试恰一次"
t4_assert_contains "$T4_PI_SMOKE_INFO" "attempt1 rc=124" "R1b: info 行含首次超时"
t4_assert_contains "$T4_PI_SMOKE_INFO" "attempt2 rc=0 bytes=8" "R1b: info 行含重试成功与其字节数"
t4_assert_contains "$(cat "$OUT")" '{"ok":1}' "R1b: 重试产物落盘给调用方解析"

# ---------------------------------------------------------------- R2 非超时失败 ⇒ 不重新调用（负控）
mk_stub fail 20
T4_PI_TIMEOUT=5 T4_PI_RETRY_TIMEOUT=5 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "4" "$rc" "R2: 非超时失败 ⇒ 返回 4（原样判，不洗白）"
t4_assert_eq "1" "$n_calls" "R2 负控: **未重试**（按实际调用次数证，不只信 info 行）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "attempt1 rc=7 bytes=20" "R2 负控: info 行给出首次 rc 与字节数"
t4_assert_contains "$T4_PI_SMOKE_INFO" "attempt2 rc=- bytes=-" "R2 负控: info 行标重试未发生（占位 -）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "retry=no" "R2 负控: info 行标 retry=no"

# ---------------------------------------------------------------- R3 收严（P2-1）：非零退出 + 0 字节 ⇒ **不**重试
mk_stub empty 0
T4_PI_TIMEOUT=5 T4_PI_RETRY_TIMEOUT=5 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "1" "$n_calls" "R3: 非零退出 + 0 字节 ⇒ **不重试**（收严后的判据，钉 1 次调用）"
t4_assert_eq "4" "$rc" "R3: 该支仍返回 4（不洗白）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "retry=no" "R3: info 行标 retry=no"

# ---------------------------------------------------------------- R3b rc=0 且 0 字节 ⇒ **仍**重试
mk_stub zeroexit 0
T4_PI_TIMEOUT=5 T4_PI_RETRY_TIMEOUT=5 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "2" "$n_calls" "R3b: rc=0 且 0 字节 ⇒ **仍**重试一次（判据的左半支）"
t4_assert_eq "4" "$rc" "R3b: 重试后仍空 ⇒ 返回 4（不洗白）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "retry=yes" "R3b: info 行标 retry=yes"

# ---------------------------------------------------------------- R2b 首次非零失败 + 第二次会成功 ⇒ 仍不重试、仍 4
mk_stub failthenok 0
T4_PI_TIMEOUT=5 T4_PI_RETRY_TIMEOUT=5 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "1" "$n_calls" "R2b 负控: 首次非零失败 ⇒ 不重试（哪怕第二次本会成功）"
t4_assert_eq "4" "$rc" "R2b 负控: 真故障不被重试洗成绿（仍返回 4）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "retry=no" "R2b 负控: info 行标 retry=no"

# ---------------------------------------------------------------- R4 No API key ⇒ 不重试、返回 3
mk_stub nokey 0
T4_PI_TIMEOUT=5 T4_PI_RETRY_TIMEOUT=5 t4_pi_smoke "$OUT" "$ERR" "$LAB/stub.sh"
rc="$?"
n_calls="$(wc -l < "$CNT" | tr -d ' ')"
t4_assert_eq "3" "$rc" "R4: 无凭据 ⇒ 返回 3（调用方 SKIP 口径）"
t4_assert_eq "1" "$n_calls" "R4: 无凭据不重试（凭据缺失与延迟抖动无关）"
t4_assert_contains "$T4_PI_SMOKE_INFO" "retry=no" "R4: info 行标 retry=no"

# ---------------------------------------------------------------- R5 接线（防护栏只在用例里空转）
t4_assert_contains "$(cat "$T4_ROOT/tests/t4/cases/02-skill-registration.sh")" "t4_pi_smoke" \
  "R5: cases/02 真跑路径确实经该护栏（非只在用例内空转）"
t4_assert_match "$(cat "$T4_ROOT/tests/t4/lib.sh")" 'T4_PI_TIMEOUT:-120' \
  "R5: 默认首次超时 = 120s（护栏④）"
t4_assert_match "$(cat "$T4_ROOT/tests/t4/lib.sh")" 'T4_PI_RETRY_TIMEOUT:-180' \
  "R5: 默认重试超时 = 180s（护栏④）"

t4_exit
