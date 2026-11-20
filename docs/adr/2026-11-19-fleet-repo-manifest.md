# ADR：联动仓 manifest（`fleet.yaml` · 1 fleet = 1 workspace · 放置键与身份键不同源）

- 状态：已接受（待落地）
- 更新：2026-11-19
- Owner：arch-designer
- 指针：Issue [#139](https://github.com/Nathan3303/nao-skills/issues/139) · PRD `docs/prds/2026-11-19-fleet-manifest.md` · 判据 `docs/reports/139-lite-spec.md` · 前序 `docs/adr/2026-11-17-fleet-identity-source.md` · `docs/adr/2026-11-13-herdr-workspace-scope-key.md`

## 背景

- 批一（#138）已落地：放置键 = 身份 scope = fleet 值，1 fleet = 1 workspace；`ensure` 的会话只落在目标仓一个仓里。
- 批二形态（用户 2026-11-17 拍板三条，不再讨论）：fleet = **1 个 workspace**（联动仓角色同住，tab 按仓分组）· 新文件 `.agents/fleet.yaml`（slug + 联动仓列表 + 短代号）· scope = **仓短代号**。MVP = A（`fleet-scope` 保留不动），门禁 = 加速档（PRD §七）。
- 硬障碍三条：① 无「辖域声明」载体 ② 放置键与身份键同源 ⇒ 多仓必然散场 ③ 名字 `@` 段（fleet）要让位给仓代号 ⇒ 必须显式改写前序 ADR。
- 现状事实（已核代码，禁 cat 全文口径）：positional `ensure <role>@<x>` 的 `@` 段**已被占用**为「目标仓路径」（`nao-fleet.sh:4439`）；名字 scope 与放置入参是同一个 `$fleet`（`:4564` 与 `:4597`/`:4599`）；布局 A 收敛按 `tab label == 名字` 等值判（`:1073-1109`）。

## 决策

1. **谓词改写（AC9①）**：放置键 = **manifest `slug`**（舰队值），名字 `@` 段 = **`code`**（联动仓）/ `slug`（主仓）。新判据句 = **放置键恒为「舰队值」，身份 scope 恒为「仓代号或舰队值」，二者只在主仓会话上取值相同**。`placement_key` 仍是唯一放置来源，**禁**由名字反解（前序禁令不变）。
2. **`@` 双语义的唯一判据（AC9②）**：manifest 校验期强制 `code ∩ {slug} = ∅`、联动仓不得用保留代号 `main` ⇒ 任意 `@` 值的三分法是**全域函数**而非猜：∈ codes ⇒ 联动仓（scope = code，落 code.path）；== slug ⇒ 主仓（scope = slug，落 manifest 根）；其余 ⇒ fail loud 列候选。positional `@` 段另有旧义（仓路径），解析顺序 = ① code 命中 ② 仓路径存在（legacy）③ 两者都命中但物理路径不同 ⇒ fail loud ④ 都未命中 ⇒ fail loud 列 codes。**名字段与 positional 段是两个命名空间**，各用同一三分法判定；文案必须逐处指明是哪一段。
3. **放置**：1 fleet = 1 workspace。`workspace create --cwd <目标仓> --label <slug>` + `tab create --workspace <wsid>`（表结构不变），**不因目标仓不同而新开 workspace**。
4. **tab 分组（唯一判据）**：herdr tab label 改为 **`<code>/<name>`**（主仓组前缀 = 保留代号 `main`）。判据句 = **tab 属某仓组 ⇔ 该 tab label 首段（第一个 `/` 之前）恰等于该仓 code**。「按仓分组」= 标签命名空间，**不**以物理相邻为判据：herdr 0.9.x 无 tab 重排命令，`tab list` 的 `number` 单调递增且不可回写（见参考来源），相邻性只能靠关闭重建 tab 换取，会打断运行中会话。`code`/`scope`/`core` 字符集均不含 `/` ⇒ 首段切分全域唯一。无 manifest ⇒ tab label 逐字 = name。
5. **优先级（AC6）**：放置值 `--fleet` > `.agents/fleet-scope` > `manifest.slug` > 仓 slug。`fleet-scope` 与 `manifest.slug` **同时声明且分歧 ⇒ fail loud**（同权来源禁静默取一）；`--fleet` 与 `manifest.slug` 不一致 ⇒ fail loud（同一 manifest 只有一支舰队名）。`fleet_of_invocation` **本身不改**，manifest 判定在其**之外**叠加 ⇒ AC2 零回归由结构保证。
6. **命名预算不变**：scope = code（≤16，复用 `fleet_scope_problem`），**不拼接** `slug-code`；core ≤32 / full ≤48 原样。撞线 fail loud 并点名够不着的那一段；**禁**自动截短 code（截短 = 猜）；默认 tier 的 slug 截短只对 `slug` 来源保留。
7. **回收（AC7 · 沿用 T551/T552 不猜）**：`close <core>@<code>` 的期望仓 = manifest 的 code → path（`main` ⇒ manifest 根）；无 manifest 逐字沿用 T551 锚 + T552 双键三态。期望仓只是**回落值**，不参与并列判定：候选 >1 一律 die 列候选、零回收。

- **拍板记录（2026-11-20 · PM · D1–D6 全部照本篇建议）**：D1 未命中 code ⇒ fail loud 列候选（不回落三档，PRD M2 已收敛）· D2 `--fleet` ≠ `manifest.slug` ⇒ fail loud · D3 tab 分组 = `<组前缀>/<name>` 首段判据 · D4 主仓组前缀固定 `main` · D5 用例 39 不入快档 · D6 AC9③ 事实源 = manifest + `AGENTS.md` 一行指针。**本篇技术签字生效**，实施口径见 `docs/reports/139-lite-spec.md`。

## 理由

1. 业务：辖域从「一个仓」变「一组声明过的仓」，而摆放 / 身份 / 单例三件事仍各有一个来源；PM 唯一调度者的边界不动。
2. 成熟度：名字单点构造/解析、放置单点入参、close 三态均已在位；本批只加一层 `manifest → (code, repo, slug)` 的**纯函数**，不新增 herdr 调用面（布局 A 的 tab 语义不改）。
3. 团队：批一 ADR 已把「label 与名字同源但保持两个变量」写成批次二解耦点 ⇒ 本批 = 把 `t_fleets[]` 拆成 `t_scopes[]` / `t_labels[]` / `t_groups[]`，t4 可逐项负控。
4. 成本：零新依赖（YAML 只收受限子集）、零迁移（MVP A）、回退安全（删 manifest 即回 v0.25.2 行为）。

## 对照过的备选模式

1. **维持现状**（fleet 单值，多仓 = 多 workspace）—— 适用：单仓单舰队；代价：即本缺陷（角色不能跨仓同住）；**不采纳**。
2. **名字拼 fleet + code**（`<core>@<fleet>-<code>`）—— 适用：跨 fleet 也要全局唯一；代价：scope 16 与 full 48 立刻撞线、身份两段耦合不可解析；**不采纳**。
3. **物理相邻分组**（把同 code 的 tab 排在一起）—— 适用：后端有重排 API；代价：`herdr tab` 仅 list/create/get/focus/rename/close（0.9.5 实测），只能关 tab 重建 ⇒ 打断会话；**不采纳**。
4. **一 tab 一仓、仓内多 pane** —— 适用：把 tab 当仓视图；代价：推翻布局 A「每 tab 恰 1 pane / tab label = 名字」，J2 收敛、status 归属、用例 12/25 全量重写；**不采纳**。
5. **采纳：manifest 声明 + 放置键/身份键不同源 + tab 前缀命名空间**（见决策 1–7）。

## 后果与风险

- 正面：AC1（同 workspace 跨仓派生）、AC6（唯一优先级）、AC2（无 manifest 逐字不变，结构上保证）成立；回退 = 删 manifest 一行。
- 负面：tab label 形态变（仅 manifest 仓）⇒ 复用/收敛判据**四处须同源**（`:1073-1109` 收敛、`:1002` `tab_id_for`、`:1228` 建 tab、`:1238` `tab create`）；`@` 语义从一处变三处（positional 旧义 / code / slug）⇒ 报错文案必须逐处指路。
- 风险清单与否定条件：`docs/reports/139-lite-spec.md` §六（R1 `@` 双语义静默二选一为最高风险）。

## 限制与已知边界

- manifest 源 = **调用方仓**（`$PWD` 物理 toplevel 下的 `.agents/fleet.yaml`），不做向上查找、不自动发现联动仓；从联动仓内 `ensure` 时无 manifest 语义（= 批一行为）。
- 跨 fleet 同 code（两个 manifest 都有 `api`）不在本批治理：pane label 全 session 唯一，撞名由既有「同名 label 多命中 ⇒ fail loud」兜底（不静默）。
- `status` 的 `fleet=` 事实只在 manifest 可读时可判定；不可读印 `?`（显式不可知，禁空值）。
- AC9③ 辖域边界：事实源 = 各仓 `.agents/fleet.yaml`；`AGENTS.md` 一行指针 + PM 卡指针由 PM 落（`.agents/**` 属架构师禁改区，本批不动）。
- 不做：跨 herdr session、`fleet-scope` 迁移/deprecate、联动仓依赖编排、自动发现。

## 相关指针

- 实施判据（数据通道 / 各态断言 / 禁改区 / 风险否定条件 / 待拍板）：`docs/reports/139-lite-spec.md`
- 前序改写面：`docs/adr/2026-11-17-fleet-identity-source.md` 的「放置键与身份键同源」由本篇决策 1 取代，其余结论不变；`docs/adr/2026-11-13-herdr-workspace-scope-key.md` 的「1 workspace/仓」由本篇决策 3 改写为「1 workspace/舰队」。

## 参考来源

- [herdr CLI reference](https://herdr.dev/tui/docs/cli-reference/) · 访问 2026-11-19 · `tab` 仅 list/create/get/focus/rename/close，**无**重排/索引参数；`workspace create --label` = 放置语义。
- 本机实测（herdr 0.9.5 · 2026-11-19）· `tab list` 返回 `label / number / pane_count / tab_id / workspace_id`；`tab rename` 接受含 `/` 的 60 字符串（本会话实改实还原）。
- [YAML 1.2.2 spec](https://yaml.org/spec/1.2.2/) · 访问 2026-11-19 · 完整 YAML 含锚点/别名/多文档/流式结构 ⇒ 本仓零新依赖只收受限子集，其余形态属「非法」而非「尽力解释」。
- [JSON Schema · object / additionalProperties](https://json-schema.org/understanding-json-schema/reference/object) · 访问 2026-11-19 · 「未知字段 = 错误」惯例 ⇒ 支持 PRD AC3 的 unknown-field fail loud。
