# ADR：舰队身份单一来源（`--fleet` 同时定会话名 scope 与 workspace 放置键）

- 状态：已接受（待落地）
- 更新：2026-11-17
- Owner：arch-designer
- 指针：Issue [#138](https://github.com/Nathan3303/nao-skills/issues/138) · PRD `docs/prds/2026-11-17-fleet-param.md` · 评审 `docs/reports/138-arch-review.md` · 前序 `docs/adr/2026-11-13-herdr-workspace-scope-key.md` · 批次二占位 [#139](https://github.com/Nathan3303/nao-skills/issues/139)

## 背景

- 今天 `ensure` 的一个决定拆成两个来源：放置键 = 「已声明 scope 否则仓 slug」（`nao-fleet.sh:1114`），身份 scope 只来自 `--scope` 或 `<目标仓>/.agents/fleet-scope`（`:1886`）。
- 后果可复现：两仓都不声明 scope ⇒ 放置分开，名字**都叫 `pm`** ⇒ 第二个 `ensure` fail loud。「能否开 N 舰队」取决于用户有没有手写配置文件，而非显式输入。
- `docs/INSTALL.md:124` 只允许「替换 scope 的来源」；名字语法 `<core>[@<scope>]`、48/32/16 三个上限均冻结。

## 决策

`fleet` 成为唯一输入并按 `--fleet` > `<目标仓>/.agents/fleet-scope` > 仓 slug（`fleet_scope_slug`）解析，**恒非空、失败即 die**；该值同时构成会话名 scope 与 herdr workspace 放置键，且**以参数传入 spawn**（不再由名字反解）。`--scope` 降为弃用别名（warn 一条，下一 MINOR 删除）。语法、三个长度上限、`status`/`close` 的归属判据（pane label + pane cwd）均不变。

## 理由

1. 业务：既有的三件事（放置 / 身份 / 单例边界）由一个值决定 ⇒ 「N 仓并行」从「要写配置」变成默认成立（用户拍板 ①–③）。
2. 成熟度：名字的单点构造/解析（`:1796`/`:1816`）已在位，本批只换来源 + 去掉反解，不引入新机制、不新增 herdr 调用。
3. 团队：改动收敛在三处（resolver、spawn 入参、args），t4 负控可独立复核；与批次二的边界靠「放置键单点函数」保持可演进。
4. 成本：零配置迁移；代价是推翻「无 scope ⇒ 名字逐字不变」（BR1 前提**按设计退役**），已在 release notes 承担。

## 对照过的备选模式

1. **维持现状**（放置分离 / 身份分离）—— 适用：单仓单舰队；代价：第二个 `ensure` 必 fail loud，N 仓须手写 `fleet-scope`；**不采纳**：即本缺陷。
2. **强制声明 scope**（缺则 fail loud 指路）—— 适用：愿为每仓写一行的团队；代价：默认路径仍不可用，且 `nao-*` 仓连写都写不成（保留前缀）；**不采纳**：把默认能力变成配置负担。
3. **名字不改、只按 workspace 分组**（身份仍撞）—— 适用：永不并存；代价：违背 AC1、`status` 两行同名无法区分；**不采纳**。
4. **采纳：fleet 单一来源 + 名字恒带 `@` + 放置/身份同源** —— 适用：同机同 session 多仓、每仓一支舰队；代价：升级期并存两条命名 + 旧断言面需重定（见评审 D2）。

## 后果与风险

- 正面：AC1 零配置并存成立；spawn 的第二数据源消失（静态判据从「恰 1 次 slug 调用」收紧为「0 次」）；`fleet-scope` 从「必需声明」降级为「覆盖值」。
- 负面：会话名恒带后缀 ⇒ 升级期新旧名并存；`status`/`close` 需一条「同仓 legacy 裸名」等价/回退规则，否则旧会话既会被重复拉起、`close` 又会假成功（评审 R2/R3）。
- 风险（待拍板）：默认 slug 撞保留前缀使**本仓**默认不可用（D-1）；32+1+16=49 的组合在默认 tier 下新可达（D-4）；`status` 若加「无 fleet」标注会破三处全文 golden（D-2）。
- 迁移：不追溯改名；`close <全名>` 恒可达；下游三仓一行提示 = 「首轮 `ensure` 将新建 `@<仓 slug>` 名；旧裸名会话 `close <名>` 后重开」。

## 限制与已知边界

- 本批放置键 = fleet **单段**：`placement_key(fleet, repo)` 退化为 fleet-only；批次二（#139）才允许变「fleet + 仓短代号」两段，且**必须**在该函数内改，禁回退到「由名字派生放置键」。
- `fleet`（身份）与 `label`（放置）在实现中保持两个变量，取值相同**不得**合并成一个 —— 这是批次二的解耦点。
- 单 `@` 语法冻结 ⇒ 批次二「一 fleet 多仓」必须把仓编进同一段 slug，16 字符预算届时是真约束（已登记 `docs/tasks-state.md:10`）。
- 不做：`--fleet` 用于 `close`/`status`（跨 fleet 用全名）；同名仓自动探测；对已存在的 pane 重排或改名。

## 相关指针

- D1–D6 全文 · 回归面点名 · 风险 · 连带同步清单（含 Owner）：`docs/reports/138-arch-review.md`
- 前序：`docs/adr/2026-11-13-herdr-workspace-scope-key.md`（放置键/身份键分离；本篇把放置键**来源**并入 fleet，原文的「label = 已声明 scope 否则 slug」由本篇取代）

## 参考来源

- [herdr CLI reference](https://herdr.dev/tui/docs/cli-reference/) · 访问 2026-11-17 · workspace 以 `--label` / `--cwd` 创建 ⇒ label 是**放置**语义，不承担身份。
- [tmux 3.7c manual（libtmux 镜像）](https://libtmux.org/en/tmux/latest/manual/full/) · 访问 2026-11-17 · 会话名唯一但 `-t` 默认为前缀匹配 ⇒ 名字必须能被精确解析（本仓以 `=` 锚定，`nao-fleet.sh:2400`）。
- [Kubernetes · Object Names and IDs](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/) · 访问 2026-11-17 · 「唯一名即身份，非唯一属性用 labels」⇒ 支持「label 不作归属证据」。
- [Kubernetes · Namespaces](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/) · 访问 2026-11-17 · 名字在 scope 内唯一、跨 scope 不唯一 ⇒ 与「fleet 内同 core 唯一、跨 fleet 可并存」同形。
