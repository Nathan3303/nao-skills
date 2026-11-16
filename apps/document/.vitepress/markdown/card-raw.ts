/**
 * 角色卡原文的构建期注入（ADR 2026-11-16-docs-site-pipeline D3）。
 *
 * 页面里只写一个「占位栅栏」：
 *
 *   ```card pm
 *   ```
 *
 * 编译期由本模块替换为 `.agents/prompts/<card>.md` 的**现读正文**：
 *   - 零中间产物（不产出 json / md 副本）、零网络；
 *   - frontmatter 整块剥掉，正文原文渲染；
 *   - 卡内标题整体降一级（h1→h2 …），保证每页 h1 唯一、h2/h3 不跳级；
 *   - 徽标带来源路径与卡内 `version`，不靠颜色区分「解说 / 原文」。
 *
 * 容错（AC5）：仓库缺 `.agents/prompts` ⇒ 渲染「卡原文见仓库」占位 + 一条显式告警，
 * 构建不缺省失败；`--strict` 的失败语义由 scripts/build.mjs 承担。
 */
import fs from 'node:fs'
import path from 'node:path'
import MarkdownIt from 'markdown-it'
import {
  CARDS_MISSING_ENV,
  PROMPTS_DIR,
  readCard,
  readCardSource,
} from './repo-source'

const CARD_FENCE = /^card\s+(\S+)$/

const INFO_ICON =
  '<svg class="card-raw-icon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false">' +
  '<path fill="currentColor" d="M8 1.2a6.8 6.8 0 1 0 0 13.6A6.8 6.8 0 0 0 8 1.2Zm0 2.6a1.1 1.1 0 1 1 0 2.2 1.1 1.1 0 0 1 0-2.2Zm.95 7.9h-1.9V7.05h1.9v4.65Z"/></svg>'

const ALERT_ICON =
  '<svg class="card-raw-icon" viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" focusable="false">' +
  '<path fill="currentColor" d="M8 1.4 15 14H1L8 1.4Zm0 3.2a.9.9 0 0 0-.9.9v3.4a.9.9 0 0 0 1.8 0V5.5a.9.9 0 0 0-.9-.9Zm0 6a1 1 0 1 0 0 2 1 1 0 0 0 0-2Z"/></svg>'

/** 卡正文渲染器：独立的 markdown-it 实例（不继承站点插件，避免锚点 id 与页面标题撞车）。 */
const cardMd = new MarkdownIt({
  html: true,
  linkify: false,
  typographer: false,
  breaks: false,
})

// 标题降一级：页面 h1 = 角色名，卡内 h1 = 角色卡抬头，落在 h2 起；
// 同时补 id（默认主题的右栏 TOC 只收带 id 的标题），页面里不会与站点标题撞 id。
for (const rule of ['heading_open', 'heading_close']) {
  if (rule === 'heading_close') {
    cardMd.renderer.rules[rule] = (tokens, idx, options, _env, self) => {
      const token = tokens[idx]
      token.tag = `h${Math.min(Number(token.tag.slice(1)) + 1, 6)}`
      return self.renderToken(tokens, idx, options)
    }
    continue
  }

  cardMd.renderer.rules[rule] = (tokens, idx, options, env, self) => {
    const token = tokens[idx]
    token.tag = `h${Math.min(Number(token.tag.slice(1)) + 1, 6)}`

    const used: Set<string> = (env?.__cardHeadingIds as Set<string>) ?? new Set<string>()
    env.__cardHeadingIds = used
    const text = tokens[idx + 1]?.content ?? ''
    const base = text
      .toLowerCase()
      .replace(/[`*_~\[\]()<>]/g, '')
      .replace(/[^\p{L}\p{N}]+/gu, '-')
      .replace(/^-+|-+$/g, '') || 'section'
    let id = base
    let suffix = 2
    while (used.has(id)) id = `${base}-${suffix++}`
    used.add(id)
    token.attrSet('id', id)

    return self.renderToken(tokens, idx, options)
  }
}

/** 缺卡源占位：不隐藏周边导航，也不假装有原文。 */
function missingRegion(relPath: string, reason: string): string {
  return [
    '<section class="card-raw-region card-raw-region--missing" aria-labelledby="card-raw-label">',
    '<p class="card-raw-sep" aria-hidden="true">人话版 ↑ / 权威原文 ↓</p>',
    `<p class="card-raw-badge">${ALERT_ICON}<span>来源 · <code>${relPath}</code> · 构建期未注入</span></p>`,
    '<p class="card-raw-label" id="card-raw-label">卡原文</p>',
    `<p class="card-raw-hint">${ALERT_ICON}<span><strong>卡原文见仓库</strong>：本次构建没找到角色卡源（${reason}）。` +
      `原文只在 <code>.agents/prompts/</code> 里，请在源码仓库查看 <code>${relPath}</code>；本页解说不受影响。</span></p>`,
    '</section>',
  ].join('')
}

function presentRegion(relPath: string, version: string | null, html: string): string {
  const versionText = version ? `v${version}` : '版本未知'
  return [
    '<section class="card-raw-region" aria-labelledby="card-raw-label">',
    '<p class="card-raw-sep" aria-hidden="true">人话版 ↑ / 权威原文 ↓</p>',
    `<p class="card-raw-badge">${INFO_ICON}<span>来源 · <code>${relPath}</code> · ${versionText} · 构建期注入</span></p>`,
    '<p class="card-raw-label" id="card-raw-label">卡原文（构建期注入，未改写）</p>',
    `<article class="card-raw-body">${html}</article>`,
    '</section>',
  ].join('')
}

let warned = false

/** 渲染一张卡的区域 HTML；卡 id 未知或卡文件缺失属仓库缺陷 ⇒ fail loud。 */
function renderCardRegion(id: string): string {
  const source = readCardSource()

  if (!source.available) {
    if (process.env.NAO_STRICT === '1') {
      // build.mjs 已前置拦截；这里是第二道（直接跑 vitepress build 时的兜底）
      throw new Error('[card-raw] --strict：未找到 .agents/prompts，角色卡原文无法注入')
    }
    if (!warned && process.env[CARDS_MISSING_ENV] !== '1') {
      // build.mjs 已在 stderr 打过一条时不再重复（避免双告警）
      console.warn('⚠ 跳过角色卡注入：未找到 .agents/prompts（角色页显示「卡原文见仓库」）')
      warned = true
    }
    return missingRegion(`.agents/prompts/${id}.md`, source.reason)
  }

  const role = source.roles.find((entry) => entry.id === id)
  if (!role) {
    throw new Error(
      `[card-raw] 页面里的角色 id 未在 .agents/roles.yaml 声明：${id}（跑 .agents/scripts/nao-fleet.sh check 复核）`,
    )
  }

  const card = readCard(role)
  if (!card) {
    throw new Error(
      `[card-raw] 角色卡文件缺失：${path.join(PROMPTS_DIR, role.card)}（.agents/prompts 存在但该卡不在）`,
    )
  }

  return presentRegion(card.relPath, card.version, cardMd.render(card.body, {}))
}

/** VitePress `markdown.config` 钩子：只拦截 info 形如 `card <role-id>` 的栅栏。 */
export function cardRawPlugin(md: MarkdownIt): void {
  const fallback = md.renderer.rules.fence
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const info = tokens[idx].info.trim()
    const match = CARD_FENCE.exec(info)
    if (!match) {
      return fallback
        ? fallback(tokens, idx, options, env, self)
        : self.renderToken(tokens, idx, options)
    }
    return renderCardRegion(match[1])
  }
}

/** dev 下把 `.agents/prompts` 显式纳入监听（卡源在 Vite root 之外，默认不热更）。 */
export function cardsWatcher(): {
  name: string
  apply: 'serve'
  configureServer: (server: { watcher: { add: (p: string) => void; on: (e: string, cb: (event: string, file: string) => void) => void }; ws: { send: (payload: { type: string }) => void } }) => void
} {
  return {
    name: 'nao-cards-watch',
    apply: 'serve',
    configureServer(server) {
      if (!fs.existsSync(PROMPTS_DIR)) return
      server.watcher.add(PROMPTS_DIR)
      server.watcher.on('all', (_event, file) => {
        if (file.startsWith(PROMPTS_DIR)) {
          server.ws.send({ type: 'full-reload' })
        }
      })
    },
  }
}
