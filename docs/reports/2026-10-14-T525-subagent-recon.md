# T525 QA 现状复现：`subagent-*` 对 `status` / `close` / `ensure` / 孤儿 pane 的影响

- 状态：已定稿 · 更新：2026-10-14 · Owner：qa
- 指针：来源 `docs/reports/2026-10-12-pi-subagents-compat-review.md`（§2.2 / §2.3 / §4.3 / 附录 A）· PRD `docs/prds/2026-10-14-subagent-isolation.md` · 接缝 `tests/t4/cases/15-subagent-isolation.sh` · 收口方 `docs/reports/2026-10-14-T525-qa-verify.md`
- 性质：**只读复现**（PRD 落稿前 · 零代码改动；夹具仅在 `/tmp` + 隔离 tmux socket，跑完清理）

## 结论（首屏）

- **核心危害面 ≈ 0**：`status` 不列出子代理名、`close subagent-*` 现状已 `die` rc=1 且不触任何 pane、`ensure`/`running` 判重无洞、前缀边界正确。
- **但安全是隐式的**：全部靠「角色前缀匹配 + 别名解析」的偶然成立（`nao-fleet.sh` 内 `grep -c subagent` = 0），无显式分支、无断言、文案不点名 —— 改一个角色名即可能失守。
- **发现 1 个真边界缺口（E2）**：`unattributed_pi_panes` 的 claimed 集合会被子代理继承的 `tmuxPane` 认领 ⇒ 本应「无法归属会话名」的孤儿 `comm=pi` pane 告警被掩盖。
- **接缝确认 = C1**：新增 `tests/t4/cases/15-subagent-isolation.sh`（hermetic 假名册 + 真 tmux 隔离 socket 验「父 pane 存活」）；E2 与「绝不触 pane」是行为契约，只有真句柄链可证伪。

## 一、方法（hermetic 夹具）

- **路径**：全部落 `/tmp/t525-work`（真 tmux 隔离 socket `TMUX_TMPDIR` + `env -u TMUX -u TMUX_PANE`，socket ≠ 生产默认候选）。
- **名册**：复制 `.agents` 后以假探针读 `NAO_QA_FAKE_ROSTER_FILE`，**绝不接触真实 pi-intercom 名册 / broker**。
- **桩 pi**：`cp $(command -v sleep) <bin>/pi` —— 用**复制的二进制**保 `pane_current_command=pi`（`exec sleep` 脚本会丢 `comm=pi`，实测踩过）。
- **闸门**：`NAO_TASKS_STATE` 指向不存在文件以跳过 tasks-state 闸门；收尾 `cleanup -S <隔离 socket>` + 清目录；仓库零改动。
- **夹具陷阱（写进用例纪律）**：fleet 名册解析按行（`intercom-probe.mts` 的 awk `sub(/.*"name":…/)`）；**假名册探针必须 `JSON.stringify(x, null, 2)` 逐字段一行**——紧凑单行 JSON 会被贪婪 `.*` 只取到**最后一条**名字（本仓真探针用的正是 pretty-print，故仅夹具需注意）。

## 二、逐条实测现象 + 判定

1. **`status` 名册注入 `subagent-qa-<id>` / `subagent-chat-<id18>`** —— 二者**均不出现在任何输出**（角色区 / 派生区 / 告警区），`grep -c subagent` = 0。根因：`visible_session_names` 确实读名册，但派生区按 `"$dname" == "$role"-*` 过滤，子代理名不以任何角色 id 开头 ⇒ `continue`。**判定：无洞**（PM 推测成立）；但**无汇总/提示**（「看不见即误判」，与 T522–T524 非静默口径相反），且过滤隐式。
2. **`close subagent-qa-<id>` / `close subagent-chat-<id18>`（父 pane 在场 + 名册共 `tmuxPane`）** —— 均 rc=1「未知角色或派生会话名」，**父 `nao-qa` pane 存活**；`close --task <id> qa`（父+子在场）rc=0「未运行（无需回收）」且不触父 pane；`close qa` 正常回收父 pane（正控）。**判定：无洞** ——「命父 pane」路径不存在（子代理名无法经 `ALIAS_ROLE` 前缀解析，在 pane 定位前即 `die`）；欠缺仅限**文案不点名** `subagent-*` / `pi-subagents`。
3. **`ensure` 判重（`running`）** —— 名册仅子代理时 `ensure qa` **不判「已在运行」**（继续走 spawn）；正控（名册有精确 `qa`）正确判「已在运行」；`status` 角色区也不误报在线。根因：`intercom_online` / `intercom_pane_for` / `find_pane_for` 均精确名匹配。**判定：无洞**。
4. **`unattributed_pi_panes`** —— E1：未认领的真实 `comm=pi` pane（标题改写 `pi:c`）正确告警。**E2：追加一条仅以该 pane 为 `tmuxPane` 的 `subagent-*` 条目 ⇒ 告警消失**（claimed 被继承 pane 认领）。**判定：边界（真缺口，低危）** —— 真实场景该 pane 多已被父条目认领、掩盖无副作用；但父会话未注册/无 `tmuxPane` 时，孤儿 pane 会被静默吞掉。
5. **前缀边界** —— `qa-subagent-x`（合法派生名，任务号含 `subagent`）仍入派生区、`close` 走正常非静默路径；`subagentfoo` / `mysubagent-x` / 裸 `subagent` 均不入排除面、`close` 走通用「未知角色」文案（**不**归类为 `subagent-*`）。**判定：无洞（边界正确）**。
6. **`tasks-state` 存在时子代理是否获误导性 `close` 建议** —— 不会（不入派生区）。

## 三、风险与建议（交 PRD / arch 裁定）

- **E2 取值**：建议 `unattributed_pi_panes` 的 claimed 改**条目感知**并排除 `^subagent-`（非静默优先）；代价 = 某 pane 仅被子代理条目认领时回到告警。已由用户拍板「收口」并落 ADR。
- **排除面**：`^subagent-`（含 `subagent-chat-`）；须正向钉住 `qa-subagent-x` 不被误伤；并加 `check` 守卫（角色 id / 别名不得以 `subagent-` 开头），避免「排除面吃掉角色名」。
- **夹具纪律**：隔离 socket ≠ 生产候选 · `env -u TMUX -u TMUX_PANE` · 假名册 **pretty-print** · 桩 pi 用**复制**二进制 · 收尾机制 `cleanup -S`。

- 修订：2026-10-14 初版（T525 现状复现：4 路径 × 前缀边界 × E2，含夹具纪律与接缝 C1 结论）
