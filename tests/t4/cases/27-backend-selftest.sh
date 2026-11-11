#!/usr/bin/env bash
# 用例 27 —— 后端抽象层自检（PRD #96 一期**步 1** · AC1.4/AC1.5/AC1.7 · BR4/BR6/BR9 · 附一）
#
# 被测对象：`tests/t4/lib-backend.sh`（**测试侧**后端抽象；生产 `nao-fleet.sh` 本批**零改动**）
# 后端开关：`NAO_TEST_TERMINAL=tmux|herdr|auto`（#96 三期 P2：未设 = **herdr**，与生产默认一致；auto = herdr）
#
# 断言映射（PRD #96 §七 AC / §五 BR）：
#   AC1.7 就绪与幂等：`be_start_server` 已就绪 ⇒ effect=0；就绪 = **50×100ms 轮询 + 5s 上限**
#          （禁固定 sleep）；超时 fail loud（`BE-READY-FAIL:`）
#   AC1.4 隔离：两个实验场（各自 lab 根）pane `terminal_id` 交集为空；会话名唯一含 `$$`；
#          A 增建 pane 不动 B；herdr 侧「起 server 前已清 env」由 BR6 四条判据覆盖
#   AC1.5 依赖门槛：**协议/版本不兼容 ⇒ SKIP 并给原因**；而 lab 根不在 cache 下 / 缺 `--session`
#          ⇒ **FAIL**（fail loud，不 SKIP）—— 后两条由护栏断言 + 变异自证守
#   BR6 清环境（含反向护栏）：pane 内 `env | grep -c '^TMUX'` == 0 · `HERDR_SESSION` == 期望名 ·
#          `HERDR_SOCKET_PATH` 前缀 == 实验根下该会话目录 · 只隔离 `XDG_CONFIG_HOME` 而
#          **`XDG_STATE_HOME` 透传未改**（mise 等工具会写它）· 任何 herdr 调用缺 `--session` ⇒ FAIL
#   BR9 default 不可达：私有根下 `default` == stopped 且目录在私有根内（碰不到用户会话）；
#          tmux 侧对偶 = 生产 server 快照 diff 空
#   BR4 拆场：`stop` 容忍非 0 + `delete` 幂等（连跑 2 次 effect=0）+ 零残留（`sessions/` 空 / 无 server / 无进程）
#
# 夹具纪律：两实验场都在 `$T4_CACHE_DIR` 下（herdr 私有 `XDG_CONFIG_HOME` / tmux 隔离 socket）；
#   全程 `env -u TMUX -u TMUX_PANE -u TMUX_TMPDIR` + `HERDR_*` 枚举清除（由 lib-backend 单点完成）；
#   等待一律轮询（`be_wait_until`），无固定 sleep。变异自证只动 `$T4_CACHE_DIR` 的 lib **副本**。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"
BE_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"   # 静态自检要扫本文件

# 变异自证用：允许指向 **副本**（护栏改松后子进程跑本用例必须翻红并点名）
BE_LIB="${T4_BACKEND_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib-backend.sh}"
[ -f "$BE_LIB" ] || { t4_bad "后端抽象层不存在: $BE_LIB"; t4_exit; }
# shellcheck disable=SC1090
source "$BE_LIB"

# ---------------------------------------------------------------- JSON 取值（herdr 响应解析）
json_probe() { # <expr>（env JS=JSON）⇒ 打印取值；解析失败非 0
  node -e '
let j;try{j=JSON.parse(process.env.JS||"")}catch(e){process.exit(2)}
let v;try{v=eval("j."+(process.env.EXPR||""))}catch(e){process.exit(3)}
process.stdout.write(v===undefined?"":String(v))'
}

# ---------------------------------------------------------------- 护栏组（可单独跑：变异自证子集）
GUARD_ONLY="${T4_BACKEND_GUARD_ONLY:-0}"
if [ "$GUARD_ONLY" = "1" ]; then
  # 只跑护栏三条：变异要翻红的正是这一组（子进程路径本身要能被证「未变异时复绿」）
  GUARD_LAB="$T4_CACHE_DIR/guardon-$$"
  BE_CFGROOT="$GUARD_LAB/config"
  BE_CACHE_ROOT="$T4_CACHE_DIR"
  out="$(be_guard_session "" 2>&1)"; rc=$?
  t4_assert_ne "0" "$rc" "护栏①：空 session 被拒（缺 --session ⇒ FAIL；实测无 --session 会静默读到用户 default）"
  t4_assert_contains "$out" "缺 --session" "护栏①：拒绝理由点名「缺 --session」"
  out="$(be_guard_session "default" 2>&1)"; rc=$?
  t4_assert_ne "0" "$rc" "护栏②：会话名 default 被拒（用户会话，绝不作为实验场）"
  t4_assert_contains "$out" "不得为 default" "护栏②：拒绝理由点名「不得为 default」"
  # 护栏③：会话根指向**用户 herdr 根** ⇒ 拒（sweep 与守卫共用的结构性边界；BR9 碰不到）
  root_saved="$BE_CFGROOT"; BE_CFGROOT="$HOME/.config/herdr"
  out="$(be_guard_session "nao-t4-27-guard" 2>&1)"; rc=$?
  BE_CFGROOT="$root_saved"
  t4_assert_ne "0" "$rc" "护栏③：会话根指向用户 herdr 根被拒（绝不碰用户 default）"
  t4_assert_contains "$out" "用户 herdr 根" "护栏③：拒绝理由点名「用户 herdr 根」"
  # 护栏④：实验根不在 \$T4_CACHE_DIR 下 ⇒ be_init FAIL（AC1.5 第二类：fail loud，不 SKIP）
  out="$(NAO_TEST_TERMINAL=herdr NAO_T4_BE_CFGROOT="${T4_CACHE_DIR%/*}/nao-outside-$$" \
          be_init "$GUARD_LAB/lab4" "nao-t4-27-guard4" 2>&1)"; rc=$?
  t4_assert_ne "0" "$rc" "护栏④：实验根不在 \$T4_CACHE_DIR 下 ⇒ be_init FAIL（AC1.5 第二类）"
  t4_assert_contains "$out" "实验根不在" "护栏④：拒绝理由点名「实验根不在」（含 cache 根对照）"
  # 护栏⑤（P3-2）：实验根过深 ⇒ 前置拒绝并把 sun_path 上限 + 改法说清（不许退化成「rc=9 兜底未点火」误导）
  long_cache="$T4_CACHE_PARENT/nao-t4-$(printf 'y%.0s' $(seq 1 60))"
  cache_saved="$BE_CACHE_ROOT"
  BE_CACHE_ROOT="$long_cache"
  out="$(NAO_TEST_TERMINAL=herdr be_init "$long_cache/lab" "nao-t4-27-long-$$" 2>&1)"; rc=$?
  BE_CACHE_ROOT="$cache_saved"
  t4_assert_ne "0" "$rc" "护栏⑤：实验根过深（sun_path 108 上限）⇒ be_init 直接拒绝（不等到 bind 才炸）"
  t4_assert_contains "$out" "sun_path" "护栏⑤：报错点名 sun_path 上限（不再是裸 Error 栈）"
  t4_assert_contains "$out" "108" "护栏⑤：报错给出上限数值（108 含结尾 NUL）"
  t4_assert_contains "$out" "T4_CACHE_DIR" "护栏⑤：报错给出可执行改法（换短 T4_CACHE_DIR / 缩短会话名）"
  t4_assert_contains "$out" "当前长度" "护栏⑤：报错给出当前长度（可判定超多少）"
  t4_assert_not_contains "$out" "rc=9" "护栏⑤：不再是「rc=9 兜底未点火」那种误导定位"
  rm -rf "$long_cache"                     # 长路径夹具不留在 /tmp（be_init 会先建 lab 根再判护栏）
  t4_exit
fi

# ---------------------------------------------------------------- 依赖门槛（AC1.5 第一类 ⇒ SKIP）
BE_NAME="$(be_backend)" || { t4_bad "NAO_TEST_TERMINAL 非法（期望 tmux|herdr|auto）"; t4_exit; }
case "$BE_NAME" in
  tmux)  command -v tmux >/dev/null 2>&1 || t4_skip "环境缺少 tmux（后端自检需真 tmux 隔离 socket）" ;;
  herdr) command -v herdr >/dev/null 2>&1 || t4_skip "环境缺少 herdr（AC1.5 第一类：能力/版本缺失 ⇒ SKIP 并给原因）" ;;
esac

LAB="$T4_CACHE_DIR/be27-$$"
mkdir -p "$LAB"

# 依赖门槛细节（herdr）：版本 + 协议——不兼容 ⇒ SKIP 并给原因（不静默降级）
if [ "$BE_NAME" = "herdr" ]; then
  # 最小上下文（仅探元数据，不起 server）：be_guard_session 要求实验根已在 cache 下
  BE_CFGROOT="$LAB/config"; BE_CACHE_ROOT="$T4_CACHE_DIR"
  # 版本探针也走**唯一入口**（#96 步 2b · P3-3：白名单是整行等值，不容忍「捕获写法」）：
  #   实测 herdr 0.9.1 接受 `--session <s> --version`（输出与裸 `--version` 一致，rc=0）。
  H_VER="$(be_herdr "nao-t4-27-probe-$$" --version 2>/dev/null | sed -nE 's/^herdr[[:space:]]+([0-9.]+)$/\1/p' | head -1)"
  H_PROTO="$(be_herdr_protocol "nao-t4-27-probe-$$" 2>/dev/null || true)"
  if [ -z "$H_VER" ]; then t4_skip "herdr --version 无法解析 ⇒ 协议/版本不兼容（AC1.5 第一类）"; fi
  if [ "$H_PROTO" != "22" ]; then
    t4_skip "herdr api schema protocol=${H_PROTO:-?}（依赖边界要求 22；AC1.5 第一类 ⇒ SKIP 并给原因）"
  fi
  t4_assert_eq "0" "$(printf '%s\n%s\n' "$H_VER" "0.9.1" | sort -V | head -1 | grep -qx '0.9.1' && echo 0 || echo 1)" \
    "依赖门槛①：herdr 版本 ${H_VER} ≥ 0.9.1（依赖边界）"
  t4_assert_eq "22" "$H_PROTO" "依赖门槛②：herdr api schema protocol == 22"
fi

# ---------------------------------------------------------------- 变异自证：护栏改松 ⇒ 必红并点名
MUT_LIB="$LAB/mut-lib-backend.sh"
{ cat "$BE_LIB"; printf '\n# 变异（用例内自证用）：把「缺 --session ⇒ FAIL」护栏改松为恒放行\nbe_guard_session() { return 0; }\n'; } \
  > "$MUT_LIB"
real_out="$(T4_BACKEND_LIB="$BE_LIB"   T4_BACKEND_GUARD_ONLY=1 bash "$0" 2>&1)"; real_rc=$?
mut_out="$( T4_BACKEND_LIB="$MUT_LIB" T4_BACKEND_GUARD_ONLY=1 bash "$0" 2>&1)"; mut_rc=$?
t4_assert_eq "0" "$real_rc" "变异自证：未变异 lib 跑护栏组复绿（证明红来自变异，不是子进程路径坏）"
t4_assert_ne "0" "$mut_rc" "变异自证：护栏改松 ⇒ 自检例必红（缺 --session 不再被拒）"
t4_assert_contains "$mut_out" "护栏①" "变异自证：红得点名「护栏①」（不是笼统失败）"

# ---------------------------------------------------------------- 静态自检：调用点位单一 + 禁固定 sleep
FXG="$LAB/lint"
mkdir -p "$FXG"; cp "$BE_LIB" "$FXG/lib-backend.sh"
viol="$(t4_scan_host_pane_refs "$FXG")"
t4_assert_eq "" "$viol" "静态①：lib-backend 无命令行位裸 tmux 调用（复用 #84 行级 lint；tmux 恒经 _be_tmux 带 -S）"
# herdr 裸调用点位：行级静态只认**命令位**（行首 / `;` / `$(` / `{` 之后，可带 exec/setsid 前缀）；
#   字符串字面量里的 `herdr xxx` 不纳管（本文件报错文案含该类文本）—— 与 #84 行级 lint 同口径。
#   前缀集注：本文件的内联判据**比公共 lint 窄**（`lib.sh::t4_scan_herdr_bare_calls` 另有 `| & (`；
#   那条负责全 `cases` 目录，见 `cases/06`）—— 本处只自扫单文件，宽窄不同不影响二者合取从严。
# BR6④ 口径（P3-3）：调用必须带 `--session`（经唯一入口 `_be_herdr_exec` 注入）；
#   **白名单只此一条且整行等值**：整行恰为 `[exec|setsid] herdr --version`
#   （纯本地元数据：无会话参数、不读写任何会话/用户文件）。行内出现 `herdr --version` **不豁免**
#   （`herdr workspace list # herdr --version` / `herdr --version ; herdr workspace list` 均违规）。
#   注：本文件的内联判据**不剥行尾注释**（本文件无「尾注白名单」写法；剥注释在公共 lint 里）；
#   本文件现已**零豁免使用**：版本探针也改走唯一入口（旧写法 `$(herdr --version | …)` 属捕获壳，
#   在整行等值口径下就是裸调用）—— 白名单的正控留在 fixtures，不靠真实调用占位。
HRE='(^|;|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?herdr([[:space:]]|$)'
HWL='^[[:space:]]*(exec[[:space:]]+|setsid[[:space:]]+)?herdr[[:space:]]+--version[[:space:]]*$'
herdr_raw="$(grep -nE "$HRE" "$BE_LIB" | grep -vE '^[0-9]+:[[:space:]]*#')"
t4_assert_ge "2" "$(printf '%s\n' "$herdr_raw" | grep -c .)" "静态②：lib-backend 的 herdr 裸调用点位可被检出（非空转；口径 = 命令位）"
t4_assert_eq "0" "$(printf '%s\n' "$herdr_raw" | grep -v -- '--session' | grep -c .)" \
  "静态②：lib-backend 的裸调用点位 0 处缺 --session（--session 由唯一入口注入）"
be_fstart="$(grep -nE '^_be_herdr_exec[[:space:]]*\(\)' "$BE_LIB" | cut -d: -f1)"
be_fend="$(awk -v s="${be_fstart:-0}" 'NR>s && /^}/ {print NR; exit}' "$BE_LIB")"
be_outside="$(printf '%s\n' "$herdr_raw" | cut -d: -f1 | awk -v s="${be_fstart:-0}" -v e="${be_fend:-0}" '$1<s||$1>e')"
t4_assert_eq "" "$be_outside" "静态②：lib-backend 的裸 herdr 调用全部在 _be_herdr_exec 函数体内（唯一入口，无旁路）"
# 用例侧：白名单**零豁免使用**（P3-3 收紧：捕获壳写法不再算白名单；探针已走唯一入口）
case_raw="$(grep -nE "$HRE" "$BE_SELF" | grep -vE '^[0-9]+:[[:space:]]*#')"
case_wl="$(printf '%s\n' "$case_raw" | grep -E "$HWL")"
case_other="$(printf '%s\n' "$case_raw" | grep -vE "$HWL")"
t4_assert_eq "0" "$(printf '%s\n' "$case_wl" | grep -c .)" \
  "静态②：cases/27 白名单 0 处使用（版本探针走唯一入口；整行等值口径下捕获壳 = 裸调用）"
t4_assert_eq "" "$case_other" "静态②：cases/27 除白名单外无命令位裸 herdr 调用（其余一律经唯一入口）"
# 双向负控：① 伪造 `herdr workspace list` 裸调用 ⇒ 同一判据必红 ② 只放 `herdr --version` ⇒ 判据放行
NEG1="$LAB/lint-herdr-neg-bare.sh"; NEG2="$LAB/lint-herdr-neg-wl.sh"
printf 'herdr workspace list\n' > "$NEG1"
printf 'herdr --version\n' > "$NEG2"
t4_assert_eq "1" "$(grep -E "$HRE" "$NEG1" | grep -vE "$HWL" | grep -c .)" \
  "静态② 负控：伪造裸 herdr 调用 ⇒ 判据命中 1 处（非白名单 ⇒ 必红）"
t4_assert_eq "0" "$(grep -E "$HRE" "$NEG2" | grep -vE "$HWL" | grep -c .)" \
  "静态② 正控：仅 herdr --version ⇒ 判据放行（白名单不是空转）"
# P3-3 安全洞负控：白名单必须是**整行等值** —— 「裸调用 + 附带白名单片段」两形态必红
NEG3="$LAB/lint-herdr-neg-trick.sh"; NEG4="$LAB/lint-herdr-neg-semicolon.sh"
printf 'herdr workspace list # herdr --version\n' > "$NEG3"
# 夹具正文用 @H@ 占位再替换：本行若直接写 `; herdr …`，会被公共 lint 判成字符串字面量假阳
printf '@H@ --version ; @H@ workspace list\n' > "$NEG4"; sed -i 's/@H@/herdr/g' "$NEG4"
t4_assert_eq "1" "$(grep -E "$HRE" "$NEG3" | grep -vE "$HWL" | grep -c .)" \
  "静态② 负控（P3-3①）：裸调用 + 行尾注释伪造白名单 ⇒ 仍命中 1 处（整行等值才放行）"
t4_assert_eq "1" "$(grep -E "$HRE" "$NEG4" | grep -vE "$HWL" | grep -c .)" \
  "静态② 负控（P3-3②）：herdr --version 后接 ; 裸调用 ⇒ 仍命中 1 处（不是「行内出现即豁免」）"
t4_assert_eq "0" "$(grep -cE '(^|[[:space:];|&(])sleep[[:space:]]+[0-9]' "$BE_LIB" || true)" \
  "静态③：无固定 sleep（禁固定等待；就绪/等待只用轮询间隔）"
t4_assert_contains "$(grep -E 'BE_POLL_MAX|BE_POLL_INT' "$BE_LIB")" 'BE_POLL_MAX:-50' \
  "静态③：轮询参数单点 = 50 次（5s 上限 / 100ms 间隔见下一断言）"
t4_assert_contains "$(grep -E 'BE_POLL_MAX|BE_POLL_INT' "$BE_LIB")" 'BE_POLL_INT:-0.1' \
  "静态③：轮询间隔单点 = 100ms"

# ---------------------------------------------------------------- 两实验场：初始化 + 起 server
SESS_A="nao-t4-27-a-$$"; SESS_B="nao-t4-27-b-$$"
be_ctx() { be_init "$LAB/$1" "$2"; }   # 切换上下文（各自 lab 根 ⇒ 各自 socket / 私有 XDG 根）
be_ctx a "$SESS_A" || { t4_bad "be_init A 失败（$BE_NAME）"; t4_exit; }
SOCK_A="${BE_SOCK:-}"; ROOT_A="${BE_CFGROOT:-}"
be_ctx b "$SESS_B" || { t4_bad "be_init B 失败（$BE_NAME）"; t4_exit; }
SOCK_B="${BE_SOCK:-}"; ROOT_B="${BE_CFGROOT:-}"
PROD_SOCK="${TMUX%%,*}"; [ -n "$PROD_SOCK" ] || PROD_SOCK="/tmp/tmux-$(id -u)/default"
before_prod="$(tmux -S "$PROD_SOCK" list-panes -a -F '#{session_name}:#{pane_id}' 2>/dev/null || true)"

t4_assert_ne "$SESS_A" "$SESS_B" "隔离：两会话名唯一且不同（含 \$\$ 唯一化）"
t4_assert_match "$SESS_A" '^nao-t4-27-a-[0-9]+$' "隔离：会话名带 \$\$（跨次/并发不撞名）"
case "$BE_NAME" in
  tmux)
    t4_assert_contains "$SOCK_A" "$LAB/a/" "隔离：实验 socket 在实验根内（不存在裸打生产 server 的写法）"
    t4_assert_ne "/tmp/tmux-$(id -u)/default" "$SOCK_A" "隔离：实验 socket ≠ 生产默认候选" ;;
  herdr)
    t4_assert_ne "$ROOT_A" "$ROOT_B" "隔离：两实验场各自私有 XDG_CONFIG_HOME 根（互不可见）" ;;
esac

be_ctx a "$SESS_A" || { t4_bad "be_init A 复入失败"; t4_exit; }
be_start_server >/dev/null || { t4_bad "A server 起不来（$BE_NAME）"; t4_exit; }
t4_assert_eq "1" "$BE_START_EFFECT" "就绪：A server 首次起（effect=1）且 5s 轮询内就绪（无固定 sleep）"
be_start_server >/dev/null || { t4_bad "A server 二次起失败"; t4_exit; }
t4_assert_eq "0" "$BE_START_EFFECT" "幂等：A 已就绪时再起 ⇒ effect=0（AC1.7 连跑 2 次 effect=0）"
PANE_A="$(be_new_pane)" || { t4_bad "A 建 pane 失败"; t4_exit; }

be_ctx b "$SESS_B" || { t4_bad "be_init B 复入失败"; t4_exit; }
be_start_server >/dev/null || { t4_bad "B server 起不来（$BE_NAME）"; t4_exit; }
t4_assert_eq "1" "$BE_START_EFFECT" "就绪：B server 首次起（effect=1；两场各自独立）"
PANE_B="$(be_new_pane)" || { t4_bad "B 建 pane 失败"; t4_exit; }

PA="$(be_ctx a "$SESS_A" && be_panes)"; PB="$(be_ctx b "$SESS_B" && be_panes)"
t4_assert_ge "1" "$(printf '%s\n' "$PA" | grep -c .)" "隔离：A 实验场 pane 视图可观测（≥1；会话/workspace 自带）"
t4_assert_ge "1" "$(printf '%s\n' "$PB" | grep -c .)" "隔离：B 实验场 pane 视图可观测（≥1）"
inter="$(comm -12 <(printf '%s\n' "$PA" | cut -f2 | sort -u) <(printf '%s\n' "$PB" | cut -f2 | sort -u) | grep -c . || true)"
t4_assert_eq "0" "$inter" "隔离：两会话 terminal_id 交集为空（AC1.4 互不可见）"
n_a0="$(printf '%s\n' "$PA" | grep -c .)"
be_ctx a "$SESS_A" >/dev/null || true
PANE_A2="$(be_new_pane)" || { t4_bad "A 增建 pane 失败"; t4_exit; }
t4_assert_eq "$((n_a0 + 1))" "$(be_panes | grep -c .)" "隔离：A 增建 pane ⇒ A pane 数 +1（pane 视图与实际一致）"
PB2="$(be_ctx b "$SESS_B" && be_panes)"
t4_assert_eq "$(printf '%s\n' "$PB" | sort)" "$(printf '%s\n' "$PB2" | sort)" "隔离：A 增建 pane 后 B 的 pane 集合逐字不变"

# ---------------------------------------------------------------- 反向护栏：清环境（BR6 四条）
be_ctx a "$SESS_A" >/dev/null || true
ENVF="$LAB/pane-env-a.txt"
be_run "$PANE_A" "env > $ENVF" || { t4_bad "A pane 内 env 落盘失败"; t4_exit; }
be_wait_until 50 0.1 test -s "$ENVF" || { t4_bad "A pane 内 env 未在 5s 内落盘"; t4_exit; }
case "$BE_NAME" in
  herdr)
    t4_assert_eq "0" "$(grep -c '^TMUX' "$ENVF" || true)" \
      "零渗透①：pane 内 env | grep -c '^TMUX' == 0（TMUX/TMUX_PANE/TMUX_TMPDIR 全清）"
    t4_assert_eq "$SESS_A" "$(sed -nE 's/^HERDR_SESSION=(.*)$/\1/p' "$ENVF")" \
      "零渗透②：pane 内 HERDR_SESSION == 期望会话名（未读到别的会话）"
    t4_assert_eq "$ROOT_A/herdr/sessions/$SESS_A/herdr.sock" \
      "$(sed -nE 's/^HERDR_SOCKET_PATH=(.*)$/\1/p' "$ENVF")" \
      "零渗透③：pane 内 HERDR_SOCKET_PATH == 实验根下该会话目录（验收口径：前缀在根内）"
    t4_assert_eq "$ROOT_A" "$(sed -nE 's/^XDG_CONFIG_HOME=(.*)$/\1/p' "$ENVF")" \
      "零渗透④：pane 内 XDG_CONFIG_HOME == 私有实验根（唯一被隔离的 XDG 变量）"
    st="$({ sed -nE 's/^XDG_STATE_HOME=(.*)$/\1/p' "$ENVF"; } || true)"
    if [ -n "${XDG_STATE_HOME:-}" ]; then
      t4_assert_eq "$XDG_STATE_HOME" "$st" "零渗透④反向：XDG_STATE_HOME 透传未改（== 调用方值；不得指向实验根，mise 等会写它）"
    else
      t4_assert_ne "$ROOT_A" "${st%/}" "零渗透④反向：XDG_STATE_HOME 未被指向实验根（mise 等工具会写它）"
    fi
    sockpath="$(sed -nE 's/^HERDR_SOCKET_PATH=(.*)$/\1/p' "$ENVF")"
    case "$sockpath" in
      "$ROOT_A/herdr/sessions/$SESS_A/"*) t4_ok "零渗透③：HERDR_SOCKET_PATH 前缀在实验根内（实验根下该会话目录）" ;;
      *) t4_bad "零渗透③：HERDR_SOCKET_PATH 前缀不在实验根内（实际=$sockpath 期望前缀=$ROOT_A/herdr/sessions/$SESS_A/）" ;;
    esac
    ;;
  tmux)
    t4_assert_eq "$SOCK_A" "$(sed -nE 's/^TMUX=(.*)$/\1/p' "$ENVF" | cut -d, -f1)" \
      "零渗透（tmux 对偶）：pane 内 TMUX socket == 隔离 socket（未打用户 server）"
    ;;
esac

# ---------------------------------------------------------------- default 不可达（BR9）
case "$BE_NAME" in
  herdr)
    JS_A="$(be_herdr "$SESS_A" session list --json 2>/dev/null)"
    def_state="$(JS="$JS_A" EXPR='sessions.find(s=>s.default)?.running' json_probe 2>/dev/null)"
    def_dir="$(JS="$JS_A" EXPR='sessions.find(s=>s.default)?.session_dir' json_probe 2>/dev/null)"
    t4_assert_eq "false" "$def_state" "default 不可达：私有根下 default == stopped（用户 default 本次视角不可见）"
    t4_assert_eq "$ROOT_A/herdr" "$def_dir" "default 不可达：私有根的 default 目录在实验根内（结构上碰不到用户会话）"
    t4_assert_ne "" "$(printf '%s' "$JS_A" | grep -o "$SESS_A" | head -1)" \
      "default 不可达：私有根会话表里只有自己的会话（无用户会话条目）"
    ;;
  tmux)
    t4_assert_contains "$(tmux -S "$SOCK_A" list-sessions -F '#{session_name}' 2>/dev/null)" "$SESS_A" \
      "default 不可达：实验 server 内只有本实验会话（隔离 socket 自带）"
    ;;
esac

# ---------------------------------------------------------------- 孤儿 sweep（P2 缺陷修复）
# 缺陷现场（PM 实测）：server 用 `setsid` 脱离进程组 ⇒ 用例被中断/失败时 EXIT 钩子杀不掉它，
#   而 T524 口径「失败保留 cache」⇒ 每次失败留一个常驻 server（比目录泄漏更重）。
# 三层防护：① 起跑前扫孤儿 ② 失败/中断 EXIT 兜底 ③ 正常拆场。本组按 **effect** 断言，不看 rc。
if [ "$BE_NAME" = "herdr" ]; then
  t4_assert_eq "no" "$(_be_is_lab_root "$HOME/.config/herdr" && echo yes || echo no)" \
    "孤儿 sweep①：用户 herdr 根结构上不算实验根（判据里根本选不中它）"
  user_before="$(_be_scan_herdr_servers | awk -F'\t' '$3 !~ /nao-t4\./ {print $1}' | sort -u)"
  # 造孤儿：陈旧 cache 形态的实验根（**无活 run 持有**，与实测现场同形）+ 起 server 后「不 teardown」
  SWEEP_CACHE="$T4_CACHE_PARENT/nao-t4.sweep-$$"
  SWEEP_LAB="$SWEEP_CACHE/lab"
  BE_CFGROOT="$SWEEP_LAB/config"; BE_SESSION="nao-t4-27-sweep-$$"; BE_CACHE_ROOT="$SWEEP_CACHE"
  be_start_server >/dev/null 2>&1 || t4_bad "孤儿构造：server 起不来（$BE_NAME）"
  SWEEP_PID="$(_be_scan_herdr_servers | awk -F'\t' -v r="$SWEEP_LAB/config" '$3==r{print $1; exit}')"
  t4_assert_ne "" "${SWEEP_PID:-}" "孤儿 sweep②：复现现场 —— 「失败/中断未收尾」的 server 仍在跑（pid 已取，无人 stop）"
  t4_assert_eq "1" "$(be_orphan_server_count "$SWEEP_LAB/config")" "孤儿 sweep②：该实验根下 server 数 = 1（与 PM 实测同形）"
  be_sweep_orphans; sw_rc=$?
  t4_assert_eq "0" "$sw_rc" "孤儿 sweep③：sweep rc=0（失败逐条点名，不静默）"
  # P3-1（QA · 假红修正）：sweep 语义是「清**所有**死残留」⇒ 断「本 run 自己的 root 归零 + effect 非零」，
  #   **不**断绝对值 —— 否则把用例与「环境里恰好只有我这一个残留」耦合（直跑遇到别的死残留就假红）。
  t4_assert_ge "1" "${BE_SWEEP_EFFECT:-0}" "孤儿 sweep③：sweep effect ≥ 1（实际 ${BE_SWEEP_EFFECT:-0}；真停掉了死残留，不断绝对值）"
  t4_assert_eq "0" "$(be_orphan_server_count "$SWEEP_LAB/config")" "孤儿 sweep③：本 run 自己的 root 已归零（server 数 = 0）"
  be_sweep_orphans; sw_rc2=$?
  t4_assert_eq "0" "$BE_SWEEP_EFFECT" "孤儿 sweep④：幂等 —— 连跑 2 次 effect=0（rc=$sw_rc2）"
  t4_assert_eq "0" "$(ls -A "$SWEEP_LAB/config/herdr/sessions" 2>/dev/null | grep -c . || true)" \
    "孤儿 sweep④：遗留会话场一并清掉（sessions/ 空）"
  rm -rf "$SWEEP_CACHE"
  t4_assert_ge "1" "$(be_orphan_server_count "$ROOT_A")" \
    "孤儿 sweep⑤ 负控：本 run 自己的场（活 cache）不被 sweep 误杀"
  # 失败路径兜底（EXIT 钩子）：子进程起 server 后 exit 1、**不调 teardown** ⇒ 退出即被停
  EXIT_LAB="$LAB/exitlab"
  ch_out="$(bash -c 'set -uo pipefail; source "$1"; source "$2"; be_init "$3" "$4" || exit 9; be_start_server || exit 9; exit 1' \
            _ "$T4_ROOT/tests/t4/lib.sh" "$BE_LIB" "$EXIT_LAB" "nao-t4-27-exit-$$" 2>&1)"; ch_rc=$?
  t4_assert_eq "1" "$ch_rc" "孤儿 sweep⑥：子进程按预期 rc=1 退出（失败路径；EXIT 兜底不得改退出码）"
  t4_assert_contains "$ch_out" "BE-CLEANUP" "孤儿 sweep⑥：兜底钩子点火（BE-CLEANUP 点名本场会话）"
  t4_assert_eq "0" "$(be_orphan_server_count "$EXIT_LAB/config")" "孤儿 sweep⑥：子进程退出后该 root server 数 = 0（EXIT 兜底生效）"
  user_after="$(_be_scan_herdr_servers | awk -F'\t' '$3 !~ /nao-t4\./ {print $1}' | sort -u)"
  t4_assert_eq "$user_before" "$user_after" \
    "孤儿 sweep⑦ 负控：用户 herdr server 集合 sweep 前后逐字一致（未被误杀；本机基线 ${user_before:-<无>}）"
  # 归位：恢复本 run 的 cache 根与失败兜底（sweep 停过 scratch 场，可能已卸 flag）
  BE_CACHE_ROOT="$T4_CACHE_DIR"
  be_ctx a "$SESS_A" >/dev/null 2>&1 || true
  be_arm_cleanup
fi

# ---------------------------------------------------------------- 零残留前置：pane 内长驻进程（拆场应带走）
printf 'sleep 600\n' > "$LAB/marker-a.sh"
printf 'sleep 600\n' > "$LAB/marker-b.sh"
be_ctx a "$SESS_A" >/dev/null || true
be_run "$PANE_A2" "exec bash $LAB/marker-a.sh"
be_wait_until 50 0.1 pgrep -f "$LAB/marker-a.sh" || t4_bad "A 标记进程未在 5s 内起来（零残留断言前提）"
PID_A="$(be_pane_pid "$PANE_A2" || true)"
be_ctx b "$SESS_B" >/dev/null || true
be_run "$PANE_B" "exec bash $LAB/marker-b.sh"
be_wait_until 50 0.1 pgrep -f "$LAB/marker-b.sh" || t4_bad "B 标记进程未在 5s 内起来（零残留断言前提）"
PID_B="$(be_pane_pid "$PANE_B" || true)"
t4_assert_ne "" "${PID_A:-}" "零残留前置：A pane 进程 pid 取到（$BE_NAME 结构化字段，非标题解析）"
t4_assert_ne "" "${PID_B:-}" "零残留前置：B pane 进程 pid 取到"

# ---------------------------------------------------------------- 拆场：effect 判据（不信 rc）
be_ctx a "$SESS_A" >/dev/null || true
be_teardown; rc_a1=$?
t4_assert_eq "0" "$rc_a1" "拆场①：A stop+delete rc=0（stop 第二次非 0 由实现容忍，判据看 effect）"
t4_assert_eq "1" "$BE_TEARDOWN_EFFECT" "拆场①：A 首次拆场 effect=1（会话真的被清掉）"
be_teardown; rc_a2=$?
t4_assert_eq "0" "$rc_a2" "拆场②：A 二次拆场 rc=0（delete 幂等）"
t4_assert_eq "0" "$BE_TEARDOWN_EFFECT" "拆场②：A 二次拆场 effect=0（连跑 2 次 effect=0）"
be_ctx b "$SESS_B" >/dev/null || true
be_teardown; rc_b1=$?
t4_assert_eq "1" "$BE_TEARDOWN_EFFECT" "拆场③：B 拆场 effect=1（rc=$rc_b1）"

# ---------------------------------------------------------------- 零残留
t4_assert_eq "0" "$(pgrep -f "$LAB/marker-a.sh" | grep -c . || true)" "零残留①：A 标记进程 0 个（后端拆场带走 pane 内进程）"
t4_assert_eq "0" "$(pgrep -f "$LAB/marker-b.sh" | grep -c . || true)" "零残留②：B 标记进程 0 个"
ok_a=0; kill -0 "$PID_A" 2>/dev/null && ok_a=1
ok_b=0; kill -0 "$PID_B" 2>/dev/null && ok_b=1
t4_assert_eq "0" "$ok_a" "零残留③：A pane shell pid 已退出"
t4_assert_eq "0" "$ok_b" "零残留④：B pane shell pid 已退出"
case "$BE_NAME" in
  herdr)
    t4_assert_eq "0" "$(ls -A "$(be_sessions_dir)" 2>/dev/null | grep -c . || true)" \
      "零残留⑤：实验根 sessions/ 为空（BR4：stop+delete 后无残留会话场）" ;;
  tmux)
    if tmux -S "$SOCK_A" list-sessions >/dev/null 2>&1; then t4_bad "零残留⑤：隔离 socket 上仍有 server"; else t4_ok "零残留⑤：隔离 socket 上无 server 存活"; fi
    if tmux -S "$SOCK_B" list-sessions >/dev/null 2>&1; then t4_bad "零残留⑤：B 隔离 socket 上仍有 server"; else t4_ok "零残留⑤：B 隔离 socket 上无 server 存活"; fi ;;
esac
after_prod="$(tmux -S "$PROD_SOCK" list-panes -a -F '#{session_name}:#{pane_id}' 2>/dev/null || true)"
t4_assert_eq "$before_prod" "$after_prod" "default 不可达：生产 tmux server 快照 diff 空（本用例全程未触及用户 pane）"

t4_exit
