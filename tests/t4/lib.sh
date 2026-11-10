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
  rm -rf -- "$dir" 2>/dev/null || printf 'T4 缓存清理失败（已保留目录）: %s\n' "$dir" >&2  # BR9 不改 rc
  return "$rc"
}
trap t4_cache_cleanup EXIT

export T4_ROOT PKG_NAME PKG_VERSION T4_CACHE_DIR T4_ALLOW_MISSING T4_REQUIRE_FULL T4_TARBALL

T4_FAIL=0
T4_DEGRADE=0
T4_RC=0
T4_OUT=""
T4_ERR=""

# ---------------------------------------------------------------- 输出 / 断言
t4_log()  { printf '%s\n' "$*"; }
t4_ok()   { printf '  [PASS] %s\n' "$*"; }
t4_bad()  { T4_FAIL=$((T4_FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
# NOTE 白名单（T531 · BR1）：tag 枚举的**单点定义** —— run.sh 复用本数组做合法性判定。
# 新增 tag 必须同时改这里 + 在 tests/README.md「NOTE 白名单」写明理由（缺一不可）。
# 语义：static-contract=静态替代证据 · pin-fallback=pin 未发布改对照 latest · migrate-fallback=缺 migrate 走 init
#        baseline-selfequiv=AC5① 基线 fixture 正文 == 被测脚本正文（本轮对照为自等价，非零回归证据）
T4_NOTE_TAGS=(static-contract pin-fallback migrate-fallback baseline-selfequiv)

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

# #96 二期 B1 门面 lint（静态）：业务区**禁**裸后端调用，后端差异只允许出现在两个标记区。
#   标记区（脚本内注释标记，可多对）：
#     `# >>> term-impl-tmux BEGIN` … `# <<< term-impl-tmux END`  —— tmux 证据层内部
#     `# >>> term-facade-herdr BEGIN` … `# <<< term-facade-herdr END` —— herdr 实现内部
#   另外允许**显式台账**（`<函数名><TAB><B2|B3|B4><TAB>理由`）里的函数：它们仍是 tmux 直调（spawn/close/
#   布局/check 终端前提），迁移归 B2/B3/B4；台账随批次**只减不增**（t4_verify_term_ledger 断言）。
#   判据：命令行位 `tmux|herdr`（与 t4_scan_host_pane_refs / t4_scan_herdr_bare_calls 同一前缀集，不另造正则）；
#   `command -v tmux|herdr` / `t4_require_cmd` 豁免。herdr 额外要求：命中行必须在 herdr 标记区内**且**在唯一入口
#   `_term_herdr_exec` 函数体内（或整行恰为 `herdr --version` 白名单 —— 纯元数据、不触会话）。
#   输出 `行号:内容 [标签]`（一行一个）。
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
t4_scan_term_bare_calls() { # <script> [台账文件]
  local script="$1" ledger="${2:-}" lnno body trim fname
  local re='(^|[|;&(]|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?(tmux|herdr)([[:space:]]|$)'
  local allow='(command -v (tmux|herdr)|t4_require_cmd (tmux|herdr))'
  local wl='^[[:space:]]*(exec[[:space:]]+|setsid[[:space:]]+)?herdr[[:space:]]+--version[[:space:]]*$'
  local tmux_r herdr_r funcs ledger_fns="" herdr_exec
  tmux_r="$(_t4_term_ranges "$script" term-impl-tmux)"
  herdr_r="$(_t4_term_ranges "$script" term-facade-herdr)"
  funcs="$(_t4_term_func_ranges "$script")"
  herdr_exec="$(awk -F'\t' '$1 == "_term_herdr_exec" { print $2 "\t" $3; exit }' <<< "$funcs")"
  if [ -n "$ledger" ] && [ -f "$ledger" ]; then
    ledger_fns="$(grep -vE '^[[:space:]]*(#|$)' "$ledger" | cut -f1)"
  fi
  while IFS= read -r ln; do
    lnno="${ln%%:*}"; body="${ln#*:}"
    trim="${body#"${body%%[![:space:]]*}"}"
    case "$trim" in \#*) continue;; esac
    grep -qE -- "$allow" <<< "$ln" && continue
    fname="$(awk -F'\t' -v n="$lnno" '$2 <= n && n <= $3 { print $1; exit }' <<< "$funcs")"
    if grep -qE '(^|[^A-Za-z0-9_])(herdr)([[:space:]]|$)' <<< "$body"; then
      # herdr：唯一入口 + 白名单（双重判据）
      if ! _t4_in_ranges "$lnno" "$herdr_r"; then
        printf '%s:%s [herdr-区外]\n' "$lnno" "$trim"; continue
      fi
      if grep -qE -- "$wl" <<< "$trim"; then continue; fi
      if [ -n "$herdr_exec" ] && _t4_in_ranges "$lnno" "$herdr_exec"; then continue; fi
      printf '%s:%s [herdr-旁路唯一入口]\n' "$lnno" "$trim"; continue
    fi
    _t4_in_ranges "$lnno" "$tmux_r" && continue
    if [ -n "$fname" ] && [ -n "$ledger_fns" ] && grep -qxF "$fname" <<< "$ledger_fns"; then continue; fi
    printf '%s:%s [tmux-门面外]\n' "$lnno" "$trim"
  done < <(grep -nE -- "$re" "$script")
}

# 台账校验（B1）：① 每行可验（函数真实存在 + 函数体仍含裸后端调用）② 去重 ③ 行数只允许下降（文件头 baseline）
#   ④ 渲染层函数禁入台账（cmd_status / visible_session_names / pane_cwd_snapshot / running / term_*）。
t4_verify_term_ledger() { # <script> <台账文件>
  local script="$1" ledger="$2" base n=0 f owner why body tmux_r herdr_r
  local funcs; funcs="$(_t4_term_func_ranges "$script")"
  tmux_r="$(_t4_term_ranges "$script" term-impl-tmux)"
  herdr_r="$(_t4_term_ranges "$script" term-facade-herdr)"
  [ -f "$ledger" ] || { printf '台账缺失: %s\n' "$ledger"; return 0; }
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
    body="$(awk -F'\t' -v n="$f" '$1 == n { print $2 "\t" $3; exit }' <<< "$funcs")"
    if [ -z "$body" ]; then printf '台账条目函数不存在（typo）: %s\n' "$f"; continue; fi
    if _t4_in_ranges "${body%%$'\t'*}" "$tmux_r" || _t4_in_ranges "${body%%$'\t'*}" "$herdr_r"; then
      printf '台账多余（该函数已在标记区内，应删条目）: %s\n' "$f"
    fi
    if ! sed -n "${body%%$'\t'*},${body##*$'\t'}p" "$script" \
         | grep -qE '(^|[|;&(]|\$\(|\{)[[:space:]]*(exec[[:space:]]+)?(setsid[[:space:]]+)?(tmux|herdr)([[:space:]]|$)'; then
      printf '台账 stale（该函数已无裸后端调用，应删条目）: %s\n' "$f"
    fi
  done < <(grep -vE '^[[:space:]]*(#|$)' "$ledger")
  if [ -n "$base" ] && [ "$n" -gt "$base" ]; then printf '台账行数 %d 超过 baseline %s（只允许下降）\n' "$n" "$base"; fi
  return 0
}

# herdr 实现区禁字（BR2/BR6 机械兜）：tmux 句柄与标题字段名都不得出现在 herdr 实现里。
t4_scan_term_herdr_forbidden() { # <script>
  local script="$1" rs s e off lnno body
  rs="$(_t4_term_ranges "$script" term-facade-herdr)"
  [ -n "$rs" ] || { printf 'herdr 实现区标记缺失（# >>> term-facade-herdr BEGIN）\n'; return 0; }
  while IFS=$'\t' read -r s e; do
    [ -n "$s" ] || continue
    while IFS= read -r off; do
      [ -n "$off" ] || continue
      lnno=$((s + off - 1))
      body="$(sed -n "${lnno}p" "$script")"
      printf '%s:%s\n' "$lnno" "$body"
    done < <(sed -n "${s},${e}p" "$script" | grep -nE 'TMUX|terminal_title|pane_title' | cut -d: -f1)
  done <<< "$rs"
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
  ( cd "$dir" && env "$@" timeout 60 bash .agents/scripts/nao-fleet.sh check ) >"$of" 2>"$ef"
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
