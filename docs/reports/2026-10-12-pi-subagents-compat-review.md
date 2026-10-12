# pi-subagents × nao 舰队 兼容性调研（T512）

- 状态：定稿 · 更新：2026-10-12 · Owner：arch-designer
- 指针：`.agents/scripts/nao-fleet.sh` · `.agents/common/intercom-protocol.md` · `docs/ARCHITECTURE.md` · `docs/adr/2026-10-08-nao-skills-single-skill-pi-package.md`
- 边界：只调研、零代码；不改机制/测试/构建；不建 Issue/PR。

## 结论摘要（TL;DR）

- 二者**可组合，非同层替代**：nao = 跨进程常驻舰队 + 交付治理闸门；pi-subagents = 单会话内子代理执行原语（含 worktree / 验收 / 工件 / retention）。
- 实测（本会话）：pi-subagents 0.77.0 在 nao 会话中**已可用**；`subagent({action:"list"})` 仅返回 builtin + 外部 CLI，**无 nao 角色**（`.agents/prompts/*.md` 不构成 agent）。
- 推荐组合层次 = ①会话内只读嵌套（默认）→ ③显式 intercom 桥（仅 PM 派生角色时）。
- **不建议**用 pi-subagents 替代 6 常驻会话：6 项 nao 硬闸门中 3 项失效、2 项削弱（§2）。
- 需用户裁量决策点 3 个（§5）。

## 1. 互斥还是可组合？可行组合层次

结论：**可组合**，分层归属不同。可行层次与成立条件：

1. **角色内嵌套**——nao 角色会话在自己 turn 内 `subagent` 起只读子代理（scout / researcher / oracle / reviewer / evidence-auditor）。条件：子代理由父会话负责（父仍发 nao 回执）；只读或单写；产物落盘；父忙碌时 intercom 状态保持 `thinking`，PM 忙闲闸门自然生效。
2. **PM 派生「角色子会话」**——PM 直接 spawn 子代理代行 RD/QA。条件（缺一不可）：配 `intercomBridge` + `orchestratorTarget` 可达 + 子代理有 `intercom` 工具 + 子代理自回 `[编号] done`；tasks-state 仍为唯一状态源。不满足 ⇒ 降级为「PM 自述回执」，违反闸门语义。
3. **intercom 桥（子→PM）**——`contact_supervisor`↔`subagent_supervisor` 是**进程内父子通道**（按 parent session id 限定，不依赖 pi-intercom）；跨到 nao 线程须 `intercomBridge.instructionFile` 注入显式目标。条件：目标可解析（命名会话如 `pm`）；无目标时桥不激活。
4. **替代常驻舰队**——不成立（§2、§5）。
5. **其它**——fleet 继续做进程监督者，子代理只做会话内并行（①的工程化渐进路径）。

依据：`pi-subagents/docs/agents.md`（agent 优先级 / builtin 清单）、`skills/pi-subagents/references/execution-controls.md` §Subagent + Intercom Coordination、`src/intercom/intercom-bridge.js`（`resolveIntercomBridge`/`diagnoseIntercomBridge`/`applyIntercomBridgeToAgent`）、`nao-fleet.sh:886` `spawn_one`（`--name` / `--append-system-prompt`）。

## 2. nao 硬闸门逐条判定（保持 / 削弱 / 失效）

1. **终态回执 done(lite|full)**——嵌套：**保持**（父角色自留回执义务，子代理输出仅作证据，须写进回执「测试」字段）；子代理代行角色：**失效**（run 结果 ≠ `[编号] done`，PM 匹配不到）。补救：桥指令文件强制子代理经 `intercom send to=<PM>` 发 nao 模板回执，父会话核对。
2. **忙闲闸门**——**削弱**。父跑子代理期间只显示 `thinking`，闸门仍拦住 PM；但子会话以 `subagent-<agent>-<runid>` / 无名时 `subagent-chat-<id18>` 进入名册，污染 `status` 枚举（`visible_session_names` 读名册）。补救：`status`/`close` 排除 `subagent-` / `subagent-chat-` 前缀。
3. **close/status 句柄模型**——**失效（对子代理）**。句柄靠 tmux pane / 标题契约 / 名册 `tmuxPane`，而原生子会话无独立 pane；若子代理也用 pi-intercom 注册，会继承父进程 `$TMUX_PANE`（`pi-intercom/index.ts:567-573` 注册时读取），存在**父子 pane 句柄串扰**风险：对子会话 `close` 可能命中父 pane。补救：nao 只对 fleet 拉起的会话用 close；子代理生命周期交 pi-subagents（stop/retention）。
4. **tasks-state 外部状态**——**削弱**。pi-subagents 自带 run/mission 状态（`.pi/subagents/`），与 tasks-state 并存即双源（同「Issue 与 docs 双源」反模式）。补救：tasks-state 为唯一权威，runId 只作其中一列证据，不引入 mission 状态。
5. **角色卡注入**——**失效**。fleet 用 `--append-system-prompt` 注入卡片；子代理系统提示来自 agent `.md` 的 frontmatter+body。实测 nao 卡片不被发现为 agent ⇒ 子代理默认无角色卡；任务文本贴卡也不进系统提示。补救：为角色生成薄 agent 文件或 `subagents.agentOverrides.<role>.systemPrompt` 指向卡片（**不复制卡片内容**）。
6. **按批次重开 + 接续快照**——**削弱**。nao 恢复语义 =「PM 重开 + 读 tasks-state」；子代理 = run retention/resume。两套生命周期指向同一工作单元会矛盾。补救：分层——常驻会话归 fleet，会话内子代理归 pi-subagents，同一工作单元禁用混用恢复。

补充 **模型白名单**——**削弱**：fleet 在命令行入口用 `NAO_MODEL_WHITELIST` 校验 `--model`；子代理 model 由父 `subagent({model})` / agent 覆盖决定，nao 无校验点。

## 3. 一 writer 一 cwd + 需求分支 vs worktree 隔离

- **归谁管**：fleet/nao 管「谁在哪个 cwd/分支写」；pi-subagents 管「同一会话内并发子写的隔离」。二者**不得同时声称同一 worktree**。
- **冲突 1**：`worktree:true` 要求**干净 git 状态**，nao 却是「工作期只落分支、路径级暂存」的 WIP 工作树 ⇒ 脏树会导致 worktree 分配失败。补救：进 worktree 前把 WIP 提交到需求分支，再 `baseRef=HEAD`。
- **冲突 2**：worktree 子代理的改动在**独立分支/目录**，不在 nao 单一工作树；nao 的「PM 验收后 RD squash 合并」需增加**集成步骤**（patch / cherry-pick 回需求分支），集成者必须是唯一 writer。
- **不冲突**：worktree 隔离**加强**并发写安全；「非 worktree 子代理保持单写 + worktree 子代理各自隔离」即与 one-writer 不矛盾。`worktree.cleanup` 与 nao 无关，不得用于清理 nao 必要分支。

依据：`execution-controls.md` §Worktree Isolation（clean-check / baseRef / 保留策略）。

## 4. 需要改机制的点（只列不改；标注是否建议立项）

1. 协议/角色卡补「会话内子代理」授权与回执归属条款（子代理结果不替代 done）——**建议立项**（文档类，低成本）。
2. 提供 nao 版 `intercomBridge.instructionFile` 模板（含 done 模板 + 显式 target）——**建议立项**（配置类）。
3. `nao-fleet.sh status/close` 排除/识别 `subagent-*` 会话，防误杀父 pane——**建议立项**（脚本类，中风险，需回归）。
4. 角色→pi-subagents agent 薄壳（或 agentOverrides.systemPrompt）避免卡片复制漂移——**建议立项、低优先级**（有替代：继续 `--append-system-prompt`）。
5. 子代理路径的 model 白名单缺口——**记录为已知缺口，暂不立项**。
6. `detect_host` 不识别 foot/Hyprland（`xdg-terminal-exec` 存在，但宿主名单仅 ghostty|ptyxis|tmux|screen；非 tmux 下退到缺失的 screen 并 die）——与 pi-subagents 无关，**独立课题**，建议单立。

## 5. 推荐用法 / 不建议用法（按场景）

推荐：

1. **只读子代理侦察/评审/外部调研**（scout / researcher / oracle / reviewer / claude-code / codex-exec）——零新状态源、零写冲突；父会话发回执。
2. **单写子代理 + worktree**，父会话做唯一集成与回执。
3. **PM 派生角色子会话**——仅在配置 intercom 桥 + tasks-state 唯一源后使用（进阶）。
4. 渐进路径：先做只读嵌套，验证后再考虑桥。

不建议：

1. 用 pi-subagents **完全替代** 6 常驻会话（丢跨进程恢复、忙闲闸门、close 句柄、批次重开）。
2. 多写子代理共享同一 cwd（无 worktree）。
3. 把子代理 run 完成直接当 nao 回执、不经父角色核对。
4. 同编号双状态源（pi-subagents mission + tasks-state 同记）。
5. 依赖 `PI_SUBAGENT_ORCHESTRATOR_TARGET` 自动路由：pi-intercom 0.17.0 读该变量（`index.ts:197-210`），pi-subagents 0.77.0 未见写入（子配置走 `PI_SUBAGENT_RUNNER_CONFIG`）⇒ 当前装机该自动通道**惰性**，须显式配 intercomBridge。

**对照过的备选模式（含不采纳理由）**：

- ⓪ **维持现状**（仅 fleet + intercom）：零新增风险；放弃会话内并行与外部模型第二意见 ⇒ 作基线保留，非终态默认。
- ① **会话内只读嵌套**：**采纳（默认推荐）**。条件：只读/单写、产物落盘、父回执。代价：父上下文增长、子会话不可被 nao 调度。
- ② **子代理替代常驻舰队**：**不采纳**。丢 3 失效 + 2 削弱项、状态双源、恢复性差。
- ③ **显式 intercom 桥**：**有条件采纳**（PM 派生角色时）。条件：instructionFile + target 可达 + 子有 intercom 工具。代价：双源与自述回执风险。
- ④ **fleet 会话内工程化嵌套**（①演进）：**推荐渐进**，避免一次性改闸门。

**适配三栏**：它解决什么 = 会话内并行 / 外部模型第二意见 / 受控写隔离；适用条件 = 单父会话、clean git（用 worktree 时）、显式目标（用桥时）；本项目差异 = nao 是跨进程常驻 + 外部状态源 + 双闸门，故只能作为会话内原语嵌入，不接管编排与治理。

## 来源

- pi-subagents（npm 0.77.0）· https://www.npmjs.com/package/pi-subagents · 访问 2026-10-12
- pi-subagents（仓库）· https://github.com/nicobailon/pi-subagents · 访问 2026-10-12
- pi-intercom（npm 0.17.0）· https://www.npmjs.com/package/pi-intercom · 访问 2026-10-12
- 本地包文档 `~/.pi/agent/npm/node_modules/pi-subagents/docs/agents.md`、`docs/tool-reference.md`、`skills/pi-subagents/references/execution-controls.md`、`src/intercom/intercom-bridge.js` · 访问 2026-10-12
- 本地包源码 `~/.pi/agent/npm/node_modules/pi-intercom/index.ts:50,197-210,555,567-573` · 访问 2026-10-12
- Pi Packages · https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/packages.md · 访问 2026-10-12
- 实测（本会话）：`subagent({action:"list"})` 仅 builtin + 外部 CLI、无 nao 角色；`intercom list` 显示 `arch-designer` 与无名 `subagent-chat-*` · 2026-10-12

## 未检索到项

- 未检索到 pi-subagents 与「多会话跨进程舰队」的官方集成指南（其 intercom 章节只覆盖进程内 supervisor 与可选 resultDelivery）。
- 未检索到 `PI_SUBAGENT_ORCHESTRATOR_TARGET` 的生产方（pi-subagents 0.77.0 内无写入点）——按代码判为惰性，未做运行时抓取验证。

## 附录：引入 pi-subagents 后的目标流程（候选 · 未立项 · 未落地）

- 状态：**仅记录**。触发条件：用户决定推进时先按 §4 立项，再落地；当前不改 fleet/协议/配置，不建 Issue/PR。
- **A 轻量（推荐先做）**：舰队与闸门不变；角色会话内加只读/单写子代理（scout / researcher / oracle / reviewer；写用 `worktree:true`）；父角色仍发 done；唯一改动 = `status`/`close` 排除 `subagent-*` + 协议补「子代理结果不替代 done」。
- **B 深度（校验 A 后）**：PM 用 `subagent` 派生角色子会话 + `intercomBridge` 注入 done 目标；闸门变化见 §2；git 需新增「worktree → 需求分支」集成步骤；恢复语义由 run retention 接管。
- 渐进：A 试点 1–2 个任务 → 记 `contextTokens/cacheRead/产出质量` → 再评估 B。

- 修订：2026-10-12 首版（T512 调研）；附：候选流程（未立项/未落地）
