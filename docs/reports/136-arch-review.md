# T546 文档站（VitePress）架构评审 · Issue #136

- 状态：**已拍板（PM 2026-11-16：D1–D6 全部采纳 · AC5 用真参数 · Node 分叉接受并登记遗留至 2027-01-31）** · 更新：2026-11-16 · Owner：arch-designer
- 指针：PRD `docs/prds/2026-11-16-docs-site.md` · 设计基线 `docs/designs/2026-11-13-portal-site.md` · ADR `docs/adr/2026-11-16-docs-site-pipeline.md`

## 一、可行性结论

**可行（有条件）**：AC1–AC11 无技术阻断。签字条件 = §三 六条结论落地 + §四 R2/R3/R4 转入 AC 判据。

- 真正的风险面不是构建，是 **AC2/AC10 保真**：门户六段超出 VitePress home 布局能力；默认主题自带 `Inter` 与 `#3451b2`，不脱钩即违反 AC10。
- **AC3 与 AC7 互相压**：卡原文逐字注入会带进 `@.agents/...` 一类字符串；AC7 若按裸 `http` 扫必假红（见 §二 实测）。

## 二、取证（本机实测，非文档转述）

- `vitepress@1.6.4`（latest；`2.0.0-alpha.21` 仍 alpha）· 传递依赖 `vite ^5.4.14` / `vue ^3.5.13`；包无 `engines` 字段。
- 默认主题入口 `theme-default/index.ts:1` = `import './styles/fonts.css'`（自托管 Inter，实测 dist 20 个 woff2）；包导出 `./theme-without-fonts` 可整块脱钩。
- 默认主题 `styles/vars.css`：`--vp-c-brand-1: var(--vp-c-indigo-1)` = `#3451b2`（暗 `#a8b1ff`）；`--vp-font-family-base` 首项 `'Inter'`。
- `appearance: 'force-auto'` ⇒ 走 `usePreferredDark()`，且导航栏开关不渲染 = **跟随系统且无手动开关**（正合 PRD §六）。
- `vitepress build --base /nao-skills/` 实测生效（产物资源前缀已改写）；构建自动产出 `404.html`。
- 空站 dist 的 `http(s)://` 实测命中：`w3.org` 命名空间 ×19、`vuejs.org/error-reference`、`api.iconify.design`、`a.com` ⇒ 裸扫必假红。
- 根 `npm pack --dry-run` = 59 files，`files` 白名单已排除 `apps/` ⇒ AC9 结构性成立，无需动发布面。
- NFR 可达：空站首屏 JS 58.5KB + CSS 19.3KB gzip（实测）⇒ 预算 300KB 余量充足；空站构建 2.65s ⇒ 16 页量级远低于 90s。
- 本机 `node v24.22.1` ⇒ 与 PRD「dev 用 22」不符（R1）。

## 三、待拍板点结论（D1–D6）

1. **D1 依赖归属 = 独立包**：`apps/document` 自有 `package.json` + `package-lock.json`，不用根 workspaces；根只加三个 `npm --prefix` 薄脚本。理由：发布面与站点面靠目录边界隔离，根 `npm ci`（含 `prepack` 门禁）不背站点依赖。
2. **D2 版本与运行时**：`vitepress ^1.6.4`，`vite` / `vue` **不单列**（由 vitepress 传递，单列会造双份 vite）；`apps/document/.nvmrc` = `22.23.5` + 该包 `engines.node >=22`；CI 用 `setup-node` 的 `node-version-file` 读同一文件；根 `engines >=18` 与 devDeps 一字不改。理由：版本的单一事实放包内，npm 用户的 Node 18 前提不受影响。
3. **D3 注入形态 = `markdown.config` 指令（config 内 transform）**：markdown-it 插件在编译期读 `.agents/prompts/<card>.md`、去 frontmatter、现算现渲染；**零中间产物**。helper 写 TS（由 config 的 Vite 加载，不需要 tsx）。`--strict` 由 `apps/document/scripts/build.mjs` 包装 `vitepress build` 承载为**真命令行参数**（PM 裁定；env 形式不作本批口径——VitePress 自身不认 `--strict`，直传给 CLI 会报未知参数）。理由：单管道 = 单失败面，且「产出不入版本库」自动成立。
4. **D4 部署 = `npm ci` → build → 上传 dist**：`base` 由 CI 传 `--base /nao-skills/`（config 保持 `/`，否则 dev/preview 也要带前缀）；缓存只开 `setup-node` 的 npm 缓存 + `cache-dependency-path: apps/document/package-lock.json`（不缓存 `node_modules`）；**失败必须红**：无 `continue-on-error`、上传步骤在 build 之后、旧产物永不重传；`paths` 增 `apps/document/**`、`.agents/prompts/**`、`.agents/roles.yaml`。理由：AC3 的源在 `content/` 之外，filter 不覆盖就等于线上静默过期（R4）。
5. **D5 写入分工 = 保留 `srcDir=content`，`content/index.md` 归 rd-fe**：首页是呈现壳（自建 `PortalHome.vue`），不是内容；PM 只填**已存在**的 `content/**/*.md` 正文，不新建文件、不动 nav/sidebar；页面骨架 + 导航 + 侧栏由 rd-fe 一次成型后交付。理由：把「谁新建文件」这条歧义消掉，剩余只要内容/结构两面。
6. **D6 AC7 判据 = 按资源角色扫，不按字符串扫**：HTML 逐属性判（`script[src]`、`link[href]`（`rel=canonical/alternate` 除外）、`img/source[src|srcset]`、`video/audio[src|poster]`、`iframe[src]`、`object[data]`、`embed[src]`、`meta[property=og:image]`），凡解析出非本站 origin ⇒ 红；CSS 只扫 `url(http…)` 与 `@import` 外部；JS/JSON 用 **CDN · 统计域名 denylist**（jsdelivr / unpkg / cdnjs / fonts.googleapis / fonts.gstatic / googletagmanager / google-analytics / hm.baidu / sentry 等），并白名单命名空间与框架文档字符串（`w3.org/*`、`vuejs.org/error-reference`、`api.iconify.design`——实测均为死字符串）。**双守卫防假绿**：扫描命中文件数 0 ⇒ 直接红；并断言 `dist/index.html` 存在、`*.html` 数量 ≥ 内容页数（六章 + 7 卡 + FAQ + 术语 + 首页）。理由：`a href` 文本链接天然被属性角色排除，裸字符串扫描既假绿（漏 `link`）又假红（命名空间）。

## 四、风险清单（影响 → 应对）

- **R1 dev 与 CI 工具链不一致**（本机 24 / CI 22）→ 构建产物不可复算；`apps/document/.nvmrc` 为 22.23.5 且 CI 同源读取。**PM 2026-11-16 裁定：接受偏差**，本机 24 仅作开发态，登记遗留（到期 2027-01-31：若构建出现版本相关诊断再回看）。
- **R2 默认主题残留**（Inter 字体族、`#3451b2`/`#a8b1ff` 品牌色）→ AC10 直接红；主题入口改 `vitepress/theme-without-fonts`，覆盖 `--vp-font-family-base` 与 `--vp-c-brand-*`；**判据**：dist CSS 不含 `3451b2` / `a8b1ff`、字体栈不含首项 `Inter`。
- **R3 首页六段超 `layout: home` 能力**（home 只有 hero+features）→ AC2 保真被默认布局削；用 `layout: page` + 自建 `PortalHome.vue`（rd-fe 拥有），只复用 token 不套默认首页。
- **R4 Pages `paths` 漏卡源** → 改卡不重建，AC3 线上静默过期；见 D4。
- **R5 dev 下改卡无 HMR** → 改了卡看不到；`vite: { server: { watcher: { … } } }` 把 `.agents/prompts` 加入监听（一行，非强制）。
- **R6 NFR 余量会被自家资源吃掉** → 首页组件若引入大图/图标字体，300KB 预算即破；首屏只允许 CSS 绘制（设计基线 §三 已定），图标用内联 SVG，禁新增字体文件。
- **R7 AC5 在 CI 不可验证**（仓库恒有 `.agents/prompts`）→「默认不崩」可能假绿；QA 在临时副本移走该目录真跑两次：默认 rc=0 且 stderr 出现**一条**显式告警、`--strict` rc≠0。

## 五、交付约束（RD 照做，非本报告展开项）

- 版本锁定：`apps/document` 提交 `package-lock.json`；vitepress 走 `^1.6.4`，**不接 2.x alpha**。
- `.gitignore` 需补 `.vitepress/dist/`、`.vitepress/cache/`；注入零产物 ⇒ 不新增其它忽略项。
- 根三脚本 = `npm --prefix apps/document run <dev|build|preview>`；首次须 `npm install --prefix apps/document`（README 一句前置）。
- AC7 扫描器由 QA 自带（不入 build 脚本、不入 `tests/`），与 `--strict`（只管道卡源缺失）职责分离。

- 修订：2026-11-16 首版（D1–D6 结论 + 取证 + 风险）
- 修订：2026-11-16 PM 裁定：D1–D6 采纳 · AC5 走真参数 · Node 分叉接受并登记遗留（2027-01-31）
