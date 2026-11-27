# T587 首页 banner 位（舰队录屏）设计规格

- 状态：待 PM / 用户确认 · 更新：2026-11-27 · Owner：uiux-designer
- 指针：PM 派单（2026-11-27，三条裁定）· 视觉基准 `docs/designs/2026-11-16-docs-site.md` §三–§六 · 实现面 `apps/document/components/home/`
- 素材：1896×1030 · 15.47s · 60fps · 无音轨（初转 1280×696 / CRF20 / 698KB）
- 交付档位：**① 结构化文字规格**（本单无画板需求，不出图，理由见 §九）
- 屏幕角色句：这屏在访客读完 Hero 定位之后，用 15 秒真实会话让他看到「七个角色同时干活」是什么样；产品定位与安装命令不在这里，它们在 Hero 与「三步装好」。

## 一、信息架构

- 顺序：Hero → **banner** → JumpNav → 五个内容段 → 页脚。banner 是 Hero 的「证据条」，不是新章节。
- 层级 2：`<section id="preview">` → `<figure>` + `<figcaption>`；**无 h2 / 无 kicker / 无 lead**，屏上文字只有 caption 一行。
- 跳读条 5 → 6 项，首项「舰队实录 → `#preview`」（页序即首项）；锚点仅此 1 个，section 需 `scroll-margin-top: 84px`（同 `.section`）。
- 判据回答：读者**需要**一句话区分「Hero 的终端是示意、这段是真实会话」⇒ 给 caption；但**不需要**第二组标题+副标⇒ 不给 title/lead。

## 二、流程

1. 落页 → Hero 读定位 → 下滚 32px 见视频卡（自动无声循环）→ 需要时点右下暂停。
2. 减少动效：默认不自动播，见 §八。
3. 异常 · 资源 404 / 不支持 h264：卡内 fallback 文案 + 「下载这段录屏」链接（底色 `--nh-sunken`，不留黑框）；加载中 poster 先出，无 spinner / 骨架。
4. 空 / 错误 / 无权限：不适用：静态媒体，无数据请求、无用户态。

## 三、视觉规范

- 版心：套在 `.wrap` 内（1128 / 内容 1080），视频卡宽 100%，不破栏。
- 间距：section 上 `--nh-sp-8`（32）下 `--nh-sp-8`（32）；≤720 上下 `--nh-sp-6`（24）。caption 距卡 `--nh-sp-3`（12）。
- 卡：`1px solid var(--nh-border)` + `border-radius: var(--nh-r-14)` + `background: var(--nh-sunken)` + `overflow: hidden`；**内边距 0**（视频满宽，不嵌边）。
- 比例：`aspect-ratio: 1896 / 1030`（=1.841），`video{display:block;width:100%;height:100%;object-fit:cover}`。不套 16:9 —— 套则必裁切或加黑边，违反「不裁不改」。
- **不用 `--nh-shadow-1`**：该档只服务可交互卡片 hover；静态媒体卡用描边分层，暗色亦不加投影。
- caption：`--nh-fs-13` / `--nh-text-3`，单行（≤720 允许 2 行）；不设 h2。
- 形态红线：无渐变 / 无玻璃 / 无发光 / 无大圆角 / 不加播放图标遮罩层；圆角 ≤14。

## 四、token

- 复用（新增 0 个颜色 / 字阶 / 间距 / 圆角）：`--nh-page` `--nh-sunken` `--nh-border` `--nh-text` `--nh-text-3` `--nh-accent` `--nh-fs-13` `--nh-sp-3` `--nh-sp-6` `--nh-sp-8` `--nh-r-12` `--nh-r-14` `--nh-r-pill`。
- 唯一新数值 = 比例 `1896 / 1030`（素材固有比，不是设计刻度）。
- 播放/暂停按钮：44×44，底 `--nh-page` + 1px `--nh-border`，`--nh-r-pill`，图标 16px `--nh-text`；focus 2px `--nh-accent` + 2px offset。

## 五、状态

- 播放中（默认）/ 用户暂停：同一按钮切图标（▶ / ❚❚）与 `aria-label`，不单靠颜色变化。
- 结束态：不适用：`loop` 循环，无结束画面。
- 资源不可用：fallback 文案 + 下载链接，卡仍占位（`--nh-sunken`），不塌陷。

## 六、断点

- ≥1080：1080 版心，圆角 14，高 ≈587。
- 720–1079：同版心随宽度缩，圆角 14。
- <720：左右 24（卡宽 312–672），圆角收 `--nh-r-12`，上下留白 24，caption 允许 2 行。
- 首屏（360×640）：Hero 已占满，banner 不承诺进首屏，**不压缩 Hero**；320 以下同窄档，`min-width: 0`。
- 极值：≥1080 锁 1080 宽不放大（高 ≈587）；360 卡宽 312 → 高 ≈170，正文不缩。

## 七、可用性

- 点击数：看 0（自动播）· 暂停 1 · 降级下载 1；主任务（读定位 → 点 CTA）不被 banner 增加点击。
- 反馈 ≤100ms（图标即时变），无 >400ms 过渡；不自动全屏、不弹层、不出声。性能：视频 ≤700KB、`preload="metadata"`、poster ≤60KB；`Save-Data` 或 `prefers-reduced-motion` 都落静态态（§八）。

## 八、无障碍

- 裁定：`prefers-reduced-motion: reduce` ⇒ **不自动播放，显示 poster + 播放按钮**（点播后仍可暂停）。
- 理由：WCAG 2.2.2 要求 >5s 自动动效可暂停；「只给海报 + 下载链接」等于对这类用户关闭内容，且把「看 15 秒」变成「下载文件」，成本更高。给按钮保留选择权。
- 普通模式同样常驻暂停按钮（触屏无 hover，不能只在 hover 出现），满足 2.2.2。
- 语义：`<figure>` + `<figcaption>`（caption 即说明）；`video` 收 `aria-label`；按钮 `aria-label="暂停录屏"` / `"播放录屏"`；无音轨 ⇒ 不需字幕与音量，**不用** `controls`（原生控件命中区与视觉不可控）。
- 键盘：Tab 顺序 Hero CTA → 播放按钮 → 跳读条；focus-visible 2px `--nh-accent`；命中区 44×44。对比度：caption `--nh-text-3` 在 `--nh-page` 上亮 5.9:1 / 暗 ≈5.1:1（≥4.5:1）。

## 九、降级产物

- 档位 ①（无画板需求，不出图）：banner 不引入新视觉语言（现有卡 + 现有 token），画板只会复述 §三 数值；效果验收走实现真机截图（QA 口径），不另出稿。
- 素材与命名（建议，rd-fe 可改但需在报告写明）：`content/public/nao-fleet-demo.mp4`（≤700KB / faststart）· `nao-fleet-demo-poster.jpg`（机械取 t≈0.5s，≤60KB）；路径一律 `withBase()`，禁写死 `/`。
- 文案（frontmatter `home.banner`，仅 3 键）：`caption`「真实舰队会话 · 7 个角色各占一屏并行干活（15 秒，无声）」· `alt`「七个 AI 角色在同一次舰队会话中同时处理各自子任务」· `fallback`「你的浏览器不能播放这段录屏。」；`types.ts` 增 `HomeBanner { caption; alt; fallback }`，**不增** kicker / title / lead。
- 与昨日撤除案（`79b2f23` → `b121775`）的差别：本次无标题说明段、无大投影、无 24s 大块，15s 直贴 Hero 之下 —— 规模与位置都更克制。

## AC 逐条结论

- A1 纯媒体位（非第 7 段）：**PASS** —— 1 行 caption + 1 锚点，无标题层。
- A2 容器规格：**PASS** —— `--nh-r-14` / 无阴影 / `.wrap` 内 / 窄屏 `--nh-r-12` 可接受 / 上下 `--nh-sp-8`（窄 `--nh-sp-6`）/ 卡内 0。
- A3 `prefers-reduced-motion`：**PASS** —— 静态 poster + 播放按钮（含可见 hover/focus）。
- A4 不改素材内容：**PASS** —— 原比例渲染，不挑帧、不裁切、不加字幕，poster 仅机械取帧。
- A5 单一源与路径：**PASS** —— 3 键 frontmatter + `withBase()`；文案不进组件。
- 自评：**PASS**（可交 rd-fe 写码；若 PM 已另有 PRD 编号，替换本节 A1–A5 为对应 AC 即可）。
