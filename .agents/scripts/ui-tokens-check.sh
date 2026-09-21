#!/usr/bin/env bash
# =============================================================================
# ui-tokens-check.sh — 扫描 UI 硬编码色值（绕过主题令牌）
#
# 用法
#   ui-tokens-check.sh [<repo>]    默认 $PWD；退出码 0=通过 1=存在违规
#
# 背景
#   UI 风格应收敛到主题令牌（如 nue-ui 的 --nue-* 变量）；组件内裸色值
#   （#fff / rgba() / #d4a72c）会导致换主题/暗色模式失效、风格漂移。
#   本脚本扫出这些绕过令牌的色值，供 agent 交付前自查，或接入 CI/lint-staged。
#
# 排除
#   node_modules / .codegraph / 类型声明(.d.ts)
#   主题令牌定义行（含 --nue- 或 var(-- 的上下文）放行
# =============================================================================
set -uo pipefail

repo="${1:-$PWD}"
cd "$repo" 2>/dev/null || { echo "✗ 目录不存在: $repo" >&2; exit 2; }

hits="$(grep -rnoE --include='*.vue' --include='*.ts' --include='*.tsx' \
        --include='*.js' --include='*.jsx' --include='*.css' \
        -E '#[0-9a-fA-F]{3,8}\b' . 2>/dev/null \
      | grep -vE 'node_modules|\.codegraph|\.d\.ts' \
      | grep -viE -- 'var\(--|--[a-z0-9-]+[[:space:]]*:[[:space:]]*#' \
      | head -40 || true)"

if [[ -n "$hits" ]]; then
  echo "✗ UI 令牌违规（$(basename "$repo")）— 以下色值应改为 --nue-* 令牌："
  echo "$hits"
  if [[ $(grep -c . <<< "$hits") -ge 40 ]]; then echo "  …（更多）"; fi
  exit 1
fi

echo "✓ $(basename "$repo") 无硬编码色值（UI 令牌一致）"
exit 0
