# 机制批：fix 通道 + Issue 受理（本地开发工作流）

> 日期：2026-11-03 · 分支：`feat/72-fix-channel-triage`（Issue [#72](https://github.com/Nathan3303/nao-skills/issues/72)）· 不单独发版（随下次发布进 release notes）

## 一、问题证据

- **证据 1（用户反馈，2026-11-03）**：机制只有一条通道 —— `product-manager.md` §二 要求任何任务都产 9 模块 PRD、`checklists/pm.md` 44 项全量核；修一个本地 bug 的仪式成本高于修复本身。
- **证据 2（机制取证）**：`.agents/skills/github-flow.md:47` 只有 `feat/<issue-id>-<slug>` 与 `hotfix/<issue-id>` 两种命名，**无日常 `fix/` 通道**；`hotfix` 语义偏线上（`docs/...` 只见命名，未定义切分支基线）。
- **证据 3（机制取证）**：Issue 现为**输出物**（PM 立项后建 Issue 写摘要，`github-flow.md` 八阶段第 1 步）；**无输入侧受理**——他人/线上转来的 bug 报告没有入口，也没有 `triage` 动作。
- **证据 4（用户澄清，2026-11-03）**：「生产部署方面不归舰队管」——但**线上暴露的问题要能作为 Issue 来源进来**。即舰队负责「问题 → 分流 → 修 → PR → 合并 → 发版」，不负责部署、灰度、监控、线上回滚、MTTR。
- **5 Whys**：为什么修 bug 重？→ 因为没有第二通道。为什么没有第二通道？→ 因为机制按「批次 = 需求」建模不动点，Volume 小的修复也被要求完整立项。为什么 Issue 不能当输入？→ 因为反双源红线要求正文留 `docs/`，而外部报障正文天然在平台。⇒ 根因 = **缺「任务性质」这一维**，不是缺流程细节。

## 二、目标指标

- **北极星**：同类小修复（≤ 3 文件、无契约变化）从「提出 → 合并」的**人工确认轮次**由现状 3–4 轮（立项 / 开工卡 / 验收 / 合并）降至 **2 轮**（受理确认 / 合并授权）。
- **辅助指标**：`fix` 任务的 PRD 文档体积从 9 模块降至 3 字段；`checklists/pm.md` 的 `fix` 核对项 ≤ 8 条；机制常驻 token 增量 ≤ 15 行（仅 PM 卡）。

## 三、范围 / 非范围

**范围（4 个机制文件 + 1 台账）**

- `.agents/skills/github-flow.md`：新增八阶段之前的「阶段 0 受理（被动触发）」；分支命名补 `fix/<issue-id>-<slug>`；补「通道分流判据」；补「输入侧 Issue 与反双源边界」。
- `.agents/prompts/product-manager.md`：§二 补 `fix` 通道豁免（3 字段替代 9 模块）；§十三 把 Issue 职责从「输出物」扩为「输入 + 摘要」双职并补 triage 三问；**bump `version` + `updated`**（31 → 32）。
- `.agents/checklists/pm.md`：`fix` 通道**深度裁剪**（核 5–8 项，不删条目；其余标注「仅 feat」）。
- `.agents/templates/github/issue_template_bug.md.example`、`issue_template_feature.md.example`：两份新模板（与现有 PR 模板同一分发方式：PM 复制到项目 `.github/ISSUE_TEMPLATE/`）。
- `docs/tasks-state.md`：登记本批（随本 PR）。

**非范围**

- 不动 `nao-fleet.sh` / `bin/nao-skill.js`：**不新增自动安装逻辑**，Issue 模板沿用「PM 复制」的既有做法（与 PR 模板一致）。
- 不做 Issue 标签自动化、不做 webhook / 轮询 / 定时扫描（机制零网络，`triage` 只在被触发时执行一条 `gh issue list`）。
- 不接管生产部署、灰度、监控、线上回滚、MTTR、SLA（**显式 out-of-scope**，写进 `github-flow.md` 以免日后回潮）。
- 不改 `qa` / `rd-*` 角色卡。

## 四、用户场景

- **场景 1（对话报 bug）**：用户在 PM 会话说「导出 CSV 少了一列」。PM 判「期望 vs 实际」可写出 ⇒ `fix` 通道，一句话确认后派 RD，PR 带红色→绿色用例，回执 lite，PM 验收后 ask-me 授权合并。
- **场景 2（GitHub Issue 报 bug）**：用户说「看一下 Issue #88」。PM 执行 `gh issue list`/`gh issue view`，按 triage 三问判定：是 bug（有复现）→ 摘录进 `docs/tasks-state.md` 并以 Issue 号回链 → 走场景 1。
- **场景 3（Issue 其实是需求）**：Issue 描述「希望支持导出 Excel」且无法写出「期望 vs 实际」⇒ **不降级**，回 `feat` 通道（全量 PRD + 开工确认卡）。
- **场景 4（线上故障转来）**：Issue 带「受影响版本 v1.4.2」。舰队只做两件事：`fix` 分支从该 tag 切出、修复后回合 main；**观测、灰度、回滚阈值不在本机制内**。

## 五、业务规则

- **R1 分流判据（唯一）**：默认 `fix`；**硬条件 = 能写出「期望行为 vs 实际行为」且可复现**。写不出、或「改变用户可见行为 / 新增能力 / 破坏性契约」⇒ 升 `feat`。
- **R2 分支**：`fix/<issue-id>-<slug>`；无 Issue 时仍走 `nao/<批次-slug>` 降级；线上补丁需从**受影响版本 tag** 切出（R1 之外的唯一 tag 场景）。
- **R3 受理触发（被动）**：`triage` 只在两种时机执行 —— 用户明确要求看 Issue，或 PM 在对话中被指向具体 Issue 号。**不轮询、不常驻、不建后台任务**。
- **R4 triage 三问**：① 能否写出「期望 vs 实际」且可复现？② 来源是哪（用户 / QA / 线上 / 自查）？③ 是否影响已发布版本（影响则记版本 tag）？三问任一不能判定 ⇒ 挂起并回问用户，不猜。
- **R5 反双源（输入侧例外）**：外部 Issue 的**原始报告正文留在平台**（它是证据，不是规格）；PM triage 后**摘录成 `docs/tasks-state.md` 任务条目并以 Issue 号回链**；凡进入 `docs/prds/` 的规格正文仍只写一处。⇒ 与既有「Issue 不抄正文（输出侧）」不冲突，两者按「输入 / 输出」区分。
- **R6 `fix` 通道减负**：免 9 模块 PRD，改 **3 字段**（现象 / 复现 / 回退）；开工确认卡降为**一问**（「现在修吗」）；回执用 `lite`；复盘默认 `L0` 一行。
- **R7 `fix` 通道不减免的底线**（4 条）：先写可失败用例再修 · diff 只碰修复路径（禁夹带重构/格式化）· `git revert <sha>` 可干净回退（数据/契约类在 Issue 里 3 行写影响面）· 非作者复核（QA 或另一会话；单人项目允许「作者自审 + 写明理由」留痕）。
- **R8 不可逆动作仍须人工确认**：合并 main、打 tag、发 npm、破坏性契约、删文件/数据 —— 一律 `ask-me`，`fix` 通道**不豁免**该闸门。

## 六、NFRs

- **零网络**：`triage` 只用既有 `gh` 调用（`gh issue list/view`），不引入轮询、webhook、后台进程；离线时降级为「用户口述 Issue 内容」并留痕。
- **token 预算**：常驻增量只落在 PM 卡 ≤ 15 行；其余进按需读取的 `github-flow.md` / `checklists/pm.md`。
- **可判定性**：分流判据必须能被第三方按文字判定（R1 的硬条件），不得出现「视情况」。
- **门禁不降级**：`check`（含角色卡 version 校验）+ `npm test` 必须 rc=0；`fix` 通道减的是**仪式**，不是门禁。

## 七、验收标准（AC）

- **AC1 分流可判定**：`github-flow.md` 出现且仅出现一处「通道分流判据」，含硬条件「能写出期望 vs 实际且可复现」，并与 `feat` 升级条件并列；`fix/<issue-id>-<slug>` 与 `feat/` 命名并列出现。
- **AC2 受理是 0 阶段且被动**：`github-flow.md` 的流程序列含「阶段 0 受理」，明确触发条件为**被动**（用户要求 / 被指向 Issue 号），并显式写「不轮询、不常驻」。
- **AC3 fix 减负落地**：`product-manager.md` §二 写 `fix` 免 9 模块 + 3 字段；开工确认卡降为一问；回执 `lite`。§十三 写 Issue「输入 + 摘要」双职 + triage 三问。
- **AC4 双源边界无冲突**：`github-flow.md` 明确「输入侧 Issue 正文留平台 + 摘录回链」与「输出侧 Issue 不抄正文」并存，读者能按一句判据区分二者。
- **AC5 模板可用**：两份 example 存在，`bug_report` 含 现象 / 期望 vs 实际 / 复现步骤 / 影响版本 / 来源；`feature_request` 含 场景 / 期望 / 价值；顶部注释给出安装路径 `.github/ISSUE_TEMPLATE/`。
- **AC6 清单深度裁剪**：`checklists/pm.md` 有 `fix` 通道小节，核对项 **5–8 条**，其余条目标注「仅 feat」；**清单总条数不减少**（只在既有条目加通道标注 / 新增小节）。
- **AC7 门禁与版本纪律**：`bash .agents/scripts/nao-fleet.sh check` rc=0 · `npm test` rc=0 · PM 卡 `version` 31 → 32 且 `updated` 为 2026-11-03 · 广播记录（`card product-manager v32`）落台账。

## 八、上线闭环

- 不涉及部署。合并后随下次发布进 release notes（面向用户一句话：修 bug 不再需要写完整 PRD）。
- 观察项（合并后 30 天）：`fix` 任务是否出现「需求伪装成 bug」；若出现 ≥2 次，收紧 R1 判据并在复盘登记。

## 九、变更治理

- **冻结点**：本 PRD 定稿（开工确认卡确认时）。冻结后新增要求须重开确认卡，不在实施中夹带。
- **裁定权**：口径冲突由 PM 裁定并留痕；涉及机制语义（如与 `feat` 通道重叠）转 `arch-designer` 评审。
- **回退**：单条 squash 提交，`git revert` 即整批回退；无迁移、无数据影响。
