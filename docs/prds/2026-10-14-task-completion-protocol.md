# 任务完成协议（DoD + 遗留项三出口 + 分级复盘）

- 状态：**已交付并发布（v0.18.6 · PR #47 squash `3e98f0d` · 归档 2026-10-27）** · Owner：PM · 更新：2026-10-27
- 指针：Issue [#46](https://github.com/Nathan3303/nao-skills/issues/46) · 触发事件 = 2026-10-14 `pi update --extensions`（4 漏洞 + 1 待批 install script，命令 exit 0、无任何收口要求）· 现有闸门 @.agents/skills/pm-operations.md · 回执模板 @.agents/checklists/comm-templates.md

## TL;DR

- **做什么**：抽一层与「派发→回执→验收→合并」正交的**任务完成协议**——DoD 四类骨架 + 维护型补充判据 + 遗留项三出口 + 分级复盘。
- **给谁**：PM（主执行者）+ rd-infra（维护型动作执行者）；下游项目经广播继承。
- **成功标准**：任务收尾时遗留项 100% 有出口与 owner；「`exit 0` 即完成」判定 0 次（抽查 ≥3 批）。
- **不做什么**：不改 `nao-fleet.sh`（不新增脚本硬门禁）· 不加常驻第 7 角色 · 不改 GitHub Flow 阶段。

## 一、问题证据（5 Whys 摘要）

- **现象**：依赖更新类动作 exit 0 后，4 个漏洞告警（high: `zod <4.6.6`）与 1 个待批 `postinstall`（`esbuild@0.28.2`）无人处置即结束。
- **Whys**：告警只打印不落盘 → 无落盘要求因为 DoD 只存在于交付链路（PRD/AC）→ 维护型动作无 PRD → 机制只服务「需求交付」→ **根因：缺少与交付链路正交的完成协议，且回执模板无「遗留项」字段**。
- **旁证**：`grep "遗留\|残差\|未决" .agents/checklists/comm-templates.md` = 0 命中；`done(lite)` 单行模板无任何未决项入口。
- **证据口径**：本仓近 20 批 `tasks-state` 的「残差 / 遗留项」均为事后补写（非闸门产出）。

## 二、目标指标

- **遗留项收口率**：任务收尾时三出口明确 = 100%（当前无定义，视作 0%）。
- **判定违规次数**：「输出有 warn/error 却判完成」= 0（PM 抽查，每批 1 次）。
- **同类复发**：完整复盘（L1）记入的问题连续 2 批不复发。
- **token 增量**：常驻卡 ≤ +2 行/张；按需技能 ≤ 80 行（`wc -l`）。

## 三、范围 / 非范围

范围内：

1. 新增按需技能 `.agents/skills/task-completion.md`（协议单一载体）。
2. `comm-templates.md` 两处回执模板加 `遗留：` 字段。
3. PM 卡 v25→v26、rd-infra 卡 v2→v3（条款 + 指针）。
4. `checklists/pm.md` 交付清单 +2、红线 +1；`AGENTS.md` 项目约束 +1 行。
5. 回溯演练一份（用本次 `pi update` 事件走完协议，作可用性证明）。

非范围（每条带理由）：

- **不改 `nao-fleet.sh` / 不加 rc≠0 硬阻断**：理由 = 本批形态拍板为纪律条款（E0），脚本校验成本另议（§九 E1）。
- **不加常驻第 7 角色（如 reviewer）**：理由 = 复用既有 PM/QA 职责，避免舰队常驻成本与广播面膨胀。
- **不改 GitHub Flow 阶段与合并权**：理由 = 已完成形态的样板，本批只补「任务收尾」一段。
- **不追溯改写历史 PRD/报告**：理由 = `deliverable-docs.md` §七 明令不追溯，避免无谓 diff。
- **不建 Issue 平台级 backlog 集成**：理由 = 轻量台账已拍板；Issue 仅在超阈值时用（BR5）。

## 四、用户场景

- **场景 A（维护型 · 本次事件）**：用户贴外部命令输出 → PM 逐条归类每个 warn/error/待批 → 出「待决卡」给用户拍板 → 结论落台账 → 任务才可关闭。
- **场景 B（交付型 · 常规批次）**：PRD 定稿 → 开工确认卡实例化 DoD → 派发 → 回执含 `遗留：` → PM 验收时核对出口 → 归档时遗留项进 `tasks-state` 待派发队列。
- **场景 C（异常 · 返工）**：批次出现返工/漏闸 → 触发 L1 完整复盘 → 产出「机制改动 + 可验证防线」，不进正文 PRD。
- **画像**：PM（唯一常驻调度者）为主用户；rd-infra 为维护型执行者；下游三仓 PM 为继承者。

## 五、业务规则

- **BR1 任务单元分层**：交付型 = Issue 号（已建）或降级批次号；维护型 = `M<YYYYMMDD>-<slug>`（如 `M20261014-pi-ext-update`）。两套粒度共存，台账字段一致。
- **BR2 DoD 四类骨架（逐任务实例化）**：① **产物**（落盘路径，第三方可独立读到）② **验证**（可执行判据：命令 + exit code + 数字，或结构断言）③ **遗留项**（三出口，零遗留必须显式写「无」）④ **交接**（状态外部化 + 会话回收/重开 + 接手者第一动作）。
- **BR3 维护型补充判据**：命令 `exit 0` **不构成**完成。输出中每条 `warn` / `error` / `pending approval` / `N vulnerabilities` 必须归入：已处置 / 显式接受（含理由 + 到期）/ 转台账（含 owner）。
- **BR4 遗留项三出口**：**关闭**（已解决）· **接受**（降级 + 理由 + 到期日）· **转办**（进 `docs/tasks-state.md` 待派发队列或 Issue）。无第四出口；「先放着」不算出口。
- **BR5 台账不建二级真相**：证据落 `docs/reports/<编号>-followups.md`（未决项 >0 时建，一行一条：编号/来源/严重度/出口/到期）；**可执行项同步进项目既定 backlog**（本仓 = `tasks-state` 待派发队列）；超阈值（安全类 / 到期未决 >30 天）升 Issue。
- **BR6 复盘分级**：**L0 一行**（默认，四字段：结论/遗留/日期/编号）落台账；**L1 完整复盘** `docs/reports/<编号>-retro.md` 四节（发生了什么 / 根因 / 改了哪条机制 / 可验证防线），触发 = 返工 ≥1 / 漏闸 / 事故 / 同类第二次出现 / 用户投诉。
- **BR7 只指针不改写**：新技能对既有闸门（终态回执 / 验收闭环 / 上线闭环 / 合并闸门）**只引用路径，不复制条款**；出现重复表述视为违规（AC7 复核）。

## 六、NFRs（业务视角基线）

- **作用面**：纯文档层，运行期风险面 = 0（不改脚本/依赖/构建）。
- **上下文成本**：常驻卡增量 ≤ 2 行/张；技能为按需加载（不进常驻上下文）。
- **幂等**：文档条款重复应用无副作用（无迁移、无状态变更）。
- **兼容降级**：下游项目无 `tasks-state` 时回落到「Issue 或报告末尾遗留段」，不阻塞。
- **可审计**：任何「接受」类遗留项必须带到期日，否则验收打回。

## 七、验收标准

- **AC1（主路径 · 协议载体）**：Given 已合并，When 读 `.agents/skills/task-completion.md`，Then 含五节（任务单元 / DoD 四类 / 维护型补充判据 / 遗留项三出口 / 分级复盘）且每节可对照 BR1–BR6，全文 ≤80 行。
- **AC2（回执接缝）**：Given 读 `comm-templates.md`，When 看两模板，Then `done(lite)` 单行与 `done(full)` 各含 `遗留：` 字段，取值枚举 `无 | <n> 项 → <台账|tasks-state|Issue|接受(到期)>`，且与 `output-format.md`「回执硬性」不冲突。
- **AC3（PM 卡实例化）**：Given PM 卡 v26，When 读 §六，Then 新增一条含「维护型入口 / DoD 随开工卡实例化 / 三出口 / L1 触发」四点并指回技能；红线新增「输出有 warn/error 却判完成」1 条；`version` 与 `updated` 已 bump。
- **AC4（执行者卡）**：Given rd-infra 卡 v3，When 读维护型段落，Then 含 BR3 判据（依赖类：audit 与 install-scripts 必须决策）+ 指针；`version` bump。
- **AC5（清单与项目约束）**：Given `checklists/pm.md` 与 `AGENTS.md`，When 检索，Then 交付清单新增 2 项（DoD 已随开工卡确认 / 遗留项已三出口收口）、红线新增 1 项、`AGENTS.md` 项目约束新增 1 行维护型闭环口径。
- **AC6（负向闭环）**：Given 变更集，When 看 diff，Then `nao-fleet.sh` / `bin/` / `tests/` **零改动**，无新增角色、无新增流水线阶段。
- **AC7（设计一致性）**：Given 全文，When 比对既有闸门，Then 无成段复制（重复表述 >3 条视为失败）；`check` rc=0（roles=6 · files 计数 = 基线+1）· `npm test` rc=0。
- **AC8（可用性回溯演练）**：Given 协议成稿，When 用它处理本次 `pi update` 事件，Then 产出 `docs/reports/M20261014-pi-ext-update-followups.md`：4 漏洞 + 1 待批脚本每条落三出口之一，且 ≥1 条带到期日。
- **AC9（复盘门槛可测）**：Given BR6，When 抽查一次收尾，Then L1 触发五条枚举可逐条判定，L0 四字段格式固定；触发与不触发各给 1 例。

## 八、上线闭环

- **版本**：v0.18.6（PATCH；T527 已占 v0.18.5，本批排其之后）。
- **发布**：`gh release` 标题裸版本号（核 `.agents/common/release-notes.md`）；npm 重发与否发布时拍板。
- **广播**：`card pm v26`、`card infra v3`（下游三仓会话在线且 idle 时发，留痕）。
- **回滚**：单提交 `git revert`（文档层，无数据/兼容成本）。
- **监控信号**：`check` 的 `files` 计数、`npm test` 断言数基线、后续 2 批台账是否出现「无出口遗留项」。

## 九、变更治理与优先级

- **战略筛子**：命中主线「机制自身可交付性」——维护型任务的漏项直接腐蚀机制可信度；不挤占 T527（在飞，须排队）。
- **MoSCoW**：Must = AC1–AC5、AC7；Should = AC8、AC9；Could = E1 脚本校验；Won't（本批）= 硬阻断、第 7 角色。
- **RICE**：Reach = 20（未来一月适用任务数：批次 + 维护动作）· Impact = 3（高，遗留项失忆=隐患累积）· Confidence = 0.8 · Effort = 0.5 人日 ⇒ **RICE = 96**。
- **Kano**：基本型（缺失即不满：告警无人管）；非期望型增值 = 有出口的遗留项台账。
- **强制力成本分析（拍板项）**：E0 纪律条款 = 5 文件 + 0 脚本；E1 `check` 结构校验（归档时遗留项未收口 → warn）= +脚本 + 用例 ≈ 0.5 人日；E2 硬阻断 = 收窗/归档 rc≠0，误伤风险高。**建议 E0，升级门槛 = 连续 2 批出现「遗留项失忆」再立 PRD 做 E1**。
- **决策留痕（2026-10-14 开工卡拍板 D1–D4）**：D1 **排队**（T527 闭环后再开工）· D2 **E0 纯纪律条款**（不新增脚本校验）· D3 **v0.18.6 PATCH + 发布时重发 npm** · D4 **rd-infra 实施 + qa 复核、arch 跳过**。前序 grill 拍板：形态 = 角色卡/checklists · 对象 = 交付 + 维护通用 · 缺口 = DoD + 复盘 · DoD = 通用骨架 + 实例化 · 粒度 = 交付 Issue / 维护动作 · 复盘 = 分级 · 台账 = 轻量 `docs/reports` · 落点 = 新增按需技能。

## 附：本批 DoD 实例化

- **产物**：`.agents/skills/task-completion.md` + 5 处改动 + `docs/reports/M20261014-pi-ext-update-followups.md`。
- **验证**：`bash .agents/scripts/nao-fleet.sh check` rc=0（roles=6 · files=基线+1）· `npm test` rc=0 · `grep -c "遗留："` 两模板各 1 · 卡片 version bump 逐张核。
- **遗留项**：T527 未闭环期间的广播待发（转 `tasks-state` 待派发队列）。
- **交接**：`tasks-state` 快照更新 + 广播 + 派生会话回收。

- 修订：2026-10-14 首版成稿（grill 两轮定 9 项拍板）＋开工卡 D1–D4 拍板（排队 / E0 / v0.18.6 + 重发 / rd-infra+qa）

## 十、派发记录 / 验收结果 / 变更记录（归档 2026-10-27）

- **派发**：`rd-infra-T528` 落地 6 处改动（`9009ef7`）→ `qa-T528` 独立复核（报告 `docs/reports/2026-10-27-T528-qa-verify.md`，入库 `265ca8a`）→ `rd-infra-T528` 收缺陷 D1–D4（`608a941`）→ `qa-T528` 点检 4/4 → `rd-infra-T528` 执行合并。
- **需求分支 / PR**：`feat/46-task-completion-protocol`（Issue #46）· PR [#47](https://github.com/Nathan3303/nao-skills/pull/47) · **squash 合并 `3e98f0d`**（main 恰 1 条 · 无 `wip()` · 分支删净）· 验收评论 issuecomment-6445928184。
- **验收结论**：**通过（AC1–AC9）**。QA 独立门禁 `check` rc=0（roles=6 · **files 49→50**）· `npm test` rc=0 · 17/17 PASS · SKIP=0/DEGRADE=0 · 契约守护 PASS=85；PM 复核数字一致 + 逐条读变更文件；发布前置 `test:t4:full`（空载）rc=0。
- **QA 缺陷处置**：D1 台账遗留改「一行一条」+F3 补严重度/到期 · D2 技能 §五 指针改显式路径 · D3 台账 L0 补四字段 · D4 闸门枚举补「上线闭环」+§号 —— 全部合并前修（`608a941`，净 9+/8-），QA 点检 4/4 修好。
- **变更记录**：本批未产生 AC 口径订正（PM 派发时的「≤6 行」目标写低，实际 9+/8-，不影响结论）；版本 v0.18.6（PATCH）。
- **发布**：tag `v0.18.6` + GitHub Release（标题 = 裸版本号）；npm 重发由用户执行，判据 = `dist-tags.latest` = 0.18.6 且 `dist.integrity` 与本地 `npm pack` tarball 逐字节一致。
- **遗留项**：`事故` 阈值仅半句界定（转办，若出现判歧义按 E1 门槛评估）· `M20261014` 台账 F1/F2 接受至 2026-11-14（另有台账，不重复登记）。
