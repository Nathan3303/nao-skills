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
# 依赖物缺失时默认 BLOCKED（T4_ALLOW_MISSING=1）；T2 回执后以 T4_ALLOW_MISSING=0 严格复跑，缺失即 FAIL。
set -uo pipefail

T4_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
T4_TESTS_DIR="$(cd "$T4_LIB_DIR/.." && pwd)"
T4_ROOT="${T4_ROOT:-$(cd "$T4_TESTS_DIR/.." && pwd)}"

PKG_NAME="@nathan33/nao-skill"
PKG_VERSION="$(node -p "try{require('${T4_ROOT}/package.json').version}catch(e){'0.0.0'}" 2>/dev/null || echo 0.0.0)"
T4_CACHE_DIR="${T4_CACHE_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/nao-t4.XXXXXX")}"
T4_ALLOW_MISSING="${T4_ALLOW_MISSING:-1}"
T4_TARBALL="${T4_TARBALL:-}"
export T4_ROOT PKG_NAME PKG_VERSION T4_CACHE_DIR T4_ALLOW_MISSING T4_TARBALL

T4_FAIL=0
T4_RC=0
T4_OUT=""
T4_ERR=""

# ---------------------------------------------------------------- 输出 / 断言
t4_log()  { printf '%s\n' "$*"; }
t4_ok()   { printf '  [PASS] %s\n' "$*"; }
t4_bad()  { T4_FAIL=$((T4_FAIL + 1)); printf '  [FAIL] %s\n' "$*"; }
t4_note() { printf '  [NOTE] %s\n' "$*"; }
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

# 依赖的 T2 产物缺失：宽松模式=BLOCKED(78)，严格模式=FAIL(1)
t4_blocked() {
  if [ "$T4_FAIL" -gt 0 ]; then
    t4_bad "前置缺失且已有断言未过：$1"
    t4_exit
  fi
  if [ "$T4_ALLOW_MISSING" = "1" ]; then
    printf 'BLOCKED: %s\n' "$1"
    printf '（该产物由 T2 交付；T2 回执后设 T4_ALLOW_MISSING=0 复跑，缺失即判 FAIL）\n'
    exit 78
  fi
  t4_bad "前置缺失（strict 模式）：$1"
  t4_exit
}

t4_assert_eq()   { [ "$1" = "$2" ] && t4_ok "$3" || t4_bad "$3（期望=$1 实际=$2）"; }
t4_assert_ne()   { [ "$1" != "$2" ] && t4_ok "$3" || t4_bad "$3（不应等于 $1）"; }
t4_assert_ge()   { [ "$2" -ge "$1" ] 2>/dev/null && t4_ok "$3" || t4_bad "$3（期望>= $1 实际=$2）"; }
t4_assert_contains()     { printf '%s' "$1" | grep -qF -- "$2" && t4_ok "$3" || t4_bad "$3（未包含: $2）"; }
t4_assert_not_contains() { printf '%s' "$1" | grep -qF -- "$2" && t4_bad "$3（不应包含: $2）" || t4_ok "$3"; }
t4_assert_match()        { printf '%s' "$1" | grep -qE -- "$2" && t4_ok "$3" || t4_bad "$3（不匹配正则: $2）"; }
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
t4_cli_supports() {
  local sub="$1" h
  h="$(node "$T4_ROOT/bin/nao-skill.js" --help 2>&1 || true)"
  printf '%s' "$h" | grep -qE "(^|[^[:alnum:]_])${sub}([^[:alnum:]_]|$)"
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
    t4_note "CLI 未提供 migrate，改用 init（自动迁移路径）"
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
