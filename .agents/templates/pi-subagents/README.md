# nao 版子代理桥指令（`intercomBridge.instructionFile`）安装说明

本目录是 nao 舰队对「会话内子代理」的口径模板，供 pi-subagents 的 `intercomBridge.instructionFile` 使用。模板只做一件事：把**回执归属 / 身份禁令 / 证据格式**三条 nao 语义注入子代理。协议侧对应条款见 `@.agents/common/intercom-protocol.md`「会话内子代理（授权与回执归属）」。

- **本批不写任何用户配置文件**：下面步骤由使用者自行执行；本仓不修改 `~/.pi/...`。
- **零敏感值 / 零绝对家目录路径**：本目录内所有文档只用 `~/...` 或 `$HOME/...` 形式。

## 一、安装（两条命令 + 一段配置）

1. 把模板复制到 pi-subagents 的配置目录（目录不存在时先建）：

   ```bash
   mkdir -p ~/.pi/agent/extensions/subagent
   cp <本仓>/.agents/templates/pi-subagents/intercom-bridge.md \
      ~/.pi/agent/extensions/subagent/nao-intercom-bridge.md
   ```

2. 在用户级配置 `~/.pi/agent/extensions/subagent/config.json` 中启用（**相对**路径，不写绝对家目录）：

   ```json
   {
     "intercomBridge": {
       "mode": "always",
       "instructionFile": "nao-intercom-bridge.md",
       "resultDelivery": false
     }
   }
   ```

   - `instructionFile` 的相对路径从 `~/.pi/agent/extensions/subagent/` 解析，因此与模板放在同一目录即可。
   - `mode` 取值 `off` / `always` / `fork-only`；nao 场景用 `always`（每次子代理都注入）。
   - `resultDelivery` 保持 `false`：nao 不需要外部监听者 ack 结果。

3. 生效检查：在 pi 会话内运行 `/subagents-doctor`，确认 `bridge: active` 且指令来自上述文件。

## 二、为什么不用 `{orchestratorTarget}` 占位符

pi-subagents 的默认模板支持一个「父会话目标」占位符，但 nao 版**刻意不使用**它：

- 父会话目标由 `contact_supervisor` 在子代理运行时**自行解析**（native 通道，不依赖 pi-intercom）；把父会话名写进模板反而会把启动契约摘要绑到具体父会话上，父会话一变就可能让启动前置校验失败。
- 目标名写死还会带来「换个 PM 会话名就失效」的可移植性问题。
- 因此本模板只写「用 `contact_supervisor` 回父角色」，不出现任何目标占位符。

## 三、已知行为与排障

- **已知低危行为（本批只记录，不调整）**：pi-subagents 0.78 的默认控制通知通道包含 `intercom`，长跑的会话内子代理偶尔会向父会话**本地注入**一条 control 消息。该消息**不经 broker、不会出现在 `intercom list`**，只占一点父会话上下文。nao 暂不改用户配置里的通知通道；如噪音明显，可在用户配置中收紧通知通道。
- **模板未生效 / 仍看到默认文案**：确认 `config.json` 的键名与 `mode`；确认文件已复制到 `~/.pi/agent/extensions/subagent/` 且文件名与 `instructionFile` 完全一致。
- **排障入口**：`/subagents-doctor` 会显示桥是否 active、当前 mode 与目标解析结果；先看它，再怀疑配置。
- **子代理仍直发 PM / 发 `done`**：这属于越权，说明注入未生效或子代理由外部工具另配了 intercom；父角色仍只认自己的 `done`，不采信子代理消息。

## 四、口径归属（唯一事实分工）

- **语义**（授权 / 回执归属 / 身份禁令 / 证据格式）在 `.agents/common/intercom-protocol.md`。
- **注入文本**在本文件的同目录 `intercom-bridge.md`。
- **安装步骤**在本文件。
- 机械探针对应 `tests/t4/cases/16-intercom-bridge.sh`（校验模板条款齐备、无目标占位符、配置样例接受/拒绝与协议小节四条齐备）。
