# ADR：子代理会话（subagent-*）排除面与会话身份模型边界

- 状态：已接受（待落地 v0.18.3）
- 更新：2026-10-14
- Owner：arch-designer
- 指针：`docs/prds/2026-10-14-subagent-isolation.md` · `docs/reports/2026-10-14-T525-arch-review.md`

## 背景

- pi-subagents 子会话以 `subagent-<agent>-<runid>`（无名时 `subagent-chat-<id18>`）进入 pi-intercom 名册，且原生子会话无独立 pane、继承父进程 `$TMUX_PANE`（`docs/reports/2026-10-12-pi-subagents-compat-review.md` §2.2/§2.3）。
- 现状安全靠命名巧合：派生区按 `"$name" == "$role"-*` 过滤、`close` 靠泛化「未知角色」`die`，脚本内 `grep -c subagent` = 0 ⇒ 改一个角色名即失守。
- QA 实证核心危害面 ≈ 0，但发现真边界缺口 **E2**：`unattributed_pi_panes` 的 claimed 被子代理继承的 `tmuxPane` 认领 ⇒ 孤儿 `comm=pi` pane 告警被掩盖。

## 决策

把「子代理会话不属舰队会话身份模型」固化为显式契约：`status` 只计数（N=0 不打印、不列名）· `close` 目标解析最前显式拒绝且绝不触任何 pane · `unattributed_pi_panes` 的 claimed 改条目感知并排除 `^subagent-` · `check` 增设 `subagent-` 保留前缀守卫（canonical id + alias）。`fallback_pane_for` 的 claimed 语义不变。

## 理由

1. 业务匹配：命中「机制可信度 / 会话语义安全」，把偶然安全变为可断言契约（BR1 显式优先）。
2. 成熟度：沿用既有前缀过滤与逐条目名册解析（与 `intercom_pane_for` 同源取法），零新依赖、零网络。
3. 团队能力：改动限脚本内 4 个消费点 + 1 用例，既有 `check` / `npm test` 门禁即可覆盖。
4. 成本效益：低成本（PATCH v0.18.3）换掉未来「误杀父 pane + 枚举污染」隐患。

## 对照过的备选模式

1. **维持现状（仅 fleet + intercom，靠命名巧合）** —— 适用：永不新增角色/别名；代价：隐性安全，一次改名即失守；**不采纳**（BR1 显式优先）。
2. **在 `visible_session_names` 层统一过滤 `subagent-`** —— 适用：只有 `status` 一个消费方；代价：该函数同时喂 `derived_in_field` / `fallback_pane_for` claimed / `status`，过滤会污染「可见即枚举」与兜底认领语义（E2 反向）；**不采纳**。
3. **仅在 `close` 加护栏，`status`/E2 不动** —— 适用：只关心误杀父 pane；代价：枚举污染与孤儿 pane 掩盖仍在，安全继续隐式；**不采纳**。
4. **nao 接管子代理生命周期（当派生会话回收）** —— 适用：子代理有独立 pane；代价：实际无独立 pane、父子句柄串扰，生命周期归 pi-subagents；**不采纳**。
5. **各消费点就地显式识别 + 保留前缀守卫** —— 适用：多消费方、需最小副作用面；代价：四处改动需用例钉住；**采纳**。

## 限制与已知边界

- `fallback_pane_for` 的 claimed **保持含子代理条目**：该处语义是「pane 已被占用」，排除会令兜底误认领父 pane（新增误判），故与 `unattributed_pi_panes` 不同构。
- E2 收口后，仅被子代理条目认领的 pane 会重新告警（非静默优先）；该 pane 实为其父会话且父条目缺失/无 `tmuxPane` 时属预期。
- 本 ADR 不含协议侧「子代理结果不替代 done / intercom 桥」语义（台账 ⑦ 另批）。

## 相关指针

- 实施闸门 / 用例集 / 接线清单：`docs/reports/2026-10-14-T525-arch-review.md`
- 索引：`docs/adr/README.md`

## 参考来源

- `docs/reports/2026-10-12-pi-subagents-compat-review.md`（T512 调研）· 2026-10-14 引用 · §2.2 名册污染 / §2.3 父子 pane 串扰 / §4.3 建议立项。
- `docs/prds/2026-10-14-subagent-isolation.md` · 2026-10-14 引用 · BR1–BR9 / AC2–AC8。
- [pi-subagents（npm）](https://www.npmjs.com/package/pi-subagents) · 访问 2026-10-12 · 子代理 run / retention 生命周期归本包。
- [pi-intercom（npm）](https://www.npmjs.com/package/pi-intercom) · 访问 2026-10-12 · 注册时读 `$TMUX_PANE`，子会话继承父句柄。
