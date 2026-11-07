---
description: 按需技能——新需求/缺陷修复落地流水线（阶段 0 受理分流 → Issue → 分支 → PR → 验收 → squash 合并 → Release；双通道 feat / fix）
---

# 新需求落地流水线（GitHub Flow）

## 触发时机

PM 在**受理 / 立项 / 终签 / 发布**时读取；RD 在**起分支 / 开 PR / 合并**时读取；QA 在 **PR 验证**时读取。日常轮次不加载。

## 原则

- **main 始终可发布**：main 只接收经 PR + 验收的 **squash 合并（1 条 = 1 需求）**。
- **短生命周期分支**：一个需求一条分支，存活 ≤ 一个批次；跨天过长就拆需求。
- **边界对齐**：一个批次 ≡ 一个需求 ≡ 一个父 Issue ≡ 一条分支 ≡ 一个 PR（前后端分离则每仓库一条）。
- **合并权在 RD，闸门在 PM**：PM **验收通过前不得合并**；合并由 RD 在 PR 上执行，**PM 不亲自合并**。
- **一个任务 PR = 全量改动**：实现 / 测试 / 文档（PRD 定稿 · 验收报告 · ADR · `tasks-state` 台账 · 报告 · 索引 · release notes）同属**一条** PR；**文档不单开 PR、不独立落 main**（唯一例外 = 立项摘要，细则见「文档与台账载体（一任务一 PR）」）。

## 通道分流判据（唯一判据）

- **默认 `fix`（轻通道）**：硬条件 = **能写出「期望行为 vs 实际行为」且可复现**（第三方按文字即可判定，禁「视情况」「大概率」）。
- **升 `feat`（全通道）**：写不出期望/实际对比 · 不可复现 · **或超出报告所描述的期望范围**（新增能力 / 改动既有行为约定 / 破坏性契约）⇒ 全量 PRD（9 模块）+ 开工确认卡，按原流程走。**把「实际」改回「期望」不算行为改变**（否则每条修复都命中）。
- **命名随通道**：`fix/<issue-id>-<slug>`（轻通道，diff 只碰修复路径）｜`feat/<issue-id>-<slug>`（全通道）；两者无 Issue 时统一降级 `nao/<批次-slug>`。
- **减仪式不减门禁**：`fix` 免 9 模块 PRD / 开工卡降为一问 / 回执 `lite` / 复盘 `L0`，但 `check` + `npm test` 全量 rc=0 与「先红后绿」不变（细则 @.agents/prompts/product-manager.md §二）。**无测试设施**（纯文档仓 / 无 `npm test`）→ 用**最小复现命令**，修复前失败 / 修复后通过的**命令 + 输出**贴回执（可放 `docs/reports/<编号>-repro.*` 或 Issue 内联）；项目 `AGENTS.md` 指定了门禁命令则**以它为准**，未指定则 `check` rc=0。

## 阶段 0 受理（triage；被动触发）

| 触发 | 动作 | 产出 |
| :--- | :--- | :--- |
| ① 用户明确要求「看 Issue」；② PM 被指向具体 Issue 号；③ 对话中用户直接报障 | 一条 `gh issue list` 或 `gh issue view <n>`；按 triage 三问判定；摘录成 `docs/tasks-state.md` 任务条目并**以 Issue 号回链** | 通道判定（`fix` / `feat`）+ 台账条目 |

- **triage 三问**：① 能否写出「期望 vs 实际」且可复现？② 来源是哪（用户 / QA / 线上 / 自查）？③ 是否影响已发布版本（影响则记版本 tag，`fix` 分支从该 tag 切出）？任一不能判定 ⇒ **挂起并回问用户，不猜**。
- **被动义务（硬约束）**：**不轮询、不常驻、不建后台任务、不做标签自动化**；只在上述三种时机执行。无 `gh` / 离线时降级为用户口述 Issue 内容并留痕。

## 八阶段（阶段 1–8）

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

## 非范围（显式 out-of-scope）

**生产部署 / 灰度发布 / 线上监控与告警 / 线上回滚执行 / MTTR / SLA 不归舰队**。舰队只负责「问题 → 分流 → 修 → PR → 验收 → 合并 → 发版」；线上暴露的问题仅作为 **Issue 输入源**进来（记受影响版本 tag、`fix` 分支从该 tag 切出、修完回合 main），其观测与回滚阈值不在本机制内。

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

- 命名：`fix/<issue-id>-<slug>`（缺陷修复）｜`feat/<issue-id>-<slug>`（新能力 / 行为变更）；无 Issue 时统一降级 `nao/<批次-slug>`；线上补丁用 `hotfix/<issue-id>`，且**从受影响版本 tag 切出**（tag 作为基线的唯一场景）。
- **禁止** `git push` 到 main、**禁止绕过 PR 合并**；feature 分支允许 `--force-with-lease`（改基 / 压缩历史时）。
- 提交规范、`wip()` 前缀、路径级暂存、可读性：见 @.agents/skills/commit.md。
- **squash 后 main 上的提交信息 = PR 标题 + PR 正文** → **可读性硬性落在 PR 标题**（用户可见行为，禁纯编号/类名/路径）。
- ⚠️ **squash 提交信息的两处陷阱（T511 / #84 实测，主干上不可回溯）**：
  1. **subject**：PR **只有 1 条提交**时 `gh pr merge --squash` 取的是**该提交的 subject**（**不是** PR 标题）⇒ 分支纪律的 `wip(<编号>):` 前缀会直接进主干；
  2. **body**：未显式给 `--body` / `--body-file` 时，GitHub 把**各提交标题**自动拼成 body ⇒ 主干 body 含 `wip(` 与**已被证伪的旧表述**（实测：#84 6 处、#80 8 处、#82 4 处，同型）。
  - ✅ **合并命令必须同时显式指定 subject 与 body，且 body 取 PR 描述**：
    `gh pr merge <n> --squash --delete-branch --subject "<用户可读主题>" --body-file <PR 描述文件>`
    （取描述：`gh pr view <n> --json body --jq .body > /tmp/pr<n>.md`，或复用开 PR 时写的那份文件。）
  - **合并后即时自证（判据，两处都要 0）**：`git log -1 --format=%s | grep -c 'wip(' || true` = 0 **且** `git log -1 --format=%b | grep -c 'wip(' || true` = 0。
    ⚠️ 写成 `|| true` 是硬要求：`grep -c` 在 0 命中时**退出码为 1**，裸用在 `set -e` / `&&` 链里会把「通过」误读成失败。
  - **人工项（不可机械判）**：body 首行是否仍含**已被证伪的旧表述**（结论会随认知更新而变化）⇒ 合并前由执行者**读一遍 PR 描述**确认，不设自动判据。
  - **写法（与上面的判据同处，防判据自伤）**：PR 描述 / 文档正文**要提及该前缀时写「`wip` 前缀（不带左括号）」**，不要写字面形态；判据保持机械 `grep -c 'wip('` = 0（`#86` 合并时实测：正文写了字面形态会让判据自伤，故改指代写法）。
  - 主干受保护（禁 force-push / `enforce_admins=true`）时该偏差**不可回溯**，只能记录 —— 故此处是**合并前**的硬要求。

## Issue 与状态（避免双源）

- **一句判据（区分两侧，互不冲突）**：**输入侧 = 别人交来的报障原文，留平台（它是证据，不是规格）；输出侧 = PM 立项摘要，不抄正文（正文在 `docs/`）**。
- **输入侧（外部 Issue / 线上转来）**：原始报告正文**留在平台**，不搬进仓库；PM 在阶段 0 triage 后**摘录成 `docs/tasks-state.md` 任务条目并以 Issue 号回链**；凡进入 `docs/prds/` 的规格正文仍**只写一处**（规格在 `docs/`，证据在平台）。原文里的**规格建议不算证据** —— 被采纳 ⇒ 写入 `docs/prds/`（规格唯一权威）并在 Issue 回帖指针、**原帖不改**；未采纳 ⇒ 只在 `tasks-state` 记一行决策。
- **输出侧（PM 立项）**：**Issue = 入口 / 摘要 + 指针**：body 只放 TL;DR、AC 编号、优先级、`docs/prds/...md` 指针。
- **`docs/` = 正文权威**（PRD 全文、`tasks-state.md` 运行时状态）：离线可用、会话重开读本地。
- **同步时机（仅 5 个节点）**：立项、派发、验收通过、合并、发布——其余不动 Issue，省 gh 往返。
- Issue 上的业务讨论由 PM **摘录进 `docs/`**，不留在平台（**报障原文及其规格建议按输入侧处理，不在此列**）。

## PR 模板与 Reviewer

- 模板 `.github/pull_request_template.md`（PM 从 `.agents/templates/github/pull_request_template.md.example` 复制建立）。
- Reviewer 由 PM 在开工确认卡指定（默认 `arch-designer`；纯 CRUD 可写「无」并注明理由）。
- QA 在 PR 评论贴**门禁精确数字**；PM 在 PR 评论核 AC。

## 发布（阶段 7）

- 版本号：SemVer，PM 按批次范围定（feat→MINOR / fix→PATCH / 破坏性→MAJOR）；项目 `AGENTS.md` 有约定则从之。
- 门禁：AC 全过 + 验收闭环 + main 门禁全绿 + 工作区干净 + PR 已合并。
- **发布前置（严格闸门 · 双环境）**：若仓库提供 `test:t4:full:dual` 脚本，发布前须先 `npm run test:t4:full:dual` **rc=0**（**两组**= `$TMUX_PANE` 已设 / `env -u TMUX_PANE`；判据 = **两组 SKIP 计数与 DEGRADE 计数均为 0，且非白名单 NOTE 计数为 0**，`SKIP`/`DEGRADE`/非白名单 `NOTE` 即 FAIL）。仅有 `test:t4:full`（单环境）的仓库退用 `npm run test:t4:full` rc=0；双环境 gate 误红时可临时回落单环境并记台账。
- **优先 `gh`**：`gh release create <tag> --title "vX.Y.Z" --notes-file docs/releases/<version>.md`（**标题口径（强约束）：@.agents/common/release-notes.md** —— 标题仅裸版本号，描述进正文首段）。
- **`gh release create <tag> --target <短 sha>` 不可用（两次实测：v0.21.0 / v0.21.1）**：会报 `tag_name is not a valid tag` / `target_commitish is invalid`。正确路径 = 先 `git tag -a <tag> -m "<说明>"` → `git push origin <tag>` → `gh release create <tag> --title <裸版本号> --notes-file <file> --verify-tag`（**不要**用 `--target` 指向未 push 的短 sha）。
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

### 网络降级三步（B · 在线动作失败时的统一口径）

适用：`git pull/push`、`npm view`、`gh` 等**在线动作**超时或连接失败（`#90` 实测 `git pull` 133–136s 超时、`push` 连失 5 次、`npm view` 超时）。

1. **重试一次**（同一命令、不改参数；`push` 重推即可，**禁 force / 禁改写历史 / 禁为绕过而另开 PR**）。
2. 仍失败 ⇒ **记录降级**：在 `tasks-state` 该任务条目与回执里写「在线动作失败 + 旁证」（如 `curl -m 8 https://github.com` 的 `http_code`）与**改用的本地可核事实**（本地门禁数字、`git rev-parse`、本地 md5 / 文件数）。
3. **回执首段逐条标注**哪些结论属「**间接确认、未做在线复核**」；**不出整体 PASS** —— 在线侧未核的部分只能写「未核」，不得写成已通过。

> 依据：`#90`（推送被网络阻断 ⇒ 如实报阻塞 + 给处置选项，未静默重试、未破坏流程）。

- **降级用载体（无 PR 对象时）**：`fix` 通道的「书面理由」（>3 文件）与「复核 / 自审留痕」两个载体均默认落在 PR；降级模式（无远端 / 无 `gh`，无 PR 可写）⇒ 改为 **`docs/reports/<编号>-review.md`**（或 `docs/tasks-state.md` 该任务条目相邻行），内容不变（理由 + 日期 + 自审声明），「>3 文件须写书面理由」同落此处。

## 红线

- [ ] 未过 PM 验收就合并 PR，或直推 main？
- [ ] main 上出现多条本需求提交，或出现 `wip()` 提交（未 squash）？
- [ ] 为文档 / 台账**单开 PR**，或任务期文档作为**独立提交直落 main**（立项摘要例外见 BR3）？
- [ ] PM 亲自执行合并 / `push` main？
- [ ] Issue 与 `docs/` 双源（输入侧报障原文搬进 `docs/`，或输出侧把规格正文抄进 Issue）？
- [ ] `fix` 通道夹带重构 / 格式化 / 无关文件，或未先写可失败用例？
- [ ] 线上暴露的问题未记受影响版本 tag，或把部署 / 灰度 / 监控 / 回滚 / MTTR 揽进本机制？
- [ ] 未过验收 / 门禁未绿就打 tag，或 tag 指向非 main 提交？
- [ ] PR 标题 / release notes 不可读（纯编号 / 类名 / 路径）？
- [ ] 降级未标注？
