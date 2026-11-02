# T538 门禁数字可复现口径 —— 交付报告（rd-infra）

- 状态：待 QA 点检 · 更新：2026-11-02 · Owner：rd-infra
- 指针：`docs/prds/2026-11-02-gate-number-provenance.md`（AC1–AC5 + 附录 D1–D4）· 台账 `docs/tasks-state.md` 首行

## TL;DR

- 做了什么：回执「测试」字段补三件套（静默工作区 / HEAD sha / 命令 + 输出）+ 不合格回执反例；四条取数命令正文集中到 `tests/README.md`，PM/QA/RD 三侧只留指针；清单条数零漂移。
- 结论：AC1–AC5 全过，`check` / `npm test` / `test:t4:full` 三门禁 rc=0，`roles.yaml` diff = 0。
- 代价/边界：只改文本，脚本与门禁实现零改动；本批**只合并不发版**，合并后 main 机制文本将领先 npm 0.21.2。
- 待办：QA 点检 → PM 验收 → squash 合并 → 随下次发布进 release notes。

## 变更清单（5 文件 / +15 −5）

- `.agents/common/output-format.md`「回执硬性」第 3 条：拆出三件套子条（**静默工作区** = `git status --porcelain` 空 + 同 worktree 无并行会话跑门禁；**HEAD sha**；**命令 + 输出**，禁「我数了 N」），并给一条**不合格回执反例**（无 HEAD / 无命令 / 只有结论 + 最大编号误当例数）写明「据此打回」。
- `tests/README.md`：新增「取数命令四条（全仓单源）」——用例数 / 断言数 / `files=` / 变更行数与文件数，各带「何时用 + 易错点」，并写明「正文只在本处、三侧只留指针」+「不符即打回」。原 `计数可见` 条内重复的命令串已删（原文同一命令出现 2 次）。
- `.agents/checklists/pm.md` 第 110 条：删掉内嵌命令串，改为**指针**（指向 `tests/README.md`「取数命令四条」）+ 三件套要求，条目数与位置不变。
- `.agents/checklists/qa.md` 红线第 12 条（既有条目内改写）：指针 + 三件套，表述沿用该文件问句风格，**不新增条目**。
- `.agents/checklists/rd-infra.md` 红线第 8 条（既有条目内改写）：指针 + 三件套，**不新增条目**（AC4 与「不新增清单项」在此冲突时以零计数漂移为准）。

## 门禁（HEAD `2df07f9` · `git status --porcelain` 为空 · 无并行会话同 worktree 跑门禁）

- `bash .agents/scripts/nao-fleet.sh check` → `check: OK · roles=6 · files=50 · layout=main-row2`，rc=0。
- `npm test` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`，rc=0。
- 用例数 = `bash tests/t4/run.sh --list | tail -n +2 | wc -l` → `20`（不以最大编号 21 推断）。
- 断言数 = `bash tests/t4/run.sh 2>&1 | grep -c '\[PASS\]'` → `694`（与例数不同轴）。
- `files=` 交叉核对 = `find "$NAO_SKILLS/.agents" -type f | wc -l` → `50`，与 `check` 一致。
- `npm run test:t4:full` → `RESULT: PASS（SKIP=0 · DEGRADE=0 · NOTE=2 · NOTE白名单=2）`，rc=0 ⇒ **非白名单 NOTE = 0**。
- 变更行数/文件数 = `git show --shortstat --oneline 2df07f9` → `5 files changed, 15 insertions(+), 5 deletions(-)`。
- `git diff 4346bb4..HEAD -- .agents/roles.yaml` → 0 行（diff = 0）；`nao-fleet.sh` / `tests/t4/**` 未触碰。

## AC 自证

- **AC1**：`common/output-format.md` 第 3 条含三件套三条 + 一条不合格回执反例并写明「打回」。
- **AC2**：四条命令串在 `.agents/**` + `tests/README.md` 字面命中各 **1** 次（`grep -ro "<cmd>" .agents/ tests/README.md | wc -l` ⇒ `1/1/1/1`）；三份清单内命中 **0**。改前 → 改后：用例数 `3 → 1`（README 重复 2 次已删）、断言数 `1 → 1`（正文由 pm 迁至 README）、`files=` `1 → 1`（同上）、行数 `0 → 1`（此前无成文命令）。
- **AC3**：`qa.md` / `rd-infra.md` 各存在一条指向单源的条目（均在既有红线内，表述贴合各自风格）。
- **AC4**：`grep -c '^- \[ \]\|^| '` 逐文件改前 → 改后 = `pm 94 → 94`、`qa 32 → 32`、`rd-infra 22 → 22`，零漂移。
- **AC5**：见上「门禁」节。

## 风险与已知边界

- 报告提交（本文件）落在门禁 HEAD 之后，**仅新增 1 个 docs 文件**，机制文件零差异（`git diff 2df07f9..HEAD --name-only` 可自证）；需要严格同 HEAD 时可复跑 `check`（秒级）。
- `find "$NAO_SKILLS/.agents" -type f | wc -l` 在 `NAO_SKILLS` 未设置时会**静默得 0** —— 已在 README 该条「易错点」写明（本次实测踩到）。
- 口径生效性只能靠观察：下 2 批回执若仍出现「无 HEAD / 无命令」即视为本批未生效（PRD §八 监控项）。

- 修订：2026-11-02 首版（AC1–AC5 自证 + 门禁数字）。
