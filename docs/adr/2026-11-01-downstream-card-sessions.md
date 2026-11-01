# ADR：下游仓自定义角色会话（`ensure --card`）

- 状态：已接受（待落地）
- 更新：2026-11-01
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-11-01-downstream-role-sessions.md` · 评审报告 `docs/reports/2026-11-01-T537-arch.md`（闸门与断言口径在此）

## 背景

- fleet 的角色来源只有机制包根的 `roles.yaml`；`resolve_role` 未命中即 die、`spawn_one` 卡路径写死 ⇒ 下游 `.agents/prompts/*.md` 无任何机制消费。
- 批次中段需要按需角色（Review 等）介入，手工起的会话游离在 pane 托管 / `status` / `close` 回收纪律之外。
- 已有结论：不新增常驻第 7 角色；不登记上游清单。

## 决策

- `ensure` 增 `--card <卡路径>`（**目标级修饰符**，绑定其后第一个 positional），卡限定 `<repo>/.agents/prompts/<file>.md`；由卡 frontmatter `role`（退化文件名）推派生/一次性会话，`close` 回收但不弹常驻警告。
- 三条机制不变量：卡 role 与 `ROLE_ORDER`/别名**前缀不相交**（含 `subagent-` 保留前缀）；卡集内部**前缀反链**；`status` 前缀集 = 静态集 ∪ 本仓锚下卡集，静态路径逐字不动。

## 理由

1. 业务匹配：满足「nao 提供机制、下游自持角色」，上游清单改动为 0。
2. 技术成熟度：复用 `build_system_prompt`（锚点同源）、派生回收、T530 三态归属，全部已验证语义。
3. 团队能力/成本：单文件 + `check` 一节 + 用例；不新增配置与生成物。
4. 风险最省：把关卡前移到「命名不相交」，`status`/`close` 才可能在既有循环后追加而不改既有行。

## 对照过的备选模式

1. **维持现状（手工起会话 + 人工 `kill-pane`）** —— 适用：无需回执身份的一次性调研；代价：脱离托管与回收纪律。不采纳。
2. **登记进 `roles.yaml`（常驻化）** —— 适用：真正常驻角色；代价：上游清单负担 + 6 角色断言连锁改。不采纳。
3. **overlay 清单（`NAO_SKILLS` 指下游清单）** —— 适用：下游要整套自定义 6 角色；代价：绑常驻语义、下游维护整份清单。不与本参数并用（同一仓二选一）。
4. **pi-subagents 项目 agent** —— 适用：并行调研、省 token；代价：无 pane 托管 / 无 `status` / nao 不回收。互补而非替代。
5. **新增第 7 常驻角色** —— 适用：长期编制需求；代价：与「按需」语义相反、测试与文档连锁。不采纳。

## 后果与风险

- 正面：按需角色进入同一套托管与可见性；`roles=6` 与既有输出不变。
- 负面：`status` 多一节、`check` 多一节；卡即系统提示 ⇒ 内容完全可信（不属权限边界）。
- 风险：卡被删后会话可能成孤儿 ⇒ 须按报告 Q2-F3 单列「角色未识别」，不得静默；overlay 生效时 `check` 须按 realpath 相等跳过该节，否则恒红。

## 限制与已知边界

- 不做 uid/属主/权限判定（同 uid 场景无增量价值；多用户共享仓为非目标）。
- 不做内容安全校验；不读他仓 `.agents/prompts`（他仓卡会话只按三态标注、不给回收命令）。
- `close` 对卡会话跳过 `tasks-state` active 闸门，在跑 turn 闸门不放宽。
- 不自动注册为 pi-subagents agent（随卡自加 `name:` 的双用允许，但卡正文不得依赖 `## 环境锚点`）。

## 相关指针

- `docs/reports/2026-11-01-T537-arch.md`（D5–D8 待拍板 · 双向断言 · 风险 R1–R8）
- `docs/adr/2026-10-31-fleet-status-repo-attribution.md`（三态归属）· `docs/adr/2026-10-14-subagent-session-identity-exclusion.md`（`subagent-` 排除面）

## 参考来源

- 未检索到（本决策为仓内机制演进，无外部方案依赖；相关问题取证见 PRD §一 的仓内行号证据）。
