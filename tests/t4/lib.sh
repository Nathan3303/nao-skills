#!/usr/bin/env bash
# T4 用例公共库 —— PRD #18「nao-skills 单 SKILL 化 + pi 原生分发」
#
# 约束（路径纪律）：本套用例只新增 tests/ 与 docs/reports/2026-10-08-T4-*.md，
# 不修改 package.json / bin/ / .agents/。所有夹具建在临时目录，不改仓库工作区。
#
# 契约来源：PRD §7 AC1/AC3/AC4/AC6 · §11 D3/D5/D6/D7 · §12-A/B/C/D
#           T1 报告 docs/reports/2026-10-08-T1-pi-package-verify.md（pi 1.1.0 实测）
#
# 退出码约定（用例脚本）：
#   0  = PASS      1  = FAIL      77 = SKIP（环境能力缺失）   78 = BLOCKED（依赖的 T2 产物未交付）
# 默认严格：依赖物缺失即 FAIL。仅显式 T4_ALLOW_MISSING=1 时降级为 BLOCKED（宽松）。
# T4_REQUIRE_FULL=1（发布前置）：汇总层 SKIP 计数 + DEGRADE 计数必须均为 0，与 T4_ALLOW_MISSING 正交。
set -uo pipefail

T4_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T4_TESTS_DIR="$(cd "$T4_LIB_DIR/.." && pwd)"
T4_ROOT="${T4_ROOT:-$(cd "$T4_TESTS_DIR/.." && pwd)}"

PKG_NAME="@nathan33/nao-skill"
PKG_VERSION="$(node -p "try{require('${T4_ROOT}/package.json').version}catch(e){'0.0.0'}" 2>/dev/null || echo 0.0.0)"
T4_ALLOW_MISSING="${T4_ALLOW_MISSING:-0}"
T4_REQUIRE_FULL="${T4_REQUIRE_FULL:-0}"
T4_TARBALL="${T4_TARBALL:-}"

# ---------------------------------------------------------------- 夹具缓存生命周期（单点实现）
# 归属（BR3）：只有「本进程自己 mktemp 成功」的目录可被删。T4_CACHE_OWNED 不导出、
#   不从环境读取——只要 T4_CACHE_DIR 由外部传入（run.sh 导给用例、或 `export T4_CACHE_OWNED=1`
#   的越权调用）即在此强制 OWNED=0，防子进程先于父进程删掉本批缓存。
# 前缀（BR4）：删除守卫用创建时捕获的 $T4_CACHE_PARENT（禁硬编码 /tmp）。
# 逃生口：T4_KEEP_CACHE=1（env-only）⇒ 恒保留。
# T4_CACHE_NO_CREATE=1：只读探测（run.sh --preflight 的 `source lib.sh` 子进程）抑制建目录（BR8）。
T4_CACHE_PARENT="${TMPDIR:-/tmp}"
T4_KEEP_CACHE="${T4_KEEP_CACHE:-0}"
T4_CACHE_OWNED=0
if [ -z "${T4_CACHE_DIR:-}" ] && [ "${T4_CACHE_NO_CREATE:-0}" != "1" ]; then
  if T4_CACHE_DIR="$(mktemp -d "$T4_CACHE_PARENT/nao-t4.XXXXXX")"; then
    T4_CACHE_OWNED=1
  else
    T4_CACHE_DIR=""
    printf 'T4 夹具缓存创建失败（mktemp: %s/nao-t4.XXXXXX）；不空值续跑（BR9）\n' "$T4_CACHE_PARENT" >&2
    exit 1
  fi
fi
T4_CACHE_DIR="${T4_CACHE_DIR:-}"
# 兜底（BR3）：外部传入的 T4_CACHE_DIR 一律不归属本进程；并摘掉可能继承来的导出属性。
export -n T4_CACHE_OWNED

# 删除单点：两条回收路径（t4_cache_cleanup / t4_reclaim_stale_caches）共用，全 tests/t4 下唯一的
# `rm -rf --` 语句（cases/14 ⑳ 的静态契约依赖此唯一性）。
_t4_rm_cache_dir() { rm -rf -- "$1" 2>/dev/null; }

# t4_cache_cleanup —— 清理逻辑唯一实现点（BR10：run.sh / cases 复用，不复制）。
# BR5：EXIT trap 内 `local rc=$?; …; return $rc`，禁 exit（不得吞/改退出码）。
t4_cache_cleanup() {
  local rc=$?
  local dir="${T4_CACHE_DIR:-}"
  [ "${T4_CACHE_OWNED:-0}" = "1" ] || return "$rc"                        # BR3 仅自建
  [ "${T4_KEEP_CACHE:-0}" = "1" ] && return "$rc"                          # 逃生口
  [ "$rc" = "0" ] || return "$rc"                                          # BR7 失败一律保留
  [ -n "$dir" ] || return "$rc"                                            # BR4① 非空
  case "$dir" in "$T4_CACHE_PARENT"/nao-t4.*) ;; *) return "$rc" ;; esac  # BR4② 前缀（取自捕获值）
  [ "${dir%/*}" = "$T4_CACHE_PARENT" ] || return "$rc"                    # BR4② 仅一层（防 glob 吃路径穿越）
  [ -d "$dir" ] || return "$rc"                                            # BR4③ 是目录
  [ ! -L "$dir" ] || return "$rc"                                          # BR4④ 非软链
  [ "$dir" != "/" ] || return "$rc"                                        # BR4⑤ 非根
  _t4_rm_cache_dir "$dir" || printf 'T4 缓存清理失败（已保留目录）: %s\n' "$dir" >&2  # BR9 不改 rc
  return "$rc"
}
trap t4_cache_cleanup EXIT

# ---------------------------------------------------------------- 陈旧缓存回收（#121）
# 背景：EXIT trap 捕不到 SIGKILL，起跑 sweep 只在「下次运行」生效 ⇒ 硬掐（实测 32M / 63 条）的残留
#   可能一直躺着。本段只在**启动期**（source lib.sh 时；run.sh 与各用例共用同一条路，无第二处调用点）
#   回收「超过 T4_STALE_CACHE_HOURS 小时 **且** 无活进程关联」的兄弟缓存目录。
# 判据双向（cases/14 ㉑–㉘）：正控 8h + 无进程 ⇒ 清；负控① 1h ⇒ 不清；负控② 8h + 活进程 ⇒ 不清。
# 安全边界（与 t4_cache_cleanup 同源）：仅 $T4_CACHE_PARENT 下一层、名 nao-t4.*、是目录、非软链、
#   非本次使用的 $T4_CACHE_DIR（用户传入的陈旧目录亦不删）。
# 路径口径（#121 二轮 AC7/AC8）：归属与活进程的比对一律先 `realpath -m` **归一**再判「等于/前缀」
#   ⇒ 尾斜杠 / 相对路径 / 软链拼写的同一目录不会被误判为「不同目录」。
# 逃生口：T4_KEEP_CACHE=1 ⇒ 整段跳过（调试期一条都不删）；T4_CACHE_NO_CREATE=1（只读探测）⇒ 跳过。
# 可观测：真清过才打印一行（条数 + 路径前缀）；删除失败逐条 WARN 点名；恒返回 0（不改退出码）。
T4_STALE_CACHE_HOURS="${T4_STALE_CACHE_HOURS:-6}"

# 路径归一单点（AC7/AC8）：`realpath -m` 不要求路径存在，且会把尾斜杠 / 相对路径 / 软链统一成
#   绝对物理路径。调用方必须先 `command -v realpath` 把关，否则本函数失败（不猜）。
_t4_realpath() {
  local p="${1:-}"
  [ -n "$p" ] || return 1
  realpath -m -- "$p" 2>/dev/null
}

# 活进程关联（$@ = **已归一**的候选目录）⇒ 输出「在用」的候选（去重）。
# 两条判据各自独立生效（AC8/AC9）：
#   ① cwd 判据：`readlink /proc/<pid>/cwd` 已给物理路径 ⇒ 与归一候选直接比「等于 / 在其下」；
#      本分支**不依赖 environ 可读**（QA P3-1：旧写法先 `[ -r environ ] || continue` 会连带跳过 cwd）。
#   ② env 判据：`T4_CACHE_DIR` 归一后「等于候选」或「落在候选之下」（后者 = 指向子目录也算在用）；
#      相对值按**该进程自己的 cwd** 解析（不是本进程的 cwd）。
# 只读 /proc（本套用例本就依赖 Linux /proc），不引 lsof / fuser；一次扫完供逐候选比对。
_t4_cache_roots_in_use() {
  local d rawcwd cwd val root c
  for d in /proc/[0-9]*; do
    rawcwd="$(readlink "$d/cwd" 2>/dev/null)" || rawcwd=""
    cwd="$rawcwd"
    # 预筛**只作用于 cwd 判据本身**（充要性：候选末段恒为 nao-t4.* ⇒ 等于/在其下的路径必含该串）；
    # env 分支不得用被清空的 cwd（P3-5：相对值的基准必须是原始 cwd）。
    case "$cwd" in */nao-t4.*|*/nao-t4.*/*) ;; *) cwd="" ;; esac
    if [ -n "$cwd" ]; then
      for c in "$@"; do
        [ "$cwd" = "$c" ] && printf '%s\n' "$c"
        case "$cwd" in "$c"/*) printf '%s\n' "$c" ;; esac
      done
    fi
    [ -r "$d/environ" ] || continue
    val="$(tr '\0' '\n' < "$d/environ" 2>/dev/null | sed -nE 's/^T4_CACHE_DIR=(.*)$/\1/p' | head -1)"
    [ -n "$val" ] || continue
    case "$val" in
      /*) root="$val" ;;
      *) [ -n "$rawcwd" ] && root="$rawcwd/$val" || continue ;;
    esac
    root="$(_t4_realpath "$root")" || continue
    [ -n "$root" ] || continue
    for c in "$@"; do
      [ "$root" = "$c" ] && printf '%s\n' "$c"
      case "$root" in "$c"/*) printf '%s\n' "$c" ;; esac
    done
  done 2>/dev/null | sort -u
}

t4_reclaim_stale_caches() {
  local parent="${T4_CACHE_PARENT:-}" dir norm mtime now limit n=0 live="" cur="" i
  local -a raw=() normd=() mt=() stale=() stalend=()
  [ -n "$parent" ] || return 0
  [ "${T4_KEEP_CACHE:-0}" = "1" ] && return 0                          # 逃生口：一条都不删
  [ "${T4_CACHE_NO_CREATE:-0}" = "1" ] && return 0                     # 只读探测：无副作用
  case "$T4_STALE_CACHE_HOURS" in ''|*[!0-9]*) return 0 ;; esac          # 非法阈值不猜
  [ "$T4_STALE_CACHE_HOURS" -gt 0 ] || return 0                         # AC10：0 等同全清 ⇒ 跳过
  command -v stat >/dev/null 2>&1 && command -v realpath >/dev/null 2>&1 || {
    printf '陈旧缓存回收: WARN 缺少 stat/realpath，跳过本轮（未删任何目录）\n' >&2; return 0; }
  cur="$(_t4_realpath "${T4_CACHE_DIR:-}")" || cur=""
  # 形态合格（一层 / 目录 / 非软链 / 非本次使用的目录）⇒ 收集归一路径 + mtime，暂不扫 /proc
  for dir in "$parent"/nao-t4.*; do
    [ -d "$dir" ] && [ ! -L "$dir" ] || continue
    [ "${dir%/*}" = "$parent" ] || continue
    norm="$(_t4_realpath "$dir")" || continue
    [ -n "$norm" ] || continue
    [ -n "$cur" ] && [ "$norm" = "$cur" ] && continue                  # AC7 归属守卫（归一后判等）
    mtime="$(stat -c %Y -- "$dir" 2>/dev/null)" || continue
    case "$mtime" in ''|*[!0-9]*) continue ;; esac
    raw+=("$dir"); normd+=("$norm"); mt+=("$mtime")
  done
  [ "${#raw[@]}" -gt 0 ] || return 0                                     # 稳态：不扫 /proc
  now="$(date +%s)"; limit=$((T4_STALE_CACHE_HOURS * 3600))
  for i in "${!raw[@]}"; do
    [ $((now - mt[i])) -gt "$limit" ] || continue                        # 未来时间戳 ⇒ 不清
    stale+=("${raw[$i]}"); stalend+=("${normd[$i]}")
  done
  [ "${#stale[@]}" -gt 0 ] || return 0
  live="$(_t4_cache_roots_in_use "${stalend[@]}")"
  for i in "${!stale[@]}"; do
    if [ -n "$live" ] && grep -qxF -- "${stalend[$i]}" <<< "$live"; then continue; fi  # 活进程在用 ⇒ 不清
    if _t4_rm_cache_dir "${stale[$i]}"; then
      n=$((n + 1))
    else
      printf '陈旧缓存回收: WARN 删除失败（已保留）: %s\n' "${stale[$i]}" >&2
    fi
  done
  [ "$n" -gt 0 ] && printf '陈旧缓存回收: 已清 %d 个（> %sh 且无活进程）: %s/nao-t4.*\n' \
    "$n" "$T4_STALE_CACHE_HOURS" "$parent"
  return 0
}

# 启动期回收：挂在 source 末尾 ⇒ run.sh 与各用例同一条路（不再有第二处调用点）。
t4_reclaim_stale_caches

export T4_ROOT PKG_NAME PKG_VERSION T4_CACHE_DIR T4_ALLOW_MISSING T4_REQUIRE_FULL T4_TARBALL

# ---------------------------------------------------------------- 宿主环境净化（#111 / T544）
# 宿主 herdr 会话会把**生产脚本的内部旗标**漏进 pane env。
#   T543：生产侧 `nao-fleet.sh` 用「函数调用前置变量赋值」传「我是起 server 者」⇒ bash 会把它交给子进程
#         ⇒ herdr server 继承 ⇒ 它创建的 pane 全量继承 ⇒ 用例侧靠本行 `unset` 兜底。
#   T544（Issue #116）：生产侧已改为**显式枚举/首参数**传信号（不再读写这个环境变量，pane env 也不再有它）
#         ⇒ 本兜底已冗余，**摘除**（保留等于拿测试侧掩盖生产侧，且注释描述的实现已不在）。
#         旧 pane（旧 server 起的）即使仍带该变量也无影响：生产脚本不再读它。
# 注意仍**不动** HERDR_* 契约变量 —— cases/06 的默认值探针与 cases/27 的生产端点锚需要宿主真实的 HERDR_*。

T4_FAIL=0
T4_DEGRADE=0
T4_RC=0
T4_OUT=""
T4_ERR=""

# ---------------------------------------------------------------- 宿主终端句柄：HERDR_* 清除清单（**单源**）
# 背景（#130 D2 = T543-O2）：herdr 宿主会把 HERDR_ENV / HERDR_SESSION / HERDR_SOCKET_PATH … 导出进 pane；
#   夹具若漏清一个，就会「打到生产 server / 读到生产会话 / 拿生产 socket 当夹具端点」—— 这类假绿
#   （#111 同类渗漏）不报错、只让断言失真。旧实现把清单手写在 4 处（lib-backend `envs` /
#   cases/06 `B3_CLEAN_ENV` / cases/28 `TMUX_FIELD_ENV` + 两处直连 `env` 逐项清 HERDR_ENV/HERDR_SESSION）
#   ⇒ 加一个新的 HERDR_* 要改 3–5 处，漏一处即渗漏。
# 形态（单一事实 + 派生参数）：
#   T4_HERDR_ENV_VARS   = 变量名数组（**唯一**需要维护的地方）
#   T4_HERDR_UNSET_ARGS = 由上面派生的 `env -u <名>` 参数数组（调用点只用这个，**不得**再手写变量名）
# ⇒ 新增一个 HERDR_* 只改 T4_HERDR_ENV_VARS 一行。枚举集合由 cases/06 的 golden 断言钉死（只增不减）。
# 注意：cases/35 的动态枚举（`env | grep -o '^HERDR_[A-Z_]*'`）是**超集**清法，不需要登记，故意不改。
T4_HERDR_ENV_VARS=(HERDR_ENV HERDR_SESSION HERDR_SOCKET_PATH HERDR_SOCKET_FILE
                   HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID HERDR_BIN_PATH)
T4_HERDR_UNSET_ARGS=()
for _t4_hv in "${T4_HERDR_ENV_VARS[@]}"; do T4_HERDR_UNSET_ARGS+=(-u "$_t4_hv"); done
unset _t4_hv

# ---------------------------------------------------------------- 输出 / 断言
t4_log()  { printf '%s\n' "$*"; }
t4_ok()   { printf '  [PASS] %s\n' "$*"; }
t4_bad()  { T4_FAIL=$((T4_FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
# NOTE 白名单（T531 · BR1）：tag 枚举的**单点定义** —— run.sh 复用本数组做合法性判定。
# 新增 tag 必须同时改这里 + 在 tests/README.md「NOTE 白名单」写明理由（缺一不可）。
# 语义：static-contract=静态替代证据 · pin-fallback=pin 未发布改对照 latest · migrate-fallback=缺 migrate 走 init
#        baseline-selfequiv=AC5① 基线 fixture 正文 == 被测脚本正文（本轮对照为自等价，非零回归证据）
#        backend-gate=断言组按后端门控（该行为本后端结构上不可达/不可执行；门控点必须点名理由，禁静默跳过）
T4_NOTE_TAGS=(static-contract pin-fallback migrate-fallback baseline-selfequiv backend-gate backend-no-signal)

# tag 是否登记在白名单（判定唯一入口；run.sh 聚合层调用）
t4_note_tag_registered() {
  local t="${1:-}" x
  [ -n "$t" ] || return 1
  for x in "${T4_NOTE_TAGS[@]}"; do [ "$t" = "$x" ] && return 0; done
  return 1
}

# NOTE = 用例产出的事实（合法能力/前提说明）；**不合规判定只在 run.sh 聚合层**（BR2，本函数从不 exit）。
#   t4_note <tag> <msg>   —— 规范形式；tag 须来自 T4_NOTE_TAGS
#   t4_note <msg>         —— 旧式调用（无 tag，兼容旧分支）：仍打印，非 full 仅警告，full 下判 FAIL
# 输出形态（run.sh 按行首 `[NOTE]` + 首个 token 解析）：`  [NOTE] <tag> <msg>` / `  [NOTE] (untagged) <msg>`
t4_note() {
  if [ "$#" -ge 2 ] && [ -n "${1:-}" ]; then
    printf '  [NOTE] %s %s\n' "$1" "${*:2}"
  else
    printf '  [NOTE] (untagged) %s\n' "$*"
  fi
}
# 能力降级（环境缺能力但**继续跑其余断言**）：打印可计分标记 [DEGRADE] + 累加；由 run.sh 汇总并计入 full 判据。
# 与 t4_skip 的区别：t4_skip 会终止用例（77）；t4_degrade 不终止，默认豁免、T4_REQUIRE_FULL=1 时计分。
t4_degrade() { T4_DEGRADE=$((T4_DEGRADE + 1)); printf '  [DEGRADE] %s\n' "$*"; }
t4_info() { printf '  -- %s\n' "$*"; }

t4_exit() {
  if [ "$T4_FAIL" -gt 0 ]; then
    printf 'RESULT: FAIL (%d 项断言未过)\n' "$T4_FAIL"
    exit 1
  fi
  printf 'RESULT: PASS\n'
  exit 0
}

t4_skip() {
  printf 'SKIP: %s\n' "$1"
  if [ "$T4_FAIL" -gt 0 ]; then
    printf 'RESULT: FAIL (%d 项断言未过；SKIP 不掩盖已失败断言)\n' "$T4_FAIL"
    exit 1
  fi
  exit 77
}

# 依赖的 T2 产物缺失：默认严格=FAIL(1)；仅 T4_ALLOW_MISSING=1 宽松模式=BLOCKED(78)
t4_blocked() {
  if [ "$T4_FAIL" -gt 0 ]; then
    t4_bad "前置缺失且已有断言未过：$1"
    t4_exit
  fi
  if [ "$T4_ALLOW_MISSING" = "1" ]; then
    printf 'BLOCKED: %s\n' "$1"
    printf '（宽松模式 T4_ALLOW_MISSING=1；默认严格模式下缺失即判 FAIL）\n'
    exit 78
  fi
  t4_bad "前置缺失（strict 模式）：$1"
  t4_exit
}

t4_assert_eq()   { [ "$1" = "$2" ] && t4_ok "$3" || t4_bad "$3（期望=$1 实际=$2）"; }
t4_assert_ne()   { [ "$1" != "$2" ] && t4_ok "$3" || t4_bad "$3（不应等于 $1）"; }
t4_assert_ge()   { [ "$2" -ge "$1" ] 2>/dev/null && t4_ok "$3" || t4_bad "$3（期望>= $1 实际=$2）"; }
# 断言实现注意：printf 经**管道**送给 grep -q 在大输入 + 早退时会触发 SIGPIPE，pipefail 下把**命中**判成 FAIL
# （实测 case16 读 16KB 协议文件 ~10% 假 FAIL = T534-O2 根因）。改用 here-string：grep 读临时文件，无上游写者被中断。
t4_assert_contains()     { grep -qF -- "$2" <<< "$1" && t4_ok "$3" || t4_bad "$3（未包含: $2）"; }
t4_assert_not_contains() { grep -qF -- "$2" <<< "$1" && t4_bad "$3（不应包含: $2）" || t4_ok "$3"; }
t4_assert_match()        { grep -qE -- "$2" <<< "$1" && t4_ok "$3" || t4_bad "$3（不匹配正则: $2）"; }
t4_assert_file()   { [ -f "$1" ] && t4_ok "$2" || t4_bad "$2（文件不存在: $1）"; }
t4_assert_dir()    { [ -d "$1" ] && t4_ok "$2" || t4_bad "$2（目录不存在: $1）"; }
t4_assert_absent() { [ ! -e "$1" ] && t4_ok "$2" || t4_bad "$2（不应存在: $1）"; }

# ---------------------------------------------------------------- 环境 / 夹具
t4_require_cmd() { command -v "$1" >/dev/null 2>&1 || t4_blocked "环境缺少命令: $1"; }

# #84 A 行级 lint：用例不得在**命令行位直接调 `tmux`**（默认 socket ⇒ 生产 server）取 pane 数/做绝对断言。
#   判定：命令行位（行首 / | ; & ( $( { 之后）出现 tmux 或 $REAL_TMUX，且同串无 `-S`；
#   `command -v tmux` / `t4_require_cmd tmux` 豁免（非调用）。输出 "basename:line: content"。
#   覆盖边界：真实缺陷类（同 server 累积残留 + 全 server 计数 + `tail -1` 启发式）写法普遍带 `-S`，
#   **不在此 lint 覆盖面**；那类由下面的 `t4_scan_all_server_tail1`（#93 语义化 lint）守，
#   用例级解耦仍是 `cases/20` 的 reset_lab + 快照 diff。
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

# #96 延长线（步 2b）herdr 侧行级 lint：命令行位出现 `herdr` 必须**既在唯一入口
#   `_be_herdr_exec` 函数体内、又同串带 `--session`**（不在函数体 ⇒ 旁路；缺 `--session` ⇒
#   实测会静默读到用户 `default` 会话）。与上面 `t4_scan_host_pane_refs` 对称：行级、静态，
#   输出 "basename:line:content"（同格式），缩进注释先 trim 再判注释符。
#   判定（违规 = 以下同时成立）：① 命令位命中 herdr ② ¬「命中行在 `_be_herdr_exec` 函数体内」
#   ③ ¬「命中行带 `--session`」（②③ 是 AND：函数体外带 `--session` 仍是旁路，函数体内缺
#   `--session` 仍会打到用户会话）④ ¬白名单。
#   **命令位前缀集只有 7 种**（即判据正则的字符类）：行首 / `|` / `;` / `&` / `(` / `$(` / `{`
#   （其后可带 `exec` / `setsid` 前缀与空白）。**已知漏判**（本批不扩前缀集：扩了会引入新假阳，
#   边界只声明不改判据）：`herdr|wc -l`（管道无空白）、`env X=1 herdr …`、`X=1 herdr …`、
#   `! herdr …`、反引号 `` `herdr …` ``、`if herdr …` / `; then herdr …`（shell 关键字后的命令位）。
#   **已知假阳**（行级静态不解析 heredoc / 引号 / 续行 / 数据流）：heredoc 正文行首的 `herdr …`、
#   字符串字面量里的 `; herdr …` / `$(herdr …)` 等含命令位形态前缀的文本、跨行 `herdr \` ＋
#   换行 `--session`（会被判缺 `--session`）。这些目前仓内 0 命中 —— 属**声明边界**，不承诺判对。
#   白名单（显式且最小，**整行等值**，绝不是「行内出现就放行」）：剥掉行尾注释（空白 + `#` 起）
#   后，整行必须**恰好**是 `[exec|setsid] herdr --version`：
#     `^[[:space:]]*(exec[[:space:]]+|setsid[[:space:]]+)?herdr[[:space:]]+--version[[:space:]]*$`
#   理由：`herdr --version` 是纯本地元数据（不读会话、不连 server、不写用户文件），也因此无法
#   经唯一入口注入 `--session`（唯一入口的契约正是「注入 --session」）。
#   **行内出现不是豁免**（安全边界，禁改成子串匹配）：`herdr workspace list # herdr --version`、
#   `herdr --version ; herdr workspace list` 都是「裸调用 + 附带白名单片段」⇒ 违规。
#   白名单只有这一条：`--help` 等其它 `--` 旗标不豁免；新增条目必须在此逐条写理由。
#   函数体边界：文件内首个 `^_be_herdr_exec[[:space:]]*\(\)`（空格写法 `_be_herdr_exec () {`
#   同样识别）到其后首个 `^}`；一个文件最多认一个入口（多个入口 = 单点契约已破，属另案）。
#   覆盖面：tmux 侧那条守「裸 socket」，本 lint 守「绕过唯一入口 / 缺会话参数」—— 两者都**不**
#   判 herdr 的语义正确性（隔离/私有根见 `lib-backend.sh` 与 `cases/27`）。
t4_scan_herdr_bare_calls() { # $1=用例目录（扫其 *.sh）
  local dir="$1" f ln lnno body body_trim body_nc fstart fend inbody
  local re='(^|[|;&(]|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?herdr([[:space:]]|$)'
  local wl='^[[:space:]]*(exec[[:space:]]+|setsid[[:space:]]+)?herdr[[:space:]]+--version[[:space:]]*$'
  local sess='--session([[:space:]]|=|$)'
  for f in "$dir"/*.sh; do
    [ -f "$f" ] || continue
    fstart="$(grep -nE '^_be_herdr_exec[[:space:]]*\(\)' "$f" 2>/dev/null | head -1 | cut -d: -f1)"
    fend=""
    [ -n "$fstart" ] && fend="$(awk -v s="$fstart" 'NR>s && /^}/ {print NR; exit}' "$f")"
    while IFS= read -r ln; do
      lnno="${ln%%:*}"; body="${ln#*:}"
      body_trim="${body#"${body%%[![:space:]]*}"}"     # 缩进注释先 trim 再判注释符（与 #93 P3-2 同口径）
      case "$body_trim" in \#*) continue;; esac
      # 剥行尾注释（空白 + `#` 起）后**整行等值**判白名单 —— 行内出现 `herdr --version` 不豁免
      body_nc="$(printf '%s' "$body_trim" | sed 's/[[:space:]]#.*$//')"
      grep -qE -- "$wl" <<< "$body_nc" && continue
      inbody=0
      if [ -n "$fstart" ] && [ "$lnno" -ge "$fstart" ] && { [ -z "$fend" ] || [ "$lnno" -le "$fend" ]; }; then
        inbody=1
      fi
      [ "$inbody" = "1" ] && grep -qE -- "$sess" <<< "$body" && continue
      printf '%s:%s:%s\n' "$(basename "$f")" "$lnno" "$body_trim"
    done < <(grep -nE "$re" "$f")
  done
}

# #93 语义化 lint：真实缺陷类「全 server 计数（`list-panes -a`）+ 顺序启发式挑尾（`| tail -1`）」。
#   病根见 #84 P3-2：这类写法**普遍带 `-S`**（同一隔离 server 内跨块/跨次累积残留），
#   上面那条「命令行位裸 tmux 必须 -S」的行级 lint 对它零覆盖。
#   判定（行级、静态）：同一行内 `list-panes` 带全 server 旗标 `-a`，且 `list-panes` 所在的
#   **第一条**管道直接接只取末行的 `tail`（`tail -1` / `-n 1` / `-n1` / `--lines=1`）。
#   不看调用方是不是 `tmux`、也不看 socket 形态（`-S` / `-L` 均不解除风险）；
#   **不解析引号 / 续行 / 数据流**（行级静态判据的固有边界，下面逐类写明）。
#   输出 "basename:line: content"；命中即属缺陷类，应改「只数夹具窗口 / 快照 diff」。
#
#   承诺边界（#93 AC4 + 复核 P2-1：逐类写清纳管/不纳管 + 理由，禁止「声明比判据强」）：
#     纳管：`list-panes -a … | tail -1`（`list-panes` 前为行首/空白/`;`）—— 含包装函数
#           `TX list-panes -a … | tail -1`、显式 `tmux -S … list-panes -a … | tail -1`、
#           同行 `env tmux …` / `bash -c "tmux …"` 前缀、`tail -n 1` / `-n1` / `--lines=1`。
#     不纳管（**已知漏判**；理由 = 行级静态不解析引号/续行/数据流）：
#       ① 中间隔了别的管道：`list-panes -a … | grep -v x | tail -1` —— 判据只认**第一条**管道。
#       ② `list-panes` 紧跟 `(` / `"` / `$(`：`arr=(list-panes -a …)`、`args="list-panes -a …"`、
#          `x=$(list-panes -a … | tail -1)` —— 前缀只认行首/空白/`;`；末例是命令位置包裹，
#          前两例是变量间接拼装（判据不追数据流）。
#       ③ 跨行写法（`-a` 与 `| tail -1` 不在同一行）：行级 lint 不拼接续行。
#       ④ 两行变量拼装（先 `cmds="list-panes -a …"` 再 `tmux -S … $cmds | tail -1`）：不追数据流。
#          **同一行 `;` 之后调用整条命令变量**（`cmd="tmux … list-panes -a …"; $cmd | tail -1`）
#          同样不纳管：行级静态不追数据流，且 `;` 会截断 gap。
#       ⑤ `list-panes -a … | wc -l` / `| head -1`：只有全 server 计数或只取首行，缺「顺序挑尾」要件。
#       ⑥ `list-panes -t <target> … | tail -1`：会话/窗口定向采样，不是全 server 计数。
#     已知假阳（**不承诺判对**；理由 = 行级静态不解析引号）：
#       - 字符串字面量：`echo "run list-panes -a | tail -1"`（引号内文本被当代码）。
#       - `-a` 只在引号内：`list-panes -F '#{@x} -a ' | tail -1`（`-a` 不是真旗标）。
#       - 跨语句已收紧：`;` / `&&` 后的无关 `tail -1` 不得算同一条管道 —— gap 用
#         `([^|;&]|&[^&])*`（比 `[^|;&]*` 多容忍 `2>&1` 这类单个 `&`；代价 = 单 `&` 后台写法
#         （`… list-panes -a … & echo done | tail -1`）仍会命中，属**残余边界**，不承诺判对）。
#     #84 假阳 3 例（旧 lint 的 socket 判定面）：`tmux -S"$SOCK"` 紧贴 / 跨行 `tmux \` / `tmux -L`
#       —— 本 lint 不判 socket 形态，故均不纳管（这 3 类不构成新 lint 的承诺面）；
#       其中跨行若把 `-a` / `| tail -1` 拆两行，按 ③ 漏判。
#     #84 漏判 4 例（旧 lint 的命令行位判定面）：`env tmux …` / `bash -c "tmux …"` / 数组或变量
#       间接 / `TMUX=$SOCK tmux …` —— 本 lint 不看调用方，只看同行是否有 `list-panes -a` + 第一条
#       管道接 `tail`：同行出现的 `env` / `bash -c` 前缀纳管；数组/变量间接看形态 —— 调用与
#       `list-panes` 同行的命中（如 `args=(-S s); tmux "${args[@]}" list-panes -a … | tail -1`），
#       命令拼进变量字符串的按 ② 漏判；同一行 `;` 之后调用整条命令变量的按 ④ 漏判。
t4_scan_all_server_tail1() { # $1=用例目录
  local dir="$1" f ln body
  local re='(^|[[:space:];])list-panes([^|;&]|&[^&])*[[:space:]]-a[[:alnum:]]*([[:space:]]|$)([^|;&]|&[^&])*\|[[:space:]]*tail[[:space:]]+(-[0-9]*1|-n[[:space:]]*1|--lines=1)([^[:alnum:]]|$)'
  for f in "$dir"/*.sh; do
    [ -f "$f" ] || continue
    while IFS= read -r ln; do
      body="${ln#*:}"
      body="${body#"${body%%[![:space:]]*}"}"   # P3-2：先 trim 前导空白再判注释
      case "$body" in \#*) continue;; esac
      printf '%s:%s\n' "$(basename "$f")" "$ln"
    done < <(grep -nE "$re" "$f")
  done
}

# ---------------------------------------------------------------- T567-A：nao-fleet.sh = **文件集**
# 拆分（ADR 2026-11-24 §D3）后，`nao-fleet.sh` 只是入口（注释头 + CLI 解析 + 分发），实现分布
#   在 `fleet/lib/*.sh`（11 模块）。静态闸与计数断言一律按**文件集**扫：参数可传目录（⇒ 入口 +
#   `fleet/lib/*.sh`）或单个文件（负控副本 / 变异副本仍按单文件口径）。
#   证据面：任一模块都可以独立被扫，闸的强度不依赖「实现恰好在一个文件里」。
_t4_fleet_files() { # <dir|file>... → 文件清单（一行一个）
  local p f
  for p in "$@"; do
    if [ -d "$p" ]; then
      [ -f "$p/nao-fleet.sh" ] && printf '%s\n' "$p/nao-fleet.sh"
      for f in "$p"/fleet/lib/*.sh; do [ -f "$f" ] && printf '%s\n' "$f"; done
    else
      [ -f "$p" ] && printf '%s\n' "$p"
    fi
  done
}
# 公开包装：文件集清单（用例层只调它，不触 `_t4_fleet_files`）
t4_fleet_files() { _t4_fleet_files "$@"; }

# 单点输出格式：单文件 = `行号:内容`（负控副本口径逐字不变）；多文件 = `文件:行号:内容`（可定位）
_t4_emit() { # <多文件标记 ''|1> <文件> <行号> <内容>
  if [ -n "$1" ]; then printf '%s:%s:%s\n' "$(basename "$2")" "$3" "$4"
  else printf '%s:%s\n' "$3" "$4"; fi
}

# 计数：文件集内 `grep -cE` 逐文件相加（无命中 = 0；不因某文件 0 命中而中断）
t4_fleet_count() { # <ERE> <dir|file>...
  local re="$1"; shift
  local f c n=0
  while IFS= read -r f; do
    c="$(grep -cE -- "$re" "$f" 2>/dev/null || true)"
    n=$(( n + ${c:-0} ))
  done < <(_t4_fleet_files "$@")
  printf '%s\n' "$n"
}
# 顶层函数 → 所属文件（拆分的「哪个模块」查询单点；找不到 = 空 + rc=1）
t4_fleet_file_for() { # <dir> <函数名>
  local d="$1" fn="$2" f
  while IFS= read -r f; do
    grep -qE "^${fn}\\(\\) \\{" "$f" && { printf '%s\n' "$f"; return 0; }
  done < <(_t4_fleet_files "$d")
  return 1
}
# 定位串 → 所属文件（变异/断言用：不写死模块路径，实现搬家不误红）
t4_fleet_file_with() { # <dir|file> <fixed-string>
  local d="$1" pat="$2" f
  while IFS= read -r f; do
    grep -qF -- "$pat" "$f" && { printf '%s\n' "$f"; return 0; }
  done < <(_t4_fleet_files "$d")
  return 1
}
# 读面合并视图：把入口 + fleet/lib/*.sh 依次拼到一个临时文件（grep/awk 的「单文件」旧口径）。
#   只用于**只读断言**（计数/取函数体/取常量）；写面（sed -i 变异）必须落到真实模块文件。
t4_fleet_bundle() { # <scripts-dir> [输出路径]
  local src="$1" out="${2:-}"
  [ -n "$out" ] || out="$T4_CACHE_DIR/fleet-bundle.$$.sh"
  {
    while IFS= read -r f; do cat "$f"; printf '\n'; done < <(_t4_fleet_files "$src")
  } > "$out" || return 1
  printf '%s\n' "$out"
}

# 文件集指纹（"变异只动副本" 类断言的整集口径：入口 + fleet/lib 全部文件逐字节）
t4_fleet_md5() { # <scripts-dir>
  local f
  while IFS= read -r f; do md5sum "$f"; done < <(_t4_fleet_files "$1") | md5sum | awk '{print $1}'
}

# 克隆入口 + fleet/ 到新目录（变异副本必须整集可跑；返回入口路径）
t4_fleet_clone() { # <src-scripts-dir> <dst-scripts-dir> → <dst>/nao-fleet.sh
  local src="$1" dst="$2"
  [ -f "$src/nao-fleet.sh" ] || return 1
  [ -d "$src/fleet" ] || return 1
  mkdir -p "$dst" || return 1
  cp "$src/nao-fleet.sh" "$dst/nao-fleet.sh" || return 1
  cp -r "$src/fleet/." "$dst/fleet/" || return 1
  printf '%s\n' "$dst/nao-fleet.sh"
}

# #96 二期 B1 门面 lint（静态 · T555 收窄 · T567-A 文件集）：业务区**禁**裸后端调用。
#   唯一后端 = herdr（ADR 2026-11-22-herdr-only）：tmux 侧区间/台账分支已随后端删除，
#   本函数只剩 herdr 判据 —— 命中行必须既在 `# >>> term-facade-herdr` 标记区内、又在唯一入口
#   `_term_herdr_exec` 函数体内（或整行恰为 `herdr --version` 白名单：纯元数据、不触会话）。
#   判据：命令行位 `herdr`（前缀集：行首 / `|` / `;` / `&` / `(` / `$(` / `{`）；
#   `command -v herdr` / `t4_require_cmd herdr` 豁免。输出 `行号:内容 [标签]`（一行一个）。
#   注：第 2 参（旧 tmux 台账）已无对象，签名保留以兼容调用方（T555 · 台账 baseline = 0）。
_t4_term_ranges() { # <script> <标记种类> → start<TAB>end
  awk -v k="$2" '
    $0 ~ ("^# >>> " k " BEGIN") { s = NR; next }
    $0 ~ ("^# <<< " k " END")   { if (s) { print s "\t" NR; s = 0 } }
  ' "$1"
}
_t4_term_func_ranges() { # <script> → name<TAB>start<TAB>end
  awk '
    /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)[[:space:]]*\{/ {
      name = $0; sub(/[[:space:]]*\(\).*/, "", name); start = NR; inb = 1; next
    }
    inb && /^}/ { print name "\t" start "\t" NR; inb = 0 }
  ' "$1"
}
_t4_in_ranges() { # <行号> <ranges> → 0/1
  local n="$1" rs="$2" s e
  while IFS=$'\t' read -r s e; do
    [ -n "$s" ] || continue
    if [ "$n" -ge "$s" ] && [ "$n" -le "$e" ]; then return 0; fi
  done <<< "$rs"
  return 1
}
t4_scan_term_bare_calls() { # <dir|file> [旧台账（T555 起不再使用）]
  local target="$1" script lnno body trim tag
  local re='(^|[|;&(]|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?herdr([[:space:]]|$)'
  local allow='(command -v herdr|t4_require_cmd herdr)'
  local wl='^[[:space:]]*(exec[[:space:]]+|setsid[[:space:]]+)?herdr[[:space:]]+--version[[:space:]]*$'
  local herdr_r funcs herdr_exec _pfx="" _n=0 _f
  local -a _fs=()
  while IFS= read -r _f; do _fs+=("$_f"); done < <(_t4_fleet_files "$target")
  [ "${#_fs[@]}" -gt 1 ] && _pfx=1
  for script in "${_fs[@]}"; do
    # 实现区 = 带标记的文件取标记区间；不带的文件（= 非实现模块）整文件都算「区外」。
    herdr_r="$(_t4_term_ranges "$script" term-facade-herdr)"
    funcs="$(_t4_term_func_ranges "$script")"
    herdr_exec="$(awk -F'\t' '$1 == "_term_herdr_exec" { print $2 "\t" $3; exit }' <<< "$funcs")"
    while IFS= read -r ln; do
      lnno="${ln%%:*}"; body="${ln#*:}"
      trim="${body#"${body%%[![:space:]]*}"}"
      case "$trim" in \#*) continue;; esac
      grep -qE -- "$allow" <<< "$ln" && continue
      if [ -z "$herdr_r" ] || ! _t4_in_ranges "$lnno" "$herdr_r"; then
        printf '%s [herdr-区外]\n' "$(_t4_emit "$_pfx" "$script" "$lnno" "$trim")"; continue
      fi
      if grep -qE -- "$wl" <<< "$trim"; then continue; fi
      if [ -n "$herdr_exec" ] && _t4_in_ranges "$lnno" "$herdr_exec"; then continue; fi
      printf '%s [herdr-旁路唯一入口]\n' "$(_t4_emit "$_pfx" "$script" "$lnno" "$trim")"
    done < <(grep -nE -- "$re" "$script")
  done
}

# T555 / AC8 静态 lint：**禁旧 tmux 面复活**（与 t4_scan_term_herdr_forbidden 反向写法）。
#   判据（行级，任一即红；T555/QA P2-2 + P3-1 扩形态）：
#     ① 命令位 `tmux`：`(^|[|;&(]|$\()[[:space:]]*(exec|setsid)?[[:space:]]*tmux([[:space:]]|$)`
#     ② 旧后端赋值字面量：`NAO_TERMINAL[ ]*=[ ]*["']?tmux`
#     ③ 旧后端比较式：`$NAO_TERMINAL` / `${NAO_TERMINAL:-…}` 与 `tmux` 做 `=`/`==`/`!=`
#     ④ 旧后端 case 臂：`tmux)` / `tmux*)`（前缀 = 行首 / 空白 / `;` / `&`）；
#        **`|` 前缀只在 `case … in …` 形态里算臂**（判据 = 同行出现 `case … in`）——
#        这样 `case … in herdr|tmux)` 会红，而 `grep -E '…(herdr|tmux)…'` 这类**正则字面量**不会误伤。
#        代价：单行 `case` 里若把臂写在引号/注释中也会红（可接受：宁可误红不可假绿）。
#   白名单（逐条注释，缺任一条即误伤）：
#     a) 注释行（首个非空字符 `#`）—— 迁移指路「已移除 tmux 后端」只允许写在这里；
#     b) 名册字段 `"tmuxPane"`（外部 JSON 契约：pi-intercom 探针字段名，不可改）；
#     c) 宿主句柄名表 `_TERM_HOST_HANDLE_VARS=(TMUX TMUX_PANE TMUX_TMPDIR)`（起 herdr server 前必须清）；
#     d) 守卫臂（④ 命中时）—— 必须**同时**满足三件事，否则视为旧面复活：
#        ① 臂体（该行起 ≤9 行内、**先剥 `#` 注释**、再取到首个 `;;` 之前）含「已移除」文案；
#        ② 该臂体含真正的 fail loud 出口 `exit 2` / `return 2`（**只有文案不算守卫**：文案能被顺手
#           写进任何臂，`tmux) printf '已移除…'; return 0` 仍必须红）；
#        ③ 该行本身不命中 ①②③（守卫臂不是「顺手把调用写进臂里」）。
#        **注释穿透回归（QA P3-1）**：`case … in tmux) exec … ;; esac  # 已移除` 曾因「整段含已移除」
#        被放行 ⇒ 现在先剥注释再截到 `;;`，该形态必红。
#   边界声明（P3-2，二选一取 ①）：`case "$TERM" in tmux) …`（检测「自己是否在 tmux 里」以便提示迁移）
#   同样会红 —— 仓内 0 处使用，且它本身就是「按 tmux 分支」的旧面。**需要判断是否装过 tmux 请用
#   `command -v tmux`（不红）；需要提示迁移请写在注释里（不红）。** 未采取「把臂规则限定到 NAO_TERMINAL
#   上下文」的替代方案：那会让 `case "$BE" in tmux)` 这类改名变量（BE=`${NAO_TERMINAL}`）漏判。
#   作用域：`.agents/scripts/*.sh` + `tests/t4/run.sh`（**不扫 docs/**：文档必须保留迁移指路）。
#   输出 `行号:内容`（一行一个）；空输出 = 干净。
t4_scan_tmux_residue() { # <dir|file>
  local target="$1" script lnno body trim
  local re='(^|[|;&(]|\$\()[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?tmux([[:space:]]|$)'
  local re_assign='NAO_TERMINAL[[:space:]]*=[[:space:]]*["'"'"']?tmux'
  local re_cmp='NAO_TERMINAL[^[:space:]]*["'"'"']?[[:space:]]*(=|==|!=)[[:space:]]*["'"'"']?tmux'
  local allow='(tmuxPane|_TERM_HOST_HANDLE_VARS=)'
  # ④ 臂命中：行首/空白/;/& 前缀，或 `case … in …|tmux)`（`|` 只在 case 形态里算臂）
  _tmux_arm_hit() {
    grep -qE '(^|[[:space:];&])(tmux\)|tmux\*\))' <<< "$1" && return 0
    grep -qE '(^|[[:space:]])case[[:space:]].*[[:space:]]in[[:space:]]' <<< "$1" \
      && grep -qE '\|(tmux\)|tmux\*\))' <<< "$1" && return 0
    return 1
  }
  # 臂体规范化（剥 # 注释 → 截到首个 `;;`）—— 白名单判定只认规范化后的文本
  _tmux_arm_text() {
    sed -n "${1},$(( $1 + 8 ))p" "$script" \
      | sed -E 's/[[:space:]]#.*$//' \
      | awk '{ i = index($0, ";;"); if (i) { print substr($0, 1, i - 1); exit } print }'
  }
  # 白名单 d：文案（已移除）**且** 真出口（exit 2 / return 2）
  _tmux_guard_arm() {
    local t; t="$(_tmux_arm_text "$1")"
    grep -q '已移除' <<< "$t" || return 1
    grep -qE '(exit|return)[[:space:]]+2([^0-9]|$)' <<< "$t" || return 1
    return 0
  }
  local _pfx="" _f
  local -a _fs=()
  while IFS= read -r _f; do _fs+=("$_f"); done < <(_t4_fleet_files "$target")
  [ "${#_fs[@]}" -gt 1 ] && _pfx=1
  for script in "${_fs[@]}"; do
    while IFS= read -r ln; do
      lnno="${ln%%:*}"; body="${ln#*:}"
      trim="${body#"${body%%[![:space:]]*}"}"
      case "$trim" in \#*) continue;; esac
      grep -qE -- "$allow" <<< "$body" && continue
      if grep -qE -- "$re" <<< "$body" || grep -qE -- "$re_assign" <<< "$body" \
         || grep -qE -- "$re_cmp" <<< "$body"; then
        _t4_emit "$_pfx" "$script" "$lnno" "$trim"; continue
      fi
      if _tmux_arm_hit "$body"; then
        _tmux_guard_arm "$lnno" && continue
        _t4_emit "$_pfx" "$script" "$lnno" "$trim"; continue
      fi
    # 预筛：四条判据都必然含小写字面量 `tmux`（大写 TMUX/TMUX_PANE 不在覆盖面）
    done < <(grep -n 'tmux' "$script" || true)
  done
}

# 台账校验（B1）：① 每行可验（函数真实存在 + 函数体仍含裸后端调用）② 去重 ③ 行数只允许下降（文件头 baseline）
#   ④ 渲染层函数禁入台账（cmd_status / visible_session_names / pane_cwd_snapshot / running / term_*）。
#   T555：台账对象（旧 tmux 迁移）已随后端删除 ⇒ baseline = 0、条目 0；机制保留以守「不回暖」。
t4_verify_term_ledger() { # <dir|file> <台账文件>
  local target="$1" ledger="$2" base n=0 f owner why rec script s e bfile in_region
  local funcs=""
  [ -f "$ledger" ] || { printf '台账缺失: %s\n' "$ledger"; return 0; }
  while IFS= read -r script; do
    funcs+="$(_t4_term_func_ranges "$script" | awk -F'\t' -v f="$script" '{ print $1 "\t" f "\t" $2 "\t" $3 }')"$'\n'
  done < <(_t4_fleet_files "$target")
  base="$(sed -n 's/^#[[:space:]]*baseline:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ledger" | head -1)"
  [ -n "$base" ] || printf '台账缺 baseline 头（# baseline: N）\n'
  local -A seen=()
  while IFS=$'\t' read -r f owner why; do
    [ -n "$f" ] || continue
    n=$((n + 1))
    case "$f" in cmd_status|visible_session_names|pane_cwd_snapshot|running|term_*) printf '台账不得收录渲染层/门面函数: %s\n' "$f" ;; esac
    if [ -n "${seen[$f]:-}" ]; then printf '台账重复条目: %s\n' "$f"; fi
    seen["$f"]=1
    if [ -z "$owner" ] || [ -z "$why" ]; then printf '台账条目缺 owner/理由: %s\n' "$f"; fi
    rec="$(awk -F'\t' -v n="$f" '$1 == n { print $2 "\t" $3 "\t" $4; exit }' <<< "$funcs")"
    if [ -z "$rec" ]; then printf '台账条目函数不存在（typo）: %s\n' "$f"; continue; fi
    bfile="${rec%%$'\t'*}"; rec="${rec#*$'\t'}"; s="${rec%%$'\t'*}"; e="${rec##*$'\t'}"
    # 实现区 = term-herdr.sh 全文（拆分后为独立文件）；带标记的单文件副本仍按标记区间
    in_region=0
    if [ "$(basename "$bfile")" = "term-herdr.sh" ] || _t4_in_ranges "$s" "$(_t4_term_ranges "$bfile" term-facade-herdr)"; then
      in_region=1
      printf '台账多余（该函数已在标记区内，应删条目）: %s\n' "$f"
    fi
    if ! sed -n "${s},${e}p" "$bfile" \
         | grep -qE '(^|[|;&(]|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?(tmux|herdr)([[:space:]]|$)'; then
      printf '台账 stale（该函数已无裸后端调用，应删条目）: %s\n' "$f"
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$ledger")
  if [ -n "$base" ] && [ "$n" -gt "$base" ]; then printf '台账行数 %d 超过 baseline %s（只允许下降）\n' "$n" "$base"; fi
  return 0
}

# herdr 实现区禁字（BR2/BR6 机械兜 + 三期 P1 的 J3 静态证明）：
#   宿主句柄名、标题字段名，以及 tmux 的**布局算式 symbols**（最小列宽闸门 / main-row2 列差 /
#   长度常量 137/184）都不得出现在 herdr 实现里 —— 后者是 herdr 布局 = tab 拓扑（结构判据）的反证：
#   T555 已把 tmux 布局函数整组删除，本判据防它们被顺手搬进 herdr 区复活（AC8 同族）。
t4_scan_term_herdr_forbidden() { # <dir|file>
  local target="$1" script rs s e off lnno body trim f _pfx="" _ff
  local re='TMUX|terminal_title|pane_title|TMUX_MIN_PANE_WIDTH|main_row2_min_col|137|184'
  local allow='(tmuxPane|_TERM_HOST_HANDLE_VARS=)'
  local -a files=()
  if [ -d "$target" ]; then
    for f in "$target"/fleet/lib/*.sh; do [ -f "$f" ] && files+=("$f"); done
    # 结构性前提：实现区标记必须仍在 term-herdr.sh（删掉标记 ⇒ 不得静默变绿）
    local _m
    _m="$(grep -hcE '^# (>>>|<<<) term-facade-herdr (BEGIN|END)$' "$target"/fleet/lib/*.sh 2>/dev/null | awk '{ n += $1 } END { print n + 0 }')"
    [ "$_m" = "2" ] || printf 'herdr 实现区标记缺失/重复（期望 BEGIN/END 各 1，实得 %s）\n' "$_m"
  else
    files=("$target")
  fi
  [ "${#files[@]}" -gt 1 ] && _pfx=1
  for script in "${files[@]}"; do
    rs="$(_t4_term_ranges "$script" term-facade-herdr)"
    if [ -n "$rs" ]; then
      while IFS=$'\t' read -r s e; do
        [ -n "$s" ] || continue
        while IFS= read -r off; do
          [ -n "$off" ] || continue
          lnno=$((s + off - 1))
          body="$(sed -n "${lnno}p" "$script")"
          _t4_emit "$_pfx" "$script" "$lnno" "$body"
        done < <(sed -n "${s},${e}p" "$script" | grep -nE "$re" | cut -d: -f1)
      done <<< "$rs"
    else
      # 文件集模式：term-herdr.sh = 实现区（全文）；其他模块只允许白名单位置（宿主句柄名表 / 名册字段）
      while IFS= read -r lnno; do
        [ -n "$lnno" ] || continue
        body="$(sed -n "${lnno}p" "$script")"
        trim="${body#"${body%%[![:space:]]*}"}"
        # 非实现模块：注释行不参与（原判据只扫 herdr 实现区；这些文件里的 TMUX 只出现在迁移说明里）
        case "$trim" in \#*) continue;; esac
        grep -qE -- "$allow" <<< "$body" && continue
        _t4_emit "$_pfx" "$script" "$lnno" "$body"
      done < <(grep -nE "$re" "$script" | cut -d: -f1)
    fi
  done
}

# T562/AC7 静态闸：**app 臂禁裸调 hc**（唯一入口 `_term_app_exec`）。
#   缺陷类：app 臂里直接 `hc run …` 会绕过 `HC_SOCKET=$HC_TERMINAL_SOCKET` 注入 ⇒ 连到错 core
#   （`HC_SESSION` 拼错会静默新建空 core = 假成功），且错误判据（JSON error 字段）不再统一。
#   判据：全脚本命令位的 `hc`（`(^|[|;&(]|$(|{) [exec] hc`）只允许两处例外：
#     a) `_term_app_exec` 函数体内（唯一入口）；b) `command -v hc`（存在性探测）。
#   输出 `行号:内容`（空 = 合规）。
t4_scan_app_bare_hc() { # <script>
  # AC7 静态闸（T562）：app 臂**禁裸调 hc**，唯一入口 = `_term_app_exec`。
  #   两向都必须承重（QA P2：旧版只认「语句位 hc」，三种形态全绿）：
  #   ① 调用形态：前置 env 赋值 / `command` / `exec` / `env` 前缀也算调用（`command hc ls`、
  #      `HC_SOCKET=x hc ls` 同样是裸调 —— 它们绕过了唯一入口的 socket/rc 归一化）；
  #      T563/AC1 补**关键字位**：`if|then|else|elif|while|until|do|!` 之后、`command -<opt>` 之后
  #      同样是命令位（旧组只认行首/管道/命令替换 ⇒ 写进 `if hc ls` 就静默漏检）。
  #      T563/P3-2 补三类（QA 探针实测，方向都是**闸静音**而非噪音）：
  #      ① `sudo` 带选项/参数（`sudo -u root hc ls`；只认「sudo + 选项 + 选项自带的那个参数」，
  #         不吃任意单词 ⇒ `sudo grep hc file` 不误报）；② case 模式 `)` 前有空格（`* ) hc ls`）；
  #      ③ `pat) hc` 的 case 分支位（`)` 单独不当分隔符，只认「行首/`case … in` 之后的模式」
  #         ⇒ 不把 `$()`/`$(( ))` 的 `)` 当命令位，防误报）。
  #      **已知盲区（不修）**：模式内含空格的交替（`up | down) hc ls`）—— 允许 `|` 进模式字符类
  #      会把 `(herdr|tmux)` 之类正则字面量误判成 case 臂（T558 已踩），假阳之害 > 漏检之害。
  #      **分行形态不必特判**：`pat)` 与命令分行时，命令行自身以 `hc` 开头（行首规则已覆盖）
  #      ⇒ 仍被抓红（QA 复核：上一版注释称其为盲区，是错的）。
  #   ② 入口存在性：`_term_app_exec() {` 必须**恰 1 处**；整删/改名后没有 hc 调用也**不许算绿**
  #      （否则「删掉入口」= 判据空转，是最容易被绕过的一种）。
  local target="$1" script lnno body trim execr="" entry_n=0 f
  local entry_re='^_term_app_exec\(\) \{'
  local -r sudo_re='sudo([[:space:]]+(-[a-zA-Z]*[ugpChU][[:space:]]+[^[:space:]]+|--(user|group|prompt|close-from|other-user)(=[^[:space:]]+|[[:space:]]+[^[:space:]]+)|-[^[:space:]]+))*'
  local pre="([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|command[[:space:]]+-[a-zA-Z]|${sudo_re}|exec|command|env|nohup|time|if|then|else|elif|while|until|do|!)"
  local case_re='^[[:space:]]*(case[[:space:]].*[[:space:]]in[[:space:]]+)?[^()[:space:];&]+[[:space:]]*\)'
  local re="(^|[|;&({]|${case_re})[[:space:]]*(${pre}[[:space:]]+)*hc([[:space:]]|$)"
  local allow='(command -v hc|t4_require_cmd hc)'
  # 入口存在性按**文件集**合计（拆分后唯一入口在 term-app.sh，但仍必须是 1 处）
  while IFS= read -r f; do
    entry_n=$(( entry_n + $(grep -cE -- "$entry_re" "$f" || true) ))
  done < <(_t4_fleet_files "$target")
  [ "$entry_n" = "1" ] || printf 'MISSING_ENTRY: %s 内 `_term_app_exec() {` 定义数 = %s（唯一入口缺失/重复 ⇒ app 臂可能裸调 hc 或已被删）\n' "$target" "$entry_n"
  local _pfx="" _f
  local -a _fs=()
  while IFS= read -r _f; do _fs+=("$_f"); done < <(_t4_fleet_files "$target")
  [ "${#_fs[@]}" -gt 1 ] && _pfx=1
  for script in "${_fs[@]}"; do
    execr="$(awk -F'\t' '$1 == "_term_app_exec" { print $2 "\t" $3; exit }' <<< "$(_t4_term_func_ranges "$script")")"
    while IFS= read -r ln; do
      lnno="${ln%%:*}"; body="${ln#*:}"
      trim="${body#"${body%%[![:space:]]*}"}"
      case "$trim" in \#*) continue;; esac
      grep -qE -- "$allow" <<< "$ln" && continue
      if [ -n "$execr" ] && _t4_in_ranges "$lnno" "$execr"; then continue; fi
      _t4_emit "$_pfx" "$script" "$lnno" "$trim"
    done < <(grep -nE -- "$re" "$script")
  done
}

# T567-A：174 守恒三向断言（ADR D3「174 函数锚怎么迁」）。
#   <scripts-dir> <functions.txt> → 违规行（空 = 合规）。三向 = ①并集无漏登记 ②无孤儿（清单里有、
#   代码里没有）③ 总数守恒（清单行数 == 头 `# total: N` == 各模块顶层函数实际并集）。
#   归属也断言：清单写的模块必须就是定义该函数的文件（防「清单对、代码搬家没改清单」）。
t4_verify_functions_manifest() { # <scripts-dir> <functions.txt>
  local dir="$1" manifest="$2" f n path line total expected name decl_path actual_path bad=0
  local -A decl=() seen=()
  [ -f "$manifest" ] || { printf '清单缺失: %s\n' "$manifest"; return 0; }
  total="$(sed -n 's/^#[[:space:]]*total:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$manifest" | head -1)"
  if [ -z "$total" ]; then printf '清单缺 total 头（# total: N）\n'; fi
  while IFS=$'\t' read -r path name; do
    case "$path" in ''|\#*) continue ;; esac
    if [ -n "${decl[$name]:-}" ]; then printf '清单重复条目: %s（%s / %s）\n' "$name" "${decl[$name]}" "$path"; fi
    decl["$name"]="$path"
    if [ ! -f "$dir/$path" ]; then printf '清单路径不存在: %s（%s）\n' "$path" "$name"; fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$manifest")
  n=0
  while IFS= read -r f; do
    path="${f#"$dir"/}"
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      n=$((n + 1))
      if [ -n "${seen[$name]:-}" ]; then printf '函数重名（跨模块）: %s（%s / %s）\n' "$name" "${seen[$name]}" "$path"; fi
      seen["$name"]="$path"
      if [ -z "${decl[$name]:-}" ]; then
        printf '漏登记（代码有、清单无）: %s @ %s\n' "$name" "$path"
      elif [ "${decl[$name]}" != "$path" ]; then
        printf '归属不符: %s 清单写 %s，实际在 %s\n' "$name" "${decl[$name]}" "$path"
      fi
    done < <(sed -nE 's/^([A-Za-z_][A-Za-z0-9_]*)\(\)[[:space:]]*\{.*$/\1/p' "$f")
  done < <(_t4_fleet_files "$dir")
  for name in "${!decl[@]}"; do
    [ -n "${seen[$name]:-}" ] || printf '孤儿（清单有、代码无）: %s @ %s\n' "$name" "${decl[$name]}"
  done
  if [ -n "$total" ] && [ "$n" != "$total" ]; then
    printf '总数不符: 实际 %s ≠ 清单头 total %s\n' "$n" "$total"
  fi
  # 清单行数也必须与 total 一致（防「只加行不改 total」）
  expected="$(grep -vcE '^[[:space:]]*(#|$)' "$manifest")"
  if [ -n "$total" ] && [ "$expected" != "$total" ]; then
    printf '清单行数 %s ≠ 头 total %s\n' "$expected" "$total"
  fi
  return 0
}

# T558/#160 静态闸：放置快照 pane 行的**裸 read 消费点 = 0**，且每个消费循环首步必须经单点访问器。
#   缺陷背景（Issue #160 · P0）：行字段分隔符原为 TAB（IFS 空白类）⇒ 无 label 的 pane 行整体左移，
#   wsid 位读到 tab_id ⇒ `ensure` 把「只有用户自己 pane 的 workspace」判成空 workspace 并 `workspace close`，
#   连带杀掉用户 pi 会话。修法 = 单一构造器/访问器 + 非空白分隔符（US），本闸防回潮。
#   判据（逐个 `for … in "${_TERM_PLACE_PANE_ROWS[@]:-}"` 循环体）：
#     ① 循环体内不得出现「消费行变量」的 `read`（`read … <<< "$line"`）⇒ 又走回 IFS 折叠语义；
#        （循环体内用 `read` 拆**名字/其他值**是合法的，不算违规）
#     ② 循环体必须出现 `_term_place_pane_fields "$line"`（唯一取值入口）；
#     ③ 循环体内不得做 `$'\t'` 字段运算（前缀切 / IFS=TAB）。
#   输出：`<行号>:<正文>`（空 = 合规）。行号 = 真件行号（循环体内的行）；② 缺访问器时给循环起始行。
#   注：只认「首层 done 收尾」的简单循环；T567-A 起按**文件集**扫（消费循环在 term-herdr.sh 与
#   manifest.sh/ensure.sh 里）；若日后新增嵌套循环或其他消费写法（`mapfile`/子 shell 复制数组），
#   本闸需同步扩展。
t4_scan_place_pane_rows() { # <dir|file>
  local target="$1" script ln rest start body line
  while IFS= read -r script; do
  while IFS=: read -r ln rest; do
    [ -n "$ln" ] || continue
    start="$ln"
    body="$(awk -v s="$start" 'NR>s { if ($0 ~ /^[[:space:]]*done[[:space:]]*$/) exit; print NR":"$0 }' "$script")"
    # ① 消费行变量的裸 read（`read … <<< "$line"`；其他值的 read 合法）
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "${line#*:}" in
        *read*'<<< "$line"'*|*read*'<<<"$line"'*) printf '%s\n' "$line" ;;
      esac
    done <<< "$body"
    # ② 访问器（唯一取值入口）
    grep -qF -- '_term_place_pane_fields "$line"' <<< "$body" \
      || printf '%s:%s\n' "$start" "缺访问器（循环体未调用 _term_place_pane_fields \"\$line\"）"
    # ③ TAB 字段运算
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "${line#*:}" in *"\$'\\t'"*) printf '%s\n' "$line" ;; esac
    done <<< "$body"
  done < <(grep -nE 'for [a-z_]+ in "\$\{_TERM_PLACE_PANE_ROWS\[@\]:-\}"' "$script")
  done < <(_t4_fleet_files "$target")
}

# 三期 P2（默认翻 herdr）静态面：**用例不得依赖生产默认值**。
#   默认已 = herdr ⇒ 靠「未设」搭车的用例会在不同机器/不同默认下走不同后端（不可复现）。基线由
#   `run.sh` 按 `NAO_TEST_TERMINAL` **显式导出** `NAO_TERMINAL`；允许 unset/清空的**唯一**位置 =
#   「验默认值」段，且必须包在 `# >>> default-value-probe BEGIN` / END 标记块内。
#   本函数逐行扫全部用例：标记块外的 `unset NAO_TERMINAL` / `env -u NAO_TERMINAL` / 空串赋值 = 违规输出。
t4_scan_nao_terminal_default_probe() { # <目录（其下 *.sh）>
  local target="$1"
  local -a files=()
  if [ -d "$target" ]; then files=("$target"/*.sh)
  elif [ -f "$target" ]; then files=("$target")
  else printf '路径不存在: %s\n' "$target"; return 0; fi
  awk '
    FNR == 1 { inblk = 0 }
    /^[[:space:]]*# >>> default-value-probe BEGIN/ { inblk = 1; next }
    /^[[:space:]]*# >>> default-value-probe END/   { inblk = 0; next }
    inblk { next }
    /^[[:space:]]*#/ { next }
    /(^|[^A-Za-z0-9_])unset[[:space:]]+(-v[[:space:]]+)?NAO_TERMINAL([[:space:]]|;|$)/ {
      printf "%s:%d [unset] %s\n", FILENAME, FNR, $0; next }
    /-u[[:space:]]+NAO_TERMINAL([[:space:]]|$)/ {
      printf "%s:%d [env -u] %s\n", FILENAME, FNR, $0; next }
    /NAO_TERMINAL=(["]{0,2})([[:space:]]|$)/ {
      printf "%s:%d [空串] %s\n", FILENAME, FNR, $0; next }
  ' "${files[@]}"
}

t4_fixture() { # 输出一个 git 初始化过的临时项目目录
  local d
  d="$(mktemp -d "$T4_CACHE_DIR/fx.XXXXXX")" || t4_blocked "无法创建临时夹具目录"
  ( cd "$d" && git init -q && git config user.email t4@local && git config user.name t4 ) >/dev/null 2>&1
  printf '%s' "$d"
}

# 从仓库打包（--ignore-scripts：不触发 prepack 门禁，避免与仓库 check 耦合）
t4_pkg_tarball() {
  if [ -n "$T4_TARBALL" ] && [ -f "$T4_TARBALL" ]; then printf '%s' "$T4_TARBALL"; return 0; fi
  local cached="$T4_CACHE_DIR/nao-skill-${PKG_VERSION}.tgz"
  if [ ! -f "$cached" ]; then
    ( cd "$T4_ROOT" && npm pack --silent --ignore-scripts --pack-destination "$T4_CACHE_DIR" ) >/dev/null 2>&1 \
      || t4_blocked "npm pack 失败，无法构造被测包"
    local made
    made="$(ls -t "$T4_CACHE_DIR"/*.tgz 2>/dev/null | head -1)"
    [ -n "$made" ] || t4_blocked "npm pack 未产出 tarball"
    mv "$made" "$cached"
  fi
  printf '%s' "$cached"
}

# 把被测包物化进项目内 .pi/npm（模拟 `pi install --local` 的落盘结果；T1 §2 实测布局）
t4_materialize() {
  local dir="$1" tb
  tb="$(t4_pkg_tarball)"
  mkdir -p "$dir/.pi/npm"
  printf '*\n!.gitignore\n' > "$dir/.pi/npm/.gitignore"   # 模拟 pi 1.1.0 自建 .gitignore（T1 §2 证据）
  npm install --prefix "$dir/.pi/npm" --no-audit --no-fund --silent "$tb" >/dev/null 2>&1 \
    || t4_blocked "npm install（本地 tarball）失败"
  printf '{"packages":["npm:%s@%s"]}\n' "$PKG_NAME" "$PKG_VERSION" > "$dir/.pi/settings.json"
  [ -f "$dir/.pi/npm/node_modules/$PKG_NAME/package.json" ] || t4_blocked "包未物化到 .pi/npm"
}

t4_pkg_dir()  { printf '%s/.pi/npm/node_modules/%s' "$1" "$PKG_NAME"; }
t4_pkg_bin()  { printf '%s/bin/nao-skill.js' "$(t4_pkg_dir "$1")"; }
t4_shim()     { printf '%s/.agents/scripts/nao-fleet.sh' "$1"; }

# T2 CLI 子命令是否已交付（读仓库 bin 的 --help；不修改任何文件）
# T536/BR4：here-string 而非「printf 经**管道**送给 grep -q」（与 T535 修掉的三处断言同口径：大输入 + grep 早退会
#   SIGPIPE，pipefail 下把**命中**误判为未命中 ⇒ 本函数误报「子命令未交付」，整批用例静默 SKIP/BLOCKED）。
t4_cli_supports() {
  local sub="$1" h
  h="$(node "$T4_ROOT/bin/nao-skill.js" --help 2>&1 || true)"
  grep -qE -- "(^|[^[:alnum:]_])${sub}([^[:alnum:]_]|$)" <<< "$h"
}

t4_require_cli() { t4_cli_supports "$1" || t4_blocked "CLI 子命令未交付: nao-skill $1（T2 bin/）"; }

t4_require_shim() {
  local dir="$1" p
  p="$(t4_shim "$dir")"
  [ -f "$p" ] || t4_blocked "shim 未生成: $p（T2 init/migrate）"
  grep -q 'NAO_SHIM_ENTERED' "$p" || t4_blocked "shim 缺少 D7 marker 守卫 NAO_SHIM_ENTERED: $p"
}

# ---------------------------------------------------------------- 执行封装
# 在目录中执行命令；结果写入 T4_RC / T4_OUT / T4_ERR
t4_run_in_dir() {
  local dir="$1"; shift
  local of ef
  of="$(mktemp)"; ef="$(mktemp)"
  ( cd "$dir" && "$@" ) >"$of" 2>"$ef"
  T4_RC=$?
  T4_OUT="$(cat "$of")"; T4_ERR="$(cat "$ef")"
  rm -f "$of" "$ef"
}

# 在目录中执行 shim；可传 env 覆盖（如 -u NAO_SKILLS 或 NAO_SHIM_ENTERED=1）
t4_run_shim() {
  local dir="$1"; shift
  local of ef
  of="$(mktemp)"; ef="$(mktemp)"
  # #126 P3④：统一摘掉宿主导出的 NAO_STASH_ROOT —— check 的 stash 闸在夹具里不适用；
  #   不摘则宿主 `export NAO_STASH_ROOT=<有 stash 的仓>` 会让夹具 check 平白多一条 warn（假红）。
  ( cd "$dir" && env -u NAO_STASH_ROOT "$@" timeout 60 bash .agents/scripts/nao-fleet.sh check ) >"$of" 2>"$ef"
  T4_RC=$?
  T4_OUT="$(cat "$of")"; T4_ERR="$(cat "$ef")"
  rm -f "$of" "$ef"
}

t4_run_init() {
  local dir="$1"; shift
  t4_run_in_dir "$dir" node "$(t4_pkg_bin "$dir")" init "$@"
}

t4_run_migrate() { # 优先 migrate；否则 init（自动迁移路径）
  local dir="$1"
  if t4_cli_supports migrate; then
    t4_run_in_dir "$dir" node "$(t4_pkg_bin "$dir")" migrate
  else
    t4_note migrate-fallback "CLI 未提供 migrate，改用 init（自动迁移路径）"
    t4_run_init "$dir"
  fi
}

# ---------------------------------------------------------------- 网络隔离 / 追踪
t4_bwrap_available() {
  command -v bwrap >/dev/null 2>&1 || return 1
  bwrap --unshare-net --ro-bind / / true >/dev/null 2>&1
}

t4_strace_available() {
  command -v strace >/dev/null 2>&1 || return 1
  strace -f -e trace=connect -o /dev/null true >/dev/null 2>&1
}

# ---------------------------------------------------------------- 真 pi 冒烟（#86 A：受限重试）
# 语义（Issue #86 §A，护栏一条不简化）：
#   ① 每次调用都产出可 grep 的 info 行（两次 attempt 的 rc + stdout 字节数）；
#   ② **只有**「首次 rc=124（timeout 超时）」**或**「首次 rc=0 且 stdout 0 字节」才允许重试 ——
#      **非零退出即便 0 字节也不重试**（`--mode json` 解析崩、进程异常退出）照原样判（BR10：由调用方 SKIP/红）；
#   ③ 重试后仍失败 ⇒ 语义不变（调用方仍走原判，full 轴照旧计分）；
#   ④ 轻度放宽：首次 120s / 重试 180s（`T4_PI_TIMEOUT` / `T4_PI_RETRY_TIMEOUT` 可覆盖，供负控用）；
#   ⑤ 额外不重试前置：「No API key」（凭据缺失与延迟抖动无关，重试必同样失败）。
# 返回：0=拿到真实输出 · 3=无凭据 · 4=超时/失败（调用方按 BR10 判 SKIP）
# 副作用：写 $1（stdout）/$2（stderr）与 **"$2.info"**（同一行 info，供**子 shell** 调用方回读）；
#   另设全局 T4_PI_SMOKE_INFO（仅**父 shell 直接调用**时可见 —— 子 shell 里设的全局不会传回，
#   `set -u` 下直接插值会中止用例 ⇒ 子 shell 调用方必须读 "$2.info"，禁插值全局）。
T4_PI_SMOKE_INFO=""          # set -u 兜底：任何插值都不会因未绑定而中止
t4_pi_smoke() {
  local out="$1" err="$2"; shift 2
  local t1="${T4_PI_TIMEOUT:-120}" t2="${T4_PI_RETRY_TIMEOUT:-180}"
  local rc1=0 b1=0 rc2="-" b2="-" retry="no" reason="" rcf=0 bf=0
  timeout "$t1" "$@" >"$out" 2>"$err"; rc1=$?
  b1="$(wc -c <"$out" 2>/dev/null | tr -d ' ')"; b1="${b1:-0}"
  if grep -q "No API key" "$err" 2>/dev/null; then
    reason="no-api-key"
  elif [ "$rc1" = "124" ] || { [ "$rc1" = "0" ] && [ "$b1" = "0" ]; }; then
    retry="yes"
    timeout "$t2" "$@" >"$out" 2>"$err"; rc2=$?
    b2="$(wc -c <"$out" 2>/dev/null | tr -d ' ')"; b2="${b2:-0}"
  fi
  if [ "$retry" = "yes" ]; then
    rcf="$rc2"; bf="$b2"
    T4_PI_SMOKE_INFO="pi-smoke: attempt1 rc=$rc1 bytes=$b1 · attempt2 rc=$rc2 bytes=$b2 · retry=yes"
  else
    rcf="$rc1"; bf="$b1"
    T4_PI_SMOKE_INFO="pi-smoke: attempt1 rc=$rc1 bytes=$b1 · attempt2 rc=- bytes=- · retry=no${reason:+（$reason）}"
  fi
  # 三处出口：① 用例输出（人看/可 grep）② "$err.info"（**子 shell 调用方唯一可靠通道**）③ 全局（仅父 shell）
  t4_info "$T4_PI_SMOKE_INFO"
  printf '%s\n' "$T4_PI_SMOKE_INFO" > "${err}.info" 2>/dev/null || true
  grep -q "No API key" "$err" 2>/dev/null && return 3
  [ "$rcf" = "0" ] && [ "$bf" != "0" ] && return 0
  return 4
}
