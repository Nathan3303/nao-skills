# ADR：workspace 为绑定单位（取消 fleet · 名字不含位置）

- 状态：已落地（v0.27.0 起 · 实现 `f962813`）· 注记 2026-11-22：tmux 回退面已删除（`2026-11-22-herdr-only`），本文的 workspace=仓 / 名字契约在单后端下不变
- 更新：2026-11-21
- Owner：arch-designer
- 指针：Issue [#554](https://github.com/Nathan3303/nao-skills/issues/554) · PRD `docs/prds/2026-11-20-fleet-model-v2.md` · 判据 `docs/reports/554-lite-spec.md` · 被本篇取代：`2026-11-13-herdr-workspace-scope-key.md` / `2026-11-17-fleet-identity-source.md` / `2026-11-19-fleet-repo-manifest.md`

## 背景

- herdr 0.9.5 **不做任何 label 唯一性校验**（同 workspace 内两个 `pm` tab、同 label 的 workspace 均允许）⇒ 唯一性必须由机制自己持有。
- v0.26.0 的 fleet 同时承担会话名 `@` 段 / 判重键 / workspace 放置键；而「1 workspace = 1 仓」要求放置键是**仓**，三职责无法共存于一个字符串。
- 用户四答（2026-11-20）：彻底取消 fleet · 名字 = 角色名 + 数字 · 每仓一个 pm · `fleet.yaml` 只留「仓代号 → 路径」· default session 全放行。

## 决策

1. **新判据句：放置键 = 仓**（workspace label = 仓基键，同名加数字）；**名字不含位置**（`@` 段删除）。
2. 名字 = 常驻 `<role>[<N>]` / 派生 `<role>[<N>](<task>)`（task 逐字入括号、紧贴角色名，N 在 `(` 前、单字符）；同 workspace 内同名加数字，N > 9 fail loud。
3. 1 workspace = 1 仓 = 1 pm（pm 与 worker 同为 workspace 内 tab）；`.agents/fleet.yaml` 降级为 `code → path` 映射（去 `slug`）；`ensure <role>@<code>` 的 `@` 只选目标仓、不进名字。
4. `default` 与专用 session 等价，差异只在破坏性动作**打印影响面**；`--fleet` / `--scope` / `.agents/fleet-scope` 本版 warn + 忽略，下一 MINOR 移除。

## 理由

1. 业务：用户诉求是「不挑 session、每仓一个 pm」；唯一性由机制持有才不依赖后端校验。
2. 成熟度：名字单点构造/解析、放置单点入参、`close` 归属判据已在位；本批只换来源并收窄 manifest，不新增后端调用面。
3. 团队：改动收敛在四处（label 计算 / 名字构造与解析 / `ensure` 相位 1 / `default` 守卫分级），t4 可逐态负控。
4. 成本：零新依赖、零网络；弃用期一版；回退 = 单条 squash revert（`fleet.yaml` 缺失即回到单仓行为）。

## 对照过的备选模式

1. **维持现状（fleet 三职责同源）** —— 适用：单仓单舰队；代价：放置键与「1 ws = 1 仓」直接冲突，名字与位置强耦合；**不采纳**：即本缺陷。
2. **全局名字唯一（跨仓也加数字）** —— 适用：名册/回收需要全局唯一名；代价：用户明确要求每仓都可叫 `pm`，跨仓也膨胀成 `pm2/pm3` 且位置仍不可读；**不采纳**。
3. **保留 `@` 只作判重键（不表位置）** —— 适用：想留升级锚点；代价：`@` 语义已漂移两次（fleet → code），保留只会加深歧义，且判重仍与放置纠缠；**不采纳**。
4. **采纳：workspace 为绑定单位 + 名字去位置 + 数字后缀**（见决策 1–4）。

## 后果与风险

- **取代关系与各自失效点**：
  - `2026-11-13-herdr-workspace-scope-key`：「放置键 = 已声明 scope 否则仓 slug」失效（放置键只由仓派生，scope 退场）；「键恒非空 / worktree 同键 / 禁名字反解」保留（基键归一只需一处）。
  - `2026-11-17-fleet-identity-source`：「放置键与身份键同源（都 = fleet）」失效（名字无位置段，放置键 = 仓）；「`--fleet` 三档优先级」随弃用退场；「禁由名字反解放置键」保留并加强。
  - `2026-11-19-fleet-repo-manifest`：「1 fleet = 1 workspace」与「tab 前缀 `<code>/` 分组」失效（1 ws = 1 仓，同仓无需分组）；manifest 只留 `code → path`。
- 正面：跨仓同名合法且互不影响；`close`/`status` 归属由 workspace + pane cwd 唯一确定；名字可读（`pm2` = 第二个 pm）。
- 负面：升级期新旧名字并存 ⇒ 带 `@` 的旧会话只能走 legacy 读模式；`--fleet`/`fleet-scope` 被忽略属「配置静默失效」，靠恰一行 warn 兜住。
- 风险：名字文法（括号位置 + 槽位形态）是最高回归面；判据 §一 给两条反例，§四 逐处迁移旧断言（实为 8 个用例，含 20/22/24）。

## 限制与已知边界

- **`default` 放行的风险边界**：`cleanup --session default`（含内部 `session stop`）**必须**先打印「将停止 session=default，影响 N 个 workspace / M 个 pane」；无 `--force` 时零动作（rc=2），有 `--force` 才执行并点名「当前 pane 属于该 session，将被终止」。`close`（单会话）照旧打印目标名 + `@ <仓>`。
- **不许旁路的护栏**：自面板守卫（`_term_herdr_self_refuse`，`cleanup default` 亦须拒当前 pane 自拆）/ 归属不可判定即拒（pane cwd 与名册均无 ⇒ die，禁「首命中」）/ 忙闲闸门（`cleanup` 含 working/blocked pane ⇒ 无 `--force` 拒绝）。
- 名字预算：`<N>` 占 1 字符、`(task)` 逐字入括号（`T` 是任务号自带前缀，不另加）；name ≤ 48、role 段（含 N）≤ 32；三形态按首个分隔符 `(`/`-`/`@` 分派，旧形只读。
- manifest 源仍 = 调用方仓根，不向上查找、不自动发现；旧 `slug:` 字段与 `fleet-scope` 同属弃用面（warn + 忽略一版）。
- 不做：跨 herdr session 协同、自动发现联动仓、布局几何算式、`pi` 侧改动。

## 参考来源

- [herdr CLI reference](https://herdr.dev/tui/docs/cli-reference/) · 访问 2026-11-13（沿用前序 ADR 检索）· `workspace create --label` 是放置语义；`tab` 无重排命令。
- [Kubernetes · Object Names and IDs](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/) · 访问 2026-11-17（沿用）· 唯一名即身份、非唯一属性用 label。
- 本机实测（herdr 0.9.5 · 2026-11-20 · PM 探测会话，已回收）：同 workspace 两个 `pm` tab、同 label workspace 均允许 ⇒ 唯一性必须机制自持。
