# ADR：引入 codegraph 插件为「可选增强」（warn-only 检测 + rc 语义收敛）

- 状态：已接受（待落地 v0.20.0）
- 更新：2026-10-28
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-28-codegraph-plugin.md` · 评审报告 `docs/reports/2026-10-28-T532-arch-review.md` · 接缝报告 `docs/reports/2026-10-28-T532-qa-recon.md`

## 背景

- 舰队代码定位口径全为 codegraph CLI；第三方插件 `@sean_pedersen/pi-codegraph` v0.1.0 提供原生 MCP 工具，但**默认只暴露 `codegraph_explore`**，且其 system prompt 注入在舰队内被 `--append-system-prompt` 整体抑制。
- 插件激活条件 = cwd 有 `.codegraph/`，sidecar 在**扩展工厂期** spawn ⇒ 机制侧无 per-session 开关，唯一杠杆是「该仓建不建索引」。
- 约束：零新依赖、机制零网络、不改上游、不改 `roles.yaml`、下游三仓当前无索引。

## 决策

1. codegraph 以**可选增强**引入：`check` 四态**全 warn**（索引 pending 由 rc=1 降为 warn），插件缺失/失效永不进 rc 通道，含 `--strict`。
2. 口径单源在技能：三段阶梯「`codegraph_explore` → CLI → `grep -rn` + 行段」；卡片只写场景句 + 指针，唯一硬编码工具名 = `codegraph_explore`。
3. 舰队 `spawn` 注入 `CODEGRAPH_TELEMETRY=0`；索引按仓 opt-in（本批仅本仓），sidecar 资源受实测门约束（>1.2GB 或锁冲突 ⇒ 删索引降级）。

## 理由

1. 业务匹配：6 角色每天定位代码，一次原生调用替代多轮 grep + cat；但下游三仓无索引 ⇒ 做门禁会立刻拉红派发链。
2. 成熟度：插件 v0.1.0 + CLI 遥测 + 工具集合默认 1 个 ⇒ 只宜作增强，不宜作依赖；上游 README 与本机 CLI 冲突（`init -i`）已证文案必须实测。
3. 团队能力：检测只读两份 `settings.json`（~5ms），无新工具链；四态文本是唯一可断言契约。
4. 成本：rc 收敛后门禁语义更纯（红 = 资产缺陷）；代价是丢失「索引过期」的 rc 信号，用 `!` + 摘要 `warn=N` 补偿。

## 对照过的备选模式

1. **维持现状（仅 grep + 行段）** —— 适用：无索引、工具集不稳定、机器内存紧张；代价：多轮 grep + 行段，token 与轮次更高；不采纳：本机已有可用插件入口，收益实测存在，且本决策保留完整回退路径。
2. **插件为硬依赖（缺失 ⇒ fail）** —— 适用：全员全仓都有索引与 CLI；代价：下游三仓即刻全红、插件静默失败被误当资产缺陷；不采纳：与用户拍板 warn-only 冲突，且激活面在 cwd 不受机制控制。
3. **自建/移植原生工具（fork 或 fallback extension）** —— 适用：上游长期停滞且需 per-session 开关；代价：改上游 + 长期维护 MCP 桥 + 版本跟随；不采纳：越出「不新增依赖、不改上游」红线，本批收益不抵维护面。
4. **只检测 + 文档指引（采纳）** ⭐ —— 适用：外部工具成熟度不足、需要渐进；代价：提示与实际生效可能不一致（插件静默）；以「已声明（未验证生效）」措辞 + 四态检测兜住。

## 后果与风险

- 正面：口径单源、门禁语义收敛、下游零成本；负面：`Pending` 不再拉红 ⇒ 索引过期只能靠人读 `-v`。
- 风险：6 并发 sidecar 对单一 SQLite 索引未验证（回退 = 删 `.codegraph/`）；上游工具集合与 env 名漂移（只认 `codegraph_explore` + 文档手工兜底）。

## 限制与已知边界

- 插件自带 system prompt 指引在舰队内不生效（`--append-system-prompt` 抑制 + fallback 在 pi 1.4.0 是死代码），**截至 pi 1.4.0 / pi-codegraph 0.1.0**；口径由 nao 技能承载。
- `pi --help -e` 类非会话调用会永久残留 `.pi/APPEND_SYSTEM.md`：只做 ignore + 文档，**不代跑清理**（nao 不得写用户/插件产物）。
- 不覆盖：自动安装/建索引、下游 pin 升级、`--tools` 级抑制、插件内部失败可观测性。

## 相关指针

- 骨架/规范：`.agents/checklists/deliverable-docs.md` §四 · 模式对照：`.agents/skills/arch-patterns.md`
- 实施口径与待实测项：`docs/reports/2026-10-28-T532-arch-review.md` §二/§三

## 参考来源

- [@sean_pedersen/pi-codegraph（npm registry metadata 0.1.0）](https://registry.npmjs.org/@sean_pedersen/pi-codegraph/latest) · 访问 2026-10-28 · 声明仓库/peer 依赖；包仅 3 文件、解包 9.5KB（单一扩展面，审计成本低）。
- [SeanPedersen/pi-codegraph README](https://github.com/SeanPedersen/pi-codegraph) · 访问 2026-10-28 · 上游称注册 9 工具、`codegraph init -i`、无索引则 no-op（与本机实测的工具集/命令差异见评审 §三 T1/T2）。
- [codegraph 官方站](https://colbymchenry.github.io/codegraph/) · 访问 2026-10-28 · tree-sitter 知识图谱 + MCP server，定位为「local-first」代码情报工具。
