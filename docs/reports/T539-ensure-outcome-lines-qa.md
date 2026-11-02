# T539 `ensure` 输出语义三态互斥 —— QA 独立复核报告

- 状态：**复核通过（GO）· 六项全过**（待 PM 验收；不合并、不 push main）
- 更新：2026-11-02/03 · Owner：qa · 分支 `feat/66-ensure-outcome-lines` · 复核 HEAD **`0e7c3bf`**
- 指针：PRD `docs/prds/2026-11-02-ensure-outcome-lines.md`（AC1–AC5 · BR1–BR6 · D1–D4）· Issue [#66](https://github.com/Nathan3303/nao-skills/issues/66) · Draft PR [#67](https://github.com/Nathan3303/nao-skills/pull/67) · RD 报告 `docs/reports/T539-ensure-outcome-lines-rd.md`
- 结论依据：**自建夹具**（不复用 RD 用例断言）三态 36/36 + 旧版负控点名 12 项 + BR6 逐字对照 + rc 语义 trace + 隔离计数。

## TL;DR

- **六项全过**：① 三态互斥（自建夹具 36/36）② 负控点名 FAIL（旧 `a693706` 跑 `--case 22` = 12 项未过）③ BR6 成功行逐字不变、全量差异仅摘要行 ④ rc 语义不变（内部 2/3 不外泄；对外 `exit 3` 未混用）⑤ 隔离未触碰生产会话 ⑥ 数字自跑一致（21 例 / 730 断言 / 摘 22 号后 696 ⇒ **+34** 验证）· `check`/`npm test`/`test:t4:full` 全 rc=0 · 未推送 0。
- **无阻塞遗留**：唯一环境观察 = 既有 flake `M20261102-F2` 本轮命中 **1/6 次**（用例 02 真 `pi` `rc=124`，SKIP 形态、断言 FAIL=0），单跑复跑均过，**非本批引入**。
- **未改实现**：仅新增本报告；临时换回旧版/摘除用例注册的两次负控测量均已按 md5 还原（见 §四）。
- **发布建议**：**GO** —— PM 可验收；合并、v0.21.3（含 T538 攒批）与 npm 发布仍归 PM/RD。

## 一、环境与命令（三件套）

- **HEAD**：`0e7c3bf`（复核前后一致；`git fetch origin` 后 `origin/feat/66-ensure-outcome-lines` 同为 `0e7c3bf`）。
- **工作区**：门禁与复跑期间 `git status --porcelain` 为空；无其他并行会话在同一 worktree 跑门禁或写文件（`rd-infra-T539` 同 cwd 但 idle）。本报告为唯一新增文件，落盘后单独提交。
- **全范围门禁**（命令 + 输出，均为最终还原态）：
  - `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=6 · files=50 · layout=main-row2` · **rc=0**
  - `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · **rc=0** · `grep -c '\[PASS\]'` → **730**
  - `npm run test:t4:full` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）` · **rc=0** ⇒ **非白名单 NOTE=0**（2 条均 `06:static-contract`）
  - `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → **21**（改前 20）
  - 摘掉 22 号注册后同命令 → **696**；**730 − 696 = 34 = 用例 22 断言数**（§六）
- **范围数字**：`git diff --shortstat main...HEAD` → `7 files changed, 440 insertions(+), 17 deletions(-)`（含 PM 的 PRD/台账提交；RD 的「5 文件 +334 −13」为它当时 `--cached` 口径，属口径差异不是错）。
- **零回归旁证**：`git diff main...HEAD -- .agents/roles.yaml | wc -l` → **0**；敏感值复核（家目录绝对路径 / token / PRIVATE 关键字，扫 `nao-fleet.sh` + `tests/` 的 diff）→ **0** 命中。
- **未推送**：`timeout 60 git fetch origin` rc=0 ⇒ `git rev-list --count origin/feat/66-ensure-outcome-lines..HEAD` = **0**；`HEAD..origin/main` = **0**。

## 二、复核六项（逐条判定）

### 1. 三态断言（核心）= 过（36/36，自建断言）

不复用 `tests/t4/cases/22` 的断言。自建夹具：隔离 tmux socket + 桩 `pi`（记录 argv 后长驻）+ 选择性失败 `tmux` 桩（仅指定名字的 `split-window` 返回 1）+ `PI_CODING_AGENT_DIR` 空目录（名册离线）。结果：

- **成功**：`ensure arch@<lab>` ⇒ rc=0；`[tmux] 已拉起` 恰 **1** 行；内容逐字 = `[tmux] 已拉起 arch-designer @ <lab>（layout=main-row2）`；摘要恰 1 行 = `已拉起 1 个会话（成功 1 / 跳过 0 / 失败 0）；…`；真新增 **1** pane。
- **跳过**（标题置为 `π - arch-designer - <lab>`，不给 `--force`）⇒ rc=0；`已拉起` 行 = **0**；既有 warn「已在运行…跳过」在位；摘要 `0/1/0`；pane 数不变。
- **失败**（桩令 `split-window` 失败）⇒ rc=0；`已拉起` 行 = **0**；两条诊断 warn 均在位；摘要 `0/0/1`；pane 数不变。
- **混合 3 目标**（arch 成功 + rd-fe 跳过 + rd-be 失败）⇒ 结果行恰 **1** 条且只归 arch；`已拉起 rd-be` / `已拉起 rd-fe` **均 0**；摘要 `1/1/1`；三类之和 = **3 = 目标数**；只真创建 1 pane。
- **额外分支**：`--force`（目标标题已在）⇒ 摘要 `1/0/0` 且 pane +1；`--task TQA` ⇒ 会话名 `arch-designer-TQA`、摘要 `1/0/0`，证明计数覆盖 `--force/--task` 分支（BR3）。

### 2. 负控（自己做）= 过

- 临时把 `.agents/scripts/nao-fleet.sh` 换回 `a693706`（md5 `b0157c75…`）⇒ `bash tests/t4/run.sh --case 22` → **`RESULT: FAIL (12 项断言未过)`**，落点含：
  - `AC3 失败 ⇒ 0 行 [tmux] 已拉起（期望=0 实际=1）`（**失败分支假已拉起**）
  - `AC4 失败目标 rd-be 无假成功行（不应包含: [tmux] 已拉起 rd-be）`
  - `AC3 摘要三类计数 = 0/0/1`、`AC4 三类计数 = 1/1/1`、`AC4 计数守恒（和=3）`（**三类计数缺失**）
- `git checkout --` 还原后：工作区 md5 = HEAD = **`5f1bec24d0d38cfec644860666eea3e1`**；`git diff` 为空；同命令复跑 `--case 22` → **PASS**（34/34）。

### 3. BR6 零回归（单角色成功 旧 vs 新）= 过

同一夹具、同一 repo 路径，分别跑 `a693706` 版与新 HEAD 版（各自独立隔离 socket），去 ANSI 后逐行 diff：

```text
旧：[fleet] [tmux] 已拉起 arch-designer @ <LAB>（layout=main-row2）
    [fleet] 已拉起 1 个会话；就绪后在线状态用 nao-fleet.sh status 查看

新：[fleet] [tmux] 已拉起 arch-designer @ <LAB>（layout=main-row2）
    [fleet] 已拉起 1 个会话（成功 1 / 跳过 0 / 失败 0）；就绪后在线状态用 nao-fleet.sh status 查看
```

- 成功行**逐字相同**（含 `layout=main-row2`）；全量 diff **恰 2 行**（旧摘要 1 + 新摘要 1），无其他差异；旧→新唯一变化 = 摘要行括号内计数（BR6 允许，且前缀 `已拉起 N 个会话` 保留）。

### 4. rc 语义 = 过

- 失败场景 `ensure` 的退出码 **仍为 0**（BR4）：自建夹具 AC3/AC4 均 `rc=0`；`tests/t4/cases/22` 的 AC3 断言亦 PASS。
- 内部返回码**不外泄**：`bash -x` trace 实测失败分支 `+ return 3`（trace 行 333）而脚本 `rc=0`；宿主窗口解析失败分支 `+ return 2`（trace 行 360）而脚本 `rc=0`（摘要 `0/1/0`、零假行）。
- 对外 `exit 3` 语义**未混用**：`env -u TMUX … ensure qa@<lab>` ⇒ `rc=3` 且 stderr 单行「需要 tmux：nao-fleet 只支持在 tmux 会话内运行…」；与内部 2/3 无交叉。

### 5. 隔离纪律 = 过

- **生产 tmux 快照**（默认 socket `/tmp/tmux-1000/default`）：复核前 **1 session / 5 panes**（`%85 %101 %74 %99 %102`）；自建夹具跑完（起停 3 个隔离 server）后 **1 session / 5 panes，pane_id+标题逐行相同**；`--case 22` 旧版负控 + 新版复跑后同样 **完全相同**。
- **夹具实参**：自建夹具 socket = `/tmp/t539qa-lab-<pid>/sock/tmux-1000/default`（≠ 生产候选，护栏 PASS）；`cases/22` 为 `$LAB/sock/...`，源码使用 `TX(){ "$REAL_TMUX" -S "$SOCK" … }`、`env -u TMUX -u TMUX_PANE TMUX="$FTMUX" TMUX_PANE="$CALLER" TMUX_TMPDIR="$SOCKDIR"`，并有「socket 命中生产候选即失败」硬护栏与 `cleanup -S` 收尾。
- **收尾**：两个夹具 socket 均已无 server（`dead`）；无残留 `pi` 桩 / `sleep 900` 孤儿进程。
- **后续出现的第 6 个 pane 不是本批复核产生**：`%103 π - rd-fe-T637 - nao-todo` 于 01:07:51 由 **nao-todo 的 PM** 拉起（cwd = nao-todo 仓、`pi --name rd-fe-T637 --append-system-prompt /tmp/nao-fleet-frontend-developer-*.md`，intercom peer `rd-fe-T637` 在线于 nao-todo）；我的全部夹具均在 `/tmp/t539qa-lab-*` 且 `NAO_SKILLS=$LAB`，不可能落该 pane 到生产 socket。

### 6. 数字与 flake = 过

- 用例数 **21**（`--list` 自跑；不以最大编号推断）；断言数 **730**（`grep -c '\[PASS\]'` 自跑）。
- **+34 求差**：同树从 `run.sh` 摘掉 22 号注册（备份后改、跑完 `cp` 还原，md5 = HEAD `919b0270…`）⇒ `test:t4:full` **PASS · 696**；`730 − 696 = 34`，与 `--case 22` 单跑 `[PASS]` 数 **34** 吻合。
- `check` rc=0（roles=6 · files=50）· `npm test` rc=0 · `test:t4:full` 非白名单 NOTE=0 · 未推送 0（见 §一）。
- **flake `M20261102-F2` 命中 1 次**：共 **6 次**跑过用例 02（`npm test` ×2、`test:t4:full` ×3、`--case 02` ×1），其中摘 22 号的首次全量 `SKIP=1`（用例 02 `pi rc=124 · stdout=81237B` ⇒ `T4_REQUIRE_FULL=1` 判 gate FAIL，**断言 FAIL=0**）。按派单要求先单跑 `--case 02`：**PASS（未复现）**；随后同树全量重跑：**PASS（696）**。⇒ 跑 6 次 / 失败 1 次 / 同一条（用例 02，真 pi 超时），与既有观察项一致，非本批引入。

## 三、自建夹具断言清单（36 条摘要）

- 护栏与夹具建立（隔离 socket / 不在 git 仓 / 调用者 pane）：2 条。
- AC1 成功：rc、结果行数、逐字内容、摘要行数、计数 1/0/0、真创建 pane：6 条。
- AC2 跳过：rc、零假行、既有 warn、计数 0/1/0、pane 不变：5 条。
- AC3 失败：rc、零假行、两条 warn、计数 0/0/1、pane 不变：6 条。
- AC4 混合：rc、结果行恰 1、归属 arch、两个目标无假行、计数 1/1/1、和=3、只建 1 pane：9 条。
- rc=2 路径：rc=0、零假行、计数 0/1/0、pane 不变：4 条。
- 对外 exit 3：rc=3、提示行：2 条。
- BR6 A/B：两版 rc、成功行逐字、diff 仅摘要 2 行：4 条。
- 合计 **36/36 PASS**（脚本与完整日志留在本机 `/tmp/t539qa/`，未入库）。

## 四、临时改动与还原（可核）

- `nao-fleet.sh`：换回 `a693706` 跑负控 → 还原；md5 `5f1bec24…` = HEAD。
- `tests/t4/run.sh`：摘 22 号注册测差分 → 还原；md5 `919b0270…` = HEAD，`--list` 回到 **21**。
- 两次还原后 `git status --porcelain` 为空；最终还原态再跑 `npm test` = **730 / rc=0**。

## 五、遗留 / 风险

- **遗留：无**（三出口均无新增项）。
- **观察项（非本批）**：`M20261102-F2`（用例 02 真 `pi` 偶发 `rc=124`）本轮 **1/6** 命中，单跑与重跑均过；维持既有观察与到期（2026-12-31），不作为本批缺陷。
- **风险说明**：摘要行措辞变化是唯一用户可见差异（BR6 允许）；按前缀 `已拉起 N 个会话` 匹配的脚本不受影响，按整行精确匹配旧摘要的外部脚本会失配（PRD 已接受）。

## 六、发布建议

- **GO**：AC1–AC5 / BR1–BR6 复核通过，六项无未过项；本批可由 PM 验收后交 RD squash 合并，随 **v0.21.3（含 T538 攒批）** 发布。
- 未做：合并 / push main / 改版本 / 发 Release / npm 发布（均非 QA 职责）。
