# ADR 索引（架构决策记录）

> 约定见 `.agents/prompts/architecture-designer.md` §十一：落盘 `docs/adr/YYYY-MM-DD-<简短主题>.md`（日期取评审终签日）；
> 每篇必含 `参考来源`（链接 + 访问日期）与 `对照过的备选模式`（含不采纳理由）。
> 本文件是**索引**，不是条款出处；机制条款以 `.agents/` 为准（单一事实来源）。

| 日期 | 主题 | 决策 | 状态 |
| :--- | :--- | :--- | :--- |
| 2026-09-25 | [新增 `rd-infra`（工程基座）角色](2026-09-25-new-rd-infra-role.md) | 新增专精角色 `rd-infra`（别名 `infra`），不新增通用开发角色；口诀「改业务行为 ⇒ rd-fe/rd-be；改怎么构建/验/发/治理 ⇒ rd-infra」 | 提议（待 RD 落地） |
| 2026-09-25 | [舰队 tmux 布局：新增 `main-col` 与窄列守卫](2026-09-25-tmux-fleet-layout-modes.md) | 新增 `NAO_TMUX_LAYOUT=main-col`（委托内建 `main-vertical`）；`main-row2` 加最小列宽守卫与 `main-col → grid` 回退阶梯 | 提议（待 RD 落地） |
