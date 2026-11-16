# ADR：文档站构建与交付管线

- 状态：已接受（待落地）
- 更新：2026-11-16
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-11-16-docs-site.md` · 评审报告 `docs/reports/136-arch-review.md` · Issue #136

## 背景

- 门户 `site/` 是零构建直传 Pages 的单页；新增文档站必须在构建期生成，且角色卡正文只能来自 `.agents/prompts/*.md`（单一事实）。
- 约束：根目录是 npm 发布包（`files` 白名单不含 `apps/`）；站点零外链、构建零网络、缺卡源默认不崩；AC 另有 `--strict` 失败语义。

## 决策

1. `apps/document` 为**独立私有包**（自有 `package.json` + `package-lock.json`），不纳入根 npm workspaces；根只留 `docs:dev|build|preview` 三个 `npm --prefix` 薄脚本。
2. 角色卡走 **VitePress `markdown.config` 的 markdown-it 指令**编译期现读现渲染，不产出任何中间产物；`--strict` 由 `apps/document/scripts/build.mjs` 包装 `vitepress build` 承载。
3. Pages 改为 构建 → 上传 `apps/document/.vitepress/dist`（`--base /nao-skills/` 由 CI 传 CLI，config 保持 `/`）；构建失败即工作流红，永不回传旧产物。

## 理由

1. 业务匹配：发布面与站点面靠目录边界隔离，AC9 由结构保证而非靠约定。
2. 技术成熟度：三项均为框架一等公民（独立包 / `markdown.config` / CLI `--base`），无自研构建层。
3. 团队能力：单管道 = 单失败面；QA 只需 `docs:build` 一个接缝 + dist 扫描。
4. 成本：零中间产物 ⇒ 零 gitignore 例外、零「脚本先跑否则空页」时序坑；CI 只多一条 npm 缓存。

## 对照过的备选模式

1. **根 npm workspaces（单 lockfile）** —— 适用：多包共享依赖、需跨包引用；代价：根 `npm ci` 每次多装站点依赖、根 lockfile 被污染、发布包与站点的 Node 前提被强行统一；**不采纳**。
2. **独立私有包（采纳）** —— 适用：发布包与内部开发工具共存；代价：两处安装（`npm install --prefix apps/document`）；**采纳**。
3. **构建期脚本产出 `.vitepress/data/cards.json`** —— 适用：注入物需多页/客户端复用；代价：产物要 gitignore、dev 需重跑脚本、失败面分散在脚本与页面两处；**不采纳**。
4. **`transformPageData` 注入卡正文** —— 该钩子只能改 pageData，正文在 markdown 编译阶段才成型，落不了；**不采纳**。
5. **config 内 markdown-it 指令（采纳）** —— 适用：源是仓库内 md 且要求单一事实；代价：卡在 `content/` 之外，dev 需把 `.agents/prompts` 加入 vite watcher 才有热更；**采纳**（附此缓解）。
6. **维持现状（零构建直传）** —— 适用：单页门户；代价：无路由/侧栏/高亮，深度内容承载不了（PRD §一 的瓶颈）；**不采纳**。

## 后果与风险

- 正面：「产出不入版本库」自动满足；AC9 结构性成立；站点依赖升级不触碰发布面。
- 负面：两处 `npm install`；根 `docs:*` 裸跑会因缺 `apps/document/node_modules` 失败（README 需一句前置）。
- 风险：主题默认自带 Inter 字体族与 `#3451b2` 品牌色，未换 `theme-without-fonts` 即违反设计基线与 AC10。

## 限制与已知边界

- 不覆盖：搜索服务端、版本化文档、英文站（PRD 非范围）；单站、单版本。
- 卡注入只取 frontmatter 之后的 body，卡版本号变化不产生页面 diff（AC3 判据以 body 为准）。
- 本决策不涉及内容分章与视觉规格（设计基线 `docs/designs/2026-11-13-portal-site.md` 为准）。

## 参考来源

- [vitepress（npm）](https://www.npmjs.com/package/vitepress) · 访问 2026-11-16 · latest=1.6.4、next=2.0.0-alpha.21，依赖 `vite ^5.4.14` / `vue ^3.5.13`。
- [VitePress Site Config](https://vitepress.dev/reference/site-config) · 访问 2026-11-16 · `base` 子路径口径：`https://foo.github.io/bar/` ⇒ `base: '/bar/'`，前后斜杠必需。
- [vitepress v1.6.4 theme-default/index.ts](https://github.com/vuejs/vitepress/blob/v1.6.4/src/client/theme-default/index.ts) · 访问 2026-11-16 · 主题入口首行引入 `styles/fonts.css`，另有 `without-fonts` 入口。
- [vitepress v1.6.4 theme-default/styles/vars.css](https://github.com/vuejs/vitepress/blob/v1.6.4/src/client/theme-default/styles/vars.css) · 访问 2026-11-16 · 默认品牌色 `#3451b2`、字体栈首项 `Inter`。
