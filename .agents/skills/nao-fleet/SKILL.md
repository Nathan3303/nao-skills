---
name: nao-fleet
description: nao 多角色 AI 开发舰队的单一入口。当用户要在当前项目启用/运行 nao 工作流时加载——按角色拉起 7 个常驻会话（pm / arch-designer / uiux-designer / rd-fe / rd-be / qa / rd-infra）、跑机制体检 check、迁移旧版安装。本 skill 只做入口与说明书：加载后按指引调用项目内 `.agents/scripts/nao-fleet.sh`（shim）；角色卡仍由 fleet 以 `--append-system-prompt` 常驻注入，不由 skill 承载。
---

# nao 舰队入口

## 何时加载

- 用户要在当前项目**启用 nao 工作流**（立项、拆任务、派活、验收、发版）。
- 用户要**拉起舰队**或查看会话状态。
- 用户要**迁移旧版 nao 安装**（项目内平铺 `.agents/` → 包内单一来源 + 项目 shim）。

## 三条核心命令

- **`ensure`（拉起）**：`bash .agents/scripts/nao-fleet.sh ensure pm arch-designer uiux-designer rd-fe rd-be qa rd-infra`（任务派生 `ensure --task <编号> <别名>`；task 只落元数据，名字仍是 `<role>[N]`）
- **`check`（体检）**：`bash .agents/scripts/nao-fleet.sh check`——exit=0 即可开工；非 0 看报告
- **`status`（状态）**：`bash .agents/scripts/nao-fleet.sh status`（任务会话回收 `close --task <编号> <别名>`，按元数据匹配）

硬约束：角色仍是 7 个独立会话；角色卡仍由 fleet `--append-system-prompt` 常驻注入，**不得**改为按需 skill 加载。完整用法见 `$NAO_SKILLS/docs/INSTALL.md`（前置环境 = herdr + pi 版本 · 布局 · `--card` 按需角色 · 迁移 · 离线 CI）。
