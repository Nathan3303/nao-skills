<!-- ADR 首实例（T520）：同时作为 `.agents/templates/adr.md.example` 的结构实证（AC1）。 -->

# ADR：ADR 结构契约（骨架单源 / 状态值域 / 职责下沉）

- 状态：已接受（待落地 v0.17.2）
- 更新：2026-10-14
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-14-doc-templates-convention.md` · 评审报告 `docs/reports/2026-10-14-T520-arch-review.md`

## 背景

- 7 篇 ADR 实测 41–154 行，5 篇超 ≤60 上限（最长 2.5×）；章节标题存在「编号 / 无编号」两套。
- 根因：ADR 兼收实施类内容（闸门 / 清单 / 实现细节），且存在语义重叠的旧备选字段，长期空转。
- 约束：纯文档改动、不追溯历史正文、不改 `check` 工具面、不新增编号体系。

## 决策

采用固定骨架「必写 5 节 + 可选 3 节」（标题逐字、不编号、顺序固定），唯一载体 `.agents/templates/adr.md.example`；实施类内容下沉评审报告；状态取四值域，头部四项，`出具日` 与 `落地版本` 不单设字段。

## 理由

1. 业务匹配：标题逐字 + 白名单 + 顺序即可机械核验，探针 0 人工判断。
2. 成熟度：与 Nygard 的 Context / Decision / Status / Consequences 同源，仅裁冗余节。
3. 团队能力：复制 `.example` 填空即合规，6 角色与下游 3 仓无需新工具。
4. 成本：改 3 个文档 + 2 个 `.example`，人日级；下沉后行数自然复位。

## 对照过的备选模式

1. **维持现状（自由式章节）** —— 适用：单作者、低频改；代价：5/7 超限、字段双源；不采纳：本仓 6 角色 + 3 下游仓复制。
2. **MADR 全量模板（含 `考虑过的方案` / `决策驱动`）** —— 适用：外部评审密集；代价：字段多、与现有 9 模块体系重复；不采纳：旧备选字段的双源问题未解。
3. **放宽 ≤60 行至 150 行** —— 适用：决策本身复杂且拒绝下沉；代价：上限失效、不可核验；不采纳：证据显示超限源于越界而非复杂度。

## 后果与风险

- 正面：骨架单源、探针可断言、索引列宽收敛；负面：存量 5 篇超标 ADR 不追溯，保留原样归档。
- 风险：机械核验误伤（标题微调即 FAIL）→ 以「白名单外标题 = FAIL」正向验收，改骨架走本文修订。

## 限制与已知边界

- 仅对**新写 / 新改** ADR 生效；历史 7 篇正文不改（`deliverable-docs.md` §七「不追溯改写历史文档」）。
- 只校验节标题 / 顺序 / 字段，不校验正文语义，也不校验 ADR 编号与数量。
- `已废弃` 的被取代者以**文件名**指称（本仓不引入 `ADR-N` 编号）。

## 相关指针

- 骨架：`.agents/templates/adr.md.example` · 索引骨架：`.agents/templates/adr-index.md.example`
- 规范口径：`.agents/checklists/deliverable-docs.md` §四 · 模式对照法：`.agents/skills/arch-patterns.md`

## 参考来源

- [Architectural Decision Records (ADRs)](https://adr.github.io/) · 访问 2026-10-14 · ADR 定义与多模板对照（MADR / Y-statement）。
- [Documenting Architecture Decisions](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) · 访问 2026-10-14 · Nygard 四段式与状态值 proposed / accepted / deprecated / superseded。
