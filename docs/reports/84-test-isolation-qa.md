# #84 测试用例与宿主窗口解耦 —— QA 非作者复核

- 分支：`fix/84-test-isolation` · 复核基线 HEAD `dbbc857`（`git diff main...HEAD` = 7 文件 +210 −63）
- Draft PR [#85](https://github.com/Nathan3303/nao-skills/pull/85) · Issue [#84](https://github.com/Nathan3303/nao-skills/issues/84)
- 结论：**CONDITIONAL GO（0 P1 / 1 P2 / 3 P3）** —— 代码与断言全部通过，条件仅一条**文字级**：根因口径按实测订正（见 P2-1），不改任何实现。
- 复核方式：全部证据由 QA 自跑自造，未复用 RD 的注入脚本与结论。

## 一、事实裁定（PM 点名要求）

**RD 的表述正确，Issue #84 / `docs/tasks-state.md` #84 行 / `cases/06` 护栏注释的「用例依赖宿主窗口 pane 数」表述不成立。**

三条独立证据：

1. 用例全程走隔离 socket（`TX() { tmux -S "$SOCK" … }`，`SOCK` 硬护栏校验 ≠ 生产默认候选），`list-panes -a` 的 `-a` 只在**该 server** 内枚举 —— 用户宿主窗口（默认 server）的 pane 根本不在这个命名空间里，进不了断言。
2. 修前（`main` 4c46f05）两个 `cases/20` **并发**跑：rc=0 / rc=0，双方 PASS ⇒ 「并发」本身不是触发条件（每次运行自带 PID 化缓存 + 独立 socket）。
3. 修前在同一隔离 server 内预置「另一窗口同名卡会话」⇒ 立刻复现红，且失败文案与 RD 一致。链路是：残留会话标题 `π - data-reviewer - <base>` 被 `running()`→`find_pane_by_title` 判为「已在运行」⇒ `ensure` 跳过该目标 ⇒ 只拉起 1 个 pane ⇒ `AC3④` 断言期望 2 实际 1。

**正确表述（建议台账/发布说明照此订正）**：`cases/20` 依赖**同一隔离 server 内的累积残留**（跨块/跨次运行的会话与 pane）+ **全 server 计数**（`list-panes -a`）+ **`tail -1` 顺序启发式挑选**；残留或时序一变化即假红。与「宿主窗口 pane 数」无关。

## 二、逐 AC

**AC1（A · 先红后绿）— 通过**

QA 自造注入（两份脚本插入**逐字相同**的一段，插在 `BASE=…` 之后）：隔离 server 内预置会话 `data-reviewer`（标题 `π - data-reviewer - $BASE`，进程 `exec sleep 900`）+ 一个无关残留窗口。

- 修前（`main` 工作树，同一注入）：`RESULT: FAIL (2 项断言未过)` · rc=1 —— `AC3④ 混合批次拉起 2 个 pane（qa + data-reviewer）（期望=2 实际=1）` · `AC3④ 卡目标默认名 = 卡 role（data-reviewer）（未包含: data-reviewer）`
- 修后（`dbbc857` 工作树，同一注入）：`RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=0）` · rc=0
- 并发：修后两个 `cases/20` 并行 ⇒ rc=0 / rc=0，两组均 `RESULT: PASS（SKIP=0 · DEGRADE=0）`
- 块结构复核：`AC4①→AC4④→AC4③B` 未被 `reset_lab` 打断（`fx-residue` 残留链仍有意义）；`reset_lab` 插在块边界，未削弱该链的检测意图。

判据措辞校正：AC1 写「宿主窗口多 1 个残留 pane」在该夹具上**不可实现**（见事实裁定）；按其本义（同一 server 残留）已验。

**AC2（A · 机械护栏）— 形式通过，诊断价值需订正（见 P2-1 / P3-2）**

- 真用例集 0 违规：`t4_scan_host_pane_refs tests/t4/cases` 输出空（QA 另用裸 `tmux` 正则独立复核亦 0 命中）。
- 两侧验证（QA 自造 18 个微用例）：命中「行首/`$()`/管道后的裸 `tmux`」「包装函数内裸 `tmux`」「裸 `"$REAL_TMUX"`」；不误报「`tmux -S "$SOCK"`」「`command -v tmux`」「`t4_require_cmd tmux`」「注释里的 `tmux`」。
- **假阳 3 例**（合规写法被报违规）：`tmux -S"$SOCK"`（`-S` 紧贴取值）· 跨行 `tmux \` 后下一行 `-S "$SOCK"` · `tmux -L <name>`（用 name socket 隔离）。
- **漏判 4 例**：`env tmux …`、`bash -c "tmux …"`、`A=(tmux); "${A[@]}" …`、`TMUX=$SOCK tmux …`（最后一种其实**是合规隔离形态**，不报是对的，但它说明「裸 tmux ⇒ 默认 socket」这个前提并不普遍成立）。
- **关键**：本批真实缺陷类的行**全部带 `-S`**（如修前的 `pane_count() { TX list-panes -a … }`、`… | tail -1`）⇒ 护栏对真实根因类**零覆盖**，缺陷即使原样回归也仍是绿的。它只是一条「socket 显式性 lint」。
- 独立意见：作为增量 lint 可接受（行级静态、最小 diff，RD 已自认数据流可绕）；**不可接受**的是把它写成「宿主 pane 数假红的根因已关进用例」（见 P2-1）。

**AC3（B · 负控自包含）— 通过**

- 真清单摘 `uiux-designer`（临时改真仓，事后 `md5sum -c` 逐字还原、`git status` 静默）：`cases/06` rc=1，**恰 2 红**且都指向漂移本身 —— `A: 真 roles.yaml 与卡集一致…（角色数=6（期望 7）` / `A: 真清单下 check 报 roles=7`。
- 对照修前（`main` 工作树，同样摘条目）：**3 红**，多出的正是误导性的 `A: 复位后断言复绿（角色数=6（期望 7）`。
- 复位后 `cases/06` `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2）`。
- 遗留耦合（P3-1）：自包含清单只解掉了「清单→夹具」方向，反向仍耦合真**卡集**。

**AC4（C · 容量默认值抽取）— 通过**

- `cases/25` rc=0：`C: 从脚本抽取 TMUX_MAIN_WIDTH_DEFAULT（33）` / `TMUX_MIN_PANE_WIDTH_DEFAULT（30）`；M1 八条阈值两侧逐值（n=7/8/9/10）、拍板表 137/184/184/230 全 PASS；M2 活体 183 warn / 184 零 warn；M3 `n-1` 变异敏感。
- 改默认值演示：`M4: 副本默认值已改 33/30 → 40/24（抽取器跟随）` + `M4: 新默认值下「阈值两侧」断言仍成立（不因改默认值假红）` 均 PASS，且 `M4: 真脚本默认值未被改动（33/30）`。
- `git diff main...HEAD -- .agents/scripts/nao-fleet.sh` 输出为空 ⇒ 真实脚本确实未被改动。

**AC5（门禁）— 通过（QA 自跑 · 串行 · 跑前 `ps` 确认）**

- `bash .agents/scripts/nao-fleet.sh check` → rc=0 · `check: OK · roles=7 · files=54 · layout=main-row2`；连跑 2 次输出 `diff` 空。
- `npm test` → rc=0 · 用例 **24** · 断言 **924** · `SKIP=0 · DEGRADE=0 · NOTE=2`（白名单 `06:static-contract` ×2）。
- `npm run test:t4:full:dual` → rc=0 · 组 1（保留 `TMUX_PANE`）924 断言 / 24 例 / `SKIP=0 · DEGRADE=0` · 组 2（`env -u TMUX_PANE`）924 / 24 / `SKIP=0 · DEGRADE=0` · 非白名单 NOTE=0。
- 环境插曲（既有 flaky，不计本批）：首跑 `npm test` 出现 `SKIP=1`（`cases/02` 真 `pi --mode json … -p ok` rc=124 触 120s 超时、stdout 87 KB）；单跑 `--case 02` 14.9 s PASS，其后 `npm test` 与 dual 均 `SKIP=0`。与 #82 台账 O-1 同类。

## 三、缺陷（分级 · 全量入库）

**P2-1 · 根因表述错误且被写进三处（Issue #84 / `docs/tasks-state.md` #84 行 / `cases/06`「#84 A 机械护栏」注释）+ PR 描述「A 根因」**
期望：诊断与实测一致；实际：把「同一隔离 server 内累积残留 + 全 server 计数 + 顺序启发式」写成「依赖宿主窗口 pane 数」（实测证伪，见 §一）。影响：① 台账/发布说明会长期带着错误诊断；② 按错误类别设计的护栏（AC2）对真实缺陷类零覆盖，读者会误以为该类缺陷已被机械守护。处置：只改文字（Issue 回帖订正 + 注释 + 台账），不需改代码。

**P3-1 · B 的自包含清单反向耦合真卡集**
造「正常新增第 8 角色」（新增卡 + 清单条目，未来大概率发生）：`cases/06` rc=1 共 4 红，其中两条与本批 B 要消灭的「误导性红」同类 —— `A 负控：check 只降到 warn=1（未包含: warn=1）`（夹具清单缺新卡 ⇒ 变异体两条孤儿卡 ⇒ warn=2）与 `A: 复位后断言复绿（新卡：卡存在但 roles.yaml 未登记）`。修前该方向是绿的（修前夹具复制真清单）。不阻断（属「有意新增角色时必须同步更新夹具」的已知动作），记可读性/维护性观察。

**P3-2 · 护栏假阳/漏判面（AC2 真实性边界）**
3 类假阳（`-S` 紧贴、跨行 `-S`、`-L`）、4 类漏判（`env`、`bash -c`、数组/变量间接、`TMUX=` 前缀），且对真实缺陷类零覆盖（§二 AC2）。建议下批做成「`list-panes -a` + `tail -1`/`grep -c` 组合」语义 lint，或提供「只数夹具窗口/只算快照 diff」的 helper 供用例复用。

**P3-3 · 残留形态的检测灵敏度不对称（观察）**
第二组注入（块间插入一个**不撞名**的残留 pane）：修前与修后都 PASS —— 修前那次是靠 `tail -1` 恰好挑中残留 pane 仍判绿（断言可能落在错误 pane 上而无声），修后靠 `reset_lab` + 快照 diff 收敛。不是本批缺陷，但说明「累积残留」不总翻红，回归防护依赖 `reset_lab` 的块边界纪律。

## 四、范围外核查

- 变更面与派发一致：7 文件 +210 −63；`docs/releases/v0.22.1.md` 仅回填 npm 核验事实（`dist-tags.latest` + `dist.integrity` + tarball 168,345 B），`docs/tasks-state.md` 仅新增 #84 进行态行。
- 零敏感值：`git diff main...HEAD` 无家目录绝对路径 / token / 私钥字样（仅 npm 完整性哈希，非密钥）。
- 未改实现：`.agents/scripts/nao-fleet.sh` 分支侧 diff 为空。
- 夹具收尾：QA 未残留 tmux server（自造夹具均 `kill-server`）、未残留缓存目录（本轮 `T4_KEEP_CACHE` 产物 3 个已删）；工作区静默。

## 五、结论与条件

- **CONDITIONAL GO**：0 P1 · 1 P2（文字级口径订正）· 3 P3（转办下批，建议到期 2026-12-05）。
- 条件（P2-1）：PR 描述「A 根因」、`cases/06` 护栏注释、`docs/tasks-state.md` #84 行按 §一 订正；Issue #84 回帖订正。若 PM 采「先合并、口径在台账/发布说明订正」，则视为 GO。
- P3 建议下批项：① 语义化护栏（真实缺陷类）+ 3 类假阳收窄；② 负控夹具与卡集解耦（或夹具自检）；③ AC1 类用例统一「只数夹具窗口 + 快照 diff」helper。
