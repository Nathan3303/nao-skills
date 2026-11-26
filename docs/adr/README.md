# ADR 索引（架构决策记录）

> 约定见 `.agents/prompts/architecture-designer.md` §十一：落盘 `docs/adr/YYYY-MM-DD-<简短主题>.md`（日期取评审终签日）；
> 每篇必含 `参考来源`（链接 + 访问日期）与 `对照过的备选模式`（含不采纳理由）。
> 本文件是**索引**，不是条款出处；机制条款以 `.agents/` 为准（单一事实来源）。
> 决策列只放 ≤20 字短结论，细节留在各 ADR 正文（骨架见 `.agents/templates/adr-index.md.example`）。

| 日期 | 主题 | 决策 | 状态 |
| :--- | :--- | :--- | :--- |
| 2026-09-25 | [新增 `rd-infra`（工程基座）角色](2026-09-25-new-rd-infra-role.md) | 新增专精角色 rd-infra | 已接受（已落地 v0.9.0） |
| 2026-09-25 | [舰队 tmux 布局：新增 `main-col` 与窄列守卫](2026-09-25-tmux-fleet-layout-modes.md) | 布局新增 main-col 模式 | 已接受（已落地 v0.9.0） |
| 2026-10-08 | [单 SKILL 化 + pi 原生分发](2026-10-08-nao-skills-single-skill-pi-package.md) | 单 SKILL 化 + 原生分发 | 已接受 |
| 2026-10-08 | [migrate 收尾：迁移标记、shim 判定式与 lock 去重](2026-10-08-migrate-shim-and-marker.md) | 迁移收尾与 shim 判定式 | 已接受（已落地 v0.13.0 · T510） |
| 2026-10-12 | [非 tmux 宿主的舰队派生（宿主阶梯 + 派生方式 + 句柄模型）](2026-10-12-non-tmux-host-spawn.md) | 非 tmux 宿主派生阶梯 | 已废弃（被 2026-10-27-strict-tmux-pi 取代） |
| 2026-10-13 | [舰队 pane 创建与布局的显式目标寻址（派生宿主窗口）](2026-10-13-derived-pane-window-addressing.md) | 派生 pane 显式目标寻址 | 已接受（已落地 v0.16.2 · T517） |
| 2026-10-13 | [cleanup 守卫：生产默认 socket 判定与 TMUX_TMPDIR 解耦](2026-10-13-close-anchor-cleanup-guard.md) | 默认 socket 判定与解耦 | 已接受（随 T516 / 0.16.0；随 PR #30 入库） |
| 2026-10-14 | [ADR 结构契约（骨架单源 / 状态值域 / 职责下沉）](2026-10-14-adr-structure-contract.md) | ADR 结构契约（骨架单源） | 已接受（已落地 v0.17.2） |
| 2026-10-14 | [npm test 门禁范围与严格性（t4 升格 + prepack 解耦）](2026-10-14-npm-test-gate-scope.md) | npm test 默认全量门禁 | 已接受（已落地 v0.18.0） |
| 2026-10-14 | [子代理会话（`subagent-*`）排除面与会话身份模型边界](2026-10-14-subagent-session-identity-exclusion.md) | 子代理不属舰队身份模型 | 已接受（已落地 v0.18.3） |
| 2026-10-14 | [角色→子代理 agent 的单一事实（运行时注册扩展）](2026-10-14-role-agents-runtime-registration.md) | 运行时注册单一事实 | 已接受（已落地 v0.18.5） |
| 2026-10-27 | [舰队绑死 tmux + pi ≥1.4.0（删净宿主阶梯）](2026-10-27-strict-tmux-pi.md) | 绑死 tmux + pi 前提 | 已废弃（被 2026-11-22-herdr-only 取代；pi 前提仍现行） |
| 2026-10-28 | [引入 codegraph 插件为可选增强（warn-only + rc 收敛）](2026-10-28-codegraph-plugin-adoption.md) | 插件仅增强，不进 rc | 已接受（已落地 v0.20.0） |
| 2026-10-31 | [status 残留判定加仓维度（按 pane 工作目录）](2026-10-31-fleet-status-repo-attribution.md) | 残留判定按 pane cwd 归属 | 已接受（已落地 v0.20.2） |
| 2026-11-01 | [下游仓自定义角色会话（`ensure --card`）](2026-11-01-downstream-card-sessions.md) | 卡参数线 + 前缀不相交 | 已接受（已落地 v0.21.0） |
| 2026-11-13 | [herdr workspace 放置键与 scope 分离](2026-11-13-herdr-workspace-scope-key.md) | 未声明 scope 时放置键取仓 slug | 已废弃（被 2026-11-20-workspace-as-binding-unit 取代） |
| 2026-11-16 | [文档站构建与交付管线（独立包 + 编译期注入 + 构建后部署）](2026-11-16-docs-site-pipeline.md) | 独立包 + 编译期注入 + 构建 | 已接受（待落地） |
| 2026-11-17 | [舰队身份单一来源（`--fleet` 同时定名字 scope 与放置键）](2026-11-17-fleet-identity-source.md) | fleet 单源，名字恒带 @ | 已废弃（被 2026-11-20-workspace-as-binding-unit 取代） |
| 2026-11-19 | [联动仓 manifest（1 fleet = 1 workspace · tab 前缀分组）](2026-11-19-fleet-repo-manifest.md) | 放置键与身份键不同源 | 已废弃（被 2026-11-20-workspace-as-binding-unit 取代） |
| 2026-11-20 | [workspace 为绑定单位（取消 fleet · 名字不含位置）](2026-11-20-workspace-as-binding-unit.md) | 放置键 = 仓，名字去 @ | 已接受（待落地） |
| 2026-11-22 | [herdr 唯一后端（删除 tmux 回退面）](2026-11-22-herdr-only.md) | 唯一后端 = herdr，旧面 fail loud | 已落地（v0.28.0） |
| 2026-11-24 | [herdr desktop app 作为第二后端](2026-11-24-herdr-app-backend.md) | 双后端并存，放置读 doc 验证 | 已落地 v0.30.0 |
| 2026-11-24 | [设计技能的职责分层（新建 vs 重构）](2026-11-24-design-skill-layering.md) | 新建与重构分读两只技能 | 已接受（待落地） |
| 2026-11-24 | [编排器阶段 2 落点 + `nao-fleet.sh` 拆分边界](2026-11-24-orch-stage2-and-script-split.md) | orch 独立 Node + 一次性 tick；按层拆 12 模块 | **部分作废**：orch 部分 superseded（编排器 2026-11-26 下线）· 模块拆分仍生效 |
