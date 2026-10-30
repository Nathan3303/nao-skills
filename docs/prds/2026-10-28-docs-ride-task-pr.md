# PRD：文档与台账随任务 PR（一个任务 = 一条 PR 全量改动）

- 状态：已开工（T533 · 降级批次 `nao/pr-scope`）· Owner：PM · 更新：2026-10-28
- 指针：上游 = 用户 2026-10-28 口头约束（四项 ask-me 拍板，见附录 D1–D4）· 实测取证 = main 近 25 条提交 + `gh pr list`
- 优先级：高（流程口径 · 低成本高杠杆）· RICE 结论 ≈ 32（附录）

## TL;DR（≤5 行）

- **做什么**：把「台账 / PRD / 报告 / 索引 / notes」等文档改动收进该任务的 PR，禁止为文档单开 PR 或任务期独立落 main。
- **给谁**：PM（提交与验收）、RD（squash 带入）、下游三仓（复制口径）。
- **成功标准**：main 上每需求除任务提交外，文档独立提交数 = 0（发布提交另计）；机制 5 处文本齐备 + 探针 PASS + `check`/`npm test` rc=0。
- **不做什么**：不追改历史 docs 提交；不加脚本闸门；不动 Issue 5 个同步节点与 release notes 写法。

## 一、问题证据

- **实测（2026-10-28）**：main 近 25 条提交里 **13 条是 `docs(T5xx)` 独立提交**（`74e922d` `e8ecb7c` `4187ea9` `f5fc3b5` `51a2ced` `8da2722` `a2e6377` `d935ad8` `2d07bcd` `b8f61c7` `43321e2` `99026e5` `bf0c36d`），而 `gh pr list` 12 条全是任务 PR ⇒ 文档实际走的是「绕 PR 直达 main」通道。
- **后果**：① 一个需求散落在多条 main 提交，`main = 1 条/需求` 名存实亡、无法整条回滚；② PR diff 不含台账，PM 验收与 QA 门禁都看不到文档变化；③ 批间提交堆积，`git log` 不再等于需求历史。
- **5 Whys**：文档独立落 main ← `github-flow.md` 八阶段只写「PRD 落 docs/prds」「阶段 8 归档」，**未规定文档载体** ← PM 卡 §六/§十三 只管「不 push main」，未管「文档随哪个提交进 main」← 历史上文档无风险（不进测试），无人卡 ← 规则从未定义「一个任务 PR 的边界包含文档」。
- **证据留痕**：本条 PR 自身即首实例（PRD 作为需求分支首提交，无独立 main 文档提交）。

## 二、目标指标

- **北极星**：main 上「文档独立提交数 / 需求」= 0（发布提交内的文档不算独立提交）。
- 预期：新批次 PR diff 的 `docs/` 路径改动占比可核（台账/报告在 diff 内）；单开文档 PR 数 = 0。
- 观测：`git log --oneline main` 中 `docs(<编号>):` 独立提交数（排除发布提交与立项摘要）· `gh pr list` 新增文档 PR 数 · `check` 的 `files` 精确数字。

## 三、范围 / 非范围

- **范围**（4 处机制文本 + 1 处项目上下文，改动全部在本 PR 内）
  1. `.agents/skills/github-flow.md`：原则补「一个任务 PR = 全量改动」；八阶段表「产出」列补文档载体；**新增小节「文档与台账载体（一任务一 PR）」**（BR1–BR5 落条款）；红线 +1；离线降级表补一行（无远端时文档同样随分支）。
  2. `.agents/prompts/product-manager.md`：§六 合并闸门/验收补一条 + §十三 补一条 + 红线 +1；`version` 28→29、`updated` 更新。
  3. `.agents/checklists/pm.md`：交付清单 +1 项、红线 +1（33→34）。
  4. `AGENTS.md`：项目约束「Git 流程」条目追加一句指针（不复制条款）。
  5. `docs/reports/2026-10-28-docs-ride-pr-probe.sh`：一次性只读探针（AC 验证接缝，不进 `tests/`）。
- **非范围**（各带理由）
  - 不改 `.agents/scripts/nao-fleet.sh`：理由 「文档是否随 PR」无法由脚本判定（需读 PR/提交意图），加闸门误报率高，收益不成立（另议可做「main 文档提交计数」只读提示）。
  - 不追改 13 条历史 docs 提交：理由 需改写 main 历史（force-push 共享分支风险），收益仅为美观。
  - 不改 Issue 的 5 个同步节点：理由 与本规则正交（节点管平台同步，本规则管代码/文档载体）。
  - 不改 `.agents/common/release-notes.md` 与 `.github/pull_request_template.md`：理由 只变载体不变写法与结构。
  - 不改 `.agents/templates/tasks-state.md.example`：理由 模板为下游通用骨架，本规则属项目口径（AGENTS.md 承载）。

## 四、用户场景

- **画像 A（用户/维护人）**：`git log main` 每条 = 一个需求，含文档；要回滚整条 `git revert` 即可。
- **画像 B（PM）**：批内台账/报告直接提在需求分支，验收在 PR diff 里一眼见文档变化，无需另开 PR 核对。
- **画像 C（RD）**：squash 合并自动带入 PM 的 docs 提交，不增额外操作。
- **画像 D（接手者）**：`tasks-state` 快照与实现同一提交 → 重开后读到的快照与代码同版本，不会「台账说已交付、代码没到」。
- **关键路径**：立项 → 起分支 → PM 在分支提交 docs → RD 提交实现 → PR 验收（diff 含文档）→ squash（1 条）→ 发布提交（notes/索引/台账收尾）。
- **页面状态**：不适用：无 UI 改动。

## 五、业务规则

- **BR1 一任务一 PR 全量**：任务 PR 必须包含该任务**全部**文件改动 —— 实现 / 测试 / PRD 定稿 / 验收报告 / ADR / `docs/tasks-state.md` / `docs/reports/*-followups.md` / `docs/prds/README.md` 索引 / `docs/releases/<v>.md`。
- **BR2 禁令**：禁止为文档/台账单开 PR；禁止任务期文档作为独立提交直落 main（唯一例外见 BR3）。
- **BR3 立项例外（三条件同时满足才可用）**：① 仅用于「建 Issue / 定分支名所需的最小摘要」；② 内容上限 = TL;DR + AC 编号 + PRD 路径指针（正文仍留 `docs/`，禁抄正文）；③ 单条 `docs(<编号>):` 提交、只含该摘要文件、不与其它改动混提。降级批次（无 Issue）无此例外。
- **BR4 谁提交**：PM 在需求分支做路径级提交（`git add <具体路径>`，`docs(<编号>):` 前缀，**禁 `-A`**、禁 push main）；RD 最终 squash 时一并带入。同 worktree 并行时由提交方只暂存自己的路径。
- **BR5 批间收尾**：合并后产生的事实（npm 核验结果 / Release 标题核验 / 角色卡广播登记 / 会话交接快照）随**发布提交一次带走**；发布提交之后才产生的事实，登记进**下一个任务 PR** 或下一次发布提交，不得单独提交 main。
- **BR6 可读性不变**：PR 标题与 `gh pr merge --squash --subject` 仍须用户可读；文档改动不降低该要求。

## 六、NFRs

- **离线可用**：全部口径在仓内文档与 `AGENTS.md`，无平台依赖；无远端降级时同样在本地分支提交、`merge --squash` 带入。
- **可核性**：验收给 3 条可执行命令（main 上本需求提交计数 / PR diff 是否含 `docs/` 路径 / 工作区干净），无需人工判断意图。
- **不适用**：性能 / 安全 / 并发 —— 理由 纯流程与文档口径，无运行时代码。

## 七、AC

- **验证接缝**：`docs/reports/2026-10-28-docs-ride-pr-probe.sh`（一次性只读 · 不进 `tests/`）+ `nao-fleet.sh check` + `npm test`。
- **AC1（主路径 · 规则单源在位）**：`github-flow.md` 含新小节「文档与台账载体（一任务一 PR）」，正文覆盖 BR1–BR5 五条要点（探针按关键词集合断言，逐条缺一 FAIL）；八阶段表「产出」列体现文档载体；红线新增 1 条（为文档/台账单开 PR 或任务期文档独立直落 main）。
- **AC2（异常 · 禁令四处齐备）**：`product-manager.md` §六、§十三 各含 1 条「文档随任务 PR」禁令；PM 卡红线含 1 条；`checklists/pm.md` 红线含 1 条 + 清单 1 项（4 处 + 清单，缺一 FAIL）。
- **AC3（边界 · 立项例外可判）**：BR3 三条件逐字在位（仅 Issue 建立所需 / 最小摘要三要素 / 单条且不混提），并写明「降级批次无此例外」。
- **AC4（负向闭环 · 探针 + 负控）**：探针在临时 git 仓构造两个反例（① 任务期另开 docs-only 提交直落 main ② 为台账单开独立 PR 的提交序列），按 AC1/AC2 口径判 **FAIL**；正向夹具判 **PASS**；探针 `PASS/FAIL` 精确计数 + 负控 2/2 命中；探针连跑两次输出逐字一致；真仓库零写入（前后 `git status --porcelain` 为空）。
- **AC5（设计一致性 · 版本纪律与门禁）**：`product-manager.md` `version` 28→29 + `updated` 更新；`AGENTS.md` 只有 1 条指针（不复制条款）；`check` rc=0 · `roles=6` · `files=<实测，须报旧→新>`；`npm test` rc=0；角色卡广播 `card pm v29` 已登记（目标会话在线且 idle 才发，否则登记待发）。

## 八、上线闭环

- **灰度**：不适用：文档口径无运行时。
- **监控**：**下批首次执行即验证** —— 下一个任务批次按新规则跑通后，PM 在验收里报「本需求 main 提交数 = 1（+发布提交 1）」。
- **回滚**：`git revert <main-squash-sha>`（单条）。
- **发布**：PATCH **v0.20.1**；`package.json` pin 在发布提交升；tag 指向 main 合并提交；release notes 落 `docs/releases/v0.20.1.md`。**npm 是否重发 = 待拍板 D2**（`.agents/**` 属包内容，本批改了包内文档 ⇒ 倾向重发）。

## 九、变更治理

- **流程**：**T533**（降级批次 `nao/pr-scope` · **无 Issue**；理由：机制维护批次，且本批目的正是取消「文档独立落 main」通道，立项摘要例外在此无意义）→ 分支内提交（PM `docs(T533):` / RD `wip(T533):`，路径级暂存）→ PM 验收 → RD squash（`--subject` 用户可读）→ tag `v0.20.1` + Release。
- **立项载体**：**本 PR 的首提交**（自我示范 BR1/BR4：PRD 与台账登记不再独立落 main）。
- **本批文件归属**：`github-flow.md` / `product-manager.md` / `checklists/pm.md` / 探针 = rd-infra；`AGENTS.md` / 本 PRD / `tasks-state.md` / PR 验收评论 = PM。
- **版本记录**：v0.20.1 = 本批（文档随任务 PR 口径）。
- **Hotfix**：24h 内补单；已 push 的 tag 不删（改发下一个 PATCH）。

## 附录：战略筛子 / RICE / 决策

- **战略筛子**：命中 —— 机制可读性与验收完整性；不做则 main 历史继续与需求脱钩，`main = 1 条/需求` 继续失效。
- **RICE**：Reach 9（6 角色 + 下游 3 仓）× Impact 2（验收看得见文档 / 历史可回滚）× Confidence 0.9 ÷ Effort 0.5 人日 ≈ **32** ⇒ 高优先。
- **D1（用户 2026-10-28）**：范围 = **全部任务文档随 PR**，唯一例外 = Issue 立项所需 PRD 摘要。
- **D2（用户 2026-10-28）**：批间收尾 = **随发布提交一次带走**，其后事实进下一任务 PR 或下次发布提交。
- **D3（用户 2026-10-28）**：提交人 = **PM 在需求分支路径级提交**，RD squash 带入。
- **D4（用户 2026-10-28）**：形态 = **立即小批落地**（本 PRD + Issue/降级 + 机制改 + 发布）。
- **待拍板（开工确认卡）**：npm 是否重发 0.20.1；arch 是否评审（PM 建议跳过，纯流程文本无结构决策）。
