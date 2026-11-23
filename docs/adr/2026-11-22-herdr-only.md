# ADR：herdr 唯一后端（删除 tmux 回退面）

- 状态：已落地（2026-11-23 随 `2d5dcfc` 入 main · v0.28.0 MINOR）
- 更新：2026-11-23
- Owner：arch-designer
- 指针：Issue [#156](https://github.com/Nathan3303/nao-skills/issues/156) · PRD `docs/prds/2026-11-22-herdr-only.md` · 判据 `docs/reports/555-lite-spec.md` · 被本篇取代：`docs/adr/2026-10-27-strict-tmux-pi.md`（当年「只支持 tmux」）

## 背景

- 用户 2026-11-21 拍板：「不再支持 tmux，后面就是纯 herdr 的舰队」；本机与下游三仓实践已全 herdr（默认后端自 v0.23）。
- tmux 面仍占脚本 ≈615 行（7 个 `term-impl-tmux` 区间）+ 门面 10 处分派臂 + 语义双写（`cleanup -S` vs `--session`、pane 定位两套）。
- 每次改动都要双后端跑门禁（`run-dual.sh` 两组全量），成本 ≈×2，而 tmux 侧已无真实用户回归信号。
- 约束：本批只删不加；herdr 实现与三条护栏（自面板 / 归属不可判定即拒 / 忙闲）零 diff。

## 决策

后端身份是**常量而非分支**：唯一后端判据句 = `NAO_TERMINAL` 的唯一赋值点恒为 `herdr`，`term_backend()` 收窄为守卫 —— 空或 `herdr` 无输出放行，其余值（含 `tmux`）单行 stderr + `exit 2`（命令未执行）。旧调用面一律 fail loud 不降级：`NAO_TERMINAL=tmux`（及任何非 herdr 值）与 `cleanup -S <socket>` ⇒ rc=2 + 指路 `--session <名>`；`term-impl-tmux` 七区间、门面 tmux 臂、`require_tmux` / `_term_tmux_snapshot`、测试侧 `be_*` tmux 侧与双跑编排整组删除。

## 理由

1. 业务匹配：使用者只有 herdr 一种真实场景，回退通道无用户、无遥测、无回归信号。
2. 成熟度：herdr 侧 status/ensure/close/cleanup/deliver 全链路已在 T545/T548/T554 落地并有替身+真机双覆盖，删 tmux 不留未验证面。
3. 团队能力：单后端后「怎么起/怎么收/怎么定位」各只有一种答案，双写语义（`-S` / `--session`、标题 / label）不再需要维护者对表。
4. 成本：门禁由「双后端各一组」收敛为单组（发布前置仍是一次全量）；一次破坏换后续批次不再双跑、不再双写。

## 对照过的备选模式

1. **维持双后端（现状基线）** —— 适用：确有 tmux 用户或多宿主诉求；代价：每次改动 ×2 门禁 + 双写语义永久维护；不采纳：用户已拍板、且本仓无 tmux 侧回归信号，成本换不到收益。
2. **保留 tmux 代码但冻结（不再跑门禁）** —— 适用：想留一条应急通道；代价：无人验证的死代码会被后续批次改坏，却仍对外宣称可用（比删更危险）；不采纳：不诚实的可选面。
3. **`NAO_TERMINAL=tmux` 静默降级为 no-op、继续按 herdr 跑** —— 适用：怕打断存量脚本；代价：用户以为在 tmux 里、实际落 herdr，故障现象与提示脱节；不采纳：违反 fail loud 口径。
4. **纯 herdr（采纳）** —— 适用：单宿主 + 单一实践；代价：一次性破坏（存量 `NAO_TERMINAL=tmux` 与 `cleanup -S` 直接报错）；采纳：出口是发布说明一行迁移指路，可 pin 回旧版。

## 后果与风险

- 正面：后端事实单点可判（一个常量 + 一个守卫），`cleanup` / 定位 / 门禁都只剩一条路径；门面与区间逻辑不再分叉。
- 负面（有意破坏性）：`NAO_TERMINAL=tmux`、`cleanup -S` 从「可用」变 rc=2；`run-dual.sh` 与「双后端」概念消失，发布前置只剩单组全量。
- **目标风险（必须 PM 裁定）**：可删上限自测 ≈799 行（615 区间 + 79 区间外代码 + 105 注释；名册字段 `tmuxPane` 等须保留），减去必须新增的守卫与 fail loud 文案 ≈20 行 ⇒ 净 **−13.5%~−14.2%**，PRD AC2 的「≥15%」（删 ≥823 行）在「只删不加」下**不可达**（逐项算式见判据 §1）。
- 测试风险：退役用例（12 / 25）会减少断言总数，必须逐条写明「后端不存在 ⇒ 该断言不成立」，不得让断言强度静默下降。

## 限制与已知边界

- 不追溯改写历史 ADR 正文：`2026-11-13` / `2026-11-17` / `2026-11-20` 只加「tmux 回退面已删除」注记；`2026-10-27` 状态改「已废弃」，其 `pi ≥1.4.0` 前提与 exit 3 / 零副作用语义仍现行。
- 三条护栏的「逐字保留」指 **herdr 侧副本**（`_term_herdr_self_refuse` / `_term_herdr_busy` / 归属谓词）；tmux 侧副本随区间删除，不视为护栏丢失。
- 布局几何与命名契约不动；`NAO_TMUX_*` 死配置去留属 PM 裁定（判据 D3）。
- 逐用例处置、静态 lint 判据与减重算式不进本文（`docs/reports/555-lite-spec.md`）。

## 参考来源

- [herdr CLI reference](https://herdr.dev/tui/docs/cli-reference/) · 访问 2026-11-22（沿用 2026-11-13 检索）· `--session` 为唯一会话注入点，无 `--session` 会静默落用户 `default`。
- [herdr v0.9.1（release）](https://github.com/herdrdev/herdr/releases/tag/v0.9.1) · 访问 2026-11-22（沿用）· 本机版本锚点，protocol 22。
- [tmux(1)](https://man.openbsd.org/tmux.1) · 访问 2026-11-22（沿用 2026-10-27）· 被删除面（`split-window` / `list-panes` / `-S` socket 语义）的原始契约。
