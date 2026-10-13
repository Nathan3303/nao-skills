# PRD：派生会话 tmux 落点修正——建到「宿主窗口」，不再拆用户当前窗口

- 状态：已定稿 · 更新：2026-10-13 · Owner：PM
- 指针：勘查回执 `[T517] done(full)`（rd-infra，2026-10-13；未落盘，实施阶段补 `docs/reports/`）；关联 ADR `2026-10-12-non-tmux-host-spawn.md` §38、`2026-09-25-tmux-fleet-layout-modes.md`

## TL;DR

- **做什么**：`ensure`（含 `--task` 派生）创建 pane 时，**显式以「派生宿主窗口」为目标**（调用者 pane 所在 window），不再落到用户当前正在看的 window；并修正布局与 `main-pane-width` 对用户窗口的泄漏。
- **给谁**：多 tmux window 工作的舰队使用者（不再出现「派生会话把用户正在干活的窗口拆开」）。
- **成功标准**：多 window 场景下新 pane、布局重排、`main-pane-width` 选项**只作用于宿主窗口**；单窗口场景 pane 数与几何**逐值零回归**。
- **不做什么**：不改非 tmux 宿主阶梯 ③④⑤ 与 `new-session -d` 分支；不改 `status`/`close` 的 pane 定位；不提供「旧行为」开关。

## 一、问题证据

- 用户报（2026-10-13）：用户切到其他 tmux window 后执行派生，新 pane 建到**用户当前 window**，把正在使用的窗口拆开。
- 根因（rd-infra 隔离 socket 实测，tmux 3.7c，5 组实验 + 真实 server 只读旁证）：`spawn_tmux` 的 `tmux split-window -h` 与整条布局链**全部无 `-t`**；tmux 无 `-t` 时落点 = **当前窗口**（有 attached client ⇒ 该 client 的当前 window；无 client ⇒ session current window），**与调用者 pane 无关**（`$TMUX_PANE` 不参与目标解析）⇒ 拆用户窗口；`select-layout`/`set-window-option main-pane-width` 同样作用于用户窗口（选项泄漏）。
- 长期漏检原因：T513-AC7 用 detached + **单窗口**验证，此时 current window ≡ 调用者窗口，结构上测不出该缺陷。
- 5 Whys：为何 pane 跑到用户窗口 → 无 `-t`，tmux 取「当前窗口」→ 为何取当前窗口 → 有 client 时「当前窗口」= 用户视图 → 为何依赖 tmux 默认 → 创建目标未显式声明 → 结论：**创建/布局目标必须显式声明为宿主窗口**。

## 二、目标指标

- 多 window 场景（含无 client 的确定性复现用例）：新 pane 落在宿主窗口的比例 100%（AC2/AC3）。
- 宿主窗口布局与 `main-pane-width`：前后一致（零变化），用户窗口 pane 数/`window_layout`/选项零变化（AC4）。
- 单窗口零回归：pane 数与几何逐值等于 T513-AC7 golden（AC1）。

## 三、范围 / 非范围

**范围内**
- `nao-fleet.sh`：入口一次性解析宿主窗口，`-t` 贯穿 `split-window` 与全部布局调用（`apply_tmux_layout` / `apply_main_col` / grid 分支）。
- 宿主窗口定位链（D1 已拍板）：`NAO_TMUX_HOST_WINDOW`（显式覆盖）> `TMUX_PANE` → `#{window_id}` → 名册唯一命中 → **warn + skip（不创建）**（skip 必须打 warn，不静默）。
- **常驻 ensure 与 `--task` 派生同批修**（D2 已拍板：同源，不做人工分叉）。
- 文档同步：`intercom-protocol.md` 宿主阶梯②措辞 + 脚本 usage 注释 + ADR 修订。
- 回归用例：隔离 socket 用例（QA 独立维护断言）。

**非范围**
- 非 tmux 宿主阶梯 ③④⑤、`new-session -d`、`TMUX_ENV_SCRUB`/F2 不变量、自 pane 闸门。
- `status`/`close` 的 pane 定位（现走 `list-panes -a` + 显式 `-t`，不受影响）。
- 「旧行为」开关（D3 已拍板：旧行为即缺陷，只留显式覆盖 env）。
- 附带项（`cmd_status` 跨 session 显示）不在本批，另记候选。

## 四、用户场景

- **多 window**：舰队在 W1，用户切到 W2 干活；PM 派生子会话 ⇒ 新 pane 出现在 **W1**，W2 的 pane 数、布局、窗口选项**均不变**。
- **单一 window**：行为与修前逐值一致（pane 数、几何、布局模式、窄列回退）。
- **跨 session**：调用者 pane 在 session A 的窗口、用户 client 视图在 session B ⇒ 新 pane 落 **A 的宿主窗口**（D4 已拍板：按「派生宿主」而非「用户正在看的」语义）。
- **异常**：宿主窗口已关闭 ⇒ 走既有「pane 创建失败」warn 路径，**不得**回退去拆用户窗口；`TMUX` 已设但 `TMUX_PANE` 空 ⇒ 明确降级：warn + skip（不创建；不静默、不建到当前窗口）。

## 五、业务规则

- **目标显式化**：凡「创建 pane / 应用布局 / 写窗口选项」的操作必须带显式目标（宿主窗口），禁止依赖 tmux 的「当前窗口」隐式解析。
- **定位链固定**：`NAO_TMUX_HOST_WINDOW`（显式覆盖，允许跨 session，warn 标注）> `TMUX_PANE` → `window_id` > 名册唯一命中（名册推断仅限本 `$TMUX` 所属 session 内）> warn+skip（不创建）；每一级降级都要可观测（warn 带数字/原因）。
- **不回退污染**：任何降级路径都不得把 pane 建到「当前窗口」（用户视图）。
- **client==host 零变化**：单窗口/调用者即宿主时，几何与布局结果与修前逐值一致。
- **无人工分叉**：常驻与派生共用同一条落点逻辑。
- **断言归属**：回归断言由 QA 独立维护（rd-infra 不自验自己的守卫）。

## 六、NFRs

- 兼容：tmux ≥ 3.6（勘查用 3.7c 实测；`window_id` 目标语法与 `-t` 带窗口目标在既有支持范围）。
- 性能：L1/L2 ≤1 次 tmux 调用；L3（名册兜底）≤2 次；布局路径调用次数不因目标参数显著增加。
- 可观测：降级链每级 warn 可区分（可复核，不静默）。
- 约束：不改 tmux 用户状态（不得 `select-window` 移动用户视图）；实验一律隔离 socket（`-S`）执行。

## 七、AC

- **AC1 零回归**：隔离 socket、单窗口、有效 `TMUX_PANE` ⇒ 新 pane 落该窗口；pane 数与几何逐值等于 T513-AC7 golden。
- **AC2 缺陷修复（无 client，核心）**：session current window 设 W2、调用者 pane 在 W1 ⇒ 新 pane 必须落 **W1**；同一用例负向断言 **W2 的 pane 数与 `window_layout` 均未变化**。
- **AC3 缺陷修复（有 client）**：attach 假 client 且视图切到 W2 ⇒ 仍落 **W1**、W2 几何不变。
- **AC4 布局/选项不外溢**：layout 作用于 W1（`display-message -t @W1 '#{window_layout}'` + 几何 = golden）；`show-window-options -t @W2 -v main-pane-width` 前后一致。
- **AC5 边界/负向**：a) 宿主 window 已关闭 ⇒ 走既有 warn 路径、rc 语义不劣化、**不得**回退拆用户窗口；b) `TMUX` 已设但 `TMUX_PANE` 空 ⇒ 明确降级：warn + skip（不创建；不静默、不建到当前窗口）；c) 跨 session（调用 pane 在 A、client 视图在 B）⇒ 落 A 的窗口；d) 宿主窗口极窄 ⇒ 窄列守卫按**宿主窗口宽**生效，回退链（main-row2→main-col→grid）保持。
- **AC6 幂等**：连跑 2 次 `ensure`（第 2 次命中 running 跳过；`--force` 时 pane 数 +1 且布局仍收敛 golden）。
- **AC7 同源一致**：常驻 `ensure` 与 `--task` 派生在 AC2/AC4 场景下行为一致（无人工分叉分支）。
- **AC8 文档同步**：`intercom-protocol.md` 宿主阶梯②由「当前窗口分屏」改为「派生宿主窗口（调用者 pane 所在 window）分屏」；脚本 usage 注释同步；ADR 修订（落地 `2026-10-12-non-tmux-host-spawn.md` §38「跨窗口需改目标寻址」）。
- **AC9 门禁/回归**：全范围 `check` rc0 + `npm test` rc0 + `tests/t4` 全范围回归绿（含本批新增用例）；赛道按 `docs/reports/` 留痕。

## 八、上线闭环

- 缺陷修复类（fix）⇒ 发版为 **PATCH**（v0.16.2 或随下批）；tag 指向 main 合并提交。
- 回滚：脚本单函数改动，`git revert` 合并提交即恢复旧行为（旧行为即缺陷，仅作应急）。
- 监控：`ensure` 输出中降级 warn 的出现频次（可观测即可，不设强制指标）。

## 九、变更治理

- 决策留痕（用户 2026-10-13 拍板）：**D1** 定位链如上（显式覆盖 > TMUX_PANE > 名册唯一命中 > warn+skip（不创建），不静默）；**D2** 常驻与派生同批修；**D3** 不加旧行为开关，只留显式覆盖 env；**D4** 跨 session 落「派生宿主（调用者）窗口」。
- 分工：`rd-infra` 实施脚本与 usage；`qa` 用例先行 + 独立验收断言；`arch-designer` ADR 修订与评审；`pm` 本 PRD/Issue/台账与 `intercom-protocol.md` 措辞。
- 变更需 bump 相关卡版本（如无卡改动则不 bump）并广播。