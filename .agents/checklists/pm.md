---
description: PM 交付核对清单（按需，交付/派发前读取）
---

# PM 红线与交付检查清单

> 角色卡只常驻最硬红线；本文件在**交付/派发前**读取并逐项核对。
> 汇报只报未过项：`未过：R-XX-03；其余 pass`（见 output-format）。

## PRD 9 模块速查（内容与缺失后果）

> 本表是**写前参考**（模块内容与缺失后果），**不是 PRD 正文格式**：正文按 @.agents/checklists/deliverable-docs.md §三 用列表 + 加粗字段名承载，**不用表格**。

| 模块 | 内容 | 缺失后果 |
| :--- | :--- | :--- |
| 问题证据 | 数据/反馈 + 5 Whys 动机 | 解决错误问题 |
| 目标指标 | 北极星拆解 + 预期提升值 | 无法验证价值 |
| 范围/非范围 | 做什么 / 不做什么 | 需求蔓延 |
| 用户场景 | 画像 + 场景卡片 + 关键路径 + 页面状态清单（加载/空/错误/成功） | 体验不清 |
| 业务规则 | 状态流转、权限、边界、不变量 | 实现分歧返工 |
| NFRs | 性能/安全/兼容性基线（业务视角） | 上线即事故 |
| AC | Given/When/Then + 数据不达标处置预案 | 验收扯皮 |
| 上线闭环 | 灰度 / 监控 / 回滚 | 事故无预案 |
| 变更治理 | 正式流程 + 版本记录（Hotfix 24h 补单） | 变更失控 |

> 写作要求（首屏 TL;DR、每格 ≤3 句、不适用项写法、长度上限 150 行）：@.agents/checklists/deliverable-docs.md §三（写 PRD 前读）。

## 硬性红线（完整 34 项）

- [ ] 无目标指标/假设就进开发？
- [ ] 边界不清晰（未写不做什么）？
- [ ] 用户故事无 AC 或无负向闭环？
- [ ] 变更口头沟通？（须正式；Hotfix 24h 补单）
- [ ] 数据口径/埋点未定义？
- [ ] 把非核心需求塞进当前版本（未过战略筛子）？
- [ ] PRD 只写方案、未写问题与 5 Whys？
- [ ] 验收在开发完成后才发现偏差（未评审对齐）？
- [ ] NFRs 未定义或未与技术达成共识？
- [ ] 模糊需求未触发 `grill-me` 就臆测产出？
- [ ] PRD 缺页面状态清单？
- [ ] **未经用户开工确认**就派发？
- [ ] 对未标注角色的会话臆测身份派发？
- [ ] **PM 亲自修改/新增代码**？（无 intercom 也不豁免）
- [ ] **PM 以「亲自探查技术实现」替代转角色**，并据此形成 PRD 前提？（越界调研 = 无效决策轮次；见 @.agents/skills/pm-routing.md §二）
- [ ] 派发消息贴了 PRD/方案全文、或用 `attachments` 传全文？（应给引用路径，worker 自己读文件）
- [ ] 跨批次未重开会话、未更新接续快照？（长上下文丢红线/闸门；见 @.agents/skills/pm-operations.md §三）
- [ ] 用外部调研（文章/竞品/开源实现）替代 arch 技术取舍，或把外部做法写成既定技术前提？（越界；见 @.agents/skills/pm-routing.md §二 + @.agents/skills/research.md）
- [ ] 非 PI/无 intercom 未按降级处理？
- [ ] 派发后未收终态回执就默认成功？（应追讨）
- [ ] **PM 无谓重复跑 worker 已跑的门禁？**（应避免：仅在异常时复跑/抽查；worker 须自跑全范围）
- [ ] 用户未指定模型却传了 `--model` 或继承 PM 模型？
  （默认不传，走 pi 全局默认；显式指定时由 `nao-fleet.sh` 的 `NAO_MODEL_WHITELIST` 白名单门禁校验，PM 无需自行校验，但**必须**在开工确认卡单独一行如实注明）
- [ ] 未过 PM 验收就合并 PR，或直推 main？（PM 验收通过 = 授权合并；见 `github-flow.md`）
- [ ] PM 亲自合并 PR / `push` main？（合并由 RD 执行，PM 只验收授权）
- [ ] PM 改了**源码/测试/构建配置**，或手改冲突内容？（应转 worker；PM 只做仓库治理与发布）
- [ ] main 上出现多条本需求提交，或出现 `wip()` 提交（未 squash）？或 squash **body** 被自动拼接出 `wip(`/已证伪的旧表述（合并时缺 `--body-file`）？（判据：`%s` 与 `%b` 各 `grep -c 'wip(' || true` = 0 —— `grep -c` 0 命中时 rc=1，必须 `|| true`；body 首行的旧表述为**人工项**；见 `github-flow.md` 合并节）
- [ ] 为文档 / 台账**单开 PR**，或任务期文档作为**独立提交直落 main**？（应随任务 PR；唯一例外 = BR3 立项摘要，降级批次无例外；见 `github-flow.md`）
- [ ] PR 标题 / 提交信息不可读（纯编号/类名/函数名/文件路径）？
- [ ] Issue 与 `docs/` 双源（正文抄进 Issue，或状态只留平台）？
- [ ] 未过验收 / 门禁未绿就打 tag 或 release，或 tag 指向非 main 合并提交？（见 `github-flow.md`）
- [ ] `git push --force` 到 main/共享分支（未经用户明确授权并指明分支）？
- [ ] release notes 不可读（纯编号/类名/路径），或未落盘 `docs/releases/`？（规范：@.agents/common/release-notes.md —— 面向用户「本次更新」置顶、内部信息下沉、正文不用表格）
- [ ] 输出里有 `warn`/`error`/`pending approval`/`N vulnerabilities` 却判完成，或遗留项未走三出口（「先放着」不算出口）？（见 @.agents/skills/task-completion.md）
- [ ] 降级（无 `gh` / 无远端）未在 `tasks-state` 与回执中标注？

## 交付检查清单（完整 44 项 · 仅 feat）

> 通道标注：本节 44 项**仅 `feat` 通道**核对（逐项标 `【仅 feat】`）；`fix` 通道只核下一节 8 条。分流判据（能写出「期望 vs 实际」且可复现）唯一出处：@.agents/skills/github-flow.md。
> **例外（两通道中立，非 feat 专属）**：文档 / 台账随任务 PR、工作期不落 main —— 见下节第 8 条。

- [ ] 【仅 feat】目标/边界/验收三件事齐备
- [ ] 【仅 feat】证据 + 5 Whys 已产出
- [ ] 【仅 feat】战略筛子已过，RICE 可追溯
- [ ] 【仅 feat】PRD 含 9 模块
- [ ] 【仅 feat】接缝候选已列并经 qa 确认（不适用注明理由）
- [ ] 【仅 feat】路径无关判据已核（@.agents/skills/pm-to-spec.md §六 逐条）
- [ ] 【仅 feat】场景模块含画像+场景卡+关键路径+页面状态清单
- [ ] 【仅 feat】AC 五覆盖
- [ ] 【仅 feat】变更记录完整（含 Hotfix）
- [ ] 【仅 feat】AC 可测 + NFRs 验收方式与研发/测试/架构对齐
- [ ] 【仅 feat】数据口径/埋点/指标清晰
- [ ] 【仅 feat】模糊需求已 `grill-me`
- [ ] 【仅 feat】环境判定已执行；开工确认卡获确认；派发前 `list` 验在线；**开工自检 · 本地 `main` 无领先提交**：`git rev-list --count origin/main..main` = 0（≠0 则先处置：发布收尾类由 RD 按显式 sha 推，任务期文档一律落分支。来源：arch `O1` / `docs/reports/2026-11-01-T537-arch.md` §Q5）
- [ ] 【仅 feat】worker 离线已检测并处理（`ensure --force` 重拉 + 恢复/重派）
- [ ] 【仅 feat】降级交付已回流登记（tasks-state + 归档，标注「降级回流」）
- [ ] 【仅 feat】派发前已核对目标在线且 `idle`（忙则排队/紧急抢占注明）
- [ ] 【仅 feat】路由已核对：工程基座类（CI/构建/发布/脚本守卫/依赖安全/仓库治理）未误派 `rd-be`（应派 `rd-infra`）
- [ ] 【仅 feat】无匹配角色时：显式声明 + 选最接近专精角色 + 临时附加清单 + 台账登记（不许默默兜底）
- [ ] 【仅 feat】`docs/tasks-state.md` 已随派发/回执/验收同步更新（状态外部化，可恢复）
- [ ] 【仅 feat】需新开的会话已 `ensure` 并经 `list` 验证
- [ ] 【仅 feat】派生会话已回收（验收通过后 `close --task <编号> <别名>`；常驻会话**不回收**，需重开时 `ensure --force`）
- [ ] 【仅 feat】全程 PM 未触碰代码
- [ ] 【仅 feat】PRD 已归档 `docs/prds/` 并同步 README 索引
- [ ] 【仅 feat】项目 `AGENTS.md` 已建立/同步（项目级属性与约束，见 @.agents/skills/pm-operations.md §四）
- [ ] 【仅 feat】worker 回执含**全量**门禁精确数字（命令 + exit code + 文件数/例数/红数）；PM 仅核对数字 + 读变更文件 + 异常才抽查（未重复跑）
- [ ] 【仅 feat】派发消息只给引用路径（`docs/...md#section`），无 PRD/方案全文或附件传全文
- [ ] 【仅 feat】派发含「根因 + 修复方向」的指令已附**一条已执行的实测命令与输出**（无实测只能派「诊断/复现任务」，不得先给方向）
- [ ] 【仅 feat】派发时已声明回执级别（未声明默认 `done(lite)`；有阻塞/风险/需决策已要求 `done(full)`）；模板已按需读取 `@.agents/checklists/comm-templates.md`
- [ ] 【仅 feat】用户口头约束已**当场落盘**（`AGENTS.md` 项目级 / PRD「变更治理」），未等归档
- [ ] 【仅 feat】归档前已更新接续快照 + 记录会话体检（归档后按 @.agents/skills/pm-operations.md §三 重开会话）
- [ ] 【仅 feat】业界调研（若有）已落盘 `docs/research/`，每条含「适用条件 + 本项目差异（采纳/改造/不采纳）」；引用带访问日期，查不到已写「未检索到」
- [ ] 【仅 feat】派发消息已给出**需求分支** `feat/<issue-id>-<slug>`（或降级 `nao/<批次-slug>`）、PR owner、Reviewer
- [ ] 【仅 feat】工作期无 WIP 提交落在 main；暂存为路径级（无 `git add -A` 卷走他人改动）
- [ ] 【仅 feat】**文档随任务 PR**：本任务文档与台账（PRD 定稿 / 报告 / ADR / `docs/tasks-state.md` / 索引 / release notes）已在本需求分支提交并随同一 PR 进 main；main 上无 `docs(<编号>):` 独立提交、无文档-only PR（立项摘要例外仅 1 条且单一文件）
- [ ] 【仅 feat】Issue 已建（或降级已标注）：body 为摘要 + 指针，正文在 `docs/prds/`；同步仅 5 个节点
- [ ] 【仅 feat】验收在 PR 上完成：AC 逐条评论核对 + QA 门禁数字；**UI 呈现类已交用户验收清单并获回填**（QA 产出 → PM 审 → 用户执行）；**验收通过后才授权合并**
- [ ] 【仅 feat】合并由 RD 执行（`--squash` + 显式 `--subject` **与 `--body-file`（用 PR 描述）**）；main 上本需求恰好 1 条提交、**subject 与 body 均无 `wip()`**；需求分支已删除
- [ ] 【仅 feat】合并前已核「分支无未推送提交」（适用：在分支上提交过的**任何角色**，含 PM 落的文档/台账）：`git rev-list --count origin/<branch>..HEAD` = 0 · `git status --porcelain` 为空 · `HEAD == @{u}`；任一不满足 ⇒ 不得贴验收评论 / 授权合并（T533 孤儿提交教训：`docs/reports/2026-10-30-T533-retro.md`）
- [ ] 【仅 feat】发布（若有）：版本号符合 SemVer/项目约定；tag 指向 main 合并提交；release notes 用户可读且落盘 `docs/releases/`（核 @.agents/common/release-notes.md）
- [ ] 【仅 feat】`gh` 可用则已用 `gh`，降级已注明；发布后事实（含 `tasks-state` 版本/Tag 行）的**落地时机与工作区纪律见 `github-flow.md` BR5**（单源指针，本清单不复写命令细节）
- [ ] 【仅 feat】任务 DoD 四类已随**开工确认卡**逐任务实例化（产物路径 / 可执行验证判据 / 遗留项 / 交接），验收按同一份核
- [ ] 【仅 feat】回执含 `遗留：` 字段且遗留项已**三出口**收口（关闭 / 接受含到期日 / 转办；零遗留显式「无」，可执行项已进 `tasks-state` 待派发队列）
- [ ] 【仅 feat】**计数类数字必须自证一条命令** —— 用例数 / 断言数 / `files=` / 行数的**取数命令单源见 `tests/README.md`「取数命令四条」**（本清单**不复写命令**；PM / QA / RD 三侧同源）；回执须同时给 **命令 + 输出 + HEAD sha + 静默工作区状态**（三件套见 @.agents/common/output-format.md「回执硬性」第 3 条）；**回执与命令输出不一致时以命令为准**，并当场订正回执/文档（来源：L1 复盘 `docs/reports/2026-11-01-T536-retro.md`）
- [ ] 【仅 feat】通过上面全部红线

## 派单纪律核对（M20261107 · 派发前逐条勾 · 执行者：PM）

> 依据：`#84` P1（数据通道）· `#86` P1（各态断言）· `#86` P3-1 / `#88` P3-③（作用域+变异）。**只写在 `pm-operations.md` 正文不算落地**——本节即可勾选口径。

- [ ] **数据通道已点明**：凡「让 A 拿到 B 的数据」（跨 shell / 跨进程 / 跨角色）已写明走**文件 / 参数 / 返回值**，未写「用全局变量」（`#84` P1：子 shell 拿不到全局 ⇒ SKIP 变 FAIL）
- [ ] **各态断言已列**：成功 / 失败有输出 / 失败无输出 / 无凭据 / 超时 五态逐条要求「必须 SKIP 或 PASS，不得 FAIL/中止」（`#86` P1：`SKIP=0` 全绿 ≠ 安全）
- [ ] **作用域 + 变异已写**：断言作用域（整段 / 某行 / 某字段）已指定；「改空 / 改错 ⇒ 必红」的变异自证已列为交付物（`#86` P3-1、`#88` P3-③）
- [ ] **判定方式可机械执行**：上述三段在派发消息里**能逐段检索到**（QA 复核时按此判「可执行性」，而非「有没有写」）

## `fix` 通道核对（完整 8 项 · 仅 fix）

> 判据：能写出「期望行为 vs 实际行为」且可复现 → `fix`，否则升 `feat`（判据唯一出处：@.agents/skills/github-flow.md「通道分流判据」，本处不复制条件）。本节只核 8 条，**不减门禁**（`check` + `npm test` 全量 rc=0 照旧；无测试设施的降级见第 3 条）。

- [ ] 分流成立：3 字段齐备（现象 / 复现 / 回退），「期望 vs 实际」可复现；不成立 ⇒ 当场升 `feat` 而非降格开工
- [ ] 分支与范围：`fix/<issue-id>-<slug>`（无 Issue 降级 `nao/<批次-slug>`；线上问题从受影响版本 tag 切出）；diff 只碰修复路径，无夹带重构 / 格式化；**PM 按 `git diff --name-only` 核：文件集 ⊆ 修复点 + 其测试 + 台账，超出即打回；>3 文件须在 PR 内写书面理由（降级无 PR ⇒ 落 `docs/reports/<编号>-review.md` 或 `tasks-state` 该任务条目相邻行）**
- [ ] 先红后绿：可失败用例先复现失败（回执贴命令 + 输出）→ 修复后全量 `bash .agents/scripts/nao-fleet.sh check` 与 `npm test` rc=0；**无测试设施**（纯文档仓 / 无 `npm test`）⇒ 用最小复现命令贴「修复前失败 / 修复后通过」的命令 + 输出（可放 `docs/reports/<编号>-repro.*` 或 Issue 内联）；项目 `AGENTS.md` 指定了门禁命令则**以它为准**，未指定则 `check` rc=0
- [ ] 回退可执行：`git revert <sha>` 可干净回退；数据 / 契约类在 Issue 上 3 行写影响面
- [ ] 复核留痕：非作者复核（QA / 另一会话）；单人项目允许**作者自审**，但**唯二载体**才算留痕 —— PR 描述「复核」一节 + `docs/tasks-state.md` 条目一行（理由 + 日期 + 自审声明），缺任一不算留痕；**降级模式（无远端 / 无 `gh`，无 PR）⇒ 首载体改 `docs/reports/<编号>-review.md`（或 `tasks-state` 该条目相邻行），内容与判据不变**
- [ ] 不可逆动作仍走 `ask-me`（合并 main / 打 tag / 发 npm / 破坏性契约 / 删文件或数据）——`fix` 不豁免
- [ ] 回执 `lite` 含门禁精确数字 + 遗留三出口；`docs/tasks-state.md` 已同步；合并前已核「分支无未推送提交」（`git rev-list --count origin/<branch>..HEAD` = 0 · `git status --porcelain` 空）
- [ ] 文档 / 台账随任务 PR，工作期无 `wip()` 落 main —— **两通道同规**

## 会话回收 / 收窗核对（验收通过后 / 手工关窗前）

- [ ] 派生会话：`tasks-state` 已把任务推进到「已验收 / 已归档」→ `nao-fleet.sh close --task <编号> <别名>`（否则会被状态闸门拦下）
- [ ] `status` 残留节按**仓归属**读：本仓行才可 `close`；他仓 / 归属不可判定行的处置见 @.agents/skills/pm-operations.md「残留自检」（单源，本清单不重复文案）
- [ ] 常驻会话**不回收**（保留复用）；上下文变长时 `ensure --force` 重开
- [ ] 手工关窗（tmux `kill-pane`）前：该会话已回**终态回执**（**未回执不得关**）+ `tmux capture-pane -p -t <pane>` 末 5 行无 `Working`/spinner + 产物已落盘（`git log` 有提交且**落在需求分支**、工作区干净、无 WIP 提交泄漏到 main、dev server/探针已停）
- [ ] 残留已核对：`nao-fleet.sh status` **本仓**无 `! 残留` 提示（有则 `close --task` 或补登 tasks-state）；`~`（他仓）/ `?`（归属不可判定）行按上一条指针处置，**不得**在本仓 `close`
