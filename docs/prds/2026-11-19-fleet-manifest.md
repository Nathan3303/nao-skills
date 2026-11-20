# PRD · 联动仓 manifest（多仓编队）· #139 / T553

- 状态：草案（PM 已按结构契约重排 · 待 arch 判据核可后开工）· 更新：2026-11-20 · Owner：product-manager · 批次二
- 前序：批次一 `--fleet` 单一来源（#138 / T547 · 已合并 v0.25.0）· 本文取代 Issue #139 占位正文
- 用户拍板：2026-11-17 形态三条（① fleet = 1 workspace ② 新文件 `.agents/fleet.yaml` ③ scope = 仓短代号）；2026-11-19 追加（**MVP = A 最小可用**，`fleet-scope` 不迁移 · **门禁 = 加速档** · **ADR 由 arch-designer 出**）

## TL;DR（≤5 行）

- 一支舰队要能**声明联动仓**（如 `api` / `web`），并把角色**派生到指定联动仓**干活，而它们仍属**同一支舰队**（同一 workspace）。
- 名字用 `<core>@<仓代号>`；放置键恒为**舰队值**（manifest `slug`）⇒ 「放置」与「身份」**不再同源**（前序 ADR 条款由本批 ADR 改写）。
- 无 manifest 的仓库行为**逐字不变**；三处「不许猜」（解析 / 放置 / 回收）。

## 一、问题证据

1. **没有辖域声明载体**：`ensure` 的派生只能落在调用方仓；既无法校验「这支舰队辖哪几个仓」，也无法给派生物起名。
2. **放置键 = 舰队身份**（`docs/adr/2026-11-17-fleet-identity-source.md`）：多仓协作时必然散成多个 workspace，或落进他仓 workspace。
3. **`@` 段已被占用且已有另一含义**：`ensure <role>@<x>` 的 `@` **今天就是「目标仓路径」**（`nao-fleet.sh` 的 positional 解析段）⇒ 加 `@<code>` 会造成同一条命令的 `@` 有两种语义（arch 实测已确认，见 `docs/reports/139-lite-spec.md` 现状断点）。
4. 证据面：用户 2026-11-17 口述前后端分离协作场景；本仓现行 6 角色 + `ensure` 多目标能力（T539）已具备「一次拉多个角色」，缺的只是「拉到哪个仓」。

## 二、目标指标

- **可声明**：一个仓能用 `.agents/fleet.yaml` 描述「舰队名 + n 个联动仓（短代号 + 路径）」，非法即 fail loud（带字段与行号）。
- **可派生**：`ensure rd-be@api` 能落进 api 仓并起会话名 `rd-be@api`，**与原舰队同一 workspace**。
- **零回归**：无 manifest 的仓库，`ensure` / `check` / `status` / `close` 输出**逐字不变**（既有断言面不减）。
- **不猜**：`@` 未命中、编译期并列、回收歧义三处一律 fail loud 并列候选。

## 三、范围 / 非范围

**范围**：M1 manifest 解析与校验 · M2 目标解析（`@` 四步）· M3 放置键 = `slug` + tab 按仓分组 · M4 命名契约（三预算不放宽）· M5 `status`/`close` 读面与回收 · M6 文档（`README` 一句 + `INSTALL` 写法 + `AGENTS.md` 一行指针）。

**非范围**：跨 herdr session 协同 · `fleet-scope` 迁移/deprecate（保留不动，MVP=A）· 联动仓之间的依赖编排/构建 · 自动发现联动仓 · tmux 的后端 tab 分组语义（结构不可达，NOTE 点名）。

## 四、用户场景

- **S1（主路径）**：主仓有 `fleet.yaml`（`slug: alpha` · `api: ../api` · `web: ../web`）。PM 在主仓 `ensure rd-be@api` ⇒ 终端切到既有 `alpha` workspace，tab 标签 `<code>/<name>` 归入 api 组，pane cwd = `../api` 物理路径；`status` 同时显示「目标仓 api」与「所属舰队 alpha」两组事实。
- **S2（不声明）**：没有 manifest 的仓 `ensure rd-be` ⇒ 与 v0.25.2 完全一致（含 `--fleet` / `fleet-scope` / 仓 slug 三档）。
- **S3（写错）**：`ensure rd-be@nop`（code 不存在）⇒ 拒绝并列出可用 code；`fleet.yaml` 里 `path` 不存在 ⇒ 拒绝并指出字段与行号，**零 pane**。

## 五、业务规则

- **R1 放置键单值**：workspace 只由**舰队值**决定（`--fleet` > `fleet-scope` > `manifest.slug` > 仓 slug）；manifest 与 `fleet-scope` 分歧 ⇒ fail loud；`--fleet` ≠ `manifest.slug` ⇒ fail loud（arch D2，已拍）。
- **R2 `@` 四步解析（唯一顺序）**：① 命中 manifest `code` ⇒ 联动仓 ② 否则按**既有仓路径**语义 ③ 两者同时命中且物理路径不同 ⇒ **fail loud** ④ 都未命中 ⇒ fail loud 并列出可用 code 与「按路径」写法。**禁**「先试 code 失败再当路径」的静默两义兜底。
- **R3 `code` 命名空间**：manifest 校验期强制 `code ∩ {slug} = ∅` 且联动仓禁 `main` ⇒ 任意 `@` 值三分法全域唯一（`main` = 主仓组前缀，常量）。
- **R4 tab 分组判据（取代「物理相邻」）**：herdr tab label = `<组前缀>/<name>`；**属组 ⇔ 首段（第一个 `/` 前）= 组前缀**；主仓组前缀固定 `main`。herdr 0.9.x 无 tab 重排 ⇒ 不追求相邻。
- **R5 三预算不放宽**：`core ≤32` / `scope(code) ≤16` / `full ≤48`；本设计**不拼接** `slug+code`（scope 单段 = code）⇒ 数值不变；撞线 fail loud 并点名够不着的段，**禁自动截短**。
- **R6 不猜**：解析、放置、回收三处禁「首个命中」兜底（沿用 #146/#151 口径）。

## 六、NFRs

- **兼容**：无 manifest ⇒ 行为逐字等价（结构保证，不靠断言兜）；`check` 的 files 计数与既有用例断言面**不得减少**。
- **失败可读**：所有 fail loud 文案含「哪个文件/字段/行号 + 该怎么办」；禁裸 `exit 1`。
- **零网络 / 零新依赖**：manifest 解析纯 shell + 既有函数复用（`nao_phys_path` / `repo_contains_path`）。
- **缓存**：解析结果**仅进程内**一次；**禁**落盘缓存（运行期改坏必须下一次即 fail loud）。
- **成本**：带 manifest 的 `ensure` 额外不引入 per-target 的重复解析（单次加载，多目标共用）。

## 七、AC

### 主路径
- **AC1** manifest 合法时 `ensure rd-be@api` ⇒ 会话名 `rd-be@api` · pane cwd = api 仓物理路径 · 落在 `slug` 决定的**同一** workspace · tab label 首段 = `api`。
- **AC2** 无 manifest 时，`ensure` / `check` / `status` / `close` 四命令输出与 v0.25.2 **逐字一致**（零回归，含三档 fleet 解析与既有用例断言面不减）。

### 异常
- **AC3** manifest 各字段非法（缺 `slug` / `code` 重复 / `code` 撞 `slug` / `code` 含 `@ . :` 或空白 / `path` 不存在 / `path` 逃出仓根 symlink / 未知字段）⇒ fail loud 指出字段 + 行号，**零 pane**。
- **AC4** `@` 未命中：code 不存在且不是有效仓路径 ⇒ 拒绝并列出可用 code；若同时是仓路径 ⇒ 按 R2③ 判定（不同路径 ⇒ fail loud）。

### 边界
- **AC5** 三预算逐条可触发 fail loud（`core`/`code`/`full`），文案点明够不着的段；不放宽任何一条。
- **AC6** `fleet.yaml` 与 `fleet-scope` 共存：优先级唯一（R1），分歧 ⇒ fail loud；`--fleet` ≠ `manifest.slug` ⇒ fail loud。

### 负向闭环
- **AC7** `close <core>@<code>` 在同 code 多 pane / 同名跨仓时拒绝并列候选、零回收（不猜）。
- **AC8** manifest 运行期被改坏（单行非法）⇒ 下一次调用即 fail loud，不沿用上次结果（无落盘缓存）。

### 设计一致性
- **AC9** ADR `docs/adr/2026-11-19-fleet-repo-manifest.md` 落地且与实现一致：显式改写「放置键与身份键同源」· 唯一化 `@` 双语义 · 给出 `fleet-scope` 共存优先级 · tab 分组判据句唯一。
- **AC10** 单源：manifest 解析**一处**实现；`code` 校验与三预算**复用**既有函数（禁第二份）；tab 前缀四处同源（收敛 / `tab_id_for` / 建 tab / rename）。

## 八、上线闭环

- 门禁（**加速档**，用户 2026-11-19 拍板）：实现期 `check` rc=0 + 目标用例 `cases/39` + `npm run test:fast` rc=0；**合并前一次** `npm run test:t4:full:dual` 两组 rc=0（SKIP=0 / DEGRADE=0 / 非白名单 NOTE=0）；QA **一轮**（非作者复核为底线，不做逐条变异全覆盖 / 不做终检轮）。
- 发布：合并后 **v0.26.0 MINOR**（新功能面）；release notes 面向用户写「能声明联动仓了 + 无 manifest 不受影响」。
- 回退：单条 squash 后 `git revert <squash-sha>`；manifest 缺失即回 v0.25.2 行为 ⇒ 回退天然安全。

## 九、变更治理

- **ADR 必带**（Issue 要求）：`docs/adr/2026-11-19-fleet-repo-manifest.md`（arch-designer 出 · 已含 5 个对照模式与 R1–R7 风险）。
- **判据单源**：`docs/reports/139-lite-spec.md`（13 态判据表 + 变异方向 + 禁改区）。
- **文档面**：`README.md` 一句 + 指针 · `docs/INSTALL.md` manifest 写法与边界 · `AGENTS.md` 一行（PM 辖域 = 「能派到哪些仓」，AC9③ 事实源 = manifest + 该指针）。
- **快档**：用例 39 **不入** `FAST_CASES`（D5，已拍）。
