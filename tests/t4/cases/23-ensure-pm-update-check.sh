#!/usr/bin/env bash
# 用例 23 —— `ensure pm` 注入下游机制包版本自检提示（M20261103 · Issue #74）
#
# PRD：docs/prds/2026-11-03-ensure-pm-update-check.md（AC1–AC7 · R1–R6）
# 被测对象：.agents/scripts/nao-fleet.sh 的 `spawn_one` / `cmd_ensure` / `NAO_UPDATE_MSG`
#
# 断言映射：
#   AC1/R1 注入条件：① `ensure pm` 注入 · ② `ensure rd-be` 不注入 · ③ `NAO_UPDATE_ON_ENSURE=0` 时 pm 不注入
#   AC2/R3 注入文本：常量可 grep · 六要素齐备（pin+5s / gh 要点两句话 / 一行询问 / 五种降级 / 硬约束 / 同意后序列）
#   AC3/R2 分隔与转义：消息经 printf %q 整体转义，位于 `--append-system-prompt` 之后的 `--` 之后，
#                   且真 pi 侧收到**恰好一个** argv 参数（= 常量全文，未被空格/换行拆开）
#   AC4/R6 零回归：非 pm（rd-be）与开关关闭（pm-off）两条路径的 `bash -lc <inner>` 命令串
#                   与「按格式逐字重建」的期望串 **diff 为空**
#   AC7 零网络：fleet 内除常量块以外无 `npm view` / `gh release` / `curl` / `wget` 命令
#
# 夹具纪律（沿用 T4 血训）：
#   - 真 tmux **隔离 socket**（显式硬护栏：≠ 生产默认候选）+ `env -u TMUX -u TMUX_PANE` + `TMUX_TMPDIR` 指向夹具
#   - 桩 `pi`（记录 argv + END 终止行后长驻，绝不拉起真 pi 会话）；名册离线（`PI_CODING_AGENT_DIR` 指向空目录）
#   - 桩 `tmux`（把 split-window 的**命令串原样落盘**后转发真 tmux）⇒ 命令行断言取 fleet 交给 tmux 的原始字节，
#     不经 pane_start_command 的任何再引用；同时按需驱动真 pane 创建（argv 侧断言用）
#   - 夹具根不得落在任何 git 仓内；收尾走机制 `cleanup -S <隔离 socket>`
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

command -v tmux >/dev/null 2>&1 \
  || t4_skip "环境缺少 tmux（用例 23 需真 tmux 隔离 socket 观察 ensure 命令行）"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
BASH_BIN="$(command -v bash)"
REAL_TMUX="$(command -v tmux)"
LAB="$T4_CACHE_DIR/lab23-$$"
SOCKDIR="$LAB/sock"
SOCK="$SOCKDIR/tmux-$(id -u)/default"
FTMUX="$SOCK,0,0"
SPLIT_LOG="$LAB/split.log"
PI_LOG="$LAB/fake-pi.log"

# ---- 硬护栏（先于一切 tmux 操作）：socket 不得命中生产候选，夹具根不得落 git 仓内 ----
GUARD=0
_TM="${TMUX:-}"
for p in "/tmp/tmux-$(id -u)/default" "${TMPDIR:-/tmp}/tmux-$(id -u)/default" "${_TM%%,*}"; do
  [ -n "$p" ] && [ "$SOCK" = "$p" ] && GUARD=1
done
[[ "$SOCK" == "$LAB"/* ]] || GUARD=1
if [ "$GUARD" != 0 ]; then
  t4_bad "护栏触发：夹具 SOCK=$SOCK 不在 \$LAB 下或与生产默认候选冲突"
  t4_exit
fi
FIXTURE_TOP="$(git -C "$T4_CACHE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$FIXTURE_TOP" ]; then
  t4_bad "夹具根落在 git 仓内（$FIXTURE_TOP）⇒ 锚根/归属判定会被污染；请把 TMPDIR 指到仓外"
  t4_exit
fi
t4_ok "护栏：隔离 socket + 夹具根不在任何 git 仓内"

# ---- 夹具 ----
mkdir -p "$LAB" "$SOCKDIR/tmux-$(id -u)" "$LAB/bin" "$LAB/pi-empty"
chmod 700 "$SOCKDIR/tmux-$(id -u)"
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }
# 本仓是机制源（无 .pi/settings.json）：保持现状 ⇒ 「未检测到下游 pin」是注入文本必须覆盖的真实情形
[ -f "$LAB/.pi/settings.json" ] && rm -f "$LAB/.pi/settings.json"

# pi 桩：记录 argv（块间以 cwd= 行分隔、块尾 END 行）后长驻；--version 供前置校验
cat > "$LAB/bin/pi" <<SH
#!/usr/bin/env bash
[ "\${1:-}" = "--version" ] && { echo "1.4.0"; exit 0; }
{ printf 'cwd=%s\n' "\$PWD"; printf '%q\n' "\$@"; printf 'END\n'; } >> "$PI_LOG"
exec sleep 900
SH
chmod +x "$LAB/bin/pi"

# tmux 桩：split-window 的命令串（末位实参）原样落盘（fleet 交给 tmux 的**原始字节**），再转发真 tmux
cat > "$LAB/bin/tmux" <<'SH'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
if [ "${1:-}" = "split-window" ]; then
  args=("$@")
  printf '%s\n' "${args[${#args[@]}-1]}" >> "$D/../split.log"
fi
exec "${NAO_T23_REAL_TMUX:?}" "$@"
SH
chmod +x "$LAB/bin/tmux"

TX() { "$REAL_TMUX" -S "$SOCK" "$@"; }
TX new-session -d -s lab -x 240 -y 80 -c "$LAB" >/dev/null 2>&1
sleep 0.3
CALLER="$(TX list-panes -t lab -F '#{pane_id}' | head -1)"
TX setenv -g PATH "$LAB/bin:$PATH" >/dev/null 2>&1   # 新 pane 用桩 pi / 桩 tmux
BASE="$(basename "$LAB")"

t4_assert_ne "" "$CALLER" "夹具：隔离 tmux server + 调用者 pane 建立（$CALLER）"

# ---- 收尾：先机制 cleanup -S，再复刻 lib 缓存清理语义（保真退出码）----
t523_teardown() {
  [ -n "${SOCK:-}" ] && [ -d "${LAB:-/nonexistent}" ] || return 0
  ( cd "$LAB" 2>/dev/null || cd /tmp
    env -u TMUX TMUX_TMPDIR="$SOCKDIR" "$BASH_BIN" "$LAB/.agents/scripts/nao-fleet.sh" cleanup -S "$SOCK" >/dev/null 2>&1 ) || true
  return 0
}
t523_exit_trap() {
  local rc=$?
  t523_teardown
  trap - EXIT
  if [ "$rc" = "0" ]; then t4_cache_cleanup 2>/dev/null || true; fi
  exit "$rc"
}
trap t523_exit_trap EXIT

# ---- 调用封装 ----
run_fleet() { # <args...> → T4_RC / T4_OUT / T4_ERR（*_ANSI = 去色后版本）
  t4_run_in_dir "$LAB" env -u TMUX -u TMUX_PANE TMUX="$FTMUX" TMUX_PANE="$CALLER" \
    TMUX_TMPDIR="$SOCKDIR" NAO_SKILLS="$LAB" PI_CODING_AGENT_DIR="$LAB/pi-empty" \
    NAO_T23_REAL_TMUX="$REAL_TMUX" NAO_UPDATE_ON_ENSURE="${T23_SWITCH:-1}" \
    PATH="$LAB/bin:$PATH" \
    timeout 90 bash "$LAB/.agents/scripts/nao-fleet.sh" "$@"
  T4_ERR_ANSI="$(printf '%s' "$T4_ERR" | sed -e 's/\x1b\[[0-9;]*m//g')"
  T4_OUT_ANSI="$(printf '%s' "$T4_OUT" | sed -e 's/\x1b\[[0-9;]*m//g')"
}
split_count() { [ -f "$SPLIT_LOG" ] && wc -l < "$SPLIT_LOG" || echo 0; }
# new_split <before> → 本轮新增的 split-window 命令串（每行一条）
new_split() { [ -f "$SPLIT_LOG" ] && sed -n "$(( $1 + 1 )),\$p" "$SPLIT_LOG" || true; }
launch_lines() { grep -cF -- '[tmux] 已拉起' <<< "$T4_OUT_ANSI" || true; }

# ---- 期望命令行（逐字重建；与 fleet 的构造式同源 = 契约本身，非逻辑复制）----
expected_inner() { # <name> <prompt_file>
  printf 'cd %s && export CODEGRAPH_TELEMETRY=0 && exec pi --name %s --append-system-prompt %s' \
    "$(printf %q "$LAB")" "$(printf %q "$1")" "$(printf %q "$2")"
}
expected_wrapped() { printf 'bash -lc %s' "$(printf %q "$(expected_inner "$1" "$2")")"; }
# 注入路径：消息在 inner 层以 printf %q 拼接，再由外层 printf %q 整体转义（两级引用）
expected_wrapped_pm() { # <name> <prompt_file>
  local inner
  inner="$(expected_inner "$1" "$2") -- $(printf %q "$MSG")"
  printf 'bash -lc %s' "$(printf %q "$inner")"
}
prompt_file_of() { # <wrapped> → 其中的 --append-system-prompt 文件路径
  local flat; flat="$(printf '%s' "$1" | tr -d '\\')"
  printf '%s' "$flat" | sed -nE 's#.*--append-system-prompt (/tmp/nao-fleet-[^ ]*\.md).*#\1#p'
}
# diff_assert <期望> <实际> <标签>：逐字比对，失败时打印 diff（AC4 的「diff 为空」证据）
diff_assert() {
  local exp="$1" act="$2" tag="$3" d
  d="$(diff <(printf '%s\n' "$exp") <(printf '%s\n' "$act") 2>&1 || true)"
  if [ -z "$d" ]; then t4_ok "$tag（diff 为空）"; else t4_bad "$tag：diff 非空"; printf '%s\n' "$d" | sed 's/^/    /'; fi
}

# ---- 注入常量：从脚本原样抽出（R3「常量便于 grep 自证」的取证方式）----
MSG_START="$(grep -n "^NAO_UPDATE_MSG='" "$FLEET" | cut -d: -f1)"
MSG_END="$(awk -v s="${MSG_START:-0}" 'NR>s && /'"'"'[[:space:]]*$/ {print NR; exit}' "$FLEET")"
t4_assert_ne "" "$MSG_START" "R3 注入文本是脚本内常量（\$NAO_UPDATE_MSG 可 grep 定位）"
t4_assert_ne "" "$MSG_END" "R3 常量边界可解析（起始行 ${MSG_START:-?} → 结束行 ${MSG_END:-?}）"
sed -n "${MSG_START:-1},${MSG_END:-1}p" "$FLEET" > "$LAB/msg.sh"
# shellcheck disable=SC1090
MSG="$(. "$LAB/msg.sh" && printf '%s' "$NAO_UPDATE_MSG")"
t4_assert_ne "" "$MSG" "R3 常量可解析为实际文本（$(printf '%s' "$MSG" | wc -c) 字节 / $(printf '%s' "$MSG" | wc -l) 行）"

# ============================================================ AC2/R3 六要素（常量本体）
check_msg() { # <子串> <要素标签>
  if printf '%s' "$MSG" | grep -qF -- "$1"; then t4_ok "R3 $2"; else t4_bad "R3 $2（缺：$1）"; fi
}
check_msg ".pi/settings.json" "①读本地 pin"
check_msg "@nathan33/nao-skill" "①pin 包名"
check_msg "npm view @nathan33/nao-skill version" "①远端版本查询"
check_msg "5s" "①5s 超时口径"
check_msg "gh release view" "②有新版取 release 要点"
check_msg "不超过两句" "②要点压成不超过两句"
check_msg "要升吗？" "③一行询问"
check_msg "已是最新" "④降级②已最新"
check_msg "离线或超时" "④降级③离线或超时"
check_msg "未检测到下游 pin" "④降级④无下游 pin"
check_msg "无 gh" "④降级⑤无 gh 只报版本号"
check_msg "未获我同意前不要改任何文件、不要升级" "⑤硬约束句"
check_msg "pi install -l npm:@nathan33/nao-skill@<Y>" "⑥同意后动作 ①"
check_msg "pi update --extensions" "⑥同意后动作 ②"
check_msg "建议重开" "⑥本轮会话仍是旧角色卡提醒"
check_msg "--fetch-timeout=5000" "① 5s 超时可移植（npm 内置参数，不用外部 timeout）"
t4_assert_eq "0" "$(grep -cF -- 'timeout 5 npm view' <<< "$MSG" || true)" \
  "D1 常量不再依赖外部 timeout 命令（macOS 原生无该命令）"
check_msg "若提示安装脚本授权" "⑥授权提示须停下交用户确认（不自行放行）"

# ============================================================ AC7 零网络：常量块外不得出现网络命令
OUTSIDE="$LAB/fleet-outside-msg.sh"
awk -v s="${MSG_START:-0}" -v e="${MSG_END:-0}" 'NR<s || NR>e' "$FLEET" > "$OUTSIDE"
NET_HITS="$(grep -nE 'npm[[:space:]]+view|gh[[:space:]]+release|curl|wget' "$OUTSIDE" || true)"
t4_assert_eq "" "$NET_HITS" "AC7 fleet 内除常量块外无网络/外部命令（npm view / gh release / curl / wget）"
t4_assert_eq "0" "$(grep -cE '^\s*(npm|gh|curl|wget)\b' <<< "$MSG" || true)" \
  "AC7 常量块内也无「行首即命令」形态（只是给 PM 的文本）"

# ============================================================ AC1① ensure pm ⇒ 注入
BEFORE="$(split_count)"
T23_SWITCH=1
run_fleet ensure "pm@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1① ensure pm rc=0（T4_ERR=$(printf '%s' "$T4_ERR" | head -1)）"
t4_assert_eq "1" "$(launch_lines)" "AC1① 恰 1 行 [tmux] 已拉起（三态契约不变，AC5）"
CMD_PM="$(new_split "$BEFORE" | head -1)"
t4_assert_ne "" "$CMD_PM" "AC1① 捕获到 fleet 交给 tmux 的 split-window 命令串"
PF_PM="$(prompt_file_of "$CMD_PM")"
t4_assert_ne "" "$PF_PM" "AC1① 命令串含 --append-system-prompt 文件（$PF_PM）"
diff_assert "$(expected_wrapped_pm pm "$PF_PM")" "$CMD_PM" \
  "AC3① pm 命令行 = 「bash -lc %q(基线 + ' -- ' + %q(常量))」（逐字）"
FLAT_PM="$(printf '%s' "$CMD_PM" | tr -d '\\')"
t4_assert_eq "1" "$(grep -oF -- '【nao 机制包版本自检' <<< "$FLAT_PM" | wc -l)" \
  "AC3① 注入常量在命令行中恰出现 1 次（无重复无残留）"
REST_PM="${FLAT_PM#*--append-system-prompt }"      # <prompt_file> -- $'<常量>'
FILE_PM="${REST_PM%% *}"
AFTER_PM="${REST_PM#"$FILE_PM"}"                 # 去反斜杠后： -- $'…'
if [[ "$AFTER_PM" == " -- \$'"* ]]; then
  t4_ok "AC3① 分隔符紧跟 --append-system-prompt <file> 之后，且后接 $'<常量>' 单引形态"
else
  t4_bad "AC3① 分隔符位置/形态不符：${AFTER_PM:0:40}…"
fi

# 真 pi 侧 argv：`--` 恰一次、位置在 --append-system-prompt 之后、`--` 之后恰 1 个参数 = 常量全文
argv_of() { # <name> → 该会话 argv（每行一个参数；块尾须为 END，避免读到半截）
  awk -v n="$1" '
    function flush() { if (ok && done) { printf "%s", blk; exit 0 } }
    /^cwd=/ { flush(); blk=""; ok=0; done=0; prev=""; next }
    $0 == "END" { done=1; next }
    { blk = blk $0 "\n"; if (prev == "--name" && $0 == n) ok=1; prev=$0 }
    END { flush() }
  ' "$PI_LOG" 2>/dev/null
}
wait_argv() { # <name> [秒] → argv；未记录到则空
  local i=0 lim=$(( ${2:-10} * 20 ))
  while (( i < lim )); do
    local out; out="$(argv_of "$1")"
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    sleep 0.05; i=$((i + 1))
  done
  printf ''
}
ARGS_PM="$(wait_argv pm)"
t4_assert_contains "$ARGS_PM" "--append-system-prompt" "AC3① 桩 pi 记录了 pm 的 argv（真启动路径已走到）"
t4_assert_eq "1" "$(grep -cxF -e '--' <<< "$ARGS_PM")" "AC3① argv 中「--」恰 1 次"
N_APPEND="$(grep -nxF -e '--append-system-prompt' <<< "$ARGS_PM" | cut -d: -f1)"
N_DASH="$(grep -nxF -e '--' <<< "$ARGS_PM" | cut -d: -f1)"
t4_assert_eq "1" "$(( ${N_DASH:-0} > ${N_APPEND:-0} ? 1 : 0 ))" \
  "AC3① 「--」位于 --append-system-prompt（行 ${N_APPEND:-?}）之后（行 ${N_DASH:-?}）"
MSG_ARG="$(awk 'f{print; exit} $0=="--"{f=1}' <<< "$ARGS_PM")"
t4_assert_eq "$(printf %q "$MSG")" "$MSG_ARG" "AC3① 「--」之后恰 1 个参数且逐字等于常量全文（未被空格/换行拆开）"
t4_assert_eq "1" "$(awk 'f{n++} $0=="--"{f=1} END{print n+0}' <<< "$ARGS_PM")" \
  "AC3① 「--」之后参数个数 = 1（无残片）"

# ============================================================ AC1② ensure rd-be ⇒ 不注入
BEFORE="$(split_count)"
run_fleet ensure "rd-be@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1② ensure rd-be rc=0"
t4_assert_eq "1" "$(launch_lines)" "AC1② 恰 1 行 [tmux] 已拉起"
CMD_RD="$(new_split "$BEFORE" | head -1)"
PF_RD="$(prompt_file_of "$CMD_RD")"
t4_assert_ne "" "$PF_RD" "AC1② rd-be 命令串正常（$PF_RD）"
t4_assert_eq "0" "$(printf '%s' "$CMD_RD" | grep -cF -- ' -- ' || true)" \
  "AC1② rd-be 命令行无「 -- 」注入段"
diff_assert "$(expected_wrapped rd-be "$PF_RD")" "$CMD_RD" "AC4② rd-be 命令行与本批前逐字一致"
ARGS_RD="$(wait_argv rd-be)"
t4_assert_eq "" "$(awk 'f{print; exit} $0=="--"{f=1}' <<< "$ARGS_RD")" \
  "AC1② rd-be argv 无「--」后的注入消息"
t4_assert_eq "0" "$(grep -cF -- '按 ①–⑤ 顺序命中即止' <<< "$ARGS_RD" || true)" \
  "AC1② rd-be argv 不含注入文本任何片段"

# ============================================================ AC1③ NAO_UPDATE_ON_ENSURE=0 ⇒ pm 也不注入
BEFORE="$(split_count)"
T23_SWITCH=0
run_fleet ensure --task off "pm@$LAB"
t4_assert_eq "0" "$T4_RC" "AC1③ 开关关闭 ensure pm rc=0"
t4_assert_eq "1" "$(launch_lines)" "AC1③ 恰 1 行 [tmux] 已拉起"
CMD_PMOFF="$(new_split "$BEFORE" | head -1)"
PF_PMOFF="$(prompt_file_of "$CMD_PMOFF")"
t4_assert_ne "" "$PF_PMOFF" "AC1③ pm-off 命令串正常（$PF_PMOFF）"
t4_assert_eq "0" "$(printf '%s' "$CMD_PMOFF" | grep -cF -- ' -- ' || true)" \
  "AC1③ 开关关闭时 pm 命令行无「 -- 」注入段"
diff_assert "$(expected_wrapped pm-off "$PF_PMOFF")" "$CMD_PMOFF" \
  "AC4③ NAO_UPDATE_ON_ENSURE=0 下 pm 命令行与本批前逐字一致"
ARGS_PMOFF="$(wait_argv pm-off)"
t4_assert_eq "" "$(awk 'f{print; exit} $0=="--"{f=1}' <<< "$ARGS_PMOFF")" \
  "AC1③ 开关关闭时 pm argv 无「--」后的注入消息"
t4_assert_eq "$(printf '%s\n' "$ARGS_PMOFF" | grep -c . || true)" "4" \
  "AC1③ 开关关闭时 argv 长度回到基线 4（--name X --append-system-prompt <file>）"

# ============================================================ AC4④ 反向对照：注入路径 argv 恰多 2 个（-- + 消息）
N_BASE="$(printf '%s\n' "$ARGS_PMOFF" | grep -c . || true)"
N_PM="$(printf '%s\n' "$ARGS_PM" | grep -c . || true)"
t4_assert_eq "$(( N_BASE + 2 ))" "$N_PM" \
  "AC4④ 注入路径 argv 恰比基线多 2 个元素（-- + 消息），无其它增量（基线 $N_BASE → 注入 $N_PM）"

t4_exit
