<!-- ADR（T527）：骨架 @.agents/templates/adr.md.example；实施类内容下沉 docs/reports/2026-10-14-T527-arch-review.md -->

# ADR：角色→子代理 agent 的单一事实（运行时注册扩展）

- 状态：已接受（待落地 v0.18.5）
- 更新：2026-10-14
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-14-role-agents-runtime-registration.md` · 评审报告 `docs/reports/2026-10-14-T527-arch-review.md`

## 背景

- 舰队 6 角色仅由 `nao-fleet.sh:1297` 的 `--append-system-prompt` 注入；pi-subagents 子代理路径**完全没有** nao 角色口径（卡无 `name`，不被发现）。
- 四条静态路线均不成立：A 生成式副本（复制 40,582 B，且带不了机器相关锚点）· B 引用式（`@` 只在 CLI/TUI 首条消息展开，非 system prompt）· C `agentOverrides.systemPrompt`（漂移反向 + 触用户配置）· F 卡片即 agent（违 AC8：manifest 不得含 `.agents/prompts`）。
- 约束：不改舰队注入路径与 6 张卡正文；零副本 / 零生成物；既有 `check` 与 `npm test` 门禁须保持绿。

## 决策

新增**包内扩展** `.agents/extensions/nao-role-agents.mjs`（`package.json` `pi.extensions` 声明）：`session_start` 运行时读同一批 `.agents/prompts/*.md` 与 `.agents/roles.yaml`，经 `pi-subagents:runtime-agent-register:v1` 注册 6 个 `nao-<role-id>`（`systemPrompt` = 卡正文 + 与 `nao-fleet.sh:1068` 逐字一致的锚点行 · `systemPromptMode=replace` · `inheritProjectContext=true`）；注册/装配失败仅 warn。

## 理由

1. 业务匹配：角色在「子代理路径」可用，且与常驻会话**同卡同锚** —— 漂移由构造消除（无副本可漂）。
2. 成熟度：运行时注册 v1 是 pi-subagents **长期公开契约**（0.67.0 文档已含该节，装配期即挂监听）；本批零 LLM 实测注册 ×6 成功。
3. 团队能力：1 扩展 + 1 用例 + 1 `check` 断言，复用既有门禁；零新依赖、零网络。
4. 成本效益：PATCH 级成本换掉「40 KB 复制 + 生成器 + 守卫」的长期维护面；AC8/BR2 不破。

## 对照过的备选模式

1. **维持现状（仅 fleet 注入 + builtin agents）** —— 适用：永不使用会话内角色子代理；代价：子代理无角色口径（T512 §2.5）；**不采纳**：⑦ 已闭（协议授权会话内子代理），缺口显式。
2. **生成式静态薄壳（A）** —— 适用：机制文件路径固定且机器无关；代价：复制 40,582 B + 生成器 + 守卫，且静态文件**无法携带机器相关 `NAO_SKILLS` 锚点**（shim-only 下卡内引用静默失效）；**不采纳**。
3. **引用式薄壳（B）** —— 适用：宿主展开 `@` 引用；代价：Pi 仅在 CLI/TUI 首条消息展开、pi-subagents 不做展开 ⇒ 退化为「让模型自己读」，无机械保证；**不采纳**。
4. **`agentOverrides.<name>.systemPrompt`（C）** —— 适用：单机单作者；代价：漂移反向（卡升级 settings 不动）+ 触用户/项目配置 + 大段正文进 JSON；**不采纳**。
5. **卡片即 agent（F）** —— 适用：无 AC8 门禁的仓；代价：违 `cases/06` 断言（manifest 不得含 `.agents/prompts`）+ legacy 发现面污染 + 静态锚点缺失；**不采纳**。
6. **运行时注册扩展（E-lite）** —— 适用：卡为单一事实、需机器相关锚点、要求零副本；代价：依赖 pi-subagents 且在每个 trusted 会话加载；**采纳**。

## 限制与已知边界

- **tools 不设**：子代理**不被工具约束为只读**，角色卡文本是唯一约束（`arch-designer` 的 `codegraph` 依赖 `bash`，无法干净只读化）。
- **`advertise` 机制不支持**（上游显式拒 `unknown fields: advertise`）；可发现性 = `subagent({action:"list"})` + 文档。
- **`inheritProjectContext` 属实现面字段**（上游只文档 `description/systemPrompt/tools`）：行为面由 qa 一次 live 实证；不被 honor 则回落「systemPrompt 内嵌『先读工作区根 `AGENTS.md`』指示行」。
- **trust 前提 + 行为面扩散**：扩展随包加载，**未授信会话不出现**（与 `pi.skills` 同前提）；**每个 trusted 会话都加载**（不止舰队会话），逃生阀 `NAO_ROLE_AGENTS=off`。
- **`systemPrompt` 首尾空白归一**：上游硬性要求 `trim()` 一致 ⇒ 只归一卡正文首尾、**内部逐字节保留**；`check` 的 `pi.extensions` 断言**在非包根（无 `package.json`）跳过、不判 FAIL**（保 `cases/09` 夹具）。
- **动态读卡口径**：改卡正文 ⇒ 两路自动同步，**不构成 FAIL**；能 FAIL 的是**破坏不变量的编辑**（`frontmatter role:` 与 `roles.yaml` 不一致、卡文件缺失、锚点行改写）与**夹具副本改卡**（证字节比对非自证）。
- **命名 vs T525 身份模型**：`nao-<role-id>` / 不设裸 alias / 不占 `subagent-`；agent 名与舰队会话名是**不同命名空间**（pi-subagents 不拦 `subagent-` 前缀，故由 `cases/17` 自钉）；子代理会话名仍为 `subagent-nao-qa-<runid>` ⇒ 命中 T525 排除面，身份模型不变。

## 相关指针

- 评审报告（六候选全文 / 三栏清单 / 接线与用例 / 负控与失败模式）：`docs/reports/2026-10-14-T527-arch-review.md`
- 实现与探针：`.agents/extensions/nao-role-agents.mjs` · `tests/t4/cases/17-role-agents.sh` · 分支 `nao/role-agents`（RD 落地 `de07437`）· 协议指针 `.agents/common/intercom-protocol.md` §会话内子代理

## 参考来源

- `docs/reports/2026-10-12-pi-subagents-compat-review.md` §2.5/§4.4（T512）· 2026-10-14 引用 · 子代理路径无角色卡。
- [pi-subagents · docs/extension-api.md](https://github.com/nicobailon/pi-subagents/blob/main/docs/extension-api.md) · 访问 2026-10-14 · `pi-subagents:runtime-agent-register:v1` 公开契约。
- [pi-subagents · docs/agents.md](https://github.com/nicobailon/pi-subagents/blob/main/docs/agents.md) · 访问 2026-10-14 · agent 发现/覆盖字段（`advertise` 等）。
- 本地包 `~/.pi/agent/npm/node_modules/pi-subagents`（0.78.0）：`src/agents/runtime-agent-registry.js`（`advertise` 拒绝）· `src/agents/runtime-agent-events.js`（同步事件）· `src/runs/shared/child-launch.js:207-230`（body 直灌 systemPrompt）· 访问 2026-10-14。
- Pi `docs/packages.md` · `docs/cli.md`（`pi.extensions` manifest / 项目 trust / `@path` 仅首条用户消息）· 访问 2026-10-14。
