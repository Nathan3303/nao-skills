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
T4_NOTE_TAGS=(static-contract pin-fallback migrate-fallback)

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
# 断言实现注意：printf 经管道嗂 grep -q 在大输入 + 早退时会触发 SIGPIPE，pipefail 下把**命中**判成 FAIL
# （实测 case16 读 16KB 协议文件 ~10% 假 FAIL = T534-O2 根因）。改用 here-string：grep 读临时文件，无上游写者被中断。
t4_assert_contains()     { grep -qF -- "$2" <<< "$1" && t4_ok "$3" || t4_bad "$3（未包含: $2）"; }
t4_assert_not_contains() { grep -qF -- "$2" <<< "$1" && t4_bad "$3（不应包含: $2）" || t4_ok "$3"; }
t4_assert_match()        { grep -qE -- "$2" <<< "$1" && t4_ok "$3" || t4_bad "$3（不匹配正则: $2）"; }
t4_assert_file()   { [ -f "$1" ] && t4_ok "$2" || t4_bad "$2（文件不存在: $1）"; }
t4_assert_dir()    { [ -d "$1" ] && t4_ok "$2" || t4_bad "$2（目录不存在: $1）"; }
t4_assert_absent() { [ ! -e "$1" ] && t4_ok "$2" || t4_bad "$2（不应存在: $1）"; }

# ---------------------------------------------------------------- 环境 / 夹具
t4_require_cmd() { command -v "$1" >/dev/null 2>&1 || t4_blocked "环境缺少命令: $1"; }

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
# T536/BR4：here-string 而非 printf 管道嗂 grep -q（与 T535 修掉的三处断言同口径：大输入 + grep 早退会
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
