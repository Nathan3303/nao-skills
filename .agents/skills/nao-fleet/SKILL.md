---
name: nao-fleet
description: nao 多角色 AI 开发舰队的单一入口。当用户要在当前项目启用/运行 nao 工作流时加载——按角色拉起 6 个常驻会话（pm / arch-designer / rd-fe / rd-be / qa / rd-infra）、跑机制体检 check、迁移旧版安装。本 skill 只做入口与说明书：加载后按指引调用项目内 `.agents/scripts/nao-fleet.sh`（shim）；角色卡仍由 fleet 以 `--append-system-prompt` 常驻注入，不由 skill 承载。
---

# nao 舰队入口

nao 是一套「多角色 AI 开发舰队」：6 个分工明确的常驻会话（PM 拆需求/派活/验收，前端、后端、测试、架构、工程基座各自干活），用户只回答问题、点确认。

## 何时加载

- 用户要在当前项目**启用 nao 工作流**（立项、拆任务、派活、验收、发版）。
- 用户要**拉起舰队**或查看会话状态。
- 用户要**迁移旧版 nao 安装**（项目内平铺 `.agents/` → 包内单一来源 + 项目 shim）。

## 机制在哪（单一事实来源）

机制全部在 **nao 机制包内**，项目内只有 shim。包根由环境锚点 `$NAO_SKILLS` 给出（fleet 注入到会话系统提示）：

- 角色清单：`$NAO_SKILLS/.agents/roles.yaml`（6 角色，id 即 intercom 会话名）
- 角色卡：`$NAO_SKILLS/.agents/prompts/<card>.md`
- 按需技能：`$NAO_SKILLS/.agents/skills/*.md`
- 交付清单：`$NAO_SKILLS/.agents/checklists/<role>.md`
- 协作协议 / 输出规范：`$NAO_SKILLS/.agents/common/`

> 若 `$NAO_SKILLS` 未设置（普通会话），按本 SKILL.md 所在包解析（本文件位于 `<包根>/.agents/skills/nao-fleet/SKILL.md`，包根 = 本文件上两级）。

## 怎么用

1. **体检**：`bash .agents/scripts/nao-fleet.sh check`（exit=0 即可开工；非 0 看报告）。
2. **拉起舰队**：`bash .agents/scripts/nao-fleet.sh ensure pm arch-designer rd-fe rd-be qa rd-infra`
   - 任务派生（并行隔离）：`ensure --task <编号> <别名>`
   - 状态 / 回收：`status` / `close --task <编号> <别名>`
3. **迁移旧版安装**：`npx @nathan33/nao-skill migrate`（旧文件备份到 `.agents/.nao-obsolete/`）。是否写 shim 由**判定式**决定（旧脚本 / 已有 shim / 全仓 `nao-fleet|nao-skill|NAO_SKILLS` 引用 ⇒ 写）；纯文档仓判定为跳过并显式告知，可用 `--shim` / `--no-shim` 覆盖。

## 硬约束（勿违反）

- **BR1**：角色仍是 6 个独立会话；本 skill 不合并角色。
- **BR2**：角色卡必须继续由 fleet `--append-system-prompt` 常驻注入；**不得**改用 skill / prompt 按需加载。
- 项目根 `AGENTS.md` 是项目级单一事实来源（PM 维护，pi 自动注入），本 skill 不复制其内容。
- 机制自身零网络；shim 只用 node resolve 定位包，不调用 `pi`/`npm` 可执行文件。
