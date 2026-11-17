# T547 · Issue #138 架构评审：`ensure` 舰队身份单一来源（批次一）

- 可行性：**有条件可行**（条件 = 下方 D-1..D-4 拍板；PRD §6 NFR 可满足，AC1–AC10 可实现）。输入 = PRD `2026-11-17-fleet-param.md` · `docs/adr/2026-11-13-herdr-workspace-scope-key.md` · `docs/INSTALL.md:121-124` · `nao-fleet.sh:1114/1796/1816/1886/2468` · Issue #139。ADR = `docs/adr/2026-11-17-fleet-identity-source.md`。检查清单未过项：**无**。
- **拍板结论（2026-11-17，权威见 ADR「拍板记录」）**：D-1..D-4 **全取 A 案**（D-1/D-4 用户 · D-2/D-3 PM）；下文各「待拍板」小段即评审期建议之存档，勿当未决项引用。

## D1 · 同源后的一致性：删回退，改传参

- **删** `_term_herdr_spawn` 的「parse 名字拿 label + 拿不到回退仓 slug」，改为**入参 `label`（= fleet）**，spawn 内 `fleet_scope_slug` 归零；连带 `cases/28` C3④ 与 `cases/33:196` 静态判据由「恰 1 次」改「**0 次**」= 收紧（第二数据源消失）。
- **历史残留判归属：零特判**。`status`/`close` 归属判据是 pane label（= 会话名）+ pane cwd，**workspace label 从不参与归属**（前序 ADR「不改归属判据」）⇒「名字 fleet ≠ workspace label」只是放置痕迹，列得出、`close <全名>` 必达。
- `fleet_scope_of_invocation` 的「文件缺失 ⇒ 静默空」本批**不可达**（默认 tier 恒非空）⇒ 收敛为「三档解析、永不为空、失败即 die」；该函数属抽取块，`cases/28` C1⑤ 相应断言改口径（空 ⇒ 仓 slug）。

## D2 · 名字恒带 scope 的回归面（只点名，不改）

- **契约失效**：`cases/28` C2②（ensure「已拉起」行 + pi `--name` 的 md5 == 冻结 fixture `2692b42`）与 `GOLD_ENSURE_TMUX`(`:674`)。fixture 是冻结 sha **不可重生** ⇒ 改为「新期望表 + 负控（默认 tier 改回空 ⇒ 名字丢 `@` ⇒ 必红）」；`--scope 16` 的 P2-1 三控原样保留。
- **判据字面**：`cases/33` U1/U2/U3/U4 的 `pane_ws_by_label rd-fe|qa|arch-designer`（pane label = 会话名 ⇒ 变 `*@<slug>`）；**U5 改语义** —— 两仓都无 scope 现在是 AC1 正路径，撞车负控改为「两仓同 `--fleet`」。
- **成功行字面**：`cases/22` AC1/AC2/AC4 的 `[tmux] 已拉起 arch-designer @ $LAB`（名字中段插 `@slug`）与「预置同名标题 ⇒ 跳过」夹具（须预置带 fleet 名）；`cases/32:154-155` 同型。`已拉起 rd-fe`（前缀匹配）与 status 渲染断言不受影响。
- 裸名解析（本仓 fleet → 唯一命中 → 拒绝）与 `cases/33` **不冲突**（33 不打 close/status）；与 AC6 的洞见 R2。

## D3 · 名长：会撞，且是新可达路径

- 32(core) + 1 + 16(fleet) = **49 > 48**（`fleet_name_parse:1819` 硬判）。今天只有显式 16 位 scope 才撞（P2-1 负控B 已钉「32+16 ⇒ 拒」）；恒带默认 slug 后**用户没选过**的长 core（卡/`--as`）+ 16 位目录名也会撞。
- 处置：**两条冻结上限都不动**（48 不抬、16 不缩），改分段适配 —— 默认 tier ⇒ slug 收到 `48-core-1`（≥1、去尾 `-`、打一条 log）；显式 tier（`--fleet`/文件）⇒ fail loud 并按 P3-b 口径点明缩哪段。

## D4 · `.agents/fleet-scope` 语义迁移的 check 面

- **加，但用 `·` 信息行**（完整报告/`-v`），**不进 `warn=N`、不进 rc**：文件存在是合法状态不是问题，而 `warn` 计数是 `cases/06:829` golden 行与 `cases/18:285` 的输入，用 `!` 会污染真问题信号。
- 行文给「生效 fleet 值 + 来源 tier（`--fleet`/文件/默认 slug）」，让单一来源在体检面可见（比「已降级」更有用；以调用者 cwd 解析，复用同一 resolver）。

## D5 · 弃用通道

- warn 放**参数解析处一次性**（`:4256` `case --scope)`）⇒ 天然「恰一条」（AC9）；`--scope` 维持 `_need_ensure`，回收/查看面零影响。
- **不打架**：`warn()` 走 stderr，t4 断言全为 `contains`，无「stderr 必须为空」类断言（已核 cases 22/25/29-32）。**不留 `NAO_STRICT_FLEET` 开关**：开关造第三态 + 自带用例/golden；下一 MINOR 移除是**语法删除**，届时本身 fail loud。替代 = 文案注明移除版本 + `-v` 打印 `≡ --fleet`。

## D6 · 批次二演进接口（不封死）

- 三条硬约束：① 放置键**禁止**由名字派生（D1 后成立）；② 放置键收敛到单点 `placement_key(fleet, repo)`（本批退化为 fleet-only），批次二只在同一函数内改「fleet + 仓短代号」，名字侧零改动；③ `fleet`（身份）与 `label`（放置）保持两个变量、禁止合并。
- 留给批次二自决（本批不设计）：单 `@` 冻结下「一 fleet 多仓」须把仓编进同一段 slug ⇒ 16 字符预算届时是真约束（`docs/tasks-state.md:10`）。

## 风险清单（影响 + 应对）

- **R1 默认 slug 撞保留前缀 ⇒ 本仓默认不可用**：`nao-skills` ⇒ `fleet_scope_problem` 拒（:1772）⇒ 升级后本仓 `ensure` 全仓中止（PM 手工删文件的那个现象**结构性复发**），任何 `nao-*`/`subagent-*` 目录名同命中。应对 = D-1（推荐把保留前缀规则限定在 core：scope 在 `@` 之后不占锚，`^subagent-` 排除不受影响）。
- **R2 AC6 的 `close` 裸名会「假成功」**：`fleet_scoped_candidates` 只收**带 scope** 候选 ⇒ `close pm` 解析成 `pm@slug`（不存在）⇒ 打「未运行（无需回收）」rc=0，而旧 `pm` 仍在跑。应对：解析增第 4 档「同仓 legacy 裸名」（仓证据成立才用；与 `pm@slug` 同时在场 ⇒ 拒绝并列候选）。
- **R3 升级期同角色重复（比 fail loud 更坏）**：冲突判据 = 同 core ∧ **同 scope** ∧ 异仓(:2490) ⇒ legacy `pm`(空 scope) 与 `pm@slug` 不同 scope ⇒ 判 absent ⇒ 同仓起出第二个 PM。应对：加「legacy 等价」—— 仅当 fleet 来自默认 tier 时，`core`(裸) 与 `core@<该仓 slug>` 视为同一会话 ⇒ `same`（skip + warn「旧名未追溯改名」）；显式 `--fleet` 时按 conflict。
- **R4 测试锚点随重构失效**：`cases/33:159` 变异锚 `SLUG_ANCHOR=…fleet_scope_slug…` 与 `:196` 静态断言在 D1 后不命中 ⇒ 用例红而非实现错。应对：RD 同 PR 重定锚点（N1 =「spawn 忽略入参回退会话名」；N2 =「resolver 返回空」），QA 复核两条负控仍点名红。
- **R5「已在运行」失配是用户可见的**：升级后首轮 `ensure` 不再识别裸旧会话（除非 R3）；`docs/INSTALL.md:121`「没有 scope 时名字与旧版逐字相同」必须删。应对：R3 + release notes 一条 `close <裸名>` 后重开。
- **R6 性能边界**：R3 等价判定需 pane cwd（`running_verdict` 内已有 `pane_cwd_snapshot`，每 run ≤1 次）；实现若再调一次 `pane list` 即破 NFR「≤1 次」。应对：复用快照，禁新增反查。

## 待拍板（架构师不代拍）

- **D-1 保留前缀（R1）**：A 把规则**限定在 core**、scope 放开（推荐：本仓零配置可用；代价 = §语法 guard 收窄一条）· B 保持拒绝（代价 = 本仓与 `nao-*` 仓必须写 `--fleet`）。
- **D-2 AC6「status 标注无 fleet」**：A **不做**（推荐：无 `@` 已可辨；加标注破 `cases/28` C2①/B1①/P2① 三处全文 golden + 用户可见渲染变更）· B 做（三处 golden 重写 + release note）。
- **D-3 legacy 等价（R3）**：A 同仓等价 = `same`（推荐：升级零操作）· B fail loud 列候选（用户须先 `close` 旧名）。
- **D-4 名长（D3）**：A 默认 tier 自动收 slug（推荐）· B 一律 fail loud 让用户写 `--fleet`。

## 连带同步清单（改既有条款；Owner）

- `docs/INSTALL.md:121`「无 scope ⇒ 名字逐字相同」+ :123 预算 + :124 冻结口径 ⇒ **PM**；`README.md` 多仓段 ⇒ **PM**
- `.agents/common/intercom-protocol.md:11`（两仓并发「必须」设 scope · 裸名 close 口径）⇒ **rd-infra**；`nao-fleet.sh:41-47` usage ⇒ **rd-infra**；ADR `2026-11-13-…` 放置键来源由本 ADR 演进（不废原文）⇒ **arch**
