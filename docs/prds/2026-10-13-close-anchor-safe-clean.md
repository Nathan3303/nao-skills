# T516 PRD：close 会话名精确锚定 + 实验场安全清理入口

- **日期**：2026-10-13 · **实施**：rd-infra（单波）· **评审**：arch（close 家族语义敏感）· **载体 Issue**：#29
- **版本**：**0.16.0**（MINOR：#1 为缺陷修，#2 新增安全清理入口能力）
- **依据**：T515 报告缺陷 #1/#2（`docs/reports/2026-10-13-T515-mechanism-bug-hunt.md`）· 用户 2026-10-13 拍板开批（「开」）

## TL;DR

- **做什么**：修 close/status 的会话名**唯一前缀误命中**（一律 `=nao-<名>` 精确锚定）；新增**实验场安全清理入口**（显式 `-S` socket、默认 socket 拒绝）；同步纪律文档与帮助文案。
- **给谁**：机制使用与维护者（多会话/多仓/夹具实验场景）。
- **成功标准**：status 不再把派生误计在线；close 不再静默误回收派生并谎报成功；既有精确回收与派生回收（`--task`）全部不回退。
- **不做什么**：不做 T515 #3（F1 跨 server 撞号）/ #4（回执 repo 误导）；不重构 close 定位链；不变更宿主阶梯。

## 一、问题证据

- T515 V4 实验复现（正反对照均验）：`has-session/kill-session -t nao-<名>` 在精确会话缺席、派生 `nao-<名>-<task>` 在场时误命中 ⇒ status 误报「在线」+ close 静默回收派生并谎报成功。
- T515 两次 rd-infra 自灭实证：裸 `tmux kill-server` 连坐真 server（`$TMUX` 已设时 TMUX_TMPDIR 被无视）；fleet 无安全清理入口，纪律无载体。

## 二、业务规则（不变量）

- close 以 intercom 名册为权威在线判定（既有口径不变）。
- 自安全：close 对自 pane 的 F1 闸门行为不变。
- 派生会话命名 `nao-<角色>-<任务>`；常驻 `nao-<角色>`。**名字锚定后二者不再互通误命**。
- 实验夹具纪律：**一律 `env -u TMUX` + `-S <socket>`**；默认 socket 是生产名册所在，任何清理命令不得默认打到它。

## 三、验收标准（AC）

- **AC1**：Given 常驻名精确会话缺席、仅派生 `nao-<名>-<任务>` 在场，When `status`，Then 常驻报「未运行（ensure 拉起）」，派生不误计入常驻在线。
- **AC2**：Given 精常驻会话在场，When `close <别名>`，Then 照常回收成功（既有能力零回退）。
- **AC3**：Given 精确缺席 + 仅派生在场，When `close <常驻名>`，Then **非 0 退出 + 诊断**（不得静默谎报），派生会话存活。
- **AC4**：Given 派生会话显式回收（`close --task <任务> <别名>` / 直接派生名），Then 派生会话正确回收（既有能力零回退）。
- **AC5**：Given 安全清理入口，When 以 `-S <socket>` 清理夹具 server，Then 该 server 终结 rc=0；When 不带 `-S` 面向默认 socket，Then **exit 2 + 单行拒绝**，真 server 不受影响。
- **AC6**：`--help` 含清理入口用法与实验纪律一行（`env -u TMUX` + `-S`）。
- **AC7**：门禁全绿：`check` rc0 roles=6；t4 全集 0 红（RD 复跑给精确数字）。
- **AC8**：新负向用例覆盖 AC1/AC3/AC5 三处（T515 的正反对照场景固化为回归用例）。
- **AC9**：T513 既有验收口径不回退（AC14 连跑 3 次一致）。
- **AC10**：main 恰 1 条 squash 提交、无 `wip()`、分支删净。

## 四、范围 / 非范围

- **D2 已拍板（2026-10-13）**：**A·子命令 + 守卫**——fleet 新增实验场安全清理子命令：强制显式 socket（`-S`）；默认 socket 直接拒绝（exit 2 + 单行文案）；文档纪律一并落。
- **做**：`nao-fleet.sh` 内 status/close（含派生判定与名册解析）tooltip 会话名的锚定统一收敛到 `=nao-<名>` 形态；新增清理子命令（形态 A）；`--help`/相关纪律文档同步；版本 0.16.0。
- **不做**：T515 #3/#4；`bin/nao-skill.js`/迁移逻辑；宿主阶梯；下游三仓；历史归档。
- 版本/发布：tag + Release 由 PM 验收后执行；npm publish 待用户。

## 五、上线闭环

- 无灰度；监控 = Issues；回滚 = revert + 0.16.1。
- 实施期间 rd-infra 自用实验一律按 §二 纪律执行（T515 教训写进本 PRD 作为硬约束）。

## 六、变更治理

- 用户 2026-10-13 口头决策已落盘（本 PRD + tasks-state）。
- T515 报告与 forensics 为本批复现/回归基线资产。

## 七、事故补录（2026-10-13 17:11，AC8 负向用例自伤）

- **现象**：AC8 回归脚本跑至 AC5e 时杀掉**调用者自己的 tmux server**（终端显示 server exited，调用进程随 SIGHUP 消失）；AC5a 同时恒拒（rc=2）。现场：夹具 server 存活（keeper+sleep 桩）＝AC5a 从未成功；真 socket mtime 落后重建时间＝真 server 已被杀。
- **真因**：`cmd_cleanup` 的「默认 socket」判定取 `${TMUX_TMPDIR:-/tmp}/tmux-<uid>/default`，而 `run_fleet()` 为隔离把 `TMUX_TMPDIR` 指向夹具目录 ⇒ 夹具 socket 被误判为默认（AC5a 恒拒）、**真默认 socket 被误判为非默认**（AC5e 放行后 `kill-server` 连坐）。纪律（env -u TMUX + -S）拦不住——这是 T515 I1「夹具误杀」的**精确机制**，非偶发。
- **修**：① `prod_sock_candidates`：默认 socket 判定 = `$TMUX` 句柄 + `/tmp/tmux-<uid>/default`（+`$TMPDIR` 变体），**与 TMUX_TMPDIR 无关**，恒含常量不空表；② AC8 脚本护栏（exit 3）：夹具 SOCK 与生产候选冲突或不在 `$LAB` 下即拒，同常量独立复算；③ 纪律补「验证脚本勿在承载自己会话的 tmux 内执行（清 TMUX_PANE 令 F1 自 pane 闸门失效）」。
- **影响**：AC5/AC8 措辞改「生产默认 socket」；`check` 守卫无 cleanup 断言，不受影响；未发布（0.16.0 未 tag），无历史债。
- **范围修正（同日 · t4 2 红后裁定）**：`=` 锚定**只收敛到匹配类路径**（`running()`/status、`cmd_close`、`has-session`/`kill-session`/`list-clients`、screen 锚、cleanup）。`spawn_tmux` 的日志文案与 `spawn_tmux_attach` 传给窗口桩的 `attach -t` argv **两处回退**为 `nao-<名>`：① §四「做」未含 spawn/attach；② `tmux attach` 的目标由 `new-session -d -s nao-<名>` 刚建、精确名优先命中，无需 `=`（无 #1 前缀误命风险）；③ 保 T513 冻结断言 `attach -t nao-qa`（t4 case 11 / AC7+AC9 口径不回退）。**裁定：PM（方案 A）**，arch 于 PR 复核。
- **arch 评审 F2 处置（同日 · 中严重度未签）**：`cmd_close` screen 销毁（L1539）与 `spawn_screen` 失败清理（L1001）的 `screen -S nao-<名> -X quit` **仍为前缀目标**（检测已锚、销毁未锚）⇒ 同批修：按 `screen -ls` 锚定行取 `pid.name` 精确令牌再 quit，取不到即不 quit（宁不回收不误伤）；F1（低）同源同修。顺带 `cleanup` 比对前 `readlink -f` 归一化（F3-B3 低，堵符号链接绕过）。**ADR `docs/adr/2026-10-13-close-anchor-cleanup-guard.md` 并入本 PR**。screen 侧行为用例由 qa 以 **PATH 注入 stub `screen`** 覆盖（本机无 screen 二进制，无法runtime 实测）。裁定：PM。
