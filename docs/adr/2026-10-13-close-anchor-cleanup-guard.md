# ADR：cleanup 守卫「生产默认 socket 判定」与 TMUX_TMPDIR 解耦

- **状态**：已接受（随 T516 / 0.16.0 落地；本 ADR 随 PR #30 入库） · 日期：2026-10-13 · 出具：arch-designer · 落地：rd-infra
- **指针**：PRD `docs/prds/2026-10-13-close-anchor-safe-clean.md`（§四 D2 / §七 事故补录）· Issue #29 · PR #30

## 背景

- T515 I1 结案：实验夹具收尾时裸 `tmux kill-server` 连坐真 server（`$TMUX` 已设时客户端无视 `TMUX_TMPDIR`）；fleet 无安全清理入口，纪律无载体。
- 2026-10-13 17:11 事故（AC5e）：初版守卫的「默认 socket」判定取 `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default`；夹具为隔离把 `TMUX_TMPDIR` 指向夹具目录 ⇒ 夹具 socket 被误判为默认（恒拒）、**真默认 socket 被误判为非默认**（放行后 `kill-server` 连坐调用者自己的 server）。T515 I1 的精确机制，非偶发。
- 关键语义：**tmux 客户端的 socket 选择 = `$TMUX` 句柄（已连接时）或 TMUX_TMPDIR/TMPDIR 解析（裸调用时）；夹具隔离若依赖改 TMUX_TMPDIR，会污染任何基于 TMUX_TMPDIR 的守卫判定。**

## 决策

1. `prod_sock_candidates` 的默认 socket 候选 = **$TMUX 句柄**（`${TMUX%%,*}`，去 `,pid,idx` 后缀）+ **常量** `/tmp/tmux-<uid>/default` + `${TMPDIR:-/tmp}/tmux-<uid>/default`；**不读取、不派生自 TMUX_TMPDIR**。恒含常量 ⇒ 候选表永不空。
2. 回归脚本护栏用**同一常量独立复算**（双保险，互不依赖），夹具 SOCK 与候选冲突或不在 `$LAB` 下 ⇒ exit 3。
3. 纪律升级：夹具一律 `env -u TMUX` + `-S <隔离 socket>`；验证脚本勿在承载自己会话的 tmux 内执行（清 `TMUX_PANE` 令 F1 自 pane 闸门失效）。

## 理由（四步法）

- 业务匹配：守卫要防的是「夹具清理误伤生产名册所在 server」；生产默认 socket 的最稳健事实源 = 连入句柄（$TMUX）+ tmux 固定的 uid 默认布局常量。TMUX_TMPDIR 是**可变污染面**（夹具可设），不能进判定。
- 技术成熟：tmux 3.7c 实测 `-S <自定义路径>` kill-server 不卸载 socket 文件（幂等兜底需 `ls` 探测 + 残留清除）；客户端「$TMUX 已设时无视 TMUX_TMPDIR」为实测语义。
- 团队/成本：改动局部（1 个函数 + 脚本护栏），风险仅「更保守」（误拒方向，exit 2 显式报错），无「误放行」方向的新增。

## 对照过的备选模式（含不采纳理由）

| 模式 | 条件 | 代价 | 结论 |
| :-- | :-- | :-- | :-- |
| 维持 TMUX_TMPDIR 派生判定 | — | 17:11 事故即其产物：夹具设 TMUX_TMPDIR ⇒ 真默认 socket 被放行连坐 | **不采纳**（根因） |
| 仅 $TMUX 句柄 + 常量 /tmp/tmux-<uid>/default | 标准布局 | 自定义 TMUX_TMPDIR 生产布局不在守卫内（裸调用时不可判） | **采纳**（标准布局全覆盖；非标准布局靠纪律兜底，已记录为已知边界） |
| $TMUX 句柄 + 常量 + $TMPDIR 变体 | TMPDIR 通常=/tmp | 夹具恰放 $TMPDIR 变体路径会被保守误拒（exit 2 显式） | **采纳**（安全方向保守；误拒可显式诊断） |
| 路径归一化（readlink -f）后比对 | 防符号链接/`//` 绕过 | 一行成本；正常纪律不产生该输入 | **可选加固**（未达阻碍级） |

## 已知边界

- 生产侧自定义 TMUX_TMPDIR 启动（非标准布局）且裸（无 $TMUX）调用 cleanup 时，守卫无法推知该布局 —— 不可判定，靠纪律「夹具 socket 须区别于生产候选」+ 脚本护栏常量兜底。
- screen 宿主侧 `-X quit` 前缀残留为独立缺陷（见 arch 评审报告 F1/F2，不看本 ADR 放行）。

## 参考来源

- RD/QA/arch 三方复跑记录：`docs/reports/2026-10-13-T516-arch-review.md`（评审·复跑 18/18）· `docs/reports/2026-10-13-T516-qa-report.md`（QA · 18/18 + AC9×3）· tasks-state（RD t4 11/11 · 348/348）
- T515 取证：`docs/reports/2026-10-13-T515-forensics.md` · `docs/reports/2026-10-13-T515-mechanism-bug-hunt.md`
- tmux 手册（socket 选择/$TMUX 语义）与 3.7c 实测（2026-10-13 本机）