# PRD：角色→子代理 agent 的单一事实（运行时注册扩展）

- 状态：**已交付（v0.18.5 · PR #45 squash `fb4c106` · 归档 2026-10-27）** · Owner：PM · 更新：2026-10-27
- 开工确认卡（2026-10-14 · ask-me 用户拍板 6 项）：D1 方案 = **做 E-lite**（包内扩展运行时注册 6 个 `nao-<role-id>`；含 **M1 零 LLM 前置探针**，失败即转 **D** 并回报）· D2 tools = **Phase 1 不设**（ADR 须写「子代理不被工具约束为只读，角色卡文本是唯一约束」）· D3 命名/可发现性 = **`nao-<role-id>` + 不设裸 alias + 不启 advertise** · D4 = **采纳逃生阀 `NAO_ROLE_AGENTS=off`** + 文档写明分发面 · D5 版本/npm = **v0.18.5（PATCH）+ 发布时重发**（用户执行 `npm publish`）· D6 立项 = **降级 `nao/role-agents`** + **授权 arch 落盘 ADR/评审报告**
- 指针：上游 = 用户 2026-10-14 选定台账 **⑧（= T512-③）**「角色→pi-subagents agent 薄壳」· 来源 `docs/reports/2026-10-12-pi-subagents-compat-review.md` §2.5/§4.4 · 成熟度判定 = 命中 `pm-to-spec.md` §一.4 · **QA 实测复核** = 2026-10-14 `done(full)`（**引用式薄壳实测不可行**；发现序/信任/字段全部钉死）· **arch 结构评审** = 2026-10-14 `done(full)`（六候选对比 → **推荐候选 ⑤ 运行时注册扩展（E-lite）**；A/B/C/F 均不采纳）
- 优先级：中（角色在「子代理路径」可用 + 消除双份提示词）· 战略筛子：命中「机制单一事实 / 角色可用性」→ 做 · MoSCoW：Should · Kano：期望型 · RICE ≈6.0（附录）

## TL;DR（≤5 行）

- **做什么**：新增**包内扩展** `.agents/extensions/nao-role-agents.mjs`，在 `session_start` 时**读取同一批角色卡**并运行时注册 6 个 `nao-<role-id>` 子代理（零副本、零生成物）；`package.json` 增 `pi.extensions`；加装配/契约/幂等探针与 `check` 断言。
- **给谁**：6 个舰队角色（其派生的子代理继承同一角色口径）、下游仓（装包即得）、维护者（改卡即两端同步）。
- **成功标准**：`cases/17` 装配字节比对 + 锚点 cross-assert + 命名双向一致 + 幂等全绿；`check` rc=0；断言只增不减（基线 **404**）。
- **不做什么**：不做静态副本/生成物（A）· 不做引用式薄壳（B，实测不可行）· 不用 `agentOverrides.systemPrompt`（C）· 不把卡片改造成 agent 登记文件（F，违 AC8）· 不设 `tools`/`model`/`advertise` · 不改舰队 `--append-system-prompt` · 不改 6 张卡正文 · 不在门禁内真跑 LLM 子代理。

## 一、问题证据

- **现状（本机实测）**：舰队 6 角色由 `nao-fleet.sh:1297` 以 `--append-system-prompt <卡片临时副本>` 注入（卡片 = `.agents/prompts/*.md`，frontmatter 仅 `description/role/version/updated`，**无 `name:`**）；`subagent({action:"list"})` **仅 builtin** ⇒ **子代理路径完全没有 nao 角色口径**（T512 §2.5 结论仍成立）。
- **四条静态路线实测/评审均不成立**：
  - **A 生成式静态薄壳**：复制卡片正文 ≈ **40,582 B**（6 卡 569 行）+ 生成器 + 守卫；且**静态文件带不了机器相关的 `NAO_SKILLS` 锚点**（仓库禁绝对家目录路径、下游路径不同、shim-only 项目内无 `.agents/prompts/`）⇒ 卡内 `@.agents/...` 引用在 shim-only 下**静默失效**。
  - **B 引用式薄壳**：**实测不可行** —— `@path` 只用于 CLI 位置参数/TUI 首条消息；pi-subagents 把 agent body 直接灌入 `systemPrompt`（`src/runs/shared/child-launch.js:207-230`），**不做任何 `@` 展开**；1 次最小只读 delegate 双证：子代理逐字复述 `@…` 行、被引文件内容不在上下文中。
  - **C `agentOverrides.<name>.systemPrompt`**：settings 里的**字面串**（同样不展开）+ 漂移方向**相反**（卡升级而 settings 不动）+ 大段卡正文进 JSON 不可评审。
  - **F 卡片即 agent**（给卡加 `name` + manifest 声明目录）：**直接违反既有 AC8 机械门禁** —— `tests/t4/cases/06-contract-guards.sh:17-25` 断言 `JSON.stringify(pi)` 不含 `.agents/prompts`。
- **采纳路线（E-lite）的机制证据**：pi-subagents 有**长期公开契约**「Runtime agent registration v1」（`docs/extension-api.md`；`src/extension/index.js:735` 在装配期注册监听）；**本会话以假 `pi.events` 总线实证全链路**：`registerRuntimeAgentEventListener(pi)` + 6× `registerAgentViaEvents` → `listRuntimeAgentConfigs(pi)` = **6 条**（`nao-pm/nao-arch-designer/nao-rd-fe/nao-rd-be/nao-qa/nao-rd-infra`）· `inheritProjectContext=true` · `systemPromptMode=replace`（**零 LLM、零真 pi**）。实现面还接受 `tools/model/thinking/...`；**`advertise` 被显式拒**（实测 `unknown fields: advertise`）。
- **5 Whys**：子代理路无角色口径 ← 口径只由舰队注入路径承载 ← T512 只做调研、把此项列为「缓/有替代」← 替代品（builtin agents）与 nao 角色无关 ← **从未有「同卡两路共用」的机制**（静态复制与引用展开两条路都走不通）。
- 证据留痕：T512 报告 §2.5/§4.4 · QA 本轮只读实测（发现序/信任/字段/引用不可行）· arch 本轮结构评审（六候选 + E 机制实证）· `docs/tasks-state.md` 台账 ⑧。

## 二、目标指标

- **北极星**：**同一角色在「常驻舰队」与「子代理」两路共用同一卡文件与同一环境锚点** —— 漂移由构造消除（无副本、无生成物）。
- **预期**：① 6 个 `nao-<role-id>` agent 在 trusted 会话可注册且可列出（`listRuntimeAgentConfigs` == 6）② 其 `systemPrompt` 的卡正文段与卡文件**逐字节一致**、锚点行与 `nao-fleet.sh:1068` **逐字一致** ③ 名称集与 `roles.yaml` **双向一一对应** ④ 幂等（连跑 2 次 effect=0）⑤ `check` rc=0 · 断言只增不减（基线 **404**）。
- **观测**：`npm test` rc + `cases/17` 逐条 + `check` rc + 负控（改卡/删声明/加 `advertise`）。

## 三、范围 / 非范围

- **范围**
  1. **新增包内扩展** `.agents/extensions/nao-role-agents.mjs`（≈120–180 行）：可导出的**纯装配函数**（读 `.agents/prompts/*.md` + `.agents/roles.yaml` → 6 条定义）+ 薄 glue（`session_start` 注册、`session_shutdown`/reload 前 `dispose`、失败**仅 warn 不 throw**、`NAO_ROLE_AGENTS=off` 逃生阀）。
  2. **定义口径**：`systemPrompt` = **卡正文（去 frontmatter）逐字节** + **环境锚点行**（与 `nao-fleet.sh:1068` 的 `## 环境锚点 / - NAO_SKILLS=` 句**逐字一致**）· `systemPromptMode=replace` · `inheritProjectContext=true` · `description` 取自卡 frontmatter · 名称 `nao-<role-id>`（**不设 alias**、**不占 `subagent-`**）。
  3. **`package.json`**：增 `"pi": { "skills": [...], "extensions": ["./.agents/extensions/nao-role-agents.mjs"] }`（**不**声明 `pi.prompts`、**不**引用 `.agents/prompts` ⇒ AC8 不破）。
  4. **`check` 增 1 条断言**：声明了 `pi.extensions` 且该文件存在（防「声明漏写 ⇒ 静默无 agent」）。
  5. **新增 `tests/t4/cases/17-role-agents.sh`**：① 装配字节比对（6 条 `systemPrompt` 的卡正文段 == 卡文件去 frontmatter 正文）② 锚点 **cross-assert**（与 `nao-fleet.sh:1068` 逐字）③ `description` == 卡 frontmatter ④ 名称集 ↔ `roles.yaml` **双向一一对应** ⑤ 无 `subagent-` 前缀 ⑥ schema 探针（假 `pi.events`：注册 ×6 成功 + `listRuntimeAgentConfigs` == 6 + `dispose()` 幂等）⑦ 幂等（`session_start` 连发 2 次 ⇒ 净 6 条）⑧ 负控（改卡 1 行 ⇒ FAIL；删 manifest 声明 ⇒ `check` FAIL；加 `advertise` ⇒ FAIL）· `pi-subagents` 缺失 ⇒ `t4_skip` · **不断言其内部文案**。注册 `run.sh` `"17"` + usage `<01-16>` → `<01-17>`。
  6. **ADR**：`docs/adr/2026-10-14-role-agents-runtime-registration.md`（arch 落盘；含限界：tools 不设 / `advertise` 不支持 / `inheritProjectContext` 属实现面字段 / trust 前提 / 行为面扩散）。
  7. **文档**：`tests/README.md` 用例 17 行 · `docs/releases/v0.18.5.md` · 指针一行（`roles.yaml` 注释或 `intercom-protocol.md` 子代理小节：**常驻会话 = `--append-system-prompt`；子代理 = runtime 注册；同卡同锚**，不掺 ⑧ 条款）。
- **非范围**（各带理由）
  - **不做静态副本/生成物（A）与卡片即 agent（F）**：理由 A 复制 40 KB 且无法携带机器相关锚点（shim-only 下卡内引用静默失效）；F 违 AC8 门禁 + 污染 legacy 项目发现面。
  - **不做引用式薄壳（B）/`agentOverrides.systemPrompt`（C）**：理由 QA 实测 `@` 不展开；C 漂移反向且触碰用户/项目配置。
  - **不设 `tools`（Phase 1）**：理由 只读化需按 6 卡发明策略，且 `arch-designer` 的 `codegraph impact` 依赖 `bash`；**ADR 须写明「子代理不被工具强约束为只读，角色卡文本仍是唯一约束」**。
  - **不设 `model`**：理由 沿用 operator 默认；T512 §4.5「子代理 model 白名单缺口」**继续记录、本批不处理**。
  - **不做 `advertise`**：理由 运行时注册**不支持**（实测拒绝），可发现性靠 `subagent({action:"list"})` + 文档。
  - **不改舰队注入路径、不改 6 张卡正文、不在门禁内真跑 LLM 子代理、不做配置安装器**：理由 各自边界与风险面（舰队路径是既有稳定面；卡正文改动会放大回归面；LLM 成本/不确定性；安装器属用户配置动作）。

## 四、用户场景

- 画像 A（角色会话内委派）：`qa` 会话起一个 `nao-qa` 子代理做独立复核 ⇒ 子代理拿到**与父角色同一份卡口径与同一锚点**（能解析 `.agents/skills/...` 路径、知道自己受项目 `AGENTS.md` 最高约束）。
- 画像 B（维护者改卡）：只改 `.agents/prompts/qa.md` ⇒ **舰队与会话内子代理两端同时生效**；忘记改锚点/声明/加 `advertise` 都会被门禁拦。
- 画像 C（下游仓）：装 nao 包即获得 6 个 `nao-*` agent（**前提 = 会话 trusted**，与 `pi.skills` 同前提）；不装则不出现。
- 画像 D（现场止血）：行为面不想扩散时 `NAO_ROLE_AGENTS=off` 一键关闭。
- 状态清单：**trusted 会话** = 注册 6 个 agent；**未授信** = 包不加载 ⇒ 无 agent（文档写明前提）；**`NAO_ROLE_AGENTS=off`** = 不注册；**注册失败** = 仅 warn（最坏=无 agent，不伤会话）；**卡被改而未同步** = `cases/17` FAIL。

## 五、业务规则

- **BR1 单一事实零副本**：扩展**运行时**读 `.agents/prompts/*.md`；**禁**任何副本/生成物入库（40 KB 复制 + 漂移面）。
- **BR2 同卡同锚**：`systemPrompt` = 卡正文逐字节 + 锚点行；锚点行与 `nao-fleet.sh:1068` **逐字一致**（唯一双写点，由 `cases/17` cross-assert 兜住）。
- **BR3 命名纪律**：规范名 `nao-<role-id>`（6 个）· **不设裸 alias**（`mergeRuntimeAgents` 对同名/同 alias 冲突**抛错**，会伤下游会话）· **不占 `subagent-`** 前缀（T525 保留面；agent 名与舰队会话名是不同命名空间，须自行钉住）。
- **BR4 上下文口径**：`systemPromptMode=replace` + `inheritProjectContext=true` —— 卡片自述「项目根 `AGENTS.md` 最高优先级」在 replace 下默认**不继承**，不设即静默丢契约。
- **BR5 韧性**：注册/装配失败**仅 warn、绝不 throw**；`session_start` 先 `dispose` 再注册、`session_shutdown` `dispose` ⇒ **幂等**（连跑 2 次 effect=0）。
- **BR6 逃生阀**：`NAO_ROLE_AGENTS=off` ⇒ 不注册（行为面扩散时的现场止血）。
- **BR7 门禁纪律**：探针**零 LLM/零网络**、确定性；缺 `pi-subagents` ⇒ `t4_skip`（不 FAIL）；**不断言** pi-subagents 内部文案；事件名 + version 作为契约点记录（防升版脆断，T526 同纪律）。
- **BR8 AC8 不破**：`package.json` 的 `pi` 段**只**增 `extensions`；**不得**出现 `.agents/prompts` 引用、**不得**声明 `pi.prompts`（既有 `cases/06` 断言须保持绿）。
- **BR9 分发面诚实**：扩展在**每个 trusted 会话**加载（非仅舰队会话）；ADR 与文档须写明该扩散面与 trust 前提。

## 六、NFRs

- **时长**：`cases/17` 为纯本地只读探针（毫秒级）；全量门禁仍 ≈2min 量级。
- **可移植性**：缺 `pi-subagents` ⇒ SKIP；不依赖 `pi-intercom`/tmux/网络；不写用户配置。
- **安全/隐私**：扩展零外发、零敏感值、零绝对家目录路径；只读卡文件。
- **可诊断**：装配/注册失败 warn 指名原因；探针失败指名缺哪条（卡正文/锚点/命名/幂等）。
- **幂等（红线）**：连跑 2 次 effect=0（`dispose` 先于注册；`check` 与 `cases/17` 双覆盖静态与装配面）。

## 七、AC

- **验证接缝（QA/arch 已确认 2026-10-14）**：新增 `tests/t4/cases/17-role-agents.sh`（只读 Node：装配字节比对 + 锚点 cross-assert + 命名双向 + 假总线 schema + 幂等 + 负控）+ 复用 `npm test` 门禁；`check` 增 1 条 manifest/文件存在断言（不新增第二接缝）。
- **AC1（主路径 · 接缝复核）**：Given 本批需求，When QA/arch 复核候选，Then 确认/改定并记录日期 —— **已完成 2026-10-14**（QA 判 B 不可行；arch 出六候选定稿 → 采 E-lite）。
- **AC2（主路径 · 单一事实）**：Given 扩展装配产物，When `cases/17` 比对，Then 6 条 `systemPrompt` 的卡正文段与对应卡文件（去 frontmatter）**逐字节一致**，且 `description` 等于卡 frontmatter（BR1/BR2）。
- **AC3（设计一致性 · 同卡同锚）**：Given 锚点行，When 与 `nao-fleet.sh:1068` 逐字比对，Then **一致**（cross-assert；任一改动即 FAIL）（BR2）。
- **AC4（业务规则 · 命名与清单）**：Given 6 条定义，When 与 `.agents/roles.yaml` 双向比对，Then **一一对应（不漏不多）**、名形为 `nao-<role-id>`、**无裸 alias**、**无 `subagent-` 前缀**（BR3）。
- **AC5（边界 · schema 与幂等）**：Given 假 `pi.events` 总线，When `registerAgentViaEvents` ×6 + 连发 2 次 `session_start`，Then 注册成功、`listRuntimeAgentConfigs` == 6、`dispose()` 幂等、**净 6 条**（BR5）。
- **AC6（负向闭环 · 非空转）**：Given 三态改坏（改卡 1 行 / 删 `package.json` 的 `pi.extensions` 声明 / 给定义加 `advertise`），Then 对应探针或 `check` **FAIL** 且指名缺项；还原后全绿（附 md5 证据）。
- **AC7（异常 · 能力门与韧性）**：Given `pi-subagents` 缺失，Then `cases/17` **SKIP**（不 FAIL）；Given 注册路径注入失败，Then 脚本/扩展**仅 warn**、不 throw（可用桩证）；Given `NAO_ROLE_AGENTS=off`，Then 不注册（BR6/BR7）。
- **AC8（一致性 · 门禁与文档）**：Given 交付终态，When 跑全范围门禁，Then `check` rc=0（roles=6 · **files 48→49**，`check` 只统计 `.agents/**`，本批 +1 = 新扩展文件）· `npm test` rc=0 · `17` 在册 · 断言只增不减（基线 **404**）· **`cases/06` 的 AC8 断言仍绿**（BR8）· `tests/README.md` 用例 17 行 · ADR 落盘 · `docs/releases/v0.18.5.md` 落盘 · 指针一行到位 · 台账 ⑧ 收口。

## 八、上线闭环

- **版本**：**v0.18.5（PATCH）** —— 改动含 `.agents/` 与 `package.json`（**均在 tarball 内**）⇒ **需重发 npm**（先例：T522/T524/T525/T526）。
- **灰度**：不适用；可发现性靠 `subagent({action:"list"})`（不启 `advertise`）。
- **回滚**：删/停扩展声明（`pi.extensions`）即回到现状；或 `NAO_ROLE_AGENTS=off` 现场关闭；已 push tag 不删。
- **发布前置**：`npm run test:t4:full` **rc=0**（**空载**跑；遇 FAIL **先单例复现再重跑全量**，O-1/O-2 口径）。
- **监控**：不适用；指标 = `npm test` rc + `cases/17` 逐条 + 断言数 + `check` rc。

## 九、变更治理

- **流程**：降级批次分支 `nao/role-agents`（无 Issue）→ PR → **arch 落盘 ADR + 评审报告**（同一分支，序位在 RD 落地后）→ qa 独立复核 + **一次 live 实证**（真 pi 会话 `subagent list` 见 6 项；`inheritProjectContext` 是否被 honor；如不被 honor 则回落「systemPrompt 内嵌『先读工作区根 AGENTS.md』指示行」并回报）→ PM 验收 → RD `--squash` 合并（显式 `--subject` + `--match-head-commit`；**推送用显式 sha 源**）→ PM 发 tag/Release（按 §八 决定 npm）→ PRD 归档。
- **实现分工（同分支顺序写，禁并发）**：① **rd-infra** 落扩展 + `package.json` + `check` 断言 + `cases/17` + `run.sh` 注册 + `tests/README.md` + `docs/releases/v0.18.5.md` → 回执；② **arch-designer** 落 ADR + `docs/reports/2026-10-14-T527-arch-review.md` + ADR 索引一行 → 回执；③ **qa** 独立复核（装配/schema/幂等/负控 + live 实证）+ 报告 `docs/reports/2026-10-14-T527-qa-verify.md` → `done(full)`。
- **架构评审闸门**：**已完成 2026-10-14**（arch `done(full)`：六候选对比 → 采 **E-lite**；A/B/C/F 不采纳理由逐条；**ADR 达门槛**，落盘待授权）。
- **M1 前置探针**：开工卡若采纳 E-lite，则由 RD 在实现前先跑一次**零 LLM 可达性探针**（假总线 + `dispose` 幂等）；失败即转 **D（本批不做）** 并回报，不带病落地。
- **版本记录**：PRD 落 `docs/prds/2026-10-14-role-agents-runtime-registration.md`（本文件；归档时登记 `docs/prds/README.md`）；运行时状态记 `docs/tasks-state.md`（⑧ 收口）。
- **待裁量项**：本批关闭 ⑧；维持 ⑨（T512 流程 A/B）· ⑫后半 · ①–⑤ 更早遗留 · R1/R2（探针健壮性）· O-1/O-2（负载偶发）· T512 §4.5 model 白名单缺口。

## 附：RICE 与依据

- Reach 2（6 个角色会话 + 下游仓）· Impact 2（消除双份提示词、角色在子代理路径可用）· Confidence 0.8（机制由假总线实证，但 **live 行为面**尚待一次真 pi 实证）· Effort 0.8（1 扩展 + 1 用例 + 1 断言 + ADR + 文档）⇒ **RICE ≈6.0**。
- 战略筛子：命中「机制单一事实 + 角色可用性」→ 本批做；「静态副本（A）· 卡片即 agent（F）· tools 只读化 · model 白名单 · advertise」被筛除（各自理由见 §三）。

## 十、派发记录 / 验收结果 / 变更记录（归档 2026-10-27）

- **派发与顺序**（同分支顺序写，禁并发）：① `rd-infra-T527` 落实现（`de07437`）→ ② `arch-designer-T527` 落 ADR + 评审报告（`e228706`）→ ③ `qa-T527` 独立复核 + live 实证（报告 `docs/reports/2026-10-14-T527-qa-verify.md`，入库 `3ba2d5e`）→ ④ `rd-infra` 执行合并（PM 验收授权）。
- **需求分支 / PR**：`nao/role-agents`（降级批次，无 Issue）· PR [#45](https://github.com/Nathan3303/nao-skills/pull/45) · **squash 合并 `fb4c106`**（main 恰 1 条 · 无 `wip()` · 分支已删净）· 验收评论 issuecomment-6444421262。
- **验收结论**：**通过（AC2–AC8 全过）**。QA 独立复核 GO（`check` rc=0 ×2 · roles=6 · **files=49** · `npm test` rc=0 99s · **17/17 PASS · PASS 449**（−45 = 404 基线）· SKIP=0/DEGRADE=0 · 空载 `test:t4:full` rc=0 · 自建探针 53/0 · 三态负控 + 自建两态 md5 还原 · live：6 个 `nao-*` 可列且 `inheritProjectContext` 被 honor）。PM 独立重跑 `check`（rc=0 · files=49）并读实现核对 AC2–AC8；发布前置 `test:t4:full`（空载）rc=0 · SKIP=0/DEGRADE=0。
- **变更记录**：AC8 口径订正（`files` 48→50 ⇒ **48→49**，`check` 只统计 `.agents/**`）· 版本 v0.18.5（PATCH）。
- **发布**：tag `v0.18.5` + GitHub Release 已发（标题 = 裸版本号）；npm 重发由用户执行，判据 = `dist-tags.latest` = 0.18.5 且 `dist.integrity` 与本地 `npm pack` tarball 逐字节一致。
- **遗留项**：**R1（中 · 发布闭环硬条件）** npm 注册表 → `pi.extensions` 未直接观测，发布后须冒烟（`pi install -l --approve npm:@nathan33/nao-skill@0.18.5` → `subagent list` 见 6 个 `nao-*`），失败则回退声明或 `NAO_ROLE_AGENTS=off` · **R2** 已订正 · 探针健壮性（`cases/17` 与上游事件名/导出名硬耦合，升版漂移 fail-loud）留后续小项。
