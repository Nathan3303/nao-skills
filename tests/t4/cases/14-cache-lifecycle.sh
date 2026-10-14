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

t4_exit
