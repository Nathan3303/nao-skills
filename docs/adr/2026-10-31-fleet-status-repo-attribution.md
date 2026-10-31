# ADR：status 残留判定加仓维度（按 pane 实际工作目录归属）

- 状态：已接受（已落地 v0.20.2）
- 更新：2026-10-31
- Owner：arch-designer
- 指针：PRD `docs/prds/2026-10-30-fleet-guards.md`（§五 BR1–BR3 · §七 AC1/AC2/AC6/AC7）· 评审报告 `docs/reports/2026-10-31-T534-arch-review.md` · Issue #56

## 背景

- 本仓 `status` 按 tmux 标题**全机**匹配派生会话，再用**本仓** `tasks-state` 判归属；他仓会话（实测 `qa-T596` / `qa-T580`，cwd = `nao-todo`）被报成「本仓残留」，并附可直接执行的 `close --task`（`close` 支持跨仓定位）⇒ 误杀他仓在飞会话。
- 约束：`close` 跨仓定位是刻意能力（BR3 保留）；会话名 `<别名>-<编号>` 不含仓信息且不改名（PRD 非范围）；`task_state_class()` 语义是契约不变量，本批不动。

## 决策

派生会话归属改按 **pane 的实际工作目录** 判定，本仓锚 = `pwd -P`（`git rev-parse --show-toplevel` 是 cwd 严格祖先时并入锚集；**不用** `roles.yaml` workspace）；pane cwd 取**一次** `tmux list-panes -a` 快照的 `pane_current_path`（权威），名册 `intercom_roster` 的 cwd 兜底（优先级 pane > 名册，冲突取 pane）；两侧物理归一后做**组件级**前缀比较。只有本仓实例计入残留节并给 `close --task` 提示；他仓实例单列标注「勿在本仓回收」且整行不含可执行命令；归属不可判定 ⇒ **fail-closed**（只标注、不给命令）。

## 理由

1. 业务匹配：归属 = 事实（pane 在哪），名字 = 巧合；由此「提示即可执行」恒成立（BR2 北极星：误杀概率 0）。
2. 技术成熟度：`pane_current_path`（前台进程 cwd）与 `rev-parse --show-toplevel` 均为稳定原语，零新依赖、零网络。
3. 团队能力：判据收敛为单行谓词 `repo_contains_path <root> <cwd>`，可单行变异自证（AC2/AC7），维护面小。
4. 成本效益：一次全表快照替代逐名定位（O(1) 次 tmux 调用，不违 NFR）；`close`/`ensure` 零改动，改动只在 `status` 一节。

## 对照过的备选模式

1. **维持现状（标题全机匹配 + 本仓台账）** —— 适用：单仓、无跨仓同 role-id 会话；代价：多仓并行时必然给出跨仓可执行提示 ⇒ 误杀。不采纳：本批即修此缺陷。
2. **会话名/名册记录带仓栈（`<仓>-<别名>-<编号>`）** —— 适用：可自由改命名且无外部消费者；代价：破坏 `close --task` 与既有回归用例（`cases/09`、`cases/13`、`cases/15`）、连带 `visible_session_names` 与 `subagent-*` 前缀语义。不采纳：改名属破坏性变更（PRD 非范围）。
3. **`NAO_SKILLS` 环境锚判仓** —— 适用：env 恒等于「当前工作仓」且他人可查询；代价：跨仓会话的 `NAO_SKILLS` 指向机制包而非其工作仓，且 `status` 侧读不到他人进程 env。不采纳：判据不可得。
4. **本仓台账反查会话名（有记录 ⇒ 本仓）** —— 适用：任务编号全局唯一；代价：违背 BR1「归属优先于名称」，把他仓同号会话重新召回残留节（T596 类误杀制度化）且需读全表。不采纳。

## 后果与风险

- 正面：他仓会话不再产生可执行回收提示；单仓（无他仓会话）`status` 输出**逐字不变**（NFR 兼容性，机械 diff 证）。
- 负面：他仓旧会话失去本仓指路（改为在其所在仓执行，能力未减，BR3）；不可判定会话（进程已退 / 权限读不到 `/proc` / legacy `nao-*` detached 名）只标注不指路。
- 风险：本仓与他仓存在同 role-id 会话时仍按「本仓优先」给提示（PRD 非范围：同名编号歧义不处理）；两仓 basename 相同时标题层可互串（既有缺陷，非本批）。

## 限制与已知边界

- 路径不可解析（目录已删 / `pwd -P` 失败）⇒ 退 `readlink -f` → 原串；仍不可判则归入不可判定桶，不猜。
- git worktree、指向仓外的符号链接子目录会被判他仓（保守侧：无 close 提示）；在仓根重跑或在该仓操作即可。
- `status` 宜在仓根运行；在子目录运行时依赖 toplevel 并锚集，否则本仓 pane 落入他仓桶（安全侧、非静默）。
- 前例依据：T530 的「不可判定时不得声称是自己」（`nao-fleet.sh` `self_pane_refuse` 三态 fail-closed），本 ADR 取其**对偶**：也不得声称「是本仓残留」。

## 相关指针

- 评审报告 `docs/reports/2026-10-31-T534-arch-review.md` · PRD `docs/prds/2026-10-30-fleet-guards.md` · 实现入口 `.agents/scripts/nao-fleet.sh`（`cmd_status`）

## 参考来源

- [tmux manual（FORMATS：`pane_current_path` / `pane_title` / `pane_id`）](https://man.openbsd.org/tmux.1) · 访问 2026-10-31 · `pane_current_path` = pane 前台进程的当前工作目录，可作仓归属判据。
- [git-rev-parse(1)（`--show-toplevel`）](https://git-scm.com/docs/git-rev-parse) · 访问 2026-10-31 · 输出工作树根绝对路径，用于把子目录 cwd 的锚抬到仓根。
