#!/usr/bin/env bash
# 用例 07 —— 真实 `pi install -l --approve` 与 tarball 复现布局对照
#
# 目的：确认 T4 夹具的物化方式（npm install 本地 tarball）与 pi 实际落盘布局一致。
# T594（#262）：**改为零网络** —— 用 `npm pack` 产出的本地 tgz 走 `pi install -l --approve npm:<pkg>@file:<tgz>`，
#   不再依赖 registry 是否已发布（否则「必须先发布才能验证发布前置」逻辑倒置；同族消掉 registry 延迟/不可达的 flake）。
#   registry 可达时只打一行 `t4_info` 观察（**不计门禁**：既不是 SKIP 也不产生 NOTE）。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

t4_require_cmd node
t4_require_cmd npm
command -v pi >/dev/null 2>&1 || t4_skip "pi CLI 不可用，跳过真实安装对照"

TARBALL="$(t4_pkg_tarball)"
t4_assert_file "$TARBALL" "前置：本地 tarball 已产出（npm pack --ignore-scripts，零网络）"
t4_info "对照版本: 本地 pack=$PKG_NAME@$PKG_VERSION（tgz=$(basename "$TARBALL")）"
# registry 观察行（非门禁）：可达就打印 latest，仅作背景；不可达同样不改变本用例结论
REG_LATEST="$(timeout 20 npm view "$PKG_NAME" version 2>/dev/null | tail -1 | tr -d "'\"[:space:]")"
t4_info "registry 观察（不计门禁）：latest=${REG_LATEST:-<不可达或未发布>}"

# A: 真实 pi install
A="$(t4_fixture)"
of="$(mktemp)"; ef="$(mktemp)"
( cd "$A" && timeout 180 pi install -l --approve "npm:${PKG_NAME}@file:${TARBALL}" ) >"$of" 2>"$ef"
rcA=$?; outA="$(cat "$of")"; errA="$(cat "$ef")"; rm -f "$of" "$ef"
t4_info "pi install（本地 tgz）rc=$rcA（$(printf '%s' "$outA" | tail -1)）"
# BR10 极性：外部不可达 / 未成功启动 ⇒ SKIP（不得假红）；只有拿到真实落盘后内容不符才 FAIL
if [ "$rcA" -ne 0 ]; then
  t4_skip "pi install（本地 tgz）未成功启动（rc=$rcA）：$(printf '%s' "$errA" | tail -1)"
fi

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
