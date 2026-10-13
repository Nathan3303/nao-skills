# PRD：文档模板与格式约定（ADR 结构边界 + 单源 + 索引模板）

- 状态：待用户确认开工 · Owner：PM · 更新：2026-10-14
- 指针：上游 = 用户 2026-10-14 对话（ADR 结构问询 → 选定第 1/3/5 条）· 启动前置：`nao-fleet.sh check` rc=0 files=44
- 优先级：高（机制文档一致性 · 低成本高杠杆）· RICE 结论：≈29（附录）

## TL;DR（≤5 行）

- **做什么**：收敛 ADR 的职责边界、字段口径与索引模板为单一事实来源，并补齐 ADR + ADR 索引两个 `.example` 模板。
- **给谁**：arch-designer（产出 ADR）、PM（评审与归档）、下游三仓（复制模板）。
- **成功标准**：ADR 骨架单源（规范给指针 + 唯一 `.example`）；ADR 不含实施闸门（下沉评审报告）；`check` rc=0 且 `files=46`。
- **不做什么**：不改历史 ADR 正文；不加 `check` 结构校验；不改 60 行上限数值；不改 `init` 落 docs 骨架。

## 一、问题证据

- 实测 7 篇 ADR 行数：85 / 119 / 150 / 154 / 82 / 41 / 60 —— **5 篇超 ≤60 上限，最长 2.5×**，上限形同虚设。
- 5 Whys：上限被突破 ← ADR 兼了「实施闸门 / 接线清单 / 交接单」三类内容 ← 无明确下沉落点 ← 规则只给上限不给职责边界 ← 规范只写「留下 决策/对照/来源」而未列「禁写 / 下沉清单」。
- 单源破坏：`arch-patterns.md` 模板字段（日期 / 状态 / 备选方案）与 `deliverable-docs.md` §二 通用头部（状态 / 更新 / Owner / 指针）不一致；`备选方案` 与 `对照过的备选模式` 语义重叠，多篇只写后者，前者空转。
- 模板缺口：`.agents/templates/` 已有 PRD / tasks-state / 发版说明 / 验收清单 `.example`，**ADR 与 ADR 索引缺失**；`docs/adr/README.md`「决策」列出现 ≈100 字整段结论，违反 §七「单元格 ≤20 字」。
- 证据留痕：`docs/adr/*.md`（行数与章节清点即上表）+ PM 对话结论（本 PRD §一 / 附录）。

## 二、目标指标

- 北极星：**ADR 结构可机械核验** —— 探针断言 0 歧义、0 人工判断。
- 预期：新写 ADR 100% 落在「必写 5 节 + 可选 3 节」骨架内；骨架引用点 = 1（`.example`）；索引列宽违规数 = 0。
- 观测：探针 `PASS/FAIL` 计数 + `check` 的 `files` 精确数字（本批 44 → 46）。

## 三、范围 / 非范围

- **范围**（对应用户选定第 1/3/5 条）
  1. **第 1 条 · ADR 职责边界与下沉落点**：`deliverable-docs.md` §四 增「禁写 / 下沉清单」，明确实施闸门 / 接线清单 / 交接实现细节下沉 `docs/reports/<编号>-arch-review.md`；≤60 行上限保留（靠下沉复位，不放宽数值）。
  2. **第 3 条 · 单源化**：删 `备选方案` 字段；ADR 骨架唯一载体 = `.agents/templates/adr.md.example`；字段口径（状态值域 / 出具日 / 落地版本 / 通用头部 / 修订行）只写 `deliverable-docs.md` §四；`arch-patterns.md` 保留模式对照法 + 指针。
  3. **第 5 条 · 索引模板与列宽**：新增 `.agents/templates/adr.md.example` + `adr-index.md.example`（表头 4 列：日期 / 主题 / 决策 / 状态）；收敛本仓活索引 `docs/adr/README.md`（决策列 ≤20 字）；`architecture-designer.md` §十一 增索引模板指针（含版本 bump + 广播）。
  4. **评审回执（结构契约）**：arch-designer 对「必写 5 节 + 可选 3 节 + 状态值域 + 下沉边界」出具评审回执；若其判定需落 ADR（arch 卡 §十一 红线），随批次落 `docs/adr/2026-10-14-adr-structure-contract.md` —— 该文件同时作为新骨架的**首实例**（AC1 增一项实证）。
- **非范围**（各带理由）
  - 不改 7 篇历史 ADR 正文：理由 `deliverable-docs.md` §七「不追溯改写历史文档」。
  - 不加 `check` 的 ADR / PRD 结构校验：理由 需动 `check_eol` / 工具面并带回归，另开下批（第 6 条）。
  - 不改 `nao-skill init` 落 docs 骨架：理由 涉 CLI 与安装面，另开下批（T1）。
  - 不改 PRD / tasks-state 现有模板内容：理由 本批聚焦 ADR，二者补齐另批。
  - 不删 `arch-patterns.md` 模式对照表与检索纪律：理由 与 ADR 骨架职责不同，保留。

## 四、用户场景

- 画像 A（arch-designer）：评审终签 → 复制 `templates/adr.md.example` 填必写 5 节，实施闸门另存评审报告。
- 画像 B（PM）：验收读 ADR → 探针核「必写节齐 / 来源在 / 索引列宽合规」，无需逐篇人眼判。
- 画像 C（下游三仓 PM）：从包内模板复制 `docs/adr/` 骨架与索引，无格式漂移。
- 关键路径：选定结构 → 复制模板 → 填空 → 探针校验 → 索引登记一行。
- 页面状态：不适用：文档改动无 UI。

## 五、业务规则

- **BR1 单源**：骨架正文只在 `.example`，规范只在 `deliverable-docs.md`，其余位置只给指针（禁双写）。
- **BR2 不追溯**：历史 ADR 正文不改；仅活索引 `docs/adr/README.md` 按新列宽收敛（信息不丢：短结论 + 行内链接）。
- **BR3 边界优先于上限**：ADR 不含实施闸门 / 接线清单 / 交接实现；超长先下沉，不放宽 60 行上限。
- **BR4 状态值域**：`提议` / `已接受（待落地）` / `已接受（已落地 vX.Y.Z）` / `已废弃（被 <yyyy-mm-dd-slug> 取代）`（本仓 ADR 无编号，禁用 `ADR-N` 写法）。
- **BR5 卡片版本纪律**：改 `architecture-designer.md` 必须 bump `version` + `updated`，并广播 `card arch-designer v12`。
- **BR6 格式禁令**：ADR 正文默认不用表格（§七）；索引属「需被解析的结构化清单」例外，仅 4 窄列。
- **BR7 索引原子性**：索引「决策」列 ≤20 字，细节一律在 ADR 正文。

## 六、NFRs

- 离线可用：全部指针为仓内相对路径或 `@.agents/...` 锚点，无外链依赖。
- 可核性：探针只读且幂等（连跑两次输出逐字一致）。
- 不适用：性能 / 安全 / 并发 —— 理由 纯文档改动，无运行时代码。

## 七、AC

- 验证接缝：`docs/reports/2026-10-14-T520-doc-contract-probe.sh`（一次性 · 不进 `tests/`）+ `nao-fleet.sh check`（**QA 确认待回执**）
- AC1（主路径 · 骨架单源）：`.agents/templates/adr.md.example` 存在，含**必写 5 节**（`## 背景` / `## 决策` / `## 理由` / `## 对照过的备选模式` / `## 参考来源`）与**可选 3 节**（`## 后果与风险` / `## 限制与已知边界` / `## 相关指针`），全序 = 背景 → 决策 → 理由 → 对照过的备选模式 → [后果与风险] → [限制与已知边界] → [相关指针] → 参考来源（参考来源恒末）；头部恰 4 字段（状态 / 更新 / Owner / 指针）；**不含** `备选方案` 字段；`deliverable-docs.md` §四 与 `arch-patterns.md` 均含指针 `templates/adr.md.example`。
- AC1-探针口径：必写 5 必在；`## ` 标题集合 ⊆ 上述 8 个；顺序单调；禁用词（`实施闸门` / `接线清单` / `交接` / `备选方案`）命中 = FAIL —— 扫描范围 = `adr.md.example` **正文非注释行**（`<!-- -->` 与 `⛔` 行除外）+ `arch-patterns.md` 的 `## ADR 模板` 段；首实例 ADR 套同一组断言（新增件 ≤60 行 = `wc -l`，历史 7 篇不追溯）。
- AC2（异常 · 职责边界）：`deliverable-docs.md` §四 含下沉条款且给出落点 `docs/reports/<编号>-arch-review.md`；节序与 arch 定稿一致；「对照模式表」改称 **「对照模式清单」**（BR6 禁表）；`arch-patterns.md` 的 `## ADR 模板` 段不再出现「实施闸门 / 接线清单 / 交接」示例节。
- AC3（边界 · 索引模板与列宽）：`.agents/templates/adr-index.md.example` 存在且表头恰 4 列（日期 / 主题 / 决策 / 状态）；`docs/adr/README.md` 仍 4 列、决策列单元格 ≤20 字（探针给最大值）；`architecture-designer.md` §十一 含索引模板指针。
- AC4（负向闭环 · 不追溯 + 门禁）：本批 diff 在 **既有 7 篇** `docs/adr/2026-*.md` **零命中**（`README.md` 按 AC3 收敛、评审所需**新增** ADR 不算违规）；`check` rc=0 且 `files=46`；`npm test` rc=0；`tests/t4/run.sh` 12/12；工作区干净。负控：历史 ADR 被改或 `files` ≠ 46 → FAIL。
- AC5（设计一致性 · 版本纪律）：`architecture-designer.md` version 11 → 12、`updated` 更新；`check` roles=6 通过；广播 `card arch-designer v12` 已发（回执记录收件方）。

## 八、上线闭环

- 灰度：不适用：文档改动无运行时。
- 监控：探针 PASS 计数 + `check` / `npm test` 精确数字（回执核对）。
- 回滚：`git revert <main-sha>`（单条 squash 提交）。
- 发布：PATCH **v0.17.2** —— tag 指向 main 合并提交；**npm 不重发**（包运行面与 0.17.x 无差异，沿用用户既有口径）。

## 九、变更治理

- 正式流程：降级分支 `nao/doc-templates`（机制维护批次 · 无 Issue）→ `wip(T520):` 检查点 + 路径级暂存（禁 `-A`）→ PM 验收通过后 RD squash 合并（`--subject` 用户可读）→ tag v0.17.2 + Release。
- 立项提交：PM docs-only 直落 main（本 PRD + tasks-state 台账），沿用 T519 实践。
- 版本记录：v0.17.2 = 本批（ADR 结构边界 + 骨架单源 + 索引模板）。
- Hotfix：24h 补单；已 push 的 tag 不删（改发下一个 PATCH）。

## 附录：战略筛子 / RICE 结论

- 战略筛子：**命中** —— 机制一致性与文档可读性；不做则 ADR 继续膨胀、字段继续双源。
- RICE：Reach 9（6 角色 + 下游 3 仓 PM）× Impact 2（结构清晰度）× Confidence 0.8 ÷ Effort 0.5 人日 ≈ **29** ⇒ 高优先 / 低成本。
- 打分过程不展开；依据即 §一 实测数据与本 PRD 范围。
- **arch 结构定稿（2026-10-14 · `done(full)` · 报告 `docs/reports/2026-10-14-T520-arch-review.md`）**：D1 **采纳**（改「被 `<yyyy-mm-dd-slug>` 取代」）· D2 **采纳**（头部保 4 字段，出具日 = 文件名日期、落地版本 = 状态值，均不单设字段）· D3 **采纳**（补「限制与已知边界」可选节）—— 三项均属 PM 文档口径范围，已由 PM 裁量并回执 arch。
