#!/usr/bin/env bash
# 用例 44 —— herdr desktop app 第二后端（T562 / Issue #168 · ADR 2026-11-24-herdr-app-backend）
#
# 形态（arch R1 定论 ③ 部分隔离）：`hc` 用**确定性替身**（fixtures/hc-double）把契约面做成可断言事实；
#   真 `hc` 的**子集往返**用**私有 core**（私有 XDG_RUNTIME_DIR/XDG_STATE_HOME + 独立 HC_SESSION）跑，
#   有 `hc` 才跑、无则 SKIP 并给理由。**绝不碰用户真实桌面版**：三件套与 socket 全指向私有根。
#
# 断言组（编号 ↔ 依据）：
#   ① AC7 静态闸：app 臂禁裸调 `hc`（唯一入口 `_term_app_exec`）+ 正控（注入裸调 ⇒ 必红）。
#   ② M2 身份闸门：三件套缺任一 / socket 不在 app core 下 / socket 不是 socket ⇒ exit 3 + 一行指路。
#   ③ AC3b：窗口未在跑 ⇒ ensure exit 3 且**未创建任何终端**（先于创建，不玩「起了再回滚」）。
#   ④ M3 放置 + 硬护栏：`--no-parent`（parent 为空）+ `--keep` + 标签 `herdr.space/tab` + doc 读回命中 + 就绪门。
#   ⑤ M3 回滚：doc 读回不命中 ⇒ kill → rm 且 fail loud（不留孤儿）。
#   ⑥ M4 就绪门：`status.app=pi ∧ state=idle` 不到 ⇒ 超时 fail loud，终端**保留**（不自动 kill）。
#   ⑦ M5 回收：`kill` → `rm` 固定顺序（live 直接 rm 必失败）、effect 复核（从 `ls --all` 消失）、拒回收自身。
#   ⑧ BR4 keep 换壳：finished 残留**不占 tab**（重建前清理）+ status 不把它当在线（`终端残留` 节）。
#   ⑨ 拆场：只清带放置标签的舰队终端（core 属桌面版，不动）。
#   ⑩ AC1 零回归：`NAO_TERMINAL` 未设/herdr 的生效后端子串逐字不变；非法值 rc=2 不变。
#   ⑪ 真 `hc`（私有 core，有则跑）：`--no-parent` 之 parent=null、live `rm` 被拒、kill→rm 往返、标签落库。
#
# 夹具：`tests/t4/fixtures/hc-double`（hc + herdr-app 替身）+ 私有 XDG 根（node unix socket）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
source "$T4_ROOT/tests/t4/lib-backend.sh"

FLEET="$T4_ROOT/.agents/scripts/nao-fleet.sh"
FLEET_SCRIPTS="$T4_ROOT/.agents/scripts"                     # T567-A：文件集（入口 + fleet/lib）
FLEET_APP_MOD="$(t4_fleet_file_for "$FLEET_SCRIPTS" _term_app_exec)"   # app 实现模块（变异/注入的源）
FIXT="$T4_ROOT/tests/t4/fixtures/hc-double"
REAL_HC="$(command -v hc 2>/dev/null || true)"   # 必须在 PATH 前置替身**之前**取（否则拿到替身）
[ -x "$FIXT/hc" ] || { t4_bad "夹具缺失可执行: $FIXT/hc"; t4_exit; }
PATH="$FIXT:$PATH"; export PATH
LAB="$T4_CACHE_DIR/lab44-$$"
mkdir -p "$LAB" || { t4_bad "无法建 lab"; t4_exit; }
cp -r "$T4_ROOT/.agents" "$LAB/.agents" || { t4_bad "夹具复制 .agents 失败"; t4_exit; }

be_app_init "$LAB" "lab44-$$" || { t4_bad "be_app_init 失败"; t4_exit; }
be_app_arm_cleanup

APP_RC=0; APP_OUT=""; APP_ERR=""
APP_OVR=()   # 覆盖项（`KEY=` 空值 = 缺参；后写覆盖先写 ⇒ 必须排在基础 env 之后）
run_app() { # 走与生产一致的 env 面（显式 NAO_TERMINAL=app + 三件套 + 私有根）
  local -a envs=(NAO_TERMINAL=app "HC_SCOPE=$BE_SESSION" HC_TERMINAL_ID=t0
    "HC_TERMINAL_SOCKET=$BE_APP_SOCK" "XDG_RUNTIME_DIR=$BE_APP_RT"
    "HC_DOUBLE_STATE=$BE_APP_STATE" "PATH=$FIXT:$PATH"
    "HOME=$LAB/.t4-home" "PI_CODING_AGENT_DIR=$LAB/.t4-home/.pi/agent")
  local script="${BE_FLEET_SCRIPT:-$LAB/.agents/scripts/nao-fleet.sh}"
  local -a argv=(env)
  argv+=("${envs[@]}")
  if (( ${#APP_OVR[@]} )); then argv+=("${APP_OVR[@]}"); fi
  argv+=(timeout "${BE_FLEET_TIMEOUT:-120}" bash "$script")
  t4_run_in_dir "$LAB" "${argv[@]}" "$@"
  APP_RC=$T4_RC; APP_OUT="$T4_OUT"; APP_ERR="$T4_ERR"
}
require_app() { [ -n "${BE_APP_STATE:-}" ] || { t4_bad "app 夹具未初始化"; t4_exit; }; }

stub_hc() { HC_DOUBLE_STATE="$BE_APP_STATE" "$FIXT/hc" "$@"; }
app_addrs() { find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | grep -v '^t0$' | sort -V; }
app_field() { head -1 "$BE_APP_STATE/t/$1/$2" 2>/dev/null; }
app_log() { cat "$BE_APP_STATE/log" 2>/dev/null || true; }
app_reset() {
  find "$BE_APP_STATE/t" -mindepth 1 -maxdepth 1 -type d ! -name t0 -exec rm -rf {} + 2>/dev/null || true
  find "$BE_APP_STATE/spaces" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  : > "$BE_APP_STATE/log"
  rm -f "$BE_APP_STATE"/docver "$BE_APP_STATE"/doc_hide "$BE_APP_STATE"/ready \
        "$BE_APP_STATE"/status_app "$BE_APP_STATE"/status_state "$BE_APP_STATE"/run_fail \
        "$BE_APP_STATE"/send_fail "$BE_APP_STATE"/app_status_rc "$BE_APP_STATE"/bare_get \
        "$BE_APP_STATE"/bare_labels
}
one_addr() { local a; a="$(app_addrs | head -1)"; printf '%s' "$a"; }

# ---------------------------------------------------------------- ① AC7 静态闸（两向）
out="$(t4_scan_app_bare_hc "$FLEET_SCRIPTS")"
t4_assert_eq "" "$out" "① AC7 静态闸：app 臂裸调 hc = 0（唯一入口 _term_app_exec）"
t4_assert_eq "1" "$(t4_fleet_count '^_term_app_exec\(\) \{' "$FLEET_SCRIPTS")" \
  "① AC7 结构断言：唯一入口 \`_term_app_exec\` 恰 1 处（删/改名必红，不靠「无命中」冒充绿）"
MUT="$T4_CACHE_DIR/c44-barehc-$$.sh"
python3 - "$FLEET_APP_MOD" "$MUT" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('# >>> term-impl-app BEGIN','# >>> term-impl-app BEGIN\nhc schema >/dev/null',1))
PY
out="$(t4_scan_app_bare_hc "$MUT")"
t4_assert_contains "$out" "hc schema" "① 正控A：语句位注入裸调 ⇒ 静态闸必红（原形态不回归）"
rm -f "$MUT"
# 变异B：`command hc` 前缀（QA P2 漏检形态① —— env/`command` 前缀同样是绕过唯一入口）
python3 - "$FLEET_APP_MOD" "$MUT" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('# >>> term-impl-app BEGIN','# >>> term-impl-app BEGIN\ncommand hc schema >/dev/null',1))
PY
out="$(t4_scan_app_bare_hc "$MUT")"
t4_assert_contains "$out" "command hc schema" "① 正控B：\`command\` 前缀裸调 hc ⇒ 必红（QA 漏检形态）"
rm -f "$MUT"
# 变异C：前置 env 赋值（`HC_SOCKET=x hc ls` —— 绕过入口的 socket 归一化）
python3 - "$FLEET_APP_MOD" "$MUT" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('# >>> term-impl-app BEGIN','# >>> term-impl-app BEGIN\nHC_SOCKET=/tmp/x.sock hc ls >/dev/null',1))
PY
out="$(t4_scan_app_bare_hc "$MUT")"
t4_assert_contains "$out" "HC_SOCKET=/tmp/x.sock hc ls" "① 正控C：env 前缀 ⇒ 必红（QA 漏检形态）"
rm -f "$MUT"
# 变异D：整删/改名唯一入口（「无命中即绿」的根因）
python3 - "$FLEET_APP_MOD" "$MUT" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('_term_app_exec() {','_term_app_exec_gone() {',1))
PY
out="$(t4_scan_app_bare_hc "$MUT")"
t4_assert_contains "$out" "MISSING_ENTRY" "① 正控D：删/改名入口 ⇒ 结构断言必红（不靠痕量命中）"
rm -f "$MUT"
# 正控E–I（T563/AC1）：**关键字位就是命令位**（旧前缀组只认行首/管道/命令替换 ⇒ 漏检）
# 正控J–M（T563/P3-2）：`sudo` 前缀（含带选项/参数）、case 分支位（`pat) hc`、`* ) hc`）同样漏检
for kw in 'if hc ls' 'then hc ls' '! hc ls' 'while hc ls' 'command -p hc ls' 'sudo hc ls' 'up) hc ls' '*) hc ls' \
          'sudo -u root hc ls' 'sudo -Eu www-data hc ls' '* ) hc ls'; do
  python3 - "$FLEET_APP_MOD" "$MUT" "$kw" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('# >>> term-impl-app BEGIN','# >>> term-impl-app BEGIN\n'+sys.argv[3]+' >/dev/null',1))
PY
  out="$(t4_scan_app_bare_hc "$MUT")"
  t4_assert_contains "$out" "$kw" "① 正控（命令位）：\`$kw\` ⇒ 必红"
  rm -f "$MUT"
done
# 负控（防空转）：非调用形态 / 存在性探测不得误报
python3 - "$FLEET_APP_MOD" "$MUT" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
add='\n'.join(['hc_ls x >/dev/null','_hc_wrapper ls','command -v hc >/dev/null',
                't4_require_cmd hc','case "$x" in *) :;; esac'])
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('# >>> term-impl-app BEGIN','# >>> term-impl-app BEGIN\n'+add,1))
PY
out="$(t4_scan_app_bare_hc "$MUT")"
t4_assert_eq "" "$out" "① 负控：\`hc_ls\` / \`_hc_wrapper\` / \`command -v hc\` / \`t4_require_cmd hc\` / 非 hc 的 case 分支 均不得误报（白名单不空转）"
rm -f "$MUT"
# 负控2（T563/P3-2 防假阳）：`sudo` 只吃「选项 + 选项自带的那个参数」，不吃任意单词；
#   模式字符类不含 `(` ⇒ `(herdr|tmux)` 这类正则字面量不得被当成 case 臂（T558 踩过的假阳）
python3 - "$FLEET_APP_MOD" "$MUT" <<'PY'
import sys
src=open(sys.argv[1],encoding='utf-8').read()
add='\n'.join(['sudo grep hc /tmp/f >/dev/null','sudo -u root grep hc /tmp/f >/dev/null',
                'printf "%s\\n" "(herdr|tmux)"','echo "hc ls"'])
open(sys.argv[2],'w',encoding='utf-8').write(src.replace('# >>> term-impl-app BEGIN','# >>> term-impl-app BEGIN\n'+add,1))
PY
out="$(t4_scan_app_bare_hc "$MUT")"
t4_assert_eq "" "$out" "① 负控2：\`sudo grep hc\` / \`sudo -u root grep hc\` / \`(herdr|tmux)\` 字面量 / 引号内\`hc ls\` 均不得误报（假阳比漏检更有害）"
rm -f "$MUT"

# ---------------------------------------------------------------- ② M2 身份闸门
APP_OVR=("HC_SCOPE=")
run_app status
t4_assert_eq "3" "$APP_RC" "② 缺 HC_SCOPE ⇒ exit 3"
t4_assert_contains "$APP_ERR" "HC_SCOPE" "② 指路点名 HC_SCOPE"
APP_OVR=("HC_TERMINAL_ID=")
run_app status
t4_assert_eq "3" "$APP_RC" "② 缺 HC_TERMINAL_ID ⇒ exit 3"
APP_OVR=("HC_TERMINAL_SOCKET=")
run_app status
t4_assert_eq "3" "$APP_RC" "② 缺 HC_TERMINAL_SOCKET ⇒ exit 3"
APP_OVR=("HC_TERMINAL_SOCKET=/tmp/nao44-notapp/c.sock")
run_app status
t4_assert_eq "3" "$APP_RC" "② socket 不在 app core 下 ⇒ exit 3"
t4_assert_contains "$APP_ERR" "herdr-core" "② 指路说明应在 herdr-core 下"
printf '' > "$BE_APP_RT/herdr-core/notasock"
APP_OVR=("HC_TERMINAL_SOCKET=$BE_APP_RT/herdr-core/notasock")
run_app status
t4_assert_eq "3" "$APP_RC" "② socket 存在但不是 socket ⇒ exit 3"
t4_assert_contains "$APP_ERR" "不是 socket" "② 区分「未运行/非 socket」"
APP_OVR=()

# ---------------------------------------------------------------- ③ AC3b 窗口未在跑
app_reset
printf '1' > "$BE_APP_STATE/app_status_rc"
run_app ensure rd-fe
t4_assert_eq "3" "$APP_RC" "③ 窗口未在跑 ⇒ ensure exit 3"
t4_assert_contains "$APP_ERR" "desktop app 未在运行" "③ 指路说明「先打开 app 窗口」"
t4_assert_eq "" "$(app_addrs)" "③ **未创建任何终端**（先于创建判前提）"
t4_assert_not_contains "$(app_log)" "run " "③ 桩调用日志里没有 hc run"
rm -f "$BE_APP_STATE/app_status_rc"

# ---------------------------------------------------------------- ④ M3 放置 + 硬护栏
app_reset
run_app ensure rd-fe
t4_assert_eq "0" "$APP_RC" "④ ensure rc=0（app 后端）"
A1="$(one_addr)"
t4_assert_eq "rd-fe" "$(app_field "$A1" name)" "④ 终端名 = 会话名（rd-fe）"
t4_assert_eq "" "$(app_field "$A1" parent)" "④ 硬护栏①：--no-parent ⇒ parent 为空（否则父终端退出会带走子终端）"
t4_assert_eq "1" "$(app_field "$A1" keep)" "④ 硬护栏①：--keep 已传（core 丢失后原地换 shell）"
t4_assert_ne "" "$(app_field "$A1" space)" "④ 放置：space 标签已写"
t4_assert_ne "" "$(app_field "$A1" tab)" "④ 放置：tab 标签（= 会话名）已写"
doc="$(stub_hc connect <<< '{"jsonrpc":"2.0","id":1,"method":"doc.get","params":{"name":"herdr-app"}}')"
t4_assert_contains "$doc" "\"terminal\":\"$A1\"" "④ 硬护栏④：doc.get 里终端落在目标 tab 树（不用 where）"
t4_assert_contains "$APP_OUT" "已拉起 1 个会话" "④ 摘要计数（成功 1）"

# ---------------------------------------------------------------- ⑤ M3 回滚（doc 读回不命中）
app_reset
printf 't1' > "$BE_APP_STATE/doc_hide"
run_app ensure rd-fe
t4_assert_contains "$APP_OUT$APP_ERR" "放置验证失败" "⑤ 读回不命中 ⇒ fail loud 点名放置验证"
t4_assert_contains "$(app_log)" "kill t1" "⑤ 回滚先 kill"
t4_assert_contains "$(app_log)" "rm t1" "⑤ 回滚再 rm（顺序不可反）"
t4_assert_eq "" "$(one_addr)" "⑤ 回滚后不留孤儿终端"
rm -f "$BE_APP_STATE/doc_hide"

# ---------------------------------------------------------------- ⑥ M4 就绪门超时
app_reset
printf 'never' > "$BE_APP_STATE/ready"
run_app ensure rd-fe
t4_assert_contains "$APP_OUT$APP_ERR" "就绪门超时" "⑥ 5s 内无 pi/idle ⇒ 超时 fail loud"
A6="$(one_addr)"
t4_assert_ne "" "$A6" "⑥ 超时终端**保留**（不自动 kill：留证据人工核对）"
t4_assert_eq "live" "$(app_field "$A6" state)" "⑥ 终端仍 live"
rm -f "$BE_APP_STATE/ready"

# ---------------------------------------------------------------- ⑦ M5 回收（kill → rm）
app_reset
run_app ensure rd-fe
A7="$(one_addr)"
: > "$BE_APP_STATE/log"
run_app close rd-fe --force
t4_assert_eq "0" "$APP_RC" "⑦ close rc=0"
log7="$(app_log)"
t4_assert_contains "$log7" "kill $A7" "⑦ 回收走 kill"
t4_assert_contains "$log7" "rm $A7" "⑦ 回收走 rm"
t4_assert_eq "kill" "$(printf '%s\n' "$log7" | grep -E "^(kill|rm) $A7$" | head -1 | cut -d' ' -f1)" "⑦ 顺序：kill 在 rm 之前"
t4_assert_not_contains "$(stub_hc ls --all --json)" "\"address\":\"$A7\"" "⑦ effect 判据：已从 ls --all 消失"

# ---------------------------------------------------------------- ⑧ BR4 keep 换壳（finished 残留）
app_reset
run_app ensure rd-fe
A8="$(one_addr)"
stub_hc kill "$A8" >/dev/null 2>&1
t4_assert_eq "finished" "$(app_field "$A8" state)" "⑧ 夹具：终端已 finished（pi 退出、壳保留）"
run_app status
t4_assert_not_contains "$APP_OUT" "✓ rd-fe" "⑧ 残留不得判「在线」"
t4_assert_contains "$APP_OUT" "终端残留" "⑧ status 单列「终端残留」（name 命中 ≠ 在线）"
run_app ensure rd-fe
t4_assert_contains "$APP_OUT$APP_ERR" "清理残留（finished）" "⑧ 重建前清理 finished 残留（否则 tab 被永久占用）"
t4_assert_ne "" "$(one_addr)" "⑧ 重建后新终端在"

# ---------------------------------------------------------------- ⑨ 拆场
app_reset
run_app ensure rd-fe
run_app ensure qa
t4_assert_eq "2" "$(app_addrs | grep -c . || true)" "⑨ 前置：两个舰队终端"
run_app cleanup --session "$BE_SESSION" --force
t4_assert_eq "" "$(app_addrs)" "⑨ 拆场清掉带放置标签的舰队终端"
t4_assert_ne "" "$(app_field t0 name)" "⑨ 自身/非舰队终端不动（t0 仍记录在案）"

# ---------------------------------------------------------------- ⑩ AC1 零回归（herdr 文案逐字）
# >>> default-value-probe BEGIN（唯一允许 unset/清空 NAO_TERMINAL 的位置：验「默认 = herdr」）
#   本块断言的是**默认值**（未设 ⇒ herdr）⇒ 必须登记在 cases/06 的默认值探针白名单；
#   若日后改成非默认值断言，必须移出白名单（维护约束见 docs/reports/168-impl-rd-infra.md §六）
t4_run_in_dir "$LAB" env -u NAO_TERMINAL -u HC_SCOPE -u HC_TERMINAL_ID -u HC_TERMINAL_SOCKET \
  -u HC_DOUBLE_STATE -u XDG_RUNTIME_DIR bash "${BE_FLEET_SCRIPT:-$LAB/.agents/scripts/nao-fleet.sh}" check
# <<< default-value-probe END
t4_assert_contains "$T4_OUT" "生效后端 NAO_TERMINAL=herdr（形态 TUI；desktop app 走 NAO_TERMINAL=app" "⑩ 未设 ⇒ herdr 生效后端文案 = AC4 新口径（AC1 允许面第 5 类：仅此一行）"
t4_run_in_dir "$LAB" env NAO_TERMINAL=app bash "${BE_FLEET_SCRIPT:-$LAB/.agents/scripts/nao-fleet.sh}" check
t4_assert_contains "$T4_OUT" "生效后端 NAO_TERMINAL=app（第二后端" "⑩ app ⇒ 打印第二后端（不谎报唯一）"
t4_run_in_dir "$LAB" env NAO_TERMINAL=bogus bash "${BE_FLEET_SCRIPT:-$LAB/.agents/scripts/nao-fleet.sh}" status
t4_assert_eq "2" "$T4_RC" "⑩ 非法后端值 rc=2（用法守卫不变）"

# ---------------------------------------------------------------- ⑫ AC8 契约缺失 fail loud
#   app 的 doc/labels/status 都是**非版本化**契约（arch R2）：缺失时必须点名「不支持」，
#   不得退化成「当作空闲/空布局继续跑」。
app_reset
printf '0' > "$BE_APP_STATE/docver"
run_app ensure rd-fe
t4_assert_eq "1" "$APP_RC" "⑫ doc.get value=null（窗口未开/版本过旧）⇒ ensure 非 0（die）"
t4_assert_contains "$APP_ERR" "布局文档不可用" "⑫ 点名「布局文档不可用」，不按空布局继续"
printf '9' > "$BE_APP_STATE/docver"
run_app ensure rd-fe
t4_assert_eq "1" "$APP_RC" "⑫ doc version=9 < 10 ⇒ ensure 非 0"
t4_assert_contains "$APP_ERR" "版本不支持" "⑫ 点名「当前 desktop app 版本不支持放置契约」"
rm -f "$BE_APP_STATE/docver"
# 契约缺字段（无 labels/status）：不得判「在线」，也不得当成空闲
printf '1' > "$BE_APP_STATE/bare_get"
run_app ensure rd-fe
# T563/AC5 后：缺 status ⇒ 就绪门永远验不出 idle ⇒ **全部失败 ⇒ rc=1**（这正是要的 fail loud，
#   不是 die：终端已建出且保留，属「建了但无法确认就绪」）。
t4_assert_eq "1" "$APP_RC" "⑫ 缺 status ⇒ 就绪门无法确认 ⇒ rc=1（fail loud，非 die）"
t4_assert_contains "$APP_ERR" "就绪门超时" "⑫ 点名就绪门超时（不退化空闲、不静默成功）"
t4_assert_not_contains "$APP_ERR" "版本不支持" "⑫ 不误报「版本不支持」（契约缺字段 ≠ 版本旧）"
run_app status
t4_assert_contains "$APP_OUT" "集成缺失" "⑫ status 判「集成缺失 ⇒ 不可投递」（不退化 idle）"
t4_assert_not_contains "$APP_OUT" "✓ rd-fe" "⑫ 缺 status 不得判在线"
rm -f "$BE_APP_STATE/bare_get"
# 子形态（PM 裁定）：只缺 labels、status 仍 idle ⇒ **unknown + 一行 warn，不判在线/不可投递**。
#   理由：真 hc 恒给 `"labels":{}`，单缺键不构成「版本不支持」；但「同名未放置终端」会让 close
#   因同名多命中而拒 —— 残余风险必须显式喊出（warn），不得静默当作可投递。
app_reset
env HC_DOUBLE_STATE="$BE_APP_STATE" "$FIXT/hc" run --bg --no-parent --keep \
  --name rd-fe --cwd "$LAB" --label herdr.space=spx --label herdr.tab=tbx -- true >/dev/null
printf '1' > "$BE_APP_STATE/bare_labels"
run_app status
t4_assert_contains "$APP_ERR" "集成缺 labels" "⑫ 子形态：只缺 labels ⇒ warn「无法确认放置归属」"
t4_assert_eq "1" "$(grep -c '集成缺 labels' <<< "$APP_ERR" || true)" "⑫ 子形态：warn **恰 1 行**（同名被问两次会刷两条）"
t4_assert_not_contains "$APP_OUT" "✓ rd-fe" "⑫ 子形态：缺 labels 不判在线（unknown，不退化 idle）"
rm -f "$BE_APP_STATE/bare_labels"
run_app status
t4_assert_not_contains "$APP_ERR" "集成缺 labels" "⑫ 负控：labels 齐全 ⇒ 无该 warn（判据不空转）"
app_reset

# ---------------------------------------------------------------- ⑬ T563/AC2：unknown ⇒ ensure fail-closed
#   缺 labels 的**在场终端**不得被当成「不在运行」而拉起第二个（否则同名多命中，close 随即拒）。
app_reset
env HC_DOUBLE_STATE="$BE_APP_STATE" "$FIXT/hc" run --bg --no-parent --keep \
  --name rd-fe --cwd "$LAB" --label herdr.space=spx --label herdr.tab=tbx -- true >/dev/null
n_before="$(app_addrs | grep -c . || true)"
printf '1' > "$BE_APP_STATE/bare_labels"
run_app ensure rd-fe
t4_assert_eq "1" "$APP_RC" "⑬ AC2：unknown（缺 labels）⇒ ensure 拒绝（rc=1，不静默拉第二个）"
t4_assert_contains "$APP_ERR" "无法确认放置归属" "⑬ AC2：一行指路点名「无法确认放置归属」"
t4_assert_contains "$APP_ERR" "确需重开请加 --force" "⑬ AC2：指路给 --force 出口"
t4_assert_eq "$n_before" "$(app_addrs | grep -c . || true)" "⑬ AC2：未新起终端（fail-closed 生效）"
# 负控：labels 齐全 ⇒ 同一路径不得出现该拒绝（判据不空转）
rm -f "$BE_APP_STATE/bare_labels"
run_app ensure rd-fe
t4_assert_not_contains "$APP_ERR" "无法确认放置归属" "⑬ 负控：labels 齐全 ⇒ 无该拒绝行"
t4_assert_eq "0" "$APP_RC" "⑬ 负控：labels 齐全 ⇒ 走正常拉起（rc=0，不再判 unknown）"

# ---------------------------------------------------------------- ⑬ 纯跳过（QA P2-1）
#   旧断言「已在运行 ⇒ 纯跳过 ⇒ rc=0（幂等 effect=0）」是**空转绿**：常驻重复 ensure 会递增槽位
#   （S3 既有设计，见 cases/22「常驻重复 ensure 会递增槽位」）⇒ 那次 rc=0 实际来自「成功拉起第二个」，
#   纯跳过分支一条断言都没覆盖。修法 = 按既有口径构造真跳过：**同 role+task 派生**的二次 ensure
#   （与 cases/22 AC2 同形态），并用「第二次后终端数不变」钉住 effect=0 —— 跳过被改坏时必红。
app_reset
run_app ensure --task T1 rd-fe
t4_assert_eq "0" "$APP_RC" "⑬ 纯跳过夹具：首次 ensure（派生 T1）rc=0"
t4_assert_eq "1" "$(grep -cF '[app] 已拉起' <<< "$APP_OUT" || true)" "⑬ 纯跳过夹具：首次恰 1 行 [app] 已拉起"
n_skip="$(app_addrs | grep -c . || true)"
t4_assert_eq "1" "$n_skip" "⑬ 纯跳过夹具：场面上恰 1 个终端"
run_app ensure --task T1 rd-fe
t4_assert_eq "0" "$APP_RC" "⑬ 纯跳过：二次 ensure（同名派生已在运行）⇒ rc=0（幂等重跑不报失败）"
t4_assert_eq "0" "$(grep -cF '[app] 已拉起' <<< "$APP_OUT" || true)" "⑬ 纯跳过：零假行（不另起第二个终端）"
t4_assert_contains "$APP_ERR" "已在运行" "⑬ 纯跳过：warn 点名「已在运行」"
t4_assert_contains "$APP_ERR" "跳过" "⑬ 纯跳过：warn 点名「跳过」"
t4_assert_contains "$APP_OUT" "（成功 0 / 跳过 1 / 失败 0）" "⑬ 纯跳过：摘要三类 = 0/1/0"
t4_assert_eq "$n_skip" "$(app_addrs | grep -c . || true)" "⑬ 纯跳过：终端数不变（effect=0）"

# ---------------------------------------------------------------- ⑭ T563/AC5：全败 ⇒ rc=1
app_reset
printf '1' > "$BE_APP_STATE/run_fail"
run_app ensure rd-fe
t4_assert_eq "1" "$APP_RC" "⑭ AC5：全败（实际拉起成功 0）⇒ rc=1"
t4_assert_contains "$APP_ERR" "均未拉起" "⑭ AC5：一行汇总「全部 N 个角色均未拉起」"
rm -f "$BE_APP_STATE/run_fail"
# 负控：有成功 ⇒ rc=0（不得一律报失败）
app_reset
run_app ensure rd-fe
t4_assert_eq "0" "$APP_RC" "⑭ 负控：有成功 ⇒ rc=0"
app_reset

# ---------------------------------------------------------------- ⑪ 真 hc（私有 core；无则 SKIP）
if [ -z "$REAL_HC" ]; then
  t4_skip "真 hc 子集往返（本机无 hc；夹具已覆盖契约面，真机往返归人工验收）"
else
  RRT="$T4_CACHE_DIR/apprt-real-$$"
  mkdir -p "$RRT" || t4_bad "无法建真 hc 私有运行时根"
  SESS="nao-t4-real-$$"
  racc() { XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION="$SESS" "$REAL_HC" "$@" 2>&1; }
  out="$(racc run --bg --no-parent --keep --name rd-t4-real --label herdr.space=spreal --label herdr.tab=tbreal -- sleep 3 || true)"
  raddr="$(sed -n 's/.*"address":"\([^"]*\)".*/\1/p' <<< "$out" | head -1)"
  if [ -z "$raddr" ]; then
    t4_skip "真 hc 起终端失败（私有 core 未就绪）：$(printf '%s' "$out" | head -c 120)"
  else
    g="$(racc get "$raddr" --json || true)"
    t4_assert_contains "$g" '"parent":null' "⑪ 真 hc：--no-parent ⇒ parent=null（否则父终端结束带走子终端）"
    t4_assert_contains "$g" '"herdr.space":"spreal"' "⑪ 真 hc：label herdr.space 落库"
    rm_live="$(racc rm "$raddr")"; rm_live_rc=$?
    t4_assert_ne "0" "$rm_live_rc" "⑪ 真 hc：live 直接 rm 必失败（顺序 kill → rm 的依据）"
    t4_assert_contains "$rm_live" "live" "⑪ 真 hc：失败原因点名 live（kind 判据，不看 rc 文案）"
    racc kill "$raddr" >/dev/null 2>&1 || true
    racc rm "$raddr" >/dev/null 2>&1; rm_after_rc=$?
    t4_assert_eq "0" "$rm_after_rc" "⑪ 真 hc：kill 后 rm 成功"
    t4_assert_not_contains "$(racc ls --all --json || true)" "\"address\":\"$raddr\"" "⑪ 真 hc：往返后从 ls --all 消失"
  fi
  # 收掉私有 core（只 stop 本场 session；effect 判据 = 进程/socket 消失，不阻塞用例结论）
  XDG_RUNTIME_DIR="$RRT" XDG_STATE_HOME="$RRT/state" HC_SESSION="$SESS" "$REAL_HC" server kill >/dev/null 2>&1 || true
  _t4_rm_cache_dir "$RRT"   # 删除走 lib.sh 单点（cases/14 ⑳ 断言删除语句全仓唯一）
fi

t4_exit
