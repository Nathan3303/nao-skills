# PRD · 舰队模型 v2：取消 fleet，workspace 为绑定单位 · T554

- 状态：草案（待 arch ADR + 判据）· 更新：2026-11-20 · Owner：product-manager
- 前序（本批**改写**对象）：`docs/adr/2026-11-13-herdr-workspace-scope-key.md`（放置键 = scope）· `docs/adr/2026-11-17-fleet-identity-source.md`（放置键与身份键同源）· `docs/adr/2026-11-19-fleet-repo-manifest.md`（1 fleet = 1 workspace）
- 用户拍板（2026-11-20，四答）：① **彻底取消 fleet**，重名在后面加数字（`pm2` / `pm3`…）② 名字**只用角色名 + 数字后缀**（`@` 段彻底去掉）③ **每仓一个 pm** ④ `.agents/fleet.yaml` **保留为「仓代号 → 路径」映射**、去掉 `slug`；⑤ default session **全放行**

## TL;DR（≤5 行）

- herdr 实测：**不做任何 label 唯一性校验**（不同 workspace 或同一 workspace 内都允许多个 `pm`）⇒ 唯一性由我们自己做。
- 因此 **workspace 就是绑定单位**：1 workspace = 1 仓 = 1 pm；pm 是 tab，worker 也是 tab。
- 派生只需指定 **workspace（= 仓）**，不再需要 fleet，也不再要求「特定 session」（`default` 可用）。
- 名字 = 角色名（冲突加数字后缀 `2/3…`）；`.agents/fleet.yaml` 降级为「仓代号 → 路径」映射。

## 一、问题证据

1. **实测（herdr 0.9.5 · 2026-11-20 · 已回收探测会话）**：`workspace create --label ws-one` ×2 允许；`tab create --label pm` 在 w1 与 w2 **均允许**；同一 w1 内再建一个 `pm` **也允许** ⇒ herdr 无 label 唯一性。
2. **用户实操受挫**：在 `default` session 的 pane 里 `ensure pm` 被 `exit 3` 拒（`HERDR_SESSION` 为 `default` ⇒ 两道守卫拦），而用户诉求正是「不规定某个 session」。
3. **模型冲突**：v0.26.0 的 fleet 同时承担 ① 会话名 `@` 段 ② 判重键 ③ **workspace 放置键**；而「1 workspace = 1 仓」要求放置键必须是**仓**，三职责无法共存于一个字符串。
4. **v0.26.0 的连带负担**：`@` 段已被 manifest `code` 占用 ⇒ 名字里 `@` 的语义已经从「舰队」漂移到「仓」，继续保留只会加深歧义。

## 二、目标指标

- **一个 workspace 一个仓**：workspace label = 仓（同名时加数字），pane cwd = 该仓物理路径。
- **一 workspace 一 pm**：pm 与该仓的 worker 同为 workspace 内的 tab。
- **零 fleet 概念**：会话名 = 角色名（冲突 `pm2`），`--fleet` / `.agents/fleet-scope` 弃用（warn 后忽略，下一 MINOR 移除）。
- **不挑 session**：`default` 与专用 session 一视同仁（含 `cleanup`），只在破坏性动作上打印将影响的对象。
- **零回归**：无 manifest、单仓场景行为与用户预期一致（旧 `@` 名字的存活会话仍能被 `close` 命中，见 AC6）。

## 三、范围 / 非范围

**范围**：M1 命名契约 v2（去 `@`，数字后缀）· M2 放置键 = 仓（workspace label）· M3 tab = 角色（+同名数字）· M4 `default` 放行（守卫分级）· M5 manifest 降级为 `code→path` 映射（去 `slug`）· M6 `status`/`close` 读面与「不猜」· M7 弃用与迁移（`--fleet`、`fleet-scope`）· M8 文档（README / INSTALL / AGENTS / 三篇 ADR supersede）· M9 测试面（`cases/40` + 既有断言迁移）。

**非范围**：跨 herdr session 协同 · 自动发现联动仓 · 布局几何算式（沿用现状）· `pi` 侧任何改动。

## 四、用户场景

- **S1 单仓**：在仓 A（`default` session 的 pane 里）`ensure pm` ⇒ 建 workspace `A` + tab `pm`；再 `ensure rd-be` ⇒ **同一 workspace** 里新增 tab `rd-be`。再 `ensure pm` ⇒ 新会话 `pm2` + 新 tab `pm2`（同 workspace）。
- **S2 多仓**：仓 A 的 manifest 声明 `api: ../api`；`ensure pm@api` ⇒ 在 `api` 仓建 workspace `api` + tab `pm`（与仓 A 的 `pm` **同名但不同 workspace**，用户明确要求允许）。
- **S3 破坏性动作**：`cleanup -S default` 现在允许执行，但**打印将被停止的 session 名与受影响的 workspace/pane 数**并要求确认或 `--force`（形态交 ADR 定，原则 = 放行但不静默）。

## 五、业务规则

- **R1 唯一性由我们负责**：herdr 不做校验 ⇒ 会话名冲突时**在角色名后紧贴数字**（`pm2`、`rd-be2`），派生会话为 `<role>N-<task>`（数字在任务前，保证任务段仍可解析）。
- **R2 放置键 = 仓**：`workspace label` 取仓目录 basename（物理归一）；两仓同名 ⇒ 后者加数字并在提示里说明。**禁**再用 fleet/slug/code 当放置键。
- **R3 名字不再承载位置**：`@` 段彻底去掉；位置只由 workspace 表达。`ensure <role>@<code>` 里的 `@<code>` 仅表示「目标仓（manifest 映射）」，**不进会话名**。
- **R4 每仓一个 pm**：`pm` 属于 workspace；跨仓协作由各仓 pm 之间 intercom 协调（PM 卡需补这条边界）。
- **R5 session 不设限**：`default` 与专用 session 等价；**唯一保留的差异** = 破坏性动作（`cleanup -S` / `session stop`）对 `default` 打印影响面。
- **R6 不猜**：解析 / 放置 / 回收三处禁「首个命中」兜底（沿用 #146/#151/#139 口径）。
- **R7 弃用留痕**：`--fleet <x>` 与 `.agents/fleet-scope` 命中 ⇒ **warn 一行（指明本版忽略、下版移除）并忽略**，不静默、不 fail。

## 六、NFRs

- **兼容**：旧 `@` 名字的**存活会话**仍可被 `close` 命中（名字解析需容忍历史形态）；新起会话一律用 v2 名字。
- **失败可读**：冲突、非法 manifest、放置失败均给「哪个仓/哪个名字/该怎么办」。
- **零新依赖 / 零网络**；manifest 解析与路径归一复用既有函数（`nao_phys_path`、`repo_contains_path`）。
- **成本**：`ensure` 不新增 per-target 的重复 herdr 查询（一次 `workspace list` + 一次 `tab list` 复用）。

## 七、AC

### 主路径
- **AC1** 单仓 `ensure pm` ⇒ workspace label = 仓 basename · tab label = `pm` · pane cwd = 仓物理路径 · 会话名 `pm`。
- **AC2** 同一 workspace 内再 `ensure rd-be` ⇒ 复用同一 workspace（不新建），新增 tab `rd-be`。

### 异常
- **AC3** 名字冲突：同名会话已存在 ⇒ 新会话 `pm2`（再冲突 `pm3`…），tab label 同步；`N > 9` 时给明确的「先清理」提示而非无限加号。
- **AC4** manifest 非法 / `@code` 不存在 ⇒ fail loud 列可用 code + 字段行号，**零 pane**。

### 边界
- **AC5** `default` session 内 `ensure` / `status` / `close` **可用**（不再 `exit 3`）；`cleanup -S default` 可执行但**必须**打印「将停止 session=default，影响 N 个 workspace / M 个 pane」。
- **AC6** 历史形态兼容：名册里带 `@` 的旧会话仍能被 `close <core>` / `close <core>@<旧 fleet>` 命中并回收（不静默「未运行」）。

### 负向闭环
- **AC7** 两仓同名 tab（都叫 `pm`）**互不影响**：`close pm` 只回收**当前 workspace** 的那一个；跨 workspace 同名不误杀。
- **AC8** 破坏面防护不回退：自面板守卫、归属不可判定即拒、忙闲闸门三条既有护栏**逐字保留**（`cleanup default` 放行不得旁路它们）。

### 设计一致性
- **AC9** ADR supersede 三篇：`2026-11-13-herdr-workspace-scope-key` / `2026-11-17-fleet-identity-source` / `2026-11-19-fleet-repo-manifest` 各加「已被本篇取代」注记，新 ADR 写明新判据句（放置键 = 仓；名字不含位置）。
- **AC10** 单源：放置键计算、名字冲突解析、manifest 映射各**一处**实现；`--fleet`/`fleet-scope` 的 warn 文案单处；文档三处（README/INSTALL/AGENTS）只留指针不双写。

## 八、上线闭环

- 门禁（**加速档**，沿用用户 2026-11-20 口径）：实现期 `check` + 目标用例 + `test:fast`；合并前**一次** `test:t4:full:dual`；QA **一轮**。
- 既有断言迁移：`cases/28`（命名契约）/ `33` / `37` / `38` / `39` 中依赖 `@` 段的断言需**迁移而非删除**（每处必须给「旧→新」对照）。
- 发布：**v0.27.0 MINOR**（0.x 下破坏性变更走 MINOR）；release notes 必须写「升级后旧 `@` 名字不再生成，但旧会话仍可回收 + `--fleet`/`fleet-scope` 弃用」。
- 回退：单条 squash 后 `git revert`；`fleet.yaml` 缺失即回到单仓行为。

## 九、变更治理

- **ADR 必带**（三篇 supersede ⇒ 结构性决策）：`docs/adr/2026-11-20-workspace-as-binding-unit.md`。
- **判据单源**：`docs/reports/554-lite-spec.md`（状态表：单仓/多仓/冲突/落后形态/default/破坏性动作）。
- **文档面**：`README.md`（用户面一句 + 指针）· `docs/INSTALL.md`（workspace=仓、manifest 映射、default 放行与 cleanup 提示）· `AGENTS.md`（PM 每仓一个的边界一行）· PM 卡（§三 或 §九 补「每仓 1 pm / 跨仓靠 intercom」一句，需 bump + 广播）。
- **弃用节奏**：`--fleet` / `fleet-scope` 本版 warn+忽略，**下一 MINOR 移除**（记入三档表）。
