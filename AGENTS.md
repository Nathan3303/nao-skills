# AGENTS.md — nao-skills（nao 机制包根）

> 本仓即 nao 机制包本身：`$NAO_SKILLS` 指向这里；项目安装侧只有 shim。维护人：PM。
> 角色级/团队级内容在 `.agents/`（roles.yaml / common / checklists），本文件只写「项目级属性 + 约束」。

## 项目属性

- **仓库结构**：`.agents/`（机制单一事实：prompts 角色卡 · checklists 清单 · skills 技能 · common 协议 · roles.yaml）· `bin/`（CLI 与 shim）· `docs/`（prds/adr/reports/research/releases）· `tests/`（回归用例）
- **技术栈**：shell（`.agents/scripts/nao-fleet.sh`）+ Node/TypeScript（`bin/` CLI、`nao-skill` npm 包）；本身零网络。
- **命令**：
  - 机制体检：`bash .agents/scripts/nao-fleet.sh check`（rc=0 才可开工）
  - 测试：`npm test`（tests/ 全范围）
  - 代码定位：**本仓无 CodeGraph 索引**（实测 `codegraph status` → Not initialized）→ 直接 `grep -rn` + `sed` 行段读取，**禁 cat 全文**（可选 `codegraph init` 自建索引，非必需）
- **环境**：`NAO_SKILLS` 必须指向本仓根（凡是引用 `.agents/...` 的绝对路径锚点）；跨仓工作用 `"$NAO_SKILLS/.agents/scripts/nao-fleet.sh"` 显式调用。

## 项目约束（红线）

- **全范围门禁口径（本项目）**：`bash .agents/scripts/nao-fleet.sh check` rc=0 + `npm test` rc=0（tests/ 全目录，非子目录）；改任何机制文件/角色卡后必跑 `check`。
- **零敏感值**：仓库内禁 token/私钥/绝对家目录路径；grep 复核是 rd-infra 红线的硬门禁。
- **幂等**：脚本/迁移/安装器连跑 2 次 effect = 0 且 rc = 0；守卫改动带失败演练。
- **维护型闭环口径**：外部命令 / 依赖 / 环境类动作 = 维护型任务（`M<YYYYMMDD>-<slug>`），**`exit 0` 不算完成** —— `audit` / `install-scripts` / 每条 `warn`/`error`/`pending approval` 逐条归口，遗留项走三出口（关闭 / 接受含到期 / 转办），台账落 `docs/reports/<编号>-followups.md`（协议 `.agents/skills/task-completion.md`；首个实例 `M20261014-pi-ext-update`）。
- **角色卡版本纪律**：改 `.agents/prompts/<card>.md` 必须 bump `version` + 更新 `updated`（version 是唯一事实，roles.yaml 不重复维护），并经 intercom 广播 `card <role> v<N+1>` 摘要。
- **Git 流程（GitHub Flow）**：一个需求一条分支 `feat/<issue-id>-<slug>`（机制维护批次用降级 `nao/<批次-slug>`）；工作期 `wip(<编号>):` 小步提交 + 路径级暂存（禁 `git add -A`）；**PM 验收通过后由 RD 在 PR 上 squash 合并**（main = 1 条/需求）；**禁直推 main、禁 PM 亲自合并**。
- **发布与仓库治理**：PM 负责 Issue / PR 验收评论 / tag / release / `.github/` 模板（优先 `gh`，不可用降级 `git`）；**发版说明写法遵循 `.agents/common/release-notes.md`**（面向用户「本次更新」置顶、内部信息下沉、正文不用表格）；已 push 的 tag 不删（改发下一个 PATCH，用户明确要求才删）。
- **npm 发布成功判据（本机三次同型，2026-10-14 精确化）**：`npm publish` 的 `PUT 202 + exit 0`（"being processed"）**不可作成功判据** —— 既可能是**假成功**（token 无 Publish 权限，registry 永无该版本），也可能**延迟落地**（本次约 2 分钟后才出现）。唯一判据 = **直连 registry 实测**：`dist-tags.latest` 已是该版本 + `dist.integrity` 与本地 `npm pack` tarball **逐字节一致**。
- **需求确认方式（用户 2026-10-14 口头约束）**：凡需用户确认 / 拍板的问题**一律用 ask-me 提问**，不用正文追问替代。

## 与 nao 机制衔接

- 角色清单与别名：`.agents/roles.yaml`（唯一事实；卡片 frontmatter 与其一致，`check` 校验）。
- 本文档构建与机制：本仓不复制任一机制条款到本文件——需要时引用 `.agents/` 内文件，勿双写。
- 布局/宿主/句柄语义：`.agents/scripts/nao-fleet.sh` + `.agents/common/intercom-protocol.md`（tmux 布局三选一，窄列回退 `main-col → grid`）。
- 文档规范：`.agents/checklists/deliverable-docs.md`（PRD/ADR/报告/调研统一骨架；默认不用表格）。