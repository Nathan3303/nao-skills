#!/usr/bin/env node
/**
 * AC7「产物零外链」扫描器 —— 判据按 ADR 2026-11-16-docs-site-pipeline D6：
 *
 *   HTML 按**资源角色**逐属性判（a href 文本链接天然排除）
 *   CSS 只扫 url(http…) 与 @import 外部
 *   JS/JSON 用 CDN / 统计域名 denylist，并白名单已知的死字符串
 *
 * 双守卫防假绿：命中文件数 0 ⇒ 红；dist/index.html 不存在或 *.html 数量不足 ⇒ 红。
 *
 * 第三条守卫（T588 / Issue #250）：<link rel="icon"> 的 href 必须在产物里有对应文件 ——
 * transformHead 写的 `${base}favicon.svg` 曾指向一个从未进 dist 的位置（源文件放在 apps/document/public，
 * 而 srcDir 是 content，publicDir 跟着走），构建、外链扫描、链接检查全绿但线上 favicon 404。
 *
 * 用法：node scripts/check-links.mjs   （rc=0 = 通过；rc=1 = 有外链或守卫未过）
 */
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = path.dirname(fileURLToPath(import.meta.url))
const DIST = path.resolve(HERE, '..', '.vitepress', 'dist')

/** 内容页数下限：六章 + 7 卡 + FAQ + 术语 + 首页（ADR D6） */
const MIN_HTML = 16

const HTML_ATTRS = [
  { tag: 'script', attr: 'src' },
  { tag: 'link', attr: 'href', skipRel: ['canonical', 'alternate'] },
  { tag: 'img', attr: 'src' },
  { tag: 'img', attr: 'srcset', srcset: true },
  { tag: 'source', attr: 'src' },
  { tag: 'source', attr: 'srcset', srcset: true },
  { tag: 'video', attr: 'src' },
  { tag: 'video', attr: 'poster' },
  { tag: 'audio', attr: 'src' },
  { tag: 'iframe', attr: 'src' },
  { tag: 'object', attr: 'data' },
  { tag: 'embed', attr: 'src' },
]

const DENYLIST = [
  'jsdelivr',
  'unpkg.com',
  'cdnjs',
  'fonts.googleapis',
  'fonts.gstatic',
  'googletagmanager',
  'google-analytics',
  'hm.baidu',
  'sentry',
]

const ALLOWLIST = [
  'www.w3.org',
  'w3.org',
  'vuejs.org/error-reference',
  'api.iconify.design',
]

const problems = []
let scanned = 0
let htmlCount = 0
let attrChecked = 0

function walk(dir) {
  const out = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) out.push(...walk(full))
    else out.push(full)
  }
  return out
}

function isLocal(url) {
  if (url === '' || url === undefined) return true
  if (url.startsWith('#')) return true
  if (url.startsWith('data:') || url.startsWith('mailto:')) return true
  if (url.startsWith('//')) return false
  return !/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(url)
}

function isAllowedString(text) {
  return ALLOWLIST.some((allowed) => text.includes(allowed))
}

function checkHtml(file, raw) {
  for (const { tag, attr, srcset, skipRel } of HTML_ATTRS) {
    const tagRe = new RegExp(`<${tag}\\b[^>]*>`, 'gi')
    for (const match of raw.matchAll(tagRe)) {
      const element = match[0]
      if (skipRel) {
        const relMatch = /\brel\s*=\s*["']([^"']*)["']/i.exec(element)
        const rel = relMatch ? relMatch[1].toLowerCase() : ''
        if (skipRel.some((value) => rel.includes(value))) continue
      }
      const attrRe = new RegExp(`\\b${attr}\\s*=\\s*["']([^"']*)["']`, 'i')
      const attrMatch = attrRe.exec(element)
      if (!attrMatch) continue
      const values = srcset ? attrMatch[1].split(',').map((part) => part.trim().split(/\s+/)[0]) : [attrMatch[1]]
      for (const value of values) {
        attrChecked += 1
        if (!isLocal(value)) problems.push(`${path.relative(DIST, file)}: <${tag} ${attr}="${value}">`)
      }
    }
  }

  // og:image（meta property）
  for (const match of raw.matchAll(/<meta\b[^>]*>/gi)) {
    const element = match[0]
    if (!/property\s*=\s*["']og:image["']/i.test(element)) continue
    const content = /content\s*=\s*["']([^"']*)["']/i.exec(element)
    if (content && !isLocal(content[1])) {
      problems.push(`${path.relative(DIST, file)}: <meta og:image="${content[1]}">`)
    }
  }
}

function checkCss(file, raw) {
  for (const match of raw.matchAll(/url\(\s*['"]?(https?:[^'")]+)['"]?\s*\)/gi)) {
    problems.push(`${path.relative(DIST, file)}: css url(${match[1]})`)
  }
  for (const match of raw.matchAll(/@import\s+(?:url\()?['"]?(https?:[^'");]+)/gi)) {
    problems.push(`${path.relative(DIST, file)}: @import ${match[1]}`)
  }
}

function checkScript(file, raw) {
  if (isAllowedString(raw)) {
    // 白名单只覆盖已知死字符串，仍需继续查 denylist（下面按内容整体判）
  }
  for (const domain of DENYLIST) {
    let index = raw.indexOf(domain)
    while (index !== -1) {
      const context = raw.slice(Math.max(0, index - 120), index + domain.length + 120)
      if (!isAllowedString(context)) {
        problems.push(`${path.relative(DIST, file)}: 命中 ${domain}`)
        break
      }
      index = raw.indexOf(domain, index + 1)
    }
  }
}

/**
 * 图标守卫：两件事一起把守。
 *
 *   ① 前缀一致（T591）：icon / apple-touch 的 href 前缀必须与**同页其它资源**一致。
 *      基准取同页 `<script src>`（或 stylesheet / modulepreload 的 href）中 `assets/` 之前那一段 ——
 *      那是构建真正用的 base（`/` 或 `/nao-skills/`）。**为什么不信 config**：base 有两条来路
 *      （配置文件 `base` 与 CLI `--base`），两处各算一次就会静默错位；同页比对抓的是产物事实，
 *      不管前缀是哪个原因崩的。
 *   ② 文件存在：href 指向的文件要在 dist 里是**非空**文件。
 *
 * 能力边界（别过度解读）：② 的「剥一段前缀再试」只证明「产物里有这个文件」，**不证明部署前缀与
 * 服务一致** —— 部署路径是否挂对，只能靠线上 200 验证。
 *
 * 一个 icon link 都没扫到同样算红 —— 否则「检查器扫了个空」会被当成通过。
 *
 * @returns {{links:number, unique:number}} links = 命中的 `<link rel=…icon>` 条数（23 页 × 2），
 *   unique = 去重后的 href 数（文件数）。
 */
function assetPrefixOf(raw) {
  for (const match of raw.matchAll(/<(?:script|link)\b[^>]*>/gi)) {
    const element = match[0]
    let url
    if (/^<script/i.test(element)) {
      url = /\bsrc\s*=\s*["']([^"']*)["']/i.exec(element)?.[1]
    } else {
      const rel = /\brel\s*=\s*["']([^"']*)["']/i.exec(element)?.[1] ?? ''
      if (!/stylesheet|modulepreload/i.test(rel)) continue
      url = /\bhref\s*=\s*["']([^"']*)["']/i.exec(element)?.[1]
    }
    if (!url || !url.startsWith('/')) continue
    const index = url.indexOf('assets/')
    if (index <= 0) continue
    return url.slice(0, index) // '/' 或 '/nao-skills/'
  }
  return null
}

function checkIcons(distDir = DIST, sink = problems) {
  let links = 0
  const hrefs = new Set()

  for (const file of walk(distDir)) {
    if (path.extname(file) !== '.html') continue
    const raw = fs.readFileSync(file, 'utf8')
    const prefix = assetPrefixOf(raw)
    const icons = []
    for (const match of raw.matchAll(/<link\b[^>]*>/gi)) {
      const element = match[0]
      const rel = /\brel\s*=\s*["']([^"']*)["']/i.exec(element)
      // 覆盖所有图标语义：icon / apple-touch-icon / mask-icon（T590 起 apple-touch 也在这里把守）
      if (!rel || !rel[1].toLowerCase().includes('icon')) continue
      const href = /\bhref\s*=\s*["']([^"']*)["']/i.exec(element)
      if (!href) continue
      links += 1
      hrefs.add(href[1])
      icons.push(href[1])
    }

    if (prefix && icons.length) {
      for (const href of icons) {
        if (!href.startsWith(prefix)) {
          sink.push(
            `${path.relative(distDir, file)}: 前缀不一致（icon "${href}" vs 其它资源 "${prefix}…"）`,
          )
        }
      }
    }
  }

  if (links === 0) {
    sink.push('未扫到任何 <link rel="icon">（页面丢了图标，或本守卫已失效）')
    return { links: 0, unique: 0 }
  }

  for (const href of hrefs) {
    const clean = href.split(/[?#]/)[0]
    if (!clean) {
      sink.push(`<link rel="icon" href="${href}"> 是空值`)
      continue
    }
    const relative = clean.replace(/^\/+/, '')
    const candidates = [path.join(distDir, relative)]
    // 带 base 的构建（href=/nao-fleet/favicon.svg）在 dist 里是根路径，剥掉第一段再试
    const withoutBase = relative.split('/').slice(1).join('/')
    if (withoutBase) candidates.push(path.join(distDir, withoutBase))
    const hit = candidates.find((candidate) => {
      try {
        return fs.existsSync(candidate) && fs.statSync(candidate).size > 0
      } catch {
        return false
      }
    })
    if (!hit) {
      const tried = candidates.map((candidate) => path.relative(distDir, candidate)).join(' 或 ')
      sink.push(`<link rel="icon" href="${href}"> 在产物里没有对应文件（找过 ${tried}）`)
    }
  }

  return { links, unique: hrefs.size }
}

/**
 * 图标守卫自检（`--self-test`）：用最小夹具跑 4 个正负控，断言守卫本身不会静默失真。
 * 手动造一次反例只能证明「此刻」，这条自检证明「以后改守卫也还抓得住」。
 * 夹具刻意用**不透明标记文件**（内容非空），与真实位图/图标同形，不靠合成占位取巧。
 */
function runSelfTest() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'nao-icon-guard-'))
  const make = (name, html, files = []) => {
    const dist = path.join(root, name)
    fs.mkdirSync(dist, { recursive: true })
    fs.writeFileSync(path.join(dist, 'index.html'), html)
    for (const file of files) {
      fs.mkdirSync(path.dirname(path.join(dist, file)), { recursive: true })
      fs.writeFileSync(path.join(dist, file), 'x')
    }
    return dist
  }

  const script = '<script src="/nao-skills/assets/app.js"></script>'
  const run = (dist) => {
    const sink = []
    const counts = checkIcons(dist, sink)
    return { sink, counts }
  }

  const cases = []

  {
    const dist = make(
      'consistent',
      `<html><head>${script}<link rel="icon" href="/nao-skills/favicon.svg"><link rel="apple-touch-icon" href="/nao-skills/apple-touch-icon.png"></head></html>`,
      ['favicon.svg', 'apple-touch-icon.png'],
    )
    const { sink, counts } = run(dist)
    cases.push({
      name: '正控 · 前缀一致且文件在',
      ok: sink.length === 0 && counts.links === 2 && counts.unique === 2,
      detail: `problems=${sink.length} links=${counts.links} unique=${counts.unique}`,
    })
  }

  {
    const dist = make(
      'prefix-mismatch',
      `<html><head>${script}<link rel="icon" href="/favicon.svg"></head></html>`,
      ['favicon.svg'],
    )
    const { sink } = run(dist)
    cases.push({
      name: '反例 · 前缀与其它资源不一致',
      ok: sink.length === 1 && sink[0].includes('前缀不一致'),
      detail: sink[0] ?? '(没有报错 —— 守卫失效)',
    })
  }

  {
    const dist = make(
      'missing-file',
      `<html><head>${script}<link rel="icon" href="/nao-skills/favicon.svg"></head></html>`,
    )
    const { sink } = run(dist)
    cases.push({
      name: '反例 · 前缀对但产物里没有文件',
      ok: sink.length === 1 && sink[0].includes('没有对应文件'),
      detail: sink[0] ?? '(没有报错 —— 守卫失效)',
    })
  }

  {
    const dist = make('no-icons', `<html><head>${script}</head></html>`)
    const { sink } = run(dist)
    cases.push({
      name: '反例 · 一个图标都没扫到',
      ok: sink.length === 1 && sink[0].includes('未扫到任何'),
      detail: sink[0] ?? '(没有报错 —— 守卫失效)',
    })
  }

  fs.rmSync(root, { recursive: true, force: true })

  let failed = 0
  for (const testCase of cases) {
    if (!testCase.ok) failed += 1
    console.log(`${testCase.ok ? '✓' : '✗'} ${testCase.name} · ${testCase.detail}`)
  }
  console.log(`图标守卫自检：${cases.length - failed}/${cases.length} 通过`)
  return failed === 0
}

if (process.argv.includes('--self-test')) {
  process.exit(runSelfTest() ? 0 : 1)
}

if (!fs.existsSync(DIST)) {
  console.error(`✗ 产物目录不存在：${DIST}（先跑 npm run docs:build）`)
  process.exit(1)
}

if (!fs.existsSync(path.join(DIST, 'index.html'))) {
  console.error('✗ 守卫未过：dist/index.html 不存在')
  process.exit(1)
}

for (const file of walk(DIST)) {
  const ext = path.extname(file)
  if (!['.html', '.css', '.js', '.json'].includes(ext)) continue
  scanned += 1
  const raw = fs.readFileSync(file, 'utf8')
  if (ext === '.html') {
    htmlCount += 1
    checkHtml(file, raw)
  } else if (ext === '.css') {
    checkCss(file, raw)
  } else {
    checkScript(file, raw)
  }
}

if (scanned === 0) {
  console.error('✗ 守卫未过：扫描命中文件数 0（扫描器自身失效，不能算通过）')
  process.exit(1)
}

if (htmlCount < MIN_HTML) {
  console.error(`✗ 守卫未过：dist 只有 ${htmlCount} 个 html（下限 ${MIN_HTML}：首页 + 六章 + 7 卡 + FAQ + 术语）`)
  process.exit(1)
}

const icons = checkIcons()

if (problems.length) {
  console.error(`✗ check 未过：发现 ${problems.length} 处问题（外链 / 图标引用）`)
  for (const problem of problems.slice(0, 40)) console.error(`  · ${problem}`)
  if (problems.length > 40) console.error(`  … 其余 ${problems.length - 40} 处略`)
  process.exit(1)
}

console.log(
  `✓ AC7 通过：扫描 ${scanned} 个文件（html ${htmlCount}）· 校验 ${attrChecked} 个资源属性 · 外链 0 处 · 图标 ${icons.links} 条 / ${icons.unique} 个唯一文件（前缀与文件成对）`,
)
