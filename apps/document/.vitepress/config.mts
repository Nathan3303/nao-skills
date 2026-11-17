/**
 * 文档站配置。设计唯一基准：docs/designs/2026-11-16-docs-site.md
 * 架构：docs/adr/2026-11-16-docs-site-pipeline.md（独立包 / 编译期注入 / 构建后部署）
 *
 * 约定：
 *   - `base` 保持 '/'：CI 用 `vitepress build --base /nao-skills/`，dev/preview 不带前缀；
 *   - 首页走 `layout: page` + 自建 PortalHome（默认 home 版式承载不了六段结构）；
 *   - 侧栏「七个角色」组由 `.agents/roles.yaml` 生成（顺序与名称不手写）。
 */
import { defineConfig } from 'vitepress'
import { cardsWatcher, cardRawPlugin } from './markdown/card-raw'
import { REPO_ROOT, readRoles } from './markdown/repo-source'
import { stripThemeResidue } from './vite/strip-theme-residue'

const roleItems = readRoles().map((role) => ({
  text: role.id,
  link: `/roles/${role.id}`,
}))

const sidebar = [
  {
    text: '快速开始',
    items: [
      { text: '装前置', link: '/quickstart/prereq' },
      { text: '装机制', link: '/quickstart/install' },
      { text: '拉队开工', link: '/quickstart/fleet' },
      { text: '排错', link: '/quickstart/troubleshoot' },
    ],
  },
  {
    text: '它怎么干活',
    items: [
      { text: '一个需求的旅程', link: '/how/task-journey' },
      { text: '验收与回执', link: '/how/acceptance' },
    ],
  },
  {
    text: '七个角色',
    items: roleItems,
  },
  {
    text: '角色配合',
    items: [
      { text: '谁派谁', link: '/collab/dispatch' },
      { text: '冲突与升级', link: '/collab/conflict' },
    ],
  },
  {
    text: '插件选择',
    items: [{ text: '内置 5 个', link: '/plugins' }],
  },
  {
    text: '进阶用法',
    items: [
      { text: '多项目布局', link: '/advanced/multi-project' },
      { text: '自定义角色卡', link: '/advanced/custom-cards' },
    ],
  },
  { text: '常见问题', link: '/faq' },
  { text: '术语表', link: '/glossary' },
]

// 首页 og 文案与旧门户逐字一致（基线 §八 SEO 条目）；纯静态、无统计
const HOME_OG = {
  title: 'nao-skills · 给你的 pi 配一支开发小队',
  description: '7 个 AI 角色分工干活，各管一段。你只做两件事：回答问题、点确认。纯静态、零外部依赖。',
}

// 角色页「解说区」包裹：设计 §八 要求两区各自用 <section aria-labelledby> 命名。
// 解说正文归 PM，这里只在渲染产物外面加壳（隐藏标签不进视觉，不新增文案）。
function wrapRoleGuide(html: string): string {
  if (!html.includes('card-raw-region') || html.includes('role-guide-label')) return html
  const pattern = /(<h1\b[^>]*>[\s\S]*?<\/h1>)([\s\S]*?)(<section class="card-raw-region")/
  if (!pattern.test(html)) return html
  return html.replace(
    pattern,
    (_match, h1: string, middle: string, region: string) =>
      `${h1}<section class="role-guide" aria-labelledby="role-guide-label">` +
      `<p class="visually-hidden" id="role-guide-label">人话解说</p>` +
      `${middle}</section>${region}`,
  )
}

export default defineConfig({
  lang: 'zh-CN',
  title: 'nao-skills',
  titleTemplate: ':title · nao-skills',
  description: '给你的 pi 配一支开发小队：7 个 AI 角色分工干活，你只回答问题、点确认。',
  appearance: 'force-auto',
  cleanUrls: true,
  srcDir: 'content',
  head: [
    ['meta', { name: 'color-scheme', content: 'light dark' }],
    ['meta', { name: 'theme-color', content: '#FFFFFF', media: '(prefers-color-scheme: light)' }],
    ['meta', { name: 'theme-color', content: '#0B0F14', media: '(prefers-color-scheme: dark)' }],
  ],
  // favicon 走 transformHead：`--base /nao-skills/` 时静态 head 不会被改前缀
  transformHead({ pageData, title, description, siteData }) {
    const base = siteData.base || '/'
    const isHome = pageData.relativePath === 'index.md'
    return [
      ['link', { rel: 'icon', type: 'image/svg+xml', href: `${base}favicon.svg` }],
      ['meta', { property: 'og:type', content: 'website' }],
      ['meta', { property: 'og:locale', content: 'zh_CN' }],
      ['meta', { property: 'og:title', content: isHome ? HOME_OG.title : title }],
      ['meta', { property: 'og:description', content: isHome ? HOME_OG.description : description }],
    ]
  },
  // 角色页解说区包裹（两区各自命名，设计 §八）
  transformHtml(html, _id, ctx) {
    if (!ctx.pageData.relativePath?.startsWith('roles/')) return html
    return wrapRoleGuide(html)
  },
  markdown: {
    // 代码块复制按钮与首页同文案（视觉统一在 theme/styles/content.css）
    codeCopyButtonTitle: '复制',
    config: (md) => {
      // VitePress 自带 markdown-it 类型与 @types/markdown-it 存在版本分叉：只在这一处边界放宽，
      // 插件内部仍然按 markdown-it 的真实签名实现（ADR D3：无自研构建层）。
      md.use(cardRawPlugin as unknown as Parameters<typeof md.use>[0])
    },
  },
  vite: {
    plugins: [cardsWatcher(), stripThemeResidue()],
    server: {
      // 卡源与 roles.yaml 在 apps/document 之外，dev 需要读仓库根
      fs: { allow: [REPO_ROOT] },
    },
  },
  themeConfig: {
    // 品牌左、GitHub 右；四个入口不给搜索（本批不启用搜索）
    nav: [
      { text: '文档', link: '/quickstart/prereq', activeMatch: '^/quickstart/' },
      { text: '角色', link: '/roles/pm', activeMatch: '^/roles/' },
      { text: '插件', link: '/plugins', activeMatch: '^/plugins' },
      {
        text: 'GitHub ↗',
        link: 'https://github.com/Nathan3303/nao-skills',
        target: '_blank',
        rel: 'noopener',
      },
    ],
    sidebar,
    outline: { level: [2, 3], label: '本页目录' },
    docFooter: { prev: '上一篇', next: '下一篇' },
    editLink: undefined,
    socialLinks: [],
    skipToContentLabel: '跳到主内容',
    returnToTopLabel: '回到顶部',
    sidebarMenuLabel: '菜单',
    darkModeSwitchLabel: '外观',
    externalLinkIcon: true,
    notFound: {
      title: '页面不存在',
      quote: '这一页还没写，或者链接写错了。回首页，或用侧栏目录继续找。',
      linkLabel: '回首页',
      linkText: '回首页',
    },
  },
})
