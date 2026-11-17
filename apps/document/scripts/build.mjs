#!/usr/bin/env node
/**
 * 构建包装（ADR 2026-11-16-docs-site-pipeline D2/D3）。
 *
 *   npm run build            默认：卡源缺失 ⇒ 跳过注入 + 一条显式告警，rc=0
 *   npm run build -- --strict 卡源缺失 ⇒ rc≠0（真命令行参数，非 env 口径）
 *
 * 其余参数原样透传给 `vitepress build`（例如 CI 的 `--base /nao-skills/`）。
 */
import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const DOCS_ROOT = path.resolve(HERE, '..')
const REPO_ROOT = path.resolve(DOCS_ROOT, '..', '..')
const PROMPTS_DIR = path.join(REPO_ROOT, '.agents', 'prompts')
const DIST_DIR = path.join(DOCS_ROOT, '.vitepress', 'dist')

const argv = process.argv.slice(2)
const strict = argv.includes('--strict')
const passthrough = argv.filter((arg) => arg !== '--strict')

const vitepressBin = path.join(DOCS_ROOT, 'node_modules', 'vitepress', 'bin', 'vitepress.js')
if (!fs.existsSync(vitepressBin)) {
  console.error(
    '✗ 缺少站点依赖：先跑 `npm install --prefix apps/document`（ADR D1：apps/document 是独立私有包）',
  )
  process.exit(1)
}

// QA D8：任何失败路径都不得留下上一轮的 dist —— 否则随后的 check:cards / check:links
// 会对着旧产物误判为绿。构建前先清空，构建失败再清一次。
fs.rmSync(DIST_DIR, { recursive: true, force: true })
console.log('· 已清理旧产物 .vitepress/dist（失败路径不残留）')

if (!fs.existsSync(PROMPTS_DIR)) {
  if (strict) {
    console.error('✗ --strict：未找到 .agents/prompts，角色卡原文无法注入，按约定构建失败')
    process.exit(1)
  }
  // 唯一一条显式告警；配置侧读到本环境变量后不再重复打印
  console.warn(
    '⚠ 跳过角色卡注入：未找到 .agents/prompts（角色页原文区显示「卡原文见仓库」，其余页面照常构建）',
  )
  process.env.NAO_CARDS_MISSING = '1'
}

process.env.NAO_STRICT = strict ? '1' : '0'

const result = spawnSync(process.execPath, [vitepressBin, 'build', ...passthrough], {
  cwd: DOCS_ROOT,
  env: process.env,
  stdio: 'inherit',
})

if (result.error) {
  fs.rmSync(DIST_DIR, { recursive: true, force: true })
  console.error(`✗ 拉起 vitepress build 失败：${result.error.message}`)
  process.exit(1)
}

if (result.status !== 0) {
  // 构建中途失败可能已写下部分产物，一律清掉：只有成功构建才留 dist
  fs.rmSync(DIST_DIR, { recursive: true, force: true })
}

process.exit(result.status ?? 1)
