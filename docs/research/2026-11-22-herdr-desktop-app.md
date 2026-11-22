# 可行性笔记 · 舰队机制配合 herdr **desktop app**（非 TUI）

- 状态：**可行（高）**，但属「**新后端移植**」，不是现有 TUI 后端的开关 · 更新：2026-11-22 · Owner：product-manager
- 触发：用户 2026-11-22「要将舰队机制配合 herdr desktop app，看一下可不可行」
- 结论摘要：**本机三块前提全齐**（桌面版在跑 / `hc` CLI 可用 / pi 支持 OSC 7501）⇒ 可行；**难点不在启动与状态，而在「放置」** —— 桌面版的 space / tab 是**配置文件 + mods（JS）**驱动，**没有** CLI 创建接口。

## 一、两套程序（先分清，否则白做）

| | Herdr **TUI**（现用） | Herdr **desktop app**（新） |
|---|---|---|
| 服务端 | `herdr` 自带 server（`--session`） | `herdr-core`（`serve` / `connect` / `hold`） |
| CLI | `herdr --session S workspace/tab/pane/agent …` | **`hc`**（`run` / `ls` / `get` / `send` / `keys` / `wait` / `kill` / `exec` / `file`） |
| 概念 | workspace / tab / pane / agent_status | **space / tab / terminal** · `state` + `turn` + `where` |
| 配置 | `~/.config/herdr/sessions/<名>` | `~/.config/herdr-app/`（`layouts/*.json` · `mods/*.js` · `herdr.d.ts` · `AGENTS.md`） |
| 状态协议 | 快照里的 `agent_status` | **OSC 7501**（working / done / waiting / failed） |
| 互通 | **与 app 互不共享 agent**（官方 FAQ 明示） | 同左 |

本机实测（2026-11-22）：`hc` = `~/.local/bin/hc` · `herdr-core` 三个进程在跑（serve/connect/hold）· `~/.config/herdr-app/` 有 `layouts/main.json` `terminals.json` `mods/{agents,changes,confirm,files,help}` `herdr.d.ts` · `hc ls --json` 返回 `{"terminals":[{"address":"t2","cwd":"…","state":"live","turn":0,"where":"nao-todo / 1"}]}` ⇒ **space / tab 可从 `where` 读出**。

## 二、关键前提：状态可读吗？**可**

- **pi 原生支持 OSC 7501**（`docs/terminal-setup.md#program-status`；`PI_PROGRAM_STATUS` 可强制开/关，二进制内有 4 处字符串）⇒ 桌面版能显示我们的 agent 是 working / waiting / done。
- ⇒ 现机制里「忙闲闸门 + 就绪门」所依赖的 `agent_status` 快照，在 app 侧有等价物（`hc ls --json` 的 `state` / `turn`）。

## 三、三处集成面（可行性判断落在这里）

1. **启动 / 回收**（`ensure` / `close` 的骨架）：✅ 有 CLI —— `hc run --bg <cmd>`、`hc kill <t>`、`hc ls --json`、`hc get <t>`、`hc read <t>`；跨机还有 `--on <machine>`。
2. **放置（space = 仓 / tab = 任务）**：⚠️ **无 CLI**。桌面版的 space/tab 由 `~/.config/herdr-app/layouts/*.json` 与 `mods/*.js` 决定 ⇒ 要么**生成/增量改 layout JSON**，要么写一个 **mod**（JS，`herdr.d.ts` 有完整类型）。这是本方案唯一需要设计的地方，也是风险集中点（schema 非公开契约、app 升级可能改）。
3. **命名与身份**：✅ 正好对味 —— app 的官方模型就是「**space per repo · tab per task**」，与 v0.27.0 的「1 workspace = 1 仓 = 1 pm」同构；`hc label <t> k=v` 可挂我们的身份标签。

## 四、可选路线（供立项时选）

- **A 双后端并存（推荐先做验证）**：`term_backend` 增加 `app` 实现（`hc` 驱动 + layout 生成），TUI 保留；用户按需 `NAO_TERMINAL=app`。代价：后端抽象要能容「放置 = 改配置」这种非 CLI 语义。
- **B 全面迁到 app**：等同再做一次 T555（把 TUI 面删掉），但**现在不建议** —— TUI 的 `workspace/tab` CLI 语义与现机制完全贴合，app 侧的放置面还不稳。
- **C 只做「观测」不做「放置」**：舰队仍在 TUI 跑，另用 app 的 mod 把 TUI 的会话只读展示出来 —— **不可行**：官方明示两套程序**不共享 agent**。

## 五、风险与否定条件

- **R1 schema 风险**：`layouts/*.json` 与 `mods` 不是稳定 API（官方口径是「让 agent 改它」）⇒ 若 app 小版本改动 schema 就破，需要**能力探测 + fail loud**，不能静默错位。
- **R2 两套程序不互通**：用户可能以为「装了 app 就能看到现有舰队」——**不能**。任何方案必须显式处理「迁移/并存」二选一，且文档写死。
- **R3 放置语义差**：TUI 是「命令建 workspace/tab」；app 是「配置决定布局」。若把后者硬塞进前者语义，会写出「改了 JSON 但 app 没重载」这类静默失败 ⇒ **否定条件**：放置断言必须验「`hc ls` 的 `where` 真的到了目标 space/tab」，而不是「JSON 写成功了」。
- **R4 先决**：T555（纯 herdr + 减重）**必须先做完** —— 后端抽象收敛成单一实现之后再加第二实现，成本最低；否则会在双后端 + 双放置语义上打结。

## 六、建议

**立项为独立任务（T556）**，前置 = T555 合并（v0.28.0）。第一阶段只做 **A 路线的「可跑通」验证**：`hc run --bg` 起一个 pi 会话 + `hc ls` 读到 `state` + 生成一份最小 layout 让它在目标 space 出现 —— 三步跑通再谈「接入 ensure/close 全语义」。
