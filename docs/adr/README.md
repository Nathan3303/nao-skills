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
| 2026-10-12 | [非 tmux 宿主的舰队派生（宿主阶梯 + 派生方式 + 句柄模型）](2026-10-12-non-tmux-host-spawn.md) | 非 tmux 宿主派生阶梯 | 已接受（待 RD 落地 v0.14.0） |
| 2026-10-13 | [舰队 pane 创建与布局的显式目标寻址（派生宿主窗口）](2026-10-13-derived-pane-window-addressing.md) | 派生 pane 显式目标寻址 | 已接受（T517 · 待 RD 落地） |
| 2026-10-13 | [cleanup 守卫：生产默认 socket 判定与 TMUX_TMPDIR 解耦](2026-10-13-close-anchor-cleanup-guard.md) | 默认 socket 判定与解耦 | 已接受（随 T516 / 0.16.0；随 PR #30 入库） |
| 2026-10-14 | [ADR 结构契约（骨架单源 / 状态值域 / 职责下沉）](2026-10-14-adr-structure-contract.md) | ADR 结构契约（骨架单源） | 已接受（待落地 v0.17.2） |
| 2026-10-14 | [npm test 门禁范围与严格性（t4 升格 + prepack 解耦）](2026-10-14-npm-test-gate-scope.md) | npm test 默认全量门禁 | 已接受（待落地 v0.18.0） |
| 2026-10-14 | [子代理会话（`subagent-*`）排除面与会话身份模型边界](2026-10-14-subagent-session-identity-exclusion.md) | 子代理不属舰队身份模型 | 已接受（待落地 v0.18.3） |
