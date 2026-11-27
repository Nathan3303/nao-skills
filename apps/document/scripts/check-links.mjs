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
 * 图标守卫：每个 `<link rel="icon" href>` 都要在 dist 里找到对应文件（含 `--base` 前缀两种解析）。
 * 一个 icon link 都没扫到同样算红 —— 否则「检查器扫了个空」会被当成通过。
 */
function checkIcons() {
  const hrefs = new Set()
  let iconLinks = 0
  for (const file of walk(DIST)) {
    if (path.extname(file) !== '.html') continue
    const raw = fs.readFileSync(file, 'utf8')
    for (const match of raw.matchAll(/<link\b[^>]*>/gi)) {
      const element = match[0]
      const rel = /\brel\s*=\s*["']([^"']*)["']/i.exec(element)
      // 覆盖所有图标语义：icon / apple-touch-icon / mask-icon（T590 起 apple-touch 也在这里把守）
      if (!rel || !rel[1].toLowerCase().includes('icon')) continue
      const href = /\bhref\s*=\s*["']([^"']*)["']/i.exec(element)
      if (!href) continue
      iconLinks += 1
      hrefs.add(href[1])
    }
  }

  if (iconLinks === 0) {
    problems.push('未扫到任何 <link rel="icon">（页面丢了图标，或本守卫已失效）')
    return 0
  }

  for (const href of hrefs) {
    const clean = href.split(/[?#]/)[0]
    if (!clean) {
      problems.push(`<link rel="icon" href="${href}"> 是空值`)
      continue
    }
    const relative = clean.replace(/^\/+/, '')
    const candidates = [path.join(DIST, relative)]
    // 带 base 的构建（href=/nao-skills/favicon.svg）在 dist 里是根路径，剥掉第一段再试
    const withoutBase = relative.split('/').slice(1).join('/')
    if (withoutBase) candidates.push(path.join(DIST, withoutBase))
    const hit = candidates.find((candidate) => {
      try {
        return fs.existsSync(candidate) && fs.statSync(candidate).size > 0
      } catch {
        return false
      }
    })
    if (!hit) {
      const tried = candidates.map((candidate) => path.relative(DIST, candidate)).join(' 或 ')
      problems.push(`<link rel="icon" href="${href}"> 在产物里没有对应文件（找过 ${tried}）`)
    }
  }

  return hrefs.size
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

const iconCount = checkIcons()

if (problems.length) {
  console.error(`✗ check 未过：发现 ${problems.length} 处问题（外链 / 图标引用）`)
  for (const problem of problems.slice(0, 40)) console.error(`  · ${problem}`)
  if (problems.length > 40) console.error(`  … 其余 ${problems.length - 40} 处略`)
  process.exit(1)
}

console.log(
  `✓ AC7 通过：扫描 ${scanned} 个文件（html ${htmlCount}）· 校验 ${attrChecked} 个资源属性 · 外链 0 处 · 图标引用 ${iconCount} 项且文件成对`,
)
