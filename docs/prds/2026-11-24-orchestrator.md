# 编排器 nao-orch（把人工调度变成机制自己转）

- 状态：待批准
- 日期：2026-11-24
- 关联：`docs/reports/2026-11-24-task-flow.md`（流程分段图）· T563（`agent_verdict` 三态）· T562（app 后端 · OSC 7501 忙闲）
- 目标版本：分三阶段，阶段 1 随下个 MINOR；阶段 2/3 另批

## 一、背景与目标

当前「多角色 intercom 协作」的骨架已成立（7 常驻角色 · `ensure/close` · 角色卡注入 · 闸门与回执），但**调度靠 PM 会话单点**：队列是人维护的文档、回执是散文、忙闲靠人看、PM 上下文满了流水线就停。

本 PRD 的目标：把调度从「人记得派单」变成「机制自己 tick」，**但不把人从「判断对不对」里解放出来**——合并与发版永不自动化。

**成功判据（阶段 2 结束）**：PM 会话不在线 30 分钟内，队列中无依赖阻塞、无 `blocked` 的任务仍能推进到 `qa_pass`。

## 二、现状与差距

| 维度 | 现状 | 差距 |
|---|---|---|
| 队列 | `docs/tasks-state.md` 人写 Markdown | 无机器可读状态、无依赖、无超时 |
| 回执 | 散文 + 三件套，格式三种 | 无 schema，无法自动判成败 |
| 忙闲 | `nao-fleet.sh status` 一屏文字 | 无 `--json`，编排器无法消费 |
| 调度 | PM 会话手工 `ensure` + intercom 派单 | 单点、不可恢复、易漏派/双派 |
| 观测 | 人读 status | 无阻塞时长、无周期时间 |
| 寻址 | 曾用裸名（三次跨仓误投） | 需强制 id 或 id+cwd |

## 三、范围与非范围

**范围**：结构化队列与回执 · 状态机与超时 · 编排 tick · 看板 · 多仓作用域 · 机械校验用例。

**非范围**：自动合并/自动发版（永不）· 自然语言任务拆解（人写 PRD）· 会话内容理解（不回读工作记录做判断）· 角色卡生成。

## 四、模块与数据契约

模块图见 `docs/reports/2026-11-24-task-flow.md`。四层边界：CORE 无状态 · ADAPT 不含决策 · `queue.jsonl` 唯一事实源 · 状态机到 `qa_pass` 停。

**队列**：`docs/queue.jsonl`，一行一任务。字段：`id/kind/title/state/prio/deps/repo/branch/owner/qa/acs/attempt/created/updated/blocked_reason`。

**状态机**：`queued → dispatched → working → qa → (qa_fail → working) → qa_pass → merging → merged → released`，另有 `blocked` 由 `no_ack(15m)` / `stalled(90m, HEAD 未变)` / `attempt>2` 进入。

**回执**：`docs/queue/<id>.receipt.json`，字段 `id/author/at/head/pushed/gates{check{rc,log},full{rc,cases,pass,fail,note}}/acs[{id,how,evidence}]/blocked/artifacts/deviation`。

**机读首行**：`receipt: <id> <role> head=<sha> gates=<ok|red>,<ok|red> acs=<n>/<n>`。

## 五、验收（AC，机械可判）

**阶段 1（队列与回执）**
- AC1 回执缺任一必需字段 ⇒ `cases/50` 红
- AC2 `pushed:true` 与 `git ls-remote` 不一致 ⇒ 红
- AC3 非法状态转换（如 `queued → merged`）⇒ 红
- AC4 `tasks-state.md` 由 `queue.jsonl` 渲染，手改后再渲染 ⇒ diff 非空 ⇒ 红

**阶段 2（编排 tick）**
- AC5 两个 orch 并发 ⇒ 只派一次（`flock` 生效）
- AC6 目标角色 `working|unknown` ⇒ 不投递、只记等待
- AC7 派单 15m 无 `ack` ⇒ `blocked(no_ack)` + 追问一次，`attempt` 不递增
- AC8 崩溃恢复：tick 中途 `kill -9`，下一 tick 重建视图且不重复派单
- AC9 **绝不能**由 orch 触发 `gh pr merge` / `npm publish` / `git push origin main`（静态闸 + 用例双向）

**阶段 3（看板与多仓）**
- AC10 两仓同名角色（各有一个 `pm`）⇒ 派单不串仓（回归：三次裸名误投）
- AC11 `nao-board` 数值与 `queue.jsonl` 一致（同 tick 快照）

## 六、接口与副作用

- 新增 `bin/nao-orch`（`tick|board|dispatch|reap`）· `bin/nao-board` 或子命令
- `nao-fleet.sh status --json`（只增输出，不改现有文本输出 ⇒ AC1 逐字面不变）
- 队列与回执写入限定 `docs/queue/**`
- 副作用边界：orch 会 `ensure`/`close` 会话、写队列；**不会**动 git 远端、不动 `package.json`、不碰 tag/Release

## 七、失败模式

| 失败 | 处置 |
|---|---|
| orch 崩 | 无状态 ⇒ 下一 tick 自恢复；`blocked` 保留原因 |
| 双 orch | `flock` 拒第二实例，返回 rc=1 + 点名持锁 pid |
| 会话被外部杀掉 | `agent_verdict=absent` ⇒ 标 `blocked(absent)`，不自动重派（先让人看原因） |
| 队列与台账不一致 | 以 `queue.jsonl` 为准，重渲染 `tasks-state.md`；不一致本身记账 |
| 回执伪造（自述 pass 无日志） | `gates.full.log` 指向不存在/无 `RESULT: PASS` ⇒ 判红 |

## 八、依赖与风险

- 依赖 T563（`agent_verdict` 三态）· T562（app 后端忙闲）· intercom 0.18.x（`ask` 阻塞语义）
- 风险：**回执 schema 变更成本**——一旦有历史回执，改 schema 需迁移期（建议 `schema:1` 字段，1 年内只增不删）
- 风险：**误把自动化当复核**——明确写入 ADR：orch 不替代 QA 独立复核

## 九、发布策略

- 阶段 1：MINOR（新增文件与用例，无行为变更；`status --json` 只增）
- 阶段 2：MINOR（新增 daemon；默认**不启用**，需显式 `nao-orch` 启动，避免下游仓被自动调度）
- 阶段 3：MINOR
- 回滚：删 `bin/nao-orch` 无副作用（队列文件保留、可人读）；`status --json` 回退不影响旧调用

## 十、开放问题

1. 队列与 `tasks-state.md` 的渲染方向是否要反向（人改 md ⇒ 解析回 jsonl）？倾向**否**（单向）。
2. 阶段 2 是否提供 systemd user unit 模板？倾向**是**（附卸载说明）。
3. `blocked` 通知 PM 走 intercom 还是写文件？倾向**两者**（intercom 唤醒 + 文件留证）。
