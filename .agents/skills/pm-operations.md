---
description: 按需技能——PM 运行手册（调度细则 / 开工确认卡 / 会话生命周期 / AGENTS.md 治理 / 交付归档 / 机制包版本自检）
---

# PM 运行手册

> 触发：**调度与运营操作**（拉起会话、派发、重开、建/改 `AGENTS.md`、归档）时读取；身份/边界/红线常驻在角色卡。
> 角色路由与会话登记在 @.agents/skills/pm-routing.md；需求分支与 PR 流水线在 @.agents/skills/github-flow.md。

## 一、多会话调度细则

- **准入判定**：先 `intercom status` + `list`；不可用立即降级不重试。
- **会话登记**：用户提供名称**及角色标注**（`fe-dev`/`be-dev`/`qa`/`infra`）；**未标注禁止猜测**，必须补问。
- **舰队启动**：不在线先拉起再 `list` 验证（`ask` 仅对在线会话）：`bash .agents/scripts/nao-fleet.sh ensure <别名>[@<repo目录>]`；项目独立于 nao-skills 仓库时用 `bash "$NAO_SKILLS/.agents/scripts/nao-fleet.sh" ...`。
- **环境自检（开工确认后、派发前）**：`bash .agents/scripts/nao-fleet.sh check`——默认 2 行摘要（摘要行 + codegraph 状态行；完整报告不进 PM 上下文），`warn>0` 或失败加 `-v`；**exit code 非 0（硬错误）→ 停止派发**（白名单 / CodeGraph 处置见 intercom-protocol「开工前自检」）。
- **架构评审闸门**：PRD 涉及架构/NFR/选型时，开工确认后、派发前 `send` arch-designer 评审。纯 CRUD 跳过。
- **派发协议（省 token）**：一条消息给 `编号 + 范围 + 引用路径（docs/...md#section）+ AC 编号 + 回执级别 + 需求分支（feat/<issue-id>-<slug>）`；**设计类任务的开工卡另须写明「设计稿验收模型」**（未出图同样必问；不答 = 用户本人确认，形状见 §二）；**不贴 PRD/方案全文、不用 `attachments` 传全文**（worker 自己读文件，PM 上下文不留副本）；worker `ask` → PM `reply`。
- **派单三段（强制，缺段即打回重派）** —— 本日 `#84`/`#86`/`#90` 三批返工的共同根因是**派单口径不完整**（非实现错误）；三段固定写在派发消息里，worker 据此自检、QA 据此判「可执行性」：
  - **① 数据通道**：凡「让 A 拿到 B 的数据」必须点明通道（**文件 / 参数 / 返回值**），**禁靠全局变量**（`#84` P1：用例在子 shell 里调护栏、再插值全局 ⇒ `set -u` 下中止，SKIP 变 FAIL，网络正常时看不出、会静默进 main）。
  - **② 各态 wired 断言**：**成功 / 失败有输出 / 失败无输出 / 无凭据 / 超时** 五态各一条「必须 SKIP 或 PASS，**不得 FAIL/中止**」（`#86` P1：`SKIP=0` 全绿 ≠ 安全）。
  - **③ 作用域 + 变异自证**：断言文本必须写明**作用域**（整段 / 某行 / 某字段），并配「改空 / 改错 ⇒ 必红」的**变异自证**（`#86` P3-1 与 `#88` P3-③：两次「声明比判据强」——文案说收紧了、实测仍是整段匹配）。
- **忙闲闸门**：`list` 见目标在线**且 `idle`** 才派完整任务；忙碌（`thinking`/`tool:*`）→ **不投递任务内容**，记入待派发队列（`docs/tasks-state.md`），转 `idle` 再派；**紧急**才抢占（交互会话可 steer 注入并注明 `紧急抢占：…回执须报告挂起任务状态`；非交互会话只能排队）。
- **任务派生会话（并行隔离）**：`ensure <role>@<repo> --task <编号>` → `--name <角色>-<编号>`（如 `rd-be-T1`）；**验收通过后回收**：`nao-fleet.sh close --task <编号> <别名>`（工具内置「在跑 turn / tasks-state 未推进」双闸门，后者防验收未过就回收丢返工上下文）；回执 role 写派生名。
- **状态外部化 + 接续快照（可恢复）**：任务状态落盘 `docs/tasks-state.md`（五栏 + 顶部「PM 接续快照」；骨架见 @.agents/templates/tasks-state.md.example），每次派发/回执/验收/抢占后更新；重开后**先读该文件重建状态**，不依赖历史消息。
- **终态回执闸门**：每次派发（含架构评审）必须收到 `[编号] done` 回执（两级：默认 `done(lite)`；有阻塞/风险/需决策 `done(full)`，模板见 @.agents/checklists/comm-templates.md）；未见回执（含 arch 静默）→ 主动追讨，必要时上报用户，**不默认成功**。
- **残留自检**：`nao-fleet.sh status` 标出派生会话残留（tasks-state 已归档 / 无记录）；发现即核对状态并 `close --task <编号> <别名>` 回收。判据按 pane 实际工作目录定归属 ⇒ **他仓会话单列、勿在本仓回收**（`~ <名>（他仓 @ <仓名>）` 行不含可执行命令；归属不可判定 ⇒ 人工核对）。
- **会话回收与收窗**：派生会话验收通过即 `close`；**常驻会话不回收**（保留复用，上下文变长时 `ensure --force` 重开）；手工关窗前按 checklists/pm.md「会话回收 / 收窗核对」逐项核对（工具不替代回执与产物核对）。
- **角色提示词加载**：fleet 拉起的会话已启动期注入，派发只要求回执 `已按 <role> 角色执行`；仅对用户手工开、未注入的会话才指示加载 `@.agents/prompts/<role>.md`。
- **验收闭环（省 token）**：核对 AC 五覆盖 + 回执「清单」字段（未核对则打回）；验收 = 核对回执**全量门禁精确数字** + 读变更文件核对 AC + **异常才复跑/抽查**（**不可改码**、**不重复跑 worker 已跑的门禁**）；读码走三段阶梯（原生入口 `codegraph_explore`（需插件 + CLI + 索引齐备）→ CLI → `grep -rn` + 行段；行段读取如 `codegraph node --file <f> --offset <n> --limit <m>`），**禁 cat 全文**；依赖 QA 先行用例。
- **合并闸门（PM 控制合并时间点）**：工作期 RD 只在需求分支 `feat/<issue-id>-<slug>`（降级 `nao/<批次-slug>`）提交（`wip(<编号>):` 检查点、路径级暂存、禁 `-A`）。**PM 验收通过 = 授权合并**；合并由 RD 在 PR 上 `--squash` 执行（降级走本地 `merge --squash`），**PM 不亲自合并、不 push main**。验收核对：PR 标题/信息**用户可读** + main 上本需求**恰好 1 条提交且无 `wip()`** + 工作区干净。特例白名单与流水线见 @.agents/skills/github-flow.md。

## 二、开工确认卡（强制闸门）

表格输出，末尾询问「是否开工？会话/角色是否如上？」：

| 任务编号 | 目标会话 | 角色 | 任务概要 | 对应 AC |
| :--- | :--- | :--- | :--- | :--- |
| T1 | rd-be | 后端 | ... | AC1/AC3 |

分支：`feat/<issue-id>-<slug>`（降级 `nao/<批次-slug>`）· PR owner：<角色> · Reviewer：<arch-designer / 无> · 预览环境：<URL / 无>
QA 测试范围（派发无人值守时按此执行；用户在场时由 QA 直接询问用户）：<列出范围 / 无 QA>
设计稿验收模型：用户本人 / 托管给 PM（设计类任务必答、非设计类写「不适用：无设计稿」；**不答 = 用户本人确认**；绘图类 MCP 出图后未获用户确认不派 RD，见 @.agents/prompts/product-manager.md §六）

建议顺序：**QA 先行用例 → 前后端并行**。

用户指定模型时在开工确认卡另起一行注明（如 `rd-be: deepseek-v4-flash:high`）；**未指定禁止传 `--model`、禁止继承 PM 模型**（白名单由 `nao-fleet.sh` 校验，PM 只需如实转达）。

## 三、PM 会话生命周期（重开纪律，PM 专属）

PM 是舰队唯一常驻长寿会话：上下文过长时丢的是**纪律**（红线/闸门遗漏且无感），因此不靠「记得住」，靠**批次边界重开 + 落盘接续**。**三个触发点，任一命中即 `ensure --force pm`**：

1. 交付归档完成（批次终态，默认触发）；
2. 用户切入新需求、上一需求已闭环；
3. `/session` 显示 contextTokens 超上下文窗口 40%（主动交接，不等自动压缩）。

- **重开前**：更新 `docs/tasks-state.md` 顶部「PM 接续快照」（当前阶段 / 当前 PRD / 未决决策 / 待用户回答 / 下次唤醒条件 / 会话体检）。
- **重开后**：读 tasks-state（含接续快照）+ `docs/prds/README.md` 索引 → **向用户回读确认 3 行**（当前阶段 · 未决决策 · 口头约束），确认后方可调度；**禁止凭残缺记忆调度**。
- **自动压缩只作兜底**：LLM 摘要**有损且不可审计**（决策点最易丢）、额外花 token、禁用该次 prompt-cache 写——它救的是溢出，不是记忆。

## 四、AGENTS.md 项目上下文治理（PM 独有职责）

项目根 `AGENTS.md` 是**项目级单一事实来源**（pi 自动加载进所有会话上下文，与 CLAUDE.md 兼容）。PM 负责建立与维护——让任何角色进入项目即获得一致的项目属性与约束。

**内容范围（只放项目级；它常驻上下文，必须精简）**

- 项目属性：仓库结构 / 技术栈与版本 / 构建·测试·lint 命令 / 运行方式 / 环境变量 / 目录约定。
- 项目约束：领域红线、依赖与命令纪律、与 nao 机制衔接（CodeGraph 索引位置、UI tokens/ux-playbook 路径、checklists 位置）。
- **指针而非复制**：角色级/团队级内容留在 nao-skills（roles.yaml / common / checklists），AGENTS.md 只写「在哪里」。

**接入已有 AGENTS.md（项目已存在且非空时）**

- **合并不覆盖**：原文件是项目既有资产，PM 无权单方面改写；先读全文判断来源（手写规范 / 工具生成）。
- **在 pi 实际加载的文件里合并**：pi 按 `AGENTS.override.md → AGENTS.md → CLAUDE.md` 只取第一个存在者；在**被加载的那个文件**里追加，而非新建遮蔽文件。
- **保留原文 + 追加接入区块**：原内容原样保留，末尾追加 `## nao 舰队接入（YYYY-MM-DD）` 区块，含：角色清单指针（`$NAO_SKILLS/.agents/roles.yaml`）、机制衔接（CodeGraph / checklists / UI tokens）、命令纪律；区块加注释标记便于未来移除（可回退）。
- **同主题冲突**：原文件条目优先（它是项目既定决策）；nao 需要的补充以接入区块承载，不混改原文措辞。
- **删除/改写原文须用户确认**：与零代码边界同源——PM 只增不改既有资产，除非用户明确授权。
- **验收**：合并后 `nao-fleet.sh check` 通过；任意会话进项目可复述 AGENTS.md 中的项目约束。

**更新时机**

- 项目初始化（首个 PRD 定稿后**当日建立**）。
- **用户口头约束即时落盘**：用户的任何约束性表述（如「这个项目不许用 ORM」）**当场**写入 `AGENTS.md`（项目级）或 PRD「变更治理」（需求级），**不等归档**——不落盘则 PM 重开后无法恢复。
- 关键技术决策（ADR 归档时同步一条）。
- 约束/命令/结构变化随改随更；交付归档时顺带核对（见本文件 §五）。

**自查（PM 交付前）**

- [ ] AGENTS.md 掺入角色级/团队级内容？（应留在 nao-skills）
- [ ] AGENTS.md 超长（>120 行）或含易变细节？（应精简/移除）
- [ ] 技术决策或约束变化后未同步 AGENTS.md？

## 五、交付归档

- 时机：PRD 完成且交付闭环后**当日**归档。
- 落盘：`docs/prds/YYYY-MM-DD-<主题>.md`。
- 内容：背景(5 Whys 摘要) → 目标指标与埋点 → 9 模块要点 → 决策留痕(RICE/取舍/回滚) → 参考来源(`docs/research/` 路径) → 派发记录（含需求分支、PR 编号、main 合并 commit hash） → 验收结果 → 变更记录 → 遗留项。
- 首次归档创建 `docs/prds/README.md` 索引（日期 | 主题 | 交付 | 终签状态）。
- 归档同时：更新 `docs/tasks-state.md` 接续快照；「派发记录」末行记**会话体检**（`contextTokens / 压缩次数 / cacheRead 占比`，取自 `/session`）；随后按本文件 §三「PM 会话生命周期」重开 PM 会话（归档 = 批次终态）。

## 六、机制包版本自检（`ensure pm` 注入，仅提示不自动升级）

> 契约来源：`docs/prds/2026-11-03-ensure-pm-update-check.md`（R1–R6）；关闭开关 `NAO_UPDATE_ON_ENSURE=0`。
> 机制侧实现：`.agents/scripts/nao-fleet.sh` 的 `NAO_UPDATE_MSG` 常量（字符串常量，`grep -n '^NAO_UPDATE_MSG='` 可定位）。

**触发**：目标解析为 `pm` 时，fleet 在 `--append-system-prompt <卡>` **之后**以 `--` 分隔追加一条固定首条用户消息；fleet 进程内**不执行任何** `npm`/`gh`/`curl`（零网络），检查由本会话自己做。非 `pm` 目标与开关关闭时命令行逐字不变。

**检查顺序（只读）**

1. 本地 pin：读 `.pi/settings.json` 里 `@nathan33/nao-skill` 的版本 X；无该文件/无该 pin ⇒ 走输出 ④。
2. 远端：`npm view @nathan33/nao-skill version --fetch-timeout=5000`（内置 5s 超时；**不要**用外部 `timeout` 命令——macOS 原生无该命令，rc=127 会被误判成「离线或超时」）；超时/报错 ⇒ 走输出 ③。
3. 仅当 Y > X 才取要点：`gh release view v<Y>`，**压成不超过两句**；无 `gh` 或取不到 ⇒ 走输出 ⑤。

**输出（恰好一行，按序命中即止）**

- ① 有新版：`当前 X → 可升 Y（要点）。要升吗？`
- ② 已最新：`版本检查：已是最新 X。`
- ③ 离线或超时：`版本检查：离线或超时，跳过（可稍后手动 npx @nathan33/nao-skill --version 核对）。`
- ④ 未检测到下游 pin：`版本检查：未检测到下游 pin（本仓为机制源），跳过。`
- ⑤ 无 `gh`：`版本检查：当前 X → 可升 Y（要点取不到，见 https://github.com/Nathan3303/nao-skills/releases）。要升吗？`

**零改动保证**：检查阶段只读（`.pi/settings.json` 只读、`npm view` / `gh release view` 均为查询）；**「未获我同意前不要改任何文件、不要升级」**（逐字引自注入常量；不改 pin、不跑 `pi install` / `pi update`）。

**用户同意后的动作序列**（升级属不可逆动作，按 ask-me 口径确认后再执行）

1. `pi install -l npm:@nathan33/nao-skill@<Y>`（更新项目 `.pi/settings.json` 的 pin；**若提示安装脚本授权 ⇒ 停下来交给用户确认，不自行放行**）；
2. `pi update --extensions`；
3. 提醒用户「本轮会话仍是旧角色卡，建议重开」（`ensure --force pm`）。

用户未表态或说「稍后」⇒ 原样待命，不重试、不轮询、不后台检查（无定时任务）。噪声可接受度见 PRD §八 观察项（若用户抱怨，改为 24h 节流，需另立需求）。
