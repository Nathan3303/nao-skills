# ADR：herdr desktop app 作为第二后端（`NAO_TERMINAL=app`）

- 状态：已接受（待落地 v0.30.0）
- 更新：2026-11-24
- Owner：arch-designer
- 指针：Issue [#168](https://github.com/Nathan3303/nao-skills/issues/168) · PRD `docs/prds/2026-11-24-herdr-app-backend.md` · 评审报告 `docs/reports/168-arch-review.md` · 证据 `docs/research/2026-11-22-herdr-desktop-app.md` · 前置 ADR `2026-11-22-herdr-only.md`

## 背景

- 桌面版用户要在 Herdr **app** 里跑舰队；app 与 TUI 是两套程序（各自 core 与 CLI），官方明示**不共享 agent**，谁也不能看到对方。
- app 面能用的是 `hc`（core 0.1.22）：起/收/读状态都有命令，**放置靠给终端挂 `herdr.space`/`herdr.tab` 标签、由 app 收养**（2026-11-23 实测订正旧判）。
- 约束：默认后端不得变（AC1 逐字一致）；app 的 `doc`/`labels`/`where` 非版本化 API；TUI 放置是服务端语义，app 放置是「服务端只存标签、客户端收养」。
- 两条实测硬事实改写了设计：① app 窗口不在跑 ⇒ 标签**永不**被收养（默认 core 也只留 label，无 `where`、doc 无该终端）；② 从 TUI pane 起的 app 终端会**同时继承** `HERDR_*` 与 `HC_*`。

## 决策

- **双后端并存**：`NAO_TERMINAL=herdr`（默认，行为逐字不变）/ `app`；其余值 rc=2。后端身份只由这个显式值决定，**禁止按 env 存在性自动探测**。
- app 臂放置 = 写标签 → **读 `doc.get herdr-app` 验证终端地址落在目标 tab 树里** → 不成则 kill+rm 回滚 + fail loud。space id 发现三级：doc 按仓匹配 → 自标签扫描 → 确定性铸造 `sp<sha256(realpath(repo))[:32]>`；doc 不可读 ⇒ exit 3，不盲铸。
- 就绪/忙闲用 `status.app` + `status.state` 映射；`status` 缺失 = unknown = 不可投递；**`turn` 不是 `state_change_seq` 的等价物**。
- 生命周期 = `hc run --bg --no-parent --keep`；close = kill（幂等）→ rm（顺序不可反，rm 在跑 ⇒ rc=1）；kill 连带子终端。
- 契约以 `hc schema`（OpenRPC · generation 1）+ `doc.version` 做能力探测，缺字段一律 fail loud，不退化成「当作空闲」。

## 理由

1. 业务匹配：两类用户各在自己的窗口工作，互不可见是官方事实；并存是唯一不误导用户的形态。
2. 成熟度：`hc` 的 run/get/ls/kill/rm/label/status 已真机跑通；不稳的是 app 的布局文档与收养时机 ⇒ 把 app 面收敛到「标签 + 一条结构验证」，其余语义复用 TUI 已验证结论。
3. 团队能力：TUI 面零改动；app 面新增一个区间 + 唯一入口，两套语义差异集中一处可审。
4. 成本：不迁 TUI、不写 layout/mod；代价 = app 臂多一条「窗口在跑」前提 + 一次 doc 读 + 长期两套语义对表。

## 对照过的备选模式

1. **维持现状（只 TUI，基线）** —— 适用：桌面版无真实用户；代价：诉求不满足。不采纳：用户已拍板要 app 可用。
2. **只做只读观测（在 app 里看 TUI 舰队）** —— 适用：两程序共享 agent；代价：无。不采纳：官方明示不共享，`hc ls` 只列 app 终端 ⇒ 没有可观测对象。
3. **全面迁移到 app（删 TUI 面）** —— 适用：app 放置面稳定且有版本化契约；代价：把唯一后端押在 `doc version:10` + 标签契约上，且失去「无 app 窗口也能放置」的能力。不采纳：用未稳定面替换已验证面。
4. **按 env 自动探测后端** —— 适用：两套 env 互斥；代价：无。不采纳：实测 app 终端可同时带 `HERDR_*` ⇒ 会误判到 TUI core。
5. **双后端并存（采纳）** —— 适用：两种窗口各有真实用户；代价：两套语义长期对表 + app 臂多一条窗口前提。采纳。

## 后果与风险

- 正面：TUI 零行为变化；app 用户可用；放置失败不再「写成功即认为成功」。
- 负面：`NAO_TERMINAL=app` 必须先开 app 窗口（否则前置 exit 3）；app 契约随版本漂移 ⇒ 只能靠探测 fail loud，不能静默降级。
- 风险：keep 恢复会保留 labels 但把程序换成 shell（幽灵 pane）⇒ 身份判据必须含 `foreground`/`status.app`，labels 永不单独作证据。
- **测试（R1 定论）**：③ 部分隔离 —— 核心面可自动化（私有 `XDG_RUNTIME_DIR`+`XDG_STATE_HOME`+`HC_SESSION`，实测用户 core 完全不可见）；**收养/放置与 UI 可见效果不可自动化**（必写用户布局；`HERDR_APP_HOME` 只换窗口不换 core）⇒ 桩 + 人工验收。

## 限制与已知边界

- 非范围：跨机 `hc --on`、mod/layout 生成、TUI↔app 迁移或双跑同步。
- 空 space 随最后一个 tab 关闭（留 `recent`）⇒ 回滚可能留一条 recent 记录，不追溯清理。
- `where` 是 app 写的展示 label（可陈旧；空间名随首终端 cwd 变）⇒ 只作辅助证据，禁作判据。
- 逐条闸门、用例形态与探针原始证据在 `docs/reports/168-arch-review.md`，不进本文。

## 相关指针

- 实施契约 / 门禁 / R1 用例形态：`docs/reports/168-arch-review.md`；app 布局与收养说明：本机 `~/.config/herdr-app/AGENTS.md`。

## 参考来源

- [Program Status Protocol (OSC 7501)](https://www.superlogical.com/rex/docs/build/program-status) · 访问 2026-11-24 · `state` 值域与生命周期（`working` 随进程退出丢弃、`done` 本应存活）是 app `status` 的语义来源。
- [herdr releases](https://github.com/herdrdev/herdr/releases) · 访问 2026-11-24 · 本机锚点 `hc 0.1.22` / `herdr-app 0.1.16`；app 布局文档无公开文档，契约面只能读 `hc schema`。
