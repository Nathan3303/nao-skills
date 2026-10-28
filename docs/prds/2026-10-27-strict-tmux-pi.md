# 绑定 tmux + pi：删净宿主阶梯，非 tmux 硬失败

- 状态：**已交付并发布（v0.19.1 · PR #49 squash `f83cc6f` + 修复 PR #50 squash `ac5cc4c` · 归档 2026-10-28）** · Owner：PM · 更新：2026-10-28
- 指针：Issue [#48](https://github.com/Nathan3303/nao-skills/issues/48) · 取代 ADR `docs/adr/2026-10-12-non-tmux-host-spawn.md`（宿主阶梯）与 `docs/adr/2026-10-13-derived-pane-window-addressing.md` 的宿主外段落 · 现行实现 `.agents/scripts/nao-fleet.sh`（1947 行）· 协议 @.agents/skills/task-completion.md

## TL;DR

- **做什么**：舰队只支持「**tmux 内 + pi**」一种运行方式——删净 5 档宿主阶梯（≈215 行），非 tmux 环境直接 rc≠0 带提示退出，`check` 增 `pi ≥ 1.4.0` 硬断言。
- **给谁**：舰队 6 角色、下游三仓、维护者。
- **成功标准**：宿主分支 `grep` 归零 · 非 tmux 实测 rc≠0 + 提示 · tmux 内 `ensure/status/close` 行为等价 · 脚本净减 ≥180 行 · `check`/`npm test` rc=0。
- **不做什么**：不保留 screen/background/自建 attach/`NAO_TERMINAL` 多终端；不改 pipeline 阶段；不动下游三仓；不删与宿主无关的守卫。

## 一、问题证据

- **兼容面成本**：`nao-fleet.sh` 1947 行中约 **215 行**服务宿主选择——5 档阶梯（`tmux-in` / `tmux-attach` / `xdg-window` / `tmux-bg` / `screen-bg`）+ `NAO_TERMINAL` 白名单（5 值）+ `xdg-terminal-exec` 启动器 + 四种窗口句柄查询（`hyprctl`/`swaymsg`/`xdotool`/`wmctrl`）+ screen 分支。
- **模糊地带代价**：最近三批（T523/T524/T525）都在同一条缝上打补丁——`close` 的「无法确认在线状态」（`nao-fleet.sh:1747`，T523 刚加护栏与 `cases/13` 15 条断言）本质是「宿主句柄可能查不到」的副产物。**绑死 tmux 后这类不确定性消失**，护栏与对应断言可一并删除。
- **真实使用面**：本机与下游三仓的实际运行方式 = tmux 内常驻会话 + 派生 pane/window（用户陈述）；阶梯的 ③/④ 档在实测中从未作为常态路径使用。
- **根因**：兼容层为「可能有人不用 tmux」付了常态成本，而这条可能性没有被任何真实用户验证过。

## 二、目标指标

- **脚本净减**：`wc -l` 1947 → **≤1760**（净减 ≥180 行）。
- **删除面归零**：`grep -c 'NAO_TERMINAL|xdg-terminal-exec|hyprctl|swaymsg|xdotool|wmctrl|screen_present|screen-bg'`（脚本内）= **0**。
- **失败可读**：非 tmux 下任一子命令 rc≠0 且输出**一行**可操作提示（含起 tmux 的命令）。
- **行为等价**：tmux 内 `ensure`（新拉 / 判重 / `--force` 重开）、`status`、`close`（含双闸门）现有断言全绿。
- **门禁基线**：`check` rc=0 · `npm test` rc=0，报告**新旧**用例数与断言数（允许断言净减，见 AC4）。

## 三、范围 / 非范围

范围内：

1. 删宿主阶梯与配套件（`resolve_action` / `has_tmux_handle` / `xdg_launcher_ok` / `open_xdg_window` / `app_class_visible` / `wait_for_app_class` / `spawn_xdg_window` / `spawn_tmux_attach` / `wait_for_tmux_client` / `spawn_screen` / `screen_token_for` / `screen_present` / `spawn_fork_window` / `NAO_TERMINAL_ALLOWED`）。
2. 非 tmux 硬失败 + 提示（`ensure` / `status` / `close` / `cleanup` 一致）。
3. `check` 新增 `pi` 存在 + `pi ≥ 1.4.0` 断言。
4. 删除 `close` 的「无法确认在线状态」分支及其护栏（T523 段落）。
5. 新 ADR（取代旧宿主阶梯 ADR）+ 旧 ADR 标废弃 + 文档措辞收窄。

非范围（每条带理由）：

- **保留 screen / background / 自建 attach**：理由 = 用户拍板「最彻底」；半绑比全绑维护成本更高（仍要维护两套可见性判定）。
- **`NAO_TERMINAL` 保留一个 tmux 值**：理由 = 单一宿主下该变量无自由度，保留会诱发「以为还能切」的误用。
- **改 GitHub Flow / 发布流程 / 合并权**：理由 = 与本需求无关。
- **下游三仓同批改**：理由 = 用户拍板「自然升级」；本仓发版后由三仓下次 pin 升级生效（遗留项登记，见 §九）。
- **删 `tests/` 目录内与宿主无关的用例**：理由 = 只删/改与被删代码绑定的断言，其余一律不动。
- **跨 CLI 兼容层（CLAUDE.md 桥等）**：理由 = 用户只要求「绑死 pi 的运行前提」，未要求删互操作文档。

## 四、用户场景

- **场景 A（正常）**：用户在 tmux 里 `ensure infra` → 建 pane/window、注入角色卡、`list` 验证；`status` 列在线；`close` 走双闸门（在跑 turn / tasks-state 未推进）。
- **场景 B（非 tmux）**：用户在裸终端跑 `nao-fleet.sh ensure pm` → 立即 rc≠0，一行提示 `需要 tmux：请先 tmux new -s nao 再运行`，**不创建任何进程、不写状态**。
- **场景 C（pi 版本过低）**：`check` 报 `pi 版本 1.1.0 < 1.4.0`，rc≠0，派发前即被拦下。
- **画像**：舰队维护者（本机 tmux）、下游仓 PM（装包即用）、未来接手的维护者（读 ADR 即知「只有一条路」）。

## 五、业务规则

- **BR1 单一运行前提**：`${TMUX:-}` 非空且 `tmux` 命令可用 = 唯一合法运行环境；否则硬失败（rc=3，区别于 11 档值非法 / 12 命令缺失的历史语义，见 ADR）。
- **BR2 删除面最小完备**：只删「为宿主选择而存在」的代码；`spawn_tmux` 与 pane/window 寻址（T517）**保留**，因为它是唯一路径。
- **BR3 失败即不动作**：非 tmux / pi 缺失时 `ensure` 不得半启动（不建 session、不写 lock、不留 pane）。
- **BR4 pi 版本断言**：`pi` 存在且版本 ≥ **1.4.0**（semver 比较，预发布视为不满足）；`check` rc≠0 并指名当前版本。
- **BR5 close 语义收窄**：删「无法确认在线状态」分支后，`close` 只判「在跑 turn」+「tmux 会话/pane 存在」；不可判定不再发生（tmux 下必有句柄）。
- **BR6 断言净减豁免（一次性）**：本批允许断言总数下降，但必须在回执与 PR 中给出**旧基线 → 新基线**与差额去处（删了哪些、为什么）。
- **BR7 破坏性沟通**：release notes 首屏必须写清「本版起要求 tmux + pi ≥1.4.0」，并给一句迁移指引。
- **BR8 文档单一事实**：布局/宿主说明只保留 tmux 段；旧 ADR 标废弃并指回新 ADR，不复制正文。

## 六、NFRs

- **可维护性**：脚本行数净减 ≥180；新增分支数 = 1（环境判定），删除分支数 ≥5。
- **无新依赖**：不引入新外部命令（除已用的 `tmux` / `pi`）；版本比较用纯 shell/node 现有能力。
- **幂等**：`ensure` 连跑 2 次 effect = 0（判重路径不变）。
- **兼容降级**：不适用：本次为显式破坏性变更（用户已拍板）。
- **可审计**：删除面用 `grep -c` 断言 + 行数对照留痕在 QA 报告。

## 七、验收标准

- **AC1（主路径 · 单一前提）**：Given 非 tmux 环境，When 跑 `ensure`/`status`/`close`，Then 三者均 **rc=3** 且输出一行含 `tmux new -s nao` 的可操作提示，**无 session/pane/lock 产生**。**`cleanup` 豁免**：其正常场景就是「非 tmux 的隔离实验场」（`env -u TMUX … -S <socket>`），保持 **rc=2 用法守卫 + 幂等 0**，不得改为 rc=3。
- **AC2（删除面）**：Given 合并后的脚本，When `grep -cE 'NAO_TERMINAL|xdg-terminal-exec|hyprctl|swaymsg|xdotool|wmctrl|screen_present|screen_token_for|spawn_screen|spawn_xdg_window|spawn_tmux_attach|wait_for_tmux_client|app_class_visible|wait_for_app_class|spawn_fork_window'`，Then 结果 = **0**；且 `wc -l` 净减 ≥180。
- **AC3（pi 断言）**：Given `pi` 缺失或版本 < 1.4.0，When 跑 `check`，Then 输出 `✗ pi 版本 <cur> < 1.4.0` 且 **rc=1（聚合，不复用 3）**，并**继续跑完其余体检**（一次看全，不早退）；Given ≥1.4.0，Then 该断言 PASS 且完整 `check` 仍 rc=0（roles=6）。版本源 = `pi --version` 首个 semver，预发布视为不满足。
- **AC4（close 收窄 + 用例退役）**：Given tmux 内一场在跑 turn 的会话 / 一场空闲会话，When `close`，Then 前者拒、后者回收；`nao-fleet.sh` 内 `grep -c '无法确认在线'` = 0。**`cases/13`** 中依赖 `NAO_TERMINAL=foot|ghostty|ptyxis|screen` 的断言已删或改。**`cases/11`（宿主阶梯）整案退役**：删 `tests/t4/cases/11-host-ladder.sh` + `run.sh` 注册项与 usage 区间；其实体 `docs/reports/2026-10-12-T513-verify.sh`（971 行 · 39 处 `NAO_TERMINAL`）**原文保留、不追溯改写**（QA 冻结条款），仅在归档处加一行「随 T529 退役」。**回执须报旧基线 → 新基线 + 差额去处**（cases/13 删除项 + cases/11 整案）。
- **AC5（ADR 与文档）**：（ADR 文件名沿用 `docs/adr/2026-10-27-strict-tmux-pi.md`，不改为 10-28，避免与 PRD/Issue 字符串漂移）Given `docs/adr/`，When 读，Then 新增 ADR 取代旧宿主阶梯 ADR（旧 ADR 状态 = `已废弃（被 2026-10-27-strict-tmux-pi 取代）`）· ADR 索引 +1 行 · `intercom-protocol.md` 布局段只剩 tmux 三选一与窄列回退 · `AGENTS.md` 布局语义行同步。
- **AC6（负向 / 边界）**：Given 变更集，When 看 diff，Then 未改 GitHub Flow 阶段、未删 `tests/` 中与宿主无关的用例、未引入新依赖、未动下游三仓。
- **AC7（门禁一致性）**：Given 交付终态，When 跑全范围门禁，Then `check` rc=0（roles=6 · files 计数按新基线）· `npm test` rc=0，两者数字精确可复核；`test:t4:full`（空载）rc=0 且 SKIP=0/DEGRADE=0。
- **AC8（可用性实测）**：Given 真 tmux 会话，When 依次跑 `ensure`（新拉 + 判重 + `--force`）/`status`/`close`，Then 行为与改动前一致（留命令 + 输出摘要）；Given 非 tmux，Then 按 AC1 失败（留实测输出）。
- **AC9（破坏性沟通）**：Given `docs/releases/v0.19.0.md`，When 读首屏，Then 明确「必须 tmux + pi ≥1.4.0」+ 两句迁移指引（① 起 tmux 的方式；② **旧版曾用 `--background`/screen 拉起的会话本版不可见，需 `screen -ls` 手工清理**）；Release 标题 = 裸 `v0.19.0`。

## 八、上线闭环

- **版本**：**v0.19.0**（0.x 语义下承载破坏性变更；users 已拍板一步到位）。
- **发布**：tag + Release（标题裸版本号）· npm 重发（用户执行，判据 = `latest` + `dist.integrity` 逐字节一致）。
- **灰度为不适用**：本地工具，无服务端灰度；回滚 = `git revert` 单提交（脚本自带旧路径已删，回滚即恢复）。
- **监控信号**：后续 2 批 `check` 是否出现「非 tmux 环境」误报（若出现说明用户环境与假设不符，需复查 BR1）。
- **迁移**：下游三仓下次 pin 升级时按 release notes 首屏操作；不主动改。

## 九、变更治理与优先级

- **战略筛子**：命中「机制可维护性」——兼容层是常态成本、收益未被验证；不做则同类「无法确认」补丁会持续出现在 close/status。**不插队**：当前批次终态、无在飞任务，可立即开工。
- **MoSCoW**：Must = AC1–AC7；Should = AC8；Could = 情形化提示（如检测到无 tmux 时顺手提示 `apt install tmux`）；Won't = 下游同批改。
- **RICE**：Reach = 20（未来一月运行次数）· Impact = 3 · Confidence = 0.85 · Effort = 1.5 人日 ⇒ **RICE ≈ 34**（Effort 高，故低于 T528 的 96）。
- **Kano**：期望型（越简单越可信）；反面 = 少一个「另外还支持 X」的承诺。
- **决策留痕（2026-10-27 用户拍板）**：① 绑死程度 = **只留「必须在 tmux 内」**（删五档 + xdg + app-class + screen）② 绑死 pi = **加版本硬检查** ③ 发布 = **一步到位 v0.19.0** ④ 非 tmux = **硬失败 + 提示** ⑤ pi 基线 = **≥1.4.0** ⑥ close 护栏 = **删 T523 段并允许断言净减（一次性豁免）** ⑦ 下游 = **不管，自然升级**。
- **开工卡拍板（2026-10-27 · D1–D4）**：D1 **现在开工**（派生 `rd-infra-T529`）· D2 **轻量 arch 评审**（只评删除面完备性与 ADR 取代关系，不重写方案）· D3 硬失败退出码 **rc=3**（与 11 档值非法 / 12 命令缺失分开语义）· D4 `cases/13` **允许断言净减**，回执须给旧基线→新基线 + 差额去处。
- **arch 轻量评审结论（2026-10-28 · `done(lite)`）**：14 项全可删、**零必须保留**；`screen_token_for`/`screen_present` 确被 `status`/`close` 硬依赖，须**成组连带 6 处**一并删；另有 **10 项清单外漏项**（`app_client_pid`/`pi_descendant_of`/`app_pid_for` + close 的 app-id 分支 · pid pipe 全套 · `TMUX_ENV_SCRUB` · `NAO_TERMINAL_LIST` · `offline_verifiable` · `visible_session_names` screen 块 · `--background`/`BACKGROUND` · `spawn_tmux` 的 `new-session -d` else 分支 · `check` 宿主阶梯段 · 头注释）⇒ 实删 **255–285 行**、净减 ≈240。ADR 够格，另加 3 条硬要求（文件名沿用 10-27 · 对照模式含「维持现状」基线 · 逐函数删除表下沉 arch 报告）。**11/12 从来只是 `resolve_action` 的内部 return 码**，进程实际 exit 仅 0/1/2 ⇒ ADR 写「随 `resolve_action` 一并退役，无外部可见退出码消失」。
- **PM 追加拍板（2026-10-27 · D5–D8）**：D5 **AC1 收窄** —— `cleanup` 豁免（非 tmux 是其正常场景），保持 rc=2 守卫 + 幂等 0 · D6 **`cases/11` 整案退役**（QA 冻结「不改断言」⇒ 只能退役；实体探针原文保留）· D7 **pi 断言失败 rc=1 聚合且跑完全部体检**（check = 已执行并给完整报告，3 = 未执行）· D8 ADR 文件名沿用 `2026-10-27` · D9 release notes 增 legacy screen 手工清理指引。
- **遗留项预判**：下游三仓旧 pin 继续跑旧行为（出口 = 接受含到期，日期 = v0.19.0 发布 +30 天）；`cases/13` 断言净减需在新基线上留档。

- 修订：2026-10-27 首版（grill 两轮 7 项拍板）

## 十、派发记录 / 验收结果 / 变更记录（归档 2026-10-28）

- **派发链**：`arch-designer-T529`（轻量评审 `docs/reports/48-arch-review.md`）→ `rd-infra-T529` 实现（`da50fcc`）→ `qa-T529` 独立复核（`docs/reports/48-qa-verify.md`）→ `rd-infra` 合并（`f83cc6f`）→ **PM 发布前置闸门 FAIL** → `rd-infra-T530` 修复两轮（`0c17d62` / `876ae02`）→ `qa-T530` 复核 + D-1 点检 → 合并（`ac5cc4c`）。
- **PR**：[#49](https://github.com/Nathan3303/nao-skills/pull/49)（squash `f83cc6f` · 验收评论 issuecomment-6461012072）· [#50](https://github.com/Nathan3303/nao-skills/pull/50)（squash `ac5cc4c` · 验收评论 issuecomment-6461675826）。
- **验收结论**：**通过（AC1–AC7）**。门禁：`check` rc=0（roles=6 · files=50）· `npm test` rc=0 · 16/16 · `test:t4:full` 空载 rc=0（SKIP=0/DEGRADE=0）。断言双口径：调用点 261→252（−9）/ 运行期 PASS 行 483→391（−92；全绿 485→391 = −94），去处 `cases/11` −85 · `cases/13` −8 · `cases/15` −1。
- **发布阻断与根因（PM 初判有误，以 QA 实测为准）**：非「88 处 tmux 调用打默认 server」（tmux 客户端本就认 `$TMUX`），而是**自面板守卫跨 server pane id 撞号**（pane id 为 server 局部命名空间）⇒ 误拒；修复 = `pane_hosts_caller` 进程归属判定 + **三态 fail-closed**（D-1：不可判定且撞号也拒，避免 QA 实证的 SELF_KILLED）。
- **变更记录**：AC1 收窄（`cleanup` 豁免 rc=3，D5）· `cases/11` 整案退役（D6）· pi 断言失败 rc=1 聚合（D7）· 断言净减一次性豁免并须报差额（BR6）· 版本 v0.19.0 → **v0.19.1**（0.19.0 未发布）。
- **遗留项**：下游三仓旧 pin（接受，到期 = v0.19.1 发布 +30 天 = **2026-11-27**）· `MIN_PI_VERSION` 常量提炼（D3，backlog）· 未覆盖「真实嵌套 tmux 端到端」（用例以双隔离 server 等价覆盖，接受）· 非 Linux/macOS 的 `ps` 行为未验（接受）。
