---
description: 按需技能——新需求落地流水线（Issue → 分支 → PR → 验收 → squash 合并 → Release；GitHub Flow / trunk-based）
---

# 新需求落地流水线（GitHub Flow）

## 触发时机

PM 在**立项 / 终签 / 发布**时读取；RD 在**起分支 / 开 PR / 合并**时读取；QA 在 **PR 验证**时读取。日常轮次不加载。

## 原则

- **main 始终可发布**：main 只接收经 PR + 验收的 **squash 合并（1 条 = 1 需求）**。
- **短生命周期分支**：一个需求一条分支，存活 ≤ 一个批次；跨天过长就拆需求。
- **边界对齐**：一个批次 ≡ 一个需求 ≡ 一个父 Issue ≡ 一条分支 ≡ 一个 PR（前后端分离则每仓库一条）。
- **合并权在 RD，闸门在 PM**：PM **验收通过前不得合并**；合并由 RD 在 PR 上执行，**PM 不亲自合并**。
- **一个任务 PR = 全量改动**：实现 / 测试 / 文档（PRD 定稿 · 验收报告 · ADR · `tasks-state` 台账 · 报告 · 索引 · release notes）同属**一条** PR；**文档不单开 PR、不独立落 main**（唯一例外 = 立项摘要，细则见「文档与台账载体（一任务一 PR）」）。

## 八阶段

| # | 阶段 | 主责 | 动作 | 产出 |
| :--- | :--- | :--- | :--- | :--- |
| 1 | 立项 | PM | 建 Issue（用户故事 / AC / 优先级 / 里程碑）+ PRD 正文落 `docs/prds` | 可追踪 Issue + **PRD 定稿（随本 PR）** |
| 2 | 拆分排期 | PM | 拆任务、定 PR owner / Reviewer / 分支名 | 开工确认卡 + **`docs/tasks-state.md` 登记（随本 PR）** |
| 3 | 起分支 | RD | 从 main 拉 `feat/<issue-id>-<slug>`，开 **Draft PR** | Draft PR + CI（+ 立项摘要，唯一例外） |
| 4 | 开发提交 | RD | 小步 `wip(<编号>):` 提交，push 触发 CI | 增量代码 + CI 结果 + 阶段文档（ADR / 报告，**随本 PR**） |
| 5 | 评审测试 | RD / QA / Reviewer | 填 PR 模板、QA 跑全量门禁、预览环境验证 | Review 通过 + QA 报告 / 用户验收清单（`docs/reports/`，**随本 PR**） |
| 6 | 验收合并 | PM → RD | PM 逐条核 AC 并在 PR 评论；**通过后由 RD squash 合并、删分支** | main 上 1 条提交（**含该任务全部文档改动**） |
| 7 | 发布 | PM | 版本号 + tag + Release notes（优先 `gh`） | Release 记录 + notes 落 `docs/releases/`，批间收尾事实随发布提交带走 |
| 8 | 复盘 | PM | 监控指标、关 Issue、归档 PRD | 复盘 + 归档（随发布提交或**下一任务 PR**） |

## 文档与台账载体（一任务一 PR）

**一个任务 PR = 该任务全量改动**（BR1）：文档与台账不另立载体，`docs/` 改动一律随该任务的 PR 进 main。

- **BR1 全量（一 PR 含全部改动）**：任务 PR 必须包含该任务**全部文件改动** —— 实现 / 测试 / PRD 定稿 / 验收报告 / ADR / `docs/tasks-state.md` / `docs/reports/*-followups.md` / `docs/prds/README.md` 索引 / `docs/releases/<v>.md`。验收读 PR diff 即见文档变化；回滚 `git revert` 单条即整需求。
- **BR2 禁令**：① 禁止为文档 / 台账**单开 PR**；② 禁止任务期文档作为**独立提交直落 main**（唯一例外见 BR3）。发布提交（阶段 7）承载批间收尾事实，不计入本禁令。
- **BR3 立项例外（三条件同时满足才可用）**：① **仅用于**建 Issue / 定分支名所需的最小摘要；② 内容上限 = **最小摘要三要素**（TL;DR + AC 编号 + PRD 路径指针），正文仍留 `docs/`，**禁抄正文**；③ **单条** `docs(<编号>):` 提交、只含该摘要文件、**不与其它改动混提**。**降级批次（无 Issue）无此例外**。
- **BR4 谁提交**：PM 在需求分支做**路径级**提交（`git add <具体路径>`，`docs(<编号>):` 前缀，**禁 `-A`**、禁 push main）；RD 最终 squash 时一并带入。同 worktree 并行时，提交方**只暂存自己的路径**。
- **BR5 批间收尾（发布后事实）**：合并后产生的事实（npm 核验结果 / Release 标题核验 / 角色卡广播登记 / 会话交接快照）随**发布提交一次带走**；**发布提交之后**才产生的事实登记进**下一个任务 PR 的首个文档提交**（随该 PR 一并进 main），**不得单独提交 main**。其间**不得留工作区脏改**：需要先保住改动时用**带标签的 `git stash`**（如 `git stash push -m "<编号>: 发布后事实" -- <路径>`），在下一分支的首个文档提交里 `git stash pop` 后一并提交。理由：实测 PM 把 `tasks-state` 改动留在工作区时，用户执行 `git pull --ff-only` 会被未暂存改动拒绝（`pull.rebase=true` 下周期性阻塞协作）。
- **BR6 可读性不变**：PR 标题与 `gh pr merge --squash --subject` 仍须用户可读（禁纯编号 / 类名 / 路径）；文档改动不降低该要求。
- **自查三条（可执行）**：main 上本任务提交数（`git log --oneline main | grep -c '(<编号>)'`）· 本 PR diff 是否含 `docs/` 路径（`git diff --name-only main...HEAD | grep '^docs/'`）· 工作区干净（`git status --porcelain` 为空）。
- **验证接缝**：文本口径由一次性只读探针核（如 `docs/reports/<日期>-*-probe.sh`），不进 `tests/`。

## 分支与提交

- 命名：`feat/<issue-id>-<slug>`；无 Issue 时降级 `nao/<批次-slug>`；hotfix 用 `hotfix/<issue-id>`。
- **禁止** `git push` 到 main、**禁止绕过 PR 合并**；feature 分支允许 `--force-with-lease`（改基 / 压缩历史时）。
- 提交规范、`wip()` 前缀、路径级暂存、可读性：见 @.agents/skills/commit.md。
- **squash 后 main 上的提交信息 = PR 标题 + PR 正文** → **可读性硬性落在 PR 标题**（用户可见行为，禁纯编号/类名/路径）。
- ⚠️ **单提交 PR 的 squash 陷阱（T511 实测 3/3 仓中招）**：`gh pr merge --squash` 在 PR **只有 1 条提交**时，取的是**该提交的 subject**（**不是** PR 标题）⇒ 分支纪律的 `wip(<编号>):` 前缀会直接进主干。**合并命令必须显式指定**：`gh pr merge <n> --squash --delete-branch --subject "<用户可读主题>" --body "<摘要>"`；或合并前把分支压成一条用户可读提交。主干受保护（禁 force-push / `enforce_admins=true`）时该偏差**不可回溯**，只能记录。

## Issue 与状态（避免双源）

- **Issue = 入口 / 摘要 + 指针**：body 只放 TL;DR、AC 编号、优先级、`docs/prds/...md` 指针。
- **`docs/` = 正文权威**（PRD 全文、`tasks-state.md` 运行时状态）：离线可用、会话重开读本地。
- **同步时机（仅 5 个节点）**：立项、派发、验收通过、合并、发布——其余不动 Issue，省 gh 往返。
- Issue 上的业务讨论由 PM **摘录进 `docs/`**，不留在平台。

## PR 模板与 Reviewer

- 模板 `.github/pull_request_template.md`（PM 从 `.agents/templates/github/pull_request_template.md.example` 复制建立）。
- Reviewer 由 PM 在开工确认卡指定（默认 `arch-designer`；纯 CRUD 可写「无」并注明理由）。
- QA 在 PR 评论贴**门禁精确数字**；PM 在 PR 评论核 AC。

## 发布（阶段 7）

- 版本号：SemVer，PM 按批次范围定（feat→MINOR / fix→PATCH / 破坏性→MAJOR）；项目 `AGENTS.md` 有约定则从之。
- 门禁：AC 全过 + 验收闭环 + main 门禁全绿 + 工作区干净 + PR 已合并。
- **发布前置（严格闸门 · 双环境）**：若仓库提供 `test:t4:full:dual` 脚本，发布前须先 `npm run test:t4:full:dual` **rc=0**（**两组**= `$TMUX_PANE` 已设 / `env -u TMUX_PANE`；判据 = **两组 SKIP 计数与 DEGRADE 计数均为 0，且非白名单 NOTE 计数为 0**，`SKIP`/`DEGRADE`/非白名单 `NOTE` 即 FAIL）。仅有 `test:t4:full`（单环境）的仓库退用 `npm run test:t4:full` rc=0；双环境 gate 误红时可临时回落单环境并记台账。
- **优先 `gh`**：`gh release create <tag> --title "vX.Y.Z" --notes-file docs/releases/<version>.md`（**标题口径（强约束）：@.agents/common/release-notes.md** —— 标题仅裸版本号，描述进正文首段）。
- 探测：`gh auth status` 按 **exit code** 判定（`keyring` 警告但 exit 0 **仍可用**，可 `gh api user` 复核）；**不自动 `gh auth login`**（涉用户凭证）。
- release notes 落盘 `docs/releases/<version>.md`（**写作规范（强约束）：@.agents/common/release-notes.md** —— 面向用户「本次更新」置顶、内部编号 / 文件名 / 属性名一律下沉「技术细节」、正文不用表格；骨架见 @.agents/templates/release-notes.md.example）。
- 回滚：未 push → `git tag -d`；已 push → **不删远端 tag**，改发下一个 PATCH 修正（用户明确要求才删）。

## 离线 / 无远端降级

无 `gh` / 无远端 / 未认证时**不阻断交付**，按同构降级（**保持「main = 1 条/需求」不变**）：

| 环节 | 正常 | 降级 |
| :--- | :--- | :--- |
| 立项 | GitHub Issue | 摘要写 `docs/prds` + tasks-state，跳过 Issue |
| 分支 | `feat/<issue-id>-<slug>` | `nao/<批次-slug>` |
| 评审 | PR + CI + 预览环境 | 本地全量门禁 + PM 读 diff |
| 合并 | PR squash merge | PM 验收通过后，RD 本地 `git merge --squash feat/… && git commit` + 删分支 |
| 文档载体 | 随任务 PR（PR diff 含 `docs/`） | 同样在本地分支提交并由 `merge --squash` 带入 main，**不另开文档提交** |
| 发布 | `gh release create` | `git tag -a` + notes 落 `docs/releases/` |

降级须在 `tasks-state` 与回执中标注「降级」。

## 红线

- [ ] 未过 PM 验收就合并 PR，或直推 main？
- [ ] main 上出现多条本需求提交，或出现 `wip()` 提交（未 squash）？
- [ ] 为文档 / 台账**单开 PR**，或任务期文档作为**独立提交直落 main**（立项摘要例外见 BR3）？
- [ ] PM 亲自执行合并 / `push` main？
- [ ] Issue 与 `docs/` 双源（正文抄进 Issue，或状态只留平台）？
- [ ] 未过验收 / 门禁未绿就打 tag，或 tag 指向非 main 提交？
- [ ] PR 标题 / release notes 不可读（纯编号 / 类名 / 路径）？
- [ ] 降级未标注？
