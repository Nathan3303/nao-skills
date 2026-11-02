# T539 `ensure` 输出三态互斥 —— 交付报告（rd-infra）

- 状态：待 QA 复核 · 更新：2026-11-02 · Owner：rd-infra
- 指针：`docs/prds/2026-11-02-ensure-outcome-lines.md`（AC1–AC5 + D1–D4）· Issue [#66](https://github.com/Nathan3303/nao-skills/issues/66) · 分支 `feat/66-ensure-outcome-lines`

## TL;DR

- 做了什么：`spawn_tmux` 改为**显式返回三态**（成功 `0` / 跳过 `2` / 失败 `3`），调用方 `spawn_one` 只对成功盖章并打印 `[tmux] 已拉起 …`；跳过/失败**零假行**（既有 warn 原样保留、不合并）；摘要行仍恰一行，追加「成功 N / 跳过 M / 失败 K」。
- 结论：AC1–AC4 由新用例 22 逐条断言；AC5 门禁全绿；单角色成功场景与旧版**逐字等价**（唯一差异 = 摘要行括号内新增计数）。
- 边界：退出码不变（失败仍 rc=0，BR4）；不改拉起方式/布局/prompt 注入/判重；`roles.yaml` 零改动。
- 待办：QA 独立复核 → PM 验收 → squash → **v0.21.3（与 T538 攒批一并发布）**。

## 一、实现（范围 A–C）

### A · 三态显式契约（`spawn_tmux`）

- 新增常量 `SPAWN_RC_OK=0` / `SPAWN_RC_SKIP=2` / `SPAWN_RC_FAIL=3`：**返回值是唯一契约**，函数不再用 `return 0` 同时表达「成功 / 跳过 / 失败」。
- 两个未创建分支各自返回专属状态：
  - 宿主窗口为空（`resolve_host_window` 已 warn）⇒ `return 2`（跳过，不是成功）；
  - `split-window` 非 0 ⇒ 两条既有诊断 warn 后 `return 3`（失败，不是成功）。
- `set -euo pipefail` 兼容写法：调用方 `spawn_tmux … || rc=$?`（`||` 列表豁免 errexit），**不**依赖 `if` 包裹、**不**临时关 errexit。
- 未知返回值按**失败**处理（`case` 的 `*` 分支），保守侧失败：宁可少报成功，不产生假成功行。
- 布局步骤 `apply_tmux_layout || true`：布局是尽力而为（内部 tmux 调用均已 `|| true`），布局失败不代表 pane 未创建 ⇒ 不影响三态判定。

### B · 每目标恰一行结果（`spawn_one` / `cmd_ensure`）

- 成功：`SPAWN_OK++` + 打印既有成功行（**内容逐字不变**，含 `--model` 变体）。
- 跳过：`continue` 前 `SPAWN_SKIP++`；既有 `已在运行…跳过` warn 保留；不打印成功行。
- 失败：`SPAWN_FAIL++`；`pane 创建失败` + `已跳过该 pane…` 两条诊断 warn 保留（不合并）；不打印成功行。

### C · 摘要行三类计数

- 条件由「`SPAWN_OK > 0`」改为「任意一类 > 0」，三类全 0 仍不打印（与现状一致）。
- 仍**恰一行**（BR5）；前缀保留，计数追加在括号内（见 §二旧→新对照）。

## 二、旧 → 新输出对照（BR6）

旧（`a693706`，单角色成功）：

```
[fleet] [tmux] 已拉起 arch-designer @ <repo>（layout=main-row2）
[fleet] 已拉起 1 个会话；就绪后在线状态用 nao-fleet.sh status 查看
```

新（本批，同一夹具）：

```
[fleet] [tmux] 已拉起 arch-designer @ <repo>（layout=main-row2）
[fleet] 已拉起 1 个会话（成功 1 / 跳过 0 / 失败 0）；就绪后在线状态用 nao-fleet.sh status 查看
```

- **成功行逐字不变**（BR1）；除摘要行外**全量 diff 为空**（A/B 实测，见 §四负控）。
- 摘要变化的必要性（BR6 允许）：三类计数必须出现在**同一行**内（BR5），且「成功数」与既有 `已拉起 N 个会话` 是同一事实。保留前缀使既有断言（如 `cases/20` 的 `已拉起 1 个会话`）与用户习惯不破，计数以括号追加。
- 三类全 0 的批次（如全部目标在相位 1 之前就退出）仍无摘要行。

三态输出全景（新）：

- 成功 = 唯一一条 `[fleet] [tmux] 已拉起 …` + 摘要「成功 1 / 跳过 0 / 失败 0」。
- 跳过 = 既有跳过 warn + 摘要「成功 0 / 跳过 1 / 失败 0」，**无** `已拉起` 结果行。
- 失败 = 两条诊断 warn + 摘要「成功 0 / 跳过 0 / 失败 1」，**无** `已拉起` 结果行，**rc 仍 0**。

## 三、用例 D（`tests/t4/cases/22-ensure-outcome-lines.sh`）

并入既有用例不可行：`cases/20` 的夹具目标是「卡会话 + 托管」，与三态输出不同轴；`cases/12` 断言由 QA 冻结在报告脚本内（只读挂载）。故**新增 22**，共 34 条 `[PASS]` 断言：

- AC1 成功：恰 1 行结果、内容逐字（含 `layout=main-row2`）、摘要 1/0/0、真创建 1 个 pane。
- AC2 跳过：0 条结果行、既有跳过 warn 在位、摘要 0/1/0、pane 数不变。
- AC3 失败：0 条结果行、两条诊断 warn 在位且「`pane 创建失败` 恰 1 条」、摘要 0/0/1、pane 数不变、**rc=0**。
- AC4 混合（`arch` 成功 + `rd-fe` 预置标题跳过 + `rd-be` 桩失败）：结果行恰 1 条且只归成功目标；摘要 1/1/1；三类之和 = 3 = 目标数；真创建 1 个 pane。

夹具纪律：

- 真 tmux **隔离 socket** + 开跑前硬护栏（socket ≠ 生产候选、夹具根不在任何 git 仓内）+ `env -u TMUX -u TMUX_PANE` + `TMUX_TMPDIR` 指向夹具；收尾走机制 `cleanup -S`。
- 桩 `pi` 只记录 argv 后长驻；`PI_CODING_AGENT_DIR` 指向空目录 ⇒ 名册离线；零网络、不接触生产会话。
- 失败分支用 **tmux 桩**：`NAO_T539_FAIL_SPLIT=<名字>` 时仅该名字的 `split-window` 返回非 0（参数串先去 `printf %q` 的反斜杠再比对 `--name`），**不依赖真实窗口过窄**。
- 跳过分支用 `select-pane -T 'π - <name> - <repo basename>'` 注入标题（不依赖 pi 自身设标题）。

自测过程中用例先红后绿（保留作为可诊断记录）：首轮 AC2 摘要缺失暴露了**跳过计数漏在 `cmd_ensure` 的 `continue` 分支前**；首轮 AC3 未失败暴露了桩对 `--name\ rd-be`（`printf %q` 转义）匹配不上。两处均已修，修后连跑稳定 PASS。

## 四、负控（证明用例会红）

- **旧实现对照**：临时把 `nao-fleet.sh` 换回 `a693706` 版本跑 `--case 22` ⇒ `RESULT: FAIL (12 项断言未过)`，点名 `AC3 失败 ⇒ 0 行 [tmux] 已拉起（实际=1）`、`AC4 失败目标 rd-be 无假成功行（实际含假行）`、三类计数缺失等；还原后 `md5sum -c` 通过。
- **单角色成功 A/B**：同一夹具分别跑旧/新脚本，输出归一化后 diff 仅摘要行（另有 A/B 夹具目录名标签差异，不属脚本输出）。
- 新用例断言数 34；用例内失败分支即「诊断信息不合并 + 不加成功行」的负向断言。

## 五、门禁（三件套）

- **HEAD**：`a693706`（门禁在提交前跑；工作区 = 本批改动，见下）
- **工作区**：`git status --porcelain` → ` M .agents/scripts/nao-fleet.sh` · ` M tests/README.md` · ` M tests/t4/run.sh` · `?? tests/t4/cases/22-ensure-outcome-lines.sh`（+ 本报告）；**无其他并行会话在同一 worktree 跑门禁**。
- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=6 · files=50 · layout=main-row2` · rc=0（`files=50` 与改动前一致；本批未增删 `.agents/**` 文件）
- `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · rc=0 · 断言 **730**
- `npm run test:t4:full` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · rc=0 ⇒ **非白名单 NOTE=0**
- 用例数 = `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → **21**（改前 20；不以最大编号推断）
- 断言数 = `bash tests/t4/run.sh 2>&1 | grep -c '\[PASS\]'` → **730**（改前同树同环境 **696**）⇒ **+34 = 新用例 22 的全部断言**
  - 改前口径的取法：同一工作树临时摘掉 `run.sh` 的 22 号注册后跑全量（`RESULT: PASS` · 696 · `NOTE=2`），随即从备份还原并以 `md5sum -c` 校验；非跨 worktree 推断。
- `git diff a693706 -- .agents/roles.yaml | wc -l` → **0**
- 未推送：`git rev-list --count origin/feat/66-ensure-outcome-lines..HEAD` → **0**（推送前；推后回执更新）
- 敏感值复核：`git diff -- .agents/scripts/nao-fleet.sh tests/ | grep -nE '/home/|ghp_|token|PRIVATE'` → 无命中
- **flake（`M20261102-F2`）**：本轮 `npm test` 1 次、`test:t4:full` 1 次、同树无 22 号注册测量 1 次、基线 worktree 2 次（共 5 次全量），用例 02 **0 次失败、0 次 `rc=124`**；未触发「先单跑复现再重跑」流程。

## 六、风险与已知边界

- 摘要行措辞变化是本批**唯一**用户可见差异（BR6 允许）：若有外部脚本按旧串整行精确匹配摘要，会失配；按前缀 `已拉起 N 个会话` 匹配则不受影响。失败/跳过分支的输出只减少假行、不新增行（诊断 warn 原样）。
- 未知返回值按失败计数：这是对内部实现错误的保守兜底，正常路径不触发。
- 失败原因仍只在两条诊断 warn 中；摘要只报数不报因（NFR「可诊断」）。
- `M20261102-F2` 仍为观察项（非本批引入、未在本轮复现），不夹带处理。

## 七、遗留（三出口）

- **关闭**：无（本批未产生新遗留）。
- **接受（含到期）**：`M20261102-F2`（用例 02 真 `pi` 偶发 `rc=124`）维持既有观察项，到期 2026-12-31；本轮 5 次全量 0 命中，不作为本批缺陷。
- **转办**：发布（v0.21.3，含 T538 攒批 + npm 重发与 integrity 核验）归 PM；QA 独立复核对 §五门禁与本报告 §四负控做独立复跑。
