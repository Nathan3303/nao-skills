# 编排器 nao-orch（把人工调度变成机制自己转）

- 状态：已接受（2026-11-24 · §十 三问已拍板）
- 日期：2026-11-24
- 关联：`docs/reports/2026-11-24-task-flow.md`（流程分段图）· T563（`agent_verdict` 三态）· T562（app 后端 · OSC 7501 忙闲）
- 目标版本：分三阶段，阶段 1 随下个 MINOR；阶段 2/3 另批

## TL;DR（≤5 行）

- **做什么**：把调度从「PM 会话人记得派单」变成机制自己 tick —— 结构化队列 + 回执契约 + 状态机 + 编排 tick + 看板。
- **给谁**：nao 舰队（PM 与 7 个常驻角色）及其下游使用方。
- **成功标准**：阶段 2 结束时，PM 会话不在线 30 分钟内，无依赖阻塞、无 `blocked` 的任务仍能推进到 `qa_pass`。
- **不做什么**：自动合并 / 自动发版（永不）· 自然语言任务拆解 · 会话内容理解。

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

**状态机**：`queued → dispatched → working → qa → (qa_fail → working) → qa_pass → merging → merged → released`，另有 `blocked` 由 `no_ack(15m)` / `stalled(90m, HEAD 未变)` / `attempt>2` / `dispatch_unknown` 进入。

- `queued → blocked`（`blocked_reason=dispatch_unknown`，阶段 2 落地点见 ADR D4）：WAL 里已有派单意图（`intent`），但恢复期用该意图的 `session_id + cwd` 去 `nao-fleet.sh status --json` **探不到**目标会话 ⇒ 冻结交人，**绝不自动重派**（重派即可能双派）。
- `blocked → queued` = **人工**核对原因后重新排队；本状态机不提供任何自动出口（唯一的写入口是人的判断或 tick 按上表判定）。
- 状态表**单源** = `bin/lib/queue.mjs::TRANSITIONS`（`bin/nao-queue` 与 `bin/nao-orch` 同引，复制即双源）。

**回执**：`docs/queue/<id>.receipt.json`，字段 `id/author/at/head/pushed/gates{check{rc,log},full{rc,cases,pass,fail,note}}/acs[{id,how,evidence}]/blocked/artifacts/deviation`。

**机读首行**：`receipt: <id> <role> head=<sha> gates=<ok|red>,<ok|red> acs=<n>/<n>`。

## 五、接口与副作用

- 新增 `bin/nao-orch`（`tick|board|dispatch|reap`）· `bin/nao-board` 或子命令
- `nao-fleet.sh status --json`（只增输出，不改现有文本输出 ⇒ AC1 逐字面不变）
- 队列与回执写入限定 `docs/queue/**`
- 副作用边界：orch 会 `ensure`/`close` 会话、写队列；**不会**动 git 远端、不动 `package.json`、不碰 tag/Release

## 六、失败模式

| 失败 | 处置 |
|---|---|
| orch 崩 | 无状态 ⇒ 下一 tick 自恢复；`blocked` 保留原因 |
| 双 orch | `flock` 拒第二实例，返回 rc=1 + 点名持锁 pid |
| 会话被外部杀掉 | `agent_verdict=absent` ⇒ 标 `blocked(absent)`，不自动重派（先让人看原因） |
| 队列与台账不一致 | 以 `queue.jsonl` 为准，重渲染 `tasks-state.md`；不一致本身记账 |
| 回执伪造（自述 pass 无日志） | `gates.check.log` 指向不存在文件，或 `gates.full` 缺 `rc/cases/pass/fail/note` 任一 ⇒ 判红 |
| 派单意图已落 WAL、会话不存在（`kill -9` 等） | `blocked(dispatch_unknown)` + 通知 PM；**绝不自动重派**（先让人看原因） |

> 超时动作的**当前覆盖面**（阶段 2 实施口径，读者须知）：只有 `dispatched`（派单 15m 无回执）有自动动作（`blocked(no_ack)` + 追问一次）。**`working` 行当前没有任何超时自动动作** —— 90m `stalled`（HEAD 未变）判据要「派单时的 HEAD」而本 PRD §四 明确不新增 `dispatch_at` 类字段，故随阶段 3 的 board 指标一并实现（在那之前不会误判：`working` 行只会等人推进）。
>
> 锚点（T566-F2）：`gates.check.log` 为相对路径时一律按**仓库根**解析（`git rev-parse --show-toplevel`，以调用 cwd 为起点）；绝对路径原样使用；仓库根不可判定（调用 cwd 不在任何 git 仓内）⇒ 判红（fail closed），不静默跳过。

## 七、验收（AC，机械可判）

分组依据 `.agents/checklists/deliverable-docs.md` §三（五覆盖）；阶段归属写在每条 AC 前（阶段 1 = 本批）。

### 主路径

- **AC4**（阶段 1）`tasks-state.md` 由 `queue.jsonl` 渲染，手改后再渲染 ⇒ diff 非空 ⇒ 红

### 异常

- **AC6**（阶段 2）目标角色 `working|unknown` ⇒ 不投递、只记等待
- **AC7**（阶段 2）派单 15m 无 `ack` ⇒ `blocked(no_ack)` + 追问一次，`attempt` 不递增
- **AC8**（阶段 2）崩溃恢复：tick 中途 `kill -9`，下一 tick 重建视图且不重复派单

### 边界

- **AC5**（阶段 2）两个 orch 并发 ⇒ 只派一次（`flock` 生效）
- **AC10**（阶段 3）两仓同名角色（各有一个 `pm`）⇒ 派单不串仓（回归：三次裸名误投）

### 负向闭环

- **AC1**（阶段 1）回执缺任一必需字段 ⇒ `tests/t4/cases/46-queue-receipt.sh` 红
- **AC2**（阶段 1）`pushed:true` 与 `git ls-remote` 不一致 ⇒ 红
- **AC3**（阶段 1）非法状态转换（如 `queued → merged`）⇒ 红
- **AC9**（阶段 2）**绝不能**由 orch 触发 `gh pr merge` / `npm publish` / `git push origin main`（静态闸 + 用例双向）

### 设计一致性

- **AC11**（阶段 3）`nao-board` 数值与 `queue.jsonl` 一致（同 tick 快照）

## 八、依赖与风险

- 依赖 T563（`agent_verdict` 三态）· T562（app 后端忙闲）· intercom 0.18.x（`ask` 阻塞语义）
- 风险：**回执 schema 变更成本**——一旦有历史回执，改 schema 需迁移期（建议 `schema:1` 字段，1 年内只增不删）
- 风险：**误把自动化当复核**——明确写入 ADR：orch 不替代 QA 独立复核

## 九、发布策略

- 阶段 1：MINOR（新增文件与用例，无行为变更；`status --json` 只增）
- 阶段 2：MINOR（新增 daemon；默认**不启用**，需显式 `nao-orch` 启动，避免下游仓被自动调度）
- 阶段 3：MINOR
- 回滚：删 `bin/nao-orch` 无副作用（队列文件保留、可人读）；`status --json` 回退不影响旧调用

## 十、开放问题（已拍板 2026-11-24）

1. 台账方向 = **单向**（`queue.jsonl` → `tasks-state.md`）：jsonl 是唯一事实源，md 是渲染产物；手改 md 会在下次渲染被覆盖（AC4 即此判据）。
2. systemd = **要**：阶段 2 随交付出 `nao-orch.service` / `nao-orch.timer` + 安装/卸载命令，安装须幂等（连装两次 effect=0），日志走 journald。理由：orch 的价值前提是「PM 会话不在时也能推进」，`cron` 不保证登录后仍在跑。
3. `blocked` 通知 = **两者都做**：写 `queue.jsonl` / receipt 留证，同时 intercom 唤醒 PM 会话（消息带会话 id + cwd，禁裸名）。

以上三条不再是开放问题；后续变更须改本节并 bump 版本。
