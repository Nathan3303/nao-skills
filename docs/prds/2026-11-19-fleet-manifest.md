# PRD · 联动仓 manifest（多仓编队）· #139 / T553

- 状态：草案（待 PM 自审 → arch ADR）· 更新：2026-11-19 · Owner：product-manager · 批次二
- 前序：批次一 `--fleet` 单一来源（#138 / T547 · 已合并 v0.25.0）· 本文取代 Issue #139 的占位正文
- 用户拍板（2026-11-17，形态三条，不再讨论）：① **fleet = 1 个 workspace**（所有联动仓的角色同住，tab 按仓分组）② 新文件 **`.agents/fleet.yaml`**（slug + 联动仓列表 + 短代号）③ **scope = 仓短代号**（由 manifest 分配）
- 本次追加拍板（2026-11-19）：**MVP = A 最小可用**（`fleet-scope` 保留不动、不迁移）· **门禁 = 加速档**（实现期 `test:fast` + 目标用例；合并前一次双后端全量；QA 一轮）· **ADR 由 arch-designer 出**

## 一、问题

一支舰队目前**只能在一个仓里干活**：`ensure` 的派生会话落在调用方仓，放置键（1 workspace/仓）与身份键（`<core>@<fleet>`）**同源**。真实协作里常见前后端分离（`api` / `web`）：PM 在同一支舰队里要能**把 rd-be 派到 api 仓、rd-fe 派到 web 仓**，而它们仍属于**同一支舰队**（同一 workspace、同一 fleet 身份）。

现状的硬障碍三条：
1. 没有「这支舰队辖哪几个仓」的声明载体 ⇒ 既无法校验目标、也无法给派生物起名
2. 放置键 = 舰队身份 ⇒ 多仓必然散成多个 workspace（或落到他舱 workspace）
3. 会话名 `@<scope>` 段已被 fleet 占用；若 scope 改仓短代号，则「身份」与「位置」不再同源（**必须由 ADR 显式改写前序结论**）

## 二、目标 / 非目标

**目标**：一支舰队可**声明联动仓**，并把角色**派生到指定联动仓**上干活；派生会话名字用**仓短代号**、放置仍归**同一个 workspace**；`status` / `close` / 回收面按新语义工作且**不猜**。

**非目标（本批不做）**：跨 herdr session 协同（无需求证据）· `fleet-scope` 迁移/deprecate（用户选 A，保留不动）· 联动仓之间的依赖编排/构建（只解决「派谁去哪个仓」）· 自动发现联动仓（必须显式声明）。

## 三、形态（已定，实现按此）

- **manifest**：`<仓>/.agents/fleet.yaml`，字段 = `slug`（舰队名，≤16）· `repos`（列表：`code`（仓短代号，≤16）+ `path`（相对或绝对，物理归一后必须存在））。主仓（manifest 所在仓）允许用保留代号 `main` 指代自身。
- **命名**：派生到联动仓的会话名 = `<core>@<code>`（`code` 即 scope）；主仓会话沿用现有 fleet slug（= `slug`），**保持向后兼容**。
- **放置**：`slug` 决定 workspace（1 fleet = 1 workspace）；tab 按仓分组（`<code>` 前缀或 tab 命名含 code，具体形态交 arch 定）。

## 四、范围（模块）

- **M1 manifest 解析**：读取/校验 `fleet.yaml`（缺失 ⇒ 与服务现状等价；非法/多行/越界/symlink 逃仓/未知字段 ⇒ **fail loud**，不猜）。解析结果进程内缓存一次。
- **M2 目标仓解析**：`ensure <角色>@<code>` 中 `@` 段先按 **manifest code** 解析；未命中 ⇒ 回落现有 fleet 语义（`--fleet` / `fleet-scope` / 仓 slug）并**给出可判定提示**；`--fleet` 与 `@<code>` 同时给且冲突 ⇒ fail loud。
- **M3 放置键**：`slug` → workspace；**不因目标仓不同而新开 workspace**（与现行「1 workspace/仓」冲突处由 ADR 改判）。
- **M4 命名契约**：`<core> ≤32` / `scope(code) ≤16` / `full ≤48` 三条**既有硬约束不变**；超限 fail loud 并指出是哪一段够不着。
- **M5 读面与回收**：`status` 能显示「目标仓」与「所属 fleet」两组事实（不混为一谈）；`close` 对带 code 的会话**只在本仓锚内解析**（禁跨仓猜），歧义列候选。
- **M6 文档**：`README.md`（用户面一句 + 指针）· `docs/INSTALL.md`（manifest 写法与边界）· `AGENTS.md`（若需项目约束一行）。

## 五、AC（五组骨架 · 缺一即结构性缺失）

### 主路径
- **AC1** 有 manifest（`slug: alpha` + `api: ../api`）时，在主仓 `ensure rd-be@api` ⇒ 会话名 `rd-be@api`、pane cwd = api 仓物理路径、落在 `alpha` 的 **同一** workspace、tab 属 api 分组。
- **AC2** 不带 `@code` 的 `ensure rd-be` ⇒ 行为与 v0.25.2 逐字一致（零回归，含 `--fleet` 三档解析）。

### 异常
- **AC3** manifest 非法（缺 `slug` / `code` 重复 / `code` 含 `@ . :` 或空白 / `path` 不存在或逃出仓根 symlink）⇒ **fail loud** 且指出字段与行号；进程不得起任何 pane。
- **AC4** `ensure rd-be@nope`（code 不在 manifest）⇒ 拒绝并列出**可用 code**，不静默回落成仓 slug（回落会让用户以为派生成功但落错仓）。

### 边界
- **AC5** 名字预算：`core` 32 / `code` 16 / `full` 48 三条逐条可触发 fail loud，文案点明哪段够不着（回归备份：不因本批放宽任何一条）。
- **AC6** `fleet.yaml` 与 `fleet-scope` **同时存在**：按 A 口径 `fleet-scope` 仍生效（不迁移），二者冲突时以谁为准必须**唯一且写进文档**，并有断言。

### 负向闭环
- **AC7** `close <core>@<code>` 在「同 code 多 pane」或「同名气跨仓」时**拒绝并列候选**、零回收（沿用 T551/T552 的「不猜」口径）。
- **AC8** manifest 文件在运行期被改坏（单行非法）：下一次调用 fail loud 而**不沿用上次缓存**（缓存不得跨调用持久化到磁盘）。

### 设计一致性
- **AC9** ADR 落地并与实现一致：ADR 必须显式处理 ① 改写「放置键与身份键同源」的前序结论 ② 命名 `@` 段语义变化（fleet → code）与 `fleet-scope` 的共存 ③ PM 辖域边界（「能派到哪些仓」写入 PM 卡或 `AGENTS.md` 指针）。
- **AC10** 单源：manifest 解析只有一处实现；`code` 校验与名字预算**复用**既有函数（禁复制粘贴第二份）。

## 六、硬约束与风险

- **命名硬约束不放宽**：`full ≤48` 是现有断言面，联动仓叠加很容易撞线 ⇒ ADR 必须给「撞线时怎么办」（建议：fail loud + 指出缩短哪段，禁自动截短）。
- **向后兼容红线**：无 manifest 的仓库行为**逐字不变**（`check` 的 files 计数与既有用例断言不得减少）。
- **PM 唯一调度者不变**：辖域变宽只扩大「能派到哪些仓」，不改变「PM 是唯一调度者」。
- **不猜**：解析、放置、回收三处**都不许**用「首个命中」兜底（这是 #146/#151 两批刚立的规矩）。

## 七、门禁（加速档 · 用户 2026-11-19 拍板）

- 实现期：`bash .agents/scripts/nao-fleet.sh check` rc=0 + 目标用例（`cases/39`）+ `npm run test:fast` rc=0
- 合并前：**一次** `npm run test:t4:full:dual` 两组 rc=0（SKIP=0 / DEGRADE=0 / 非白名单 NOTE=0）
- QA：**一轮**（不做逐条变异全覆盖、不做终检轮）；仍需「非作者复核」一条底线
- 发布：合并后 **v0.26.0 MINOR**（新功能面）

## 八、验收与回退

- 验收：PM 自证数字（`check` / 用例数 / 目标用例断言 / 全量一次）+ 读码核 AC1–AC10 + QA 一轮结论。
- 回退：单条 squash 后 `git revert <squash-sha>`（manifest 缺失即回到 v0.25.2 行为 ⇒ 回退天然安全）。
