# PRD：to-spec 改造引入——PM 规格生产方式（验证接缝 + 对话综合）

- 状态：待用户开工确认（PRD 已定稿 2026-10-14）· Owner：PM
- 指针：上游技能 `devcxl/mattpocock-skills-zh` → `skills/engineering/to-spec/SKILL.md`（访问 2026-10-14）· 写法规范 `@.agents/checklists/deliverable-docs.md` §三 · 项目约束 `AGENTS.md`

## TL;DR（≤5 行）

- **做什么**：为 PM 引入 to-spec 的**两个增量**——①「验证接缝」先行（写 PRD 前先定可测接入点）；②「对话综合」入口（已有 grill 结论/原型/ADR 时直接成稿，不重复盘问）。产出物仍是 PRD 正文。
- **给谁**：nao 舰队 PM / QA 会话（nao-skills 本仓机制）；下游 = 所有使用舰队的项目的 PM 行为。
- **成功标准**：成熟需求零重复盘问；含行为改动的 PRD 100% 带「验证接缝」行且与 QA 用例范围一致；PRD 保持「路径无关」（看不出由哪条路径产出）。
- **不做什么**：不写「实现决策 / 测试决策」正文（改为指针）；不引入 `spec` 并列术语与标签体系；不动 RICE / 开工闸门 / Issue 摘要口径 / `nao-fleet.sh` / `tests/`。

## 一、问题证据

- 现状：PRD 与 QA 用例之间**没有显式的验证接入点约定**——接缝由 QA 在派发后才隐式决定（`test-design.md` 的 DDD 分层表），AC 可测性与用例范围脱节。
- 现状：PM 只有「模糊 → 强制 grill-me」一条路，缺「已充分」的判定与捷径 ⇒ 已给过 grill 结论/原型/ADR 的需求仍可能被重复盘问（无效澄清轮次）。
- 现状：用户无法显式触发「写规格」动作，本轮讨论「收口」无信号。
- 5 Whys 摘要：为何验收口径易漂 → 验证接入点派发后才定 → 为何 → 接缝从未显式化 → 为何 → PRD 只承接需求、不承接可测性 → 结论：需在 PRD 阶段显式产出「验证接缝」。

## 二、目标指标

- 本批后**新 PRD**：含行为改动的批次 **100%** 带「验证接缝」行（不适用则写「不适用 + 一行理由」）。
- 成熟需求（已有 grill 结论 / 原型 / ADR）**重复盘问轮次 = 0**（以 PRD 头部指针 + 回执可核）。
- 「路径无关」判据通过率 **100%**（第三方按清单逐条可核）。

## 三、范围 / 非范围

**范围内**

- 新增 `.agents/skills/pm-to-spec.md`：成熟度判定 · 接缝步骤 · 对话综合流程 · 上游 7 节 → 9 模块映射 · 缺口检查 · 路径无关判据。
- `.agents/prompts/product-manager.md`：按需技能 +1 行、§二 补入口分支一句、version 23→24 + 广播。
- `.agents/skills/pm-grill.md`：补「需求成熟度判定」（与综合入口口径一致）。
- `.agents/prompts/test-engineer.md` + `.agents/checklists/qa.md`：补「接缝确认 = QA 在 PRD 阶段的输入（PM 列候选 / QA 确认）」；qa 卡 version 13→14 + 广播。
- `.agents/checklists/pm.md`：交付清单加「接缝候选已列并经 qa 确认（不适用注明）」「路径无关判据已核」。
- `.agents/checklists/deliverable-docs.md`：§三 补「非范围必带理由」+ PRD 模板登记进文档类型表。
- 新增 `.agents/templates/prd.md.example`（头部 + TL;DR + 9 模块 + AC 占位）。
- 项目根 `AGENTS.md`：项目约束补一行「需用户确认的问题一律用 ask-me 提问」（用户 2026-10-14 口头约束，即时落盘）。

**非范围**

- 不写「实现决策 / 测试决策」正文 —— 理由：PM 越界红线（@.agents/skills/pm-routing.md §二）且与 arch/qa 职责重复；派发协议要求 worker 自读源码，PRD 无需承载实现细节 ⇒ 改指针。
- 不做宿主层斜杠命令 / pi skill 分发 —— 理由：nao 无 commands 机制；本批不引入宿主安装侧改动，且分发面已实测无需注册。
- 不引入 `spec` 并列术语 —— 理由：避免同物两名、术语双源导致验收口径漂移（领域词汇里 PRD 已占位）。
- 不建 `ready-for-agent` 标签体系 —— 理由：与开工确认闸门语义冲突（打标签即派工）；本批只降级为状态语义，标签治理另议。
- 不动 RICE / 战略筛子 / 开工确认闸门 / Issue 摘要口径 —— 理由：均为既有验收闸门，本批只加「生产方式」，不改闸门。
- 不动 `nao-fleet.sh` 与 `tests/` —— 理由：本批无执行面（纯机制文档）；改脚本/用例需回归成本，收益不抵，且已由 QA 一次性探针覆盖。
- 不追溯改写历史 PRD —— 理由：@.agents/checklists/deliverable-docs.md §七「不追溯改写历史文档」，避免无谓 diff 与破坏归档。

## 四、用户场景

- **成熟需求**：用户说「写 spec / 执行 to-spec」→ PM 判成熟（有 grill 结论或原型或 ADR）→ 不盘问 → 列接缝候选 → QA 确认 → 缺口检查 → 出 PRD。
- **不成熟需求**：同入口 → 判定不通过 → 回落 grill 五层追问 → 追问后再综合。
- **缺口场景**：目标指标 / NFRs / 上线闭环 / 变更治理在上下文里无依据 → 逐条列出 → 定点补产，缺口清空前不出稿。
- **QA 视角**：收到接缝候选 → 确认或修正（可改为更高/更少接缝）→ 回执；用例按确认后的接缝组织。

## 五、业务规则

- **成熟度判定（4 条，任一命中即可走综合）**：① 已有 grill 结论；② 已有原型/设计稿；③ 已有 ADR 或架构评审回执；④ 用户明示「讨论已充分」。**一条都不命中 → 仍走 grill**，不跳过。
- **接缝规则**：理想 1 个接缝；优先复用已有接缝；能高不高低；**PM 只列候选，QA 确认**；结论写入 PRD「七、AC」首行。
- **产出物单一名**：产出物一律叫 **PRD**（禁用 `spec` 作为并列术语）；格式 = 头部 + TL;DR + 9 模块。
- **路径无关判据（验收可核）**：头部齐 · TL;DR ≤5 行 · 9 模块无空 · AC 逐条 Given/When/Then + 五覆盖 · 非范围含理由 · 战略筛子 + RICE 结论在 · 正文无表格 · ≤150 行 · 落 `docs/prds/` 且索引更新 · Issue 只有摘要 + 指针。
- **版本纪律**：改 PM 卡与 qa 卡各 bump version + 广播 `card pm v24` / `card qa v14`。

## 六、NFRs

- **常驻上下文预算**：PM 卡为常驻注入，本批卡内增量 ≤3 行，其余内容一律放按需技能（避免挤占常驻预算）。
- 无新增依赖、不动构建与脚本；门禁沿用 `check` + `npm test`。
- 兼容性：不破坏既有 9 模块验收闸门；历史 PRD 不追溯改写。

## 七、AC

- **验证接缝（QA 确认 2026-10-14）**：docs 层「**文档审计 + 全范围门禁**」单接缝 + 复用 `check` 现成断言 + 一次性只读探针；解析级补强 = **卡 version 精确值**（`check` 只查整数，不查 ==24/14）。分发面由临时目录安装探针另行核对。
- AC1（主路径·技能）：Given 本批落地，When 打开 `.agents/skills/pm-to-spec.md`，Then 含成熟度判定 4 条、接缝步骤、7 节→9 模块映射（列表形式）、缺口检查、路径无关判据。
- AC2（主路径·PM 卡）：Given 改卡，When 检查 `product-manager.md`，Then 按需技能含 `pm-to-spec.md`、§二 含入口分支、version=24、updated=2026-10-14，且广播 `card pm v24` 留痕。
- AC3（主路径·grill 不冲突）：Given 打开 `pm-grill.md`，When 读触发口径，Then 明确「成熟度判定命中时不触发」，且与 `pm-to-spec.md` 无相互矛盾表述。
- AC4（主路径·QA 归属）：Given 改 qa 侧，When 检查 `test-engineer.md` 与 `checklists/qa.md`，Then 含「接缝确认 = PRD 阶段输入」、qa 卡 version=14 且广播留痕。
- AC5（主路径·清单与模板）：Given 改清单与模板，When 检查 `checklists/pm.md`、`deliverable-docs.md` §三、`templates/prd.md.example`，Then 交付项含接缝与路径无关两条、§三 含「非范围必带理由」、模板含头部 + TL;DR + 9 模块 + AC 占位且不含表格。
- AC6（异常·缺口回落）：Given 一份缺「目标指标/NFRs/上线闭环/变更治理」的上下文，When 执行综合流程，Then 先输出缺口清单并回落 grill/定点补产，**不得**直接出稿。
- AC7（边界·负向）：Given 本批 diff，When 核对边界，Then 未引入实现/测试决策正文、未引入 `spec` 并列术语、未新建标签、未改 RICE/开工闸门/Issue 口径、未改 `nao-fleet.sh` 与 `tests/`、未改历史 PRD。（禁 `spec` 术语探针**限定本批改动文件**：全仓扫会命中 `nao-fleet.sh` 的 `spec` 变量名，属假阳性。）**语境豁免**：探针命中「禁用声明 / 反模式」语境视为合规（非并列术语使用）。
- AC8（负向闭环）：Given 某 PRD 的接缝与 QA 用例范围不一致，When PM 验收，Then 打回并要求对齐后重新验收（不得带不一致合入）。
- AC9（设计一致性·自证 + 门禁）：Given 本 PRD 自身，When 按路径无关判据核验，Then 逐条通过，且 `check` rc0 + `npm test` rc0。（第 9 条「索引更新」为**归档时点**闭合项：既有一贯做法是在闭环提交中登记索引（见 `docs/prds/README.md` 首行语义），立项 / 开发期不登记。）

## 八、上线闭环

- 发版：机制能力新增（feat）⇒ **MINOR**（v0.17.0，随下批）；tag 指向 main 合并提交。
- 回滚：纯文档改动，`git revert` 合并提交即恢复；删 `pm-to-spec.md` + 卡 version 回退即退回原流程。
- 监控：后续批次 PRD 是否带「验证接缝」行；成熟需求重复盘问轮次（观察项，不设强制指标）。

## 九、变更治理

- 变更人：PM（机制文档**内容**定稿）；落地执行 = `rd-infra`（写文件 / 门禁 / 交叉引用校验）。
- 用户拍板留痕（2026-10-14，ask-me 确认单）：**D1** 采用范围 1B（只取接缝 + 综合）· **D2** 关系 2A（to-spec = PRD 生产方式）· **D3** grill 条件化 · **D4** 落点 4A（正文 `docs/prds/`，Issue 只放摘要指针）· **D5** 优先级 5A（保留 RICE + 战略筛子，`ready-for-agent` 降级为状态语义）· **D6** 派生项全部按建议（接缝归 QA / 纯技能 md / 命名 `pm-to-spec.md` / 路径无关入 AC / 非范围带理由入 deliverable-docs / 新增 PRD 模板 / 分工如上）。
- 产品约束即时落盘：用户 2026-10-14 要求「需用户确认的问题一律用 ask-me」→ 写入项目 `AGENTS.md` 项目约束。
- bump：`card pm v23→v24` · `card qa v13→v14` + 广播；历史文档不追溯改写。

## 附录：战略筛子 / RICE 结论

- 战略筛子：**通过**——与「机制单一事实来源 / 省 token / 减少无效澄清轮次」一致，不新增并行体系。
- MoSCoW：**Should**（用户明示引入）。
- RICE：Reach 中（所有使用舰队的项目 PM 行为）· Impact 中（AC 可测性与澄清轮次）· Confidence 高（上游已实践 + 本仓流程已逐条核对）· Effort 小（纯文档）⇒ **优先级高**。
- 打分过程不展开；明细见本文件与 `docs/tasks-state.md` 决策留痕。
