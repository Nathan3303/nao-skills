# PRD · 纯 herdr 化 + 脚本减重（移除 tmux 后端）· T555

- 状态：草案（待 arch ADR + 判据）· 更新：2026-11-22 · Owner：product-manager
- 来源：用户 2026-11-21 拍板 —— 「不再支持 tmux，后面就是纯 herdr 的舰队」+「进一步缩减 `nao-fleet.sh` 代码数量」；「一步一步来，做完当前任务再做这个」（T554 已合并 `f962813`）
- 前序：`docs/adr/2026-10-27-strict-tmux-pi.md`（当年「只支持 tmux」）→ `2026-11-13-herdr-workspace-scope-key`（herdr 上桌面）→ `2026-11-20-workspace-as-binding-unit`（模型 v2，herdr 为默认）

## TL;DR（≤5 行）

- 删除 **tmux 后端全部**：`term-impl-tmux` 七个区间（QA 估 ≈615 行）+ 门面里所有 tmux 分支 + `NAO_TERMINAL=tmux` 入口。
- 顺带把「双后端」的测试编排收成单后端，删掉为 tmux 存在的用例与替身；**不删任何断言强度**（tmux 专有面按「后端不存在 ⇒ 断言退役」处理，逐条留痕）。
- 目标：`nao-fleet.sh` 体量可量化下降（基线以命令为准），运行时行为**除「不再有 tmux」外**不变。

## 一、问题证据

1. 用户多仓实践已全程 herdr（`NAO_TERMINAL` 默认 herdr 自 v0.23）；tmux 只剩「回退」价值，而每次改动都要**双后端**跑门禁（全量 ×2 ≈ 双倍时间），本仓 39 个用例里多个是 tmux 专有或需真 tmux。
2. 体量：`nao-fleet.sh` 现约 4700+ 行（判据以 `wc -l` 为准），其中 `term-impl-tmux` 七个区间 ≈615 行（QA 2026-11-22 估），另有门面 `term_backend()` 分派、`-S` 实验场、双后端测试编排。
3. 双后端还带来**语义双写**：如 `cleanup -S`（tmux）vs `cleanup --session`（herdr）、`-S default` vs `--session default`、pane 定位（标题/名册）两套。

## 二、目标指标

- **`nao-fleet.sh` 行数下降 ≥15%**（以 `wc -l` 前后对比，落台账）。
- **门禁时间**：单后端全量 ≤ 双后端全量的 **60%**（同机实测，落台账）。
- **零行为漂移**：除 tmux 相关外，`check` / `ensure` / `status` / `close` / `cleanup` 输出与 v0.27.0 逐字一致（同一 herdr 夹具两树对照）。
- **用例数**下降必须逐条归因（退役/合并），**断言强度不得下降**（除「后端不存在」类）。

## 三、范围 / 非范围

**范围**：M1 删除 `term-impl-tmux` 七区间与门面 tmux 分支 · M2 `NAO_TERMINAL` 语义收窄（`tmux` ⇒ fail loud 指路升级/降级）· M3 `cleanup`/`session-start` 参数面统一（去掉 `-S`）· M4 测试编排单后端化（`lib-backend.sh`、`backends/herdr.txt`、`run.sh` 的 tmux-only 概念）· M5 用例退役与改写（`12/25` tmux 专有 ⇒ 退役；`20/21/22/23/24` 需真 tmux ⇒ 改 herdr 替身或退役，逐条裁定）· M6 文档（README/INSTALL/AGENTS/ADR supersede 当年「只 tmux」）· M7 台账「体量基线」记录。

**非范围**：任何 `term-impl-herdr` 的功能改动 · 布局几何 · 命名契约（v2 已定）· 跨 session 协同。

## 四、用户场景

- **S1**：用户 `export NAO_TERMINAL=tmux` 后运行 `ensure` ⇒ **fail loud**：「本版已移除 tmux 后端；herdr ≥0.9.1 是唯一后端」+ 升级/迁移指路，不静默回退。
- **S2**：herdr 内一切命令与 v0.27.0 逐字一致（`status`/`ensure`/`close`/`cleanup`）。
- **S3**：`cleanup` 只剩 `--session <名>` 一种写法；旧 `-S` 传入 ⇒ fail loud 指路新写法（避免习惯性误用静默生效）。

## 五、业务规则

- **R1 唯一后端**：`term_backend()` 恒为 herdr；不存在分支选择。`NAO_TERMINAL` 只用于**拒绝**（`tmux` ⇒ 报错）。
- **R2 fail loud 不静默**：旧调用面（`-S`、`NAO_TERMINAL=tmux`）必须报错并给新写法，**不得**静默忽略或降级。
- **R3 测试不降强度**：退役用例必须写明「为什么后端没了这条就不成立」；可迁移的（如真 tmux 场景）用 herdr 替身等价覆盖。
- **R4 单源**：门面只剩 herdr 实现；`lib-backend.sh` 删掉 `be_*` 的 tmux 侧，保留 herdr 抽象（未来换后端仍需接口）。
- **R5 体量可量化**：改动前后 `wc -l`、`grep -c` 函数数、全量门禁耗时三组数字落台账。

## 六、NFRs

- **零新依赖**；删代码不引入新逻辑。
- **可回退**：单条 squash 后 `git revert`。
- **文档一致性**：所有「tmux 回退」表述（README 前置环境 / INSTALL / AGENTS / 各 ADR 注记 / 卡内文）必须同步，禁留旧话（本仓已有「端前提一致性 warn」可复用）。

## 七、AC

### 主路径
- **AC1** herdr 内 `check` / `ensure` / `status` / `close` / `cleanup` 输出与 v0.27.0 **逐字一致**（同夹具两树 diff 空）。
- **AC2** `nao-fleet.sh` 行数下降 ≥15%，且 `grep -c '^[a-zA-Z_][A-Za-z0-9_]*() *{'` 的函数数下降有逐条清单（哪些函数整体消失）。

### 异常
- **AC3** `NAO_TERMINAL=tmux` ⇒ fail loud（点名「已移除」+ 指路），rc 与文案可断言。
- **AC4** `cleanup -S <名>` ⇒ fail loud 指路 `--session <名>`；`cleanup --session` 行为与 v0.27.0 一致（含 `default` 的 `--force` 口径）。

### 边界
- **AC5** 用例退役清单：每条给「原用例 → 处置（退役/改 herdr 替身）+ 理由」；可迁移的必须迁移，断言数下降逐条归因。
- **AC6** `backends/herdr.txt` 的登记集概念若因单后端而失去意义 ⇒ 可简化，但**不得**因此让任何用例静默变成 PENDING/SKIP。

### 负向闭环
- **AC7** 三条护栏（自面板守卫 / 归属不可判定即拒 / 忙闲闸门）逐字保留；`default` 的破坏性动作仍需 `--force`。
- **AC8** 禁旧面复活：静态 lint 断言「脚本内不再出现 tmux 命令位 / `NAO_TERMINAL=tmux` 分支」（仿既有 `t4_scan_term_herdr_forbidden` 反向写法），并有正控证明 lint 真会红。

### 设计一致性
- **AC9** ADR：`docs/adr/2026-11-22-herdr-only.md`，**supersede** `2026-10-27-strict-tmux-pi.md`，并在 `2026-11-13` / `2026-11-17` / `2026-11-20` 三篇加「tmux 回退面已删除」注记。
- **AC10** 文档单源：README/INSTALL/AGENTS 三处只留一份正文 + 指针；`check` 的端前提一致性 warn 覆盖新表述。

## 八、上线闭环

- 门禁：`check` rc=0 + 目标用例（`cases/41` 纯 herdr 化）+ **单后端**全量 rc=0（双后端概念消失）+ 一次 `test:t4:full`（原 full 语义）。
- 发布：**v0.28.0 MINOR**（0.x 破坏性）；release notes 必须写「tmux 回退已移除 + 迁移指路 + 体量/耗时数字」。
- 回退：单条 revert；旧版本可通过 pin 回退使用。

## 九、变更治理

- **ADR 必带**（结构性：删掉一整个后端）：`docs/adr/2026-11-22-herdr-only.md`。
- **判据单源**：`docs/reports/555-lite-spec.md`（退役清单 + 断言迁移表 + 体量基线）。
- **文档面**：README（前置环境只剩 herdr + Node + git）· INSTALL（删 tmux 节、补「已移除」与迁移）· AGENTS（项目约束一条）· 三篇 ADR 注记。
- **验收硬数字**：`wc -l` 前后 · 函数数前后 · 单后端全量耗时 vs 双后端（同机）。
