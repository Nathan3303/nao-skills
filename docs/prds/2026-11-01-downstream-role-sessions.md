# PRD：下游仓自定义角色会话（`ensure --card`）

- 状态：待开工确认 · Owner：PM · 更新：2026-11-01
- 指针：来源 = 用户 2026-11-01 需求讨论（「用户创建自定义卡 → PM 开工卡后调整 → 某 rd 完成后启动 Review 会话决定收尾 → PM 更新开工卡后直接 `ensure` 出来」）· 既有结论 `docs/tasks-state.md` 下批候选 ① · 机制现况证据见 §一
- 需求编号：T537 · 版本预期：**v0.21.0（MINOR）**
- 优先级：中高 · RICE ≈ 4.8（附录 A）· MoSCoW = Must · 战略筛子：**契合**「nao 提供机制、下游自持角色」定位（不增加上游角色维护负担、不改常驻角色语义）

## TL;DR（≤5 行）

- **做什么**：给 `ensure` 增加 `--card <卡路径>` 参数线 —— 用**下游项目仓**的 `.agents/prompts/<role>.md` 拉起一个会话，获得与 6 常驻角色等价的 fleet 托管（pane 宿主管辖 / `status` 可见 / `close` 可回收 / 残留检测），且**不登记**上游 `roles.yaml`。
- **给谁**：需要按批次拉起按需角色（Code Review 等）的 PM 与下游项目使用者。
- **成功标准**：不带 `--card` 时既有行为逐字不变；带 `--card` 时会话从拉起→可见→回收全链路闭环，且 `roles.yaml` diff = 0。
- **不做什么**：不新增第 7 常驻角色、不登记 `roles.yaml`、不改 pi-subagents 集成、不做下游卡自动生成 agent。

## 一、问题证据

- **机制现况（只读定位，三条硬事实）**：
  1. fleet 的角色来源是**唯一清单** `$SKILLS_DIR/.agents/roles.yaml`，且 `SKILLS_DIR` 恒为机制包根（`nao-fleet.sh:76-79`；项目内 shim 显式把 `NAO_SKILLS` 指回包根）⇒ 下游 `.agents/` 不参与任何解析。
  2. `resolve_role()` 只查清单填充的别名表，未命中即 `die "未知角色"`（`:354`）⇒ 下游卡无拉起入口。
  3. `spawn_one` 的卡路径写死为 `$PROMPTS_DIR/$PROMPT`（`:1077`）⇒ 无「外部卡路径」入口。
- **下游并非没有卡**：用户已在下游仓 `.agents/prompts/` 放角色卡；但该目录当前**无任何机制消费** —— fleet 不读，pi-subagents 虽递归扫项目 `.agents/**/*.md`（上游 `pi-subagents/src/agents/agents.js:2187`），却要求 frontmatter 同时有 `name` 与 `description`（缺任一静默跳过，`:1915-1918`），而 nao 角色卡用的是 `role:`。⇒ 用户写了卡，**却没有任何机制会用它**。
- **用户场景痛点（原话归纳）**：批次中段（某 RD 回执后）需要一个 Review 角色介入决定是否收尾；手工起会话得不到 fleet 的 pane 托管、`status` 可见性、`close` 回收与残留检测，PM 只能靠 `intercom list` + 人工 `kill-pane`，违反「状态外部化 + 回收闭环」纪律。
- **5 Whys（为什么缺这一档）**：只能手工起 ← fleet 只有「清单内常驻角色」一条拉起路径 ← `ensure` 的角色解析与卡路径都绑定清单 ← 设计时把「角色」等同于「团队常驻编制」← 从未区分「编制角色」与「批次按需角色」。
- **同类既有结论**：`docs/tasks-state.md` 下批候选 ①（CodeReview 是否新增角色）已定「不新增常驻第 7 角色，走最小改动包」；本需求正是该结论的**落地形态**（按需拉起，非常驻）。

## 二、目标指标

- **北极星**：下游卡会话的 fleet 托管等价度 = **3/3**（拉起方式、状态可见、可回收），且上游清单改动 = **0 行**。
- 预期：PM 为一个按需角色付出的手工操作从「3 条命令 + 2 次人工核对」降到 **1 条 `ensure` 命令 + `close`**。
- 观测：`check` 报告（roles 计数不变、新增下游卡节）· `ensure --card` 起出的 pane 标题契约 · `status` 输出行 · `close` 退出码与名册收敛 · `git diff --stat .agents/roles.yaml` = 0。

## 三、范围 / 非范围

- **范围**
  1. **A · 调用入口**：`ensure --card <路径> [--as <会话名>]`，`--card` 可与非 `--card` 角色同批混用；`--task` / `--repo` / `--force` / `-m` 与本参数正交可用。**卡路径口径（开工卡 D3 拍定）**：仅接受 `<repo>/.agents/prompts/<file>.md` —— 同时校验 realpath 前缀与目录归属，任一项不符即拒绝。
  2. **B · 会话命名与语义**：默认 `<role>-<task>`（有 `--task`）或 `<role>`（无 task），`role` 取自卡 frontmatter `role`，退化取文件名；`--as` 显式覆盖。属**派生/一次性会话线**（不是常驻）。
  3. **C · 系统提示**：复用既有 `build_system_prompt`（卡正文 + `## 环境锚点` 行）—— 锚点文案与 6 角色**同源同字**，不新增第二份。
  4. **D · 全托管三接线**：`status` 可见（含「本仓 / 他仓 / 不可判定」三态与残留标注）· `close` 可回收且**不**触发常驻警告 · 残留检测覆盖。
  5. **E · `check` 新增「下游角色卡（若存在）」一节**：校验 `<cwd>/.agents/prompts/*.md` 的 frontmatter（`role`/`description` 可取、非空）与卡内 `@.agents/...` 引用（**按机制包根解析**）；目录不存在 ⇒ 跳过且不影响 rc。
  6. **F · 文档**：`nao-fleet.sh` 帮助文本 + `README.md` 一节（下游角色卡接入）+ `intercom-protocol.md` 角色表脚注（自定义会话不入表，一句说明）。
- **非范围**（各带理由）
  - 不登记 `roles.yaml`、不新增常驻角色：理由 违背「下游自持、上游零负担」定位；一旦登记就变成上游维护项（且测试/文档 6 角色断言需连锁修改）。
  - 不改 `status` 对 6 常驻角色的既有展示、不改 `close` 对常驻/派生的既有语义：理由 T516/T530 已定稿并有回归用例，回归面不可控。
  - 不做「下游卡自动注册为 pi-subagents agent」：理由 T527 已定 **6 个 `nao-<role-id>`** 命名纪律，扩面会让 subagent 注册表随项目漂移，另立项。
  - 不支持「卡来自工作区外 / 远程 URL」：理由 信任边界（卡即系统提示）与可审计性。
  - 不做 overlay 清单方案（`NAO_SKILLS` 指向下游清单目录）的能力化：理由 该路径已可用且与「常驻」语义绑定，与本需求的按需语义互斥；文档需说明二选一。

## 四、用户场景

- **画像 A（PM · 批次中段起 Review）**：RD 回执后 `ensure --card .agents/prompts/code-reviewer.md --task T537` → `status` 见在线 → 经 intercom 派活 → 收到 `done` → `close --task T537 code-reviewer`。
- **画像 B（下游使用者 · 新项目首次接入）**：写下游 `.agents/prompts/data-reviewer.md` → 一条命令拉起 → 无需读机制包源码、无需改上游清单。
- **画像 C（PM · 开工卡声明）**：开工确认卡「本批附加会话」段登记卡路径与拉起时机；批次结束按同一条 `close` 回收，`status` 与名册双清。
- **关键路径**：写卡 → `ensure --card` → pane 起 + 命名 → `status` 可见 → intercom 派活/回执 → `close` → 残留检测为 0。
- **页面状态**：不适用（CLI）。

## 五、业务规则

- **BR1 不登记清单**：全程不得读写 `roles.yaml` 以登记下游角色；`git diff .agents/roles.yaml` 必须为 0。
- **BR2 反冒充**：卡推导出的 `role`（或 `--as`）**不得命中** `ROLE_ORDER` 的任何 id 或别名；命中即拒绝并提示改用 `--as`。理由 舰队身份靠名字前缀识别（`status` 派生区扫描 `:1461-1463`、`close` 派生名解析 `:1531`），同名会污染常驻语义与他人回执。
- **BR3 限定目录 + 工作区内**：`--card` 只接受 `<repo>/.agents/prompts/<file>.md`（`<repo>` = `--repo` 或 `$PWD`）；须同时满足「realpath 落在 `<repo>` 之内」与「父目录为 `<repo>/.agents/prompts`」两条，任一不符即拒绝。理由 卡即系统提示，等价于「能写工作区文件即可定义角色」；固定目录让授权面可审计（谁在哪个目录写了什么）。
- **BR4 锚点同源**：系统提示必须由既有 `build_system_prompt` 生成；**禁止**新增第二份锚点文案（否则与 `tests/t4/cases/17` 的 cross-assert 契约分叉）。
- **BR5 一次性语义**：属派生/一次性会话 —— `close` 正常回收即可，**不得**触发「常驻会话…应 `ensure --force` 重开」警告（`:1541`）。
- **BR6 零副作用**：卡校验失败（缺失/空/无法解出 role/越界/冒充）时必须**不建 pane、不写状态、不推送**，退出码非 0 + 单行原因（沿用 BR3 口径）。
- **BR7 既有行为不变**：不带 `--card` 的所有分支（解析、判重、布局、输出行、退出码）逐字不变。
- **BR8 卡内引用归包根**：下游卡的 `@.agents/...` 引用按机制包根解析（锚点行已声明），`check` 的校验口径同此。

## 六、NFRs（业务视角基线，技术指标待 arch 转译）

- **兼容**：pi ≥ 1.4.0 / tmux 内（既有唯一前提不变）；不带 `--card` 时零行为差异；`roles=6` 计数不变。
- **可审计**：下游卡随项目任务 PR 提交（可 diff、可回滚）；批次级会话在 `docs/tasks-state.md` 有登记（PM 状态外部化不变）。
- **安全**：卡路径限定工作区内；拒绝冒充常驻角色；不引入网络与凭证面。
- **可维护**：改动集中在 `nao-fleet.sh` 单文件 + `check` 一节 + 测试用例；不新增生成物、不新增配置文件。
- **可诊断**：失败必须单行可读原因（含「该怎么办」的提示），符合既有 die 文案风格。
- **不适用**：吞吐/并发压测（拉起为低频人工动作）· 多租户隔离。

## 七、AC

- **验证接缝**：`tests/t4` 新增用例（`cases/2x`，编号由 rd 按序取）+ 既有全量用例 + `check` + `npm test`；一次性只读探针放 `docs/reports/2026-11-01-T537-*-probe.sh`（如需要）。
- **AC1（主路径 · 拉起与身份）**：Given 下游夹具 `<repo>/.agents/prompts/code-reviewer.md`（frontmatter `role: code-reviewer` + `description`），When `ensure --card .agents/prompts/code-reviewer.md --task T537`，Then ① 新 pane 起于调用者宿主窗口；② 终端标题命中 `π - code-reviewer-T537 - <repo basename>`；③ 系统提示文件内容 = 卡正文逐字节 + `## 环境锚点` 行，且锚点行与 6 角色起出的文件**逐字相同**（`NAO_SKILLS` 指向机制包根）。
- **AC2（异常 · 零副作用）**：六种失败输入（卡不存在 / 空文件 / frontmatter 无 `role` 且无可退化文件名 / 卡不在 `<repo>/.agents/prompts/` 内 / 卡经 symlink 逃逸到该目录外 / 缺少路径参数）逐个断言：退出码非 0 · stderr 单行含原因与「该怎么办」 · **pane 数不变** · tmux session 列表不变 · 无 prompt 临时文件残留。
- **AC3（边界 · 冒充与命名）**：① `role: qa`（命中常驻 id）⇒ 拒绝且提示 `--as`；② `--as` 含非法字符（空格/`/`）⇒ 拒绝；③ `--as` 命中 `ROLE_ORDER` id ⇒ 拒绝；④ 默认名 `code-reviewer` 与 `--task` 组合后不与常驻名冲突（正控：同一批同时 `ensure qa --card …` 中 `qa` 走清单、卡走默认名，两者互不干扰）。
- **AC4（负向闭环 · 托管三接线）**：① `status` 将该会话列在派生/一次性节，且**本仓**会话无「他仓」「不可判定」标注；② `close` 回收成功（rc=0、pane 消失、名册不再列出）；③ `close` 输出**不含**「应 `ensure --force` 重开」常驻警告（反例：对常驻角色执行 `close` 时该警告仍须出现 —— 双向断言）；④ 会话残留于 `tasks-state` 标记的用例：已归档 task ⇒ `status` 给出「残留」标注且给出可执行 `close` 命令；⑤ 回收后 `status` 与 intercom 名册双清。
- **AC5（设计一致性 · 门禁与零回归）**：① `check` rc=0、`roles=6` 不变、`files=` 变化有说明、新增「下游角色卡」节在无卡时跳过且不影响 rc；② `npm test` rc=0、`tests/t4` 全量 PASS/FAIL/SKIP/DEGRADE 精确数字（发布口径 SKIP=0/DEGRADE=0/非白名单 NOTE=0）；③ **零回归探针**：不带 `--card` 的 6 角色 `ensure`/`status`/`close` 输出与旧版**逐字等价**（`git show main:.agents/scripts/nao-fleet.sh` 对照，允许新增节，不允许既有行改动）；④ `git diff --stat .agents/roles.yaml` = 0；⑤ 广告面（`--help`）含 `--card` 与一句用途说明。

## 八、上线闭环

- **灰度**：不适用（CLI，新参数可选，默认关闭）。
- **监控**：发布后首次真实使用由 PM 在下游仓实测并在 release notes 技术细节记录（首个样本 = 本批自身的 review 会话）。
- **回滚**：`git revert <main-squash-sha>`（单条）；下游不受影响（不依赖新参数）。
- **发布**：**v0.21.0（MINOR）**；`docs/releases/v0.21.0.md`（用户可见段置顶：一句话 + 一段示例命令）；`npm` **需重发**（`nao-fleet.sh` 属包内容）；下游接入 = 各仓 `AGENTS.md` 加一行指针（不复制命令细节，指向 `README.md` 一节）。
- **文档同步**：`README.md` 新增一节 + `intercom-protocol.md` 脚注 + `nao-fleet.sh` 帮助 + PM 卡 §六（新增「按需角色会话」一句，版本 bump + 广播）。

## 九、变更治理

- **变更权限**：范围/AC 变更需 PM 与 architecture-designer 双签；实现方式（参数解析细节、`status` 识别口径）由 arch 定稿、PM 不改技术细节。
- **文件归属**：`nao-fleet.sh` + `tests/t4/**` = rd-infra；`docs/reports/*-probe.sh` = rd-infra；PRD/台账/验收评论/发布说明 = PM；QA 报告 = QA 落盘随分支提交；`README.md`/协议脚注/PM 卡 = 按职责分（机制文本 PM 可提交，脚本一律 RD）。
- **流程**：Issue（本 PRD 定稿后建）→ 分支 `feat/<issue-id>-downstream-role-sessions` → 开工确认卡 → **arch 评审（涉及信任边界与识别口径，必过）** → 派 rd-infra-T537 → QA 独立复核 → PM 验收 → RD `--squash` 合并 → 发布 v0.21.0。
- **批次边界**：本批不夹带其它遗留项（`T536-O1`–`O4` 仍待另批）。

## 附录 A · 优先级打分

- **战略筛子（四问）**：契合「机制提供方」定位 ✓（下游自持角色，上游零清单负担）；复用既有语义 ✓（锚点/派生/回收全复用）；不损既有 AC ✓（`--card` 为可选参数）；对用户价值明确 ✓（PM 批次中段刚需）。结论：**通过**。
- **MoSCoW**：**Must**（缺口明确、无替代品，overlay 方案需下游维护清单且绑常驻语义）。
- **RICE**：Reach **3**（当前 3 个下游仓 + 未来用户，属团队级工具）× Impact **3**（解锁「按需角色」整个档位）× Confidence **0.8**（拉起/锚点/回收语义已验证；未验证者仅 `status` 识别口径）× Effort **1.5**（单文件 + 用例 + 3 处文档）⇒ **RICE ≈ 4.8**。
- **Kano**：**期望型**（做了满意度上升，不做不会立刻抱怨但会持续用错——手工拉起的会话游离在纪律之外）。

## 附录 B · 开工卡拍板（2026-11-01 · 用户 ask-me）

- **D1 开工**：现在开工，按本开工卡。
- **D2 arch 强度**：**完整评审**（信任边界 · `status` 识别口径 · `close` 语义分叉 · 与 subagent/overlay 划界）。
- **D3 卡路径口径**：**限定目录** —— 只接受 `<repo>/.agents/prompts/<file>.md`（比「任意路径 + 工作区内」更严）；已写入 §三 A 与 BR3、AC2 增一条 symlink 逃逸用例。
- **D4 待推送提交**：`main` 领先 `origin/main` 1 条（`a8a678a`，T536 发布收尾纯文档）→ **派 rd-infra-T537 首步按显式 sha push**（PM 授权），使本 PR diff 干净；PM 不 push main。

## 附录 C · 与既有能力的关系（防误用）

- **pi-subagents 项目 agent**：适合一次性并行调研/评审（省 token、无交互身份）；本需求适用于**需多轮质询 + 有回执身份 + 需进入舰队纪律**的会话。二者并存，卡可两用（加 `name` 字段即被 subagents 扫到），文档需说明差异。
- **overlay 清单目录（`NAO_SKILLS` 指向下游清单）**：效果是把下游角色变成**常驻**；与本需求的按需语义互斥。同一项目不建议两法并用（名册/清单双源）。
- **`ensure --task` 派生**：本需求在其之上增加「卡来自下游」一维；`--task` 语义（并行隔离、`close --task`）保持不变。
