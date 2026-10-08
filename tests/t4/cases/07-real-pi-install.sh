#!/usr/bin/env bash
# 用例 07 —— 真实 `pi install -l --approve` 与 tarball 复现布局对照
#
# 目的：确认 T4 夹具的物化方式（npm install 本地 tarball）与 pi 实际落盘布局一致。
# 版本动态读取：优先 PIN 版本（若已发布），否则用已发布 latest，仅做布局对照并标注。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
command -v pi >/dev/null 2>&1 || t4_skip "pi CLI 不可用，跳过真实安装对照"

pubver="$(timeout 40 npm view "${PKG_NAME}@${PKG_VERSION}" version 2>/dev/null | tail -1 | tr -d "'\"[:space:]")"
exact="1"
if [ "$pubver" != "$PKG_VERSION" ]; then
  exact="0"
  pubver="$(timeout 40 npm view "$PKG_NAME" version 2>/dev/null | tail -1 | tr -d "'\"[:space:]")"
  t4_note "pin 版本 $PKG_VERSION 未发布；改用已发布 latest=$pubver 做**布局**对照（内容差异不计）"
fi
[ -n "$pubver" ] || t4_skip "npm registry 不可达，无法做真实安装对照"
t4_info "对照版本: pubver=$pubver · pin=$PKG_VERSION · 版本一致=$exact"

# A: 真实 pi install
A="$(t4_fixture)"
of="$(mktemp)"; ef="$(mktemp)"
( cd "$A" && timeout 180 pi install -l --approve "npm:${PKG_NAME}@${pubver}" ) >"$of" 2>"$ef"
rcA=$?; outA="$(cat "$of")"; errA="$(cat "$ef")"; rm -f "$of" "$ef"
t4_info "pi install rc=$rcA（$(printf '%s' "$outA" | tail -1)）"
t4_assert_eq "0" "$rcA" "真实 pi install exit=0"

# B: tarball 复现
B="$(t4_fixture)"
t4_materialize "$B"

# --- 布局对照 ---------------------------------------------------------------
listA="$(cd "$A" && find .pi -path '*/node_modules' -prune -o -type f -print 2>/dev/null | sort)"
listB="$(cd "$B" && find .pi -path '*/node_modules' -prune -o -type f -print 2>/dev/null | sort)"
t4_info "pi 落盘: $(printf '%s' "$listA" | tr '\n' ' ')"
t4_info "tarball: $(printf '%s' "$listB" | tr '\n' ' ')"
t4_assert_eq "$listA" "$listB" "布局文件集一致（.pi 下非 node_modules）"

giA="$(cat "$A/.pi/npm/.gitignore" 2>/dev/null)"; giB="$(cat "$B/.pi/npm/.gitignore" 2>/dev/null)"
t4_assert_eq "$giA" "$giB" ".pi/npm/.gitignore 内容一致（pi 自建）"
t4_assert_contains "$giA" '*' ".pi/npm/.gitignore 忽略全部（pi 行为）"

pkgA="$A/.pi/npm/node_modules/$PKG_NAME/package.json"
pkgB="$B/.pi/npm/node_modules/$PKG_NAME/package.json"
t4_assert_file "$pkgA" "pi 落盘含 .pi/npm/node_modules/<pkg>/package.json"
t4_assert_file "$pkgB" "tarball 落盘含同路径 package.json"

# settings 形态一致（版本号允许不同）
shapeA="$(node -e 'const s=require(process.argv[1]);const p=s.packages||[];console.log(p.length+":"+String(p[0]).replace(/@[^@]+$/,""))' "$A/.pi/settings.json" 2>/dev/null)"
shapeB="$(node -e 'const s=require(process.argv[1]);const p=s.packages||[];console.log(p.length+":"+String(p[0]).replace(/@[^@]+$/,""))' "$B/.pi/settings.json" 2>/dev/null)"
t4_assert_eq "$shapeA" "$shapeB" ".pi/settings.json packages 形态一致（npm:<pkg> pin）"
t4_assert_eq "1:npm:${PKG_NAME}" "$shapeA" "pi 写入的 packages == npm:${PKG_NAME}@<ver>"

# 未跟踪性在真实安装下同样成立
if ( cd "$A" && git check-ignore -q ".pi/npm/node_modules/$PKG_NAME/package.json" ); then
  t4_ok "真实安装 .pi/npm/node_modules/** 被 git 忽略"
else
  t4_bad "真实安装 .pi/npm/node_modules/** 未被忽略"
fi

t4_exit
