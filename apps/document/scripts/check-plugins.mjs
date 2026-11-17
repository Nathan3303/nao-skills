#!/usr/bin/env node
/**
 * AC4 自助断言：插件页 ↔ `bin/nao-skill.js` 的 `PI_PLUGINS` 单一事实。
 *
 * 判据（PRD AC4 / QA D2）：
 *   1. `PI_PLUGINS` 的每个 `pkg` 在**渲染产物**（dist/plugins.html）里出现 ≥1 次；
 *   2. 渲染文本里不得出现 `PI_PLUGINS` 清单外的插件包名；
 *   3. 每个插件的分节（`<h3>` 段）内有「缺了（会）失去什么」一句。
 *
 * 守卫（防假绿，与 D8 同族）：dist 缺失或比 `content/plugins.md` / `bin/nao-skill.js` 旧 ⇒ 直接红，
 * 提示先 `npm run docs:build`。
 *
 * 用法：node scripts/check-plugins.mjs（rc=0 = 通过；失败点名到包名）
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const DOCS_ROOT = path.resolve(HERE, '..')
const REPO_ROOT = path.resolve(DOCS_ROOT, '..', '..')
const BIN_FILE = path.join(REPO_ROOT, 'bin', 'nao-skill.js')
const CONTENT_FILE = path.join(DOCS_ROOT, 'content', 'plugins.md')
const PAGE_FILE = path.join(DOCS_ROOT, '.vitepress', 'dist', 'plugins.html')

const problems = []

function fail(message) {
  problems.push(message)
}

/** 从 bin/nao-skill.js 抠出 PI_PLUGINS（name → pkg）。抠不到即红，避免静默失守。 */
function readPluginTable() {
  if (!fs.existsSync(BIN_FILE)) {
    fail(`找不到插件清单源：${BIN_FILE}`)
    return []
  }
  const source = fs.readFileSync(BIN_FILE, 'utf8')
  const block = /const PI_PLUGINS\s*=\s*\{([\s\S]*?)\n\};/.exec(source)
  if (!block) {
    fail('bin/nao-skill.js 里没找到 `const PI_PLUGINS = { ... };`（结构变了，断言需同步）')
    return []
  }

  const entries = []
  const entry = /(?:'([^']+)'|"([^"]+)"|([A-Za-z_$][\w$]*))\s*:\s*\{\s*pkg:\s*'([^']+)'/g
  for (const match of block[1].matchAll(entry)) {
    entries.push({ name: match[1] ?? match[2] ?? match[3], pkg: match[4] })
  }
  if (!entries.length) fail('PI_PLUGINS 解析出 0 个条目（结构变了，断言需同步）')
  return entries
}

function stripHtml(html) {
  return html
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/<script[\s\S]*?<\/script>/g, ' ')
    .replace(/<style[\s\S]*?<\/style>/g, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim()
}

const plugins = readPluginTable()
if (!fs.existsSync(PAGE_FILE)) {
  console.error('✗ 产物缺失：dist/plugins.html（先跑 npm run docs:build）')
  process.exit(1)
}

const distMtime = fs.statSync(PAGE_FILE).mtimeMs
for (const source of [CONTENT_FILE, BIN_FILE]) {
  if (fs.existsSync(source) && fs.statSync(source).mtimeMs > distMtime) {
    console.error(`✗ 产物比源文件旧：${path.relative(REPO_ROOT, source)}（先跑 npm run docs:build）`)
    process.exit(1)
  }
}

const html = fs.readFileSync(PAGE_FILE, 'utf8')
const text = stripHtml(html)

// 分节：每个 <h3> 起一段，用于逐插件核对「缺了失去什么」
const sections = html
  .split(/<h3\b[^>]*>/i)
  .slice(1)
  .map(stripHtml)

if (sections.length < plugins.length) {
  fail(`插件页只有 ${sections.length} 个 <h3> 分节，少于清单的 ${plugins.length} 个（页面结构变了）`)
}

const knownPkgs = new Set(plugins.map((plugin) => plugin.pkg))

/** 按包名 token 切分（`pi-ask-me-x` 不算 `pi-ask-me`，避免子串假绿） */
function tokensOf(chunk) {
  const tokens = new Set()
  for (const match of chunk.matchAll(/(?:@[\w.\-/]+)?pi-[\w.\-]+/g)) {
    tokens.add(match[0].replace(/[.\-]+$/, ''))
  }
  return tokens
}

const pageTokens = tokensOf(text)

for (const { name, pkg } of plugins) {
  if (!pageTokens.has(pkg)) {
    fail(`渲染产物里没有包名 ${pkg}（PI_PLUGINS.${name}）`)
    continue
  }
  const section = sections.find((chunk) => tokensOf(chunk).has(pkg))
  if (!section) {
    fail(`包名 ${pkg} 不在任何 <h3> 分节里（无法核对「缺了失去什么」）`)
    continue
  }
  if (!/缺了(会)?失去什么/.test(section)) {
    fail(`插件 ${pkg} 的分节缺少「缺了失去什么」一句`)
  }
}

// 清单外插件：形如 pi-xxx 或 @scope/pi-xxx 的包名，必须都属于 PI_PLUGINS
for (const token of [...pageTokens].sort()) {
  if (knownPkgs.has(token)) continue
  // 允许页面用不带 scope 的短名指代带 scope 的包
  if ([...knownPkgs].some((pkg) => pkg.endsWith(`/${token}`))) continue
  fail(`出现清单外的插件包名：${token}（不在 bin/nao-skill.js 的 PI_PLUGINS 里）`)
}

if (problems.length) {
  console.error(`✗ AC4 未过：${problems.length} 处问题`)
  for (const problem of problems) console.error(`  · ${problem}`)
  process.exit(1)
}

console.log(
  `✓ AC4 通过：${plugins.length} 个插件与 PI_PLUGINS 逐字一致（${plugins
    .map((plugin) => plugin.pkg)
    .join(' / ')}）· 清单外包名 0 · 每条含「缺了失去什么」`,
)
