# PRD：非 tmux 宿主的舰队派生（宿主阶梯 + 前台可见 + 句柄模型）· T513

> Issue：[#26](https://github.com/Nathan3303/nao-skills/issues/26) · 批次：T513 · 分支：`feat/26-non-tmux-host-spawn`（base `main`）
> 版本影响：**MINOR `0.13.0 → 0.14.0`**（新增非 tmux 宿主阶梯与 `--background` 能力 = additive；npm 发布由用户执行，tag/Release 由 PM 出）
> 执行：rd-infra · 验证：qa · 架构：arch-designer（ADR + 终签）
> 状态：**已开工**（用户 2026-10-12 拍板：范围与版本 = 本 PRD 全文 + `0.14.0` MINOR；决策 D1–D5 见 §9）· 正文为权威（Issue 只放摘要与指针）
> 设计依据：`docs/reports/2026-10-12-pi-subagents-compat-review.md`（§4.6 宿主面）+ 本 PRD §1 实测（PM 2026-10-12 在 tmux 内外各跑一次）

## 0. TL;DR

- **做什么**：把「宿主选择」从**枚举模拟器**改为**问环境**的阶梯（`NAO_TERMINAL` → tmux 内 → tmux+可见窗口 → `xdg-terminal-exec` 窗口 → 显式 `--background`），并修掉两处假成功/裸中断。
- **给谁**：不在 tmux 里用舰队的用户（本机默认 = Omarchy/Hyprland/foot，`detect_host` 名单里**没有 foot**）。
- **成功标准**：tmux 外 `ensure` 出来的角色**用户看得见**；任何失败都**非 0 且可读**，不存在「打印已拉起但什么都没有」。
- **不做什么**：不动 tmux 内既有行为、不动角色/闸门语义、不并入 pi-subagents 的 `subagent-*` 课题。

## 1. 问题证据

- **P1 枚举模拟器**：`detect_host()`（`nao-fleet.sh:316`）只在 `ghostty|ptyxis|tmux` 中选，兜底 `screen`；**全仓 `foot` 0 命中**，而本机终端正是 foot 1.28.0 ⇒ 名单必然漏（模拟器是无穷集合）。
- **P2 静默不可见**：非 tmux 环境下落到 tmux 候选 → `tmux new-session -d`，**detached 后台会话**，屏幕上没有；`status` 却报在线。
- **P3 裸中断（实测）**：`NAO_TERMINAL=screen`（未安装）→ `行 903: screen: 未找到命令`，**rc=127**，无诊断、无恢复提示。
- **P4 假成功（实测 · 最恶劣）**：`NAO_TERMINAL=ghostty`（未安装）→ 打印 **`[ghostty] 已拉起 qa @ .` 且 rc=0**，随后 `status` 显示 qa **未运行**（`setsid -f` 对缺失命令返回 0）。
- **P5 句柄模型绑死 tmux**：`find_pane_for*` 三层后备 + `pane_busy()`（`tmux capture-pane` 末 12 行）+ `offline_verifiable()`（仅 tmux/screen 宿主敢断言不在线）⇒ 换宿主即失据。
- **5 Whys**：① 为什么非 tmux 派生有问题 → 宿主识别漏了用户的真实终端；② 为什么漏了就出事 → 落到 tmux ⇒ 后台会话（不可见）；③ 为什么不可见是问题 → 用户以为没起来，`status` 说起来了（可见性契约破裂）；④ 为什么长期没发现 → 历史 QA **全在 tmux 内**跑，非 tmux 路径 0 断言；⑤ 根本原因 → 把「宿主」当**有限集合枚举**，而它应是**环境查询 + 显式覆盖**。

## 2. 目标指标

- 非 tmux 环境下 `ensure <角色>`：**可见窗口命中率 100%**（本机 foot+Hyprland 实测口径），后台静默会话 **0 例**。
- 失败可读性：宿主不可用类失败 **rc≠0 且 0 处「已拉起」**（基线：P3 = rc 127 裸中断 / P4 = rc 0 假成功）。
- tmux 内回归：AC6 逐值比对**零差异**（分屏几何 + 三布局 + 窄列守卫）。
- 句柄可用性：非 tmux 窗口宿主下 `close <角色>` 回收成功率 **100%**（app-id/pid 句柄）。

## 3. 范围 / 非范围

**IN（做什么）**
- `detect_host()` → **宿主阶梯**；新增 `spawn_window()`（`xdg-terminal-exec --app-id=org.nao.<名> --dir=<repo>`）与 `--background` 显式开关。
- 失败语义统一：环境不足 `exit 2` + 单行可读诊断 + 可复制恢复命令；**禁止假成功**（成功日志须以宿主句柄存在为前置校验）。
- 非 tmux 句柄：`find_pane_for*` 增 **app-id 层**（`hyprctl clients -j` 的 `class`/`pid`）· `pane_busy` 非 tmux 下改用**名册状态** · `offline_verifiable()` 新语义 · `close` 按 pid/class 回收。
- `cmd_check()` 宿主段改为宿主无关；文档四处同步：usage 头 · `.agents/common/intercom-protocol.md` · `README.md` · `docs/ARCHITECTURE.md` 工具层。
- `tests/t4/` 新增 case 11（宿主阶梯 + 失败语义 + 非 tmux 句柄）；`docs/releases/v0.14.0.md`。

**OUT（不做什么）**
- ❌ tmux 内既有行为与三布局语义（`NAO_TMUX_*`）——**零变更**。
- ❌ pi-subagents 相关（`status`/`close` 排除 `subagent-*`）——arch 已定性**独立课题**，本批不碰。
- ❌ 合成器特定深度适配：`hyprctl`/`swaymsg` **仅作后备**，只探测存在性，不做多合成器矩阵。
- ❌ 角色语义、闸门语义、`.agents/prompts|skills` 内容；下游三仓 pin（另批次）。
- ❌ 非 tmux 宿主的 `status` **turn 判定完整等价**（本批按 D2 明确降级，见 §5 BR7）。

## 4. 用户场景

- **画像**：单机桌面用户（Omarchy / Hyprland / **foot**），有时在 tmux 里、有时直接在终端里；偶尔 SSH 进无图形会话的机器。
- **S1（现状不变）** 在 tmux 内 `ensure` → 当前窗口分屏，三布局与窄列守卫照旧。
- **S2（本批主路径）** 在 foot 终端里（无 `$TMUX`）`ensure qa rd-be` → **每个角色一个可见窗口**，标题/`app-id` 带角色名，用户当场看得见在跑什么。
- **S3（D5 路径）** 不在 tmux 但本机有 tmux → 建 `nao-<角色>` **tmux 会话**并**开一个可见窗口 attach 到它** ⇒ 既可见、又保留完整 tmux 句柄（pane 标题 / `$TMUX_PANE` / `pane_busy`）。
- **S4（无图形会话）** SSH 里 `ensure` → 因无图形会话**明确拒绝**并给可复制命令；要后台需显式 `--background`。
- **S5（失败）** `NAO_TERMINAL=<未安装宿主>` → 立即非 0 + 诊断，绝不假成功。
- **关键路径**：`check` → `ensure`（宿主判定 → 句柄建立 → 进程拉起）→ `status`（可见性/在线核对）→ 任务闭环 → `close` 回收。
- **CLI 输出状态清单**（页面状态清单的 CLI 等价物）：**正常**（宿主 + 句柄 + 窗口标识）· **跳过**（角色已在线，判重）· **降级**（非 tmux 宿主：标注 turn 判定来源）· **错误**（环境不足 `exit 2` / 拉起失败 `exit 1`，各带一行诊断与恢复命令）。

## 5. 业务规则

- **BR1 宿主阶梯（顺序固定）**：① `NAO_TERMINAL` 显式强制 → ② `$TMUX` 存在 ⇒ 当前窗口分屏 → ③ 不在 tmux、有 tmux、有图形会话 ⇒ **tmux 会话 + 可见窗口 attach**（用户 D5）→ ④ 无 tmux、有图形会话 ⇒ `xdg-terminal-exec` 直接开窗跑 pi → ⑤ 无图形会话 ⇒ **仅** `--background` 时 detached tmux/screen → ⑥ 无可用宿主 ⇒ `exit 2` + 诊断。
- **BR2 禁止假成功**：任何「已拉起」必须**先**验证宿主句柄已建立（窗口/会话/进程存在）；`setsid -f` 一类异步 fork 必须检出子进程失败（P4 根因）。
- **BR3 失败语义**：环境不足/不可运行 = **`exit 2`**（沿用 0.12.0 D5 口径）；能运行但动作失败 = `exit 1`；两者都必须可读、可复制恢复，禁裸 127。
- **BR4 默认不产生不可见会话**：默认路径不得只建后台会话；后台需**显式** `--background`（用户 D4）。
- **BR5 tmux 内零回归**：②路径行为与本批前逐值一致（用户 D3）。
- **BR6 降级必须显式告知**：非 tmux 宿主下 `status`/`close` 的能力边界须在输出中标注一行，并写入文档（用户 D2）。
- **BR7 句柄优先级**：tmux pane（层①②③ 现状）> **app-id/class**（非 tmux 窗口宿主）> 名册状态（turn 判定）；`offline_verifiable()` 在无宿主句柄时**不得**断言「不在线」。
- **BR8 `NAO_TMUX_*` 三变量仅对 tmux 宿主（②③）生效**，非 tmux 路径不得静默忽略其非法值（`check` 仍校验合法性）。

## 6. NFRs

- **NFR1 门禁**：`npm test` exit 0；`tests/t4/run.sh` 全绿且断言数**只增不减**（基线 ≥179 · 10 用例）。
- **NFR2 零网络**：宿主探测只用「命令存在性 + 环境变量 + 进程句柄」，无网络、无时间依赖（`PI_OFFLINE=1` 下可跑）。
- **NFR3 零回归**：tmux 内路径逐值一致（AC6）+ 复用 T509 断言集（`docs/reports/2026-10-08-T509-alias-close-verify.sh`，507 行/34 断言/`--with-tmux` 真拉模式）做 `close`/`status` 回归。
- **NFR4 可移植性**：主路径用 freedesktop 标准 `xdg-terminal-exec`；合成器命令仅后备且必须先探测存在性，探测失败不得影响主路径。
- **NFR5 覆盖限制须写明**：本机仅有 foot + Hyprland ⇒ ghostty/ptyxis/其它合成器路径**无法真测**，以桩/mock 断言覆盖并在 AC 中标注（不得声称已验证）。
- **NFR6 无新常驻面**：新增环境变量 ≤1（`--background` 用 CLI 开关，不引入新 env）；`check` 单行摘要格式不变。

## 7. 验收标准（AC）

- **AC1（主路径 · 阶梯③）** Given 不在 tmux 内、tmux 可用、有图形会话 When `ensure qa` Then 创建 `nao-qa` 会话并打开可见窗口 attach 到它（窗口标识含 `org.nao.qa`）且 rc=0。
- **AC2（主路径 · 阶梯④）** Given 不在 tmux、无 tmux、有图形会话 When `ensure qa` Then 以 `xdg-terminal-exec --app-id=org.nao.qa --dir=<repo>` 开窗跑 pi 且 rc=0，窗口可被 `hyprctl clients -j` 按 class 定位。
- **AC3（异常 · P4 回归）** Given `NAO_TERMINAL=ghostty`（未安装）When `ensure qa` Then **rc≠0** 且输出含诊断、**0 处「已拉起」**。
- **AC4（异常 · P3 回归）** Given 六个宿主全不可用 When `ensure qa` Then **rc=2** + 单行诊断 + 可复制恢复命令（非 127、无裸报错）。
- **AC5（边界 · D4）** Given 无图形会话 When `ensure qa`（无 `--background`）Then `exit 2` + 诊断；**加** `--background` Then 建 detached 会话并打印 attach 命令（rc=0）。
- **AC6（负向闭环）** Given 任一失败路径 Then **无半拉起残留**（无孤儿窗口/会话；`status` 不显示该角色在线），且失败前已创建的资源被清理。
- **AC7（设计一致性 · D3）** Given 在 tmux 内 When `ensure qa rd-be qa` Then 分屏几何、判重跳过、三布局与窄列守卫行为与本批次前**逐值一致**。
- **AC8（句柄降级 · D2）** Given 非 tmux 窗口宿主 When `close <角色>` Then 按 app-id/pid 回收成功 rc=0；`status` 输出含「turn 判定来源 = 名册」的降级标注。
- **AC9（文档一致性）** Given 实现完成 Then usage 头 / `intercom-protocol.md` / `README.md` / `docs/ARCHITECTURE.md` 与 BR1 阶梯逐条一致，且 `check` 有对应断言。

## 8. 上线闭环

- **发布**：`0.14.0`（MINOR）；tag 指向 main 合并提交；`docs/releases/v0.14.0.md` 面向用户（重点讲「不在 tmux 里也能看见舰队」+ 失败不再假成功）。
- **回滚**：不改数据、无迁移 ⇒ 回滚 = 发下一个 PATCH 恢复阶梯；**即时绕过** = `NAO_TERMINAL=tmux`（本批保留该逃生口）。
- **监控**：`check` 宿主段 + `status` 降级标注；PM 在验收时实拉一次（tmux 内 + tmux 外各一次）。
- **灰度**：本机（foot/Hyprland）真跑为主路径；不可真测路径（ghostty/ptyxis）在 release notes 与 AC 中**显式标注覆盖限制**。

## 9. 变更治理

- **决策台账（用户 2026-10-12 拍板）**：**D1** tmux 外默认**开可见窗口** · **D2** 非 tmux 宿主 `close` 支持、`status` turn 判定**明确降级**（文档写明）· **D3** tmux 内**仍优先 tmux** · **D4** 无图形会话**必须显式 `--background`**，否则 `exit 2` · **D5**（用户本轮追加）tmux 可用时**可用 tmux，但必须前台可见**，禁止静默后台会话。
- **D5 的架构后果（关键）**：阶梯③把 tmux 会话放进**可见窗口** ⇒ 会话仍是真 tmux 会话（`$TMUX_PANE` / 标题契约 / `pane_busy` 全部可用）⇒ **句柄模型完整保留**（P5/P6/P7 在该路径零改动）；D2 的降级面**只在阶梯④**（无 tmux 但有图形会话）成立。故本批次的回归风险显著小于初判。
- **实测纠正**：P3 = rc 127 裸中断（原为推断，本轮实测）；P4 = rc 0 假成功且 `status` 显示未运行（本轮实测）。
- **待办（不在本批）**：T512-① `subagent-*` 会话的 `status`/`close` 排除（独立课题）；T512-②/③（pi-subagents 桥与 agent 薄壳）；`.nao-version` 收敛等既有后续项。
- **变更流程**：本 PRD 定稿 → 建 Issue → 开工确认卡 → arch ADR（备选四方对照）→ QA 用例先行 → rd-infra 实施 → PM 验收 → RD squash 合并 → PM 发版。Hotfix 若发生 24h 内补单。

## 10. 优先级

- **战略筛子：通过**——非「新功能」而是**可用性前提**（舰队拉不起来 ⇒ 机制对非 tmux 用户不成立）。
- **MoSCoW**：Must = 波1 失败语义（BR2/BR3）+ 阶梯①–③（BR1）+ `--background`（BR4）；Should = 阶梯④ 与句柄降级（BR7）；Could = app-id 句柄的 turn 判定增强；Won't = 合成器矩阵。
- **RICE**：Reach **高**（本机默认路径即 foot ⇒ 100% 本机用户）· Impact **3**（阻塞级）· Confidence **0.8** · Effort **2 人日** ⇒ 分数 **120**（相对同批最高）。
- **Kano**：**基本型（Must-be）**——做不好直接不可用，做好了也不会加分，故本批目标只求「可用 + 不骗人」。
