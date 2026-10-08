#!/usr/bin/env bash
# 用例 03 —— 异常/边界：不可运行退出码与防重入（PRD AC3 / NFR3 / §11 D5·D6·D7 / 闸门B）
#
# 3a 未物化            → exit 2 + 单行 DEGRADED: + 可复制恢复命令（不静默）
# 3b marker env 命中   → exit 2，不得递归（D7）
# 3c 伪造 NAO_SKILLS   → 自指/非法包根 → exit 2，不得递归（D7 双重防护）
# 3d NAO_SKILLS 合法   → 显式覆盖生效，check exit=0（D6 第 1 优先级）
# 3e ~/.pi/agent/npm   → 版本==pin 可用；版本!=pin 显式失败（D6 第 3 优先级）
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
t4_require_cli init

assert_degraded() { # <label> 依据当前 T4_RC/T4_OUT/T4_ERR
  local label="$1" joined n
  joined="$(printf '%s\n%s\n' "$T4_OUT" "$T4_ERR")"
  t4_assert_eq "2" "$T4_RC" "$label: exit=2（与「能跑但失败=1」区分，D5）"
  n="$(printf '%s\n' "$joined" | grep -cE '^DEGRADED:')"
  t4_assert_eq "1" "$n" "$label: 恰一行 DEGRADED:"
  t4_assert_match "$joined" '(pi install|npm ci|npm install)' "$label: 含可复制恢复命令"
}

fx="$(t4_fixture)"
t4_materialize "$fx"
t4_run_init "$fx" >/dev/null 2>&1
t4_require_shim "$fx"

# --- 3a 未物化（隔离空 HOME，排除 ~/.pi/agent/npm 兜底） ---------------------
empty_home="$(mktemp -d "$T4_CACHE_DIR/home.XXXXXX")"
rm -rf "$fx/.pi/npm/node_modules"
t4_run_shim "$fx" -u NAO_SKILLS -u NAO_SHIM_ENTERED "HOME=$empty_home"
t4_info "3a rc=$T4_RC"
assert_degraded "3a 未物化"
t4_assert_not_contains "$T4_OUT$T4_ERR" "check: OK" "3a 不得静默成功"

# 重建物化，供后续子用例
t4_materialize "$fx" >/dev/null 2>&1

# --- 3b marker env 命中 -----------------------------------------------------
t4_run_shim "$fx" -u NAO_SKILLS NAO_SHIM_ENTERED=1
t4_info "3b rc=$T4_RC"
assert_degraded "3b marker 防重入"

# --- 3c 伪造 NAO_SKILLS（自指 / 非包根） ------------------------------------
t4_run_shim "$fx" -u NAO_SHIM_ENTERED NAO_SKILLS="$fx"
t4_info "3c-1 rc=$T4_RC"
assert_degraded "3c-1 NAO_SKILLS=项目根（自指）"

t4_run_shim "$fx" -u NAO_SHIM_ENTERED NAO_SKILLS="$fx/.agents"
t4_info "3c-2 rc=$T4_RC"
t4_assert_ne "0" "$T4_RC" "3c-2 NAO_SKILLS=.agents（旧语义）不得当作包根成功"
[ "$T4_RC" -ne 124 ] && t4_ok "3c-2 未递归/未超时" || t4_bad "3c-2 递归或超时"

# --- 3d NAO_SKILLS 指向合法包根（异位副本） ---------------------------------
alt="$(mktemp -d "$T4_CACHE_DIR/altpkg.XXXXXX")"
cp -a "$fx/.pi/npm/node_modules/$PKG_NAME/." "$alt/"
t4_run_shim "$fx" -u NAO_SHIM_ENTERED NAO_SKILLS="$alt"
t4_info "3d rc=$T4_RC out=$(printf '%s' "$T4_OUT" | head -1)"
t4_assert_eq "0" "$T4_RC" "3d NAO_SKILLS 显式覆盖：check exit=0"
t4_assert_contains "$T4_OUT" "check: OK" "3d 显式覆盖 check 成功"

# --- 3e ~/.pi/agent/npm 版本校验 -------------------------------------------
rm -rf "$fx/.pi/npm/node_modules"           # 去掉 tier-2
home_ok="$(mktemp -d "$T4_CACHE_DIR/homeok.XXXXXX")"
mkdir -p "$home_ok/.pi/agent/npm/node_modules/@nathan33"
cp -a "$alt" "$home_ok/.pi/agent/npm/node_modules/@nathan33/nao-skill"
t4_run_shim "$fx" -u NAO_SKILLS -u NAO_SHIM_ENTERED "HOME=$home_ok"
t4_info "3e-ok rc=$T4_RC"
t4_assert_eq "0" "$T4_RC" "3e 全局兜底版本==pin：check exit=0（D6 第 3 优先级）"

home_bad="$(mktemp -d "$T4_CACHE_DIR/homebad.XXXXXX")"
mkdir -p "$home_bad/.pi/agent/npm/node_modules/@nathan33"
cp -a "$alt" "$home_bad/.pi/agent/npm/node_modules/@nathan33/nao-skill"
node -e '
const fs=require("fs"),p=process.argv[1];
const j=JSON.parse(fs.readFileSync(p,"utf8"));j.version="0.0.1";
fs.writeFileSync(p,JSON.stringify(j,null,2));
' "$home_bad/.pi/agent/npm/node_modules/@nathan33/nao-skill/package.json"
t4_run_shim "$fx" -u NAO_SKILLS -u NAO_SHIM_ENTERED "HOME=$home_bad"
t4_info "3e-bad rc=$T4_RC"
assert_degraded "3e 全局兜底版本!=pin"

t4_exit
