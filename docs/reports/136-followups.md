# T546 文档站交付 · 维护型动作台账（`136-followups`）

- 编号：`M20261116-docs-site` · 任务：T546（Issue #136）· 分支 `feat/136-docs-site`
- 触发：`.github/workflows/pages.yml` 改为构建后部署，需在本机复跑 `npm ci --prefix apps/document`（ADR D1 独立包安装）⇒ 带出 `npm audit` / `install-scripts` / Node 版本三处外部事实
- 边界：只登记这三条。站点代码与依赖选型归 `rd-fe`；机制口径（`e2_gate` 只认 `≥` / `低于` / 「截至」三形态）本批不改
- 环境：node `24.22.1` · npm `11.19.1` · `npm ci --prefix apps/document` rc=0（`added 135 packages`）

## 一、npm audit 3 项（`136-F1`）⇒ 接受（到期 2027-02-28）

证据（`npm audit --prefix apps/document --json`）：`total 3 = high 1 + moderate 2`，三项 `fixAvailable=false`。

- `vite`（high · transitive）——7 条 advisory（optimized deps path traversal / launch-editor 系 / custom middleware / `server.fs` 绕过），利用面是 dev server 与 Windows。
- `esbuild`（moderate · transitive，`<=0.24.2`）——dev server 可被任意站点跨域读取。
- `vitepress`（moderate · direct）——经 `vite` 传递，自身无独立 advisory。

判定：三条全部落在 devDependency 的 dev-server 面；站点零后端、零用户输入，CI 只 build、不对外暴露 dev server ⇒ 生产面无入口。成因是 vitepress 1.6.4 锁 `vite ^5.4.14`，上游当前无修复版本。

出口：**接受** · 到期 **2027-02-28** · owner `rd-infra` · 动作 = 下次 vitepress 升级后复跑 audit，上游修掉即关闭。提前回看触发：若某天需要对外暴露 dev server（`--host`），立即升级或限 `server.host`。

## 二、`install-scripts` 1 条（esbuild@0.21.5 postinstall · `136-F2`）⇒ 接受不 approve

证据：`npm ci` 输出 `npm warn install-scripts 1 package has install scripts not yet covered by allowScripts: esbuild@0.21.5 (postinstall: node install.js)`；同轮 `npm --prefix apps/document run build -- --base /nao-skills/` **rc=0**（3.58s），`check:types` / `check:cards` / `check:links` 全 rc=0 ⇒ 平台包 `@esbuild/linux-x64` 自带二进制，postinstall 非必需。

出口：**接受不 approve**（不扩大脚本执行面） · 到期 **随下次 vitepress 升级回看** · owner `rd-infra`。

## 三、Node 版本偏差（`.nvmrc`/CI = 22.23.5 · 本机开发态 24.22.1 · `136-F3`）⇒ 接受（到期 2027-01-31）

证据：`apps/document/.nvmrc` = `22.23.5`（nodejs 官方 tag 实测存在）· workflow 用 `node-version-file` 同源读取 · 本机 `node v24.22.1`。ADR「限制与已知边界」与 arch R1 已登记同一事实。

出口：**接受** · 到期 **2027-01-31** · owner `rd-infra` · 动作 = 构建出现版本相关诊断时回看；CI 与开发态分叉不变更 NFR。

- 修订：2026-11-16 首版（T546 交付随附；PM 授权建本文件）

## 四、pages actions 版本未 bump（`136-F4`）⇒ 接受（到期 2027-02-28）

证据：`configure-pages` 当前 latest = **v6**（workflow 用 v5）· `upload-pages-artifact` 当前 latest = **v5**（workflow 用 v4，`path` 输入口径已核 `action.yml`）；`checkout@v5` / `deploy-pages@v5` 已是 latest major。本批 workflow 已在改部署链（新增 PR 触发 + 主干 gate），同批再叠版本变量会让首跑归因变难 ⇒ PM 2026-11-16 裁定不夹带。

出口：**接受** · 到期 **2027-02-28** · owner `rd-infra` · 动作 = 下次动该 workflow 时一并升，同一 PR 内复跑结构断言与首跑观察。

## 五、主题英文无障碍文案残留（`136-F5`）⇒ 接受（到期 2027-02-28）

证据（QA `docs/reports/136-qa-verify.md` §四 D6）：产物 HTML 残留默认主题的英文 `aria-label`（`extra navigation` / `mobile navigation` · `Permalink to …`）；VitePress 1.6.4 多数不可配（无暴露 i18n 入口），属上流。

判定：不影响可用性与对比度（屏幕阅读器仍能正确朗读，只是语言混用）；自建替换需 patch 主题内部模板，成本 > 收益。

出口：**接受** · 到期 **2027-02-28** · owner `rd-fe` · 动作 = 随下次 vitepress 升级回看是否已可配；否则若用户反馈，再评估 patch。

## 六、`<title>` 顺序与现代约定不同（`136-F6`）⇒ 接受（到期 2027-02-28）

证据（QA §四 D7）：旧站标题为 `nao-skills · <副标>`（站名在前），现站为 `<页标题> · nao-skills`（`titleTemplate` 造成）。内容不变，仅顺序。

判定：页面标题在前是现代搜索引擎/标签页习惯（且深层页需要页名区分），改回旧序需刻意反转 `titleTemplate`，会让全部 21 页标题都变成「站名打头」，反而降低多标签场景的区分度。

出口：**接受** · 到期 **2027-02-28** · owner `rd-fe` · 动作 = 如果用户走查时明确要求旧序，用一行 `titleTemplate` 切回并重跑门禁。

- 修订：2026-11-17 补登 136-F5 / 136-F6（QA D6 / D7 接受项；D1–D5 已在批内修复，不入遗留）

## 七、og 与角色页分区的修复无自动断言护栏（`136-F7`）⇒ 接受（到期 2027-02-28）

证据（QA §六 N1）：D3 的 4 条 og 与 D5 的 `role-guide-label` 目前只靠人工验 —— 将来被改动静默弄丢时 CI 不会红（`check:cards` 只看卡原文区、`check:links` 只看资源属性、`check:plugins` 只看插件包名）。

判定：本批不加断言 —— 合并前再加一道新检查会引发新一轮「新检查自身是否可靠」的复核，收益（SEO / 读屏分区丢失）低于代价；风险等级 P3。

出口：**接受** · 到期 **2027-02-28** · owner `rd-fe` · 动作 = 并入现有 `check-links`/`check-cards` 或新增 `check:meta`（判据：`dist/index.html` 恰 4 条 og 且与基线文案相等；7 个角色页各含两个 `aria-labelledby`），加断言时须自测负控必红。**已进「待派发队列」作为小批次候选。**

- 修订：2026-11-17 补登 136-F5 / 136-F6 / 136-F7，并给前三条补齐 `136-F1`–`F3` 编号（QA §六 N2）
