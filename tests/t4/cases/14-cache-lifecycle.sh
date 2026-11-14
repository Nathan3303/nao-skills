#!/usr/bin/env bash
# 用例 14 —— t4 夹具缓存生命周期自洽（T524）
#
# PRD：docs/prds/2026-10-14-cache-warn-cleanup.md（§三 范围 3–7 · §五 BR3–BR10 · §七 AC4–AC7）
# 被测对象：tests/t4/lib.sh 的 t4_cache_cleanup（清理逻辑唯一实现点）+ run.sh 的 mode 感知与三态打印
#
# 语义（BR3/BR7）：
#   自建 + rc=0            ⇒ 清理
#   自建 + rc≠0（FAIL/SKIP 等，含 T4_REQUIRE_FULL 判 FAIL）⇒ 保留 + 打印路径
#   用户传入 T4_CACHE_DIR  ⇒ 永不删（非本进程 mktemp 返回）
#   T4_KEEP_CACHE=1        ⇒ 恒保留（env-only 逃生口）
#
# 断言编号 ↔ PRD：
#   ① 成功自建 ⇒ rc=0 且目录消失        ② 失败自建 ⇒ rc=1 且目录保留
#   ③ T4_KEEP_CACHE=1 成功 ⇒ 保留       ④ T4_KEEP_CACHE=1 失败 ⇒ 保留
#   ⑤ 用户传入 ⇒ 永不删（且 case-06.log 仍在）
#   ⑥ OWNED 导出洞 ⇒ 强制不删（BR3）    ⑦ 前缀守卫负控（非 nao-t4.* ⇒ 不删）
#   ⑧ 软链替换 ⇒ 不删（BR4④）          ⑨ rc 保真（rc=1 不被 trap 吞，BR5）
#   ⑩–⑬ --list / --preflight / --case 99 / 裸位置参数 ⇒ 净增 0（BR8）
#   ⑭ mktemp 失败 ⇒ 非 0 退出（BR9）    ⑮ 未进入 run 循环（堵 /fx.XXXXXX 空值续跑）
#   ⑯–⑱ 收尾孤儿扫描（probe-tmp / probe-mode / probe-user 由本用例自清）
#   ㉑–㉙ 启动期陈旧缓存回收（#121 · M20261114-t4-cache）：
#        正控 8h+无进程 ⇒ 清 · 负控① 1h ⇒ 不清 · 负控② 8h+活进程 ⇒ 不清 · 用户传入目录不删 ·
#        逃生口 T4_KEEP_CACHE=1 整段跳过 · 可观测（条数+前缀）· 释放活进程后下一轮回收 · 二跑 effect=0
#   ⑲⑳ 静态契约（AC7/D-2/R-2）：定义单点（含 function 形态）· 删除语句唯一且限 tests/t4 下 *.sh · rm 词边界
#
# hermetic：全部操作在私有 TMPDIR（$T4_CACHE_DIR/probe-*）内，不依赖 tmux/tsx/网络/registry；
#   探针只经 `source lib.sh` + `t4_exit` 驱动 EXIT trap，恒 PASS、不 DEGRADE。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

LIB="$T4_LIB_DIR/lib.sh"
RUN="$T4_TESTS_DIR/t4/run.sh"

PROBE_TMP="$T4_CACHE_DIR/probe-tmp"
PROBE_MODE="$T4_CACHE_DIR/probe-mode"
PROBE_USER="$T4_CACHE_DIR/probe-user"
PROBE_USER2="$T4_CACHE_DIR/probe-user2"
PROBE_CUSTOM="$PROBE_TMP/not-nao-t4.abc"          # 真实目录，但名字不匹配 nao-t4.* 前缀
rm -rf "$PROBE_TMP" "$PROBE_MODE" "$PROBE_USER" "$PROBE_USER2"
mkdir -p "$PROBE_TMP" "$PROBE_MODE" "$PROBE_USER" "$PROBE_USER2"
: > "$PROBE_USER/case-06.log"                     # 模拟 run.sh 的失败诊断产物（用户目录内不得被删）

# 在私有 TMPDIR 下跑探针：不继承 run.sh 导出的缓存变量（子进程须自行 mktemp 才能 OWNED=1）。
run_probe() { # $1=脚本路径；其余 = 额外 env KEY=VAL（探针输出重定向到文件，避免探针自身的 PASS/FAIL 混入断言计数）
  local s="$1"; shift
  env -u T4_CACHE_DIR -u T4_CACHE_OWNED -u T4_CACHE_PARENT -u T4_KEEP_CACHE -u T4_CACHE_NO_CREATE \
    TMPDIR="$PROBE_TMP" "$@" bash "$s" >"$PROBE_TMP/$(basename "$s").out" 2>&1
}

# 记录 mktemp 返回值的探针模板：$1=记录文件名，$2=t4_ok|t4_bad
write_probe() {
  cat > "$PROBE_TMP/$1.sh" <<EOF
source "$LIB"
printf '%s' "\$T4_CACHE_DIR" > "$PROBE_TMP/$1.rec"
$2 "probe-$1"
t4_exit
EOF
}

count_dirs() { # 私有 TMPDIR 下一层 nao-t4.* 目录数（不用 find）
  local p="$1" n=0 f
  for f in "$p"/nao-t4.*; do [ -e "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

# ---------------------------------------------------------------- ① 成功自建 ⇒ 清理
write_probe p-ok t4_ok
run_probe "$PROBE_TMP/p-ok.sh"; rc=$?
REC_OK="$(cat "$PROBE_TMP/p-ok.rec" 2>/dev/null || true)"
t4_assert_eq "0" "$rc" "① 成功自建缓存：探针 rc=0"
t4_assert_absent "$REC_OK" "① 成功自建缓存：EXIT trap 已清理（$REC_OK 消失）"

# ---------------------------------------------------------------- ②⑨ 失败自建 ⇒ 保留 + rc 保真
write_probe p-bad t4_bad
run_probe "$PROBE_TMP/p-bad.sh"; rc=$?
REC_BAD="$(cat "$PROBE_TMP/p-bad.rec" 2>/dev/null || true)"
t4_assert_eq "1" "$rc" "② 失败自建缓存：探针 rc 保真 =1（BR5，trap 不吞退出码）"
t4_assert_dir "$REC_BAD" "② 失败自建缓存：目录保留（失败证据优先于卫生，BR7）"

# ---------------------------------------------------------------- ③④ T4_KEEP_CACHE=1 恒保留
write_probe p-keep-ok t4_ok
run_probe "$PROBE_TMP/p-keep-ok.sh" T4_KEEP_CACHE=1; rc=$?
REC_KOK="$(cat "$PROBE_TMP/p-keep-ok.rec" 2>/dev/null || true)"
t4_assert_eq "0" "$rc" "③ T4_KEEP_CACHE=1 · 成功：rc=0"
t4_assert_dir "$REC_KOK" "③ T4_KEEP_CACHE=1 · 成功：目录仍保留（逃生口）"
write_probe p-keep-bad t4_bad
run_probe "$PROBE_TMP/p-keep-bad.sh" T4_KEEP_CACHE=1; rc=$?
REC_KBAD="$(cat "$PROBE_TMP/p-keep-bad.rec" 2>/dev/null || true)"
t4_assert_dir "$REC_KBAD" "④ T4_KEEP_CACHE=1 · 失败：目录仍保留"

# ---------------------------------------------------------------- ⑤ 用户传入 ⇒ 永不删
cat > "$PROBE_TMP/p-user.sh" <<EOF
source "$LIB"
printf '%s' "\$T4_CACHE_DIR" > "$PROBE_TMP/p-user.rec"
t4_ok "probe-user"
t4_exit
EOF
run_probe "$PROBE_TMP/p-user.sh" T4_CACHE_DIR="$PROBE_USER"; rc=$?
t4_assert_eq "0" "$rc" "⑤ 用户传入 T4_CACHE_DIR：探针 rc=0"
t4_assert_dir "$PROBE_USER" "⑤ 用户传入 T4_CACHE_DIR：目录永不删（BR3/BR7）"
t4_assert_file "$PROBE_USER/case-06.log" "⑤ 用户目录内 case-06.log 仍在（失败证据不被误删）"

# ---------------------------------------------------------------- ⑥ OWNED 导出洞（BR3）
cat > "$PROBE_TMP/p-hole.sh" <<EOF
source "$LIB"
t4_ok "probe-hole"
t4_exit
EOF
run_probe "$PROBE_TMP/p-hole.sh" T4_CACHE_DIR="$PROBE_USER2" T4_CACHE_OWNED=1; rc=$?
t4_assert_eq "0" "$rc" "⑥ export T4_CACHE_OWNED=1 + 用户目录：探针 rc=0"
t4_assert_dir "$PROBE_USER2" "⑥ lib.sh 侧兜底：外部传递即强制 OWNED=0 ⇒ 不删（堵导出洞）"

# ---------------------------------------------------------------- ⑦ 前缀守卫负控（BR4②）
cat > "$PROBE_TMP/p-prefix.sh" <<EOF
source "$LIB"
mkdir -p "$PROBE_CUSTOM"
T4_CACHE_DIR="$PROBE_CUSTOM"
printf '%s' "\$T4_CACHE_DIR" > "$PROBE_TMP/p-prefix.rec"
t4_ok "probe-prefix"
t4_exit
EOF
run_probe "$PROBE_TMP/p-prefix.sh"; rc=$?
t4_assert_eq "0" "$rc" "⑦ 前缀守卫探针 rc=0"
t4_assert_dir "$PROBE_CUSTOM" "⑦ OWNED=1 但路径非 nao-t4.* ⇒ 前缀守卫拒绝删除"

# ---------------------------------------------------------------- ⑧ 软链替换 ⇒ 不删（BR4④）
cat > "$PROBE_TMP/p-symlink.sh" <<EOF
source "$LIB"
d="\$T4_CACHE_DIR"
printf '%s' "\$d" > "$PROBE_TMP/p-symlink.rec"
rm -rf "\$d"
mkdir -p "$PROBE_TMP/symlink-target"
ln -s "$PROBE_TMP/symlink-target" "\$d"
t4_ok "probe-symlink"
t4_exit
EOF
run_probe "$PROBE_TMP/p-symlink.sh"; rc=$?
REC_SYM="$(cat "$PROBE_TMP/p-symlink.rec" 2>/dev/null || true)"
t4_assert_eq "0" "$rc" "⑧ 软链探针 rc=0"
t4_assert_eq "1" "$([ -L "$REC_SYM" ] && echo 1 || echo 0)" "⑧ 目录被替换为软链 ⇒ 非软链守卫拒绝删除"

# ---------------------------------------------------------------- ⑩–⑬ 早退/错误 mode 净增 0（BR8）
mode_probe() { # $1=描述；其余 = run.sh 参数
  local desc="$1"; shift
  local before after
  before="$(count_dirs "$PROBE_MODE")"
  env -u T4_CACHE_DIR -u T4_CACHE_OWNED -u T4_CACHE_PARENT -u T4_KEEP_CACHE TMPDIR="$PROBE_MODE" \
    bash "$RUN" "$@" >"$PROBE_MODE/out.log" 2>&1
  after="$(count_dirs "$PROBE_MODE")"
  t4_assert_eq "$before" "$after" "$desc ⇒ 私有 TMPDIR 净增 0（before=$before after=$after）"
}
mode_probe "⑩ --list" --list
mode_probe "⑪ --preflight" --preflight
mode_probe "⑫ --case 99（无匹配 ⇒ 参数错误）" --case 99
mode_probe "⑬ 裸位置参数（参数错误）" xyz

# ---------------------------------------------------------------- ⑭⑮ mktemp 失败 ⇒ 非 0 退出（BR9）
env -u T4_CACHE_DIR -u T4_CACHE_OWNED TMPDIR="$PROBE_MODE/no-such-dir" \
  bash "$RUN" --case 01 >"$PROBE_MODE/out-fail.log" 2>&1; rc=$?
t4_assert_ne "0" "$rc" "⑭ mktemp 建目录失败 ⇒ 明确非 0 退出（BR9）"
t4_assert_not_contains "$(cat "$PROBE_MODE/out-fail.log")" "用例 01" "⑮ 失败于建目录，未进入 run 循环（堵 /fx.XXXXXX 空值续跑）"

# ---------------------------------------------------------------- ⑯–⑱ 收尾孤儿扫描（本用例自清）
rm -rf "$PROBE_TMP" "$PROBE_MODE" "$PROBE_USER" "$PROBE_USER2"
t4_assert_absent "$PROBE_TMP" "⑯ 收尾：probe-tmp 已自清"
t4_assert_absent "$PROBE_MODE" "⑰ 收尾：probe-mode 已自清"
t4_assert_absent "$PROBE_USER" "⑱ 收尾：probe-user 已自清"

# ---------------------------------------------------------------- ㉑–㉙ 启动期陈旧缓存回收（#121）
# 触发路径 = 真实启动期（探针 `source lib.sh`）：run.sh 与各用例共用同一条路，不需要第二处调用点。
# 判据双向：正控（8h + 无活进程 ⇒ 清）/ 负控①（1h ⇒ 不清）/ 负控②（8h + 活进程 ⇒ 不清）。
PROBE_STALE="$T4_CACHE_DIR/probe-stale"
rm -rf "$PROBE_STALE"
mkdir -p "$PROBE_STALE"
ST_DEAD8H="$PROBE_STALE/nao-t4.dead8h"     # 正控：8h 前 + 无进程 ⇒ 回收
ST_FRESH1H="$PROBE_STALE/nao-t4.fresh1h"   # 负控①：1h 前（可能是并发另一批）⇒ 不清
ST_LIVE8H="$PROBE_STALE/nao-t4.live8h"     # 负控②：8h 前 + 活进程持有 ⇒ 不清
ST_USER8H="$PROBE_STALE/nao-t4.user8h"     # 用户传入（陈旧也不得删）
ST_KEEP8H="$PROBE_STALE/nao-t4.keep8h"     # 逃生口 T4_KEEP_CACHE=1 ⇒ 不清
for d in "$ST_DEAD8H" "$ST_LIVE8H"; do mkdir -p "$d"; : > "$d/case-32.log"; done
mkdir -p "$ST_FRESH1H"; : > "$ST_FRESH1H/case-32.log"
touch -d '8 hours ago' "$ST_DEAD8H" "$ST_LIVE8H"
touch -d '1 hour ago' "$ST_FRESH1H"
cat > "$PROBE_STALE/probe.sh" <<EOF
source "$LIB"
t4_ok "probe-stale"
t4_exit
EOF
run_stale_probe() { # $1=输出文件名；其余 = 额外 env（TMPDIR 私有 ⇒ 只扫本夹具目录）
  local out="$1"; shift
  env -u T4_CACHE_DIR -u T4_CACHE_OWNED -u T4_CACHE_PARENT -u T4_KEEP_CACHE TMPDIR="$PROBE_STALE" "$@" \
    bash "$PROBE_STALE/probe.sh" >"$PROBE_STALE/$out" 2>&1
}
# 活进程关联：持有该目录的 T4_CACHE_DIR（与 sweep 的活 cache 判据同形）
env T4_CACHE_DIR="$ST_LIVE8H" sleep 30 &
ST_LIVE_PID=$!
run_stale_probe s1.log; rc=$?
t4_assert_eq "0" "$rc" "㉑ 正控：8h 前无进程的假缓存 ⇒ 启动期回收（探针 rc=0）"
t4_assert_absent "$ST_DEAD8H" "㉑ 正控：nao-t4.dead8h 已被清（8h + 无进程）"
t4_assert_dir "$ST_FRESH1H" "㉒ 负控①：1h 前无进程 ⇒ 不清（可能是并发另一批）"
t4_assert_dir "$ST_LIVE8H" "㉓ 负控②：8h 前但有活进程持有 ⇒ 不清"
S1_OUT="$(cat "$PROBE_STALE/s1.log" 2>/dev/null || true)"
t4_assert_contains "$S1_OUT" "陈旧缓存回收: 已清 1 个" "㉔ 可观测：打印清理条数（已清 1 个）"
t4_assert_contains "$S1_OUT" "$PROBE_STALE/nao-t4.*" "㉔ 可观测：打印路径前缀（$PROBE_STALE/nao-t4.*）"
kill -TERM "$ST_LIVE_PID" 2>/dev/null; wait "$ST_LIVE_PID" 2>/dev/null
# 逃生口：8h 死目录 + KEEP=1 ⇒ 一条都不删（活进程已释放也不再保留）
mkdir -p "$ST_KEEP8H"; : > "$ST_KEEP8H/case-32.log"; touch -d '8 hours ago' "$ST_KEEP8H"
run_stale_probe s2.log T4_KEEP_CACHE=1; rc=$?
t4_assert_eq "0" "$rc" "㉖ 逃生口：T4_KEEP_CACHE=1 探针 rc=0"
t4_assert_dir "$ST_KEEP8H" "㉖ 逃生口：T4_KEEP_CACHE=1 ⇒ 陈旧回收整段跳过（8h 死目录保留）"
t4_assert_dir "$ST_LIVE8H" "㉖ 逃生口：活进程已释放 + 8h，KEEP=1 仍不删"
t4_assert_not_contains "$(cat "$PROBE_STALE/s2.log" 2>/dev/null || true)" "陈旧缓存回收" "㉖ 逃生口：无回收输出（不虚报）"
# 用户传入目录（8h 陈旧）⇒ 归属守卫不得删；同时释放后的 8h 死目录本轮被清
mkdir -p "$ST_USER8H"; : > "$ST_USER8H/case-32.log"; touch -d '8 hours ago' "$ST_USER8H"
run_stale_probe s3.log T4_CACHE_DIR="$ST_USER8H"; rc=$?
t4_assert_eq "0" "$rc" "㉕ 用户传入 8h 目录：探针 rc=0"
t4_assert_dir "$ST_USER8H" "㉕ 用户传入 T4_CACHE_DIR：即便 8h 陈旧也不删（归属守卫）"
t4_assert_file "$ST_USER8H/case-32.log" "㉕ 用户目录内容不被回收"
t4_assert_absent "$ST_LIVE8H" "㉗ 活进程释放后（无进程 + 8h）⇒ 下一轮启动回收（保留只因活进程）"
t4_assert_absent "$ST_KEEP8H" "㉗ 逃生口只跳过本轮（不再 KEEP ⇒ 下一轮回收）"
t4_assert_dir "$ST_FRESH1H" "㉗ 1h 目录跨轮仍不清（时效判据稳定）"
# 幂等：没有新的陈旧项 ⇒ 不再打印回收（effect=0）
run_stale_probe s4.log T4_CACHE_DIR="$ST_USER8H"; rc=$?
t4_assert_eq "0" "$rc" "㉘ 二跑：探针 rc=0"
t4_assert_not_contains "$(cat "$PROBE_STALE/s4.log" 2>/dev/null || true)" "已清 " "㉘ 幂等：无新的陈旧项 ⇒ 不再打印回收（effect=0）"
rm -rf "$PROBE_STALE"
t4_assert_absent "$PROBE_STALE" "㉙ 收尾：probe-stale 已自清"

# ---------------------------------------------------------------- ⑲⑳ 静态契约（AC7 单点实现 · D-2）
# 不吃死整句提示语：以「函数定义形态」「缓存删除语句形态」计数；期望值用 `|` 拼接，
# 失败时 t4_assert_eq 会并排打印期望/实际，可直接定位是哪一项不符。
# R-2 收紧：① rm 用词边界（防 confirm/form 假命中）；② 计数范围限 tests/t4 下 *.sh（排除 .md 等文档）；
#           ③ 定义形态同时识别 POSIX `name()` 与 bash `function name`（防漏判假绿）。
DEF_RE='^[[:space:]]*(t4_cache_cleanup[[:space:]]*\(\)|function[[:space:]]+t4_cache_cleanup([[:space:]]*\(\))?)'
RM_RE='(^|[^[:alnum:]_])rm([^[:alnum:]_]|$)'
DEL_RE='rm[[:space:]]+-rf[[:space:]]+--[[:space:]]+"'
DEF_ALL="$(grep -rE --include='*.sh' "$DEF_RE" "$T4_TESTS_DIR" | wc -l | tr -d ' ')"
DEF_LIB="$(grep -cE "$DEF_RE" "$LIB")"
RUN_DEF="$(grep -cE "$DEF_RE" "$RUN")"
RUN_SRC="$(grep -cE '^[[:space:]]*source[[:space:]]+.*lib\.sh' "$RUN")"
t4_assert_eq "1|1|0|1" "$DEF_ALL|$DEF_LIB|$RUN_DEF|$RUN_SRC" \
  "⑲ 单点实现：t4_cache_cleanup 定义（含 function 形态）仅 1 处且在 lib.sh，run.sh 不重复定义并经 source 复用（def_all|def_lib|run_def|run_src）"

DEL_ALL="$(grep -rE --include='*.sh' "$DEL_RE" "$T4_TESTS_DIR" | wc -l | tr -d ' ')"
DEL_LIB="$(grep -cE "$DEL_RE" "$LIB")"
RUN_RM="$(grep -cE "$RM_RE" "$RUN" || true)"
RUN_GLOB="$(grep -cE "$RM_RE.*\*" "$RUN" || true)"
t4_assert_eq "1|1|0|0" "$DEL_ALL|$DEL_LIB|$RUN_RM|$RUN_GLOB" \
  "⑳ 破坏面唯一：缓存删除语句（rm -rf -- 加引号变量）在 tests/t4 下 *.sh 内仅 1 处且在 lib.sh，run.sh 无真 rm / 无 glob 删除（del_all|del_lib|run_rm|run_glob）"

t4_exit
