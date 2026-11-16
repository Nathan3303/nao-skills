# T546 文档站交付 · 维护型动作台账（`136-followups`）

- 编号：`M20261116-docs-site` · 任务：T546（Issue #136）· 分支 `feat/136-docs-site`
- 触发：`.github/workflows/pages.yml` 改为构建后部署，需在本机复跑 `npm ci --prefix apps/document`（ADR D1 独立包安装）⇒ 带出 `npm audit` / `install-scripts` / Node 版本三处外部事实
- 边界：只登记这三条。站点代码与依赖选型归 `rd-fe`；机制口径（`e2_gate` 只认 `≥` / `低于` / 「截至」三形态）本批不改
- 环境：node `24.22.1` · npm `11.19.1` · `npm ci --prefix apps/document` rc=0（`added 135 packages`）

## 一、npm audit 3 项 ⇒ 接受（到期 2027-02-28）

证据（`npm audit --prefix apps/document --json`）：`total 3 = high 1 + moderate 2`，三项 `fixAvailable=false`。

- `vite`（high · transitive）——7 条 advisory（optimized deps path traversal / launch-editor 系 / custom middleware / `server.fs` 绕过），利用面是 dev server 与 Windows。
- `esbuild`（moderate · transitive，`<=0.24.2`）——dev server 可被任意站点跨域读取。
- `vitepress`（moderate · direct）——经 `vite` 传递，自身无独立 advisory。

判定：三条全部落在 devDependency 的 dev-server 面；站点零后端、零用户输入，CI 只 build、不对外暴露 dev server ⇒ 生产面无入口。成因是 vitepress 1.6.4 锁 `vite ^5.4.14`，上游当前无修复版本。

出口：**接受** · 到期 **2027-02-28** · owner `rd-infra` · 动作 = 下次 vitepress 升级后复跑 audit，上游修掉即关闭。提前回看触发：若某天需要对外暴露 dev server（`--host`），立即升级或限 `server.host`。

## 二、`install-scripts` 1 条（esbuild@0.21.5 postinstall）⇒ 接受不 approve

证据：`npm ci` 输出 `npm warn install-scripts 1 package has install scripts not yet covered by allowScripts: esbuild@0.21.5 (postinstall: node install.js)`；同轮 `npm --prefix apps/document run build -- --base /nao-skills/` **rc=0**（3.58s），`check:types` / `check:cards` / `check:links` 全 rc=0 ⇒ 平台包 `@esbuild/linux-x64` 自带二进制，postinstall 非必需。

出口：**接受不 approve**（不扩大脚本执行面） · 到期 **随下次 vitepress 升级回看** · owner `rd-infra`。

## 三、Node 版本偏差（`.nvmrc`/CI = 22.23.5 · 本机开发态 24.22.1）⇒ 接受（到期 2027-01-31）

证据：`apps/document/.nvmrc` = `22.23.5`（nodejs 官方 tag 实测存在）· workflow 用 `node-version-file` 同源读取 · 本机 `node v24.22.1`。ADR「限制与已知边界」与 arch R1 已登记同一事实。

出口：**接受** · 到期 **2027-01-31** · owner `rd-infra` · 动作 = 构建出现版本相关诊断时回看；CI 与开发态分叉不变更 NFR。

- 修订：2026-11-16 首版（T546 交付随附；PM 授权建本文件）
