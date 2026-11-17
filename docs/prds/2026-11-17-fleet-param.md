# PRD：`ensure` 的舰队身份显式化（`--fleet` 单一来源 · 批次一）

- 状态：待确认（开工前须用户确认）· Owner：PM
- 更新：2026-11-17
- 指针：上游对话（2026-11-17 用户提出「同一 herdr session 跑 n 仓 n 舰队」）· 现行契约 ADR `docs/adr/2026-11-13-herdr-workspace-scope-key.md` · 会话名契约 BR8（`fleet_name_build`/`fleet_name_parse`，语法冻结）· 姐妹批 = 批次二「联动仓 manifest」（本批合并后另立项，见 `docs/tasks-state.md` 待派发队列）
- 优先级：战略筛子通过（直接解「N 仓并行」卡点）· RICE 见附录（Score 13.5，P1）

## TL;DR（≤5 行）

- **做什么**：把「我是哪个舰队」变成 `ensure` 的**显式单一输入**。新增 `--fleet <slug>`；缺省值 = 目标仓 slug；该值**同时**决定 workspace 放置、会话名 scope 与单例边界。会话名因此**恒定**带 `@<fleet>`。
- **给谁**：同一台机、同一个 herdr session 里并行多个仓的用户（每仓一个 PM、一支舰队）。
- **成功标准**：不开任何 scope 文件、不写 `--scope`，两个仓各自 `ensure pm rd-fe qa` 后**并存**（`pm@api` / `pm@web`），`status` 一张表看全，`close pm` 在各自仓内各回收各的；`check` + `npm test` 全量 rc=0。
- **不做什么**：不做联动仓 manifest（批次二）；不把 workspace 粒度从「1 仓 1 个」改成「1 舰队 1 个」；不合并 `.agents/fleet-scope` 与新 manifest（批次二一次性迁移）。

## 一、问题证据

`ensure` 今天已经在决定四件事，但**四个决定的来源互不相同**（`nao-fleet.sh`）：工作目录取 `[@<仓>]` 或 `roles.yaml` workspace（`:4062`、`:1209`）；workspace 放置取「已声明 scope 否则仓 slug」（`:1114`）；会话名取 `core[@scope]`，scope **只来自** `--scope` 或 `<仓>/.agents/fleet-scope`（`:1796`）；单例边界由名字撞不撞决定。

后果是可复现的：两个仓都不声明 scope 时，**放置是分开的**（各自 workspace，label=仓 slug），但**身份撞在一起**（都叫 `pm`）⇒ 第二个仓 `ensure pm` 直接 fail loud。也就是说「能不能开 N 个舰队」取决于用户有没有手写一个 scope 文件，而不是一个显式输入。

5 Whys：为什么用户以为「不支持 N 舰队」→ 因为第二次 `ensure pm` 被拒；→ 因为身份键不取默认值；→ 因为设计刻意把「放置键」与「身份键」分离（T545，防跨仓落错）；→ 因为当时只解「落错仓」，没解「一个仓一个舰队」的表达；→ 现在需要显式的舰队身份。

## 二、目标指标

- 北极星：零配置文件前提下，第二个仓 `ensure pm` 成功率 100%（现状 0%），且 `status` 单表可见全部舰队会话。
- 支撑：`check` + `npm test` 全量 rc=0；名字长度约束（core ≤32 · scope ≤16 · 总长 ≤48）零违规；并存期旧裸名会话仍可 `status`/`close`。

## 三、范围 / 非范围

- **范围**：`ensure` 新增 `--fleet <slug>`；fleet 值解析优先级 `--fleet` > `<目标仓>/.agents/fleet-scope` > 目标仓 slug；名字**恒定**带 `@<fleet>`；workspace label 与名字 scope **同源**；`--scope` 降为弃用别名（warn 不报错，下一 MINOR 移除）；`status`/`close` 的识别口径随之统一；文档（`docs/INSTALL.md`、README 多仓段、`--help`）；`tests/t4` 相应断言更新。
- **非范围**：1) 联动仓 manifest（`.agents/fleet.yaml`、仓短代号、fleet=1 workspace、tab 按仓分组）——理由：会改布局 ADR 与会话名上限口径，风险量级不同，另批；2) 把「1 仓 1 workspace」改成「1 舰队 1 workspace」——理由：同上，批次二定；3) 移除 `.agents/fleet-scope`——理由：批次二引入新 manifest 时一次性迁移，本批保留为唯一覆盖文件；4) 跨 herdr session（多 session 协同）——理由：本批只解同 session 多仓，跨 session 无现行需求证据。

## 四、用户场景

- **画像**：一台机、一个 herdr session、2–4 个仓（如 `api` / `web` / `docs`），每个仓各装机制、各有 pin。
- **主路径**：在 `api` 仓 `ensure pm rd-be qa` → 得 `pm@api`/`rd-be@api`/`qa@api`，落 label `api` 的 workspace；到 `web` 仓 `ensure pm rd-fe qa` → 得 `pm@web`/`rd-fe@web`/`qa@web`，落 label `web` 的 workspace；两套并存。
- **异常**：同仓重复 `ensure pm`（同名）→ 仍 fail loud 并给可执行提示（`close pm` 或换 `--fleet`）；仓目录名相同（两个 `api`）→ 提示显式 `--fleet` 或 `.agents/fleet-scope` 区分。
- **兼容场景**：升级前已存在的裸名会话（`pm`、`rd-be`）仍在场 → `status` 仍列出并标注「无 fleet」；在对应仓内 `close pm` 仍能命中（按「调用方仓推导的 fleet」匹配，无匹配时回退裸名）。
- **页面/输出状态**：不适用（CLI，无 UI）；错误信息需给「下一步命令」。

## 五、业务规则

- **fleet 值解析**（唯一来源，按优先级）：`--fleet <slug>` → `<目标仓>/.agents/fleet-scope` → `fleet_scope_slug(<目标仓>)`。三者都不合法 ⇒ fail loud（不静默回落空值）。
- **名字恒定带 scope**：所有 `ensure` 拉起的会话名形如 `<role>[-<task>]@<fleet>`；不再存在「无 scope」的新会话。
- **放置键与身份键同源**：workspace label = 名字里的 fleet 值（不再从会话名 parse 后再回退仓 slug）。
- **单例边界**：同 fleet 内同 core 唯一（现状不变）；不同 fleet 天然不同名 ⇒ 允许并存。
- **`--scope` 弃用**：等价 `--fleet`，打一条 deprecated warn（含替代写法），不报错；与 `--fleet` 同时给 ⇒ 拒绝（歧义）。
- **裸名解析**：`status`/`close` 收到裸 core 时，用「调用方所在仓推导的 fleet」匹配；无匹配再回退到「全 session 唯一同 core」；仍不唯一 ⇒ 拒绝并列出候选（不猜）。
- **并存期**：不追溯改名已存在的裸名会话；不因旧会话存在而放宽新规则。
- **`.agents/fleet-scope`**：本批保留，语义 = 「覆盖默认 fleet 名」；校验口径不变（空/多行/非法/symlink 逃仓 ⇒ fail loud）。

## 六、NFRs

- **兼容**：升级后旧会话不被顶掉、不被静默回收；`close` 裸名在旧会话上仍需可达（并存期规则见五）。
- **性能**：`ensure`/`status`/`close` 的 herdr 调用次数不变（每命令 ≤1 次 `pane list`；不新增反查）。
- **安全**：不新增网络调用；fleet 值仍受 `^[a-z0-9][a-z0-9_-]{0,15}$`（≤16）约束，防注入式 label。
- **容量**：名字总长 ≤48 必须对「最长 core（≤32）+ 最长 fleet（16）」成立，超限 ⇒ fail loud 并说明该缩哪一段。
- **不适用**：前端渲染 / 移动端 / 离线降级（CLI 侧无这些面；离线行为与现状一致）。

## 七、AC

- 验证接缝：`tests/t4` 新用例（命名/放置/并存/裸名解析）+ 现有 `cases/33`（放置键）与 `cases/28`（命名契约）扩展；QA 自建夹具。QA 已确认：待派发后确认。
- AC1（主路径）：Given 仓 A 与仓 B 均无任何 scope 文件，When 各自跑 `ensure pm rd-fe qa`，Then 两套会话并存，名字分别为 `*@<A slug>` 与 `*@<B slug>`，且各自落在 label 等于 slug 的 workspace。
- AC2（主路径 · 显式覆盖）：Given 仓 A 的目录名与仓 B 相同，When A 跑 `ensure --fleet alpha pm`、B 跑 `ensure --fleet beta pm`，Then 两者并存且不共用 workspace。
- AC3（优先级）：Given 同时存在 `--fleet x` 与 `.agents/fleet-scope` = `y`，When `ensure pm`，Then 用 `x`；只给文件时用 `y`；都没有时用仓 slug（三条各一断言）。
- AC4（异常）：Given fleet 值非法（空 / 含 `@` / 超 16 / 尾 `-` / `子代理 保留前缀），When `ensure`，Then fail loud 且**不建任何 pane**（BR6 零副作用）。
- AC5（异常 · 歧义）：Given `--fleet x` 与 `--scope y` 同时给，When `ensure`，Then 拒绝并说明二者等价、只给一个。
- AC6（兼容）：Given 升级前存在裸名会话 `pm`，When 跑 `status` 与在对应仓 `close pm`，Then `status` 列出并标注「无 fleet」，`close` 命中该会话并返回可复现证据（不误伤 `pm@<fleet>`）。
- AC7（负向闭环）：Given 同仓同 fleet 已有 `pm`，When 重复 `ensure pm`，Then 仍 fail loud（不因新参数放宽单例），提示含可执行命令。
- AC8（负向闭环 · 零回归）：Given 单仓单舰队（配置文件与现状相同）跑门禁，When `npm test`，Then 全量 rc=0；`cases/28` 命名契约与 `cases/33` 放置键断言按新口径更新后有对应的「改回旧实现必红」负控。
- AC9（弃用路径）：Given 使用 `--scope x`，When `ensure`，Then 行为等价 `--fleet x` 且 stdout/stderr 出现**恰一条** deprecated 提示；`--help` 里 `--fleet` 为主、`--scope` 标注弃用。
- AC10（文档一致）：Given 本次改动，When 读 `docs/INSTALL.md`「会话命名与多仓 scope」与 README 多仓段，Then 示例命令与新语义逐字一致（含 `--fleet` 示例与「名字恒带 scope」说明），且不存在「无 scope 时名字与旧版逐字相同」这类已失效表述。

## 八、上线闭环

- 版本：**MINOR（0.25.0）**——用户可见的 CLI 与命名语义变化，无破坏性移除（`--scope` 保留弃用别名）。
- 上线：合并后发布，release notes 必须写清「会话名现在恒定带 `@<fleet>`」与升级后旧会话的处置方式；下游三仓需一行迁移提示（ADR 里给）。
- 回滚：`git revert` 该 squash 提交即回退；已拉起的带 `@` 会话不会被旧版自动回收，release notes 给一条 `close <全名>` 的清理命令。
- 观测：发布后 7 天内看是否出现「裸名 close 误伤」类反馈（AC6 的真实场景）。

## 九、变更治理

- `feat` 全通道；**必过 arch 评审**（会话名契约换来源 + 放置键与身份键同源 + 迁移路径），产出 ADR `docs/adr/<日期>-fleet-identity-source.md`。
- 批次二（联动仓 manifest）在本批合并后另行立项，须带自己的 ADR：改布局 A（fleet=1 workspace、tab 按仓分组）、`.agents/fleet.yaml` 格式、仓短代号分配、`fleet-scope` deprecate 迁移。
- 文档随任务 PR；`AGENTS.md` 仅加一条指针（不复制机制条款）。

## 附录：战略筛子 / RICE 结论

- 战略筛子：① 解真实卡点（用户已撞）② 只换 scope 来源（落在 BR8 冻结契约允许范围内）③ 可在单批内回退 —— 通过。
- RICE：Reach 5（多仓用户）/ Impact 3（从「不能」到「能」）/ Confidence 0.8 / Effort 0.9 人日 → **Score ≈ 13.5 → P1**。
- MoSCoW：Must = `--fleet` + 默认 slug + 名字恒带 scope + 裸名兼容 + 文档一致；Should = `--scope` 弃用提示 + 歧义拒绝；Could = 名字超长时的「该缩哪段」提示；Won't（本批）= 联动仓 / fleet workspace / 移除 fleet-scope。
- Kano：N 仓并行 = 基本型（做不到就换工具）；一张 status 看全 = 期望型；「撞名时给可执行下一步」= 兴奋型。
