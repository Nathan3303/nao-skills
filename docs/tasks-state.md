# 任务状态（PM 维护，运行时事实）

> 每次派发 / 回执 / 验收 / 抢占后更新本文件；PM 会话重开（`ensure --force`）后**先读本文件重建状态**再继续调度。
> 历史见 `docs/tasks-archive.md`；权威来源 = `docs/prds/` 与 `docs/releases/`；本文件只记**运行时**状态，保持精简。
> 归档动作 = 从「进行中」**删除** + 归档墙**新增**（同一 id 同时出现在两处会因 `arch` 优先被判 **`closed`**，`close` 闸门保护静默消失）。


> **结构（T580 起）**：`## 批次索引` 一行对应一条归档批次；**活批次**各自一个 `## <任务号> · <slug>` 段，内含 6 列卡摘要表；任务进入 `已合并`/`已发布`/`已关闭` ⇒ **完成即收**：删摘要行，只留索引一行（`kickoff.md` 本体保留）。
> 正文（字段集 / 表头 / 状态值域 / 完成即收 / 归档规则）单源：`.agents/checklists/deliverable-docs.md` §十一；`check` 的台账探针 warn-only，「删一行必须红」由 `tests/t4/cases/54` 承载。

## 批次索引（已完成批次 → 归档锚点）

| 任务号 | 归档锚点 | 状态 | 完成日期 |
| :--- | :--- | :--- | :--- |
| T597 | `docs/tasks-archive.md#T597` | 已合并 | 2026-11-28 |
| T583 | `docs/tasks-archive.md#T583` | 已合并 | 2026-11-28 |
| T595 | `docs/tasks-archive.md#T595` | 已发布 | 2026-11-28 |
| T596 | `docs/tasks-archive.md#T596` | 已发布 | 2026-11-28 |
| T586 | `docs/tasks-archive.md#T586` | 已发布 | 2026-11-28 |
| T589 | `docs/tasks-archive.md#T589` | 已发布 | 2026-11-28 |
| T582 | `docs/tasks-archive.md#T582` | 已发布 | 2026-11-28 |
| T592 | `docs/tasks-archive.md#T592` | 已发布 | 2026-11-28 |
| T584 | `docs/tasks-archive.md#T584` | 已发布 | 2026-11-28 |
| T591 | `docs/tasks-archive.md#T591` | 已发布 | 2026-11-28 |
| T593 | `docs/tasks-archive.md#T593` | 已发布 | 2026-11-28 |
| T594 | `docs/tasks-archive.md#T594` | 已发布 | 2026-11-27 |
| T590 | `docs/tasks-archive.md#T590` | 已发布 | 2026-11-27 |
| T588 | `docs/tasks-archive.md#T588` | 已发布 | 2026-11-27 |
| T587 | `docs/tasks-archive.md#T587` | 已发布 | 2026-11-27 |
| T585 | `docs/tasks-archive.md#T585` | 已发布 | 2026-11-27 |
| T580 | `docs/tasks-archive.md#T580` | 已发布 | 2026-11-27 |
| T579 | `docs/tasks-archive.md#T579` | 已发布 | 2026-11-27 |
| T581 | `docs/tasks-archive.md#T581` | 已发布 | 2026-11-27 |
| I96 | `docs/tasks-archive.md#I96` | 已发布 | 2026-11-11 |
| M20261109-queue-slim | `docs/tasks-archive.md#M20261109-queue-slim` | 已关闭 | 2026-11-09 |
| I93 | `docs/tasks-archive.md#I93` | 已关闭 | 2026-11-09 |
| M20261107-discipline-doc | `docs/tasks-archive.md#M20261107-discipline-doc` | 已合并 | 2026-11-07 |
| I90 | `docs/tasks-archive.md#I90` | 已合并 | 2026-11-06 |
| I88 | `docs/tasks-archive.md#I88` | 已合并 | 2026-11-06 |
| HIST-01 | `docs/tasks-archive.md#HIST-01` | 已关闭 | 2026-11-06 |
| HIST-02 | `docs/tasks-archive.md#HIST-02` | 已关闭 | 2026-11-18 |
| HIST-03 | `docs/tasks-archive.md#HIST-03` | 已关闭 | 2026-11-18 |
| T543 | `docs/tasks-archive.md#T543` | 已关闭 | 2026-11-18 |
| T547 | `docs/tasks-archive.md#T547` | 已合并 | 2026-11-17 |
| HIST-04 | `docs/tasks-archive.md#HIST-04` | 已关闭 | 2026-11-17 |
| HIST-05 | `docs/tasks-archive.md#HIST-05` | 已关闭 | 2026-11-17 |
| T546 | `docs/tasks-archive.md#T546` | 已合并 | 2026-11-17 |
| HIST-06 | `docs/tasks-archive.md#HIST-06` | 已关闭 | 2026-11-06 |
| I86 | `docs/tasks-archive.md#I86` | 已合并 | 2026-11-05 |
| I84 | `docs/tasks-archive.md#I84` | 已合并 | 2026-11-05 |
| I82 | `docs/tasks-archive.md#I82` | 已合并 | 2026-11-05 |
| T538 | `docs/tasks-archive.md#T538` | 已关闭 | 2026-11-05 |
| I79 | `docs/tasks-archive.md#I79` | 已合并 | 2026-11-03 |
| HIST-07 | `docs/tasks-archive.md#HIST-07` | 已关闭 | 2026-11-03 |
| I77 | `docs/tasks-archive.md#I77` | 已合并 | 2026-11-03 |
| I75 | `docs/tasks-archive.md#I75` | 已关闭 | 2026-11-03 |
| M20261103-update-check | `docs/tasks-archive.md#M20261103-update-check` | 已合并 | 2026-11-03 |
| M20261103-fix-channel | `docs/tasks-archive.md#M20261103-fix-channel` | 已合并 | 2026-11-03 |
| M20261103-readme-polish | `docs/tasks-archive.md#M20261103-readme-polish` | 已合并 | 2026-11-03 |
| M20261103-readme-refresh | `docs/tasks-archive.md#M20261103-readme-refresh` | 已合并 | 2026-11-03 |
| T539 | `docs/tasks-archive.md#T539` | 已合并 | 2026-11-02 |
| T533 | `docs/tasks-archive.md#T533` | 已关闭 | 2026-11-02 |
| T535 | `docs/tasks-archive.md#T535` | 已关闭 | 2026-11-02 |
| M20261101-status-pane-cwd-key | `docs/tasks-archive.md#M20261101-status-pane-cwd-key` | 已关闭 | 2026-11-01 |
| T537 | `docs/tasks-archive.md#T537` | 已关闭 | 2026-11-01 |
| T567 | `docs/tasks-archive.md#T567` | 已关闭 | 2026-11-25 |
| T568 | `docs/tasks-archive.md#T568` | 已关闭 | 2026-11-25 |
| HIST-08 | `docs/tasks-archive.md#HIST-08` | 已合并 | 2026-11-24 |
| T555 | `docs/tasks-archive.md#T555` | 已关闭 | 2026-11-23 |
| T563 | `docs/tasks-archive.md#T563` | 已合并 | 2026-11-24 |
| I121 | `docs/tasks-archive.md#I121` | 已关闭 | 2026-11-14 |
| HIST-09 | `docs/tasks-archive.md#HIST-09` | 已关闭 | 2026-11-14 |
| M20261114-t4-cache | `docs/tasks-archive.md#M20261114-t4-cache` | 已关闭 | 2026-11-14 |
| M20261113-cleanup-checklist | `docs/tasks-archive.md#M20261113-cleanup-checklist` | 已关闭 | 2026-11-13 |
| HIST-10 | `docs/tasks-archive.md#HIST-10` | 已关闭 | 2026-11-13 |
| M20261113-gate-source | `docs/tasks-archive.md#M20261113-gate-source` | 已关闭 | 2026-11-13 |
| HIST-11 | `docs/tasks-archive.md#HIST-11` | 已关闭 | 2026-11-14 |
| I118 | `docs/tasks-archive.md#I118` | 已关闭 | 2026-11-13 |
| T544 | `docs/tasks-archive.md#T544` | 已合并 | 2026-11-13 |
| HIST-12 | `docs/tasks-archive.md#HIST-12` | 已关闭 | 2026-11-13 |
| HIST-13 | `docs/tasks-archive.md#HIST-13` | 已关闭 | — |
| T542 | `docs/tasks-archive.md#T542` | 已发布 | 2026-11-13 |
| HIST-14 | `docs/tasks-archive.md#HIST-14` | 已关闭 | 2026-11-13 |
| T541 | `docs/tasks-archive.md#T541` | 已关闭 | 2026-11-13 |
| I109 | `docs/tasks-archive.md#I109` | 已关闭 | 2026-11-13 |
| T545 | `docs/tasks-archive.md#T545` | 已关闭 | 2026-11-13 |
| HIST-15 | `docs/tasks-archive.md#HIST-15` | 已关闭 | 2026-11-13 |
| T536 | `docs/tasks-archive.md#T536` | 已关闭 | 2026-11-01 |
| HIST-16 | `docs/tasks-archive.md#HIST-16` | 已关闭 | — |
| T534 | `docs/tasks-archive.md#T534` | 已关闭 | 2026-10-31 |
| HIST-17 | `docs/tasks-archive.md#HIST-17` | 已关闭 | — |
| T532 | `docs/tasks-archive.md#T532` | 已合并 | 2026-10-28 |
| HIST-18 | `docs/tasks-archive.md#HIST-18` | 已关闭 | — |
| T530 | `docs/tasks-archive.md#T530` | 已关闭 | 2026-10-28 |
| T531 | `docs/tasks-archive.md#T531` | 已合并 | 2026-10-28 |
| T529 | `docs/tasks-archive.md#T529` | 已关闭 | 2026-10-28 |
| T528 | `docs/tasks-archive.md#T528` | 已关闭 | 2026-10-27 |
| T527 | `docs/tasks-archive.md#T527` | 已合并 | 2026-10-27 |
| T526 | `docs/tasks-archive.md#T526` | 已发布 | 2026-10-14 |
| T525 | `docs/tasks-archive.md#T525` | 已关闭 | 2026-10-14 |
| T524 | `docs/tasks-archive.md#T524` | 已关闭 | 2026-10-14 |
| T523 | `docs/tasks-archive.md#T523` | 已关闭 | 2026-10-14 |
| T522 | `docs/tasks-archive.md#T522` | 已关闭 | 2026-10-14 |
| T521 | `docs/tasks-archive.md#T521` | 已关闭 | 2026-10-14 |
| T520 | `docs/tasks-archive.md#T520` | 已关闭 | 2026-10-14 |
| HIST-19 | `docs/tasks-archive.md#HIST-19` | 已关闭 | 2026-11-11 |
| HIST-20 | `docs/tasks-archive.md#HIST-20` | 已关闭 | 2026-11-02 |
| T512 | `docs/tasks-archive.md#T512` | 已关闭 | 2026-10-14 |
| M20261014-F1 | `docs/tasks-archive.md#M20261014-F1` | 已关闭 | 2026-11-14 |
| HIST-21 | `docs/tasks-archive.md#HIST-21` | 已关闭 | — |
| T548 | `docs/tasks-archive.md#T548` | 已合并 | 2026-11-17 |
| T549 | `docs/tasks-archive.md#T549` | 已合并 | 2026-11-18 |
| M20261118-card-trim | `docs/tasks-archive.md#M20261118-card-trim` | 已合并 | 2026-11-18 |
| M20261118-prd-structure | `docs/tasks-archive.md#M20261118-prd-structure` | 已合并 | 2026-11-18 |
| M20261118-test-hygiene | `docs/tasks-archive.md#M20261118-test-hygiene` | 已合并 | 2026-11-18 |
| T551 | `docs/tasks-archive.md#T551` | 已合并 | 2026-11-18 |
| HIST-22 | `docs/tasks-archive.md#HIST-22` | 已关闭 | — |
| T553 | `docs/tasks-archive.md#T553` | 已关闭 | 2026-11-20 |
| T552 | `docs/tasks-archive.md#T552` | 已关闭 | 2026-11-19 |
| T562 | `docs/tasks-archive.md#T562` | 已合并 | 2026-11-24 |
| T564 | `docs/tasks-archive.md#T564` | 已关闭 | 2026-11-24 |
| T559 | `docs/tasks-archive.md#T559` | 已关闭 | 2026-11-23 |
| T560 | `docs/tasks-archive.md#T560` | 已关闭 | 2026-11-20 |
| T561 | `docs/tasks-archive.md#T561` | 已关闭 | 2026-11-20 |
| T557 | `docs/tasks-archive.md#T557` | 已关闭 | 2026-11-23 |
| T558 | `docs/tasks-archive.md#T558` | 已关闭 | — |
| T554 | `docs/tasks-archive.md#T554` | 已关闭 | 2026-11-20 |
| M20261116-final-audit | `docs/tasks-archive.md#M20261116-final-audit` | 已关闭 | — |
| M20261116-backlog-sweep | `docs/tasks-archive.md#M20261116-backlog-sweep` | 已关闭 | 2027-02-14 |
| I128 | `docs/tasks-archive.md#I128` | 已关闭 | 2026-11-15 |
| I126 | `docs/tasks-archive.md#I126` | 已关闭 | — |
| I124 | `docs/tasks-archive.md#I124` | 已关闭 | — |
| I123 | `docs/tasks-archive.md#I123` | 已关闭 | 2026-11-14 |

## 活约束与遗留跟踪（长期有效 · 不下沉）

- 待用户裁量的后续项（均不阻塞、**未开单**）：① **O1** nao-todo `AGENTS.md:131` 仍把 `.nao-migrated` 列为「0.12.0 起入库面」→ 收敛 ② ✅ **B8 接受（2026-11-25 · 不改）** —— `close` 同名跨仓不可定向：现状已是 fail-closed + 指路，T551/T552 已明确裁定「同名多仓不猜」是**设计**；加定向会推翻既定决策，收益仅「少复制一条命令」⇒ 维持现状，靠使用纪律（仓级唯一任务号）覆盖③ **D6** `failWarn` 文案措辞（PRD §8.1）④ ✅ **B1 已做（2026-11-25）** —— 迁移/初始化新增 `--dry-run` 预演（清单逐条 + 盘面零写入 + 与 `--force` 互斥 + 清单==真跑动作）；仍按目录名判定，`docs/INSTALL.md` 已写已知边界⑤ 三仓 `.agents/.nao-version` 仍 `0.12.0`（0.13.0 无读取方，版本权威 = pin）⑥ ✅ **已收口（T525 / v0.18.3）** —— `subagent-*` 已显式排除：`status` 只汇总计数（不列名）· `close subagent-*` 显式拒绝且不触 pane（父 pane 存活）· E2 孤儿 pane 告警回归 · `check` 保留前缀校验 · 新增用例 15（T1–T10）。⑦ ✅ **已收口（T526 / v0.18.4）** —— nao 版桥指令模板 + 协议「会话内子代理（授权与回执归属）」小节 + 只读探针 `cases/16`。**关键更正**：T512「自动桥整条死」的前提**在 pi-subagents 0.78.0 已过期**（零配置下 `bridge: active` · `mode: always` · target = 父会话名；`subagent_supervisor`/`contact_supervisor` 均不依赖 pi-intercom）⇒ 本批实际补的是 **G1 回执归属 / G2 身份禁令 / G3 证据契约** 三个语义差距。⑧ ✅ **T512-③ 已收口（0.18.5）** —— `.agents/extensions/nao-role-agents.mjs` 在 `session_start` 注册 6 张角色卡为 `nao-<role-id>` agent（nao-todo AGENTS.md 同记）⑨ **T512 附录** pi-subagents 引入目标流程 A/B —— **无动作**（报告附录已标「候选 · 未立项 · 未落地」）⑩ **宿主检测 ⇒ 已交付（T513 / 0.14.0，见上）**；原问题：`detect_host` 不识别 foot / Hyprland；用户 2026-10-12 拍 **D1–D5**（D1 默认开可见窗口 · D2 非 tmux 宿主 close 支持 / status turn 判定明确降级 · D3 tmux 内仍优先 · D4 无图形会话必须显式 `--background` 否则 exit 2 · **D5 tmux 可用但当前不在 tmux 时可用 tmux，但必须前台可见、禁静默后台会话**）。**D5 使阶梯③保留完整 tmux 句柄 ⇒ 回归面大幅缩小**。P3/P4 已实测（127 裸中断 / rc0 假成功）。PRD：`docs/prds/2026-10-12-non-tmux-host-spawn.md`。⑪ ✅ **npm 发布已执行（2026-10-13）**：只发 `0.16.0`（`latest → 0.16.0`，不补发 0.12.1–0.15.0）· 用户执行 · 已验 tarball sha512 与 dist.integrity 一致。 ⑫ **`nao-fleet.sh` 体量与职责混装**（**`4326` 行 / `136` 函数 / `cmd_check` 281 行**（as-of 2026-11-15 · 本批 HEAD 实测；⚠️ **数字必漂 ⇒ 一律以命令为准**：`wc -l < .agents/scripts/nao-fleet.sh` · `grep -cE '^[a-zA-Z_][A-Za-z0-9_]*\(\) *\{' .agents/scripts/nao-fleet.sh` · `awk '/^cmd_check\(\)/{s=NR} s&&/^}$/{print NR-s+1; exit}' .agents/scripts/nao-fleet.sh`（现 281）；历史：1874/72/228（2026-10）· 4298/135/277（`705fd69`），均过期） · 占机制文本 58.6%）—— **「`tests/t4` 未接入 `npm test`」半条已收口（T522 / v0.18.0）**：t4 已串入 `npm test` + 默认严格 + `test:t4:full` 发布前置（见 `docs/releases/v0.18.0.md`）；**脚本拆分/减重半条保留**（仍未立项，待 arch 评审后再议）。**新增待裁量项**：⑭ ✅ **已收口（T523 / v0.18.1）** —— `close` 末段「无法确认在线状态」静默语义已有回归护栏（新增用例 13 · 6 组 15 条双侧断言 · 三变异均被拦）；⑮ ✅ **已收口（T524 / v0.18.2）** —— `/tmp/nao-t4.*` 存量 129 → **0**，且新增自洽生命周期（成功即清 / 失败保留 / 用户目录永不删 / 只读命令不建目录 / `mktemp` 失败非 0）。· ⑯ ✅ **已收口（T524 / v0.18.2）** —— `nao-fleet.sh:1676` 已删净「或用 `--force` 跳过闸门」（用例 13 双向断言钉住）。· ⑰ ✅ **npm 0.18.2 重发已核验（2026-10-14 · 用户执行）**：`dist-tags.latest = 0.18.2` + `dist.integrity` 与本地 `npm pack` tarball **逐字节一致**（`sha512-pXgAgzq…` · 129,985 B）—— 发布→元数据可见约 2 分钟延迟、tarball 再延约 2–3 分钟（本次实测），**早于此刻的 404 属预期**。⑲ ✅ **npm 0.18.3 重发已核验（2026-10-14 · 用户执行）**：`latest = 0.18.3` + `dist.integrity` 与本地 tarball **逐字节一致**（`sha512-UjGFdSG…` · 131,465 B）—— 节奏同前（元数据约 2 分钟、tarball 随后）。⑳ ✅ **npm 0.18.4 重发已核验（2026-10-14 · 用户执行）**：`latest = 0.18.4` + `dist.integrity` 与本地 tarball **逐字节一致**（`sha512-rzP9tuEu…` · 134,484 B）—— 本次实测**落地很快**（元数据与 tarball 首次查询即得，无延迟）。**观察项 O-1（非缺陷）**：连续跑批可能出现**负载性 SKIP**（用例 02 真 `pi` 启动 rc=124 超时 · 用例 07 registry 不可达；该次 rc=0 · 用例 13 仍 PASS，空载单独复跑均 PASS）⇒ **发布判据须空载跑 `npm run test:t4:full``。**观察项 O-2（T526 发布期实测 · 非缺陷）**：v0.18.4 发布前置闸门首跑出现 **case 11（T513 冻结实体）AC12 F1- 两条断言 FAIL**（`rc=1（期望 0；正常路径被 F1 闸门误伤）` + `未命中 %42`），**同环境立即单跑 `--case 11` rc=0**、**空载重跑全量 rc=0**（1m34s）⇒ 属**负载/时序偶发**（夹具会话/ pane 定位竞态），非回归；失败证据保留于 `/tmp/nao-t4.KFffxp`（已引用入台账，可清理）。**口径**：发布前置闸门遇 FAIL 必须**先复现单例再重跑全量**，不得直接放行。 ⑬ ✅ **npm 0.17.3 重发已核验（2026-10-14 · 用户执行）**：`dist-tags.latest = 0.17.3` + `dist.integrity` 与本地 `npm pack` tarball 逐字节一致（`sha512-xKitNAZbPhphS+…`）。
- 既定口径（长期有效）：**README 视角 = 纯舰队机制，不写具体上下游应用信息（应用仓名/迁移操作细节不入 README；用户 2026-10-13 拍板，已删除「下游仓库迁移」节并中和泛化措辞）**；迁移命令从**仓外**执行；`.pi/settings.json` pin 入库；`.agents/.nao-obsolete/` 加 gitignore；迁移判据 = 机制类归零 + 自有资产保留；历史归档文档不改；不碰源码/测试/构建配置
- **PM 交互约定（用户 2026-10-14 拍板，长期有效）**：**需要用户确认 / 拍板的问题一律用 `ask-me` 提问**（不用自由文本提问）；本约定写入项目 `AGENTS.md` 项目约束（T518 范围内）。
- ⚠️ **合并纪律（T511 教训，已落 `.agents/skills/github-flow.md`）**：PR 只有 1 条提交时 `gh pr merge --squash` 取**该提交 subject**（非 PR 标题）⇒ **必须显式 `--subject "<用户可读主题>"`**，否则 `wip()` 进主干
- ⚠️ **同仓协作纪律**：nao-fleet 本仓工作（如 T509/T510）——RD 持有分支期间 PM 不做本仓 git 写操作；台账提交只在「派发前」「合并后」两个时点
- ⚠️ 环境注意：`nao-fleet.sh` 别名解析已修（0.12.1）· `ensure` 会真拉 pane，未信任目录会停在 pi Trust 提示（D7）· `close` 以 intercom 名册为权威在线判定 · `status` 残留识别要求表格内**裸批次号**单元格
- ⚠️ **本仓 remote（2026-11-09 起）**：origin = `ssh://git@ssh.github.com:443/Nathan3303/nao-fleet.git`。本机实测：`github.com:443`（HTTPS）不通、`github.com:22` 不稳定、**`ssh.github.com:443` 两边都通** ⇒ fetch/pull/push 一律走 SSH-over-443（旧口径「2026-10-13 起改 HTTPS」已作废）。
- ⚠️ **npm 发布教训（v0.16.1 首次 + v0.16.2 首次均中招，同型）**：`npm publish` 若 `~/.npmrc` 的 `_authToken` 无发布权限 ⇒ `PUT 401` → CLI 转浏览器 web auth → **`PUT 202` + `exit 0` + "being processed" = 假成功**，registry 永远无该版本。**成功判据 = 输出出现 `+ nao-fleet@<ver>`**（或几秒后 `npm view ... dist-tags` 已是新版）；修复 = `npm login` 重授权 **或** 换含 Publish 权限的 Granular Access Token（必要时勾 bypass 2FA）。
- 📌 **台账写法约定（T519 订正）**：`status` 残留识别按**单元格全等**匹配 ⇒ 进行中行须有**裸批次号**单元格（如 `T508`）；带后缀单元格（`T508-QA`/`T508-RD`）实测判 **`absent`**（非「仅散文提及」）。
- **通用既定口径（T506 · 留档见 `docs/tasks-archive.md` §9）**：`.pi/*` + `!.pi/settings.json`；迁移判据 = 机制类归零 + 自有资产保留；旧脚本调用改 `$NAO_SKILLS/…`。

### 上游遗留单（**已收敛** · 2026-10-14 刷新）

- **#19 / #21 已闭环**：分别由 **T509（v0.12.1）/ T510（v0.13.0）** 交付，原「待用户确认开工」状态作废（原文见 `docs/tasks-archive.md` §1）。
- 原候选「`close` 跨仓派生会话回收宿主定位假阴性（报「未运行」但 pane 存活）」→ 与「待用户裁量的后续项」**② B8** 重复，已合并登记、不再单列。
- 结论：**当前无待开工的上游遗留单**。

## 待派发队列（真待办 · 需写代码或改文本）

> 下方为手写台账（原队列工具的渲染块已于 2026-11-26 随编排器下线移除，改为手写维护）。

| 任务编号 | 目标会话 | 概要 | 排队原因 |
| :--- | :--- | :--- | :--- |
| **T595-B/F** | `rd-infra` | 多仓命名 B/F 步：label 承载归属（`nao.repo`/`role`/`slot`）+ app 里 `tab.rename` 显示
  `pm · omarchy` | 进行中（B 步）+ 排队（F 步） |
| **T583-C** | `pm` → `rd-infra` → `qa` | T581 C 批：红线重分类（pm 34→18 / 清单 44→38）+ 3 道闸（G1 计数 / G2 ADR 结构 / G3 release notes 编号）+ 补 `uiux-design.md` 清单 | 待派（B 批已合并） |
| **T598** | 待立项 | 槽位扩容 2..99：属命名契约变更（`fleet_core_build`/`parse` + 名长预算 + `cases/28` + 文档） | 按需（当前 2..9 够用） |

> **T556 候选已划销（2026-11-24 · PM）**：目标「舰队机制配合 herdr desktop app」已被 T562（app 第二后端 · 合并 `bc6c0c3` · v0.30.0）与 T565（app 后端放置验证修复 · v0.31.1）交付覆盖 ⇒ 不再单独立项。

> **队列已清空（2026-11-19 · T552 合并闭环）**：`#151` 已随 v0.25.2 合并 `fe96718` 闭环，陈旧行已划销 ⇒ 本表**数据行 = 0**（合法状态，不是漏更新）。其余在做的事见「进行中」。

> **队列已清空（2026-11-16 · M20261116-backlog-sweep）**：批次 A/B/C 与 T543-O2 全部合并闭环，划销行已移除；本表**空 = 无真待办**是合法状态，不是漏更新（判据：本表数据行数 = 0，其余仍在做的事在「进行中」）。历史上本表曾混入「已接受 / 观察 / 已关闭」行（14 行里 9 行不需动作）⇒ 2026-11-09 起纪律：**只放需要动作的项**。
>
> **队列口径（2026-11-09 起，用户提出「怎么越做越多了」后立）**：本表**只放需要动作的项**。「已接受 / 观察等复现 / 定时重评」一律进下一节 —— 那些不是任务，到期看一眼即可，不进待办计数。P3 级问题的默认处置 = **当批修**（#93 起实证：4 项 P3 全当批改、遗留 0；M20261109 批 3 项 P3 全当批收）。**2026-11-10 更新：本表已清空（真待办 0）** —— 最后一条 `T536-O1` 经实测早已由 T539 交付（三态 `0/2/3` + 只有成功分支打印 `[tmux] 已拉起 …` + 摘要三计数；`cases/22` 33 条断言覆盖），属陈旧行，已关闭。

## 观察 / 定时 / 已接受（无需动作 · 到期只回看）

> **准入原则（L2 · 2026-11-14 批次 B 落地）**：本表**只收两类** —— ① **接受项**（明确「不修/不改」，必带**到期日**）② **定时/观察项**（带到期日，到期只看一眼即可判）。**不收**：已在队列里的转办项（转办 ⇒ 队列）· 决策轨迹（改判/立项留痕 ⇒ 写在批次行，另给指针）· 已完成项（⇒ 已归档表）。**每条必须能独立判定**：到期时只需读该行 + 一个命令即可决定关闭/续期，不需要回溯批次行；**真机/人工类无法机械判的**，须显式标「**人工判定型** + 判定要点」，**禁止用恒真或恒假的假命令充当判据**（反例：本条曾写 `grep -c 未验 herdr.txt` = 0 恒真）**处置三出口**：关闭（写证据）· 接受含到期（写理由 + 到期日）· 转办（**必须同时在「待派发队列」出现一行**，本条只留指针）。

| 编号 | 类别 · 到期 | 内容 | 来源 |
| :--- | :--- | :--- | :--- |
| M20261116-pkgver-classified | 观察 · 2027-05-09 | **`#132` 完备性判据会把包版本判「未归类」**（`pi-subagents 0.x` 这类；现仓 0 命中）。处置口径已定（写 `≥` 或加「截至」），到期回看是否需要开特例。判定命令：`grep -rnE "pi-[a-z]+[[:space:]]+[0-9]+\.[0-9]+" $(git ls-files "*.md" \| grep -vE "^docs/(adr\|prds\|releases\|reports)/")` | 批次 E QA P3-3(c) |
| M20261028-F5 | 定时 · 2026-12-28 | **到期重评** 插件 0.1.0 × CLI 1.6.2 版本耦合（工具集合/行为无版本承诺）；期间观察上游 | 定时：**2026-12-28** |
| M20261014-F1 | 定时 · **续期 2027-02-14** | `pi-ask-me` 旧 SDK 子树 12 high（已接受）。**2026-11-16 复核**：上游仍 **0.1.1**（`npm view pi-ask-me version`），8 个月未发版 ⇒ 续期，期间观察上游升版；台账 `docs/reports/M20261014-pi-ext-update-followups.md` | 定时项续期 |
| M20261102-F1 | 观察 · 2026-12-31 | **`check` 对 legacy 全量安装的同名机制卡副本跳过冲突检查**（T537 RD 范围外稳健性增补）：跳过逻辑若过宽，会漏报「下游卡与机制卡同名」这类人为异常；首次真实使用后决定是否文档化/加断言 | T537 观察项（PM 登记） |
| M20261102-F2 | 观察 · 2026-12-31 | **`test:t4:full` 用例 02 真 `pi` 动态注册超时 flake**：RD 一次 5 跑中 2 次 `rc=124`（`timeout 120`，stdout 已出 82,900 B，非无凭据）；同批 QA 7 次运行（full ×3 + `--case 02` ×3 + `npm test` ×1）全 PASS、单跑 8–15 s ⇒ 量级差约 10× = 既有 O-1 类网络/负载抖动，非代码引入。候选处置：超时上调 /「真 pi 慢」与「无凭据」分开计数，独立任务做 | RD 转办（M20261102 报告 §四）· **复现率 ≈20 跑 3 次 ≈15%**（RD 5 跑 2 · QA 7 跑 0 + 本轮 2 跑 1 · PM 2 跑 0）⇒ 升级待派发候选 |
| M20261109-install-scripts | 已接受 · 2027-05-09 | **`pi update --extensions` 报 3 条 install-scripts 未授权**（`protobufjs@1.6.6`/`1.6.5` postinstall 生成代码、`@google/genai@1.52.0` preinstall 为 no-op）：均为上游依赖脚本，`pi-subagents` 功能实测正常 ⇒ **不 approve**（维持默认安全姿态），到期动作 = 若 pi-subagents 出异常再回看 | PM 裁决（2026-11-09，用户报障输出） |
| T552-asym | 接受 · 2027-05-09 | **`close` 两条入口对「名册同 cwd 重复条目」非对称**（T552 明示设计）：全名分支去重后**采用**（用户显式键）；裸名分支去重后**仍 die**（只修文案）。理由 = 裸名多一层「本仓同名多 pane」风险，采用会走到句柄层而 tmux 按标题取首条 = 猜（T551 要堵的形态）。判定要点：到期回看是否已把「同名多 pane」在 fleet 层做成显式拒绝（若已做 ⇒ 两分支可统一为采用）| T552 判据 v3 · `docs/reports/151-lite-spec.md` §二 |
| T555-legacy-lint | 接受 · 2026-12-31 | **`t4_scan_term_bare_calls` 第 2 参与 `fixtures/term-legacy-allowlist.txt`（baseline 0 条）单后端后已成壳**：本批不删（避免同批既删后端又删 lint 的连带面）。到期动作 = 若 allowlist 仍 0 条 ⇒ 删该参数与夹具 + `cases/06` 对应 4 条负控 | T555 实施回执 · `docs/reports/555-impl-rd-infra.md` |
| T552-nits | 观察 · 2027-05-09 | **`cases/38` 两处弱耦合**（QA 终检 P3，均自曝不假绿）：① m 态「不说『N 个仓』」是对**全输出**的子串扫描，日后别的路径打印「个仓」会假红；② 负控⑦ 锚落在 `_term_herdr_reclaim` 文案上，该文案合法改写会让 38 红（自检点名「锚未命中」）。判定要点：到期回看 38 是否已改用结构化判据（如 JSON 字段）而非子串 | T552 QA 报告 §追加二 |
| T551-R2R6 | 接受 · 2027-05-09 | **`close` 裸名归属的两个既有边界**（T551/#146 三态决策留下的，非回归）：① **R2** 名册条目缺 `cwd` 时该条目对仓过滤不可见（`intercom_roster` 逐行 awk 需 name/cwd 成对）；② **R6** herdr 后端 + 名册缺该名 `cwd` ⇒ 采用候选后 repo 无法校正，仍可能报「未运行（无需回收）」rc=0。**明示不修**：R2 只能靠 pane cwd 兜底，而 arch 否定条件明禁「pane cwd 充当名册唯一判据」（第二事实源）；R6 只能把 0 命中改 die ⇒ 破 D1/⑤ 兼容面（旧会话将不可回收）。判定要点：到期回看 herdr 名册是否已稳定给出 `cwd`（有 ⇒ 两条同时失效）| T551 QA 报告 §八 · v0.25.1 |
| T545-O1 | 接受 · 2027-01-31 | **卡会话跨仓同 core 不判重**（旧行为延续、非回归）；到期重评是否加 `@scope` 强制。判定命令：`grep -n "fleet_scope_slug" .agents/scripts/nao-fleet.sh` —— 若结果只出现在放置键/显示名、未参与**判重**，则本条仍成立 | #96 全链路终态行 |
| 96-未验三项 | 观察 · 2027-06-30 | **真机 attach 重排 / pi TUI 最小行列 / `pane move` 后长稳** —— PRD 标注「未验」。**人工判定型**（无机械命令：真机行为类；`grep` 只能命中设计/实现报告里的**提及**，不能当已验证据 —— 实测 8 处命中全为提及）。判定要点：到期时在 `docs/reports/` 找**真机实测结论**（有 ⇒ 关闭并回填该报告指针；无 ⇒ 续期）| #96 全链路终态行 |
| T545-same-slug | 接受 · 2027-01-31 | **同 slug 两仓共用 workspace**（label=slug 兜底）；到期重评是否加仓标识。判定：`grep -n "fleet_scope_slug" .agents/scripts/nao-fleet.sh` 看放置键是否已含仓后缀 | T545 验收行 · 方案行 |

**本批关闭（三出口 = 关闭，2026-11-09 · `M20261109-queue-slim`）**：`T535-O2` —— 早已由 T536 B 项修好（`t4_cli_supports` 现用 here-string，`grep -n 'printf .*| *grep' tests/t4/lib.sh` = 0），台账行陈旧 ⇒ 关闭 · `T536-O2` —— 纪律本已存在（`AGENTS.md:23` 改卡必须 bump `version`+`updated`），本批补「无同批例外」半句 ⇒ 关闭 · `T529-D3` —— 本批交付（`MIN_PI_VERSION` 单一事实）⇒ 关闭 · `M20261102-F3` —— 早已标注关闭却仍占行 ⇒ 删除。


## 已回执待验收

| 任务编号 | 回执摘要（≤150字） | 详情路径 | 待办 |
| :--- | :--- | :--- | :--- |







## 挂起（被抢占 / 降级）

| 任务编号 | 挂起原因 | 恢复方式 |
| :--- | :--- | :--- |
