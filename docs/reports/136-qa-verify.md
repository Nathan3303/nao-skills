# T546 文档站（门户 → VitePress）QA 全量验收 · Issue #136

- 状态：**有缺陷待判（P2×3 · P3×5；无 P0/P1）** · 日期：2026-11-16 · Owner：qa
- 被测：`feat/136-docs-site` @ `945b0c3`（= PM 指的 `2542d18` + 1 条台账提交，差异仅 `docs/tasks-state.md`）· PR #137
- 环境：**新建干净 worktree** `/tmp/t546-qa`（`git worktree add`，零本地产物）· node `v24.22.1` / npm `11.19.1`（与 `.nvmrc` 22.23.5 分叉，台账已接受）
- 判据：PRD AC1–AC11 · 设计规格 §一/§四/§六/§八 · ADR D1/D3/D4/D6 · 旧门户 `git show 2b9f9fb:site/index.html`
- 边界：未改实现、未改正文、未改 workflow；下列缺陷只报不修

## 一、门禁数字（我方独立执行）

- `npm ci --prefix apps/document` → rc=0（added 135 packages · 3 vulns=1 high+2 moderate · 1 install-script warn，与台账三/四项逐条一致）
- `npm --prefix apps/document run check:types` → rc=0（无输出）
- `npm --prefix apps/document run build -- --base /nao-skills/` → rc=0（3.69s）· `dist/index.html` 存在 · 22 个 html（21 页 + 404）
- `npm --prefix apps/document run check:cards` → rc=0（`✓ AC3 通过：7 个角色页正文与 .agents/prompts 逐段一致`）
- `npm --prefix apps/document run check:links` → rc=0（`扫描 70 个文件（html 22）· 校验 151 个资源属性 · 外链 0 处`）
- `bash .agents/scripts/nao-fleet.sh check` → rc=0（roles=7 · files=54 · layout=main-row2）
- `npm test`（根 · 全范围）→ rc=0（10m26s · 34 用例 · SKIP=0 DEGRADE=0 NOTE=11 全白名单）
- `npm pack --dry-run` → rc=0 · **59 files** · `apps/` 命中 **0** · `site/` 命中 0 · 219074 B（unpacked 572940 B）
- 干净性：跑前 / 跑后 `git status --porcelain` 均 **0 行**

## 二、AC 结论

- **AC1 PASS**：冷装 → 类型 → 构建全 rc=0，产物路径存在。
- **AC2 FAIL（D1/D3）**：六段齐备；归一化文本逐行 diff 出 6 处差异 = 3 处设计 §一 已允许（顶栏 4 锚点降为跳读条 · Hero 加「快速开始」· 七角色卡可点进角色页）+ 3 处问题（页脚前文见 D1/D3/D7）。
- **AC3 PASS**：我自写脚本（非 `check-cards.mjs` 归一化逻辑）抽 `roles/pm`（卡 `product-manager.md` 139 行）与 `roles/rd-infra`（`infra-engineer.md` 61 行）逐段比：非代码/非表格段 **28/28**、**13/13** 全命中；`apps/document` 内无卡正文手抄副本（`不自验自己的守卫` 等卡内独有串 0 命中）；徽标版本实读 frontmatter（v38 / v6）。
- **AC4 FAIL（D2）**：插件页 5 个齐备，包名与 `bin/nao-skill.js:96 PI_PLUGINS` 逐字一致（`pi-ask-me` / `@sean_pedersen/pi-codegraph` 等各 1 命中），每个含「缺了失去什么」；但 PRD 要求的「脚本比对断言」**仓库内不存在**（`grep PI_PLUGINS` 仅命中 bin 与 t4 用例 18 的 codegraph 单点，无 docs 侧断言）⇒ 人工一致，漂移不会被 CI 抓。
- **AC5 PASS**：临时 `mv .agents/prompts`（非删除）→ 默认 rc=0 且 stderr **恰 1 条**告警（`⚠ 跳过角色卡注入…`）+ 7 个角色页均出现「卡原文见仓库」；`--strict` → rc=1（`✗ --strict：未找到 .agents/prompts…`）。还原后 `git status` 空、7 张卡齐。
- **AC6 待用户回填**（清单 `136-user-acceptance.md`）；静态侧 §六 6 项显式覆盖齐（抽屉遮罩 · LocalNav≥44 · TOC<1280 隐 · <720 padding 24 · 顶栏 56 · 代码/表格横滚），`overflow-x:hidden` 0 处。
- **AC7 PASS**：三种假外链各自必红 —— `<img src=https>` rc=1 / CSS `url(https)` rc=1 / `<script src=cdn.jsdelivr>` rc=1；正控 `<a href=https>外部文档</a>` 仍 rc=0；守卫删 `dist/index.html` rc=1。
- **AC8 PASS**：`git ls-files site` = 0；非 `docs/` 路径 `site/` 引用 0 处（`docs/` 内仅历史记录，不计）；workflow 只 `path: apps/document/.vitepress/dist` 上传，PR 事件不上传、deploy 只在主干/dispatch。
- **AC9 PASS**：见 §一 pack / test / check 三行；发布面结构性不变。
- **AC10 静态 PASS · 视觉待回填**：`theme-without-fonts` 生效；dist CSS `3451b2`/`a8b1ff`/`Inter` 各 **0 次**；`--vp-c-brand-1: var(--nh-accent)` 位于默认声明之后（偏移 105314 > 2278，覆盖生效）；token 与基线 §四 逐项同值；9 处清零点 **8 处落地**（搜索框不存在 = PRD 非范围，见观察 1）；对比度实算 亮 17.7/7.7/6.7、暗 16.3/9.1/9.3 : 1，全部 ≥AAA。
- **AC11 FAIL（D4）**：术语表 6 词全覆盖、门禁与闸门**分列**且有「门禁 ≠ 闸门」一条；但按阅读序首现，**PRD / 回执 / 门禁** 三词首现于首页营销卡（`index.md` 02/03/qa 卡）无半句解释，解释在 `how/task-journey.md:26` / `quickstart/fleet.md:40` / `how/acceptance.md:21`。AC / 闸门 / RICE 合规。

## 三、变异负控（我自己造的失败，非 RD 自证）

- AC3 破坏：改 `dist/roles/pm.html` 卡原文区「前置澄清义务」→ `check-cards` rc=1 并点名该段；还原 rc=0。（改解说区同名串**不**报红 —— 判据只看原文区，符合 AC3 口径，非缺陷）
- AC7 负控 3 类 + 正控 1 类 + 守卫 1 类：结果见 AC7 行，全部按预期红/绿。
- AC5 负控：缺卡源两种模式（rc=0 恰 1 告警 / rc=1）实测。
- 遗留复核：台账 4 条（audit 3 项 · install-script 1 条 · Node 分叉 · pages actions 版本）我逐条复跑证据，均成立；**漏登候选 3 条**见 §五。

## 四、缺陷（只报不修）

- **D1 · P2 · AC2**：首页「三步装好」第 02 步正文渲染出**字面反引号**「pin 写进 \`.pi/settings.json\` 进仓库」（旧站是 `<code>` 等宽样式）。根因已定位到行级：`components/home/inline.ts` 有现成的 `inlineHtml()`（`` `x` `` → `<code>`），但 `HomeSteps.vue` 用 `{{ step.body }}` 纯文本插值、未走该函数；全仓只有 `HomeFaq.vue` 用了 `inlineHtml`。一行改动（`v-html="inlineHtml(step.body)"`）即可，内容侧无需动。
- **D2 · P2 · AC4**：插件页与 `PI_PLUGINS` 的一致性没有脚本断言（PRD AC4 明写），CI 不会因包名漂移变红。建议补一条 `check-plugins.mjs` 或并入 `check-cards` 同风格脚本。
- **D3 · P2 · 基线 §八**：首页 `og:title` / `og:description` 丢失（旧站有 `og:type`/`og:locale`/`og:title`/`og:description` 四条），基线 §八 SEO 条目明确要求 og 两项；`description` 已保留。
- **D4 · P3 · AC11**：PRD / 回执 / 门禁三词首现于首页无半句解释（见 AC11）。
- **D5 · P3 · 设计 §八**：角色页只有原文区是 `<section aria-labelledby>`，**解说区没有独立 `<section>`**，与「两区各自命名」不符（其余无障碍项齐：h1 唯一 / main / footer / 跳过链接 / 终端 `aria-hidden` / 复制 `aria-live` / `<details>` 默认收起）。
- **D6 · P3 · 设计 §八**：默认主题英文无障碍文案残留 —— nav `aria-label="extra navigation"`、`"mobile navigation"`、标题锚点 `"Permalink to …"`（zh-CN 站点交给读屏器的是英文）。
- **D7 · P3 · AC2**：`<title>` 顺序与旧站相反（旧 `nao-skills · 给你的 pi…`，新 `给你的 pi… · nao-skills`，由 `titleTemplate` 造成）。
- **D8 · P3 · 健壮性**：`--strict` 构建失败**不清理旧 `dist/`**，随后 `check:cards` / `check:links` 会检验上一轮产物（本地误判风险；CI 因为上传步骤在 build 之后，无线上影响）。

## 五、风险与漏登候选

- 漏登候选（建议入 `136-followups.md`，三出口由 PM 定）：① D2 的「AC4 无脚本断言」；② D6 的英文 aria 残留（VitePress 1.6.4 多数不可配，属上游）；③ D8 的失败构建旧产物。
- 残余风险：Node 24 与 CI 22 分叉 ⇒ 产物不可复算（已接受至 2027-01-31）；卡片内容改动只经 `paths` 触发构建，若将来卡源换目录须同步 filter。
- 观察 1：9 处清零点中「搜索框」在本批不存在（PRD 非范围 + 设计遗留④），按 N/A 记，不算残留。
- 观察 2：对比度实测值与基线标注（16.4/8.0/6.3）有 ±0.4 差，属测量口径/取整差异，均 ≥AAA，不构成缺陷。

## 六、建议

- 合并前修 D1/D2/D3（P2，均小改动）；D4/D5/D6/D7 由 PM 二选一：本批判定修 or 转办 + 台账到期；D8 建议至少补一句「失败后重跑 build」提示。
- 我方可交付的用户侧验收清单：`docs/reports/136-user-acceptance.md`（AC6/AC10/AC11 人工部分，不含自动化断言）。
- 结论：**有条件通过** —— P2 三条修完并复跑 `docs:build` + `check:cards` + `check:links` 后，我方可出 `done` 复核。

- 修订：2026-11-16 首版（T546 全量验收；干净 worktree 实测 + 5 类变异负控）
