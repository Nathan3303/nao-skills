# UI/UX 设计师常驻角色卡（T537）

- 状态：待确认 · 更新：2026-11-03 · Owner：pm
- 指针：技能 `.agents/skills/uiux-design.md`（本批新增）· 二期任务 T538（Penpot MCP 接入）· 文档骨架 `.agents/checklists/deliverable-docs.md` §九

## TL;DR

- **做什么**：新增第 7 个常驻角色 `uiux-designer`（角色卡 + 设计技能 + 设计报告骨架 + 设计一致性验收闸门），并把「六个角色」口径全量改为七个。
- **给谁**：跑 nao 舰队、有真实界面产出的下游项目；本仓是机制源。
- **成功标准**：`check` rc=0（roles=7）· `npm test` rc=0 · 7 pane 下无新增布局 warn · 设计类需求在 PM 验收前有可引用的设计结论载体。
- **不做什么**：本期**不接入 Penpot MCP**（另立 T538）· 不做截图 diff 类视觉自动化 · 不动 `rd-fe` 卡与 `frontend-design` 技能。

## 一、问题证据

- **责任缺位**：现有 6 角色里没有设计负责人——`rd-fe` 卡内置的 `frontend-design` 技能只约束「实现层不产出 AI 默认样式」，`qa` 卡明确把视觉/UI 呈现转为用户人工验收清单（不判定设计好坏）。
- **后果**：信息架构、交互流程、视觉规范、设计一致性四项**无归属**；PM 在 PR 上只能凭主观裁，Penpot 稿无处安放。
- **证据**：`frontend-developer.md` §一（视觉一致/四态/不 AI 味）· `test-engineer.md` §一（不做视觉自动化，转用户验收清单）· `README.md:94` 角色表无设计角色。
- **影响面**：每条含界面的需求，验收链路缺一个可引用的设计结论；舰队对「好看且可用」这件事没有正式责任位。

## 二、目标指标

- **设计类需求出报告率**：本仓 0 → 1 个样例，口径 = `docs/designs/<编号>-<slug>.md` 存在且含 9 项骨架。
- **闸门可查性**：设计类需求在 PM 验收前 100% 有设计师 PASS/REJECT 意见（带 AC 编号）。
- **卡体积**：常驻卡 ≤ 8 KB / ≤ 120 行；技能 ≤ 80 行（现有卡 5–7 KB，不得膨胀成第二张 PM 卡）。
- **机制门禁**：`check` rc=0（roles=7）· `npm test` rc=0 · `test:t4:full` 空载 SKIP=0 / DEGRADE=0。

## 三、范围 / 非范围

**范围**

- **`roles.yaml` 登记**：`uiux-designer`，`aliases: [uiux, ui-designer]`，`card: uiux-designer.md`、`workspace: .`。
- **角色卡** `.agents/prompts/uiux-designer.md` v1：定位与边界 · 降级阶梯 · 闸门与回执 · 红线 · 环境锚点。
- **技能** `.agents/skills/uiux-design.md`：设计报告骨架、降级阶梯细则、Penpot 操作口径（二期扩展位）、可用性/无障碍基线、反 AI 味清单。
- **文档骨架**：`deliverable-docs.md` 新增「设计报告」章节（骨架 + 行数上限 + 禁写清单）。
- **落点**：`docs/designs/README.md` 索引 + 一件本批自用样例报告。
- **闸门接入**：`product-manager.md`（designer gate + 派发纪律，**bump version**）· `pm-routing.md` 路由行 · `intercom-protocol.md` 角色表 · `README.md` / `docs/INSTALL.md` / `skills/nao-fleet/SKILL.md` 的「六个角色 → 七个角色」与启动串。
- **测试**：`tests/t4/cases/09-alias-guard.sh:88` 的 `roles=6` 断言改 `roles=7`（否则必红）；必要时补一条 7 角色下别名解析正例。

**非范围（每条带理由）**

- **Penpot MCP 接入**（`.pi/mcp.json` / `@penpot/mcp` / 浏览器插件）：需 Penpot 实例 + 浏览器常开插件 + key，故障面与回退都独立；先定降级路径再做真实接入，另立 T538。
- **视觉自动化（截图 diff / 无头浏览器）**：`qa` 卡已定不做，体感类只能人验；重复实现等于双源。
- **改 `rd-fe` 卡或 `frontend-design` 技能**：实现层视觉已由该技能覆盖，再加一遍即双源。
- **设计师产出功能代码**：与零代码红线冲突；Penpot/ASCII/规格属设计资产，不算源码。
- **角色子集安装（只装 6 个不装设计师）**：现状无此机制，改安装语义成本远超本需求，记已知边界。

## 四、用户场景

- **场景 1（设计类需求）**：PM 派发「PRD 路径 + AC 编号 + 回执级别」→ 设计师读 PRD、出设计报告与原型 → `done(lite)` → PM 验收时引用其结论。
- **场景 2（无 Penpot，本期默认）**：设计师按降级阶梯交付文字规格 / ASCII 线框 / 分步作图指令，**不因缺工具挂起任务**。
- **场景 3（T538 落地后）**：同一张卡切换为 MCP 作图，报告里留帧链接 + 要点摘录，闸门不变。
- **场景 4（非设计类需求）**：纯接口/数据/构建改动，PM 不派发设计师，链路不长出第 7 跳。

## 五、业务规则

- **BR1 触发条件**：需求含新增/改版界面、交互流程变更、视觉规范（token/组件）变更 ⇒ **必过设计师**；其余不触发。
- **BR2 闸门语义**：设计类需求的 PM 验收前须得设计师 PASS；REJECT 必须给**可执行修改项 + 对应 AC 编号**，只给主观评价视为无效回执。
- **BR2a 覆盖边界（arch 评审补）**：设计师 PASS **仅覆盖设计产物**（`docs/designs/` vs AC 设计条目，实现前）；实现后的视觉一致性仍走 QA「用户验收清单」交用户判。设计师被 PM 邀约做一致性复验时，意见按 AC5 带 AC 编号。设计产物问题回设计师，实现偏差回 `rd-fe`。
- **BR3 代码边界**：设计师不改源码/测试/构建配置；可写 `docs/designs/` 与 Penpot 文件。
- **BR4 降级阶梯**（按序取一，交付即成立）：① 结构化文字规格（层级/间距/状态/断点）② ASCII 线框 ③ 分步作图指令（画板/图层/组件命名）。
- **BR5 资产落点**：设计报告与降级产物随任务 PR 落 `docs/designs/`；外部 Penpot 链接必须附要点摘录，防断链不可追溯。
- **BR6 命名约束**：角色 id/别名不得与既有 6 角色前缀相交；别名取 `[uiux, ui-designer]`（避开 `arch-designer` 的 `designer` 模糊面）；若 `check` 前缀校验报冲突 ⇒ 回退为 `[uiux]` 单名并在回执说明。

## 六、NFRs

- **体积**：卡 ≤ 8 KB / ≤ 120 行，技能 ≤ 80 行；卡正文不复述 PM/QA 卡条款（只给指针）。
- **布局**：7 pane 在 `main-row2 | main-col | grid` 三选一与窄列回退链下**零脚本改动、零新增 warn**（arch 实证：`main_row2_geom` 的 `cols=(n-1+1)/2` ⇒ n=6 与 n=7 同为 3 列，几何逐字相同；1920×1080 与 120 列窄窗表现均属既有行为）。
- **离线**：卡与技能零网络依赖，降级路径完全离线可用。
- **幂等**：`check` 连跑 2 次 rc=0 且输出一致（roles=7，`files` 计数按实测）。
- **敏感值**：卡/技能/样例报告中禁绝对家目录路径、token、真实实例 URL。

## 七、AC

- **AC1 主路径（夹具验，不 live）**：Given `roles.yaml` 已登记 `uiux-designer`，When 在 t4 夹具下 `ensure uiux`，Then 桩 `tmux`/`pi` 记录到会话名 `uiux-designer` 且注入提示文件 = 该卡正文逐字 + 锚点行；**不真起会话**（不碰用户实际 tmux 窗口）。
- **AC2 主路径**：Given 设计类需求派发，When 设计师交付，Then `docs/designs/<编号>-<slug>.md` 存在且含 9 项骨架（信息架构 / 流程 / 视觉规范 / token / 状态 / 断点 / 可用性 / 无障碍 / 降级产物）。
- **AC3 异常（无 Penpot）**：Given 无 MCP 与实例，When 派发原型任务，Then 交付物含降级阶梯至少一项，且回执不报阻塞、不挂起。
- **AC4 边界（命名冲突）**：Given 别名 `ui-designer` 与既有 `arch-designer` 并存，When 跑 `check`，Then 前缀校验不误红且 `ensure ui-designer` 解析到 `uiux-designer`；若冲突则按 BR6 回退 `[uiux]` 并在回执说明。
- **AC5 负向闭环**：Given 设计一致性被 REJECT，When 复验，Then 每条意见带 AC 编号且可逐条核；无编号的意见 PM 必须打回。
- **AC6 设计一致性（口径统一）**：When 全仓 grep，Then 角色表述统一为「七个角色」，`README` / `INSTALL` / `intercom-protocol` / `pm-routing` / `nao-fleet` SKILL 的新增角色行与 `roles.yaml` 完全一致，「六个角色」残留 = 0。
- **AC7 门禁**：`check` rc=0（roles=7 · files 按实测）+ `npm test` rc=0 + `test:t4:full` 空载 SKIP=0 / DEGRADE=0，且 `cases/09` 的 roles 断言已同步为 7。

## 八、上线闭环

- **Issue/分支**：`gh` 可用 ⇒ 建 Issue（摘要 + 指针，正文留本文）；分支 `feat/<issue>-uiux-designer-card`，`wip(T537):` 小步 + 路径级暂存。
- **版本纪律**：新卡 v1；改 `product-manager.md` 必须 bump version 并广播 `card pm v<N+1>`（本批 ≥ v34）。
- **发布**：feat ⇒ MINOR，0.21.3 → **0.22.0**；`docs/releases/v0.22.0.md` 面向用户首段写「现在有 7 个角色，多了 UI/UX 设计师」。
- **文档载体**：PRD / 技能 / 卡 / 报告 / 台账全随本任务 PR，不单开 PR。
- **回退**：删卡 + `roles.yaml` 回退 + 文档口径回退，单条 `git revert <squash sha>` 可清爽回滚。

## 九、变更治理

- **T538（二期）**：Penpot MCP 接入（arch 评审结论：**本地自托管 4400/4401 优于云端 remote**，因凭证与故障面留在本机且可逐角色门控）。
- **MCP 门控事实（arch 复核已定稿）**：pi 的 MCP 配置在 `.pi/mcp.json`（项目级，需 trust）/ `~/.pi/agent/mcp.json`（用户级），**无 role 维度**，会话启动即连 ⇒ 7 个会话同见工具。隔离两条路——**A 卡内行为约束**（默认，零改动，本期做）｜**B `ensure` 时按角色下发 `--no-mcp` / `--tools` 白名单**（改启动串 + t4 夹具，属 T538 可选加固）。
- **T538 三条硬约束**：① 凭证与实例 URL 零入库（文档只给占位符；本机 `mcp.json` 内是真 JWT，严禁复制进仓）② 不依赖浏览器插件常开（断链必须走 BR4 降级、不阻塞）③ 可被 `--tools` / `--no-mcp` 精确门控。
- **二期改动面**：只动卡与技能里的「原型产出」章节 + 安装说明，**不动**闸门（BR1/BR2）与 `docs/designs/` 落点。
- **已知边界**：不支持「只装 6 个角色」的子集安装；设计质量最终仍由人（用户）判定，卡只保证产出结构与可核性。

## 优先级（RICE + 战略筛子）

- **战略筛子**：机制包卖点是「角色覆盖度」；UI 需求是下游主场而设计位空缺 ⇒ **命中**，进候选。
- **MoSCoW**：**Should**（本期做）。
- **RICE**：Reach 4（全部下游 UI 仓）· Impact 3（补一个责任缺位）· Confidence 0.8 · Effort 0.5 人日 ⇒ **RICE ≈ 19.2**，排序靠前。
- **Kano**：期望型——有则满意、无则抱怨（设计需求无人负责），非兴奋型，故不做花活（不做视觉自动化）。

- 修订：2026-11-03 初稿（用户已确认 5 项澄清：报告+原型 / 第 7 常驻 / MCP 分两期且需 ASCII 降级 / 设计一致性须过设计师 / `docs/designs/` 独立落点）
- 修订：2026-11-03 开工确认：派发前走 arch 轻量评审 · AC1 改夹具验不 live · 别名定 `[uiux, ui-designer]`
- 修订：2026-11-03 arch 评审落地（无阻塞）：布局零改动只需改 `cases/09:88` · MCP 隔离改「A 卡内约束（本期）+ B `--tools`/`--no-mcp` 门控（T538）」· 新增 BR2a 覆盖边界 · T538 三条硬约束与本地优先结论
